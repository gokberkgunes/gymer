part of '../models.dart';

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
