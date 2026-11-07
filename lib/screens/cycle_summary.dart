import 'package:flutter/material.dart';

import '../logic/numbers.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'cycle.dart';
import 'finish.dart';
import '../store.dart';

/// Estimates shown to the nearest half unit: two decimals would claim precision an estimate does not have.
String _estimate(double v) => formatNumber((v * 2).round() / 2, NumKind.weight);

void openCycleSummary(BuildContext context, Mesocycle cycle) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CycleSummaryScreen(cycleId: cycle.id)));
}

class _CycleSummaryScreen extends StatelessWidget {
  final String cycleId;
  const _CycleSummaryScreen({required this.cycleId});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cycle = store.cycles.where((c) => c.id == cycleId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycle summary'),
        actions: [
          if (cycle != null)
            IconButton(
              tooltip: 'Edit mesocycle',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CycleEditor(cycle: cycle, isNew: false, past: !cycle.active),
                  ),
                );
                if (context.mounted && !store.cycles.any((c) => c.id == cycleId)) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: cycle == null
          ? null
          : ListView(
              padding: subPageInsets,
              children: [CycleSummaryContent(cycle: cycle, onStarted: () => Navigator.pop(context))],
            ),
    );
  }
}

/// Reused on the Cycle tab when a cycle is complete, and when reviewing a past cycle.
class CycleSummaryContent extends StatelessWidget {
  final Mesocycle cycle;
  final VoidCallback? onStarted;
  const CycleSummaryContent({super.key, required this.cycle, this.onStarted});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final summary = store.summarizeCycle(cycle);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    void info(String title, String body) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
      ),
    );

    Widget stat(String value, String label, {String? explanation}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: t.titleLarge?.copyWith(fontFeatures: tabular)),
          ),
          const SizedBox(height: 4),
          if (explanation == null)
            Text(label, style: t.labelSmall)
          else
            LabelWithInfo(
              Text(label, style: t.labelSmall),
              InfoDot(tooltip: label, onTap: () => info(label, explanation)),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(cycle.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          '${fmtShortDate(summary.start)} – ${fmtShortDate(summary.end)}',
          style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: EdgeInsets.all(context.style.sp(16)),
            child: Row(
              children: [
                stat('${summary.workouts}', 'Workouts'),
                const SizedBox(width: 8),
                stat(
                  '${summary.attended}/${summary.scheduled}',
                  'Scheduled',
                  explanation:
                      'Completed scheduled workouts out of scheduled days up to the end of this cycle. A moved workout counts for its original day; extra workouts count only toward Workouts.',
                ),
                const SizedBox(width: 8),
                stat(
                  '${summary.records}',
                  'Records',
                  explanation:
                      'Personal bests achieved during this cycle, compared with all earlier workouts. The card below shows the latest record of each kind for each exercise.',
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text(
            '${summary.sets} working sets · ${fmtDuration(summary.duration)}',
            style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        if (summary.strength.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
            child: LabelWithInfo(
              Text('ESTIMATED 1RM', style: t.labelSmall),
              InfoDot(
                tooltip: 'Strength change',
                onTap: () => info(
                  'Strength change',
                  'The best straight working set of the first build ${cycle.periodNoun()} compared with the best of the last one, counting reps in reserve so sets taken closer to failure do not look stronger. Loads are converted to ${summary.unit}. Warm-ups, deloads, other methods and changed setups are excluded. This is an estimate, not a tested maximum.',
                ),
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                for (final (i, change) in summary.strength.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  Padding(
                    padding: EdgeInsets.all(context.style.sp(16)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(change.name, style: t.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text(
                                '${_estimate(change.first)} → ${_estimate(change.last)} ${summary.unit}',
                                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          change.change.abs() < 0.25
                              ? '—'
                              : '${change.change > 0
                                    ? '+'
                                    : change.change < 0
                                    ? '−'
                                    : ''}${_estimate(change.change.abs())} ${summary.unit}',
                          style: t.titleMedium?.copyWith(
                            color: change.change > 0.05 ? cs.primary : cs.onSurfaceVariant,
                            fontFeatures: tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (summary.bests.isNotEmpty) ...[
          const SizedBox(height: 16),
          PersonalBestCard(summary.bests, title: 'Personal bests'),
        ],
        if (summary.workouts == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No completed workouts in this cycle.',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () async {
            final started = await startNextCycle(context, cycle);
            if (started && context.mounted) onStarted?.call();
          },
          child: const Text('Start next cycle'),
        ),
      ],
    );
  }
}
