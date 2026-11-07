import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The Sketchify mark: a lens ring with a pencil stroke.
class SketchifyMark extends StatelessWidget {
  const SketchifyMark({super.key, this.size = 56, this.showGlow = true});

  final double size;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(showGlow: showGlow),
        isComplex: true,
        willChange: false,
      ),
    );
  }
}

class SketchifyWordmark extends StatelessWidget {
  const SketchifyWordmark({
    super.key,
    this.fontSize = 24,
    this.showTagline = false,
    this.alignment = CrossAxisAlignment.start,
  });

  final double fontSize;
  final bool showTagline;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        Text(
          'Sketchify',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.0,
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: 6),
          Text(
            'AI ANIME • SKETCH • TRACE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.6,
              fontSize: 9,
            ),
          ),
        ],
      ],
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.showGlow});

  final bool showGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.width * 0.28);
    final rounded = RRect.fromRectAndRadius(rect, radius);

    if (showGlow) {
      final glow = Paint()
        ..color = AppColors.primary.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(4, size.width * 0.22),
        );
      canvas.drawCircle(
        Offset(size.width * 0.52, size.height * 0.55),
        size.width * 0.36,
        glow,
      );
    }

    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          AppColors.primary,
          Color(0xFFFF9A62),
          AppColors.secondary,
        ],
        stops: <double>[0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rounded, fill);

    final lens = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.052
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.95);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.53),
      size.width * 0.215,
      lens,
    );

    final dot = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.53),
      size.width * 0.075,
      dot,
    );

    final pencil = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * 0.072
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.31, size.height * 0.72),
      Offset(size.width * 0.665, size.height * 0.345),
      pencil,
    );

    final tip = Paint()..color = const Color(0xFF2A1206);
    canvas.drawCircle(
      Offset(size.width * 0.705, size.height * 0.295),
      size.width * 0.042,
      tip,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.showGlow != showGlow;
}
