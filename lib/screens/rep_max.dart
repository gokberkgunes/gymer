import 'package:flutter/material.dart';

import '../logic/numbers.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/num_field.dart';
import 'plates.dart';
import '../store.dart';

void openRepMaxForExercise(BuildContext context, String exercise) {
  final store = StoreScope.read(context);
  final (weight, rm, note) = store.repMaxSeed(exercise);
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RepMaxScreen(exercise: exercise, initialWeight: weight, initialRm: rm, note: note),
    ),
  );
}

/// Rep Max calculator: a known RM gives an estimated 1RM (Wathan), RIR
/// targets for the chosen rep count, and the 1–20 RM table.
class RepMaxScreen extends StatefulWidget {
  final String? exercise;
  final double? initialWeight;
  final int? initialRm;
  final String? note;
  final bool asTab;

  const RepMaxScreen({super.key, this.exercise, this.initialWeight, this.initialRm, this.note, this.asTab = false});

  @override
  State<RepMaxScreen> createState() => _RepMaxScreenState();
}

class _RepMaxScreenState extends State<RepMaxScreen> {
  late double? _weight = widget.initialWeight;
  late int? _rm = widget.initialRm;
  int? _targetReps;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final unit = store.settings.unit;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final targetReps = _targetReps ?? store.settings.repMaxTargetReps;
    final w = _weight, rm = _rm;
    final oneRm = w != null && w > 0 && rm != null && rm >= 1 ? w / (wathanPercent(rm) / 100) : null;
    String kg(double v) => '${v.round()} $unit';

    Widget table(List<Widget> rows) => Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
    // Light header: small muted labels over a hairline, no filled bar.
    // The last column holds loads: a small dumbbell there says a tap shows the plates.
    Widget header(List<String> cells) => Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (final (i, c) in cells.indexed)
            Expanded(
              flex: i == cells.length - 1 ? 2 : 1,
              child: i == cells.length - 1
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(Icons.fitness_center_rounded, size: 12, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(c.toUpperCase(), style: t.labelSmall),
                      ],
                    )
                  : Text(c.toUpperCase(), textAlign: TextAlign.right, style: t.labelSmall),
            ),
        ],
      ),
    );
    // Tapping a load opens the plate calculator (with the exercise's own bar when opened from one).
    Widget load(double? v, TextStyle style) => InkWell(
      borderRadius: context.style.brSmall,
      onTap: v == null || v <= 0 ? null : () => showPlates(context, v.roundToDouble(), exercise: widget.exercise),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(v == null ? '—' : kg(v), textAlign: TextAlign.right, style: style),
      ),
    );

    final info = InfoDot(tooltip: 'How to use this calculator', onTap: () => _info(context));
    final body = ListView(
      padding: widget.asTab ? pageInsets : subPageInsets,
      children: [
        if (widget.asTab) PageHeader('Rep Max', info: info),
        if (widget.note != null) Text(widget.note!, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        if (!widget.asTab) const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: NumField(
                value: _weight,
                kind: NumKind.weight,
                placeholder: 'Known weight ($unit)',
                suffix: unit,
                dense: false,
                onChanged: (v) => setState(() => _weight = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: NumField(
                value: _rm?.toDouble(),
                kind: NumKind.rm,
                placeholder: 'Known RM',
                dense: false,
                onChanged: (v) => setState(() => _rm = v?.round()),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Row(
            children: [
              Expanded(child: Text('Estimated 1RM', style: t.bodyLarge)),
              Text(oneRm == null ? '—' : kg(oneRm), style: t.titleLarge?.copyWith(fontFeatures: tabular)),
            ],
          ),
        ),
        // Targets need a known 1RM; until then the tables would be a column of dashes.
        if (oneRm != null) ...[
          const SectionLabel('RIR targets'),
          Row(
            children: [
              Text('Target reps', style: t.bodyLarge),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: NumField(
                  value: targetReps.toDouble(),
                  kind: NumKind.targetReps,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _targetReps = v.round());
                    store.updateSettings((s) => s.repMaxTargetReps = v.round());
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          table([
            header(['RIR', '$targetReps reps', 'Target weight']),
            for (final rir in const [3, 2, 1])
              () {
                final double target = (oneRm * wathanPercent(targetReps + rir) / 100).roundToDouble();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$rir',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(child: Text('$targetReps', textAlign: TextAlign.right)),
                      Expanded(
                        flex: 2,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            load(target, const TextStyle(fontWeight: FontWeight.bold, fontFeatures: tabular)),
                            if (widget.exercise != null) ...[
                              const SizedBox(width: 8),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(minimumSize: compactButton),
                                onPressed: target <= 0 || store.active == null
                                    ? null
                                    : () {
                                        final message = store.applyRepMaxTarget(
                                          widget.exercise!,
                                          target,
                                          targetReps,
                                          rir,
                                        );
                                        Navigator.pop(context);
                                        notify(context, message);
                                      },
                                child: const Text('Use'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }(),
          ]),
          if (widget.exercise != null) ...[
            const SizedBox(height: 6),
            Text(
              'Use loads that target into the next unfinished set.',
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
        const SectionLabel('1–20 RM table'),
        table([
          header(['RM', '% 1RM', 'Target']),
          for (var r = 1; r <= 20; r++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$r RM',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(child: Text('${wathanPercent(r).round()}%', textAlign: TextAlign.right)),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: load(
                        oneRm == null ? null : oneRm * wathanPercent(r) / 100,
                        const TextStyle(fontFeatures: tabular),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ]),
      ],
    );
    return widget.asTab
        ? body
        : Scaffold(
            appBar: AppBar(
              title: LabelWithInfo(
                Text(
                  widget.exercise == null ? 'Rep Max Calculator' : '${widget.exercise} Rep Max',
                  overflow: TextOverflow.ellipsis,
                ),
                info,
              ),
            ),
            body: body,
          );
  }

  void _info(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('How to use Rep Max'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (title, body) in const [
                (
                  'Start from a set you already know',
                  'Enter a weight and the repetition maximum that weight represents. You can use 1RM, any value '
                      'shown in the 1–20RM table, or a higher RM value. You do not need to test a true one-rep maximum.',
                ),
                (
                  'Use the RIR targets to choose a working weight',
                  'Pick the effort you want for the next set. The target rows translate your rep goal and RIR into a '
                      'suggested starting weight. Use the result as a practical first choice, then adjust from your '
                      'actual performance.',
                ),
                (
                  'Prefer your own history',
                  'The estimate is most useful for choosing a sensible starting load. If your completed sets '
                      'repeatedly feel easier or harder than predicted, your own logged performance should take priority.',
                ),
                (
                  'Wathan equation',
                  'The calculator uses the Wathan repetition-max equation for RM conversions above 1RM. The 1RM row '
                      'itself is 100% by definition.\n\n1RM = weight × 100 / (48.8 + 53.8 × exp(-0.075 × reps))\n'
                      'For reps ≥ 2: %1RM = 48.8 + 53.8 × exp(-0.075 × reps)\n1RM = 100%\n\n'
                      'The calculator keeps the Wathan percentage at full precision when calculating weights. The %1RM '
                      'column is rounded to the nearest whole percent only to keep the table easy to read. Calculations '
                      'can still use RM values above 20. For RIR planning, target reps + RIR selects the effective '
                      'repetition maximum. For example, 8 reps with 3 RIR uses the 11RM estimate.',
                ),
              ]) ...[
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(body),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }
}
