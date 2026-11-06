/// Workout duration estimate, as storage.estimate_active_workout_seconds.
library;

class TimingBreakdown {
  final int lifting, setup, rest, transitions, session, sets, exercises;
  const TimingBreakdown({
    required this.lifting,
    required this.setup,
    required this.rest,
    required this.transitions,
    required this.session,
    required this.sets,
    required this.exercises,
  });
  int get total => lifting + setup + rest + transitions + session;
}

/// [rows] are the planned entries in order as (exercise, rest after it).
TimingBreakdown estimateWorkout({
  required List<(String, int)> rows,
  required int Function(String exercise) setSeconds,
  required int setOverhead,
  required int transition,
  required int sessionOverhead,
}) {
  var lifting = 0, rest = 0, transitions = 0;
  final names = <String>{};
  for (var i = 0; i < rows.length; i++) {
    final (name, restAfter) = rows[i];
    names.add(name);
    lifting += setSeconds(name);
    if (i == rows.length - 1) continue;
    if (rows[i + 1].$1 == name) {
      rest += restAfter;
    } else {
      transitions += transition;
    }
  }
  return TimingBreakdown(
    lifting: lifting,
    setup: rows.length * setOverhead,
    rest: rest,
    transitions: transitions,
    session: sessionOverhead,
    sets: rows.length,
    exercises: names.length,
  );
}

/// Estimates round up to the next five minutes rather than faking precision.
String formatTargetDuration(int seconds) {
  if (seconds <= 0) return '0 min';
  return '${((seconds + 299) ~/ 300) * 5} min';
}

String compactMinutes(int seconds) {
  final m = seconds ~/ 60, s = seconds % 60;
  return s == 0 ? '${m}m' : '${m}m ${s}s';
}
