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

  /// The muscles losing the most, and those gaining the most, each with its volume zone on the tab.
  final List<MuscleVerdict> declining;
  final List<MuscleVerdict> rising;

  const CoachReport({
    required this.cycle,
    required this.planned,
    required this.volume,
    this.performed,
    required this.verdicts,
    required this.suggestions,
    this.deload = const [],
    required this.declining,
    required this.rising,
  });
}

extension AppStoreCoach on AppStore {
  CoachReport coachReport([DateTime? at]) {
    final now = at ?? DateTime.now();
    final active = activeCycle;
    final status = active == null ? null : cycleStatus(active, now);
    final cycle = status == null || status.phase == 'Complete' ? null : active;
    final byId = {for (final t in templates) t.id: t};
    final byVolume = settings.coachCompare == 'volume';

    var verdicts = <String, MuscleVerdict>{};
    var suggestions = <SetSuggestion>[];
    var deload = const <MuscleVerdict>[];
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
      if (status.phase == 'Build' && status.deloadMicro > 0 && cycle.deloadHintDismissed != micro) {
        deload = wholeBodyDecline(finished);
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
      declining: declining.take(2).toList(),
      rising: rising.take(2).toList(),
    );
  }

  /// Stores the change on the cycle: one per muscle per microcycle. Saved workouts stay as they are.
  void applySuggestion(SetSuggestion s) {
    final cycle = activeCycle;
    if (cycle == null || s.applied != null) return;
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
