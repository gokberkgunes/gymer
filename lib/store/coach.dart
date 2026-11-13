part of '../store.dart';

/// What the Coach tab shows: weekly sets, a verdict per muscle, and this period's set changes.
class CoachReport {
  final Mesocycle? cycle;

  /// Whether [volume] is the cycle's plan; otherwise it is what was completed in the last seven days.
  final bool planned;
  final Map<String, WeeklyVolume> volume;
  final Map<String, MuscleVerdict> verdicts;
  final List<SetSuggestion> suggestions;

  /// The muscles losing the most strength, shown when there is nothing to change.
  final List<MuscleVerdict> declining;

  const CoachReport({
    required this.cycle,
    required this.planned,
    required this.volume,
    required this.verdicts,
    required this.suggestions,
    required this.declining,
  });
}

extension AppStoreCoach on AppStore {
  CoachReport coachReport([DateTime? at]) {
    final now = at ?? DateTime.now();
    final active = activeCycle;
    final status = active == null ? null : cycleStatus(active, now);
    final cycle = status == null || status.phase == 'Complete' ? null : active;
    final byId = {for (final t in templates) t.id: t};

    var verdicts = <String, MuscleVerdict>{};
    var suggestions = <SetSuggestion>[];
    final Map<String, WeeklyVolume> volume;
    if (cycle != null && status!.running) {
      volume = plannedWeeklyVolume(cycle, byId, musclesOf);
      final sessions = _cycleSessions(
        cycle,
      ).where((s) => (s.phase ?? cycleStatus(cycle, s.startedAt).phase) == 'Build').toList();
      final periods = CoachPeriods(dateOnly(cycle.start), math.max(1, cycle.microDays));
      Map<String, MuscleVerdict> of(int micro) => muscleVerdicts(sessions, periods, micro - 1, musclesOf);
      final micro = status.currentMicro;
      verdicts = of(micro);
      final finished = of(micro - 1);
      if (verdicts.isEmpty) verdicts = finished;
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
          missedWorkout: calendarDays(
            cycle,
            history,
          ).any((d) => d.micro == micro - 1 && d.templateId != null && (d.status == 'missed' || d.status == 'planned')),
        );
      }
    } else {
      final sessions = history.where((s) => s.phase != 'Deload' && s.doneSets > 0).toList();
      final week = CoachPeriods.weeks.indexOf(now);
      verdicts = muscleVerdicts(sessions, CoachPeriods.weeks, week, musclesOf);
      if (verdicts.isEmpty) verdicts = muscleVerdicts(sessions, CoachPeriods.weeks, week - 1, musclesOf);
      volume = cycle != null
          ? plannedWeeklyVolume(cycle, byId, musclesOf)
          : performedVolume(history.where((s) => daysBetween(s.startedAt, now) < 7), musclesOf);
    }
    final declining = verdicts.values.where((v) => v.trend == Trend.falling).toList()
      ..sort((a, b) => a.percent.compareTo(b.percent));
    return CoachReport(
      cycle: cycle,
      planned: cycle != null,
      volume: volume,
      verdicts: verdicts,
      suggestions: suggestions,
      declining: declining.take(2).toList(),
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

  void undoSuggestion(SetSuggestion s) {
    if (activeCycle?.setAdjustments.remove(s.applied) ?? false) changed();
  }
}
