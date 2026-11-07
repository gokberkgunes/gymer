import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/cycle.dart';
import '../logic/numbers.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'history.dart';
import 'home.dart';
import 'cycle_summary.dart';

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
                  if (v == 'rir') editWeeklyRir(context, cycle);
                  if (v == 'extend') _extend(context, store, cycle);
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
        'add one available load increment after every planned set reaches the upper limit. Missed sets or unknown '
        'effort block an increase. Change the range or select manual progression in exercise details; other methods '
        'have separate rules.',
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

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final store = StoreScope.read(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No active mesocycle', style: t.titleLarge),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () {
                final now = DateTime.now();
                editCycle(
                  context,
                  Mesocycle(id: 'C${now.microsecondsSinceEpoch}', start: dateOnly(now)),
                  isNew: true,
                  onCreated: store.beginCycleSetup,
                );
              },
              child: const Text('Create mesocycle'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: store.openDemoCycle, child: const Text('Open demo cycle')),
          ],
        ),
      ),
    );
  }
}

class _SetupBanner extends StatelessWidget {
  final Mesocycle cycle;
  const _SetupBanner({required this.cycle});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: context.style.br,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Expanded(
                child: Text('Assign workouts to schedule days below, then press Start. Leaving now cancels the setup.'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final error = store.startPendingCycle();
                  notify(context, error ?? 'Mesocycle started.');
                },
                child: const Text('Start'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Name, week/day, phase, target RIR and time left; tap opens the Cycle tab.
class CycleStatusCard extends StatelessWidget {
  final Mesocycle cycle;
  final VoidCallback? onTap;
  final bool compact;
  const CycleStatusCard({super.key, required this.cycle, this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final status = cycleStatus(cycle);
    final phaseColor = switch (status.phase) {
      'Deload' => cs.warning,
      'Build' => cs.success,
      _ => cs.primary,
    };
    final todayName = store.template(cycle.schedule[status.dayInMicro])?.name;
    final period = cycle.periodNoun();
    if (compact) {
      return Material(
        color: cs.primary.withValues(alpha: 0.065),
        shape: RoundedRectangleBorder(
          borderRadius: context.style.br,
          side: BorderSide(color: cs.primary.withValues(alpha: 0.45)),
        ),
        child: InkWell(
          borderRadius: context.style.br,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cycle.name, style: t.titleSmall),
                      Text(
                        '${period[0].toUpperCase()}${period.substring(1)} ${status.currentMicro}/${status.totalMicro} · ${status.phase}',
                        style: t.bodySmall,
                      ),
                      Text(
                        todayName == null ? 'Today: unplanned' : 'Today: $todayName',
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'RIR ${status.suggestedRir}',
                      style: TextStyle(color: phaseColor, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      status.phase == 'Complete' ? 'Complete' : '${status.remainingDays} days left',
                      style: t.labelSmall,
                    ),
                  ],
                ),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.style.sp(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(cycle.name, style: t.titleLarge)),
                Text(
                  status.phase,
                  style: TextStyle(color: phaseColor, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Stat('${status.currentMicro}/${status.totalMicro}', period)),
                Expanded(child: Stat('${status.dayInMicro}/${cycle.microDays}', 'day')),
                Expanded(child: Stat('${status.suggestedRir}', 'target RIR')),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: status.progress, minHeight: 4, backgroundColor: cs.outlineVariant),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(fmtShortDate(status.start), style: t.labelSmall),
                const Spacer(),
                Text(
                  status.phase == 'Complete' ? 'Complete' : '${status.remainingDays} days left',
                  style: t.labelSmall,
                ),
                const Spacer(),
                Text(fmtShortDate(status.end), style: t.labelSmall),
              ],
            ),
            if (!cycle.rirLock || cycle.restLock) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (!cycle.rirLock) 'Target RIR override allowed',
                  if (cycle.restLock) 'Rest timers locked',
                ].join(' · '),
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TodayCard extends StatelessWidget {
  final CycleDay day;
  final Mesocycle cycle;
  const TodayCard({super.key, required this.day, required this.cycle});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final ids = [
      if (day.templateId != null && day.status == 'planned') day.templateId!,
      for (final (_, id) in day.incoming) id,
    ];
    final done = day.status == 'done' || day.status == 'moved_done';
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: context.style.br,
      child: Padding(
        padding: EdgeInsets.all(context.style.sp(16)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TODAY', style: t.labelSmall),
                  const SizedBox(height: 4),
                  Text(
                    done
                        ? '${store.template(day.templateId)?.name ?? 'Workout'} · done'
                        : ids.isEmpty
                        ? (day.status == 'missed' ? 'Marked missed' : 'Rest day')
                        : ids.map((id) => store.template(id)?.name ?? 'Workout').join(' + '),
                    style: t.titleMedium,
                  ),
                ],
              ),
            ),
            if (done)
              Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.success)
            else if (ids.isNotEmpty)
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: compactButton),
                onPressed: () => startPlanned(context, ids.first),
                child: const Text('Start'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Only one workout can be in progress; the same one simply reopens.
Future<void> startPlanned(BuildContext context, String templateId) async {
  final store = StoreScope.read(context);
  final tpl = store.template(templateId);
  if (tpl == null) return;
  final active = store.active;
  if (active != null) {
    if (active.templateId == templateId) return openSession(context);
    return notify(context, 'Finish or discard the current workout before starting another one.');
  }
  if (tpl.exercises.every((e) => e.sets.isEmpty)) {
    return notify(context, 'Add exercises to this workout first.');
  }
  store.startSession(tpl);
  openSession(context);
}

class _RirStrip extends StatelessWidget {
  final Mesocycle cycle;
  const _RirStrip({required this.cycle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    final status = cycleStatus(cycle);
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var w = 1; w <= status.totalMicro; w++)
            () {
              final current = w == status.currentMicro && status.running;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  width: 54,
                  decoration: BoxDecoration(
                    borderRadius: st.brSmall,
                    color: current ? cs.primary : cs.surfaceContainerHigh,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${rirForWeek(cycle, w)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: current ? cs.onPrimary : null,
                        ),
                      ),
                      Text(
                        w > status.buildMicro ? 'DL $w' : '${cycle.periodShort}$w',
                        style: TextStyle(fontSize: 11, color: current ? cs.onPrimary : cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}

class _Schedule extends StatelessWidget {
  final Mesocycle cycle;
  final VoidCallback? onChanged;
  const _Schedule({required this.cycle, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        children: [
          for (var d = 1; d <= cycle.microDays; d++) ...[
            if (d > 1) const Divider(indent: 16, endIndent: 16),
            InkWell(
              onTap: () async {
                final id = await pickTemplate(context, cycle.schedule[d], title: 'Schedule day $d');
                if (id == null) return;
                if (id.isEmpty) {
                  cycle.schedule.remove(d);
                } else {
                  cycle.schedule[d] = id;
                }
                (onChanged ?? store.changed)();
              },
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: context.style.sp(12)),
                child: Row(
                  children: [
                    SizedBox(width: 56, child: Text('Day $d', style: t.labelSmall)),
                    Expanded(
                      child: Text(
                        store.template(cycle.schedule[d])?.name ?? 'Rest',
                        style: cycle.schedule[d] == null
                            ? t.bodyLarge?.copyWith(color: cs.onSurfaceVariant)
                            : t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Returns a template id, '' for rest, or null if dismissed.
Future<String?> pickTemplate(
  BuildContext context,
  String? current, {
  String title = 'Choose workout',
  bool allowRest = true,
}) {
  final store = StoreScope.read(context);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(title, style: Theme.of(sheet).textTheme.titleLarge),
            ),
            if (allowRest)
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('Rest'),
                onTap: () => Navigator.pop(sheet, ''),
              ),
            for (final tpl in store.templates)
              ListTile(
                title: Text(tpl.name),
                trailing: tpl.id == current
                    ? Icon(Icons.check_rounded, color: Theme.of(sheet).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(sheet, tpl.id),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Training heatmap: green as planned, blue on another day, red missed.
class CycleHeatmap extends StatelessWidget {
  final Mesocycle cycle;
  final bool compact;
  const CycleHeatmap({super.key, required this.cycle, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final days = calendarDays(cycle, store.history);
    final perRow = math.max(1, cycle.microDays);
    const weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

    Widget tile(CycleDay d, double cell) {
      final today = dateKey(d.date) == dateKey(DateTime.now());
      final planned = d.templateId != null || d.incoming.isNotEmpty;
      final Color fill = switch (d.status) {
        'missed' => cs.error,
        _ when d.offPlan => cs.info,
        'done' => cs.success,
        _ => cs.onSurface.withValues(alpha: 0.12),
      };
      final strong = d.status == 'missed' || d.status == 'done' || d.offPlan;
      final border = today
          ? (dark ? Colors.white : Colors.black)
          : (planned && d.sessions.isEmpty ? cs.primary : cs.onSurface.withValues(alpha: 0.28));
      final label = const {
        'done': 'Completed',
        'moved_done': 'Completed on another day',
        'missed': 'Missed',
        'moved': 'Moved',
        'planned': 'Planned',
        'rest': 'Rest',
      }[d.status];
      return Tooltip(
        message:
            '${fmtRecent(d.date, store.settings.unit, includeTime: false)} · ${store.template(d.templateId)?.name ?? 'Rest'} · $label'
            '${d.offPlan && d.status != 'moved_done' ? ' · Workout completed off schedule' : ''}',
        child: InkWell(
          onTap: () => _dayActions(context, store, d),
          child: Container(
            width: cell,
            height: cell,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: border, width: today ? 2.5 : 1),
            ),
            child: planned || d.sessions.isNotEmpty
                ? Text(
                    '${d.dayInMicro}',
                    style: TextStyle(
                      fontSize: compact ? 9 : 9.5,
                      fontWeight: today ? FontWeight.bold : FontWeight.w500,
                      color: strong ? Colors.white : null,
                    ),
                  )
                : null,
          ),
        ),
      );
    }

    List<Widget> rows(double cell) => <Widget>[
      Row(
        children: [
          const SizedBox(width: 28),
          for (final d in days.take(perRow))
            Container(
              width: cell + 4,
              alignment: Alignment.center,
              child: Text(
                weekdays[d.date.weekday - 1],
                style: t.labelSmall?.copyWith(fontSize: compact ? 9.5 : 10, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      for (var r = 0; r * perRow < days.length; r++)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${cycle.periodShort}${r + 1}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              for (final d in days.skip(r * perRow).take(perRow))
                Padding(padding: const EdgeInsets.only(right: 4), child: tile(d, cell)),
            ],
          ),
        ),
      if (!compact)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Green: as planned  ·  Blue: another day  ·  Red: missed', style: t.bodySmall),
        ),
    ];
    Widget grid(double cell) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows(cell));
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 12),
        // The squares share the card's width (up to a comfortable size) instead of leaving a gap on the right.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fit = (constraints.maxWidth - 28) / perRow - 4;
            final cell = fit.clamp(compact ? 12.0 : 10.0, 44.0);
            return SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid(cell));
          },
        ),
      ),
    );
  }

  Future<void> _dayActions(BuildContext context, AppStore store, CycleDay d) async {
    final key = dateKey(d.date);
    final todayKey = dateKey(DateTime.now());
    final isToday = key == todayKey;
    final name = store.template(d.templateId)?.name;
    final event = cycle.events[key];
    final running = store.activeCycle?.id == cycle.id;
    final canLog =
        d.sessionId == null &&
        (key.compareTo(todayKey) <= 0 || (d.movedTo != null && dateKey(d.movedTo!).compareTo(todayKey) <= 0));
    final details = <String>[
      name ?? 'Rest',
      switch (d.status) {
        'missed' => 'Missed',
        'moved' => 'Moved to ${fmtRecent(d.movedTo!, store.settings.unit, includeTime: false)}',
        'moved_done' => 'Completed off schedule',
        'done' => 'Completed as planned',
        _ => '',
      },
      for (final (from, id) in d.incoming)
        '${store.template(id)?.name ?? 'Workout'} · moved from ${fmtRecent(from, store.settings.unit, includeTime: false)}',
    ].where((x) => x.isNotEmpty).toList();

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fmtRecent(d.date, store.settings.unit, includeTime: false),
                      style: Theme.of(sheet).textTheme.titleLarge,
                    ),
                    for (final line in details) Text(line),
                  ],
                ),
              ),
              if (d.sessionId != null)
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('Edit recorded workout'),
                  onTap: () => Navigator.pop(sheet, 'session:${d.sessionId}'),
                ),
              for (final s in d.sessions.where((s) => s.id != d.sessionId))
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: Text('Edit ${s.name}'),
                  onTap: () => Navigator.pop(sheet, 'session:${s.id}'),
                ),
              if (d.templateId != null && d.sessionId == null && !d.unplanned) ...[
                if (d.status == 'planned' && isToday && running)
                  ListTile(
                    leading: const Icon(Icons.play_arrow_rounded),
                    title: const Text('Start workout'),
                    onTap: () => Navigator.pop(sheet, 'start:${d.templateId}'),
                  ),
                ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: const Text('Move'),
                  onTap: () => Navigator.pop(sheet, 'move'),
                ),
                ListTile(
                  leading: const Icon(Icons.event_busy_outlined),
                  title: const Text('Mark missed'),
                  onTap: () => Navigator.pop(sheet, 'missed'),
                ),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('Link recorded workout'),
                  onTap: () => Navigator.pop(sheet, 'link'),
                ),
                if (d.status == 'moved' || d.status == 'missed')
                  ListTile(
                    leading: const Icon(Icons.undo_rounded),
                    title: const Text('Undo change'),
                    onTap: () => Navigator.pop(sheet, 'undo'),
                  ),
              ],
              if (canLog)
                ListTile(
                  leading: const Icon(Icons.post_add_rounded),
                  title: const Text('Log past workout'),
                  onTap: () => Navigator.pop(sheet, 'log'),
                ),
              for (final (from, id) in d.incoming) ...[
                if (isToday && running)
                  ListTile(
                    leading: const Icon(Icons.play_arrow_rounded),
                    title: Text('Start ${store.template(id)?.name ?? 'workout'}'),
                    onTap: () => Navigator.pop(sheet, 'start:$id'),
                  ),
                if (key.compareTo(todayKey) <= 0)
                  ListTile(
                    leading: const Icon(Icons.post_add_rounded),
                    title: Text('Log ${store.template(id)?.name ?? 'workout'}'),
                    onTap: () => Navigator.pop(sheet, 'logfrom:${dateKey(from)}:$id'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action.startsWith('session:')) {
      final s = store.history.where((x) => x.id == action.substring(8)).firstOrNull;
      if (s != null) openSessionEditor(context, s);
    } else if (action.startsWith('start:')) {
      startPlanned(context, action.substring(6));
    } else if (action == 'missed') {
      cycle.events[key] = DayEvent(templateId: d.templateId!, status: 'missed', movedTo: event?.movedTo);
      store.changed();
    } else if (action == 'undo') {
      cycle.events.remove(key);
      store.changed();
    } else if (action == 'move') {
      final picked = await showDatePicker(
        context: context,
        initialDate: (d.movedTo ?? dateOnly(DateTime.now())).isBefore(cycleStatus(cycle).start)
            ? cycleStatus(cycle).start
            : (d.movedTo ?? dateOnly(DateTime.now())).isAfter(cycleStatus(cycle).end)
            ? cycleStatus(cycle).end
            : (d.movedTo ?? dateOnly(DateTime.now())),
        // A workout moved outside the cycle would vanish from its calendar.
        firstDate: cycleStatus(cycle).start,
        lastDate: cycleStatus(cycle).end,
      );
      if (picked == null) return;
      cycle.events[key] = DayEvent(templateId: d.templateId!, movedTo: dateKey(picked) == key ? null : picked);
      store.changed();
    } else if (action == 'link') {
      final options = store.history.where((s) => s.templateId == d.templateId && s.doneAll > 0).take(100).toList();
      if (options.isEmpty) return notify(context, 'No recorded workouts found.');
      final picked = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Choose recorded workout', style: Theme.of(sheet).textTheme.titleLarge),
              ),
              for (final s in options)
                ListTile(
                  title: Text(fmtRecent(s.startedAt, store.settings.unit)),
                  onTap: () => Navigator.pop(sheet, s.id),
                ),
            ],
          ),
        ),
      );
      if (picked == null || !context.mounted) return;
      final error = store.linkRecordedSession(cycle, key, d.templateId!, picked);
      if (error != null) notify(context, error);
    } else if (action == 'log') {
      var templateId = d.templateId;
      var unplanned = d.unplanned;
      if (templateId == null) {
        if (store.templates.isEmpty) return notify(context, 'Create a workout first.');
        templateId = await pickTemplate(context, null, title: 'Choose workout', allowRest: false);
        if (templateId == null || !context.mounted) return;
        unplanned = true;
      }
      _log(context, store, key, templateId, d.movedTo ?? d.date, unplanned: unplanned);
    } else if (action.startsWith('logfrom:')) {
      final parts = action.split(':');
      _log(context, store, parts[1], parts[2], d.date);
    }
  }

  void _log(
    BuildContext context,
    AppStore store,
    String plannedKey,
    String templateId,
    DateTime date, {
    bool unplanned = false,
  }) {
    final tpl = store.template(templateId);
    if (tpl == null) return notify(context, 'This workout is no longer available.');
    if (tpl.exercises.isEmpty) return notify(context, 'Add exercises to this workout first.');
    final day = date.isAfter(DateTime.now()) ? DateTime.now() : date;
    final draft = store.draftPastSession(templateId, day);
    openSessionEditor(context, draft, cycle: cycle, plannedKey: plannedKey, draft: true, unplanned: unplanned);
  }
}

class _Volume extends StatelessWidget {
  final Mesocycle cycle;
  const _Volume({required this.cycle});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final volume = plannedWeeklyVolume(cycle, {for (final tpl in store.templates) tpl.id: tpl}, store.musclesOf);
    final names = [
      for (final m in rpLandmarks.keys)
        if (volume.containsKey(m)) m,
      for (final m in volume.keys)
        if (!rpLandmarks.containsKey(m)) m,
    ];
    String n(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    final protocols = volume.values.any((v) => v.direct.hasProtocols || v.indirect.hasProtocols);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Estimated from your repeating schedule: direct sets count as 1, indirect sets as 0.5.',
                style: t.bodySmall,
              ),
            ),
            if (names.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Add workouts and muscle tags to see weekly sets.',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            for (final m in names)
              ListTile(
                dense: true,
                title: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${n(volume[m]!.sets)} sets / ${rpLandmarks[m]?.mev ?? '—'} MEV'),
                    const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
                onTap: () => _landmarkInfo(context, m),
              ),
            if (protocols) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                child: Text('Special set methods are not included in these estimates.', style: t.bodySmall),
              ),
              for (final m in names)
                for (final (label, metrics) in [('Direct', volume[m]!.direct), ('Indirect', volume[m]!.indirect)])
                  if (metrics.hasProtocols)
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
    );
  }

  void _landmarkInfo(BuildContext context, String muscle) {
    final l = rpLandmarks[muscle];
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(muscle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('What the landmarks mean', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                'MV: maintenance volume. MEV: minimum effective volume. MAV: maximum adaptive volume. '
                'MRV: maximum recoverable volume. Values are hard sets per week.',
              ),
              const SizedBox(height: 8),
              const Text(
                'These are general references, not personal targets. The weekly estimate counts indirect sets as half a '
                'set, so it may not be directly comparable to these ranges.',
              ),
              const SizedBox(height: 12),
              if (l == null)
                const Text('No RP landmark is available for this muscle.')
              else ...[
                const Text('RP volume landmarks', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final (k, v) in [('MV', l.mv), ('MEV', l.mev), ('MAV', l.mav), ('MRV', l.mrv)])
                  Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: Text(k, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Text(v),
                    ],
                  ),
                const SizedBox(height: 8),
                SelectableText(l.url, style: Theme.of(c).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }
}

// ---------------------------------------------------------------- Editors

void editCycle(BuildContext context, Mesocycle cycle, {bool isNew = false, void Function(Mesocycle)? onCreated}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CycleEditor(cycle: cycle, isNew: isNew, onCreated: onCreated),
    ),
  );
}

void editPastCycle(BuildContext context, Mesocycle cycle) {
  Navigator.of(context).push(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => CycleEditor(cycle: cycle, isNew: false, past: true)),
  );
}

Future<bool> startNextCycle(BuildContext context, Mesocycle source) async {
  final store = StoreScope.read(context);
  final draft = store.cloneCycle(source);
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CycleEditor(cycle: draft, isNew: true, cloneSource: source),
        ),
      ) ??
      false;
}

/// Mirrors deloads.effort_error(): deload effort must be easier than the final build week.
String? deloadEffortError(Mesocycle c) {
  if (c.deloadMicro >= c.length) return 'Keep at least one build week.';
  if (c.deloadManual || c.deloadMicro == 0) return null;
  final build = c.length - c.deloadMicro;
  final finalBuild = rirForWeek(c, build);
  for (var w = build + 1; w <= c.length; w++) {
    final r = rirForWeek(c, w);
    if (r < 1 || r <= finalBuild) return 'Deload RIR must be higher than the final build week.';
  }
  return null;
}

class CycleEditor extends StatefulWidget {
  final Mesocycle cycle;
  final bool isNew;
  final bool past;
  final Mesocycle? cloneSource;
  final void Function(Mesocycle)? onCreated;
  const CycleEditor({
    super.key,
    required this.cycle,
    required this.isNew,
    this.onCreated,
    this.past = false,
    this.cloneSource,
  });

  @override
  State<CycleEditor> createState() => _CycleEditorState();
}

class _CycleEditorState extends State<CycleEditor> {
  late final Mesocycle _d = Mesocycle.fromJson(widget.cycle.toJson());
  late final _name = TextEditingController(text: _d.name);
  int _loadPercent = 100;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _apply(Mesocycle target) {
    final previousDeloadRir = target.deloadRir;
    target
      ..name = _name.text.trim().isEmpty ? 'Mesocycle' : _name.text.trim()
      ..start = _d.start
      ..microDays = _d.microDays
      ..length = _d.length
      ..deloadMicro = _d.deloadMicro
      ..startRir = _d.startRir
      ..endRir = _d.endRir
      ..deloadRir = _d.deloadRir
      ..deloadManual = _d.deloadManual
      ..deloadLoadPct = _d.deloadLoadPct
      ..deloadVolumePct = _d.deloadVolumePct
      ..rirLock = _d.rirLock
      ..restLock = _d.restLock;
    // An edited deload target applies to existing weekly deload overrides.
    if (previousDeloadRir != _d.deloadRir) {
      final build = target.length - target.deloadMicro;
      for (final w in target.weekRir.keys.toList()) {
        if (w > build) target.weekRir[w] = _d.deloadRir;
      }
      if (target.rirScheduleMode == 'steady' && _d.deloadRir != 4) target.rirScheduleMode = 'custom';
    }
    target.schedule.removeWhere((day, _) => day > target.microDays);
  }

  void _save() {
    final store = StoreScope.read(context);
    if (widget.isNew) {
      _apply(_d);
      if (widget.cloneSource != null) {
        _d.schedule.removeWhere((_, id) => store.template(id) == null);
        if (_d.schedule.isEmpty) {
          return notify(context, 'Assign at least one workout day before starting the mesocycle.');
        }
        _d
          ..setupComplete = true
          ..startingLoads.removeWhere((id, _) => !_d.schedule.containsValue(id));
        store.saveCycle(_d);
        Navigator.pop(context, true);
        return;
      }
      widget.onCreated?.call(_d);
    } else {
      _apply(widget.cycle);
      store.changed();
      if (widget.past) notify(context, 'Previous mesocycle saved.');
    }
    Navigator.pop(context);
  }

  Future<void> _toggleOverride(bool allow) async {
    if (!allow) return setState(() => _d.rirLock = true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Override prescribed targets?'),
        content: const Text(
          'The cycle keeps its scheduled targets. Unlocking permits a calculator target override. Always record '
          'performed reps and actual RIR honestly; actual effort can be edited with either setting.',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep locked')),
          OutlinedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Unlock')),
        ],
      ),
    );
    if (ok == true) setState(() => _d.rirLock = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final error = deloadEffortError(_d);

    Widget stepper(
      String title,
      int value,
      int min,
      int max,
      void Function(int) set, {
      String? subtitle,
      int step = 1,
    }) => Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: context.style.sp(6)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.bodyLarge),
                if (subtitle != null) Text(subtitle, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            onPressed: value > min ? () => setState(() => set((value - step).clamp(min, max))) : null,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: t.titleMedium?.copyWith(fontFeatures: tabular),
            ),
          ),
          IconButton(
            onPressed: value < max ? () => setState(() => set((value + step).clamp(min, max))) : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );

    Widget group(List<Widget> children) => Card(
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[if (i > 0) const Divider(indent: 16, endIndent: 16), c],
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: Text(
          widget.cloneSource != null
              ? 'Next mesocycle'
              : widget.isNew
              ? 'New mesocycle'
              : (widget.past ? 'Previous mesocycle' : 'Edit mesocycle'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: error == null ? _save : null,
              child: Text(
                widget.cloneSource != null
                    ? 'Start'
                    : widget.isNew
                    ? 'Next'
                    : 'Save',
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: subPageInsets,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Mesocycle name'),
          ),
          if (widget.cloneSource != null) ...[
            const SectionLabel('Starting loads'),
            _StartingLoadSetup(
              draft: _d,
              percent: _loadPercent,
              onChanged: (percent) => setState(() {
                _loadPercent = percent;
                _d
                  ..startingLoadUnit = store.settings.unit
                  ..startingLoads = store.cycleStartingLoads(
                    widget.cloneSource!,
                    loadPercent: percent,
                    templateIds: _d.schedule.values,
                  );
              }),
            ),
            SectionLabel('Repeating ${_d.microDays}-day schedule'),
            _Schedule(
              cycle: _d,
              onChanged: () => setState(() {
                // A workout assigned to a day after the draft was made needs its own starting loads.
                _d
                  ..startingLoadUnit = store.settings.unit
                  ..startingLoads = store.cycleStartingLoads(
                    widget.cloneSource!,
                    loadPercent: _loadPercent,
                    templateIds: _d.schedule.values,
                  );
              }),
            ),
            SectionLabel(
              'Weekly RIR',
              trailing: TextButton(
                onPressed: () async {
                  await editWeeklyRir(context, _d);
                  if (mounted) setState(() {});
                },
                child: const Text('Edit'),
              ),
            ),
            _RirStrip(cycle: _d),
          ],
          const SectionLabel('Structure'),
          group([
            ListTile(
              title: const Text('Start date'),
              trailing: Text(
                fmtDate(_d.start),
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _d.start,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _d.start = picked);
              },
            ),
            stepper('Repeat (days)', _d.microDays, 1, 28, (v) => _d.microDays = v),
            stepper(
              'Length',
              _d.length,
              1,
              52,
              (v) => _d.length = v,
              subtitle: '${_d.periodNoun(plural: true)}, including deload',
            ),
            stepper('Deload', _d.deloadMicro, 0, 8, (v) => _d.deloadMicro = v, subtitle: _d.periodNoun(plural: true)),
          ]),
          const SectionLabel('Effort'),
          group([
            stepper('Start RIR', _d.startRir, 0, 10, (v) => _d.startRir = v),
            stepper('Final build RIR', _d.endRir, 0, 10, (v) => _d.endRir = v),
            stepper('Deload RIR', _d.deloadRir, 0, 10, (v) => _d.deloadRir = v),
            SwitchListTile(
              title: LabelWithInfo(
                const Text('Allow target RIR override'),
                InfoDot(tooltip: 'Prescribed RIR target', onTap: () => showRirOverrideInfo(context)),
              ),
              subtitle: const Text('Lets a calculator replace the prescribed target; actual RIR is always editable'),
              value: !_d.rirLock,
              onChanged: _toggleOverride,
            ),
            SwitchListTile(
              title: LabelWithInfo(
                const Text('Lock rest times'),
                InfoDot(tooltip: 'Lock rest times', onTap: () => showRestLockInfo(context)),
              ),
              subtitle: const Text('Rest timers follow the workout plan and cannot be edited during the cycle'),
              value: _d.restLock,
              onChanged: (v) => setState(() => _d.restLock = v),
            ),
          ]),
          const SectionLabel('Deload'),
          group([
            SwitchListTile(
              title: const Text('Plan it myself'),
              subtitle: const Text('Off: use suggested deload based on your settings'),
              value: _d.deloadManual,
              onChanged: (v) => setState(() => _d.deloadManual = v),
            ),
            if (!_d.deloadManual) ...[
              stepper('Weight kept %', _d.deloadLoadPct, 1, 100, (v) => _d.deloadLoadPct = v, step: 5),
              stepper('Sets kept %', _d.deloadVolumePct, 1, 100, (v) => _d.deloadVolumePct = v, step: 5),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Weight kept is based on your last matching workout before deload. For example, 90% of 100 '
                '${store.settings.unit} is about 90 ${store.settings.unit}. Sets kept is a percentage of planned working '
                'sets; the result rounds to the nearest set, with at least one set: 50% of 3 sets becomes 2. Intensifier and cluster '
                'methods normally become one straight set.',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ]),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(error, style: t.bodyMedium?.copyWith(color: cs.error)),
            ),
          if (widget.past) ...[
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                _apply(widget.cycle);
                store.saveCycle(widget.cycle);
                Navigator.pop(context);
                notify(context, 'Mesocycle continued.');
              },
              child: const Text('Continue this mesocycle'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: cs.error),
              onPressed: () async {
                final ok = await confirm(
                  context,
                  'Delete mesocycle',
                  'Its calendar is removed; workout history is kept.',
                  action: 'Delete',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                store.deleteCycle(widget.cycle);
                Navigator.pop(context);
              },
              child: const Text('Delete mesocycle'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StartingLoadSetup extends StatelessWidget {
  final Mesocycle draft;
  final int percent;
  final ValueChanged<int> onChanged;
  const _StartingLoadSetup({required this.draft, required this.percent, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final plans = draft.startingLoads.entries.where((e) => draft.schedule.containsValue(e.key)).toList();
    return Card(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: context.style.sp(8)),
            child: Row(
              children: [
                Expanded(
                  child: LabelWithInfo(
                    const Text('Last build loads'),
                    InfoDot(
                      tooltip: 'Starting loads',
                      onTap: () => _infoDialog(context, 'Starting loads', const [
                        (
                          '',
                          'Scale the last compatible build loads from the previous cycle. Saved workout defaults are used when there is no matching history; unknown loads stay blank. Loads round down to available plates or the exercise increment, with the bar as the minimum. Bodyweight and assisted exercises are unchanged. This applies only to the first workout of each exercise in the new cycle; calibration and later progression still work as usual.',
                        ),
                      ]),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: percent > 50 ? () => onChanged(percent - 5) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '$percent%',
                    textAlign: TextAlign.center,
                    style: t.titleMedium?.copyWith(fontFeatures: tabular),
                  ),
                ),
                IconButton(
                  onPressed: percent < 150 ? () => onChanged(percent + 5) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          if (plans.isNotEmpty)
            ExpansionTile(
              title: const Text('View loads'),
              shape: const Border(),
              collapsedShape: const Border(),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (final plan in plans) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        store.template(plan.key)?.name ?? 'Workout',
                        style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                  for (final exercise in plan.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              exercise.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              '${exercise.work.where((s) => s.weight != null).map((s) => formatNumber(s.weight!, NumKind.weight)).toSet().join(' / ')} ${draft.startingLoadUnit}',
                              textAlign: TextAlign.right,
                              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

Future<void> editWeeklyRir(BuildContext context, Mesocycle cycle) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => WeeklyRirEditor(cycle: cycle)));
}

/// Per-week RIR targets with the Steady and "Ramp 4 → 1" presets.
class WeeklyRirEditor extends StatefulWidget {
  final Mesocycle cycle;
  const WeeklyRirEditor({super.key, required this.cycle});

  @override
  State<WeeklyRirEditor> createState() => _WeeklyRirEditorState();
}

class _WeeklyRirEditorState extends State<WeeklyRirEditor> {
  late final Mesocycle c = widget.cycle;
  late final int total = cycleStatus(c).totalMicro;
  late final int buildWeeks = cycleStatus(c).buildMicro;
  late final List<int> _rir = [for (var w = 1; w <= total; w++) rirForWeek(c, w)];
  late bool _steady =
      c.rirScheduleMode != 'custom' &&
      _rir.take(buildWeeks).toSet().length == 1 &&
      _rir.skip(buildWeeks).every((v) => v == 4) &&
      c.weekRir.length == total;
  late int _steadyLevel = _steady ? _rir.first : 3;

  void _useSteady() => setState(() {
    _steadyLevel = _steady ? (_steadyLevel > 1 ? _steadyLevel - 1 : 3) : _steadyLevel;
    _steady = true;
    for (var i = 0; i < total; i++) {
      _rir[i] = i >= buildWeeks ? 4 : _steadyLevel;
    }
  });

  void _useRamp() => setState(() {
    _steady = false;
    _steadyLevel = 3;
    for (var i = 0; i < total; i++) {
      final n = i + 1;
      _rir[i] = n > buildWeeks
          ? 4
          : buildWeeks == 1
          ? 1
          : buildWeeks < 4
          ? 4 - (3 * (n - 1) / (buildWeeks - 1)).round()
          : 4 - math.min(3, 4 * (n - 1) ~/ buildWeeks);
    }
  });

  void _apply() {
    final draft = Mesocycle.fromJson(c.toJson())..weekRir = {for (var i = 0; i < total; i++) i + 1: _rir[i]};
    final error = deloadEffortError(draft);
    if (error != null) return notify(context, error);
    c
      ..weekRir = draft.weekRir
      ..rirScheduleMode = _steady ? 'steady' : 'custom';
    StoreScope.read(context).changed();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final period = c.periodNoun();
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly RIR')),
      body: ListView(
        padding: subPageInsets,
        children: [
          Text('Presets', style: t.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.repeat_rounded),
                onPressed: _useSteady,
                label: Text('Steady · $_steadyLevel RIR'),
              ),
              OutlinedButton(onPressed: _useRamp, child: const Text('Ramp 4 → 1')),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < total; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${period[0].toUpperCase()}${period.substring(1)} ${i + 1}${i + 1 > buildWeeks ? ' · Deload' : ''}',
                      style: t.bodyLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: (_steady && i >= buildWeeks) || _rir[i] <= 0
                        ? null
                        : () => setState(() {
                            _rir[i]--;
                            if (_steady && i < buildWeeks) {
                              _steadyLevel = _rir[i];
                              for (var k = 0; k < buildWeeks; k++) {
                                _rir[k] = _steadyLevel;
                              }
                            }
                          }),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text('${_rir[i]}', textAlign: TextAlign.center, style: t.titleMedium),
                  ),
                  IconButton(
                    onPressed: (_steady && i >= buildWeeks) || _rir[i] >= 10
                        ? null
                        : () => setState(() {
                            _rir[i]++;
                            if (_steady && i < buildWeeks) {
                              _steadyLevel = _rir[i];
                              for (var k = 0; k < buildWeeks; k++) {
                                _rir[k] = _steadyLevel;
                              }
                            }
                          }),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(onPressed: _apply, child: const Text('Apply')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
