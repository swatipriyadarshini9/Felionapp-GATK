import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Circular Circos-style genome plot of called variants.
class CircosPlot extends StatelessWidget {
  const CircosPlot({
    super.key,
    required this.variants,
    this.height = 280,
  });

  final List<dynamic> variants;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade900, width: 2),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CustomPaint(
                painter: CircosPainter(variants: variants),
              ),
            ),
          ),
          const Positioned(
            top: 12,
            left: 14,
            child: Text(
              'CIRCOS // VARIANT MAP',
              style: TextStyle(
                color: Colors.blueAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 14,
            right: 14,
            child: _Legend(variants: variants),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.variants});

  final List<dynamic> variants;

  @override
  Widget build(BuildContext context) {
    final chroms = <String>{};
    for (final v in variants) {
      final c = (v as Map)['chromosome']?.toString() ?? '?';
      chroms.add(_normalizeChrom(c));
    }
    final list = chroms.toList()..sort(_chromCompare);
    if (list.isEmpty) {
      return const Text(
        'No variants',
        style: TextStyle(color: Colors.white54, fontSize: 10),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: list.take(8).map((c) {
        final alarming = c.contains('10');
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: alarming ? Colors.redAccent : Colors.cyanAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'chr$c',
              style: const TextStyle(color: Colors.white70, fontSize: 9),
            ),
          ],
        );
      }).toList(),
    );
  }
}

String _normalizeChrom(String raw) {
  return raw.replaceFirst(RegExp(r'^chr', caseSensitive: false), '');
}

int _chromCompare(String a, String b) {
  final ai = int.tryParse(a);
  final bi = int.tryParse(b);
  if (ai != null && bi != null) return ai.compareTo(bi);
  if (ai != null) return -1;
  if (bi != null) return 1;
  return a.compareTo(b);
}

class CircosPainter extends CustomPainter {
  CircosPainter({required this.variants});

  final List<dynamic> variants;

  // Approximate human chromosome lengths (Mb) for layout proportions.
  static const Map<String, double> _chromLengthsMb = {
    '1': 249,
    '2': 242,
    '3': 198,
    '4': 190,
    '5': 182,
    '6': 171,
    '7': 159,
    '8': 145,
    '9': 138,
    '10': 134,
    '11': 135,
    '12': 133,
    '13': 114,
    '14': 107,
    '15': 102,
    '16': 90,
    '17': 83,
    '18': 80,
    '19': 59,
    '20': 64,
    '21': 47,
    '22': 51,
    'X': 156,
    'Y': 57,
    'M': 0.017,
    'MT': 0.017,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 8);
    final radius = math.min(size.width, size.height) / 2 - 28;

    final ringPaint = Paint()
      ..color = Colors.blueGrey.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;

    canvas.drawCircle(center, radius, ringPaint);

    final chromSet = <String>{};
    for (final v in variants) {
      chromSet.add(_normalizeChrom((v as Map)['chromosome']?.toString() ?? '?'));
    }
    var chroms = chromSet.toList()..sort(_chromCompare);
    if (chroms.isEmpty) {
      chroms = ['1', '2', '3', '4', '5', '10', '17', 'X'];
    }

    double totalWeight = 0;
    for (final c in chroms) {
      totalWeight += _chromLengthsMb[c] ?? 80;
    }

    final gap = 0.02;
    final usable = (2 * math.pi) - (gap * chroms.length);
    double angle = -math.pi / 2;

    final segments = <_ChromSegment>[];
    for (final c in chroms) {
      final weight = _chromLengthsMb[c] ?? 80;
      final sweep = usable * (weight / totalWeight);
      segments.add(_ChromSegment(c, angle, sweep, weight * 1e6));
      final alarming = c.contains('10');
      final paint = Paint()
        ..color = alarming
            ? Colors.redAccent.withValues(alpha: 0.85)
            : Colors.cyan.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        sweep,
        false,
        paint,
      );

      // Label
      final mid = angle + sweep / 2;
      final labelR = radius + 22;
      final lp = Offset(
        center.dx + math.cos(mid) * labelR,
        center.dy + math.sin(mid) * labelR,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: c,
          style: TextStyle(
            color: alarming ? Colors.redAccent : Colors.white70,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, lp - Offset(tp.width / 2, tp.height / 2));

      angle += sweep + gap;
    }

    // Inner guide ring
    canvas.drawCircle(
      center,
      radius * 0.72,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Plot variants as radial ticks / dots
    for (final raw in variants) {
      final map = Map<String, dynamic>.from(raw as Map);
      final chrom = _normalizeChrom(map['chromosome']?.toString() ?? '');
      _ChromSegment? seg;
      for (final s in segments) {
        if (s.chrom == chrom) {
          seg = s;
          break;
        }
      }
      if (seg == null) continue;

      final pos = map['position'] is int
          ? (map['position'] as int).toDouble()
          : double.tryParse('${map['position']}') ?? 0;
      final frac = (pos / seg.lengthBp).clamp(0.0, 1.0);
      final a = seg.start + seg.sweep * frac;
      final alarming = chrom.contains('10');

      final outer = Offset(
        center.dx + math.cos(a) * (radius - 8),
        center.dy + math.sin(a) * (radius - 8),
      );
      final inner = Offset(
        center.dx + math.cos(a) * (radius * 0.55),
        center.dy + math.sin(a) * (radius * 0.55),
      );

      canvas.drawLine(
        outer,
        inner,
        Paint()
          ..color = alarming
              ? Colors.redAccent.withValues(alpha: 0.9)
              : Colors.lightBlueAccent.withValues(alpha: 0.7)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(
        inner,
        alarming ? 3.5 : 2.5,
        Paint()
          ..color = alarming ? Colors.redAccent : Colors.cyanAccent,
      );
    }

    // Center hub
    canvas.drawCircle(
      center,
      18,
      Paint()..color = const Color(0xFF16213E),
    );
    final hub = TextPainter(
      text: TextSpan(
        text: '${variants.length}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hub.paint(canvas, center - Offset(hub.width / 2, hub.height / 2));
  }

  @override
  bool shouldRepaint(CircosPainter oldDelegate) =>
      oldDelegate.variants != variants;
}

class _ChromSegment {
  _ChromSegment(this.chrom, this.start, this.sweep, this.lengthBp);

  final String chrom;
  final double start;
  final double sweep;
  final double lengthBp;
}
