import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alert.dart';
import '../providers/alert_provider.dart';
import '../utils/signal_engine.dart';
import 'market_narrator.dart';
import 'confidence_gauge.dart';
import 'iceberg_depth_bar.dart';
import 'radar_blip.dart';
import 'whale_depth_list.dart';

// Model to track fading blips locally
class _FadingBlipModel {
  final String id;
  final Alert alert;
  final AnimationController controller;
  final Animation<double> opacity;
  final AnimationController pulseController;
  final Animation<double> pulseScale;
  final double angle; // Polar angle in radians
  final double distance; // Polar distance (0.0 to 1.0)

  _FadingBlipModel({
    required this.id,
    required this.alert,
    required this.controller,
    required this.opacity,
    required this.pulseController,
    required this.pulseScale,
    required this.angle,
    required this.distance,
  });
}

class RadarView extends ConsumerStatefulWidget {
  const RadarView({super.key});

  @override
  ConsumerState<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends ConsumerState<RadarView>
    with TickerProviderStateMixin {
  late AnimationController _scannerController;
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  
  // Per-coin blip storage - maintains state when switching coins
  final Map<String, List<_FadingBlipModel>> _coinBlips = {
    'BTC': [],
    'ETH': [],
    'SOL': [],
  };
  String _lastCoin = 'BTC'; // Track last selected coin

  Timer? _queueTimer;
  final List<Alert> _alertQueue = [];

  @override
  void initState() {
    super.initState();
    // Continuous scanner sweep
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    
    // Start Queue Processor (500ms throttle)
    _queueTimer = Timer.periodic(const Duration(milliseconds: 500), _processQueue);
  }

  void _processQueue(Timer timer) {
    if (_alertQueue.isEmpty) return;
    
    // Throttling Logic:
    // If queue > 20, sort by Notional and take Top 5
    List<Alert> batch = List.from(_alertQueue);
    _alertQueue.clear();
    
    if (batch.length > 20) {
      print('⚠️ Throttling Radar: ${batch.length} blips queued. Showing Top 5.');
      batch.sort((a, b) => b.data.notional.compareTo(a.data.notional));
      batch = batch.take(5).toList();
    }
    
    for (var alert in batch) {
      _addBlip(alert);
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _sheetController.dispose();
    _queueTimer?.cancel();
    _clearAllBlips();
    super.dispose();
  }
  
  // Helper to clear all blips across all coins and dispose controllers
  void _clearAllBlips() {
    _coinBlips.forEach((coin, blips) {
      for (var blip in blips) {
        blip.controller.dispose();
        blip.pulseController.dispose();
      }
    });
    _coinBlips.clear();
  }

  void _addBlip(Alert alert) {
    // Only show WHALE, ICEBERG, SPOOF, LIQUIDATION, WALL, BREAKOUT
    // Basically everything except maybe generic trades
    // if (alert.type != 'WHALE' && alert.type != 'ICEBERG') return;

    // 1. Calculate Position (Random Spread Across Radar)
    final now = DateTime.now().millisecondsSinceEpoch;
    final alertTime = alert.data.timestamp;
    
    // Random angle using timestamp hash for consistent but varied distribution
    final angleHash = (alertTime * 2654435761) % 360; // Knuth's multiplicative hash
    final angleInDegrees = angleHash.toDouble();
    final angleInRadians = angleInDegrees * (math.pi / 180);
    
    // Random distance from center (0.2 to 0.9 to keep blips visible and spread out)
    final distanceHash = ((alertTime * 1103515245 + 12345) % 100) / 100.0; // Linear congruential
    final distancePercent = 0.2 + (distanceHash * 0.7); // Range: 0.2 to 0.9
    
    // print('🎯 Blip positioning: ${alert.type} ${alert.symbol}, angle: ${angleInDegrees.toStringAsFixed(0)}°, distance: ${distancePercent.toStringAsFixed(2)}');

    // 2. Variable Lifespan Based on Alert Type
    Duration lifespan;
    if (alert.type == 'SPOOF') {
      lifespan = const Duration(seconds: 120); // 2 minutes for ghost signals
    } else {
      lifespan = const Duration(seconds: 900); // 15 minutes for real trades/whales
    }

    // 3. Setup Animation Controller with variable lifespan
    final controller = AnimationController(
      vsync: this,
      duration: lifespan,
    );

    // 4. Opacity Tween (1.0 -> 0.0 over lifespan)
    final opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: controller, curve: Curves.linear),
    );

    // 5. NEW: Pulse Animation (plays once on entry)
    final pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // 1 second pulse
    );

    final pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.5, end: 1.2).chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(pulseController);

    final blip = _FadingBlipModel(
      id: '${alert.symbol}_$alertTime',
      alert: alert,
      controller: controller,
      opacity: opacity,
      pulseController: pulseController,
      pulseScale: pulseScale,
      angle: angleInRadians,
      distance: distancePercent,
    );

    // Get coin symbol and initialize bucket if needed
    String coin = alert.symbol.toUpperCase();
    if (!_coinBlips.containsKey(coin)) {
      _coinBlips[coin] = [];
    }

    if (mounted) {
      setState(() {
        _coinBlips[coin]!.add(blip);
        // print('🎯 RadarView: Added blip for ${alert.type} ${alert.symbol}. Total blips for $coin: ${_coinBlips[coin]!.length}');
      });
    }

    // Start fade animation
    controller.forward().then((_) {
      // Remove after animation completes
      if (mounted) {
        String coin = alert.symbol.toUpperCase();
        setState(() {
          _coinBlips[coin]?.remove(blip);
        });
        blip.controller.dispose();
        blip.pulseController.dispose();
      }
    });

    // Start pulse animation (plays once)
    pulseController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final painThreshold = ref.watch(painThresholdProvider);
    final selectedCoin = ref.watch(selectedCoinProvider);
    final alertsMap = ref.watch(recentAlertsProvider);
    final recentAlerts = alertsMap[selectedCoin] ?? [];
    
    // Get blips for current coin
    final currentBlips = _coinBlips[selectedCoin] ?? [];
    
    // Listen to recent alerts map and add new blips for current coin
    ref.listen<Map<String, List<Alert>>>(recentAlertsProvider, (previous, next) {
      // Get current coin inside listener to ensure it's up-to-date
      final currentCoin = ref.read(selectedCoinProvider);
      final prevAlerts = previous?[currentCoin] ?? [];
      final nextAlerts = next[currentCoin] ?? [];
      if (nextAlerts.isEmpty) return;
      
      // Find new alerts that weren't in the previous list
      final previousIds = prevAlerts.map((a) => '${a.type}_${a.symbol}_${a.data.timestamp}').toSet();
      for (var alert in nextAlerts) {
        final alertId = '${alert.type}_${alert.symbol}_${alert.data.timestamp}';
        if (!previousIds.contains(alertId)) {
          // Check Pain Threshold
          bool shouldShow = alert.type == 'SPOOF' || 
                            alert.type == 'WALL' || 
                            alert.type == 'LIQUIDATION' ||
                            alert.type == 'ICEBERG' ||
                            alert.data.notional >= painThreshold;

          if (shouldShow) {
            // INSTEAD OF ADDING DIRECTLY, QUEUE IT
            _alertQueue.add(alert);
          }
        }
      }
    });
    
    // AUTO-POPUP LISTENER ... (Same as before)
    // ...

    // AUTO-POPUP LISTENER (Only for Mega Whales > $10M)
    ref.listen<Map<String, List<Alert>>>(recentAlertsProvider, (previous, next) {
      // Get current coin inside listener to ensure it's up-to-date
      final currentCoin = ref.read(selectedCoinProvider);
      final prevAlerts = previous?[currentCoin] ?? [];
      final nextAlerts = next[currentCoin] ?? [];
      
      if (nextAlerts.isEmpty) return;
      final newest = nextAlerts.first;
      
      // ONLY show popup if it's a new alert
      if (prevAlerts.isNotEmpty && newest == prevAlerts.first) return;

      // Map-First UX: Only auto-show for MEGA WHALES (>$10M)
      // All other alerts are interactive blips on the radar
      if (newest.data.notional >= 10000000.0) { 
          if (mounted) _showAlertDetails(newest);
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        final center = size / 2;
        final radius = size / 2;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Layer 1: Background Gradient & Grid
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF0D47A1).withOpacity(0.2), // Deep Blue Center
                      const Color(0xFF0a0e27).withOpacity(0.0), // Fade to transparent
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
              CustomPaint(
                size: Size(size, size),
                painter: RadarGridPainter(),
              ),

              // Layer 2: Scanner
              AnimatedBuilder(
                animation: _scannerController,
                builder: (context, child) {
                  return CustomPaint(
                    size: Size(size, size),
                    painter: ScannerPainter(
                      angle: _scannerController.value * 2 * math.pi,
                    ),
                  );
                },
              ),

              // Layer 3: Fading Blips (Ghost Trails) - Only show current coin's blips
              ...currentBlips.map((blip) {
                // Cartesian conversion
                final r = (radius - 40) * blip.distance; // -40 padding
                final x = center + r * math.cos(blip.angle) - 20; // -20 center icon
                final y = center + r * math.sin(blip.angle) - 20;

                return Positioned(
                  left: x,
                  top: y,
                  child: _buildAnimatedBlip(blip),
                );
              }),

              // Layer 4: Whale Depth List (Floating Card)
              const Positioned(
                top: 100, // Below header
                left: 20,
                child: WhaleDepthList(),
              ),
              
              // Layer 4: Time Labels (for temporal context)
              IgnorePointer(
                child: Stack(
                  children: [
                    // Center label: NOW
                    Positioned(
                      left: center - 15,
                      top: center - 10,
                      child: Text(
                        'NOW',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Middle ring label: -15m
                    Positioned(
                      left: center - 20,
                      top: center - radius * 0.5 - 10,
                      child: Text(
                        '-15m',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 7,
                        ),
                      ),
                    ),
                    // Outer ring label: -30m
                    Positioned(
                      left: center - 20,
                      top: center - radius + 50,
                      child: Text(
                        '-30m',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Layer 5: Iceberg Depth Bar (Left Edge HUD)
              IcebergDepthBar(
                activeAlerts: recentAlerts,
                currentPrice: ref.watch(currentPriceProvider),
              ),

              // Layer 6: Signal Confidence Gauge (Top Right)
              Positioned(
                top: 20,
                right: 20,
                child: Builder(
                  builder: (context) {
                    final signal = SignalEngine.analyze(recentAlerts);
                    // Update confidence score provider for trend flip detection
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ref.read(currentConfidenceScoreProvider.notifier).state = signal.score;
                    });
                    return ConfidenceGauge(signal: signal);
                  },
                ),
              ),

              // Layer 7: Market Narrator
              Positioned(
                bottom: 110, // Slightly higher to clear bottom sheet handle
                left: 20,
                right: 20,
                child: Center(
                  child: MarketNarrator(alerts: recentAlerts),
                ),
              ),
              
            ],
          ),
        );
      },
    );
  }

  // Helper: Calculate blip size based on trade value (T-Shirt Sizing)
  double _getBlipSize(double value) {
    if (value < 100000) return 6.0;        // Small: < $100K
    if (value < 500000) return 10.0;       // Medium: $100K - $500K
    if (value < 1000000) return 15.0;      // Large: $500K - $1M
    if (value < 5000000) return 22.0;      // Whale: $1M - $5M
    return 35.0;                            // Mega: > $5M
  }

  Widget _buildAnimatedBlip(_FadingBlipModel blip) {
    // Get current price for broken detection
    final currentPrice = ref.watch(currentPriceProvider);
    
    // 1. Determine if Iceberg is "Broken"
    bool isBroken = false;
    if (blip.alert.isIceberg) {
      if (blip.alert.data.side.toLowerCase() == 'buy') {
        // Buy wall (support): Broken if price drops below it
        isBroken = currentPrice < blip.alert.data.price;
      } else {
        // Sell wall (resistance): Broken if price rises above it
        isBroken = currentPrice > blip.alert.data.price;
      }
    }
    
    // 2. Determine if this should be a Double Ring (Historical Marker)
    bool isHighValue = blip.alert.data.notional >= 1000000; // L4/L5 (Whale/God Tier)
    bool isCompleted = (blip.alert.type.toUpperCase() == 'TRADE') || 
                       (blip.alert.isIceberg && isBroken);
    bool showDoubleRing = isHighValue && isCompleted;
    
    // 3. Enforce Color Coding
    Color getBlipColor() {
      if (blip.alert.isSpoof) return Colors.purpleAccent;
      if (blip.alert.isIceberg) return Colors.cyanAccent;
      if (blip.alert.isBreakout) return Colors.yellowAccent;
      if (blip.alert.isWall) return Colors.orangeAccent;
      if (blip.alert.isLiquidation) return Colors.red;
      return blip.alert.data.side.toLowerCase() == 'buy' ? Colors.greenAccent : Colors.redAccent;
    }

    Color color = getBlipColor();
    double size = _getBlipSize(blip.alert.data.notional);
    
    // 4. Build the blip based on state
    Widget blipDot;
    
    if (showDoubleRing) {
      // DOUBLE RING: Historical high-value marker (no glow, no pulse)
      blipDot = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(
            color: color.withOpacity(0.8),
            width: 1.5,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(4.0), // Gap between rings
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(
              color: color.withOpacity(0.5),
              width: 1.0,
            ),
          ),
        ),
      );
    } else if (isBroken) {
      // BROKEN: Single hollow ring (no glow)
      blipDot = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(
            color: color.withOpacity(0.6),
            width: 2.0,
          ),
        ),
      );
    } else {
      // ACTIVE: Solid dot with neon glow
      List<BoxShadow> glowEffect = [
        BoxShadow(
          color: color.withOpacity(0.8 * blip.opacity.value),
          blurRadius: size / 2,
          spreadRadius: size / 4,
        ),
      ];
      
      blipDot = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(blip.opacity.value),
          boxShadow: glowEffect,
        ),
      );
    }

    // 5. Add ripple animation ONLY for active Whale/Mega (not historical markers)
    Widget finalBlip = blipDot;
    if (!showDoubleRing && !isBroken && size >= 22.0) {
      finalBlip = Stack(
        alignment: Alignment.center,
        children: [
          // Ripple effect
          AnimatedBuilder(
            animation: blip.controller,
            builder: (context, child) {
              double rippleScale = 1.0 + (blip.controller.value * 1.5);
              return Container(
                width: size * rippleScale,
                height: size * rippleScale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withOpacity(0.3 * (1 - blip.controller.value)),
                    width: 2,
                  ),
                ),
              );
            },
          ),
          // Main dot
          blipDot,
        ],
      );
    }

    return AnimatedBuilder(
      animation: blip.controller,
      builder: (context, child) {
        // Apply ghosted opacity for broken icebergs
        double finalOpacity = isBroken ? 0.4 : blip.opacity.value;
        
        return Opacity(
          opacity: finalOpacity,
          child: GestureDetector(
            onTap: () => _showAlertDetails(blip.alert),
            child: AnimatedBuilder(
              animation: blip.pulseController,
              builder: (context, child) {
                // Only apply pulse to non-historical markers
                double pulseScale = showDoubleRing ? 1.0 : blip.pulseScale.value;
                
                return Transform.scale(
                  scale: pulseScale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      finalBlip,
                      
                      // Text Label - ONLY for Mega Whales (>$1M)
                      if (blip.alert.data.notional >= 1000000)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: color.withOpacity(0.5)),
                          ),
                          child: Text(
                            _formatValue(blip.alert.data.notional),
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlertCard(Alert alert) {
    final isWhale = alert.isWhale;
    final isIceberg = alert.isIceberg;
    final isSpoof = alert.isSpoof;
    final isLiquidation = alert.isLiquidation;

    Color cardColor;
    IconData icon;
    if (isWhale) {
      cardColor = alert.data.side.toLowerCase() == 'buy' 
          ? const Color(0xFF00FF41) 
          : const Color(0xFFFF1493);
      icon = Icons.waves;
    } else if (isIceberg) {
      cardColor = const Color(0xFF00D9FF);
      icon = Icons.ac_unit;
    } else if (isSpoof) {
      cardColor = const Color(0xFF9D4EDD); // Purple
      icon = Icons.visibility_off;
    } else if (isLiquidation) {
        cardColor = const Color(0xFFFF0000); // Red
        icon = Icons.water_drop;
    } else if (alert.isWall) {
        cardColor = const Color(0xFF00FF41); // Green
        icon = Icons.shield;
    } else if (alert.isBreakout) {
        cardColor = const Color(0xFFFFFF00); // Yellow
        icon = Icons.rocket_launch;
    } else {
      cardColor = Colors.white;
      icon = Icons.circle;
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0d1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cardColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: cardColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alert.type} • ${alert.symbol}',
                  style: TextStyle(
                    color: cardColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '\$${_formatNumber(alert.data.notional)} • ${alert.data.side.toUpperCase()}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 18),
            color: Colors.white.withOpacity(0.5),
            onPressed: () => _showAlertDetails(alert),
          ),
        ],
      ),
    );
  }

  void _showAlertDetails(Alert alert) {
    String strengthLabel = "🛡️ MEDIUM WALL";
    Color strengthColor = const Color(0xFF9D4EDD); // Purple default
    IconData icon = Icons.warning;
    double val = alert.data.notional;

    if (alert.isWhale) {
        icon = Icons.water; // Whale
        if (val >= 5000000) {
            strengthLabel = "🌋 GOD TIER WHALE";
            strengthColor = const Color(0xFFFF1493); // Pink
        } else {
            strengthLabel = "🐋 WHALE DETECTED";
            strengthColor = const Color(0xFF9D4EDD); // Purple
        }
    } else if (alert.isIceberg) {
        icon = Icons.ac_unit; // Iceberg
        strengthLabel = "🧊 ICEBERG ORDER";
        strengthColor = const Color(0xFF00D9FF); // Cyan
    } else if (alert.isSpoof) {
        icon = Icons.visibility_off; // Spoof
        strengthLabel = "👻 SPOOF DETECTED";
        strengthColor = const Color(0xFFFF4136); // Red
    } else if (alert.isLiquidation) {
        icon = Icons.water_drop; // Liquidation (Blood)
        strengthLabel = "💀 LIQUIDATION";
        strengthColor = const Color(0xFFFF0000); // Red
    } else if (alert.isWall) {
        icon = Icons.shield; // Wall
        strengthLabel = "🧱 STRONG WALL";
        strengthColor = const Color(0xFF00FF41); // Green
    } else if (alert.isBreakout) {
        icon = Icons.rocket_launch; 
        strengthLabel = "🚀 BREAKOUT";
        strengthColor = const Color(0xFFFFFF00); // Yellow
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1e3a),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: strengthColor,
            width: 2,
          ),
        ),
        title: Row(
          children: [
            Icon(icon, color: strengthColor, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.type,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strengthLabel,
                    style: TextStyle(
                      color: strengthColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Symbol', alert.symbol),
            _buildDetailRow('Exchange', alert.data.exchange),
            
            // Special handling for Spoof
            if (alert.isSpoof) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Value',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${_formatNumber(alert.data.notional)}',
                          style: const TextStyle(
                            color: Color(0xFFFF4136),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const Text(
                          '⚠️ CANCELLED ORDER',
                          style: TextStyle(
                            color: Color(0xFFFF4136),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              _buildDetailRow('Value', '\$${_formatNumber(alert.data.notional)}'),
            ],
            
            _buildDetailRow('Price', _formatPrice(alert.data.price)),
            _buildDetailRow('Size', alert.data.size.toStringAsFixed(4)),
            _buildDetailRow('Side', alert.data.side.isEmpty ? 'N/A' : alert.data.side.toUpperCase()),
            
            // Special handling for Spoof type
            if (alert.isSpoof) ...[
              _buildDetailRow(
                'Type',
                _inferSpoofDirection(alert),
                valueColor: const Color(0xFFFF4136),
              ),
              _buildDetailRow('Side', alert.data.side.toUpperCase()),
            ],
            
            _buildDetailRow('Level', 'L${alert.level}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFF00FF41)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  String _inferSpoofDirection(Alert alert) {
    // Get current price from cache
    final priceCache = ref.read(priceCacheProvider);
    final currentPrice = priceCache[alert.symbol] ?? alert.data.price;
    
    // Compare spoof price to current price
    if (alert.data.price < currentPrice) {
      return 'FAKE BUY WALL';
    } else if (alert.data.price > currentPrice) {
      return 'FAKE SELL WALL';
    } else {
      return 'FAKE WALL';
    }
  }

  String _formatNumber(double number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}K';
    }
    return number.toStringAsFixed(0);
  }

  String _formatValue(double value) {
    if (value >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '\$${(value / 1000).toStringAsFixed(0)}K';
    }
    return '\$${value.toStringAsFixed(0)}';
  }

  String _formatPrice(double price) {
    if (price < 1.0) {
      return '\$${price.toStringAsFixed(8)}';
    }
    return '\$${price.toStringAsFixed(2)}';
  }

}

// Custom Painter for Radar Grid (no image, pure drawing)
class RadarGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    final paint = Paint()
      ..color = const Color(0xFF00FF41).withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw 5 concentric circles
    for (int i = 1; i <= 5; i++) {
      final radius = maxRadius * (i / 5);
      canvas.drawCircle(center, radius, paint);
    }

    // Draw crosshair lines (horizontal and vertical)
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      paint,
    );
    
    // Draw diagonal lines for better radar effect
    canvas.drawLine(
      Offset(0, 0),
      Offset(size.width, size.height),
      paint..color = const Color(0xFF00FF41).withOpacity(0.1), // Reduced opacity for cleaner look
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(0, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(RadarGridPainter oldDelegate) => false;
}

// Scanner sweep gradient painter
class ScannerPainter extends CustomPainter {
  final double angle;

  ScannerPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Create sweep gradient for scanner effect
    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: angle,
        endAngle: angle + math.pi / 2,
        colors: [
          const Color(0xFF00FF41).withOpacity(0.0),
          const Color(0xFF00FF41).withOpacity(0.4),
          const Color(0xFF00FF41).withOpacity(0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(ScannerPainter oldDelegate) => true;
}
