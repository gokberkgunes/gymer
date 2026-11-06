import 'package:flutter/material.dart';

import '../logic/achievements.dart';
import '../theme.dart';
import 'edition_card.dart';

IconData achievementIcon(AchievementKind kind) => switch (kind) {
  AchievementKind.workouts => Icons.emoji_events_outlined,
  AchievementKind.sets => Icons.layers_outlined,
  AchievementKind.weeks => Icons.local_fire_department_outlined,
  AchievementKind.load => Icons.fitness_center_rounded,
};

class AchievementEmblem extends StatelessWidget {
  final AchievementKind kind;
  final bool earned;
  const AchievementEmblem(this.kind, {super.key, this.earned = true});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: earned ? cs.primary.withValues(alpha: 0.10) : cs.surfaceContainerHigh,
        borderRadius: context.style.brSmall,
      ),
      child: Icon(achievementIcon(kind), size: 24, color: earned ? cs.primary : cs.onSurfaceVariant),
    );
  }
}

/// One quiet highlight, even when several milestones unlock in the same workout.
class AchievementUnlockCard extends StatelessWidget {
  final List<AchievementProgress> achievements;
  final String unit;
  final bool animate;
  final VoidCallback? onTap;
  const AchievementUnlockCard({
    super.key,
    required this.achievements,
    required this.unit,
    this.animate = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final first = achievements.first.achievement;
    final base = Color.alphaBlend(cs.primary.withValues(alpha: 0.06), cs.surface);
    final edition = editionOf(first);
    return TiltCard(
      builder: (context, tilt) => AchievementGlint(
        animate: animate,
        child: Material(
          color: base,
          borderRadius: context.style.br,
          child: CustomPaint(
            painter: EditionFoilPainter(edition, tilt, cs, context.style.br),
            child: InkWell(
              borderRadius: context.style.br,
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.all(context.style.sp(16)),
                child: Row(
                  children: [
                    AchievementEmblem(first.kind),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Achievement unlocked', style: t.labelMedium?.copyWith(color: cs.primary)),
                          const SizedBox(height: 4),
                          Text(first.title, style: t.titleMedium),
                          Text(first.goal(unit), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (achievements.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text('+${achievements.length - 1}', style: t.titleMedium?.copyWith(color: cs.primary)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single accent-light sweep. No repeating animation and no change to the layout.
class AchievementGlint extends StatefulWidget {
  final Widget child;
  final bool animate;
  const AchievementGlint({super.key, required this.child, this.animate = false});

  @override
  State<AchievementGlint> createState() => _AchievementGlintState();
}

class _AchievementGlintState extends State<AchievementGlint> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: context.style.br,
    child: AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => CustomPaint(
        foregroundPainter: _GlintPainter(_controller.value, Theme.of(context).colorScheme.primary),
        child: child,
      ),
    ),
  );
}

class _GlintPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _GlintPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final x = -size.width * 0.5 + size.width * 2 * Curves.easeInOut.transform(progress);
    final rect = Rect.fromLTWH(x, 0, size.width * 0.45, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_GlintPainter oldDelegate) => progress != oldDelegate.progress || color != oldDelegate.color;
}
