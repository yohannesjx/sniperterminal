import '../models/alert.dart';

class TradeSignal {
  final String type; // "LONG" or "SHORT" or "WAIT"
  final double entry;
  final double stopLoss;
  final double takeProfit;
  final double riskReward;
  final String reasoning;

  TradeSignal({
    required this.type,
    required this.entry,
    required this.stopLoss,
    required this.takeProfit,
    required this.riskReward,
    required this.reasoning,
  });
}

class TradeSignalEngine {
  // Hysteresis State
  static TradeSignal? _lastConfirmedSignal;
  static int _lastSignalTimestamp = 0;

  static TradeSignal analyze(double currentPrice, List<Alert> alerts) {
    TradeSignal rawSignal = _calculateRaw(currentPrice, alerts);

    // HYSTERESIS LOGIC (Anti-Chopping)
    final now = DateTime.now().millisecondsSinceEpoch;

    // If we have a locked signal (LONG/SHORT)
    if (_lastConfirmedSignal != null && _lastConfirmedSignal!.type != 'WAIT') {
      final timeDiff = now - _lastSignalTimestamp;
      final isLocked = timeDiff < 300000; // 5 Minute Cooldown

      if (isLocked) {
        // 1. Check for Crash/Pump Bypass (> 1% move)
        final priceMove = (currentPrice - _lastConfirmedSignal!.entry).abs() / _lastConfirmedSignal!.entry;
        if (priceMove > 0.01) {
           _lastConfirmedSignal = rawSignal;
           _lastSignalTimestamp = now;
           return rawSignal;
        }

        // 2. If raw signal matches, allow update (refresh levels)
        if (rawSignal.type == _lastConfirmedSignal!.type) {
           _lastConfirmedSignal = rawSignal;
           return rawSignal;
        }

        // 3. ENFORCE LOCK: Return previous signal even if raw is WAIT/Opposite
        return TradeSignal(
          type: _lastConfirmedSignal!.type,
          entry: _lastConfirmedSignal!.entry,
          stopLoss: _lastConfirmedSignal!.stopLoss,
          takeProfit: _lastConfirmedSignal!.takeProfit,
          riskReward: _lastConfirmedSignal!.riskReward,
          reasoning: "Signal Locked 🔒 (${((300000 - timeDiff) / 1000).toStringAsFixed(0)}s). Waiting for breakout.",
        );
      }
    }

    // New Signal (or expired lock)
    if (rawSignal.type != 'WAIT') {
      // If switching from WAIT/Opposite to NEW Active Signal, start timer
      if (_lastConfirmedSignal == null || _lastConfirmedSignal!.type != rawSignal.type) {
         _lastSignalTimestamp = now;
      }
      _lastConfirmedSignal = rawSignal;
    } else {
      _lastConfirmedSignal = null; // Reset on WAIT (after lock expires)
    }

    return rawSignal;
  }

  static TradeSignal _calculateRaw(double currentPrice, List<Alert> alerts) {
    if (alerts.isEmpty) {
      return _wait("No active alerts to analyze.");
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    // Filter active Support/Resistance (Whales/Icebergs < 10 mins old)
    final activeLevels = alerts.where((a) {
      final isTypeMatch = a.type == 'WHALE' || a.type == 'ICEBERG' || a.type == 'WALL';
      return isTypeMatch; 
    }).toList();

    Alert? nearestSupport;
    Alert? nearestResistance;
    double minDistSupport = double.infinity;
    double minDistResistance = double.infinity;

    for (var alert in activeLevels) {
      final price = alert.data.price;

      if (price < currentPrice) {
        // Support
        if (alert.data.side == 'buy' || alert.type == 'ICEBERG') {
           final dist = (currentPrice - price).abs();
           if (dist < minDistSupport) {
             minDistSupport = dist;
             nearestSupport = alert;
           }
        }
      } else {
        // Resistance
        if (alert.data.side == 'sell' || alert.type == 'ICEBERG') {
           final dist = (price - currentPrice).abs();
           if (dist < minDistResistance) {
             minDistResistance = dist;
             nearestResistance = alert;
           }
        }
      }
    }

    if (nearestSupport == null && nearestResistance == null) {
      return _wait("No key levels nearby.");
    }
    
    // Safety check: Ensure levels are reasonably close (within 2%)
    final range = currentPrice * 0.02; 
    bool validSupport = nearestSupport != null && minDistSupport < range;
    bool validResistance = nearestResistance != null && minDistResistance < range;

    if (!validSupport && !validResistance) {
        return _wait("Levels too far away for Sniper entry.");
    }

    // NEUTRAL ZONE LOGIC (20/20 Rule)
    if (nearestSupport != null && nearestResistance != null) {
      final supportPrice = nearestSupport.data.price;
      final resistancePrice = nearestResistance.data.price;
      
      final totalRange = resistancePrice - supportPrice;
      if (totalRange > 0) {
        final position = (currentPrice - supportPrice) / totalRange;
        
        // NEUTRAL ZONE: 20% to 80%
        if (position > 0.20 && position < 0.80) {
          return _wait("Price in middle of range (${(position * 100).toStringAsFixed(0)}%). Wait for dip or rally.");
        }
      }
    }

    if (validSupport && (!validResistance || minDistSupport < minDistResistance)) {
      // LONG SETUP
      final sl = nearestSupport!.data.price * 0.998; // 0.2% below support
      
      final tp = validResistance 
          ? nearestResistance!.data.price * 0.998 
          : currentPrice * 1.015;
      
      final risk = currentPrice - sl;
      final reward = tp - currentPrice;
      
      return TradeSignal(
        type: "LONG",
        entry: currentPrice,
        stopLoss: sl,
        takeProfit: tp,
        riskReward: risk == 0 ? 0 : reward / risk,
        reasoning: "Bounce off ${nearestSupport!.type} @ \$${nearestSupport.data.price.toStringAsFixed(0)}",
      );
    } else if (validResistance) {
      // SHORT SETUP
      final sl = nearestResistance!.data.price * 1.002; // 0.2% above resistance
      
      final tp = validSupport 
          ? nearestSupport!.data.price * 1.002 
          : currentPrice * 0.985;

      final risk = sl - currentPrice;
      final reward = currentPrice - tp;

      return TradeSignal(
        type: "SHORT",
        entry: currentPrice,
        stopLoss: sl,
        takeProfit: tp,
        riskReward: risk == 0 ? 0 : reward / risk,
        reasoning: "Rejection at ${nearestResistance!.type} @ \$${nearestResistance.data.price.toStringAsFixed(0)}",
      );
    }

    return _wait("Market structure unclear.");
  }

  static TradeSignal _wait(String reason) {
    return TradeSignal(
      type: "WAIT",
      entry: 0,
      stopLoss: 0,
      takeProfit: 0,
      riskReward: 0,
      reasoning: reason,
    );
  }
}
