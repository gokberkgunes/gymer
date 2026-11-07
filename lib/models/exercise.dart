part of '../models.dart';

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
    primary: List<String>.from(j['primary'] as List? ?? const []),
    secondary: List<String>.from(j['secondary'] as List? ?? const []),
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
