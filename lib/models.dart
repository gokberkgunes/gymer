import 'dart:math' as math;

import 'logic/methods.dart';
import 'logic/plates.dart';
import 'logic/status_icons.dart';

int? _int(Object? v) => v is int ? v : (v is num ? v.round() : null);
double? _dbl(Object? v) => (v as num?)?.toDouble();

/// A saved plate list; the untouched former default becomes the current default (null).
List<double>? _plates(Object? v, List<double> former) {
  if (v is! List) return null;
  final list = [for (final x in v) (x as num).toDouble()];
  if (list.length != former.length) return list;
  for (var i = 0; i < list.length; i++) {
    if (list[i] != former[i]) return list;
  }
  return null;
}

String _str(Object? v) => v is String ? v : '';

/// Declared logging meaning of a set; blanks are unknown and never converted.
class SetContext {
  final String setup;
  final String loadBasis; // '' | total | per_implement | per_side
  final String repBasis; // '' | total | per_side
  final String side; // '' | bilateral | left | right | both_separately

  const SetContext({this.setup = '', this.loadBasis = '', this.repBasis = '', this.side = ''});

  static const loadBasisLabels = {
    '': 'Unknown / not recorded',
    'total': 'Total load',
    'per_implement': 'Per implement (e.g. one dumbbell)',
    'per_side': 'Load per side',
  };
  static const repBasisLabels = {
    '': 'Unknown / not recorded',
    'total': 'Total repetitions',
    'per_side': 'Repetitions per side',
  };
  static const sideLabels = {
    '': 'Unknown / not recorded',
    'bilateral': 'Bilateral',
    'left': 'Left',
    'right': 'Right',
    'both_separately': 'Both sides in one entry',
  };

  bool get isEmpty => setup.isEmpty && loadBasis.isEmpty && repBasis.isEmpty && side.isEmpty;

  SetContext copyWith({String? setup, String? loadBasis, String? repBasis, String? side}) => SetContext(
    setup: setup ?? this.setup,
    loadBasis: loadBasis ?? this.loadBasis,
    repBasis: repBasis ?? this.repBasis,
    side: side ?? this.side,
  );

  @override
  bool operator ==(Object other) =>
      other is SetContext &&
      other.setup == setup &&
      other.loadBasis == loadBasis &&
      other.repBasis == repBasis &&
      other.side == side;

  @override
  int get hashCode => Object.hash(setup, loadBasis, repBasis, side);

  String summary() => [
    if (setup.isNotEmpty) 'Setup: $setup',
    if (loadBasis.isNotEmpty) 'Load basis: ${loadBasisLabels[loadBasis]}',
    if (repBasis.isNotEmpty) 'Rep count basis: ${repBasisLabels[repBasis]}',
    if (side.isNotEmpty) 'Side: ${sideLabels[side]}',
  ].join(' · ');

  Map<String, dynamic> toJson() => {
    if (setup.isNotEmpty) 'setup': setup,
    if (loadBasis.isNotEmpty) 'load': loadBasis,
    if (repBasis.isNotEmpty) 'reps': repBasis,
    if (side.isNotEmpty) 'side': side,
  };

  factory SetContext.fromJson(Map<String, dynamic>? j) => j == null
      ? const SetContext()
      : SetContext(
          setup: _str(j['setup']),
          loadBasis: _str(j['load']),
          repBasis: _str(j['reps']),
          side: _str(j['side']),
        );
}

class Exercise {
  final String name;
  final List<String> primary;
  final List<String> secondary;
  final String equipment;
  final String description;
  final String note;
  final bool favourite;
  final String loadMode;
  final double? incrementKg;
  final double? incrementLb;

  /// Bar (or sled) weight for the plate calculator, overriding the default; per unit like increments.
  final double? barKg;
  final double? barLb;
  final int repMin;
  final int repMax;
  final bool autoProgression;
  final int? setSeconds;
  final SetContext context;

  const Exercise({
    required this.name,
    this.primary = const [],
    this.secondary = const [],
    this.equipment = '',
    this.description = '',
    this.note = '',
    this.favourite = false,
    this.loadMode = 'external',
    this.incrementKg,
    this.incrementLb,
    this.barKg,
    this.barLb,
    this.repMin = 8,
    this.repMax = 12,
    this.autoProgression = true,
    this.setSeconds,
    this.context = const SetContext(),
  });

  Exercise copyWith({
    String? name,
    List<String>? primary,
    List<String>? secondary,
    String? equipment,
    String? description,
    String? note,
    bool? favourite,
    String? loadMode,
    double? Function()? incrementKg,
    double? Function()? incrementLb,
    double? Function()? barKg,
    double? Function()? barLb,
    int? repMin,
    int? repMax,
    bool? autoProgression,
    int? Function()? setSeconds,
    SetContext? context,
  }) => Exercise(
    name: name ?? this.name,
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    equipment: equipment ?? this.equipment,
    description: description ?? this.description,
    note: note ?? this.note,
    favourite: favourite ?? this.favourite,
    loadMode: loadMode ?? this.loadMode,
    incrementKg: incrementKg != null ? incrementKg() : this.incrementKg,
    incrementLb: incrementLb != null ? incrementLb() : this.incrementLb,
    barKg: barKg != null ? barKg() : this.barKg,
    barLb: barLb != null ? barLb() : this.barLb,
    repMin: repMin ?? this.repMin,
    repMax: repMax ?? this.repMax,
    autoProgression: autoProgression ?? this.autoProgression,
    setSeconds: setSeconds != null ? setSeconds() : this.setSeconds,
    context: context ?? this.context,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'primary': primary,
    'secondary': secondary,
    'equipment': equipment,
    'description': description,
    if (note.isNotEmpty) 'note': note,
    if (favourite) 'favourite': true,
    'loadMode': loadMode,
    'incKg': incrementKg,
    'incLb': incrementLb,
    if (barKg != null) 'barKg': barKg,
    if (barLb != null) 'barLb': barLb,
    'repMin': repMin,
    'repMax': repMax,
    'auto': autoProgression,
    if (setSeconds != null) 'setSeconds': setSeconds,
    if (!context.isEmpty) 'context': context.toJson(),
  };

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
    name: j['name'] as String,
    primary: List<String>.from(j['primary'] ?? const []),
    secondary: List<String>.from(j['secondary'] ?? const []),
    equipment: _str(j['equipment']),
    description: _str(j['description']),
    note: _str(j['note']),
    favourite: j['favourite'] as bool? ?? false,
    loadMode: normalizeLoadMode(j['loadMode'] as String?),
    incrementKg: _dbl(j['incKg']),
    incrementLb: _dbl(j['incLb']),
    barKg: _dbl(j['barKg']),
    barLb: _dbl(j['barLb']),
    repMin: _int(j['repMin']) ?? 8,
    repMax: _int(j['repMax']) ?? 12,
    autoProgression: j['auto'] as bool? ?? true,
    setSeconds: _int(j['setSeconds']),
    context: SetContext.fromJson(j['context'] as Map<String, dynamic>?),
  );
}

/// One planned set of a template: role, defaults and the rest after it.
class TemplateSet {
  String type;
  double? weight;
  int? reps;
  int rest;
  bool groupStart;

  /// Explicit per-set logging context; null inherits the exercise defaults.
  SetContext? context;

  TemplateSet({this.type = 'Normal', this.weight, this.reps, this.rest = 180, this.groupStart = false, this.context});

  TemplateSet copy() =>
      TemplateSet(type: type, weight: weight, reps: reps, rest: rest, groupStart: groupStart, context: context);

  Map<String, dynamic> toJson() => {
    'type': type,
    if (weight != null) 'w': weight,
    if (reps != null) 'r': reps,
    'rest': rest,
    if (groupStart) 'group': true,
    if (context != null) 'context': context!.toJson(),
  };

  factory TemplateSet.fromJson(Map<String, dynamic> j) => TemplateSet(
    type: _str(j['type']).isEmpty ? 'Normal' : j['type'] as String,
    weight: _dbl(j['w']),
    reps: _int(j['r']),
    rest: _int(j['rest']) ?? 180,
    groupStart: j['group'] as bool? ?? false,
    context: j['context'] == null ? null : SetContext.fromJson(j['context'] as Map<String, dynamic>),
  );
}

class TemplateExercise {
  String name;
  String method;
  List<TemplateSet> sets;

  TemplateExercise({required this.name, this.method = 'Straight', List<TemplateSet>? sets})
    : sets = sets ?? [for (final t in plannedSetTypes(method, warmups: 0, work: 3)) TemplateSet(type: t)];

  /// Convenience for building a plan from set roles that share one rest time.
  factory TemplateExercise.typed({
    required String name,
    String method = 'Straight',
    required List<String> types,
    int rest = 180,
  }) => TemplateExercise(
    name: name,
    method: canonicalMethod(method),
    sets: [for (final t in types) TemplateSet(type: t, rest: rest)],
  );

  List<String> get types => [for (final s in sets) s.type];
  int get workSets => sets.where((s) => !isWarmup(s.type)).length;
  int get warmups => sets.where((s) => isWarmup(s.type)).length;
  int get restSeconds => sets.isEmpty ? 180 : sets.firstWhere((s) => !isWarmup(s.type), orElse: () => sets.first).rest;

  /// Rebuild warm-up/work counts or the method while keeping per-set details.
  void replan({String? method, int? warmups, int? work}) {
    this.method = canonicalMethod(method ?? this.method);
    final w = warmups ?? this.warmups;
    final n = work ?? workSets;
    final oldWarm = sets.where((s) => isWarmup(s.type)).toList();
    final oldWork = sets.where((s) => !isWarmup(s.type)).toList();
    final rest = restSeconds;
    TemplateSet from(List<TemplateSet> pool, int i) =>
        i < pool.length ? pool[i] : (pool.isEmpty ? TemplateSet(rest: rest) : (pool.last.copy()..groupStart = false));
    sets = [
      for (var i = 0; i < w; i++) from(oldWarm, i)..type = 'Warm-up',
      for (var i = 0; i < n; i++) from(oldWork, i)..type = (i < oldWork.length ? oldWork[i].type : 'Normal'),
    ];
    reconcile();
  }

  void reconcile() {
    final fixed = reconcileMethodSets(method, [for (final s in sets) (s.type, s.groupStart)]);
    for (var i = 0; i < sets.length; i++) {
      sets[i].type = fixed[i].$1;
      sets[i].groupStart = fixed[i].$2;
    }
  }

  Map<String, dynamic> toJson() => {'name': name, 'method': method, 'sets': sets.map((s) => s.toJson()).toList()};

  factory TemplateExercise.fromJson(Map<String, dynamic> j) {
    final method = canonicalMethod(j['method'] as String?);
    final rest = _int(j['rest']) ?? 180;
    final List<TemplateSet> sets;
    if (j['sets'] is List) {
      sets = [for (final s in j['sets'] as List) TemplateSet.fromJson(s as Map<String, dynamic>)];
    } else if (j['types'] is List) {
      sets = [for (final t in j['types'] as List) TemplateSet(type: t as String, rest: rest)];
    } else {
      sets = [
        for (final t in plannedSetTypes(method, warmups: 0, work: _int(j['sets']) ?? 3))
          TemplateSet(type: t, rest: rest),
      ];
    }
    return TemplateExercise(name: j['name'] as String, method: method, sets: sets);
  }
}

/// Exercises performed in alternating rounds, with one shared rest between rounds.
class ExerciseCircuit {
  final String id;
  List<String> exercises;
  int rest;

  ExerciseCircuit({required this.id, required this.exercises, this.rest = 120});

  Map<String, dynamic> toJson() => {'id': id, 'exercises': exercises, 'rest': rest};

  factory ExerciseCircuit.fromJson(Map<String, dynamic> j) => ExerciseCircuit(
    id: j['id'] as String,
    exercises: (j['exercises'] as List).cast<String>().toList(),
    rest: math.max(0, _int(j['rest']) ?? 120),
  );
}

class WorkoutTemplate {
  final String id;
  String name;
  String description;
  int setSeconds;
  int setOverhead;
  int transition;
  int sessionOverhead;
  List<TemplateExercise> exercises;
  List<ExerciseCircuit> circuits;

  WorkoutTemplate({
    required this.id,
    required this.name,
    required this.exercises,
    List<ExerciseCircuit>? circuits,
    this.description = '',
    this.setSeconds = 45,
    this.setOverhead = 30,
    this.transition = 300,
    this.sessionOverhead = 300,
  }) : circuits = circuits ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'setSeconds': setSeconds,
    'setOverhead': setOverhead,
    'transition': transition,
    'sessionOverhead': sessionOverhead,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    if (circuits.isNotEmpty) 'circuits': circuits.map((c) => c.toJson()).toList(),
  };

  factory WorkoutTemplate.fromJson(Map<String, dynamic> j) => WorkoutTemplate(
    id: j['id'] as String,
    name: j['name'] as String,
    description: _str(j['description']),
    setSeconds: _int(j['setSeconds']) ?? 45,
    setOverhead: _int(j['setOverhead']) ?? 30,
    transition: _int(j['transition']) ?? 300,
    sessionOverhead: _int(j['sessionOverhead']) ?? 300,
    exercises: [for (final e in j['exercises'] as List) TemplateExercise.fromJson(e as Map<String, dynamic>)],
    circuits: [for (final c in j['circuits'] as List? ?? []) ExerciseCircuit.fromJson(c as Map<String, dynamic>)],
  );
}

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
  double get volume => done && !warmup ? (weight ?? 0) * (reps ?? 0) : 0;

  /// Wathan estimate on effective reps (reps + RIR); unknown RIR counts as 0.
  double? get e1rm {
    final w = weight, r = reps;
    if (!done || warmup || w == null || r == null || w <= 0 || r <= 0) return null;
    return estimatedOneRm(w, r, rir ?? 0);
  }

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

class Session {
  final String id;
  final String? templateId;
  String name;
  String unit;
  DateTime startedAt;
  DateTime? finishedAt;
  List<SessionExercise> exercises;
  List<ExerciseCircuit> circuits;
  List<SessionExercise> warmupExercises;
  bool warmingUp;
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

  Session({
    required this.id,
    required this.templateId,
    required this.name,
    required this.unit,
    required this.startedAt,
    this.finishedAt,
    required this.exercises,
    List<ExerciseCircuit>? circuits,
    List<SessionExercise>? warmupExercises,
    this.warmingUp = false,
    this.cycleId,
    this.microcycle,
    this.phase,
    this.targetRir,
    this.rirLocked = false,
    this.restLocked = false,
    this.clockStarted = false,
    this.clockRunningSince,
    this.clockElapsed = 0,
  }) : circuits = circuits ?? [],
       warmupExercises = warmupExercises ?? [];

  List<SessionExercise> get visibleExercises => warmingUp ? warmupExercises : exercises;
  List<SetEntry> visibleSetsFor(SessionExercise exercise) =>
      !warmingUp && warmupExercises.isNotEmpty ? exercise.work : exercise.sets;
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
  double get volume => exercises.fold(0.0, (a, e) => a + e.sets.fold(0.0, (b, s) => b + s.volume));

  Map<String, dynamic> toJson() => {
    'id': id,
    'template': templateId,
    'name': name,
    'unit': unit,
    'start': startedAt.toIso8601String(),
    'end': finishedAt?.toIso8601String(),
    if (cycleId != null) 'cycle': cycleId,
    if (microcycle != null) 'micro': microcycle,
    if (phase != null) 'phase': phase,
    if (targetRir != null) 'trir': targetRir,
    if (rirLocked) 'rirLock': true,
    if (restLocked) 'restLock': true,
    if (clockStarted) 'clockStarted': true,
    if (clockRunningSince != null) 'clockSince': clockRunningSince!.toUtc().toIso8601String(),
    if (clockElapsed > 0) 'clockElapsed': clockElapsed,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    if (circuits.isNotEmpty) 'circuits': circuits.map((c) => c.toJson()).toList(),
    if (warmupExercises.isNotEmpty) 'warmupExercises': warmupExercises.map((e) => e.toJson()).toList(),
    if (warmingUp) 'warmingUp': true,
  };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
    id: j['id'] as String,
    templateId: j['template'] as String?,
    name: j['name'] as String,
    unit: j['unit'] as String? ?? 'kg',
    startedAt: DateTime.parse(j['start'] as String),
    finishedAt: j['end'] == null ? null : DateTime.parse(j['end'] as String),
    cycleId: j['cycle'] as String?,
    microcycle: _int(j['micro']),
    phase: j['phase'] as String?,
    targetRir: _int(j['trir']),
    rirLocked: j['rirLock'] as bool? ?? false,
    restLocked: j['restLock'] as bool? ?? false,
    clockStarted: j['clockStarted'] as bool? ?? false,
    clockRunningSince: j['clockSince'] == null ? null : DateTime.parse(j['clockSince'] as String).toLocal(),
    clockElapsed: _int(j['clockElapsed']) ?? 0,
    exercises: [for (final e in j['exercises'] as List) SessionExercise.fromJson(e as Map<String, dynamic>)],
    circuits: [for (final c in j['circuits'] as List? ?? []) ExerciseCircuit.fromJson(c as Map<String, dynamic>)],
    warmupExercises: [
      for (final e in j['warmupExercises'] as List? ?? []) SessionExercise.fromJson(e as Map<String, dynamic>),
    ],
    warmingUp: j['warmingUp'] as bool? ?? false,
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

/// One planned day's exception to the repeating schedule.
class DayEvent {
  String templateId;
  String status; // planned | missed | unplanned
  DateTime? movedTo;
  String? sessionId;

  DayEvent({required this.templateId, this.status = 'planned', this.movedTo, this.sessionId});

  Map<String, dynamic> toJson() => {
    'template': templateId,
    'status': status,
    if (movedTo != null) 'moved': dateKey(movedTo!),
    if (sessionId != null) 'session': sessionId,
  };

  factory DayEvent.fromJson(Map<String, dynamic> j) => DayEvent(
    templateId: j['template'] as String,
    status: j['status'] as String? ?? 'planned',
    movedTo: j['moved'] == null ? null : DateTime.parse(j['moved'] as String),
    sessionId: j['session'] as String?,
  );
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day arithmetic; Duration(days:) drifts by an hour across DST.
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

class Mesocycle {
  final String id;
  String name;
  DateTime start;
  int microDays;
  int length;
  int deloadMicro;
  int startRir;
  int endRir;
  int deloadRir;
  bool deloadManual;
  int deloadLoadPct;
  int deloadVolumePct;
  Map<int, int> weekRir;
  String rirScheduleMode; // '' | steady | custom
  bool rirLock;
  bool restLock;
  bool active;
  bool setupComplete;
  Map<int, String> schedule;
  Map<String, DayEvent> events;

  Mesocycle({
    required this.id,
    this.name = 'Mesocycle',
    required this.start,
    this.microDays = 7,
    this.length = 5,
    this.deloadMicro = 1,
    this.startRir = 3,
    this.endRir = 1,
    this.deloadRir = 4,
    this.deloadManual = false,
    this.deloadLoadPct = 90,
    this.deloadVolumePct = 50,
    Map<int, int>? weekRir,
    this.rirScheduleMode = '',
    this.rirLock = true,
    this.restLock = false,
    this.active = true,
    this.setupComplete = true,
    Map<int, String>? schedule,
    Map<String, DayEvent>? events,
  }) : weekRir = weekRir ?? {},
       schedule = schedule ?? {},
       events = events ?? {};

  /// "week" for 7-day microcycles, otherwise "microcycle".
  String periodNoun({bool plural = false}) =>
      microDays == 7 ? (plural ? 'weeks' : 'week') : (plural ? 'microcycles' : 'microcycle');
  String get periodShort => microDays == 7 ? 'W' : 'M';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start': dateKey(start),
    'microDays': microDays,
    'length': length,
    'deloadMicro': deloadMicro,
    'startRir': startRir,
    'endRir': endRir,
    'deloadRir': deloadRir,
    'deloadManual': deloadManual,
    'deloadLoadPct': deloadLoadPct,
    'deloadVolumePct': deloadVolumePct,
    'weekRir': {for (final e in weekRir.entries) '${e.key}': e.value},
    if (rirScheduleMode.isNotEmpty) 'rirMode': rirScheduleMode,
    'rirLock': rirLock,
    'restLock': restLock,
    'active': active,
    if (!setupComplete) 'setupComplete': false,
    'schedule': {for (final e in schedule.entries) '${e.key}': e.value},
    'events': {for (final e in events.entries) e.key: e.value.toJson()},
  };

  factory Mesocycle.fromJson(Map<String, dynamic> j) => Mesocycle(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Mesocycle',
    start: DateTime.parse(j['start'] as String),
    microDays: _int(j['microDays']) ?? 7,
    length: _int(j['length']) ?? 5,
    deloadMicro: _int(j['deloadMicro']) ?? 1,
    startRir: _int(j['startRir']) ?? 3,
    endRir: _int(j['endRir']) ?? 1,
    deloadRir: _int(j['deloadRir']) ?? 4,
    deloadManual: j['deloadManual'] as bool? ?? false,
    deloadLoadPct: _int(j['deloadLoadPct']) ?? 90,
    deloadVolumePct: _int(j['deloadVolumePct']) ?? 50,
    weekRir: {for (final e in (j['weekRir'] as Map? ?? {}).entries) int.parse('${e.key}'): _int(e.value)!},
    rirScheduleMode: _str(j['rirMode']),
    rirLock: j['rirLock'] as bool? ?? true,
    restLock: j['restLock'] as bool? ?? false,
    active: j['active'] as bool? ?? true,
    setupComplete: j['setupComplete'] as bool? ?? true,
    schedule: {for (final e in (j['schedule'] as Map? ?? {}).entries) int.parse('${e.key}'): e.value as String},
    events: {
      for (final e in (j['events'] as Map? ?? {}).entries)
        e.key as String: DayEvent.fromJson(e.value as Map<String, dynamic>),
    },
  );
}

/// Weight jumps per equipment type, (kg, lb). Defaults match the Flet app.
const defaultIncrements = {
  'Barbell': (5.0, 10.0),
  'Dumbbell': (2.5, 5.0),
  'Plate loaded': (5.0, 10.0),
  'Weight-stack machine': (5.0, 10.0),
};

const equipmentTypes = ['Barbell', 'Dumbbell', 'Plate loaded', 'Weight-stack machine'];

/// Set roles offered by the set-type database, as in the Flet app.
const defaultSetTypes = [
  'Normal',
  'Warm-up',
  'Top Set',
  'Back-off',
  'AMRAP',
  'Failure',
  'Drop Set',
  'Mechanical Drop Set',
  'Rest-Pause',
  'Myo-Reps',
  'Activation',
  'Myo-set',
  'Myo-Rep Match',
  'Cluster Set',
  'Paused',
  'Tempo',
  'Partial',
  'Burnout',
];

/// A location's physical plate inventory. Counts are pairs, not individual plates.
class PlateProfile {
  final String id;
  String name;
  double barKg;
  double barLb;
  List<double> platesKg;
  List<double> platesLb;
  bool limitedPairs;
  Map<double, int> pairsKg;
  Map<double, int> pairsLb;

  PlateProfile({
    required this.id,
    required this.name,
    this.barKg = defaultBarKg,
    this.barLb = defaultBarLb,
    List<double>? platesKg,
    List<double>? platesLb,
    this.limitedPairs = false,
    Map<double, int>? pairsKg,
    Map<double, int>? pairsLb,
  }) : platesKg = List.of(platesKg ?? defaultPlatesKg),
       platesLb = List.of(platesLb ?? defaultPlatesLb),
       pairsKg = Map.of(pairsKg ?? {}),
       pairsLb = Map.of(pairsLb ?? {});

  int pairsFor(double plate, String unit) => (unit == 'lb' ? pairsLb : pairsKg)[plate] ?? 1;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'barKg': barKg,
    'barLb': barLb,
    'platesKg': platesKg,
    'platesLb': platesLb,
    'limitedPairs': limitedPairs,
    'pairsKg': {for (final e in pairsKg.entries) '${e.key}': e.value},
    'pairsLb': {for (final e in pairsLb.entries) '${e.key}': e.value},
  };

  factory PlateProfile.fromJson(Map<String, dynamic> j) {
    Map<double, int> counts(Object? value) => {
      for (final e in (value as Map? ?? {}).entries)
        if (double.tryParse('${e.key}') case final weight?)
          if (weight.isFinite && weight > 0 && (_int(e.value) ?? 0) >= 0) weight: _int(e.value)!,
    };
    return PlateProfile(
      id: j['id'] as String,
      name: j['name'] as String,
      barKg: _dbl(j['barKg']) ?? defaultBarKg,
      barLb: _dbl(j['barLb']) ?? defaultBarLb,
      platesKg: (j['platesKg'] as List?)?.map((v) => (v as num).toDouble()).toList(),
      platesLb: (j['platesLb'] as List?)?.map((v) => (v as num).toDouble()).toList(),
      limitedPairs: j['limitedPairs'] as bool? ?? false,
      pairsKg: counts(j['pairsKg']),
      pairsLb: counts(j['pairsLb']),
    );
  }
}

class Settings {
  String unit;
  int defaultRest;
  int defaultSets;
  bool trackRir;
  bool haptics;
  bool restHaptics;
  bool restSound;
  bool keepAwake;

  /// How rest is shown outside the app: live (sticky status-bar timer), alarm ("Rest over"
  /// notification), both, or off.
  String restNotice;

  /// Status-bar timer icons: during rest and in overtime (keys from logic/status_icons.dart).
  bool customIcons;
  String restIcon;
  String overtimeIcon;

  /// What the status-bar chip shows next to the icon: 'time' (live time) or 'text' ([chipText],
  /// up to 7 characters).
  String chipMode;
  String chipText;
  bool showPreviousReps;
  bool dimCompleted;
  bool collapseCompleted;
  List<String> pinnedExerciseActions;
  bool requirePreviousSet;
  bool updateFollowingDefaults;
  bool enterCompletesSet;
  bool enterMovesToNextSet;
  bool enterClosesKeyboard;
  bool backspaceMovesToPreviousSet;
  String timerMode; // both | floating | nearset | off
  String plannedRestDisplay; // hide | smart | always
  String defaultTimerDisplay; // elapsed | countdown
  int repMaxTargetReps;
  List<String> setTypes;
  Map<String, (double, double)> increments;

  List<PlateProfile> plateProfiles;
  String selectedPlateProfile;
  bool groupRepeatedPlates;
  int accent;
  String themeMode;
  String background;
  int rounding;
  String density;
  int setSpacing;
  double fontScale;
  double uiScale;

  Settings({
    this.unit = 'kg',
    this.defaultRest = 180,
    this.defaultSets = 3,
    this.trackRir = true,
    this.haptics = true,
    this.restHaptics = true,
    this.restSound = false,
    this.keepAwake = true,
    this.restNotice = 'live',
    this.customIcons = false,
    this.restIcon = 'muscle',
    this.overtimeIcon = 'warning',
    this.chipMode = 'time',
    this.chipText = '',
    this.showPreviousReps = false,
    this.dimCompleted = true,
    this.collapseCompleted = true,
    List<String>? pinnedExerciseActions,
    this.requirePreviousSet = false,
    this.updateFollowingDefaults = false,
    this.enterCompletesSet = true,
    this.enterMovesToNextSet = false,
    this.enterClosesKeyboard = true,
    this.backspaceMovesToPreviousSet = false,
    this.timerMode = 'both',
    this.plannedRestDisplay = 'hide',
    this.defaultTimerDisplay = 'elapsed',
    this.repMaxTargetReps = 8,
    List<String>? setTypes,
    Map<String, (double, double)>? increments,
    double barKg = defaultBarKg,
    double barLb = defaultBarLb,
    List<double>? platesKg,
    List<double>? platesLb,
    List<PlateProfile>? plateProfiles,
    this.selectedPlateProfile = 'gym',
    this.groupRepeatedPlates = false,
    this.accent = 0,
    this.themeMode = 'system',
    this.background = 'auto',
    this.rounding = 18,
    this.density = 'normal',
    this.setSpacing = 3,
    this.fontScale = 1.0,
    this.uiScale = 1.0,
  }) : pinnedExerciseActions = pinnedExerciseActions ?? [],
       setTypes = setTypes ?? List.of(defaultSetTypes),
       increments = increments ?? Map.of(defaultIncrements),
       plateProfiles = plateProfiles != null && plateProfiles.isNotEmpty
           ? plateProfiles
           : [PlateProfile(id: 'gym', name: 'Gym', barKg: barKg, barLb: barLb, platesKg: platesKg, platesLb: platesLb)];

  PlateProfile get plateProfile =>
      plateProfiles.where((profile) => profile.id == selectedPlateProfile).firstOrNull ?? plateProfiles.first;
  double get barKg => plateProfile.barKg;
  set barKg(double value) => plateProfile.barKg = value;
  double get barLb => plateProfile.barLb;
  set barLb(double value) => plateProfile.barLb = value;
  List<double> get platesKg => plateProfile.platesKg;
  set platesKg(List<double> value) => plateProfile.platesKg = value;
  List<double> get platesLb => plateProfile.platesLb;
  set platesLb(List<double> value) => plateProfile.platesLb = value;

  double get bar => unit == 'lb' ? barLb : barKg;
  List<double> get plates => unit == 'lb' ? platesLb : platesKg;
  Map<double, int>? get platePairs =>
      plateProfile.limitedPairs ? {for (final plate in plates) plate: plateProfile.pairsFor(plate, unit)} : null;

  bool get floatingTimer => timerMode == 'both' || timerMode == 'floating';
  bool get nearSetTimer => timerMode == 'both' || timerMode == 'nearset';

  void resetAppearance() {
    final d = Settings();
    accent = d.accent;
    themeMode = d.themeMode;
    background = d.background;
    rounding = d.rounding;
    density = d.density;
    setSpacing = d.setSpacing;
    fontScale = d.fontScale;
    uiScale = d.uiScale;
    dimCompleted = d.dimCompleted;
  }

  Map<String, dynamic> toJson() => {
    'unit': unit,
    'defaultRest': defaultRest,
    'defaultSets': defaultSets,
    'trackRir': trackRir,
    'haptics': haptics,
    'restHaptics': restHaptics,
    'restSound': restSound,
    'keepAwake': keepAwake,
    'restNotice': restNotice,
    'customIcons': customIcons,
    'restIcon': restIcon,
    'overtimeIcon': overtimeIcon,
    'chipMode': chipMode,
    'chipText': chipText,
    'showPreviousReps': showPreviousReps,
    'dimCompleted': dimCompleted,
    'collapseCompleted': collapseCompleted,
    'pinnedExerciseActions': pinnedExerciseActions,
    'requirePreviousSet': requirePreviousSet,
    'updateFollowingDefaults': updateFollowingDefaults,
    'enterCompletesSet': enterCompletesSet,
    'enterMovesToNextSet': enterMovesToNextSet,
    'enterClosesKeyboard': enterClosesKeyboard,
    'backspaceMovesToPreviousSet': backspaceMovesToPreviousSet,
    'timerMode': timerMode,
    'plannedRestDisplay': plannedRestDisplay,
    'defaultTimerDisplay': defaultTimerDisplay,
    'repMaxTargetReps': repMaxTargetReps,
    'setTypes': setTypes,
    'increments': {
      for (final e in increments.entries) e.key: [e.value.$1, e.value.$2],
    },
    'barKg': barKg,
    'barLb': barLb,
    'platesKg': platesKg,
    'platesLb': platesLb,
    'plateProfiles': plateProfiles.map((profile) => profile.toJson()).toList(),
    'selectedPlateProfile': plateProfile.id,
    'groupRepeatedPlates': groupRepeatedPlates,
    'accent': accent,
    'themeMode': themeMode,
    'background': background,
    'rounding': rounding,
    'density': density,
    'setSpacing': setSpacing,
    'fontScale': fontScale,
    'uiScale': uiScale,
  };

  factory Settings.fromJson(Map<String, dynamic> j) {
    final d = Settings();
    bool b(String k, bool fallback) => j[k] as bool? ?? fallback;
    String s(String k, String fallback, Set<String> allowed) => allowed.contains(j[k]) ? j[k] as String : fallback;
    return Settings(
      unit: s('unit', 'kg', {'kg', 'lb'}),
      defaultRest: _int(j['defaultRest']) ?? d.defaultRest,
      defaultSets: _int(j['defaultSets']) ?? d.defaultSets,
      trackRir: b('trackRir', d.trackRir),
      haptics: b('haptics', d.haptics),
      restHaptics: b('restHaptics', d.restHaptics),
      restSound: b('restSound', d.restSound),
      keepAwake: b('keepAwake', d.keepAwake),
      restNotice: s('restNotice', d.restNotice, {'live', 'alarm', 'both', 'off'}),
      customIcons: b('customIcons', d.customIcons),
      restIcon: s('restIcon', d.restIcon, {for (final (k, _) in restIcons) k}),
      overtimeIcon: s('overtimeIcon', d.overtimeIcon, {for (final (k, _) in overtimeIcons) k}),
      chipMode: s('chipMode', d.chipMode, {'time', 'text'}),
      chipText: j['chipText'] is String ? (j['chipText'] as String) : d.chipText,
      showPreviousReps: b('showPreviousReps', d.showPreviousReps),
      dimCompleted: b('dimCompleted', d.dimCompleted),
      collapseCompleted: b('collapseCompleted', d.collapseCompleted),
      pinnedExerciseActions: j['pinnedExerciseActions'] is List
          ? (j['pinnedExerciseActions'] as List).whereType<String>().toList()
          : null,
      requirePreviousSet: b('requirePreviousSet', d.requirePreviousSet),
      updateFollowingDefaults: b('updateFollowingDefaults', d.updateFollowingDefaults),
      enterCompletesSet: b('enterCompletesSet', d.enterCompletesSet),
      enterMovesToNextSet: b('enterMovesToNextSet', d.enterMovesToNextSet),
      enterClosesKeyboard: b('enterClosesKeyboard', d.enterClosesKeyboard),
      backspaceMovesToPreviousSet: b('backspaceMovesToPreviousSet', d.backspaceMovesToPreviousSet),
      timerMode: s('timerMode', d.timerMode, {'both', 'floating', 'nearset', 'off'}),
      plannedRestDisplay: s('plannedRestDisplay', d.plannedRestDisplay, {'hide', 'smart', 'always'}),
      defaultTimerDisplay: s('defaultTimerDisplay', d.defaultTimerDisplay, {'elapsed', 'countdown'}),
      repMaxTargetReps: _int(j['repMaxTargetReps']) ?? d.repMaxTargetReps,
      setTypes: j['setTypes'] is List ? List<String>.from(j['setTypes'] as List) : null,
      increments: j['increments'] == null
          ? null
          : {
              for (final e in (j['increments'] as Map).entries)
                e.key as String: (((e.value as List)[0] as num).toDouble(), ((e.value as List)[1] as num).toDouble()),
            },
      barKg: _dbl(j['barKg']) ?? d.barKg,
      barLb: _dbl(j['barLb']) ?? d.barLb,
      platesKg: _plates(j['platesKg'], formerPlatesKg),
      platesLb: _plates(j['platesLb'], formerPlatesLb),
      plateProfiles: (j['plateProfiles'] as List?)
          ?.map((profile) => PlateProfile.fromJson(profile as Map<String, dynamic>))
          .toList(),
      selectedPlateProfile: _str(j['selectedPlateProfile']).isEmpty ? 'gym' : j['selectedPlateProfile'] as String,
      groupRepeatedPlates: b('groupRepeatedPlates', d.groupRepeatedPlates),
      accent: _int(j['accent']) ?? d.accent,
      themeMode: s('themeMode', d.themeMode, {'system', 'light', 'dark'}),
      background: _str(j['background']).isEmpty ? d.background : j['background'] as String,
      rounding: _int(j['rounding']) ?? d.rounding,
      density: s('density', d.density, {'compact', 'normal', 'roomy'}),
      setSpacing: _int(j['setSpacing']) ?? d.setSpacing,
      fontScale: _dbl(j['fontScale']) ?? d.fontScale,
      uiScale: _dbl(j['uiScale']) ?? d.uiScale,
    );
  }
}
