import 'dart:math' as math;
import 'package:flutter/material.dart';

class TrendSpeedometer extends StatelessWidget {
  final double velocity; // 0-100

  const TrendSpeedometer({
    super.key,
    required this.velocity,
  });

  @override
  Widget build(BuildContext context) {
    // Determine Zone
    String label = "CREEPING";
    Color color = Colors.blueGrey;
    if (velocity > 70) {
      label = "🔥 HOT";
      color = const Color(0xFFFF4500); // OrangeRed
    } else if (velocity > 30) {
      label = "WALKING";
      color = Colors.amber;
    }

    return Container(
      width: 140, 
      height: 70, // Half circle roughly
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Background Arc
          CustomPaint(
            size: const Size(140, 70),
            painter: SpeedometerPainter(velocity: velocity, color: color),
          ),
          
          // Label
          Positioned(
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 Text(
                  velocity.toStringAsFixed(0),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class SpeedometerPainter extends CustomPainter {
  final double velocity;
  final Color color;

  SpeedometerPainter({required this.velocity, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    // Background Track (Grey)
    paint.color = Colors.white.withOpacity(0.1);
    canvas.drawArc(rect, math.pi, math.pi, false, paint);

    // Active Arc
    paint.color = color;
    // Map 0-100 to 0-PI
    final sweepAngle = (velocity / 100).clamp(0.0, 1.0) * math.pi;
    canvas.drawArc(rect, math.pi, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter oldDelegate) {
    return oldDelegate.velocity != velocity || oldDelegate.color != color;
  }
}
