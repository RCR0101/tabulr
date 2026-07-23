import 'package:flutter/material.dart';
import '../../models/cgpa_data.dart';

/// SGPA-per-semester bars with the cumulative CGPA drawn as a line on top, on a
/// shared 0–10 grade scale. An optional [targetCgpa] adds a dashed goal line.
///
/// Self-contained CustomPaint (no charting dependency); colours are resolved
/// from the theme by the widget and handed to the painter.
class CgpaTrajectoryChart extends StatelessWidget {
  const CgpaTrajectoryChart({
    super.key,
    required this.points,
    this.targetCgpa,
    this.height = 240,
  });

  final List<CgpaTrajectoryPoint> points;
  final double? targetCgpa;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Add graded semesters to see your trajectory.',
              style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.5))),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _TrajectoryPainter(
          points: points,
          targetCgpa: targetCgpa,
          barColor: scheme.primary.withValues(alpha: 0.28),
          barTopColor: scheme.primary.withValues(alpha: 0.55),
          lineColor: scheme.tertiary,
          dotColor: scheme.tertiary,
          gridColor: scheme.onSurface.withValues(alpha: 0.08),
          axisTextColor: scheme.onSurface.withValues(alpha: 0.55),
          valueTextColor: scheme.onSurface.withValues(alpha: 0.8),
          targetColor: scheme.error,
        ),
      ),
    );
  }
}

class _TrajectoryPainter extends CustomPainter {
  _TrajectoryPainter({
    required this.points,
    required this.targetCgpa,
    required this.barColor,
    required this.barTopColor,
    required this.lineColor,
    required this.dotColor,
    required this.gridColor,
    required this.axisTextColor,
    required this.valueTextColor,
    required this.targetColor,
  });

  final List<CgpaTrajectoryPoint> points;
  final double? targetCgpa;
  final Color barColor;
  final Color barTopColor;
  final Color lineColor;
  final Color dotColor;
  final Color gridColor;
  final Color axisTextColor;
  final Color valueTextColor;
  final Color targetColor;

  static const double _maxScale = 10.0;
  static const double _topPad = 18;
  static const double _bottomPad = 34;
  static const double _leftPad = 26;

  @override
  void paint(Canvas canvas, Size size) {
    final chartH = size.height - _topPad - _bottomPad;
    final chartW = size.width - _leftPad;
    if (chartH <= 0 || chartW <= 0) return;

    double yFor(double v) => _topPad + chartH * (1 - v / _maxScale);

    // Gridlines + left labels at 0/2/4/6/8/10.
    final gridPaint = Paint()..color = gridColor..strokeWidth = 1;
    for (var g = 0; g <= 10; g += 2) {
      final y = yFor(g.toDouble());
      canvas.drawLine(Offset(_leftPad, y), Offset(size.width, y), gridPaint);
      _text(canvas, '$g', Offset(0, y - 6), axisTextColor, 9, align: TextAlign.left, width: _leftPad - 4);
    }

    final slot = chartW / points.length;
    final barW = (slot * 0.5).clamp(6.0, 40.0);

    // SGPA bars.
    for (var i = 0; i < points.length; i++) {
      final cx = _leftPad + slot * (i + 0.5);
      final top = yFor(points[i].sgpa);
      canvas.drawRect(
          Rect.fromLTRB(cx - barW / 2, top, cx + barW / 2, yFor(0)),
          Paint()..color = barColor);
      // A brighter cap so the bar top reads clearly against the fill.
      canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(cx - barW / 2, top, cx + barW / 2, top + 3),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()..color = barTopColor);
      // Semester label.
      _text(canvas, _shortSem(points[i].semester),
          Offset(cx - slot / 2, size.height - _bottomPad + 6), axisTextColor, 9,
          align: TextAlign.center, width: slot);
      _text(canvas, points[i].sgpa.toStringAsFixed(2),
          Offset(cx - slot / 2, size.height - _bottomPad + 18), axisTextColor, 8,
          align: TextAlign.center, width: slot);
    }

    // Target line (dashed).
    if (targetCgpa != null && targetCgpa! > 0 && targetCgpa! <= _maxScale) {
      final y = yFor(targetCgpa!);
      final p = Paint()
        ..color = targetColor.withValues(alpha: 0.8)
        ..strokeWidth = 1.5;
      const dash = 6.0, gap = 4.0;
      var x = _leftPad;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width), y), p);
        x += dash + gap;
      }
      _text(canvas, 'target ${targetCgpa!.toStringAsFixed(2)}',
          Offset(_leftPad + 2, y - 12), targetColor, 9,
          align: TextAlign.left, width: chartW);
    }

    // Cumulative CGPA line + dots + values.
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    final centers = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final cx = _leftPad + slot * (i + 0.5);
      final o = Offset(cx, yFor(points[i].cumulativeCgpa));
      centers.add(o);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(path, linePaint);
    for (var i = 0; i < centers.length; i++) {
      canvas.drawCircle(centers[i], 4, Paint()..color = dotColor);
      canvas.drawCircle(centers[i], 4, Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4);
      _text(canvas, points[i].cumulativeCgpa.toStringAsFixed(2),
          Offset(centers[i].dx - 18, centers[i].dy - 16), valueTextColor, 9,
          align: TextAlign.center, width: 36);
    }
  }

  void _text(Canvas canvas, String s, Offset at, Color color, double size,
      {TextAlign align = TextAlign.left, double width = 40}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w500)),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final dx = align == TextAlign.center
        ? at.dx + (width - tp.width) / 2
        : at.dx;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  static String _shortSem(String s) => s.replaceAll(' ', '');

  @override
  bool shouldRepaint(_TrajectoryPainter old) =>
      old.points != points || old.targetCgpa != targetCgpa;
}
