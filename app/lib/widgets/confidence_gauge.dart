import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/signal_engine.dart';

/// Circular gauge widget displaying signal confidence (0-100)
class ConfidenceGauge extends StatelessWidget {
  final SignalResult signal;

  const ConfidenceGauge({Key? key, required this.signal}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Apply Sticky Zones (Hysteresis) to prevent label flickering
    String displayLabel;
    Color displayColor;
    
    if (signal.score > 65) {
      // BULLISH Zone (sticky threshold)
      displayLabel = "BULLISH";
      displayColor = const Color(0xFF00FF41); // Bright green
    } else if (signal.score < 35) {
      // BEARISH Zone (sticky threshold)
      displayLabel = "BEARISH";
      displayColor = const Color(0xFFFF0000); // Bright red
    } else {
      // NEUTRAL Zone (35-65)
      displayLabel = "NEUTRAL";
      displayColor = Colors.grey;
    }

    return Container(
      width: 140,
      height: 140,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0a0e27).withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: displayColor.withOpacity(0.4),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: displayColor.withOpacity(0.2),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Gauge
          SizedBox(
            width: 100,
            height: 100,
            child: CustomPaint(
              painter: _GaugePainter(
                score: signal.score,
                color: displayColor,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Score
                    Text(
                      '${signal.score}',
                      style: TextStyle(
                        color: displayColor,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    // Sticky Label
                    Text(
                      displayLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: displayColor.withOpacity(0.8),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Footer
          Text(
            'SIGNAL CONFIDENCE',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the circular gauge
class _GaugePainter extends CustomPainter {
  final int score;
  final Color color;

  _GaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Background arc (full circle, grey)
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Colored zones (Red → Grey → Green)
    _drawZone(canvas, center, radius, -135, 108, Colors.red.withOpacity(0.3)); // 0-40
    _drawZone(canvas, center, radius, -27, 54, Colors.grey.withOpacity(0.3));  // 40-60
    _drawZone(canvas, center, radius, 27, 108, Colors.green.withOpacity(0.3)); // 60-100

    // Progress arc (based on score)
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    // Convert score (0-100) to angle (-135° to 135°, total 270°)
    double sweepAngle = (score / 100) * 270;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _degreesToRadians(-135),
      _degreesToRadians(sweepAngle),
      false,
      progressPaint,
    );

    // Needle (pointing to current score)
    _drawNeedle(canvas, center, radius, score);
  }

  void _drawZone(Canvas canvas, Offset center, double radius, double startDeg, double sweepDeg, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _degreesToRadians(startDeg),
      _degreesToRadians(sweepDeg),
      false,
      paint,
    );
  }

  void _drawNeedle(Canvas canvas, Offset center, double radius, int score) {
    // Calculate needle angle (-135° to 135°)
    double angle = -135 + (score / 100 * 270);
    double angleRad = _degreesToRadians(angle);

    // Needle endpoint
    double needleLength = radius - 5;
    Offset needleEnd = Offset(
      center.dx + needleLength * math.cos(angleRad),
      center.dy + needleLength * math.sin(angleRad),
    );

    // Draw needle
    final needlePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, needleEnd, needlePaint);

    // Center dot
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 4, dotPaint);
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) {
    return oldDelegate.score != score || oldDelegate.color != color;
  }
}
