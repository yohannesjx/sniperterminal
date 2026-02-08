import 'dart:math';
import 'package:flutter/material.dart';

class EntryGauge extends StatelessWidget {
  final double score; // 0.0 to 100.0 (100 = Perfect, 0 = Bad)

  const EntryGauge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      width: 200,
      child: CustomPaint(
        painter: _GaugePainter(score: score),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${score.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Orbitron', // Assuming font is available globally
                  ),
                ),
                Text(
                  _getStatusText(score),
                  style: TextStyle(
                    color: _getStatusColor(score),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Orbitron',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getStatusText(double score) {
    if (score >= 80) return 'PERFECT ENTRY';
    if (score >= 50) return 'CAUTION';
    return 'OVEREXTENDED';
  }

  Color _getStatusColor(double score) {
    if (score >= 80) return Colors.greenAccent;
    if (score >= 50) return Colors.yellowAccent;
    return Colors.redAccent;
  }
}

class _GaugePainter extends CustomPainter {
  final double score;

  _GaugePainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2;

    // 1. Draw Background Arc (The Track)
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;

    // Red Zone (Left/Bottom - Low Score?) 
    // Wait, High Score = Perfect. So Right = Green?
    // Let's say: 
    // Left (0%) = Red. 
    // Middle (50%) = Yellow.
    // Right (100%) = Green.

    // Draw Red Section
    trackPaint.color = Colors.redAccent.withOpacity(0.3);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi, // Start at 180 degrees (Left)
      pi / 3, // 60 degrees slice
      false,
      trackPaint,
    );

    // Draw Yellow Section
    trackPaint.color = Colors.yellowAccent.withOpacity(0.3);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi + (pi / 3),
      pi / 3,
      false,
      trackPaint,
    );

    // Draw Green Section
    trackPaint.color = Colors.greenAccent.withOpacity(0.3);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi + (2 * pi / 3),
      pi / 3,
      false,
      trackPaint,
    );

    // 2. Draw Active Gauge Indicator (Needle or Fill)
    // Let's use a needle approach for precision
    final needleAngle = pi + (score / 100) * pi; // Map 0-100 to pi-2pi
    
    final needlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final needleEnd = Offset(
      center.dx + (radius - 10) * cos(needleAngle),
      center.dy + (radius - 10) * sin(needleAngle),
    );

    canvas.drawLine(center, needleEnd, needlePaint);
    
    // Draw Pivot
    canvas.drawCircle(center, 8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.score != score;
  }
}
