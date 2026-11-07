/// Port of the Flet app's progression.py.
///
/// Straight sets use all-set double progression. Other methods progress from
/// their anchor segment behind a quality gate. The Flet gate also compared
/// setup text, stop reasons and actual inter-segment rest; those observations
/// are not recorded here, so the gate checks only what is.
library;

import 'dart:math' as math;

import '../models.dart';
import 'methods.dart';

const lowRepLimit = 8;
const highRepLimit = 12;
const targetRepsDefault = 8;
const miniSetMinReps = 2;
const clusterLowReps = 2;
const clusterHighReps = 5;
const clusterTargetReps = 3;
const defaultDropRatio = 0.75;
const maxAutomaticChange = 0.10;

class Recommendation {
  final String method;
  final String action; // increase | decrease | hold
  final double weight;
  final bool applyWeight;
  final List<int> setRepTargets;
  final int targetReps;
  final int? targetRir;
  final String reason;
  final List<double?> continuationWeights;
  final (int, int)? continuationRepRange;
  final double step;

  const Recommendation({
    required this.method,
    required this.action,
    required this.weight,
    required this.applyWeight,
    required this.setRepTargets,
    required this.targetReps,
    required this.targetRir,
    required this.reason,
    this.continuationWeights = const [],
    this.continuationRepRange,
    required this.step,
  });
}

double practicalWeightStep(double weight, String unit, [double? configured]) {
  if (configured != null && configured.isFinite && configured > 0) return configured;
  weight = math.max(0, weight);
  if (unit == 'lb') return weight < 20 ? 2.5 : 5.0;
  return weight < 10 ? 1.0 : 2.5;
}

double _roundHalfUp(double value, double step) => step <= 0 ? value : (value / step + 0.5).floor() * step;

double practicalWeight(double value, String unit, double reference, [double? configured]) {
  final step = practicalWeightStep(reference, unit, configured);
  return math.max(0, reference + _roundHalfUp(value - reference, step));
}

/// Applies the 10% limit to estimate-driven load changes. Straight double progression passes [capped] false:
/// one increment after the top of the rep range is the rule itself, even when that increment is more than 10%
/// of a light load (a 5 kg step on a 30 kg machine would otherwise never be taken).
(double, String, String) _boundedLoad(
  double current,
  double proposed,
  String intended,
  double step,
  String reason, {
  bool capped = true,
}) {
  if (intended == 'hold') return (current, 'hold', reason);
  final direction = intended == 'increase' ? 1 : -1;
  final delta = proposed - current;
  if (delta * direction <= 1e-9) {
    return (
      current,
      'hold',
      'The rep-based direction conflicts with the effort-based estimate or rounding; '
          'keep the load and review the observation.',
    );
  }
  if (!capped) {
    if (proposed <= 0) return (current, 'hold', 'No positive load fits this automatic change; choose manually.');
    return (proposed, proposed > current ? 'increase' : 'decrease', reason);
  }
  final available = ((current * maxAutomaticChange + 1e-9) / step).floor();
  if (available < 1) {
    return (
      current,
      'hold',
      'The smallest configured increment exceeds the 10% automatic-change limit; choose a suitable load manually.',
    );
  }
  final bounded = current + direction * math.min(delta.abs(), available * step);
  if (bounded <= 0) return (current, 'hold', 'No positive load fits this automatic change; choose manually.');
  if ((bounded - proposed).abs() > 1e-9) reason += ' The change is capped at 10% using available increments.';
  return (bounded, bounded > current ? 'increase' : 'decrease', reason);
}

List<double?> _descendingDropWeights(double anchor, List<double> ratios, String unit, double step) {
  var previous = anchor;
  final values = <double?>[];
  for (final ratio in ratios) {
    final candidate = math.min(practicalWeight(anchor * ratio, unit, anchor, step), previous - step);
    if (candidate <= 1e-9) {
      values.add(null);
      previous = 0;
    } else {
      values.add(candidate);
      previous = candidate;
    }
  }
  return values;
}

String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// [previous] is the last session's sets for this exercise (all types).
Recommendation? recommend({
  required List<SetEntry> previous,
  required String method,
  required int? targetRir,
  required String unit,
  double? increment,
  int repMin = lowRepLimit,
  int repMax = highRepLimit,
  bool auto = true,
  int? expectedWorkSets,
  String phase = 'Build',
  String loadMode = 'external',
  List<SetEntry>? planned,
  bool rirTracked = true,
}) {
  if (phase == 'Deload' || normalizeLoadMode(loadMode) != 'external') return null;
  method = canonicalMethod(method);
  if (method == 'Straight' && !auto) return null;
  return method == 'Straight'
      ? _straight(previous, targetRir, unit, increment, repMin, repMax, expectedWorkSets, planned, rirTracked)
      : _method(previous, method, targetRir, unit, increment, expectedWorkSets, planned, rirTracked);
}

/// set_context.comparison_error: recorded and planned logging context must be
/// one and the same, and "both sides in one entry" is never comparable.
String? contextProblem(List<SetEntry> rows, [List<SetEntry>? planned]) {
  Set<SetContext> contexts(List<SetEntry> items) => {
    for (final r in items)
      if (!r.warmup) r.context,
  };
  if ([...rows, ...?planned].any((r) => r.context.side == 'both_separately')) {
    return 'Both sides in one entry require manual progression; separate left/right outcomes are not recorded.';
  }
  final recorded = contexts(rows);
  final plan = planned == null ? recorded : contexts(planned);
  if (recorded.length > 1 ||
      plan.length > 1 ||
      (recorded.isNotEmpty && plan.isNotEmpty && recorded.first != plan.first)) {
    return 'The setup, side or logging conventions differ or changed; establish a comparable baseline or progress manually.';
  }
  return null;
}

Recommendation? _straight(
  List<SetEntry> rows,
  int? target,
  String unit,
  double? increment,
  int low,
  int high,
  int? expected,
  List<SetEntry>? currentPlan,
  bool rirTracked,
) {
  final planned = rows.where((r) => isStraightType(r.type)).toList();
  final sets = planned.where((r) => r.done && (r.weight ?? 0) > 0 && (r.reps ?? 0) > 0).toList();
  if (sets.isEmpty) return null;
  final current = sets.first.weight!;
  final step = practicalWeightStep(current, unit, increment);
  var targets = [for (final r in planned) (r.reps ?? low).clamp(low, high)];
  var suggested = current;
  var intended = 'hold';
  var apply = true;
  String reason;

  final contextError = contextProblem(planned, currentPlan?.where((r) => isStraightType(r.type)).toList());
  if (contextError != null) {
    apply = false;
    reason = contextError;
  } else if (expected != null && planned.length != expected) {
    apply = false;
    reason = 'The planned working-set count changed; establish a complete baseline before increasing load.';
  } else if (sets.length != planned.length) {
    reason = 'A planned working set was missed or has invalid observations; repeat the load before progressing.';
  } else if (sets.any((s) => (s.weight! - current).abs() > 1e-6)) {
    apply = false;
    reason = 'Working loads differ; preserve the individual loads and choose progression manually.';
  } else if (!rirTracked) {
    // RIR tracking is off, so there is no effort to read: plain double progression on reps alone.
    if (sets.every((s) => s.reps! >= high)) {
      suggested = current + step;
      intended = 'increase';
      targets = List.filled(planned.length, low);
      reason = 'Every planned set reached $high reps; add one increment and restart at $low reps.';
    } else if (sets.any((s) => s.reps! < low)) {
      suggested = math.max(0, current - step);
      intended = 'decrease';
      targets = List.filled(planned.length, low);
      reason = 'A working set fell below $low reps; try one increment lower.';
    } else {
      targets = [for (final s in sets) math.min(high, s.reps! + 1)];
      reason = 'Keep the load and build reps within $low–$high; increase after every planned set reaches $high.';
    }
  } else if (target == null) {
    reason = 'Target RIR is unknown; choose an effort target before automatic progression.';
  } else if (sets.any((s) => s.rir == null || s.rir! < 0)) {
    reason = 'Actual RIR is unknown for a working set; record effort before progressing.';
  } else {
    final capacity = [for (final s in sets) s.reps! + s.rir! - target];
    final minCap = capacity.reduce(math.min);
    if (sets.every((s) => s.reps! >= high && s.rir! >= target)) {
      suggested = current + step;
      intended = 'increase';
      targets = List.filled(planned.length, low);
      reason =
          'Every planned set reached $high reps at or above $target RIR; add one increment and restart at $low reps.';
    } else if (minCap < low || sets.any((s) => s.reps! < low)) {
      final weakest = sets[capacity.indexOf(minCap)];
      final oneRm = estimatedOneRm(current, weakest.reps!, weakest.rir!)!;
      final estimate = oneRm * wathanPercent(low + target) / 100;
      if (estimate >= current) {
        reason =
            'The low-rep observation conflicts with its recorded effort; keep the load and review the observation.';
      } else {
        suggested = math.max(0, current - step);
        intended = 'decrease';
        reason = 'A working set does not support $low reps at $target RIR; try one increment lower.';
      }
      targets = List.filled(planned.length, low);
    } else if (sets.any((s) => s.rir! < target)) {
      targets = [for (final c in capacity) c.clamp(low, high)];
      reason = 'Effort exceeded the $target RIR target; keep the load and reduce reps to meet that target.';
    } else {
      targets = [for (final s in sets) math.min(high, s.reps! + 1)];
      reason =
          'Keep the load and build reps within $low–$high, stopping at $target RIR; '
          'increase only after every planned set reaches $high.';
    }
  }
  // Earlier branches (a missed set, a changed plan) can be reached with mixed loads too; never apply one load then.
  if (sets.any((s) => (s.weight! - current).abs() > 1e-6)) apply = false;
  final (weight, action, why) = _boundedLoad(current, suggested, intended, step, reason, capped: false);
  if (intended == 'increase' && action == 'hold') targets = List.filled(planned.length, high);
  return Recommendation(
    method: 'Straight',
    action: action,
    weight: weight,
    applyWeight: apply,
    setRepTargets: targets,
    targetReps: targets.isEmpty ? low : targets.reduce(math.min),
    targetRir: target,
    reason: why,
    step: step,
  );
}

String _anchorType(String method) => switch (method) {
  'AMRAP' => 'AMRAP',
  'Cluster' => 'Cluster Set',
  _ when methodsWithActivation.contains(method) => 'Activation',
  _ => 'Normal',
};

String? _qualityProblem(
  String method,
  List<SetEntry> work,
  int? expected,
  int? target,
  List<SetEntry>? currentPlan,
  bool rirTracked,
) {
  final plan = currentPlan?.where((r) => !r.warmup).toList();
  if (isGroupedMethod(method) &&
      (work.skip(1).any((r) => r.groupStart) || (plan?.skip(1).any((r) => r.groupStart) ?? false))) {
    return 'multiple protocol groups require manual progression';
  }
  final contextError = contextProblem(work, plan);
  if (method != 'Mechanical Drop Set' && contextError != null) return contextError;
  if (expected != null && work.length != expected) {
    return 'the planned segment count changed; establish a comparable baseline';
  }
  if (methodsWithActivation.contains(method) && work.length < 2) {
    return 'activation only was recorded; no continuation protocol was completed';
  }
  final roles = [for (final w in work) canonicalSetType(w.type)];
  final expectedRoles = plannedSetTypes(method, warmups: 0, work: work.length);
  for (var i = 0; i < roles.length; i++) {
    if (roles[i] != expectedRoles[i]) return 'the segment roles do not match this method';
  }
  if (work.any((w) => !w.done)) return 'not all planned segments were completed';
  final weights = [for (final w in work) w.weight ?? 0];
  final reps = [for (final w in work) w.reps ?? 0];
  if (weights.any((v) => v <= 0) || reps.any((v) => v <= 0)) return 'a segment has invalid load or reps';
  final setups = [for (final w in work) w.context.setup.trim()];
  if (plan != null) {
    if (plan.length != work.length || [for (final r in plan) canonicalSetType(r.type)].join('|') != roles.join('|')) {
      return 'the current segment sequence differs from the recorded protocol';
    }
    if ([for (final r in plan) r.context.setup.trim()].join('|') != setups.join('|')) {
      return 'the current setup/variation differs or is unknown';
    }
  }
  final now = plan ?? work;
  for (var i = 0; i < work.length - 1; i++) {
    final intended = work[i].rest, actual = work[i].actualRest, current = now[i].rest;
    // Actual rest is optional: unknown is accepted, but a recorded or planned difference is not.
    if ((actual != null && actual != intended) || current != intended) {
      return 'recorded or planned inter-segment rests differ; progress manually';
    }
  }
  if (method == 'Mechanical Drop Set') {
    return 'mechanical leverage changes require manual progression; setup labels alone do not establish equivalence';
  }
  if (sameLoadMethods.contains(method) && weights.any((v) => (v - weights.first).abs() > 1e-6)) {
    return 'this same-load method used different segment loads';
  }
  if (method == 'Drop Set') {
    for (var i = 1; i < weights.length; i++) {
      if (weights[i] >= weights[i - 1]) return 'drop loads did not strictly decrease between segments';
    }
  }
  if ({'Myo-Reps', 'Rest-Pause', 'Drop Set'}.contains(method) && reps.skip(1).any((r) => r < miniSetMinReps)) {
    return 'a continuation segment fell below $miniSetMinReps reps';
  }
  if (method == 'Myo-Rep Match' && reps.skip(1).any((r) => r < reps.first)) {
    return 'not every match segment reached the activation rep count';
  }
  if (method != 'Cluster') {
    final anchors = method == 'AMRAP' ? work : work.take(1);
    const knownStops = {'target_rir', 'technical_failure', 'muscular_failure'};
    // An unrecorded stop reason is accepted; only an explicit unsafe or unclear one needs manual review.
    if (anchors.any((a) => a.stopReason.isNotEmpty && !knownStops.contains(a.stopReason))) {
      return 'an anchor stop reason is unknown, safety-limited or requires manual review';
    }
    if (anchors.any((a) => a.stopReason == 'muscular_failure' && a.rir != null && a.rir != 0)) {
      return 'muscular failure conflicts with the recorded nonzero actual RIR';
    }
    if (target == null) return 'the anchor effort target is unknown';
    // With RIR tracking off there is no box to record it, so an unrecorded anchor is taken as on target.
    if (anchors.any((a) => (a.rir == null && rirTracked) || (a.rir != null && a.rir! < target))) {
      return 'actual anchor RIR is unknown or effort exceeded the target';
    }
  }
  return null;
}

Recommendation? _method(
  List<SetEntry> rows,
  String method,
  int? target,
  String unit,
  double? increment,
  int? expected,
  List<SetEntry>? currentPlan,
  bool rirTracked,
) {
  final work = rows.where((r) => !r.warmup).toList();
  final anchorType = _anchorType(method);
  final anchor = work.where(
    (r) => r.done && canonicalSetType(r.type) == anchorType && (r.weight ?? 0) > 0 && (r.reps ?? 0) > 0,
  );
  if (anchor.isEmpty) return null;
  final a = anchor.first;
  final anchorWeight = a.weight!, anchorReps = a.reps!;
  final step = practicalWeightStep(anchorWeight, unit, increment);
  final current = practicalWeight(anchorWeight, unit, anchorWeight, step);
  final problem = _qualityProblem(method, work, expected, target, currentPlan, rirTracked);

  if (method == 'Cluster') {
    final reps = [
      for (final r in work)
        if (r.done && (r.reps ?? 0) > 0) r.reps!,
    ];
    double suggested = current;
    var intended = 'hold';
    String reason;
    if (problem != null) {
      reason = 'Hold cluster load: $problem.';
    } else if (reps.every((r) => r > clusterHighReps)) {
      suggested = current + step;
      intended = 'increase';
      reason = 'Cluster reps rose above the $clusterLowReps-$clusterHighReps working window.';
    } else if (reps.any((r) => r < clusterLowReps)) {
      suggested = math.max(step, current - step);
      intended = 'decrease';
      reason = 'Cluster reps fell below the $clusterLowReps-$clusterHighReps working window.';
    } else {
      reason = 'Cluster reps remain inside the $clusterLowReps-$clusterHighReps working window.';
    }
    final (weight, action, why) = _boundedLoad(current, suggested, intended, step, reason);
    return Recommendation(
      method: method,
      action: action,
      weight: weight,
      applyWeight: problem == null,
      setRepTargets: List.filled(work.length, clusterTargetReps),
      targetReps: clusterTargetReps,
      targetRir: null,
      reason: why,
      continuationRepRange: (clusterLowReps, clusterHighReps),
      step: step,
    );
  }

  final anchorRir = a.rir ?? (rirTracked ? null : target);
  final oneRm = anchorRir == null ? null : estimatedOneRm(anchorWeight, anchorReps, anchorRir);
  final repsForWindow = method == 'AMRAP' ? work.map((w) => w.reps ?? 0).reduce(math.min) : anchorReps;
  double suggested = current;
  var intended = 'hold';
  String reason;
  if (problem != null) {
    reason = 'Hold $method load: $problem.';
  } else if (oneRm == null) {
    reason = "The anchor's actual RIR is unknown; do not infer failure or increase load.";
  } else if (repsForWindow > highRepLimit) {
    final raw = oneRm * wathanPercent(targetRepsDefault + (target ?? 0)) / 100;
    suggested = practicalWeight(raw, unit, anchorWeight, step);
    if (raw > anchorWeight && suggested <= current) suggested = current + step;
    intended = 'increase';
    reason = 'The $method anchor exceeded $highRepLimit reps and continuation quality was maintained.';
  } else if (anchorReps < lowRepLimit) {
    final raw = oneRm * wathanPercent(targetRepsDefault + (target ?? 0)) / 100;
    suggested = practicalWeight(raw, unit, anchorWeight, step);
    if (raw < anchorWeight && suggested >= current) suggested = math.max(step, current - step);
    intended = 'decrease';
    reason = 'The $method anchor fell below $lowRepLimit reps.';
  } else {
    reason = 'The $method anchor remains inside the $lowRepLimit-$highRepLimit rep window.';
  }
  final (weight, action, why) = _boundedLoad(current, suggested, intended, step, reason);

  var drops = <double?>[];
  if (method == 'Drop Set') {
    final continuations = work.skip(1).toList();
    final ratios = [
      for (final (i, r) in continuations.indexed)
        (() {
          final w = r.weight;
          final ratio = w != null && w > 0 ? w / anchorWeight : 0.0;
          return ratio >= 0.20 && ratio < 1.0 ? ratio : math.pow(defaultDropRatio, i + 1).toDouble();
        })(),
    ];
    drops = _descendingDropWeights(weight, ratios, unit, step);
  }
  return Recommendation(
    method: method,
    action: action,
    weight: weight,
    applyWeight: problem == null,
    setRepTargets: List.filled(work.length, targetRepsDefault),
    targetReps: targetRepsDefault,
    targetRir: target,
    reason: why,
    continuationWeights: drops,
    continuationRepRange: switch (method) {
      'Myo-Reps' => (2, 4),
      'Rest-Pause' => (2, 5),
      'Myo-Rep Match' => (anchorReps, anchorReps),
      _ => null,
    },
    step: step,
  );
}

/// Load hint for the [workIndex]th working segment, or null when the
/// recommendation should not prefill a weight there.
double? weightForSet(Recommendation r, String type, int workIndex) {
  if (!r.applyWeight || isWarmup(type)) return null;
  if (r.method == 'Straight' && !isStraightType(type)) return null;
  if (r.method == 'Drop Set' && workIndex > 0) {
    final i = workIndex - 1;
    if (i < r.continuationWeights.length) return r.continuationWeights[i];
    final ratios = [for (var k = 1; k <= workIndex; k++) math.pow(defaultDropRatio, k).toDouble()];
    return _descendingDropWeights(r.weight, ratios, '', r.step).last;
  }
  return r.weight;
}

/// Deload: fraction of working sets kept, never below one.
int recoveryCount(String method, int workingCount, int percent) {
  if (workingCount <= 0) return 0;
  if (methodsWithActivation.contains(method) || method == 'Cluster') return 1;
  // Rounded, not floored: half of 3 sets is 2, not 1 (the Flet app floored, which read as a bug).
  return math.max(1, (workingCount * percent / 100).round());
}

/// Deload: round down on the reference load's lattice; never a rise.
double? recoveryWeight(double reference, int percent, double step) {
  if (reference <= 0) return null;
  final raw = reference * percent / 100;
  final drops = ((reference - raw) / step - 1e-9).ceil();
  final candidate = reference - math.max(0, drops) * step;
  return candidate > 0 ? candidate : null;
}

String describe(Recommendation r, String unit) {
  final verb = switch (r.action) {
    'increase' => '↑',
    'decrease' => '↓',
    _ => '=',
  };
  return '$verb ${_fmt(r.weight)} $unit · ${r.reason}';
}

double convertWeight(double w, String from, String to) {
  if (from == to) return w;
  return from == 'kg' ? w * 2.2046226218 : w / 2.2046226218;
}

class Calibration {
  final double weight;
  final int targetReps;
  final int? targetRir;
  final bool usesRir;
  const Calibration(this.weight, this.targetReps, this.targetRir, this.usesRir);
}

const calibrationTargetReps = 10;

/// Starting load for a method's first mesocycle session from a prior set.
Calibration? calibrationRecommendation({
  required double weight,
  required int reps,
  required int? rir,
  required String method,
  required int? targetRir,
  required String unit,
  double? increment,
  int repMin = lowRepLimit,
  int repMax = highRepLimit,
}) {
  method = canonicalMethod(method);
  if (weight <= 0 || reps <= 0) return null;
  if (method == 'Cluster') {
    return Calibration(practicalWeight(weight, unit, weight, increment), clusterTargetReps, null, false);
  }
  if (rir == null || rir < 0) return null;
  final oneRm = estimatedOneRm(weight, reps, rir);
  if (oneRm == null) return null;
  final target = method == 'Straight' ? math.max(0, targetRir ?? 0) : targetRir;
  if (target == null || target < 0) return null;
  // Straight sets start at the bottom of the rep range: double progression then has the whole range (8 → 12 by
  // default) to add reps before the first load increase, instead of starting mid-range and jumping sooner.
  final goal = method == 'Straight' ? repMin : calibrationTargetReps;
  final suggested = practicalWeight(oneRm * wathanPercent(goal + target) / 100, unit, weight, increment);
  return suggested > 0 ? Calibration(suggested, goal, target, true) : null;
}

/// Seeds later segments right after a first-session calibration.
double? calibratedFollowupWeight(double anchor, String method, int workIndex, String unit, double? increment) {
  method = canonicalMethod(method);
  if (anchor <= 0) return null;
  if (method == 'Straight' || sameLoadMethods.contains(method) || method == 'Mechanical Drop Set') return anchor;
  if (method == 'Drop Set') {
    final step = practicalWeightStep(anchor, unit, increment);
    final ratios = [for (var k = 1; k <= math.max(1, workIndex); k++) math.pow(defaultDropRatio, k).toDouble()];
    return _descendingDropWeights(anchor, ratios, unit, step).last;
  }
  return null;
}
