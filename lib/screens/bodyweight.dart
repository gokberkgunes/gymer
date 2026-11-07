import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/bodyweight.dart';
import '../logic/numbers.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/num_field.dart';
import '../store.dart';

class BodyweightSummaryCard extends StatelessWidget {
  const BodyweightSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (!store.settings.trackBodyweight) return const SizedBox.shrink();
    final points = bodyweightTrend(store.bodyweights, store.settings.unit);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BodyweightScreen())),
          child: Padding(
            padding: EdgeInsets.all(context.style.sp(16)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bodyweight', style: t.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        points.isEmpty
                            ? 'No entries'
                            : '${formatNumber(points.last.weight, NumKind.weight)} ${store.settings.unit}',
                        style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                      ),
                    ],
                  ),
                ),
                if (points.isNotEmpty)
                  SizedBox(
                    width: 96,
                    height: 36,
                    child: CustomPaint(painter: _WeightChart(points, cs.primary, cs.onSurfaceVariant, dots: false)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BodyweightScreen extends StatelessWidget {
  const BodyweightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final unit = store.settings.unit;
    final points = bodyweightTrend(store.bodyweights, unit);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final enabled = store.settings.trackBodyweight;
    return Scaffold(
      appBar: AppBar(
        title: LabelWithInfo(
          const Text('Bodyweight'),
          InfoDot(
            tooltip: 'Bodyweight tracking',
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Bodyweight'),
                content: const Text(
                  'One measurement per day. The line is a seven-day smoothed trend; dots show actual measurements. New workouts keep the latest known bodyweight from that day or earlier. Editing this log never rewrites finished workouts.',
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
              ),
            ),
          ),
        ),
        actions: [
          if (enabled)
            IconButton.filled(
              tooltip: 'Log bodyweight',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _editBodyweight(context),
            ),
        ],
      ),
      body: !enabled
          ? null
          : ListView(
              padding: subPageInsets,
              children: [
                if (points.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Text(
                      'No entries.',
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(child: Stat('${formatNumber(points.last.weight, NumKind.weight)} $unit', 'Latest')),
                      Expanded(child: Stat('${formatNumber(points.last.trend, NumKind.weight)} $unit', '7-day trend')),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(context.style.sp(16)),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 180,
                            width: double.infinity,
                            child: CustomPaint(painter: _WeightChart(points, cs.primary, cs.onSurfaceVariant)),
                          ),
                          const SizedBox(height: 12),
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
                  const SectionLabel('Measurements'),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, entry) in store.bodyweights.reversed.indexed) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          ListTile(
                            title: Text(fmtDate(entry.date)),
                            trailing: Text(
                              '${formatNumber(entry.inUnit(unit), NumKind.weight)} $unit',
                              style: t.titleMedium?.copyWith(fontFeatures: tabular),
                            ),
                            onTap: () => _editBodyweight(context, entry: entry),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

Future<void> _editBodyweight(BuildContext context, {BodyweightEntry? entry}) async {
  final store = StoreScope.read(context);
  if (!store.settings.trackBodyweight) return;
  var day = entry?.date ?? dateOnly(DateTime.now());
  double? value = entry?.inUnit(store.settings.unit);
  await showDialog<void>(
    context: context,
    builder: (dc) => StatefulBuilder(
      builder: (dc, setDialog) => AlertDialog(
        title: Text(entry == null ? 'Log bodyweight' : 'Edit bodyweight'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NumField(
              value: value,
              kind: NumKind.weight,
              suffix: store.settings.unit,
              placeholder: 'Weight',
              onChanged: (v) => setDialog(() => value = v),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                final date = await showDatePicker(
                  context: dc,
                  initialDate: day,
                  firstDate: DateTime(2000),
                  lastDate: dateOnly(DateTime.now()),
                );
                if (date != null && dc.mounted) setDialog(() => day = date);
              },
              child: Text(fmtDate(day)),
            ),
          ],
        ),
        actions: [
          if (entry != null)
            TextButton(
              onPressed: () {
                store.removeBodyweight(entry.date);
                Navigator.pop(dc);
              },
              style: TextButton.styleFrom(foregroundColor: Theme.of(dc).colorScheme.error),
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancel')),
          TextButton(
            onPressed: value == null || !value!.isFinite || value! <= 0
                ? null
                : () {
                    final error = store.logBodyweight(day, value!);
                    if (error != null) return notify(dc, error);
                    if (entry != null && dateKey(entry.date) != dateKey(day)) store.removeBodyweight(entry.date);
                    Navigator.pop(dc);
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

class _WeightChart extends CustomPainter {
  final List<BodyweightPoint> points;
  final Color color, neutral;
  final bool dots;
  _WeightChart(this.points, this.color, this.neutral, {this.dots = true});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final lo = points.map((p) => math.min(p.weight, p.trend)).reduce(math.min);
    final hi = points.map((p) => math.max(p.weight, p.trend)).reduce(math.max);
    final span = math.max(1.0, hi - lo);
    final center = (lo + hi) / 2;
    final days = math.max(1, daysBetween(points.first.date, points.last.date));
    Offset at(BodyweightPoint p, double value) => Offset(
      points.length == 1 ? size.width / 2 : 6 + daysBetween(points.first.date, p.date) / days * (size.width - 12),
      6 + (center + span / 2 - value) / span * (size.height - 12),
    );
    final path = Path();
    for (final (i, point) in points.indexed) {
      final position = at(point, point.trend);
      if (i == 0) {
        path.moveTo(position.dx, position.dy);
      } else {
        path.lineTo(position.dx, position.dy);
      }
      if (dots) canvas.drawCircle(at(point, point.weight), 3, Paint()..color = neutral.withValues(alpha: 0.6));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(at(points.last, points.last.trend), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WeightChart old) =>
      old.points != points || old.color != color || old.neutral != neutral || old.dots != dots;
}
