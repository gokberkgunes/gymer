import 'package:flutter/material.dart';

import '../logic/circuits.dart';
import '../logic/estimate.dart';
import '../logic/methods.dart';
import '../logic/numbers.dart';
import '../logic/progression.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/celebration.dart';
import '../widgets/common.dart';
import '../widgets/circuit_editor.dart';
import '../widgets/exercise_actions.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/num_field.dart';
import '../widgets/rest_timer.dart';
import '../widgets/tick.dart';
import 'exercises.dart';
import 'finish.dart';
import 'plates.dart';
import 'progress.dart';
import 'rep_max.dart';
import 'template_editor.dart';

/// Focus nodes for one set's numeric fields.
class _SetFocus {
  final weight = FocusNode(), reps = FocusNode(), rir = FocusNode();
  void dispose() {
    weight.dispose();
    reps.dispose();
    rir.dispose();
  }
}

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _focus = Expando<_SetFocus>();
  final _allFocus = <_SetFocus>[];
  final _setKeys = Expando<GlobalKey>();

  GlobalKey keyOf(SetEntry set) => _setKeys[set] ??= GlobalKey();

  _SetFocus focusOf(SetEntry s) {
    final existing = _focus[s];
    if (existing != null) return existing;
    final created = _SetFocus();
    _allFocus.add(created);
    return _focus[s] = created;
  }

  @override
  void dispose() {
    for (final f in _allFocus) {
      f.dispose();
    }
    super.dispose();
  }

  // ---- Keyboard flow (Enter / Backspace), as in the Flet app ----

  bool rirEditable(AppStore store, SessionExercise e, SetEntry s) =>
      methodSetUsesRir(e.method, s.type) &&
      (store.settings.trackRir || (e.calibrate && calibrationAnchor(e.method, s.type)));

  String lastEditable(AppStore store, SessionExercise e, SetEntry s) => rirEditable(store, e, s) ? 'rir' : 'reps';

  void submit(AppStore store, SessionExercise e, int index, String field) {
    final s = e.sets[index];
    final v = switch (field) {
      'weight' => s.weight,
      'reps' => s.reps,
      _ => s.rir,
    };
    if (v != null) s.accepted.add('$field:$v'); // Enter explicitly accepts an unusual value.
    final isLast = field == lastEditable(store, e, s);
    if (isLast && !s.done && store.settings.enterCompletesSet) complete(store, e, index);
    if (!store.active!.visibleExercises.contains(e)) {
      FocusScope.of(context).unfocus();
      return;
    }
    final visible = store.active!.visibleSetsFor(e);
    final position = visible.indexOf(s);
    FocusNode? next;
    if (field == 'weight') next = focusOf(s).reps;
    if (field == 'reps' && rirEditable(store, e, s)) next = focusOf(s).rir;
    if (next == null && isLast && store.settings.enterMovesToNextSet) {
      final linked = s.done ? nextCircuitStep(store.active!, e) : null;
      if (linked != null) {
        next = focusOf(linked.set).weight;
      } else if (position + 1 < visible.length) {
        next = focusOf(visible[position + 1]).weight;
      }
    }
    if (next != null) {
      next.requestFocus();
    } else if (isLast && store.settings.enterClosesKeyboard) {
      // Nowhere further to go: put the keyboard away instead of staying in the box.
      FocusScope.of(context).unfocus();
    }
  }

  void backspace(AppStore store, SessionExercise e, int index, String field) {
    final s = e.sets[index];
    if (field == 'rir') return focusOf(s).reps.requestFocus();
    if (field == 'reps') return focusOf(s).weight.requestFocus();
    // Crossing from this set's weight into the previous set is optional.
    final visible = store.active!.visibleSetsFor(e);
    final position = visible.indexOf(s);
    if (position > 0 && store.settings.backspaceMovesToPreviousSet) {
      final prev = visible[position - 1];
      (lastEditable(store, e, prev) == 'rir' ? focusOf(prev).rir : focusOf(prev).reps).requestFocus();
    }
  }

  void complete(AppStore store, SessionExercise e, int index) {
    final wasDone = e.sets[index].done;
    final result = store.toggleSet(e, index);
    if (result.message != null) notify(context, result.message!);
    if (!result.ok || wasDone || store.active == null) return;
    final next = nextCircuitStep(store.active!, e);
    if (next == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = keyOf(next.set).currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 240), alignment: 0.25);
      }
    });
  }

  // ---- Actions ----

  Future<void> _finish(AppStore store) async {
    FocusScope.of(context).unfocus();
    final s = store.active!;
    final violation = store.setOrderViolation();
    if (violation != null) return notify(context, violation);
    if (s.doneAll == 0) return notify(context, 'No completed sets. Mark at least one set first.');
    // Finishing cannot be undone, so a stray tap mid-workout must not end it.
    final open = s.exercises.fold(0, (n, e) => n + s.visibleSetsFor(e).where((x) => !x.done).length);
    if (open > 0) {
      final ok = await confirm(
        context,
        'Finish workout?',
        '${plural(open, 'set')} not done yet. They will be saved as skipped.',
        action: 'Finish',
      );
      if (!ok || !mounted) return;
    }
    var saveStructure = false;
    if (store.templateChanged()) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Keep workout changes for next time?'),
          content: const Text(
            "This workout's exercise/set structure, rest timers or set types differ from the saved workout. "
            'Keep these changes for the next workout? Completed weights and reps still update defaults with '
            'the same context. This choice controls the programmed structure.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('This workout only')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save for next time')),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      saveStructure = choice;
    }
    final summary = store.finishSession(saveStructure: saveStructure);
    if (summary == null || !mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => FinishScreen(summary: summary)));
  }

  Future<void> _discard(AppStore store) async {
    final ok = await confirm(
      context,
      'Discard workout',
      'Nothing from this session will be saved.',
      action: 'Discard',
      destructive: true,
    );
    if (!ok || !mounted) return;
    store.discardSession();
    Navigator.pop(context);
  }

  void _editWorkout(AppStore store) {
    final t = store.template(store.active?.templateId);
    if (t == null) return notify(context, 'This quick workout has no saved plan; add exercises below.');
    editTemplate(context, t, fromActive: true);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final session = store.active;
    if (session == null) return const Scaffold();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Text(session.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        // Header actions are rounded squares (theme shape), never circles; see CLAUDE.md.
        actions: [
          IconButton.filled(
            tooltip: 'Edit workout',
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editWorkout(store),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Discard workout',
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _discard(store),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filled(
              tooltip: 'Finish workout',
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              icon: const Icon(Icons.check_rounded),
              onPressed: () => _finish(store),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _Header(session: session),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 130),
                  children: [
                    for (final block in exerciseBlocks(session))
                      Column(
                        children: [
                          for (final e in block) ...[
                            _ExerciseBlock(key: ObjectKey(e), exercise: e, screen: this),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    if (!session.warmingUp)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final name = await pickExercise(context);
                          if (name == null || !context.mounted) return;
                          final error = store.addSessionExercise(name);
                          if (error != null) notify(context, error);
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add exercise'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Positioned.fill(child: SetConfetti(trigger: store.setCelebration)),
          Positioned(
            right: 16,
            bottom: 16,
            child: SafeArea(child: FloatingRestTimer(onTap: () {})),
          ),
        ],
      ),
    );
  }
}

/// Big workout clock on the left, set progress on the right, progress bar below.
class _Header extends StatelessWidget {
  final Session session;
  const _Header({required this.session});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final sets = [for (final e in session.visibleExercises) ...session.visibleSetsFor(e)];
    final total = sets.length;
    final done = sets.where((set) => set.done).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!session.warmingUp &&
              (session.phase == 'Deload' || (session.phase != null && session.targetRir != null))) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (session.targetRir != null && session.phase != null) _WorkoutTag(label: '${session.targetRir} RIR'),
                if (session.phase == 'Deload') const _WorkoutTag(label: 'Deload'),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _WorkoutClock(session: session)),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'Workout phase',
                      onSelected: (phase) {
                        FocusScope.of(context).unfocus();
                        if (phase == 'warmup' || phase == 'working') {
                          store.showWorkoutPhase(warmup: phase == 'warmup');
                        } else {
                          final error = store.startWarmups(sets: phase == 'two' ? 2 : 3);
                          if (error != null) notify(context, error);
                        }
                      },
                      itemBuilder: (_) => [
                        CheckedPopupMenuItem(
                          value: 'working',
                          checked: !session.warmingUp,
                          child: const Text('Working sets'),
                        ),
                        if (session.warmupExercises.isNotEmpty)
                          CheckedPopupMenuItem(
                            value: 'warmup',
                            checked: session.warmingUp,
                            child: const Text('Warm-up'),
                          ),
                        if (session.doneSets == 0 &&
                            !session.warmupExercises.any((e) => e.sets.any((set) => set.done))) ...[
                          const PopupMenuDivider(),
                          const PopupMenuItem(value: 'two', child: Text('Warm-up · 2 sets')),
                          const PopupMenuItem(value: 'three', child: Text('Warm-up · 3 sets')),
                        ],
                      ],
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$done/$total ${session.warmingUp ? 'warm-up' : 'sets'}',
                            style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                          ),
                          Icon(Icons.expand_more_rounded, size: 16, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                    Text(
                      session.clockStarted && !session.clockRunning
                          ? 'Paused'
                          : '~${formatTargetDuration(store.estimateActiveSeconds())}',
                      style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHigh,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutTag extends StatelessWidget {
  final String label;
  const _WorkoutTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// Tap to start/pause/resume · hold to reset. Starts itself on the first set.
class _WorkoutClock extends StatelessWidget {
  final Session session;
  const _WorkoutClock({required this.session});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Tap to start/pause/resume · hold to reset',
      child: InkWell(
        borderRadius: context.style.brSmall,
        onTap: store.toggleClock,
        onLongPress: store.resetClock,
        child: TickBuilder(
          builder: (context) {
            final seconds = session.clockSeconds;
            final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
            final text = h > 0
                ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
                : '$m:${s.toString().padLeft(2, '0')}';
            return Text(
              text,
              style: t.displayMedium?.copyWith(
                fontFeatures: tabular,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.5,
                color: session.clockRunning ? null : cs.onSurfaceVariant,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ExerciseBlock extends StatefulWidget {
  final SessionExercise exercise;
  final _SessionScreenState screen;
  const _ExerciseBlock({super.key, required this.exercise, required this.screen});

  @override
  State<_ExerciseBlock> createState() => _ExerciseBlockState();
}

class _ExerciseBlockState extends State<_ExerciseBlock> {
  SessionExercise get exercise => widget.exercise;
  _SessionScreenState get screen => widget.screen;

  /// While the exercise name is pressed, the whole card lights up (not just the name area).
  bool _pressed = false;

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
    final circuit = session.warmingUp ? null : circuitFor(session.circuits, e.name);
    final scheduledSteps = {for (final step in sessionSteps(session)) step.set: step};
    final blocks = exerciseBlocks(session);
    final blockIndex = blocks.indexWhere((block) => block.contains(e));
    final visibleSets = session.visibleSetsFor(e);
    final collapsed =
        e.collapsed ??
        (visibleSets.isNotEmpty && visibleSets.every((set) => set.done) && store.settings.collapseCompleted);
    final irregularRest = {for (final s in e.sets) s.rest}.length > 1;

    Future<void> substitute() async {
      if (e.sets.any((s) => s.done)) {
        return notify(context, 'Substitute before completing sets for this exercise.');
      }
      final name = await pickExercise(context);
      if (name == null || !context.mounted) return;
      final error = store.substituteExercise(e, name);
      if (error != null) notify(context, error);
    }

    final menu = <(String, IconData, String, VoidCallback)>[
      ('repMax', Icons.calculate_outlined, 'Rep max calculator', () => openRepMaxForExercise(context, e.name)),
      ('rest', Icons.timer_outlined, 'Rest timers', () => _restEditor(context, store, e)),
      ('history', Icons.show_chart_rounded, 'History & progress', () => openExerciseProgress(context, e.name)),
      ('details', Icons.info_outline_rounded, 'Exercise details', () => openExerciseEditor(context, e.name)),
      if (!session.warmingUp)
        ('circuit', Icons.link_rounded, 'Superset / circuit', () => _circuitEditor(context, store, e)),
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
      if (blockIndex < blocks.length - 1)
        (
          'moveDown',
          Icons.arrow_downward_rounded,
          circuit == null ? 'Move down' : 'Move group down',
          () => store.moveSessionExercise(e, 1),
        ),
      if (!session.warmingUp) ('substitute', Icons.swap_horiz_rounded, 'Substitute exercise', substitute),
      (
        'remove',
        Icons.delete_outline_rounded,
        session.warmingUp ? 'Skip warm-up' : 'Remove exercise',
        () {
          final error = store.removeSessionExercise(e);
          if (error != null) notify(context, error);
        },
      ),
    ];
    final pinned = menu.where((action) => store.settings.pinnedExerciseActions.contains(action.$1)).toList();
    final muscles = info?.primary ?? const <String>[];

    final firstAnchor = e.sets.indexWhere((x) => calibrationAnchor(e.method, x.type));
    final heading = ExerciseActionHeader(
      minimumTitleWidth: circuit == null ? 96 : (note.isEmpty ? 144 : 160),
      title: InkWell(
        // No highlight box of its own: the whole card is tinted instead (see _pressed).
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onHighlightChanged: (v) {
          if (v) return setState(() => _pressed = true);
          // Keep the tint briefly after a quick tap so it is visible, then fade it out.
          Future.delayed(const Duration(milliseconds: 250), () {
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
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
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
                              maxLines: note.isEmpty ? null : 2,
                              overflow: note.isEmpty ? null : TextOverflow.ellipsis,
                              style: t.titleMedium?.copyWith(fontSize: 18),
                            ),
                          ),
                        ),
                        if (e.advice.isNotEmpty)
                          InfoDot(tooltip: 'Notes for this exercise', onTap: () => _showAdvice(context, e)),
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
                  if ((e.calibrate || e.calibrationEntered) && firstAnchor >= 0)
                    _CalibrationCard(exercise: e, index: firstAnchor),
                  if (e.method != 'Straight')
                    Tooltip(
                      message: 'Training method; edit the workout to change it',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          e.method,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary),
                        ),
                      ),
                    ),
                  if (collapsed)
                    Text(
                      '${visibleSets.where((x) => x.done).length}/${visibleSets.length}',
                      style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
              if (muscles.isNotEmpty)
                Text(muscles.join(' · '), style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
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
        child: child,
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
                              child: PlateBar(target: plateTarget(store, e), exercise: e.name),
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
    if (session.restLocked && !session.warmingUp) {
      return notify(context, 'Rest times are locked by the active mesocycle.');
    }
    final scopes = store.restScopes(e);
    final circuit = session.warmingUp ? null : circuitFor(session.circuits, e.name);
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
                        seconds = store.rest!.totalSeconds;
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
    if (session == null || session.warmingUp) return;
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

/// SET · KG · REPS · RIR captions aligned with the set row columns.
class _ColumnHeader extends StatelessWidget {
  final SessionExercise exercise;
  final String unit;
  const _ColumnHeader({required this.exercise, required this.unit});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600);
    final e = exercise;
    final rir = (store.active?.visibleSetsFor(e) ?? e.sets).any(
      (s) => methodSetUsesRir(e.method, s.type) && (store.settings.trackRir || s.targetRir != null),
    );
    final load = e.loadMode == 'external' ? unit.toUpperCase() : loadSuffix(e.loadMode, unit).toUpperCase();
    Widget cap(String text, int flex) => Expanded(
      flex: flex,
      child: Text(text, textAlign: TextAlign.center, style: style),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text('SET', textAlign: TextAlign.center, style: style),
          ),
          if (e.loadMode == 'external' && store.platesApply(e.name))
            // The load caption doubles as the plate calculator for the next unfinished set.
            Expanded(
              flex: 10,
              child: Tooltip(
                message: 'Plates',
                child: InkWell(
                  borderRadius: context.style.brSmall,
                  onTap: () => openPlatesFor(context, store, e),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(load, style: style),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.fitness_center_rounded,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            cap(load, 10),
          const SizedBox(width: 6),
          cap('REPS', 7),
          const SizedBox(width: 6),
          cap(rir ? 'RIR' : '', 7),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  final SessionExercise exercise;
  final int index;
  final int position;
  final int count;
  final _SessionScreenState screen;
  final bool showPlannedRest;
  final int plannedRest;
  final bool sharedRest;
  final String unit;

  const _SetRow({
    super.key,
    required this.exercise,
    required this.index,
    required this.position,
    required this.count,
    required this.screen,
    required this.showPlannedRest,
    required this.plannedRest,
    required this.sharedRest,
    required this.unit,
  });

  /// Robust "usual weight": own history, or two independent references.
  /// Prescribed loads never count as evidence of what the user lifts.
  double? _usualWeight(SessionExercise e, SetEntry s) {
    bool compatible(SetEntry o) =>
        isStraightType(s.type) ? isStraightType(o.type) : canonicalSetType(o.type) == canonicalSetType(s.type);
    final own = e.calibrate ? null : s.hintWeight;
    final refs = <double>[if (own != null && own > 0) own];
    for (final o in e.sets) {
      if (identical(o, s) || !compatible(o)) continue;
      if (o.hintWeight != null && o.hintWeight! > 0) refs.add(o.hintWeight!);
      if (o.weight != null && o.weight! > 0 && !o.prescribed) refs.add(o.weight!);
    }
    if ((own == null || own <= 0) && refs.length < 2) return null;
    return refs.isEmpty ? null : median(refs);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    final e = exercise;
    final s = e.sets[index];
    final f = screen.focusOf(s);
    final weightKind = e.loadMode == 'external' ? NumKind.weight : NumKind.load;
    final rirVisible =
        methodSetUsesRir(e.method, s.type) &&
        (store.settings.trackRir || s.targetRir != null || (e.calibrate && calibrationAnchor(e.method, s.type)));
    final number = s.warmup ? 'W${position + 1}' : '${e.sets.take(index + 1).where((x) => !x.warmup).length}';

    String? warning(NumKind kind, num? v) => v == null
        ? null
        : unusualReason(kind, v.toDouble(), usualWeight: kind == NumKind.weight ? _usualWeight(e, s) : null);

    final weightWarn = e.loadMode == 'external' ? warning(NumKind.weight, s.weight) : null;
    final repsWarn = warning(NumKind.reps, s.reps);
    final rirWarn = rirVisible ? warning(NumKind.rir, s.rir) : null;

    final timer = store.rest;
    final nearSet =
        timer != null &&
        timer.exercise == e.name &&
        timer.setIndex == index &&
        timer.warmup == (store.active?.warmingUp ?? false) &&
        store.settings.nearSetTimer;

    final record = store.recordKind(e, s);
    final previous = store.active?.warmingUp == true ? null : store.lastTimeSets(e.name, store.active?.templateId);
    final prev = previous != null && index < previous.length && previous[index].done ? previous[index] : null;
    final repsVisible = store.active == null || store.historicalRepsVisible(store.active!);
    final String? lastTime = prev == null || (prev.weight == null && prev.reps == null)
        ? null
        : [
            if (prev.weight != null) formatNumber(prev.weight!, weightKind),
            if (repsVisible && prev.reps != null) '${prev.weight == null ? '' : '×'}${prev.reps}',
          ].join();

    // Rest sits under the set number so every row keeps the same columns.
    const restStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFeatures: tabular);
    final Widget? restLabel = nearSet
        ? TickBuilder(
            builder: (_) => Tooltip(
              message: timer.overdue ? 'Rest complete' : 'Rest remaining',
              child: Text(signedRest(timer.remainingSeconds), style: restStyle),
            ),
          )
        : showPlannedRest && plannedRest > 0
        ? Text(formatDuration(plannedRest), style: restStyle.copyWith(color: cs.onSurfaceVariant))
        : null;

    // Inputs sit one step lighter than the set tile.
    final fieldFill = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(cs.surfaceContainerHigh, Colors.white, 0.07)
        : cs.surface;

    final typeButton = Tooltip(
      message: store.active?.warmingUp == true
          ? 'Warm-up $number. Hold for set details.'
          : '${s.type} — Set $number. Tap to change set role; hold for set details.',
      child: InkWell(
        borderRadius: st.brSmall,
        onTap: store.active?.warmingUp == true ? null : () => _pickType(context, store),
        onLongPress: () => showSetDetails(
          context,
          store,
          s,
          restLocked: store.active?.warmingUp == true ? false : store.active?.restLocked ?? false,
          linkedRest: s.done && s.circuitRestAfter != null ? s.circuitRestAfter : (sharedRest ? plannedRest : null),
        ),
        child: SizedBox(
          width: 56,
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Plain straight sets and warmups ("W") need no role label.
              if (!isStraightType(s.type) && !s.warmup)
                Text(
                  activeSetTypeLabel(s.type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: cs.primary, fontWeight: FontWeight.w600),
                ),
              Text(number, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              if (restLabel != null)
                restLabel
              else if (record != null)
                Tooltip(
                  message: record == 'weight' ? 'Heaviest weight so far' : 'Best estimated 1RM so far',
                  child: Icon(Icons.emoji_events_outlined, size: 14, color: cs.primary),
                )
              else if (lastTime != null)
                Text(
                  lastTime,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant, fontFeatures: tabular),
                ),
            ],
          ),
        ),
      ),
    );

    final row = Row(
      children: [
        typeButton,
        Expanded(
          flex: 10,
          child: NumField(
            value: s.weight,
            kind: weightKind,
            placeholder: s.hintWeight != null ? formatNumber(s.hintWeight!, weightKind) : null,
            completed: s.done,
            fill: fieldFill,
            align: TextAlign.center,
            invalid: s.invalid.contains('weight'),
            warning: weightWarn,
            tooltip: loadGuidance(e.loadMode),
            focusNode: f.weight,
            onChanged: (v) {
              s
                ..weight = v
                ..prescribed = false
                ..invalid.remove('weight');
              store.changed();
            },
            onSubmitted: () => screen.submit(store, e, index, 'weight'),
            onBackspaceEmpty: () => screen.backspace(store, e, index, 'weight'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 7,
          child: NumField(
            value: s.reps?.toDouble(),
            kind: NumKind.reps,
            placeholder: s.hintReps?.toString(),
            completed: s.done,
            fill: fieldFill,
            align: TextAlign.center,
            invalid: s.invalid.contains('reps'),
            warning: repsWarn,
            tooltip: s.targetReps == null
                ? null
                : (store.active?.phase == 'Deload'
                      ? 'Recovery goal: ${s.targetReps} reps at ${s.targetRir} RIR. Record actual reps.'
                      : 'Next goal: ${s.targetReps} reps at target ${s.targetRir} RIR. Record actual reps.'),
            focusNode: f.reps,
            onChanged: (v) {
              s
                ..reps = v?.round()
                ..invalid.remove('reps');
              store.changed();
            },
            onSubmitted: () => screen.submit(store, e, index, 'reps'),
            onBackspaceEmpty: () => screen.backspace(store, e, index, 'reps'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 7,
          child: rirVisible
              ? NumField(
                  value: s.rir?.toDouble(),
                  kind: NumKind.rir,
                  completed: s.done,
                  fill: fieldFill,
                  align: TextAlign.center,
                  invalid: s.invalid.contains('rir'),
                  warning: rirWarn,
                  tooltip: s.targetRir != null
                      ? 'Actual reps left; target ${s.targetRir} RIR. Leave blank if unknown.'
                      : 'Actual reps left. Leave blank if unknown.',
                  focusNode: f.rir,
                  onChanged: (v) {
                    s
                      ..rir = v?.round()
                      ..invalid.remove('rir');
                    store.changed();
                  },
                  onSubmitted: () => screen.submit(store, e, index, 'rir'),
                  onBackspaceEmpty: () => screen.backspace(store, e, index, 'rir'),
                )
              : const SizedBox.shrink(),
        ),
        Semantics(
          button: true,
          checked: s.done,
          label: '${e.name}, set $number, ${s.done ? 'completed' : 'not completed'}',
          child: InkWell(
            borderRadius: st.brSmall,
            onTap: () {
              FocusScope.of(context).unfocus();
              screen.complete(store, e, index);
            },
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: s.done ? cs.primary : null,
                  border: Border.all(color: s.done ? cs.primary : cs.outline, width: 2),
                  // Rounded square like the other buttons; no circles (see CLAUDE.md).
                  borderRadius: BorderRadius.circular(st.small.clamp(0, 10)),
                ),
                child: s.done ? Icon(Icons.check_rounded, size: 20, color: cs.onPrimary) : null,
              ),
            ),
          ),
        ),
      ],
    );

    // Unusual values only turn orange (reason on long press); no text line under the row,
    // so a set never changes height.
    // Each set is its own tile (as in the Appearance preview) so the set gap reads clearly.
    final content = Container(
      padding: EdgeInsets.symmetric(horizontal: 2, vertical: st.sp(2)),
      decoration: BoxDecoration(
        color: s.done ? cs.primary.withValues(alpha: 0.12) : cs.surfaceContainerHigh,
        borderRadius: st.setTile(position, count),
      ),
      child: Opacity(
        opacity: s.done && st.dimCompleted ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row,
            if (e.notesVisible)
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 4),
                child: _NoteField(set: s),
              ),
          ],
        ),
      ),
    );

    return Dismissible(
      key: ObjectKey(s),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.25},
      background: Container(
        decoration: BoxDecoration(color: cs.error, borderRadius: st.setTile(position, count)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => removeSetWithUndo(context, store, e, s),
      child: content,
    );
  }

  Future<void> _pickType(BuildContext context, AppStore store) async {
    final e = exercise;
    final picked = await pickSetType(context, e.method, [for (final s in e.sets) (s.type, s.groupStart)], index);
    if (picked != null) store.changeSetType(e, e.sets[index], picked);
  }
}

/// Set-role choices valid for this row of the method.
Future<String?> pickSetType(BuildContext context, String method, List<(String, bool)> rows, int index) {
  final choices = setTypeChoices(method, rows, index);
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Set role', style: Theme.of(sheet).textTheme.titleLarge),
          ),
          for (final c in choices)
            ListTile(
              title: Text(displaySetType(c)),
              trailing: canonicalSetType(rows[index].$1) == c
                  ? Icon(Icons.check_rounded, color: Theme.of(sheet).colorScheme.primary)
                  : null,
              onTap: () => Navigator.pop(sheet, c),
            ),
        ],
      ),
    ),
  );
}

class _NoteField extends StatefulWidget {
  final SetEntry set;
  const _NoteField({required this.set});

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final _c = TextEditingController(text: widget.set.note);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    textCapitalization: TextCapitalization.sentences,
    decoration: const InputDecoration(hintText: 'Note'),
    onChanged: (v) {
      widget.set.note = v;
      StoreScope.read(context).changed();
    },
  );
}

/// Long-press set details: logging context, stop reason, planned and actual
/// rest. Labels never convert load or reps.
Future<void> showSetDetails(
  BuildContext context,
  AppStore store,
  SetEntry s, {
  bool restLocked = false,
  bool historical = false,
  int? linkedRest,
}) async {
  final setup = TextEditingController(text: s.context.setup);
  var load = s.context.loadBasis, reps = s.context.repBasis, side = s.context.side, stop = s.stopReason;
  var rest = linkedRest ?? s.rest;
  final actual = TextEditingController(text: s.actualRest?.toString() ?? '');
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
  final saved = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Set details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: setup,
              decoration: const InputDecoration(
                labelText: 'Setup / variation',
                hintText: 'Machine, handle, position or leverage variant',
              ),
            ),
            const SizedBox(height: 10),
            dropdown('Load basis', load, SetContext.loadBasisLabels, (v) => load = v),
            const SizedBox(height: 10),
            dropdown('Rep count basis', reps, SetContext.repBasisLabels, (v) => reps = v),
            const SizedBox(height: 10),
            dropdown('Side', side, SetContext.sideLabels, (v) => side = v),
            const SizedBox(height: 8),
            Text(
              'These labels do not convert load or reps. Correct the recorded numbers separately if their meaning was wrong.',
              style: Theme.of(c).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            dropdown('Observed stop reason', stop, stopReasons, (v) => stop = v),
            const SizedBox(height: 10),
            DurationField(
              seconds: rest,
              label: linkedRest == null ? 'Planned rest after segment' : 'Linked rest after segment',
              readOnly: linkedRest != null || (restLocked && !historical),
              tooltip: linkedRest == null ? null : 'Shared rest is set for the whole superset or circuit',
              onChanged: (v) => rest = v,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: actual,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Actual rest after segment (seconds)',
                hintText: 'Leave blank if unknown',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Actual rest is your reported rest after this segment, not the timer setting. Unknown records remain blank.',
              style: Theme.of(c).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save details')),
      ],
    ),
  );
  if (saved == true) {
    s
      ..context = SetContext(setup: setup.text.trim(), loadBasis: load, repBasis: reps, side: side)
      ..stopReason = stop
      ..rest = linkedRest == null ? rest : s.rest
      ..actualRest = int.tryParse(actual.text.trim());
    store.changed();
  }
  setup.dispose();
  actual.dispose();
}

class _CalibrationCard extends StatelessWidget {
  final SessionExercise exercise;
  final int index;
  const _CalibrationCard({required this.exercise, required this.index});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final e = exercise;
    final cal = store.calibrationFor(e.name, e.method, store.active!);
    final unit = store.active!.unit;
    final entered = !e.calibrate && e.calibrationEntered;
    final hint = entered
        ? 'save the workout to keep it'
        : cal != null
        ? 'start ~${formatNumber(cal.weight, NumKind.weight)} $unit'
        : 'set a baseline';
    final color = entered ? cs.onSurfaceVariant : cs.primary;
    // A small pill beside the exercise name; the dialog carries the explanation.
    return Tooltip(
      message: entered ? 'Calibrated · $hint' : 'Calibrate · $hint',
      child: Material(
        color: color.withValues(alpha: 0.14),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: entered ? null : () => _calibrate(context, store, cal),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(entered ? Icons.check_rounded : Icons.tune_rounded, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  entered ? 'Calibrated' : 'Calibrate',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _calibrate(BuildContext context, AppStore store, Calibration? cal) async {
    final e = exercise;
    final unit = store.active!.unit;
    final copy = switch (e.method) {
      'Straight' =>
        'Record one honest straight set. Gymer uses weight, reps, and RIR to establish the mesocycle baseline.',
      'Cluster' =>
        'Record the first cluster segment. Cluster rest periods make normal rep-max conversion inappropriate, so method-specific history is used instead of pretending a cluster set is an RM test.',
      'AMRAP' => "Record the AMRAP set and actual RIR if known. The method's name does not prove muscular failure.",
      _ =>
        'Record the ${e.method} activation set. The activation set is the strength anchor; later fatigued segments do not become independent rep-max tests.',
    };
    final usesRir = cal?.usesRir ?? e.method != 'Cluster';
    var weight = cal?.weight;
    int? reps;
    int? rir;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Mesocycle calibration · ${e.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Establish this exercise for the new mesocycle',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(copy),
              const SizedBox(height: 10),
              Text(
                cal == null
                    ? 'There is not enough compatible history to estimate a starting weight. Pick a sensible load and use this set to establish one.'
                    : 'Suggested starting weight: ${formatNumber(cal.weight, NumKind.weight)} $unit for about ${cal.targetReps} reps'
                          '${cal.usesRir && cal.targetRir != null ? ' @ ${cal.targetRir} RIR' : ''}.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: NumField(
                      value: weight,
                      kind: NumKind.weight,
                      placeholder: 'Weight',
                      suffix: unit,
                      onChanged: (v) => weight = v,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: NumField(
                      value: null,
                      kind: NumKind.reps,
                      placeholder: 'Reps',
                      onChanged: (v) => reps = v?.round(),
                    ),
                  ),
                  if (usesRir) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: NumField(
                        value: null,
                        kind: NumKind.rir,
                        placeholder: 'RIR',
                        onChanged: (v) => rir = v?.round(),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'The load hint aims for about ${cal?.targetReps ?? calibrationTargetReps} reps. Record what you actually achieve; '
                'calibration is not rejected if you land outside the planned rep range.',
                style: Theme.of(c).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Skip')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Use calibration set')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final w = weight, r = reps;
    if (w == null || r == null || (usesRir && rir == null)) {
      return notify(context, 'Enter weight, reps${usesRir ? ' and RIR' : ''} for the calibration set.');
    }
    store.applyCalibration(e, index, w, r, rir);
  }
}

/// Removes a set and offers a few seconds to put it back.
void removeSetWithUndo(BuildContext context, AppStore store, SessionExercise e, SetEntry set) {
  final index = e.sets.indexOf(set);
  if (index < 0) return;
  store.removeSet(e, set);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Set removed from ${e.name}'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.restoreSet(e, index, set)),
      ),
    );
}
