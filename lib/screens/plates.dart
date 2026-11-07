import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../logic/numbers.dart';
import '../logic/plates.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/plate_profile_picker.dart';
import 'settings.dart';
import '../store.dart';

/// The plate calculator as a bottom sheet: one side of the bar drawn to scale with labelled plates.
/// When the plates cannot make [target], the nearest loads either side are
/// offered; with [onUse] (opened from a set) the chosen load can be put into that set.
Future<void> showPlates(BuildContext context, double target, {String? exercise, ValueChanged<double>? onUse}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
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
    final cs = Theme.of(context).colorScheme;
    final unit = store.settings.unit;
    final plan = store.plates(widget.target, name: widget.exercise);
    String w(double v) => '${formatNumber(v, NumKind.load)} $unit';

    final options = [?plan.below, ?plan.above];
    final load = plan.exact ?? (_up ? plan.above ?? plan.below : plan.below ?? plan.above);
    final heaviest = store.settings.plates.fold(0.0, math.max);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SizedBox(
          height: 128,
          child: Stack(
            children: [
              if (load != null)
                Positioned.fill(
                  child: Semantics(
                    image: true,
                    label:
                        '${w(load.total)} total. Plates on each side: '
                        '${plateGroups(load.perSide, groupRepeated: true).map((group) => '${group.count} × ${formatNumber(group.weight, NumKind.load)} $unit').join(', ')}',
                    child: AnimatedPlateBar(
                      plates: load.perSide,
                      animateInitial: true,
                      painter: (keep, t) => BarPainter(
                        plates: load.perSide,
                        heaviest: heaviest,
                        unit: unit,
                        bar: cs.onSurfaceVariant.withValues(alpha: 0.55),
                        groupRepeated: store.settings.groupRepeatedPlates,
                        keep: keep,
                        t: t,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 96),
                      child: const IntrinsicWidth(child: PlateProfilePicker()),
                    ),
                    IconButton(
                      tooltip: 'Bar & plates',
                      onPressed: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        nav.push(plateSettingsRoute());
                      },
                      icon: const Icon(Icons.tune_rounded, size: 18),
                    ),
                  ],
                ),
              ),
              if (plan.exact == null && load != null)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (options.length > 1)
                        PopupMenuButton<bool>(
                          tooltip: 'Nearest available load to ${w(widget.target)}',
                          onSelected: (up) => setState(() => _up = up),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: false, child: Text(w(plan.below!.total))),
                            PopupMenuItem(value: true, child: Text(w(plan.above!.total))),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '≈ ${w(load.total)}',
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                                ),
                                Icon(Icons.expand_more_rounded, size: 16, color: cs.onSurfaceVariant),
                              ],
                            ),
                          ),
                        )
                      else if (widget.onUse == null)
                        Tooltip(
                          message: 'Nearest available load to ${w(widget.target)}',
                          child: Text(
                            '≈ ${w(load.total)}',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      if (widget.onUse != null)
                        TextButton(
                          style: TextButton.styleFrom(minimumSize: compactButton),
                          onPressed: () {
                            widget.onUse!(load.total);
                            Navigator.pop(context);
                          },
                          child: Text('Use ${w(load.total)}'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
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
          child: AnimatedPlateBar(
            plates: load?.perSide ?? const [],
            painter: (keep, t) => BarPainter(
              plates: load?.perSide ?? const [],
              heaviest: store.settings.plates.fold(0.0, math.max),
              unit: unit,
              bar: cs.onSurfaceVariant.withValues(alpha: 0.55),
              compact: true,
              groupRepeated: store.settings.groupRepeatedPlates,
              keep: keep,
              t: t,
            ),
          ),
        ),
        if (plan != null && plan.exact == null)
          Text('≈', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.warning)),
      ],
    );
  }
}

/// Draws a [BarPainter] and slides newly added plates onto the bar from the outer end. Plates already
/// on the bar (the same leading plates as before) stay still, so small edits only move what changed.
/// The sheet animates when it opens; the inline bar only when its load changes. Reduced motion skips it.
class AnimatedPlateBar extends StatefulWidget {
  final List<double> plates;
  final bool animateInitial;
  final BarPainter Function(int keep, double t) painter;
  const AnimatedPlateBar({super.key, required this.plates, required this.painter, this.animateInitial = false});

  @override
  State<AnimatedPlateBar> createState() => _AnimatedPlateBarState();
}

class _AnimatedPlateBarState extends State<AnimatedPlateBar> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700), value: 1);
  late int _keep = widget.animateInitial ? 0 : widget.plates.length;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.animateInitial && widget.plates.isNotEmpty && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(AnimatedPlateBar old) {
    super.didUpdateWidget(old);
    if (listEquals(old.plates, widget.plates)) return;
    var common = 0;
    while (common < old.plates.length && common < widget.plates.length && old.plates[common] == widget.plates[common]) {
      common++;
    }
    _keep = common;
    if (common < widget.plates.length && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => CustomPaint(size: Size.infinite, painter: widget.painter(_keep, _controller.value)),
  );
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
  final bool groupRepeated;

  /// Plates before this index are static; later ones slide in as [t] runs from 0 to 1.
  final int? keep; // null: every plate is already on the bar
  final double t;
  BarPainter({
    required this.plates,
    required this.heaviest,
    required this.unit,
    required this.bar,
    this.compact = false,
    this.groupRepeated = false,
    this.keep,
    this.t = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final barPaint = Paint()..color = bar;
    final collarX = compact ? 10.0 : 36.0;
    final groups = plateGroups(plates, groupRepeated: groupRepeated);
    final quantities = [
      for (final group in groups)
        group.count > 1
            ? (TextPainter(
                text: TextSpan(
                  text: '${group.count}',
                  style: TextStyle(
                    color: _plateColors[plateColorClass(group.weight, unit)]!.$2,
                    fontSize: compact ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
                textDirection: TextDirection.ltr,
              )..layout())
            : null,
    ];
    double ratio(double p) => heaviest <= 0 ? 1 : (p / heaviest).clamp(0.0, 1.0);
    // The inline bar is short, so its light plates are relatively taller there to fit "1.25" or "2.5".
    double height(double p) =>
        size.height * (compact ? 0.42 + 0.58 * math.sqrt(ratio(p)) : 0.32 + 0.68 * math.sqrt(ratio(p)));
    // The inline bar uses thinner plates (the owner's request), but never under 9 px: that is the narrowest a
    // rotated label fits, and every plate must keep its number (thinner light plates once lost theirs).
    double thickness(double p) => compact ? 9 + 5 * ratio(p) : 9 + 13 * ratio(p);
    final gap = compact ? 2.0 : 3.0;
    final natural = groups.fold(0.0, (a, group) => a + thickness(group.weight) + gap);
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
    var plateIndex = 0;
    var newOrder = 0;
    var firstNew = -1;
    for (final (index, group) in groups.indexed) {
      if (keep != null && plateIndex >= keep! && firstNew < 0) firstNew = index;
      plateIndex += group.count;
    }
    final fresh = firstNew < 0 ? 0 : groups.length - firstNew;
    plateIndex = 0;
    for (final (index, group) in groups.indexed) {
      final isNew = keep != null && plateIndex >= keep! && t < 1;
      plateIndex += group.count;
      double slide = 1;
      if (isNew) {
        final start = newOrder++ * 0.5 / math.max(1, fresh);
        slide = Curves.easeOutCubic.transform(((t - start) / 0.5).clamp(0.0, 1.0));
        if (slide <= 0) {
          x += thickness(group.weight) * scale + gap * scale;
          continue;
        }
        canvas
          ..saveLayer(null, Paint()..color = Color.fromRGBO(255, 255, 255, slide))
          ..translate((1 - slide) * 36, 0);
      }
      final p = group.weight;
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
      final quantity = quantities[index];
      final quantityScale = quantity == null ? 1.0 : math.min(1.0, math.max(0.0, w - 2) / quantity.width);
      // Centre the count along the plate's top edge without changing plate size or spacing.
      // Keep the weight centred where it fits; on small plates, use the space immediately below the count.
      final labelTop = mid - h / 2 + (quantity == null ? 2 : quantity.height * quantityScale + 3);
      final labelBottom = mid + h / 2 - 2;
      final labelRoom = math.max(0.0, labelBottom - labelTop);
      if (w >= 9 && labelRoom > 0) {
        final labelScale = math.min(1.0, labelRoom / text.width);
        final halfLength = text.width * labelScale / 2;
        final labelMid = math.max(labelTop + halfLength, math.min(mid, labelBottom - halfLength));
        canvas
          ..save()
          ..translate(x + w / 2, labelMid)
          ..rotate(-math.pi / 2)
          ..scale(labelScale);
        // Centre the digits themselves, not the line box: its ascent and descent are uneven and digits have
        // no descenders, so the visual middle is half a digit height (~0.71 em in Roboto) above the baseline.
        final baseline = text.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        text.paint(canvas, Offset(-text.width / 2, -(baseline - 0.71 * fontSize / 2)));
        canvas.restore();
      }
      if (quantity != null) {
        canvas
          ..save()
          ..translate(x + (w - quantity.width * quantityScale) / 2, mid - h / 2 + 1)
          ..scale(quantityScale);
        quantity.paint(canvas, Offset.zero);
        canvas.restore();
      }
      if (isNew) canvas.restore();
      x += w + gap * scale;
    }
  }

  @override
  bool shouldRepaint(BarPainter old) =>
      old.compact != compact ||
      old.keep != keep ||
      old.t != t ||
      old.groupRepeated != groupRepeated ||
      !listEquals(old.plates, plates) ||
      old.unit != unit ||
      old.bar != bar ||
      old.heaviest != heaviest;
}
