part of '../settings.dart';

/// Original estimates against saved workout-clock durations; viewing never rebuilds a past estimate.
class _WorkoutTimingSettings extends StatefulWidget {
  const _WorkoutTimingSettings();

  @override
  State<_WorkoutTimingSettings> createState() => _WorkoutTimingSettingsState();
}

class _WorkoutTimingSettingsState extends State<_WorkoutTimingSettings> {
  String? _templateId;
  int _visible = 20;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final recorded = store.history.where((s) => s.finishedAt != null && s.doneSets > 0).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final workouts = <String, String>{};
    for (final s in recorded) {
      if (s.templateId case final id?) workouts.putIfAbsent(id, () => s.name);
    }
    final selected = workouts.containsKey(_templateId) ? _templateId : null;
    final sessions = recorded.where((s) => selected == null || s.templateId == selected).toList();
    final visible = sessions.take(_visible).toList();
    final comparable = sessions.where((s) => (s.estimatedSeconds ?? 0) > 0 && s.duration.inSeconds > 0).toList();
    final estimated = comparable.fold(0, (sum, s) => sum + s.estimatedSeconds!);
    final actual = comparable.fold(0, (sum, s) => sum + s.duration.inSeconds);

    Widget cell(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: context.style.sp(8)),
      child: child,
    );
    TableRow row(int index, String date, String name, Widget time) => TableRow(
      decoration: BoxDecoration(color: index.isEven ? cs.surfaceContainerHigh : cs.surface),
      children: [
        cell(Text(date, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 1)),
        cell(Text(name, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
        cell(time),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: LabelWithInfo(
          const Text('Workout timing'),
          InfoDot(
            tooltip: 'About these times',
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Estimates and actual time'),
                content: const Text(
                  'New planned workouts save their original estimate when started, including any deload reduction. '
                  'Later edits never change that estimate. Time uses the saved workout clock, excluding pauses; '
                  'it starts with your first completed set unless you start it yourself.\n\n'
                  'Green means shorter than estimated, red means longer. Hold a time to see its original estimate '
                  'and exact seconds. Percentages use unrounded seconds; displayed minutes are rounded. '
                  'The average includes only workouts with both times. Added warm-ups, extra sets, skipped sets '
                  'and clock resets can affect the comparison.\n\n'
                  'Older workouts and empty quick starts have no original estimate, so only their time is shown.',
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: subPageInsets,
        children: [
          if (workouts.length > 1) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selected,
                  hint: const Text('All workouts'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(child: Text('All workouts')),
                    for (final MapEntry(key: id, value: name) in workouts.entries)
                      DropdownMenuItem(
                        value: id,
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) => setState(() {
                    _templateId = id;
                    _visible = 20;
                  }),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (sessions.isNotEmpty)
            ClipRRect(
              borderRadius: context.style.brSmall,
              child: Table(
                columnWidths: const {0: FixedColumnWidth(60), 1: FlexColumnWidth(), 2: IntrinsicColumnWidth()},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    children: [
                      cell(Text('Date', style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant))),
                      cell(Text('Workout', style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant))),
                      cell(
                        Text(
                          'Time',
                          textAlign: TextAlign.end,
                          style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  for (final (i, s) in visible.indexed)
                    row(i, fmtShortDate(s.startedAt), s.name, _time(context, s.duration.inSeconds, s.estimatedSeconds)),
                  if (comparable.length > 1)
                    row(
                      visible.length,
                      '',
                      'Average · ${comparable.length}',
                      _time(context, actual, estimated, samples: comparable.length),
                    ),
                ],
              ),
            ),
          if (sessions.length > _visible) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => setState(() => _visible += 20), child: const Text('Show more')),
          ],
        ],
      ),
    );
  }

  Widget _time(BuildContext context, int actual, int? estimated, {int samples = 1}) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final percent = estimated != null && estimated > 0 && actual > 0
        ? ((actual - estimated) / estimated * 100).round()
        : null;
    final color = percent == null || percent == 0
        ? cs.onSurface
        : percent > 0
        ? cs.error
        : cs.success;
    final displayedSeconds = actual ~/ samples;
    final value = displayedSeconds < 60 ? '$displayedSeconds s' : '${(displayedSeconds / 60).round()} min';
    final change = percent == null
        ? ''
        : percent == 0
        ? ' (0%)'
        : ' (${percent.abs()}% ${percent > 0 ? 'longer' : 'shorter'})';
    return Tooltip(
      message: [
        if (estimated != null && estimated > 0) 'Estimated ${compactMinutes(estimated ~/ samples)}',
        'Actual ${compactMinutes(displayedSeconds)}',
      ].join(' · '),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: value),
            TextSpan(
              text: change,
              style: t.bodySmall?.copyWith(color: color),
            ),
          ],
        ),
        textAlign: TextAlign.end,
        maxLines: 1,
        style: t.bodyMedium?.copyWith(color: color, fontFeatures: tabular),
      ),
    );
  }
}
