/// Plate calculator: which plates go on each side of the bar for a target weight.
library;

import 'dart:math' as math;

typedef PlateGroup = ({double weight, int count});

/// Presentation only: keep the physical plan unchanged while optionally merging matching sizes.
List<PlateGroup> plateGroups(Iterable<double> plates, {bool groupRepeated = false}) {
  if (!groupRepeated) return [for (final plate in plates) (weight: plate, count: 1)];
  final counts = <double, int>{};
  for (final plate in plates) {
    counts[plate] = (counts[plate] ?? 0) + 1;
  }
  return [for (final entry in counts.entries) (weight: entry.key, count: entry.value)];
}

const defaultPlatesKg = [20.0, 10.0, 5.0, 2.5, 1.25];
const defaultPlatesLb = [45.0, 25.0, 10.0, 5.0, 2.5];

/// The first defaults; a saved list equal to one of these is moved to the current defaults on load.
const formerPlatesKg = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
const formerPlatesLb = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];

/// Competition (IWF) colour class of a plate, by its weight in kg: 25 red, 20 blue, 15 yellow, 10 green,
/// 5 white, then the change plates 2.5 red, 2 blue, 1.5 yellow, 1 green, 0.5 white, and anything else chrome.
/// Pound plates use the class of their nearest kg equivalent.
String plateColorClass(double weight, String unit) {
  final kg = unit == 'lb' ? weight * 0.45359237 : weight;
  const classes = [
    (25.0, 'red'),
    (20.0, 'blue'),
    (15.0, 'yellow'),
    (10.0, 'green'),
    (5.0, 'white'),
    (2.5, 'red'),
    (2.0, 'blue'),
    (1.5, 'yellow'),
    (1.0, 'green'),
    (0.5, 'white'),
  ];
  // Exact kg plates match their class; odd sizes (and pounds) take the nearest within 15 %.
  var best = 'chrome';
  var gap = double.infinity;
  for (final (w, c) in classes) {
    final d = (kg - w).abs() / w;
    if (d < gap && d <= 0.15) {
      gap = d;
      best = c;
    }
  }
  return best;
}

const defaultBarKg = 20.0;
const defaultBarLb = 45.0;

/// Equipment that is loaded with plates, and so gets the calculator.
bool usesPlates(String equipment) => equipment == 'Barbell' || equipment == 'Plate loaded';

class PlateLoad {
  /// Total on the bar, bar included, and the plates for one side, heaviest first.
  final double total;
  final List<double> perSide;
  const PlateLoad(this.total, this.perSide);
}

class PlatePlan {
  final double target;
  final double bar;

  /// The exact load, or null when the plates cannot make the target.
  final PlateLoad? exact;

  /// Without an exact load: the nearest loads below and above (null when none exists, e.g. below the bar).
  final PlateLoad? below;
  final PlateLoad? above;
  const PlatePlan(this.target, this.bar, {this.exact, this.below, this.above});
}

// Weights are compared on a 0.05 grid, fine enough for fractional plates in either unit.
const _grid = 20;

class _PlateStack {
  final int plate;
  final int count;
  final _PlateStack? previous;
  const _PlateStack(this.plate, this.count, this.previous);

  List<int> expanded() {
    final result = <int>[];
    for (_PlateStack? stack = this; stack != null; stack = stack.previous) {
      result.addAll(List.filled(stack.count, stack.plate));
    }
    return result..sort((a, b) => b.compareTo(a));
  }
}

/// Fewest plates per side; ties prefer heavier plates. [pairs] limits the available pairs of each size
/// (missing sizes mean zero). Null retains the gym default of unlimited pairs.
/// Inexact targets give the nearest achievable loads either side.
PlatePlan planPlates(double target, double bar, List<double> plates, {Map<double, int>? pairs}) {
  final available = <int, int>{};
  for (final plate in plates.toSet()) {
    if (!plate.isFinite || plate <= 0) continue;
    final size = (plate * _grid).round();
    if (size <= 0) continue;
    final count = pairs == null ? 1 : pairs[plate] ?? 0;
    if (count > 0) available[size] = (available[size] ?? 0) + count;
  }
  final sizes = available.keys.toList()..sort((a, b) => b.compareTo(a));
  final goal = ((target - bar) / 2 * _grid).round();
  if (goal < 0) {
    return PlatePlan(target, bar, above: PlateLoad(bar, const []));
  }
  // A reachable load above the goal needs at most one extra plate. With counts, stop at the inventory's
  // total as well, so a target far beyond the available plates does not allocate a huge search table.
  final ceiling = goal + (sizes.isEmpty ? 0 : sizes.first);
  final limit = pairs == null
      ? ceiling
      : math.min(ceiling, available.entries.fold(0, (sum, entry) => sum + entry.key * entry.value));
  const none = 1 << 30;
  final count = List.filled(limit + 1, none)..[0] = 0;
  final stacks = List<_PlateStack?>.filled(limit + 1, null);
  bool heavier(_PlateStack candidate, _PlateStack current) {
    final a = candidate.expanded(), b = current.expanded();
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  for (final plate in sizes) {
    var left = pairs == null ? limit ~/ plate : math.min(available[plate]!, limit ~/ plate);
    // Binary groups make large inventories cheap to search while each group can only be used once.
    for (var group = 1; left > 0; group *= 2) {
      final take = math.min(group, left);
      left -= take;
      final weight = plate * take;
      for (var sum = limit; sum >= weight; sum--) {
        final nextCount = count[sum - weight] + take;
        if (nextCount >= none || nextCount > count[sum]) continue;
        final candidate = _PlateStack(plate, take, stacks[sum - weight]);
        if (nextCount == count[sum] && !heavier(candidate, stacks[sum]!)) continue;
        count[sum] = nextCount;
        stacks[sum] = candidate;
      }
    }
  }
  PlateLoad load(int s) {
    final side = [for (final plate in stacks[s]?.expanded() ?? <int>[]) plate / _grid];
    return PlateLoad(bar + 2 * s / _grid, side);
  }

  if (goal <= limit && count[goal] < none) return PlatePlan(target, bar, exact: load(goal));
  int? down, up;
  for (var s = math.min(goal, limit); s >= 0; s--) {
    if (count[s] < none) {
      down = s;
      break;
    }
  }
  for (var s = goal; s <= limit; s++) {
    if (count[s] < none) {
      up = s;
      break;
    }
  }
  return PlatePlan(target, bar, below: down == null ? null : load(down), above: up == null ? null : load(up));
}
