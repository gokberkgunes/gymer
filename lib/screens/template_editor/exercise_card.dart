part of '../template_editor.dart';

class _PlannedWork extends StatelessWidget {
  final VolumeReport report;
  const _PlannedWork({required this.report});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    List<Widget> section(String title, Map<String, VolumeMetrics> rows) => [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(title, style: t.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
      ),
      if (rows.isEmpty) Text('No tagged work', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      for (final MapEntry(key: m, value: v) in rows.entries) Text('$m: ${v.describe()}', style: t.bodySmall),
    ];
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: const Text('Planned work', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(report.totals.describe(), style: t.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Protocol groups: ${report.totals.completeGroups.round()} complete; ${report.totals.partialGroups.round()} partial or unverified',
            style: t.bodySmall,
          ),
          ...section('Direct involvement', report.direct),
          ...section('Indirect involvement', report.indirect),
          const SizedBox(height: 6),
          Text(
            'Warmups are separate. Protocol groups and segments are not conventional-set equivalents; indirect tags show involvement.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// A primary muscle's weekly sets with the draft, as a small pill under the exercise name ("Chest 14/wk").
/// The number takes the Cycle tab's colours; tapping opens that muscle's landmarks.
class _MuscleTotal extends StatelessWidget {
  final String muscle;
  final double sets;
  const _MuscleTotal({required this.muscle, required this.sets});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final br = context.style.brSmall;
    return Material(
      color: cs.onSurface.withValues(alpha: 0.06),
      borderRadius: br,
      child: InkWell(
        borderRadius: br,
        onTap: () => showLandmarkInfo(context, muscle),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$muscle ',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                TextSpan(
                  text: '${fmtSets(sets)}/wk',
                  style: TextStyle(
                    color: weeklySetsColor(cs, muscle, sets),
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
            style: t.labelMedium,
          ),
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final TemplateExercise exercise;
  final bool invalidName, restLocked, groupsLocked;
  final VoidCallback onChanged, onChoose, onDetails, onRemove, onAddGroup;
  final VoidCallback onCircuit;
  final String? circuitLabel;
  final ValueChanged<int> onMove;
  final ValueChanged<TemplateSet> onEditContext;

  /// Weekly sets per muscle with the draft, when Settings shows them on exercises; null otherwise.
  final Map<String, double>? weekly;

  const _ExerciseCard({
    super.key,
    required this.exercise,
    this.weekly,
    required this.invalidName,
    required this.restLocked,
    required this.groupsLocked,
    required this.onChanged,
    required this.onChoose,
    required this.onDetails,
    required this.onMove,
    required this.onRemove,
    required this.onAddGroup,
    required this.onCircuit,
    this.circuitLabel,
    required this.onEditContext,
  });

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final st = context.style;
    // Inputs one shade lighter than the set tile, as in the workout screen.
    final fieldFill = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(cs.surfaceContainerHigh, cs.onSurface, 0.07)
        : cs.surface;
    final e = exercise;
    final info = store.exercise(e.name);
    final loadMode = info?.loadMode ?? 'external';
    final weightKind = loadMode == 'external' ? NumKind.weight : NumKind.load;
    final grouped = isGroupedMethod(e.method);
    final note = info?.note.trim() ?? '';
    final stalled = e.name.isEmpty ? 0 : store.stalledSessions(e.name);

    final rows = <Widget>[];
    var group = 0;
    for (final (i, s) in e.sets.indexed) {
      final working = !isWarmup(s.type);
      if (grouped && working) {
        final canSplit = group > 0;
        if (group == 0 || s.groupStart) {
          group++;
          rows.add(
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text('Protocol group $group', style: t.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
            ),
          );
        }
        if (canSplit) {
          rows.add(
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: groupsLocked
                    ? null
                    : () {
                        s.groupStart = !s.groupStart;
                        e.reconcile();
                        onChanged();
                      },
                child: Text(s.groupStart ? 'Join preceding group' : 'Start group here'),
              ),
            ),
          );
        }
      }
      // Same set tiles as the workout screen: they join into one block at small set gaps.
      rows.add(
        Container(
          margin: EdgeInsets.symmetric(vertical: st.setGap / 2),
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: st.sp(4)),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: st.setTile(i, e.sets.length)),
          child: Row(
            children: [
              SizedBox(
                width: 84,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: compactButton,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  onPressed: () async {
                    final picked = await pickSetType(context, e.method, [
                      for (final x in e.sets) (x.type, x.groupStart),
                    ], i);
                    if (picked == null) return;
                    s.type = picked;
                    e.reconcile();
                    onChanged();
                  },
                  onLongPress: () => onEditContext(s),
                  child: Text(
                    displaySetType(s.type).replaceAll('Straight (Normal)', 'Straight'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 5,
                child: NumField(
                  value: s.weight,
                  kind: weightKind,
                  placeholder: loadSuffix(loadMode, store.settings.unit),
                  suffix: s.weight == null ? null : loadSuffix(loadMode, store.settings.unit),
                  fill: fieldFill,
                  onChanged: (v) => s.weight = v,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 4,
                child: NumField(
                  value: s.reps?.toDouble(),
                  kind: NumKind.reps,
                  placeholder: 'Reps',
                  fill: fieldFill,
                  onChanged: (v) => s.reps = v?.round(),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 4,
                child: DurationField(
                  seconds: s.rest,
                  readOnly: restLocked,
                  fill: fieldFill,
                  tooltip: restLocked ? 'Rest time is locked by the active mesocycle' : null,
                  onChanged: (v) {
                    s.rest = v;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ),
      );
      if (s.context != null) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: 88, bottom: 2),
            child: Text(s.context!.summary(), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        );
      }
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, st.sp(10), 8, st.sp(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: compactButton,
                      alignment: Alignment.centerLeft,
                      side: BorderSide(color: invalidName ? cs.error : cs.outlineVariant, width: invalidName ? 2.2 : 1),
                    ),
                    onPressed: onChoose,
                    child: Text(
                      e.name.isEmpty ? 'Choose exercise' : e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit exercise details',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onDetails,
                ),
                IconButton(
                  tooltip: 'Move up',
                  icon: const Icon(Icons.arrow_upward_rounded),
                  onPressed: () => onMove(-1),
                ),
                IconButton(
                  tooltip: 'Move down',
                  icon: const Icon(Icons.arrow_downward_rounded),
                  onPressed: () => onMove(1),
                ),
                IconButton(
                  tooltip: 'Remove exercise',
                  icon: Icon(Icons.remove_circle_outline_rounded, color: cs.onSurfaceVariant),
                  onPressed: onRemove,
                ),
              ],
            ),
            if (stalled >= stallSessions || (weekly != null && (info?.primary.isNotEmpty ?? false)))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (stalled >= stallSessions)
                      Material(
                        color: cs.warning.withValues(alpha: 0.14),
                        borderRadius: context.style.brSmall,
                        child: InkWell(
                          borderRadius: context.style.brSmall,
                          onTap: () => showStallInfo(context, e.name, stalled),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            child: Text('Stalled', style: t.labelMedium?.copyWith(color: cs.warning)),
                          ),
                        ),
                      ),
                    if (weekly != null)
                      for (final m in info?.primary ?? const <String>[]) _MuscleTotal(muscle: m, sets: weekly![m] ?? 0),
                  ],
                ),
              ),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  note,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Flexible(
                  child: ActionChip(
                    avatar: const Icon(Icons.tune_rounded, size: 16),
                    label: Text('Method: ${e.method}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: groupsLocked && grouped
                        ? null
                        : () async {
                            final m = await pickMethod(context, e.method);
                            if (m == null) return;
                            e.replan(method: m);
                            onChanged();
                          },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: circuitLabel == null ? 'Superset / circuit' : 'Edit group $circuitLabel',
                  icon: circuitLabel == null
                      ? const Icon(Icons.link_rounded)
                      : Text(circuitLabel!, style: t.labelMedium),
                  onPressed: onCircuit,
                ),
              ],
            ),
            ...rows,
            Row(
              children: [
                IconButton(
                  tooltip: 'Add set',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () {
                    final last = e.sets.isEmpty ? null : e.sets.last;
                    e.sets.add(
                      TemplateSet(
                        type: defaultNextSetType(e.method, e.types),
                        weight: last?.weight,
                        reps: last?.reps,
                        rest: last?.rest ?? store.settings.defaultRest,
                        context: last?.context,
                      ),
                    );
                    e.reconcile();
                    onChanged();
                  },
                ),
                IconButton(
                  tooltip: 'Remove last set',
                  icon: const Icon(Icons.remove_rounded),
                  onPressed: e.sets.length <= 1
                      ? null
                      : () {
                          e.sets.removeLast();
                          e.reconcile();
                          onChanged();
                        },
                ),
                if (grouped)
                  TextButton.icon(
                    onPressed: groupsLocked ? null : onAddGroup,
                    icon: const Icon(Icons.add_box_outlined, size: 18),
                    label: const Text('Add protocol group'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
