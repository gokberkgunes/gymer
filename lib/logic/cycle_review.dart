import '../models.dart';
import 'methods.dart';
import 'progression.dart';

class CycleStrengthChange {
  final String name;
  final double first, last;
  const CycleStrengthChange(this.name, this.first, this.last);
  double get change => last - first;
  double get percent => change / first * 100;
}

/// Compare the first and last build sessions with the same method and logging context.
/// Deloads, warm-ups, unfinished sets and non-external loads cannot establish strength changes.
List<CycleStrengthChange> cycleStrengthChanges(Mesocycle cycle, List<Session> sessions, String unit) {
  final points = <(String, String, SetContext), List<({String id, String name, DateTime date, double value})>>{};
  for (final session in sessions) {
    final deload =
        session.phase == 'Deload' ||
        (session.phase == null &&
            daysBetween(cycle.start, session.startedAt) >= (cycle.length - cycle.deloadMicro) * cycle.microDays);
    if (deload) continue;
    final bests = <(String, String, SetContext), ({String name, double value})>{};
    for (final exercise in session.exercises) {
      if (exercise.loadMode != 'external' || exercise.method != 'Straight') continue;
      for (final set in exercise.work) {
        if (!set.done || !isStraightType(set.type) || (set.weight ?? 0) <= 0 || (set.reps ?? 0) <= 0) continue;
        final value = estimatedOneRm(convertWeight(set.weight!, session.unit, unit), set.reps!, 0)!;
        final key = (exercise.name.toLowerCase(), exercise.method, set.context);
        if (value > (bests[key]?.value ?? 0)) bests[key] = (name: exercise.name, value: value);
      }
    }
    for (final entry in bests.entries) {
      points.putIfAbsent(entry.key, () => []).add((
        id: session.id,
        name: entry.value.name,
        date: session.startedAt,
        value: entry.value.value,
      ));
    }
  }
  final changes = <String, ({DateTime date, CycleStrengthChange change})>{};
  for (final entries in points.values) {
    entries.sort((a, b) => a.date.compareTo(b.date));
    if (entries.length < 2 || entries.first.id == entries.last.id) continue;
    final last = entries.last;
    final key = last.name.toLowerCase();
    final existing = changes[key];
    if (existing == null || last.date.isAfter(existing.date)) {
      changes[key] = (date: last.date, change: CycleStrengthChange(last.name, entries.first.value, last.value));
    }
  }
  return changes.values.map((x) => x.change).toList()..sort((a, b) => b.percent.compareTo(a.percent));
}
