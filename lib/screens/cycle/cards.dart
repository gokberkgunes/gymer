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
                store.settings.includePartialSets
                    ? 'Planned per week from your schedule; indirect sets count half. Tap a muscle for its landmarks.'
                    : 'Planned per week from your schedule; direct sets only. Tap a muscle for its landmarks.',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
            const SizedBox(height: 4),
            for (final m in names)
              MuscleVolumeRow(
                muscle: m,
                sets: volume[m]!.countedSets(includePartialSets: store.settings.includePartialSets),
                frequency: volume[m]!.directDaysPerWeek,
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
}

/// The RP landmarks of [muscle] and how to read its weekly-sets bar.
void showLandmarkInfo(BuildContext context, String muscle) {
  final l = rpLandmarks[muscle];
  final partialSets = StoreScope.read(context).settings.includePartialSets;
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
            Text(
              partialSets
                  ? 'These are general references, not personal targets. The weekly estimate counts indirect sets as half a '
                        'set, so it may not be directly comparable to these ranges.'
                  : 'These are general references, not personal targets. The weekly estimate counts direct conventional sets only.',
            ),
            const SizedBox(height: 8),
            const Text('Reading the bar', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'The light part runs from MEV to MAV, the solid part is the MAV range, and the orange end is the MRV '
              'range. The numbers beneath are where these zones begin and end; the small mark is your planned '
              'weekly sets.',
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

/// Weekly sets as written on the Cycle tab: up to two decimals, no trailing zeros (7.5, 12).
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

/// One muscle's weekly sets: name and number on one line, with a thin landmark bar beneath and the landmark
/// boundaries as small muted numbers under it. No names, legends or chevrons: the dialog behind the tap explains
/// the bar. [delta], when given, is the change from the saved plan (the workout editor's weekly-sets sheet).
/// [frequency] adds direct training days per week beside the name on the Cycle tab.
class MuscleVolumeRow extends StatelessWidget {
  final String muscle;
  final double sets;
  final double? delta;
  final double? frequency;
  const MuscleVolumeRow({super.key, required this.muscle, required this.sets, this.delta, this.frequency});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final l = rpLandmarks[muscle];
    final numberColor = weeklySetsColor(cs, muscle, sets);
    final change = delta;
    return InkWell(
      onTap: () => showLandmarkInfo(context, muscle),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: context.style.sp(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          muscle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (frequency case final days?) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message:
                              'Planned direct training days per week. Each scheduled day counts once, including '
                              'special set methods. Warm-ups and indirect work do not count. Schedules longer or '
                              'shorter than seven days are averaged per week.',
                          child: Text(
                            '${fmtSets(days)}×/week',
                            style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (change != null && change.abs() > 1e-9)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '${change > 0 ? '+' : '−'}${fmtSets(change.abs())}',
                      style: t.labelMedium?.copyWith(color: cs.primary, fontFeatures: tabular),
                    ),
                  ),
                Text(
                  '${fmtSets(sets)} ${sets == 1 ? 'set' : 'sets'}',
                  style: t.bodyMedium?.copyWith(color: numberColor, fontFeatures: tabular),
                ),
              ],
            ),
            if (l != null && l.mavRange != null) ...[
              const SizedBox(height: 2),
              Builder(
                builder: (context) {
                  final scaler = MediaQuery.textScalerOf(context);
                  final style = t.labelSmall!.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular);
                  final numbers = TextPainter(
                    text: TextSpan(text: '0', style: style),
                    textScaler: scaler,
                    textDirection: TextDirection.ltr,
                  )..layout();
                  return SizedBox(
                    // The planned sets above the track, the landmark numbers below it.
                    height: numbers.height + 2 + _LandmarkBar.trackHeight + 2 + numbers.height,
                    child: CustomPaint(
                      painter: _LandmarkBar(
                        sets: sets,
                        landmark: l,
                        colors: cs,
                        numberStyle: style,
                        plannedColor: numberColor,
                        textScaler: scaler,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A 4 px track: faint from MEV to MAV, solid across MAV, warning across MRV to the bar's end, and a small mark at
/// [sets], with the planned sets (rounded) written above the mark. Beneath the track, 0 and each zone boundary
/// (MEV start, MAV start and end, MRV start and end) is a small number centred on its position; a number that
/// would touch its neighbour is left out.
class _LandmarkBar extends CustomPainter {
  static const trackHeight = 10.0;
  final double sets;
  final Landmark landmark;
  final ColorScheme colors;
  final TextStyle numberStyle;
  final Color plannedColor;
  final TextScaler textScaler;
  const _LandmarkBar({
    required this.plannedColor,
    required this.sets,
    required this.landmark,
    required this.colors,
    required this.numberStyle,
    required this.textScaler,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mev = landmark.mevRange, mav = landmark.mavRange!, mrv = landmark.mrvRange;
    // The scale ends exactly at the top of MRV, so its number sits at the bar's right end. Planned sets beyond it
    // stretch the scale a little past the mark; without an MRV, the track runs a quarter past MAV.
    final end = mrv?.$2 ?? mav.$2 * 1.25;
    final top = sets > end ? sets * 1.04 : end;
    double x(double v) => (v / top).clamp(0.0, 1.0) * size.width;
    TextPainter text(String s, TextStyle style) => TextPainter(
      text: TextSpan(text: s, style: style),
      textScaler: textScaler,
      textDirection: TextDirection.ltr,
    )..layout();
    double centred(double at, TextPainter tp) =>
        (at - tp.width / 2).clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble();

    final planned = text('${sets.round()}', numberStyle.copyWith(color: plannedColor, fontWeight: FontWeight.w700));
    planned.paint(canvas, Offset(centred(x(sets), planned), 0));
    canvas
      ..save()
      ..translate(0, planned.height + 2);
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

    final mark = x(sets).clamp(1.5, size.width - 1.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(mark, mid), width: 3, height: trackHeight),
        const Radius.circular(1.5),
      ),
      Paint()..color = colors.onSurface,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LandmarkBar old) =>
      old.sets != sets ||
      old.landmark != landmark ||
      old.colors != colors ||
      old.numberStyle != numberStyle ||
      old.plannedColor != plannedColor ||
      old.textScaler != textScaler;
}
