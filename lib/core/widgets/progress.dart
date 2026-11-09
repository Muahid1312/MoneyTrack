import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Animated rounded linear progress with optional gradient fill.
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 10,
    this.trackColor,
  });

  /// 0..1 (values above 1 are clamped visually).
  final double value;
  final Color color;
  final double height;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: AppDurations.chart,
      curve: AppCurves.emphasized,
      builder: (context, v, _) => Container(
        height: height,
        decoration: BoxDecoration(
          color: trackColor ?? p.chartTrack,
          borderRadius: BorderRadius.circular(height),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height),
              gradient: LinearGradient(colors: [
                Color.lerp(color, Colors.white, 0.18)!,
                color,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated circular ring with rounded caps.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 160,
    this.stroke = 14,
    this.trackColor,
    this.child,
  });

  final double value;
  final Color color;
  final double size;
  final double stroke;
  final Color? trackColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final track = trackColor ?? context.palette.chartTrack;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: AppCurves.emphasized,
      builder: (context, v, child) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, color, track, stroke),
          child: Center(child: child),
        ),
      ),
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track, this.stroke);
  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final sweep = math.pi * 2 * value;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: const GradientRotation(-math.pi / 2),
        colors: [Color.lerp(color, Colors.white, 0.25)!, color, Color.lerp(color, Colors.white, 0.25)!],
        stops: [0, value.clamp(0.05, 1.0), 1],
      ).createShader(rect);
    canvas.drawArc(r, -math.pi / 2, sweep, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Colour for a budget usage ratio.
Color budgetColor(BuildContext context, double ratio) {
  final p = context.palette;
  if (ratio > 1) return p.expense;
  if (ratio >= 0.8) return p.warning;
  return AppColors.emerald;
}
