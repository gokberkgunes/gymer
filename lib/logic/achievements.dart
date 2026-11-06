import 'dart:math' as math;

import '../models.dart';
import 'numbers.dart';
import 'progression.dart';

enum AchievementKind { workouts, sets, weeks, load }

class Achievement {
  final String id, title;
  final AchievementKind kind;
  final int target;
  const Achievement(this.id, this.title, this.kind, this.target);

  String goal(String unit) => switch (kind) {
    AchievementKind.workouts => '$target ${target == 1 ? 'workout' : 'workouts'}',
    AchievementKind.sets => '${groupThousands(target.toDouble())} working sets',
    AchievementKind.weeks => '$target weeks in a row',
    AchievementKind.load =>
      '${formatNumber(convertWeight(target.toDouble(), 'kg', unit), NumKind.weight)} $unit logged',
  };

  String get explanation => switch (kind) {
    AchievementKind.workouts =>
      'Finish workouts with at least one completed working set. Warm-up-only workouts do not count.',
    AchievementKind.sets => 'Complete working sets across your saved workouts. Warm-ups do not count.',
    AchievementKind.weeks =>
      'Train at least once each week, Monday to Sunday. Rest days are welcome. Progress shows your best streak.',
    AchievementKind.load =>
      'Complete a working set at this load or higher. Uses the weight you logged, never an estimated max. Bodyweight, assisted, per-side and per-implement loads are excluded.',
  };
}

const achievements = [
  Achievement('workouts_1', 'First step', AchievementKind.workouts, 1),
  Achievement('workouts_10', 'Finding rhythm', AchievementKind.workouts, 10),
  Achievement('workouts_25', 'In the groove', AchievementKind.workouts, 25),
  Achievement('workouts_50', 'Steady effort', AchievementKind.workouts, 50),
  Achievement('workouts_100', 'Century club', AchievementKind.workouts, 100),
  Achievement('workouts_250', 'The long game', AchievementKind.workouts, 250),
  Achievement('sets_100', 'Solid foundation', AchievementKind.sets, 100),
  Achievement('sets_500', 'Built by effort', AchievementKind.sets, 500),
  Achievement('sets_1000', 'A thousand strong', AchievementKind.sets, 1000),
  Achievement('weeks_2', 'Showing up', AchievementKind.weeks, 2),
  Achievement('weeks_4', 'A new habit', AchievementKind.weeks, 4),
  Achievement('weeks_8', 'Making it stick', AchievementKind.weeks, 8),
  Achievement('weeks_12', 'Part of your life', AchievementKind.weeks, 12),
  Achievement('load_50', 'Moving weight', AchievementKind.load, 50),
  Achievement('load_100', 'Triple digits', AchievementKind.load, 100),
  Achievement('load_150', 'Raising the bar', AchievementKind.load, 150),
  Achievement('load_200', 'Built over time', AchievementKind.load, 200),
];

class AchievementProgress {
  final Achievement achievement;
  final double value;
  final DateTime? earnedAt;
  final String? sessionId;
  const AchievementProgress(this.achievement, this.value, {this.earnedAt, this.sessionId});

  bool get earned => earnedAt != null;
  double get fraction => (value / achievement.target).clamp(0, 1);
  String progress(String unit) {
    final current = math.min(value, achievement.target.toDouble());
    if (achievement.kind == AchievementKind.load) {
      String w(double kg) => formatNumber(convertWeight(kg, 'kg', unit), NumKind.weight);
      return '${w(current)} / ${w(achievement.target.toDouble())} $unit';
    }
    return '${groupThousands(current)} / ${groupThousands(achievement.target.toDouble())}';
  }
}

/// History is the source of truth. Read-only, independent of display units, and never includes an active session.
List<AchievementProgress> achievementProgress(Iterable<Session> history) {
  final sessions =
      {
        for (final s in history)
          if (s.finishedAt != null) s.id: s,
      }.values.toList()..sort((a, b) {
        final byDate = a.startedAt.compareTo(b.startedAt);
        return byDate == 0 ? a.id.compareTo(b.id) : byDate;
      });
  final values = {for (final kind in AchievementKind.values) kind: 0.0};
  final earned = <String, (DateTime, String)>{};
  DateTime? lastWeek;
  var streak = 0;
  for (final session in sessions) {
    var sets = 0;
    var load = 0.0;
    for (final exercise in session.exercises) {
      for (final set in exercise.sets) {
        if (!set.done || set.warmup || (set.reps ?? 0) <= 0) continue;
        sets++;
        final weight = set.weight;
        if (exercise.loadMode == 'external' &&
            (set.context.loadBasis.isEmpty || set.context.loadBasis == 'total') &&
            weight != null &&
            weight.isFinite &&
            weight > 0) {
          load = math.max(load, convertWeight(weight, session.unit, 'kg'));
        }
      }
    }
    if (sets == 0) continue;
    final day = dateOnly(session.startedAt.toLocal());
    final week = addDays(day, 1 - day.weekday);
    if (lastWeek == null || daysBetween(lastWeek, week) != 0) {
      streak = lastWeek != null && daysBetween(lastWeek, week) == 7 ? streak + 1 : 1;
      lastWeek = week;
    }
    values[AchievementKind.workouts] = values[AchievementKind.workouts]! + 1;
    values[AchievementKind.sets] = values[AchievementKind.sets]! + sets;
    values[AchievementKind.weeks] = math.max(values[AchievementKind.weeks]!, streak.toDouble());
    values[AchievementKind.load] = math.max(values[AchievementKind.load]!, load);
    for (final achievement in achievements) {
      // History's unit conversion rounds to two decimals; tolerate that conversion noise only.
      final tolerance = achievement.kind == AchievementKind.load ? 0.01 : 0;
      if (values[achievement.kind]! + tolerance >= achievement.target) {
        earned.putIfAbsent(achievement.id, () => (session.finishedAt!, session.id));
      }
    }
  }
  return [
    for (final achievement in achievements)
      AchievementProgress(
        achievement,
        values[achievement.kind]!,
        earnedAt: earned[achievement.id]?.$1,
        sessionId: earned[achievement.id]?.$2,
      ),
  ];
}
