/// Plate calculator: which plates go on each side of the bar for a target weight.
library;

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
    (25.0, 'red'), (20.0, 'blue'), (15.0, 'yellow'), (10.0, 'green'), (5.0, 'white'),
    (2.5, 'red'), (2.0, 'blue'), (1.5, 'yellow'), (1.0, 'green'), (0.5, 'white'),
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

/// Fewest plates per side for [target] with unlimited pairs of each size in [plates]; ties prefer heavier
/// plates. Inexact targets give the nearest loads either side.
PlatePlan planPlates(double target, double bar, List<double> plates) {
  final sizes = {for (final p in plates) if (p > 0) (p * _grid).round()}.toList()..sort((a, b) => b.compareTo(a));
  final goal = ((target - bar) / 2 * _grid).round();
  if (goal < 0) {
    return PlatePlan(target, bar, above: PlateLoad(bar, const []));
  }
  // Reach one plate beyond the goal, so the next load up can be found too.
  final limit = goal + (sizes.isEmpty ? 0 : sizes.first);
  const none = 1 << 30;
  final count = List.filled(limit + 1, none)..[0] = 0;
  final last = List.filled(limit + 1, 0);
  for (var s = 1; s <= limit; s++) {
    for (final p in sizes) {
      if (p <= s && count[s - p] + 1 < count[s]) {
        count[s] = count[s - p] + 1;
        last[s] = p;
      }
    }
  }
  PlateLoad load(int s) {
    final side = <double>[];
    for (var x = s; x > 0; x -= last[x]) {
      side.add(last[x] / _grid);
    }
    side.sort((a, b) => b.compareTo(a));
    return PlateLoad(bar + 2 * s / _grid, side);
  }

  if (count[goal] < none) return PlatePlan(target, bar, exact: load(goal));
  int? down, up;
  for (var s = goal; s >= 0; s--) {
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
  return PlatePlan(
    target,
    bar,
    below: down == null ? null : load(down),
    above: up == null ? null : load(up),
  );
}
