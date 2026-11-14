part of '../cycle.dart';

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
            if (starterPrograms(store.templates) case final programs when programs.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final chosen = await showDialog<StarterProgram>(
                    context: context,
                    builder: (c) => SimpleDialog(
                      title: const Text('Starter programs'),
                      children: [
                        for (final p in programs)
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                            title: Text(p.name),
                            subtitle: Text(p.summary),
                            onTap: () => Navigator.pop(c, p),
                          ),
                      ],
                    ),
                  );
                  if (chosen == null || !context.mounted) return;
                  // Weeks start on Monday, so the schedule's days mean what the program says.
                  final today = dateOnly(DateTime.now());
                  editCycle(
                    context,
                    Mesocycle(
                      id: 'C${DateTime.now().microsecondsSinceEpoch}',
                      name: chosen.name,
                      start: addDays(today, 1 - today.weekday),
                      schedule: Map.of(chosen.schedule),
                    ),
                    isNew: true,
                    onCreated: store.beginCycleSetup,
                  );
                },
                child: const Text('Starter programs'),
              ),
            ],
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
    final todayName = dueWorkouts(cycle, store.history).map((id) => store.template(id)?.name).nonNulls.firstOrNull;
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
                        status.phase == 'Upcoming'
                            ? 'Starts ${fmtShortDate(status.start)}'
                            : status.phase == 'Complete'
                            ? ''
                            : todayName == null
                            ? 'Today: nothing due'
                            : 'Today: $todayName',
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
    ].where((id) => store.template(id) != null).toList();
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
    // A seven-day microcycle repeats on the same weekdays, so its days are named and listed Monday first.
    final weekly = cycle.microDays == 7;
    DateTime dateOf(int d) => addDays(cycle.start, d - 1);
    final days = [for (var d = 1; d <= cycle.microDays; d++) d];
    if (weekly) days.sort((a, b) => dateOf(a).weekday.compareTo(dateOf(b).weekday));
    return Card(
      child: Column(
        children: [
          for (final (i, d) in days.indexed) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            InkWell(
              onTap: () async {
                final id = await pickTemplate(
                  context,
                  cycle.schedule[d],
                  title: weekly ? 'Schedule ${fmtWeekday(dateOf(d))} (day $d)' : 'Schedule day $d',
                );
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
                    SizedBox(
                      width: 56,
                      child: weekly
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(fmtWeekday(dateOf(d)), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                                Text('Day $d', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                              ],
                            )
                          : Text('Day $d', style: t.labelSmall),
                    ),
                    Expanded(
                      child: Text(
                        // A scheduled workout that was deleted is shown as missing, never as a rest day.
                        store.template(cycle.schedule[d])?.name ??
                            (cycle.schedule[d] == null ? 'Rest' : '? Deleted workout'),
                        style: cycle.schedule[d] == null
                            ? t.bodyLarge?.copyWith(color: cs.onSurfaceVariant)
                            : t.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: store.template(cycle.schedule[d]) == null ? cs.error : null,
                              ),
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

/// The RP landmarks of [muscle], its optional [sets] (planned unless [setsLabel] says otherwise), the coach's
/// [verdict] with the exercises behind it, and how to read the weekly-sets bar.
void showLandmarkInfo(
  BuildContext context,
  String muscle, {
  double? sets,
  String setsLabel = 'Planned weekly sets',
  double? performed,
  MuscleVerdict? verdict,
  bool goalEditable = false,
  PersonalRange? personal,
  String? feel,
  List<String> changes = const [],
  bool charts = false,
}) {
  final l = rpLandmarks[muscle];
  final store = StoreScope.read(context);
  final partialSets = store.settings.includePartialSets;
  final past = charts ? store.muscleHistory(muscle) : null;
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(muscle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (goalEditable && store.activeCycle != null) ...[
              // What the coach is told about this muscle for the running mesocycle.
              StatefulBuilder(
                builder: (c, setGoal) => SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: '', label: Text('Grow')),
                      ButtonSegment(value: 'maintain', label: Text('Maintain')),
                      ButtonSegment(value: 'priority', label: Text('Priority')),
                    ],
                    selected: {store.activeCycle?.muscleGoals[muscle] ?? ''},
                    onSelectionChanged: (v) => setGoal(() => store.setMuscleGoal(muscle, v.first)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Grow: normal coaching. Maintain: the coach changes no sets and only reports a drop. '
                'Priority: first in line when sets are added.',
                style: Theme.of(c).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
            ],
            if (sets != null) ...[
              Row(
                children: [
                  Expanded(child: Text(setsLabel)),
                  const SizedBox(width: 12),
                  Text(
                    fmtSets(sets),
                    style: Theme.of(c).textTheme.titleLarge?.copyWith(
                      color: weeklySetsColor(Theme.of(c).colorScheme, muscle, sets),
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
              if (performed != null)
                Row(
                  children: [
                    const Expanded(child: Text('Completed so far this week')),
                    const SizedBox(width: 12),
                    Text(fmtSets(performed), style: Theme.of(c).textTheme.titleLarge?.copyWith(fontFeatures: tabular)),
                  ],
                ),
              const SizedBox(height: 16),
            ],
            if (verdict != null) ...[
              Text(switch (verdict.trend) {
                Trend.progressing => 'Progressing',
                Trend.holding => 'Holding',
                Trend.falling => 'Falling',
              }, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              for (final e in verdict.exercises)
                Row(
                  children: [
                    Expanded(child: Text(e.name)),
                    const SizedBox(width: 12),
                    Text(fmtTrend(e.percent), style: TextStyle(color: trendColor(Theme.of(c).colorScheme, e.trend))),
                  ],
                ),
              if (verdict.fatigue.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Signs of fatigue: ${verdict.fatigue.join('; ')}.', style: Theme.of(c).textTheme.bodySmall),
              ],
              if (feel != null) ...[
                const SizedBox(height: 4),
                Text('Check-in: $feel.', style: Theme.of(c).textTheme.bodySmall),
              ],
              if (sets != null && zoneAdvice(verdict.trend, volumeZone(muscle, sets)).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '${volumeZone(muscle, sets)}: ${zoneAdvice(verdict.trend, volumeZone(muscle, sets))}',
                  style: Theme.of(c).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
            ],
            if (past != null && past.sets.any((v) => v > 0)) ...[
              if (past.strength case final strength?) ...[
                Row(
                  children: [
                    const Expanded(
                      child: Text('Strength, last 12 weeks', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Text(
                      fmtTrend(strength.last),
                      style: TextStyle(color: trendColor(Theme.of(c).colorScheme, trendOf(strength.last))),
                    ),
                  ],
                ),
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: LineChartPainter(values: strength, color: Theme.of(c).colorScheme.primary, fill: false),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text('Completed sets per week', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: CustomPaint(painter: _WeeklySetsBars(past.sets, l, Theme.of(c).colorScheme)),
              ),
              const SizedBox(height: 4),
              Text(
                'Oldest week on the left. The tinted band is MEV to the top of MAV; above it is the MRV range.',
                style: Theme.of(c).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
            ],
            if (changes.isNotEmpty) ...[
              const Text('Set changes this mesocycle', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              for (final line in changes) Text(line),
              const SizedBox(height: 16),
            ],
            if (personal != null) ...[
              const Text('Your range', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'From ${personal.cycles} earlier mesocycles: it progressed from ${fmtSets(personal.low)} weekly sets'
                '${personal.high == null ? ' and has not yet fallen at a higher volume.' : ', and first fell at ${fmtSets(personal.high!)}.'}'
                ' The thin line under the bar shows it.',
              ),
              const SizedBox(height: 16),
            ],
            const Text('What the landmarks mean', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'MV: maintenance volume. MEV: minimum effective volume. MAV: maximum adaptive volume. '
              'MRV: maximum recoverable volume. Values are hard sets per week.',
            ),
            const SizedBox(height: 8),
            Text(
              partialSets
                  ? 'These are general references, not personal targets. The weekly estimate counts indirect sets as half a '
                        'set, so it may not be directly comparable to these ranges. Special set methods are estimated in '
                        'straight-set equivalents.'
                  : 'These are general references, not personal targets. The weekly estimate counts direct sets only, '
                        'with special set methods estimated in straight-set equivalents.',
            ),
            const SizedBox(height: 8),
            const Text('Reading the bar', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'The light part runs from MEV to MAV, the solid part is the MAV range, and the orange end is the MRV '
              'range. The numbers beneath are where these zones begin and end; the small mark is your weekly sets.',
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

/// Estimated-1RM change as written by the coach: +2.1 %, −0.8 %.
String fmtTrend(double percent) => '${percent < 0 ? '−' : '+'}${percent.abs().toStringAsFixed(1)} %';

Color trendColor(ColorScheme cs, Trend trend) => switch (trend) {
  Trend.progressing => cs.success,
  Trend.holding => cs.onSurfaceVariant,
  Trend.falling => cs.error,
};

/// Weekly sets as written on the Coach tab: up to two decimals, no trailing zeros (7.5, 12).
String fmtSets(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

/// Weekly sets are muted below MEV and warning-coloured from MRV up; otherwise plain.
Color weeklySetsColor(ColorScheme cs, String muscle, double sets) {
  final l = rpLandmarks[muscle];
  final mev = l?.mevRange, mrv = l?.mrvRange;
  return mev != null && sets < mev.$1
      ? cs.onSurfaceVariant
      : mrv != null && sets >= mrv.$1
      ? cs.warning
      : cs.onSurface;
}

/// A full-width landmark bar with a small muscle label at the left and weekly frequency at the right. Tapping
/// reveals the exact weekly sets. [delta], when given, is the change from the saved plan (the workout editor's
/// weekly-sets sheet). [frequency] adds direct training days per week and [verdict] the coach's arrow, both
/// on the Coach tab, where [setsLabel] names sets that are not the plan.
class MuscleVolumeRow extends StatefulWidget {
  final String muscle;
  final double sets;
  final double? delta;
  final double? frequency;
  final MuscleVerdict? verdict;
  final String setsLabel;

  /// Sets completed so far this week, drawn as a second, solid mark beside the planned one.
  final double? performed;

  /// The coach goal of this muscle in the running cycle ('maintain', 'priority' or null), named after the
  /// muscle; [goalEditable] lets the tap dialog change it.
  final String? goal;
  final bool goalEditable;

  /// The muscle's own range from earlier mesocycles, drawn as a thin line under the track.
  final PersonalRange? personal;

  /// Latest check-in answers in words and the cycle's applied set changes, both for the tap dialog.
  final String? feel;
  final List<String> changes;

  /// A short warning after the name, such as too many sets for the muscle in one workout.
  final String? warning;

  /// Show the muscle's twelve-week strength and weekly-sets charts in the tap dialog.
  final bool charts;
  const MuscleVolumeRow({
    super.key,
    required this.muscle,
    required this.sets,
    this.delta,
    this.frequency,
    this.verdict,
    this.setsLabel = 'Planned weekly sets',
    this.performed,
    this.goal,
    this.goalEditable = false,
    this.personal,
    this.feel,
    this.changes = const [],
    this.warning,
    this.charts = false,
  });

  @override
  State<MuscleVolumeRow> createState() => _MuscleVolumeRowState();
}

class _MuscleVolumeRowState extends State<MuscleVolumeRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final l = rpLandmarks[widget.muscle];
    final change = widget.delta;
    final scaler = MediaQuery.textScalerOf(context);
    final numberStyle = t.labelSmall!.copyWith(fontSize: 9, color: cs.onSurfaceVariant, fontFeatures: tabular);
    // Keep case intact for real small-cap glyph substitution. Names match the scale's font size; frequency
    // stays smaller, with both labels kept faint.
    final labelStyle = t.labelSmall!.copyWith(
      fontSize: numberStyle.fontSize,
      fontWeight: FontWeight.w400,
      color: cs.onSurfaceVariant.withValues(alpha: 0.65),
      letterSpacing: 0.1,
      height: 1,
      fontFeatures: const [FontFeature.enable('smcp'), FontFeature.tabularFigures()],
    );
    final frequencyStyle = labelStyle.copyWith(fontSize: 7.5);
    final numbers = TextPainter(
      text: TextSpan(text: '0', style: numberStyle),
      textScaler: scaler,
      textDirection: TextDirection.ltr,
    )..layout();
    return Semantics(
      label:
          '${widget.muscle}, ${fmtSets(widget.sets)} ${widget.setsLabel.toLowerCase()}'
          '${widget.performed == null ? '' : ', ${fmtSets(widget.performed!)} completed so far'}',
      child: InkWell(
        onTap: () => showLandmarkInfo(
          context,
          widget.muscle,
          sets: widget.sets,
          setsLabel: widget.setsLabel,
          performed: widget.performed,
          verdict: widget.verdict,
          goalEditable: widget.goalEditable,
          personal: widget.personal,
          feel: widget.feel,
          changes: widget.changes,
          charts: widget.charts,
        ),
        onHighlightChanged: (pressed) {
          if (_pressed != pressed) setState(() => _pressed = pressed);
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: context.style.sp(4)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.goal == null ? widget.muscle : '${widget.muscle} · ${widget.goal}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
                      ),
                    ),
                    if (widget.verdict case final verdict?)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          switch (verdict.trend) {
                            Trend.progressing => Icons.trending_up_rounded,
                            Trend.holding => Icons.trending_flat_rounded,
                            Trend.falling => Icons.trending_down_rounded,
                          },
                          size: 12,
                          color: trendColor(cs, verdict.trend),
                        ),
                      ),
                    if (widget.warning case final warning?)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(warning, style: labelStyle.copyWith(color: cs.warning)),
                      ),
                    const Spacer(),
                    if (change != null && change.abs() > 1e-9)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '${change > 0 ? '+' : '−'}${fmtSets(change.abs())}',
                          style: labelStyle.copyWith(color: cs.primary),
                        ),
                      ),
                    if (widget.frequency case final days?)
                      Tooltip(
                        message:
                            'Direct training days per week. Each day counts once, including '
                            'special set methods. Warm-ups and indirect work do not count. Schedules longer or '
                            'shorter than seven days are averaged per week.',
                        child: Text('${fmtSets(days)} ${days == 1 ? 'day' : 'days'}/week', style: frequencyStyle),
                      ),
                  ],
                ),
                if (l != null && l.mavRange != null) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    height: _LandmarkBar.trackHeight + 2 + numbers.height,
                    child: CustomPaint(
                      painter: _LandmarkBar(
                        sets: widget.sets,
                        performed: widget.performed,
                        personal: widget.personal,
                        landmark: l,
                        colors: cs,
                        numberStyle: numberStyle,
                        textScaler: scaler,
                        pressed: _pressed,
                      ),
                    ),
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

/// A 4 px track: faint from MEV to MAV, solid across MAV, warning across MRV to the bar's end, and a small mark at
/// [sets]. Beneath the track, 0 and each zone boundary
/// (MEV start, MAV start and end, MRV start and end) is a small number centred on its position; a number that
/// would touch its neighbour is left out.
class _LandmarkBar extends CustomPainter {
  static const trackHeight = 14.0;
  final double sets;
  final double? performed;
  final PersonalRange? personal;
  final Landmark landmark;
  final ColorScheme colors;
  final TextStyle numberStyle;
  final TextScaler textScaler;
  final bool pressed;
  const _LandmarkBar({
    required this.sets,
    this.performed,
    this.personal,
    required this.landmark,
    required this.colors,
    required this.numberStyle,
    required this.textScaler,
    required this.pressed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mev = landmark.mevRange, mav = landmark.mavRange!, mrv = landmark.mrvRange;
    // The scale ends exactly at the top of MRV, so its number sits at the bar's right end. Planned sets beyond it
    // stretch the scale a little past the mark; without an MRV, the track runs a quarter past MAV.
    final end = mrv?.$2 ?? mav.$2 * 1.25;
    final most = math.max(math.max(sets, performed ?? 0), personal?.low ?? 0);
    final top = most > end ? most * 1.04 : end;
    double x(double v) => (v / top).clamp(0.0, 1.0) * size.width;
    TextPainter text(String s, TextStyle style) => TextPainter(
      text: TextSpan(text: s, style: style),
      textScaler: textScaler,
      textDirection: TextDirection.ltr,
    )..layout();
    double centred(double at, TextPainter tp) =>
        (at - tp.width / 2).clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble();

    const mid = trackHeight / 2;
    final track = RRect.fromRectAndRadius(Rect.fromLTRB(0, mid - 2, size.width, mid + 2), const Radius.circular(2));
    canvas
      ..save()
      ..clipRRect(track)
      ..drawRRect(track, Paint()..color = colors.onSurface.withValues(alpha: 0.08));
    void zone(double from, double to, Color color) =>
        canvas.drawRect(Rect.fromLTRB(x(from), mid - 2, x(to), mid + 2), Paint()..color = color);
    zone(mev?.$1 ?? mav.$1, mav.$1, colors.primary.withValues(alpha: 0.25));
    zone(mav.$1, mav.$2, colors.primary.withValues(alpha: 0.6));
    if (mrv != null) zone(mrv.$1, top, colors.warning.withValues(alpha: 0.45));
    canvas.restore();

    final boundaries = <double>{0, ?mev?.$1, mav.$1, mav.$2, ?mrv?.$1, ?mrv?.$2}.toList()..sort();
    var lastRight = double.negativeInfinity;
    for (final v in boundaries) {
      final tp = text(v == v.roundToDouble() ? '${v.round()}' : '$v', numberStyle);
      final left = centred(x(v), tp);
      if (left < lastRight + 4) continue;
      tp.paint(canvas, Offset(left, trackHeight + 2));
      lastRight = left + tp.width;
    }

    // The muscle's own range: a thin line between the track and its numbers, open-ended until it has fallen.
    if (personal case final own?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            x(own.low),
            mid + 4,
            own.high == null ? size.width : math.max(x(own.high!), x(own.low) + 2),
            mid + 6,
          ),
          const Radius.circular(1),
        ),
        Paint()..color = colors.info,
      );
    }
    // Completed sets: a short solid mark inside the track, under the longer faint planned tick.
    if (performed case final done?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x(done).clamp(1.5, size.width - 1.5), mid), width: 3, height: 8),
          const Radius.circular(1.5),
        ),
        Paint()..color = colors.onSurface,
      );
    }
    final width = pressed ? 3.0 : 1.0;
    final mark = x(sets).clamp(width / 2, size.width - width / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(mark, mid), width: width, height: trackHeight),
        Radius.circular(width / 2),
      ),
      Paint()..color = colors.onSurface.withValues(alpha: pressed ? 1 : 0.4),
    );
  }

  @override
  bool shouldRepaint(_LandmarkBar old) =>
      old.sets != sets ||
      old.performed != performed ||
      old.personal != personal ||
      old.landmark != landmark ||
      old.colors != colors ||
      old.numberStyle != numberStyle ||
      old.textScaler != textScaler ||
      old.pressed != pressed;
}

/// Completed weekly sets of one muscle as bars, oldest week first, over its landmark bands: MEV to the top of
/// MAV tinted with the accent, the MRV range above it with the warning colour.
class _WeeklySetsBars extends CustomPainter {
  final List<double> sets;
  final Landmark? landmark;
  final ColorScheme colors;
  const _WeeklySetsBars(this.sets, this.landmark, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final mev = landmark?.mevRange, mav = landmark?.mavRange, mrv = landmark?.mrvRange;
    final top = [...sets, mrv?.$2 ?? mav?.$2 ?? 0.0].reduce(math.max) * 1.05;
    if (top <= 0) return;
    double y(double v) => size.height - v / top * size.height;
    if (mav != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, y(mav.$2), size.width, y(mev?.$1 ?? mav.$1)),
        Paint()..color = colors.primary.withValues(alpha: 0.12),
      );
    }
    if (mrv != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, y(mrv.$2), size.width, y(mrv.$1)),
        Paint()..color = colors.warning.withValues(alpha: 0.14),
      );
    }
    final slot = size.width / sets.length;
    for (final (i, v) in sets.indexed) {
      if (v <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(i * slot + slot * 0.2, y(v), (i + 1) * slot - slot * 0.2, size.height),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        Paint()..color = colors.onSurface.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(_WeeklySetsBars old) => old.sets != sets || old.landmark != landmark || old.colors != colors;
}
