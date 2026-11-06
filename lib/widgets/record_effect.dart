import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A looping holographic finish for a completed personal-best set. Values and layout stay still.
class RecordEffect extends StatefulWidget {
  static const duration = Duration(milliseconds: 4200);
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
        final t = reducedMotion ? 0.9 : _controller.value; // 0.9 is the resting finish, without the sweep
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

/// A calm foil finish: one soft prismatic band glides across the tile, then it rests for a moment while a
/// thin colour-shifting edge keeps a faint life. Everything is drawn beneath the values, from theme colours.
class _RecordHologram extends CustomPainter {
  final double t;
  final ColorScheme colors;
  final BorderRadius radius;
  final bool outline;
  const _RecordHologram(this.t, this.colors, this.radius, this.outline);

  /// The sweep takes the first part of each cycle; the rest is a pause.
  static const _sweepShare = 0.38;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect);
    final sweep = (t / _sweepShare).clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(sweep);
    final glow = math.sin(sweep * math.pi); // 0 at rest, 1 mid-sweep
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);

    canvas.save();
    canvas.clipRRect(shape);
    // A faint resting foil so a record never looks plain between sweeps.
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.info.withValues(alpha: 0.07),
            colors.primary.withValues(alpha: 0.05),
            colors.success.withValues(alpha: 0.07),
          ],
        ).createShader(rect),
    );
    if (sweep > 0 && sweep < 1) {
      // A prismatic band, tilted by running the gradient along the diagonal of a wide rectangle.
      final bandWidth = size.width * 0.55;
      final x = -bandWidth + (size.width + bandWidth * 1.6) * eased;
      final band = Rect.fromLTWH(x, -size.height * 0.3, bandWidth, size.height * 1.6);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              colors.info.withValues(alpha: 0),
              colors.info.withValues(alpha: 0.22 * glow),
              colors.success.withValues(alpha: 0.26 * glow),
              colors.primary.withValues(alpha: 0.3 * glow),
              colors.primary.withValues(alpha: 0),
            ],
            stops: const [0, 0.28, 0.5, 0.72, 1],
          ).createShader(band),
      );
      // A narrow specular core riding in the middle of the band.
      final shine = colors.brightness == Brightness.dark ? colors.onSurface : colors.surface;
      final core = Rect.fromCenter(center: band.center, width: bandWidth * 0.16, height: band.height);
      canvas.drawRect(
        core,
        Paint()
          ..shader = LinearGradient(
            colors: [shine.withValues(alpha: 0), shine.withValues(alpha: 0.3 * glow), shine.withValues(alpha: 0)],
          ).createShader(core),
      );
      // One small four-point glint where the band crosses the tile.
      final centre = Offset(band.center.dx, size.height * 0.3);
      final arm = math.min(7.0, size.height * 0.22) * glow;
      final glint = Paint()
        ..color = shine.withValues(alpha: 0.7 * glow)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawLine(centre.translate(-arm, 0), centre.translate(arm, 0), glint)
        ..drawLine(centre.translate(0, -arm), centre.translate(0, arm), glint);
    }
    canvas.restore();
    if (outline) {
      canvas.drawRRect(
        shape.deflate(0.75),
        Paint()
          ..shader = SweepGradient(
            colors: [
              colors.primary.withValues(alpha: 0.28 + 0.2 * pulse),
              colors.info.withValues(alpha: 0.5),
              colors.success.withValues(alpha: 0.28 + 0.2 * pulse),
              colors.primary.withValues(alpha: 0.28 + 0.2 * pulse),
            ],
            transform: GradientRotation(t * math.pi * 2),
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25,
      );
    }
  }

  @override
  bool shouldRepaint(_RecordHologram old) =>
      t != old.t || colors != old.colors || radius != old.radius || outline != old.outline;
}
