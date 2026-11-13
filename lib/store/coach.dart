part of '../store.dart';

/// What the Coach tab shows: weekly sets, a verdict per muscle, and this period's set changes.
class CoachReport {
  final Mesocycle? cycle;

  /// Whether [volume] is the cycle's plan; otherwise it is the weekly average completed in the last four weeks.
  final bool planned;
  final Map<String, WeeklyVolume> volume;

  /// Sets completed so far in the running microcycle, per seven days like the plan; null outside a cycle.
  final Map<String, WeeklyVolume>? performed;
  final Map<String, MuscleVerdict> verdicts;
  final List<SetSuggestion> suggestions;

  /// Set when most judged muscles fell last period: the muscles behind an early deload, worst first. New set
  /// changes are held back while it shows.
  final List<MuscleVerdict> deload;

  /// The finished period's total hard sets were the most of any week so far.
  final bool deloadAtHigh;

  /// The muscles losing the most, and those gaining the most, each with its volume zone on the tab.
  final List<MuscleVerdict> declining;
  final List<MuscleVerdict> rising;

  /// Each muscle's own range from earlier mesocycles, drawn under the bar once two of them have data.
  final Map<String, PersonalRange> personal;

  /// The arrows compare the first weeks of this mesocycle with the last build week of the one before, across
  /// its deload: whether strength came back.
  final bool sincePrevious;

  /// The latest pump and recovery answers per muscle, in words, for the details dialog.
  final Map<String, String> feel;

  /// Applied set changes of this mesocycle per muscle, each with what the muscle did the week after.
  final Map<String, List<String>> changeLog;

  /// Sleep and overall answers of the last ten workouts that had either, oldest first.
  final List<({DateTime date, int? sleep, int? overall})> dayAnswers;

  const CoachReport({
    required this.cycle,
    required this.planned,
    required this.volume,
    this.performed,
    required this.verdicts,
    required this.suggestions,
    this.deload = const [],
    this.deloadAtHigh = false,
    required this.declining,
    required this.rising,
    this.personal = const {},
    this.sincePrevious = false,
    this.feel = const {},
    this.changeLog = const {},
    this.dayAnswers = const [],
  });
}

extension AppStoreCoach on AppStore {
  CoachReport coachReport([DateTime? at]) {
    useSensitivity(settings.coachSensitivity);
    final now = at ?? DateTime.now();
    final active = activeCycle;
    final status = active == null ? null : cycleStatus(active, now);
    final cycle = status == null || status.phase == 'Complete' ? null : active;
    final byId = {for (final t in templates) t.id: t};
    final byVolume = settings.coachCompare == 'volume';

    final personal = personalRanges([
      for (final c in cycles)
        if (c.setupComplete && c != cycle) cycleResponses(c),
    ]);

    var verdicts = <String, MuscleVerdict>{};
    var suggestions = <SetSuggestion>[];
    var deload = const <MuscleVerdict>[];
    var deloadAtHigh = false;
    var sincePrevious = false;
    final changeLog = <String, List<String>>{};
    Map<String, WeeklyVolume>? performed;
    final Map<String, WeeklyVolume> volume;
    if (cycle != null && status!.running) {
      volume = plannedWeeklyVolume(cycle, byId, musclesOf);
      final sessions = _cycleSessions(
        cycle,
      ).where((s) => (s.phase ?? cycleStatus(cycle, s.startedAt).phase) == 'Build').toList();
      final periods = CoachPeriods(dateOnly(cycle.start), math.max(1, cycle.microDays));
      Map<String, MuscleVerdict> of(int micro) =>
          muscleVerdicts(sessions, periods, micro - 1, musclesOf, byVolume: byVolume);
      final micro = status.currentMicro;
      // Every workout of the running microcycle counts here, deload ones included: this is what was done.
      performed = performedVolume(
        _cycleSessions(cycle).where((s) => periods.indexOf(s.startedAt) == micro - 1),
        musclesOf,
        weeks: periods.days / 7,
      );
      verdicts = of(micro);
      final finished = of(micro - 1);
      if (verdicts.isEmpty) verdicts = finished;
      if (verdicts.isEmpty) {
        // Nothing to compare inside this cycle yet: look back across the deload to the last build week of the
        // mesocycle before, to see whether strength came back.
        final earlier = cycles.where((c) => c != cycle && c.setupComplete && c.start.isBefore(cycle.start)).toList()
          ..sort((a, b) => b.start.compareTo(a.start));
        final last = earlier.firstOrNull;
        if (last != null) {
          final old = _cycleSessions(
            last,
          ).where((s) => (s.phase ?? cycleStatus(last, s.startedAt).phase) == 'Build').toList();
          final oldPeriods = CoachPeriods(dateOnly(last.start), math.max(1, last.microDays));
          final lastWeek = old.isEmpty ? null : old.map((s) => oldPeriods.indexOf(s.startedAt)).reduce(math.max);
          verdicts = muscleVerdictsBetween(
            sessions,
            old.where((s) => oldPeriods.indexOf(s.startedAt) == lastWeek),
            musclesOf,
            byVolume: byVolume,
            maxGapDays: 42,
          );
          sincePrevious = verdicts.isNotEmpty;
        }
      }
      for (final a in cycle.setAdjustments.where((a) => a.delta != 0)) {
        final after = a.micro + 1 <= micro ? of(a.micro + 1)[a.muscle]?.trend.name : null;
        changeLog
            .putIfAbsent(a.muscle, () => [])
            .add(
              '${a.micro == 0 ? 'Start' : '${cycle.periodShort}${a.micro}'}: ${a.delta > 0 ? '+' : '−'}${a.delta.abs()} set '
              '${a.exercise}, ${after == null ? 'not judged yet' : '$after the ${cycle.periodNoun()} after'}',
            );
      }
      if (status.phase == 'Build' && status.deloadMicro > 0 && cycle.deloadHintDismissed != micro) {
        // Every hard set of the finished period, per seven days, against all weeks before it.
        final own = _cycleSessions(cycle).where((s) => periods.indexOf(s.startedAt) == micro - 2).toList();
        final periodStart = addDays(periods.start, (micro - 2) * periods.days);
        deloadAtHigh = isPersonalHighWeek(
          own.fold(0, (n, s) => n + s.doneSets) * 7 / periods.days,
          history.where((s) => s.startedAt.isBefore(periodStart)),
        );
        deload = wholeBodyDecline(finished, atPersonalHigh: deloadAtHigh);
      }
      if (status.phase == 'Build') {
        suggestions = coachSuggestions(
          cycle: cycle,
          micro: micro,
          templates: byId,
          musclesOf: musclesOf,
          verdicts: finished,
          previous: of(micro - 2),
          weeklySets: {
            for (final e in volume.entries) e.key: e.value.countedSets(includePartialSets: settings.includePartialSets),
          },
          keepMev: settings.coachKeepMev,
          experience: settings.experience,
          personal: personal,
          before: of(micro - 3),
          recovery: recoveryOf(sessions.where((s) => periods.indexOf(s.startedAt) == micro - 2)),
          missedWorkout: calendarDays(
            cycle,
            history,
          ).any((d) => d.micro == micro - 1 && d.templateId != null && (d.status == 'missed' || d.status == 'planned')),
        );
      }
    } else {
      final sessions = history.where((s) => s.phase != 'Deload' && s.doneSets > 0).toList();
      final week = CoachPeriods.weeks.indexOf(now);
      verdicts = muscleVerdicts(sessions, CoachPeriods.weeks, week, musclesOf, byVolume: byVolume);
      if (verdicts.isEmpty) {
        verdicts = muscleVerdicts(sessions, CoachPeriods.weeks, week - 1, musclesOf, byVolume: byVolume);
      }
      volume = cycle != null
          ? plannedWeeklyVolume(cycle, byId, musclesOf)
          : performedVolume(history.where((s) => daysBetween(s.startedAt, now) < 28), musclesOf, weeks: 4);
    }
    final declining = verdicts.values.where((v) => v.trend == Trend.falling).toList()
      ..sort((a, b) => a.percent.compareTo(b.percent));
    final rising = verdicts.values.where((v) => v.trend == Trend.progressing).toList()
      ..sort((a, b) => b.percent.compareTo(a.percent));
    return CoachReport(
      cycle: cycle,
      planned: cycle != null,
      volume: volume,
      performed: performed,
      verdicts: verdicts,
      // A deload answers whole-body fatigue; set-by-set changes wait until it is taken or dismissed.
      suggestions: deload.isEmpty ? suggestions : suggestions.where((s) => s.applied != null).toList(),
      deload: deload,
      deloadAtHigh: deloadAtHigh && deload.isNotEmpty,
      declining: declining.take(2).toList(),
      rising: rising.take(2).toList(),
      personal: personal,
      sincePrevious: sincePrevious,
      changeLog: changeLog,
      feel: _latestFeel(now),
      dayAnswers: [
        for (final s in history.where((s) => s.checkIn?.sleep != null || s.checkIn?.overall != null).take(10))
          (date: s.startedAt, sleep: s.checkIn!.sleep, overall: s.checkIn!.overall),
      ].reversed.toList(),
    );
  }

  /// The newest pump and recovery answer per muscle from the last three weeks.
  Map<String, String> _latestFeel(DateTime now) {
    const pump = ['low', 'good', 'great'], recovered = ['still sore', 'in time', 'days ago'];
    final words = <String, List<String>>{};
    final seenPump = <String>{}, seenRecovered = <String>{};
    for (final s in history) {
      final c = s.checkIn;
      if (c == null || daysBetween(s.startedAt, now) > 21) continue;
      for (final e in c.pump.entries) {
        if (seenPump.add(e.key)) words.putIfAbsent(e.key, () => []).add('pump ${pump[e.value]}');
      }
      for (final e in c.recovered.entries) {
        if (seenRecovered.add(e.key)) words.putIfAbsent(e.key, () => []).add('recovered ${recovered[e.value]}');
      }
    }
    return {for (final e in words.entries) e.key: e.value.join(', ')};
  }

  /// Direct sets per muscle inside this one workout, special methods as equivalents: what a single session
  /// asks of each muscle, for the editor's ceiling mark ([sessionSetCeiling]).
  Map<String, double> sessionSets(WorkoutTemplate template) => {
    for (final e in plannedWeeklyVolume(Mesocycle(id: '', start: DateTime(2024), schedule: {1: template.id}), {
      template.id: template,
    }, musclesOf).entries)
      if (e.value.direct.sets > 0) e.key: e.value.direct.sets,
  };

  /// Latest sessions of [exercise] in a row without a gain in estimated 1RM; [stallSessions] or more is a stall.
  int stalledSessions(String exercise) => sessionsWithoutGain([for (final p in progress(exercise)) p.value]);

  /// Net coach change to the working sets of [template] in the running mesocycle, for the Train card.
  int coachSetDelta(WorkoutTemplate template) =>
      activeCycle?.setAdjustments.where((a) => a.templateId == template.id).fold<int>(0, (n, a) => n + a.delta) ?? 0;

  /// How each muscle answered the build weeks of [cycle], in landmark order.
  Map<String, MuscleResponse> cycleResponses(Mesocycle cycle) {
    useSensitivity(settings.coachSensitivity);
    final status = cycleStatus(cycle, cycle.start);
    final sessions = _cycleSessions(
      cycle,
    ).where((s) => (s.phase ?? cycleStatus(cycle, s.startedAt).phase) == 'Build').toList();
    if (sessions.isEmpty) return const {};
    final response = cycleResponse(
      sessions,
      CoachPeriods(dateOnly(cycle.start), math.max(1, cycle.microDays)),
      status.buildMicro,
      musclesOf,
      byVolume: settings.coachCompare == 'volume',
      includePartialSets: settings.includePartialSets,
    );
    final order = [...rpLandmarks.keys, ...response.keys.where((m) => !rpLandmarks.containsKey(m))];
    return {for (final m in order) m: ?response[m]};
  }

  /// Starting volumes for [draft], the next cycle after [source]: one set fewer where a muscle ended [source]
  /// falling, one more where it never left holding. Same limits as weekly suggestions; maintained muscles and
  /// exercises already changed are left alone. Stored as adjustments of microcycle 0.
  List<SetAdjustment> startingVolumes(Mesocycle source, Mesocycle draft) {
    final byId = {for (final t in templates) t.id: t};
    final plan = Mesocycle.fromJson(draft.toJson())..setAdjustments = [];
    final weekly = plannedWeeklyVolume(plan, byId, musclesOf);
    final taken = <(String, String)>{};
    for (final r in cycleResponses(source).values) {
      final delta = r.nextStart;
      if (delta == 0 || plan.muscleGoals[r.muscle] == 'maintain' || (delta > 0 && plan.diet == 'cut')) continue;
      final landmark = rpLandmarks[r.muscle];
      final sets = weekly[r.muscle]?.countedSets(includePartialSets: settings.includePartialSets) ?? 0;
      final floor =
          (settings.coachKeepMev ? landmark?.mevRange?.$1 : null) ?? Landmark.range(landmark?.mv ?? '')?.$1 ?? 0;
      final top = addCeiling(r.muscle, settings.experience, null);
      if (delta < 0 ? sets - 1 < floor : top != null && sets + 1 > top) continue;
      final target = adjustmentTarget(plan, byId, musclesOf, r.muscle, delta, null);
      if (target == null || !taken.add((target.$1, target.$2.toLowerCase()))) continue;
      plan.setAdjustments.add(
        SetAdjustment(muscle: r.muscle, templateId: target.$1, exercise: target.$2, delta: delta, micro: 0),
      );
    }
    return plan.setAdjustments;
  }

  /// Stores the change on the cycle: one per muscle per microcycle. Saved workouts stay as they are.
  void applySuggestion(SetSuggestion s) {
    final cycle = activeCycle;
    if (cycle == null || s.applied != null || s.delta == 0) return;
    final micro = cycleStatus(cycle).currentMicro;
    if (cycle.setAdjustments.any((a) => a.micro == micro && a.muscle == s.muscle)) return;
    cycle.setAdjustments.add(
      SetAdjustment(muscle: s.muscle, templateId: s.templateId, exercise: s.exercise, delta: s.delta, micro: micro),
    );
    changed();
  }

  /// Starts the deload in the running microcycle: the build phase ends with the last finished one and the
  /// mesocycle becomes that much shorter. Weekly RIR overrides of dropped build weeks go; deload ones move up.
  void startDeloadNow() {
    final cycle = activeCycle;
    if (cycle == null) return;
    final status = cycleStatus(cycle);
    if (status.phase != 'Build' || status.deloadMicro == 0 || status.currentMicro < 2) return;
    final build = status.currentMicro - 1, dropped = status.buildMicro - build;
    cycle
      ..weekRir = {
        for (final e in cycle.weekRir.entries)
          if (e.key <= build) e.key: e.value else if (e.key > status.buildMicro) e.key - dropped: e.value,
      }
      ..length = build + status.deloadMicro
      ..deloadMicro = status.deloadMicro;
    changed();
  }

  /// Tells the coach how to treat [muscle] in the running cycle: 'maintain', 'priority', or anything else to grow.
  void setMuscleGoal(String muscle, String goal) {
    final cycle = activeCycle;
    if (cycle == null) return;
    if (goal == 'maintain' || goal == 'priority') {
      cycle.muscleGoals[muscle] = goal;
    } else {
      cycle.muscleGoals.remove(muscle);
    }
    changed();
  }

  /// Tells the coach the eating phase of the running cycle: 'maintain', 'cut', or anything else for gaining.
  void setDiet(String diet) {
    final cycle = activeCycle;
    if (cycle == null) return;
    cycle.diet = diet == 'maintain' || diet == 'cut' ? diet : '';
    cycleEdited(cycle); // a cut plans no ramp
  }

  void dismissDeloadHint() {
    final cycle = activeCycle;
    if (cycle == null) return;
    cycle.deloadHintDismissed = cycleStatus(cycle).currentMicro;
    changed();
  }

  /// Saves answers of the finish screen's recovery check-in on the finished workout.
  void editCheckIn(String sessionId, void Function(CheckIn checkIn) edit) {
    final session = history.where((s) => s.id == sessionId).firstOrNull;
    if (session == null) return;
    edit(session.checkIn ??= CheckIn());
    changed();
  }

  void undoSuggestion(SetSuggestion s) {
    if (activeCycle?.setAdjustments.remove(s.applied) ?? false) changed();
  }
}
