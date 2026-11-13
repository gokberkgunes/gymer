import 'package:flutter/material.dart';

import '../logic/coach.dart';
import '../logic/cycle.dart';
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
    final t = Theme.of(context).textTheme;
    final report = store.coachReport();
    final volume = report.volume;
    final setsLabel = report.planned ? 'Planned weekly sets' : 'Sets in the last 7 days';
    final names = [
      ...rpLandmarks.keys,
      for (final m in volume.keys)
        if (!rpLandmarks.containsKey(m)) m,
    ];
    final protocols = volume.values.any((v) => v.direct.hasProtocols || v.indirect.hasProtocols);
    return ListView(
      padding: pageInsets,
      children: [
        PageHeader(
          'Coach',
          info: InfoDot(tooltip: 'How the coach reads your log', onTap: () => _coachInfo(context)),
        ),
        if (report.suggestions.isNotEmpty) ...[
          SectionLabel('This ${report.cycle?.periodNoun() ?? 'week'}'),
          Card(
            child: Column(
              children: [
                for (final (i, s) in report.suggestions.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  _SuggestionRow(suggestion: s),
                ],
              ],
            ),
          ),
        ] else if (report.declining.isNotEmpty) ...[
          const SectionLabel('Strength falling'),
          Card(
            child: Column(
              children: [
                for (final (i, v) in report.declining.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  _DecliningRow(verdict: v),
                ],
              ],
            ),
          ),
        ],
        SectionLabel(report.planned ? 'Weekly sets' : 'Sets, last 7 days'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in names)
                  MuscleVolumeRow(
                    muscle: m,
                    sets: volume[m]?.countedSets(includePartialSets: store.settings.includePartialSets) ?? 0,
                    frequency: volume[m]?.directDaysPerWeek ?? 0,
                    verdict: report.verdicts[m],
                    setsLabel: setsLabel,
                  ),
                if (protocols) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                    child: Text('Special set methods are not included in these estimates.', style: t.bodySmall),
                  ),
                  for (final m in names)
                    for (final (label, metrics) in [('Direct', volume[m]?.direct), ('Indirect', volume[m]?.indirect)])
                      if (metrics != null && metrics.hasProtocols)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '$m · $label: ${(metrics.scaled(1)..conventional = 0).describe()} / week',
                            style: t.bodySmall,
                          ),
                        ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Chest +1 set" with its target beneath, the reason behind (i), and Apply (or Undo once applied).
class _SuggestionRow extends StatelessWidget {
  final SetSuggestion suggestion;
  const _SuggestionRow({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final s = suggestion;
    final change = '${s.delta > 0 ? '+' : '−'}${s.delta.abs()} set';
    final color = s.delta > 0 ? cs.success : cs.warning;
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
                  [s.exercise, ?workout].join(' · '),
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
          const SizedBox(width: 12),
          if (s.applied == null)
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

class _DecliningRow extends StatelessWidget {
  final MuscleVerdict verdict;
  const _DecliningRow({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final v = verdict;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: LabelWithInfo(
                Text(v.muscle, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                InfoDot(
                  tooltip: 'Details',
                  onTap: () => showLandmarkInfo(context, v.muscle, verdict: v),
                ),
              ),
            ),
          ),
          Text(
            fmtTrend(v.percent),
            style: t.titleMedium?.copyWith(color: cs.error, fontFeatures: tabular),
          ),
        ],
      ),
    );
  }
}

void _coachInfo(BuildContext context) => showInfoSections(context, 'How the coach reads your log', const [
  (
    'Arrows',
    'Each exercise is compared with the same exercise in the same workout one week (or microcycle) earlier, set by '
        'set, using estimated 1RM so reps in reserve count. Up means progressing, flat holding, down falling. Only '
        'straight sets with an external load and the same logging context are compared; deloads and warm-ups never '
        'are. A muscle needs two comparable workouts before it gets an arrow. Tap a muscle for the exercises.',
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
        'sets, and sets stopped at a safety limit or discomfort.',
  ),
  (
    'Limits',
    'One change per muscle per week, never above the top of MRV or below MV, nothing in the first two weeks or '
        'during a deload, and no added sets after a week with a missed workout.',
  ),
  (
    'Apply',
    'The change is kept on the mesocycle and used when the workout starts. The saved workout is not rewritten, '
        'and the next mesocycle starts from it again.',
  ),
  (
    'Strength falling',
    'With nothing to change, the two muscles losing the most strength are listed. Falling across several muscles '
        'at once usually means too much total work or too little recovery.',
  ),
]);
