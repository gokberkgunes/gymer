/// An editable warm-up ramp derived from a working load, with short, decreasing rep targets.
library;

import 'dart:math' as math;

import 'plates.dart';

typedef WarmupStep = ({double weight, int reps});

List<WarmupStep> warmupRamp(
  double workingWeight, {
  int sets = 3,
  double increment = 0.5,
  double bar = 0,
  List<double>? plates,
  Map<double, int>? pairs,
}) {
  if (!workingWeight.isFinite || workingWeight <= 0 || (sets != 2 && sets != 3)) return [];
  if (plates != null && workingWeight < bar) return [];
  final ramp = sets == 2 ? [(0.4, 8), (0.8, 3)] : [(0.4, 8), (0.6, 5), (0.8, 3)];
  final result = <WarmupStep>[];
  for (final (fraction, reps) in ramp) {
    final target = math.max(bar, workingWeight * fraction);
    final double weight;
    if (plates != null) {
      final plan = planPlates(target, bar, plates, pairs: pairs);
      final load = plan.exact ?? plan.below ?? plan.above;
      if (load == null || load.total <= 0 || load.total > workingWeight) continue;
      weight = load.total;
    } else {
      final step = increment.isFinite && increment > 0 ? increment : 0.5;
      weight = double.parse(math.max(step, ((target + 1e-8) / step).floor() * step).toStringAsFixed(2));
      if (weight > workingWeight) continue;
    }
    result.add((weight: weight, reps: reps));
  }
  return result;
}
