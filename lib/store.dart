import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'data/seed.dart';
import 'logic/achievements.dart';
import 'logic/circuits.dart';
import 'logic/bodyweight.dart';
import 'logic/cycle.dart';
import 'logic/cycle_review.dart';
import 'logic/estimate.dart';
import 'logic/legacy_import.dart';
import 'logic/methods.dart';
import 'logic/numbers.dart';
import 'logic/plates.dart';
import 'logic/progression.dart';
import 'logic/snapshots.dart';
import 'logic/volume.dart';
import 'logic/warmup.dart';
import 'models.dart';

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

  /// Whether the app is on screen; the live timer is only shown outside the app.
  void setForeground(bool foreground) {}

  /// Foreground rest-over feedback: haptics and optional sound.
  void restDone({required bool haptics, required bool sound}) {}
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
  });
}

/// Best completed working set of an exercise in history, in the current unit.
typedef LiftBest = ({double weight, double e1rm});
typedef PlannedLoadIncrease = ({double load, double previous, double increase});

/// One automatic backup: when it was taken and what it holds (-1 when the file cannot be read).
typedef BackupInfo = ({DateTime at, File file, int sessions, int workouts});

class AppStore extends ChangeNotifier {
  AppStore({File? file, Alerts? alerts})
    // ignore: prefer_initializing_formals
    : _file = file,
      alerts = alerts ?? NoAlerts();

  final File? _file;
  final Alerts alerts;
  Timer? _saveDebounce;

  Settings settings = Settings();
  List<WorkoutTemplate> templates = [];
  List<Exercise> exercises = [];
  List<Session> history = [];
  List<Mesocycle> cycles = [];
  List<BodyweightEntry> bodyweights = [];
  Set<String> _seenAchievements = {};
  Session? active;
  RestTimer? rest;

  /// Bumped when a set is completed, so the UI can play its confetti.
  int setCelebration = 0;

  /// Set when the data file could not be read at launch: the path of the copy kept aside, so the UI can
  /// tell the user and offer to save it. Cleared once shown.
  String? unreadableCopy;

  Future<void> load() async {
    final file = _file;
    if (file != null && await file.exists()) {
      try {
        _fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
        _syncAlerts();
        notifyListeners();
        _dailySnapshot(); // only after a good load: never let fresh data replace a real copy
        return;
      } catch (e) {
        debugPrint('gymer: unreadable data file, keeping a copy: $e');
        final copy = '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
        await file.copy(copy);
        unreadableCopy = copy;
      }
    }
    exercises = List.of(seedExercises);
    templates = seedTemplates();
    notifyListeners();
    await _persist();
  }

  /// Parses everything before replacing anything, so a file that fails halfway leaves the current data
  /// untouched instead of half-replaced.
  void _fromJson(Map<String, dynamic> j) {
    final newSettings = Settings.fromJson(j['settings'] as Map<String, dynamic>? ?? {});
    final newTemplates = [
      for (final t in j['templates'] as List? ?? []) WorkoutTemplate.fromJson(t as Map<String, dynamic>),
    ];
    final newExercises = [for (final e in j['exercises'] as List? ?? []) Exercise.fromJson(e as Map<String, dynamic>)];
    final newHistory = [for (final s in j['history'] as List? ?? []) Session.fromJson(s as Map<String, dynamic>)];
    // A provisional cycle abandoned during its first calendar setup is discarded.
    final newCycles = [for (final c in j['cycles'] as List? ?? []) Mesocycle.fromJson(c as Map<String, dynamic>)]
      ..removeWhere((c) => !c.setupComplete);
    final newActive = j['active'] == null ? null : Session.fromJson(j['active'] as Map<String, dynamic>);
    final newBodyweights = <String, BodyweightEntry>{
      for (final entry in j['bodyweights'] as List? ?? [])
        dateKey(DateTime.parse((entry as Map<String, dynamic>)['date'] as String)): BodyweightEntry.fromJson(entry),
    }.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final r = j['rest'];
    final newRest = r == null || newActive == null ? null : RestTimer.fromJson(r as Map<String, dynamic>);
    final seen = j['seenAchievements'];
    final newSeen = seen is List
        ? seen.whereType<String>().toSet()
        : {
            for (final p in achievementProgress(newHistory))
              if (p.earned) p.achievement.id,
          };
    settings = newSettings;
    templates = newTemplates;
    exercises = newExercises;
    history = newHistory;
    cycles = newCycles;
    active = newActive;
    bodyweights = newBodyweights;
    rest = newRest;
    _seenAchievements = newSeen;
  }

  Map<String, dynamic> toJson() => {
    'version': 3,
    'settings': settings.toJson(),
    'templates': templates.map((t) => t.toJson()).toList(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'history': history.map((s) => s.toJson()).toList(),
    'cycles': cycles.map((c) => c.toJson()).toList(),
    if (bodyweights.isNotEmpty) 'bodyweights': bodyweights.map((e) => e.toJson()).toList(),
    if (_seenAchievements.isNotEmpty) 'seenAchievements': _seenAchievements.toList()..sort(),
    'active': active?.toJson(),
    'rest': rest?.toJson(),
  };

  /// Saves run one after another: an autosave and the save on leaving the app must never write the
  /// temporary file at the same time.
  Future<void> _saving = Future.value();

  Future<void> _persist() => _saving = _saving.then((_) => _write()).catchError((Object e) {
    debugPrint('gymer: save failed: $e');
  });

  Future<void> _write() async {
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);
    await tmp.rename(file.path);
  }

  /// Call after mutating any model object in place.
  void changed() {
    notifyListeners();
    if (_file == null) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _persist);
  }

  Future<void> flush() async {
    _saveDebounce?.cancel();
    await _persist();
  }

  void _syncAlerts() {
    alerts.keepAwake(active != null && settings.keepAwake);
    final r = rest;
    final notice = settings.restNotice;
    final alarm = notice == 'alarm' || notice == 'both';
    if (r != null && alarm && !r.overdue) {
      alerts.scheduleRest(r.endsAt, r.exercise);
    } else {
      alerts.cancelRest();
    }
    if (r != null && active != null && (notice == 'live' || notice == 'both')) {
      // With both, the alarm replaces the live timer when rest ends (one notification at a time);
      // the sticky timer alone keeps counting into overtime.
      alerts.showLiveRest(
        r.endsAt,
        r.exercise,
        endAtZero: alarm,
        // Defaults unless the user turned on custom icons (their picks are kept either way).
        icon: settings.customIcons ? settings.restIcon : 'muscle',
        overtimeIcon: settings.customIcons ? settings.overtimeIcon : 'warning',
        chipText: settings.chipMode == 'text' ? settings.chipText : '',
        vibrate: settings.restHaptics,
      );
    } else {
      alerts.clearLiveRest();
    }
  }

  // ---------------------------------------------------------------- Settings

  void updateSettings(void Function(Settings s) edit) {
    final before = settings.unit;
    final trackedBodyweight = settings.trackBodyweight;
    edit(settings);
    if (settings.unit != before) _convertAllWeights(before, settings.unit);
    if (!trackedBodyweight && settings.trackBodyweight && active?.bodyweight == null) _refreshActiveBodyweight();
    _syncAlerts();
    changed();
  }

  /// Like storage.convert_all_weights: every stored load follows the unit,
  /// rounded to two decimals with conversion noise snapped away.
  void _convertAllWeights(String from, String to) {
    double? c(double? w, String src) =>
        w == null ? null : double.parse(snapWeight(convertWeight(w, src, to)).toStringAsFixed(2));

    void session(Session s) {
      final src = s.unit;
      if (src == to) return;
      for (final e in [...s.exercises, ...s.warmupExercises]) {
        for (final set in e.sets) {
          set
            ..weight = c(set.weight, src)
            ..hintWeight = c(set.hintWeight, src);
        }
      }
      s.unit = to;
      s.bodyweight = c(s.bodyweight, src);
    }

    history.forEach(session);
    if (active != null) session(active!);
    for (final t in templates) {
      for (final e in t.exercises) {
        for (final s in e.sets) {
          s.weight = c(s.weight, from);
        }
      }
    }
  }

  // ---------------------------------------------------------------- Catalog

  double? bodyweightAt(DateTime day, String unit) {
    if (!settings.trackBodyweight) return null;
    final available = bodyweights.where((e) => !e.date.isAfter(dateOnly(day))).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return available.firstOrNull?.inUnit(unit);
  }

  String? logBodyweight(DateTime day, double value) {
    if (!settings.trackBodyweight) return 'Enable bodyweight tracking in Settings first.';
    if (!value.isFinite || value <= 0) return 'Enter a bodyweight greater than zero.';
    if (dateOnly(day).isAfter(dateOnly(DateTime.now()))) return 'Choose today or an earlier date.';
    final entry = BodyweightEntry(day, convertWeight(value, settings.unit, 'kg'));
    bodyweights = [...bodyweights.where((e) => dateKey(e.date) != dateKey(day)), entry]
      ..sort((a, b) => a.date.compareTo(b.date));
    _refreshActiveBodyweight();
    changed();
    return null;
  }

  void removeBodyweight(DateTime day) {
    bodyweights.removeWhere((e) => dateKey(e.date) == dateKey(day));
    _refreshActiveBodyweight();
    changed();
  }

  void _refreshActiveBodyweight() {
    final session = active;
    if (session != null && settings.trackBodyweight) session.bodyweight = bodyweightAt(session.startedAt, session.unit);
  }

  Exercise? exercise(String name) {
    final key = name.trim().toLowerCase();
    for (final e in exercises) {
      if (e.name.toLowerCase() == key) return e;
    }
    return null;
  }

  Exercise addExercise(String name) {
    final existing = exercise(name);
    if (existing != null) return existing;
    final e = Exercise(name: name.trim(), loadMode: defaultLoadModeFor(name));
    exercises = [...exercises, e]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    changed();
    return e;
  }

  void toggleExerciseFavourite(String name) {
    final current = exercise(name);
    if (current == null) return;
    exercises = [for (final e in exercises) e == current ? e.copyWith(favourite: !e.favourite) : e];
    changed();
  }

  /// Recently performed exercises, newest session first, without duplicates.
  List<String> recentExercises() {
    final sessions = [...history]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final seen = <String>{};
    return [
      for (final session in sessions)
        for (final e in session.exercises)
          if (e.sets.any((s) => s.done) && exercise(e.name) != null && seen.add(e.name.toLowerCase())) e.name,
    ];
  }

  /// Names of saved workouts that use [name]; such an exercise cannot be deleted.
  List<String> workoutsUsing(String name) => [
    for (final t in templates)
      if (t.exercises.any((e) => e.name.toLowerCase() == name.toLowerCase())) t.name,
    if (active?.exercises.any((e) => e.name.toLowerCase() == name.toLowerCase()) ?? false) active!.name,
  ];

  bool inHistory(String name) => history.any((s) => s.exercises.any((e) => e.name.toLowerCase() == name.toLowerCase()));

  void deleteExercise(String name) {
    exercises.removeWhere((e) => e.name == name);
    changed();
  }

  /// Saves details; a new name is applied everywhere the exercise appears.
  /// Returns an error message when the new name is taken.
  String? saveExercise(Exercise updated, {String? oldName}) {
    final from = oldName ?? updated.name;
    if (from.toLowerCase() != updated.name.toLowerCase() && exercise(updated.name) != null) {
      return 'An exercise with that name already exists.';
    }
    final previous = exercise(from);
    exercises = [for (final x in exercises) x.name == from ? updated : x]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (from != updated.name) {
      for (final t in templates) {
        renameCircuitExercise(t.circuits, from, updated.name);
        for (final e in t.exercises) {
          if (e.name == from) e.name = updated.name;
        }
      }
      for (final s in [...history, ?active]) {
        renameCircuitExercise(s.circuits, from, updated.name);
        if (s.warmupExercise == from) s.warmupExercise = updated.name;
        for (final e in [...s.exercises, ...s.warmupExercises]) {
          if (e.name == from) e.name = updated.name;
        }
      }
      if (rest?.exercise == from) rest = rest!.copyWith(exercise: updated.name);
    }
    // A new default context clears inherited template defaults that no longer match.
    if (previous != null && previous.context != updated.context) {
      for (final t in templates) {
        for (final e in t.exercises.where((e) => e.name == updated.name)) {
          for (final s in e.sets.where((s) => s.context == null)) {
            s
              ..weight = null
              ..reps = null;
          }
        }
      }
    }
    changed();
    return null;
  }

  /// Configured jump for this exercise in [unit]: per-exercise, then equipment.
  double? incrementFor(String name, String unit) {
    final e = exercise(name);
    final own = unit == 'lb' ? e?.incrementLb : e?.incrementKg;
    if (own != null) return own;
    final eq = settings.increments[e?.equipment ?? ''];
    return eq == null ? null : (unit == 'lb' ? eq.$2 : eq.$1);
  }

  /// Whether [name] is loaded with plates (barbell or plate-loaded), so the plate calculator applies.
  bool platesApply(String name) => usesPlates(exercise(name)?.equipment ?? '');

  /// Plates for [target] on [name]'s bar: its own bar weight, else none for plate-loaded machines (the
  /// sled is usually not counted) and the default bar for barbells.
  PlatePlan plates(double target, {String? name}) {
    final unit = settings.unit;
    final e = name == null ? null : exercise(name);
    final own = unit == 'lb' ? e?.barLb : e?.barKg;
    final bar = own ?? (e?.equipment == 'Plate loaded' ? 0.0 : settings.bar);
    return planPlates(target, bar, settings.plates, pairs: settings.platePairs);
  }

  void addSetType(String name) {
    final n = name.trim();
    if (n.isEmpty || settings.setTypes.any((t) => t.toLowerCase() == n.toLowerCase())) return;
    settings.setTypes.add(n);
    changed();
  }

  void removeSetType(String name) {
    settings.setTypes.remove(name);
    changed();
  }

  // ---------------------------------------------------------------- Templates

  WorkoutTemplate newTemplate() =>
      WorkoutTemplate(id: 'W${DateTime.now().microsecondsSinceEpoch}', name: '', exercises: []);

  WorkoutTemplate? template(String? id) => templates.where((t) => t.id == id).firstOrNull;

  void saveTemplate(WorkoutTemplate t) {
    final i = templates.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      templates[i] = t;
    } else {
      templates = [...templates, t];
    }
    if (active?.templateId == t.id) _applyTemplateToActive(t);
    changed();
  }

  void deleteTemplate(String id) {
    templates.removeWhere((t) => t.id == id);
    changed();
  }

  SetContext contextFor(String exerciseName, TemplateSet? planned) =>
      planned?.context ?? exercise(exerciseName)?.context ?? const SetContext();

  int setSecondsFor(String exerciseName, int fallback) => exercise(exerciseName)?.setSeconds ?? fallback;

  TimingBreakdown templateTiming(WorkoutTemplate t) {
    final steps = workoutSteps([
      for (final e in t.exercises)
        SessionExercise(
          name: e.name,
          method: e.method,
          sets: [for (final s in e.sets) SetEntry(type: s.type, rest: s.rest, groupStart: s.groupStart)],
        ),
    ], t.circuits);
    return estimateWorkout(
      rows: [for (final step in steps) (step.exercise.name, step.restAfter)],
      circuitIds: [for (final step in steps) circuitFor(t.circuits, step.exercise.name)?.id],
      setSeconds: (n) => setSecondsFor(n, t.setSeconds),
      setOverhead: t.setOverhead,
      transition: t.transition,
      sessionOverhead: t.sessionOverhead,
    );
  }

  int estimateActiveSeconds() {
    final s = active;
    if (s == null) return 0;
    final t = template(s.templateId) ?? WorkoutTemplate(id: '', name: '', exercises: []);
    final steps = sessionSteps(s);
    return estimateWorkout(
      rows: [for (final step in steps) (step.exercise.name, step.restAfter)],
      circuitIds: [for (final step in steps) circuitFor(s.circuits, step.exercise.name)?.id],
      setSeconds: (n) => setSecondsFor(n, t.setSeconds),
      setOverhead: t.setOverhead,
      transition: t.transition,
      sessionOverhead: t.sessionOverhead,
    ).total;
  }

  // ---------------------------------------------------------------- Mesocycles

  Mesocycle? get activeCycle => cycles.where((c) => c.active && c.setupComplete).firstOrNull;

  /// The running cycle and its status on [at], if any.
  (Mesocycle, CycleStatus)? cycleContext([DateTime? at]) {
    final c = activeCycle;
    if (c == null) return null;
    final st = cycleStatus(c, at);
    return st.running ? (c, st) : null;
  }

  /// Saving or continuing a cycle makes it the single active one.
  void saveCycle(Mesocycle c) {
    if (!cycles.any((x) => x.id == c.id)) cycles = [...cycles, c];
    for (final x in cycles) {
      if (x.active && x.id != c.id) x.endedAt ??= dateOnly(DateTime.now());
      x.active = x.id == c.id;
    }
    c.endedAt = null;
    changed();
  }

  /// A new cycle is provisional until Start is pressed with a scheduled day.
  Mesocycle? get pendingCycle => cycles.where((c) => !c.setupComplete).firstOrNull;

  void beginCycleSetup(Mesocycle c) {
    cycles.removeWhere((x) => !x.setupComplete);
    c
      ..setupComplete = false
      ..active = false;
    cycles = [...cycles, c];
    changed();
  }

  /// Returns an error when no workout day is assigned yet.
  String? startPendingCycle() {
    final c = pendingCycle;
    if (c == null) return null;
    if (c.schedule.isEmpty) return 'Assign at least one workout day before starting the mesocycle.';
    c.setupComplete = true;
    saveCycle(c);
    return null;
  }

  /// Leaving setup before Start cancels the new cycle. Returns true if one was dropped.
  bool cancelPendingCycle() {
    final had = pendingCycle != null;
    if (had) {
      cycles.removeWhere((c) => !c.setupComplete);
      changed();
    }
    return had;
  }

  void endCycle(Mesocycle c) {
    c
      ..active = false
      ..endedAt = dateOnly(DateTime.now());
    changed();
  }

  List<Session> _cycleSessions(Mesocycle cycle) {
    final linked = {for (final event in cycle.events.values) ?event.sessionId};
    return history.where((s) => (s.cycleId == cycle.id || linked.contains(s.id)) && s.doneSets > 0).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }

  CycleSummary summarizeCycle(Mesocycle cycle, {DateTime? at}) {
    final sessions = _cycleSessions(cycle);
    final status = cycleStatus(cycle);
    final today = dateOnly(at ?? DateTime.now());
    var end = cycle.endedAt ?? status.end;
    if (end.isAfter(status.end)) end = status.end;
    if (end.isAfter(today)) end = today;
    final due = calendarDays(
      cycle,
      history,
    ).where((d) => d.templateId != null && !d.unplanned && !d.date.isAfter(end)).toList();
    final completed = {for (final s in sessions) s.id};
    final attended = {
      for (final d in due)
        if (completed.contains(d.sessionId)) d.sessionId,
    };
    final bests = <(String, String), PersonalBest>{};
    var records = 0;
    for (final session in sessions) {
      for (final best in summarizeSession(session).bests) {
        records++;
        bests[(best.exercise.toLowerCase(), best.kind)] = best;
      }
    }
    return CycleSummary(
      unit: settings.unit,
      start: dateOnly(cycle.start),
      end: end.isBefore(cycle.start) ? dateOnly(cycle.start) : end,
      workouts: sessions.length,
      attended: attended.length,
      scheduled: due.length,
      sets: sessions.fold(0, (n, s) => n + s.doneSets),
      records: records,
      duration: sessions.fold(Duration.zero, (total, s) => total + s.duration),
      bests: bests.values.toList(),
      strength: cycleStrengthChanges(cycle, sessions, settings.unit),
    );
  }

  /// A detached draft: no shared maps, calendar events, template changes or activation until Start.
  Mesocycle cloneCycle(Mesocycle source, {DateTime? start, int loadPercent = 100}) {
    final json = source.toJson();
    final match = RegExp(r'^(.*) · (\d+)$').firstMatch(source.name);
    json
      ..['id'] = 'C${DateTime.now().microsecondsSinceEpoch}'
      ..['name'] = match == null ? '${source.name} · 2' : '${match.group(1)} · ${int.parse(match.group(2)!) + 1}'
      ..['start'] = dateKey(start ?? DateTime.now())
      ..['active'] = false
      ..['setupComplete'] = false
      ..['events'] = <String, dynamic>{}
      ..remove('endedAt')
      ..remove('startingLoads');
    final draft = Mesocycle.fromJson(json);
    draft.schedule.removeWhere((_, id) => template(id) == null);
    draft
      ..startingLoadUnit = settings.unit
      ..startingLoads = cycleStartingLoads(source, loadPercent: loadPercent);
    return draft;
  }

  /// Last compatible build loads of this cycle; absent loads stay unknown and are never guessed.
  Map<String, List<SessionExercise>> cycleStartingLoads(Mesocycle source, {int loadPercent = 100}) {
    if (loadPercent <= 0 || loadPercent > 200) throw ArgumentError.value(loadPercent, 'loadPercent');
    final sessions = _cycleSessions(source).reversed.where(
      (s) => s.phase == 'Build' || (s.phase == null && cycleStatus(source, s.startedAt).phase == 'Build'),
    );
    double? scaled(String name, double? weight) {
      if (weight == null || weight <= 0) return null;
      final target = weight * loadPercent / 100;
      if (platesApply(name)) {
        final plan = plates(target, name: name);
        return plan.exact?.total ?? plan.below?.total ?? plan.above?.total;
      }
      final step = incrementFor(name, settings.unit) ?? practicalWeightStep(target, settings.unit, null);
      return snapWeight(math.max(step, (target / step + 1e-9).floor() * step));
    }

    final result = <String, List<SessionExercise>>{};
    for (final id in source.schedule.values.toSet()) {
      final plan = template(id);
      if (plan == null) continue;
      final exercises = <SessionExercise>[];
      for (final planned in plan.exercises) {
        final mode = exercise(planned.name)?.loadMode ?? defaultLoadModeFor(planned.name);
        final method = canonicalMethod(planned.method);
        if (mode != 'external' || method == 'Mechanical Drop Set') continue;
        SessionExercise? reference;
        String? unit;
        for (final session in sessions.where((s) => s.templateId == id)) {
          reference = session.exercises
              .where(
                (e) =>
                    e.name.toLowerCase() == planned.name.toLowerCase() &&
                    e.method == method &&
                    e.loadMode == mode &&
                    e.sets.length == planned.sets.length &&
                    planned.sets.indexed.every((entry) {
                      final previous = e.sets[entry.$1];
                      final set = entry.$2;
                      return canonicalSetType(previous.type) == canonicalSetType(set.type) &&
                          previous.groupStart == set.groupStart &&
                          previous.context == contextFor(planned.name, set);
                    }) &&
                    e.work.any((s) => s.done && (s.weight ?? 0) > 0),
              )
              .firstOrNull;
          if (reference != null) {
            unit = session.unit;
            break;
          }
        }
        final sets = <SetEntry>[];
        for (final (i, set) in planned.sets.indexed) {
          final context = contextFor(planned.name, set);
          final previous = reference != null && i < reference.sets.length ? reference.sets[i] : null;
          final compatible =
              previous != null &&
              previous.done &&
              previous.context == context &&
              canonicalSetType(previous.type) == canonicalSetType(set.type) &&
              previous.groupStart == set.groupStart;
          final weight = compatible
              ? convertWeight(previous.weight ?? 0, unit!, settings.unit)
              : reference == null
              ? set.weight
              : null;
          sets.add(
            SetEntry(
              type: set.type,
              groupStart: set.groupStart,
              rest: set.rest,
              context: context,
              weight: isWarmup(set.type) ? null : scaled(planned.name, weight),
            ),
          );
        }
        if (sets.any((s) => s.weight != null)) {
          exercises.add(SessionExercise(name: planned.name, method: method, loadMode: mode, sets: sets));
        }
      }
      if (exercises.isNotEmpty) result[id] = exercises;
    }
    return result;
  }

  void deleteCycle(Mesocycle c) {
    cycles.removeWhere((x) => x.id == c.id);
    changed();
  }

  /// Adds microcycles to the build phase of [c] (before its deload).
  void extendCycle(Mesocycle c, int microcycles) {
    if (microcycles <= 0) return;
    final build = c.length - c.deloadMicro;
    c
      ..weekRir = {for (final e in c.weekRir.entries) (e.key > build ? e.key + microcycles : e.key): e.value}
      ..length += microcycles;
    changed();
  }

  /// A reusable demo: three workouts on days 1, 3 and 5, started last week.
  Mesocycle openDemoCycle() {
    final existing = cycles.where((c) => c.name == 'Demo cycle').firstOrNull;
    if (existing != null) return existing;
    var n = 0;
    String make(String name, List<(String, int)> lifts) {
      final t = WorkoutTemplate(
        id: 'W${DateTime.now().microsecondsSinceEpoch}${n++}',
        name: name,
        exercises: [
          for (final (lift, reps) in lifts)
            TemplateExercise(
              name: addExercise(lift).name,
              sets: [for (var i = 0; i < 3; i++) TemplateSet(reps: reps, rest: settings.defaultRest)],
            ),
        ],
      );
      templates = [...templates, t];
      return t.id;
    }

    final push = make('Demo Push', [('Bench Press', 8), ('Shoulder Press', 10), ('Triceps Pushdown', 12)]);
    final pull = make('Demo Pull', [('Lat Pulldown', 10), ('Machine Row', 10), ('Biceps Curl', 12)]);
    final legs = make('Demo Legs', [('Squat', 8), ('Romanian Deadlift', 10), ('Leg Curl', 12)]);
    final today = dateOnly(DateTime.now());
    final c = Mesocycle(
      id: 'C${DateTime.now().microsecondsSinceEpoch}',
      name: 'Demo cycle',
      start: addDays(today, -(today.weekday - 1) - 7),
      active: activeCycle == null,
      schedule: {1: push, 3: pull, 5: legs},
    );
    cycles = [...cycles, c];
    changed();
    return c;
  }

  // ---------------------------------------------------------------- Session building

  SetEntry _inUnit(SetEntry s, String from, [String? to]) => SetEntry(
    weight: s.weight == null ? null : convertWeight(s.weight!, from, to ?? settings.unit),
    reps: s.reps,
    rir: s.rir,
    done: s.done,
    type: s.type,
    rest: s.rest,
    groupStart: s.groupStart,
    context: s.context,
    stopReason: s.stopReason,
    actualRest: s.actualRest,
    circuitRestAfter: s.circuitRestAfter,
  );

  /// Latest values of [exercise] by set position in sessions of [templateId]
  /// (storage.latest_set_values); deload sessions are skipped.
  List<SetEntry>? _latestSetValues(String exercise, String? templateId, {bool anyWorkout = false}) {
    for (final s in history) {
      if (s.phase == 'Deload') continue;
      if (!anyWorkout && s.templateId != templateId) continue;
      final e = s.exercises.where((e) => e.name.toLowerCase() == exercise.toLowerCase()).firstOrNull;
      if (e == null || !e.sets.any((x) => x.done)) continue;
      return [for (final set in e.sets) _inUnit(set, s.unit)];
    }
    return null;
  }

  // Previous-set and record lookups run on every rebuild of the workout, so
  // they are cached until the history (or the display unit) changes.
  int _historyVersion = 0;
  Object? _historyCacheKey;
  final _previousCache = <String, List<SetEntry>?>{};
  final _bestCache = <String, LiftBest?>{};
  final _comparisonCache = <(String, String, String, String?, DateTime), List<SetEntry>?>{};

  void _syncHistoryCaches() {
    final key = (identityHashCode(history), history.length, settings.unit, _historyVersion);
    if (key == _historyCacheKey) return;
    _historyCacheKey = key;
    _previousCache.clear();
    _bestCache.clear();
    _comparisonCache.clear();
  }

  /// What was done last time, set by set: same workout first, else any workout.
  List<SetEntry>? lastTimeSets(String exercise, String? templateId) {
    _syncHistoryCaches();
    return _previousCache.putIfAbsent(
      '${exercise.toLowerCase()}|$templateId',
      () => _latestSetValues(exercise, templateId) ?? _latestSetValues(exercise, null, anyWorkout: true),
    );
  }

  /// A load comparison, never a strength claim. Roles align by working-set position, not warm-up count.
  PlannedLoadIncrease? plannedLoadIncrease(SessionExercise exercise, int index) {
    if (active == null ||
        index < 0 ||
        index >= exercise.sets.length ||
        active?.phase == 'Deload' ||
        !const {'external', 'bodyweight'}.contains(exercise.loadMode)) {
      return null;
    }
    final set = exercise.sets[index];
    final load = set.weight ?? set.hintWeight;
    if (set.done || set.warmup || load == null || !load.isFinite || load <= 0) return null;
    _syncHistoryCaches();
    final previous = _comparisonCache.putIfAbsent(
      (exercise.name.toLowerCase(), exercise.method, exercise.loadMode, active?.templateId, active!.startedAt),
      () {
        List<SetEntry>? fallback;
        final ordered = [...history]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
        for (final session in ordered) {
          if (session.phase == 'Deload' || !session.startedAt.isBefore(active!.startedAt)) continue;
          final past = session.exercises
              .where(
                (e) =>
                    e.name.toLowerCase() == exercise.name.toLowerCase() &&
                    e.method == exercise.method &&
                    e.loadMode == exercise.loadMode &&
                    e.work.any((s) => s.done),
              )
              .firstOrNull;
          if (past == null) continue;
          final sets = [for (final s in past.work) _inUnit(s, session.unit)];
          if (session.templateId == active?.templateId) return sets;
          fallback ??= sets;
        }
        return fallback;
      },
    );
    final position = exercise.sets.take(index).where((s) => !s.warmup).length;
    if (previous == null || position >= previous.length) return null;
    final last = previous[position];
    if (!last.done ||
        last.weight == null ||
        !last.weight!.isFinite ||
        last.weight! < 0 ||
        (exercise.loadMode == 'external' && last.weight == 0) ||
        last.context != set.context ||
        canonicalSetType(last.type) != canonicalSetType(set.type) ||
        last.groupStart != set.groupStart) {
      return null;
    }
    final increase = load - last.weight!;
    return increase > 0.005 ? (load: load, previous: last.weight!, increase: increase) : null;
  }

  /// Heaviest weight and best Wathan e1RM over completed working sets with an
  /// external load; null without such history (a first session sets no record).
  LiftBest? bestLift(String exercise) {
    _syncHistoryCaches();
    return _bestCache.putIfAbsent(exercise.toLowerCase(), () {
      double? weight, e1rm;
      for (final s in history) {
        for (final e in s.exercises) {
          if (e.name.toLowerCase() != exercise.toLowerCase() || e.loadMode != 'external') continue;
          for (final set in e.sets) {
            if (!set.done || set.warmup) continue;
            final x = _inUnit(set, s.unit);
            final one = estimatedOneRm(x.weight ?? 0, x.reps ?? 0, 0);
            if (one == null) continue;
            weight = math.max(weight ?? 0, x.weight!);
            e1rm = math.max(e1rm ?? 0, one);
          }
        }
      }
      return weight == null ? null : (weight: weight, e1rm: e1rm!);
    });
  }

  /// 'weight' or 'e1rm' when this completed set beats every earlier session.
  String? recordKind(SessionExercise e, SetEntry s) {
    if (!s.done || s.warmup || e.loadMode != 'external') return null;
    final one = estimatedOneRm(s.weight ?? 0, s.reps ?? 0, 0);
    final best = one == null ? null : bestLift(e.name);
    if (best == null) return null;
    if (s.weight! > best.weight + 1e-9) return 'weight';
    if (one! > best.e1rm + 0.05) return 'e1rm';
    return null;
  }

  /// Rebuild a saved workout's results from the history that preceded it, in its recorded unit.
  /// Reading a summary never saves, links a calendar day or changes an active workout.
  FinishSummary summarizeSession(Session session, {List<AchievementProgress> achievements = const []}) {
    final earlier = history.where((s) => s.id != session.id && s.startedAt.isBefore(session.startedAt)).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final (bests, results) = _sessionHighlights(session, earlier);
    return FinishSummary(
      name: session.name,
      unit: session.unit,
      date: session.startedAt,
      duration: session.duration,
      sets: session.doneSets,
      volume: session.volume,
      report: sessionVolume(session),
      bests: bests,
      exercises: results,
      achievements: achievements,
    );
  }

  /// A first session of an exercise sets no record: there is nothing to beat.
  (List<PersonalBest>, List<ExerciseResult>) _sessionHighlights(Session s, List<Session> earlier) {
    final unit = s.unit;
    String w(double v) => '${formatNumber(v, NumKind.weight)} $unit';
    String total(double v) => '${groupThousands(v)} $unit';
    final bests = <PersonalBest>[];
    final results = <ExerciseResult>[];
    for (final e in s.exercises) {
      final work = [
        for (final x in e.sets)
          if (x.done && !x.warmup && (x.reps ?? 0) > 0) x,
      ];
      if (work.isEmpty) continue;
      final key = e.name.toLowerCase();
      // Earlier sessions' working sets of this exercise with the same kind of load, in today's unit.
      final past = [
        for (final h in earlier)
          for (final x in h.exercises)
            if (x.name.toLowerCase() == key && x.loadMode == e.loadMode)
              [
                for (final set in x.sets)
                  if (set.done && !set.warmup && (set.reps ?? 0) > 0) _inUnit(set, h.unit, unit),
              ],
      ].where((sets) => sets.isNotEmpty).toList();
      double oneRm(SetEntry x) => estimatedOneRm(x.weight ?? 0, x.reps!, 0) ?? 0;
      double volume(List<SetEntry> sets) => sets.fold(0.0, (a, x) => a + (x.weight ?? 0) * x.reps!);
      String? best;
      double? change;
      if (e.loadMode == 'external') {
        final top = work.reduce((a, b) => (b.weight ?? 0) > (a.weight ?? 0) ? b : a);
        final strongest = work.reduce((a, b) => oneRm(b) > oneRm(a) ? b : a);
        best = '${w(top.weight ?? 0)} × ${top.reps}';
        List<SetEntry>? previous({required bool sameWorkout}) {
          for (final h in earlier) {
            if (h.phase == 'Deload' || (sameWorkout && h.templateId != s.templateId)) continue;
            final exercise = h.exercises
                .where((x) => x.name.toLowerCase() == key && x.loadMode == e.loadMode)
                .firstOrNull;
            final sets = exercise?.work.where((x) => x.done && (x.reps ?? 0) > 0).toList();
            if (sets != null && sets.isNotEmpty) return [for (final set in sets) _inUnit(set, h.unit, unit)];
          }
          return null;
        }

        final last = previous(sameWorkout: true) ?? previous(sameWorkout: false);
        if (last != null && last.isNotEmpty && oneRm(strongest) > 0) {
          change = oneRm(strongest) - last.map(oneRm).reduce(math.max);
        }
        if (past.isNotEmpty && (top.weight ?? 0) > 0) {
          final all = past.expand((x) => x);
          final heaviest = all.map((x) => x.weight ?? 0).reduce(math.max);
          final bestRm = all.map(oneRm).reduce(math.max);
          final bestVolume = past.map(volume).reduce(math.max);
          if (top.weight! > heaviest + 1e-9) {
            bests.add(PersonalBest(e.name, 'weight', best, '+${w(top.weight! - heaviest)}'));
          }
          if (oneRm(strongest) > bestRm + 0.05) {
            final rm = oneRm(strongest);
            bests.add(PersonalBest(e.name, 'e1rm', w(_tenth(rm)), '+${w(_tenth(rm - bestRm))}'));
          }
          final v = volume(work);
          if (v > bestVolume + 0.5) {
            bests.add(PersonalBest(e.name, 'volume', total(v), '+${total(v - bestVolume)}'));
          }
        }
      } else {
        final most = work.map((x) => x.reps!).reduce(math.max);
        best = most == 1 ? '1 rep' : '$most reps';
        if (e.loadMode == 'bodyweight' && past.isNotEmpty) {
          final before = past.expand((x) => x).map((x) => x.reps!).reduce(math.max);
          if (most > before) bests.add(PersonalBest(e.name, 'reps', best, '+${most - before}'));
        }
      }
      results.add(ExerciseResult(e.name, work.length, best, change));
    }
    // The whole workout's volume against earlier sessions of the same workout.
    final earlierVolumes = [
      for (final h in earlier)
        if (h.templateId != null && h.templateId == s.templateId && h.phase != 'Deload')
          convertWeight(h.volume, h.unit, unit),
    ];
    if (earlierVolumes.isNotEmpty && s.volume > earlierVolumes.reduce(math.max) + 0.5) {
      bests.add(
        PersonalBest(s.name, 'workout', total(s.volume), '+${total(s.volume - earlierVolumes.reduce(math.max))}'),
      );
    }
    return (bests, results);
  }

  static double _tenth(double v) => (v * 10).round() / 10;

  void moveSessionExercise(SessionExercise e, int delta) {
    final session = active;
    if (session == null) return;
    final blocks = exerciseBlocks(session);
    final i = blocks.indexWhere((block) => block.contains(e));
    if (i < 0 || i + delta < 0 || i + delta >= blocks.length) return;
    blocks.insert(i + delta, blocks.removeAt(i));
    session.exercises = [
      for (final visible in blocks.expand((block) => block))
        session.exercises.firstWhere((exercise) => exercise.name == visible.name),
    ];
    changed();
  }

  /// Undo for [removeSet]: puts the same set back where it was.
  void restoreSet(SessionExercise e, int index, SetEntry set) {
    e.sets.insert(index.clamp(0, e.sets.length), set);
    _reconcileSession(e);
    e.collapsed = false;
    if (active?.isWarmupExercise(e) == true && !set.done) {
      active!
        ..warmingUp = true
        ..warmupExercise = e.name;
    }
    changed();
  }

  /// Latest completed session of this exercise and method, preferring the
  /// same workout (latest_completed_*_session).
  List<SetEntry>? _latestMethodSession(String exercise, String method, String? templateId) {
    List<SetEntry>? fallback;
    for (final s in history) {
      if (s.phase == 'Deload') continue;
      final e = s.exercises
          .where((e) => e.name.toLowerCase() == exercise.toLowerCase() && e.method == method)
          .firstOrNull;
      if (e == null || !e.sets.any((x) => x.done)) continue;
      final sets = [for (final x in e.sets) _inUnit(x, s.unit)];
      if (s.templateId == templateId) return sets;
      fallback ??= sets;
    }
    return fallback;
  }

  bool _calibrated(Mesocycle c, String? templateId, String exercise, String method) {
    for (final s in history) {
      if (s.cycleId != c.id || s.templateId != templateId || s.phase == 'Deload') continue;
      for (final e in s.exercises) {
        if (e.name.toLowerCase() != exercise.toLowerCase() || e.method != method) continue;
        if (e.sets.any(
          (x) => x.done && calibrationAnchor(method, x.type) && (x.weight ?? 0) > 0 && (x.reps ?? 0) > 0,
        )) {
          return true;
        }
      }
    }
    return false;
  }

  /// Historical reps stay hidden in mesocycles unless the setting opts in.
  bool historicalRepsVisible(Session s) => s.cycleId == null || settings.showPreviousReps;

  void startSession(WorkoutTemplate? t, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final ctx = cycleContext(now);
    final cycle = ctx?.$1;
    final status = ctx?.$2;
    final session = Session(
      id: 'S${now.microsecondsSinceEpoch}',
      templateId: t?.id,
      name: t?.name ?? 'Quick workout',
      unit: settings.unit,
      startedAt: now,
      bodyweight: bodyweightAt(now, settings.unit),
      exercises: [],
      circuits: copyCircuits(t?.circuits ?? []),
      cycleId: cycle?.id,
      microcycle: status?.currentMicro,
      phase: status?.phase,
      targetRir: status?.suggestedRir,
      rirLocked: cycle?.rirLock ?? false,
      restLocked: cycle?.restLock ?? false,
    );
    for (final te in t?.exercises ?? <TemplateExercise>[]) {
      session.exercises.add(
        status?.phase == 'Deload' ? _deloadExercise(te, cycle!, session) : _buildExercise(te, session, cycle),
      );
    }
    active = session;
    reconcileCircuits(session.circuits, session.exercises.map((e) => e.name));
    rest = null;
    _syncAlerts();
    changed();
  }

  /// The header starts the next unwarmed exercise; each exercise menu can choose explicitly.
  SessionExercise? get nextWarmupExercise {
    final session = active;
    if (session == null) return null;
    final candidates = session.exercises.where(
      (e) => e.loadMode == 'external' && !e.work.any((s) => s.done) && session.warmupFor(e.name) == null,
    );
    return candidates.where((e) => e.work.any((s) => (s.weight ?? s.hintWeight ?? 0) > 0)).firstOrNull ??
        candidates.firstOrNull;
  }

  /// Replace only this exercise's working rows with its ramp, keeping every other card visible.
  String? startWarmups({int sets = 3, String? exerciseName}) {
    final session = active;
    if (session == null) return 'Start a workout first.';
    if (sets != 2 && sets != 3) return 'Choose two or three warm-up sets.';
    final target = exerciseName == null
        ? nextWarmupExercise
        : session.exercises.where((e) => e.name == exerciseName).firstOrNull;
    if (target == null) return 'No exercise is waiting for warm-ups.';
    if (target.work.any((set) => set.done)) return 'Start warm-ups before completing this exercise’s working sets.';
    if (target.loadMode != 'external') return 'Warm-up ramps require an external working load.';
    if (session.warmupFor(target.name)?.sets.any((set) => set.done) == true) {
      return 'Warm-ups are already underway. Use Show warm-up to return to them.';
    }
    final source = target.work.where((set) => (set.weight ?? set.hintWeight ?? 0) > 0).firstOrNull;
    if (source == null) return 'Enter a working weight for ${target.name} first.';
    final usesBar = platesApply(target.name);
    final ramp = warmupRamp(
      source.weight ?? source.hintWeight!,
      sets: sets,
      increment: incrementFor(target.name, session.unit) ?? 0.5,
      bar: usesBar ? plates(source.weight ?? source.hintWeight!, name: target.name).bar : 0,
      plates: usesBar ? settings.plates : null,
      pairs: usesBar ? settings.platePairs : null,
    );
    if (ramp.isEmpty) return 'No warm-up loads are available with this plate setup.';
    session.warmupExercises.removeWhere((e) => e.name == target.name);
    session.warmupExercises.add(
      SessionExercise(
        name: target.name,
        sets: [
          for (final step in ramp)
            SetEntry(
              type: 'Warm-up',
              weight: step.weight,
              reps: step.reps,
              rest: 60,
              context: source.context,
              prescribed: true,
            ),
        ],
      ),
    );
    session
      ..warmupExercise = target.name
      ..warmingUp = true;
    _dismissRest();
    changed();
    return null;
  }

  void showWorkoutPhase({required bool warmup, String? exerciseName}) {
    final session = active;
    if (session == null || (warmup && session.warmupExercises.isEmpty)) return;
    if (warmup) {
      final target = exerciseName == null
          ? session.warmupFor(session.warmupExercise ?? '') ?? session.warmupExercises.firstOrNull
          : session.warmupFor(exerciseName);
      if (target == null) return;
      session.warmupExercise = target.name;
      target.collapsed = false;
    } else {
      final working = session.exercises.where((e) => e.name == session.activeWarmup?.name).firstOrNull;
      if (working != null && working.collapsed == true) working.collapsed = false;
    }
    session.warmingUp = warmup;
    changed();
  }

  void _finishWarmupPhase() {
    final session = active;
    final warmup = session?.activeWarmup;
    if (session != null && session.warmingUp && (warmup == null || warmup.sets.every((set) => set.done))) {
      final name = warmup?.name ?? session.warmupExercise;
      final working = session.exercises.where((e) => e.name == name).firstOrNull;
      if (working != null && working.collapsed == true) working.collapsed = false;
      session.warmingUp = false;
    }
  }

  SessionExercise _buildExercise(TemplateExercise te, Session session, Mesocycle? cycle) {
    final info = exercise(te.name);
    final loadMode = info?.loadMode ?? defaultLoadModeFor(te.name);
    final method = canonicalMethod(te.method);
    final latest = _latestSetValues(te.name, session.templateId) ?? const <SetEntry>[];
    final showReps = historicalRepsVisible(session);
    final sets = <SetEntry>[];
    for (final (i, ts) in te.sets.indexed) {
      final context = contextFor(te.name, ts);
      var prev = i < latest.length ? latest[i] : null;
      if (prev != null && (!prev.done || prev.context != context)) prev = null;
      sets.add(
        SetEntry(
          type: ts.type,
          rest: ts.rest,
          groupStart: ts.groupStart,
          context: context,
          hintWeight: prev?.weight ?? ts.weight ?? (loadMode == 'bodyweight' ? 0 : null),
          hintReps: showReps ? (prev?.reps ?? ts.reps) : null,
          targetRir: methodSetUsesRir(method, ts.type) ? session.targetRir : null,
        ),
      );
    }
    final e = SessionExercise(name: te.name, method: method, loadMode: loadMode, sets: sets);
    final starting = _cycleStartingExercise(te.name, method, session);
    if (starting != null) {
      for (final (i, set) in e.sets.indexed) {
        set.hintWeight = starting.sets[i].weight;
      }
    }
    _applyGuidance(e, session, cycle);
    return e;
  }

  /// A cloned starting plan applies only until this exercise has been trained in its new cycle.
  /// Changed methods, roles or load meaning require a fresh baseline instead of reusing an old load.
  SessionExercise? _cycleStartingExercise(String name, String method, Session session) {
    final cycle = cycles.where((c) => c.id == session.cycleId).firstOrNull;
    if (cycle == null || session.phase != 'Build') return null;
    if (history.any(
      (s) =>
          s.cycleId == cycle.id &&
          s.templateId == session.templateId &&
          s.phase != 'Deload' &&
          s.exercises.any(
            (e) => e.name.toLowerCase() == name.toLowerCase() && e.method == method && e.work.any((set) => set.done),
          ),
    )) {
      return null;
    }
    final starting = cycle.startingLoads[session.templateId]
        ?.where((e) => e.name.toLowerCase() == name.toLowerCase() && e.method == method)
        .firstOrNull;
    final plan = template(
      session.templateId,
    )?.exercises.where((e) => e.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    if (starting == null ||
        plan == null ||
        canonicalMethod(plan.method) != method ||
        starting.sets.length != plan.sets.length ||
        starting.loadMode != (exercise(name)?.loadMode ?? defaultLoadModeFor(name))) {
      return null;
    }
    for (final (i, set) in plan.sets.indexed) {
      final seed = starting.sets[i];
      if (canonicalSetType(set.type) != canonicalSetType(seed.type) ||
          set.groupStart != seed.groupStart ||
          contextFor(name, set) != seed.context) {
        return null;
      }
    }
    return SessionExercise(
      name: name,
      method: method,
      loadMode: starting.loadMode,
      sets: [for (final set in starting.sets) _inUnit(set, cycle.startingLoadUnit, session.unit)],
    );
  }

  /// Progression, calibration and the advice lines shown under an exercise.
  void _applyGuidance(SessionExercise e, Session session, Mesocycle? cycle) {
    final info = exercise(e.name);
    final method = e.method;
    final inBuild = cycle != null && session.phase == 'Build';
    final contextError = contextProblem(e.sets);
    Recommendation? rec;
    if (inBuild && e.loadMode == 'external') {
      final previous = _cycleStartingExercise(e.name, method, session) == null
          ? _latestMethodSession(e.name, method, session.templateId)
          : null;
      final straightOk = method != 'Straight' || _straightGuidanceAllowed(e);
      if (previous != null && straightOk) {
        rec = recommend(
          previous: previous,
          planned: e.sets,
          method: method,
          targetRir: session.targetRir,
          unit: session.unit,
          increment: incrementFor(e.name, session.unit),
          repMin: info?.repMin ?? lowRepLimit,
          repMax: info?.repMax ?? highRepLimit,
          auto: info?.autoProgression ?? true,
          expectedWorkSets: method == 'Straight'
              ? e.sets.where((s) => isStraightType(s.type)).length
              : e.sets.where((s) => !s.warmup).length,
          loadMode: e.loadMode,
        );
      }
    }
    var allow = method == 'Straight'
        ? _straightGuidanceAllowed(e) && (rec == null || rec.applyWeight)
        : method != 'Mechanical Drop Set' && (rec == null || rec.applyWeight);
    if (contextError != null) allow = false;

    e.calibrate =
        inBuild &&
        e.loadMode == 'external' &&
        contextError == null &&
        method != 'Mechanical Drop Set' &&
        (method != 'Straight' || _straightGuidanceAllowed(e)) &&
        e.sets.any((s) => calibrationAnchor(method, s.type)) &&
        !_calibrated(cycle, session.templateId, e.name, method);

    var workIndex = 0;
    var firstAnchor = true;
    for (final s in e.sets) {
      if (s.warmup) continue;
      final w = workIndex++;
      final managed = progressionManagedSet(method, s.type);
      if (e.calibrate && managed) {
        if (calibrationAnchor(method, s.type) && firstAnchor) {
          firstAnchor = false;
          s.hintWeight = calibrationFor(e.name, method, session)?.weight ?? s.hintWeight;
        } else {
          s.hintWeight = null;
        }
        continue;
      }
      if (rec != null && allow && managed && s.weight == null) {
        final hint = weightForSet(rec, s.type, w);
        if (hint != null) {
          s
            ..weight = hint
            ..prescribed = true;
        }
      }
      if (rec != null && managed) {
        final goals = rec.setRepTargets;
        s.targetReps = w < goals.length ? goals[w] : rec.targetReps;
      }
    }

    final unit = session.unit;
    e.advice = [
      if (e.loadMode != 'external')
        loadGuidance(e.loadMode)
      else if (method == 'Straight' && !allow)
        'Progress loads manually for this exercise; keep individual planned loads and record actual reps and RIR.',
      if (rec != null && !e.calibrate)
        '${rec.applyWeight ? 'Next load: ${formatNumber(rec.weight, NumKind.weight)} $unit. ' : 'Keep individual loads. '}'
            '${rec.reason}'
            '${rec.setRepTargets.isEmpty ? '' : ' Rep goals: ${rec.setRepTargets.join(' / ')}.'}',
      if (method == 'Mechanical Drop Set')
        'Mechanical drop sets use manual progression. Record each setup/variation; leverage changes cannot be evaluated from load alone.',
      if (methodsWithActivation.contains(method) && e.sets.where((s) => !s.warmup).length == 1)
        'Activation only: no continuation protocol is planned. Progress the load manually.',
    ];
  }

  /// Straight guidance needs one shared load across its straight sets.
  bool _straightGuidanceAllowed(SessionExercise e) {
    if (exercise(e.name)?.autoProgression == false) return false;
    if (contextProblem(e.sets) != null) return false;
    final loads = {
      for (final s in e.sets)
        if (isStraightType(s.type) && (s.weight ?? s.hintWeight ?? 0) > 0) s.weight ?? s.hintWeight,
    };
    return loads.length <= 1;
  }

  /// Method-aware starting load for a first mesocycle session.
  Calibration? calibrationFor(String name, String method, Session session) {
    final info = exercise(name);
    if (info != null && info.loadMode != 'external') return null;
    final starting = _cycleStartingExercise(
      name,
      method,
      session,
    )?.sets.where((s) => calibrationAnchor(method, s.type) && (s.weight ?? 0) > 0).firstOrNull;
    if (starting != null) {
      final reps = method == 'Cluster'
          ? clusterTargetReps
          : method == 'Straight'
          ? ((info?.repMin ?? lowRepLimit) + (info?.repMax ?? highRepLimit)) ~/ 2
          : calibrationTargetReps;
      return Calibration(starting.weight!, reps, session.targetRir, method != 'Cluster');
    }
    SetEntry? latest;
    search:
    for (final s in history) {
      for (final x in s.exercises.where((x) => x.name.toLowerCase() == name.toLowerCase())) {
        for (final set in x.sets.reversed) {
          if (!set.done || (set.weight ?? 0) <= 0 || (set.reps ?? 0) <= 0) continue;
          final sameMethod = x.method == method && calibrationAnchor(method, set.type);
          // Activation/AMRAP methods may inherit a Straight baseline; Cluster never does.
          final straightFallback =
              method != 'Straight' && method != 'Cluster' && x.method == 'Straight' && isStraightType(set.type);
          if (sameMethod || straightFallback) {
            latest = _inUnit(set, s.unit);
            break search;
          }
        }
      }
    }
    if (latest == null) return null;
    return calibrationRecommendation(
      weight: latest.weight!,
      reps: latest.reps!,
      rir: latest.rir,
      method: method,
      targetRir: session.targetRir,
      unit: session.unit,
      increment: incrementFor(name, session.unit),
      repMin: info?.repMin ?? lowRepLimit,
      repMax: info?.repMax ?? highRepLimit,
    );
  }

  /// Records the calibration set and seeds later segments from it.
  void applyCalibration(SessionExercise ex, int index, double weight, int reps, int? rir) {
    final s = ex.sets[index];
    s
      ..weight = weight
      ..reps = reps
      ..rir = rir
      ..invalid.clear();
    final unit = active?.unit ?? settings.unit;
    var workIndex = 0;
    for (final later in ex.sets.skip(index + 1)) {
      if (later.warmup) continue;
      workIndex++;
      if (later.done || later.context != s.context || !progressionManagedSet(ex.method, later.type)) continue;
      if (later.weight != null) continue;
      later.hintWeight = calibratedFollowupWeight(weight, ex.method, workIndex, unit, incrementFor(ex.name, unit));
    }
    ex
      ..calibrate = false
      ..calibrationEntered = true;
    changed();
  }

  /// Recovery sets from the fixed pre-deload reference, as in the Flet app.
  SessionExercise _deloadExercise(TemplateExercise te, Mesocycle c, Session session) {
    final info = exercise(te.name);
    final loadMode = info?.loadMode ?? defaultLoadModeFor(te.name);
    final warmups = te.sets.where((s) => isWarmup(s.type)).toList();
    final work = te.sets.where((s) => !isWarmup(s.type)).toList();
    if (c.deloadManual) {
      return SessionExercise(
        name: te.name,
        method: te.method,
        loadMode: loadMode,
        sets: [
          for (final ts in te.sets)
            SetEntry(
              type: ts.type,
              rest: ts.rest,
              context: contextFor(te.name, ts),
              targetRir: methodSetUsesRir(te.method, ts.type) ? session.targetRir : null,
            ),
        ],
        advice: ['Manual deload: choose recovery volume, load and effort; automatic progression is paused.'],
      );
    }
    final boundary = addDays(c.start, cycleStatus(c, c.start).buildMicro * c.microDays);
    Session? refSession;
    SessionExercise? ref;
    for (final s in history) {
      if (s.cycleId != c.id || s.templateId != session.templateId || !s.startedAt.isBefore(boundary)) continue;
      if (s.phase == 'Deload') continue;
      final e = s.exercises.where((e) => e.name == te.name && e.method == te.method).firstOrNull;
      if (e != null) {
        refSession = s;
        ref = e;
        break;
      }
    }
    final count = recoveryCount(te.method, work.length, c.deloadVolumePct);
    final refWork = ref?.work ?? const <SetEntry>[];
    final low = te.method == 'Cluster'
        ? math.min(info?.repMin ?? lowRepLimit, clusterTargetReps)
        : info?.repMin ?? lowRepLimit;
    final eligible =
        loadMode == 'external' &&
        ref?.loadMode == 'external' &&
        te.method != 'Cluster' &&
        te.method != 'Mechanical Drop Set' &&
        !(te.method == 'Straight' && info?.autoProgression == false);
    final step = incrementFor(te.name, session.unit);
    final sets = [for (final ts in warmups) SetEntry(type: 'Warm-up', rest: ts.rest, context: contextFor(te.name, ts))];
    for (var i = 0; i < count; i++) {
      final ts = work[i];
      var r = i < refWork.length ? refWork[i] : null;
      final context = contextFor(te.name, ts);
      if (r != null && (!r.done || r.context != context)) r = null;
      final refWeight = r?.weight == null ? null : convertWeight(r!.weight!, refSession!.unit, session.unit);
      final refReps = r?.reps;
      final weight = eligible && refWeight != null && refWeight > 0 && (refReps ?? 0) > 0
          ? recoveryWeight(refWeight, c.deloadLoadPct, practicalWeightStep(refWeight, session.unit, step))
          : null;
      sets.add(
        SetEntry(
          type: 'Normal',
          rest: ts.rest,
          context: context,
          targetReps: refReps != null && refReps > 0 ? math.max(1, math.min(low, refReps)) : low,
          targetRir: session.targetRir,
          weight: weight,
          prescribed: weight != null,
        ),
      );
    }
    final first = sets.where((s) => !s.warmup).firstOrNull;
    return SessionExercise(
      name: te.name,
      method: 'Straight',
      loadMode: loadMode,
      sets: sets,
      advice: [
        'Deload week: $count of ${work.length} sets'
            '${first?.weight != null ? ' at ${formatNumber(first!.weight!, NumKind.weight)} ${session.unit} (about ${c.deloadLoadPct}% of your build load)' : ', with a lighter load of your choice'}, '
            'aiming for ${first?.targetReps ?? '?'} reps at ${session.targetRir ?? '?'} RIR. Changes here apply only to this workout.',
      ],
    );
  }

  // ---------------------------------------------------------------- Active session edits

  /// Rebuild rows after editing the template mid-session, keeping recorded sets.
  void _applyTemplateToActive(WorkoutTemplate t) {
    final s = active!;
    final old = {for (final e in s.exercises) e.name.toLowerCase(): e};
    final cycle = cycles.where((c) => c.id == s.cycleId).firstOrNull;
    s.name = t.name;
    s.circuits = copyCircuits(t.circuits);
    s.exercises = [
      for (final te in t.exercises)
        () {
          final existing = old[te.name.toLowerCase()];
          final fresh = s.phase == 'Deload' && cycle != null
              ? _deloadExercise(te, cycle, s)
              : _buildExercise(te, s, cycle);
          if (existing == null) return fresh;
          existing.method = canonicalMethod(te.method);
          existing.sets = [
            for (final (i, ts) in te.sets.indexed)
              if (i < existing.sets.length)
                (existing.sets[i]
                  ..type = ts.type
                  ..rest = ts.rest
                  ..groupStart = ts.groupStart
                  ..hintWeight = existing.sets[i].hintWeight ?? ts.weight
                  ..hintReps = existing.sets[i].hintReps ?? (historicalRepsVisible(s) ? ts.reps : null))
              else if (i < fresh.sets.length)
                fresh.sets[i],
          ];
          for (final set in existing.sets) {
            if (!methodSetUsesRir(existing.method, set.type)) set.rir = null;
          }
          return existing;
        }(),
    ];
    // Preserve completed warm-ups when the plan is edited, and discard ramps for removed exercises.
    s.warmupExercises.removeWhere((warmup) => !s.exercises.any((exercise) => exercise.name == warmup.name));
    reconcileCircuits(s.circuits, s.exercises.map((e) => e.name));
    _finishWarmupPhase();
  }

  /// Completed sets can't disappear when editing the plan mid-workout.
  String? blockedTemplateEdit(WorkoutTemplate t) {
    final s = active;
    if (s == null || s.templateId != t.id) return null;
    for (final e in s.exercises) {
      for (final (i, set) in e.sets.indexed) {
        if (!set.done) continue;
        final te = t.exercises.where((x) => x.name.toLowerCase() == e.name.toLowerCase()).firstOrNull;
        if (te == null || i >= te.sets.length) {
          return '${e.name}: completed sets cannot be removed or replaced while the workout is active.';
        }
      }
    }
    return null;
  }

  /// Adds an exercise to the running workout. Returns an error message.
  String? addSessionExercise(String name) {
    final s = active;
    if (s == null) return null;
    if (s.exercises.any((e) => e.name.toLowerCase() == name.toLowerCase())) {
      return 'That exercise is already in the current workout.';
    }
    final info = addExercise(name);
    final fromTemplate = template(
      s.templateId,
    )?.exercises.where((e) => e.name.toLowerCase() == info.name.toLowerCase()).firstOrNull;
    final te =
        fromTemplate ??
        TemplateExercise(
          name: info.name,
          sets: [for (var i = 0; i < math.max(1, settings.defaultSets); i++) TemplateSet(rest: settings.defaultRest)],
        );
    final latest = _latestSetValues(info.name, null, anyWorkout: true) ?? const <SetEntry>[];
    final built = _buildExercise(te, s, cycles.where((c) => c.id == s.cycleId).firstOrNull);
    for (final (i, set) in built.sets.indexed) {
      if (set.hintWeight == null && i < latest.length && latest[i].done && latest[i].context == set.context) {
        set.hintWeight = latest[i].weight;
      }
    }
    s.exercises.add(built);
    changed();
    return null;
  }

  String? removeSessionExercise(SessionExercise e) {
    if (e.sets.any((s) => s.done)) return 'Completed exercises cannot be removed from the current session.';
    active?.exercises.remove(e);
    active?.warmupExercises.removeWhere((warmup) => identical(warmup, e) || warmup.name == e.name);
    if (active != null) reconcileCircuits(active!.circuits, active!.exercises.map((e) => e.name));
    _finishWarmupPhase();
    if (rest?.exercise == e.name) _dismissRest();
    changed();
    return null;
  }

  String? substituteExercise(SessionExercise e, String newName) {
    if (e.sets.any((s) => s.done)) return 'Substitute before completing sets for this exercise.';
    final s = active!;
    if (s.exercises.any((x) => x != e && x.name.toLowerCase() == newName.toLowerCase())) {
      return 'That exercise is already in the current workout.';
    }
    final info = addExercise(newName);
    renameCircuitExercise(s.circuits, e.name, info.name);
    s.warmupExercises.removeWhere((warmup) => warmup.name == e.name);
    _finishWarmupPhase();
    final latest = _latestSetValues(info.name, null, anyWorkout: true) ?? const <SetEntry>[];
    e
      ..name = info.name
      ..loadMode = info.loadMode
      ..calibrate = false
      ..advice = info.loadMode == 'external' ? [] : [loadGuidance(info.loadMode)];
    for (final (i, set) in e.sets.indexed) {
      final prev = i < latest.length ? latest[i] : null;
      set
        ..weight = null
        ..reps = null
        ..rir = null
        ..prescribed = false
        ..stopReason = ''
        ..actualRest = null
        ..circuitRestAfter = null
        ..targetReps = null
        ..context = info.context
        ..hintWeight = prev != null && prev.done && prev.context == info.context ? prev.weight : null
        ..hintReps = null;
    }
    changed();
    return null;
  }

  void addSet(SessionExercise e) {
    final last = e.sets.isEmpty ? null : e.sets.last;
    final type = active?.warmupExercises.contains(e) == true
        ? 'Warm-up'
        : defaultNextSetType(e.method, [for (final s in e.sets) s.type]);
    e.sets.add(
      SetEntry(
        type: type,
        rest: last?.rest ?? settings.defaultRest,
        context: last?.context ?? exercise(e.name)?.context ?? const SetContext(),
        hintWeight: last?.weight ?? last?.hintWeight,
        hintReps: last?.reps ?? last?.hintReps,
        targetRir: methodSetUsesRir(e.method, type) ? (last?.targetRir ?? active?.targetRir) : null,
      ),
    );
    e.collapsed = false;
    changed();
  }

  void removeSet(SessionExercise e, SetEntry set) {
    final index = e.sets.indexOf(set);
    if (index < 0) return;
    e.sets.removeAt(index);
    _reconcileSession(e);
    final r = rest;
    if (r != null && r.exercise == e.name && r.warmup == (active?.warmupExercises.contains(e) == true)) {
      if (r.setIndex == index) {
        _dismissRest();
      } else if (r.setIndex > index) {
        rest = RestTimer(
          startedAt: r.startedAt,
          totalSeconds: r.totalSeconds,
          exercise: e.name,
          setIndex: r.setIndex - 1,
          countdown: r.countdown,
          warmup: r.warmup,
        );
      }
    }
    _finishWarmupPhase();
    changed();
  }

  void changeSetType(SessionExercise e, SetEntry set, String type) {
    if (active?.warmupExercises.contains(e) == true) return;
    set.type = type;
    _reconcileSession(e);
    changed();
  }

  void _reconcileSession(SessionExercise e) {
    final fixed = reconcileMethodSets(e.method, [for (final s in e.sets) (s.type, s.groupStart)]);
    for (var i = 0; i < e.sets.length; i++) {
      e.sets[i]
        ..type = fixed[i].$1
        ..groupStart = fixed[i].$2;
      if (!methodSetUsesRir(e.method, e.sets[i].type)) e.sets[i].rir = null;
    }
  }

  /// Placeholder for an empty field: own hint, then the typed value just above.
  num? fallbackValue(SessionExercise e, int index, String field) {
    final s = e.sets[index];
    if (field == 'weight' && s.hintWeight != null) return s.hintWeight;
    if (field == 'reps' && s.hintReps != null) return s.hintReps;
    if (field == 'rir' || index == 0) return null;
    final visible = active?.visibleSetsFor(e) ?? e.sets;
    final position = visible.indexOf(s);
    if (position <= 0) return null;
    final above = visible[position - 1];
    return field == 'weight' ? above.weight : above.reps;
  }

  /// Completing a set: calibration first, optional set order, then blank
  /// fields fall back to the placeholder or the set above; anything still
  /// missing is marked invalid and the set stays open.
  CompleteResult toggleSet(SessionExercise e, int index) {
    final s = active!;
    final set = e.sets[index];
    final warmup = s.warmupExercises.contains(e);
    if (!s.visibleExercises.contains(e)) {
      return const CompleteResult.blocked('Show this exercise’s sets before editing them.');
    }
    if (set.done) {
      set
        ..done = false
        ..circuitRestAfter = null;
      final circuit = warmup ? null : circuitFor(s.circuits, e.name);
      if ((rest?.exercise == e.name && rest?.setIndex == index && rest?.warmup == warmup) ||
          (circuit != null && rest?.warmup == false && circuit.exercises.contains(rest?.exercise))) {
        _dismissRest();
      }
      e.collapsed = null;
      changed();
      return const CompleteResult.done();
    }
    if (e.calibrate && !set.warmup && !calibrationAnchor(e.method, set.type)) {
      return CompleteResult.blocked('Calibrate the ${e.method} anchor before continuing.');
    }
    if (settings.requirePreviousSet) {
      final next = nextCircuitStep(s, e);
      if (!set.warmup && next != null && (next.exercise != e || next.index != index)) {
        return CompleteResult.blocked('Complete ${next.exercise.name} set ${next.index + 1} first.');
      }
      final earlier = s.visibleSetsFor(e).where((x) => !x.done).map(e.sets.indexOf).firstOrNull ?? -1;
      if (earlier >= 0 && earlier < index) {
        return CompleteResult.blocked('Complete set ${earlier + 1} of ${e.name} first.');
      }
    }
    if (!_resolveFields(e, index)) {
      changed();
      return const CompleteResult.blocked();
    }
    set
      ..done = true
      ..accepted.addAll([
        for (final (f, v) in [('weight', set.weight), ('reps', set.reps), ('rir', set.rir)])
          if (v != null) '$f:$v',
      ]);
    if (e.calibrate && calibrationAnchor(e.method, set.type)) {
      applyCalibration(e, index, set.weight!, set.reps!, set.rir);
    } else {
      _propagateFollowing(e, index);
    }
    if (!s.clockStarted) {
      s
        ..clockStarted = true
        ..clockElapsed = 0
        ..clockRunningSince = DateTime.now();
    }
    if (settings.haptics) alerts.setDone();
    setCelebration++;
    final circuit = warmup || set.warmup ? null : circuitFor(s.circuits, e.name);
    if (circuit != null) {
      final steps = sessionSteps(s).where((step) => step.circuit == circuit).toList();
      final step = steps.where((step) => step.exercise == e && step.index == index).firstOrNull;
      final roundComplete = step != null && steps.where((other) => other.round == step.round).every((s) => s.set.done);
      final pending = steps.any((s) => !s.set.done);
      if (step != null && !step.endsTurn) {
        set.circuitRestAfter = set.rest;
        startRest(e.name, index, set.rest);
      } else if (roundComplete && pending) {
        set.circuitRestAfter = circuit.rest;
        startRest(e.name, index, circuit.rest);
      } else {
        set.circuitRestAfter = 0;
        _dismissRest();
      }
      e.collapsed = null;
    } else if (warmup) {
      startRest(e.name, index, set.rest);
      _finishWarmupPhase();
      e.collapsed = null;
    } else if (s.visibleSetsFor(e).every((set) => set.done)) {
      if (rest?.exercise == e.name) _dismissRest();
      e.collapsed = null;
    } else {
      startRest(e.name, index, set.rest);
    }
    nextCircuitStep(s, e)?.exercise.collapsed = false;
    changed();
    return const CompleteResult.done();
  }

  bool _resolveFields(SessionExercise e, int index) {
    final set = e.sets[index];
    set.invalid.clear();
    final weightKind = e.loadMode == 'external' ? NumKind.weight : NumKind.load;
    set.weight ??= fallbackValue(e, index, 'weight')?.toDouble();
    set.reps ??= fallbackValue(e, index, 'reps')?.toInt();
    if (set.weight == null || !numberAllowed(set.weight!, weightKind)) set.invalid.add('weight');
    if (set.reps == null || !numberAllowed(set.reps!.toDouble(), NumKind.reps)) set.invalid.add('reps');
    if (set.rir != null && !numberAllowed(set.rir!.toDouble(), NumKind.rir)) set.invalid.add('rir');
    if (!methodSetUsesRir(e.method, set.type)) set.rir = null;
    return set.invalid.isEmpty;
  }

  /// Seed later placeholders without violating the selected training method.
  void _propagateFollowing(SessionExercise e, int index) {
    final source = e.sets[index];
    final fields = switch (e.method) {
      'Straight' || 'Myo-Rep Match' || 'Cluster' => const ['weight', 'reps'],
      'Drop Set' => const <String>[],
      _ => const ['weight'],
    };
    if (fields.isEmpty) return;
    for (final later in e.sets.skip(index + 1)) {
      if (later.context != source.context) continue;
      if ((fields.contains('weight') && later.weight != null) || (fields.contains('reps') && later.reps != null)) {
        continue;
      }
      if (fields.contains('weight') &&
          source.weight != null &&
          (settings.updateFollowingDefaults || later.hintWeight == null)) {
        later.hintWeight = source.weight;
      }
      if (fields.contains('reps') &&
          source.reps != null &&
          (settings.updateFollowingDefaults || later.hintReps == null)) {
        later.hintReps = source.reps;
      }
    }
  }

  /// Applies a calculator target to the next unfinished set.
  String applyRepMaxTarget(String exerciseName, double weight, int reps, int rir) {
    final s = active;
    final e = s?.visibleExercises.where((x) => x.name == exerciseName).firstOrNull;
    if (s == null || e == null) return 'No active workout.';
    if (e.loadMode != 'external') return 'Choose added load or assistance manually for this exercise.';
    final target = e.sets.where((x) => !x.done).firstOrNull;
    if (target == null) return 'All sets for this exercise are already completed.';
    target
      ..weight = weight
      ..reps = reps
      ..rir = null
      ..prescribed = false
      ..targetRir = s.rirLocked && s.targetRir != null ? s.targetRir : rir
      ..accepted.addAll(['weight:$weight', 'reps:$reps']);
    changed();
    return 'Loaded ${formatNumber(weight, NumKind.weight)} ${s.unit} × $reps into the next $exerciseName set.';
  }

  // ---------------------------------------------------------------- Workout clock

  void toggleClock() {
    final s = active;
    if (s == null) return;
    if (!s.clockStarted) {
      s
        ..clockStarted = true
        ..clockElapsed = 0
        ..clockRunningSince = DateTime.now();
    } else if (s.clockRunning) {
      s
        ..clockElapsed = s.clockSeconds
        ..clockRunningSince = null;
    } else {
      s.clockRunningSince = DateTime.now();
    }
    changed();
  }

  void resetClock() {
    final s = active;
    if (s == null) return;
    s
      ..clockStarted = false
      ..clockElapsed = 0
      ..clockRunningSince = null;
    changed();
  }

  // ---------------------------------------------------------------- Rest timer

  void startRest(String exercise, int setIndex, int seconds) {
    if (seconds <= 0) {
      _dismissRest();
      return;
    }
    rest = RestTimer(
      startedAt: DateTime.now(),
      totalSeconds: seconds,
      exercise: exercise,
      setIndex: setIndex,
      countdown: settings.defaultTimerDisplay == 'countdown',
      warmup: active?.activeWarmup?.name == exercise,
    );
    _syncAlerts();
  }

  void _dismissRest() {
    rest = null;
    _syncAlerts();
  }

  void showRestCountdown() {
    if (rest == null) return;
    rest = rest!.copyWith(countdown: true);
    changed();
  }

  /// Changes only the running timer's total; zero dismisses it.
  void setRestTotal(int seconds) {
    if (rest == null) return;
    rest = seconds <= 0 ? null : rest!.copyWith(totalSeconds: seconds);
    _syncAlerts();
    changed();
  }

  /// Planned-rest edits affect unfinished entries only.
  void setPlannedRests(SessionExercise e, Iterable<int> indices, int seconds) {
    for (final i in indices) {
      if (i >= 0 && i < e.sets.length && !e.sets[i].done) e.sets[i].rest = seconds;
    }
    changed();
  }

  /// Rest-editor scopes for unfinished entries, as rest_scopes.targets.
  Map<String, List<int>> restScopes(SessionExercise e) {
    final out = <String, List<int>>{};
    void add(String k, int i) => out.putIfAbsent(k, () => []).add(i);
    final roles = [for (final s in e.sets) setRole(s.type)];
    final classified = <int, String>{};
    for (var i = 0; i < e.sets.length; i++) {
      if (roles[i] == 'warmup') classified[i] = 'warmup';
      if (roles[i] == 'conventional') classified[i] = 'conventional';
    }
    // Protocol groups: anchor + continuations, or a run of cluster fragments.
    var i = 0;
    while (i < e.sets.length) {
      final r = roles[i];
      if (r == 'anchor' || r == 'cluster_fragment') {
        var j = i + 1;
        while (j < e.sets.length &&
            !e.sets[j].groupStart &&
            (r == 'anchor' ? roles[j] == 'continuation' : roles[j] == 'cluster_fragment')) {
          j++;
        }
        if (r == 'cluster_fragment' || j - i > 1) {
          for (var k = i; k < j - 1; k++) {
            classified[k] = 'within_protocol';
          }
          classified[j - 1] = 'after_protocol';
        }
        i = j;
      } else {
        i++;
      }
    }
    for (var k = 0; k < e.sets.length; k++) {
      if (e.sets[k].done) continue;
      add('all_pending', k);
      add('set:$k', k);
      final c = classified[k];
      if (c != null) add(c, k);
    }
    return out;
  }

  // ---------------------------------------------------------------- Finishing

  /// Set order violation when "require previous set" is on.
  String? setOrderViolation() {
    if (!settings.requirePreviousSet) return null;
    final session = active;
    if (session != null) {
      final steps = sessionSteps(session);
      for (final circuit in session.circuits) {
        final group = steps.where((step) => step.circuit == circuit).toList();
        final open = group.indexWhere((step) => !step.set.done);
        if (open >= 0 && group.skip(open).any((step) => step.set.done)) {
          final next = group[open];
          return 'Complete ${next.exercise.name} set ${next.index + 1} before saving later sets.';
        }
      }
    }
    for (final e in active?.exercises ?? <SessionExercise>[]) {
      final sets = active!.visibleSetsFor(e);
      final firstOpen = sets.indexWhere((s) => !s.done);
      if (firstOpen >= 0 && sets.skip(firstOpen).any((s) => s.done)) {
        return '${e.name}: complete set ${firstOpen + 1} before saving later sets.';
      }
    }
    return null;
  }

  /// The program structure differs from the saved workout.
  bool templateChanged() {
    final s = active;
    final t = template(s?.templateId);
    if (s == null || t == null || s.phase == 'Deload') return false;
    String sig(Iterable<(String, String, int, String, bool)> rows) =>
        rows.map((r) => '${r.$1.toLowerCase()}|${r.$2}|${r.$3}|${canonicalSetType(r.$4)}|${r.$5}').join(';');
    final a = [
      for (final e in s.exercises)
        for (final set in e.sets) (e.name, e.method, set.rest, set.type, set.groupStart),
    ];
    final b = [
      for (final e in t.exercises)
        for (final set in e.sets) (e.name, canonicalMethod(e.method), set.rest, set.type, set.groupStart),
    ];
    return sig(a) != sig(b) ||
        jsonEncode(s.circuits.map((c) => c.toJson()).toList()) !=
            jsonEncode(t.circuits.map((c) => c.toJson()).toList());
  }

  /// Saves the workout; returns null when nothing was completed.
  FinishSummary? finishSession({bool saveStructure = false}) {
    final s = active;
    if (s == null || s.doneAll == 0) return null;
    final t = template(s.templateId);
    if (t != null && s.phase != 'Deload') {
      if (saveStructure) _saveStructure(s, t);
      _updateTemplateDefaults(s, t);
    }
    if (s.clockRunning) {
      s
        ..clockElapsed = s.clockSeconds
        ..clockRunningSince = null;
    }
    s.finishedAt = DateTime.now();
    for (final e in s.exercises) {
      for (final set in e.sets) {
        if (!methodSetUsesRir(e.method, set.type)) set.rir = null;
        set.invalid.clear();
      }
    }
    // Records compare against earlier sessions, so collect them first.
    final alreadyEarned = {
      for (final p in achievementProgress(history))
        if (p.earned) p.achievement.id,
    };
    final earned = achievementProgress([...history, s]).where((p) => p.earned).toList();
    final unlocked = [
      for (final p in earned)
        if (!alreadyEarned.contains(p.achievement.id) && !_seenAchievements.contains(p.achievement.id)) p,
    ];
    _seenAchievements.addAll(earned.map((p) => p.achievement.id));
    final summary = summarizeSession(s, achievements: unlocked);
    history = [s, ...history];
    final c = cycles.where((c) => c.id == s.cycleId).firstOrNull ?? activeCycle;
    if (c != null) linkSession(c, s);
    snapshot();
    active = null;
    rest = null;
    _syncAlerts();
    changed();
    return summary;
  }

  /// Persist the session's exercise/set/rest/type structure, not performance.
  void _saveStructure(Session s, WorkoutTemplate t) {
    t.circuits = copyCircuits(s.circuits);
    final old = {for (final e in t.exercises) e.name.toLowerCase(): e};
    t.exercises = [
      for (final e in s.exercises)
        TemplateExercise(
          name: e.name,
          method: e.method,
          sets: [
            for (final (i, set) in e.sets.indexed)
              () {
                final prev = old[e.name.toLowerCase()];
                final keep = prev != null && i < prev.sets.length ? prev.sets[i] : null;
                return TemplateSet(
                  type: canonicalSetType(set.type),
                  rest: set.rest,
                  groupStart: set.groupStart,
                  weight: keep?.weight,
                  reps: keep?.reps,
                  context: keep?.context,
                );
              }(),
          ],
        ),
    ];
  }

  /// Completed weights/reps become the template's per-set defaults.
  void _updateTemplateDefaults(Session s, WorkoutTemplate t) {
    for (final e in s.exercises) {
      final te = t.exercises.where((x) => x.name.toLowerCase() == e.name.toLowerCase()).firstOrNull;
      if (te == null || e.loadMode != (exercise(e.name)?.loadMode ?? e.loadMode)) continue;
      for (final (i, set) in e.sets.indexed) {
        if (!set.done || i >= te.sets.length) continue;
        if (set.context != contextFor(e.name, te.sets[i])) continue;
        te.sets[i]
          ..weight = set.weight
          ..reps = set.reps;
      }
    }
  }

  void discardSession() {
    active = null;
    rest = null;
    _syncAlerts();
    changed();
  }

  // ---------------------------------------------------------------- Volume

  (List<String>, List<String>) musclesOf(String name) {
    final e = exercise(name);
    return (e?.primary ?? const [], e?.secondary ?? const []);
  }

  VolumeReport sessionVolume(Session s, {bool planned = false}) {
    final rows = <VolumeRow>[];
    for (final (i, e) in s.exercises.indexed) {
      final (p, sec) = musclesOf(e.name);
      for (final set in e.sets) {
        rows.add(
          VolumeRow(
            scope: '$i',
            type: set.type,
            active: planned || set.done,
            groupStart: set.groupStart,
            primary: p,
            secondary: sec,
          ),
        );
      }
    }
    return summarizeVolume(rows);
  }

  VolumeReport templateVolume(WorkoutTemplate t) {
    final rows = <VolumeRow>[];
    for (final (i, e) in t.exercises.indexed) {
      final (p, sec) = musclesOf(e.name);
      for (final set in e.sets) {
        rows.add(
          VolumeRow(scope: '$i', type: set.type, active: true, groupStart: set.groupStart, primary: p, secondary: sec),
        );
      }
    }
    return summarizeVolume(rows);
  }

  // ---------------------------------------------------------------- History

  void saveHistorySession(Session edited) {
    final i = history.indexWhere((s) => s.id == edited.id);
    if (i >= 0) {
      history[i] = edited;
    } else {
      history = [edited, ...history];
    }
    history.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _historyVersion++;
    changed();
  }

  void deleteSession(String id) {
    history.removeWhere((s) => s.id == id);
    _historyVersion++;
    for (final c in cycles) {
      c.events.removeWhere((_, e) => e.sessionId == id && e.status == 'unplanned');
      for (final e in c.events.values) {
        if (e.sessionId == id) e.sessionId = null;
      }
    }
    changed();
  }

  /// A blank record of [templateId]'s plan for logging a past calendar day.
  Session draftPastSession(String templateId, DateTime date) {
    final t = template(templateId)!;
    return Session(
      id: 'S${DateTime.now().microsecondsSinceEpoch}',
      templateId: t.id,
      name: t.name,
      unit: settings.unit,
      startedAt: DateTime(date.year, date.month, date.day, 12),
      bodyweight: bodyweightAt(date, settings.unit),
      circuits: copyCircuits(t.circuits),
      exercises: [
        for (final te in t.exercises)
          SessionExercise(
            name: te.name,
            method: te.method,
            loadMode: exercise(te.name)?.loadMode ?? 'external',
            sets: [
              for (final ts in te.sets)
                SetEntry(type: ts.type, rest: ts.rest, groupStart: ts.groupStart, context: contextFor(te.name, ts)),
            ],
          ),
      ],
    );
  }

  /// Saves a calendar-logged past workout and links it to its planned day.
  void saveCalendarSession(Mesocycle c, String plannedKey, Session s, {bool unplanned = false}) {
    final st = cycleStatus(c, s.startedAt);
    s
      ..cycleId = c.id
      ..microcycle = st.running ? st.currentMicro : null
      ..phase = st.running ? st.phase : null
      ..targetRir = st.running ? st.suggestedRir : null
      ..finishedAt = s.startedAt;
    final previous = c.events[plannedKey];
    c.events[plannedKey] = DayEvent(
      templateId: s.templateId!,
      status: unplanned ? 'unplanned' : 'planned',
      movedTo: previous?.movedTo,
      sessionId: s.id,
    );
    saveHistorySession(s);
  }

  /// Links an already-recorded session to a planned day. Returns an error.
  String? linkRecordedSession(Mesocycle c, String plannedKey, String templateId, String sessionId) {
    if (c.events.entries.any((e) => e.key != plannedKey && e.value.sessionId == sessionId)) {
      return 'This workout is already linked to another day.';
    }
    final previous = c.events[plannedKey];
    c.events[plannedKey] = DayEvent(templateId: templateId, movedTo: previous?.movedTo, sessionId: sessionId);
    changed();
    return null;
  }

  // ---------------------------------------------------------------- Queries

  List<SetEntry> previousSets(String exercise, [String? templateId]) =>
      _latestSetValues(exercise, templateId, anyWorkout: templateId == null) ?? const [];

  List<ExercisePoint> progress(String exercise) {
    final points = <ExercisePoint>[];
    final combined = usesBodyweightProgress(exercise);
    for (final s in history.reversed) {
      SetEntry? best;
      double bestValue = 0;
      for (final e in s.exercises.where(
        (e) =>
            e.name == exercise &&
            (combined
                ? e.loadMode == (this.exercise(exercise)?.loadMode ?? defaultLoadModeFor(exercise))
                : e.loadMode == 'external'),
      )) {
        for (final set in e.sets) {
          final v = (combined ? combinedBodyweightLoad(s, e, set) : set.e1rm) ?? 0;
          if (v > bestValue) {
            bestValue = v;
            best = set;
          }
        }
      }
      if (best != null) {
        points.add(ExercisePoint(s.startedAt, convertWeight(bestValue, s.unit, settings.unit), _inUnit(best, s.unit)));
      }
    }
    return points..sort((a, b) => a.date.compareTo(b.date));
  }

  bool usesBodyweightProgress(String name) =>
      settings.trackBodyweight &&
      const {'bodyweight', 'assisted'}.contains(exercise(name)?.loadMode ?? defaultLoadModeFor(name));

  Set<String> performedExercises() => {
    for (final s in history)
      for (final e in s.exercises)
        if (e.sets.any((x) => x.done)) e.name,
  };

  /// Seed for the rep-max calculator: latest completed straight set.
  (double?, int?, String) repMaxSeed(String name) {
    final info = exercise(name);
    if (info != null && info.loadMode != 'external') {
      return (null, null, 'Bodyweight and assisted loads do not establish a total RM.');
    }
    final live = active?.exercises.where((x) => x.name == name).firstOrNull;
    for (final set in [...?live?.sets].reversed) {
      if (!set.done || !isStraightType(set.type) || (set.weight ?? 0) <= 0 || (set.reps ?? 0) <= 0) continue;
      return _seedFrom(set.weight!, set.reps!, set.rir, active!.unit);
    }
    for (final s in history) {
      for (final x in s.exercises.where((x) => x.name == name)) {
        for (final set in x.sets.reversed) {
          if (!set.done || !isStraightType(set.type) || (set.weight ?? 0) <= 0 || (set.reps ?? 0) <= 0) continue;
          if (x.loadMode != 'external') {
            return (null, null, 'The latest set uses bodyweight or assistance; enter an external-load RM manually.');
          }
          return _seedFrom(convertWeight(set.weight!, s.unit, settings.unit), set.reps!, set.rir, settings.unit);
        }
      }
    }
    return (null, null, 'No completed straight set is available yet. Enter a set you know.');
  }

  (double?, int?, String) _seedFrom(double weight, int reps, int? rir, String unit) {
    final w = snapWeight(weight);
    if (rir == null) return (w, null, 'Actual RIR is unknown; enter a known repetition maximum manually.');
    final note =
        'Using your latest straight set: ${formatNumber(w, NumKind.weight)} $unit × $reps${rir > 0 ? ' @ $rir RIR' : ''}.';
    final rm = reps + rir;
    return (w, rm >= 1 ? rm : null, note);
  }

  // ---------------------------------------------------------------- Import / export

  /// Replaces all data with a Flet backup's contents, after saving a safety copy.
  Future<List<String>> importLegacy(LegacyData d) async {
    final known = {for (final e in d.exercises) e.name.toLowerCase()};
    final missing = <String>{
      for (final t in d.templates)
        for (final e in t.exercises) e.name,
      for (final s in d.history)
        for (final e in s.exercises) e.name,
    }.where((n) => !known.contains(n.toLowerCase()));
    final newExercises = [...d.exercises, for (final n in missing) Exercise(name: n, loadMode: defaultLoadModeFor(n))]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final newSettings = Settings.fromJson(settings.toJson());
    d.applySettings(newSettings);
    await _backupBeforeReplace();
    exercises = newExercises;
    bodyweights = [];
    templates = d.templates.isEmpty ? seedTemplates() : d.templates;
    history = d.history;
    _seenAchievements = {
      for (final p in achievementProgress(history))
        if (p.earned) p.achievement.id,
    };
    cycles = d.cycles;
    settings = newSettings;
    active = null;
    rest = null;
    _syncAlerts();
    changed();
    return [
      'Imported ${d.templates.length} workouts, ${d.history.length} sessions and ${d.cycles.length} mesocycles.',
      ...d.notes,
    ];
  }

  Future<void> importJson(String text) async {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw const FormatException('This file is not a Gymer backup.');
    }
    if (j is! Map<String, dynamic> || j['settings'] == null || j['templates'] == null) {
      throw const FormatException('This file is not a Gymer backup.');
    }
    final incoming = AppStore();
    try {
      incoming._fromJson(j);
    } catch (e) {
      // Parse separately so a damaged backup cannot change the current data.
      throw FormatException('This backup is damaged and was not restored ($e).');
    }
    await _backupBeforeReplace();
    settings = incoming.settings;
    templates = incoming.templates;
    exercises = incoming.exercises;
    history = incoming.history;
    cycles = incoming.cycles;
    bodyweights = incoming.bodyweights;
    _seenAchievements = incoming._seenAchievements;
    active = incoming.active;
    rest = incoming.rest;
    _syncAlerts();
    changed();
  }

  // ---------------------------------------------------------------- Automatic backups

  /// Copies live next to the data file, in the app's private storage.
  Directory? get _backupDir => _file == null ? null : Directory('${_file.parent.path}/backups');

  Future<List<(DateTime, File)>> _backupFiles() async {
    final dir = _backupDir;
    if (dir == null || !await dir.exists()) return [];
    final out = <(DateTime, File)>[];
    await for (final f in dir.list()) {
      final at = f is File ? snapshotTime(f.uri.pathSegments.last) : null;
      if (at != null) out.add((at, f as File));
    }
    return out..sort((a, b) => b.$1.compareTo(a.$1));
  }

  /// Saves a copy of the current data unless it matches the newest copy, then thins older copies with
  /// [snapshotsToKeep]. Queued behind regular saves, and a failure never disturbs the app.
  Future<void> snapshot() => _saving = _saving.then((_) => _snapshot()).catchError((Object e) {
    debugPrint('gymer: automatic backup failed: $e');
  });

  /// A replacement must stop if its safety copy fails. Keep the save queue usable after that failure.
  Future<void> _backupBeforeReplace() async {
    final backup = _saving.then((_) => _snapshot());
    _saving = backup.catchError((Object e) {
      debugPrint('gymer: safety backup failed: $e');
    });
    try {
      await backup;
    } catch (e) {
      throw FileSystemException('Could not save a safety backup. Your current data was not replaced. ($e)');
    }
  }

  Future<void> _snapshot() async {
    final dir = _backupDir;
    if (dir == null) return;
    await dir.create(recursive: true);
    final text = jsonEncode(toJson());
    final existing = await _backupFiles();
    if (existing.isNotEmpty && await existing.first.$2.readAsString() == text) return;
    var now = DateTime.now();
    var target = File('${dir.path}/${snapshotName(now)}');
    // Names have second precision. Never overwrite an earlier recovery point made in the same second.
    while (await target.exists()) {
      now = now.add(const Duration(seconds: 1));
      target = File('${dir.path}/${snapshotName(now)}');
    }
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(target.path);
    final keep = snapshotsToKeep([snapshotTime(snapshotName(now))!, for (final (at, _) in existing) at]);
    for (final (at, file) in existing) {
      if (!keep.contains(at)) await file.delete();
    }
  }

  /// At launch, one copy a day: skipped when today already has one.
  Future<void> _dailySnapshot() async {
    try {
      final newest = (await _backupFiles()).firstOrNull?.$1;
      final now = DateTime.now();
      if (newest != null && newest.year == now.year && newest.month == now.month && newest.day == now.day) return;
      await snapshot();
    } catch (e) {
      debugPrint('gymer: automatic backup failed: $e');
    }
  }

  /// Every automatic backup, newest first, with its counts read in a background isolate.
  Future<List<BackupInfo>> backups() async => [
    for (final (at, file) in await _backupFiles())
      await () async {
        final (sessions, workouts) = await _backupCounts(await file.readAsString());
        return (at: at, file: file, sessions: sessions, workouts: workouts);
      }(),
  ];

  /// Replaces all data with [file]'s copy, after backing up the current data so this can be undone.
  Future<void> restoreSnapshot(File file) async {
    final text = await file.readAsString();
    await importJson(text);
  }
}

/// Logged sessions and saved workouts in a backup, decoded off the UI thread; (-1, -1) if unreadable.
/// Top-level so the isolate receives only the text, never the store.
Future<(int, int)> _backupCounts(String text) => Isolate.run(() {
  try {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return ((j['history'] as List?)?.length ?? 0, (j['templates'] as List?)?.length ?? 0);
  } catch (_) {
    return (-1, -1);
  }
});
