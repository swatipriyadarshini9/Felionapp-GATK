import 'dart:math' as math;

import 'package:flutter/material.dart';

class DNAPainter extends CustomPainter {
  DNAPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (int i = 0; i < 25; i++) {
      final yPos = size.height * (i / 25);
      final angle = (yPos * 0.015) + (progress * math.pi * 2);
      final xOffset = math.sin(angle) * 50;
      canvas.drawCircle(Offset(size.width / 2 + xOffset, yPos), 3.0, paint);
      canvas.drawCircle(Offset(size.width / 2 - xOffset, yPos), 3.0, paint);
    }
  }

  @override
  bool shouldRepaint(DNAPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class GATKChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = Colors.blue.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path();
    final random = math.Random(42);
    path.moveTo(0, size.height * 0.8);
    for (double i = 0; i <= size.width; i += 10) {
      path.lineTo(i, size.height * 0.6 + (random.nextDouble() * 40));
    }
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
