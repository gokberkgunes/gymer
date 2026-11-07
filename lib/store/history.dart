part of '../store.dart';

/// Saved workouts, calendar logging and read-only queries.
extension AppStoreHistory on AppStore {
  void saveHistorySession(Session edited) {
    final i = history.indexWhere((s) => s.id == edited.id);
    if (i >= 0) {
      history[i] = edited;
    } else {
      history = [edited, ...history];
    }
    history.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _historyVersion++;
    changed();
  }

  void deleteSession(String id) {
    history.removeWhere((s) => s.id == id);
    _historyVersion++;
    for (final c in cycles) {
      c.events.removeWhere((_, e) => e.sessionId == id && e.status == 'unplanned');
      for (final e in c.events.values) {
        if (e.sessionId == id) e.sessionId = null;
      }
    }
    changed();
  }

  /// A blank record of [templateId]'s plan for logging a past calendar day.
  Session draftPastSession(String templateId, DateTime date) {
    final t = template(templateId)!;
    return Session(
      id: 'S${DateTime.now().microsecondsSinceEpoch}',
      templateId: t.id,
      name: t.name,
      unit: settings.unit,
      startedAt: DateTime(date.year, date.month, date.day, 12),
      bodyweight: bodyweightAt(date, settings.unit),
      circuits: copyCircuits(t.circuits),
      exercises: [
        for (final te in t.exercises)
          SessionExercise(
            name: te.name,
            method: te.method,
            loadMode: exercise(te.name)?.loadMode ?? 'external',
            sets: [
              for (final ts in te.sets)
                SetEntry(type: ts.type, rest: ts.rest, groupStart: ts.groupStart, context: contextFor(te.name, ts)),
            ],
          ),
      ],
    );
  }

  /// Saves a calendar-logged past workout and links it to its planned day.
  void saveCalendarSession(Mesocycle c, String plannedKey, Session s, {bool unplanned = false}) {
    final st = cycleStatus(c, s.startedAt);
    s
      ..cycleId = c.id
      ..microcycle = st.running ? st.currentMicro : null
      ..phase = st.running ? st.phase : null
      ..targetRir = st.running ? st.suggestedRir : null
      ..finishedAt = s.startedAt;
    final previous = c.events[plannedKey];
    c.events[plannedKey] = DayEvent(
      templateId: s.templateId!,
      status: unplanned ? 'unplanned' : 'planned',
      movedTo: previous?.movedTo,
      sessionId: s.id,
    );
    saveHistorySession(s);
  }

  /// Links an already-recorded session to a planned day. Returns an error.
  String? linkRecordedSession(Mesocycle c, String plannedKey, String templateId, String sessionId) {
    if (c.events.entries.any((e) => e.key != plannedKey && e.value.sessionId == sessionId)) {
      return 'This workout is already linked to another day.';
    }
    final previous = c.events[plannedKey];
    c.events[plannedKey] = DayEvent(templateId: templateId, movedTo: previous?.movedTo, sessionId: sessionId);
    changed();
    return null;
  }

  List<SetEntry> previousSets(String exercise, [String? templateId]) =>
      _latestSetValues(exercise, templateId, anyWorkout: templateId == null) ?? const [];

  List<ExercisePoint> progress(String exercise) {
    final points = <ExercisePoint>[];
    final combined = usesBodyweightProgress(exercise);
    for (final s in history.reversed) {
      SetEntry? best;
      double bestValue = 0;
      for (final e in s.exercises.where(
        (e) =>
            e.name == exercise &&
            (combined
                ? e.loadMode == (this.exercise(exercise)?.loadMode ?? defaultLoadModeFor(exercise))
                : e.loadMode == 'external'),
      )) {
        for (final set in e.sets) {
          final v = (combined ? combinedBodyweightLoad(s, e, set) : set.e1rm) ?? 0;
          if (v > bestValue) {
            bestValue = v;
            best = set;
          }
        }
      }
      if (best != null) {
        points.add(ExercisePoint(s.startedAt, convertWeight(bestValue, s.unit, settings.unit), _inUnit(best, s.unit)));
      }
    }
    return points..sort((a, b) => a.date.compareTo(b.date));
  }

  bool usesBodyweightProgress(String name) =>
      settings.trackBodyweight &&
      const {'bodyweight', 'assisted'}.contains(exercise(name)?.loadMode ?? defaultLoadModeFor(name));

  Set<String> performedExercises() => {
    for (final s in history)
      for (final e in s.exercises)
        if (e.sets.any((x) => x.done)) e.name,
  };

  /// Seed for the rep-max calculator: latest completed straight set.
  (double?, int?, String) repMaxSeed(String name) {
    final info = exercise(name);
    if (info != null && info.loadMode != 'external') {
      return (null, null, 'Bodyweight and assisted loads do not establish a total RM.');
    }
    final live = active?.exercises.where((x) => x.name == name).firstOrNull;
    for (final set in [...?live?.sets].reversed) {
      if (!set.done || !isStraightType(set.type) || (set.weight ?? 0) <= 0 || (set.reps ?? 0) <= 0) continue;
      return _seedFrom(set.weight!, set.reps!, set.rir, active!.unit);
    }
    for (final s in history) {
      for (final x in s.exercises.where((x) => x.name == name)) {
        for (final set in x.sets.reversed) {
          if (!set.done || !isStraightType(set.type) || (set.weight ?? 0) <= 0 || (set.reps ?? 0) <= 0) continue;
          if (x.loadMode != 'external') {
            return (null, null, 'The latest set uses bodyweight or assistance; enter an external-load RM manually.');
          }
          return _seedFrom(convertWeight(set.weight!, s.unit, settings.unit), set.reps!, set.rir, settings.unit);
        }
      }
    }
    return (null, null, 'No completed straight set is available yet. Enter a set you know.');
  }

  (double?, int?, String) _seedFrom(double weight, int reps, int? rir, String unit) {
    final w = snapWeight(weight);
    if (rir == null) return (w, null, 'Actual RIR is unknown; enter a known repetition maximum manually.');
    final note =
        'Using your latest straight set: ${formatNumber(w, NumKind.weight)} $unit × $reps${rir > 0 ? ' @ $rir RIR' : ''}.';
    // Same RIR cap as every other estimate (setOneRm).
    final rm = reps + rir.clamp(0, maxCountedRir);
    return (w, rm >= 1 ? rm : null, note);
  }
}
