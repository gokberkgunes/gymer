part of '../session.dart';

/// SET · KG · REPS · RIR captions aligned with the set row columns.
class _ColumnHeader extends StatelessWidget {
  final SessionExercise exercise;
  final String unit;
  const _ColumnHeader({required this.exercise, required this.unit});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600);
    final e = exercise;
    final rir = (store.active?.visibleSetsFor(e) ?? e.sets).any(
      (s) =>
          methodSetUsesRir(e.method, s.type) &&
          (store.settings.trackRir || (e.calibrate && calibrationAnchor(e.method, s.type))),
    );
    final load = e.loadMode == 'external' ? unit.toUpperCase() : loadSuffix(e.loadMode, unit).toUpperCase();
    Widget cap(String text, int flex) => Expanded(
      flex: flex,
      child: Text(text, textAlign: TextAlign.center, style: style),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text('SET', textAlign: TextAlign.center, style: style),
          ),
          if (e.loadMode == 'external' && store.platesApply(e.name))
            // The load caption doubles as the plate calculator for the next unfinished set.
            Expanded(
              flex: 10,
              child: Tooltip(
                message: 'Plates',
                child: InkWell(
                  borderRadius: context.style.brSmall,
                  onTap: () => openPlatesFor(context, store, e),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(load, style: style),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.fitness_center_rounded,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            cap(load, 10),
          const SizedBox(width: 6),
          cap('REPS', 7),
          const SizedBox(width: 6),
          cap(rir ? 'RIR' : '', 7),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  final SessionExercise exercise;
  final int index;
  final int position;
  final int count;
  final _SessionScreenState screen;
  final bool showPlannedRest;
  final int plannedRest;
  final bool sharedRest;
  final String unit;

  const _SetRow({
    super.key,
    required this.exercise,
    required this.index,
    required this.position,
    required this.count,
    required this.screen,
    required this.showPlannedRest,
    required this.plannedRest,
    required this.sharedRest,
    required this.unit,
  });

  /// Robust "usual weight": own history, or two independent references.
  /// Prescribed loads never count as evidence of what the user lifts.
  double? _usualWeight(SessionExercise e, SetEntry s) {
    bool compatible(SetEntry o) =>
        isStraightType(s.type) ? isStraightType(o.type) : canonicalSetType(o.type) == canonicalSetType(s.type);
    final own = e.calibrate ? null : s.hintWeight;
    final refs = <double>[if (own != null && own > 0) own];
    for (final o in e.sets) {
      if (identical(o, s) || !compatible(o)) continue;
      if (o.hintWeight != null && o.hintWeight! > 0) refs.add(o.hintWeight!);
      if (o.weight != null && o.weight! > 0 && !o.prescribed) refs.add(o.weight!);
    }
    if ((own == null || own <= 0) && refs.length < 2) return null;
    return refs.isEmpty ? null : median(refs);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    final e = exercise;
    final s = e.sets[index];
    final warmup = store.active?.isWarmupExercise(e) ?? false;
    final f = screen.focusOf(s);
    final weightKind = e.loadMode == 'external' ? NumKind.weight : NumKind.load;
    final rirVisible =
        methodSetUsesRir(e.method, s.type) &&
        (store.settings.trackRir || (e.calibrate && calibrationAnchor(e.method, s.type)));
    final number = s.warmup ? 'W${position + 1}' : '${e.sets.take(index + 1).where((x) => !x.warmup).length}';

    String? warning(NumKind kind, num? v) => v == null
        ? null
        : unusualReason(kind, v.toDouble(), usualWeight: kind == NumKind.weight ? _usualWeight(e, s) : null);

    final weightWarn = e.loadMode == 'external' ? warning(NumKind.weight, s.weight) : null;
    final repsWarn = warning(NumKind.reps, s.reps);
    final rirWarn = rirVisible ? warning(NumKind.rir, s.rir) : null;

    final timer = store.rest;
    final nearSet =
        timer != null &&
        timer.exercise == e.name &&
        timer.setIndex == index &&
        timer.warmup == warmup &&
        store.settings.nearSetTimer;

    final record = store.recordKind(e, s);
    final increase = store.plannedLoadIncrease(e, index);
    final previous = warmup ? null : store.lastTimeSets(e.name, store.active?.templateId);
    // Match by position among sets of the same kind, so a different number of warm-ups last time never shifts the
    // working sets' "last time" values onto the wrong rows.
    SetEntry? prev;
    if (previous != null) {
      final position = e.sets.take(index).where((x) => x.warmup == s.warmup).length;
      final same = [
        for (final x in previous)
          if (x.warmup == s.warmup) x,
      ];
      if (position < same.length && same[position].done) prev = same[position];
    }
    final repsVisible = store.active == null || store.historicalRepsVisible(store.active!);
    final String? lastTime = prev == null || (prev.weight == null && prev.reps == null)
        ? null
        : [
            if (prev.weight != null) formatNumber(prev.weight!, weightKind),
            if (repsVisible && prev.reps != null) '${prev.weight == null ? '' : '×'}${prev.reps}',
          ].join();

    // Rest sits under the set number so every row keeps the same columns.
    const restStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFeatures: tabular);
    final Widget? restLabel = nearSet
        ? TickBuilder(
            anchor: timer.startedAt,
            builder: (_) => Tooltip(
              message: timer.overdue ? 'Rest complete' : 'Rest remaining',
              child: Text(signedRest(timer.remainingSeconds), style: restStyle),
            ),
          )
        : showPlannedRest && plannedRest > 0
        ? Text(formatDuration(plannedRest), style: restStyle.copyWith(color: cs.onSurfaceVariant))
        : null;

    // The warm-up texture belongs to the exercise card. Set tiles stay solid and ordinary.
    final tileColor = s.done
        ? s.warmup
              ? Color.alphaBlend(cs.primary.withValues(alpha: 0.12), cs.surface)
              : cs.primary.withValues(alpha: 0.12)
        : cs.surfaceContainerHigh;
    final fieldFill = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(cs.surfaceContainerHigh, cs.onSurface, 0.07)
        : cs.surface;

    final typeButton = Tooltip(
      message: warmup
          ? 'Warm-up $number. Hold for set details.'
          : '${s.type} — Set $number. Tap to change set role; hold for set details.',
      child: InkWell(
        borderRadius: st.brSmall,
        onTap: warmup ? null : () => _pickType(context, store),
        onLongPress: () => showSetDetails(
          context,
          store,
          s,
          restLocked: warmup ? false : store.active?.restLocked ?? false,
          linkedRest: s.done && s.circuitRestAfter != null ? s.circuitRestAfter : (sharedRest ? plannedRest : null),
        ),
        child: SizedBox(
          width: 56,
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Plain straight sets and warmups ("W") need no role label.
              if (!isStraightType(s.type) && !s.warmup)
                Text(
                  activeSetTypeLabel(s.type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: cs.primary, fontWeight: FontWeight.w600),
                ),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (record != null)
                    Positioned(
                      right: 2,
                      child: Tooltip(
                        message: record == 'weight' ? 'Heaviest weight so far' : 'Best estimated 1RM so far',
                        child: Icon(Icons.emoji_events_outlined, size: 14, color: cs.primary),
                      ),
                    ),
                ],
              ),
              if (restLabel != null)
                restLabel
              else if (lastTime != null)
                Text(
                  lastTime,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant, fontFeatures: tabular),
                ),
            ],
          ),
        ),
      ),
    );

    final row = Row(
      children: [
        typeButton,
        Expanded(
          flex: 10,
          child: NumField(
            value: s.weight,
            kind: weightKind,
            placeholder: s.hintWeight != null ? formatNumber(s.hintWeight!, weightKind) : null,
            completed: s.done,
            fill: fieldFill,
            align: TextAlign.center,
            invalid: s.invalid.contains('weight'),
            warning: weightWarn,
            cornerIcon: increase == null ? null : Icons.north_east_rounded,
            tooltip: [
              if (increase != null)
                '${formatNumber(increase.load, weightKind)} ${store.active?.unit ?? store.settings.unit} planned · last time ${formatNumber(increase.previous, weightKind)} (+${formatNumber(increase.increase, weightKind)})',
              loadGuidance(e.loadMode),
            ].join('\n'),
            focusNode: f.weight,
            onChanged: (v) {
              s
                ..weight = v
                ..prescribed = false
                ..invalid.remove('weight');
              store.changed();
            },
            onBadText: (bad) => bad ? s.badText.add('weight') : s.badText.remove('weight'),
            onSubmitted: () => screen.submit(store, e, index, 'weight'),
            onBackspaceEmpty: () => screen.backspace(store, e, index, 'weight'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 7,
          child: NumField(
            value: s.reps?.toDouble(),
            kind: NumKind.reps,
            placeholder: s.hintReps?.toString(),
            completed: s.done,
            fill: fieldFill,
            align: TextAlign.center,
            invalid: s.invalid.contains('reps'),
            warning: repsWarn,
            tooltip: s.targetReps == null
                ? null
                : (store.active?.phase == 'Deload'
                      ? 'Recovery goal: ${s.targetReps} reps at ${s.targetRir} RIR. Record actual reps.'
                      : 'Next goal: ${s.targetReps} reps at target ${s.targetRir} RIR. Record actual reps.'),
            focusNode: f.reps,
            onChanged: (v) {
              s
                ..reps = v?.round()
                ..invalid.remove('reps');
              store.changed();
            },
            onBadText: (bad) => bad ? s.badText.add('reps') : s.badText.remove('reps'),
            onSubmitted: () => screen.submit(store, e, index, 'reps'),
            onBackspaceEmpty: () => screen.backspace(store, e, index, 'reps'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 7,
          child: rirVisible
              ? NumField(
                  value: s.rir?.toDouble(),
                  kind: NumKind.rir,
                  completed: s.done,
                  fill: fieldFill,
                  align: TextAlign.center,
                  invalid: s.invalid.contains('rir'),
                  warning: rirWarn,
                  tooltip: s.targetRir != null
                      ? 'Actual reps left; target ${s.targetRir} RIR. Leave blank if unknown.'
                      : 'Actual reps left. Leave blank if unknown.',
                  focusNode: f.rir,
                  onChanged: (v) {
                    s
                      ..rir = v?.round()
                      ..invalid.remove('rir');
                    store.changed();
                  },
                  onBadText: (bad) => bad ? s.badText.add('rir') : s.badText.remove('rir'),
                  onSubmitted: () => screen.submit(store, e, index, 'rir'),
                  onBackspaceEmpty: () => screen.backspace(store, e, index, 'rir'),
                )
              : const SizedBox.shrink(),
        ),
        Semantics(
          button: true,
          checked: s.done,
          label: '${e.name}, set $number, ${s.done ? 'completed' : 'not completed'}',
          child: InkWell(
            borderRadius: st.brSmall,
            onTap: () {
              FocusScope.of(context).unfocus();
              screen.complete(store, e, index);
            },
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: s.done ? cs.primary : null,
                  border: Border.all(color: s.done ? cs.primary : cs.outline, width: 2),
                  // Rounded square like the other buttons; no circles (see CLAUDE.md).
                  borderRadius: BorderRadius.circular(st.small.clamp(0, 10)),
                ),
                child: s.done ? Icon(Icons.check_rounded, size: 20, color: cs.onPrimary) : null,
              ),
            ),
          ),
        ),
      ],
    );

    // Unusual values only turn orange (reason on long press); no text line under the row,
    // so a set never changes height.
    // Each set is its own tile (as in the Appearance preview) so the set gap reads clearly.
    final content = Container(
      decoration: BoxDecoration(color: tileColor, borderRadius: st.setTile(position, count)),
      child: RecordEffect(
        active: record != null,
        enabled: store.settings.recordEffects,
        edition: editionNamed(store.settings.recordEffectStyle),
        outline: !st.joinSets,
        borderRadius: st.setTile(position, count),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: st.sp(2)),
          child: Opacity(
            opacity: s.done && st.dimCompleted ? 0.55 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row,
                if (e.notesVisible)
                  Padding(
                    padding: const EdgeInsets.only(left: 52, top: 4),
                    child: _NoteField(set: s),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Dismissible(
      key: ObjectKey(s),
      // Logged work is never one stray swipe away from deletion; completed sets are removed with the − button.
      direction: s.done ? DismissDirection.none : DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.25},
      background: Container(
        decoration: BoxDecoration(color: cs.error, borderRadius: st.setTile(position, count)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(Icons.delete_rounded, color: cs.onError),
      ),
      onDismissed: (_) => removeSetWithUndo(context, store, e, s),
      child: content,
    );
  }

  Future<void> _pickType(BuildContext context, AppStore store) async {
    final e = exercise;
    final picked = await pickSetType(context, e.method, [for (final s in e.sets) (s.type, s.groupStart)], index);
    if (picked != null) store.changeSetType(e, e.sets[index], picked);
  }
}

/// Set-role choices valid for this row of the method.
Future<String?> pickSetType(BuildContext context, String method, List<(String, bool)> rows, int index) {
  final choices = setTypeChoices(method, rows, index);
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Set role', style: Theme.of(sheet).textTheme.titleLarge),
          ),
          for (final c in choices)
            ListTile(
              title: Text(displaySetType(c)),
              trailing: canonicalSetType(rows[index].$1) == c
                  ? Icon(Icons.check_rounded, color: Theme.of(sheet).colorScheme.primary)
                  : null,
              onTap: () => Navigator.pop(sheet, c),
            ),
        ],
      ),
    ),
  );
}

class _NoteField extends StatefulWidget {
  final SetEntry set;
  const _NoteField({required this.set});

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final _c = TextEditingController(text: widget.set.note);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    textCapitalization: TextCapitalization.sentences,
    decoration: const InputDecoration(hintText: 'Note'),
    onChanged: (v) {
      widget.set.note = v;
      StoreScope.read(context).changed();
    },
  );
}

/// Long-press set details: logging context, stop reason, planned and actual
/// rest. Labels never convert load or reps.
Future<void> showSetDetails(
  BuildContext context,
  AppStore store,
  SetEntry s, {
  bool restLocked = false,
  bool historical = false,
  int? linkedRest,
}) async {
  final setup = TextEditingController(text: s.context.setup);
  // Imported or older data may hold a value the pickers do not offer; show it as unset instead of asserting.
  String known(String value, Map<String, String> options) => options.containsKey(value) ? value : '';
  var load = known(s.context.loadBasis, SetContext.loadBasisLabels),
      reps = known(s.context.repBasis, SetContext.repBasisLabels),
      side = known(s.context.side, SetContext.sideLabels),
      stop = known(s.stopReason, stopReasons);
  var rest = linkedRest ?? s.rest;
  final actual = TextEditingController(text: s.actualRest?.toString() ?? '');
  Widget dropdown(String label, String value, Map<String, String> options, ValueChanged<String> onChanged) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final o in options.entries)
            DropdownMenuItem(
              value: o.key,
              child: Text(o.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => onChanged(v ?? ''),
      );
  final saved = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Set details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: setup,
              decoration: const InputDecoration(
                labelText: 'Setup / variation',
                hintText: 'Machine, handle, position or leverage variant',
              ),
            ),
            const SizedBox(height: 10),
            dropdown('Load basis', load, SetContext.loadBasisLabels, (v) => load = v),
            const SizedBox(height: 10),
            dropdown('Rep count basis', reps, SetContext.repBasisLabels, (v) => reps = v),
            const SizedBox(height: 10),
            dropdown('Side', side, SetContext.sideLabels, (v) => side = v),
            const SizedBox(height: 8),
            Text(
              'These labels do not convert load or reps. Correct the recorded numbers separately if their meaning was wrong.',
              style: Theme.of(c).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            dropdown('Observed stop reason', stop, stopReasons, (v) => stop = v),
            const SizedBox(height: 10),
            DurationField(
              seconds: rest,
              label: linkedRest == null ? 'Planned rest after segment' : 'Linked rest after segment',
              readOnly: linkedRest != null || (restLocked && !historical),
              tooltip: linkedRest == null ? null : 'Shared rest is set for the whole superset or circuit',
              onChanged: (v) => rest = v,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: actual,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Actual rest after segment (seconds)',
                hintText: 'Leave blank if unknown',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Actual rest is your reported rest after this segment, not the timer setting. Unknown records remain blank.',
              style: Theme.of(c).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save details')),
      ],
    ),
  );
  if (saved == true) {
    s
      ..context = SetContext(setup: setup.text.trim(), loadBasis: load, repBasis: reps, side: side)
      ..stopReason = stop
      ..rest = linkedRest == null ? rest : s.rest
      ..actualRest = int.tryParse(actual.text.trim());
    store.changed();
  }
  // The dialog is still animating out; release the controllers once it is gone.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    setup.dispose();
    actual.dispose();
  });
}

class _CalibrationCard extends StatelessWidget {
  final SessionExercise exercise;
  final int index;
  final bool compact;
  const _CalibrationCard({required this.exercise, required this.index, required this.compact});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final e = exercise;
    final cal = store.calibrationFor(e.name, e.method, store.active!);
    final unit = store.active!.unit;
    final entered = !e.calibrate && e.calibrationEntered;
    final hint = entered
        ? 'save the workout to keep it'
        : cal != null
        ? 'start ~${formatNumber(cal.weight, NumKind.weight)} $unit'
        : 'set a baseline';
    final color = entered ? cs.onSurfaceVariant : cs.primary;
    // A small pill beside the exercise name; the dialog carries the explanation.
    return Tooltip(
      message: entered ? 'Calibrated · $hint' : 'Calibrate · $hint',
      child: Material(
        color: color.withValues(alpha: 0.14),
        borderRadius: context.style.brSmall,
        child: InkWell(
          borderRadius: context.style.brSmall,
          onTap: entered ? null : () => _calibrate(context, store, cal),
          child: SizedBox(
            width: compact ? 28 : 96,
            height: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(entered ? Icons.check_rounded : Icons.tune_rounded, size: 16, color: color),
                if (!compact) ...[
                  const SizedBox(width: 4),
                  Text(
                    entered ? 'Calibrated' : 'Calibrate',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _calibrate(BuildContext context, AppStore store, Calibration? cal) async {
    final e = exercise;
    final unit = store.active!.unit;
    final copy = switch (e.method) {
      'Straight' =>
        'Record one honest straight set. Gymer uses weight, reps, and RIR to establish the mesocycle baseline.',
      'Cluster' =>
        'Record the first cluster segment. Cluster rest periods make normal rep-max conversion inappropriate, so method-specific history is used instead of pretending a cluster set is an RM test.',
      'AMRAP' => "Record the AMRAP set and actual RIR if known. The method's name does not prove muscular failure.",
      _ =>
        'Record the ${e.method} activation set. The activation set is the strength anchor; later fatigued segments do not become independent rep-max tests.',
    };
    final usesRir = cal?.usesRir ?? e.method != 'Cluster';
    var weight = cal?.weight;
    int? reps;
    int? rir;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Mesocycle calibration · ${e.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Establish this exercise for the new mesocycle',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(copy),
              const SizedBox(height: 10),
              Text(
                cal == null
                    ? 'There is not enough compatible history to estimate a starting weight. Pick a sensible load and use this set to establish one.'
                    : 'Suggested starting weight: ${formatNumber(cal.weight, NumKind.weight)} $unit for about ${cal.targetReps} reps'
                          '${cal.usesRir && cal.targetRir != null ? ' @ ${cal.targetRir} RIR' : ''}.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: NumField(
                      value: weight,
                      kind: NumKind.weight,
                      placeholder: 'Weight',
                      suffix: unit,
                      onChanged: (v) => weight = v,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: NumField(
                      value: null,
                      kind: NumKind.reps,
                      placeholder: 'Reps',
                      onChanged: (v) => reps = v?.round(),
                    ),
                  ),
                  if (usesRir) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: NumField(
                        value: null,
                        kind: NumKind.rir,
                        placeholder: 'RIR',
                        onChanged: (v) => rir = v?.round(),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'The load hint aims for about ${cal?.targetReps ?? calibrationTargetReps} reps. Record what you actually achieve; '
                'calibration is not rejected if you land outside the planned rep range.',
                style: Theme.of(c).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Skip')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Use calibration set')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final w = weight, r = reps;
    if (w == null || r == null || (usesRir && rir == null)) {
      return notify(context, 'Enter weight, reps${usesRir ? ' and RIR' : ''} for the calibration set.');
    }
    store.applyCalibration(e, index, w, r, rir);
  }
}

/// Removes a set and offers a few seconds to put it back.
void removeSetWithUndo(BuildContext context, AppStore store, SessionExercise e, SetEntry set) {
  final index = e.sets.indexOf(set);
  if (index < 0) return;
  store.removeSet(e, set);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Set removed from ${e.name}'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.restoreSet(e, index, set)),
      ),
    );
}
