import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/cycle.dart';
import '../logic/numbers.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/warmup_background.dart' show DiagonalStripes;
import 'history.dart';
import 'home.dart';
import 'cycle_summary.dart';

part 'cycle/cards.dart';
part 'cycle/heatmap.dart';
part 'cycle/editor.dart';

class CycleScreen extends StatelessWidget {
  const CycleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final pending = store.pendingCycle;
    final cycle = pending ?? store.activeCycle;
    final past = store.cycles.where((c) => !c.active && c.setupComplete).toList().reversed.toList();

    return ListView(
      padding: pageInsets,
      children: [
        PageHeader(
          'Cycle',
          info: InfoDot(tooltip: 'How to use a mesocycle', onTap: () => _mesocycleInfo(context)),
          actions: [
            if (cycle != null && pending == null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (v) async {
                  if (v == 'edit') editCycle(context, cycle);
                  if (v == 'rir') unawaited(editWeeklyRir(context, cycle));
                  if (v == 'extend') unawaited(_extend(context, store, cycle));
                  if (v == 'summary') openCycleSummary(context, cycle);
                  if (v == 'end' &&
                      await confirm(
                        context,
                        'End mesocycle',
                        'You can continue it later from past cycles.',
                        action: 'End',
                      )) {
                    store.endCycle(cycle);
                    if (context.mounted) openCycleSummary(context, cycle);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'summary', child: Text('Cycle summary')),
                  PopupMenuItem(value: 'edit', child: Text('Edit settings')),
                  PopupMenuItem(value: 'rir', child: Text('Edit weekly RIR')),
                  PopupMenuItem(value: 'extend', child: Text('Extend mesocycle')),
                  PopupMenuItem(value: 'end', child: Text('End mesocycle')),
                ],
              ),
          ],
        ),
        if (cycle == null)
          const _Empty()
        else if (pending == null && cycleStatus(cycle).phase == 'Complete')
          CycleSummaryContent(cycle: cycle)
        else ...[
          if (pending != null) _SetupBanner(cycle: pending),
          CycleStatusCard(cycle: cycle),
          if (pending == null) ...[
            if (calendarDays(cycle, store.history).where((d) => dateKey(d.date) == dateKey(DateTime.now())).firstOrNull
                case final today?) ...[
              const SizedBox(height: 12),
              TodayCard(day: today, cycle: cycle),
            ],
          ],
          SectionLabel(
            'Weekly RIR',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InfoDot(
                  tooltip: 'Recording reps and effort',
                  onTap: () => _infoDialog(context, 'Record performed reps and actual effort', const [
                    (
                      '',
                      'A cycle target is a prescription. Actual RIR is your estimate of clean reps left after the set. '
                          'Record the reps you performed and leave actual RIR blank when unknown.',
                    ),
                    (
                      'Example',
                      'Target 3 RIR, 8 reps performed, 2 reps left. Record 8 reps and actual RIR 2. The target remains 3.',
                    ),
                  ]),
                ),
                TextButton(onPressed: () => editWeeklyRir(context, cycle), child: const Text('Edit weekly RIR')),
              ],
            ),
          ),
          _RirStrip(cycle: cycle),
          SectionLabel('Repeating ${cycle.microDays}-day schedule'),
          _Schedule(cycle: cycle),
          const SectionLabel('Training'),
          CycleHeatmap(cycle: cycle),
          const SectionLabel('Weekly sets'),
          _Volume(cycle: cycle),
        ],
        if (past.isNotEmpty) ...[
          const SectionLabel('Past cycles'),
          Card(
            child: Column(
              children: [
                for (final (i, c) in past.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(c.name),
                    subtitle: Text('${fmtShortDate(c.start)} · ${c.length} × ${c.microDays} days'),
                    onTap: () => openCycleSummary(context, c),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _extend(BuildContext context, AppStore store, Mesocycle c) async {
    var n = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setDialog) => AlertDialog(
          title: const Text('Extend mesocycle'),
          content: Row(
            children: [
              Expanded(child: Text('Add build ${c.periodNoun(plural: true)}')),
              IconButton(onPressed: n > 1 ? () => setDialog(() => n--) : null, icon: const Icon(Icons.remove_rounded)),
              Text('$n', style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => setDialog(() => n++), icon: const Icon(Icons.add_rounded)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('Extend')),
          ],
        ),
      ),
    );
    if (ok == true) store.extendCycle(c, n);
  }
}

void _infoDialog(BuildContext context, String title, List<(String, String)> sections) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (heading, body) in sections) ...[
              if (heading.isNotEmpty) Text(heading, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (heading.isNotEmpty) const SizedBox(height: 3),
              Text(body),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}

void _mesocycleInfo(BuildContext context) => _infoDialog(context, 'How to use a mesocycle', const [
  (
    'Build the repeating schedule',
    'Set the microcycle length to match how your training actually repeats. Seven days works for a weekly plan, '
        'but shorter or longer cycles are fine too.',
  ),
  (
    'Plan the training phase',
    'Choose how many repeating training periods you want to run before resetting or changing the program. With the '
        'default 7-day microcycle these are shown as weeks; change the microcycle length in days to repeat differently.',
  ),
  (
    'Keep targets separate from actual effort',
    'Use the prescribed RIR as a guide, then record performed reps and the actual reps left. Never change the logged '
        'rep count to make it match a target. Leave actual RIR blank if unknown; legacy RIR remains unverified.',
  ),
  (
    'Progress reps, then load',
    "Straight double progression uses each exercise's rep range (8–12 by default). Build reps at the target RIR, then "
        'add one available load increment after every planned set reaches the upper limit. Missed sets block an '
        'increase, and so does unknown effort while Track RIR is on; with it off, reps alone decide. Change the range '
        'or select manual progression in exercise details; other methods use the same range for their first set.',
  ),
  (
    'Change the plan when needed',
    'A mesocycle is a planning tool, not a restriction. Edit the calendar or targets when your schedule or recovery '
        'changes, and use the history to remember what you ran.',
  ),
]);

void showRestLockInfo(BuildContext context) => _infoDialog(context, 'Lock rest times', const [
  (
    '',
    'Keeping rest times consistent makes sessions easier to compare. If rest changes substantially, reps and RIR can '
        'change because you recovered more or less between sets rather than because the exercise became easier or harder.',
  ),
]);

void showRirOverrideInfo(BuildContext context) => _infoDialog(context, 'Prescribed RIR target', const [
  (
    '',
    'This setting controls whether a calculator can override the prescribed target. Actual RIR is always editable and '
        'is recorded separately. A target never proves how hard a set actually was.',
  ),
]);
