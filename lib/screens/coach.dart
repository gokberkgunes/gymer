import 'package:flutter/material.dart';

import '../logic/bodyweight.dart';
import '../logic/coach.dart';
import '../logic/cycle.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'cycle.dart';

/// Weekly sets per muscle with the coach's reading of the log: an arrow per muscle, and inside a mesocycle the
/// set changes it would make this week.
class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final report = store.coachReport();
    final volume = report.volume;
    final setsLabel = report.planned ? 'Planned weekly sets' : 'Weekly sets, last 4 weeks';
    final names = [
      ...rpLandmarks.keys,
      for (final m in volume.keys)
        if (!rpLandmarks.containsKey(m)) m,
    ];
    double sets(String muscle) =>
        volume[muscle]?.countedSets(includePartialSets: store.settings.includePartialSets) ?? 0;
    // Falling muscles already answered by a set change are not listed twice.
    final suggested = {for (final s in report.suggestions) s.muscle};
    final changes = [
      for (final v in report.declining)
        if (!suggested.contains(v.muscle)) v,
      ...report.rising,
    ];
    return ListView(
      padding: pageInsets,
      children: [
        PageHeader(
          'Coach',
          info: InfoDot(tooltip: 'How the coach reads your log', onTap: () => _coachInfo(context)),
          // The eating phase is told to the coach here; it changes how readily sets are added or removed.
          trailing: report.cycle != null && report.cycle == store.activeCycle
              ? TextButton(
                  style: TextButton.styleFrom(minimumSize: compactButton),
                  onPressed: () => _dietDialog(context),
                  child: Text(_dietLabels[report.cycle!.diet] ?? 'Gaining'),
                )
              : null,
        ),
        if (report.suggestions.isNotEmpty || report.deload.isNotEmpty) ...[
          SectionLabel('This ${report.cycle?.periodNoun() ?? 'week'}'),
          Card(
            child: Column(
              children: [
                if (report.deload.isNotEmpty)
                  _DeloadRow(falling: report.deload, cycle: report.cycle!, atHigh: report.deloadAtHigh),
                for (final (i, s) in report.suggestions.indexed) ...[
                  if (i > 0 || report.deload.isNotEmpty) const Divider(indent: 16, endIndent: 16),
                  _SuggestionRow(suggestion: s, zone: volumeZone(s.muscle, sets(s.muscle))),
                ],
              ],
            ),
          ),
        ],
        if (changes.isNotEmpty) ...[
          SectionLabel(report.sincePrevious ? 'Since last mesocycle' : 'Biggest changes'),
          Card(
            child: Column(
              children: [
                for (final (i, v) in changes.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  _TrendRow(verdict: v, sets: sets(v.muscle), setsLabel: setsLabel),
                ],
              ],
            ),
          ),
        ],
        SectionLabel(report.planned ? 'Weekly sets' : 'Weekly sets, last 4 weeks'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in names)
                  MuscleVolumeRow(
                    muscle: m,
                    sets: sets(m),
                    goal: report.cycle?.muscleGoals[m],
                    personal: report.personal[m],
                    feel: report.feel[m],
                    changes: report.changeLog[m] ?? const [],
                    goalEditable: report.cycle != null && report.cycle == store.activeCycle,
                    performed: report.performed == null
                        ? null
                        : report.performed![m]?.countedSets(includePartialSets: store.settings.includePartialSets) ?? 0,
                    frequency: volume[m]?.directDaysPerWeek ?? 0,
                    verdict: report.verdicts[m],
                    setsLabel: setsLabel,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The early-deload hint: most judged muscles fell, so the answer is a deload, not fewer sets one by one.
class _DeloadRow extends StatelessWidget {
  final List<MuscleVerdict> falling;
  final Mesocycle cycle;
  final bool atHigh;
  const _DeloadRow({required this.falling, required this.cycle, required this.atHigh});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final period = cycle.periodNoun();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LabelWithInfo(
                  Text('Deload now', style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  InfoDot(
                    tooltip: 'Why',
                    onTap: () => showInfoSections(context, 'Deload now', [
                      (
                        '',
                        'Last $period ${falling.map((v) => '${v.muscle} (${fmtTrend(v.percent)})').join(', ')} fell. '
                            '${atHigh ? 'It was also your highest total of hard sets in any week so far. ' : ''}'
                            'That points to fatigue across the whole body rather than too many sets for one muscle.',
                      ),
                      (
                        'Start',
                        'The deload begins in this $period and the mesocycle ends that much earlier. Workouts '
                            'already done this $period stay as they are. Dismiss hides this for the $period and '
                            'brings back the set changes.',
                      ),
                    ]),
                  ),
                ),
                Text(
                  '${falling.length} muscles falling',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: compactButton),
            onPressed: store.dismissDeloadHint,
            child: const Text('Dismiss'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: compactButton),
            onPressed: () async {
              final ok = await confirm(
                context,
                'Start the deload now?',
                'The deload begins in this $period and the mesocycle ends earlier. You can change the length again '
                    'in the cycle settings.',
                action: 'Start deload',
              );
              if (ok) store.startDeloadNow();
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

/// "Chest +1 set" with its target beneath, the reason behind (i), and Apply (or Undo once applied).
class _SuggestionRow extends StatelessWidget {
  final SetSuggestion suggestion;
  final String? zone;
  const _SuggestionRow({required this.suggestion, required this.zone});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final s = suggestion;
    final change = s.delta == 0 ? s.note : '${s.delta > 0 ? '+' : '−'}${s.delta.abs()} set';
    final color = s.delta == 0
        ? cs.info
        : s.delta > 0
        ? cs.success
        : cs.warning;
    final workout = store.template(s.templateId)?.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LabelWithInfo(
                  Text(s.muscle, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  InfoDot(
                    tooltip: 'Why',
                    onTap: () => showInfoSections(context, '${s.muscle} $change', [('', s.reason)]),
                  ),
                ),
                Text(
                  [if (s.exercise.isNotEmpty) s.exercise, ?workout, ?zone].join(' · '),
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            change,
            style: t.titleMedium?.copyWith(color: color, fontFeatures: tabular),
          ),
          if (s.delta != 0) const SizedBox(width: 12),
          if (s.delta == 0)
            const SizedBox.shrink()
          else if (s.applied == null)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: compactButton),
              onPressed: () => store.applySuggestion(s),
              child: const Text('Apply'),
            )
          else
            TextButton(
              style: TextButton.styleFrom(minimumSize: compactButton),
              onPressed: () => store.undoSuggestion(s),
              child: const Text('Undo'),
            ),
        ],
      ),
    );
  }
}

/// A falling or rising muscle: its volume zone beneath the name, the change at the right, details behind (i).
class _TrendRow extends StatelessWidget {
  final MuscleVerdict verdict;
  final double sets;
  final String setsLabel;
  const _TrendRow({required this.verdict, required this.sets, required this.setsLabel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final v = verdict;
    final zone = volumeZone(v.muscle, sets);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LabelWithInfo(
                  Text(v.muscle, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  InfoDot(
                    tooltip: 'Details',
                    onTap: () => showLandmarkInfo(context, v.muscle, sets: sets, setsLabel: setsLabel, verdict: v),
                  ),
                ),
                Text(
                  [?zone, '${fmtSets(sets)} sets'].join(' · '),
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            fmtTrend(v.percent),
            style: t.titleMedium?.copyWith(color: trendColor(cs, v.trend), fontFeatures: tabular),
          ),
        ],
      ),
    );
  }
}

const _dietLabels = {'': 'Gaining', 'maintain': 'Maintaining', 'cut': 'Cutting'};

void _dietDialog(BuildContext context) {
  final store = StoreScope.read(context);
  final unit = store.settings.unit;
  final rate = store.settings.trackBodyweight
      ? bodyweightWeeklyRate(bodyweightTrend(store.bodyweights, unit), DateTime.now())
      : null;
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Eating phase'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatefulBuilder(
              builder: (c, setDiet) => SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
                    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                  ),
                  segments: [for (final e in _dietLabels.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                  selected: {store.activeCycle?.diet ?? ''},
                  onSelectionChanged: (v) => setDiet(() => store.setDiet(v.first)),
                ),
              ),
            ),
            if (rate != null) ...[
              const SizedBox(height: 12),
              Text(
                'Bodyweight trend: ${rate.abs() < 0.05 ? 'steady' : '${rate > 0 ? '+' : '−'}${rate.abs().toStringAsFixed(1)} $unit a week'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Recovery depends on how much you eat, so the coach should know.\n\n'
              'Gaining: normal coaching.\n\n'
              'Maintaining: a set is added only after two flat weeks, never sooner.\n\n'
              'Cutting: the aim is to keep strength. No sets are added, holding counts as success, and a flat '
              'week with poor sleep or a run-down day already takes a set away.\n\n'
              'Kept for this mesocycle and carried into the next one.',
            ),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}

void _coachInfo(BuildContext context) => showInfoSections(context, 'How the coach reads your log', const [
  (
    'Arrows',
    'The size of change that counts (1 % by default) follows Coach sensitivity in Settings → Advanced. '
        'Each exercise is compared with the same exercise in the same workout one week (or microcycle) earlier. '
        'Straight sets are compared set by set, by estimated 1RM so reps in reserve count, or by load × reps if '
        'you choose that in Settings → Advanced. Other set methods are always compared by total volume. Up means '
        'progressing, flat holding, down falling. Only external loads with the same logging context are compared; '
        'deloads and warm-ups never are. A muscle needs two comparable workouts before it gets an arrow. Tap a '
        'muscle for the exercises.',
  ),
  (
    'Your own range',
    'Once a muscle has been judged in two finished mesocycles, a thin line under its bar runs from the fewest '
        'weekly sets at which it progressed to the fewest at which it then fell. It stays open to the right until '
        'that has happened. The landmark zones above it are general references; the line is yours.',
  ),
  (
    'Rep drop-off',
    'When the last set of an exercise gets under 60 % of the first set\'s reps at the same load, two weeks '
        'running, its later sets are low quality. The coach never adds a set there and says so in the reason; a '
        'longer rest usually helps more.',
  ),
  (
    'Special set methods',
    'Drop sets, myo-reps, rest-pause and clusters are counted in straight-set equivalents so every muscle sits '
        'on the same scale. The activation set counts as one set and each myo-set, rest-pause segment or drop '
        'after it as half a set, up to three sets per group. A cluster group counts as one set. In trials, one '
        'drop-set group of an opening set and three or four drops grew muscle like three straight sets, and '
        'cluster sets matched straight sets one for one. These are estimates from small studies.',
  ),
  (
    'Planned and done',
    'Inside a mesocycle the thin mark on each bar is the plan and the solid mark is what you have completed so '
        'far this week, so a skipped or shortened workout shows as a muscle falling behind.',
  ),
  (
    'Set changes',
    'Inside a mesocycle, each new week suggests at most three changes from the week just finished. Progressing '
        'muscles keep their sets. A muscle that has held for two weeks without signs of fatigue gets one more set. '
        'A muscle that is falling, or holding with signs of fatigue, loses one.',
  ),
  (
    'Signs of fatigue',
    'A weaker first set, the same reps leaving fewer in reserve, reps dropping sharply from set to set, skipped '
        'sets, and sets stopped at a safety limit or discomfort. With the recovery check-in on (Settings → '
        'Advanced), still being sore at the next workout counts too; a low pump with early recovery earns an added '
        'set after one flat week, and a week of poor sleep or feeling run down adds nothing.',
  ),
  (
    'Limits',
    'One change per muscle per week. Sets are never added past a ceiling that follows your training experience '
        '(Settings → Advanced): the middle of MAV under a year, the top of MAV at one to three years, the top of '
        'MRV after that, or one set below where the muscle fell in earlier mesocycles once that is known. Never '
        'below MEV (below MV if you turn that off), nothing in the first two weeks or '
        'during a deload, and no added sets after a week with a missed workout.',
  ),
  (
    'Grow, maintain, priority',
    'Inside a mesocycle, tap a muscle to tell the coach how to treat it. Grow is the normal coaching. Maintain '
        'means its sets are never changed and only a drop in strength is reported, which frees recovery for other '
        'muscles. Priority muscles come first when sets are added. The choice is kept for the mesocycle and '
        'carried into the next one.',
  ),
  (
    'Advice without a set change',
    'Effort: a flat muscle whose sets stopped further from failure than the target RIR needs harder sets, not '
        'more of them. Add a day: every workout for the muscle already has ten or more direct sets. Swap: one '
        'exercise has not progressed for three weeks while others for the muscle have.',
  ),
  (
    'Fair comparisons only',
    'A workout is not compared when it came more than a week and a half after the one before, when the exercise '
        'moved two or more places in the workout, or when its planned rest changed by a third or more. Those would '
        'read as fatigue when they are not. Bodyweight and assisted exercises are compared by reps and added '
        'load; a logged bodyweight makes that more exact but is never required.',
  ),
  (
    'After a deload',
    'In the first weeks of a mesocycle the arrows compare with the last build week of the one before, so you '
        'can see whether strength came back.',
  ),
  (
    'Eating phase',
    'The button beside the title tells the coach whether you are gaining, maintaining or cutting in this '
        'mesocycle. Cutting adds no sets and removes them sooner; maintaining adds more slowly.',
  ),
  (
    'Deload now',
    'When at least two muscles fell last week, and they are at least half of those that could be compared or '
        'the week was your highest total of hard sets so far, the coach offers to start the planned deload now instead of removing sets muscle by muscle. Dismiss hides it '
        'for the week.',
  ),
  (
    'Apply',
    'The change is kept on the mesocycle and used when the workout starts. The saved workout is not rewritten, '
        'and the next mesocycle starts from it again.',
  ),
  (
    'Biggest changes',
    'The two muscles falling fastest and the two rising fastest, each with where its weekly sets sit: under MEV '
        '(Below MV, MV), towards MAV (MEV), in MAV, or at the recoverable limit (MRV). The same drop means '
        'something different in each: too little work at the bottom, too much at the top. Falling across several '
        'muscles at once usually means too much total work or too little recovery.',
  ),
]);
