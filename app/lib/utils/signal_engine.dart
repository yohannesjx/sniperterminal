import 'package:flutter/material.dart';
import '../models/alert.dart';

/// Result object for signal analysis
class SignalResult {
  final int score;        // 0-100
  final String label;     // "Strong Buy", "Weak Sell", etc.
  final Color color;      // Visual indicator color
  final double velocity;  // 0-100 Speedometer

  const SignalResult({
    required this.score,
    required this.label,
    required this.color,
    required this.velocity,
  });
}

/// Signal Confidence Engine
/// Analyzes whale activity to generate actionable trading signals
class SignalEngine {
  // EMA Smoothing: Prevents volatile flickering
  static double _lastScore = 50.0; // Start neutral
  static double _lastVelocity = 0.0; // Start stopped

  /// Analyze recent alerts and return a confidence score
  static SignalResult analyze(List<Alert> alerts) {
    // Calculate raw score
    int rawScore = _calculateRawScore(alerts);

    // Apply EMA Smoothing (10% toward target, 90% previous)
    // This creates a "drift" effect instead of instant jumps
    double smoothScore = (rawScore * 0.1) + (_lastScore * 0.9);
    _lastScore = smoothScore;

    // Calculate Velocity
    double rawVelocity = _calculateVelocity(alerts);
    double smoothVelocity = (rawVelocity * 0.2) + (_lastVelocity * 0.8); // Smoother velocity
    _lastVelocity = smoothVelocity;

    // Round to integer for display
    int score = smoothScore.round().clamp(0, 100);

    // Generate label & color with sticky zones
    String label;
    Color color;

    if (score >= 75) {
      label = "STRONG BUY";
      color = const Color(0xFF00FF41); // Bright green
    } else if (score >= 60) {
      label = "BUY SIGNAL";
      color = Colors.greenAccent;
    } else if (score >= 55) {
      label = "WEAK BUY";
      color = Colors.lightGreenAccent;
    } else if (score >= 45) {
      label = "WAIT";
      color = Colors.grey;
    } else if (score >= 40) {
      label = "WEAK SELL";
      color = Colors.orangeAccent;
    } else if (score >= 25) {
      label = "SELL SIGNAL";
      color = Colors.redAccent;
    } else {
      label = "STRONG SELL";
      color = const Color(0xFFFF0000); // Bright red
    }

    return SignalResult(
      score: score,
      label: label,
      color: color,
      velocity: smoothVelocity,
    );
  }

  /// Calculate raw score (before smoothing)
  static int _calculateRawScore(List<Alert> alerts) {
    int score = 50; // Start neutral
    final now = DateTime.now().millisecondsSinceEpoch;

    // Filter alerts to relevant time windows
    final last10Mins = alerts.where((a) => (now - a.data.timestamp) < 10 * 60 * 1000).toList();
    final last5Mins = alerts.where((a) => (now - a.data.timestamp) < 5 * 60 * 1000).toList();

    // 1. WHALE DIRECTION (Net Money Flow)
    double buyFlow = 0;
    double sellFlow = 0;

    for (var alert in last10Mins) {
      if (alert.isWhale || alert.data.notional >= 500000) {
        if (alert.data.side.toLowerCase() == 'buy') {
          buyFlow += alert.data.notional;
        } else {
          sellFlow += alert.data.notional;
        }
      }
    }

    double netFlow = buyFlow - sellFlow;
    if (netFlow > 2000000) {
      score += 15; // Strong buying pressure
    } else if (netFlow < -2000000) {
      score -= 15; // Strong selling pressure
    }

    // 2. INSTITUTIONAL SUPPORT (Iceberg Orders)
    bool hasIcebergBuy = last10Mins.any((a) => 
      a.isIceberg && a.data.side.toLowerCase() == 'buy' && a.data.notional >= 1000000
    );
    
    if (hasIcebergBuy) {
      score += 10; // Hidden institutional accumulation
    }

    // 3. MANIPULATION PENALTY (Spoofs)
    bool hasRecentSpoof = last5Mins.any((a) => a.isSpoof);
    
    if (hasRecentSpoof) {
      score -= 25; // Market manipulation detected - unsafe
    }

    // 4. CLAMP (0-100)
    return score.clamp(0, 100);
  }

  /// Calculate Velocity (0-100) based on Price Change & Intensity
  static double _calculateVelocity(List<Alert> alerts) {
    if (alerts.isEmpty) return 0.0;

    final now = DateTime.now().millisecondsSinceEpoch;
    // Window: Last 2 minutes
    final window = alerts.where((a) => (now - a.data.timestamp) < 2 * 60 * 1000).toList();
    
    if (window.isEmpty) return 0.0;

    // 1. FREQUENCY VELOCITY (Trades per minute)
    // Baseline: 5 trades/min is "Walking" (30), 20 trades/min is "Running" (70)
    double tradesPerMin = window.length / 2.0;
    double freqScore = (tradesPerMin / 20.0) * 100;

    // 2. PRICE VELOCITY (Price change magnitude)
    double minPrice = double.infinity;
    double maxPrice = double.negativeInfinity;
    
    for (var a in window) {
      if (a.data.price < minPrice) minPrice = a.data.price;
      if (a.data.price > maxPrice) maxPrice = a.data.price;
    }
    
    // Calculate % moves
    // If range is > 0.5% in 2 mins, that's FAST.
    double avgPrice = (minPrice + maxPrice) / 2;
    double rangePct = (maxPrice - minPrice) / avgPrice;
    double priceScore = (rangePct / 0.005) * 100; // 0.005 = 0.5%

    // Weighted Average: 60% Intensity, 40% Price Action
    double velocity = (freqScore * 0.6) + (priceScore * 0.4);
    
    return velocity.clamp(0.0, 100.0);
  }
}
