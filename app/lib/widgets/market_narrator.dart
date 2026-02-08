import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alert.dart';
import '../utils/sound_manager.dart';
import '../providers/notification_settings_provider.dart';
import '../providers/alert_provider.dart';

class MarketNarrator extends ConsumerStatefulWidget {
  final List<Alert> alerts;

  const MarketNarrator({Key? key, required this.alerts}) : super(key: key);

  @override
  ConsumerState<MarketNarrator> createState() => _MarketNarratorState();
}

class _MarketNarratorState extends ConsumerState<MarketNarrator> {
  String _lastSpokenMessage = "";
  
  // Spoof Debouncing
  Timer? _spoofDebounceTimer;
  int _spoofCount = 0;

  @override
  void initState() {
    super.initState();
    // No local TTS init needed, SoundManager handles it
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pass ref to SoundManager for mute checking
    SoundManager().setRef(ref);
  }

  @override
  void dispose() {
    _spoofDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    // Debounce: Don't repeat the same message immediately
    if (text == _lastSpokenMessage) return;
    
    _lastSpokenMessage = text;
    // Delegate to SoundManager for humanization
    await SoundManager().speak(text); 
  }

  /// Intelligent filtering: Only speak if passes notification settings
  Future<void> _attemptSpeak(String message, {
    String? alertType,
    double? value,
    int? confidenceScore,
  }) async {
    final settings = ref.read(notificationSettingsProvider);
    
    // If no passive monitoring enabled, speak everything (default behavior)
    if (!settings.isPassiveModeEnabled) {
      await _speak(message);
      return;
    }
    
    // FILTER 1: Mega Whale Filter (Handled in MainScreen)
    // if (settings.notifyMegaWhales && alertType == 'WHALE') { ... }
    
    // FILTER 2: Retail Trade Mute
    if (settings.muteRetailTrades && alertType == 'TRADE') {
      if (value != null && value < settings.retailTradeThreshold) {
        print('🔇 Muted retail trade: \$${(value / 1000).toStringAsFixed(0)}K');
        return; // Silence
      }
    }
    
    // FILTER 3: Trend Flip Detection
    if (settings.notifyTrendFlips && confidenceScore != null) {
      final previousScore = ref.read(previousConfidenceProvider);
      
      // Bearish flip: crossed below 35
      if (previousScore >= settings.bearishThreshold && confidenceScore < settings.bearishThreshold) {
        print('📉 TREND FLIP: Bearish (${previousScore} → ${confidenceScore})');
        await _speak('⚠️ TREND FLIP: Bearish pressure increasing. Score ${confidenceScore}.');
        ref.read(previousConfidenceProvider.notifier).state = confidenceScore;
        return;
      }
      
      // Bullish flip: crossed above 65
      if (previousScore <= settings.bullishThreshold && confidenceScore > settings.bullishThreshold) {
        print('📈 TREND FLIP: Bullish (${previousScore} → ${confidenceScore})');
        await _speak('⚠️ TREND FLIP: Bullish momentum building. Score ${confidenceScore}.');
        ref.read(previousConfidenceProvider.notifier).state = confidenceScore;
        return;
      }
      
      // Update previous score
      ref.read(previousConfidenceProvider.notifier).state = confidenceScore;
    }
    
    // FILTER 4: Manipulation Cluster Detection
    if (settings.notifyManipulation && alertType == 'SPOOF') {
      final spoofCount = ref.read(spoofCounterProvider);
      if (spoofCount >= settings.spoofClusterSize) {
        print('👻 MANIPULATION CLUSTER: ${spoofCount} spoofs');
        await _speak(message);
        return;
      }
    }
    
    // If passive mode enabled but no filters matched, silence
    if (settings.isPassiveModeEnabled) {
      print('🔇 Passive mode: Filtered out message');
      return;
    }
    
    // Default: speak
    await _speak(message);
  }

  void _handleSpoofAlert() {
    // Increment counter
    _spoofCount++;
    
    // Update global spoof counter for cluster detection
    ref.read(spoofCounterProvider.notifier).state = _spoofCount;
    
    // If timer is already running, just increment and return
    if (_spoofDebounceTimer != null && _spoofDebounceTimer!.isActive) {
      return;
    }
    
    // Start 5-second debounce timer
    _spoofDebounceTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      
      // Announce based on count
      String announcement;
      if (_spoofCount == 1) {
        announcement = "Spoof Detected.";
      } else {
        announcement = "Warning. $_spoofCount Spoofs detected. Manipulation active.";
      }
      
      // Use intelligent filtering
      _attemptSpeak(announcement, alertType: 'SPOOF');
      
      // Reset counter
      _spoofCount = 0;
      ref.read(spoofCounterProvider.notifier).state = 0;
    });
  }

  String _formatCurrency(double value) {
    if (value >= 1000000) return '\$${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '\$${(value / 1000).toStringAsFixed(1)}K';
    return '\$${value.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    // 1. Filter alerts context
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Keep 3 mins for Volume Analysis, but strictly LIMIT Spoof/Iceberg relevance
    final recentForVol = widget.alerts.where((a) => (now - a.data.timestamp) < 3 * 60 * 1000).toList();
    
    // 2. Logic Determination
    String message = "⚖️ NEUTRAL: Volatility low. Awaiting breakout.";
    Color color = Colors.grey;

    // Strict Window for "State Override" (Spoof/Iceberg)
    // Only block the narrative if the manipulation is VERY fresh (last 30 seconds)
    final hasRecentSpoof = widget.alerts.any((a) => a.isSpoof && (now - a.data.timestamp) < 30 * 1000);
    final hasRecentIceberg = widget.alerts.any((a) => a.isIceberg && a.data.notional > 1000000 && (now - a.data.timestamp) < 30 * 1000);

    if (hasRecentSpoof) {
      message = "👻 MANIPULATION: Fake walls detected. Tread carefully.";
      color = Colors.orange;
      
      // Trigger debounced spoof announcement
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleSpoofAlert();
      });
    } else if (hasRecentIceberg) {
      message = "🧊 HIDDEN WALLS: Institutional accumulation detected.";
      color = Colors.cyanAccent;
    } else {
    // 3. Market Sentiment (Activity Density)
    int recentCount = recentForVol.length;
    bool isVolatile = recentCount > 15 || recentForVol.any((a) => a.isWhale && a.data.notional > 5000000); // >15 alerts or $5M whale
    bool isActive = recentCount >= 5;

    if (isVolatile) {
       message = "🔴 VOLATILE: High activity ($recentCount alerts) & Whales. Caution.";
       color = Colors.redAccent;
    } else if (isActive) {
       message = "🟡 ACTIVE: Market moving ($recentCount alerts). Test trades viable.";
       color = Colors.yellowAccent;
    } else {
       message = "🔵 CALM: Low volume ($recentCount alerts). Filtering noise.";
       color = Colors.blueAccent;
    }

    // 4. Volume Analysis Override (If Sentiment is Calm/Active but volume skew is extreme)
    double buyVol = 0;
    double sellVol = 0;

    for (var a in recentForVol) {
      if (a.data.side.toLowerCase() == 'buy') {
        buyVol += a.data.notional;
      } else {
        sellVol += a.data.notional;
      }
    }

    final buyVolStr = _formatCurrency(buyVol);
    final sellVolStr = _formatCurrency(sellVol);

    // Only override if Volume Skew is significant (> 2.0 Ratio)
    if (buyVol > (sellVol * 2.0) && buyVol > 100000) {
      message = "🐂 BULLISH: Strong buying pressure ($buyVolStr).";
      color = Colors.greenAccent;
    } else if (sellVol > (buyVol * 2.0) && sellVol > 100000) {
      message = "🐻 BEARISH: Strong selling pressure ($sellVolStr).";
      color = Colors.redAccent;
    }
    }

    // Trigger TTS if message changes (Post-build to avoid side-effects during build)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Determine alert type and value for filtering
        String? alertType;
        double? value;
        
        if (message.contains('BULLISH') || message.contains('BEARISH')) {
          alertType = 'SENTIMENT';
        } else if (message.contains('MANIPULATION')) {
          alertType = 'SPOOF';
        } else if (message.contains('HIDDEN WALLS')) {
          alertType = 'ICEBERG';
        }
        
        // Get current confidence score for trend flip detection
        final confidenceScore = ref.read(currentConfidenceScoreProvider);
        
        _attemptSpeak(message, alertType: alertType, confidenceScore: confidenceScore);
      }
    });

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Container(
        key: ValueKey<String>(message),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: message.contains("PAUSED") ? Colors.red.withOpacity(0.9) : const Color(0xFF1a1e3a).withOpacity(0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ">",
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier',
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: message.contains("PAUSED") ? Colors.white : color,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            if (!message.contains("PAUSED")) ...[
              const SizedBox(height: 4),
              // STRIKE COUNTER (Visual Decoration for now, wired to backend state later)
               Row(
                mainAxisAlignment: MainAxisAlignment.center, // Center the dots
                mainAxisSize: MainAxisSize.min, // Shrink to fit children
                children: [
                  _buildStrikeDot(isActive: false), // Placeholder
                  SizedBox(width: 4),
                  _buildStrikeDot(isActive: false), // Placeholder
                  SizedBox(width: 4),
                  _buildStrikeDot(isActive: false), // Placeholder
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildStrikeDot({required bool isActive}) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: isActive ? Colors.redAccent : Colors.grey.withOpacity(0.3),
        shape: BoxShape.circle,
      ),
    );
  }
}
