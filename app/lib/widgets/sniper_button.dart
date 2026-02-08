import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/alert_provider.dart';
import '../utils/trade_signal_engine.dart';

class SniperButton extends ConsumerWidget {
  const SniperButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton(
      onPressed: () => _analyzeAndShow(context, ref),
      backgroundColor: const Color(0xFF00bcd4), // Cyan
      child: const Icon(Icons.gps_fixed, color: Colors.white),
    );
  }

  void _analyzeAndShow(BuildContext context, WidgetRef ref) {
    final selectedCoin = ref.read(selectedCoinProvider);
    final alerts = ref.read(recentAlertsProvider)[selectedCoin] ?? [];
    final currentPrice = ref.read(currentPriceProvider);

    if (currentPrice == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for price data...')),
      );
      return;
    }

    final signal = TradeSignalEngine.analyze(currentPrice, alerts);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSheet(context, signal, selectedCoin),
    );
  }

  Widget _buildSheet(BuildContext context, TradeSignal signal, String coin) {
    final isLong = signal.type == "LONG";
    final isWait = signal.type == "WAIT";
    final color = isWait 
        ? Colors.grey 
        : (isLong ? const Color(0xFF00E676) : const Color(0xFFFF5252));

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1a1e3a),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isWait ? Icons.hourglass_empty : (isLong ? Icons.trending_up : Icons.trending_down),
                color: color,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                isWait ? "NO SETUP DETECTED" : "${signal.type} OPPORTUNITY",
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          Text(
            signal.reasoning,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 24),

          if (!isWait) ...[
            // Numbers Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem("ENTRY", signal.entry),
                _buildStatItem("TARGET", signal.takeProfit, isTarget: true),
                _buildStatItem("STOP LOSS", signal.stopLoss, isStop: true),
              ],
            ),
            
            const SizedBox(height: 24),

            // Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                "Risk/Reward Ratio: 1:${signal.riskReward.toStringAsFixed(1)}",
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ] else ...[
             const SizedBox(height: 20),
             const Text(
              "Waiting for clearer whale activity...",
              style: TextStyle(color: Colors.white30, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, double value, {bool isTarget = false, bool isStop = false}) {
    Color valColor = Colors.white;
    if (isTarget) valColor = const Color(0xFF00E676);
    if (isStop) valColor = const Color(0xFFFF5252);

    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatPrice(value),
          style: TextStyle(
            color: valColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Courier',
          ),
        ),
      ],
    );
  }

  String _formatPrice(double price) {
    if (price < 1.0) return '\$${price.toStringAsFixed(6)}';
    if (price < 10.0) return '\$${price.toStringAsFixed(4)}';
    return '\$${price.toStringAsFixed(2)}';
  }
}
