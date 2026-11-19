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

  /// The last workout of this exercise and method with a completed working set in a planned
  /// context, preferring the same workout. It is the baseline for progression.
  List<SetEntry>? _latestMethodSession(SessionExercise planned, Session session) {
    final contexts = {for (final set in planned.work) set.context};
    List<SetEntry>? fallback;
    for (final s in history) {
      if (s.phase == 'Deload' || !s.startedAt.isBefore(session.startedAt)) continue;
      final e = s.exercises
          .where((e) => sameExercise(e.name, planned.name) && e.method == planned.method && e.loadMode == 'external')
          .firstOrNull;
      if (e == null ||
          !e.work.any((x) => x.done && (x.weight ?? 0) > 0 && (x.reps ?? 0) > 0 && contexts.contains(x.context))) {
        continue;
      }
      final sets = [for (final x in e.sets) _inUnit(x, s.unit, session.unit)];
      if (s.templateId == session.templateId) return sets;
      fallback ??= sets;
    }
    return fallback;
  }

  /// Last time's reps as a hint, fitted to today's target RIR: never more than that set showed it can do
  /// (a blank RIR counts as done at the target). Without a target or effort scale the observed reps stay.
  int? _repsAtTarget(SetEntry? prev, String method, String type, String loadMode, int? target) {
    if (prev == null || target == null || loadMode != 'external' || !methodSetUsesRir(method, type)) {
      return prev?.reps;
    }
    final oneRm = setOneRm(prev.weight, prev.reps, prev.rir == null || prev.rir! < 0 ? target : prev.rir);
    if (oneRm == null || (prev.weight ?? 0) <= 0) return prev.reps;
    return supportedReps(oneRm, prev.weight!, target) ?? prev.reps;
  }

  /// The planned row's value from the last workout (this workout first), by role and position.
  /// A position skipped there falls back to an older workout as a hint only: progression still
  /// judges the last workout as a whole.
  SetEntry? _lastPlannedSet(TemplateExercise plan, int index, Session current) {
    final templateId = current.templateId;
    final set = plan.sets[index];
    final warmup = isWarmup(set.type);
    final position = plan.sets.take(index).where((s) => isWarmup(s.type) == warmup).length;
    final mode = exercise(plan.name)?.loadMode ?? defaultLoadModeFor(plan.name);
    final context = contextFor(plan.name, set);
    // Prefer this workout throughout its history, then try the same exercise in other workouts.
    for (final sameWorkout in templateId == null ? [false] : [true, false]) {
      for (final session in history) {
        if (session.phase == 'Deload' ||
            !session.startedAt.isBefore(current.startedAt) ||
            (templateId != null && (session.templateId == templateId) != sameWorkout)) {
          continue;
        }
        final previous = session.exercises.where(
          (e) => sameExercise(e.name, plan.name) && e.method == canonicalMethod(plan.method) && e.loadMode == mode,
        );
        for (final exercise in previous) {
          final rows = exercise.sets.where((s) => s.warmup == warmup).toList();
          if (position >= rows.length) continue;
          final candidate = rows[position];
          final weight = candidate.weight;
          // Bodyweight rows may have no load; an external load must be positive.
          if (!candidate.done ||
              (weight != null && (!weight.isFinite || weight < 0)) ||
              (mode == 'external' && (weight ?? 0) <= 0) ||
              (candidate.reps ?? 0) <= 0 ||
              candidate.context != context ||
              canonicalSetType(candidate.type) != canonicalSetType(set.type) ||
              candidate.groupStart != set.groupStart) {
            continue;
          }
          return _inUnit(candidate, session.unit, current.unit, plan.name);
        }
      }
    }
    return null;
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
    // Coaching set changes live on the cycle; the saved workout stays the base plan.
    final plan = t == null || cycle == null ? t : plannedTemplate(cycle, t, micro: status?.currentMicro);
    for (final te in plan?.exercises ?? <TemplateExercise>[]) {
      session.exercises.add(
        status?.phase == 'Deload' ? _deloadExercise(te, cycle!, session) : _buildExercise(te, session, cycle),
      );
    }
    active = session;
    reconcileCircuits(session.circuits, session.exercises.map((e) => e.name));
    if (t != null && session.exercises.any((e) => e.sets.isNotEmpty)) {
      session.estimatedSeconds = sessionTiming(session, plan: plan).total;
    }
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
        if (!sameExercise(past.name, exercise.name) ||
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
      increment: incrementFor(target.name, session.unit) ?? practicalWeightStep(load, session.unit),
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
    final showReps = historicalRepsVisible(session);
    final sets = <SetEntry>[];
    for (final (i, ts) in te.sets.indexed) {
      final context = contextFor(te.name, ts);
      final prev = _lastPlannedSet(te, i, session);
      sets.add(
        SetEntry(
          type: ts.type,
          rest: ts.rest,
          groupStart: ts.groupStart,
          context: context,
          hintWeight: prev?.weight ?? ts.weight ?? (loadMode == 'bodyweight' ? 0 : null),
          hintReps: showReps ? (_repsAtTarget(prev, method, ts.type, loadMode, session.targetRir) ?? ts.reps) : null,
          targetRir: methodSetUsesRir(method, ts.type) ? session.targetRir : null,
        ),
      );
    }
    final e = SessionExercise(name: te.name, method: method, loadMode: loadMode, sets: sets);
    final starting = _cycleStartingExercise(te.name, method, session);
    if (starting != null) {
      for (final (i, set) in e.sets.indexed) {
        if (i < starting.sets.length) set.hintWeight = starting.sets[i].weight ?? set.hintWeight;
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
          s.exercises.any((e) => sameExercise(e.name, name) && e.method == method && e.work.any((set) => set.done)),
    )) {
      return null;
    }
    final starting = cycle.startingLoads[session.templateId]
        ?.where((e) => sameExercise(e.name, name) && e.method == method)
        .firstOrNull;
    final plan = template(session.templateId)?.exercises.where((e) => sameExercise(e.name, name)).firstOrNull;
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
    final starting = e.loadMode == 'external' ? _cycleStartingExercise(e.name, method, session) : null;
    final previous = session.phase != 'Deload' && e.loadMode == 'external' && starting == null
        ? _latestMethodSession(e, session)
        : null;
    Recommendation? rec;
    if (previous != null && (method != 'Straight' || _straightGuidanceAllowed(e))) {
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
        perSet: info?.perSet ?? false,
        expectedWorkSets: method == 'Straight'
            ? e.sets.where((s) => isStraightType(s.type)).length
            : e.sets.where((s) => !s.warmup).length,
        loadMode: e.loadMode,
        rirTracked: settings.trackRir,
        loadAtOrBelow: (target) => loadableAtOrBelow(e.name, target),
      );
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
        // An earlier set (or a cycle starting load) is the baseline; calibrate only without one.
        previous == null &&
        starting == null;

    var workIndex = 0;
    var firstAnchor = true;
    for (final s in e.sets) {
      if (s.warmup) continue;
      final w = workIndex++;
      final managed = progressionManagedSet(method, s.type);
      if (e.calibrate && managed) {
        if (calibrationAnchor(method, s.type) && firstAnchor) {
          firstAnchor = false;
          final calibration = calibrationFor(e.name, method, session, context: s.context);
          s.hintWeight = calibration?.weight ?? s.hintWeight;
          s.targetReps = calibration?.targetReps;
          s.targetRir = calibration?.targetRir ?? s.targetRir;
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
      if (rec != null && allow && managed) {
        final goals = rec.setRepTargets;
        s.targetReps = w < goals.length ? goals[w] : rec.targetReps;
        if (methodSetUsesRir(method, s.type)) s.targetRir = rec.targetRir;
      }
    }

    final unit = session.unit;
    e.advice = [
      if (e.loadMode != 'external')
        loadGuidance(e.loadMode)
      else if (method == 'Straight' && !allow)
        'Progress loads manually for this exercise; keep individual planned loads and record actual reps and RIR.',
      if (rec != null && !e.calibrate)
        '${!rec.applyWeight
                ? 'Keep individual loads. '
                : rec.setWeights.isNotEmpty
                ? 'Next loads: ${rec.setWeights.map((w) => formatNumber(w, NumKind.weight)).join(' / ')} $unit. '
                : 'Next load: ${formatNumber(rec.weight, NumKind.weight)} $unit. '}'
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
    if (exercise(e.name)?.perSet ?? false) return true; // per-set progression expects different loads
    final loads = {
      for (final s in e.sets)
        if (isStraightType(s.type) && (s.weight ?? s.hintWeight ?? 0) > 0) s.weight ?? s.hintWeight,
    };
    return loads.length <= 1;
  }

  /// Method-aware starting load for a first mesocycle session.
  Calibration? calibrationFor(String name, String method, Session session, {SetContext? context}) {
    final info = exercise(name);
    if (info != null && info.loadMode != 'external') return null;
    final starting = _cycleStartingExercise(
      name,
      method,
      session,
    )?.sets.where((s) => calibrationAnchor(method, s.type) && (s.weight ?? 0) > 0).firstOrNull;
    if (starting != null) {
      if (starting.reps != null && starting.rir != null) {
        return calibrationRecommendation(
          weight: starting.weight!,
          reps: starting.reps!,
          rir: starting.rir,
          method: method,
          targetRir: session.targetRir,
          unit: session.unit,
          increment: incrementFor(name, session.unit),
          repMin: info?.repMin ?? lowRepLimit,
          repMax: info?.repMax ?? highRepLimit,
          loadAtOrBelow: (target) => loadableAtOrBelow(name, target),
        );
      }
      final reps = method == 'Cluster'
          ? clusterTargetReps
          : method == 'Straight'
          ? info?.repMin ??
                lowRepLimit // bottom of the range, as calibrationRecommendation
          : calibrationTargetReps
                .clamp(info?.repMin ?? lowRepLimit, math.max(info?.repMin ?? lowRepLimit, info?.repMax ?? highRepLimit))
                .toInt();
      return Calibration(starting.weight!, reps, session.targetRir, method != 'Cluster');
    }
    SetEntry? latest;
    final planned = session.exercises.where((e) => sameExercise(e.name, name)).firstOrNull;
    final expectedContext =
        context ??
        planned?.sets.where((s) => calibrationAnchor(method, s.type)).firstOrNull?.context ??
        info?.context ??
        const SetContext();
    search:
    for (final s in history) {
      // A deload set is light and far from failure: as a baseline it would start the new cycle too light.
      if (s.phase == 'Deload' || !s.startedAt.isBefore(session.startedAt)) continue;
      for (final x in s.exercises.where((x) => sameExercise(x.name, name) && x.loadMode == 'external')) {
        final candidates = x.sets.where((set) {
          if (!set.done ||
              set.context != expectedContext ||
              (set.weight ?? 0) <= 0 ||
              (set.reps ?? 0) <= 0 ||
              (method != 'Cluster' && set.rir == null)) {
            return false;
          }
          final sameMethod = x.method == method && calibrationAnchor(method, set.type);
          // Activation/AMRAP methods may inherit a Straight baseline; Cluster never does.
          final straightFallback =
              method != 'Straight' && method != 'Cluster' && x.method == 'Straight' && isStraightType(set.type);
          return sameMethod || straightFallback;
        }).toList();
        if (candidates.isEmpty) continue;
        // The starting load must support the weakest comparable working set,
        // rather than borrowing extra capacity from a stronger set position.
        final baseline = method == 'Cluster'
            ? candidates.first
            : candidates.reduce(
                (a, b) => setOneRm(a.weight, a.reps, a.rir)! <= setOneRm(b.weight, b.reps, b.rir)! ? a : b,
              );
        latest = _inUnit(baseline, s.unit, session.unit);
        break search;
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
      loadAtOrBelow: (target) => loadableAtOrBelow(name, target),
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
    final info = exercise(ex.name);
    final followup = ex.method == 'Straight'
        ? calibrationRecommendation(
            weight: weight,
            reps: reps,
            rir: rir,
            method: ex.method,
            targetRir: s.targetRir ?? active?.targetRir,
            unit: unit,
            increment: incrementFor(ex.name, unit),
            repMin: info?.repMin ?? lowRepLimit,
            repMax: info?.repMax ?? highRepLimit,
            loadAtOrBelow: (target) => loadableAtOrBelow(ex.name, target),
          )
        : null;
    var workIndex = 0;
    for (final later in ex.sets.skip(index + 1)) {
      if (later.warmup) continue;
      workIndex++;
      if (later.done || later.context != s.context || !progressionManagedSet(ex.method, later.type)) continue;
      if (later.weight != null && !later.prescribed) continue;
      later
        ..weight = null
        ..prescribed = false
        ..hintWeight =
            followup?.weight ??
            calibratedFollowupWeight(weight, ex.method, workIndex, unit, incrementFor(ex.name, unit));
      if (ex.method == 'Straight' && later.reps == null) {
        later
          ..targetReps = followup?.targetReps ?? reps
          ..targetRir = followup?.targetRir ?? s.targetRir ?? active?.targetRir;
      }
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
