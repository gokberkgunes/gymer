/// Training methods, set types and load modes, as defined by the Flet app.
library;

const trainingMethods = [
  'Straight',
  'AMRAP',
  'Myo-Reps',
  'Rest-Pause',
  'Drop Set',
  'Mechanical Drop Set',
  'Cluster',
  'Myo-Rep Match',
];

const methodSetTypes = {
  'Straight': ['Normal', 'Warm-up', 'Top Set', 'Back-off'],
  'AMRAP': ['Warm-up', 'AMRAP'],
  'Myo-Reps': ['Warm-up', 'Activation', 'Myo-set'],
  'Rest-Pause': ['Warm-up', 'Activation', 'Rest-Pause'],
  'Drop Set': ['Warm-up', 'Activation', 'Drop Set'],
  'Mechanical Drop Set': ['Warm-up', 'Activation', 'Mechanical Drop Set'],
  'Cluster': ['Warm-up', 'Cluster Set'],
  'Myo-Rep Match': ['Warm-up', 'Activation', 'Myo-Rep Match'],
};

const methodsWithActivation = {'Myo-Reps', 'Rest-Pause', 'Drop Set', 'Mechanical Drop Set', 'Myo-Rep Match'};
const sameLoadMethods = {'AMRAP', 'Myo-Reps', 'Rest-Pause', 'Mechanical Drop Set', 'Cluster', 'Myo-Rep Match'};

const _methodAliases = {
  '': 'Straight',
  'normal': 'Straight',
  'straight (normal)': 'Straight',
  'straight': 'Straight',
  'amrap': 'AMRAP',
  'myoreps': 'Myo-Reps',
  'myo reps': 'Myo-Reps',
  'myo-reps': 'Myo-Reps',
  'rest-pause': 'Rest-Pause',
  'drop set': 'Drop Set',
  'mechanical drop set': 'Mechanical Drop Set',
  'cluster': 'Cluster',
  'cluster set': 'Cluster',
  'myo-rep match': 'Myo-Rep Match',
  'myo rep match': 'Myo-Rep Match',
};

String canonicalMethod(String? method) {
  final raw = (method ?? '').trim();
  return _methodAliases[raw.toLowerCase()] ?? (raw.isEmpty ? 'Straight' : raw);
}

String canonicalSetType(String? type) {
  final raw = (type ?? '').trim();
  final k = raw.toLowerCase();
  if (k.isEmpty || k == 'normal' || k == 'straight' || k == 'straight (normal)') return 'Normal';
  if (k == 'warmup' || k == 'warm up' || k == 'warm-up') return 'Warm-up';
  return raw;
}

bool isWarmup(String type) => canonicalSetType(type) == 'Warm-up';
bool isStraightType(String type) => canonicalSetType(type) == 'Normal';

/// Set types for a freshly planned exercise: warm-ups, then the method's
/// anchor and continuation segments.
List<String> plannedSetTypes(String method, {required int warmups, required int work}) {
  method = canonicalMethod(method);
  final types = [for (var i = 0; i < warmups; i++) 'Warm-up'];
  for (var i = 0; i < work; i++) {
    if (methodsWithActivation.contains(method)) {
      types.add(i == 0 ? 'Activation' : activationFollowup[method]!);
    } else if (method == 'Cluster') {
      types.add('Cluster Set');
    } else if (method == 'AMRAP') {
      types.add('AMRAP');
    } else {
      types.add('Normal');
    }
  }
  return types;
}

/// Volume role of a set type, mirroring volume_accounting.role().
String setRole(String type) {
  final k = canonicalSetType(type).toLowerCase();
  if (k == 'warm-up') return 'warmup';
  if ({'normal', 'top set', 'back-off', 'amrap'}.contains(k)) return 'conventional';
  if (k == 'activation') return 'anchor';
  if ({'myo-set', 'myo-reps', 'rest-pause', 'drop set', 'mechanical drop set', 'myo-rep match'}.contains(k)) {
    return 'continuation';
  }
  if (k == 'cluster set' || k == 'cluster') return 'cluster_fragment';
  return 'unknown';
}

/// A starting rep range for a new exercise by its type: 5–8 for barbell compounds (they involve secondary
/// muscles), 10–20 for isolations and for calves, abs and forearms, 8–12 for everything else (machine,
/// dumbbell and cable compounds, or an exercise without muscles yet). Saved exercises keep their own range.
(int, int) defaultRepRange({
  required String equipment,
  required List<String> primary,
  required List<String> secondary,
}) {
  const highRep = {'Calves', 'Abs', 'Forearms'};
  if (primary.isEmpty) return (8, 12);
  if (secondary.isEmpty || primary.every(highRep.contains)) return (10, 20);
  return equipment == 'Barbell' ? (5, 8) : (8, 12);
}

const loadModes = {
  'external': 'External load',
  'bodyweight': 'Bodyweight + added load',
  'assisted': 'Assisted bodyweight',
};

String normalizeLoadMode(String? mode) {
  final m = (mode ?? '').trim().toLowerCase();
  return loadModes.containsKey(m) ? m : 'external';
}

String loadSuffix(String mode, String unit) => switch (normalizeLoadMode(mode)) {
  'bodyweight' => '$unit +',
  'assisted' => '$unit −',
  _ => unit,
};

String defaultLoadModeFor(String exercise) => exercise.trim().toLowerCase() == 'pull-up' ? 'bodyweight' : 'external';

const activationFollowup = {
  'Myo-Reps': 'Myo-set',
  'Rest-Pause': 'Rest-Pause',
  'Drop Set': 'Drop Set',
  'Mechanical Drop Set': 'Mechanical Drop Set',
  'Myo-Rep Match': 'Myo-Rep Match',
};

/// Methods whose working sets form protocol groups.
bool isGroupedMethod(String method) => activationFollowup.containsKey(method) || method == 'Cluster';

/// Valid roles for a planned/recorded sequence, as storage.reconcile_method_sets.
/// Rows are (type, groupStart); returns the corrected pairs.
List<(String, bool)> reconcileMethodSets(String method, List<(String, bool)> rows) {
  method = canonicalMethod(method);
  final grouped = isGroupedMethod(method);
  var workSeen = false;
  return [
    for (final (rawType, rawGroup) in rows)
      () {
        final current = canonicalSetType(rawType);
        final group = grouped && rawGroup;
        if (isWarmup(current) && !workSeen) return ('Warm-up', false);
        final firstInGroup = !workSeen || group;
        workSeen = true;
        final String type;
        if (method == 'Straight') {
          type = const {'Normal', 'Top Set', 'Back-off'}.contains(current) ? current : 'Normal';
        } else if (method == 'AMRAP') {
          type = 'AMRAP';
        } else if (method == 'Cluster') {
          type = 'Cluster Set';
        } else if (activationFollowup.containsKey(method)) {
          type = firstInGroup ? 'Activation' : activationFollowup[method]!;
        } else {
          type = 'Normal';
        }
        return (type, group);
      }(),
  ];
}

/// Set-role choices for row [index], as storage.set_type_choices_for_method_row.
List<String> setTypeChoices(String method, List<(String, bool)> rows, int index) {
  method = canonicalMethod(method);
  final priorWork = rows.take(index).any((r) => !isWarmup(r.$1));
  if (activationFollowup.containsKey(method)) {
    if (index >= 0 && index < rows.length && rows[index].$2) return ['Activation'];
    return priorWork ? [activationFollowup[method]!] : ['Warm-up', 'Activation'];
  }
  final allowed = List.of(methodSetTypes[method] ?? methodSetTypes['Straight']!);
  return priorWork ? allowed.where((t) => !isWarmup(t)).toList() : allowed;
}

String defaultNextSetType(String method, List<String> types) {
  method = canonicalMethod(method);
  if (activationFollowup.containsKey(method)) {
    return types.any((t) => !isWarmup(t)) ? activationFollowup[method]! : 'Activation';
  }
  if (method == 'AMRAP') return 'AMRAP';
  if (method == 'Cluster') return 'Cluster Set';
  return 'Normal';
}

/// The method's strength/progression anchor row.
bool calibrationAnchor(String method, String type) {
  method = canonicalMethod(method);
  type = canonicalSetType(type);
  if (isWarmup(type)) return false;
  return switch (method) {
    'Straight' => type == 'Normal',
    'AMRAP' => type == 'AMRAP',
    'Cluster' => type == 'Cluster Set',
    _ when activationFollowup.containsKey(method) => type == 'Activation',
    _ => false,
  };
}

/// Whether this row meaningfully records actual RIR.
bool methodSetUsesRir(String method, String type) {
  method = canonicalMethod(method);
  if (isWarmup(type)) return false;
  return method == 'Straight' || (method != 'Cluster' && calibrationAnchor(method, type));
}

/// Whether the progression engine owns load guidance for this row.
bool progressionManagedSet(String method, String type) {
  method = canonicalMethod(method);
  type = canonicalSetType(type);
  if (isWarmup(type)) return false;
  if (method == 'Straight') return type == 'Normal';
  return (methodSetTypes[method] ?? const []).contains(type);
}

String displaySetType(String type) => canonicalSetType(type) == 'Normal' ? 'Straight (Normal)' : canonicalSetType(type);

/// Compact role label shown above the set number, as in the Flet app.
String activeSetTypeLabel(String type) =>
    const {
      'Normal': 'Straight',
      'Warm-up': 'Warmup',
      'Top Set': 'Top',
      'Back-off': 'Backoff',
      'AMRAP': 'AMRAP',
      'Failure': 'Failure',
      'Drop Set': 'Drop',
      'Mechanical Drop Set': 'Mech Drop',
      'Rest-Pause': 'RestPause',
      'Myo-Reps': 'Myo',
      'Activation': 'Activate',
      'Myo-set': 'Myo',
      'Myo-Rep Match': 'MyoMatch',
      'Cluster Set': 'Cluster',
    }[canonicalSetType(type)] ??
    type;

String loadGuidance(String mode) => switch (normalizeLoadMode(mode)) {
  'bodyweight' =>
    'Record added load only; enter 0 for bodyweight alone. Choose load manually; more added load is harder.',
  'assisted' => 'Record assistance as a positive load; 0 is unassisted. Choose it manually; less assistance is harder.',
  _ => 'Record the external load used.',
};

const stopReasons = {
  '': 'Unknown / not recorded',
  'target_rir': 'Chosen RIR target',
  'technical_failure': 'Technical failure',
  'muscular_failure': 'Muscular failure',
  'safety_limit': 'Safety limit / discomfort',
  'other': 'Other stop',
};
