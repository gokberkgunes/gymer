import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The warm-up texture sits behind the entire exercise card, leaving set tiles and inputs solid.
class WarmupBackground extends StatefulWidget {
  final String style;
  final bool active;
  final Widget child;
  const WarmupBackground({super.key, required this.style, required this.child, this.active = true});

  @override
  State<WarmupBackground> createState() => _WarmupBackgroundState();
}

class _WarmupBackgroundState extends State<WarmupBackground> with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  void _sync() {
    if (widget.active && widget.style == 'fire' && !MediaQuery.disableAnimationsOf(context)) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant WarmupBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final CustomPainter? painter = !widget.active || widget.style == 'plain'
        ? null
        : widget.style == 'stripes'
        ? _WarmupStripes(
            cs.brightness == Brightness.light ? cs.surfaceContainerHigh : cs.onSurface.withValues(alpha: 0.03),
          )
        : _WarmupFire(_motion, cs, MediaQuery.disableAnimationsOf(context));
    // Only the background layer repaints while the flames move; the controls above it stay still.
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(child: CustomPaint(painter: painter)),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _WarmupFire extends CustomPainter {
  final Animation<double> motion;
  final ColorScheme colors;
  final bool reducedMotion;
  _WarmupFire(this.motion, this.colors, this.reducedMotion) : super(repaint: motion);

  Path _flame(double x, double bottom, double width, double height, double lean) => Path()
    ..moveTo(x - width * 0.5, bottom)
    ..cubicTo(
      x - width * 0.8,
      bottom - height * 0.25,
      x - width * 0.18,
      bottom - height * 0.4,
      x - width * 0.3,
      bottom - height * 0.62,
    )
    ..cubicTo(
      x - width * 0.12,
      bottom - height * 0.58,
      x - width * 0.06,
      bottom - height * 0.48,
      x + width * 0.1,
      bottom - height * 0.53,
    )
    ..cubicTo(
      x + width * 0.2,
      bottom - height * 0.72,
      x - width * 0.1,
      bottom - height * 0.8,
      x + lean,
      bottom - height,
    )
    ..cubicTo(
      x + width * 0.7,
      bottom - height * 0.75,
      x + width * 0.28,
      bottom - height * 0.5,
      x + width * 0.46,
      bottom - height * 0.35,
    )
    ..cubicTo(
      x + width * 0.72,
      bottom - height * 0.16,
      x + width * 0.65,
      bottom - height * 0.06,
      x + width * 0.5,
      bottom,
    )
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final phase = (reducedMotion ? 0.25 : motion.value) * math.pi * 2;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.warning.withValues(alpha: 0),
            colors.error.withValues(alpha: 0.025),
            colors.warning.withValues(alpha: 0.12),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
    // Broad, asymmetric tongues reach into the header and side margins instead of decorating the set rows.
    const tongues = [(0.03, 0.94, 0.3), (0.26, 0.7, 0.36), (0.52, 1.03, 0.4), (0.76, 0.78, 0.32), (0.97, 0.97, 0.3)];
    for (final (index, (position, reach, breadth)) in tongues.indexed) {
      final width = size.width * breadth;
      final height = size.height * reach * (1 + math.sin(phase + index * 1.4) * 0.045);
      final x = size.width * position;
      final lean = math.sin(phase + index * 1.1) * width * 0.2;
      final bottom = size.height * 1.06;
      canvas.drawPath(
        _flame(x, bottom, width, height, lean),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              colors.error.withValues(alpha: 0.06),
              colors.error.withValues(alpha: 0.13),
              colors.warning.withValues(alpha: 0.18),
            ],
          ).createShader(rect),
      );
      canvas.drawPath(
        _flame(x + width * 0.08, bottom, width * 0.62, height * 0.8, lean * 0.6),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [colors.warning.withValues(alpha: 0.04), colors.warning.withValues(alpha: 0.14)],
          ).createShader(rect),
      );
    }
    final ember = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5;
    for (var i = 0; i < 4; i++) {
      final progress = ((reducedMotion ? 0.25 : motion.value) + i * 0.27) % 1;
      final x = size.width * (i.isEven ? 0.035 : 0.965) + math.sin(phase + i) * 3;
      final y = size.height * (0.9 - progress * 0.75);
      ember.color = colors.warning.withValues(alpha: math.sin(progress * math.pi) * 0.35);
      canvas.drawLine(Offset(x, y), Offset(x + 1, y - 4), ember);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WarmupFire old) =>
      colors != old.colors || motion != old.motion || reducedMotion != old.reducedMotion;
}

class _WarmupStripes extends CustomPainter {
  final Color color;
  const _WarmupStripes(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = color
      ..strokeWidth = 8;
    for (double x = -size.height; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), ink);
    }
  }

  @override
  bool shouldRepaint(_WarmupStripes old) => color != old.color;
}
