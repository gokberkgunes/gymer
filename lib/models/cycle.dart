part of '../models.dart';

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

/// A coaching change to one exercise's working sets, kept on the cycle so the saved workout is not rewritten.
/// [micro] is the microcycle (1-based) it was applied in: one change per muscle per microcycle.
class SetAdjustment {
  String muscle;
  String templateId;
  String exercise;
  int delta;
  int micro;

  SetAdjustment({
    required this.muscle,
    required this.templateId,
    required this.exercise,
    required this.delta,
    required this.micro,
  });

  Map<String, dynamic> toJson() => {
    'muscle': muscle,
    'template': templateId,
    'exercise': exercise,
    'delta': delta,
    'micro': micro,
  };

  static SetAdjustment? tryJson(Object? j) {
    if (j is! Map) return null;
    final muscle = j['muscle'], template = j['template'], exercise = j['exercise'];
    final delta = _int(j['delta']), micro = _int(j['micro']);
    if (muscle is! String || template is! String || exercise is! String || delta == null || micro == null) return null;
    return SetAdjustment(
      muscle: muscle,
      templateId: template,
      exercise: exercise,
      delta: delta.clamp(-20, 20),
      micro: micro,
    );
  }
}

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
  DateTime? endedAt;
  String startingLoadUnit;
  Map<String, List<SessionExercise>> startingLoads;
  List<SetAdjustment> setAdjustments;

  /// The microcycle in which the coach's early-deload hint was dismissed; it stays hidden for that one.
  int? deloadHintDismissed;
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
    this.endedAt,
    this.startingLoadUnit = 'kg',
    Map<String, List<SessionExercise>>? startingLoads,
    List<SetAdjustment>? setAdjustments,
    this.deloadHintDismissed,
    Map<int, String>? schedule,
    Map<String, DayEvent>? events,
  }) : startingLoads = startingLoads ?? {},
       setAdjustments = setAdjustments ?? [],
       weekRir = weekRir ?? {},
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
    if (endedAt != null) 'endedAt': dateKey(endedAt!),
    if (startingLoads.isNotEmpty) ...{
      'startingLoadUnit': startingLoadUnit,
      'startingLoads': {for (final e in startingLoads.entries) e.key: e.value.map((x) => x.toJson()).toList()},
    },
    if (deloadHintDismissed != null) 'deloadHintDismissed': deloadHintDismissed,
    if (setAdjustments.isNotEmpty) 'setAdjustments': setAdjustments.map((x) => x.toJson()).toList(),
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
    weekRir: {
      for (final e in (j['weekRir'] as Map? ?? {}).entries)
        if ((int.tryParse('${e.key}'), _int(e.value)) case (final week?, final rir?)) week: rir,
    },
    rirScheduleMode: _str(j['rirMode']),
    rirLock: j['rirLock'] as bool? ?? true,
    restLock: j['restLock'] as bool? ?? false,
    active: j['active'] as bool? ?? true,
    setupComplete: j['setupComplete'] as bool? ?? true,
    endedAt: j['endedAt'] == null ? null : DateTime.parse(j['endedAt'] as String),
    startingLoadUnit: j['startingLoadUnit'] as String? ?? 'kg',
    startingLoads: {
      for (final e in (j['startingLoads'] as Map? ?? {}).entries)
        e.key as String: [for (final x in e.value as List) SessionExercise.fromJson(x as Map<String, dynamic>)],
    },
    deloadHintDismissed: _int(j['deloadHintDismissed']),
    setAdjustments: [for (final x in j['setAdjustments'] as List? ?? []) ?SetAdjustment.tryJson(x)],
    schedule: {for (final e in (j['schedule'] as Map? ?? {}).entries) int.parse('${e.key}'): e.value as String},
    events: {
      for (final e in (j['events'] as Map? ?? {}).entries)
        e.key as String: DayEvent.fromJson(e.value as Map<String, dynamic>),
    },
  );
}
