part of '../store.dart';

/// Editing the active workout: exercises, sets and completing sets.
extension AppStoreSessionEdits on AppStore {
  /// Rebuild rows after editing the template mid-session, keeping recorded sets.
  void _applyTemplateToActive(WorkoutTemplate t) {
    final s = active!;
    final old = {for (final e in s.exercises) e.name.toLowerCase(): e};
    final cycle = cycles.where((c) => c.id == s.cycleId).firstOrNull;
    s.name = t.name;
    s.circuits = copyCircuits(t.circuits);
    s.exercises = [
      for (final te in t.exercises)
        () {
          final existing = old[te.name.toLowerCase()];
          final fresh = s.phase == 'Deload' && cycle != null
              ? _deloadExercise(te, cycle, s)
              : _buildExercise(te, s, cycle);
          if (existing == null) return fresh;
          // A deload exercise is its own plan (straight sets, fewer of them): editing the workout mid-deload
          // must not turn its rows back into the build plan's method and roles. Only rests follow the edit.
          if (s.phase == 'Deload') {
            final work = te.sets.where((ts) => !isWarmup(ts.type)).toList();
            var w = 0;
            for (final set in existing.sets.where((set) => !set.warmup && !set.done)) {
              if (w < work.length) set.rest = work[w].rest;
              w++;
            }
            return existing;
          }
          existing.method = canonicalMethod(te.method);
          existing.sets = [
            for (final (i, ts) in te.sets.indexed)
              if (i < existing.sets.length)
                (existing.sets[i]
                  ..type = ts.type
                  ..rest = ts.rest
                  ..groupStart = ts.groupStart
                  ..hintWeight = existing.sets[i].hintWeight ?? ts.weight
                  ..hintReps = existing.sets[i].hintReps ?? (historicalRepsVisible(s) ? ts.reps : null))
              else if (i < fresh.sets.length)
                fresh.sets[i],
          ];
          for (final set in existing.sets) {
            if (!methodSetUsesRir(existing.method, set.type)) set.rir = null;
          }
          return existing;
        }(),
    ];
    // Preserve completed warm-ups when the plan is edited, and discard ramps for removed exercises.
    s.warmupExercises.removeWhere((warmup) => !s.exercises.any((exercise) => exercise.name == warmup.name));
    reconcileCircuits(s.circuits, s.exercises.map((e) => e.name));
    _finishWarmupPhase();
  }

  /// Completed sets can't disappear when editing the plan mid-workout.
  String? blockedTemplateEdit(WorkoutTemplate t) {
    final s = active;
    if (s == null || s.templateId != t.id) return null;
    for (final e in s.exercises) {
      for (final (i, set) in e.sets.indexed) {
        if (!set.done) continue;
        final te = t.exercises.where((x) => sameExercise(x.name, e.name)).firstOrNull;
        if (te == null || i >= te.sets.length) {
          return '${e.name}: completed sets cannot be removed or replaced while the workout is active.';
        }
      }
    }
    return null;
  }

  /// Adds an exercise to the running workout. Returns an error message.
  String? addSessionExercise(String name) {
    final s = active;
    if (s == null) return null;
    if (s.exercises.any((e) => sameExercise(e.name, name))) {
      return 'That exercise is already in the current workout.';
    }
    final info = addExercise(name);
    final fromTemplate = template(s.templateId)?.exercises.where((e) => sameExercise(e.name, info.name)).firstOrNull;
    final te =
        fromTemplate ??
        TemplateExercise(
          name: info.name,
          sets: [for (var i = 0; i < math.max(1, settings.defaultSets); i++) TemplateSet(rest: settings.defaultRest)],
        );
    final latest = _latestSetValues(info.name, null, anyWorkout: true) ?? const <SetEntry>[];
    final built = _buildExercise(te, s, cycles.where((c) => c.id == s.cycleId).firstOrNull);
    for (final (i, set) in built.sets.indexed) {
      if (set.hintWeight == null && i < latest.length && latest[i].done && latest[i].context == set.context) {
        set.hintWeight = latest[i].weight;
      }
    }
    s.exercises.add(built);
    changed();
    return null;
  }

  String? removeSessionExercise(SessionExercise e) {
    // "Skip warm-up" arrives here with the ramp card: skipping must work after some ramp sets are done.
    // Finished ramp sets stay recorded; only the rest of the ramp is dropped.
    if (active?.isWarmupExercise(e) ?? false) {
      if (e.sets.any((s) => s.done)) {
        e.sets.removeWhere((s) => !s.done);
      } else {
        active!.warmupExercises.remove(e);
      }
      _finishWarmupPhase();
      if (rest?.exercise == e.name && rest?.warmup == true) _dismissRest();
      changed();
      return null;
    }
    if (e.sets.any((s) => s.done)) return 'Completed exercises cannot be removed from the current session.';
    active?.exercises.remove(e);
    active?.warmupExercises.removeWhere((warmup) => identical(warmup, e) || warmup.name == e.name);
    if (active != null) reconcileCircuits(active!.circuits, active!.exercises.map((e) => e.name));
    _finishWarmupPhase();
    if (rest?.exercise == e.name) _dismissRest();
    changed();
    return null;
  }

  String? substituteExercise(SessionExercise e, String newName) {
    if (e.sets.any((s) => s.done)) return 'Substitute before completing sets for this exercise.';
    final s = active!;
    if (s.exercises.any((x) => x != e && sameExercise(x.name, newName))) {
      return 'That exercise is already in the current workout.';
    }
    final info = addExercise(newName);
    renameCircuitExercise(s.circuits, e.name, info.name);
    s.warmupExercises.removeWhere((warmup) => warmup.name == e.name);
    _finishWarmupPhase();
    final latest = _latestSetValues(info.name, null, anyWorkout: true) ?? const <SetEntry>[];
    e
      ..name = info.name
      ..loadMode = info.loadMode
      ..calibrate = false
      ..advice = info.loadMode == 'external' ? [] : [loadGuidance(info.loadMode)];
    for (final (i, set) in e.sets.indexed) {
      final prev = i < latest.length ? latest[i] : null;
      set
        ..weight = null
        ..reps = null
        ..rir = null
        ..prescribed = false
        ..stopReason = ''
        ..actualRest = null
        ..circuitRestAfter = null
        ..targetReps = null
        ..context = info.context
        ..hintWeight = prev != null && prev.done && prev.context == info.context ? prev.weight : null
        ..hintReps = null;
    }
    changed();
    return null;
  }

  void addSet(SessionExercise e) {
    final last = e.sets.isEmpty ? null : e.sets.last;
    final type = active?.warmupExercises.contains(e) == true
        ? 'Warm-up'
        : defaultNextSetType(e.method, [for (final s in e.sets) s.type]);
    e.sets.add(
      SetEntry(
        type: type,
        rest: last?.rest ?? settings.defaultRest,
        context: last?.context ?? exercise(e.name)?.context ?? const SetContext(),
        hintWeight: last?.weight ?? last?.hintWeight,
        hintReps: last?.reps ?? last?.hintReps,
        targetRir: methodSetUsesRir(e.method, type) ? (last?.targetRir ?? active?.targetRir) : null,
      ),
    );
    e.collapsed = false;
    changed();
  }

  void removeSet(SessionExercise e, SetEntry set) {
    final index = e.sets.indexOf(set);
    if (index < 0) return;
    e.sets.removeAt(index);
    _reconcileSession(e);
    final r = rest;
    if (r != null && r.exercise == e.name && r.warmup == (active?.warmupExercises.contains(e) == true)) {
      if (r.setIndex == index) {
        _dismissRest();
      } else if (r.setIndex > index) {
        rest = RestTimer(
          startedAt: r.startedAt,
          totalSeconds: r.totalSeconds,
          exercise: e.name,
          setIndex: r.setIndex - 1,
          countdown: r.countdown,
          warmup: r.warmup,
        );
      }
    }
    _finishWarmupPhase();
    changed();
  }

  void changeSetType(SessionExercise e, SetEntry set, String type) {
    if (active?.warmupExercises.contains(e) == true) return;
    set.type = type;
    _reconcileSession(e);
    changed();
  }

  void _reconcileSession(SessionExercise e) {
    final fixed = reconcileMethodSets(e.method, [for (final s in e.sets) (s.type, s.groupStart)]);
    for (var i = 0; i < e.sets.length; i++) {
      e.sets[i]
        ..type = fixed[i].$1
        ..groupStart = fixed[i].$2;
      if (!methodSetUsesRir(e.method, e.sets[i].type)) e.sets[i].rir = null;
    }
  }

  /// Placeholder for an empty field: own hint, then the typed value just above.
  num? fallbackValue(SessionExercise e, int index, String field) {
    final s = e.sets[index];
    if (field == 'weight' && s.hintWeight != null) return s.hintWeight;
    if (field == 'reps' && s.hintReps != null) return s.hintReps;
    if (field == 'rir' || index == 0) return null;
    final visible = active?.visibleSetsFor(e) ?? e.sets;
    final position = visible.indexOf(s);
    if (position <= 0) return null;
    final above = visible[position - 1];
    if (above.warmup != s.warmup) return null;
    return field == 'weight' ? above.weight : above.reps;
  }

  /// Completing a set: calibration first, optional set order, then blank
  /// fields fall back to the placeholder or the set above; anything still
  /// missing is marked invalid and the set stays open.
  CompleteResult toggleSet(SessionExercise e, int index) {
    final s = active!;
    final set = e.sets[index];
    final warmup = s.warmupExercises.contains(e);
    if (!s.visibleExercises.contains(e)) {
      return const CompleteResult.blocked('Show this exercise’s sets before editing them.');
    }
    if (set.done) {
      set
        ..done = false
        ..circuitRestAfter = null;
      final circuit = warmup ? null : circuitFor(s.circuits, e.name);
      if ((rest?.exercise == e.name && rest?.setIndex == index && rest?.warmup == warmup) ||
          (circuit != null && rest?.warmup == false && circuit.exercises.contains(rest?.exercise))) {
        _dismissRest();
      }
      e.collapsed = null;
      changed();
      return const CompleteResult.done();
    }
    if (e.calibrate && !set.warmup && !calibrationAnchor(e.method, set.type)) {
      return CompleteResult.blocked('Calibrate the ${e.method} anchor before continuing.');
    }
    if (settings.requirePreviousSet) {
      final next = nextCircuitStep(s, e);
      if (!set.warmup && next != null && (next.exercise != e || next.index != index)) {
        return CompleteResult.blocked('Complete ${next.exercise.name} set ${next.index + 1} first.');
      }
      final earlier = s.visibleSetsFor(e).where((x) => !x.done).map(e.sets.indexOf).firstOrNull ?? -1;
      if (earlier >= 0 && earlier < index) {
        return CompleteResult.blocked('Complete set ${earlier + 1} of ${e.name} first.');
      }
    }
    if (!_resolveFields(e, index)) {
      changed();
      return const CompleteResult.blocked();
    }
    set
      ..done = true
      ..accepted.addAll([
        for (final (f, v) in [('weight', set.weight), ('reps', set.reps), ('rir', set.rir)])
          if (v != null) '$f:$v',
      ]);
    if (e.calibrate && calibrationAnchor(e.method, set.type)) {
      applyCalibration(e, index, set.weight!, set.reps!, set.rir);
    } else {
      _propagateFollowing(e, index);
    }
    if (!s.clockStarted) {
      s
        ..clockStarted = true
        ..clockElapsed = 0
        ..clockRunningSince = DateTime.now();
    }
    if (settings.haptics) alerts.setDone();
    setCelebration++;
    final circuit = warmup || set.warmup ? null : circuitFor(s.circuits, e.name);
    if (circuit != null) {
      final steps = sessionSteps(s).where((step) => step.circuit == circuit).toList();
      final step = steps.where((step) => step.exercise == e && step.index == index).firstOrNull;
      final roundComplete = step != null && steps.where((other) => other.round == step.round).every((s) => s.set.done);
      final pending = steps.any((s) => !s.set.done);
      if (step != null && !step.endsTurn) {
        set.circuitRestAfter = set.rest;
        startRest(e.name, index, set.rest);
      } else if (roundComplete && pending) {
        set.circuitRestAfter = circuit.rest;
        startRest(e.name, index, circuit.rest);
      } else {
        set.circuitRestAfter = 0;
        _dismissRest();
      }
      e.collapsed = null;
    } else if (warmup) {
      startRest(e.name, index, set.rest);
      _finishWarmupPhase();
      e.collapsed = null;
    } else if (s.visibleSetsFor(e).every((set) => set.done)) {
      if (rest?.exercise == e.name) _dismissRest();
      e.collapsed = null;
    } else {
      startRest(e.name, index, set.rest);
    }
    nextCircuitStep(s, e)?.exercise.collapsed = false;
    changed();
    return const CompleteResult.done();
  }

  bool _resolveFields(SessionExercise e, int index) {
    final set = e.sets[index];
    set.invalid.clear();
    final weightKind = e.loadMode == 'external' ? NumKind.weight : NumKind.load;
    // No placeholder for a box the user is visibly (if wrongly) filling in.
    if (!set.badText.contains('weight')) set.weight ??= fallbackValue(e, index, 'weight')?.toDouble();
    if (!set.badText.contains('reps')) set.reps ??= fallbackValue(e, index, 'reps')?.toInt();
    if (set.weight == null || !numberAllowed(set.weight!, weightKind)) set.invalid.add('weight');
    if (set.reps == null || !numberAllowed(set.reps!.toDouble(), NumKind.reps)) set.invalid.add('reps');
    if (set.rir != null && !numberAllowed(set.rir!.toDouble(), NumKind.rir)) set.invalid.add('rir');
    // A box still showing unusable text holds an older value than the user sees: mark it (red, no popup) and
    // leave the set open, instead of completing with a number the user did not type.
    set.invalid.addAll(set.badText);
    if (!methodSetUsesRir(e.method, set.type)) set.rir = null;
    return set.invalid.isEmpty;
  }

  /// Seed later placeholders without violating the selected training method.
  void _propagateFollowing(SessionExercise e, int index) {
    final source = e.sets[index];
    // A rehearsal's load and rep target must never flatten a ramp or seed a working set.
    if (source.warmup) return;
    final fields = switch (e.method) {
      'Straight' || 'Myo-Rep Match' || 'Cluster' => const ['weight', 'reps'],
      'Drop Set' => const <String>[],
      _ => const ['weight'],
    };
    if (fields.isEmpty) return;
    for (final later in e.sets.skip(index + 1)) {
      if (later.warmup) continue;
      if (later.context != source.context) continue;
      if ((fields.contains('weight') && later.weight != null) || (fields.contains('reps') && later.reps != null)) {
        continue;
      }
      if (fields.contains('weight') &&
          source.weight != null &&
          (settings.updateFollowingDefaults || later.hintWeight == null)) {
        later.hintWeight = source.weight;
      }
      if (fields.contains('reps') &&
          source.reps != null &&
          (settings.updateFollowingDefaults || later.hintReps == null)) {
        later.hintReps = source.reps;
      }
    }
  }

  /// Applies a calculator target to the next unfinished set.
  String applyRepMaxTarget(String exerciseName, double weight, int reps, int rir) {
    final s = active;
    // The working exercise, even while its warm-up ramp is shown: a working target never goes into a warm-up row.
    final e = s?.exercises.where((x) => x.name == exerciseName).firstOrNull;
    if (s == null || e == null) return 'No active workout.';
    if (e.loadMode != 'external') return 'Choose added load or assistance manually for this exercise.';
    final target = e.sets.where((x) => !x.done && !x.warmup).firstOrNull;
    if (target == null) return 'All working sets for this exercise are already completed.';
    target
      ..weight = weight
      ..reps = reps
      ..rir = null
      ..prescribed = false
      ..targetRir = s.rirLocked && s.targetRir != null ? s.targetRir : rir
      ..accepted.addAll(['weight:$weight', 'reps:$reps']);
    changed();
    return 'Loaded ${formatNumber(weight, NumKind.weight)} ${s.unit} × $reps into the next $exerciseName set.';
  }
}
