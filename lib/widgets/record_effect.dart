import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'edition_card.dart';

/// A looping foil finish for a completed personal-best set, in the chosen [edition]: foil is a cool silver-blue
/// sheen, holographic a shifting blue-green-accent rainbow and polychrome a full-spectrum one. Values and layout
/// stay still.
class RecordEffect extends StatefulWidget {
  static const duration = Duration(milliseconds: 3200);
  final bool active;
  final bool enabled;
  final bool outline;
  final AchievementEdition edition;
  final BorderRadius? borderRadius;
  final Widget child;
  const RecordEffect({
    super.key,
    required this.active,
    required this.child,
    this.enabled = true,
    this.outline = true,
    this.edition = AchievementEdition.holographic,
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
    // The painter repaints itself from the controller; the row on top sits behind its own repaint boundary,
    // so its fields and icons are not redrawn on every frame of the shimmer. The tree stays the same when the
    // effect turns on or off, so fields keep their focus and editing state.
    return RepaintBoundary(
      child: CustomPaint(
        painter: widget.active && widget.enabled
            ? _RecordHologram(
                _controller,
                MediaQuery.disableAnimationsOf(context),
                cs,
                radius,
                widget.outline,
                widget.edition,
              )
            : null,
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}

class _RecordHologram extends CustomPainter {
  final Animation<double> motion;
  final bool reducedMotion;
  final ColorScheme colors;
  final BorderRadius radius;
  final bool outline;
  final AchievementEdition edition;
  _RecordHologram(this.motion, this.reducedMotion, this.colors, this.radius, this.outline, this.edition)
    : super(repaint: motion);

  @override
  void paint(Canvas canvas, Size size) {
    // Paint beneath the values so the stronger foil never washes out their contrast.
    final t = reducedMotion ? 0.4 : motion.value;
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect);
    final energy = 0.9 + 0.1 * math.cos(t * math.pi * 2);
    final travel = t;
    final palette = switch (edition) {
      AchievementEdition.foil => [colors.info, colors.onSurfaceVariant, colors.primary, colors.info],
      AchievementEdition.holographic => [colors.primary, colors.info, colors.success, colors.primary],
      AchievementEdition.polychrome => [
        colors.error,
        colors.warning,
        colors.success,
        colors.info,
        colors.primary,
        colors.error,
      ],
    };
    // How strongly each layer shows: foil is the quietest, polychrome the boldest.
    final strength = switch (edition) {
      AchievementEdition.foil => 0.6,
      AchievementEdition.holographic => 1.0,
      AchievementEdition.polychrome => 1.25,
    };
    canvas.save();
    canvas.clipRRect(shape);
    // A low iridescent wash under the travelling reflection. It is a still diagonal blend whose colours
    // drift slowly sideways (no spinning); every hue comes from the app theme.
    final drift = math.sin(t * math.pi * 2) * 0.4;
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-1 + drift, -1),
          end: Alignment(1 + drift, 1),
          colors: [for (final color in palette) color.withValues(alpha: 0.12 * strength * energy)],
        ).createShader(rect),
    );
    // The left-to-right travelling bands lean 20 degrees clockwise, rotated about the tile's centre.
    void leaning(void Function() draw) {
      canvas
        ..save()
        ..translate(size.width / 2, size.height / 2)
        ..rotate(20 * math.pi / 180)
        ..translate(-size.width / 2, -size.height / 2);
      draw();
      canvas.restore();
    }

    final cover = rect.inflate(size.longestSide); // the tile's clip limits what shows
    final band = Rect.fromLTWH(
      size.width * (travel * 3 - 1.8),
      -size.height * 0.35,
      size.width * 1.4,
      size.height * 1.7,
    );
    leaning(
      () => canvas.drawRect(
        cover,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primary.withValues(alpha: 0),
              colors.info.withValues(alpha: 0.24 * strength * energy),
              (edition == AchievementEdition.foil ? colors.info : colors.success).withValues(
                alpha: 0.34 * strength * energy,
              ),
              (edition == AchievementEdition.polychrome ? colors.warning : colors.primary).withValues(
                alpha: 0.42 * strength * energy,
              ),
              (edition == AchievementEdition.polychrome ? colors.error : colors.info).withValues(
                alpha: 0.24 * strength * energy,
              ),
              colors.primary.withValues(alpha: 0),
            ],
            stops: const [0, 0.22, 0.4, 0.58, 0.76, 1],
          ).createShader(band),
      ),
    );
    // Fine slanted striations give the moving colors a foil surface, rather than a flat tinted overlay.
    final lines = Paint()..strokeWidth = 0.7;
    var index = 0;
    for (double y = -size.height * 0.2; y < size.height * 1.2; y += 6) {
      lines.color = palette[index++ % palette.length].withValues(alpha: 0.08 * strength * energy);
      final offset = math.sin(t * math.pi * 2 + y * 0.02) * 2;
      canvas.drawLine(Offset(0, y + offset), Offset(size.width, y + offset - size.height * 0.12), lines);
    }
    final shine = colors.brightness == Brightness.dark ? colors.onSurface : colors.surface;
    final reflection = Rect.fromLTWH(
      size.width * (travel * 1.6 - 0.3),
      -size.height * 0.6,
      size.width * 0.28,
      size.height * 2.2,
    );
    leaning(
      () => canvas.drawRect(
        cover,
        Paint()
          ..shader = LinearGradient(
            colors: [
              shine.withValues(alpha: 0),
              shine.withValues(alpha: 0.2 * energy),
              shine.withValues(alpha: 0),
            ],
          ).createShader(reflection),
      ),
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
      motion != old.motion ||
      reducedMotion != old.reducedMotion ||
      colors != old.colors ||
      radius != old.radius ||
      outline != old.outline ||
      edition != old.edition;
}
