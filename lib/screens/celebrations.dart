import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/achievements.dart';
import '../theme.dart';
import '../widgets/achievement.dart';
import '../widgets/edition_card.dart';
import '../widgets/celebration.dart';
import '../widgets/common.dart';
import '../widgets/num_field.dart';
import '../widgets/record_effect.dart';
import '../logic/numbers.dart';
import '../store.dart';

/// A completed personal-best set in the chosen style, always playing.
class RecordSetPreview extends StatelessWidget {
  const RecordSetPreview({super.key});

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: RecordEffect(
      active: true,
      enabled: StoreScope.of(context).settings.recordEffects,
      edition: editionNamed(StoreScope.of(context).settings.recordEffectStyle),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: IgnorePointer(
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Icon(Icons.emoji_events_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
              ),
              Expanded(
                flex: 10,
                child: NumField(
                  value: 105,
                  kind: NumKind.weight,
                  completed: true,
                  align: TextAlign.center,
                  onChanged: (_) {},
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 7,
                child: NumField(
                  value: 8,
                  kind: NumKind.reps,
                  completed: true,
                  align: TextAlign.center,
                  onChanged: (_) {},
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 7,
                child: NumField(
                  value: 2,
                  kind: NumKind.rir,
                  completed: true,
                  align: TextAlign.center,
                  onChanged: (_) {},
                ),
              ),
              SizedBox(
                width: 44,
                child: Icon(Icons.check_rounded, size: 24, color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Preview the set confetti and every workout celebration style.
class CelebrationsPreview extends StatefulWidget {
  const CelebrationsPreview({super.key});

  @override
  State<CelebrationsPreview> createState() => _CelebrationsPreviewState();
}

class _CelebrationsPreviewState extends State<CelebrationsPreview> {
  int _set = 0, _workout = 0;
  int? _style;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Celebration styles')),
    body: Stack(
      children: [
        ListView(
          padding: subPageInsets,
          children: [
            const SectionLabel('Personal best · preview'),
            const RecordSetPreview(),
            const SectionLabel('Set and workout'),
            FilledButton(onPressed: () => setState(() => _set++), child: const Text('Preview set celebration')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() {
                _style = null;
                _workout++;
              }),
              child: const Text('Preview random workout celebration'),
            ),
            const SectionLabel('Workout styles'),
            for (final (i, (message, emojis, _)) in workoutStyles.indexed)
              ListTile(
                title: Text(message),
                subtitle: Text(emojis),
                onTap: () => setState(() {
                  _style = i;
                  _workout++;
                }),
              ),
          ],
        ),
        Positioned.fill(child: SetConfetti(trigger: _set)),
        if (_workout > 0)
          Positioned.fill(
            child: WorkoutCelebration(style: _style, trigger: _workout),
          ),
      ],
    ),
  );
}

class CelebrationSettings extends StatefulWidget {
  const CelebrationSettings({super.key});

  @override
  State<CelebrationSettings> createState() => CelebrationSettingsState();
}

class CelebrationSettingsState extends State<CelebrationSettings> {
  int _preview = 0;
  Timer? _loop;

  @override
  void initState() {
    super.initState();
    // The previews replay on their own, so there is nothing to press.
    _preview = 1;
    _loop = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _preview++);
    });
  }

  @override
  void dispose() {
    _loop?.cancel();
    super.dispose();
  }

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
              const SectionLabel('Milestones'),
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
                const SectionLabel('Milestone · preview'),
                IgnorePointer(
                  child: AchievementUnlockCard(
                    key: ValueKey((_preview, s.achievementCelebration)),
                    achievements: [AchievementProgress(achievements[1], 10, earnedAt: DateTime.now())],
                    unit: s.unit,
                    animate: s.achievementCelebration == 'glow',
                  ),
                ),
              ],
              const SectionLabel('During training'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Personal-best effects'),
                      subtitle: const Text('Foil shimmer on record sets'),
                      value: s.recordEffects,
                      onChanged: (v) => store.updateSettings((x) => x.recordEffects = v),
                    ),
                    if (s.recordEffects)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            for (final e in AchievementEdition.values)
                              ButtonSegment(value: e.name, label: Text(e.label)),
                          ],
                          selected: {s.recordEffectStyle},
                          onSelectionChanged: (v) => store.updateSettings((x) => x.recordEffectStyle = v.first),
                        ),
                      ),
                    const Divider(indent: 16, endIndent: 16),
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
                          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CelebrationsPreview())),
                    ),
                  ],
                ),
              ),
              if (s.recordEffects) ...[const SectionLabel('Personal best · preview'), const RecordSetPreview()],
            ],
          ),
          if (s.achievementCelebration == 'confetti' && !reducedMotion)
            Positioned.fill(
              child: WorkoutCelebration(key: ValueKey(_preview), headline: 'Achievement unlocked'),
            ),
        ],
      ),
    );
  }
}
