import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sniper_terminal/models/signal.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';

class SonarDisplay extends StatefulWidget {
  const SonarDisplay({super.key});

  @override
  State<SonarDisplay> createState() => _SonarDisplayState();
}

class _SonarDisplayState extends State<SonarDisplay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Continuous animation for time decay updates (60fps)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10), // Cycle duration doesn't matter much if we use Tick
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SniperState>(
      builder: (context, state, child) {
        // FILTER: Hard Volume Filter > $100k (score is volume)
        // Also limit to last 10 seconds of history for "Time Decay" relevance
        final now = DateTime.now().millisecondsSinceEpoch;
        final relevantSignals = state.signalHistory.where((s) {
          final age = now - s.timestamp;
          if (age > 10000) return false; // > 10s old
          // return s.symbol == state.selectedCoin && s.score >= 100000;
          return s.symbol == state.selectedCoin; // Let painter handle visual filter if needed, but for perf better filter here
        }).where((s) => s.score >= 100000).toList();

        // Sort by volume descending for Z-ordering (Smallest on top? No, user said largest bubbles labels. Painter can sort for drawing order)
        // Drawing order: Largest first drawn means smallest drawn on top? YES.
        relevantSignals.sort((a, b) => b.score.compareTo(a.score));

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          decoration: const BoxDecoration(
            color: Colors.black, // Solid Black 100%
          ),
          child: RepaintBoundary( // Performance Optimization
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: _TacticalSonarPainter(
                    signals: relevantSignals,
                    now: DateTime.now().millisecondsSinceEpoch,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _TacticalSonarPainter extends CustomPainter {
  final List<Signal> signals;
  final int now;

  _TacticalSonarPainter({required this.signals, required this.now});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Grid (Minimalist: 5 thin horizontal grey lines)
    final gridPaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Calculate Price Range
    double minPrice = double.infinity;
    double maxPrice = double.negativeInfinity;

    if (signals.isNotEmpty) {
        // Use all signals to determine range, even if faded
        for (var s in signals) {
            if (s.price < minPrice) minPrice = s.price;
            if (s.price > maxPrice) maxPrice = s.price;
        }
    } else {
        // Fallback range if empty (center on something reasonable or just 0-100)
        minPrice = 0;
        maxPrice = 100;
    }

    // Expanding range slightly (padding)
    final range = maxPrice - minPrice;
    final padding = range == 0 ? (maxPrice * 0.005) : (range * 0.1);
    final safeMin = minPrice - padding;
    final safeMax = maxPrice + padding;
    final safeRange = safeMax - safeMin;

    // Draw 5 lines
    for (int i = 1; i < 5; i++) {
        final y = size.height * (i / 5);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 2. Process Bubbles
    // Need to identify Top 3 largest VISIBLE bubbles for labels
    // Sort signals by Volume Descending for "Top 3" logic
    // But for drawing, we might want to draw largest first so smaller ones appear on top?
    // Actually, usually smaller on top is better to verify overlapping.
    // The list passed is already sorted DESC by scale.
    // So signals[0] is the largest.

    // MAGNET INDICATOR (Largest current bubble)
    Signal? magnetSignal;
    if (signals.isNotEmpty) {
        magnetSignal = signals.first; // Largest
    }

    // Draw Magnet Line FIRST (Behind bubbles? or Top?)
    // "draw a very thin, dashed horizontal line... at its price level."
    if (magnetSignal != null) {
        final magnetY = _getY(magnetSignal.price, safeMin, safeRange, size.height);
        final magnetPaint = Paint()
            ..color = (magnetSignal.side == "LONG" || magnetSignal.side == "BUY" ? Colors.greenAccent : Colors.redAccent).withOpacity(0.5)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke;

        _drawDashedLine(canvas, magnetPaint, Offset(0, magnetY), Offset(size.width, magnetY));
    }

    // Draw Bubbles
    // We reverse list to draw Smallest LAST (On Top)?
    // signals is SORTED DESC. signals[0] is HUGE. signals[last] is SMALL.
    // If we iterate normal, HUGE is drawn FIRST. SMALL is drawn LAST (On Top). -> GOOD.
    
    int labelCount = 0;
    
    for (int i = 0; i < signals.length; i++) {
        final signal = signals[i];
        
        // Decay Logic
        final age = now - signal.timestamp;
        final maxAge = 10000; // 10s
        if (age > maxAge) continue;

        // Opacity: Linear 1.0 -> 0.0
        double opacity = 1.0 - (age / maxAge);
        opacity = opacity.clamp(0.0, 1.0);
        
        // X Position: Enter Right, Drift Left.
        // xNorm = 1.0 (Right) -> 0.0 (Left)
        final xNorm = 1.0 - (age / maxAge);
        final x = size.width * xNorm;
        
        // Y Position
        double y = _getY(signal.price, safeMin, safeRange, size.height);
        
        // --- JITTER / SPREAD LOGIC ---
        // For high-frequency coins (SOL), signals often stack at exact same Price/Time.
        // specific deterministic jitter based on ID hash.
        final int hash = signal.id.hashCode;
        // Jitter Y (Vertical/Price) by +/- 15 pixels max
        final double yJitter = (hash % 30) - 15.0; 
        // Jitter X (Time) by +/- 15 pixels max
        final double xJitter = ((hash >> 1) % 30) - 15.0;

        y += yJitter;
        // Apply X jitter but keep within bounds?
        // Actually X jitter might make recent signals look "future". 
        // Only apply negative X jitter? No, spread is fine.
        double visualX = x + xJitter;

        // Radius (Area Scaling) -> Area = Volume similar. Radius = sqrt(Volume).
        // Max Radius = 60px.
        // Reference: $1M order should look 2x larger than $250k.
        // sqrt(1M) = 1000. sqrt(250k) = 500. Correct (2x radius -> 4x area).
        // Let's normalize. Max typical volume ~5M?
        const double baseScale = 0.05; // Tunable
        double radius = sqrt(signal.score) * baseScale;
        radius = radius.clamp(4.0, 60.0); // Cap at 60px

        // Color
        final isLong = signal.side == "LONG" || signal.side == "BUY";
        final color = isLong ? Colors.greenAccent : Colors.redAccent;

        // Archetypes
        final paint = Paint()
            ..color = color.withOpacity(opacity);

        if (signal.type == 'ICEBERG') {
             // Hollow Neon Circle
             paint.style = PaintingStyle.stroke;
             paint.strokeWidth = 2;
             canvas.drawCircle(Offset(visualX, y), radius, paint);
        } else if (signal.type == 'LIQUIDATION') {
             // Glow / Bloom
             // Draw Bloom
             final glowPaint = Paint()
                ..color = color.withOpacity(opacity * 0.5)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
             canvas.drawCircle(Offset(visualX, y), radius + 10, glowPaint);
             
             // Core
             paint.style = PaintingStyle.fill;
             paint.color = Colors.white.withOpacity(opacity);
             canvas.drawCircle(Offset(visualX, y), radius, paint);
             
             // Ring
             final ringPaint = Paint()
                ..color = color.withOpacity(opacity)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2;
             canvas.drawCircle(Offset(visualX, y), radius, ringPaint);
        } else {
             // Standard Whale (Solid)
             paint.style = PaintingStyle.fill;
             canvas.drawCircle(Offset(visualX, y), radius, paint);
        }

        // Labels: Top 3 only
        // Since list is sorted by Volume, the first 3 (that are visible/opaque enough) can be labeled.
        if (i < 3 && opacity > 0.3) {
             final textSpan = TextSpan(
                text: "\$${signal.price.toStringAsFixed(0)}",
                style: GoogleFonts.robotoMono(
                    color: Colors.white.withOpacity(opacity),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                ),
             );
             final textPainter = TextPainter(
                text: textSpan,
                textDirection: TextDirection.ltr,
             );
             textPainter.layout();
             // Center inside or right below
             textPainter.paint(canvas, Offset(visualX - textPainter.width/2, y - textPainter.height/2));
        }
    }
  }

  double _getY(double price, double min, double range, double height) {
      if (range == 0) return height / 2;
      final norm = (price - min) / range;
      return height * (1.0 - norm); // Invert
  }

  void _drawDashedLine(Canvas canvas, Paint paint, Offset p1, Offset p2) {
      const dashWidth = 5.0;
      const dashSpace = 5.0;
      double startX = p1.dx;
      while (startX < p2.dx) {
          canvas.drawLine(Offset(startX, p1.dy), Offset(startX + dashWidth, p1.dy), paint);
          startX += dashWidth + dashSpace;
      }
  }

  @override
  bool shouldRepaint(covariant _TacticalSonarPainter oldDelegate) {
    return oldDelegate.now != now || oldDelegate.signals != signals;
  }
}
