package main

import (
	"sync"
	"time"
)

// LiquidationMonitor tracks aggregated liquidations
type LiquidationMonitor struct {
	mu           sync.RWMutex
	liquidations map[string][]LiquidationEvent // Symbol -> Events
	window       time.Duration
}

// LiquidationEvent represents a single rekt event
type LiquidationEvent struct {
	Symbol    string
	Side      string  // "BUY" (Shorts Liquidated) or "SELL" (Longs Liquidated)
	Amount    float64 // USD Value
	Timestamp time.Time
}

// NewLiquidationMonitor creates the monitor
func NewLiquidationMonitor(window time.Duration) *LiquidationMonitor {
	return &LiquidationMonitor{
		liquidations: make(map[string][]LiquidationEvent),
		window:       window,
	}
}

// AddLiquidation records a new event
func (lm *LiquidationMonitor) AddLiquidation(symbol string, side string, amount float64) {
	lm.mu.Lock()
	defer lm.mu.Unlock()

	lm.liquidations[symbol] = append(lm.liquidations[symbol], LiquidationEvent{
		Symbol:    symbol,
		Side:      side,
		Amount:    amount,
		Timestamp: time.Now(),
	})

	// Cleanup old events lazily
	lm.cleanup(symbol)
}

// GetLiquidationVolume returns total volume for a side in the window
// Side "BUY" = Short Liquidations (Bullish Fuel)
// Side "SELL" = Long Liquidations (Bearish Fuel)
func (lm *LiquidationMonitor) GetLiquidationVolume(symbol string, side string) float64 {
	lm.mu.RLock()
	defer lm.mu.RUnlock()

	total := 0.0
	cutoff := time.Now().Add(-lm.window)

	events, exists := lm.liquidations[symbol]
	if !exists {
		return 0.0
	}

	for _, ev := range events {
		if ev.Timestamp.After(cutoff) && ev.Side == side {
			total += ev.Amount
		}
	}
	return total
}

func (lm *LiquidationMonitor) cleanup(symbol string) {
	cutoff := time.Now().Add(-lm.window)
	events := lm.liquidations[symbol]

	valid := events[:0]
	for _, ev := range events {
		if ev.Timestamp.After(cutoff) {
			valid = append(valid, ev)
		}
	}
	lm.liquidations[symbol] = valid
}
