import 'package:flutter/material.dart';
import '../models/alert.dart';

/// Slim Edge HUD for Iceberg Depth
/// Non-intrusive visualization of hidden liquidity (Sell vs Buy pressure)
/// Anchored to the Left Edge of the screen.
class IcebergDepthBar extends StatelessWidget {
  final List<Alert> activeAlerts;
  final double currentPrice;

  const IcebergDepthBar({
    Key? key,
    required this.activeAlerts,
    required this.currentPrice,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 1. Aggregation Logic
    double buyVol = 0;
    double sellVol = 0;

    for (var alert in activeAlerts) {
      if (alert.isIceberg) {
        // Check if broken
        bool isBroken = false;
        if (alert.data.side.toLowerCase() == 'buy') {
          isBroken = currentPrice < alert.data.price;
        } else {
          isBroken = currentPrice > alert.data.price;
        }

        // Only count active (Unbroken) active icebergs
        if (!isBroken) {
          if (alert.data.side.toLowerCase() == 'buy') {
            buyVol += alert.data.notional;
          } else {
            sellVol += alert.data.notional;
          }
        }
      }
    }

    // 2. Threshold check to hide noise
    // If very little volume, don't show anything
    if (buyVol < 50000 && sellVol < 50000) return const SizedBox.shrink();

    // 3. Calculate heights (Max height = 180px for better visibility)
    // We normalize against a "reasonable" max volume (e.g., $5M) or relative to each other?
    // Let's stick to relative ratio but capped specific height
    double total = buyVol + sellVol;
    double maxHeight = 180.0; // Taller for better resolution

    double buyHeight = total > 0 ? (buyVol / total) * maxHeight : 0;
    double sellHeight = total > 0 ? (sellVol / total) * maxHeight : 0;

    // Minimum visual height if volume exists
    if (buyVol > 0 && buyHeight < 15) buyHeight = 15;
    if (sellVol > 0 && sellHeight < 15) sellHeight = 15;

    // Format Helper
    String formatVol(double vol) {
      if (vol >= 1000000) {
        return "\$${(vol / 1000000).toStringAsFixed(1)}M";
      }
      return "\$${(vol / 1000).toStringAsFixed(0)}K";
    }

    // 4. Build HUD
    return Positioned(
      left: 0,
      top: 100, // Start below header
      bottom: 100, // End above footer
      child: SizedBox(
        width: 60, // Container width for label readability
        child: Stack(
          children: [
            // --- SELL PRESSURE (RED) - Top Anchored ---
            if (sellVol > 0)
              Positioned(
                top: 0,
                left: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The Slim Bar
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      width: 3.0,
                      height: sellHeight,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(3),
                        ),
                        boxShadow: [
                            BoxShadow(
                                color: Colors.redAccent.withOpacity(0.6),
                                blurRadius: 4,
                                offset: const Offset(1, 0)
                            )
                        ]
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Value Label
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        formatVol(sellVol),
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: "Courier New", // Monospaced for tech look
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // --- BUY SUPPORT (GREEN) - Bottom Anchored ---
            if (buyVol > 0)
              Positioned(
                bottom: 0,
                left: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // The Slim Bar
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      width: 3.0,
                      height: buyHeight,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(3),
                        ),
                        boxShadow: [
                            BoxShadow(
                                color: Colors.greenAccent.withOpacity(0.6),
                                blurRadius: 4,
                                offset: const Offset(1, 0)
                            )
                        ]
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Value Label
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        formatVol(buyVol),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: "Courier New",
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
