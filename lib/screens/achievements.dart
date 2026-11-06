import 'package:flutter/material.dart';

import '../logic/achievements.dart';
import '../theme.dart';
import '../widgets/achievement.dart';
import '../widgets/celebration.dart';
import '../widgets/common.dart';
import 'celebrations.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final progress = achievementProgress(store.history);
    final earned = progress.where((p) => p.earned).length;
    final visible = switch (_filter) {
      'earned' => progress.where((p) => p.earned).toList()..sort((a, b) => b.earnedAt!.compareTo(a.earnedAt!)),
      'next' => [
        for (final kind in AchievementKind.values)
          ...progress.where((p) => p.achievement.kind == kind && !p.earned).take(1),
      ]..sort((a, b) => b.fraction.compareTo(a.fraction)),
      _ => progress,
    };
    return Scaffold(
      appBar: AppBar(
        title: LabelWithInfo(
          const Text('Achievements', maxLines: 1, overflow: TextOverflow.ellipsis),
          InfoDot(
            tooltip: 'About achievements',
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Every session adds up'),
                content: const Text(
                  'Your saved workout history counts, including imported workouts. Warm-ups are excluded. '
                  'Tap a milestone to see its goal. Older achievements are collected quietly; new ones can celebrate when you finish a workout.',
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Got it'))],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Celebration settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _CelebrationSettings())),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YOUR COLLECTION', style: t.labelSmall),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$earned',
                        style: t.displaySmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular),
                      ),
                      const SizedBox(width: 8),
                      Text('/ ${progress.length} earned', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: earned / progress.length,
                    minHeight: 4,
                    borderRadius: context.style.brSmall,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('All')),
                        ButtonSegment(value: 'earned', label: Text('Earned')),
                        ButtonSegment(value: 'next', label: Text('Next')),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (v) => setState(() => _filter = v.first),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _filter == 'next' ? 'Every milestone earned. Nicely done.' : 'Your first milestone is ahead.',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            SliverPadding(
              padding: subPageInsets,
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  final columns = (constraints.crossAxisExtent / (156 * scale.clamp(1, 1.5))).floor().clamp(1, 4);
                  return SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 224 + (context.style.sp(32) - 32).clamp(0, 16) + (scale - 1).clamp(0, 2) * 100,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, i) => _AchievementTile(visible[i], unit: store.settings.unit),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final AchievementProgress progress;
  final String unit;
  const _AchievementTile(this.progress, {required this.unit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final a = progress.achievement;
    return Semantics(
      button: true,
      label: '${a.title}, ${a.goal(unit)}, ${progress.earned ? 'earned' : progress.progress(unit)}',
      child: Material(
        color: progress.earned ? Color.alphaBlend(cs.primary.withValues(alpha: 0.035), cs.surface) : cs.surface,
        borderRadius: context.style.br,
        child: InkWell(
          borderRadius: context.style.br,
          onTap: () => _details(context, progress, unit),
          child: Padding(
            padding: EdgeInsets.all(context.style.sp(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AchievementEmblem(a.kind, earned: progress.earned),
                    Icon(
                      progress.earned ? Icons.check_rounded : Icons.lock_outline_rounded,
                      size: 16,
                      color: progress.earned ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(a.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  a.goal(unit),
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                if (progress.earned)
                  Text(fmtShortDate(progress.earnedAt!.toLocal()), style: t.labelMedium?.copyWith(color: cs.primary))
                else ...[
                  Text(
                    progress.progress(unit),
                    style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 3,
                    borderRadius: context.style.brSmall,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _details(BuildContext context, AchievementProgress progress, String unit) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: Row(
      children: [
        AchievementEmblem(progress.achievement.kind, earned: progress.earned),
        const SizedBox(width: 12),
        Expanded(child: Text(progress.achievement.title)),
      ],
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(progress.achievement.goal(unit), style: Theme.of(c).textTheme.titleMedium),
        const SizedBox(height: 12),
        Text(progress.achievement.explanation),
        const SizedBox(height: 16),
        Text(
          progress.earned
              ? 'Earned ${fmtShortDate(progress.earnedAt!.toLocal())} ${progress.earnedAt!.toLocal().year}'
              : progress.progress(unit),
        ),
      ],
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
  ),
);

class _CelebrationSettings extends StatefulWidget {
  const _CelebrationSettings();

  @override
  State<_CelebrationSettings> createState() => _CelebrationSettingsState();
}

class _CelebrationSettingsState extends State<_CelebrationSettings> {
  int _preview = 0;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Celebrations')),
      body: Stack(
        children: [
          ListView(
            padding: subPageInsets,
            children: [
              const SectionLabel('Achievements'),
              Card(
                child: Padding(
                  padding: EdgeInsets.all(context.style.sp(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LabelWithInfo(
                        Text('Milestone moment', style: t.bodyLarge),
                        InfoDot(
                          tooltip: 'When achievements celebrate',
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Milestone moment'),
                              content: const Text(
                                'New milestones appear after you finish a workout, once per achievement. '
                                'Off keeps your collection and progress without the finish-screen highlight. '
                                'Imported history never replays celebrations.',
                              ),
                              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Got it'))],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'glow', label: Text('Glow')),
                          ButtonSegment(value: 'confetti', label: Text('Confetti')),
                          ButtonSegment(value: 'off', label: Text('Off')),
                        ],
                        selected: {s.achievementCelebration},
                        onSelectionChanged: (v) => store.updateSettings((x) => x.achievementCelebration = v.first),
                      ),
                      const SizedBox(height: 8),
                      Text(switch (s.achievementCelebration) {
                        'glow' => 'A soft sweep of light over your milestone.',
                        'confetti' => 'A milestone highlight with a confetti shower.',
                        _ => 'Collect quietly.',
                      }, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              if (s.achievementCelebration != 'off') ...[
                SectionLabel(
                  'Preview',
                  trailing: IconButton(
                    tooltip: 'Preview milestone',
                    onPressed: () => setState(() => _preview++),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                ),
                // A neutral, muted sample, distinct from the interactive settings above it.
                ColorFiltered(
                  colorFilter: const ColorFilter.matrix([
                    0.40,
                    0.50,
                    0.10,
                    0,
                    0,
                    0.35,
                    0.48,
                    0.10,
                    0,
                    0,
                    0.30,
                    0.42,
                    0.10,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0.82,
                    0,
                  ]),
                  child: IgnorePointer(
                    child: AchievementUnlockCard(
                      key: ValueKey((_preview, s.achievementCelebration)),
                      achievements: [AchievementProgress(achievements[1], 10, earnedAt: DateTime.now())],
                      unit: s.unit,
                      animate: _preview > 0 && s.achievementCelebration == 'glow',
                    ),
                  ),
                ),
              ],
              const SectionLabel('During training'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Set confetti'),
                      value: s.setCelebrations,
                      onChanged: (v) => store.updateSettings((x) => x.setCelebrations = v),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('Workout celebration'),
                      value: s.workoutCelebrations,
                      onChanged: (v) => store.updateSettings((x) => x.workoutCelebrations = v),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      title: const Text('Explore celebration styles'),
                      trailing: const Icon(Icons.play_arrow_rounded, size: 20),
                      onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const CelebrationsPreview())),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_preview > 0 && s.achievementCelebration == 'confetti' && !reducedMotion)
            Positioned.fill(
              child: WorkoutCelebration(key: ValueKey(_preview), headline: 'Achievement unlocked'),
            ),
        ],
      ),
    );
  }
}
