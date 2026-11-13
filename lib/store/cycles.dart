part of '../store.dart';

/// Mesocycles: status, review, cloning and starting loads.
extension AppStoreCycles on AppStore {
  Mesocycle? get activeCycle => cycles.where((c) => c.active && c.setupComplete).firstOrNull;

  /// The running cycle and its status on [at], if any.
  (Mesocycle, CycleStatus)? cycleContext([DateTime? at]) {
    final c = activeCycle;
    if (c == null) return null;
    final st = cycleStatus(c, at);
    return st.running ? (c, st) : null;
  }

  /// Saving or continuing a cycle makes it the single active one.
  void saveCycle(Mesocycle c) {
    if (!cycles.any((x) => x.id == c.id)) cycles = [...cycles, c];
    for (final x in cycles) {
      if (x.active && x.id != c.id) x.endedAt ??= dateOnly(DateTime.now());
      x.active = x.id == c.id;
    }
    c.endedAt = null;
    changed();
  }

  /// A new cycle is provisional until Start is pressed with a scheduled day.
  Mesocycle? get pendingCycle => cycles.where((c) => !c.setupComplete).firstOrNull;

  void beginCycleSetup(Mesocycle c) {
    cycles.removeWhere((x) => !x.setupComplete);
    c
      ..setupComplete = false
      ..active = false;
    cycles = [...cycles, c];
    changed();
  }

  /// Returns an error when no workout day is assigned yet.
  String? startPendingCycle() {
    final c = pendingCycle;
    if (c == null) return null;
    if (c.schedule.values.every((id) => template(id) == null)) {
      return 'Assign at least one workout day before starting the mesocycle.';
    }
    c.setupComplete = true;
    saveCycle(c);
    return null;
  }

  /// Leaving setup before Start cancels the new cycle. Returns true if one was dropped.
  bool cancelPendingCycle() {
    final had = pendingCycle != null;
    if (had) {
      cycles.removeWhere((c) => !c.setupComplete);
      changed();
    }
    return had;
  }

  void endCycle(Mesocycle c) {
    c
      ..active = false
      ..endedAt = dateOnly(DateTime.now());
    changed();
  }

  List<Session> _cycleSessions(Mesocycle cycle) {
    final linked = {for (final event in cycle.events.values) ?event.sessionId};
    return history.where((s) => (s.cycleId == cycle.id || linked.contains(s.id)) && s.doneSets > 0).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }

  CycleSummary summarizeCycle(Mesocycle cycle, {DateTime? at}) {
    final sessions = _cycleSessions(cycle);
    final status = cycleStatus(cycle);
    final today = dateOnly(at ?? DateTime.now());
    var end = cycle.endedAt ?? status.end;
    if (end.isAfter(status.end)) end = status.end;
    if (end.isAfter(today)) end = today;
    final due = calendarDays(cycle, history)
        .where(
          // A day whose workout was deleted could never be attended; it only counts if it was done before.
          (d) =>
              d.templateId != null &&
              !d.unplanned &&
              !d.date.isAfter(end) &&
              (d.sessionId != null || template(d.templateId) != null),
        )
        .toList();
    final completed = {for (final s in sessions) s.id};
    final attended = {
      for (final d in due)
        if (completed.contains(d.sessionId)) d.sessionId,
    };
    final bests = <(String, String), PersonalBest>{};
    var records = 0;
    for (final session in sessions) {
      for (final best in summarizeSession(session).bests) {
        records++;
        bests[(best.exercise.toLowerCase(), best.kind)] = best;
      }
    }
    return CycleSummary(
      unit: settings.unit,
      start: dateOnly(cycle.start),
      end: end.isBefore(cycle.start) ? dateOnly(cycle.start) : end,
      workouts: sessions.length,
      attended: attended.length,
      scheduled: due.length,
      sets: sessions.fold(0, (n, s) => n + s.doneSets),
      records: records,
      duration: sessions.fold(Duration.zero, (total, s) => total + s.duration),
      bests: bests.values.toList(),
      strength: cycleStrengthChanges(cycle, sessions, settings.unit),
    );
  }

  /// A detached draft: no shared maps, calendar events, template changes or activation until Start.
  Mesocycle cloneCycle(Mesocycle source, {DateTime? start, int loadPercent = 100}) {
    final json = source.toJson();
    final match = RegExp(r'^(.*) · (\d+)$').firstMatch(source.name);
    json
      ..['id'] = 'C${DateTime.now().microsecondsSinceEpoch}'
      ..['name'] = match == null ? '${source.name} · 2' : '${match.group(1)} · ${int.parse(match.group(2)!) + 1}'
      ..['start'] = dateKey(start ?? DateTime.now())
      ..['active'] = false
      ..['setupComplete'] = false
      ..['events'] = <String, dynamic>{}
      ..remove('endedAt')
      ..remove('setAdjustments')
      ..remove('startingLoads');
    final draft = Mesocycle.fromJson(json);
    draft.schedule.removeWhere((_, id) => template(id) == null);
    draft
      ..startingLoadUnit = settings.unit
      ..startingLoads = cycleStartingLoads(source, loadPercent: loadPercent);
    return draft;
  }

  /// Last compatible build loads of this cycle; absent loads stay unknown and are never guessed.
  Map<String, List<SessionExercise>> cycleStartingLoads(
    Mesocycle source, {
    int loadPercent = 100,
    Iterable<String>? templateIds,
  }) {
    if (loadPercent <= 0 || loadPercent > 200) throw ArgumentError.value(loadPercent, 'loadPercent');
    final sessions = _cycleSessions(source).reversed
        .where((s) => s.phase == 'Build' || (s.phase == null && cycleStatus(source, s.startedAt).phase == 'Build'))
        .toList(); // a list, not a lazy filter: it is walked once per planned exercise
    double? scaled(String name, double? weight) {
      if (weight == null || weight <= 0) return null;
      return loadableAtOrBelow(name, weight * loadPercent / 100);
    }

    final result = <String, List<SessionExercise>>{};
    for (final id in (templateIds ?? source.schedule.values).toSet()) {
      final plan = template(id);
      if (plan == null) continue;
      final exercises = <SessionExercise>[];
      for (final planned in plan.exercises) {
        final mode = exercise(planned.name)?.loadMode ?? defaultLoadModeFor(planned.name);
        final method = canonicalMethod(planned.method);
        if (mode != 'external' || method == 'Mechanical Drop Set') continue;
        SessionExercise? reference;
        String? unit;
        for (final session in sessions.where((s) => s.templateId == id)) {
          reference = session.exercises
              .where(
                (e) =>
                    sameExercise(e.name, planned.name) &&
                    e.method == method &&
                    e.loadMode == mode &&
                    e.sets.length == planned.sets.length &&
                    planned.sets.indexed.every((entry) {
                      final previous = e.sets[entry.$1];
                      final set = entry.$2;
                      return canonicalSetType(previous.type) == canonicalSetType(set.type) &&
                          previous.groupStart == set.groupStart &&
                          previous.context == contextFor(planned.name, set);
                    }) &&
                    e.work.any((s) => s.done && (s.weight ?? 0) > 0),
              )
              .firstOrNull;
          if (reference != null) {
            unit = session.unit;
            break;
          }
        }
        final sets = <SetEntry>[];
        for (final (i, set) in planned.sets.indexed) {
          final context = contextFor(planned.name, set);
          final previous = reference != null && i < reference.sets.length ? reference.sets[i] : null;
          final compatible =
              previous != null &&
              previous.done &&
              previous.context == context &&
              canonicalSetType(previous.type) == canonicalSetType(set.type) &&
              previous.groupStart == set.groupStart;
          final weight = compatible
              ? (unit == settings.unit
                    ? previous.weight ?? 0
                    : gymLoad(planned.name, convertWeight(previous.weight ?? 0, unit!, settings.unit), settings.unit))
              : reference == null
              ? set.weight
              : null;
          sets.add(
            SetEntry(
              type: set.type,
              groupStart: set.groupStart,
              rest: set.rest,
              context: context,
              weight: isWarmup(set.type) ? null : scaled(planned.name, weight),
            ),
          );
        }
        if (sets.any((s) => s.weight != null)) {
          exercises.add(SessionExercise(name: planned.name, method: method, loadMode: mode, sets: sets));
        }
      }
      if (exercises.isNotEmpty) result[id] = exercises;
    }
    return result;
  }

  void deleteCycle(Mesocycle c) {
    cycles.removeWhere((x) => x.id == c.id);
    changed();
  }

  /// Adds microcycles to the build phase of [c] (before its deload).
  void extendCycle(Mesocycle c, int microcycles) {
    if (microcycles <= 0) return;
    final build = c.length - c.deloadMicro;
    c
      ..weekRir = {for (final e in c.weekRir.entries) (e.key > build ? e.key + microcycles : e.key): e.value}
      ..length += microcycles;
    changed();
  }

  /// A reusable demo: three workouts on days 1, 3 and 5, started last week.
  Mesocycle openDemoCycle() {
    final today = dateOnly(DateTime.now());
    final lastMonday = addDays(today, -(today.weekday - 1) - 7);
    final existing = cycles.where((c) => c.name == 'Demo cycle').firstOrNull;
    if (existing != null) {
      // The button must always show something: an ended demo starts over when no other cycle is running.
      if (!existing.active && activeCycle == null) {
        existing
          ..start = lastMonday
          ..events.clear();
        saveCycle(existing);
      }
      return existing;
    }
    var n = 0;
    String make(String name, List<(String, int)> lifts) {
      // Reuse the demo workouts if they are still there, instead of filling Train with duplicates.
      final kept = templates.where((t) => t.name == name).firstOrNull;
      if (kept != null) return kept.id;
      final t = WorkoutTemplate(
        id: 'W${DateTime.now().microsecondsSinceEpoch}${n++}',
        name: name,
        exercises: [
          for (final (lift, reps) in lifts)
            TemplateExercise(
              name: addExercise(lift).name,
              sets: [for (var i = 0; i < 3; i++) TemplateSet(reps: reps, rest: settings.defaultRest)],
            ),
        ],
      );
      templates = [...templates, t];
      return t.id;
    }

    final push = make('Demo Push', [('Bench Press', 8), ('Shoulder Press', 10), ('Triceps Pushdown', 12)]);
    final pull = make('Demo Pull', [('Lat Pulldown', 10), ('Machine Row', 10), ('Biceps Curl', 12)]);
    final legs = make('Demo Legs', [('Squat', 8), ('Romanian Deadlift', 10), ('Leg Curl', 12)]);
    final c = Mesocycle(
      id: 'C${DateTime.now().microsecondsSinceEpoch}',
      name: 'Demo cycle',
      start: lastMonday,
      active: activeCycle == null,
      schedule: {1: push, 3: pull, 5: legs},
    );
    cycles = [...cycles, c];
    changed();
    return c;
  }
}
