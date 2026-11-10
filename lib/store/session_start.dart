part of '../store.dart';

/// Starting a workout: building exercises, warm-ups, guidance and calibration.
extension AppStoreSessionStart on AppStore {
  void moveSessionExercise(SessionExercise e, int delta) {
    final session = active;
    if (session == null) return;
    final blocks = exerciseBlocks(session);
    final i = blocks.indexWhere((block) => block.contains(e));
    if (i < 0 || i + delta < 0 || i + delta >= blocks.length) return;
    blocks.insert(i + delta, blocks.removeAt(i));
    session.exercises = [
      for (final visible in blocks.expand((block) => block))
        session.exercises.firstWhere((exercise) => exercise.name == visible.name),
    ];
    changed();
  }

  /// Undo for [removeSet]: puts the same set back where it was.
  void restoreSet(SessionExercise e, int index, SetEntry set) {
    // The snackbar can outlive the workout: never put a set into a saved or discarded one.
    final session = active;
    if (session == null || !(session.exercises.contains(e) || session.warmupExercises.contains(e))) return;
    e.sets.insert(index.clamp(0, e.sets.length), set);
    _reconcileSession(e);
    e.collapsed = false;
    if (active?.isWarmupExercise(e) == true && !set.done) {
      active!
        ..warmingUp = true
        ..warmupExercise = e.name;
    }
    changed();
  }

  /// Latest completed session of this exercise and method, preferring the
  /// same workout (latest_completed_*_session).
  List<SetEntry>? _latestMethodSession(String exercise, String method, String? templateId) {
    List<SetEntry>? fallback;
    for (final s in history) {
      if (s.phase == 'Deload') continue;
      final e = s.exercises
          .where((e) => e.name.toLowerCase() == exercise.toLowerCase() && e.method == method)
          .firstOrNull;
      if (e == null || !e.sets.any((x) => x.done)) continue;
      final sets = [for (final x in e.sets) _inUnit(x, s.unit, null, exercise)];
      if (s.templateId == templateId) return sets;
      fallback ??= sets;
    }
    return fallback;
  }

  bool _calibrated(Mesocycle c, String? templateId, String exercise, String method) {
    for (final s in history) {
      if (s.cycleId != c.id || s.templateId != templateId || s.phase == 'Deload') continue;
      for (final e in s.exercises) {
        if (e.name.toLowerCase() != exercise.toLowerCase() || e.method != method) continue;
        if (e.sets.any(
          (x) => x.done && calibrationAnchor(method, x.type) && (x.weight ?? 0) > 0 && (x.reps ?? 0) > 0,
        )) {
          return true;
        }
      }
    }
    return false;
  }

  /// Historical reps stay hidden in mesocycles unless the setting opts in.
  bool historicalRepsVisible(Session s) => s.cycleId == null || settings.showPreviousReps;

  void startSession(WorkoutTemplate? t, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final ctx = cycleContext(now);
    final cycle = ctx?.$1;
    final status = ctx?.$2;
    final session = Session(
      id: 'S${now.microsecondsSinceEpoch}',
      templateId: t?.id,
      name: t?.name ?? 'Quick workout',
      unit: settings.unit,
      startedAt: now,
      bodyweight: bodyweightAt(now, settings.unit),
      exercises: [],
      circuits: copyCircuits(t?.circuits ?? []),
      cycleId: cycle?.id,
      microcycle: status?.currentMicro,
      phase: status?.phase,
      targetRir: status?.suggestedRir,
      rirLocked: cycle?.rirLock ?? false,
      restLocked: cycle?.restLock ?? false,
    );
    for (final te in t?.exercises ?? <TemplateExercise>[]) {
      session.exercises.add(
        status?.phase == 'Deload' ? _deloadExercise(te, cycle!, session) : _buildExercise(te, session, cycle),
      );
    }
    active = session;
    reconcileCircuits(session.circuits, session.exercises.map((e) => e.name));
    rest = null;
    _syncAlerts();
    changed();
  }

  /// The next eligible exercise, also used by callers without an explicit exercise.
  SessionExercise? get nextWarmupExercise {
    final session = active;
    if (session == null) return null;
    final candidates = session.exercises.where(
      (e) => e.loadMode == 'external' && !e.work.any((s) => s.done) && session.warmupFor(e.name) == null,
    );
    return candidates.where((e) => warmupWorkingWeight(e) != null).firstOrNull ?? candidates.firstOrNull;
  }

  /// Prefer today's plan. If this workout has no load yet, reuse a compatible completed working set
  /// from the same exercise in another workout. Warm-up loads are never a source.
  double? warmupWorkingWeight(SessionExercise exercise) {
    if (exercise.loadMode != 'external' || exercise.work.isEmpty) return null;
    for (final set in exercise.work) {
      final weight = set.weight ?? set.hintWeight;
      if (weight != null && weight.isFinite && weight > 0) return weight;
    }
    final context = exercise.work.first.context;
    for (final session in history) {
      if (session.phase == 'Deload') continue;
      for (final past in session.exercises) {
        if (past.name.toLowerCase() != exercise.name.toLowerCase() ||
            past.loadMode != exercise.loadMode ||
            past.method != exercise.method) {
          continue;
        }
        for (final set in past.work) {
          final weight = set.weight;
          if (set.done &&
              (set.reps ?? 0) > 0 &&
              set.context == context &&
              weight != null &&
              weight.isFinite &&
              weight > 0) {
            final unit = active?.unit ?? settings.unit;
            return session.unit == unit
                ? weight
                : gymLoad(exercise.name, convertWeight(weight, session.unit, unit), unit);
          }
        }
      }
    }
    return null;
  }

  /// Replace only this exercise's working rows with its ramp, keeping every other card visible.
  String? startWarmups({int? sets, String? exerciseName, double? workingWeight}) {
    final session = active;
    if (session == null) return 'Start a workout first.';
    sets ??= settings.warmupSets;
    if (sets != 2 && sets != 3) return 'Choose two or three warm-up sets.';
    final target = exerciseName == null
        ? nextWarmupExercise
        : session.exercises.where((e) => e.name == exerciseName).firstOrNull;
    if (target == null) return 'No exercise is waiting for warm-ups.';
    if (target.work.any((set) => set.done)) return 'Start warm-ups before completing this exercise’s working sets.';
    if (target.loadMode != 'external') return 'Warm-up ramps require an external working load.';
    if (session.warmupFor(target.name)?.sets.any((set) => set.done) == true) {
      return 'Warm-ups are already underway. Tap Resume to return to them.';
    }
    final source =
        target.work.where((set) => (set.weight ?? set.hintWeight ?? 0) > 0).firstOrNull ?? target.work.firstOrNull;
    if (source == null) return 'Add a working set first.';
    final load = workingWeight ?? warmupWorkingWeight(target);
    if (load == null || !load.isFinite || !numberAllowed(load, NumKind.weight) || load <= 0) {
      return 'Choose a working weight for ${target.name}.';
    }
    final usesBar = platesApply(target.name);
    final ramp = warmupRamp(
      load,
      sets: sets,
      increment: incrementFor(target.name, session.unit) ?? 0.5,
      bar: usesBar ? plates(load, name: target.name).bar : 0,
      plates: usesBar ? settings.plates : null,
      pairs: usesBar ? settings.platePairs : null,
    );
    if (ramp.isEmpty) return 'No warm-up loads are available with this plate setup.';
    // A first-time load is a plan, not an observation. Keep it ready for the working rows too.
    for (final set in target.work) {
      if (set.weight == null && set.hintWeight == null && set.context == source.context) set.hintWeight = load;
    }
    session.warmupExercises.removeWhere((e) => e.name == target.name);
    session.warmupExercises.add(
      SessionExercise(
        name: target.name,
        sets: [
          for (final step in ramp)
            SetEntry(
              type: 'Warm-up',
              weight: step.weight,
              reps: step.reps,
              hintWeight: step.weight,
              hintReps: step.reps,
              rest: 60,
              context: source.context,
              prescribed: true,
            ),
        ],
      ),
    );
    session
      ..warmupExercise = target.name
      ..warmingUp = true;
    _dismissRest();
    changed();
    return null;
  }

  void showWorkoutPhase({required bool warmup, String? exerciseName}) {
    final session = active;
    if (session == null || (warmup && session.warmupExercises.isEmpty)) return;
    if (warmup) {
      final target = exerciseName == null
          ? session.warmupFor(session.warmupExercise ?? '') ?? session.warmupExercises.firstOrNull
          : session.warmupFor(exerciseName);
      if (target == null) return;
      session.warmupExercise = target.name;
      target.collapsed = false;
    } else {
      final working = session.exercises.where((e) => e.name == session.activeWarmup?.name).firstOrNull;
      if (working != null && working.collapsed == true) working.collapsed = false;
    }
    session.warmingUp = warmup;
    changed();
  }

  void _finishWarmupPhase() {
    final session = active;
    final warmup = session?.activeWarmup;
    if (session != null && session.warmingUp && (warmup == null || warmup.sets.every((set) => set.done))) {
      final name = warmup?.name ?? session.warmupExercise;
      final working = session.exercises.where((e) => e.name == name).firstOrNull;
      if (working != null && working.collapsed == true) working.collapsed = false;
      session.warmingUp = false;
    }
  }

  SessionExercise _buildExercise(TemplateExercise te, Session session, Mesocycle? cycle) {
    final info = exercise(te.name);
    final loadMode = info?.loadMode ?? defaultLoadModeFor(te.name);
    final method = canonicalMethod(te.method);
    final latest = _latestSetValues(te.name, session.templateId) ?? const <SetEntry>[];
    final showReps = historicalRepsVisible(session);
    final sets = <SetEntry>[];
    for (final (i, ts) in te.sets.indexed) {
      final context = contextFor(te.name, ts);
      var prev = i < latest.length ? latest[i] : null;
      if (prev != null && (!prev.done || prev.context != context)) prev = null;
      sets.add(
        SetEntry(
          type: ts.type,
          rest: ts.rest,
          groupStart: ts.groupStart,
          context: context,
          hintWeight: prev?.weight ?? ts.weight ?? (loadMode == 'bodyweight' ? 0 : null),
          hintReps: showReps ? (prev?.reps ?? ts.reps) : null,
          targetRir: methodSetUsesRir(method, ts.type) ? session.targetRir : null,
        ),
      );
    }
    final e = SessionExercise(name: te.name, method: method, loadMode: loadMode, sets: sets);
    final starting = _cycleStartingExercise(te.name, method, session);
    if (starting != null) {
      for (final (i, set) in e.sets.indexed) {
        set.hintWeight = starting.sets[i].weight;
      }
    }
    _applyGuidance(e, session, cycle);
    return e;
  }

  /// A cloned starting plan applies only until this exercise has been trained in its new cycle.
  /// Changed methods, roles or load meaning require a fresh baseline instead of reusing an old load.
  SessionExercise? _cycleStartingExercise(String name, String method, Session session) {
    final cycle = cycles.where((c) => c.id == session.cycleId).firstOrNull;
    if (cycle == null || session.phase != 'Build') return null;
    if (history.any(
      (s) =>
          s.cycleId == cycle.id &&
          s.templateId == session.templateId &&
          s.phase != 'Deload' &&
          s.exercises.any(
            (e) => e.name.toLowerCase() == name.toLowerCase() && e.method == method && e.work.any((set) => set.done),
          ),
    )) {
      return null;
    }
    final starting = cycle.startingLoads[session.templateId]
        ?.where((e) => e.name.toLowerCase() == name.toLowerCase() && e.method == method)
        .firstOrNull;
    final plan = template(
      session.templateId,
    )?.exercises.where((e) => e.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    if (starting == null ||
        plan == null ||
        canonicalMethod(plan.method) != method ||
        starting.sets.length != plan.sets.length ||
        starting.loadMode != (exercise(name)?.loadMode ?? defaultLoadModeFor(name))) {
      return null;
    }
    for (final (i, set) in plan.sets.indexed) {
      final seed = starting.sets[i];
      if (canonicalSetType(set.type) != canonicalSetType(seed.type) ||
          set.groupStart != seed.groupStart ||
          contextFor(name, set) != seed.context) {
        return null;
      }
    }
    return SessionExercise(
      name: name,
      method: method,
      loadMode: starting.loadMode,
      sets: [for (final set in starting.sets) _inUnit(set, cycle.startingLoadUnit, session.unit, name)],
    );
  }

  /// Progression, calibration and the advice lines shown under an exercise.
  void _applyGuidance(SessionExercise e, Session session, Mesocycle? cycle) {
    final info = exercise(e.name);
    final method = e.method;
    final inBuild = cycle != null && session.phase == 'Build';
    final contextError = contextProblem(e.sets);
    Recommendation? rec;
    if (inBuild && e.loadMode == 'external') {
      final previous = _cycleStartingExercise(e.name, method, session) == null
          ? _latestMethodSession(e.name, method, session.templateId)
          : null;
      final straightOk = method != 'Straight' || _straightGuidanceAllowed(e);
      if (previous != null && straightOk) {
        rec = recommend(
          previous: previous,
          planned: e.sets,
          method: method,
          targetRir: session.targetRir,
          unit: session.unit,
          increment: incrementFor(e.name, session.unit),
          repMin: info?.repMin ?? lowRepLimit,
          repMax: info?.repMax ?? highRepLimit,
          auto: info?.autoProgression ?? true,
          expectedWorkSets: method == 'Straight'
              ? e.sets.where((s) => isStraightType(s.type)).length
              : e.sets.where((s) => !s.warmup).length,
          loadMode: e.loadMode,
          rirTracked: settings.trackRir,
        );
      }
    }
    var allow = method == 'Straight'
        ? _straightGuidanceAllowed(e) && (rec == null || rec.applyWeight)
        : method != 'Mechanical Drop Set' && (rec == null || rec.applyWeight);
    if (contextError != null) allow = false;

    e.calibrate =
        inBuild &&
        e.loadMode == 'external' &&
        contextError == null &&
        method != 'Mechanical Drop Set' &&
        (method != 'Straight' || _straightGuidanceAllowed(e)) &&
        e.sets.any((s) => calibrationAnchor(method, s.type)) &&
        !_calibrated(cycle, session.templateId, e.name, method);

    var workIndex = 0;
    var firstAnchor = true;
    for (final s in e.sets) {
      if (s.warmup) continue;
      final w = workIndex++;
      final managed = progressionManagedSet(method, s.type);
      if (e.calibrate && managed) {
        if (calibrationAnchor(method, s.type) && firstAnchor) {
          firstAnchor = false;
          s.hintWeight = calibrationFor(e.name, method, session)?.weight ?? s.hintWeight;
        } else {
          s.hintWeight = null;
        }
        continue;
      }
      if (rec != null && allow && managed && s.weight == null) {
        final hint = weightForSet(rec, s.type, w);
        if (hint != null) {
          s
            ..weight = hint
            ..prescribed = true;
        }
      }
      if (rec != null && managed) {
        final goals = rec.setRepTargets;
        s.targetReps = w < goals.length ? goals[w] : rec.targetReps;
      }
    }

    final unit = session.unit;
    e.advice = [
      if (e.loadMode != 'external')
        loadGuidance(e.loadMode)
      else if (method == 'Straight' && !allow)
        'Progress loads manually for this exercise; keep individual planned loads and record actual reps and RIR.',
      if (rec != null && !e.calibrate)
        '${rec.applyWeight ? 'Next load: ${formatNumber(rec.weight, NumKind.weight)} $unit. ' : 'Keep individual loads. '}'
            '${rec.reason}'
            '${rec.setRepTargets.isEmpty ? '' : ' Rep goals: ${rec.setRepTargets.join(' / ')}.'}',
      if (method == 'Mechanical Drop Set')
        'Mechanical drop sets use manual progression. Record each setup/variation; leverage changes cannot be evaluated from load alone.',
      if (methodsWithActivation.contains(method) && e.sets.where((s) => !s.warmup).length == 1)
        'Activation only: no continuation protocol is planned. Progress the load manually.',
    ];
  }

  /// Straight guidance needs one shared load across its straight sets.
  bool _straightGuidanceAllowed(SessionExercise e) {
    if (exercise(e.name)?.autoProgression == false) return false;
    if (contextProblem(e.sets) != null) return false;
    final loads = {
      for (final s in e.sets)
        if (isStraightType(s.type) && (s.weight ?? s.hintWeight ?? 0) > 0) s.weight ?? s.hintWeight,
    };
    return loads.length <= 1;
  }

  /// Method-aware starting load for a first mesocycle session.
  Calibration? calibrationFor(String name, String method, Session session) {
    final info = exercise(name);
    if (info != null && info.loadMode != 'external') return null;
    final starting = _cycleStartingExercise(
      name,
      method,
      session,
    )?.sets.where((s) => calibrationAnchor(method, s.type) && (s.weight ?? 0) > 0).firstOrNull;
    if (starting != null) {
      final reps = method == 'Cluster'
          ? clusterTargetReps
          : method == 'Straight'
          ? info?.repMin ??
                lowRepLimit // bottom of the range, as calibrationRecommendation
          : calibrationTargetReps;
      return Calibration(starting.weight!, reps, session.targetRir, method != 'Cluster');
    }
    SetEntry? latest;
    search:
    for (final s in history) {
      for (final x in s.exercises.where((x) => x.name.toLowerCase() == name.toLowerCase())) {
        for (final set in x.sets.reversed) {
          if (!set.done || (set.weight ?? 0) <= 0 || (set.reps ?? 0) <= 0) continue;
          final sameMethod = x.method == method && calibrationAnchor(method, set.type);
          // Activation/AMRAP methods may inherit a Straight baseline; Cluster never does.
          final straightFallback =
              method != 'Straight' && method != 'Cluster' && x.method == 'Straight' && isStraightType(set.type);
          if (sameMethod || straightFallback) {
            latest = _inUnit(set, s.unit, null, name);
            break search;
          }
        }
      }
    }
    if (latest == null) return null;
    return calibrationRecommendation(
      weight: latest.weight!,
      reps: latest.reps!,
      rir: latest.rir,
      method: method,
      targetRir: session.targetRir,
      unit: session.unit,
      increment: incrementFor(name, session.unit),
      repMin: info?.repMin ?? lowRepLimit,
      repMax: info?.repMax ?? highRepLimit,
    );
  }

  /// Records the calibration set and seeds later segments from it.
  void applyCalibration(SessionExercise ex, int index, double weight, int reps, int? rir) {
    final s = ex.sets[index];
    s
      ..weight = weight
      ..reps = reps
      ..rir = rir
      ..invalid.clear();
    final unit = active?.unit ?? settings.unit;
    var workIndex = 0;
    for (final later in ex.sets.skip(index + 1)) {
      if (later.warmup) continue;
      workIndex++;
      if (later.done || later.context != s.context || !progressionManagedSet(ex.method, later.type)) continue;
      if (later.weight != null) continue;
      later.hintWeight = calibratedFollowupWeight(weight, ex.method, workIndex, unit, incrementFor(ex.name, unit));
    }
    ex
      ..calibrate = false
      ..calibrationEntered = true;
    changed();
  }

  /// Recovery sets from the fixed pre-deload reference, as in the Flet app.
  SessionExercise _deloadExercise(TemplateExercise te, Mesocycle c, Session session) {
    final info = exercise(te.name);
    final loadMode = info?.loadMode ?? defaultLoadModeFor(te.name);
    final warmups = te.sets.where((s) => isWarmup(s.type)).toList();
    final work = te.sets.where((s) => !isWarmup(s.type)).toList();
    if (c.deloadManual) {
      return SessionExercise(
        name: te.name,
        method: te.method,
        loadMode: loadMode,
        sets: [
          for (final ts in te.sets)
            SetEntry(
              type: ts.type,
              rest: ts.rest,
              context: contextFor(te.name, ts),
              targetRir: methodSetUsesRir(te.method, ts.type) ? session.targetRir : null,
            ),
        ],
        advice: ['Manual deload: choose recovery volume, load and effort; automatic progression is paused.'],
      );
    }
    final boundary = addDays(c.start, cycleStatus(c, c.start).buildMicro * c.microDays);
    Session? refSession;
    SessionExercise? ref;
    for (final s in history) {
      if (s.cycleId != c.id || s.templateId != session.templateId || !s.startedAt.isBefore(boundary)) continue;
      if (s.phase == 'Deload') continue;
      final e = s.exercises.where((e) => sameExercise(e.name, te.name) && e.method == te.method).firstOrNull;
      if (e != null) {
        refSession = s;
        ref = e;
        break;
      }
    }
    final count = recoveryCount(te.method, work.length, c.deloadVolumePct);
    final refWork = ref?.work ?? const <SetEntry>[];
    final low = te.method == 'Cluster'
        ? math.min(info?.repMin ?? lowRepLimit, clusterTargetReps)
        : info?.repMin ?? lowRepLimit;
    final eligible =
        loadMode == 'external' &&
        ref?.loadMode == 'external' &&
        te.method != 'Cluster' &&
        te.method != 'Mechanical Drop Set' &&
        !(te.method == 'Straight' && info?.autoProgression == false);
    final step = incrementFor(te.name, session.unit);
    final sets = [for (final ts in warmups) SetEntry(type: 'Warm-up', rest: ts.rest, context: contextFor(te.name, ts))];
    for (var i = 0; i < count; i++) {
      final ts = work[i];
      var r = i < refWork.length ? refWork[i] : null;
      final context = contextFor(te.name, ts);
      if (r != null && (!r.done || r.context != context)) r = null;
      final refWeight = r?.weight == null
          ? null
          : refSession!.unit == session.unit
          ? r!.weight!
          : gymLoad(te.name, convertWeight(r!.weight!, refSession.unit, session.unit), session.unit);
      final refReps = r?.reps;
      final weight = eligible && refWeight != null && refWeight > 0 && (refReps ?? 0) > 0
          ? recoveryWeight(refWeight, c.deloadLoadPct, practicalWeightStep(refWeight, session.unit, step))
          : null;
      sets.add(
        SetEntry(
          type: 'Normal',
          rest: ts.rest,
          context: context,
          targetReps: refReps != null && refReps > 0 ? math.max(1, math.min(low, refReps)) : low,
          targetRir: session.targetRir,
          weight: weight,
          prescribed: weight != null,
        ),
      );
    }
    final first = sets.where((s) => !s.warmup).firstOrNull;
    return SessionExercise(
      name: te.name,
      method: 'Straight',
      loadMode: loadMode,
      sets: sets,
      advice: [
        'Deload week: $count of ${work.length} sets'
            '${first?.weight != null ? ' at ${formatNumber(first!.weight!, NumKind.weight)} ${session.unit} (about ${c.deloadLoadPct}% of your build load)' : ', with a lighter load of your choice'}, '
            'aiming for ${first?.targetReps ?? '?'} reps at ${session.targetRir ?? '?'} RIR. Changes here apply only to this workout.',
      ],
    );
  }
}
