import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../logic/numbers.dart';
import '../logic/plates.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/plate_profile_picker.dart';
import 'settings.dart';

/// The plate calculator as a bottom sheet: one side of the bar drawn to scale with accent-tinted plates, and
/// the plates per side as text. When the plates cannot make [target], the nearest loads either side are
/// offered; with [onUse] (opened from a set) the chosen load can be put into that set.
Future<void> showPlates(BuildContext context, double target, {String? exercise, ValueChanged<double>? onUse}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _PlatesSheet(target: target, exercise: exercise, onUse: onUse),
  );
}

class _PlatesSheet extends StatefulWidget {
  final double target;
  final String? exercise;
  final ValueChanged<double>? onUse;
  const _PlatesSheet({required this.target, this.exercise, this.onUse});

  @override
  State<_PlatesSheet> createState() => _PlatesSheetState();
}

class _PlatesSheetState extends State<_PlatesSheet> {
  /// For an inexact target: whether the load above (rather than below) is shown.
  bool _up = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final unit = store.settings.unit;
    final plan = store.plates(widget.target, name: widget.exercise);
    String w(double v) => '${formatNumber(v, NumKind.load)} $unit';

    final options = [?plan.below, ?plan.above];
    final load = plan.exact ?? (_up ? plan.above ?? plan.below : plan.below ?? plan.above);
    final heaviest = store.settings.plates.fold(0.0, math.max);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    w(load?.total ?? widget.target),
                    style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular),
                  ),
                ),
                Text(
                  plan.bar > 0 ? 'Bar ${w(plan.bar)}' : 'No bar',
                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            if (plan.exact == null) ...[
              const SizedBox(height: 4),
              Text(
                widget.target < plan.bar
                    ? '${w(widget.target)} is lighter than the bar.'
                    : '${w(widget.target)} cannot be made with your plates. Nearest:',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (options.length > 1) ...[
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text(w(plan.below!.total))),
                    ButtonSegment(value: true, label: Text(w(plan.above!.total))),
                  ],
                  selected: {_up},
                  onSelectionChanged: (v) => setState(() => _up = v.first),
                ),
              ],
            ],
            const SizedBox(height: 16),
            if (load != null) ...[
              SizedBox(
                height: 120,
                child: CustomPaint(
                  painter: BarPainter(
                    plates: load.perSide,
                    heaviest: heaviest,
                    unit: unit,
                    bar: cs.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                load.perSide.isEmpty
                    ? (plan.bar > 0 ? 'Just the bar' : 'No plates')
                    : 'Per side: ${load.perSide.map((p) => formatNumber(p, NumKind.load)).join(' + ')}',
                style: t.titleMedium?.copyWith(fontFeatures: tabular),
              ),
              if (load.perSide.isNotEmpty)
                Text(
                  '${w(load.perSide.fold(0.0, (a, b) => a + b))} on each side',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: PlateProfilePicker()),
                ),
                IconButton(
                  tooltip: 'Bar & plates',
                  onPressed: () {
                    // The sheet's own context is gone after pop, so keep its navigator.
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.push(plateSettingsRoute());
                  },
                  icon: const Icon(Icons.tune_rounded, size: 20),
                ),
                if (widget.onUse != null && plan.exact == null && load != null)
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: compactButton),
                    onPressed: () {
                      widget.onUse!(load.total);
                      Navigator.pop(context);
                    },
                    child: Text('Use ${w(load.total)}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Competition plate colours (see [plateColorClass]) and the label colour that reads on each. These are
/// fixed real-world colours, the one deliberate exception to theme tokens, like the celebration palettes.
const _plateColors = {
  'red': (Color(0xFFD32F2F), Colors.white),
  'blue': (Color(0xFF1F5FBF), Colors.white),
  'yellow': (Color(0xFFF2C230), Colors.black),
  'green': (Color(0xFF2E9E4F), Colors.black), // white on this green is only ~3:1
  'white': (Color(0xFFF2F2F2), Colors.black),
  'chrome': (Color(0xFFB8BEC6), Colors.black),
};

/// The bar loaded for [target] (the nearest loadable weight when it cannot be made exactly), drawn small
/// enough to sit inline under an exercise's sets. An inexact load gets a warning-coloured "≈" after it.
class PlateBar extends StatelessWidget {
  final double? target;
  final String exercise;
  const PlateBar({super.key, required this.target, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final unit = store.settings.unit;
    final plan = target == null || target! <= 0 ? null : store.plates(target!, name: exercise);
    final load = plan == null ? null : plan.exact ?? plan.below ?? plan.above;
    return Row(
      children: [
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: BarPainter(
              plates: load?.perSide ?? const [],
              heaviest: store.settings.plates.fold(0.0, math.max),
              unit: unit,
              bar: cs.onSurfaceVariant.withValues(alpha: 0.55),
              compact: true,
            ),
          ),
        ),
        if (plan != null && plan.exact == null)
          Text('≈', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.warning)),
      ],
    );
  }
}

/// One side of the bar: the shaft and collar in grey, then the plates from the collar outwards, heaviest
/// first, in competition colours. Plate height and thickness grow with weight, so the picture reads like a
/// real bar; each plate carries its weight, rotated, inside it when it fits. [compact] shortens the shaft
/// for the inline bar under the sets.
class BarPainter extends CustomPainter {
  final List<double> plates;
  final double heaviest;
  final String unit;
  final Color bar;
  final bool compact;
  BarPainter({
    required this.plates,
    required this.heaviest,
    required this.unit,
    required this.bar,
    this.compact = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final barPaint = Paint()..color = bar;
    final collarX = compact ? 10.0 : 36.0;
    double ratio(double p) => heaviest <= 0 ? 1 : (p / heaviest).clamp(0.0, 1.0);
    // The inline bar is short, so its light plates are relatively taller there to fit "1.25" or "2.5".
    double height(double p) =>
        size.height * (compact ? 0.42 + 0.58 * math.sqrt(ratio(p)) : 0.32 + 0.68 * math.sqrt(ratio(p)));
    // The inline bar uses thinner plates (the owner's request), but never under 9 px: that is the narrowest a
    // rotated label fits, and every plate must keep its number (thinner light plates once lost theirs).
    double thickness(double p) => compact ? 9 + 5 * ratio(p) : 9 + 13 * ratio(p);
    final gap = compact ? 2.0 : 3.0;
    final natural = plates.fold(0.0, (a, p) => a + thickness(p) + gap);
    final room = size.width - collarX - (compact ? 24 : 40);
    final scale = natural > room ? room / natural : 1.0;
    final platesEnd = collarX + 10 + natural * scale;

    // Shaft, collar, then the sleeve the plates sit on, filled as one shape: the bar colour is translucent,
    // so separate pieces would show seams where they meet. Square corners at the collar keep the joins flat;
    // only the shaft's start and the sleeve's outer end are rounded.
    const r = Radius.circular(3);
    final sleeveEnd = math.min(size.width, math.max(platesEnd + 24, collarX + 80));
    canvas.drawPath(
      Path()
        ..addRRect(RRect.fromRectAndCorners(Rect.fromLTRB(0, mid - 3, collarX + 1, mid + 3), topLeft: r, bottomLeft: r))
        ..addRect(Rect.fromLTRB(collarX, mid - 11, collarX + 7, mid + 11))
        ..addRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(collarX + 6, mid - 5, sleeveEnd, mid + 5),
            topRight: r,
            bottomRight: r,
          ),
        ),
      barPaint,
    );

    // A thin dark edge keeps white and chrome plates distinct on a light background.
    final stroke = Paint()
      ..color = const Color(0x40000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    var x = collarX + 10;
    for (final p in plates) {
      final (color, ink) = _plateColors[plateColorClass(p, unit)]!;
      final fill = Paint()..color = color;
      final w = thickness(p) * scale;
      final h = height(p);
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x, mid - h / 2, w, h), Radius.circular(math.min(4, w / 3)));
      canvas
        ..drawRRect(rect, fill)
        ..drawRRect(rect, stroke);
      final fontSize = compact ? 9.0 : 10.0;
      final text = TextPainter(
        text: TextSpan(
          text: formatNumber(p, NumKind.load),
          style: TextStyle(color: ink, fontSize: fontSize, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Only label plates the number fits inside (the inline bar is too short for the small ones).
      if (w >= 9 && text.width <= h - 4) {
        canvas
          ..save()
          ..translate(x + w / 2, mid)
          ..rotate(-math.pi / 2);
        // Centre the digits themselves, not the line box: its ascent and descent are uneven and digits have
        // no descenders, so the visual middle is half a digit height (~0.71 em in Roboto) above the baseline.
        final baseline = text.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        text.paint(canvas, Offset(-text.width / 2, -(baseline - 0.71 * fontSize / 2)));
        canvas.restore();
      }
      x += w + gap * scale;
    }
  }

  @override
  bool shouldRepaint(BarPainter old) =>
      old.compact != compact ||
      !listEquals(old.plates, plates) ||
      old.unit != unit ||
      old.bar != bar ||
      old.heaviest != heaviest;
}
