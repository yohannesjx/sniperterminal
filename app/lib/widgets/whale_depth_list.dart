import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alert.dart';
import '../providers/alert_provider.dart';

class WhaleDepthList extends ConsumerWidget {
  const WhaleDepthList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCoin = ref.watch(selectedCoinProvider);
    final alertsMap = ref.watch(recentAlertsProvider);
    final currentPrice = ref.watch(priceCacheProvider)[selectedCoin] ?? 0.0;
    
    // Get alerts for current coin
    final alerts = alertsMap[selectedCoin] ?? [];
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Filter: WHALE, ICEBERG, WALL only + < 5 mins old
    final activeLevels = alerts.where((a) {
      final isTypeMatch = a.type == 'WHALE' || a.type == 'ICEBERG' || a.type == 'WALL';
      final isFresh = now - a.data.timestamp < 300000; // 5 minutes
      return isTypeMatch && isFresh;
    }).toList();

    // 2. Split into Buys and Sells
    final buys = activeLevels.where((a) => a.data.side == 'buy').toList();
    final sells = activeLevels.where((a) => a.data.side == 'sell').toList();

    // 3. Sort
    // Buys: Highest price first (closest to current price)
    buys.sort((a, b) => b.data.price.compareTo(a.data.price));
    // Sells: Lowest price first (closest to current price)
    sells.sort((a, b) => a.data.price.compareTo(b.data.price));

    // Limit to top 5
    final topBuys = buys.take(5).toList();
    final topSells = sells.take(5).toList().reversed.toList(); // Reverse to show highest sell at top

    if (topBuys.isEmpty && topSells.isEmpty) return const SizedBox.shrink();

    return Container(
      width: 200,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0a0e27).withOpacity(0.8), // Dark Navy
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // SELLS (Red)
          ...topSells.map((alert) => _buildRow(alert, currentPrice, isSell: true)),
          
          if (topSells.isNotEmpty) const SizedBox(height: 4),

          // CURRENT PRICE SEPARATOR
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              border: Border.symmetric(horizontal: BorderSide(color: Colors.white10)),
            ),
            child: Center(
              child: Text(
                formatPrice(currentPrice),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),

          if (topBuys.isNotEmpty) const SizedBox(height: 4),

          // BUYS (Green)
          ...topBuys.map((alert) => _buildRow(alert, currentPrice, isSell: false)),
        ],
      ),
    );
  }

  Widget _buildRow(Alert alert, double currentPrice, {required bool isSell}) {
    final price = alert.data.price;
    
    // Check if level is broken
    // Sell Broken (Bullish) if Current > Price
    // Buy Broken (Bearish) if Current < Price
    bool isBroken = isSell ? currentPrice > price : currentPrice < price;

    final baseColor = isSell ? const Color(0xFFFF5252) : const Color(0xFF00E676);
    
    // Cyan for Icebergs/Walls regardless of side to standout
    // BUT if broken, use specific logic
    Color textColor = (alert.type == 'ICEBERG' || alert.type == 'WALL') 
        ? const Color(0xFF00E5FF) 
        : baseColor;

    IconData iconData = Icons.water_drop; // Default
    String iconText = '🐋';
    if (alert.type == 'ICEBERG') iconText = '❄️';
    if (alert.type == 'WALL') iconText = '🛡️';

    // BROKEN STATE OVERRIDES
    if (isBroken) {
      iconText = '✅';
      // Broken Sell = Bullish (Green Check)
      // Broken Buy = Bearish (Red Check)
      textColor = isSell ? const Color(0xFF00E676) : const Color(0xFFFF5252); 
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Opacity(
        opacity: isBroken ? 0.5 : 1.0,
        child: Row(
          children: [
            Text(iconText, style: const TextStyle(fontSize: 10)),
            const SizedBox(width: 4),
            Text(
              formatPrice(price),
              style: TextStyle(
                color: textColor,
                fontSize: 11, 
                fontWeight: FontWeight.w500,
                decoration: isBroken ? TextDecoration.lineThrough : null,
                decorationColor: textColor,
              ),
            ),
            const Spacer(),
            Text(
              _formatValue(alert.data.notional),
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                decoration: isBroken ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatValue(double value) {
    if (value >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(1)}M';
    }
    return '\$${(value / 1000).toStringAsFixed(0)}k';
  }

  String formatPrice(double price) {
    if (price < 1.0) return '\$${price.toStringAsFixed(6)}';
    if (price < 10.0) return '\$${price.toStringAsFixed(4)}';
    return '\$${price.toStringAsFixed(2)}';
  }
}
