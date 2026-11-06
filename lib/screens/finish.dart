import 'package:flutter/material.dart';

import '../logic/numbers.dart';
import '../logic/volume.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/celebration.dart';
import '../widgets/common.dart';

/// Shown after saving a workout: three headline numbers, any personal bests, how each exercise went against
/// last time, and the muscle breakdown folded away. Plus the workout celebration.
class FinishScreen extends StatelessWidget {
  final FinishSummary summary;
  final bool historical;
  final VoidCallback? onEdit;
  const FinishScreen({super.key, required this.summary, this.historical = false, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = summary;
    final pbExercises = {for (final b in s.bests) b.exercise};

    return Scaffold(
      appBar: historical
          ? AppBar(
              title: const Text('Workout summary'),
              actions: [
                if (onEdit != null)
                  IconButton(tooltip: 'Edit workout', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
              ],
            )
          : null,
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: historical ? subPageInsets : const EdgeInsets.fromLTRB(16, 24, 16, 32),
              children: [
                Text(
                  historical ? s.name : 'Workout complete',
                  style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  historical ? fmtShortDate(s.date) : s.name,
                  style: t.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _Stat(_duration(s.duration), 'Time')),
                    const SizedBox(width: 8),
                    Expanded(child: _Stat('${s.sets}', s.sets == 1 ? 'Set' : 'Sets')),
                    if (s.volume > 0) ...[
                      const SizedBox(width: 8),
                      Expanded(child: _Stat('${groupThousands(s.volume)} ${s.unit}', 'Volume')),
                    ],
                  ],
                ),
                if (s.bests.isNotEmpty) ...[const SizedBox(height: 16), _Bests(s.bests)],
                if (s.exercises.isNotEmpty) ...[
                  SectionLabel(
                    'Exercises',
                    trailing: Text('vs last time', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, e) in s.exercises.indexed) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          _ExerciseRow(e, unit: s.unit, record: pbExercises.contains(e.name)),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _Muscles(s.report),
                if (!historical) ...[
                  const SizedBox(height: 24),
                  FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                ],
              ],
            ),
          ),
          if (!historical) const Positioned.fill(child: WorkoutCelebration()),
        ],
      ),
    );
  }

  static String _duration(Duration d) {
    final m = d.inMinutes;
    if (m < 60) return '$m min';
    return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
  }
}

/// One headline number with a small uppercase label beneath.
class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: st.br),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular),
            ),
          ),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Personal bests: a monochrome trophy in the accent colour heads the card, and each record is a row with
/// the exercise and kind on the left and the new value, accent-coloured, on the right.
class _Bests extends StatelessWidget {
  final List<PersonalBest> bests;
  const _Bests(this.bests);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    final accent = cs.primary;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: st.br,
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), borderRadius: st.brSmall),
                child: Icon(Icons.emoji_events_outlined, color: accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  bests.length == 1 ? 'New personal best' : '${bests.length} personal bests',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final b in bests)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.kind == 'workout' ? b.label : b.exercise,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          b.kind == 'workout' ? b.exercise : b.label,
                          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        b.value,
                        style: t.bodyLarge?.copyWith(color: accent, fontWeight: FontWeight.w700, fontFeatures: tabular),
                      ),
                      Text(
                        b.gain,
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// An exercise's sets and best set, a small accent trophy if it set a record, and its change in estimated
/// 1RM since last time (accent when up, muted when down, hidden when unchanged).
class _ExerciseRow extends StatelessWidget {
  final ExerciseResult e;
  final String unit;
  final bool record;
  const _ExerciseRow(this.e, {required this.unit, required this.record});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final change = e.change;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (record) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.emoji_events_outlined, size: 16, color: cs.primary),
                    ],
                  ],
                ),
                Text(
                  [plural(e.sets, 'set'), ?e.best].join(' · '),
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                ),
              ],
            ),
          ),
          if (change != null && change.abs() >= 0.5)
            Tooltip(
              message: 'Estimated 1RM compared with last time',
              child: Text(
                '${change > 0 ? '+' : '−'}${formatNumber((change.abs() * 2).round() / 2, NumKind.weight)} $unit',
                style: t.bodyMedium?.copyWith(
                  color: change > 0 ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabular,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The muscle breakdown, collapsed by default.
class _Muscles extends StatelessWidget {
  final VolumeReport report;
  const _Muscles(this.report);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final r = report;
    if (r.direct.isEmpty && r.indirect.isEmpty) return const SizedBox.shrink();
    Widget rows(Map<String, VolumeMetrics> m) => Column(
      children: [
        for (final MapEntry(key: muscle, value: v) in m.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(muscle, style: t.bodyMedium)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    v.describe(),
                    textAlign: TextAlign.end,
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Text(text.toUpperCase(), style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: const Text('Muscles worked'),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.only(bottom: 10),
        children: [
          if (r.direct.isNotEmpty) ...[label('Direct'), rows(r.direct)],
          if (r.indirect.isNotEmpty) ...[label('Also involved'), rows(r.indirect)],
          if (r.totals.completeGroups + r.totals.partialGroups > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                'Protocol groups: ${r.totals.completeGroups.round()} complete, '
                '${r.totals.partialGroups.round()} partial',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
