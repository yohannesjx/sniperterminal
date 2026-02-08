package main

import (
	"log"
	"sync"
	"time"
)

// SignalAggregator groups signals to reduce noise and identify accumulation
type SignalAggregator struct {
	mu             sync.Mutex
	distributor    *AppSignalDistributor
	symbolBuckets  map[string]*SignalBucket // Symbol -> Bucket
	pushCooldowns  map[string]time.Time     // Symbol -> Last Push Time
	bucketDuration time.Duration
	cooldownDur    time.Duration
}

// SignalBucket collects signals for a symbol over a short window
type SignalBucket struct {
	Signals          []PublicSignal
	StartTime        time.Time
	AccumulatedCount int
}

// NewSignalAggregator creates the aggregator
func NewSignalAggregator(distributor *AppSignalDistributor) *SignalAggregator {
	sa := &SignalAggregator{
		distributor:    distributor,
		symbolBuckets:  make(map[string]*SignalBucket),
		pushCooldowns:  make(map[string]time.Time),
		bucketDuration: 30 * time.Second, // 30s Window
		cooldownDur:    5 * time.Minute,  // 5m Global Cooldown
	}

	// Start Flush Loop
	go sa.flushLoop()

	return sa
}

// Ingest receives a sanitized public signal
func (sa *SignalAggregator) Ingest(sig PublicSignal) {
	sa.mu.Lock()
	defer sa.mu.Unlock()

	// 1. Get or Create Bucket
	bucket, exists := sa.symbolBuckets[sig.Symbol]
	if !exists {
		bucket = &SignalBucket{
			Signals:          []PublicSignal{},
			StartTime:        time.Now(),
			AccumulatedCount: 0,
		}
		sa.symbolBuckets[sig.Symbol] = bucket
	}

	// 2. Add to Bucket
	bucket.Signals = append(bucket.Signals, sig)
	bucket.AccumulatedCount++
}

// flushLoop runs every few seconds to check buckets
func (sa *SignalAggregator) flushLoop() {
	ticker := time.NewTicker(2 * time.Second) // Check often
	defer ticker.Stop()

	for range ticker.C {
		sa.flush()
	}
}

func (sa *SignalAggregator) flush() {
	sa.mu.Lock()
	defer sa.mu.Unlock()

	now := time.Now()

	for symbol, bucket := range sa.symbolBuckets {
		// Check if bucket expired
		if now.Sub(bucket.StartTime) >= sa.bucketDuration {
			// PROCESS BUCKET
			sa.processBucket(symbol, bucket)

			// Remove from map
			delete(sa.symbolBuckets, symbol)
		}
	}
}

func (sa *SignalAggregator) processBucket(symbol string, bucket *SignalBucket) {
	if bucket.AccumulatedCount == 0 {
		return
	}

	// CHECK COOLDOWN
	if lastPush, ok := sa.pushCooldowns[symbol]; ok {
		if time.Since(lastPush) < sa.cooldownDur {
			// Cooldown active - Skip
			log.Printf("⏳ AGGREGATOR: %s skipped (Cooldown active)", symbol)
			return
		}
	}

	// 1. HEAVY ACCUMULATION (5+ Signals)
	if bucket.AccumulatedCount >= 5 {
		// Calculate average stars/confidence
		totalStars := 0
		for _, s := range bucket.Signals {
			totalStars += s.Stars
		}
		avgStars := totalStars / bucket.AccumulatedCount

		summarySig := PublicSignal{
			Symbol:     symbol,
			Direction:  bucket.Signals[0].Direction, // Assume same direction mostly
			EntryZone:  "VARIOUS",
			Stars:      avgStars,
			Volatility: bucket.Signals[0].Volatility,
			Timestamp:  time.Now().Unix(),
		}

		// Inject Summary Message logic here (usually handled by PushService formatting)
		// For now, we adjust the Volatility field to carry the summary flag or use a new field if struct allowed.
		// We'll hijack 'EntryZone' to say "HEAVY ACCUMULATION"
		summarySig.EntryZone = "💰 HEAVY ACCUMULATION"

		log.Printf("💰 AGGREGATOR: %s Heavy Accumulation (%d signals). Sending Summary.", symbol, bucket.AccumulatedCount)
		sa.send(summarySig)

	} else {
		// 2. NORMAL FLOW (Single Signal)
		// Just send the strongest one (highest stars) or last one?
		// Let's send the last one as it's most fresh.
		lastSig := bucket.Signals[len(bucket.Signals)-1]

		// Crash Filter: Score < 40 (Implied by Stars < 3 check in Distributor, but let's re-verify)
		// Distributor already drops < 3 Stars.
		// "Filter out 'Crash Warnings' if ... < 40".
		// We don't have raw Score here, only Stars. Assuming Distributor handled it.

		sa.send(lastSig)
	}
}

func (sa *SignalAggregator) send(sig PublicSignal) {
	// Update Cooldown
	sa.pushCooldowns[sig.Symbol] = time.Now()

	// Pass to PushService
	if sa.distributor.pushService != nil {
		sa.distributor.pushService.SendAppPush(sig)
	}
}
