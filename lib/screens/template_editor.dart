import 'package:flutter/material.dart';

import '../logic/circuits.dart';
import '../logic/cycle.dart' show rpLandmarks;
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
import 'cycle.dart' show MuscleVolumeRow, showLandmarkInfo, weeklySetsColor, fmtSets;
import 'exercises.dart';
import 'session.dart' show pickSetType;

part 'template_editor/exercise_card.dart';
part 'template_editor/time.dart';

void editTemplate(BuildContext context, WorkoutTemplate tpl, {bool fromActive = false}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
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
      'Remove "${_d.name}"? History is kept.'
          '${[for (final c in _store.cyclesScheduling(_d.id)) '\n\nIt is on the schedule of "${c.name}". Its days there will show a red "?" until you choose another workout for them.'].join()}',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    _store.deleteTemplate(_d.id);
    Navigator.pop(context);
  }

  Future<void> _addExercise() async {
    final name = await pickExercise(context, inWorkout: _d.exercises.map((x) => x.name));
    if (name == null || !mounted) return;
    if (_d.exercises.any((x) => sameExercise(x.name, name))) {
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
    final name = await pickExercise(context, inWorkout: _d.exercises.map((x) => x.name));
    if (name == null || !mounted || sameExercise(name, e.name)) return;
    if (_d.exercises.any((x) => x != e && sameExercise(x.name, name))) {
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

  /// Weekly sets per muscle with this draft, against the saved plan (Settings → Workout → Weekly sets button).
  Future<void> _weeklySets() async {
    final v = _store.editorWeeklySets(_d);
    final muscles = [
      for (final m in rpLandmarks.keys)
        if ((v.after[m] ?? 0) > 0 || (v.before[m] ?? 0) > 0) m,
      for (final m in v.after.keys)
        if (!rpLandmarks.containsKey(m)) m,
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        final t = Theme.of(sheet).textTheme;
        final cs = Theme.of(sheet).colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.8),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text('Weekly sets', style: t.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    v.hypothetical ? 'If this workout is added once a week' : 'With your unsaved changes',
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                if (muscles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Tag muscles on exercises to see weekly sets.', style: t.bodySmall),
                  ),
                for (final m in muscles)
                  MuscleVolumeRow(muscle: m, sets: v.after[m] ?? 0, delta: (v.after[m] ?? 0) - (v.before[m] ?? 0)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final weekly = store.settings.editorMuscleTotals ? store.editorWeeklySets(_d).after : null;
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
          if (store.settings.editorWeeklySets)
            IconButton(tooltip: 'Weekly sets', icon: const Icon(Icons.bar_chart_rounded), onPressed: _weeklySets),
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
                await Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => TimeApproximator(template: _d)));
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
              weekly: weekly,
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
                final renamed = now == null
                    ? store.exercises.map((x) => x.name).where((n) => !before.contains(n)).firstOrNull
                    : null;
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
