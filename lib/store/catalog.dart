part of '../store.dart';

/// Settings changes, bodyweight, the exercise catalog, plates and workout templates.
extension AppStoreCatalog on AppStore {
  void updateSettings(void Function(Settings s) edit) {
    final before = settings.unit;
    final trackedBodyweight = settings.trackBodyweight;
    edit(settings);
    if (settings.unit != before) _convertAllWeights(before, settings.unit);
    if (!trackedBodyweight && settings.trackBodyweight && active?.bodyweight == null) _refreshActiveBodyweight();
    _syncAlerts();
    changed();
  }

  /// Plans follow the new unit: workout templates and the workout in progress. Each load becomes the nearest one
  /// the exercise can be loaded with in the new unit ([gymLoad]), so 75 kg becomes 165 lb rather than 165.35.
  /// Bodyweight keeps one decimal. Finished workouts keep the unit they were recorded in; every reader converts
  /// with `session.unit`, so history is never rewritten (repeated toggles would otherwise compound rounding).
  void _convertAllWeights(String from, String to) {
    double? c(double? w, String src, String name) =>
        w == null || src == to ? w : gymLoad(name, convertWeight(w, src, to), to);

    void session(Session s) {
      final src = s.unit;
      if (src == to) return;
      for (final e in [...s.exercises, ...s.warmupExercises]) {
        for (final set in e.sets) {
          set
            ..weight = c(set.weight, src, e.name)
            ..hintWeight = c(set.hintWeight, src, e.name);
        }
      }
      s.unit = to;
      final bodyweight = s.bodyweight;
      s.bodyweight = bodyweight == null ? null : (convertWeight(bodyweight, src, to) * 10).roundToDouble() / 10;
    }

    if (active != null) session(active!);
    for (final t in templates) {
      for (final e in t.exercises) {
        for (final s in e.sets) {
          s.weight = c(s.weight, from, e.name);
        }
      }
    }
  }

  double? bodyweightAt(DateTime day, String unit) {
    if (!settings.trackBodyweight) return null;
    final available = bodyweights.where((e) => !e.date.isAfter(dateOnly(day))).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return available.firstOrNull?.inUnit(unit);
  }

  String? logBodyweight(DateTime day, double value) {
    if (!settings.trackBodyweight) return 'Enable bodyweight tracking in Settings first.';
    if (!value.isFinite || value <= 0) return 'Enter a bodyweight greater than zero.';
    if (dateOnly(day).isAfter(dateOnly(DateTime.now()))) return 'Choose today or an earlier date.';
    final entry = BodyweightEntry(day, convertWeight(value, settings.unit, 'kg'));
    bodyweights = [...bodyweights.where((e) => dateKey(e.date) != dateKey(day)), entry]
      ..sort((a, b) => a.date.compareTo(b.date));
    _refreshActiveBodyweight();
    changed();
    return null;
  }

  void removeBodyweight(DateTime day) {
    bodyweights.removeWhere((e) => dateKey(e.date) == dateKey(day));
    _refreshActiveBodyweight();
    changed();
  }

  void _refreshActiveBodyweight() {
    final session = active;
    if (session != null && settings.trackBodyweight) session.bodyweight = bodyweightAt(session.startedAt, session.unit);
  }

  Exercise? exercise(String name) {
    // Names match with sameExercise everywhere (case and surrounding spaces ignored), never with a bare ==.
    for (final e in exercises) {
      if (sameExercise(e.name, name)) return e;
    }
    return null;
  }

  Exercise addExercise(String name) {
    final existing = exercise(name);
    if (existing != null) return existing;
    final e = Exercise(name: name.trim(), loadMode: defaultLoadModeFor(name));
    exercises = [...exercises, e]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    changed();
    return e;
  }

  void toggleExerciseFavourite(String name) {
    final current = exercise(name);
    if (current == null) return;
    exercises = [for (final e in exercises) e == current ? e.copyWith(favourite: !e.favourite) : e];
    changed();
  }

  /// Recently performed exercises, newest session first, without duplicates.
  List<String> recentExercises() {
    final sessions = [...history]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final seen = <String>{};
    return [
      for (final session in sessions)
        for (final e in session.exercises)
          if (e.sets.any((s) => s.done) && exercise(e.name) != null && seen.add(e.name.toLowerCase())) e.name,
    ];
  }

  /// Names of saved workouts that use [name]; such an exercise cannot be deleted.
  List<String> workoutsUsing(String name) => [
    for (final t in templates)
      if (t.exercises.any((e) => sameExercise(e.name, name))) t.name,
    if (active?.exercises.any((e) => sameExercise(e.name, name)) ?? false) active!.name,
  ];

  bool inHistory(String name) => history.any((s) => s.exercises.any((e) => sameExercise(e.name, name)));

  void deleteExercise(String name) {
    exercises.removeWhere((e) => sameExercise(e.name, name));
    changed();
  }

  /// Saves details; a new name is applied everywhere the exercise appears.
  /// Returns an error message when the new name is taken.
  String? saveExercise(Exercise updated, {String? oldName}) {
    final from = oldName ?? updated.name;
    if (!sameExercise(from, updated.name) && exercise(updated.name) != null) {
      return 'An exercise with that name already exists.';
    }
    final previous = exercise(from);
    exercises = [for (final x in exercises) sameExercise(x.name, from) ? updated : x]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (from != updated.name) {
      for (final t in templates) {
        renameCircuitExercise(t.circuits, from, updated.name);
        for (final e in t.exercises) {
          if (sameExercise(e.name, from)) e.name = updated.name;
        }
      }
      for (final s in [...history, ?active]) {
        renameCircuitExercise(s.circuits, from, updated.name);
        if (s.warmupExercise != null && sameExercise(s.warmupExercise!, from)) s.warmupExercise = updated.name;
        for (final e in [...s.exercises, ...s.warmupExercises]) {
          if (sameExercise(e.name, from)) e.name = updated.name;
        }
      }
      // Everything that stores an exercise by name must follow a rename: cycle starting loads match by name too.
      for (final c in cycles) {
        for (final plan in c.startingLoads.values) {
          for (final e in plan) {
            if (sameExercise(e.name, from)) e.name = updated.name;
          }
        }
      }
      if (rest != null && sameExercise(rest!.exercise, from)) rest = rest!.copyWith(exercise: updated.name);
      _historyVersion++; // names in history changed in place: cached lookups must be rebuilt
    }
    _historyVersion++; // increments and equipment feed gymLoad, which cached last-time values were rounded with
    // A new default context clears inherited template defaults that no longer match.
    if (previous != null && previous.context != updated.context) {
      for (final t in templates) {
        for (final e in t.exercises.where((e) => sameExercise(e.name, updated.name))) {
          for (final s in e.sets.where((s) => s.context == null)) {
            s
              ..weight = null
              ..reps = null;
          }
        }
      }
    }
    changed();
    return null;
  }

  /// Configured jump for this exercise in [unit]: per-exercise, then equipment.
  double? incrementFor(String name, String unit) {
    final e = exercise(name);
    final own = unit == 'lb' ? e?.incrementLb : e?.incrementKg;
    if (own != null) return own;
    final eq = settings.increments[e?.equipment ?? ''];
    return eq == null ? null : (unit == 'lb' ? eq.$2 : eq.$1);
  }

  /// The load nearest [weight] that [name] can be loaded with in [unit]: the active plate inventory for plate
  /// exercises (when [unit] is the settings unit), otherwise a multiple of the exercise's increment. Used when a
  /// load changes unit, so a converted weight is always one the gym can make, written without float noise.
  double gymLoad(String name, double weight, String unit) {
    if (!weight.isFinite || weight <= 0) return weight;
    if (unit == settings.unit && platesApply(name)) {
      final plan = plates(weight, name: name);
      final options = [?plan.exact?.total, ?plan.below?.total, ?plan.above?.total];
      if (options.isNotEmpty) {
        final nearest = options.reduce((a, b) => (b - weight).abs() < (a - weight).abs() ? b : a);
        return double.parse(nearest.toStringAsFixed(2));
      }
    }
    final step = incrementFor(name, unit) ?? practicalWeightStep(weight, unit);
    return double.parse(math.max(step, (weight / step).round() * step).toStringAsFixed(2));
  }

  /// Whether [name] is loaded with plates (barbell or plate-loaded), so the plate calculator applies.
  bool platesApply(String name) => usesPlates(exercise(name)?.equipment ?? '');

  /// Plates for [target] on [name]'s bar: its own bar weight, else none for plate-loaded machines (the
  /// sled is usually not counted) and the default bar for barbells.
  PlatePlan plates(double target, {String? name}) {
    final unit = settings.unit;
    final e = name == null ? null : exercise(name);
    final own = unit == 'lb' ? e?.barLb : e?.barKg;
    final bar = own ?? (e?.equipment == 'Plate loaded' ? 0.0 : settings.bar);
    final pairs = settings.platePairs;
    // The inline bar asks on every rebuild; plans are pure, so remember the latest few.
    final key =
        '$target|$bar|${settings.plates.join(',')}|${pairs?.entries.map((e) => '${e.key}x${e.value}').join(',')}';
    final cached = _planCache.remove(key);
    final plan = cached ?? planPlates(target, bar, settings.plates, pairs: pairs);
    _planCache[key] = plan; // re-insert: most recently used last
    if (_planCache.length > 64) _planCache.remove(_planCache.keys.first);
    return plan;
  }

  /// The heaviest load at or below [target] that [name] can actually be loaded with: the plate inventory for
  /// plate exercises (never below the bar), otherwise the exercise's increment. Used for starting loads and
  /// Rep Max targets so a suggested load is one the user can put on.
  double loadableAtOrBelow(String name, double target) {
    if (platesApply(name)) {
      final plan = plates(target, name: name);
      return plan.exact?.total ?? plan.below?.total ?? plan.above?.total ?? target;
    }
    final step = incrementFor(name, settings.unit) ?? practicalWeightStep(target, settings.unit, null);
    return snapWeight(math.max(step, (target / step + 1e-9).floor() * step));
  }

  void addSetType(String name) {
    final n = name.trim();
    if (n.isEmpty || settings.setTypes.any((t) => t.toLowerCase() == n.toLowerCase())) return;
    settings.setTypes.add(n);
    changed();
  }

  void removeSetType(String name) {
    settings.setTypes.remove(name);
    changed();
  }

  WorkoutTemplate newTemplate() =>
      WorkoutTemplate(id: 'W${DateTime.now().microsecondsSinceEpoch}', name: '', exercises: []);

  /// An unsaved copy of [t] under a new id, named after it with " copy" added; it is added only when its editor saves it.
  WorkoutTemplate duplicateTemplate(WorkoutTemplate t) =>
      WorkoutTemplate.fromJson({...t.toJson(), 'id': newTemplate().id, 'name': t.name.isEmpty ? '' : '${t.name} copy'});

  WorkoutTemplate? template(String? id) => templates.where((t) => t.id == id).firstOrNull;

  void saveTemplate(WorkoutTemplate t) {
    final i = templates.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      templates[i] = t;
    } else {
      templates = [...templates, t];
    }
    if (active?.templateId == t.id) _applyTemplateToActive(t);
    changed();
  }

  /// Running or upcoming cycles that schedule this workout, for the warning before deleting it.
  List<Mesocycle> cyclesScheduling(String templateId) => [
    for (final c in cycles)
      if ((c.active || !c.setupComplete) && c.schedule.containsValue(templateId)) c,
  ];

  /// The cycle keeps the deleted workout's days and shows them as missing (a red "?") until another workout
  /// is chosen: silently turning them into rest days would hide a hole in the plan. Readers of a schedule
  /// must therefore expect an id with no workout behind it ([template] returns null).
  void deleteTemplate(String id) {
    templates.removeWhere((t) => t.id == id);
    changed();
  }

  SetContext contextFor(String exerciseName, TemplateSet? planned) =>
      planned?.context ?? exercise(exerciseName)?.context ?? const SetContext();

  int setSecondsFor(String exerciseName, int fallback) => exercise(exerciseName)?.setSeconds ?? fallback;

  TimingBreakdown templateTiming(WorkoutTemplate t) {
    final steps = workoutSteps([
      for (final e in t.exercises)
        SessionExercise(
          name: e.name,
          method: e.method,
          sets: [for (final s in e.sets) SetEntry(type: s.type, rest: s.rest, groupStart: s.groupStart)],
        ),
    ], t.circuits);
    return _stepsTiming(t, steps, t.circuits);
  }

  /// Today's plan, including automatic deload volume, without starting or saving a workout.
  TimingBreakdown plannedTiming(WorkoutTemplate t, {DateTime? at}) {
    final ctx = cycleContext(at);
    if (ctx == null || ctx.$2.phase != 'Deload') return templateTiming(t);
    final preview = Session(
      id: '',
      templateId: t.id,
      name: t.name,
      unit: settings.unit,
      startedAt: at ?? DateTime.now(),
      phase: 'Deload',
      targetRir: ctx.$2.suggestedRir,
      exercises: [],
      circuits: copyCircuits(t.circuits),
    );
    preview.exercises = [for (final e in t.exercises) _deloadExercise(e, ctx.$1, preview)];
    reconcileCircuits(preview.circuits, preview.exercises.map((e) => e.name));
    return sessionTiming(preview, plan: t);
  }

  TimingBreakdown sessionTiming(Session s, {WorkoutTemplate? plan}) => _stepsTiming(
    plan ?? template(s.templateId) ?? WorkoutTemplate(id: '', name: '', exercises: []),
    sessionSteps(s),
    s.circuits,
  );

  TimingBreakdown _stepsTiming(WorkoutTemplate t, List<WorkoutStep> steps, List<ExerciseCircuit> circuits) =>
      estimateWorkout(
        rows: [for (final step in steps) (step.exercise.name, step.restAfter)],
        circuitIds: [for (final step in steps) circuitFor(circuits, step.exercise.name)?.id],
        setSeconds: (n) => setSecondsFor(n, t.setSeconds),
        setOverhead: t.setOverhead,
        transition: t.transition,
        sessionOverhead: t.sessionOverhead,
      );

  int estimateActiveSeconds() => active == null ? 0 : sessionTiming(active!).total;
}
