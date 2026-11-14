part of '../store.dart';

class ExercisePoint {
  final DateTime date;
  final double value;
  final SetEntry best;
  const ExercisePoint(this.date, this.value, this.best);
}

/// Platform side effects the store triggers; a no-op in tests.
abstract class Alerts {
  void keepAwake(bool on) {}
  void scheduleRest(DateTime at, String exercise) {}
  void cancelRest() {}

  /// Live rest countdown outside the app (status bar / notification shade).
  void showLiveRest(
    DateTime endsAt,
    String exercise, {
    required bool endAtZero,
    String icon = 'muscle',
    String overtimeIcon = 'warning',
    String chipText = '',
    bool vibrate = false,
  }) {}
  void clearLiveRest() {}

  /// The plan for the coming days as JSON, for the Android home-screen widget.
  void todayWidget(String plan) {}

  /// Whether the app is on screen; the live timer is only shown outside the app.
  void setForeground(bool foreground) {}

  /// Foreground rest-over haptic feedback.
  void restDone({required bool haptics}) {}
  void setDone() {}
}

class NoAlerts extends Alerts {}

/// Outcome of trying to complete a set.
class CompleteResult {
  final bool ok;
  final String? message;
  const CompleteResult.done() : ok = true, message = null;
  const CompleteResult.blocked([this.message]) : ok = false;
}

/// One personal best set in a finished workout, e.g. Bench Press · Heaviest weight · 105 kg × 8 (+5 kg).
class PersonalBest {
  final String exercise;

  /// 'weight', 'e1rm', 'volume', 'reps' or 'workout' (the whole workout's volume).
  final String kind;
  final String value;

  /// Improvement over the previous best, e.g. "+5 kg".
  final String gain;
  const PersonalBest(this.exercise, this.kind, this.value, this.gain);

  String get label => switch (kind) {
    'weight' => 'Heaviest weight',
    'e1rm' => 'Estimated 1RM',
    'volume' => 'Exercise volume',
    'reps' => 'Most reps',
    _ => 'Workout volume',
  };
}

/// How one exercise went: completed working sets, its best set, and the change in estimated 1RM since the
/// last time it was trained (null when there is nothing to compare).
class ExerciseResult {
  final String name;
  final int sets;
  final String? best;
  final double? change;
  const ExerciseResult(this.name, this.sets, this.best, this.change);
}

class FinishSummary {
  /// The saved session this summarises, for the recovery check-in.
  final String? sessionId;
  final String name;
  final String unit;
  final DateTime date;
  final Duration duration;

  /// Completed working sets (warm-ups excluded) and their total load × reps.
  final int sets;
  final double volume;
  final VolumeReport report;
  final List<PersonalBest> bests;
  final List<ExerciseResult> exercises;
  final List<AchievementProgress> achievements;
  const FinishSummary({
    this.sessionId,
    required this.name,
    required this.unit,
    required this.date,
    required this.duration,
    required this.sets,
    required this.volume,
    required this.report,
    this.bests = const [],
    this.exercises = const [],
    this.achievements = const [],
  });
}

class CycleSummary {
  final String unit;
  final DateTime start, end;
  final int workouts, attended, scheduled, sets, records;
  final Duration duration;
  final List<PersonalBest> bests;
  final List<CycleStrengthChange> strength;

  /// Per muscle: average weekly sets, strength change and where to start next cycle.
  final List<MuscleResponse> response;

  /// Candidates to change before the next cycle: muscles whose average weekly sets sat under MEV, muscles at
  /// or above the MRV range, and scheduled exercises that have stalled.
  final List<String> underMev, atMrv, stalled;
  const CycleSummary({
    required this.unit,
    required this.start,
    required this.end,
    required this.workouts,
    required this.attended,
    required this.scheduled,
    required this.sets,
    required this.records,
    required this.duration,
    required this.bests,
    required this.strength,
    this.response = const [],
    this.underMev = const [],
    this.atMrv = const [],
    this.stalled = const [],
  });
}

/// Best completed working set of an exercise in history, in the current unit.
typedef LiftBest = ({double weight, double e1rm});
typedef PlannedLoadIncrease = ({double load, double previous, double increase});

/// One automatic backup: when it was taken and what it holds (-1 when the file cannot be read).
typedef BackupInfo = ({DateTime at, File file, int sessions, int workouts});
