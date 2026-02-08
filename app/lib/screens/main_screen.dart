import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alert.dart';
import '../models/notification_settings.dart';
import '../providers/alert_provider.dart';
import '../providers/notification_settings_provider.dart';
import '../widgets/coin_selector.dart';
import '../widgets/radar_view.dart';
import '../widgets/notification_settings_sheet.dart';
import '../utils/sound_manager.dart';
import '../utils/notification_service.dart';
import '../widgets/mute_button.dart';
import '../widgets/suggestion_card.dart';
import '../utils/signal_engine.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize Sound System
    SoundManager().init();
  }

  @override
  Widget build(BuildContext context) {
    final selectedCoin = ref.watch(selectedCoinProvider);
    final currentPrice = ref.watch(currentPriceProvider);
    final latestSymbol = ref.watch(latestSymbolProvider);
    // Smart Mute handled in sub-widgets (MuteButton)
    // print('🏗️ Building MainScreen. Coin: $selectedCoin, Symbol: $latestSymbol, Price: $currentPrice');
    
    // Listen to alert stream and update providers
    // Use UNFILTERED stream to populate cache and handle global sounds
    ref.listen(alertStreamProvider, (previous, next) {
      next.whenData((alert) {
        // Debug log
        // print('Alert received: ${alert.symbol} ${alert.type} \$${alert.data.price}');
        
        // 1. GLOBAL: Update Price Cache (Memory)
        final currentCache = ref.read(priceCacheProvider);
        if (currentCache[alert.symbol] != alert.data.price) {
           final newCache = Map<String, double>.from(currentCache);
           newCache[alert.symbol] = alert.data.price;
           ref.read(priceCacheProvider.notifier).state = newCache;
        }

        // 1.5 GLOBAL: Update Sentiment Data
        if (alert.isSentiment) {
          ref.read(sentimentProvider.notifier).state = {
            'buyVol': alert.sentimentBuyVol,
            'sellVol': alert.sentimentSellVol,
            'ratio': alert.sentimentRatio,
          };
          return; // Don't process sentiment as a regular alert
        }

        // 2. GLOBAL: Sound & Haptics (Eyes-Free Monitoring is usually global)
        final muteUntil = ref.read(mutedProvider);
        if (muteUntil == null || DateTime.now().isAfter(muteUntil)) {
            if (alert.type == 'SPOOF') {
                SoundManager().playSpoofAlert();
            } else if (alert.type == 'WALL') {
                SoundManager().playWallAlert();
            } else if (alert.type == 'WHALE' && alert.level >= 5) {
                // God Tier
                SoundManager().playGodTierAlert();
            } else if (alert.type == 'WHALE') {
                double val = alert.data.notional; 
                SoundManager().playWhaleAlert(val);
            }
        }

        // 3. Add ALL alerts to the provider (it handles coin bucketing internally)
        ref.read(recentAlertsProvider.notifier).addAlert(alert);
        
        // 3.5 BACKGROUND NOTIFICATIONS: Send push notification for critical alerts
        final settings = ref.read(notificationSettingsProvider);
        if (settings.notifyInBackground && _isCriticalAlert(alert, settings, ref)) {
          _sendBackgroundNotification(alert);
        }
        
        // 4. FILTERED: Only update UI state for selected coin
        if (selectedCoin == 'ALL' || alert.symbol == selectedCoin) {
            // Update ticker tape
            ref.read(tickerTapeProvider.notifier).addTrade(alert);
            
            // Update current price and latest symbol for selected coin only
            ref.read(currentPriceProvider.notifier).state = alert.data.price;
            ref.read(latestSymbolProvider.notifier).state = alert.symbol;
        }
      });
    });

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.5,
            colors: [
              Color(0xFF1a2342), 
              Color(0xFF0a0e27), 
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Main Content
              Column(
                children: [
                  const SizedBox(height: 20),
                  
                  // Live Feed Header
                  _buildLiveFeedHeader(selectedCoin, latestSymbol, currentPrice, ref),
                  
                  const SizedBox(height: 8), 
                  
                  // Coin Selector
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const CoinSelector(),
                  ),
                  
                  const SizedBox(height: 8), 
                  
                  // Radar View (Expanded to fill central space)
                  const Expanded(
                    child: RadarView(),
                  ),
                  
                   // Suggestion Card (Fixed at Bottom)
                  const SuggestionCard(),
              
                   // Bottom Spacing for FAB
                  const SizedBox(height: 80),
                ],
              ),
              
              // CO-PILOT STATUS BAR REMOVED
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveFeedHeader(String selectedCoin, String latestSymbol, double currentPrice, WidgetRef ref) {
    // Determine title to show
    String title = selectedCoin;
    if (selectedCoin == 'ALL') {
      title = latestSymbol.isNotEmpty ? latestSymbol : 'MARKET';
    }

    // Format Price
    String priceString = _formatPrice(currentPrice);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIVE FEED • $title',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  priceString,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32, // Slightly larger
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier', // Monospace for numbers
                  ),
                ),
              ],
            ),
          ),
          
          // Settings Button
          GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (context) => const NotificationSettingsSheet(),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.tune,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Mute Button (Smart)
          MuteButton(),
        ],
      ),
    );
  }

  Widget _buildTickerTape(WidgetRef ref) {
    final trades = ref.watch(tickerTapeProvider);
    
    if (trades.isEmpty) {
      return const SizedBox(height: 60);
    }

    return SizedBox(
      height: 60,
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.1, 0.9, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          reverse: true,
          itemCount: trades.length,
          itemBuilder: (context, index) {
            final alert = trades[index];
            return _buildTickerItem(alert);
          },
        ),
      ),
    );
  }

  Widget _buildTickerItem(Alert alert) {
    final isBuy = alert.data.side == 'buy';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isBuy
              ? const Color(0xFF00FF41).withOpacity(0.3)
              : const Color(0xFFFF1493).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${alert.symbol} ${isBuy ? '↑' : '↓'}',
            style: TextStyle(
              color: isBuy ? const Color(0xFF00FF41) : const Color(0xFFFF1493),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '\$${_formatNumber(alert.data.notional)}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    if (price == 0) return 'Scanning...';
    if (price < 1.0) {
      return '\$${price.toStringAsFixed(8)}';
    }
    return '\$${price.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}';
  }

  String _formatNumber(double number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(2)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toStringAsFixed(0);
  }

  Widget _buildPainSlider(WidgetRef ref) {
    final painThreshold = ref.watch(painThresholdProvider);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4), // Reduced vertical margin
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Reduced padding
      decoration: BoxDecoration(
        color: const Color(0xFF1a1e3a).withOpacity(0.4),
        borderRadius: BorderRadius.circular(8), // Smaller radius
        border: Border.all(
          color: const Color(0xFF9D4EDD).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Text('🎚️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: painThreshold.clamp(10000.0, 10000000.0), // Ensure value is valid
                min: 10000, // Reduced from 100k
                max: 10000000,
                divisions: 100, // Roughly 100k steps, good enough for high value
                activeColor: const Color(0xFF9D4EDD),
                inactiveColor: Colors.white.withOpacity(0.1),
                onChanged: (value) {
                  ref.read(painThresholdProvider.notifier).state = value;
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '\$${_formatNumber(painThreshold)}',
            style: const TextStyle(
              color: Color(0xFF9D4EDD),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Check if an alert is critical enough to warrant a background notification
  /// Returns true if:
  /// 1. Alert value exceeds user's whale threshold, OR
  /// 2. Confidence score drops below 25 (crash warning)
  bool _isCriticalAlert(Alert alert, NotificationSettings settings, WidgetRef ref) {
    final value = alert.data.notional;
    
    // Critical Condition 1: Mega Whale (exceeds threshold)
    if (alert.isWhale && value >= settings.getThreshold(alert.symbol)) {
      print('🚨 CRITICAL: Mega whale detected (\$${(value / 1000000).toStringAsFixed(1)}M)');
      return true;
    }
    
    // Critical Condition 2: Crash Warning (confidence < 25)
    final confidenceScore = ref.read(currentConfidenceScoreProvider);
    if (confidenceScore < 25) {
      print('🚨 CRITICAL: Crash warning (confidence: $confidenceScore)');
      return true;
    }
    
    return false;
  }

  /// Send a background notification for a critical alert
  void _sendBackgroundNotification(Alert alert) {
    final value = alert.data.notional;
    final price = alert.data.price;
    final side = alert.data.side.toUpperCase();
    
    // Format value
    String valueStr;
    if (value >= 1000000) {
      valueStr = '\$${(value / 1000000).toStringAsFixed(1)}M';
    } else {
      valueStr = '\$${(value / 1000).toStringAsFixed(0)}K';
    }
    
    // Format price
    String priceStr;
    if (price >= 1000) {
      priceStr = '\$${(price / 1000).toStringAsFixed(1)}K';
    } else {
      priceStr = '\$${price.toStringAsFixed(2)}';
    }
    
    final title = '${alert.symbol} Whale Alert 🚨';
    final body = 'A $valueStr $side order detected at $priceStr';
    
    NotificationService().showNotification(title, body);
  }
}
