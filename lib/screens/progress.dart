import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/numbers.dart';

import '../logic/methods.dart';

import '../models.dart';
import '../theme.dart';
import 'exercises.dart';
import 'bodyweight.dart';
import '../widgets/common.dart';

void openExerciseProgress(BuildContext context, String name) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExerciseProgressScreen(name: name)));
}

/// Estimated one-rep max trend per exercise (History → Exercises).
class ExerciseProgressList extends StatelessWidget {
  const ExerciseProgressList({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final rows = [
      for (final name in store.performedExercises())
        if (store.progress(name) case final points when points.isNotEmpty) (name: name, points: points),
    ]..sort((a, b) => b.points.last.date.compareTo(a.points.last.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (store.settings.trackBodyweight) const BodyweightSummaryCard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(
            store.settings.trackBodyweight ? 'Exercise trends' : 'Estimated one-rep max per exercise',
            style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'Log a workout to see trends.',
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        for (final r in rows)
          Padding(
            padding: EdgeInsets.only(bottom: context.style.sp(10)),
            child: () {
              final latest = r.points.last.value;
              final first = r.points.first.value;
              final delta = first == 0 ? 0 : (latest - first) / first * 100;
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => openExerciseProgress(context, r.name),
                  child: Padding(
                    padding: EdgeInsets.all(context.style.sp(16)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text:
                                          '${fmtNum(latest.roundToDouble())} ${store.settings.unit}${store.usesBodyweightProgress(r.name) ? ' combined' : ''}',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    if (r.points.length > 1)
                                      TextSpan(
                                        text: '  ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%',
                                        style: TextStyle(color: delta >= 0 ? cs.primary : cs.error),
                                      ),
                                  ],
                                ),
                                style: t.bodyMedium?.copyWith(fontFeatures: tabular),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 96,
                          height: 36,
                          child: CustomPaint(
                            painter: LineChartPainter(
                              values: [for (final p in r.points) p.value],
                              color: cs.primary,
                              fill: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }(),
          ),
      ],
    );
  }
}

class ExerciseProgressScreen extends StatelessWidget {
  final String name;
  const ExerciseProgressScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final info = store.exercise(name);
    final points = store.progress(name);
    final combined = store.usesBodyweightProgress(name);
    final unit = store.settings.unit;
    final best = points.isEmpty ? null : points.reduce((a, b) => a.value >= b.value ? a : b);

    return Scaffold(
      appBar: AppBar(
        title: combined
            ? LabelWithInfo(
                Text(name),
                InfoDot(
                  tooltip: 'Combined load',
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Combined load'),
                      content: const Text(
                        'Bodyweight saved with that workout, plus added load or minus assistance. This is a load trend, not an estimated rep max. The weights you enter and automatic progression stay unchanged.',
                      ),
                      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
                    ),
                  ),
                ),
              )
            : Text(name),
        actions: [
          IconButton(
            tooltip: 'Edit exercise',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => openExerciseEditor(context, name),
          ),
        ],
      ),
      body: ListView(
        padding: subPageInsets,
        children: [
          if (info != null && info.primary.isNotEmpty) ...[
            Text([...info.primary, ...info.secondary].join(' · ').toUpperCase(), style: t.labelSmall),
            const SizedBox(height: 16),
          ],
          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Text(
                'No completed sets yet.',
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Stat(
                    '${fmtNum(best!.value.roundToDouble())} $unit',
                    combined ? 'best combined load' : 'best e1RM',
                  ),
                ),
                Expanded(child: Stat('${fmtNum(best.best.weight)}×${best.best.reps}', 'best set')),
                Expanded(child: Stat('${points.length}', 'sessions')),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                child: Column(
                  children: [
                    SizedBox(
                      height: 180,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: LineChartPainter(
                          values: [for (final p in points) p.value],
                          color: cs.primary,
                          grid: cs.outlineVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(fmtShortDate(points.first.date), style: t.labelSmall),
                        Text(fmtShortDate(points.last.date), style: t.labelSmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!combined) ...[const SectionLabel('Rep maxes'), _RepMaxTable(e1rm: points.last.value, unit: unit)],
            const SectionLabel('Exercise history'),
            for (final (sess, ex) in [
              for (final h in store.history)
                for (final x in h.exercises.where((x) => x.name == name)) (h, x),
            ].take(100))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(sess.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                            ),
                            Text(fmtRecent(sess.startedAt, unit, includeTime: false), style: t.bodySmall),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (store.settings.trackBodyweight &&
                            sess.bodyweight != null &&
                            const {'bodyweight', 'assisted'}.contains(ex.loadMode))
                          Text(
                            'Bodyweight ${formatNumber(sess.bodyweight!, NumKind.weight)} ${sess.unit}',
                            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        for (final set in ex.sets)
                          Text(
                            [
                              '${set.weight == null ? '—' : formatNumber(set.weight!, NumKind.weight)} '
                                  '${loadSuffix(ex.loadMode, sess.unit)} × ${set.reps ?? '—'} reps',
                              if (set.rir != null && !set.warmup) 'actual ${set.rir} RIR',
                              if (set.targetRir != null) 'target ${set.targetRir} RIR',
                              if (!isStraightType(set.type)) set.type,
                              if (!set.context.isEmpty) set.context.summary(),
                              if (!set.done) 'not completed',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(color: set.done ? null : cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RepMaxTable extends StatelessWidget {
  final double e1rm;
  final String unit;
  const _RepMaxTable({required this.e1rm, required this.unit});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const reps = [1, 3, 5, 8, 10, 12];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            for (final r in reps)
              Expanded(
                child: Column(
                  children: [
                    Text(fmtNum(_weightFor(r)), style: t.titleMedium?.copyWith(fontFeatures: tabular)),
                    const SizedBox(height: 2),
                    Text('${r}RM', style: t.labelSmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _weightFor(int reps) {
    final w = e1rm * wathanPercent(reps) / 100;
    return (w * 2).round() / 2;
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final Color? grid;
  final bool fill;

  LineChartPainter({required this.values, required this.color, this.grid, this.fill = true});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    const pad = 6.0;
    final h = size.height - pad * 2;

    final w = size.width - pad * 2;
    Offset at(int i) =>
        Offset(pad + (values.length == 1 ? w / 2 : i / (values.length - 1) * w), pad + h - (values[i] - lo) / span * h);

    if (grid != null) {
      final gp = Paint()
        ..color = grid!
        ..strokeWidth = 1;
      for (var g = 0; g <= 3; g++) {
        final y = pad + h * g / 3;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
      }
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p0 = at(i - 1), p1 = at(i);
      final mx = (p0.dx + p1.dx) / 2;
      path.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }

    if (fill && values.length > 1) {
      final area = Path.from(path)
        ..lineTo(at(values.length - 1).dx, size.height)
        ..lineTo(at(0).dx, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = fill ? 2.5 : 2
        ..strokeCap = StrokeCap.round,
    );
    final last = at(values.length - 1);
    canvas.drawCircle(last, fill ? 5 : 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(LineChartPainter old) =>
      old.color != color || old.grid != grid || old.fill != fill || !_sameValues(old.values);

  bool _sameValues(List<double> other) {
    if (other.length != values.length) return false;
    for (var i = 0; i < values.length; i++) {
      if (other[i] != values[i]) return false;
    }
    return true;
  }
}
