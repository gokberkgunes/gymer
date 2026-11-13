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

/// Compares two sessions of one exercise in one workout; null when nothing is comparable.
///
/// Straight sets are matched by position with the same logging context. By default each pair is compared by
/// estimated 1RM, which already counts reps in reserve; with [byVolume] by load × reps instead. Every other set
/// method is always compared by the total volume of its working sets, because rep-max estimates do not hold
/// across rest-pause, drop or cluster segments and the number of segments reached is itself the result.
/// Only external loads logged as totals are comparable, as for records and volume.
ExerciseTrend? compareExercise(
  SessionExercise now,
  String nowUnit,
  SessionExercise before,
  String beforeUnit, {
  String? templateId,
  bool byVolume = false,
}) {
  if (now.loadMode != 'external' || before.loadMode != 'external' || now.method != before.method) return null;
  final straight = now.method == 'Straight';
  double kg(SetEntry s, String unit) => convertWeight(s.weight!, unit, 'kg');
  bool counted(SessionExercise e, SetEntry s) => _usable(s) && countsAsVolume(e, s);
  var percent = 0.0, pairs = 0;
  double? first;
  var harder = false, dropOff = false;
  final List<SetEntry> work;
  if (straight) {
    final a = work = _straightWork(now), b = _straightWork(before);
    var volumeNow = 0.0, volumeBefore = 0.0, total = 0.0;
    for (var i = 0; i < math.min(a.length, b.length); i++) {
      final x = a[i], y = b[i];
      if (!_usable(x) || !_usable(y) || x.context != y.context) continue;
      if (byVolume && !(countsAsVolume(now, x) && countsAsVolume(before, y))) continue;
      final wx = kg(x, nowUnit), wy = kg(y, beforeUnit);
      final change = byVolume
          ? (wx * x.reps! / (wy * y.reps!) - 1) * 100
          : (setOneRm(wx, x.reps, x.rir)! / setOneRm(wy, y.reps, y.rir)! - 1) * 100;
      volumeNow += wx * x.reps!;
      volumeBefore += wy * y.reps!;
      total += change;
      pairs++;
      if (i == 0) first = change;
      if ((wx - wy).abs() <= wy * 0.005 && x.reps == y.reps && x.rir != null && y.rir != null && x.rir! < y.rir!) {
        harder = true;
      }
    }
    if (pairs == 0) return null;
    percent = byVolume ? (volumeNow / volumeBefore - 1) * 100 : total / pairs;
    final done = a.where(_usable).toList();
    dropOff =
        done.length > 1 &&
        (done.last.weight! - done.first.weight!).abs() <= done.first.weight! * 0.005 &&
        done.last.reps! < done.first.reps! * 0.6;
  } else {
    work = now.work;
    final a = [
      for (final s in now.work)
        if (counted(now, s)) s,
    ];
    final b = [
      for (final s in before.work)
        if (counted(before, s)) s,
    ];
    if (a.isEmpty || b.isEmpty) return null;
    double volume(List<SetEntry> sets, String unit) => sets.fold(0.0, (sum, s) => sum + kg(s, unit) * s.reps!);
    percent = (volume(a, nowUnit) / volume(b, beforeUnit) - 1) * 100;
    pairs = math.min(a.length, b.length);
    // The opening segment is the least affected by what follows it.
    if (identical(a.first, now.work.first) &&
        identical(b.first, before.work.first) &&
        a.first.context == b.first.context) {
      first = (kg(a.first, nowUnit) * a.first.reps! / (kg(b.first, beforeUnit) * b.first.reps!) - 1) * 100;
    }
  }
  final skipped = work.any((s) => s.done) ? work.where((s) => !s.done).length : 0;
  return ExerciseTrend(
    name: now.name,
    templateId: templateId,
    percent: percent,
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
  (List<String>, List<String>) Function(String exercise) musclesOf, {
  bool byVolume = false,
}) {
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
    final trend = compareExercise(
      exercise,
      session.unit,
      before.$2,
      before.$1.unit,
      templateId: session.templateId,
      byVolume: byVolume,
    );
    if (trend == null) continue;
    for (final muscle in musclesOf(exercise.name).$1) {
      byMuscle.putIfAbsent(muscle, () => []).add(trend);
    }
  }
  return {for (final e in byMuscle.entries) e.key: MuscleVerdict(e.key, e.value)};
}

/// Where a muscle's weekly [sets] sit among its RP landmarks, as drawn on the weekly-sets bar; null without
/// landmarks. "Below MV" and "MV" are under the minimum effective volume.
String? volumeZone(String muscle, double sets) {
  final l = rpLandmarks[muscle];
  final mav = l?.mavRange;
  if (l == null || mav == null) return null;
  final mv = Landmark.range(l.mv), mev = l.mevRange, mrv = l.mrvRange;
  if (mv != null && sets < mv.$1) return 'Below MV';
  if (mev != null && sets < mev.$1) return 'MV';
  if (sets < mav.$1) return 'MEV';
  if (sets <= mav.$2 && (mrv == null || sets < mrv.$1)) return 'MAV';
  if (mrv == null) return 'Above MAV';
  return sets <= mrv.$2 ? 'MRV' : 'Above MRV';
}

/// What a falling or rising muscle's volume zone suggests; empty for a holding muscle or an unknown zone.
String zoneAdvice(Trend trend, String? zone) {
  if (zone == null || trend == Trend.holding) return '';
  final low = zone == 'Below MV' || zone == 'MV', high = zone == 'MRV' || zone.startsWith('Above');
  if (trend == Trend.falling) {
    return low
        ? 'Weekly sets are under the minimum effective volume. Falling here points to too little work for this '
              'muscle, or to recovery outside the gym, not to too many sets.'
        : high
        ? 'Weekly sets are at the limit of what can be recovered from. Fewer sets are the likely fix.'
        : 'Weekly sets are in the productive range. Look at sleep, food and total workload before the set count.';
  }
  return low
      ? 'Rising on very little volume. There is room to add sets later; nothing needs to change now.'
      : high
      ? 'Rising close to the limit of what can be recovered from. Hold here; more sets risk a stall.'
      : 'Rising in the productive range. Keep the sets as they are.';
}

/// Sets actually completed in the given sessions, per muscle and averaged over [weeks], in the same units as
/// [plannedWeeklyVolume]. Several weeks keep one late or early workout from emptying the picture.
Map<String, WeeklyVolume> performedVolume(
  Iterable<Session> sessions,
  (List<String>, List<String>) Function(String exercise) musclesOf, {
  double weeks = 1,
}) {
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
        (report.direct[m] ?? VolumeMetrics()).scaled(1 / weeks),
        (report.indirect[m] ?? VolumeMetrics()).scaled(1 / weeks),
        directDaysPerWeek: (days[m]?.length ?? 0) / weeks,
      ),
  };
}

/// Whole-body fatigue: at least two muscles fell, and either they are at least half of the muscles that could
/// be judged or the week's total hard sets were a personal high ([atPersonalHigh]). Removing a set here and
/// there does not answer that; a deload does. Worst first, empty otherwise.
List<MuscleVerdict> wholeBodyDecline(Map<String, MuscleVerdict> verdicts, {bool atPersonalHigh = false}) {
  final falling = verdicts.values.where((v) => v.trend == Trend.falling).toList()
    ..sort((a, b) => a.percent.compareTo(b.percent));
  return falling.length >= 2 && (atPersonalHigh || falling.length * 2 >= verdicts.length) ? falling : const [];
}

/// Whether [total] hard sets in one week match or beat every earlier Monday-to-Sunday week of [earlier]
/// workouts. Needs four earlier training weeks, so a new log cannot set a "record" by default.
bool isPersonalHighWeek(double total, Iterable<Session> earlier) {
  final weeks = <int, int>{};
  for (final s in earlier) {
    weeks.update(CoachPeriods.weeks.indexOf(s.startedAt), (n) => n + s.doneSets, ifAbsent: () => s.doneSets);
  }
  final totals = weeks.values.where((n) => n > 0);
  return totals.length >= 4 && total > 0 && total >= totals.reduce(math.max);
}

/// What the recovery check-ins of one period say, beyond the logged numbers.
class Recovery {
  /// Muscles that were still sore when trained again.
  final Set<String> sore;

  /// Muscles with a low pump every time that had also recovered days before: more work would be absorbed.
  final Set<String> underworked;

  /// Sleep or overall state was poor in at least half of the answered workouts.
  final bool runDown;

  const Recovery({this.sore = const {}, this.underworked = const {}, this.runDown = false});
}

Recovery recoveryOf(Iterable<Session> sessions) {
  final pump = <String, List<int>>{}, recovered = <String, List<int>>{};
  var answered = 0, poor = 0;
  for (final c in sessions.map((s) => s.checkIn).nonNulls) {
    for (final e in c.pump.entries) {
      pump.putIfAbsent(e.key, () => []).add(e.value);
    }
    for (final e in c.recovered.entries) {
      recovered.putIfAbsent(e.key, () => []).add(e.value);
    }
    if (c.sleep != null || c.overall != null) {
      answered++;
      if (c.sleep == 0 || c.overall == 0) poor++;
    }
  }
  return Recovery(
    sore: {
      for (final e in recovered.entries)
        if (e.value.contains(0)) e.key,
    },
    underworked: {
      for (final e in pump.entries)
        if (e.value.every((v) => v == 0) && (recovered[e.key]?.every((v) => v == 2) ?? false)) e.key,
    },
    runDown: answered > 0 && poor * 2 >= answered,
  );
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
/// direct sets (and room under [sessionSetCeiling]), on its best-progressing exercise outside [avoid] (see
/// [droppingOff]); removed sets come from the workout with the most, off the exercise that has moved least.
(String templateId, String exercise)? adjustmentTarget(
  Mesocycle cycle,
  Map<String, WorkoutTemplate> templates,
  (List<String>, List<String>) Function(String exercise) musclesOf,
  String muscle,
  int delta,
  MuscleVerdict? verdict, {
  Set<String> avoid = const {},
}) {
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
            (delta > 0 ? !avoid.contains(e.name.toLowerCase()) : e.workSets > 1))
          e,
    ];
    if (candidates.isEmpty) continue;
    double score(TemplateExercise e) => trend(e)?.percent ?? 0;
    candidates.sort((a, b) => delta > 0 ? score(b).compareTo(score(a)) : score(a).compareTo(score(b)));
    return (option.template, candidates.first.name);
  }
  return null;
}

/// Exercises (lower-case names) whose reps regularly fall off across sets: the last set under 60 % of the
/// first at the same load in the finished period, and in the one before when it was trained then. Their later
/// sets are already low quality, so they never receive an added set.
Set<String> droppingOff(MuscleVerdict verdict, MuscleVerdict? previous) => {
  for (final e in verdict.exercises)
    if (e.dropOff &&
        (previous?.exercises
                .where((x) => x.templateId == e.templateId && sameExercise(x.name, e.name))
                .firstOrNull
                ?.dropOff ??
            true))
      e.name.toLowerCase(),
};

/// The most weekly sets the coach will add up to for [muscle]. A personal range that has found where the
/// muscle falls wins: one set under that level. Otherwise experience decides: beginners stop in the middle of
/// MAV, intermediates at its top (where the MRV zone begins), advanced lifters at the top of MRV. Null without
/// landmarks.
double? addCeiling(String muscle, String experience, PersonalRange? personal) {
  if (personal?.high case final high?) return high - 1;
  final l = rpLandmarks[muscle];
  final mav = l?.mavRange;
  if (mav == null) return null;
  return switch (experience) {
    'beginner' => (mav.$1 + mav.$2) / 2,
    'advanced' => l?.mrvRange?.$2 ?? mav.$2,
    _ => mav.$2,
  };
}

/// The coach's rule for one finished build period, most important first, at most three:
/// progressing keeps its sets; flat for two periods without fatigue gets one more; flat or falling with
/// fatigue loses one. The optional check-ins ([recovery]) sharpen this: still sore counts as fatigue, a low
/// pump with early recovery earns the added set after one flat period, and a run-down period adds nothing.
/// Experience and personal ranges set how far additions go ([addCeiling]); a beginner also gets at most one
/// added set per muscle every two periods.
/// The cycle's eating phase sets the pace: while cutting nothing is added and a run-down flat week already
/// costs a set; at maintenance a set is added only after two flat periods, never on the check-in shortcut.
/// The cycle's muscle goals decide who is coached: a maintained muscle gets no set changes at all, and
/// priority muscles are served first among the additions. One change per muscle per microcycle, never past the top of MRV or below MEV (MV with
/// [keepMev] off), and no
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
  bool keepMev = true,
  Recovery recovery = const Recovery(),
  String experience = 'intermediate',
  Map<String, PersonalRange> personal = const {},
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
    if (handled.contains(v.muscle) || cycle.muscleGoals[v.muscle] == 'maintain') continue;
    final landmark = rpLandmarks[v.muscle];
    final sets = weeklySets[v.muscle] ?? 0;
    final sore = recovery.sore.contains(v.muscle), underworked = recovery.underworked.contains(v.muscle);
    final fatigue = [...v.fatigue, if (sore) 'it was still sore at the next workout'];
    final cutting = cycle.diet == 'cut';
    final remove =
        v.trend == Trend.falling || (v.trend == Trend.holding && (fatigue.isNotEmpty || (cutting && recovery.runDown)));
    final stalled = previous[v.muscle] != null && previous[v.muscle]!.trend != Trend.progressing;
    final add =
        !cutting &&
        v.trend == Trend.holding &&
        fatigue.isEmpty &&
        !recovery.runDown &&
        (stalled || (underworked && cycle.diet != 'maintain'));
    if (!remove && !add) continue;
    final delta = remove ? -1 : 1;
    final floor = (keepMev ? landmark?.mevRange?.$1 : null) ?? Landmark.range(landmark?.mv ?? '')?.$1 ?? 0;
    final top = addCeiling(v.muscle, experience, personal[v.muscle]);
    final justAdded =
        experience == 'beginner' &&
        cycle.setAdjustments.any((a) => a.muscle == v.muscle && a.micro == micro - 1 && a.delta > 0);
    if (add && justAdded) continue;
    if (remove && sets - 1 < floor) continue;
    if (add && (missedWorkout || (top != null && sets + 1 > top))) continue;
    final avoid = add ? droppingOff(v, previous[v.muscle]) : const <String>{};
    final target = adjustmentTarget(cycle, templates, musclesOf, v.muscle, delta, v, avoid: avoid);
    if (target == null) continue;
    final passedOver = avoid.isEmpty
        ? ''
        : ' ${_names(v.exercises.where((e) => avoid.contains(e.name.toLowerCase())))} gets no added set: its reps '
              'fall off sharply from set to set, so another set there would add little. A longer rest may help.';
    final signs =
        '${fatigue.isEmpty ? '' : ' Signs of fatigue: ${fatigue.join('; ')}.'}'
        '${recovery.runDown ? ' Sleep or overall state was poor that $period, which may be part of it.' : ''}'
        '${cutting ? ' While cutting, recovery is lower, so sets come off sooner and none are added.' : ''}';
    final reason = remove
        ? v.trend == Trend.falling
              ? '${_names(v.exercises)} fell ${_percent(v.percent)} from the $period before.$signs'
              : '${_names(v.exercises)} did not move from the $period before.$signs'
        : stalled
        ? '${_names(v.exercises)} have not moved for two $periodsWord, with no signs of fatigue.'
              '${cycle.muscleGoals[v.muscle] == 'priority' ? ' Priority muscles are added to first.' : ''}$passedOver'
        : '${_names(v.exercises)} did not move from the $period before; the pump was low and it had recovered '
              'days earlier.$passedOver';
    (remove ? removals : additions).add((
      v.percent,
      SetSuggestion(muscle: v.muscle, delta: delta, reason: reason, templateId: target.$1, exercise: target.$2),
    ));
  }
  removals.sort((a, b) => a.$1.compareTo(b.$1));
  int rank((double, SetSuggestion) x) => cycle.muscleGoals[x.$2.muscle] == 'priority' ? 0 : 1;
  additions.sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : a.$1.compareTo(b.$1));
  // One exercise serves every muscle it trains: a second muscle never changes the same exercise again.
  final taken = {for (final a in applied) (a.templateId, a.exercise.toLowerCase())};
  final changes = [
    for (final (_, s) in [...removals, ...additions])
      if (taken.add((s.templateId, s.exercise.toLowerCase()))) s,
  ];
  return [...applied, ...changes.take(math.max(0, 3 - applied.length))];
}

/// How one muscle answered one judged build week: the sets it completed and the verdict that week earned.
typedef WeekResponse = ({int micro, double sets, Trend trend, double percent});

/// A muscle's volume response over one mesocycle, for the cycle review and for personal landmarks.
class MuscleResponse {
  final String muscle;
  final List<WeekResponse> weeks;
  const MuscleResponse(this.muscle, this.weeks);

  /// Average weekly sets completed in the judged weeks.
  double get sets => weeks.fold(0.0, (sum, w) => sum + w.sets) / weeks.length;

  /// The weekly changes compounded: where the muscle ended relative to its first compared week.
  double get percent => (weeks.fold(1.0, (product, w) => product * (1 + w.percent / 100)) - 1) * 100;

  /// Sets that bought nothing: the muscle progressed at least as well in its lowest-volume judged week as in
  /// its highest, two or more weekly sets apart. Null otherwise.
  ({double fewer, double more})? get sameAtFewer {
    final byVolume = [...weeks]..sort((a, b) => a.sets.compareTo(b.sets));
    final low = byVolume.first, high = byVolume.last;
    return high.sets - low.sets >= 2 &&
            low.trend == Trend.progressing &&
            high.trend == Trend.progressing &&
            low.percent >= high.percent - trendStep / 2
        ? (fewer: low.sets, more: high.sets)
        : null;
  }

  /// Where to start next time: lower when the cycle ended falling or extra sets bought nothing
  /// ([sameAtFewer]), higher when two or more judged weeks never progressed and never fell (it stayed
  /// under-stimulated), otherwise the same.
  int get nextStart => weeks.last.trend == Trend.falling || sameAtFewer != null
      ? -1
      : weeks.length > 1 && weeks.every((w) => w.trend == Trend.holding)
      ? 1
      : 0;
}

/// Every muscle's response in the build weeks of one cycle. [sessions] are that cycle's build workouts and
/// [buildWeeks] its number of build microcycles; the first one has nothing to be compared with.
Map<String, MuscleResponse> cycleResponse(
  List<Session> sessions,
  CoachPeriods periods,
  int buildWeeks,
  (List<String>, List<String>) Function(String exercise) musclesOf, {
  bool byVolume = false,
  bool includePartialSets = true,
}) {
  final weeks = <String, List<WeekResponse>>{};
  for (var p = 1; p < buildWeeks; p++) {
    final verdicts = muscleVerdicts(sessions, periods, p, musclesOf, byVolume: byVolume);
    if (verdicts.isEmpty) continue;
    final done = performedVolume(
      sessions.where((s) => periods.indexOf(s.startedAt) == p),
      musclesOf,
      weeks: periods.days / 7,
    );
    for (final v in verdicts.values) {
      weeks.putIfAbsent(v.muscle, () => []).add((
        micro: p + 1,
        sets: done[v.muscle]?.countedSets(includePartialSets: includePartialSets) ?? 0,
        trend: v.trend,
        percent: v.percent,
      ));
    }
  }
  return {for (final e in weeks.entries) e.key: MuscleResponse(e.key, e.value)};
}

/// A muscle's own working range, learned from finished mesocycles: the fewest weekly sets at which it
/// progressed, and the fewest above that at which it fell (null while that has not happened).
typedef PersonalRange = ({double low, double? high, int cycles});

/// Needs the muscle in at least two cycles and one progressing week; RP's landmarks stay the reference until
/// then, and beside it afterwards.
Map<String, PersonalRange> personalRanges(Iterable<Map<String, MuscleResponse>> cycles) {
  final byMuscle = <String, List<MuscleResponse>>{};
  for (final cycle in cycles) {
    for (final r in cycle.values) {
      byMuscle.putIfAbsent(r.muscle, () => []).add(r);
    }
  }
  final ranges = <String, PersonalRange>{};
  for (final MapEntry(key: muscle, value: responses) in byMuscle.entries) {
    if (responses.length < 2) continue;
    final weeks = responses.expand((r) => r.weeks).where((w) => w.sets > 0).toList();
    final progressed = weeks.where((w) => w.trend == Trend.progressing).map((w) => w.sets);
    if (progressed.isEmpty) continue;
    final low = progressed.reduce(math.min);
    final fell = weeks.where((w) => w.trend == Trend.falling && w.sets > low).map((w) => w.sets);
    ranges[muscle] = (low: low, high: fell.isEmpty ? null : fell.reduce(math.min), cycles: responses.length);
  }
  return ranges;
}
