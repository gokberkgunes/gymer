import 'dart:math' as math;

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

/// Compare the best of the first build microcycle with the best of the last one, per exercise, method and logging
/// context. Each set's estimate counts its reps in reserve ([setOneRm]), so a cycle that ramps from 3 RIR toward
/// failure does not read as a strength gain merely because later sets were taken closer to failure. Taking the
/// best of a whole microcycle rather than of single sessions keeps one off day from deciding the result.
/// Deloads, warm-ups, unfinished sets and non-external loads cannot establish strength changes.
List<CycleStrengthChange> cycleStrengthChanges(Mesocycle cycle, List<Session> sessions, String unit) {
  final micro = math.max(1, cycle.microDays);
  final points = <(String, String, SetContext), List<({int micro, String name, DateTime date, double value})>>{};
  for (final session in sessions) {
    final day = daysBetween(cycle.start, session.startedAt);
    final deload =
        session.phase == 'Deload' ||
        (session.phase == null && day >= (cycle.length - cycle.deloadMicro) * cycle.microDays);
    if (deload) continue;
    final bests = <(String, String, SetContext), ({String name, double value})>{};
    for (final exercise in session.exercises) {
      if (exercise.loadMode != 'external' || exercise.method != 'Straight') continue;
      for (final set in exercise.work) {
        if (!set.done || !isStraightType(set.type) || (set.weight ?? 0) <= 0 || (set.reps ?? 0) <= 0) continue;
        final value = setOneRm(convertWeight(set.weight!, session.unit, unit), set.reps, set.rir)!;
        final key = (exercise.name.toLowerCase(), exercise.method, set.context);
        if (value > (bests[key]?.value ?? 0)) bests[key] = (name: exercise.name, value: value);
      }
    }
    for (final entry in bests.entries) {
      points.putIfAbsent(entry.key, () => []).add((
        micro: math.max(0, day) ~/ micro,
        name: entry.value.name,
        date: session.startedAt,
        value: entry.value.value,
      ));
    }
  }
  final changes = <String, ({DateTime date, CycleStrengthChange change})>{};
  for (final entries in points.values) {
    entries.sort((a, b) => a.date.compareTo(b.date));
    final firstMicro = entries.first.micro, lastMicro = entries.last.micro;
    if (firstMicro == lastMicro) continue;
    double best(int m) => entries.where((e) => e.micro == m).map((e) => e.value).reduce(math.max);
    final last = entries.last;
    final key = last.name.toLowerCase();
    final existing = changes[key];
    if (existing == null || last.date.isAfter(existing.date)) {
      changes[key] = (date: last.date, change: CycleStrengthChange(last.name, best(firstMicro), best(lastMicro)));
    }
  }
  return changes.values.map((x) => x.change).toList()..sort((a, b) => b.percent.compareTo(a.percent));
}
