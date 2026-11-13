/// Coach: how each muscle responded from one training period to the next, and which sets to change.
library;

import 'dart:math' as math;

import '../models.dart';
import 'cycle.dart';
import 'methods.dart';
import 'progression.dart';
import 'volume.dart';

enum Trend { progressing, holding, falling }

/// Estimated-1RM change (percent) below which a comparison counts as unchanged. One more rep at the same load
/// and effort is roughly 2.5 %, so this separates a real change from rounding.
const trendStep = 1.0;

/// Direct working sets for one muscle in one workout past which another set adds little.
const sessionSetCeiling = 10;

Trend trendOf(double percent) => percent >= trendStep
    ? Trend.progressing
    : percent <= -trendStep
    ? Trend.falling
    : Trend.holding;

/// One exercise of one workout, compared with the same exercise in that workout a period earlier.
class ExerciseTrend {
  final String name;
  final String? templateId;

  /// Mean estimated-1RM change of the matched set positions, in percent.
  final double percent;
  final int pairs;

  /// Signs that the work was more than could be recovered from, in plain words.
  final List<String> fatigue;

  /// The last set fell under 60 % of the first set's reps at the same load: later sets are low quality.
  final bool dropOff;

  const ExerciseTrend({
    required this.name,
    required this.templateId,
    required this.percent,
    required this.pairs,
    this.fatigue = const [],
    this.dropOff = false,
  });

  Trend get trend => trendOf(percent);
}

class MuscleVerdict {
  final String muscle;
  final List<ExerciseTrend> exercises;
  const MuscleVerdict(this.muscle, this.exercises);

  double get percent {
    final pairs = exercises.fold(0, (n, e) => n + e.pairs);
    return exercises.fold(0.0, (sum, e) => sum + e.percent * e.pairs) / math.max(1, pairs);
  }

  Trend get trend => trendOf(percent);
  bool get fatigued => exercises.any((e) => e.fatigue.isNotEmpty);
  List<String> get fatigue => {for (final e in exercises) ...e.fatigue}.toList();
}

List<SetEntry> _straightWork(SessionExercise e) => [
  for (final s in e.work)
    if (isStraightType(s.type)) s,
];

bool _usable(SetEntry s) => s.done && (s.weight ?? 0) > 0 && (s.reps ?? 0) > 0;

/// Compares set positions of two sessions of one exercise by estimated 1RM, which already counts reps in
/// reserve. Only straight sets of external-load exercises with the same logging context are comparable, as for
/// records; null when no position matches.
ExerciseTrend? compareExercise(
  SessionExercise now,
  String nowUnit,
  SessionExercise before,
  String beforeUnit, {
  String? templateId,
}) {
  if (now.loadMode != 'external' || before.loadMode != 'external') return null;
  if (now.method != 'Straight' || before.method != 'Straight') return null;
  final a = _straightWork(now), b = _straightWork(before);
  var total = 0.0, pairs = 0;
  double? first;
  var harder = false;
  for (var i = 0; i < math.min(a.length, b.length); i++) {
    final x = a[i], y = b[i];
    if (!_usable(x) || !_usable(y) || x.context != y.context) continue;
    final wx = convertWeight(x.weight!, nowUnit, 'kg'), wy = convertWeight(y.weight!, beforeUnit, 'kg');
    final change = (setOneRm(wx, x.reps, x.rir)! / setOneRm(wy, y.reps, y.rir)! - 1) * 100;
    total += change;
    pairs++;
    if (i == 0) first = change;
    if ((wx - wy).abs() <= wy * 0.005 && x.reps == y.reps && x.rir != null && y.rir != null && x.rir! < y.rir!) {
      harder = true;
    }
  }
  if (pairs == 0) return null;
  final done = a.where(_usable).toList();
  final dropOff =
      done.length > 1 &&
      (done.last.weight! - done.first.weight!).abs() <= done.first.weight! * 0.005 &&
      done.last.reps! < done.first.reps! * 0.6;
  final skipped = a.any((s) => s.done) ? a.where((s) => !s.done).length : 0;
  return ExerciseTrend(
    name: now.name,
    templateId: templateId,
    percent: total / pairs,
    pairs: pairs,
    dropOff: dropOff,
    fatigue: [
      if (first != null && first <= -trendStep) 'the first set was weaker than the time before',
      if (harder) 'the same reps left fewer in reserve',
      if (dropOff) 'reps fell off sharply from set to set',
      if (skipped > 0) '$skipped ${skipped == 1 ? 'set was' : 'sets were'} skipped',
      if (now.work.any((s) => s.done && s.stopReason == 'safety_limit')) 'a set ended at a safety limit or discomfort',
    ],
  );
}

/// Training periods counted from [start]: microcycles inside a mesocycle, Monday-to-Sunday weeks outside one.
class CoachPeriods {
  final DateTime start;
  final int days;
  const CoachPeriods(this.start, this.days);

  /// Calendar weeks; 2024-01-01 was a Monday.
  static final weeks = CoachPeriods(DateTime(2024, 1, 1), 7);

  int indexOf(DateTime date) => (daysBetween(start, date) / math.max(1, days)).floor();
}

/// Verdicts for [period]: each exercise's last session in it against its last session in the period before,
/// within the same workout, gathered under the exercise's primary muscles. [sessions] must already exclude
/// deloads and other cycles. A muscle with nothing comparable has no verdict.
Map<String, MuscleVerdict> muscleVerdicts(
  Iterable<Session> sessions,
  CoachPeriods periods,
  int period,
  (List<String>, List<String>) Function(String exercise) musclesOf,
) {
  final latest = <(String?, String), (Session, SessionExercise)>{};
  final earlier = <(String?, String), (Session, SessionExercise)>{};
  for (final session in sessions) {
    final index = periods.indexOf(session.startedAt);
    if (index != period && index != period - 1) continue;
    final target = index == period ? latest : earlier;
    for (final exercise in session.exercises) {
      if (!exercise.work.any((s) => s.done)) continue;
      final key = (session.templateId, exercise.name.toLowerCase());
      final existing = target[key];
      if (existing == null || session.startedAt.isAfter(existing.$1.startedAt)) target[key] = (session, exercise);
    }
  }
  final byMuscle = <String, List<ExerciseTrend>>{};
  for (final MapEntry(:key, value: (session, exercise)) in latest.entries) {
    final before = earlier[key];
    if (before == null) continue;
    final trend = compareExercise(exercise, session.unit, before.$2, before.$1.unit, templateId: session.templateId);
    if (trend == null) continue;
    for (final muscle in musclesOf(exercise.name).$1) {
      byMuscle.putIfAbsent(muscle, () => []).add(trend);
    }
  }
  return {for (final e in byMuscle.entries) e.key: MuscleVerdict(e.key, e.value)};
}

/// Sets actually completed in the given sessions, per muscle, in the same units as [plannedWeeklyVolume].
Map<String, WeeklyVolume> performedVolume(
  Iterable<Session> sessions,
  (List<String>, List<String>) Function(String exercise) musclesOf,
) {
  final rows = <VolumeRow>[];
  final days = <String, Set<String>>{};
  for (final session in sessions) {
    for (final (i, e) in session.exercises.indexed) {
      final (primary, secondary) = musclesOf(e.name);
      if (e.work.any((s) => s.done)) {
        for (final muscle in primary) {
          days.putIfAbsent(muscle, () => {}).add(dateKey(session.startedAt));
        }
      }
      for (final s in e.sets) {
        rows.add(
          VolumeRow(
            scope: '${session.id}/$i',
            type: s.type,
            active: s.done,
            groupStart: s.groupStart,
            primary: primary,
            secondary: secondary,
          ),
        );
      }
    }
  }
  final report = summarizeVolume(rows);
  return {
    for (final m in {...report.direct.keys, ...report.indirect.keys})
      m: WeeklyVolume(
        report.direct[m] ?? VolumeMetrics(),
        report.indirect[m] ?? VolumeMetrics(),
        directDaysPerWeek: (days[m]?.length ?? 0).toDouble(),
      ),
  };
}

/// One line of the weekly suggestions: add a set, remove one, or (after Apply) the change already made.
class SetSuggestion {
  final String muscle;
  final int delta;
  final String reason;
  final String templateId;
  final String exercise;

  /// Already applied in this microcycle; can be undone.
  final SetAdjustment? applied;

  const SetSuggestion({
    required this.muscle,
    required this.delta,
    required this.reason,
    required this.templateId,
    required this.exercise,
    this.applied,
  });
}

String _names(Iterable<ExerciseTrend> exercises) {
  final names = {for (final e in exercises) e.name}.toList();
  return names.length <= 2 ? names.join(' and ') : '${names.take(2).join(', ')} and ${names.length - 2} more';
}

String _percent(double v) => '${v.abs().toStringAsFixed(1)} %';

/// Where a set is added or removed for [muscle]. Added sets go to the workout where the muscle has the fewest
/// direct sets (and room under [sessionSetCeiling]), on its best-progressing exercise that is not dropping
/// off; removed sets come from the workout with the most, off the exercise that has moved least.
(String templateId, String exercise)? adjustmentTarget(
  Mesocycle cycle,
  Map<String, WorkoutTemplate> templates,
  (List<String>, List<String>) Function(String exercise) musclesOf,
  String muscle,
  int delta,
  MuscleVerdict? verdict,
) {
  final options = <({String template, int sets, List<TemplateExercise> exercises})>[];
  for (final id in cycle.schedule.values.toSet()) {
    final base = templates[id];
    if (base == null) continue;
    final plan = plannedTemplate(cycle, base);
    final direct = [
      for (final e in plan.exercises)
        if (musclesOf(e.name).$1.contains(muscle) && e.workSets > 0) e,
    ];
    final sets = direct.fold(0, (n, e) => n + e.workSets);
    if (direct.isEmpty || (delta > 0 && sets >= sessionSetCeiling)) continue;
    options.add((template: id, sets: sets, exercises: direct));
  }
  options.sort((a, b) => delta > 0 ? a.sets.compareTo(b.sets) : b.sets.compareTo(a.sets));
  for (final option in options) {
    ExerciseTrend? trend(TemplateExercise e) =>
        verdict?.exercises.where((x) => x.templateId == option.template && sameExercise(x.name, e.name)).firstOrNull;
    final candidates = [
      for (final e in option.exercises)
        if (canonicalMethod(e.method) == 'Straight' &&
            isStraightType(e.sets.last.type) &&
            (delta > 0 ? trend(e)?.dropOff != true : e.workSets > 1))
          e,
    ];
    if (candidates.isEmpty) continue;
    double score(TemplateExercise e) => trend(e)?.percent ?? 0;
    candidates.sort((a, b) => delta > 0 ? score(b).compareTo(score(a)) : score(a).compareTo(score(b)));
    return (option.template, candidates.first.name);
  }
  return null;
}

/// The coach's rule for one finished build period, most important first, at most three:
/// progressing keeps its sets; flat for two periods without fatigue gets one more; flat or falling with
/// fatigue loses one. One change per muscle per microcycle, never past the top of MRV or below MV, and no
/// additions after a missed workout. [verdicts] is the finished period, [previous] the one before it,
/// [weeklySets] the current plan per muscle and [micro] the running microcycle (1-based).
List<SetSuggestion> coachSuggestions({
  required Mesocycle cycle,
  required int micro,
  required Map<String, WorkoutTemplate> templates,
  required (List<String>, List<String>) Function(String exercise) musclesOf,
  required Map<String, MuscleVerdict> verdicts,
  required Map<String, MuscleVerdict> previous,
  required Map<String, double> weeklySets,
  required bool missedWorkout,
}) {
  final applied = <SetSuggestion>[
    for (final a in cycle.setAdjustments)
      if (a.micro == micro && a.delta != 0)
        SetSuggestion(
          muscle: a.muscle,
          delta: a.delta,
          reason: 'Applied this ${cycle.periodNoun()}. It stays for the rest of the mesocycle.',
          templateId: a.templateId,
          exercise: a.exercise,
          applied: a,
        ),
  ];
  final handled = {
    for (final a in cycle.setAdjustments)
      if (a.micro == micro) a.muscle,
  };
  final removals = <(double, SetSuggestion)>[], additions = <(double, SetSuggestion)>[];
  final period = cycle.periodNoun(), periodsWord = cycle.periodNoun(plural: true);
  for (final v in verdicts.values) {
    if (handled.contains(v.muscle)) continue;
    final landmark = rpLandmarks[v.muscle];
    final sets = weeklySets[v.muscle] ?? 0;
    final remove = v.trend == Trend.falling || (v.trend == Trend.holding && v.fatigued);
    final add =
        v.trend == Trend.holding &&
        !v.fatigued &&
        previous[v.muscle] != null &&
        previous[v.muscle]!.trend != Trend.progressing;
    if (!remove && !add) continue;
    final delta = remove ? -1 : 1;
    final floor = Landmark.range(landmark?.mv ?? '')?.$1 ?? 0;
    final top = landmark?.mrvRange?.$2 ?? landmark?.mavRange?.$2;
    if (remove && sets - 1 < floor) continue;
    if (add && (missedWorkout || (top != null && sets + 1 > top))) continue;
    final target = adjustmentTarget(cycle, templates, musclesOf, v.muscle, delta, v);
    if (target == null) continue;
    final signs = v.fatigue.isEmpty ? '' : ' Signs of fatigue: ${v.fatigue.join('; ')}.';
    final reason = remove
        ? v.trend == Trend.falling
              ? '${_names(v.exercises)} fell ${_percent(v.percent)} from the $period before.$signs'
              : '${_names(v.exercises)} did not move from the $period before.$signs'
        : '${_names(v.exercises)} have not moved for two $periodsWord, with no signs of fatigue.';
    (remove ? removals : additions).add((
      v.percent,
      SetSuggestion(muscle: v.muscle, delta: delta, reason: reason, templateId: target.$1, exercise: target.$2),
    ));
  }
  removals.sort((a, b) => a.$1.compareTo(b.$1));
  additions.sort((a, b) => a.$1.compareTo(b.$1));
  // One exercise serves every muscle it trains: a second muscle never changes the same exercise again.
  final taken = {for (final a in applied) (a.templateId, a.exercise.toLowerCase())};
  final changes = [
    for (final (_, s) in [...removals, ...additions])
      if (taken.add((s.templateId, s.exercise.toLowerCase()))) s,
  ];
  return [...applied, ...changes.take(math.max(0, 3 - applied.length))];
}
