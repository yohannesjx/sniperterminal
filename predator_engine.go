package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/adshao/go-binance/v2"
	"github.com/adshao/go-binance/v2/futures"
	"github.com/gorilla/websocket"
)

// ==========================================
// 1. GLOBAL EXPOSURE GUARD
// ==========================================

type GlobalExposureGuard struct {
	mu            sync.Mutex
	MaxConcurrent int                  // Max active scalps (Hard limit: 2)
	ActiveTrades  map[string]float64   // Symbol -> Notional Value
	BlockedUntil  map[string]time.Time // Symbol -> Cooldown Time
	TotalLimit    float64              // Total Notional Limit
}

func NewGlobalExposureGuard(maxConcurrent int, totalLimit float64) *GlobalExposureGuard {
	return &GlobalExposureGuard{
		MaxConcurrent: maxConcurrent,
		ActiveTrades:  make(map[string]float64),
		BlockedUntil:  make(map[string]time.Time),
		TotalLimit:    totalLimit,
	}
}

// CanEnter checks if we can open a new trade based on limits
func (g *GlobalExposureGuard) CanEnter(symbol string, requiredNotional float64) bool {
	g.mu.Lock()
	defer g.mu.Unlock()

	// 0. Check Cooldown
	if until, ok := g.BlockedUntil[symbol]; ok {
		if time.Now().Before(until) {
			return false // Silently blocked
		}
		delete(g.BlockedUntil, symbol) // Cleanup
	}

	// 1. Check Concurrent Limit
	if len(g.ActiveTrades) >= g.MaxConcurrent {
		return false
	}

	// 2. Strict Exposure Cap (Total Notional)
	currentNotional := 0.0
	for _, notional := range g.ActiveTrades {
		currentNotional += notional
	}

	totalNotional := currentNotional + requiredNotional

	if totalNotional > g.TotalLimit {
		needed := totalNotional - g.TotalLimit
		log.Printf("🛑 GUARD: Blocked %s. Needs $%.2f more room in Notional Limit ($%.2f > $%.2f).", symbol, needed, totalNotional, g.TotalLimit)
		g.BlockedUntil[symbol] = time.Now().Add(30 * time.Second)
		return false
	}

	return true
}

func (g *GlobalExposureGuard) RegisterTrade(symbol string, notional float64) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.ActiveTrades[symbol] = notional
}

func (g *GlobalExposureGuard) ReleaseTrade(symbol string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	delete(g.ActiveTrades, symbol)
}

// ==========================================
// 2. MULTI-ASSET PREDATOR MANAGER
// ==========================================

// WhaleCandidate tracks potential whale movements for verification
type WhaleCandidate struct {
	Symbol    string
	Side      string
	FirstSeen time.Time
	LastSeen  time.Time
	Volume    float64
}

// PredatorEngine is now the Multi-Asset Manager
type PredatorEngine struct {
	client        *futures.Client
	trendAnalyzer *TrendAnalyzer
	active        bool
	mu            sync.Mutex // General state mutex

	// Workers
	workers map[string]*PredatorWorker

	// Shared State
	positions       map[string]*PredatorPosition
	currentPrices   map[string]float64
	whaleCandidates map[string]*WhaleCandidate // Verification Map
	TradeCooldowns  map[string]time.Time       // Signal Debounce (60s)

	env              *PredatorEnv
	DailyRealizedPnL float64

	// Safety Mode Logic
	ConsecutiveLosses int
	SafetyModeUntil   time.Time

	// Guard
	guard *GlobalExposureGuard

	// Notifications
	notifier *NotificationService

	// Configuration
	Leverage int

	// Signal Hub
	hub *SignalHub

	// Precision Info
	symbolInfo map[string]SymbolProfile // Symbol -> TickSize/StepSize
}

// PredatorWorker handles a single symbol stream
type PredatorWorker struct {
	Symbol string
	Engine *PredatorEngine
	Kill   chan bool
}

type PredatorEnv struct {
	ApiKey    string
	ApiSecret string
}

type PredatorPosition struct {
	Symbol     string
	Entry      float64
	Size       float64
	Side       string
	StartTime  time.Time
	StopLoss   float64
	TakeProfit float64
	MarginUsed float64
	Leverage   int     // Asset-specific leverage
	Score      float64 // Priority Score
	Tier       string  // Tier Description
	MaxPnL     float64 // Track max unrealized PnL for trailing

	// OCO Management
	TPOrderID      int64
	SLOrderID      int64
	IsBreakEvenSet bool
}

// NewPredatorEngine initializes the manager
func NewPredatorEngine(apiKey, apiSecret string, ta *TrendAnalyzer, maxExposure float64, maxConcurrent int, notifier *NotificationService, leverage int, totalNotionalLimit float64, hub *SignalHub) *PredatorEngine {
	client := binance.NewFuturesClient(apiKey, apiSecret)
	return &PredatorEngine{
		client:          client,
		trendAnalyzer:   ta,
		active:          true,
		positions:       make(map[string]*PredatorPosition),
		currentPrices:   make(map[string]float64),
		whaleCandidates: make(map[string]*WhaleCandidate),
		TradeCooldowns:  make(map[string]time.Time),
		workers:         make(map[string]*PredatorWorker),
		env: &PredatorEnv{
			ApiKey:    apiKey,
			ApiSecret: apiSecret,
		},
		DailyRealizedPnL:  0.0,
		ConsecutiveLosses: 0,
		// Initialize Guard: Max Concurrent Trades
		// Initialize Guard: Max Concurrent Trades
		guard:      NewGlobalExposureGuard(maxConcurrent, totalNotionalLimit),
		notifier:   notifier,
		Leverage:   leverage,
		hub:        hub,
		symbolInfo: make(map[string]SymbolProfile),
	}
}

// IsSafetyMode checks if we are in protective mode
func (pe *PredatorEngine) IsSafetyMode() bool {
	pe.mu.Lock()
	defer pe.mu.Unlock()
	return time.Now().Before(pe.SafetyModeUntil)
}

// Start launches the workers
func (pe *PredatorEngine) Start() {
	log.Println("🦖 THE PREDATOR: Multi-Asset Engine Initialized.")

	// 0. Fetch Exchange Info (Precision)
	pe.FetchExchangeInfo()

	// 1. Start Position Monitor (Global)
	go pe.monitorPositions()

	// 2. Launch Independent Workers
	targets := []string{
		"BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT",
		"ADAUSDT", "DOGEUSDT", "AVAXUSDT", "TRXUSDT", "PEPEUSDT",
	}
	for _, sym := range targets {
		pe.startWorker(sym)
	}
}

func (pe *PredatorEngine) startWorker(symbol string) {
	worker := &PredatorWorker{
		Symbol: symbol,
		Engine: pe,
		Kill:   make(chan bool),
	}
	pe.mu.Lock()
	pe.workers[symbol] = worker
	pe.mu.Unlock()

	go worker.Run()
}

// Run is the main loop for a single symbol
func (w *PredatorWorker) Run() {
	log.Printf("🦖 PREDATOR: Starting Worker for %s", w.Symbol)

	// Stream URL
	lowerSym := strings.ToLower(w.Symbol)
	streamName := fmt.Sprintf("%s@depth5@100ms/%s@aggTrade", lowerSym, lowerSym)

	url := fmt.Sprintf("wss://fstream.binance.com/stream?streams=%s", streamName)

	// Retry Loop
	for {
		select {
		case <-w.Kill:
			return
		default:
			// Connect
			conn, _, err := websocket.DefaultDialer.Dial(url, nil)
			if err != nil {
				time.Sleep(5 * time.Second)
				continue
			}

			// Read Loop
			for {
				_, message, err := conn.ReadMessage()
				if err != nil {
					conn.Close()
					break
				}
				w.Engine.handleMessage(message, w.Symbol)
			}
		}
	}
}

// handleMessage processes message for specific symbol context
func (pe *PredatorEngine) handleMessage(msg []byte, ctxSymbol string) {
	var combined binanceCombinedMsg
	if err := json.Unmarshal(msg, &combined); err != nil {
		return
	}

	streamSym := extractSymbol(combined.Stream)

	if len(combined.Data) > 0 {
		isDepth := false
		sLen := len(combined.Stream)
		if sLen >= 5 && combined.Stream[sLen-5:] == "depth" {
			isDepth = true
		}
		if sLen >= 5 && combined.Stream[sLen-5:] == "100ms" {
			isDepth = true
		}

		if isDepth {
			var depth binanceDepthData
			if err := json.Unmarshal(combined.Data, &depth); err == nil {
				pe.scanForWhales(streamSym, depth)
			}
			return
		}

		isTrade := false
		if sLen >= 8 && combined.Stream[sLen-8:] == "aggTrade" {
			isTrade = true
		}

		if isTrade {
			var trade binanceTradeData
			if err := json.Unmarshal(combined.Data, &trade); err == nil {
				price, _ := strconv.ParseFloat(trade.Price, 64)
				pe.mu.Lock()
				pe.currentPrices[streamSym] = price
				pe.mu.Unlock()
			}
		}
	}
}

// FORMATTING UTILITIES (-1111 FIX)
// ================================

func (pe *PredatorEngine) FetchExchangeInfo() {
	res, err := pe.client.NewExchangeInfoService().Do(context.Background())
	if err != nil {
		log.Printf("⚠️ Failed to fetch Exchange Info: %v", err)
		return
	}

	for _, s := range res.Symbols {
		var tickSize, stepSize float64

		for _, filter := range s.Filters {
			if filter["filterType"] == "PRICE_FILTER" {
				tickSize, _ = strconv.ParseFloat(filter["tickSize"].(string), 64)
			}
			if filter["filterType"] == "LOT_SIZE" {
				stepSize, _ = strconv.ParseFloat(filter["stepSize"].(string), 64)
			}
		}

		pe.symbolInfo[s.Symbol] = SymbolProfile{
			TickSize: tickSize,
			StepSize: stepSize,
		}
	}
	log.Println("✅ Predator Precision Data Loaded.")
}

func (pe *PredatorEngine) FormatPrice(symbol string, price float64) string {
	info, exists := pe.symbolInfo[symbol]
	if !exists {
		return fmt.Sprintf("%.2f", price) // Fallback
	}
	// Round to TickSize
	rounded := math.Floor(price/info.TickSize+0.5) * info.TickSize
	// Get Precision
	prec := 0
	if info.TickSize > 0 {
		prec = int(math.Round(-math.Log10(info.TickSize)))
	}
	return fmt.Sprintf("%.*f", prec, rounded)
}

func (pe *PredatorEngine) FormatQty(symbol string, qty float64) string {
	info, exists := pe.symbolInfo[symbol]
	if !exists {
		return fmt.Sprintf("%.3f", qty) // Fallback
	}
	// Round to StepSize
	rounded := math.Floor(qty/info.StepSize) * info.StepSize // Floor (Round DOWN) for Qty to avoid -2010 (Insufficient Balance)
	// Get Precision
	prec := 0
	if info.StepSize > 0 {
		prec = int(math.Round(-math.Log10(info.StepSize)))
	}
	return fmt.Sprintf("%.*f", prec, rounded)
}

// 3. PRIORITY RANKING & EXECUTION
func (pe *PredatorEngine) scanForWhales(symbol string, depth binanceDepthData) {
	var potentialSignal *WhaleCandidate
	var side string

	// Calc Volumes for Ratio
	totalBidVol := 0.0
	totalAskVol := 0.0

	for _, b := range depth.Bids {
		p, _ := strconv.ParseFloat(b[0], 64)
		q, _ := strconv.ParseFloat(b[1], 64)
		totalBidVol += p * q
	}
	for _, a := range depth.Asks {
		p, _ := strconv.ParseFloat(a[0], 64)
		q, _ := strconv.ParseFloat(a[1], 64)
		totalAskVol += p * q
	}

	// Check Bids for Candidates
	for _, b := range depth.Bids {
		price, _ := strconv.ParseFloat(b[0], 64)
		qty, _ := strconv.ParseFloat(b[1], 64)
		notional := price * qty
		// Tiered Logic: Look for > $250k (Tier 2 minimum)
		if notional > 250000 {
			potentialSignal = &WhaleCandidate{Symbol: symbol, Side: "LONG", Volume: notional}
			side = "LONG"
			break
		}
	}
	// Check Asks
	if potentialSignal == nil {
		for _, a := range depth.Asks {
			price, _ := strconv.ParseFloat(a[0], 64)
			qty, _ := strconv.ParseFloat(a[1], 64)
			notional := price * qty
			if notional > 250000 {
				potentialSignal = &WhaleCandidate{Symbol: symbol, Side: "SHORT", Volume: notional}
				side = "SHORT"
				break
			}
		}
	}

	// Whale Verification Logic
	if potentialSignal != nil {
		pe.mu.Lock()
		candidate, exists := pe.whaleCandidates[symbol]
		if !exists || candidate.Side != side {
			// New Candidate
			pe.whaleCandidates[symbol] = &WhaleCandidate{
				Symbol:    symbol,
				Side:      side,
				FirstSeen: time.Now(),
				LastSeen:  time.Now(),
				Volume:    potentialSignal.Volume,
			}
		} else {
			// update last seen
			candidate.LastSeen = time.Now()
			candidate.Volume = potentialSignal.Volume // Update volume

			// PREDATOR SPEED TUNING: 0.8 SECONDS
			if time.Since(candidate.FirstSeen) >= 800*time.Millisecond {
				// VALID WHALE!
				pe.mu.Unlock() // Unlock before evaluation

				// Calculate Ratio based on side
				ratio := 0.0
				if side == "LONG" {
					if totalAskVol > 0 {
						ratio = totalBidVol / totalAskVol
					}
				} else {
					if totalBidVol > 0 {
						ratio = totalAskVol / totalBidVol
					}
				}

				// Get current price
				price := 0.0
				if side == "LONG" {
					price, _ = strconv.ParseFloat(depth.Bids[0][0], 64)
				} else {
					price, _ = strconv.ParseFloat(depth.Asks[0][0], 64)
				}

				// 📡 EARLY BROADCAST TO SIGNAL HUB (Visibility > Execution)
				// Create Signal Object
				ts := time.Now().UnixMilli()
				sig := Signal{
					ID:        fmt.Sprintf("SIG-%d-%s", ts, symbol),
					Symbol:    symbol,
					Side:      side,
					Entry:     price,
					Score:     candidate.Volume,
					Tier:      "🟡 Tier 2 (Test)", // Default, updated in evaluateCandidate
					StopLoss:  price * 0.99,      // Placeholder, refined later
					Target:    price * 1.01,      // Placeholder
					Timestamp: ts,
					Status:    "DETECTED", // Initial Status
				}

				// Broadcast JSON
				if pe.hub != nil {
					data, _ := json.Marshal(sig)
					pe.hub.BroadcastSignal(data)

					// 📡 BROADCAST HUD ADVICE (Predator Status)
					// "If Ratio is rising: 'Whale Pressure Increasing - HOLD.'"
					// "If Opposite Iceberg detected: 'SPOOF/ICEBERG DETECTED - EXIT SUGGESTED.'"
					var adviceMsg string
					if ratio > 2.0 {
						adviceMsg = fmt.Sprintf("Whale Pressure Increasing on %s (Ratio %.1f) - HOLD.", symbol, ratio)
					} else if candidate.Volume > 500000 {
						adviceMsg = fmt.Sprintf("Major Iceberg Detected on %s ($%.0f) - MONITOR.", symbol, candidate.Volume)
					}

					if adviceMsg != "" {
						advice := map[string]interface{}{
							"type":    "ADVICE",
							"symbol":  symbol,
							"message": adviceMsg,
							"tier":    "PREDATOR_STATUS",
						}
						adviceData, _ := json.Marshal(advice)
						pe.hub.BroadcastSignal(adviceData)
					}
				}

				pos := pe.evaluateCandidate(symbol, side, price, candidate.Volume, ratio)
				if pos != nil {
					// 📡 RE-BROADCAST VALIDATED SIGNAL (Tier 1 Update)
					if pe.hub != nil {
						// Update Signal Properties from Evaluation
						sig.Tier = pos.Tier
						sig.StopLoss = pos.StopLoss // Now includes accurate SL
						sig.Target = pos.TakeProfit // Now includes accurate TP
						sig.Status = "ACTIVE"       // Ready for execution (client side)

						// Log for debug
						// log.Printf("🚀 BROADCASTING FINAL: %s %s [%s]", sig.Side, sig.Symbol, sig.Tier)

						data, _ := json.Marshal(sig)
						pe.hub.BroadcastSignal(data)
					}

					pe.attemptExecution(pos)

					// Remove candidate after execution attempt
					pe.mu.Lock()
					delete(pe.whaleCandidates, symbol)
					pe.mu.Unlock()
				}
				return
			}
		}
		pe.mu.Unlock()
	} else {
		// Reset candidate if disappeared
		pe.mu.Lock()
		if c, exists := pe.whaleCandidates[symbol]; exists {
			// Tolerance: 1 second flicker allowed
			if time.Since(c.LastSeen) > 1*time.Second {
				delete(pe.whaleCandidates, symbol)
			}
		}
		pe.mu.Unlock()
	}
}

// evaluteCandidate with Tiered Entry Logic
func (pe *PredatorEngine) evaluateCandidate(symbol, side string, price, volume, ratio float64) *PredatorPosition {
	// 1. Trend Lock (Strict)
	trendRes := pe.trendAnalyzer.GetScalpTrend(symbol)

	valid := false
	if side == "LONG" {
		if trendRes.Trend15M == "BULLISH 🟢" && trendRes.Trend5M == "BULLISH 🟢" && trendRes.Trend1M == "BULLISH 🟢" {
			valid = true
		}
	}
	if side == "SHORT" {
		if trendRes.Trend15M == "BEARISH 🔴" && trendRes.Trend5M == "BEARISH 🔴" && trendRes.Trend1M == "BEARISH 🔴" {
			valid = true
		}
	}

	if !valid {
		return nil
	}

	// 2. Dynamic Thresholds (Relaxed for Momentum)
	isSafety := pe.IsSafetyMode()

	minRatio := 1.15 // 1.15 Aggressive Entry (Was 1.25)
	maxExt := 0.0022 // 0.22% Aggressive Chase (Was 0.20%)

	if isSafety {
		minRatio = 1.50 // Strict Safety
		maxExt = 0.0010 // 0.10% Strict Safety
		log.Printf("🛡️ SAFETY MODE ACTIVE: Applying strict filters for %s", symbol)
	}

	// Filter: Volume Ratio
	if ratio < minRatio {
		return nil
	}

	// Filter: EMA Extension
	ema9 := pe.trendAnalyzer.GetEMA(symbol, "1m", 9)

	// Adjust Max Extension for SOL (Volatility Allowance)
	if strings.Contains(NormalizeSymbol(symbol), "SOL") {
		maxExt = 0.0040 // 0.40% for SOL
	}

	if ema9 > 0 {
		dist := math.Abs(price-ema9) / ema9
		if dist > maxExt {
			log.Printf("🛑 GUARDRAIL: %s Extended from EMA (%.4f%% > %.4f%%)", symbol, dist*100, maxExt*100)
			return nil
		}
	}

	// 3. Margin & Sizing Calculation (Dynamic Engine)
	score := volume
	notional, leverage, profitTarget := pe.CalculateDynamicMargin(symbol)

	// Apply Tier Logic (Base on Score)
	tierStr := "⚪ Ignore"
	if score > 500000 {
		tierStr = "🟢 Tier 1 (Conviction)"
	} else if score >= 250000 {
		notional = notional * 0.50
		tierStr = "🟡 Tier 2 (Test)"
	} else {
		return nil
	}

	// STRIKE PENALTY (2 Strikes -> 50% Size)
	if pe.ConsecutiveLosses == 2 {
		notional = notional * 0.50
		tierStr = fmt.Sprintf("%s [STRIKE 2: 50%%]", tierStr)
	}

	// RATIO-BASED TIERING (Double Confirmation)
	if ratio < 1.50 && !isSafety {
		notional = notional * 0.30
		tierStr = fmt.Sprintf("%s [TEST-30%%]", tierStr)
	}

	log.Printf("%s SIGNAL FOUND: %s %s | Score: $%.0f | Ratio: %.2f", tierStr, side, symbol, volume, ratio)

	return &PredatorPosition{
		Symbol:     symbol,
		Side:       side,
		Entry:      price,
		Score:      score,
		MarginUsed: notional, // Target Notional Value
		Leverage:   leverage,
		Tier:       tierStr,
		TakeProfit: profitTarget, // Temporary storage or logic hint? We recalc TP in executeTrade anyway.
	}
}

// MarginCalculator Service
func (pe *PredatorEngine) CalculateDynamicMargin(symbol string) (float64, int, float64) {
	// 1. Defaults
	leverage := 20
	profitTarget := 10.0 // $10 Net Profit
	targetMove := 0.002  // 0.2% Move

	norm := NormalizeSymbol(symbol)

	// 2. Asset Specifics
	if strings.Contains(norm, "BTC") {
		leverage = 20
	} else if strings.Contains(norm, "ETH") {
		leverage = 15
	} else if strings.Contains(norm, "SOL") {
		leverage = 10
	} else {
		leverage = 10 // Fallback
	}

	// 3. Calculate Required Notional
	// Notional = Profit / Move
	requiredNotional := profitTarget / targetMove // $5000

	// 4. Wallet Guardrail
	// Max Margin = $500
	marginReq := requiredNotional / float64(leverage)

	if marginReq > 500.0 {
		// Log Warning & Scale Down
		// If we need > $500 margin, it means wallet can't support $10 profit target safely.
		// Scale to $5 Profit (Generic Fallback)
		profitTarget = 5.0
		requiredNotional = profitTarget / targetMove // $2500
		marginReq = requiredNotional / float64(leverage)
	}

	log.Printf("🎯 IDEAL MARGIN: Using $%.2f on %s for a $%.2f profit target.", marginReq, symbol, profitTarget)

	return requiredNotional, leverage, profitTarget
}

// CalculateNetTP covers fees (0.15% est) to ensure Net Profit Target
func (pe *PredatorEngine) CalculateNetTP(entry, qty, targetProfit float64) float64 {
	// Cost = EntryFee + ExitFee + Slippage
	// Rate = 0.05% + 0.05% + 0.05% = 0.15%
	notional := entry * qty
	costs := notional * 0.0015

	grossTarget := targetProfit + costs

	// Price Distance needed
	dist := grossTarget / qty

	return dist // Return the DISTANCE to add/sub
}

// CheckLivePosition queries Binance for an active position on this symbol
func (pe *PredatorEngine) CheckLivePosition(symbol string) bool {
	normSymbol := NormalizeSymbol(symbol)

	// Quick API Call
	res, err := pe.client.NewGetAccountService().Do(context.Background())
	if err != nil {
		log.Printf("⚠️ Account Check Failed: %v", err)
		return true // Fail safe: Assume position exists to block trade
	}

	for _, p := range res.Positions {
		if p.Symbol == normSymbol {
			amt, _ := strconv.ParseFloat(p.PositionAmt, 64)
			if amt != 0 {
				return true
			}
		}
	}
	return false
}

func (pe *PredatorEngine) attemptExecution(candidate *PredatorPosition) {
	pe.mu.Lock()
	// 0. DEBOUNCE: Signal Cooldown (60s)
	if cooldown, ok := pe.TradeCooldowns[candidate.Symbol]; ok {
		if time.Now().Before(cooldown) {
			pe.mu.Unlock()
			return
		}
	}
	pe.mu.Unlock()

	// ---------------------------------------------------------
	// CLIENT-SIDE EXECUTION UPDATE
	// ---------------------------------------------------------
	// We do NOT execute on backend anymore to avoid -2015 IP Errors.
	// Signals are already broadcasted in scanForWhales.
	// We simply return here to stop the engine from trying to trade.
	// log.Printf("🔇 BACKEND EXECUTION DISABLED (Client-Side Mode): Skipping %s", candidate.Symbol)
	return

	// 1. Local State Check
	/*
		pe.mu.Lock()
		if _, exists := pe.positions[candidate.Symbol]; exists {
			pe.mu.Unlock()
			log.Printf("🔇 POSITION LOCK (Local): Already in %s. Skipping attack.", candidate.Symbol)
			return
		}
		pe.mu.Unlock()

		// 2. API Position Check (Hard Lock)
		if pe.CheckLivePosition(candidate.Symbol) {
			log.Printf("🔇 POSITION LOCK (API): Binance reports active %s position. Skipping.", candidate.Symbol)
			return
		}

		targetNotional := candidate.MarginUsed
		if targetNotional == 0 {
			return
		}

		// 3. Global Guard Check
		if !pe.guard.CanEnter(candidate.Symbol, targetNotional) {
			return
		}

		// EXECUTE
		pe.executeTrade(candidate)
	*/
}

func (pe *PredatorEngine) executeTrade(pos *PredatorPosition) {
	pe.mu.Lock()
	if _, exists := pe.positions[pos.Symbol]; exists {
		pe.mu.Unlock()
		return
	}
	pe.mu.Unlock()

	normSymbol := NormalizeSymbol(pos.Symbol)
	targetNotional := pos.MarginUsed

	// 0. SLIPPAGE GUARD (Pre-Flight Check)
	// Fetch latest price to ensure we aren't chasing a spike > 0.02%
	currentPrice, ok := pe.currentPrices[pos.Symbol]
	if ok && currentPrice > 0 {
		diff := math.Abs(currentPrice-pos.Entry) / pos.Entry
		if diff > 0.0002 { // 0.02% Limit
			log.Printf("🛑 SLIPPAGE GUARD: Aborted %s. Price drifted %.4f%% (> 0.02%% Limit).", pos.Symbol, diff*100)
			return
		}
		// Update Entry to latest price for accurate calculations
		pos.Entry = currentPrice
	}

	log.Printf("🦖 PREDATOR SNIPER ATTACK: %s %s (Vol: $%.0f) [Size: $%.2f]", pos.Side, pos.Symbol, pos.Score, targetNotional)

	// 1. Set Leverage
	pe.client.NewChangeLeverageService().Symbol(normSymbol).Leverage(pos.Leverage).Do(context.Background())

	// 2. Force Isolated
	pe.client.NewChangeMarginTypeService().Symbol(normSymbol).MarginType(futures.MarginTypeIsolated).Do(context.Background())

	// 3. Market Entry
	qty := targetNotional / pos.Entry
	ordSide := futures.SideTypeBuy
	if pos.Side == "SHORT" {
		ordSide = futures.SideTypeSell
	}

	// Use Dynamic Formatting
	qtyStr := pe.FormatQty(normSymbol, qty)

	cOrder := pe.client.NewCreateOrderService().
		Symbol(normSymbol).
		Side(ordSide).
		Type(futures.OrderTypeMarket).
		Quantity(qtyStr)

	res, err := cOrder.Do(context.Background())
	if err != nil {
		log.Printf("⚠️ Exec Fail [%s]: %v", normSymbol, err)
		time.Sleep(100 * time.Millisecond)
		return
	}

	avgPrice, _ := strconv.ParseFloat(res.AvgPrice, 64)
	if avgPrice == 0 {
		avgPrice = pos.Entry
	}

	// Update Size with Executed Qty (if possible, or formatted Qty)
	parsedQty, _ := strconv.ParseFloat(qtyStr, 64)
	pos.Size = parsedQty // Use the actual size sent

	// Set Cooldown
	pe.mu.Lock()
	pe.TradeCooldowns[pos.Symbol] = time.Now().Add(60 * time.Second)
	pe.mu.Unlock()

	// Update Position
	pos.Entry = avgPrice
	pos.Size = qty
	pos.StartTime = time.Now()
	if pos.Leverage > 0 {
		pos.MarginUsed = (avgPrice * qty) / float64(pos.Leverage)
	} else {
		pos.MarginUsed = (avgPrice * qty) / 20.0
	}

	// 🛰️ SNIPER LOGIC: NET PROFIT & OCO
	stopDist := 5.0 / qty

	// 1. Calculate Net Take Profit
	tpDist := pe.CalculateNetTP(pos.Entry, qty, pos.TakeProfit) // Returns distance

	tpPrice := pos.Entry + tpDist
	slPrice := pos.Entry - stopDist

	if pos.Side == "SHORT" {
		tpPrice = pos.Entry - tpDist
		slPrice = pos.Entry + stopDist
	}

	pos.TakeProfit = tpPrice
	pos.StopLoss = slPrice

	tpSide := futures.SideTypeSell
	if pos.Side == "SHORT" {
		tpSide = futures.SideTypeBuy
	}

	// 3. Place TP (Limit Maker)
	priceStr := pe.FormatPrice(normSymbol, tpPrice)
	qtyStr = pe.FormatQty(normSymbol, qty) // Reuse formatted qty

	tpRes, err := pe.client.NewCreateOrderService().
		Symbol(normSymbol).
		Side(tpSide).
		Type(futures.OrderTypeLimit).
		TimeInForce(futures.TimeInForceTypeGTX). // Maker Only
		Quantity(qtyStr).
		Price(priceStr).
		Do(context.Background())

	if err == nil {
		pos.TPOrderID = tpRes.OrderID
		log.Printf("🎯 TP PLACED: $%s (+$30.00)", priceStr)
	}

	// 4. Place SL (Stop Limit Aggressive)
	// Calculate Limit Price (Aggressive to ensure fill)
	slLimitPrice := slPrice * 0.99
	if pos.Side == "SHORT" {
		slLimitPrice = slPrice * 1.01
	}

	stopPriceStr := pe.FormatPrice(normSymbol, slPrice)
	limitPriceStr := pe.FormatPrice(normSymbol, slLimitPrice)

	slRes, err := pe.client.NewCreateOrderService().
		Symbol(normSymbol).
		Side(tpSide).
		Type(futures.OrderType("STOP")). // Changed to STOP Limit
		Quantity(qtyStr).
		StopPrice(stopPriceStr).
		Price(limitPriceStr). // Required
		WorkingType(futures.WorkingTypeMarkPrice).
		PriceProtect(true).
		Do(context.Background())

	if err == nil {
		pos.SLOrderID = slRes.OrderID
		log.Printf("🛡️ SL PLACED (Limit): $%s (Trigger) / $%s (Limit)", stopPriceStr, limitPriceStr)
	}

	pe.mu.Lock()
	pe.positions[pos.Symbol] = pos
	pe.mu.Unlock()

	pe.guard.RegisterTrade(pos.Symbol, pos.MarginUsed)

	// BROADCAST SHIELD STATUS (Grey = Active, Not Secured Yet)
	if pe.hub != nil {
		shield := map[string]interface{}{
			"type":    "ADVICE",
			"symbol":  pos.Symbol,
			"message": "Entry Active. Shield Deploying...",
			"tier":    "SHIELD_GREY",
		}
		data, _ := json.Marshal(shield)
		pe.hub.BroadcastSignal(data)
	}

	log.Printf("📱 DASHBOARD UPDATE: %s ACTIVE [%s] [2:1 SNIPER MODE]", pos.Symbol, pos.Tier)

	// 📡 BROADCAST TO SIGNAL HUB (Moved to scanForWhales for visibility)
	// if pe.hub != nil { ... }
}

func (pe *PredatorEngine) monitorPositions() {
	ticker := time.NewTicker(500 * time.Millisecond)
	statusTicker := time.NewTicker(5 * time.Second)

	for {
		select {
		case <-statusTicker.C:
			pe.mu.Lock()
			status := "🔍 Hunting:"
			targets := []string{
				"BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT",
				"ADAUSDT", "DOGEUSDT", "AVAXUSDT", "TRXUSDT", "PEPEUSDT",
			}
			for _, sym := range targets {
				state := "WAITING"
				if _, ok := pe.positions[sym]; ok {
					state = "ACTIVE"
				}
				status += fmt.Sprintf(" [%s: %s]", sym[:3], state)
			}
			log.Println(status)
			pe.mu.Unlock()

		case <-ticker.C:
			pe.mu.Lock()
			for sym, pos := range pe.positions {
				// Timeout (Force Exit after 60 mins for Scalp?? Or keep open?)
				// Sniper mode usually implies waiting for targets. Removing hard timeout or extending it.
				if time.Since(pos.StartTime).Seconds() > 3600 {
					log.Printf("⌛ TIMEOUT: %s", sym)
					go pe.closePosition(pos, "TIMEOUT")
				}

				price, ok := pe.currentPrices[sym]
				if ok {
					var pnlUsd float64
					if pos.Side == "LONG" {
						pnlUsd = (price - pos.Entry) * pos.Size
					} else {
						pnlUsd = (pos.Entry - price) * pos.Size
					}

					// Update Max PnL
					if pnlUsd > pos.MaxPnL {
						pos.MaxPnL = pnlUsd
					}

					// 4. GREEN GUARD (Zero-Loss Trigger)
					// If ROE > 0.10%, move SL to Entry + Fees
					if !pos.IsBreakEvenSet {
						roe := 0.0
						if pos.MarginUsed > 0 {
							roe = pnlUsd / pos.MarginUsed // Approx ROE using Margin
						}

						if roe > 0.0010 { // +0.10% ROE
							// Trigger Green Guard
							log.Printf("🛡️ GREEN GUARD: %s ROE > 0.10%%. Locking in Fees.", pos.Symbol)

							// Calculate Break-Even Price (Entry +/- 0.06%)
							feeRate := 0.0006
							bePrice := 0.0
							if pos.Side == "LONG" {
								bePrice = pos.Entry * (1 + feeRate)
							} else {
								bePrice = pos.Entry * (1 - feeRate)
							}

							// Cancel Old SL
							if pos.SLOrderID != 0 {
								pe.client.NewCancelOrderService().Symbol(NormalizeSymbol(pos.Symbol)).OrderID(pos.SLOrderID).Do(context.Background())
							}

							// Determine tpSide for the new SL order
							tpSide := futures.SideTypeSell
							if pos.Side == "SHORT" {
								tpSide = futures.SideTypeBuy
							}

							// Determine precision for the symbol
							normSymbol := NormalizeSymbol(pos.Symbol)
							bePriceStr := pe.FormatPrice(normSymbol, bePrice)

							// Place New SL (STOP MARKET)
							// Fixed -4120: Using ClosePosition(true) instead of Quantity
							slRes, err := pe.client.NewCreateOrderService().
								Symbol(normSymbol).
								Side(tpSide).
								Type(futures.OrderType("STOP_MARKET")).
								StopPrice(bePriceStr).
								ClosePosition(true). // AUTO-CLOSE
								WorkingType(futures.WorkingTypeMarkPrice).
								Do(context.Background())

							if err == nil {
								pos.SLOrderID = slRes.OrderID
								pos.StopLoss = bePrice
								pos.IsBreakEvenSet = true
								log.Printf("🔒 SL UPDATED: %s Locked at $%.2f (Green Guard)", pos.Symbol, bePrice)

								// BROADCAST SHIELD STATUS (Green = Secured)
								if pe.hub != nil {
									shield := map[string]interface{}{
										"type":    "ADVICE",
										"symbol":  pos.Symbol,
										"message": "Green Guard Active. Profit Secured.",
										"tier":    "SHIELD_GREEN",
									}
									data, _ := json.Marshal(shield)
									pe.hub.BroadcastSignal(data)
								}
							} else {
								log.Printf("⚠️ Failed to place Green Guard SL: %v", err)
							}
						}
					}

					// 🛡️ BREAK-EVEN TRIGGER
					// If Profit >= $15, Move SL to Entry + $2
					if pnlUsd >= 15.0 && !pos.IsBreakEvenSet {
						log.Printf("🔓 BREAK-EVEN UNLOCKED: %s PnL $%.2f >= $15.00", sym, pnlUsd)
						go pe.MoveStopToBreakEven(pos)
						pos.IsBreakEvenSet = true // Mark locally immediately
					}

					// Note: TP/SL are handled by Server Orders (OCO).
					// But we still monitor for manual or unexpected fills via WebSocket (User Data Stream not impl here yet).
					// If we detect price passed TP/SL significantly, we can cleanup.
					// For now, rely on Server Orders.
				}
			}
			pe.mu.Unlock()
		}
	}
}

func (pe *PredatorEngine) MoveStopToBreakEven(pos *PredatorPosition) {
	normSymbol := NormalizeSymbol(pos.Symbol)

	// 1. Cancel Old SL
	if pos.SLOrderID != 0 {
		pe.client.NewCancelOrderService().Symbol(normSymbol).OrderID(pos.SLOrderID).Do(context.Background())
	}

	// 2. Calc New SL = Entry + $2
	bePrice := 0.0
	bonus := 2.0 / pos.Size

	if pos.Side == "LONG" {
		bePrice = pos.Entry + bonus
	} else {
		bePrice = pos.Entry - bonus
	}

	prec := "%.3f"
	if strings.Contains(normSymbol, "SOL") {
		prec = "%.0f"
	}
	if strings.Contains(normSymbol, "ETH") {
		prec = "%.2f"
	}

	tpSide := futures.SideTypeSell
	if pos.Side == "SHORT" {
		tpSide = futures.SideTypeBuy
	}

	// 3. Place New STOP MARKET (Aggressive)
	// Fixed -4120: Using ClosePosition(true)
	res, err := pe.client.NewCreateOrderService().
		Symbol(normSymbol).
		Side(tpSide).
		Type(futures.OrderType("STOP_MARKET")).
		StopPrice(fmt.Sprintf(prec, bePrice)).
		ClosePosition(true). // AUTO-CLOSE
		WorkingType(futures.WorkingTypeMarkPrice).
		PriceProtect(true).
		Do(context.Background())

	if err == nil {
		pe.mu.Lock()
		if p, ok := pe.positions[pos.Symbol]; ok {
			p.SLOrderID = res.OrderID
			p.StopLoss = bePrice
			// p.IsBreakEvenSet = true (already set)
		}
		pe.mu.Unlock()
		log.Printf("🔒 SL UPDATED: %s Locked at $%.2f (Entry + $2)", pos.Symbol, bePrice)
	} else {
		log.Printf("⚠️ Failed to move SL: %v", err)
	}
}

func (pe *PredatorEngine) closePosition(pos *PredatorPosition, reason string) {
	normSymbol := NormalizeSymbol(pos.Symbol)

	// 1. Cancel Open Orders (TP/SL)
	if pos.TPOrderID != 0 {
		pe.client.NewCancelOrderService().Symbol(normSymbol).OrderID(pos.TPOrderID).Do(context.Background())
	}
	if pos.SLOrderID != 0 {
		pe.client.NewCancelOrderService().Symbol(normSymbol).OrderID(pos.SLOrderID).Do(context.Background())
	}

	// 2. Market Close
	side := futures.SideTypeSell
	if pos.Side == "SHORT" {
		side = futures.SideTypeBuy
	}

	pe.client.NewCreateOrderService().
		Symbol(normSymbol).
		Side(side).
		Type(futures.OrderTypeMarket).
		Quantity(fmt.Sprintf("%.3f", pos.Size)).
		Do(context.Background())

	pe.mu.Lock()
	delete(pe.positions, pos.Symbol)
	pe.mu.Unlock()

	pe.guard.ReleaseTrade(pos.Symbol)

	// Update Circuit Breaker
	pe.mu.Lock()
	price, ok := pe.currentPrices[pos.Symbol]
	if ok {
		var pnl float64
		if pos.Side == "LONG" {
			pnl = (price - pos.Entry) * pos.Size
		} else {
			pnl = (pos.Entry - price) * pos.Size
		}
		pe.DailyRealizedPnL += pnl

		if pnl < 0 {
			pe.ConsecutiveLosses++
			if pe.ConsecutiveLosses == 2 {
				log.Printf("⚠️ STRIKE 2: Next trade reduced by 50%%.")
			}

			if pe.ConsecutiveLosses >= 3 {
				// LOCKDOWN
				pe.SafetyModeUntil = time.Now().Add(2 * time.Hour)
				pe.ConsecutiveLosses = 0

				log.Printf("🚨 CIRCUIT BREAKER: 3 Consecutive Losses. Predator Disabled for 2 Hours.")
				if pe.notifier != nil {
					pe.notifier.Notify("⚠️ **Predator Paused**\n3 losses in a row detected. Cooldown active for 2 hours.")
					pe.notifier.SendAppPush(PublicSignal{
						Symbol:     "SYSTEM",
						Direction:  "PAUSED",
						Stars:      3,
						EntryZone:  "Lockdown",
						Volatility: "High",
					})
				}

				// Cancel ALL Open Orders
				go pe.StopAll()
			}
		} else {
			pe.ConsecutiveLosses = 0
		}

		log.Printf("💀 CLOSED %s (%s) | Est PnL: $%.2f | Daily PnL: $%.2f", pos.Symbol, reason, pnl, pe.DailyRealizedPnL)

		if pe.DailyRealizedPnL <= -100.0 {
			log.Printf("🚨 DAILY LOSS LIMIT HIT. SHUTTING DOWN.")
			pe.active = false
		}
	}
	pe.mu.Unlock()
}

// StopAll cancels all open orders for all tracked symbols.
func (pe *PredatorEngine) StopAll() {
	log.Println("🛑 STOPPING ALL ORDERS...")

	// 1. Cancel Orders for all current positions
	pe.mu.Lock()
	for sym, pos := range pe.positions {
		normSymbol := NormalizeSymbol(sym)
		if pos.TPOrderID != 0 {
			pe.client.NewCancelOrderService().Symbol(normSymbol).OrderID(pos.TPOrderID).Do(context.Background())
		}
		if pos.SLOrderID != 0 {
			pe.client.NewCancelOrderService().Symbol(normSymbol).OrderID(pos.SLOrderID).Do(context.Background())
		}
	}
	pe.mu.Unlock()

	// 2. Also Cancel any rouge orders on target pairs
	targets := []string{"BTCUSDT", "ETHUSDT", "SOLUSDT"}
	for _, sym := range targets {
		pe.client.NewCancelAllOpenOrdersService().Symbol(sym).Do(context.Background())
	}
}
