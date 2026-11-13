part of '../models.dart';

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

PlateProfile? _tryPlateProfile(Object? profile) {
  try {
    return PlateProfile.fromJson(profile as Map<String, dynamic>);
  } catch (_) {
    return null; // A damaged profile is dropped rather than making the data file unreadable.
  }
}

class Settings {
  String unit;
  int defaultRest;
  int defaultSets;
  int warmupSets;
  bool trackRir;
  bool trackBodyweight;
  String achievementCelebration; // glow | confetti | off
  bool setCelebrations;
  bool recordEffects;
  String recordEffectStyle; // foil | holographic | polychrome
  bool workoutCelebrations;
  bool haptics;
  bool restHaptics;
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

  /// Workout editor: a weekly-sets button in its app bar, and muscle totals on each exercise card.
  bool editorWeeklySets;
  bool editorMuscleTotals;

  /// Include secondary-muscle work as half sets in weekly estimates.
  bool includePartialSets;

  /// How the coach compares straight sets: 'strength' (estimated 1RM) or 'volume' (load × reps). Other set
  /// methods are always compared by volume.
  String coachCompare;

  /// The coach never removes a set that would take a muscle under its MEV; off lowers the floor to MV.
  bool coachKeepMev;

  /// Ask about pump, soreness, sleep and overall state on the finish screen.
  bool coachCheckIn;

  /// Training experience: 'beginner' (under a year), 'intermediate' (one to three) or 'advanced'. Sets how
  /// high and how fast the coach adds sets.
  String experience;
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
  String warmupAppearance; // fire | embers | heat | stripes | plain
  double fontScale;
  double uiScale;

  Settings({
    this.unit = 'kg',
    this.defaultRest = 180,
    this.defaultSets = 3,
    this.warmupSets = 3,
    this.trackRir = true,
    this.trackBodyweight = false,
    this.achievementCelebration = 'glow',
    this.setCelebrations = true,
    this.recordEffects = true,
    this.recordEffectStyle = 'holographic',
    this.workoutCelebrations = true,
    this.haptics = true,
    this.restHaptics = true,
    this.keepAwake = true,
    this.restNotice = 'live',
    this.customIcons = false,
    this.restIcon = 'muscle',
    this.overtimeIcon = 'warning',
    this.chipMode = 'time',
    this.chipText = '',
    this.showPreviousReps = false,
    this.editorWeeklySets = false,
    this.editorMuscleTotals = false,
    this.includePartialSets = true,
    this.coachCompare = 'strength',
    this.coachKeepMev = true,
    this.coachCheckIn = false,
    this.experience = 'intermediate',
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
    this.warmupAppearance = 'fire',
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

  /// Saved and legacy-imported values must fit the same limits as the settings controls.
  void normalizeNumeric() {
    defaultRest = defaultRest.clamp(0, 86400);
    defaultSets = defaultSets.clamp(1, 9999);
    repMaxTargetReps = repMaxTargetReps.clamp(1, 999);
    rounding = rounding.clamp(0, 24);
    setSpacing = setSpacing.clamp(0, 18);
    fontScale = fontScale.isFinite ? fontScale.clamp(0.8, 1.4) : 1.0;
    uiScale = uiScale.isFinite ? uiScale.clamp(0.7, 1.2) : 1.0;
  }

  void resetAppearance() {
    final d = Settings();
    accent = d.accent;
    themeMode = d.themeMode;
    background = d.background;
    rounding = d.rounding;
    density = d.density;
    setSpacing = d.setSpacing;
    warmupAppearance = d.warmupAppearance;
    fontScale = d.fontScale;
    uiScale = d.uiScale;
    dimCompleted = d.dimCompleted;
  }

  Map<String, dynamic> toJson() => {
    'unit': unit,
    'defaultRest': defaultRest,
    'defaultSets': defaultSets,
    'warmupSets': warmupSets,
    'trackRir': trackRir,
    'trackBodyweight': trackBodyweight,
    'achievementCelebration': achievementCelebration,
    'setCelebrations': setCelebrations,
    'recordEffects': recordEffects,
    'recordEffectStyle': recordEffectStyle,
    'workoutCelebrations': workoutCelebrations,
    'haptics': haptics,
    'restHaptics': restHaptics,
    'keepAwake': keepAwake,
    'restNotice': restNotice,
    'customIcons': customIcons,
    'restIcon': restIcon,
    'overtimeIcon': overtimeIcon,
    'chipMode': chipMode,
    'chipText': chipText,
    'showPreviousReps': showPreviousReps,
    'editorWeeklySets': editorWeeklySets,
    'editorMuscleTotals': editorMuscleTotals,
    'includePartialSets': includePartialSets,
    if (coachCompare != 'strength') 'coachCompare': coachCompare,
    if (!coachKeepMev) 'coachKeepMev': false,
    if (coachCheckIn) 'coachCheckIn': true,
    if (experience != 'intermediate') 'experience': experience,
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
    'warmupAppearance': warmupAppearance,
    'fontScale': fontScale,
    'uiScale': uiScale,
  };

  factory Settings.fromJson(Map<String, dynamic> j) {
    final d = Settings();
    num? n(String key) {
      final value = j[key];
      return value is num && value.isFinite ? value : null;
    }

    bool b(String k, bool fallback) => j[k] as bool? ?? fallback;
    String s(String k, String fallback, Set<String> allowed) => allowed.contains(j[k]) ? j[k] as String : fallback;
    return Settings(
      unit: s('unit', 'kg', {'kg', 'lb'}),
      defaultRest: n('defaultRest')?.round() ?? d.defaultRest,
      defaultSets: n('defaultSets')?.round() ?? d.defaultSets,
      warmupSets: j['warmupSets'] == 2 ? 2 : 3,
      trackRir: b('trackRir', d.trackRir),
      trackBodyweight: b('trackBodyweight', d.trackBodyweight),
      achievementCelebration: s('achievementCelebration', d.achievementCelebration, {'glow', 'confetti', 'off'}),
      setCelebrations: b('setCelebrations', d.setCelebrations),
      recordEffects: b('recordEffects', d.recordEffects),
      recordEffectStyle: s('recordEffectStyle', d.recordEffectStyle, {'foil', 'holographic', 'polychrome'}),
      workoutCelebrations: b('workoutCelebrations', d.workoutCelebrations),
      haptics: b('haptics', d.haptics),
      restHaptics: b('restHaptics', d.restHaptics),
      keepAwake: b('keepAwake', d.keepAwake),
      restNotice: s('restNotice', d.restNotice, {'live', 'alarm', 'both', 'off'}),
      customIcons: b('customIcons', d.customIcons),
      restIcon: s('restIcon', d.restIcon, {for (final (k, _) in restIcons) k}),
      overtimeIcon: s('overtimeIcon', d.overtimeIcon, {for (final (k, _) in overtimeIcons) k}),
      chipMode: s('chipMode', d.chipMode, {'time', 'text'}),
      chipText: j['chipText'] is String ? (j['chipText'] as String) : d.chipText,
      showPreviousReps: b('showPreviousReps', d.showPreviousReps),
      editorWeeklySets: b('editorWeeklySets', d.editorWeeklySets),
      editorMuscleTotals: b('editorMuscleTotals', d.editorMuscleTotals),
      includePartialSets: b('includePartialSets', d.includePartialSets),
      coachCompare: s('coachCompare', d.coachCompare, {'strength', 'volume'}),
      coachKeepMev: b('coachKeepMev', d.coachKeepMev),
      coachCheckIn: b('coachCheckIn', d.coachCheckIn),
      experience: s('experience', d.experience, {'beginner', 'intermediate', 'advanced'}),
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
      repMaxTargetReps: n('repMaxTargetReps')?.round() ?? d.repMaxTargetReps,
      setTypes: j['setTypes'] is List ? List<String>.from(j['setTypes'] as List) : null,
      // A damaged entry is skipped (its equipment falls back to the default) rather than making the file unreadable.
      increments: j['increments'] is Map
          ? {
              ...defaultIncrements,
              for (final e in (j['increments'] as Map).entries)
                if (e.key is String &&
                    e.value is List &&
                    (e.value as List).length >= 2 &&
                    (e.value as List)[0] is num &&
                    (e.value as List)[1] is num)
                  e.key as String: (((e.value as List)[0] as num).toDouble(), ((e.value as List)[1] as num).toDouble()),
            }
          : null,
      barKg: _dbl(j['barKg']) ?? d.barKg,
      barLb: _dbl(j['barLb']) ?? d.barLb,
      platesKg: _plates(j['platesKg'], formerPlatesKg),
      platesLb: _plates(j['platesLb'], formerPlatesLb),
      plateProfiles: (j['plateProfiles'] as List?)?.map(_tryPlateProfile).nonNulls.toList(),
      selectedPlateProfile: _str(j['selectedPlateProfile']).isEmpty ? 'gym' : j['selectedPlateProfile'] as String,
      groupRepeatedPlates: b('groupRepeatedPlates', d.groupRepeatedPlates),
      accent: _int(j['accent']) ?? d.accent,
      themeMode: s('themeMode', d.themeMode, {'system', 'light', 'dark'}),
      background: _str(j['background']).isEmpty ? d.background : j['background'] as String,
      rounding: n('rounding')?.round() ?? d.rounding,
      density: s('density', d.density, {'compact', 'normal', 'roomy'}),
      setSpacing: n('setSpacing')?.round() ?? d.setSpacing,
      warmupAppearance: s('warmupAppearance', d.warmupAppearance, {'fire', 'embers', 'heat', 'stripes', 'plain'}),
      fontScale: n('fontScale')?.toDouble() ?? d.fontScale,
      uiScale: n('uiScale')?.toDouble() ?? d.uiScale,
    )..normalizeNumeric();
  }
}
