import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../providers/notification_settings_provider.dart';
import '../models/notification_settings.dart';

class NotificationSettingsSheet extends ConsumerWidget {
  const NotificationSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);

    return GlassmorphicContainer(
      width: double.infinity,
      height: 600, // Increased height for expansion
      borderRadius: 30,
      blur: 20,
      alignment: Alignment.center,
      border: 2,
      linearGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF0a0e27).withOpacity(0.95),
          const Color(0xFF0a0e27).withOpacity(0.85),
        ],
      ),
      borderGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.5),
          Colors.white.withOpacity(0.2),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Text(
            '🔕 Passive Monitoring',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Only alert on critical events',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 30),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                // WHALE EXPANSION TILE
                _buildWhaleConfigTile(context, ref, settings),
                
                const SizedBox(height: 16),
                _buildToggleTile(
                  context,
                  ref,
                  icon: '📈',
                  title: 'Trend Flips',
                  subtitle: 'Alert when confidence crosses 35/65',
                  value: settings.notifyTrendFlips,
                  onChanged: (val) {
                    ref.read(notificationSettingsProvider.notifier).state =
                        settings.copyWith(notifyTrendFlips: val);
                  },
                ),
                const SizedBox(height: 16),
                _buildToggleTile(
                  context,
                  ref,
                  icon: '👻',
                  title: 'Manipulation Clusters',
                  subtitle: 'Alert on 3+ spoofs detected',
                  value: settings.notifyManipulation,
                  onChanged: (val) {
                    ref.read(notificationSettingsProvider.notifier).state =
                        settings.copyWith(notifyManipulation: val);
                  },
                ),
                const SizedBox(height: 16),
                _buildToggleTile(
                  context,
                  ref,
                  icon: '📲',
                  title: 'Push Notifications',
                  subtitle: 'Get alerts for >\$5M whales',
                  value: settings.subscribeToWhales,
                  onChanged: (val) {
                    ref.read(notificationSettingsProvider.notifier).state =
                        settings.copyWith(subscribeToWhales: val);
                  },
                ),
                const SizedBox(height: 16),
                _buildToggleTile(
                  context,
                  ref,
                  icon: '🔇',
                  title: 'Mute Retail Trades',
                  subtitle: 'Silence trades < \$100K',
                  value: settings.muteRetailTrades,
                  onChanged: (val) {
                    ref.read(notificationSettingsProvider.notifier).state =
                        settings.copyWith(muteRetailTrades: val);
                  },
                ),
                const SizedBox(height: 30),
                if (settings.isPassiveModeEnabled)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF41).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00FF41).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Color(0xFF00FF41),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Passive mode active. App will only speak on critical events.',
                            style: TextStyle(
                              color: const Color(0xFF00FF41).withOpacity(0.9),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhaleConfigTile(BuildContext context, WidgetRef ref, NotificationSettings settings) {
    return Container(
      decoration: BoxDecoration(
         color: Colors.white.withOpacity(0.05),
         borderRadius: BorderRadius.circular(12),
         border: Border.all(
           color: settings.notifyMegaWhales 
             ? const Color(0xFF00FF41).withOpacity(0.3) 
             : Colors.white.withOpacity(0.1)
         )
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: settings.notifyMegaWhales,
          collapsedBackgroundColor: Colors.transparent,
          backgroundColor: Colors.black12,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.only(bottom: 16),
          title: Row(
            children: [
               const Text('🐋', style: TextStyle(fontSize: 28)),
               const SizedBox(width: 16),
               Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Text(
                       'Whale Thresholds', 
                       style: TextStyle(
                         color: settings.notifyMegaWhales ? const Color(0xFF00FF41) : Colors.white, 
                         fontWeight: FontWeight.bold, 
                         fontSize: 16
                       )
                     ),
                     const SizedBox(height: 4),
                     Text(
                       'Configure per-coin definitions', 
                       style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)
                     ),
                  ]
               )),
               Switch(
                  value: settings.notifyMegaWhales,
                  onChanged: (val) {
                     ref.read(notificationSettingsProvider.notifier).state = settings.copyWith(notifyMegaWhales: val);
                  },
                  activeColor: const Color(0xFF00FF41),
                  activeTrackColor: const Color(0xFF00FF41).withOpacity(0.3),
               )
            ],
          ),
          children: [
             if (settings.notifyMegaWhales)
                ...settings.coinThresholds.entries.map((entry) {
                   return _buildCoinSliderRow(ref, settings, entry.key, entry.value);
                }).toList()
          ],
        ),
      )
    );
  }

  Widget _buildCoinSliderRow(WidgetRef ref, NotificationSettings settings, String symbol, double currentVal) {
    // Format helper
    String formatVal(double val) {
       if (val >= 1000000) return '\$${(val / 1000000).toStringAsFixed(1)}M';
       return '\$${(val / 1000).toStringAsFixed(0)}K';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              // Symbol
              SizedBox(
                width: 50,
                child: Text(
                  symbol, 
                  style: const TextStyle(
                    color: Colors.white, 
                    fontWeight: FontWeight.bold,
                    fontSize: 14
                  )
                ),
              ),
              
              // Slider
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFF00FF41),
                    inactiveTrackColor: Colors.white.withOpacity(0.1),
                    thumbColor: const Color(0xFF00FF41),
                    overlayColor: const Color(0xFF00FF41).withOpacity(0.2),
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: currentVal.clamp(10000.0, 10000000.0),
                    min: 10000.0, // $10k
                    max: 10000000.0, // $10M
                    divisions: 100,
                    onChanged: (newVal) {
                      final newMap = Map<String, double>.from(settings.coinThresholds);
                      newMap[symbol] = newVal;
                      ref.read(notificationSettingsProvider.notifier).state = settings.copyWith(coinThresholds: newMap);
                    },
                  ),
                ),
              ),
              
              // Value
              SizedBox(
                width: 60,
                child: Text(
                  formatVal(currentVal),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: const Color(0xFF00FF41).withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 12
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleTile(
    BuildContext context,
    WidgetRef ref, {
    required String icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? const Color(0xFF00FF41).withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: value ? const Color(0xFF00FF41) : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF00FF41),
            activeTrackColor: const Color(0xFF00FF41).withOpacity(0.3),
          ),
        ],
      ),
    );
  }
}
