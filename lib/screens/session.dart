import 'dart:async';

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
import '../widgets/edition_card.dart';
import '../widgets/record_effect.dart';
import '../widgets/rest_timer.dart';
import '../widgets/tick.dart';
import '../widgets/warmup_background.dart';
import 'exercises.dart';
import 'finish.dart';
import 'plates.dart';
import 'progress.dart';
import 'rep_max.dart';
import 'template_editor.dart';

part 'session/exercise_block.dart';
part 'session/set_row.dart';

/// Focus nodes for one set's numeric fields.
class _SetFocus {
  final weight = FocusNode(), reps = FocusNode(), rir = FocusNode();
  FocusNode forField(String field) => switch (field) {
    'weight' => weight,
    'reps' => reps,
    _ => rir,
  };
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
    if (isLast && !s.done && store.settings.enterCompletesSet) {
      if (!complete(store, e, index) && !s.done) {
        // The set could not be completed: go back to the first empty box instead of moving on.
        final missing = [
          if (s.weight == null) focusOf(s).weight,
          if (s.reps == null) focusOf(s).reps,
          if (s.rir == null && rirEditable(store, e, s)) focusOf(s).rir,
        ].firstOrNull;
        (missing ?? focusOf(s).forField(field)).requestFocus();
        return;
      }
    }
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

  /// Returns whether the set is now complete (or was just un-completed).
  bool complete(AppStore store, SessionExercise e, int index) {
    final wasDone = e.sets[index].done;
    final result = store.toggleSet(e, index);
    if (result.message != null) notify(context, result.message!);
    if (!result.ok) return false;
    if (wasDone || store.active == null) return true;
    final next = nextCircuitStep(store.active!, e);
    if (next == null) return true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = keyOf(next.set).currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 240), alignment: 0.25);
      }
    });
    return true;
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
    unawaited(
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => FinishScreen(summary: summary))),
    );
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
    final blocks = exerciseBlocks(session);
    final steps = {for (final step in sessionSteps(session)) step.set: step};
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
              foregroundColor: Theme.of(context).colorScheme.onError,
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
                    for (final (blockIndex, block) in blocks.indexed)
                      Column(
                        children: [
                          for (final e in block) ...[
                            _ExerciseBlock(
                              key: ObjectKey(e),
                              exercise: e,
                              screen: this,
                              steps: steps,
                              blockIndex: blockIndex,
                              blockCount: blocks.length,
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final name = await pickExercise(context, inWorkout: session.exercises.map((e) => e.name));
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
          if (store.settings.setCelebrations && !MediaQuery.disableAnimationsOf(context))
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
    // This remains the working-set counter. Warm-ups have their own W1 / W2 / W3 rows.
    final sets = [for (final e in session.exercises) ...e.work];
    final total = sets.length;
    final done = sets.where((set) => set.done).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (session.phase == 'Deload' || (session.phase != null && session.targetRir != null)) ...[
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
                    Text(
                      '$done/$total sets',
                      style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
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
