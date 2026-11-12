import 'package:flutter/material.dart';

import '../logic/circuits.dart';
import '../logic/methods.dart';
import '../logic/numbers.dart';
import '../logic/progression.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/num_field.dart';
import 'cycle_summary.dart';
import 'finish.dart';
import 'progress.dart';
import 'session.dart' show pickSetType, showSetDetails;

const historyPageSize = 20;

class HistoryScreen extends StatefulWidget {
  /// Shows only this workout's sessions when set.
  final String? templateId;
  const HistoryScreen({super.key, this.templateId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _visible = historyPageSize;
  bool _exercises = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _searchField(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: SizedBox(
        height: 44,
        child: TextField(
          controller: _search,
          autofocus: false,
          style: t.bodyMedium,
          textAlignVertical: TextAlignVertical.center,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search',
            hintStyle: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            fillColor: cs.onSurface.withValues(alpha: 0.035),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            prefixIcon: Icon(Icons.search_rounded, size: 18, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            prefixIconConstraints: const BoxConstraints.tightFor(width: 36, height: 44),
            suffixIconConstraints: const BoxConstraints.tightFor(width: 44, height: 44),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => setState(() {
                      _search.clear();
                      _visible = historyPageSize;
                    }),
                  ),
          ),
          onChanged: (_) => setState(() => _visible = historyPageSize),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final source = widget.templateId == null
        ? store.history
        : store.history.where((s) => s.templateId == widget.templateId).toList();
    final terms = _search.text.trim().toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final cycleNames = {for (final c in store.cycles) c.id: c.name};
    final linkedCycles = <String, Set<String>>{};
    if (terms.isNotEmpty) {
      for (final c in store.cycles) {
        for (final event in c.events.values) {
          if (event.sessionId case final id?) linkedCycles.putIfAbsent(id, () => <String>{}).add(c.name);
        }
      }
    }
    final all = terms.isEmpty
        ? source
        : source.where((s) {
            final names = [
              s.name,
              for (final e in s.exercises) e.name,
              ?cycleNames[s.cycleId],
              ...?linkedCycles[s.id],
            ].map((name) => name.toLowerCase()).toList();
            return terms.every((term) => names.any((name) => name.contains(term)));
          }).toList();
    final sessions = all.take(_visible).toList();
    final hidden = all.length - sessions.length;
    final perDay = <String, int>{};
    for (final s in sessions) {
      perDay.update(dateKey(s.startedAt), (v) => v + 1, ifAbsent: () => 1);
    }
    final now = DateTime.now();
    final weekStart = addDays(now, 1 - now.weekday);
    final thisWeek = store.history.where((s) => !s.startedAt.isBefore(weekStart)).toList();
    final weekSets = thisWeek.fold(0, (a, s) => a + s.doneSets);
    final past = store.cycles.where((c) => !c.active).toList().reversed.take(6).toList();
    final title = widget.templateId == null
        ? 'History'
        : '${store.template(widget.templateId)?.name ?? 'Workout'} History';

    final root = widget.templateId == null;
    final body = ListView(
      padding: root ? pageInsets : subPageInsets,
      children: [
        if (root) PageHeader(title, trailing: _exercises ? null : _searchField(context)),
        if (root) ...[
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Workouts')),
              ButtonSegment(value: true, label: Text('Exercises')),
            ],
            selected: {_exercises},
            onSelectionChanged: (v) {
              FocusScope.of(context).unfocus();
              setState(() {
                _exercises = v.first;
                _search.clear();
                _visible = historyPageSize;
              });
            },
          ),
        ],
        if (_exercises)
          const ExerciseProgressList()
        else ...[
          if (root && terms.isEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(context.style.sp(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('THIS WEEK', style: t.labelSmall),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Stat('${thisWeek.length}', thisWeek.length == 1 ? 'workout' : 'workouts')),
                        Expanded(child: Stat('$weekSets', weekSets == 1 ? 'set' : 'sets')),
                        Expanded(
                          child: Stat(
                            // Past workouts keep their recorded unit; total them in the current one.
                            fmtVolume(
                              thisWeek.fold(0.0, (a, s) => a + convertWeight(s.volume, s.unit, store.settings.unit)),
                            ),
                            '${store.settings.unit} volume',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _WeekDots(sessions: thisWeek),
                  ],
                ),
              ),
            ),
          ] else
            const SizedBox(height: 12),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                terms.isEmpty ? 'No completed workouts yet.' : 'No matching workouts.',
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          for (final (i, s) in sessions.indexed) ...[
            if (i == 0 || !_sameMonth(sessions[i - 1].startedAt, s.startedAt)) SectionLabel(_monthLabel(s.startedAt)),
            Padding(
              padding: EdgeInsets.only(bottom: context.style.sp(10)),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => openSessionSummary(context, s),
                  child: Padding(
                    padding: EdgeInsets.all(context.style.sp(16)),
                    child: Row(
                      children: [
                        _DateTile(date: s.startedAt),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      s.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.titleMedium,
                                    ),
                                  ),
                                  if (s.phase != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      'W${s.microcycle} ${s.phase}',
                                      style: t.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (s.duration.inMinutes > 0) fmtDuration(s.duration),
                                  plural(s.doneSets, 'set'),
                                  if (s.volume > 0) '${fmtVolume(s.volume)} ${s.unit}',
                                  if ((perDay[dateKey(s.startedAt)] ?? 0) > 1) fmtRecent(s.startedAt).split(', ').last,
                                ].join(' · '),
                                style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (hidden > 0)
            OutlinedButton(
              onPressed: () => setState(() => _visible += historyPageSize),
              child: Text('Show ${hidden < historyPageSize ? hidden : historyPageSize} more'),
            ),
          if (root && terms.isEmpty && past.isNotEmpty) ...[
            const SectionLabel('Mesocycles'),
            Card(
              child: Column(
                children: [
                  for (final (i, c) in past.indexed) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      title: Text(c.name),
                      subtitle: Text(
                        '${fmtRecent(c.start, includeTime: false)} · '
                        '${c.length} ${c.periodNoun(plural: c.length != 1)}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => openCycleSummary(context, c),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ],
    );
    return root
        ? body
        : Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 12),
                  Flexible(child: _searchField(context)),
                ],
              ),
            ),
            body: body,
          );
  }
}

const _monthNames = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
const _dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

bool _sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;
String _monthLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

class _DateTile extends StatelessWidget {
  final DateTime date;
  const _DateTile({required this.date});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: context.style.brSmall),
      child: Column(
        children: [
          Text(
            '${date.day}',
            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.1, fontFeatures: tabular),
          ),
          Text(_dayNames[date.weekday - 1], style: t.labelSmall),
        ],
      ),
    );
  }
}

class _WeekDots extends StatelessWidget {
  final List<Session> sessions;
  const _WeekDots({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now().weekday - 1;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final trained = {for (final s in sessions) s.startedAt.weekday - 1};
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var d = 0; d < 7; d++)
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(context.style.radius.clamp(0, 15)),
                  color: trained.contains(d) ? cs.primary : cs.surfaceContainerHigh,
                  border: d == today ? Border.all(color: cs.primary, width: 1.5) : null,
                ),
                child: trained.contains(d) ? Icon(Icons.check_rounded, size: 16, color: cs.onPrimary) : null,
              ),
              const SizedBox(height: 6),
              Text(letters[d], style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
      ],
    );
  }
}

void openSessionSummary(BuildContext context, Session session) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _SavedSummary(sessionId: session.id)));
}

class _SavedSummary extends StatelessWidget {
  final String sessionId;
  const _SavedSummary({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final session = store.history.where((s) => s.id == sessionId).firstOrNull;
    if (session == null) return Scaffold(appBar: AppBar(title: const Text('Workout summary')));
    return FinishScreen(
      summary: store.summarizeSession(session),
      historical: true,
      onEdit: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SessionEditor(original: session)));
        if (context.mounted && !store.history.any((s) => s.id == sessionId)) Navigator.pop(context);
      },
    );
  }
}

void openSessionEditor(
  BuildContext context,
  Session s, {
  Mesocycle? cycle,
  String? plannedKey,
  bool draft = false,
  bool unplanned = false,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          SessionEditor(original: s, cycle: cycle, plannedKey: plannedKey, draft: draft, unplanned: unplanned),
    ),
  );
}

/// Full historical editing: name, date, exercises, sets, types, done ticks,
/// notes, set details and recorded load meaning.
class SessionEditor extends StatefulWidget {
  final Session original;
  final Mesocycle? cycle;
  final String? plannedKey;
  final bool draft;
  final bool unplanned;

  const SessionEditor({
    super.key,
    required this.original,
    this.cycle,
    this.plannedKey,
    this.draft = false,
    this.unplanned = false,
  });

  @override
  State<SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<SessionEditor> {
  late final Session _s = Session.fromJson(widget.original.toJson());
  late final _name = TextEditingController(text: _s.name);
  final _notesOpen = <SessionExercise>{};

  @override
  void initState() {
    super.initState();
    for (final e in _s.exercises) {
      if (e.sets.any((x) => x.note.trim().isNotEmpty)) _notesOpen.add(e);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _reconcile(SessionExercise e) {
    final fixed = reconcileMethodSets(e.method, [for (final s in e.sets) (s.type, s.groupStart)]);
    for (var i = 0; i < e.sets.length; i++) {
      e.sets[i]
        ..type = fixed[i].$1
        ..groupStart = fixed[i].$2;
      if (!methodSetUsesRir(e.method, e.sets[i].type)) e.sets[i].rir = null;
    }
  }

  void _save() {
    final store = StoreScope.read(context);
    final day = dateOnly(_s.startedAt);
    if (day.isAfter(dateOnly(DateTime.now()))) {
      return notify(context, 'A performed workout cannot be dated in the future.');
    }
    for (final e in _s.exercises) {
      for (final set in e.sets) {
        if (!set.done) continue;
        set.invalid.clear();
        if (set.weight == null) set.invalid.add('weight');
        if (set.reps == null) set.invalid.add('reps');
      }
    }
    if (_s.exercises.any((e) => e.sets.any((x) => x.invalid.isNotEmpty))) {
      setState(() {});
      return;
    }
    _s.name = _name.text.trim().isEmpty ? widget.original.name : _name.text.trim();
    reconcileCircuits(_s.circuits, _s.exercises.map((e) => e.name));
    if (widget.draft) {
      if (_s.doneAll == 0) return notify(context, 'Mark at least one set complete.');
      store.saveCalendarSession(widget.cycle!, widget.plannedKey!, _s, unplanned: widget.unplanned);
      notify(context, 'Workout saved.');
    } else {
      store.saveHistorySession(_s);
      notify(context, 'Saved ${_s.doneAll} historical set(s).');
    }
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      'Delete workout',
      'This removes it from history and progress.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    StoreScope.read(context).deleteSession(_s.id);
    notify(context, 'Historical workout deleted.');
    Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _s.startedAt.isAfter(DateTime.now()) ? DateTime.now() : _s.startedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      final old = _s.startedAt;
      _s.startedAt = DateTime(picked.year, picked.month, picked.day, old.hour, old.minute);
      // Keep the recorded duration: finish moves with the start.
      final end = _s.finishedAt;
      if (end != null) _s.finishedAt = end.add(_s.startedAt.difference(old));
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final unit = _s.unit;
    final report = store.sessionVolume(_s);
    // The workout order once per build, not once per set row.
    final steps = {for (final step in workoutSteps(_s.exercises, _s.circuits)) step.set: step};
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.draft ? 'Log past workout' : 'History'),
        actions: [
          if (!widget.draft)
            IconButton(
              tooltip: 'Delete historical workout',
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
        padding: subPageInsets,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Workout name'),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Workout date'),
              child: Text(dateKey(_s.startedAt)),
            ),
          ),
          const SizedBox(height: 10),
          Text('Recorded work: ${report.totals.describe()}', style: t.bodySmall),
          if (_s.phase != null)
            Text(
              'Week ${_s.microcycle} · ${_s.phase}${_s.targetRir == null ? '' : ' · target ${_s.targetRir} RIR'}',
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          for (final e in [..._s.exercises]) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final name = await pickExercise(context, inWorkout: _s.exercises.map((x) => x.name));
                      if (name == null || !context.mounted || sameExercise(name, e.name)) return;
                      if (_s.exercises.any((x) => x != e && sameExercise(x.name, name))) {
                        return notify(context, '$name is already in this workout.');
                      }
                      setState(() {
                        renameCircuitExercise(_s.circuits, e.name, name);
                        e.name = name;
                      });
                    },
                    child: Text(e.name, style: t.titleMedium?.copyWith(fontSize: 18)),
                  ),
                ),
                Text(
                  '${e.doneSets}/${e.sets.length} done',
                  style: t.bodySmall?.copyWith(
                    color: e.doneSets == e.sets.length ? null : Theme.of(context).colorScheme.warning,
                  ),
                ),
                IconButton(
                  tooltip: 'Show/hide notes',
                  icon: Icon(_notesOpen.contains(e) ? Icons.notes_rounded : Icons.notes_outlined),
                  onPressed: () => setState(() => _notesOpen.contains(e) ? _notesOpen.remove(e) : _notesOpen.add(e)),
                ),
              ],
            ),
            if (e.method != 'Straight') Text(e.method, style: t.labelSmall),
            for (final (i, set) in [...e.sets].indexed) _historySetRow(context, store, e, i, set, unit, steps[set]),
            DropdownButtonFormField<String>(
              initialValue: e.loadMode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Recorded load meaning'),
              items: [for (final m in loadModes.entries) DropdownMenuItem(value: m.key, child: Text(m.value))],
              onChanged: (v) => setState(() => e.loadMode = v ?? e.loadMode),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(loadGuidance(e.loadMode), style: t.bodySmall),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add set'),
                onPressed: () => setState(() {
                  final last = e.sets.isEmpty ? null : e.sets.last;
                  e.sets.add(
                    SetEntry(
                      type: defaultNextSetType(e.method, [for (final x in e.sets) x.type]),
                      weight: last?.weight,
                      reps: last?.reps,
                      rest: last?.rest ?? 180,
                      context: last?.context ?? const SetContext(),
                    ),
                  );
                  _reconcile(e);
                }),
              ),
            ),
            const Divider(),
          ],
          OutlinedButton(
            onPressed: () async {
              final name = await pickExercise(context, inWorkout: _s.exercises.map((x) => x.name));
              if (name == null || !context.mounted) return;
              if (_s.exercises.any((x) => sameExercise(x.name, name))) {
                return notify(context, '$name is already in this workout.');
              }
              setState(
                () => _s.exercises.add(
                  SessionExercise(
                    name: name,
                    loadMode: store.exercise(name)?.loadMode ?? defaultLoadModeFor(name),
                    sets: [SetEntry()],
                  ),
                ),
              );
            },
            child: const Text('+ Exercise'),
          ),
        ],
      ),
    );
  }

  Widget _historySetRow(
    BuildContext context,
    AppStore store,
    SessionExercise e,
    int i,
    SetEntry set,
    String unit,
    WorkoutStep? step,
  ) {
    final t = Theme.of(context).textTheme;
    final usesRir = methodSetUsesRir(e.method, set.type);
    final number = set.warmup ? 'W' : '${e.sets.take(i + 1).where((x) => !x.warmup).length}';
    final weightKind = e.loadMode == 'external' ? NumKind.weight : NumKind.load;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () async {
                  final picked = await pickSetType(context, e.method, [
                    for (final x in e.sets) (x.type, x.groupStart),
                  ], i);
                  if (picked == null) return;
                  setState(() {
                    set.type = picked;
                    _reconcile(e);
                  });
                },
                child: SizedBox(
                  width: 46,
                  height: 44,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(activeSetTypeLabel(set.type), maxLines: 1, style: const TextStyle(fontSize: 9)),
                      Text(number, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 10,
                child: NumField(
                  value: set.weight,
                  kind: weightKind,
                  placeholder: loadSuffix(e.loadMode, unit),
                  suffix: loadSuffix(e.loadMode, unit),
                  invalid: set.invalid.contains('weight'),
                  onChanged: (v) => set
                    ..weight = v
                    ..invalid.remove('weight'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 7,
                child: NumField(
                  value: set.reps?.toDouble(),
                  kind: NumKind.reps,
                  placeholder: 'Reps',
                  suffix: 'reps',
                  invalid: set.invalid.contains('reps'),
                  onChanged: (v) => set
                    ..reps = v?.round()
                    ..invalid.remove('reps'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 7,
                child: usesRir
                    ? NumField(
                        value: set.rir?.toDouble(),
                        kind: NumKind.rir,
                        placeholder: 'Actual RIR',
                        suffix: 'RIR',
                        onChanged: (v) => set.rir = v?.round(),
                      )
                    : const SizedBox.shrink(),
              ),
              IconButton(
                tooltip: set.done ? 'Mark not completed' : 'Mark completed',
                icon: Icon(
                  set.done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  color: set.done ? Theme.of(context).colorScheme.success : null,
                ),
                onPressed: () => setState(() {
                  if (!set.done && (set.weight == null || set.reps == null)) {
                    if (set.weight == null) set.invalid.add('weight');
                    if (set.reps == null) set.invalid.add('reps');
                    return;
                  }
                  set.done = !set.done;
                }),
              ),
              IconButton(
                tooltip: 'Delete set',
                icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                onPressed: () => setState(() {
                  e.sets.remove(set);
                  if (e.sets.isEmpty) {
                    _s.exercises.remove(e);
                    reconcileCircuits(_s.circuits, _s.exercises.map((e) => e.name));
                  } else {
                    _reconcile(e);
                  }
                }),
              ),
            ],
          ),
          if (_notesOpen.contains(e))
            Padding(
              padding: const EdgeInsets.only(left: 50, top: 2),
              child: TextFormField(
                key: ObjectKey(set),
                initialValue: set.note,
                decoration: const InputDecoration(hintText: 'Note'),
                onChanged: (v) => set.note = v,
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Protocol details',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.tune_rounded, size: 18),
                onPressed: () async {
                  await showSetDetails(
                    context,
                    store,
                    set,
                    historical: true,
                    linkedRest: set.done && set.circuitRestAfter != null
                        ? set.circuitRestAfter
                        : (step?.circuit != null && step!.endsTurn ? step.restAfter : null),
                  );
                  setState(() {});
                },
              ),
              Expanded(
                child: Text(
                  [
                    if (!set.context.isEmpty) set.context.summary(),
                    if (set.stopReason.isNotEmpty) 'Stop: ${stopReasons[set.stopReason]}',
                    if (step?.circuit case final circuit?)
                      '${circuitDescription(circuit)} ${circuitBadge(_s.circuits, circuit, e.name)}',
                    'Planned rest after: ${step?.restAfter ?? set.rest}s',
                    if (set.actualRest != null) 'Actual rest after: ${set.actualRest}s',
                    if (set.targetRir != null) 'Target ${set.targetRir} RIR',
                  ].join(' · '),
                  style: t.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
