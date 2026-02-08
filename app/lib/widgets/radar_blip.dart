import 'package:flutter/material.dart';
import '../models/alert.dart';

/// Pulse Blip Widget - Standard radar blip with animation
/// Handles both active (solid) and broken (hollow ring) states
class PulseBlip extends StatelessWidget {
  final Alert alert;
  final double currentPrice;
  final double size;
  final double opacity;
  final AnimationController pulseController;
  final Animation<double> pulseScale;
  final VoidCallback onTap;

  const PulseBlip({
    super.key,
    required this.alert,
    required this.currentPrice,
    required this.size,
    required this.opacity,
    required this.pulseController,
    required this.pulseScale,
    required this.onTap,
  });

  /// Determine if iceberg is broken
  bool get isBroken {
    if (!alert.isIceberg) return false;
    
    if (alert.data.side.toLowerCase() == 'buy') {
      // Buy wall (support): Broken if price drops below it
      return currentPrice < alert.data.price;
    } else {
      // Sell wall (resistance): Broken if price rises above it
      return currentPrice > alert.data.price;
    }
  }

  /// Get blip color based on alert type
  Color get blipColor {
    if (alert.isSpoof) return Colors.purpleAccent;
    if (alert.isIceberg) return Colors.cyanAccent;
    if (alert.isBreakout) return Colors.yellowAccent;
    if (alert.isWall) return Colors.orangeAccent;
    if (alert.isLiquidation) return Colors.red;
    return alert.data.side.toLowerCase() == 'buy' 
        ? Colors.greenAccent 
        : Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final color = blipColor;
    final broken = isBroken;

    // Build blip based on state
    Widget blipDot;

    if (broken) {
      // BROKEN STATE: Hollow ring (ghosted, no animation)
      blipDot = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(
            color: color.withOpacity(0.4), // Ghosted opacity
            width: 2.0,
          ),
        ),
      );
    } else {
      // ACTIVE STATE: Solid dot with neon glow
      blipDot = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(opacity),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.8 * opacity),
              blurRadius: size / 2,
              spreadRadius: size / 4,
            ),
          ],
        ),
      );
    }

    // Add ripple animation ONLY for active large blips
    Widget finalBlip = blipDot;
    if (!broken && size >= 22.0) {
      finalBlip = AnimatedBuilder(
        animation: pulseController,
        builder: (context, child) {
          double rippleScale = 1.0 + (pulseController.value * 1.5);
          return Stack(
            alignment: Alignment.center,
            children: [
              // Ripple effect
              Container(
                width: size * rippleScale,
                height: size * rippleScale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withOpacity(0.3 * (1 - pulseController.value)),
                    width: 2,
                  ),
                ),
              ),
              // Main dot
              blipDot,
            ],
          );
        },
      );
    }

    // Apply pulse scale (disabled for broken state)
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: pulseScale,
        builder: (context, child) {
          double scale = broken ? 1.0 : pulseScale.value;
          return Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: broken ? 0.4 : opacity,
              child: finalBlip,
            ),
          );
        },
      ),
    );
  }
}

/// Double Ring Blip - "Blast Crater" for historical high-value events
/// Used for L4/L5 trades or broken mega walls
class DoubleRingBlip extends StatelessWidget {
  final Alert alert;
  final double size;
  final double opacity;
  final VoidCallback onTap;

  const DoubleRingBlip({
    super.key,
    required this.alert,
    required this.size,
    required this.opacity,
    required this.onTap,
  });

  /// Get blip color based on alert type
  Color get blipColor {
    if (alert.isSpoof) return Colors.purpleAccent;
    if (alert.isIceberg) return Colors.cyanAccent;
    if (alert.isBreakout) return Colors.yellowAccent;
    if (alert.isWall) return Colors.orangeAccent;
    if (alert.isLiquidation) return Colors.red;
    return alert.data.side.toLowerCase() == 'buy' 
        ? Colors.greenAccent 
        : Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final color = blipColor;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(
              color: color.withOpacity(0.8), // Outer ring
              width: 1.5,
            ),
          ),
          child: Container(
            margin: const EdgeInsets.all(4.0), // Gap between rings
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              border: Border.all(
                color: color.withOpacity(0.5), // Inner ring
                width: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
