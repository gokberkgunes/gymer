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

  /// Heaviest weight and best e1RM ([setOneRm]) over completed working sets with an external load, logged with
  /// the same [context] (a per-side or per-implement load is never compared with a total); null without such
  /// history (a first session sets no record).
  LiftBest? bestLift(String exercise, [SetContext context = const SetContext()]) {
    _syncHistoryCaches();
    return _bestCache.putIfAbsent((exercise.toLowerCase(), context), () {
      double? weight, e1rm;
      for (final s in history) {
        for (final e in s.exercises) {
          if (e.name.toLowerCase() != exercise.toLowerCase() || e.loadMode != 'external') continue;
          for (final set in e.sets) {
            if (!set.done || set.warmup || set.context != context) continue;
            final x = _inUnit(set, s.unit);
            final one = setOneRm(x.weight, x.reps, x.rir);
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
    final one = setOneRm(s.weight, s.reps, s.rir);
    final best = one == null ? null : bestLift(e.name, s.context);
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
      // Earlier sessions' working sets of this exercise with the same kind of load, in today's unit, each paired
      // with its exercise so volume eligibility can be checked.
      final past = [
        for (final h in earlier)
          for (final x in h.exercises)
            if (x.name.toLowerCase() == key && x.loadMode == e.loadMode)
              (
                x,
                [
                  for (final set in x.sets)
                    if (set.done && !set.warmup && (set.reps ?? 0) > 0) _inUnit(set, h.unit, unit),
                ],
              ),
      ].where((entry) => entry.$2.isNotEmpty).toList();
      double oneRm(SetEntry x) => setOneRm(x.weight, x.reps, x.rir) ?? 0;
      double volume(SessionExercise owner, List<SetEntry> sets) =>
          sets.where((x) => countsAsVolume(owner, x)).fold(0.0, (a, x) => a + setVolume(x));
      String? best;
      double? change;
      if (e.loadMode == 'external') {
        final top = work.reduce((a, b) => (b.weight ?? 0) > (a.weight ?? 0) ? b : a);
        final strongest = work.reduce((a, b) => oneRm(b) > oneRm(a) ? b : a);
        best = '${w(top.weight ?? 0)} × ${top.reps}';
        // Last time's sets logged the same way as today's strongest set (same setup, load basis and side).
        List<SetEntry>? previous({required bool sameWorkout}) {
          for (final h in earlier) {
            if (h.phase == 'Deload' || (sameWorkout && h.templateId != s.templateId)) continue;
            final exercise = h.exercises
                .where((x) => x.name.toLowerCase() == key && x.loadMode == e.loadMode)
                .firstOrNull;
            final sets = exercise?.work
                .where((x) => x.done && (x.reps ?? 0) > 0 && x.context == strongest.context)
                .toList();
            if (sets != null && sets.isNotEmpty) return [for (final set in sets) _inUnit(set, h.unit, unit)];
          }
          return null;
        }

        final last = previous(sameWorkout: true) ?? previous(sameWorkout: false);
        if (last != null && last.isNotEmpty && oneRm(strongest) > 0) {
          change = oneRm(strongest) - last.map(oneRm).reduce(math.max);
        }
        if (past.isNotEmpty && (top.weight ?? 0) > 0) {
          final all = past.expand((entry) => entry.$2);
          // Records compare like with like: a per-side or per-implement load never beats (or blocks) a total.
          final sameAsTop = all.where((x) => x.context == top.context);
          final sameAsStrongest = all.where((x) => x.context == strongest.context);
          if (sameAsTop.isNotEmpty) {
            final heaviest = sameAsTop.map((x) => x.weight ?? 0).reduce(math.max);
            if (top.weight! > heaviest + 1e-9) {
              bests.add(PersonalBest(e.name, 'weight', best, '+${w(top.weight! - heaviest)}'));
            }
          }
          if (sameAsStrongest.isNotEmpty) {
            final bestRm = sameAsStrongest.map(oneRm).reduce(math.max);
            if (oneRm(strongest) > bestRm + 0.05) {
              final rm = oneRm(strongest);
              bests.add(PersonalBest(e.name, 'e1rm', w(AppStore._tenth(rm)), '+${w(AppStore._tenth(rm - bestRm))}'));
            }
          }
          final v = volume(e, work);
          final earlierVolumes = [
            for (final (owner, sets) in past)
              if (volume(owner, sets) case final pastVolume when pastVolume > 0) pastVolume,
          ];
          if (v > 0 && earlierVolumes.isNotEmpty) {
            final bestVolume = earlierVolumes.reduce(math.max);
            if (v > bestVolume + 0.5) {
              bests.add(PersonalBest(e.name, 'volume', total(v), '+${total(v - bestVolume)}'));
            }
          }
        }
      } else {
        final most = work.map((x) => x.reps!).reduce(math.max);
        best = most == 1 ? '1 rep' : '$most reps';
        if (e.loadMode == 'bodyweight' && past.isNotEmpty) {
          final before = past.expand((entry) => entry.$2).map((x) => x.reps!).reduce(math.max);
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
