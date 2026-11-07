part of '../store.dart';

/// Last-time values, personal bests and finish summaries.
extension AppStoreRecords on AppStore {
  SetEntry _inUnit(SetEntry s, String from, [String? to]) => SetEntry(
    weight: s.weight == null ? null : convertWeight(s.weight!, from, to ?? settings.unit),
    reps: s.reps,
    rir: s.rir,
    done: s.done,
    type: s.type,
    rest: s.rest,
    groupStart: s.groupStart,
    context: s.context,
    stopReason: s.stopReason,
    actualRest: s.actualRest,
    circuitRestAfter: s.circuitRestAfter,
  );

  /// Latest values of [exercise] by set position in sessions of [templateId]
  /// (storage.latest_set_values); deload sessions are skipped.
  List<SetEntry>? _latestSetValues(String exercise, String? templateId, {bool anyWorkout = false}) {
    for (final s in history) {
      if (s.phase == 'Deload') continue;
      if (!anyWorkout && s.templateId != templateId) continue;
      final e = s.exercises.where((e) => e.name.toLowerCase() == exercise.toLowerCase()).firstOrNull;
      if (e == null || !e.sets.any((x) => x.done)) continue;
      return [for (final set in e.sets) _inUnit(set, s.unit)];
    }
    return null;
  }

  void _syncHistoryCaches() {
    final key = (identityHashCode(history), history.length, settings.unit, _historyVersion);
    if (key == _historyCacheKey) return;
    _historyCacheKey = key;
    _previousCache.clear();
    _bestCache.clear();
    _comparisonCache.clear();
  }

  /// What was done last time, set by set: same workout first, else any workout.
  List<SetEntry>? lastTimeSets(String exercise, String? templateId) {
    _syncHistoryCaches();
    return _previousCache.putIfAbsent(
      '${exercise.toLowerCase()}|$templateId',
      () => _latestSetValues(exercise, templateId) ?? _latestSetValues(exercise, null, anyWorkout: true),
    );
  }

  /// A load comparison, never a strength claim. Roles align by working-set position, not warm-up count.
  PlannedLoadIncrease? plannedLoadIncrease(SessionExercise exercise, int index) {
    if (active == null ||
        index < 0 ||
        index >= exercise.sets.length ||
        active?.phase == 'Deload' ||
        !const {'external', 'bodyweight'}.contains(exercise.loadMode)) {
      return null;
    }
    final set = exercise.sets[index];
    final load = set.weight ?? set.hintWeight;
    if (set.done || set.warmup || load == null || !load.isFinite || load <= 0) return null;
    _syncHistoryCaches();
    final previous = _comparisonCache.putIfAbsent(
      (exercise.name.toLowerCase(), exercise.method, exercise.loadMode, active?.templateId, active!.startedAt),
      () {
        List<SetEntry>? fallback;
        final ordered = [...history]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
        for (final session in ordered) {
          if (session.phase == 'Deload' || !session.startedAt.isBefore(active!.startedAt)) continue;
          final past = session.exercises
              .where(
                (e) =>
                    e.name.toLowerCase() == exercise.name.toLowerCase() &&
                    e.method == exercise.method &&
                    e.loadMode == exercise.loadMode &&
                    e.work.any((s) => s.done),
              )
              .firstOrNull;
          if (past == null) continue;
          final sets = [for (final s in past.work) _inUnit(s, session.unit)];
          if (session.templateId == active?.templateId) return sets;
          fallback ??= sets;
        }
        return fallback;
      },
    );
    final position = exercise.sets.take(index).where((s) => !s.warmup).length;
    if (previous == null || position >= previous.length) return null;
    final last = previous[position];
    if (!last.done ||
        last.weight == null ||
        !last.weight!.isFinite ||
        last.weight! < 0 ||
        (exercise.loadMode == 'external' && last.weight == 0) ||
        last.context != set.context ||
        canonicalSetType(last.type) != canonicalSetType(set.type) ||
        last.groupStart != set.groupStart) {
      return null;
    }
    final increase = load - last.weight!;
    return increase > 0.005 ? (load: load, previous: last.weight!, increase: increase) : null;
  }

  /// Heaviest weight and best Wathan e1RM over completed working sets with an
  /// external load; null without such history (a first session sets no record).
  LiftBest? bestLift(String exercise) {
    _syncHistoryCaches();
    return _bestCache.putIfAbsent(exercise.toLowerCase(), () {
      double? weight, e1rm;
      for (final s in history) {
        for (final e in s.exercises) {
          if (e.name.toLowerCase() != exercise.toLowerCase() || e.loadMode != 'external') continue;
          for (final set in e.sets) {
            if (!set.done || set.warmup) continue;
            final x = _inUnit(set, s.unit);
            final one = estimatedOneRm(x.weight ?? 0, x.reps ?? 0, 0);
            if (one == null) continue;
            weight = math.max(weight ?? 0, x.weight!);
            e1rm = math.max(e1rm ?? 0, one);
          }
        }
      }
      return weight == null ? null : (weight: weight, e1rm: e1rm!);
    });
  }

  /// 'weight' or 'e1rm' when this completed set beats every earlier session.
  String? recordKind(SessionExercise e, SetEntry s) {
    if (!s.done || s.warmup || e.loadMode != 'external') return null;
    final one = estimatedOneRm(s.weight ?? 0, s.reps ?? 0, 0);
    final best = one == null ? null : bestLift(e.name);
    if (best == null) return null;
    if (s.weight! > best.weight + 1e-9) return 'weight';
    if (one! > best.e1rm + 0.05) return 'e1rm';
    return null;
  }

  /// Rebuild a saved workout's results from the history that preceded it, in its recorded unit.
  /// Reading a summary never saves, links a calendar day or changes an active workout.
  FinishSummary summarizeSession(Session session, {List<AchievementProgress> achievements = const []}) {
    final earlier = history.where((s) => s.id != session.id && s.startedAt.isBefore(session.startedAt)).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final (bests, results) = _sessionHighlights(session, earlier);
    return FinishSummary(
      name: session.name,
      unit: session.unit,
      date: session.startedAt,
      duration: session.duration,
      sets: session.doneSets,
      volume: session.volume,
      report: sessionVolume(session),
      bests: bests,
      exercises: results,
      achievements: achievements,
    );
  }

  /// A first session of an exercise sets no record: there is nothing to beat.
  (List<PersonalBest>, List<ExerciseResult>) _sessionHighlights(Session s, List<Session> earlier) {
    final unit = s.unit;
    String w(double v) => '${formatNumber(v, NumKind.weight)} $unit';
    String total(double v) => '${groupThousands(v)} $unit';
    final bests = <PersonalBest>[];
    final results = <ExerciseResult>[];
    for (final e in s.exercises) {
      final work = [
        for (final x in e.sets)
          if (x.done && !x.warmup && (x.reps ?? 0) > 0) x,
      ];
      if (work.isEmpty) continue;
      final key = e.name.toLowerCase();
      // Earlier sessions' working sets of this exercise with the same kind of load, in today's unit.
      final past = [
        for (final h in earlier)
          for (final x in h.exercises)
            if (x.name.toLowerCase() == key && x.loadMode == e.loadMode)
              [
                for (final set in x.sets)
                  if (set.done && !set.warmup && (set.reps ?? 0) > 0) _inUnit(set, h.unit, unit),
              ],
      ].where((sets) => sets.isNotEmpty).toList();
      double oneRm(SetEntry x) => estimatedOneRm(x.weight ?? 0, x.reps!, 0) ?? 0;
      double volume(List<SetEntry> sets) => sets.fold(0.0, (a, x) => a + (x.weight ?? 0) * x.reps!);
      String? best;
      double? change;
      if (e.loadMode == 'external') {
        final top = work.reduce((a, b) => (b.weight ?? 0) > (a.weight ?? 0) ? b : a);
        final strongest = work.reduce((a, b) => oneRm(b) > oneRm(a) ? b : a);
        best = '${w(top.weight ?? 0)} × ${top.reps}';
        List<SetEntry>? previous({required bool sameWorkout}) {
          for (final h in earlier) {
            if (h.phase == 'Deload' || (sameWorkout && h.templateId != s.templateId)) continue;
            final exercise = h.exercises
                .where((x) => x.name.toLowerCase() == key && x.loadMode == e.loadMode)
                .firstOrNull;
            final sets = exercise?.work.where((x) => x.done && (x.reps ?? 0) > 0).toList();
            if (sets != null && sets.isNotEmpty) return [for (final set in sets) _inUnit(set, h.unit, unit)];
          }
          return null;
        }

        final last = previous(sameWorkout: true) ?? previous(sameWorkout: false);
        if (last != null && last.isNotEmpty && oneRm(strongest) > 0) {
          change = oneRm(strongest) - last.map(oneRm).reduce(math.max);
        }
        if (past.isNotEmpty && (top.weight ?? 0) > 0) {
          final all = past.expand((x) => x);
          final heaviest = all.map((x) => x.weight ?? 0).reduce(math.max);
          final bestRm = all.map(oneRm).reduce(math.max);
          final bestVolume = past.map(volume).reduce(math.max);
          if (top.weight! > heaviest + 1e-9) {
            bests.add(PersonalBest(e.name, 'weight', best, '+${w(top.weight! - heaviest)}'));
          }
          if (oneRm(strongest) > bestRm + 0.05) {
            final rm = oneRm(strongest);
            bests.add(PersonalBest(e.name, 'e1rm', w(AppStore._tenth(rm)), '+${w(AppStore._tenth(rm - bestRm))}'));
          }
          final v = volume(work);
          if (v > bestVolume + 0.5) {
            bests.add(PersonalBest(e.name, 'volume', total(v), '+${total(v - bestVolume)}'));
          }
        }
      } else {
        final most = work.map((x) => x.reps!).reduce(math.max);
        best = most == 1 ? '1 rep' : '$most reps';
        if (e.loadMode == 'bodyweight' && past.isNotEmpty) {
          final before = past.expand((x) => x).map((x) => x.reps!).reduce(math.max);
          if (most > before) bests.add(PersonalBest(e.name, 'reps', best, '+${most - before}'));
        }
      }
      results.add(ExerciseResult(e.name, work.length, best, change));
    }
    // The whole workout's volume against earlier sessions of the same workout.
    final earlierVolumes = [
      for (final h in earlier)
        if (h.templateId != null && h.templateId == s.templateId && h.phase != 'Deload')
          convertWeight(h.volume, h.unit, unit),
    ];
    if (earlierVolumes.isNotEmpty && s.volume > earlierVolumes.reduce(math.max) + 0.5) {
      bests.add(
        PersonalBest(s.name, 'workout', total(s.volume), '+${total(s.volume - earlierVolumes.reduce(math.max))}'),
      );
    }
    return (bests, results);
  }
}
