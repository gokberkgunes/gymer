import 'package:flutter/material.dart';

import '../logic/cycle.dart';
import '../logic/methods.dart';
import '../logic/numbers.dart';
import '../logic/plates.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/num_field.dart';
import '../store.dart';

/// Exercise database: fuzzy search (leading space = exact), add, delete.
class ExercisesScreen extends StatefulWidget {
  const ExercisesScreen({super.key});

  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final raw = _query.text;
    final names = filterNames([for (final e in store.exercises) e.name], raw);
    final addable = (raw.startsWith(' ') ? raw.substring(1) : raw).trim();
    final canAdd = addable.isNotEmpty && store.exercise(addable) == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise Database')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: TextField(
              controller: _query,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Search or add', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (canAdd)
                  ListTile(
                    leading: Icon(Icons.add_rounded, color: cs.primary),
                    title: Text(
                      'Add new: "$addable"',
                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      store.addExercise(addable);
                      _query.clear();
                      setState(() {});
                    },
                  ),
                for (final name in names)
                  () {
                    final e = store.exercise(name)!;
                    return ListTile(
                      title: Text(e.name),
                      subtitle: Text(
                        [
                          if (e.primary.isNotEmpty) e.primary.join(' · '),
                          if (e.loadMode != 'external') loadModes[e.loadMode]!,
                          '${e.repMin}–${e.repMax} reps',
                        ].join('  ·  '),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          // Workouts would lose its muscles and load type, so it must leave them first.
                          final using = store.workoutsUsing(e.name).toSet();
                          if (using.isNotEmpty) {
                            return notify(context, 'Used in ${using.join(', ')}. Remove it from there first.');
                          }
                          final ok = await confirm(
                            context,
                            'Delete exercise',
                            store.inHistory(e.name)
                                ? 'Remove "${e.name}"? Past workouts keep their sets, but they will no longer '
                                      'count toward muscle volume.'
                                : 'Remove "${e.name}" from the database?',
                            action: 'Delete',
                            destructive: true,
                          );
                          if (ok) store.deleteExercise(e.name);
                        },
                      ),
                      onTap: () => openExerciseEditor(context, e.name),
                    );
                  }(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openExerciseEditor(BuildContext context, String name) {
  final store = StoreScope.read(context);
  final e = store.exercise(name) ?? store.addExercise(name);
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => ExerciseEditor(original: e)));
}

/// A persistent setup reminder, separate from set notes and logging context.
Future<void> editExerciseNote(BuildContext context, String name) async {
  final store = StoreScope.read(context);
  final exercise = store.exercise(name);
  if (exercise == null) return;
  var note = exercise.note;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Exercise note'),
      content: TextFormField(
        initialValue: note,
        autofocus: true,
        minLines: 1,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Seat 4 · neutral grip'),
        onChanged: (value) => note = value,
        onFieldSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, note.trim()), child: const Text('Save')),
      ],
    ),
  );
  if (result == null || !context.mounted) return;
  final current = store.exercise(name);
  if (current == null || current.note == result) return;
  final error = store.saveExercise(current.copyWith(note: result));
  if (error != null) notify(context, error);
}

class ExerciseEditor extends StatefulWidget {
  final Exercise original;
  const ExerciseEditor({super.key, required this.original});

  @override
  State<ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends State<ExerciseEditor> {
  late Exercise _e = widget.original;

  // Nullable while editing: a default filled in on every keystroke would refill the box the moment it is
  // cleared, so the range could never be retyped. Defaults apply on save.
  late int? _repMin = _e.repMin;
  late int? _repMax = _e.repMax;
  bool get _rangeInvalid => (_repMin ?? 8) > (_repMax ?? 12);
  late final _name = TextEditingController(text: _e.name);
  late final _note = TextEditingController(text: _e.note);
  late final _desc = TextEditingController(text: _e.description);
  late final _setup = TextEditingController(text: _e.context.setup);

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _desc.dispose();
    _setup.dispose();
    super.dispose();
  }

  void _save() {
    final store = StoreScope.read(context);
    final name = _name.text.trim();
    if (name.isEmpty) return notify(context, 'Exercise name cannot be empty.');
    if (_rangeInvalid) return notify(context, 'Minimum reps must not exceed maximum reps.');
    final error = store.saveExercise(
      _e.copyWith(
        name: name,
        repMin: _repMin ?? 8,
        repMax: _repMax ?? 12,
        note: _note.text.trim(),
        description: _desc.text.trim(),
        context: _e.context.copyWith(setup: _setup.text.trim()),
      ),
      oldName: widget.original.name,
    );
    if (error != null) return notify(context, error);
    notify(context, 'Exercise details saved.');
    Navigator.pop(context);
  }

  void _toggleMuscle(bool primary, String muscle) {
    final chosen = {...(primary ? _e.primary : _e.secondary)};
    final other = {...(primary ? _e.secondary : _e.primary)};
    if (!chosen.remove(muscle)) {
      chosen.add(muscle);
      other.remove(muscle);
    }
    // Known muscles in landmark order, then any other tag (e.g. from an import) kept as it was.
    List<String> ordered(Set<String> s) => [
      for (final m in volumeLandmarks.keys)
        if (s.contains(m)) m,
      for (final m in s)
        if (!volumeLandmarks.containsKey(m)) m,
    ];
    setState(
      () => _e = _e.copyWith(primary: ordered(primary ? chosen : other), secondary: ordered(primary ? other : chosen)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    final store = StoreScope.of(context);
    final unit = store.settings.unit;
    final equipDefault = store.settings.increments[_e.equipment];
    final defaultStep = equipDefault == null ? null : (unit == 'lb' ? equipDefault.$2 : equipDefault.$1);
    final override = unit == 'lb' ? _e.incrementLb : _e.incrementKg;

    Widget grid(bool primary) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final m in volumeLandmarks.keys)
          () {
            final selected = (primary ? _e.primary : _e.secondary).contains(m);
            return InkWell(
              borderRadius: st.brSmall,
              onTap: () => _toggleMuscle(primary, m),
              child: Container(
                width: 104,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: st.brSmall,
                  color: selected ? cs.primary.withValues(alpha: 0.18) : null,
                  border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 1.4 : 1),
                ),
                child: Text(
                  m,
                  style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.w500),
                ),
              ),
            );
          }(),
      ],
    );

    Widget dropdown(String label, String value, Map<String, String> options, ValueChanged<String> onChanged) =>
        DropdownButtonFormField<String>(
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
          onChanged: (v) => onChanged(v ?? ''),
        );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: const Text('Exercise details'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
      body: ListView(
        padding: subPageInsets,
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Exercise name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Exercise note', hintText: 'Seat 4 · neutral grip'),
          ),
          const SizedBox(height: 10),
          dropdown('Load tracking', _e.loadMode, loadModes, (v) => setState(() => _e = _e.copyWith(loadMode: v))),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(loadGuidance(_e.loadMode), style: t.bodySmall),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _setup,
            decoration: const InputDecoration(
              labelText: 'Default setup / variation',
              hintText: 'e.g. machine ID, handle, seat setting',
            ),
          ),
          const SizedBox(height: 10),
          dropdown(
            'Load basis',
            _e.context.loadBasis,
            SetContext.loadBasisLabels,
            (v) => setState(() => _e = _e.copyWith(context: _e.context.copyWith(loadBasis: v))),
          ),
          const SizedBox(height: 10),
          dropdown(
            'Rep count basis',
            _e.context.repBasis,
            SetContext.repBasisLabels,
            (v) => setState(() => _e = _e.copyWith(context: _e.context.copyWith(repBasis: v))),
          ),
          const SizedBox(height: 10),
          dropdown(
            'Side',
            _e.context.side,
            SetContext.sideLabels,
            (v) => setState(() => _e = _e.copyWith(context: _e.context.copyWith(side: v))),
          ),
          const SizedBox(height: 6),
          Text(
            'Context defaults apply to new workouts. Changing setup or logging conventions clears inherited future '
            'load/rep presets; explicit segment variants keep theirs. Existing sessions keep their recorded meaning. '
            'Unknown does not assume total load or total reps. Both sides in one entry uses manual progression. '
            'Increments apply to the entered load basis.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SectionLabel('Straight progression'),
          dropdown(
            'Straight progression',
            _e.autoProgression ? 'double_progression' : 'manual',
            const {'double_progression': 'Double progression', 'manual': 'Manual'},
            (v) => setState(() => _e = _e.copyWith(autoProgression: v != 'manual')),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: NumField(
                  value: _repMin?.toDouble(),
                  kind: NumKind.reps,
                  placeholder: 'Minimum reps',
                  dense: false,
                  invalid: _rangeInvalid,
                  onChanged: (v) => setState(() => _repMin = v?.round()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NumField(
                  value: _repMax?.toDouble(),
                  kind: NumKind.reps,
                  placeholder: 'Maximum reps',
                  dense: false,
                  invalid: _rangeInvalid,
                  onChanged: (v) => setState(() => _repMax = v?.round()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Straight sets: build reps at the target RIR, then add one increment after every planned set reaches the '
            'upper limit. Manual mode disables automatic load/calibration hints. Other methods use the same range for their first set: above it the load goes up, below it down.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SectionLabel('Description'),
          TextField(
            controller: _desc,
            minLines: 4,
            maxLines: 7,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Exercise description'),
          ),
          const SectionLabel('Primary muscles'),
          grid(true),
          const SectionLabel('Secondary muscles'),
          grid(false),
          const SectionLabel('Equipment'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final eq in equipmentTypes)
                ChoiceChip(
                  label: Text(eq),
                  selected: _e.equipment == eq,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _e = _e.copyWith(equipment: eq)),
                ),
            ],
          ),
          SectionLabel('Weight increment override ($unit)'),
          NumField(
            value: override,
            kind: NumKind.weight,
            placeholder: defaultStep == null ? 'Automatic' : 'Default ${formatNumber(defaultStep, NumKind.weight)}',
            suffix: unit,
            dense: false,
            onChanged: (v) => setState(
              () => _e = unit == 'lb' ? _e.copyWith(incrementLb: () => v) : _e.copyWith(incrementKg: () => v),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _e.equipment.isEmpty
                ? 'Choose equipment above, or leave blank to use a small automatic step.'
                : 'Leave blank to use the ${_e.equipment} default: ${formatNumber(defaultStep ?? 0, NumKind.weight)} $unit.',
            style: t.bodySmall,
          ),
          Text(
            'Increments apply to the load basis you record. The app does not double or halve load or reps for a different convention.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (usesPlates(_e.equipment)) ...[
            SectionLabel('Bar weight ($unit)'),
            NumField(
              value: unit == 'lb' ? _e.barLb : _e.barKg,
              kind: NumKind.load,
              placeholder: _e.equipment == 'Plate loaded'
                  ? 'Default 0 (sled not counted)'
                  : 'Default ${formatNumber(store.settings.bar, NumKind.weight)}',
              suffix: unit,
              dense: false,
              onChanged: (v) =>
                  setState(() => _e = unit == 'lb' ? _e.copyWith(barLb: () => v) : _e.copyWith(barKg: () => v)),
            ),
            const SizedBox(height: 4),
            Text('For the plate calculator, e.g. 10 for an EZ bar.', style: t.bodySmall),
          ],
          const SectionLabel('Approx. time per set (seconds)'),
          NumField(
            value: _e.setSeconds?.toDouble(),
            kind: NumKind.seconds,
            placeholder: 'Use workout default',
            suffix: 's',
            dense: false,
            onChanged: (v) => setState(() => _e = _e.copyWith(setSeconds: () => v?.round())),
          ),
          const SizedBox(height: 4),
          Text("Leave blank to use the workout's default set-time estimate.", style: t.bodySmall),
        ],
      ),
    );
  }
}

/// Set-type database: the set roles offered by the app, plus custom ones.
class SetTypesScreen extends StatefulWidget {
  const SetTypesScreen({super.key});

  @override
  State<SetTypesScreen> createState() => _SetTypesScreenState();
}

class _SetTypesScreenState extends State<SetTypesScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final raw = _query.text;
    final names = filterNames([for (final t in store.settings.setTypes) displaySetType(t)], raw);
    final addable = (raw.startsWith(' ') ? raw.substring(1) : raw).trim();
    final canAdd = addable.isNotEmpty && !store.settings.setTypes.any((t) => t.toLowerCase() == addable.toLowerCase());
    return Scaffold(
      appBar: AppBar(title: const Text('Set Type Database')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: TextField(
              controller: _query,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Search or add', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (canAdd)
                  ListTile(
                    leading: Icon(Icons.add_rounded, color: cs.primary),
                    title: Text(
                      'Add new: "$addable"',
                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      store.addSetType(addable);
                      _query.clear();
                      setState(() {});
                    },
                  ),
                for (final name in names)
                  ListTile(
                    title: Text(name),
                    trailing: name == 'Straight (Normal)' || name == 'Warm-up'
                        ? null
                        : IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => store.removeSetType(canonicalSetType(name)),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
