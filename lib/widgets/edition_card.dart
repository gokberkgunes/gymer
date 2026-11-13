import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/achievements.dart';
import '../theme.dart';

/// Card finishes for achievements: the first third of each ladder is foil, the middle holographic and
/// the top polychrome.
enum AchievementEdition {
  foil('Foil'),
  holographic('Holographic'),
  polychrome('Polychrome');

  final String label;
  const AchievementEdition(this.label);
}

/// The edition saved in settings ('foil', 'holographic' or 'polychrome'); holographic when unknown.
AchievementEdition editionNamed(String name) =>
    AchievementEdition.values.where((e) => e.name == name).firstOrNull ?? AchievementEdition.holographic;

AchievementEdition editionOf(Achievement a) {
  final ladder = achievements.where((x) => x.kind == a.kind).toList();
  final index = math.max(0, ladder.indexWhere((x) => x.id == a.id));
  return AchievementEdition.values[(index * 3 ~/ ladder.length).clamp(0, 2)];
}

/// Follows a finger or mouse across the card with a slight 3D tilt and eases back on release.
/// Pointer events are only observed, so scrolling and taps behave as before. Reduced motion keeps it flat.
class TiltCard extends StatefulWidget {
  final Widget Function(BuildContext context, Offset tilt) builder;
  const TiltCard({super.key, required this.builder});

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))
    ..addListener(
      () => setState(() => _tilt = Offset.lerp(_from, Offset.zero, Curves.easeOutBack.transform(_back.value))!),
    );
  Offset _tilt = Offset.zero;
  Offset _from = Offset.zero;

  @override
  void initState() {
    super.initState();
    // Created now, not on first use: a card that was never touched would otherwise build its ticker inside
    // dispose, after the widget has left the tree.
    _back.value = 0;
  }

  void _move(PointerEvent e) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty || MediaQuery.disableAnimationsOf(context)) return;
    _back.stop();
    setState(
      () => _tilt = Offset(
        (e.localPosition.dx / box.size.width * 2 - 1).clamp(-1.0, 1.0),
        (e.localPosition.dy / box.size.height * 2 - 1).clamp(-1.0, 1.0),
      ),
    );
  }

  void _end(PointerEvent e) {
    _from = _tilt;
    if (_tilt != Offset.zero) _back.forward(from: 0);
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _move,
    onPointerMove: _move,
    onPointerUp: _end,
    onPointerCancel: _end,
    child: Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0014)
        ..rotateX(-_tilt.dy * 0.2)
        ..rotateY(_tilt.dx * 0.2),
      child: widget.builder(context, _tilt),
    ),
  );
}

/// The edition's finish, painted beneath the card's content. [tilt] (-1..1 on each axis) moves the light.
class EditionFoilPainter extends CustomPainter {
  final AchievementEdition edition;
  final Offset tilt;
  final ColorScheme colors;
  final BorderRadius radius;
  final Animation<double>? idle;

  /// With [idle] (a looping 0..1), the light glides back and forth on its own while nothing is touching the card.
  const EditionFoilPainter(this.edition, this.tilt, this.colors, this.radius, {this.idle}) : super(repaint: idle);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect);
    final tilt = this.tilt == Offset.zero && idle != null
        ? Offset(math.sin(idle!.value * math.pi * 2) * 0.9, 0)
        : this.tilt;
    final pos = (0.5 + tilt.dx * 0.5 + tilt.dy * 0.2).clamp(0.0, 1.0);
    final palette = switch (edition) {
      AchievementEdition.foil => [colors.primary, colors.onSurfaceVariant, colors.primary],
      AchievementEdition.holographic => [colors.info, colors.success, colors.primary, colors.info],
      AchievementEdition.polychrome => [
        colors.error,
        colors.warning,
        colors.success,
        colors.info,
        colors.primary,
        colors.error,
      ],
    };
    final wash = switch (edition) {
      AchievementEdition.foil => 0.05,
      AchievementEdition.holographic => 0.11,
      AchievementEdition.polychrome => 0.16,
    };
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = SweepGradient(
          center: Alignment(tilt.dx * 0.6, tilt.dy * 0.6),
          transform: GradientRotation(pos * math.pi * 2),
          colors: [for (final c in palette) c.withValues(alpha: wash)],
        ).createShader(rect),
    );
    final lines = Paint()..strokeWidth = 0.7;
    var index = 0;
    for (double y = -size.height * 0.2; y < size.height * 1.2; y += 6) {
      lines.color = palette[index++ % palette.length].withValues(alpha: wash * 0.7);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - size.height * 0.12), lines);
    }
    final shine = colors.brightness == Brightness.dark ? colors.onSurface : colors.surface;
    final band = Rect.fromLTWH(size.width * (pos * 1.7 - 0.6), 0, size.width * 0.5, size.height);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [shine.withValues(alpha: 0), shine.withValues(alpha: 0.22), shine.withValues(alpha: 0)],
        ).createShader(band),
    );
    canvas.restore();
    canvas.drawRRect(
      shape.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edition == AchievementEdition.polychrome ? 1.5 : 1
        ..shader = SweepGradient(
          transform: GradientRotation(pos * math.pi * 2),
          colors: [for (final c in palette) c.withValues(alpha: edition == AchievementEdition.foil ? 0.4 : 0.65)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(EditionFoilPainter old) =>
      idle != old.idle || edition != old.edition || tilt != old.tilt || colors != old.colors || radius != old.radius;
}

/// Supplies a looping 0..1 phase to [builder] (null with reduced motion, so cards rest still).
class LoopingPhase extends StatefulWidget {
  final Duration period;
  final Widget Function(BuildContext context, Animation<double>? phase) builder;
  const LoopingPhase({super.key, this.period = const Duration(seconds: 6), required this.builder});

  @override
  State<LoopingPhase> createState() => _LoopingPhaseState();
}

class _LoopingPhaseState extends State<LoopingPhase> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, MediaQuery.disableAnimationsOf(context) ? null : _controller);
}
