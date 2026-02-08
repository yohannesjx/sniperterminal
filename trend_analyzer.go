package main

import (
	"context"
	"log"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/adshao/go-binance/v2/futures"
)

// TrendStatus enum
type TrendStatus string

const (
	TrendBullish TrendStatus = "BULLISH 🟢"
	TrendBearish TrendStatus = "BEARISH 🔴"
	TrendNeutral TrendStatus = "NEUTRAL ⚪"
)

// TrendAnalyzer handles technical analysis
type TrendAnalyzer struct {
	client *futures.Client
}

// NewTrendAnalyzer creates the service
func NewTrendAnalyzer(client *futures.Client) *TrendAnalyzer {
	return &TrendAnalyzer{client: client}
}

// TrendResult holds the analysis
type TrendResult struct {
	Trend1H   TrendStatus
	Trend15M  TrendStatus
	Trend5M   TrendStatus // New
	Trend1M   TrendStatus // New
	RSI       float64
	IsCounter bool
}

// NormalizeSymbol ensures the symbol ends with USDT
func NormalizeSymbol(symbol string) string {
	symbol = strings.ToUpper(symbol)
	if !strings.HasSuffix(symbol, "USDT") {
		return symbol + "USDT"
	}
	return symbol
}

// GetMarketTrend analyzes multiple timeframes
func (ta *TrendAnalyzer) GetMarketTrend(symbol string, side string) TrendResult {
	res := TrendResult{
		Trend1H:  TrendNeutral,
		Trend15M: TrendNeutral,
		Trend5M:  TrendNeutral,
		Trend1M:  TrendNeutral,
		RSI:      50.0,
	}

	// Analyze Timeframes
	res.Trend1H = ta.analyzeTimeframe(symbol, "1h")
	res.Trend15M = ta.analyzeTimeframe(symbol, "15m")
	res.Trend5M = ta.analyzeTimeframe(symbol, "5m")
	res.Trend1M = ta.analyzeTimeframe(symbol, "1m")

	res.RSI = ta.calculateRSI(symbol, "15m", 14)

	// Determine Counter-Trend (Against Macro)
	isBullish := res.Trend1H == TrendBullish && res.Trend15M == TrendBullish
	isBearish := res.Trend1H == TrendBearish && res.Trend15M == TrendBearish

	if side == "LONG" && !isBullish {
		res.IsCounter = true
	}
	if side == "SHORT" && !isBearish {
		res.IsCounter = true
	}

	return res
}

// analyzeTimeframe calculates EMA9 vs EMA21 with FAIL-SAFE RETRY
func (ta *TrendAnalyzer) analyzeTimeframe(symbol string, interval string) TrendStatus {
	validSymbol := NormalizeSymbol(symbol)

	// Need 30 candles to calc EMA21 accurately
	// Retry Loop (Max 2 Attempts)
	var klines []*futures.Kline
	var err error

	for i := 0; i < 2; i++ {
		klines, err = ta.client.NewKlinesService().
			Symbol(validSymbol).
			Interval(interval).
			Limit(30).
			Do(context.Background())

		if err == nil && len(klines) >= 25 {
			break // Success
		}

		// Wait before retry if failed
		if i == 0 {
			time.Sleep(500 * time.Millisecond)
		}
	}

	if err != nil || len(klines) < 25 {
		// Only log if it's NOT an Invalid Symbol error
		if err != nil && !strings.Contains(err.Error(), "-1121") {
			log.Printf("⚠️ TrendAnalyzer: Failed to fetch %s %s klines: %v", validSymbol, interval, err)
		}
		return TrendNeutral
	}

	prices := make([]float64, len(klines))
	for i, k := range klines {
		price, _ := strconv.ParseFloat(k.Close, 64)
		prices[i] = price
	}

	ema9 := calculateEMA(prices, 9)
	ema21 := calculateEMA(prices, 21)

	if ema9 > ema21 {
		return TrendBullish
	}
	return TrendBearish
}

// GetEMA calculates the specific EMA value for a symbol/interval/period
func (ta *TrendAnalyzer) GetEMA(symbol string, interval string, period int) float64 {
	validSymbol := NormalizeSymbol(symbol)

	// Fetch Klines (needs at least period + 10 for smoothing)
	klines, err := ta.client.NewKlinesService().
		Symbol(validSymbol).
		Interval(interval).
		Limit(period + 20).
		Do(context.Background())

	if err != nil || len(klines) < period {
		return 0.0
	}

	prices := make([]float64, len(klines))
	for i, k := range klines {
		price, _ := strconv.ParseFloat(k.Close, 64)
		prices[i] = price
	}

	return calculateEMA(prices, period)
}

// calculateRSI logic
func (ta *TrendAnalyzer) calculateRSI(symbol string, interval string, period int) float64 {
	validSymbol := NormalizeSymbol(symbol)

	klines, err := ta.client.NewKlinesService().
		Symbol(validSymbol).
		Interval(interval).
		Limit(period * 2). // Need enough data
		Do(context.Background())

	if err != nil || len(klines) < period+1 {
		return 50.0
	}

	var gains, losses float64

	// First Average
	for i := 1; i <= period; i++ {
		curr, _ := strconv.ParseFloat(klines[i].Close, 64)
		prev, _ := strconv.ParseFloat(klines[i-1].Close, 64)
		change := curr - prev
		if change > 0 {
			gains += change
		} else {
			losses -= change
		}
	}

	avgGain := gains / float64(period)
	avgLoss := losses / float64(period)

	rs := 0.0
	if avgLoss != 0 {
		rs = avgGain / avgLoss
	} else {
		return 100.0 // All gains
	}

	return 100 - (100 / (1 + rs))
}

// CalculateATR computes the Average True Range (14)
func (ta *TrendAnalyzer) CalculateATR(symbol string, interval string) float64 {
	validSymbol := NormalizeSymbol(symbol)

	klines, err := ta.client.NewKlinesService().
		Symbol(validSymbol).
		Interval(interval).
		Limit(15).
		Do(context.Background())

	if err != nil || len(klines) < 15 {
		return 0.0
	}

	trSum := 0.0
	for i := 1; i < len(klines); i++ {
		high, _ := strconv.ParseFloat(klines[i].High, 64)
		low, _ := strconv.ParseFloat(klines[i].Low, 64)
		prevClose, _ := strconv.ParseFloat(klines[i-1].Close, 64)

		tr1 := high - low
		tr2 := math.Abs(high - prevClose)
		tr3 := math.Abs(low - prevClose)

		// TRUE RANGE is Max(tr1, tr2, tr3)
		tr := math.Max(tr1, math.Max(tr2, tr3))
		trSum += tr
	}

	return trSum / 14.0
}

// IsHighVolatility checks if current volatility is dangerous (> 1.5x Average)
func (ta *TrendAnalyzer) IsHighVolatility(symbol string, interval string) bool {
	validSymbol := NormalizeSymbol(symbol)
	atr := ta.CalculateATR(validSymbol, interval)

	// Get Current Price
	prices, _ := ta.client.NewListPricesService().Symbol(validSymbol).Do(context.Background())
	if len(prices) == 0 {
		return false
	}
	price, _ := strconv.ParseFloat(prices[0].Price, 64)

	// Threshold: If ATR is > 0.5% of Price, it's very volatile for 15m
	threshold := price * 0.005

	return atr > threshold
}

// CalculateVelocity measures price change speed (Points per Minute)
func (ta *TrendAnalyzer) CalculateVelocity(symbol string) float64 {
	validSymbol := NormalizeSymbol(symbol)

	// Get last 5 1m candles
	klines, err := ta.client.NewKlinesService().
		Symbol(validSymbol).
		Interval("1m").
		Limit(5).
		Do(context.Background())

	if err != nil || len(klines) < 2 {
		return 0.0
	}

	// Calculate slope: (PriceNow - Price5mAgo) / 5
	startPrice, _ := strconv.ParseFloat(klines[0].Close, 64)
	endPrice, _ := strconv.ParseFloat(klines[len(klines)-1].Close, 64)

	diff := endPrice - startPrice
	minutes := float64(len(klines))

	velocity := diff / minutes // Points per minute
	return velocity
}

// GetScalpTrend analyzes 1m, 5m, and 15m trends for high-frequency trading
func (ta *TrendAnalyzer) GetScalpTrend(symbol string) TrendResult {
	res := TrendResult{
		Trend1H:  TrendNeutral,
		Trend15M: TrendNeutral,
		Trend5M:  TrendNeutral,
		Trend1M:  TrendNeutral,
		RSI:      50.0,
	}

	res.Trend15M = ta.analyzeTimeframe(symbol, "15m")
	res.Trend5M = ta.analyzeTimeframe(symbol, "5m")
	res.Trend1M = ta.analyzeTimeframe(symbol, "1m")

	return res
}

// Helper: Calculate EMA (Simple approximation for last value)
func calculateEMA(prices []float64, period int) float64 {
	if len(prices) < period {
		return 0
	}

	k := 2.0 / float64(period+1)

	// Initialize with SMA of first 'period' elements
	sum := 0.0
	for i := 0; i < period; i++ {
		sum += prices[i]
	}
	ema := sum / float64(period)

	// Iterate through rest
	for i := period; i < len(prices); i++ {
		ema = (prices[i] * k) + (ema * (1 - k))
	}

	return ema
}
