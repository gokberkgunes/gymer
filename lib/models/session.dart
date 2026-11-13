part of '../models.dart';

class SetEntry {
  double? weight;
  int? reps;
  int? rir;
  bool done;
  String type;
  String note;

  /// Planned rest after this set, in seconds.
  int rest;
  bool groupStart;
  SetContext context;
  String stopReason;
  int? actualRest;

  /// Effective planned rest when this linked set was completed; keeps past rounds unchanged.
  int? circuitRestAfter;

  /// Placeholders: what the field shows while empty. Never an observation.
  double? hintWeight;
  int? hintReps;

  /// Prescription goals shown beside the set; RIR here is the target, not actual.
  int? targetReps;
  int? targetRir;

  /// The weight was put there by progression/deload, not typed.
  bool prescribed;

  /// Unusual values the user explicitly accepted, as "field:value".
  Set<String> accepted;

  /// Fields that failed validation on the last completion attempt (not saved).
  final Set<String> invalid = {};

  /// Fields whose box currently shows text that is not a usable number (a half-typed sum like "45+", or a
  /// value out of range), reported by the box itself (not saved). The stored value is then older than what
  /// the user sees, so the set must not be completed from it.
  final Set<String> badText = {};

  SetEntry({
    this.weight,
    this.reps,
    this.rir,
    this.done = false,
    this.type = 'Normal',
    this.note = '',
    this.rest = 180,
    this.groupStart = false,
    this.context = const SetContext(),
    this.stopReason = '',
    this.actualRest,
    this.circuitRestAfter,
    this.hintWeight,
    this.hintReps,
    this.targetReps,
    this.targetRir,
    this.prescribed = false,
    Set<String>? accepted,
  }) : accepted = accepted ?? {};

  bool get warmup => isWarmup(type);

  /// The app's estimated 1RM for this completed working set; see [setOneRm].
  double? get e1rm => !done || warmup ? null : setOneRm(weight, reps, rir);

  Map<String, dynamic> toJson() => {
    'w': weight,
    'r': reps,
    'rir': rir,
    'done': done,
    if (type != 'Normal') 'type': type,
    if (note.isNotEmpty) 'note': note,
    'rest': rest,
    if (groupStart) 'group': true,
    if (!context.isEmpty) 'context': context.toJson(),
    if (stopReason.isNotEmpty) 'stop': stopReason,
    if (actualRest != null) 'actualRest': actualRest,
    if (circuitRestAfter != null) 'circuitRest': circuitRestAfter,
    if (hintWeight != null) 'hw': hintWeight,
    if (hintReps != null) 'hr': hintReps,
    if (targetReps != null) 'tr': targetReps,
    if (targetRir != null) 'trir': targetRir,
    if (prescribed) 'prescribed': true,
    if (accepted.isNotEmpty) 'accepted': accepted.toList(),
  };

  factory SetEntry.fromJson(Map<String, dynamic> j) => SetEntry(
    weight: _dbl(j['w']),
    reps: _int(j['r']),
    rir: _int(j['rir']),
    done: j['done'] as bool? ?? false,
    type: _str(j['type']).isEmpty ? 'Normal' : j['type'] as String,
    note: _str(j['note']),
    rest: _int(j['rest']) ?? 180,
    groupStart: j['group'] as bool? ?? false,
    context: SetContext.fromJson(j['context'] as Map<String, dynamic>?),
    stopReason: _str(j['stop']),
    actualRest: _int(j['actualRest']),
    circuitRestAfter: _int(j['circuitRest']),
    hintWeight: _dbl(j['hw']),
    hintReps: _int(j['hr']),
    targetReps: _int(j['tr']),
    targetRir: _int(j['trir']),
    prescribed: j['prescribed'] as bool? ?? false,
    accepted: {...?(j['accepted'] as List?)?.cast<String>()},
  );
}

double wathanPercent(num reps) {
  if (reps <= 1) return 100.0;
  return 48.8 + 53.8 * math.exp(-0.075 * reps);
}

double? estimatedOneRm(double weight, num reps, num rir) {
  if (weight <= 0 || reps <= 0 || rir < 0) return null;
  final effective = reps + rir < 1 ? 1 : reps + rir;
  return weight / (wathanPercent(effective) / 100);
}

/// Self-rated reps in reserve are reasonably accurate close to failure and drift badly beyond about four, so at
/// most this many count toward an estimate.
const maxCountedRir = 4;

/// The one estimated 1RM used for logged sets everywhere (charts, records, last-time changes, cycle reviews):
/// Wathan on reps plus reps in reserve, with RIR capped at [maxCountedRir]. Unknown RIR counts as 0.
double? setOneRm(double? weight, int? reps, int? rir) {
  if (weight == null || reps == null) return null;
  return estimatedOneRm(weight, reps, math.min(math.max(rir ?? 0, 0), maxCountedRir));
}

/// Whether a set's load × reps counts as volume: a completed working set of an external-load exercise, logged
/// as a total (or with no load basis). Assistance would turn more help into more "volume", bodyweight work has
/// no known total, and per-side or per-implement loads are never guessed into totals, so those are left out.
bool countsAsVolume(SessionExercise exercise, SetEntry set) =>
    set.done &&
    !set.warmup &&
    exercise.loadMode == 'external' &&
    (set.context.loadBasis.isEmpty || set.context.loadBasis == 'total');

/// Load × reps of one set (0 when either is missing); callers decide eligibility with [countsAsVolume].
double setVolume(SetEntry set) => (set.weight ?? 0) * (set.reps ?? 0);

class SessionExercise {
  String name;
  String method;
  String loadMode;
  List<SetEntry> sets;

  /// Guidance lines shown above the sets (progression, deload, load mode…).
  List<String> advice;
  bool notesVisible;

  /// null follows the "collapse completed exercises" setting.
  bool? collapsed;

  /// First-session mesocycle calibration is required for this exercise.
  bool calibrate;

  /// Calibration was entered in this (unsaved) session.
  bool calibrationEntered;

  SessionExercise({
    required this.name,
    required this.sets,
    this.method = 'Straight',
    this.loadMode = 'external',
    List<String>? advice,
    this.notesVisible = false,
    this.collapsed,
    this.calibrate = false,
    this.calibrationEntered = false,
  }) : advice = advice ?? [];

  List<SetEntry> get work => sets.where((s) => !s.warmup).toList();
  int get doneSets => sets.where((s) => s.done).length;
  bool get complete => sets.isNotEmpty && doneSets == sets.length;
  int get restSeconds => sets.isEmpty ? 180 : sets.first.rest;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (method != 'Straight') 'method': method,
    if (loadMode != 'external') 'load': loadMode,
    if (advice.isNotEmpty) 'advice': advice,
    if (notesVisible) 'notes': true,
    if (collapsed != null) 'collapsed': collapsed,
    if (calibrate) 'calibrate': true,
    if (calibrationEntered) 'calEntered': true,
    'sets': sets.map((s) => s.toJson()).toList(),
  };

  factory SessionExercise.fromJson(Map<String, dynamic> j) {
    final rest = _int(j['rest']);
    final rawSets = j['sets'] as List;
    final sets = [for (final s in rawSets) SetEntry.fromJson(s as Map<String, dynamic>)];
    if (rest != null) {
      for (var i = 0; i < rawSets.length; i++) {
        if ((rawSets[i] as Map)['rest'] == null) sets[i].rest = rest;
      }
    }
    final advice = j['advice'];
    return SessionExercise(
      name: j['name'] as String,
      method: canonicalMethod(j['method'] as String?),
      loadMode: normalizeLoadMode(j['load'] as String?),
      advice: advice is String ? (advice.isEmpty ? [] : [advice]) : [...?(advice as List?)?.cast<String>()],
      notesVisible: j['notes'] as bool? ?? false,
      collapsed: j['collapsed'] as bool?,
      calibrate: j['calibrate'] as bool? ?? false,
      calibrationEntered: j['calEntered'] as bool? ?? false,
      sets: sets,
    );
  }
}

/// The optional recovery check-in answered on the finish screen. Every answer is 0, 1 or 2, low to high:
/// pump low / good / great; recovered still sore / just in time / days ago; sleep and overall poor / normal /
/// good. Unanswered questions are absent.
class CheckIn {
  Map<String, int> pump;
  Map<String, int> recovered;
  int? sleep;
  int? overall;

  CheckIn({Map<String, int>? pump, Map<String, int>? recovered, this.sleep, this.overall})
    : pump = pump ?? {},
      recovered = recovered ?? {};

  bool get isEmpty => pump.isEmpty && recovered.isEmpty && sleep == null && overall == null;

  Map<String, dynamic> toJson() => {
    if (pump.isNotEmpty) 'pump': pump,
    if (recovered.isNotEmpty) 'recovered': recovered,
    if (sleep != null) 'sleep': sleep,
    if (overall != null) 'overall': overall,
  };

  static CheckIn? tryJson(Object? j) {
    if (j is! Map) return null;
    int? level(Object? v) => v is num && v >= 0 && v <= 2 ? v.round() : null;
    Map<String, int> levels(Object? m) => {
      if (m is Map)
        for (final e in m.entries)
          if ((e.key, level(e.value)) case (final String muscle, final value?)) muscle: value,
    };
    final parsed = CheckIn(
      pump: levels(j['pump']),
      recovered: levels(j['recovered']),
      sleep: level(j['sleep']),
      overall: level(j['overall']),
    );
    return parsed.isEmpty ? null : parsed;
  }
}

class Session {
  final String id;
  final String? templateId;
  String name;
  String unit;
  DateTime startedAt;
  DateTime? finishedAt;
  double? bodyweight;
  List<SessionExercise> exercises;
  List<ExerciseCircuit> circuits;
  List<SessionExercise> warmupExercises;
  bool warmingUp;
  String? warmupExercise;
  String? cycleId;
  int? microcycle;
  String? phase;
  int? targetRir;
  bool rirLocked;
  bool restLocked;

  /// Workout clock: starts with the first completed set (or a tap), pausable.
  bool clockStarted;
  DateTime? clockRunningSince;
  int clockElapsed;

  /// Original plan's duration estimate, captured at start rather than rebuilt from today's template.
  int? estimatedSeconds;

  /// Recovery check-in from the finish screen, when the user answered it.
  CheckIn? checkIn;

  Session({
    required this.id,
    required this.templateId,
    required this.name,
    required this.unit,
    required this.startedAt,
    this.finishedAt,
    this.bodyweight,
    required this.exercises,
    List<ExerciseCircuit>? circuits,
    List<SessionExercise>? warmupExercises,
    this.warmingUp = false,
    this.warmupExercise,
    this.cycleId,
    this.microcycle,
    this.phase,
    this.targetRir,
    this.rirLocked = false,
    this.restLocked = false,
    this.clockStarted = false,
    this.clockRunningSince,
    this.clockElapsed = 0,
    this.estimatedSeconds,
    this.checkIn,
  }) : circuits = circuits ?? [],
       warmupExercises = warmupExercises ?? [];

  SessionExercise? warmupFor(String name) => warmupExercises.where((e) => e.name == name).firstOrNull;
  bool isWarmupExercise(SessionExercise exercise) => warmupExercises.contains(exercise);

  SessionExercise? get activeWarmup {
    if (!warmingUp) return null;
    if (warmupExercise != null) return warmupFor(warmupExercise!);
    // Older sessions stored a whole-workout phase without a selected exercise.
    return warmupExercises.where((e) => !e.complete).firstOrNull ?? warmupExercises.firstOrNull;
  }

  List<SessionExercise> get visibleExercises {
    final warmup = activeWarmup;
    return [for (final exercise in exercises) warmup?.name == exercise.name ? warmup! : exercise];
  }

  List<SetEntry> visibleSetsFor(SessionExercise exercise) =>
      !isWarmupExercise(exercise) && warmupFor(exercise.name) != null ? exercise.work : exercise.sets;
  bool get warmupsComplete =>
      warmupExercises.isNotEmpty && warmupExercises.every((exercise) => exercise.sets.every((set) => set.done));

  bool get clockRunning => clockRunningSince != null;

  int get clockSeconds {
    final since = clockRunningSince;
    final running = since == null ? 0 : math.max(0, DateTime.now().difference(since).inSeconds);
    return clockElapsed + running;
  }

  /// Time trained: the workout clock when used, otherwise start to finish.
  Duration get duration =>
      clockStarted ? Duration(seconds: clockSeconds) : (finishedAt ?? DateTime.now()).difference(startedAt);

  int get doneSets => exercises.fold(0, (a, e) => a + e.sets.where((s) => s.done && !s.warmup).length);
  int get totalSets => exercises.fold(0, (a, e) => a + e.sets.length);
  int get doneAll => exercises.fold(0, (a, e) => a + e.doneSets);

  /// External load × reps of completed working sets (see [countsAsVolume]).
  double get volume => exercises.fold(
    0.0,
    (a, e) => a + e.sets.where((s) => countsAsVolume(e, s)).fold(0.0, (b, s) => b + setVolume(s)),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'template': templateId,
    'name': name,
    'unit': unit,
    'start': startedAt.toIso8601String(),
    'end': finishedAt?.toIso8601String(),
    if (bodyweight != null) 'bodyweight': bodyweight,
    if (cycleId != null) 'cycle': cycleId,
    if (microcycle != null) 'micro': microcycle,
    if (phase != null) 'phase': phase,
    if (targetRir != null) 'trir': targetRir,
    if (rirLocked) 'rirLock': true,
    if (restLocked) 'restLock': true,
    if (clockStarted) 'clockStarted': true,
    if (clockRunningSince != null) 'clockSince': clockRunningSince!.toUtc().toIso8601String(),
    if (clockElapsed > 0) 'clockElapsed': clockElapsed,
    if (estimatedSeconds != null) 'estimatedSeconds': estimatedSeconds,
    if (checkIn != null && !checkIn!.isEmpty) 'checkIn': checkIn!.toJson(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
    if (circuits.isNotEmpty) 'circuits': circuits.map((c) => c.toJson()).toList(),
    if (warmupExercises.isNotEmpty) 'warmupExercises': warmupExercises.map((e) => e.toJson()).toList(),
    if (warmingUp) 'warmingUp': true,
    if (warmupExercise != null) 'warmupExercise': warmupExercise,
  };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
    id: j['id'] as String,
    templateId: j['template'] as String?,
    name: j['name'] as String,
    unit: j['unit'] as String? ?? 'kg',
    startedAt: DateTime.parse(j['start'] as String),
    finishedAt: j['end'] == null ? null : DateTime.parse(j['end'] as String),
    bodyweight: _dbl(j['bodyweight']),
    cycleId: j['cycle'] as String?,
    microcycle: _int(j['micro']),
    phase: j['phase'] as String?,
    targetRir: _int(j['trir']),
    rirLocked: j['rirLock'] as bool? ?? false,
    restLocked: j['restLock'] as bool? ?? false,
    clockStarted: j['clockStarted'] as bool? ?? false,
    clockRunningSince: j['clockSince'] == null ? null : DateTime.parse(j['clockSince'] as String).toLocal(),
    clockElapsed: _int(j['clockElapsed']) ?? 0,
    estimatedSeconds: _int(j['estimatedSeconds']),
    checkIn: CheckIn.tryJson(j['checkIn']),
    exercises: [for (final e in j['exercises'] as List) SessionExercise.fromJson(e as Map<String, dynamic>)],
    circuits: [for (final c in j['circuits'] as List? ?? []) ExerciseCircuit.fromJson(c as Map<String, dynamic>)],
    warmupExercises: [
      for (final e in j['warmupExercises'] as List? ?? []) SessionExercise.fromJson(e as Map<String, dynamic>),
    ],
    warmingUp: j['warmingUp'] as bool? ?? false,
    warmupExercise: j['warmupExercise'] as String?,
  );
}

/// A rest period started by completing a set. It keeps running past zero
/// ("rest complete") until the next set or an explicit dismiss.
class RestTimer {
  final DateTime startedAt;
  final int totalSeconds;
  final String exercise;
  final int setIndex;
  final bool countdown;
  final bool warmup;

  const RestTimer({
    required this.startedAt,
    required this.totalSeconds,
    required this.exercise,
    this.setIndex = 0,
    this.countdown = false,
    this.warmup = false,
  });

  DateTime get endsAt => startedAt.add(Duration(seconds: totalSeconds));
  int get elapsed => math.max(0, DateTime.now().difference(startedAt).inSeconds);
  int get remainingSeconds => totalSeconds - elapsed;
  bool get overdue => remainingSeconds <= 0;

  Duration get remaining {
    final r = endsAt.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  RestTimer copyWith({int? totalSeconds, bool? countdown, String? exercise}) => RestTimer(
    startedAt: startedAt,
    totalSeconds: totalSeconds ?? this.totalSeconds,
    exercise: exercise ?? this.exercise,
    setIndex: setIndex,
    countdown: countdown ?? this.countdown,
    warmup: warmup,
  );

  Map<String, dynamic> toJson() => {
    'start': startedAt.toUtc().toIso8601String(),
    'total': totalSeconds,
    'exercise': exercise,
    'set': setIndex,
    if (countdown) 'countdown': true,
    if (warmup) 'warmup': true,
  };

  factory RestTimer.fromJson(Map<String, dynamic> j) {
    final total = _int(j['total']) ?? 0;
    final start = j['start'] != null
        ? DateTime.parse(j['start'] as String).toLocal()
        : DateTime.parse(j['ends'] as String).subtract(Duration(seconds: total));
    return RestTimer(
      startedAt: start,
      totalSeconds: total,
      exercise: _str(j['exercise']),
      setIndex: _int(j['set']) ?? 0,
      countdown: j['countdown'] as bool? ?? false,
      warmup: j['warmup'] as bool? ?? false,
    );
  }
}
