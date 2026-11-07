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

  /// Plans follow the new unit: workout templates and the workout in progress, rounded to two decimals with
  /// conversion noise snapped away. Finished workouts keep the unit they were recorded in; every reader converts
  /// with `session.unit`, so history is never rewritten (repeated toggles would otherwise compound rounding).
  void _convertAllWeights(String from, String to) {
    double? c(double? w, String src) =>
        w == null ? null : double.parse(snapWeight(convertWeight(w, src, to)).toStringAsFixed(2));

    void session(Session s) {
      final src = s.unit;
      if (src == to) return;
      for (final e in [...s.exercises, ...s.warmupExercises]) {
        for (final set in e.sets) {
          set
            ..weight = c(set.weight, src)
            ..hintWeight = c(set.hintWeight, src);
        }
      }
      s.unit = to;
      s.bodyweight = c(s.bodyweight, src);
    }

    if (active != null) session(active!);
    for (final t in templates) {
      for (final e in t.exercises) {
        for (final s in e.sets) {
          s.weight = c(s.weight, from);
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
    final key = name.trim().toLowerCase();
    for (final e in exercises) {
      if (e.name.toLowerCase() == key) return e;
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
      if (t.exercises.any((e) => e.name.toLowerCase() == name.toLowerCase())) t.name,
    if (active?.exercises.any((e) => e.name.toLowerCase() == name.toLowerCase()) ?? false) active!.name,
  ];

  bool inHistory(String name) => history.any((s) => s.exercises.any((e) => e.name.toLowerCase() == name.toLowerCase()));

  void deleteExercise(String name) {
    exercises.removeWhere((e) => sameExercise(e.name, name));
    changed();
  }

  /// Saves details; a new name is applied everywhere the exercise appears.
  /// Returns an error message when the new name is taken.
  String? saveExercise(Exercise updated, {String? oldName}) {
    final from = oldName ?? updated.name;
    if (from.toLowerCase() != updated.name.toLowerCase() && exercise(updated.name) != null) {
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
      if (rest?.exercise == from) rest = rest!.copyWith(exercise: updated.name);
      _historyVersion++; // names in history changed in place: cached lookups must be rebuilt
    }
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
    return estimateWorkout(
      rows: [for (final step in steps) (step.exercise.name, step.restAfter)],
      circuitIds: [for (final step in steps) circuitFor(t.circuits, step.exercise.name)?.id],
      setSeconds: (n) => setSecondsFor(n, t.setSeconds),
      setOverhead: t.setOverhead,
      transition: t.transition,
      sessionOverhead: t.sessionOverhead,
    );
  }

  int estimateActiveSeconds() {
    final s = active;
    if (s == null) return 0;
    final t = template(s.templateId) ?? WorkoutTemplate(id: '', name: '', exercises: []);
    final steps = sessionSteps(s);
    return estimateWorkout(
      rows: [for (final step in steps) (step.exercise.name, step.restAfter)],
      circuitIds: [for (final step in steps) circuitFor(s.circuits, step.exercise.name)?.id],
      setSeconds: (n) => setSecondsFor(n, t.setSeconds),
      setOverhead: t.setOverhead,
      transition: t.transition,
      sessionOverhead: t.sessionOverhead,
    ).total;
  }
}
