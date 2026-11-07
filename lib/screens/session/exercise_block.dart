part of '../session.dart';

class _ExerciseBlock extends StatefulWidget {
  final SessionExercise exercise;
  final _SessionScreenState screen;

  /// The workout order (by set) and this card's block position, computed once per screen build rather than
  /// once per card, so typing a digit does not rebuild the whole schedule for every exercise.
  final Map<SetEntry, WorkoutStep> steps;
  final int blockIndex, blockCount;
  const _ExerciseBlock({
    super.key,
    required this.exercise,
    required this.screen,
    required this.steps,
    required this.blockIndex,
    required this.blockCount,
  });

  @override
  State<_ExerciseBlock> createState() => _ExerciseBlockState();
}

class _ExerciseBlockState extends State<_ExerciseBlock> {
  SessionExercise get exercise => widget.exercise;
  _SessionScreenState get screen => widget.screen;

  /// While the exercise name is pressed, the whole card lights up (not just the name area).
  bool _pressed = false;

  /// Clears the tint shortly after release; cancelled by a new press so a quick second press stays lit.
  Timer? _release;

  @override
  void dispose() {
    _release?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final session = store.active!;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final st = context.style;
    final e = exercise;
    final info = store.exercise(e.name);
    final note = info?.note.trim() ?? '';
    final warmup = session.isWarmupExercise(e);
    final ramp = session.warmupFor(e.name);
    final canWarmup =
        warmup || ramp != null || (e.loadMode == 'external' && e.work.isNotEmpty && !e.work.any((s) => s.done));
    final circuit = warmup ? null : circuitFor(session.circuits, e.name);
    final scheduledSteps = widget.steps;
    final blockIndex = widget.blockIndex;
    final visibleSets = session.visibleSetsFor(e);
    final collapsed =
        e.collapsed ??
        (visibleSets.isNotEmpty && visibleSets.every((set) => set.done) && store.settings.collapseCompleted);
    final irregularRest = {for (final s in e.sets) s.rest}.length > 1;

    Future<void> substitute() async {
      if (e.sets.any((s) => s.done)) {
        return notify(context, 'Substitute before completing sets for this exercise.');
      }
      final name = await pickExercise(context, inWorkout: session.exercises.map((x) => x.name));
      if (name == null || !context.mounted) return;
      final error = store.substituteExercise(e, name);
      if (error != null) notify(context, error);
    }

    final menu = <(String, IconData, String, VoidCallback)>[
      ('repMax', Icons.calculate_outlined, 'Rep max calculator', () => openRepMaxForExercise(context, e.name)),
      ('rest', Icons.timer_outlined, 'Rest timers', () => _restEditor(context, store, e)),
      ('history', Icons.show_chart_rounded, 'History & progress', () => openExerciseProgress(context, e.name)),
      ('details', Icons.info_outline_rounded, 'Exercise details', () => openExerciseEditor(context, e.name)),
      if (!warmup) ('circuit', Icons.link_rounded, 'Superset / circuit', () => _circuitEditor(context, store, e)),
      if (canWarmup)
        (
          'warmup',
          Icons.local_fire_department_outlined,
          warmup
              ? 'Show working sets'
              : session.warmupFor(e.name) != null
              ? 'Show warm-up'
              : 'Warm-up',
          () => _warmupEditor(context, store, e),
        ),
      (
        'exerciseNote',
        Icons.sticky_note_2_outlined,
        note.isEmpty ? 'Add exercise note' : 'Edit exercise note',
        () => editExerciseNote(context, e.name),
      ),
      (
        'notes',
        e.notesVisible ? Icons.speaker_notes_off_outlined : Icons.notes_rounded,
        e.notesVisible ? 'Hide set notes' : 'Show set notes',
        () {
          e.notesVisible = !e.notesVisible;
          store.changed();
        },
      ),
      if (blockIndex > 0)
        (
          'moveUp',
          Icons.arrow_upward_rounded,
          circuit == null ? 'Move up' : 'Move group up',
          () => store.moveSessionExercise(e, -1),
        ),
      if (blockIndex < widget.blockCount - 1)
        (
          'moveDown',
          Icons.arrow_downward_rounded,
          circuit == null ? 'Move down' : 'Move group down',
          () => store.moveSessionExercise(e, 1),
        ),
      if (!warmup) ('substitute', Icons.swap_horiz_rounded, 'Substitute exercise', substitute),
      (
        'remove',
        Icons.delete_outline_rounded,
        warmup ? 'Skip warm-up' : 'Remove exercise',
        () {
          final error = store.removeSessionExercise(e);
          if (error != null) notify(context, error);
        },
      ),
    ];
    final pinned = menu.where((action) => store.settings.pinnedExerciseActions.contains(action.$1)).toList();
    final muscles = info?.primary ?? const <String>[];

    final firstAnchor = e.sets.indexWhere((x) => calibrationAnchor(e.method, x.type));
    final showCalibration = (e.calibrate || e.calibrationEntered) && firstAnchor >= 0;
    final heading = ExerciseActionHeader(
      minimumTitleWidth: showCalibration || canWarmup || note.isNotEmpty ? 160 : (circuit == null ? 96 : 144),
      title: InkWell(
        // No highlight box of its own: the whole card is tinted instead (see _pressed).
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onHighlightChanged: (v) {
          _release?.cancel();
          if (v) return setState(() => _pressed = true);
          // Keep the tint briefly after a quick tap so it is visible, then fade it out.
          _release = Timer(const Duration(milliseconds: 250), () {
            if (mounted) setState(() => _pressed = false);
          });
        },
        onTap: () {
          e.collapsed = !collapsed;
          store.changed();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (circuit != null) ...[
                      CircuitPill(
                        circuits: session.circuits,
                        circuit: circuit,
                        exercise: e.name,
                        onTap: () => _circuitEditor(context, store, e),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Tooltip(
                        message: e.name,
                        child: Text(
                          e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(fontSize: 18),
                        ),
                      ),
                    ),
                    if (e.advice.isNotEmpty)
                      InfoDot(tooltip: 'Notes for this exercise', onTap: () => _showAdvice(context, e)),
                    if (showCalibration) ...[
                      const SizedBox(width: 8),
                      _CalibrationCard(exercise: e, index: firstAnchor, compact: constraints.maxWidth < 220),
                    ] else if (canWarmup) ...[
                      const SizedBox(width: 8),
                      _WarmupPill(
                        active: warmup,
                        ramp: ramp,
                        compact: constraints.maxWidth < 220,
                        onTap: () => _warmupEditor(context, store, e),
                      ),
                    ],
                    if (note.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (constraints.maxWidth * 0.38).clamp(0.0, 112.0).toDouble(),
                        ),
                        child: Tooltip(
                          message: note,
                          child: Material(
                            color: cs.surfaceContainerHigh,
                            borderRadius: st.brSmall,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => editExerciseNote(context, e.name),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                // With many pins, keep the reminder accessible without crowding the name.
                                child: constraints.maxWidth < 180
                                    ? Icon(Icons.sticky_note_2_outlined, size: 16, color: cs.onSurfaceVariant)
                                    : Text(
                                        note.replaceAll(RegExp(r'\s+'), ' '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (muscles.isNotEmpty || e.method != 'Straight' || collapsed)
                Text(
                  [
                    ...muscles,
                    if (e.method != 'Straight') e.method,
                    if (collapsed) '${visibleSets.where((x) => x.done).length}/${visibleSets.length}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
      actions: [
        for (final action in pinned)
          IconButton(
            tooltip: action.$3,
            icon: Icon(action.$2, color: cs.onSurfaceVariant),
            onPressed: action.$4,
          ),
      ],
      menu: PopupMenuButton<int>(
        tooltip: 'Exercise options',
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
        onSelected: (i) => menu[i].$4(),
        itemBuilder: (_) => [
          for (final (i, m) in menu.indexed)
            PopupMenuItem(
              value: i,
              child: Row(children: [Icon(m.$2, size: 20), const SizedBox(width: 12), Text(m.$3)]),
            ),
        ],
      ),
    );

    // A Material (like the Card it replaces) so ink ripples inside the card stay visible. Its colour
    // fades to grey while the name is pressed instead of jumping, which flickered on quick taps.
    final card = TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      tween: ColorTween(
        end: _pressed ? Color.alphaBlend(cs.onSurface.withValues(alpha: 0.07), cs.surface) : cs.surface,
      ),
      builder: (context, color, child) => Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: st.br,
          side: BorderSide(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: WarmupBackground(active: warmup, style: store.settings.warmupAppearance, child: child!),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, st.sp(12), 12, st.sp(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            if (!collapsed) ...[
              // No paragraphs of advice inside the workout: it is behind the (i) beside the exercise name.
              _ColumnHeader(exercise: e, unit: session.unit),
              for (final (position, s) in visibleSets.indexed) ...[
                Padding(
                  padding: EdgeInsets.symmetric(vertical: st.setGap / 2),
                  child: _SetRow(
                    key: screen.keyOf(s),
                    exercise: e,
                    index: e.sets.indexOf(s),
                    position: position,
                    count: visibleSets.length,
                    screen: screen,
                    plannedRest: scheduledSteps[s]?.restAfter ?? s.rest,
                    sharedRest: scheduledSteps[s]?.circuit != null && scheduledSteps[s]!.endsTurn,
                    showPlannedRest:
                        !s.done &&
                        (store.settings.plannedRestDisplay == 'always' ||
                            (store.settings.plannedRestDisplay == 'smart' &&
                                (circuit != null || irregularRest || !isStraightType(s.type)))),
                    unit: session.unit,
                  ),
                ),
              ],
              // Small − / + flush right, rounded squares like the other icon buttons; the plate calculator
              // (next unfinished set) sits at the left edge of the same row.
              Padding(
                padding: EdgeInsets.only(top: st.sp(8)),
                child: Row(
                  children: [
                    if (e.loadMode == 'external' && store.platesApply(e.name)) ...[
                      // The bar as loaded for the next unfinished set, updated as its weight is typed; tap
                      // for the full calculator.
                      Expanded(
                        child: Tooltip(
                          message: 'Plates',
                          child: InkWell(
                            borderRadius: st.brSmall,
                            onTap: () => openPlatesFor(context, store, e),
                            child: SizedBox(
                              height: compactButton.height,
                              child: Builder(
                                builder: (context) {
                                  final plateSet = _plateSet(store, e);
                                  if (plateSet == null) {
                                    return PlateBar(target: plateTarget(store, e), exercise: e.name);
                                  }
                                  // While the weight is being written and still empty, show the bare bar
                                  // instead of the placeholder's plates.
                                  final focus = screen.focusOf(plateSet).weight;
                                  return ListenableBuilder(
                                    listenable: focus,
                                    builder: (context, _) => PlateBar(
                                      target: focus.hasFocus && plateSet.weight == null ? 0 : plateTarget(store, e),
                                      exercise: e.name,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ] else
                      const Spacer(),
                    IconButton.filled(
                      tooltip: 'Remove last set',
                      style: IconButton.styleFrom(
                        backgroundColor: cs.surfaceContainerHigh,
                        foregroundColor: cs.onSurface,
                      ),
                      onPressed: visibleSets.isEmpty
                          ? null
                          : () => removeSetWithUndo(context, store, e, visibleSets.last),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Add set',
                      style: IconButton.styleFrom(
                        backgroundColor: cs.primary.withValues(alpha: 0.14),
                        foregroundColor: cs.primary,
                      ),
                      onPressed: () => store.addSet(e),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return card;
  }

  Future<void> _restEditor(BuildContext context, AppStore store, SessionExercise e) async {
    final session = store.active!;
    if (session.restLocked && !session.isWarmupExercise(e)) {
      return notify(context, 'Rest times are locked by the active mesocycle.');
    }
    final scopes = store.restScopes(e);
    final circuit = session.isWarmupExercise(e) ? null : circuitFor(session.circuits, e.name);
    final timerHere = store.rest?.exercise == e.name;
    if (scopes.isEmpty && !timerHere && circuit == null) {
      return notify(context, 'No unfinished rests or running timer for this exercise.');
    }
    const labels = {
      'warmup': 'Warmups',
      'conventional': 'Conventional sets',
      'within_protocol': 'Within protocol groups',
      'after_protocol': 'After protocol groups',
      'all_pending': 'All unfinished entries',
    };
    String? scope = circuit == null ? null : 'circuit';
    var seconds = circuit?.rest ?? 0;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          String preview() {
            if (scope == null) return 'Choose which rests to change.';
            if (scope == 'circuit') return 'Shared rest between rounds of ${circuit!.exercises.join(' → ')}.';
            if (scope == 'timer') {
              return "Changes only the running timer's total duration. Elapsed time and planned rests stay as recorded. Zero dismisses this timer.";
            }
            final indices = scopes[scope]!;
            final values = {for (final i in indices) e.sets[i].rest};
            return 'Sets ${indices.map((i) => i + 1).join(', ')}: '
                '${values.length == 1 ? 'current rest ${formatDuration(values.first)}' : 'mixed current rests; enter the duration to apply.'}'
                '${scope == 'all_pending' ? ' Includes unfinished warmups and protocol fragments.' : ''}';
          }

          return AlertDialog(
            title: Text('Rest timer · ${e.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: scope,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Apply to unfinished entries / timer'),
                    items: [
                      if (circuit != null) const DropdownMenuItem(value: 'circuit', child: Text('Rest between rounds')),
                      for (final MapEntry(key: k, value: v) in scopes.entries)
                        DropdownMenuItem(
                          value: k,
                          child: Text('${labels[k] ?? 'Set ${int.parse(k.split(':').last) + 1}'} (${v.length})'),
                        ),
                      if (timerHere) const DropdownMenuItem(value: 'timer', child: Text('Running timer only')),
                    ],
                    onChanged: (v) => setDialog(() {
                      scope = v;
                      error = null;
                      if (v == 'circuit') {
                        seconds = circuit!.rest;
                      } else if (v == 'timer') {
                        seconds = store.rest?.totalSeconds ?? seconds;
                      } else if (v != null) {
                        final values = {for (final i in scopes[v]!) e.sets[i].rest};
                        seconds = values.length == 1 ? values.first : -1;
                      }
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(preview(), style: Theme.of(c).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  _RestInput(
                    key: ValueKey(scope),
                    initial: seconds < 0 || scope == null ? '' : formatDuration(seconds),
                    error: error,
                    onChanged: (text) {
                      try {
                        seconds = parseRest(text);
                        setDialog(() => error = null);
                      } on FormatException catch (x) {
                        seconds = -1;
                        setDialog(() => error = x.message);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Planned-rest edits affect unfinished entries only. Completed plans and actual rest observations stay recorded. Running timers are edited separately.',
                    style: Theme.of(c).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
              FilledButton(
                onPressed: scope == null || seconds < 0
                    ? null
                    : () {
                        if (scope == 'circuit') {
                          circuit!.rest = seconds;
                          store.changed();
                        } else if (scope == 'timer') {
                          store.setRestTotal(seconds);
                        } else {
                          store.setPlannedRests(e, scopes[scope]!, seconds);
                        }
                        Navigator.pop(c);
                      },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _circuitEditor(BuildContext context, AppStore store, SessionExercise e) async {
    final session = store.active;
    if (session == null || session.isWarmupExercise(e)) return;
    final saved = await editExerciseCircuit(
      context,
      exercise: e.name,
      exercises: session.exercises.map((e) => e.name).toList(),
      circuits: session.circuits,
      defaultRest: e.restSeconds,
      restLocked: session.restLocked,
    );
    if (saved) store.changed();
  }

  Future<void> _warmupEditor(BuildContext context, AppStore store, SessionExercise e) async {
    final session = store.active;
    if (session == null) return;
    FocusScope.of(context).unfocus();
    if (session.isWarmupExercise(e)) {
      store.showWorkoutPhase(warmup: false);
    } else if (session.warmupFor(e.name)?.sets.any((set) => set.done) == true) {
      store.showWorkoutPhase(warmup: true, exerciseName: e.name);
    } else {
      // Most starts are one tap. A first-ever exercise needs one working load, never separate warm-up loads.
      double? weight;
      if (store.warmupWorkingWeight(e) == null) {
        weight = await showDialog<double>(
          context: context,
          builder: (_) => _WarmupLoadDialog(exercise: e.name, unit: session.unit),
        );
        if (weight == null || !context.mounted) return;
      }
      final error = store.startWarmups(exerciseName: e.name, workingWeight: weight);
      if (error != null) notify(context, error);
    }
  }
}

class _WarmupPill extends StatelessWidget {
  final bool active, compact;
  final SessionExercise? ramp;
  final VoidCallback onTap;
  const _WarmupPill({required this.active, required this.compact, required this.ramp, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final complete = ramp?.complete == true;
    final label = active
        ? 'Work sets'
        : complete
        ? 'Warm-up'
        : ramp == null
        ? 'Warm up'
        : 'Resume';
    return Tooltip(
      message: active
          ? 'Show working sets'
          : complete
          ? 'Review warm-up'
          : ramp == null
          ? 'Start warm-up'
          : 'Resume warm-up',
      child: Material(
        color: (complete && !active ? cs.onSurfaceVariant : cs.primary).withValues(alpha: 0.14),
        borderRadius: context.style.brSmall,
        child: InkWell(
          onTap: onTap,
          borderRadius: context.style.brSmall,
          child: SizedBox(
            width: compact ? 28 : 88,
            height: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  active
                      ? Icons.arrow_forward_rounded
                      : complete
                      ? Icons.check_rounded
                      : Icons.local_fire_department_outlined,
                  size: 16,
                  color: complete && !active ? cs.onSurfaceVariant : cs.primary,
                ),
                if (!compact) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: complete && !active ? cs.onSurfaceVariant : cs.primary,
                        fontWeight: FontWeight.w600,
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

class _WarmupLoadDialog extends StatefulWidget {
  final String exercise, unit;
  const _WarmupLoadDialog({required this.exercise, required this.unit});

  @override
  State<_WarmupLoadDialog> createState() => _WarmupLoadDialogState();
}

class _WarmupLoadDialogState extends State<_WarmupLoadDialog> {
  double? _weight;

  @override
  Widget build(BuildContext context) {
    void start() {
      if ((_weight ?? 0) > 0) Navigator.pop(context, _weight);
    }

    return AlertDialog(
      title: const Text('Working weight'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.exercise, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          NumField(
            value: _weight,
            kind: NumKind.weight,
            suffix: widget.unit,
            placeholder: 'Working weight',
            onChanged: (v) => setState(() => _weight = v),
            onSubmitted: start,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: (_weight ?? 0) > 0 ? start : null, child: const Text('Warm up')),
      ],
    );
  }
}

class _RestInput extends StatefulWidget {
  final String initial;
  final String? error;
  final ValueChanged<String> onChanged;
  const _RestInput({super.key, required this.initial, required this.onChanged, this.error});

  @override
  State<_RestInput> createState() => _RestInputState();
}

class _RestInputState extends State<_RestInput> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: 'Rest after entry (seconds or m:ss)',
      hintText: 'e.g. 90 or 1:30',
      errorText: widget.error,
    ),
    onChanged: widget.onChanged,
  );
}

/// The exercise's advice (progression, deload, load guidance) on demand, never as text in the workout.
void _showAdvice(BuildContext context, SessionExercise e) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(e.name),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final line in e.advice) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(line))],
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
  ),
);

/// Plate calculator for [set], or the next unfinished set: its typed weight, else its placeholder. From an
/// unfinished set, a nearest loadable weight can be put straight into it.
SetEntry? _plateSet(AppStore store, SessionExercise e) {
  final sets = store.active?.visibleSetsFor(e) ?? e.sets;
  return sets.where((set) => !set.done).firstOrNull ?? sets.lastOrNull;
}

/// The weight the inline bar shows: the next unfinished set's typed weight, else its placeholder.
double? plateTarget(AppStore store, SessionExercise e) {
  final s = _plateSet(store, e);
  return s == null ? null : s.weight ?? store.fallbackValue(e, e.sets.indexOf(s), 'weight')?.toDouble();
}

void openPlatesFor(BuildContext context, AppStore store, SessionExercise e, [SetEntry? set]) {
  FocusScope.of(context).unfocus();
  final s = set ?? _plateSet(store, e);
  if (s == null) return;
  final weight = s.weight ?? store.fallbackValue(e, e.sets.indexOf(s), 'weight')?.toDouble();
  if (weight == null || weight <= 0) return notify(context, 'Enter a weight first.');
  showPlates(
    context,
    weight,
    exercise: e.name,
    onUse: s.done
        ? null
        : (v) {
            s
              ..weight = v
              ..prescribed = false
              ..invalid.remove('weight');
            store.changed();
          },
  );
}
