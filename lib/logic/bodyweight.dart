import 'dart:math' as math;

import '../models.dart';
import 'progression.dart';

/// A day-level measurement in kg, independent of the display unit.
class BodyweightEntry {
  final DateTime date;
  final double kg;
  BodyweightEntry(DateTime date, this.kg) : date = dateOnly(date) {
    if (!kg.isFinite || kg <= 0) throw const FormatException('Invalid bodyweight measurement.');
  }

  double inUnit(String unit) => convertWeight(kg, 'kg', unit);
  Map<String, dynamic> toJson() => {'date': dateKey(date), 'kg': kg};
  factory BodyweightEntry.fromJson(Map<String, dynamic> json) =>
      BodyweightEntry(DateTime.parse(json['date'] as String), (json['kg'] as num).toDouble());
}

typedef BodyweightPoint = ({DateTime date, double weight, double trend});

/// Seven-day exponential smoothing accounts for gaps between weigh-ins.
List<BodyweightPoint> bodyweightTrend(List<BodyweightEntry> entries, String unit) {
  final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
  final points = <BodyweightPoint>[];
  for (final entry in sorted) {
    final weight = entry.inUnit(unit);
    final previous = points.lastOrNull;
    final alpha = previous == null ? 1.0 : 1 - math.exp(-daysBetween(previous.date, entry.date) / 7);
    points.add((
      date: entry.date,
      weight: weight,
      trend: previous == null ? weight : previous.trend + alpha * (weight - previous.trend),
    ));
  }
  return points;
}

/// Change of the smoothed bodyweight per week over roughly the last two weeks; null without a weigh-in in the
/// last fortnight and another at least fourteen days before it.
double? bodyweightWeeklyRate(List<BodyweightPoint> trend, DateTime now) {
  final last = trend.lastOrNull;
  if (last == null || daysBetween(last.date, now) > 14) return null;
  final earlier = trend.where((p) => daysBetween(p.date, last.date) >= 14).lastOrNull;
  if (earlier == null) return null;
  return (last.trend - earlier.trend) / daysBetween(earlier.date, last.date) * 7;
}

/// Separate from entered loads and progression; no estimate for ambiguous per-side loads.
double? combinedBodyweightLoad(Session session, SessionExercise exercise, SetEntry set) {
  if (session.bodyweight == null ||
      !session.bodyweight!.isFinite ||
      session.bodyweight! <= 0 ||
      !set.done ||
      set.warmup ||
      (set.reps ?? 0) <= 0 ||
      set.weight == null ||
      !set.weight!.isFinite ||
      set.weight! < 0 ||
      (set.context.loadBasis.isNotEmpty && set.context.loadBasis != 'total')) {
    return null;
  }
  final load = switch (exercise.loadMode) {
    'bodyweight' => session.bodyweight! + set.weight!,
    'assisted' => session.bodyweight! - set.weight!,
    _ => null,
  };
  return load != null && load > 0 ? load : null;
}
