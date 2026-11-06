import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Themes from the Flet app's celebrations.py.
const palettes = [
  [Color(0xFFFFCB4B), Color(0xFFFF6B81), Color(0xFF73D895), Color(0xFF72B9FF), Color(0xFFD39AFF)],
  [Color(0xFFFF7DAA), Color(0xFFFFD3E2), Color(0xFFF6A8FF), Color(0xFFC0A3FF), Color(0xFFFFE276)],
  [Color(0xFF8EE8FF), Color(0xFF55C6E8), Color(0xFF9CDBFF), Color(0xFFB6F8EA), Color(0xFFD8C8FF)],
  [Color(0xFFFFDD68), Color(0xFFFFAC42), Color(0xFFFF7060), Color(0xFFFFE9A6), Color(0xFFF58BDF)],
  [Color(0xFFB7F28E), Color(0xFF6CE2AE), Color(0xFF79D8C4), Color(0xFFF5E988), Color(0xFFD5B2FF)],
];

const setStyles = [
  ('Nailed it!', '✨', 0, 'burst'),
  ('So strong!', '💪', 3, 'fountain'),
  ('Shine on!', '⭐', 1, 'rain'),
  ('Crushed it!', '🔥', 3, 'sides'),
  ('Lovely work!', '💖', 1, 'burst'),
  ('Keep glowing!', '🌟', 2, 'fountain'),
  ('Yes you can!', '🙌', 4, 'sides'),
  ('Power up!', '⚡', 0, 'burst'),
  ('One more win!', '🏅', 3, 'rain'),
  ('Beautiful set!', '🌸', 1, 'rain'),
  ('You rock!', '🎸', 2, 'sides'),
  ('Magic!', '🪄', 1, 'fountain'),
  ('Pure power!', '💥', 3, 'burst'),
  ('High five!', '🖐️', 4, 'sides'),
  ('Brilliant!', '💎', 2, 'rain'),
  ('On a roll!', '🎈', 1, 'fountain'),
  ('Woohoo!', '🎉', 0, 'burst'),
  ('Look at you!', '🌈', 2, 'rain'),
  ('Superstar!', '🌟', 3, 'fountain'),
  ("That's a win!", '🏆', 4, 'sides'),
];

const workoutStyles = [
  ('You did it!', '🎉🎊💪🏆🔥⭐🥳🙌', 0),
  ('Absolutely blooming!', '🌸🌺🌷🌼🌻🦋💖✨', 1),
  ('Star of the show!', '🌟⭐✨💫🌙🚀🪐💎', 2),
  ("You're on fire!", '🔥⚡💥🏆🌟💪🎉🙌', 3),
  ('Pure magic!', '🪄✨🌈🦄💎🌟💖🎉', 1),
  ('Victory parade!', '🏆🏅🎖️👑🎉🎊🙌💪', 3),
  ('Happy dance!', '💃🎶🎵🪩🎉🥳✨💖', 1),
  ('Superhero energy!', '🦸💪⚡💥🏆🔥🌟🙌', 0),
  ("You're a gem!", '💎💖✨🌟👑🦋🎉💜', 2),
  ('Sunshine champion!', '☀️🌻🌼🌈✨💛🎉🙌', 3),
  ('Cosmic strength!', '🚀🪐🌙⭐🌟💫💪✨', 2),
  ('A little sparkle!', '✨💖🌟🦋🌸💎🎀🎉', 1),
  ('Legendary work!', '👑🏆🔥💪⚡🎊🌟🙌', 3),
  ('Confetti queen!', '👑🎉🎊💖🥳✨🌟🎈', 1),
  ('A whole vibe!', '🪩💃🌈🎶✨💖🎉🔥', 0),
  ('Fantastic finish!', '🎯🏆💪🌟🎉⚡🙌🥳', 4),
  ('You made waves!', '🌊🐬🫧🐚💙✨🌟🎉', 2),
  ('Garden of gains!', '🌱🌿🌷🌼🦋🐝💪✨', 4),
  ('Sweet victory!', '🍓🍒🍭🧁💖🎉✨🏆', 1),
  ('To the moon!', '🌙🚀⭐🪐💫🌟💪🎊', 2),
  ('Pawsome work!', '🐈🐕🐾🐱🐶🦴🎾💖', 1),
];

final _rng = math.Random();
final _lastStyle = <String, int>{};

/// Random style index, never the same as the previous one of this kind.
int pickStyle(String kind, int count) {
  final previous = _lastStyle[kind];
  final choices = [
    for (var i = 0; i < count; i++)
      if (i != previous) i,
  ];
  return _lastStyle[kind] = choices[_rng.nextInt(choices.length)];
}

/// Emoji with presentation selectors kept attached.
List<String> _symbols(String text) {
  final out = <String>[];
  for (final r in text.runes) {
    final ch = String.fromCharCode(r);
    if (r == 0xFE0F && out.isNotEmpty) {
      out.last += ch;
    } else {
      out.add(ch);
    }
  }
  return out;
}

class _Particle {
  final Offset from, to;
  final double size, spin, rotation;
  final Color color;
  final String? emoji;
  final double start, end; // fractions of the animation
  final bool round;
  _Particle({
    required this.from,
    required this.to,
    required this.size,
    required this.spin,
    required this.rotation,
    required this.color,
    this.emoji,
    this.start = 0,
    this.end = 1,
    this.round = false,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  final bool fade;
  _ParticlePainter(this.particles, this.t, {this.fade = true});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (t < p.start || t > p.end) continue;
      final local = ((t - p.start) / (p.end - p.start)).clamp(0.0, 1.0);
      final eased = Curves.easeOut.transform(local);
      final pos = Offset.lerp(p.from, p.to, p.emoji != null && !fade ? local : eased)!;
      final opacity = fade ? (local < 0.7 ? 1.0 : (1 - (local - 0.7) / 0.3)).clamp(0.0, 1.0) : 1.0;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.rotation + p.spin * local);
      if (p.emoji != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: p.emoji,
            style: TextStyle(fontSize: p.size * 0.85),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: opacity));
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      } else {
        final paint = Paint()..color = p.color.withValues(alpha: opacity);
        final rect = Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * (p.round ? 1 : 1.5));
        p.round ? canvas.drawOval(rect, paint) : canvas.drawRect(rect, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}

/// Brief non-interactive confetti for one completed set. Plays whenever
/// [trigger] increases.
class SetConfetti extends StatefulWidget {
  final int trigger;
  const SetConfetti({super.key, required this.trigger});

  @override
  State<SetConfetti> createState() => _SetConfettiState();
}

class _SetConfettiState extends State<SetConfetti> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1250));
  List<_Particle> _particles = const [];

  @override
  void didUpdateWidget(covariant SetConfetti old) {
    super.didUpdateWidget(old);
    if (widget.trigger > old.trigger) _play();
  }

  void _play() {
    final size = MediaQuery.sizeOf(context);
    final (_, emoji, palette, motion) = setStyles[pickStyle('set', setStyles.length)];
    final colors = palettes[palette];
    final w = size.width, h = size.height;
    final origin = h - 60;
    _particles = [
      for (var i = 0; i < 13 + _rng.nextInt(9); i++)
        () {
          final isEmoji = i % 5 == 0;
          final s = isEmoji ? 19.0 : 4 + _rng.nextDouble() * 3;
          var x = w / 2 + (_rng.nextDouble() * 20 - 10);
          var y = origin - _rng.nextDouble() * 12;
          var rise = 110 + _rng.nextDouble() * 150;
          var tx = w / 2 + (_rng.nextDouble() * 270 - 135);
          switch (motion) {
            case 'rain':
              x = _rng.nextDouble() * (w - s);
              y = origin - 300 - _rng.nextDouble() * 80;
              rise = -(220 + _rng.nextDouble() * 80);
              tx = x + (_rng.nextDouble() * 0.3 - 0.15) * w;
            case 'sides':
              x = i.isEven ? 0 : w - s;
              y = origin - _rng.nextDouble() * 40;
              rise = 80 + _rng.nextDouble() * 140;
              tx = w * (0.2 + _rng.nextDouble() * 0.6);
            case 'fountain':
              rise = 180 + _rng.nextDouble() * 140;
          }
          return _Particle(
            from: Offset(x, y),
            to: Offset(tx.clamp(0, w), y - rise),
            size: s,
            spin: _rng.nextDouble() * 8 - 4,
            rotation: _rng.nextDouble() * math.pi * 2,
            color: colors[_rng.nextInt(colors.length)],
            emoji: isEmoji ? emoji : null,
          );
        }(),
    ];
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => _c.isAnimating
          ? CustomPaint(size: Size.infinite, painter: _ParticlePainter(_particles, _c.value))
          : const SizedBox.expand(),
    ),
  );
}

/// The finish-workout celebration: a continuous emoji shower with confetti
/// jets firing in three waves, and a banner with the style's message.
class WorkoutCelebration extends StatefulWidget {
  /// Index into [workoutStyles]; random (never repeating) when null.
  final int? style;
  final int trigger;
  final String? headline;
  const WorkoutCelebration({super.key, this.style, this.trigger = 0, this.headline});

  @override
  State<WorkoutCelebration> createState() => _WorkoutCelebrationState();
}

class _WorkoutCelebrationState extends State<WorkoutCelebration> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 6000));
  List<_Particle> _particles = const [];
  String _message = '';
  Color _border = Colors.white;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void didUpdateWidget(covariant WorkoutCelebration old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger) _play();
  }

  void _play() {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final w = size.width, h = size.height;
    final index = widget.style ?? pickStyle('workout', workoutStyles.length);
    final (message, emojiText, palette) = workoutStyles[index];
    final colors = palettes[palette];
    final pattern = index % 4;
    final emojis = [for (var k = 0; k < 8; k++) ..._symbols(emojiText)]..shuffle(_rng);
    final particles = <_Particle>[
      for (final e in emojis)
        () {
          final s = 38 + _rng.nextDouble() * 12;
          final x = _rng.nextDouble() * (w - s);
          final y = -s - _rng.nextDouble() * h * 1.6;
          return _Particle(
            from: Offset(x, y),
            to: Offset((x + _rng.nextDouble() * 100 - 50).clamp(0, w), y + h * 2.8 + s),
            size: s,
            spin: _rng.nextDouble() - 0.5,
            rotation: _rng.nextDouble() * 0.6 - 0.3,
            color: Colors.white,
            emoji: e,
          );
        }(),
      for (var k = 0; k < 36; k++)
        () {
          final s = 5 + _rng.nextDouble() * 6;
          final x = _rng.nextDouble() * (w - s);
          final y = -s - _rng.nextDouble() * h * 1.6;
          return _Particle(
            from: Offset(x, y),
            to: Offset(x, y + h * 2.8),
            size: s,
            spin: _rng.nextDouble() * 10 - 5,
            rotation: _rng.nextDouble() * math.pi * 2,
            color: colors[_rng.nextInt(colors.length)],
            round: pattern == 1,
          );
        }(),
      for (var wave = 0; wave < 3; wave++)
        for (var k = 0; k < 36; k++)
          () {
            final side = k % 3;
            final s = 5 + _rng.nextDouble() * 5;
            final x = side == 0 ? -s : (side == 1 ? w : w * (0.2 + _rng.nextDouble() * 0.6));
            final y = side < 2 ? h * (0.35 + _rng.nextDouble() * 0.45) : h;
            final (lo, hi) = side < 2
                ? (pattern == 0
                      ? (0.15, 0.85)
                      : pattern == 1
                      ? (0.35, 0.65)
                      : side == 0
                      ? (0.55, 0.95)
                      : (0.05, 0.45))
                : (0.0, 1.0);
            final tx = side < 2 ? w * (lo + _rng.nextDouble() * (hi - lo)) : (x + (_rng.nextDouble() * 0.6 - 0.3) * w);
            final ty = h * ((pattern == 3 ? 0.25 : 0.05) + _rng.nextDouble() * (pattern == 3 ? 0.25 : 0.45));
            return _Particle(
              from: Offset(x, y),
              to: Offset(tx.clamp(0, w), ty),
              size: s,
              spin: _rng.nextDouble() * 8 - 4,
              rotation: _rng.nextDouble() * math.pi * 2,
              color: colors[_rng.nextInt(colors.length)],
              start: wave * 0.33,
              end: wave * 0.33 + 0.33,
            );
          }(),
    ];
    setState(() {
      _particles = particles;
      _message = widget.headline ?? message;
      _border = colors.first;
    });
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (!_c.isAnimating) return const SizedBox.expand();
        final t = _c.value;
        final shower = _particles.where((p) => p.start == 0 && p.end == 1).toList();
        final jets = _particles.where((p) => !(p.start == 0 && p.end == 1)).toList();
        return Stack(
          children: [
            CustomPaint(size: Size.infinite, painter: _ParticlePainter(shower, t, fade: false)),
            CustomPaint(size: Size.infinite, painter: _ParticlePainter(jets, t)),
            // Below the status bar and camera cutout, over the top of the page (the "Workout complete" title).
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              left: 0,
              right: 0,
              child: Center(
                child: Opacity(
                  opacity: t > 0.92 ? (1 - (t - 0.92) / 0.08) : 1,
                  child: Container(
                    width: 230,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF263044),
                      border: Border.all(color: _border, width: 2),
                    ),
                    child: Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
