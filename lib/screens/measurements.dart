import 'package:flutter/material.dart';

import '../logic/bodyweight.dart';
import '../logic/numbers.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/num_field.dart';
import 'progress.dart' show LineChartPainter;

String _length(double value, String unit) =>
    '${formatNumber((value * 10).round() / 10, NumKind.weight)} ${MeasurementEntry.lengthUnit(unit)}';

/// The latest value of each measured site, beside the bodyweight card in History → Exercises.
class MeasurementsSummaryCard extends StatelessWidget {
  const MeasurementsSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (!store.settings.trackMeasurements) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final unit = store.settings.unit;
    final latest = [
      for (final site in measurementSites)
        if (store.measurements.where((e) => e.site == site).lastOrNull case final e?)
          '$site ${_length(e.inUnit(unit), unit)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MeasurementsScreen())),
          child: Padding(
            padding: EdgeInsets.all(context.style.sp(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Measurements', style: t.titleMedium),
                const SizedBox(height: 4),
                Text(
                  latest.isEmpty ? 'No entries' : latest.join(' · '),
                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MeasurementsScreen extends StatelessWidget {
  const MeasurementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final unit = store.settings.unit;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final enabled = store.settings.trackMeasurements;
    final weight = store.settings.trackBodyweight
        ? bodyweightTrend(store.bodyweights, unit)
        : const <BodyweightPoint>[];
    return Scaffold(
      appBar: AppBar(
        title: LabelWithInfo(
          const Text('Measurements'),
          InfoDot(
            tooltip: 'Body measurements',
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Body measurements'),
                content: const Text(
                  'Optional tape measurements: one value per site per day. Measure at the same spot, at the same '
                  'time of day, relaxed, for values you can compare. Tap a site to add today\'s value and an entry '
                  'to change it.\n\n'
                  'Waist is the simplest check on a gaining phase: bodyweight going up while the waist stays put '
                  'points to muscle, both rising together points to fat. With bodyweight tracking on, the waist '
                  'card shows the two side by side.',
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
              ),
            ),
          ),
        ),
      ),
      body: !enabled
          ? null
          : ListView(
              padding: subPageInsets,
              children: [
                const SizedBox(height: 12),
                for (final site in measurementSites)
                  () {
                    final entries = store.measurements.where((e) => e.site == site).toList();
                    final change = entries.length < 2 ? null : entries.last.inUnit(unit) - entries.first.inUnit(unit);
                    // Bodyweight over the same span, for reading the waist.
                    final span = site != 'Waist' || entries.length < 2
                        ? const <BodyweightPoint>[]
                        : weight
                              .where((p) => !p.date.isBefore(entries.first.date) && !p.date.isAfter(entries.last.date))
                              .toList();
                    return Padding(
                      padding: EdgeInsets.only(bottom: context.style.sp(10)),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _editMeasurement(context, site: site),
                          child: Padding(
                            padding: EdgeInsets.all(context.style.sp(16)),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(site, style: t.titleMedium),
                                      const SizedBox(height: 4),
                                      Text(
                                        entries.isEmpty
                                            ? 'No entries'
                                            : [
                                                _length(entries.last.inUnit(unit), unit),
                                                if (change != null && change.abs() >= 0.05)
                                                  '${change > 0 ? '+' : '−'}${_length(change.abs(), unit)}',
                                              ].join('  '),
                                        style: t.bodyMedium?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontFeatures: tabular,
                                        ),
                                      ),
                                      if (span.length > 1)
                                        Text(
                                          'Bodyweight ${span.last.trend >= span.first.trend ? '+' : '−'}'
                                          '${formatNumber((span.last.trend - span.first.trend).abs(), NumKind.weight)} $unit '
                                          'over the same time',
                                          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                        ),
                                    ],
                                  ),
                                ),
                                if (entries.length > 1)
                                  SizedBox(
                                    width: 96,
                                    height: 36,
                                    child: CustomPaint(
                                      painter: LineChartPainter(
                                        values: [for (final e in entries) e.cm],
                                        dates: [for (final e in entries) e.date],
                                        color: cs.primary,
                                        fill: false,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }(),
                if (store.measurements.isNotEmpty) ...[
                  const SectionLabel('Entries'),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, entry) in store.measurements.reversed.indexed) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          ListTile(
                            title: Text(entry.site),
                            subtitle: Text(fmtDate(entry.date)),
                            trailing: Text(
                              _length(entry.inUnit(unit), unit),
                              style: t.titleMedium?.copyWith(fontFeatures: tabular),
                            ),
                            onTap: () => _editMeasurement(context, site: entry.site, entry: entry),
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

Future<void> _editMeasurement(BuildContext context, {required String site, MeasurementEntry? entry}) async {
  final store = StoreScope.read(context);
  if (!store.settings.trackMeasurements) return;
  final unit = store.settings.unit;
  var day = entry?.date ?? dateOnly(DateTime.now());
  double? value = entry?.inUnit(unit);
  var badText = false;
  await showDialog<void>(
    context: context,
    builder: (dc) => StatefulBuilder(
      builder: (dc, setDialog) => AlertDialog(
        title: Text(site),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NumField(
              value: value,
              kind: NumKind.weight,
              suffix: MeasurementEntry.lengthUnit(unit),
              placeholder: 'Around',
              onChanged: (v) => setDialog(() => value = v),
              onBadText: (bad) => setDialog(() => badText = bad),
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
                store.removeMeasurement(entry);
                Navigator.pop(dc);
              },
              style: TextButton.styleFrom(foregroundColor: Theme.of(dc).colorScheme.error),
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancel')),
          TextButton(
            onPressed: badText || value == null || !value!.isFinite || value! <= 0
                ? null
                : () {
                    final error = store.logMeasurement(day, site, value!);
                    if (error != null) return notify(dc, error);
                    if (entry != null && dateKey(entry.date) != dateKey(day)) store.removeMeasurement(entry);
                    Navigator.pop(dc);
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
