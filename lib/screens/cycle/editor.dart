part of '../cycle.dart';

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
