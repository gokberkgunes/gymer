part of '../store.dart';

/// Finishing or discarding a workout, and volume reports.
extension AppStoreFinishing on AppStore {
  /// Set order violation when "require previous set" is on.
  String? setOrderViolation() {
    if (!settings.requirePreviousSet) return null;
    final session = active;
    if (session != null) {
      final steps = sessionSteps(session);
      for (final circuit in session.circuits) {
        final group = steps.where((step) => step.circuit == circuit).toList();
        final open = group.indexWhere((step) => !step.set.done);
        if (open >= 0 && group.skip(open).any((step) => step.set.done)) {
          final next = group[open];
          return 'Complete ${next.exercise.name} set ${next.index + 1} before saving later sets.';
        }
      }
    }
    for (final e in active?.exercises ?? <SessionExercise>[]) {
      final sets = active!.visibleSetsFor(e);
      final firstOpen = sets.indexWhere((s) => !s.done);
      if (firstOpen >= 0 && sets.skip(firstOpen).any((s) => s.done)) {
        return '${e.name}: complete set ${firstOpen + 1} before saving later sets.';
      }
    }
    return null;
  }

  /// The program structure differs from the saved workout.
  bool templateChanged() {
    final s = active;
    final saved = template(s?.templateId);
    if (s == null || saved == null || s.phase == 'Deload') return false;
    // Sets the coach added or removed for this cycle are the plan, not a change to ask about.
    final cycle = cycles.where((c) => c.id == s.cycleId).firstOrNull;
    final t = cycle == null ? saved : plannedTemplate(cycle, saved, micro: s.microcycle);
    String sig(Iterable<(String, String, int, String, bool)> rows) =>
        rows.map((r) => '${r.$1.toLowerCase()}|${r.$2}|${r.$3}|${canonicalSetType(r.$4)}|${r.$5}').join(';');
    final a = [
      for (final e in s.exercises)
        for (final set in e.sets) (e.name, e.method, set.rest, set.type, set.groupStart),
    ];
    final b = [
      for (final e in t.exercises)
        for (final set in e.sets) (e.name, canonicalMethod(e.method), set.rest, set.type, set.groupStart),
    ];
    return sig(a) != sig(b) ||
        jsonEncode(s.circuits.map((c) => c.toJson()).toList()) !=
            jsonEncode(t.circuits.map((c) => c.toJson()).toList());
  }

  /// Saves the workout; returns null when nothing was completed.
  FinishSummary? finishSession({bool saveStructure = false}) {
    final s = active;
    if (s == null || s.doneAll == 0) return null;
    final t = template(s.templateId);
    if (t != null && s.phase != 'Deload') {
      if (saveStructure) {
        _saveStructure(s, t);
        // The saved workout now holds these sets itself; keep the records so the week's change is not repeated.
        for (final a in cycles.where((c) => c.id == s.cycleId).expand((c) => c.setAdjustments)) {
          if (a.templateId == t.id && a.micro <= (s.microcycle ?? a.micro)) a.delta = 0;
        }
      }
      _updateTemplateDefaults(s, t);
    }
    if (s.clockRunning) {
      s
        ..clockElapsed = s.clockSeconds
        ..clockRunningSince = null;
    }
    s.finishedAt = DateTime.now();
    for (final e in s.exercises) {
      for (final set in e.sets) {
        if (!methodSetUsesRir(e.method, set.type)) set.rir = null;
        set.invalid.clear();
      }
    }
    // Records compare against earlier sessions, so collect them first.
    final alreadyEarned = {
      for (final p in achievementProgress(history, cycles: cycles))
        if (p.earned) p.achievement.id,
    };
    // Linked to its planned day first, so a mesocycle achievement sees this workout as done.
    final c = cycles.where((c) => c.id == s.cycleId).firstOrNull ?? activeCycle;
    if (c != null) linkSession(c, s);
    final earned = achievementProgress([...history, s], cycles: cycles).where((p) => p.earned).toList();
    final unlocked = [
      for (final p in earned)
        if (!alreadyEarned.contains(p.achievement.id) && !_seenAchievements.contains(p.achievement.id)) p,
    ];
    _seenAchievements.addAll(earned.map((p) => p.achievement.id));
    final summary = summarizeSession(s, achievements: unlocked);
    history = [s, ...history];
    snapshot();
    active = null;
    rest = null;
    _syncAlerts();
    changed();
    return summary;
  }

  /// Persist the session's exercise/set/rest/type structure, not performance.
  void _saveStructure(Session s, WorkoutTemplate t) {
    t.circuits = copyCircuits(s.circuits);
    final old = {for (final e in t.exercises) e.name.toLowerCase(): e};
    t.exercises = [
      for (final e in s.exercises)
        TemplateExercise(
          name: e.name,
          method: e.method,
          sets: [
            for (final (i, set) in e.sets.indexed)
              () {
                final prev = old[e.name.toLowerCase()];
                final keep = prev != null && i < prev.sets.length ? prev.sets[i] : null;
                return TemplateSet(
                  type: canonicalSetType(set.type),
                  rest: set.rest,
                  groupStart: set.groupStart,
                  weight: keep?.weight,
                  reps: keep?.reps,
                  context: keep?.context,
                );
              }(),
          ],
        ),
    ];
  }

  /// Completed weights/reps become the template's per-set defaults.
  void _updateTemplateDefaults(Session s, WorkoutTemplate t) {
    for (final e in s.exercises) {
      final te = t.exercises.where((x) => sameExercise(x.name, e.name)).firstOrNull;
      if (te == null || e.loadMode != (exercise(e.name)?.loadMode ?? e.loadMode)) continue;
      for (final (i, set) in e.sets.indexed) {
        if (!set.done || i >= te.sets.length) continue;
        if (set.context != contextFor(e.name, te.sets[i])) continue;
        te.sets[i]
          ..weight = set.weight
          ..reps = set.reps;
      }
    }
  }

  void discardSession() {
    active = null;
    rest = null;
    _syncAlerts();
    changed();
  }

  (List<String>, List<String>) musclesOf(String name) {
    final e = exercise(name);
    return (e?.primary ?? const [], e?.secondary ?? const []);
  }

  /// Weekly sets per muscle while [draft] is being edited, for the workout editor. When the draft is on the
  /// active (or pending) cycle's schedule, it replaces the saved workout there and [before] is the saved plan.
  /// Otherwise the draft is counted as if added once a week ([hypothetical]) on top of any cycle's plan.
  ({Map<String, double> after, Map<String, double> before, bool hypothetical}) editorWeeklySets(WorkoutTemplate draft) {
    final cycle = activeCycle ?? pendingCycle;
    final saved = {for (final t in templates) t.id: t};
    Map<String, double> sets(Mesocycle c, Map<String, WorkoutTemplate> byId) => {
      for (final MapEntry(key: m, value: v) in plannedWeeklyVolume(c, byId, musclesOf).entries)
        m: v.countedSets(includePartialSets: settings.includePartialSets),
    };
    final before = cycle == null ? <String, double>{} : sets(cycle, saved);
    if (cycle != null && cycle.schedule.containsValue(draft.id)) {
      return (after: sets(cycle, {...saved, draft.id: draft}), before: before, hypothetical: false);
    }
    final once = sets(Mesocycle(id: '', start: DateTime(2000), schedule: {1: draft.id}), {draft.id: draft});
    return (
      after: {
        for (final m in {...before.keys, ...once.keys}) m: (before[m] ?? 0) + (once[m] ?? 0),
      },
      before: before,
      hypothetical: true,
    );
  }

  VolumeReport sessionVolume(Session s, {bool planned = false}) {
    final rows = <VolumeRow>[];
    for (final (i, e) in s.exercises.indexed) {
      final (p, sec) = musclesOf(e.name);
      for (final set in e.sets) {
        rows.add(
          VolumeRow(
            scope: '$i',
            type: set.type,
            active: planned || set.done,
            groupStart: set.groupStart,
            primary: p,
            secondary: sec,
          ),
        );
      }
    }
    return summarizeVolume(rows);
  }

  VolumeReport templateVolume(WorkoutTemplate t) {
    final rows = <VolumeRow>[];
    for (final (i, e) in t.exercises.indexed) {
      final (p, sec) = musclesOf(e.name);
      for (final set in e.sets) {
        rows.add(
          VolumeRow(scope: '$i', type: set.type, active: true, groupStart: set.groupStart, primary: p, secondary: sec),
        );
      }
    }
    return summarizeVolume(rows);
  }
}
