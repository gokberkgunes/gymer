import 'package:flutter/material.dart';

import '../logic/circuits.dart';
import '../logic/estimate.dart';
import '../logic/methods.dart';
import '../logic/numbers.dart';
import '../logic/volume.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/circuit_editor.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/num_field.dart';
import 'exercises.dart';
import 'session.dart' show pickSetType;

void editTemplate(BuildContext context, WorkoutTemplate tpl, {bool fromActive = false}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TemplateEditor(original: tpl, fromActive: fromActive),
    ),
  );
}

const methodBlurbs = {
  'Straight': 'Regular sets with double progression',
  'AMRAP': 'As many reps as possible at one load',
  'Myo-Reps': 'Activation set, then short myo-sets',
  'Rest-Pause': 'Activation set, then brief-rest mini sets',
  'Drop Set': 'Activation set, then lighter drops',
  'Mechanical Drop Set': 'Same load, easier leverage each segment',
  'Cluster': 'Short clusters with mini rests',
  'Myo-Rep Match': 'Match the activation reps in each segment',
};

Future<String?> pickMethod(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          for (final m in trainingMethods)
            ListTile(
              title: Text(m),
              subtitle: Text(methodBlurbs[m] ?? ''),
              trailing: m == current ? Icon(Icons.check_rounded, color: Theme.of(sheet).colorScheme.primary) : null,
              onTap: () => Navigator.pop(sheet, m),
            ),
        ],
      ),
    ),
  );
}

class TemplateEditor extends StatefulWidget {
  final WorkoutTemplate original;
  final bool fromActive;
  const TemplateEditor({super.key, required this.original, this.fromActive = false});

  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  late final WorkoutTemplate _d = WorkoutTemplate.fromJson(widget.original.toJson());
  late final _name = TextEditingController(text: _d.name);
  late final _description = TextEditingController(text: _d.description);
  final _missingName = <TemplateExercise>{};
  bool _nameInvalid = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  AppStore get _store => StoreScope.read(context);
  bool get _isNew => !_store.templates.any((t) => t.id == _d.id);

  /// An active workout of this template locks protocol groups and methods.
  bool get _groupsLocked => _store.active?.templateId == _d.id;

  String _groupSignature(WorkoutTemplate t) => [
    for (final e in t.exercises)
      if (e.sets.any((s) => s.groupStart))
        '${e.name.toLowerCase()}|${e.method}|${[for (final (i, s) in e.sets.indexed)
          if (s.groupStart) i]}',
  ].join(';');

  Future<void> _save() async {
    final store = _store;
    _d
      ..name = _name.text.trim()
      ..description = _description.text.trim();
    setState(() {
      _nameInvalid = _d.name.isEmpty;
      _missingName
        ..clear()
        ..addAll(_d.exercises.where((e) => e.name.trim().isEmpty));
    });
    if (_nameInvalid || _missingName.isNotEmpty) return;
    reconcileCircuits(_d.circuits, _d.exercises.map((e) => e.name));
    for (final e in _d.exercises) {
      e.reconcile();
      if (e.workSets == 0) return notify(context, '${e.name}: Add at least one working set.');
    }
    if (_groupsLocked && _groupSignature(_d) != _groupSignature(widget.original)) {
      return notify(context, 'Finish or discard this active workout before changing protocol groups or their method.');
    }
    final blocked = store.blockedTemplateEdit(_d);
    if (blocked != null) return notify(context, blocked);
    if (store.activeCycle != null && !_isNew) {
      final ok = await confirm(
        context,
        'Change workout during active mesocycle?',
        'Changing exercises, set counts, rep/load targets or other workout settings can make progressive-overload '
            'comparisons less clean. The change is allowed, but treat it as a deliberate program change rather than '
            'normal progression.',
        action: 'Save change',
      );
      if (!ok || !mounted) return;
    }
    store.saveTemplate(_d);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (_store.active?.templateId == _d.id) {
      return notify(context, 'Finish or discard the active workout before deleting it.');
    }
    final ok = await confirm(
      context,
      'Delete workout',
      'Remove "${_d.name}"? History is kept.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    _store.deleteTemplate(_d.id);
    Navigator.pop(context);
  }

  Future<void> _addExercise() async {
    final name = await pickExercise(context);
    if (name == null || !mounted) return;
    if (_d.exercises.any((x) => x.name.toLowerCase() == name.toLowerCase())) {
      return notify(context, '$name is already in this workout.');
    }
    final s = _store.settings;
    setState(
      () => _d.exercises.add(
        TemplateExercise(
          name: name,
          sets: [for (var i = 0; i < s.defaultSets; i++) TemplateSet(rest: s.defaultRest)],
        ),
      ),
    );
  }

  /// Replacing an exercise keeps sets/rests/types but never carries the
  /// old exercise's loads; the replacement's own latest values are used.
  Future<void> _chooseExercise(TemplateExercise e) async {
    final name = await pickExercise(context);
    if (name == null || !mounted || name.toLowerCase() == e.name.toLowerCase()) return;
    if (_d.exercises.any((x) => x != e && x.name.toLowerCase() == name.toLowerCase())) {
      return notify(context, '$name is already in this workout.');
    }
    final latest = _store.previousSets(name);
    final context0 = _store.exercise(name)?.context ?? const SetContext();
    setState(() {
      renameCircuitExercise(_d.circuits, e.name, name);
      e.name = name;
      _missingName.remove(e);
      for (final (i, s) in e.sets.indexed) {
        final known = i < latest.length && latest[i].done && latest[i].context == context0 ? latest[i] : null;
        s
          ..context = null
          ..weight = known?.weight
          ..reps = known?.reps;
      }
    });
  }

  void _addGroup(TemplateExercise e) {
    if (_groupsLocked) return;
    final work = e.sets.where((s) => !isWarmup(s.type)).toList();
    var start = 0;
    for (var i = 0; i < work.length; i++) {
      if (work[i].groupStart) start = i;
    }
    var source = work.sublist(start);
    if (source.isEmpty) source = [TemplateSet(rest: _store.settings.defaultRest)];
    if (source.length == 1) source = [source.first, source.first];
    setState(() {
      for (final (i, s) in source.indexed) {
        e.sets.add(s.copy()..groupStart = i == 0);
      }
      e.reconcile();
    });
  }

  Future<void> _editCircuit(TemplateExercise e) async {
    final saved = await editExerciseCircuit(
      context,
      exercise: e.name,
      exercises: _d.exercises.map((e) => e.name).toList(),
      circuits: _d.circuits,
      defaultRest: e.restSeconds,
      restLocked: _store.activeCycle?.restLock ?? false,
    );
    if (saved && mounted) setState(() {});
  }

  String? _circuitLabel(TemplateExercise e) {
    final circuit = circuitFor(_d.circuits, e.name);
    return circuit == null ? null : circuitBadge(_d.circuits, circuit, e.name);
  }

  Future<void> _editContext(TemplateExercise e, TemplateSet s) async {
    if (_store.active?.templateId == _d.id) {
      return notify(context, 'Finish or discard this active workout before changing planned segment context.');
    }
    var inherit = s.context == null;
    final base = s.context ?? _store.exercise(e.name)?.context ?? const SetContext();
    final setup = TextEditingController(text: base.setup);
    var load = base.loadBasis, reps = base.repBasis, side = base.side;
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Planned segment context'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: inherit,
                  title: const Text('Inherit exercise defaults'),
                  onChanged: (v) => setDialog(() => inherit = v ?? true),
                ),
                TextField(
                  controller: setup,
                  enabled: !inherit,
                  decoration: const InputDecoration(
                    labelText: 'Setup / variation',
                    hintText: 'e.g. cable station 2, high handle, upright position',
                  ),
                ),
                for (final (label, value, options, set) in [
                  ('Load basis', load, SetContext.loadBasisLabels, (String v) => load = v),
                  ('Rep count basis', reps, SetContext.repBasisLabels, (String v) => reps = v),
                  ('Side', side, SetContext.sideLabels, (String v) => side = v),
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: DropdownButtonFormField<String>(
                      initialValue: value,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: label),
                      items: [
                        for (final o in options.entries)
                          DropdownMenuItem(
                            value: o.key,
                            child: Text(o.value, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: inherit ? null : (v) => set(v ?? ''),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved == true) {
      setState(() {
        final before = s.context;
        s.context = inherit ? null : SetContext(setup: setup.text.trim(), loadBasis: load, repBasis: reps, side: side);
        // A changed context clears the set's inherited load/rep defaults; an unchanged one keeps them.
        if (s.context != before) {
          s
            ..weight = null
            ..reps = null;
        }
      });
    }
    // The dialog is still animating out; release the controller after it is gone.
    WidgetsBinding.instance.addPostFrameCallback((_) => setup.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final cycle = store.activeCycle;
    final restLocked = cycle?.restLock ?? false;
    final timing = store.templateTiming(_d);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isNew ? 'New Workout' : 'Edit Workout'),
        actions: [
          if (!_isNew && !widget.fromActive)
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline_rounded, color: cs.error),
              onPressed: _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        children: [
          if (cycle != null && !_isNew)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Active mesocycle — changing the program can make progressive-overload comparisons less consistent.'
                '${restLocked ? ' Rest times are locked from Cycle.' : ''}',
                style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.warning, fontWeight: FontWeight.w500),
              ),
            ),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Workout name', errorText: _nameInvalid ? 'Enter a name' : null),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            minLines: 1,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Description'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.timer_outlined, size: 18),
              label: Text('~${formatTargetDuration(timing.total).replaceAll(' min', 'm')}'),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TimeApproximator(template: _d)));
                setState(() {});
              },
            ),
          ),
          _PlannedWork(report: store.templateVolume(_d)),
          const SectionLabel('Exercises'),
          for (final (i, e) in _d.exercises.indexed) ...[
            _ExerciseCard(
              key: ObjectKey(e),
              exercise: e,
              invalidName: _missingName.contains(e),
              restLocked: restLocked,
              groupsLocked: _groupsLocked,
              circuitLabel: _circuitLabel(e),
              onCircuit: () => _editCircuit(e),
              onChanged: () => setState(() {}),
              onChoose: () => _chooseExercise(e),
              onDetails: () async {
                if (e.name.isEmpty) return _chooseExercise(e);
                final store = StoreScope.read(context);
                final old = e.name;
                final before = {for (final x in store.exercises) x.name};
                final oldContext = store.exercise(old)?.context;
                await openExerciseEditor(context, old);
                if (!mounted) return;
                // The editor changes the stored templates; this screen edits a copy, so follow its changes.
                final now = store.exercise(old);
                final renamed = now == null ? store.exercises.map((x) => x.name).where((n) => !before.contains(n)).firstOrNull : null;
                if (renamed != null) {
                  renameCircuitExercise(_d.circuits, old, renamed);
                  for (final x in _d.exercises.where((x) => x.name == old)) {
                    x.name = renamed;
                  }
                }
                final current = store.exercise(renamed ?? old);
                if (oldContext != null && current != null && current.context != oldContext) {
                  for (final x in _d.exercises.where((x) => x.name == current.name)) {
                    for (final set in x.sets.where((set) => set.context == null)) {
                      set
                        ..weight = null
                        ..reps = null;
                    }
                  }
                }
                setState(() {});
              },
              onMove: (delta) => setState(() {
                final j = (i + delta).clamp(0, _d.exercises.length - 1);
                _d.exercises.insert(j, _d.exercises.removeAt(i));
                reconcileCircuits(_d.circuits, _d.exercises.map((e) => e.name));
              }),
              onRemove: () => setState(() {
                _d.exercises.removeAt(i);
                reconcileCircuits(_d.circuits, _d.exercises.map((e) => e.name));
              }),
              onAddGroup: () => _addGroup(e),
              onEditContext: (s) => _editContext(e, s),
            ),
            SizedBox(height: context.style.sp(10)),
          ],
          OutlinedButton.icon(
            onPressed: _addExercise,
            icon: const Icon(Icons.add_rounded),
            label: const Text('+ Exercise'),
          ),
        ],
      ),
    );
  }
}

class _PlannedWork extends StatelessWidget {
  final VolumeReport report;
  const _PlannedWork({required this.report});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    List<Widget> section(String title, Map<String, VolumeMetrics> rows) => [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(title, style: t.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
      ),
      if (rows.isEmpty) Text('No tagged work', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      for (final MapEntry(key: m, value: v) in rows.entries) Text('$m: ${v.describe()}', style: t.bodySmall),
    ];
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: const Text('Planned work', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(report.totals.describe(), style: t.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Protocol groups: ${report.totals.completeGroups.round()} complete; ${report.totals.partialGroups.round()} partial or unverified',
            style: t.bodySmall,
          ),
          ...section('Direct involvement', report.direct),
          ...section('Indirect involvement', report.indirect),
          const SizedBox(height: 6),
          Text(
            'Warmups are separate. Protocol groups and segments are not conventional-set equivalents; indirect tags show involvement.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final TemplateExercise exercise;
  final bool invalidName, restLocked, groupsLocked;
  final VoidCallback onChanged, onChoose, onDetails, onRemove, onAddGroup;
  final VoidCallback onCircuit;
  final String? circuitLabel;
  final ValueChanged<int> onMove;
  final ValueChanged<TemplateSet> onEditContext;

  const _ExerciseCard({
    super.key,
    required this.exercise,
    required this.invalidName,
    required this.restLocked,
    required this.groupsLocked,
    required this.onChanged,
    required this.onChoose,
    required this.onDetails,
    required this.onMove,
    required this.onRemove,
    required this.onAddGroup,
    required this.onCircuit,
    this.circuitLabel,
    required this.onEditContext,
  });

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final st = context.style;
    // Inputs one shade lighter than the set tile, as in the workout screen.
    final fieldFill = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(cs.surfaceContainerHigh, Colors.white, 0.07)
        : cs.surface;
    final e = exercise;
    final info = store.exercise(e.name);
    final loadMode = info?.loadMode ?? 'external';
    final weightKind = loadMode == 'external' ? NumKind.weight : NumKind.load;
    final grouped = isGroupedMethod(e.method);
    final note = info?.note.trim() ?? '';

    final rows = <Widget>[];
    var group = 0;
    for (final (i, s) in e.sets.indexed) {
      final working = !isWarmup(s.type);
      if (grouped && working) {
        final canSplit = group > 0;
        if (group == 0 || s.groupStart) {
          group++;
          rows.add(
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text('Protocol group $group', style: t.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
            ),
          );
        }
        if (canSplit) {
          rows.add(
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: groupsLocked
                    ? null
                    : () {
                        s.groupStart = !s.groupStart;
                        e.reconcile();
                        onChanged();
                      },
                child: Text(s.groupStart ? 'Join preceding group' : 'Start group here'),
              ),
            ),
          );
        }
      }
      // Same set tiles as the workout screen: they join into one block at small set gaps.
      rows.add(
        Container(
          margin: EdgeInsets.symmetric(vertical: st.setGap / 2),
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: st.sp(4)),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: st.setTile(i, e.sets.length)),
          child: Row(
            children: [
              SizedBox(
                width: 84,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: compactButton,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  onPressed: () async {
                    final picked = await pickSetType(context, e.method, [
                      for (final x in e.sets) (x.type, x.groupStart),
                    ], i);
                    if (picked == null) return;
                    s.type = picked;
                    e.reconcile();
                    onChanged();
                  },
                  onLongPress: () => onEditContext(s),
                  child: Text(
                    displaySetType(s.type).replaceAll('Straight (Normal)', 'Straight'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 5,
                child: NumField(
                  value: s.weight,
                  kind: weightKind,
                  placeholder: loadSuffix(loadMode, store.settings.unit),
                  suffix: s.weight == null ? null : loadSuffix(loadMode, store.settings.unit),
                  fill: fieldFill,
                  onChanged: (v) => s.weight = v,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 4,
                child: NumField(
                  value: s.reps?.toDouble(),
                  kind: NumKind.reps,
                  placeholder: 'Reps',
                  fill: fieldFill,
                  onChanged: (v) => s.reps = v?.round(),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 4,
                child: DurationField(
                  seconds: s.rest,
                  readOnly: restLocked,
                  fill: fieldFill,
                  tooltip: restLocked ? 'Rest time is locked by the active mesocycle' : null,
                  onChanged: (v) {
                    s.rest = v;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ),
      );
      if (s.context != null) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: 88, bottom: 2),
            child: Text(s.context!.summary(), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        );
      }
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, st.sp(10), 8, st.sp(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: compactButton,
                      alignment: Alignment.centerLeft,
                      side: BorderSide(color: invalidName ? cs.error : cs.outlineVariant, width: invalidName ? 2.2 : 1),
                    ),
                    onPressed: onChoose,
                    child: Text(
                      e.name.isEmpty ? 'Choose exercise' : e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit exercise details',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onDetails,
                ),
                IconButton(
                  tooltip: 'Move up',
                  icon: const Icon(Icons.arrow_upward_rounded),
                  onPressed: () => onMove(-1),
                ),
                IconButton(
                  tooltip: 'Move down',
                  icon: const Icon(Icons.arrow_downward_rounded),
                  onPressed: () => onMove(1),
                ),
                IconButton(
                  tooltip: 'Remove exercise',
                  icon: Icon(Icons.remove_circle_outline_rounded, color: cs.onSurfaceVariant),
                  onPressed: onRemove,
                ),
              ],
            ),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  note,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Flexible(
                  child: ActionChip(
                    avatar: const Icon(Icons.tune_rounded, size: 16),
                    label: Text('Method: ${e.method}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: groupsLocked && grouped
                        ? null
                        : () async {
                            final m = await pickMethod(context, e.method);
                            if (m == null) return;
                            e.replan(method: m);
                            onChanged();
                          },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: circuitLabel == null ? 'Superset / circuit' : 'Edit group $circuitLabel',
                  icon: circuitLabel == null
                      ? const Icon(Icons.link_rounded)
                      : Text(circuitLabel!, style: t.labelMedium),
                  onPressed: onCircuit,
                ),
              ],
            ),
            ...rows,
            Row(
              children: [
                IconButton(
                  tooltip: 'Add set',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () {
                    final last = e.sets.isEmpty ? null : e.sets.last;
                    e.sets.add(
                      TemplateSet(
                        type: defaultNextSetType(e.method, e.types),
                        weight: last?.weight,
                        reps: last?.reps,
                        rest: last?.rest ?? store.settings.defaultRest,
                        context: last?.context,
                      ),
                    );
                    e.reconcile();
                    onChanged();
                  },
                ),
                IconButton(
                  tooltip: 'Remove last set',
                  icon: const Icon(Icons.remove_rounded),
                  onPressed: e.sets.length <= 1
                      ? null
                      : () {
                          e.sets.removeLast();
                          e.reconcile();
                          onChanged();
                        },
                ),
                if (grouped)
                  TextButton.icon(
                    onPressed: groupsLocked ? null : onAddGroup,
                    icon: const Icon(Icons.add_box_outlined, size: 18),
                    label: const Text('Add protocol group'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Workout Time Approximator: tune the estimate to your normal pace.
class TimeApproximator extends StatefulWidget {
  final WorkoutTemplate template;
  const TimeApproximator({super.key, required this.template});

  @override
  State<TimeApproximator> createState() => _TimeApproximatorState();
}

class _TimeApproximatorState extends State<TimeApproximator> {
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final w = widget.template;
    final b = store.templateTiming(w);
    final target = formatTargetDuration(b.total);
    return Scaffold(
      appBar: AppBar(title: const Text('Workout Time Approximator')),
      body: ListView(
        padding: subPageInsets,
        children: [
          Text('Target ~$target', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Use this estimate to check whether the workout fits the time you actually have. If your real sessions '
            'consistently run longer or shorter, adjust the values below until the estimate matches your normal pace.',
          ),
          const SizedBox(height: 16),
          NumField(
            value: w.setSeconds.toDouble(),
            kind: NumKind.count,
            placeholder: 'Default entry duration (seconds)',
            suffix: 's',
            dense: false,
            onChanged: (v) => setState(() => w.setSeconds = v?.round() ?? 45),
          ),
          const SizedBox(height: 4),
          Text('Default entry duration (seconds)', style: t.bodySmall),
          const SizedBox(height: 12),
          DurationField(
            seconds: w.setOverhead,
            label: 'Setup / logging per entry',
            onChanged: (v) => setState(() => w.setOverhead = v),
          ),
          const SizedBox(height: 12),
          DurationField(
            seconds: w.transition,
            label: 'Between exercises',
            onChanged: (v) => setState(() => w.transition = v),
          ),
          const SizedBox(height: 12),
          DurationField(
            seconds: w.sessionOverhead,
            label: 'Session overhead',
            onChanged: (v) => setState(() => w.sessionOverhead = v),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tune it to your routine', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'Each programmed row contributes to timing, including warmups and protocol fragments. Tune Entry '
                    'duration to your routine. If changing plates or logging takes time, increase Setup / logging.',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Use Between exercises for walking, waiting for equipment, and setting up the next station. Session '
                    'overhead covers everything else that regularly adds a few minutes.',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Keep your programmed Rest values realistic. The goal is not to make the estimate smaller; it is to '
                    'make it resemble your actual sessions.',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Lifting ${compactMinutes(b.lifting)} · setup/logging ${compactMinutes(b.setup)} · programmed rest '
                    '${compactMinutes(b.rest)} · exercise changes ${compactMinutes(b.transitions)} · session overhead '
                    '${compactMinutes(b.session)} = ${compactMinutes(b.total)}. The displayed target rounds up to the next 5 minutes.',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'After a few real workouts, adjust these values once and leave them alone. The estimate becomes most useful '
            'when it reflects your normal pace.',
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }
}
