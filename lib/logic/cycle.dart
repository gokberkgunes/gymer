/// Mesocycle status, calendar and volume, ported from the Flet storage layer.
library;

import 'dart:math' as math;

import '../models.dart';
import 'methods.dart';
import 'volume.dart';

class CycleStatus {
  final DateTime start, end;
  final int totalDays, totalMicro, buildMicro, deloadMicro, currentMicro, dayInMicro, remainingDays;
  final String phase; // Upcoming | Build | Deload | Complete
  final double progress;
  final int suggestedRir;

  const CycleStatus({
    required this.start,
    required this.end,
    required this.totalDays,
    required this.totalMicro,
    required this.buildMicro,
    required this.deloadMicro,
    required this.currentMicro,
    required this.dayInMicro,
    required this.remainingDays,
    required this.phase,
    required this.progress,
    required this.suggestedRir,
  });

  bool get running => phase == 'Build' || phase == 'Deload';
}

/// RIR for a microcycle: spread evenly from the start RIR in the first build week to the end RIR in the final
/// build week (rounded), deload RIR afterwards. Even spacing keeps the approach to failure gradual: 3 → 0 over
/// six weeks is 3, 2, 2, 1, 1, 0 rather than reaching 0 in week four and staying there.
int rirForWeek(Mesocycle c, int week) {
  final total = math.max(1, c.length);
  final deload = math.min(math.max(0, c.deloadMicro), math.max(0, total - 1));
  final build = math.max(1, total - deload);
  int rir;
  if (deload > 0 && week > build) {
    rir = c.deloadRir;
  } else if (build <= 1) {
    rir = c.endRir;
  } else {
    final position = (math.min(week, build) - 1).clamp(0, build - 1);
    rir = (c.startRir + (c.endRir - c.startRir) * position / (build - 1)).round();
  }
  return c.weekRir[week] ?? rir;
}

CycleStatus cycleStatus(Mesocycle c, [DateTime? today]) {
  final start = dateOnly(c.start);
  final day = dateOnly(today ?? DateTime.now());
  final micro = math.max(1, c.microDays);
  final totalMicro = math.max(1, c.length);
  final totalDays = totalMicro * micro;
  final deload = math.min(math.max(0, c.deloadMicro), math.max(0, totalMicro - 1));
  final build = math.max(1, totalMicro - deload);
  final elapsed = daysBetween(start, day);
  final upcoming = elapsed < 0, complete = elapsed >= totalDays;
  final effective = math.min(math.max(elapsed, 0), math.max(0, totalDays - 1));
  final current = math.min(totalMicro, effective ~/ micro + 1);
  final phase = upcoming
      ? 'Upcoming'
      : complete
      ? 'Complete'
      : deload > 0 && current > build
      ? 'Deload'
      : 'Build';
  return CycleStatus(
    start: start,
    end: addDays(start, totalDays - 1),
    totalDays: totalDays,
    totalMicro: totalMicro,
    buildMicro: build,
    deloadMicro: deload,
    currentMicro: current,
    dayInMicro: effective % micro + 1,
    remainingDays: math.max(0, totalDays - math.max(0, elapsed)),
    phase: phase,
    progress: upcoming ? 0 : (elapsed / math.max(1, totalDays)).clamp(0.0, 1.0),
    suggestedRir: upcoming
        ? c.startRir
        : complete
        // A finished cycle reports its final build effort, as the Flet app did.
        ? c.weekRir[current] ?? c.endRir
        : rirForWeek(c, current),
  );
}

class CycleDay {
  final DateTime date;
  final int micro, dayInMicro;
  final String? templateId;
  final String status; // done | moved_done | missed | moved | planned | rest
  final String? sessionId;
  final DateTime? movedTo;
  final List<(DateTime, String)> incoming;
  final bool unplanned;

  /// A session on this date that belongs to another planned day.
  final bool offPlan;
  final List<Session> sessions;

  const CycleDay({
    this.offPlan = false,
    this.sessions = const [],
    required this.date,
    required this.micro,
    required this.dayInMicro,
    required this.templateId,
    required this.status,
    required this.sessionId,
    required this.movedTo,
    required this.incoming,
    required this.unplanned,
  });
}

List<CycleDay> calendarDays(Mesocycle c, List<Session> history) {
  final status = cycleStatus(c);
  final micro = math.max(1, c.microDays); // same guard as cycleStatus: never divide by zero
  final byId = {for (final s in history) s.id: s};
  final linked = {for (final e in c.events.values) ?e.sessionId};
  final ownByDate = <String, List<Session>>{};
  for (final s in history) {
    if (s.cycleId == c.id || linked.contains(s.id)) {
      ownByDate.putIfAbsent(dateKey(s.startedAt), () => []).add(s);
    }
  }
  final plannedBySession = {
    for (final e in c.events.entries)
      if (e.value.sessionId != null) e.value.sessionId!: e.key,
  };
  final incoming = <String, List<(DateTime, String)>>{};
  for (final MapEntry(key: planned, value: e) in c.events.entries) {
    final target = e.movedTo;
    if (target == null || e.status != 'planned' || dateKey(target) == planned) continue;
    final s = e.sessionId == null ? null : byId[e.sessionId];
    if (s == null || dateKey(s.startedAt) == dateKey(target)) {
      incoming.putIfAbsent(dateKey(target), () => []).add((DateTime.parse(planned), e.templateId));
    }
  }

  return [
    for (var i = 0; i < status.totalDays; i++)
      () {
        final date = addDays(status.start, i);
        final key = dateKey(date);
        final dayIn = i % micro + 1;
        final event = c.events[key];
        final templateId = event?.templateId ?? c.schedule[dayIn];
        Session? session = event?.sessionId == null ? null : byId[event!.sessionId];
        if (session == null && event == null) {
          session = ownByDate[key]?.where((s) => s.templateId == templateId && !linked.contains(s.id)).firstOrNull;
        }
        final String st;
        if (session != null) {
          st = dateKey(session.startedAt) == key && event?.status != 'unplanned' ? 'done' : 'moved_done';
        } else if (event?.status == 'missed') {
          st = 'missed';
        } else if (event?.movedTo != null) {
          st = 'moved';
        } else {
          st = templateId == null ? 'rest' : 'planned';
        }
        return CycleDay(
          date: date,
          micro: i ~/ micro + 1,
          dayInMicro: dayIn,
          templateId: templateId,
          status: st,
          sessionId: session?.id,
          movedTo: event?.movedTo,
          incoming: incoming[key] ?? const [],
          unplanned: event?.status == 'unplanned',
          sessions: ownByDate[key] ?? const [],
          offPlan:
              st == 'moved_done' ||
              (ownByDate[key] ?? const []).any((x) {
                final planned = plannedBySession[x.id];
                return planned != null ? planned != key : x.id != session?.id;
              }),
        );
      }(),
  ];
}

/// Workouts still due on [day] (default today): the planned one unless it was moved away, missed or done, plus
/// any moved here. Everything that says "today" must read this, never `schedule[dayInMicro]` directly, which
/// knows nothing about calendar changes or a cycle that has not started.
List<String> dueWorkouts(Mesocycle c, List<Session> history, [DateTime? day]) {
  final at = day ?? DateTime.now();
  if (!cycleStatus(c, at).running) return const [];
  final today = calendarDays(c, history).where((d) => dateKey(d.date) == dateKey(at)).firstOrNull;
  if (today == null) return const [];
  return [
    if (today.templateId != null && today.status == 'planned') today.templateId!,
    for (final (_, id) in today.incoming) id,
  ];
}

/// After a session is saved, attach it to the one calendar day it fulfils.
void linkSession(Mesocycle c, Session s) {
  if (s.templateId == null) return;
  final date = dateKey(s.startedAt);
  final candidates = c.events.entries
      .where(
        (e) =>
            e.value.templateId == s.templateId &&
            (e.value.status == 'planned' || e.value.status == 'missed') &&
            e.value.sessionId == null &&
            (e.value.movedTo == null ? e.key : dateKey(e.value.movedTo!)) == date,
      )
      .toList();
  if (candidates.length == 1) {
    candidates.first.value
      ..sessionId = s.id
      ..status = 'planned';
    return;
  }
  if (candidates.isNotEmpty || c.events.containsKey(date)) return;
  final st = cycleStatus(c, s.startedAt);
  if (!st.running || c.schedule[st.dayInMicro] != s.templateId) return;
  c.events[date] = DayEvent(templateId: s.templateId!, sessionId: s.id);
}

/// RP hypertrophy volume landmarks (weekly sets per muscle), as stated in the linked RP articles. Back's MRV is
/// only in an image in its article, so it is not provided.
class Landmark {
  final String mv, mev, mav, mrv, url;
  const Landmark(this.mv, this.mev, this.mav, this.url, [this.mrv = 'Not provided']);

  /// A landmark as (low, high) weekly sets: "6–8" → (6, 8), "4" → (4, 4); null when not provided.
  static (double, double)? range(String text) {
    final numbers = RegExp(r'\d+(?:\.\d+)?').allMatches(text).map((m) => double.parse(m[0]!)).toList();
    if (numbers.isEmpty) return null;
    return (numbers.first, numbers.last);
  }

  (double, double)? get mevRange => range(mev);
  (double, double)? get mavRange => range(mav);
  (double, double)? get mrvRange => range(mrv);
}

const rpLandmarks = <String, Landmark>{
  'Back': Landmark('2–6', '6–8', '8–20', 'https://rpstrength.com/blogs/articles/back-hypertrophy-training-tips'),
  'Quads': Landmark(
    '2–4',
    '4–6',
    '6–14',
    'https://rpstrength.com/blogs/articles/quad-hypertrophy-training-tips',
    '14–18',
  ),
  'Hamstrings': Landmark(
    '0–2',
    '2–4',
    '2–8',
    'https://rpstrength.com/blogs/articles/hamstring-hypertrophy-training-tips',
    '8–14',
  ),
  'Glutes': Landmark(
    '2–6',
    '6–8',
    '8–24',
    'https://rpstrength.com/blogs/articles/glute-hypertrophy-training-tips',
    '24–30',
  ),
  'Chest': Landmark(
    '2–4',
    '4–6',
    '6–16',
    'https://rpstrength.com/blogs/articles/chest-hypertrophy-training-tips',
    '16–24',
  ),
  'Front Delts': Landmark(
    '0–2',
    '0–2',
    '4–8',
    'https://rpstrength.com/blogs/articles/front-delt-hypertrophy-training-tips',
    '8–12',
  ),
  'Side Delts': Landmark(
    '2–6',
    '6–8',
    '8–24',
    'https://rpstrength.com/blogs/articles/side-delt-hypertrophy-training-tips',
    '24–30',
  ),
  'Rear Delts': Landmark(
    '0–4',
    '0–4',
    '4–12',
    'https://rpstrength.com/blogs/articles/rear-delt-hypertrophy-training-tips',
    '12–20',
  ),
  'Biceps': Landmark(
    '6–8',
    '8–10',
    '14–20',
    'https://rpstrength.com/blogs/articles/bicep-hypertrophy-training-tips',
    '20–26',
  ),
  'Triceps': Landmark(
    '0–4',
    '4–6',
    '6–16',
    'https://rpstrength.com/blogs/articles/triceps-hypertrophy-training-tips',
    '16–20',
  ),
  'Calves': Landmark(
    '2–4',
    '4–6',
    '6–16',
    'https://rpstrength.com/blogs/articles/calves-hypertrophy-training-tips',
    '16–24',
  ),
  'Abs': Landmark('0–4', '0–4', '4–12', 'https://rpstrength.com/blogs/articles/ab-hypertrophy-training-tips', '12–20'),
  'Traps': Landmark(
    '0–4',
    '0–4',
    '4–12',
    'https://rpstrength.com/blogs/articles/trap-hypertrophy-training-tips',
    '12–20',
  ),
  'Forearms': Landmark(
    '0–4',
    '0–8',
    '8–24',
    'https://rpstrength.com/blogs/articles/forearm-hypertrophy-training-tips',
    '24–30',
  ),
};

/// (MEV, MAV) per muscle, kept for callers that only need those two.
final volumeLandmarks = <String, (String, String)>{
  for (final e in rpLandmarks.entries) e.key: (e.value.mev, e.value.mav),
};

/// Net coaching change to one exercise's working sets in one workout of this cycle.
/// Only changes of microcycle [micro] (default: the running one) and earlier count, so a set ramp planned for
/// later weeks does not show before its week.
int setAdjustmentFor(Mesocycle c, String templateId, String exercise, {int? micro}) {
  final upTo = micro ?? cycleStatus(c).currentMicro;
  return c.setAdjustments
      .where((a) => a.templateId == templateId && a.micro <= upTo && sameExercise(a.exercise, exercise))
      .fold(0, (n, a) => n + a.delta);
}

/// The saved workout with this cycle's set adjustments applied: added sets copy the last working set, removed
/// ones come off the end, and one working set always remains. The saved workout itself is never changed.
/// Exercises swapped for the cycle ([Mesocycle.swaps]) appear under their replacement, without the original's
/// load and rep defaults, in the exercise list and in any superset.
WorkoutTemplate plannedTemplate(Mesocycle c, WorkoutTemplate t, {int? micro}) {
  final swaps = {
    for (final x in c.swaps)
      if (x.templateId == t.id) x.from.trim().toLowerCase(): x.to,
  };
  if (swaps.isEmpty && !c.setAdjustments.any((a) => a.templateId == t.id && a.delta != 0)) return t;
  final used = <String>{};
  String nameOf(String name) => swaps[name.trim().toLowerCase()] ?? name;
  return WorkoutTemplate(
    id: t.id,
    name: t.name,
    description: t.description,
    setSeconds: t.setSeconds,
    setOverhead: t.setOverhead,
    transition: t.transition,
    sessionOverhead: t.sessionOverhead,
    circuits: swaps.isEmpty
        ? t.circuits
        : [
            for (final g in t.circuits)
              ExerciseCircuit(id: g.id, exercises: [for (final n in g.exercises) nameOf(n)], rest: g.rest),
          ],
    exercises: [
      for (final e in t.exercises)
        () {
          final name = nameOf(e.name), swapped = name != e.name;
          final delta = used.add(name.toLowerCase()) ? setAdjustmentFor(c, t.id, name, micro: micro) : 0;
          if (!swapped && (delta == 0 || e.workSets == 0)) return e;
          final sets = [
            for (final s in e.sets)
              swapped
                  ? (s.copy()
                      ..weight = null
                      ..reps = null
                      ..context = null)
                  : s.copy(),
          ];
          if (e.workSets == 0) return TemplateExercise(name: name, method: e.method, sets: sets);
          for (var i = 0; i < delta; i++) {
            sets.add(sets.last.copy()..groupStart = false);
          }
          for (var i = 0; i > delta && sets.where((s) => !isWarmup(s.type)).length > 1; i--) {
            sets.removeLast();
          }
          return TemplateExercise(name: name, method: e.method, sets: sets);
        }(),
    ],
  );
}

/// Planned work per seven days for the repeating schedule. Weekly sets count direct (primary) sets as 1 and
/// indirect (secondary) as 0.5, with special methods in straight-set equivalents ([VolumeMetrics.sets]).
class WeeklyVolume {
  final VolumeMetrics direct;
  final VolumeMetrics indirect;

  /// Scheduled days with direct working sets, averaged per seven days.
  final double directDaysPerWeek;
  WeeklyVolume(this.direct, this.indirect, {this.directDaysPerWeek = 0});
  double get sets => countedSets();
  double countedSets({bool includePartialSets = true}) => direct.sets + (includePartialSets ? 0.5 * indirect.sets : 0);
}

Map<String, WeeklyVolume> plannedWeeklyVolume(
  Mesocycle c,
  Map<String, WorkoutTemplate> templates,
  (List<String>, List<String>) Function(String exercise) musclesOf, {
  int? micro,
}) {
  final rows = <VolumeRow>[];
  final directDays = <String, int>{};
  for (final MapEntry(key: day, value: id) in c.schedule.entries) {
    final saved = templates[id];
    if (saved == null) continue;
    final t = plannedTemplate(c, saved, micro: micro);
    final trained = <String>{};
    for (final (i, e) in t.exercises.indexed) {
      final (primary, secondary) = musclesOf(e.name);
      if (e.workSets > 0) trained.addAll(primary);
      for (final s in e.sets) {
        rows.add(
          VolumeRow(
            scope: '$day/$i',
            type: s.type,
            active: true,
            groupStart: s.groupStart,
            primary: primary,
            secondary: secondary,
          ),
        );
      }
    }
    for (final muscle in trained) {
      directDays.update(muscle, (days) => days + 1, ifAbsent: () => 1);
    }
  }
  final report = summarizeVolume(rows);
  final factor = 7 / math.max(1, c.microDays);
  return {
    for (final m in {...report.direct.keys, ...report.indirect.keys})
      m: WeeklyVolume(
        (report.direct[m] ?? VolumeMetrics()).scaled(factor),
        (report.indirect[m] ?? VolumeMetrics()).scaled(factor),
        directDaysPerWeek: (directDays[m] ?? 0) * factor,
      ),
  };
}
