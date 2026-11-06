import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A looping holographic finish for a completed personal-best set. Values and layout stay still.
class RecordEffect extends StatefulWidget {
  static const duration = Duration(milliseconds: 3200);
  final bool active;
  final bool enabled;
  final bool outline;
  final BorderRadius? borderRadius;
  final Widget child;
  const RecordEffect({
    super.key,
    required this.active,
    required this.child,
    this.enabled = true,
    this.outline = true,
    this.borderRadius,
  });

  @override
  State<RecordEffect> createState() => _RecordEffectState();
}

class _RecordEffectState extends State<RecordEffect> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: RecordEffect.duration);

  void _sync() {
    if (!widget.enabled || !widget.active || MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RecordEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = widget.borderRadius ?? context.style.brSmall;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = reducedMotion ? 0.4 : _controller.value;
        // Paint beneath the values so the stronger foil never washes out their contrast.
        // Keep the tree stable when enabled or undone so fields retain their focus and editing state.
        return RepaintBoundary(
          child: CustomPaint(
            painter: widget.active && widget.enabled ? _RecordHologram(t, cs, radius, widget.outline) : null,
            child: child,
          ),
        );
      },
    );
  }
}

class _RecordHologram extends CustomPainter {
  final double t;
  final ColorScheme colors;
  final BorderRadius radius;
  final bool outline;
  const _RecordHologram(this.t, this.colors, this.radius, this.outline);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect);
    final energy = 0.9 + 0.1 * math.cos(t * math.pi * 2);
    final travel = t;
    final palette = [colors.primary, colors.info, colors.success, colors.primary];
    canvas.save();
    canvas.clipRRect(shape);
    // A low iridescent wash under the traveling foil reflection; every hue comes from the app theme.
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = SweepGradient(
          center: Alignment(0.2 * math.sin(t * math.pi * 2), -0.5),
          transform: GradientRotation(t * math.pi * 2),
          colors: [for (final color in palette) color.withValues(alpha: 0.14 * energy)],
        ).createShader(rect),
    );
    final band = Rect.fromLTWH(
      size.width * (travel * 3 - 1.8),
      -size.height * 0.35,
      size.width * 1.4,
      size.height * 1.7,
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: 0),
            colors.info.withValues(alpha: 0.24 * energy),
            colors.success.withValues(alpha: 0.34 * energy),
            colors.primary.withValues(alpha: 0.42 * energy),
            colors.info.withValues(alpha: 0.24 * energy),
            colors.primary.withValues(alpha: 0),
          ],
          stops: const [0, 0.22, 0.4, 0.58, 0.76, 1],
        ).createShader(band),
    );
    // Fine slanted striations give the moving colors a foil surface, rather than a flat tinted overlay.
    final lines = Paint()..strokeWidth = 0.7;
    var index = 0;
    for (double y = -size.height * 0.2; y < size.height * 1.2; y += 6) {
      lines.color = palette[index++ % palette.length].withValues(alpha: 0.08 * energy);
      final offset = math.sin(t * math.pi * 2 + y * 0.02) * 2;
      canvas.drawLine(Offset(0, y + offset), Offset(size.width, y + offset - size.height * 0.12), lines);
    }
    final shine = colors.brightness == Brightness.dark ? colors.onSurface : colors.surface;
    final reflection = Rect.fromLTWH(size.width * (travel * 1.6 - 0.3), 0, size.width * 0.28, size.height);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          colors: [
            shine.withValues(alpha: 0),
            shine.withValues(alpha: 0.2 * energy),
            shine.withValues(alpha: 0),
          ],
        ).createShader(reflection),
    );
    canvas.restore();
    if (outline) {
      canvas.drawRRect(
        shape.deflate(1),
        Paint()
          ..shader = SweepGradient(
            colors: [for (final color in palette) color.withValues(alpha: 0.85 * energy)],
            transform: GradientRotation(t * math.pi * 2),
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_RecordHologram old) =>
      t != old.t || colors != old.colors || radius != old.radius || outline != old.outline;
}
