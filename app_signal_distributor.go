package main

import (
	"fmt"
	"log"
	"sync"
	"time"
)

// ActiveSignal tracks a signal that is currently live on the app
type ActiveSignal struct {
	Symbol      string
	Side        string
	PublishTime time.Time
	LastConfirm time.Time
}

// AppSignalDistributor handles the "Public Feed" logic
type AppSignalDistributor struct {
	mu            sync.Mutex
	candidateMap  map[string]*CandidateSignal // Pending signals
	activeMap     map[string]*ActiveSignal    // 🆕 Live Signals (The "SignalLock")
	lastPushTime  map[string]time.Time
	trendAnalyzer *TrendAnalyzer
	pushService   *NotificationService
	aggregator    *SignalAggregator

	PersistenceSecs int
	CooldownMins    int
}

// CandidateSignal tracks a signal's stability over time
type CandidateSignal struct {
	FirstSeen   time.Time
	LastUpdate  time.Time
	Signal      Signal
	UpdateCount int
}

// PublicSignal is the sanitized payload for the App
type PublicSignal struct {
	Symbol     string
	Direction  string // "LONG" or "SHORT"
	EntryZone  string // "$65000 - $65100"
	Stars      int    // 1-5
	Volatility string // "NORMAL" or "HIGH"
	Timestamp  int64
	NextUpdate int64 // Timestamp for when lock expires
}

// NewAppSignalDistributor creates the service
func NewAppSignalDistributor(ta *TrendAnalyzer, ns *NotificationService) *AppSignalDistributor {
	dist := &AppSignalDistributor{
		candidateMap:    make(map[string]*CandidateSignal),
		activeMap:       make(map[string]*ActiveSignal),
		lastPushTime:    make(map[string]time.Time),
		trendAnalyzer:   ta,
		pushService:     ns,
		PersistenceSecs: 5,  // Fast persistence check
		CooldownMins:    15, // Cooldown
	}
	dist.aggregator = NewSignalAggregator(dist)
	return dist
}

// ProcessSignal is the entry point
func (d *AppSignalDistributor) ProcessSignal(sig Signal) {
	d.mu.Lock()
	defer d.mu.Unlock()

	// 1. TREND ANCHOR (15M EMA Filter)
	// Bind to 15M Trend: Bullish -> LONG only, Bearish -> SHORT only.
	if sig.Side == "LONG" && sig.Trend15M == "BEARISH 🔴" {
		return // Block Counter-Trend Longs
	}
	if sig.Side == "SHORT" && sig.Trend15M == "BULLISH 🟢" {
		return // Block Counter-Trend Shorts
	}

	// 3. SAFETY GUARDRAIL (EMA Extension Check)
	// Prevent chasing: If Price is > 0.1% away from 15m EMA 9, it's overextended.
	if d.trendAnalyzer != nil {
		ema9 := d.trendAnalyzer.GetEMA(sig.Symbol, "15m", 9)
		if ema9 > 0 {
			// Using absolute distance logic for simplicity as "Away"
			diff := sig.Entry - ema9
			if diff < 0 {
				diff = -diff
			}

			if (diff / ema9) > 0.001 {
				log.Printf("🛑 GUARDRAIL: %s Overextended (>0.1%% from EMA). Ignored.", sig.Symbol)
				return
			}
		}
	}

	// 4. SIGNAL LOCK (60s Rule)
	now := time.Now()

	// Check if we already have an active signal for this symbol
	if active, ok := d.activeMap[sig.Symbol]; ok {
		// If direction matches, update confirmation time (keep it alive)
		if active.Side == sig.Side {
			active.LastConfirm = now
		}

		// If < 60s old, we CANNOT replace it yet.
		if time.Since(active.PublishTime).Seconds() < 60 {
			// If direction opposes, we must ignore the new one (Trend Lock + Stability)
			if active.Side != sig.Side {
				return
			}
		} else {
			// Older than 60s.
		}
	}

	// 5. CANDIDATE MANAGEMENT (Persistence)
	candidate, exists := d.candidateMap[sig.Symbol]
	if !exists {
		d.candidateMap[sig.Symbol] = &CandidateSignal{
			FirstSeen:   now,
			LastUpdate:  now,
			Signal:      sig,
			UpdateCount: 1,
		}
		return
	}

	candidate.LastUpdate = now
	candidate.UpdateCount++
	candidate.Signal = sig

	// Check Persistence
	if time.Since(candidate.FirstSeen).Seconds() >= float64(d.PersistenceSecs) {
		// Check Cooldown (unless it's an update to Active?)
		// Logic: If Active exists and < 60s, we don't push *new* push.
		// Actually, let's treat "Distribute" as "Push to Feed".

		if active, isActive := d.activeMap[sig.Symbol]; isActive {
			if active.Side != sig.Side && time.Since(active.PublishTime).Seconds() < 60 {
				return // Still locked
			}
		} else {
			// No Active. Check Cooldown.
			if lastPush, ok := d.lastPushTime[sig.Symbol]; ok {
				if time.Since(lastPush) < time.Duration(d.CooldownMins)*time.Minute {
					return
				}
			}
		}

		d.distribute(candidate.Signal)

		// Mark Active
		d.activeMap[sig.Symbol] = &ActiveSignal{
			Symbol:      sig.Symbol,
			Side:        sig.Side,
			PublishTime: now,
			LastConfirm: now,
		}
		d.lastPushTime[sig.Symbol] = now
		delete(d.candidateMap, sig.Symbol)
	}
}

// distribute builds the payload
func (d *AppSignalDistributor) distribute(sig Signal) {
	stars := 1
	// Rating Logic
	if (sig.Side == "LONG" && sig.Trend15M == "BULLISH 🟢") || (sig.Side == "SHORT" && sig.Trend15M == "BEARISH 🔴") {
		stars += 2
	}
	if (sig.Side == "LONG" && sig.Trend1H == "BULLISH 🟢") || (sig.Side == "SHORT" && sig.Trend1H == "BEARISH 🔴") {
		stars += 1
	}
	if sig.Synergy {
		stars += 1
	}

	if stars < 3 {
		return
	}

	// Entry Zone (0.05% Range)
	minEntry := sig.Entry
	maxEntry := sig.Entry * 1.0005
	if sig.Side == "SHORT" {
		minEntry = sig.Entry * 0.9995
		maxEntry = sig.Entry
	}
	zone := fmt.Sprintf("$%.2f - $%.2f", minEntry, maxEntry)

	// Next Update Timestamp (Publish Time + 60s)
	nextUpdate := time.Now().Add(60 * time.Second).Unix()

	pubSig := PublicSignal{
		Symbol:     sig.Symbol,
		Direction:  sig.Side,
		EntryZone:  zone,
		Stars:      stars,
		Volatility: "NORMAL", // Simplified
		Timestamp:  time.Now().Unix(),
		NextUpdate: nextUpdate,
	}

	if d.aggregator != nil {
		d.aggregator.Ingest(pubSig)
	}

	// Log
	log.Printf("📱 APP SIGNAL: %s %s | Stars: %d | Zone: %s", pubSig.Direction, pubSig.Symbol, stars, zone)
}
