package main

import (
	"log"
	"sync"
)

// SignalFilter validates potential trade signals against strict institutional criteria
type SignalFilter struct {
	mu            sync.Mutex
	clusterBuffer map[string][]Trade // Symbol -> Recent Whale Trades
	lastTradeTime map[string]int64   // Symbol -> Timestamp of last cleared trade

	// Configuration
	ClusterTimeWindow  int64   // e.g. 60000ms (1 minute)
	ClusterPriceRange  float64 // e.g. 0.0015 (0.15%)
	RequiredClusterCnt int     // e.g. 3
	MinVolumeRatio     float64 // e.g. 1.5 (Buyers must outweigh Sellers 1.5x)
}

func NewSignalFilter() *SignalFilter {
	return &SignalFilter{
		clusterBuffer:      make(map[string][]Trade),
		lastTradeTime:      make(map[string]int64),
		ClusterTimeWindow:  60000,
		ClusterPriceRange:  0.0015,
		RequiredClusterCnt: 3,
		MinVolumeRatio:     1.5,
	}
}

// Validate checks if a trade signal is part of a valid Institutional Cluster
// Returns: isValid, activeRatio, clusterScore
func (sf *SignalFilter) Validate(candidate Trade, buyVol, sellVol float64, isIceberg bool, liquidationVol float64) (bool, float64, float64) {
	sf.mu.Lock()
	defer sf.mu.Unlock()

	symbol := candidate.Symbol
	now := candidate.Timestamp

	// Calculate Ratio early for reporting
	activeRatio := 0.0
	if candidate.Side == "buy" {
		if sellVol > 0 {
			activeRatio = buyVol / sellVol
		} else {
			activeRatio = 999.0 // Infinite
		}
	} else {
		if buyVol > 0 {
			activeRatio = sellVol / buyVol
		} else {
			activeRatio = 999.0 // Infinite
		}
	}

	// 0. PRIORITY OVERRIDE (Iceberg > $500k OR Iceberg + Liq > 10k)
	// User req: Iceberg > $500k bypass
	if (isIceberg && candidate.Notional > 500000) || (liquidationVol > 10000 && isIceberg) {
		log.Printf("🚀 PRIORITY SIGNAL: %s | Iceberg/Liq Bypass ($%.0f). Skipping filters.", symbol, candidate.Notional)
		return true, activeRatio, 10.0 // Score 10 for priority
	}

	// 1. VOLUME DELTA CHECK (The "Noise Killer")
	if candidate.Side == "buy" {
		if activeRatio < sf.MinVolumeRatio {
			log.Printf("🔇 SIGNAL FILTER: %s Long Rejected. Vol Ratio %.2f < %.2f (Buyers weak)", symbol, activeRatio, sf.MinVolumeRatio)
			return false, activeRatio, 0.0
		}
	} else {
		if activeRatio < sf.MinVolumeRatio {
			log.Printf("🔇 SIGNAL FILTER: %s Short Rejected. Vol Ratio %.2f < %.2f (Sellers weak)", symbol, activeRatio, sf.MinVolumeRatio)
			return false, activeRatio, 0.0
		}
	}

	// 2. CLUSTER MANAGEMENT
	// Remove old trades from buffer
	validTrades := []Trade{}
	for _, t := range sf.clusterBuffer[symbol] {
		if now-t.Timestamp < sf.ClusterTimeWindow {
			validTrades = append(validTrades, t)
		}
	}

	// Add candidate temporarily to check clustering
	candidate.IsIceberg = isIceberg // CRITICAL: Save this state for future cluster checks
	potentialCluster := append(validTrades, candidate)

	// Save back cleaned buffer + new candidate
	sf.clusterBuffer[symbol] = potentialCluster

	// 3. CLUSTER CHECK (WEIGHTED)
	// Do we have >= 3 distinct massive orders within price range?
	// Icebergs count as 2 Points.
	// Liquidations (>10k) count as 1.5 Points.
	// Standard Whales count as 1 Point.

	totalScore := 0.0

	// Check Candidate Weight
	candidateScore := 1.0
	if isIceberg {
		candidateScore = 2.0
	}
	if liquidationVol > 5000 {
		candidateScore += 1.5
	}

	for _, t := range potentialCluster {
		priceDiff := (t.Price - candidate.Price) / candidate.Price
		if priceDiff < 0 {
			priceDiff = -priceDiff
		}

		if priceDiff <= sf.ClusterPriceRange {
			// STRICT FILTER: Only count massive whales (> $1,000,000) for the count
			// Icebergs (> 500k) also count as they are hidden massive movement
			if t.Notional > 1000000.0 || (t.IsIceberg && t.Notional > 500000) {
				totalScore += 1.0
			} else {
				// Smaller whales contribute less
				totalScore += 0.1
			}
		}
	}

	// Add candidate bonus to total
	// Note: The loop above counts the candidate as 1.0. We add the extra weight here.
	totalScore += (candidateScore - 1.0)

	// Threshold is 3.0
	if totalScore >= float64(sf.RequiredClusterCnt) {
		log.Printf("🏛️ INSTITUTIONAL CLUSTER CONFIRMED: %s | Score: %.1f | Ratio: %.2f", symbol, totalScore, activeRatio)

		// Clear cluster to prevent double-firing on the same wave
		sf.clusterBuffer[symbol] = []Trade{}
		return true, activeRatio, totalScore
	}

	log.Printf("⏳ BUFFERING SIGNAL: %s Clustered Score: %.1f/%d", symbol, totalScore, sf.RequiredClusterCnt)
	return false, activeRatio, totalScore
}
