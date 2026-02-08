import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/alert_provider.dart';

class SentimentGauge extends ConsumerWidget {
  const SentimentGauge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sentiment = ref.watch(sentimentProvider);
    final ratio = sentiment['ratio'] ?? 0.5;
    final buyVol = sentiment['buyVol'] ?? 0.0;
    final sellVol = sentiment['sellVol'] ?? 0.0;
    
    // Determine label and color
    final buyPressure = (ratio * 100).round();
    final sellPressure = 100 - buyPressure;
    final label = ratio >= 0.5 
        ? '$buyPressure% BUY Pressure' 
        : '$sellPressure% SELL Pressure';
    
    // Color gradient based on ratio
    Color dominantColor;
    if (ratio >= 0.7) {
      dominantColor = const Color(0xFF00FF41); // Strong Buy - Green
    } else if (ratio >= 0.55) {
      dominantColor = const Color(0xFF9D4EDD); // Mild Buy - Purple
    } else if (ratio >= 0.45) {
      dominantColor = const Color(0xFFFFFF00); // Neutral - Yellow
    } else if (ratio >= 0.3) {
      dominantColor = const Color(0xFFFF6B35); // Mild Sell - Orange
    } else {
      dominantColor = const Color(0xFFFF0000); // Strong Sell - Red
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1e3a).withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dominantColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: dominantColor.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '📊 Market Sentiment',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: dominantColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Sentiment Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  // Buy side (Green)
                  Expanded(
                    flex: (ratio * 100).round(),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF00FF41).withOpacity(0.8),
                            const Color(0xFF00FF41),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Sell side (Red)
                  Expanded(
                    flex: ((1 - ratio) * 100).round(),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFF0000),
                            const Color(0xFFFF0000).withOpacity(0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Volume Labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🟢 Buy: \$${_formatVolume(buyVol)}',
                style: TextStyle(
                  color: const Color(0xFF00FF41).withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
              Text(
                '🔴 Sell: \$${_formatVolume(sellVol)}',
                style: TextStyle(
                  color: const Color(0xFFFF0000).withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatVolume(double volume) {
    if (volume >= 1000000) {
      return '${(volume / 1000000).toStringAsFixed(1)}M';
    } else if (volume >= 1000) {
      return '${(volume / 1000).toStringAsFixed(0)}K';
    }
    return volume.toStringAsFixed(0);
  }
}
