package main

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"sync"
	"time"
)

// Advice Constants
const (
	AdviceHold      = "💪 STRONG HOLD"
	AdviceTrim      = "✂️ TRIM POSITION"
	AdviceExit      = "🚨 IMMEDIATE EXIT"
	AdviceWarning   = "⚠️ TREND FLIP"
	AdviceLiquidity = "💧 SUPPORT THIN"
	AdviceNeutral   = "👀 MONITORING"
)

// TradeSession tracks a user's active "Co-Pilot" session
type TradeSession struct {
	ID               string
	UserID           string // For future multi-user support
	Symbol           string
	EntryPrice       float64
	Side             string // "LONG" or "SHORT"
	StartTime        time.Time
	LastAdvice       string
	Reason           string
	PnLPercent       float64
	BearishStartTime time.Time // For Hysteresis
}

// CoPilotService acts as the real-time advisor
type CoPilotService struct {
	mu            sync.RWMutex
	sessions      map[string]*TradeSession
	trendAnalyzer *TrendAnalyzer
	distributor   *AppSignalDistributor // To push updates to app

	// Cache for recent whales to check against trades
	recentWhales map[string]Trade // Symbol -> Last Huge Whale
}

// NewCoPilotService creates the advisor
func NewCoPilotService(ta *TrendAnalyzer, dist *AppSignalDistributor) *CoPilotService {
	cp := &CoPilotService{
		sessions:      make(map[string]*TradeSession),
		trendAnalyzer: ta,
		distributor:   dist,
		recentWhales:  make(map[string]Trade),
	}

	// Start the Advisor Loop
	go cp.advisorLoop()

	return cp
}

// TrackPublicSession is the entry point for "I'm In" logic
func (cp *CoPilotService) TrackPublicSession(userID, symbol, side string, entryPrice float64) string {
	return cp.StartSession(userID, symbol, side, entryPrice)
}

// StartSession is called when the user clicks "I'm In"
func (cp *CoPilotService) StartSession(userID, symbol, side string, entryPrice float64) string {
	cp.mu.Lock()
	defer cp.mu.Unlock()

	sessionID := fmt.Sprintf("%s-%d", symbol, time.Now().UnixNano())
	cp.sessions[sessionID] = &TradeSession{
		ID:         sessionID,
		UserID:     userID,
		Symbol:     NormalizeSymbol(symbol),
		EntryPrice: entryPrice,
		Side:       side,
		StartTime:  time.Now(),
		LastAdvice: AdviceNeutral,
		Reason:     "Initializing Co-Pilot...",
	}

	log.Printf("👨‍✈️ CO-PILOT: Started Session for %s %s @ %.2f", side, symbol, entryPrice)
	return sessionID
}

// StopSession ends the tracking
func (cp *CoPilotService) StopSession(sessionID string) {
	cp.mu.Lock()
	defer cp.mu.Unlock()
	delete(cp.sessions, sessionID)
}

// OnTrade feeds real-time data to the Co-Pilot
func (cp *CoPilotService) OnTrade(trade Trade) {
	// Track Huge Whales for "Opposite Direction" checks
	if trade.Notional > 500000 {
		cp.mu.Lock()
		cp.recentWhales[trade.Symbol] = trade
		cp.mu.Unlock()
	}
}

// advisorLoop runs every second to check all active sessions
func (cp *CoPilotService) advisorLoop() {
	ticker := time.NewTicker(1 * time.Second)
	for range ticker.C {
		cp.checkSessions()
	}
}

func (cp *CoPilotService) checkSessions() {
	cp.mu.Lock()
	defer cp.mu.Unlock()

	for _, session := range cp.sessions {
		advice, reason := cp.evaluateSession(session)

		// Update Session State
		session.LastAdvice = advice
		session.Reason = reason

		// Push Update to App (Simulated via Log just like alerts for now)
		// In a real app, this would send a WebSocket message targeted to UserID
		log.Printf("👨‍✈️ ADVICE [%s]: %s | PnL: %.2f%% | %s", session.Symbol, advice, session.PnLPercent, reason)
	}
}

func (cp *CoPilotService) evaluateSession(s *TradeSession) (string, string) {
	// 1. GET CURRENT PRICE (Using recent whales or direct fetch fallback)
	currentPrice := s.EntryPrice
	if lastTrade, ok := cp.recentWhales[s.Symbol]; ok {
		currentPrice = lastTrade.Price
	} else {
		// Fallback: Check ListPrices (Heavy but needed if no trade stream yet)
		prices, err := cp.trendAnalyzer.client.NewListPricesService().Symbol(s.Symbol).Do(context.Background())
		if err == nil && len(prices) > 0 {
			currentPrice, _ = strconv.ParseFloat(prices[0].Price, 64)
		}
	}

	// Calculate PnL
	var pnl float64
	if s.Side == "LONG" {
		pnl = (currentPrice - s.EntryPrice) / s.EntryPrice * 100
	} else {
		pnl = (s.EntryPrice - currentPrice) / s.EntryPrice * 100
	}
	s.PnLPercent = pnl

	// 2. CHECK EXIT SIGNAL (Whale > $500k Opposite for > 10s - Hysteresis)
	// We check if "Bearish Pressure" is sustained.
	if lastWhale, ok := cp.recentWhales[s.Symbol]; ok {
		// Is this a threat?
		isOpposite := (s.Side == "LONG" && lastWhale.Side == "sell") || (s.Side == "SHORT" && lastWhale.Side == "buy")
		isHuge := lastWhale.Notional > 500000

		if isOpposite && isHuge && time.Since(time.UnixMilli(lastWhale.Timestamp)).Seconds() < 60 {
			// Whale is recent (<60s). Start/Check Timer.
			if s.BearishStartTime.IsZero() {
				s.BearishStartTime = time.Now() // Start Timer
				return AdviceWarning, "⚠️ Measuring Selling Pressure... (Standby)"
			} else {
				// Timer Running
				if time.Since(s.BearishStartTime).Seconds() > 10 {
					// Sustained for > 10s. EXIT.
					return AdviceExit, fmt.Sprintf("🚨 WHALE DUMP CONFIRMED ($%.1fM). EXIT NOW.", lastWhale.Notional/1000000)
				}
				return AdviceWarning, fmt.Sprintf("⚠️ Selling Pressure Detected... Hold (%ds)", int(10-time.Since(s.BearishStartTime).Seconds()))
			}
		} else {
			// No threat currently. Reset Timer.
			if !s.BearishStartTime.IsZero() {
				s.BearishStartTime = time.Time{} // Reset
			}
		}
	}

	// 4. TREND FLIP (1M EMA Cross)
	// Fetch Scalp Trend (1m mapped to Trend15M field)
	scalpResult := cp.trendAnalyzer.GetScalpTrend(s.Symbol)
	trend1m := scalpResult.Trend15M

	if s.Side == "LONG" && trend1m == TrendBearish {
		return AdviceWarning, "📉 Short-term momentum lost. Exit suggested."
	}
	if s.Side == "SHORT" && trend1m == TrendBullish {
		return AdviceWarning, "📈 Short-term momentum lost. Exit suggested."
	}

	// 5. STOP-LOSS ASSIST (Liquidity Check)
	if pnl < -0.3 {
		if cp.checkLiquidityThin(s.Symbol, s.Side) {
			return AdviceLiquidity, "🚨 Support is thin. High risk of drop."
		}
	}

	// 6. FEE SAVER (Price Escaping - First 60s)
	if time.Since(s.StartTime).Seconds() < 60 {
		if pnl > 0.1 {
			return AdviceWarning, "⚠️ Price escaping. Limit update recommended."
		}
	}

	// 7. TRAILING CO-PILOT (Lock Profit)
	if pnl > 0.2 {
		return AdviceTrim, "🔒 Lock Profit: Move Stop to Entry."
	}

	// Hard Stop / Target
	if pnl < -0.5 {
		return AdviceExit, "🛑 Stop Hit (-0.5%)"
	}
	if pnl > 0.5 {
		return AdviceTrim, "💰 Target Reached (+0.5%)"
	}

	return AdviceNeutral, "Market Ranging... Volume Balanced."
}

// SmartTradeParams holds entry and risk levels
type SmartTradeParams struct {
	EntryPrice float64
	StopLoss   float64
	TakeProfit float64
}

// GetSmartEntry calculates optimal entry, SL, and TP
func (cp *CoPilotService) GetSmartEntry(symbol, side string) SmartTradeParams {
	// 1. Fetch Price
	prices, err := cp.trendAnalyzer.client.NewListPricesService().Symbol(symbol).Do(context.Background())
	if err != nil || len(prices) == 0 {
		return SmartTradeParams{}
	}
	currentPrice, _ := strconv.ParseFloat(prices[0].Price, 64)

	// 2. Base Calculation (Maker Entry, 0.15% SL, 0.3% TP)
	var entry, sl, tp float64

	if side == "LONG" {
		entry = currentPrice * 0.9999
		sl = entry * 0.9985 // -0.15%
		tp = entry * 1.003  // +0.3%
	} else {
		entry = currentPrice * 1.0001
		sl = entry * 1.0015 // +0.15%
		tp = entry * 0.997  // -0.3%
	}

	// 3. WHALE-AWARE SL ADJUSTMENT (Iceberg Check)
	// Fetch Depth to detect walls near calculated SL
	// We look for walls *between* entry and standard SL, or just beyond standard SL?
	// Prompt: "If ICEBERG detected... place SL $5.00 above/below".
	// We scan depth.
	depth, err := cp.trendAnalyzer.client.NewDepthService().Symbol(symbol).Limit(20).Do(context.Background())
	if err == nil {
		threshold := 500000.0 // > $500k

		if side == "LONG" {
			// Look for BUY walls (Support) below entry
			for _, bid := range depth.Bids {
				price, _ := strconv.ParseFloat(bid.Price, 64)
				qty, _ := strconv.ParseFloat(bid.Quantity, 64)
				if price*qty > threshold {
					// If Wall is close to our SL (e.g. within 0.1%), use it as anchor
					// Logic: SL should be BELOW the Wall (Support).
					// Prompt said "Above", but for Long Support, "Above" exposes you to being stopped before wall holds.
					// Assuming "Safety" means "Behind Wall": SL = Wall - 5.0.
					if price < entry && price > (entry*0.99) { // Wall is relevant
						sl = price - 5.0
						break // Use first major wall closest to price
					}
				}
			}
		} else {
			// Look for SELL walls (Resistance) above entry
			for _, ask := range depth.Asks {
				price, _ := strconv.ParseFloat(ask.Price, 64)
				qty, _ := strconv.ParseFloat(ask.Quantity, 64)
				if price*qty > threshold {
					if price > entry && price < (entry*1.01) {
						sl = price + 5.0
						break
					}
				}
			}
		}
	}

	return SmartTradeParams{EntryPrice: entry, StopLoss: sl, TakeProfit: tp}
}

// GetWallAdvice analysis order book for walls near the recommended entry
func (cp *CoPilotService) GetWallAdvice(symbol, side string, entryPrice float64) string {
	// Fetch Depth
	depth, err := cp.trendAnalyzer.client.NewDepthService().Symbol(symbol).Limit(10).Do(context.Background())
	if err != nil {
		return "Analyzing liquidity..."
	}

	threshold := 500000.0 // > $500k wall

	if side == "LONG" {
		for _, bid := range depth.Bids {
			price, _ := strconv.ParseFloat(bid.Price, 64)
			qty, _ := strconv.ParseFloat(bid.Quantity, 64)
			notional := price * qty
			if notional > threshold && Abs(price-entryPrice)/entryPrice < 0.002 {
				return "🐳 Huge Buy Wall at entry. High chance of fill."
			}
		}
	} else {
		for _, ask := range depth.Asks {
			price, _ := strconv.ParseFloat(ask.Price, 64)
			qty, _ := strconv.ParseFloat(ask.Quantity, 64)
			notional := price * qty
			if notional > threshold && Abs(price-entryPrice)/entryPrice < 0.002 {
				return "🐳 Huge Sell Wall at entry. High chance of fill."
			}
		}
	}
	return "Liquidity normal."
}

// Helper for Abs
func Abs(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}

// checkLiquidityThin checks if support is weak against the user's position
func (cp *CoPilotService) checkLiquidityThin(symbol, userSide string) bool {
	// Fetch Depth (Top 20 levels)
	depth, err := cp.trendAnalyzer.client.NewDepthService().Symbol(symbol).Limit(20).Do(context.Background())
	if err != nil {
		return false // Assume safe if data missing
	}

	var supportVol, resistanceVol float64

	// Sum Bids and Asks
	for _, bid := range depth.Bids {
		qty, _ := strconv.ParseFloat(bid.Quantity, 64)
		supportVol += qty
	}
	for _, ask := range depth.Asks {
		qty, _ := strconv.ParseFloat(ask.Quantity, 64)
		resistanceVol += qty
	}

	// Logic: If I am LONG, I need Support (Bids). If Bids < Asks * 0.5, it's thin.
	if userSide == "LONG" {
		return supportVol < (resistanceVol * 0.5)
	}
	// If I am SHORT, I need Resistance (Asks). If Asks < Bids * 0.5, it's thin.
	return resistanceVol < (supportVol * 0.5)
}
