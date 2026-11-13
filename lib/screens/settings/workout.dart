part of '../settings.dart';

class _WorkoutSettings extends StatelessWidget {
  const _WorkoutSettings();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    return _Page(
      title: 'Workout',
      children: [
        const SectionLabel('Workout defaults'),
        _group([
          _row(
            context,
            'Units',
            _segmented(s.unit, const {'kg': 'kg', 'lb': 'lb'}, (v) => store.updateSettings((x) => x.unit = v)),
            subtitle: 'Converts plans; past workouts keep their recorded unit',
          ),
          _row(
            context,
            'Default number of sets',
            SizedBox(
              width: 80,
              child: NumField(
                value: s.defaultSets.toDouble(),
                kind: NumKind.count,
                align: TextAlign.center,
                onChanged: (v) {
                  if (v != null) store.updateSettings((x) => x.defaultSets = v.round());
                },
              ),
            ),
          ),
          _stackedChoice(
            context,
            'Warm-up ramp',
            s.warmupSets,
            const {2: '2 sets', 3: '3 sets'},
            (v) => store.updateSettings((x) => x.warmupSets = v),
            info: InfoDot(
              tooltip: 'How warm-ups work',
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Warm-up ramp'),
                  content: const Text(
                    'Tap Warm up beside an exercise name. Loads come from your working weight: '
                    '40 / 80% for two sets, or 40 / 60 / 80% for three, with fewer reps as the load increases. '
                    'Available plates and increments can reduce the number of distinct steps. '
                    'Only that exercise switches to warm-ups; its working sets return when the ramp is done.',
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Got it'))],
                ),
              ),
            ),
          ),
        ]),
        const SectionLabel('Workout tracking'),
        _group([
          Column(
            children: [
              _switch(context, 'Track bodyweight', s.trackBodyweight, (x, v) => x.trackBodyweight = v),
              if (s.trackBodyweight)
                _row(
                  context,
                  'Bodyweight log',
                  Text(
                    store.bodyweights.isEmpty
                        ? 'Open'
                        : '${formatNumber(store.bodyweights.last.inUnit(s.unit), NumKind.weight)} ${s.unit}',
                  ),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BodyweightScreen())),
                ),
            ],
          ),
          _row(
            context,
            'Track RIR',
            Switch(value: s.trackRir, onChanged: (v) => store.updateSettings((x) => x.trackRir = v)),
            info: InfoDot(tooltip: 'What is RIR?', onTap: () => showRirInfo(context)),
          ),
          _switch(
            context,
            'Dim completed sets',
            s.dimCompleted,
            (x, v) => x.dimCompleted = v,
            subtitle: 'Grey tint on completed sets',
          ),
          _switch(
            context,
            'Collapse completed exercises',
            s.collapseCompleted,
            (x, v) => x.collapseCompleted = v,
            subtitle: 'Fold an exercise once its sets are done',
          ),
        ]),
        const SectionLabel('Workout editor'),
        _group([
          _switch(
            context,
            'Weekly sets button',
            s.editorWeeklySets,
            (x, v) => x.editorWeeklySets = v,
            subtitle: 'A chart button in the editor shows weekly sets per muscle',
          ),
          _switch(
            context,
            'Weekly sets on exercises',
            s.editorMuscleTotals,
            (x, v) => x.editorMuscleTotals = v,
            subtitle: 'Each exercise shows its muscles’ weekly sets',
          ),
        ]),
        const SectionLabel('Customisation'),
        _group([
          _row(
            context,
            'Exercise shortcuts',
            Text(
              '${exerciseActions.where((action) => s.pinnedExerciseActions.contains(action.$1)).length} pinned',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            subtitle: 'Quick access beside the exercise menu',
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _ExerciseShortcutSettings())),
          ),
        ]),
      ],
    );
  }
}

class _ExerciseShortcutSettings extends StatelessWidget {
  const _ExerciseShortcutSettings();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final pinned = exerciseActions.where((action) => store.settings.pinnedExerciseActions.contains(action.$1)).toList();

    void toggle(String key) => store.updateSettings((settings) {
      final selected = !settings.pinnedExerciseActions.contains(key);
      settings.pinnedExerciseActions = [
        for (final action in exerciseActions)
          if (action.$1 == key ? selected : settings.pinnedExerciseActions.contains(action.$1)) action.$1,
      ];
    });

    return _Page(
      title: 'Exercise shortcuts',
      children: [
        const SectionLabel('Preview'),
        // Desaturate and warm the sample so it reads as a preview, not another setting.
        ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.218,
            0.735,
            0.074,
            0,
            0,
            0.209,
            0.702,
            0.071,
            0,
            0,
            0.191,
            0.642,
            0.065,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: Opacity(
            opacity: 0.72,
            child: IgnorePointer(
              child: _SetPreview(
                header: ExerciseActionHeader(
                  title: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bench Press', style: t.titleMedium?.copyWith(fontSize: 18)),
                        Text('Chest · Triceps', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  actions: [
                    for (final (_, label, icon) in pinned)
                      Tooltip(
                        message: label,
                        child: Center(child: Icon(icon, color: cs.onSurfaceVariant)),
                      ),
                  ],
                  menu: Center(child: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant)),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text('Tap an action to pin or unpin it.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        const SectionLabel('Actions'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (index, (key, label, icon)) in exerciseActions.indexed) ...[
                if (index > 0) const Divider(indent: 52, endIndent: 16),
                _ExerciseShortcutRow(
                  label: label,
                  icon: icon,
                  pinned: store.settings.pinnedExerciseActions.contains(key),
                  onTap: () => toggle(key),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ExerciseShortcutRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool pinned;
  final VoidCallback onTap;

  const _ExerciseShortcutRow({required this.label, required this.icon, required this.pinned, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      toggled: pinned,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: context.style.sp(8)),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: pinned ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
                  borderRadius: context.style.brSmall,
                ),
                child: Icon(
                  pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  size: 18,
                  color: pinned ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressionSettings extends StatelessWidget {
  const _ProgressionSettings();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final t = Theme.of(context).textTheme;
    final lb = s.unit == 'lb';
    return _Page(
      title: 'Progression',
      children: [
        const SectionLabel('Progression weight increments'),
        Text(
          'These are the default smallest available jumps. Each exercise can override its own increment in Exercise '
          'Database → Details.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 8),
        _group([
          for (final eq in equipmentTypes)
            _row(
              context,
              eq,
              SizedBox(
                width: 100,
                child: NumField(
                  value: lb ? s.increments[eq]?.$2 : s.increments[eq]?.$1,
                  kind: NumKind.weight,
                  suffix: s.unit,
                  align: TextAlign.center,
                  onChanged: (v) {
                    if (v == null) return;
                    store.updateSettings((x) {
                      final old = x.increments[eq] ?? defaultIncrements[eq]!;
                      x.increments[eq] = lb ? (old.$1, v) : (v, old.$2);
                    });
                  },
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Text(
          '${lb ? 'Barbell default: 10 lb total (+5/+5). ' : 'Barbell default: 5 kg total (+2.5/+2.5). '}'
          'Dumbbell is per dumbbell; Plate loaded is total logged load; Weight-stack machine uses the displayed stack value.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => store.updateSettings((x) => x.increments = Map.of(defaultIncrements)),
          child: const Text('Reset weight increments'),
        ),
      ],
    );
  }
}

class _AdvancedSettings extends StatelessWidget {
  const _AdvancedSettings();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    return _Page(
      title: 'Advanced',
      children: [
        const SectionLabel('Weekly sets'),
        _group([
          _row(
            context,
            'Include partial sets',
            Switch(
              value: s.includePartialSets,
              onChanged: (v) => store.updateSettings((x) => x.includePartialSets = v),
            ),
            info: InfoDot(
              tooltip: 'How partial sets count',
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Include partial sets'),
                  content: const Text(
                    'Primary muscles count as one set. With this on, secondary muscles also receive half a set. '
                    'Turn it off to count direct work only. This applies to the Coach tab and workout editor. '
                    'Warm-ups never count, and special set methods are estimated in straight-set equivalents. This does not '
                    'refer to partial-range reps.',
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
                ),
              ),
            ),
          ),
        ]),
        const SectionLabel('Coach'),
        _group([
          _stackedChoice(
            context,
            'Compare progress by',
            s.coachCompare,
            const {'strength': 'Estimated 1RM', 'volume': 'Total volume'},
            (v) => store.updateSettings((x) => x.coachCompare = v),
            info: InfoDot(
              tooltip: 'Which to choose',
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Compare progress by'),
                  content: const SingleChildScrollView(
                    child: Text(
                      'This decides how the Coach tab judges straight sets from one week to the next.\n\n'
                      'Estimated 1RM turns load, reps and reps in reserve into one strength number. It stays fair '
                      'when a mesocycle moves closer to failure each week, and when you trade reps for load. It '
                      'depends on honest RIR and is less reliable above about 12 reps.\n\n'
                      'Total volume is load × reps, set by set. It needs no RIR, so it suits you if you do not '
                      'track RIR or train in high rep ranges. It cannot tell real progress from simply pushing '
                      'closer to failure, and a heavier load for fewer reps can read as a drop.\n\n'
                      'Drop sets, myo-reps, rest-pause, clusters and other special methods are always compared by '
                      'total volume, because a rep-max estimate does not hold across their segments.',
                    ),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
                ),
              ),
            ),
          ),
          _row(
            context,
            'Keep sets at MEV or above',
            Switch(value: s.coachKeepMev, onChanged: (v) => store.updateSettings((x) => x.coachKeepMev = v)),
            info: InfoDot(
              tooltip: 'What this limits',
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Keep sets at MEV or above'),
                  content: const Text(
                    'MEV is the minimum effective volume: below it a muscle is unlikely to grow. With this on, the '
                    'coach never suggests removing a set that would take a muscle under its MEV, even when it is '
                    'falling. Turn it off to let removals continue down to MV, the maintenance volume, for example '
                    'while deliberately holding a muscle back.',
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
                ),
              ),
            ),
          ),
          _row(
            context,
            'Recovery check-in',
            Switch(value: s.coachCheckIn, onChanged: (v) => store.updateSettings((x) => x.coachCheckIn = v)),
            info: InfoDot(
              tooltip: 'What is asked',
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Recovery check-in'),
                  content: const Text(
                    'With this on, the summary after a workout asks two things per trained muscle (pump, and whether '
                    'it had recovered from last time) and two about the day (sleep and overall state). Every answer '
                    'is optional. The coach treats soreness as fatigue, adds a set sooner after a low pump with '
                    'early recovery, and adds nothing after a run-down week. Nothing is ever asked during a workout.',
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
                ),
              ),
            ),
          ),
        ]),
        const SectionLabel('Timers'),
        _group([
          _row(
            context,
            'Workout timing',
            const Text('View'),
            subtitle: 'Estimates and actual durations',
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _WorkoutTimingSettings())),
          ),
        ]),
        const SectionLabel('Workout'),
        _group([
          _switch(
            context,
            'Require previous set',
            s.requirePreviousSet,
            (x, v) => x.requirePreviousSet = v,
            subtitle:
                'When on, a set can only be completed after earlier sets of that exercise are complete. '
                'In supersets and circuits, rounds follow the linked order.',
          ),
          _switch(
            context,
            'Update following set defaults',
            s.updateFollowingDefaults,
            (x, v) => x.updateFollowingDefaults = v,
            subtitle: 'When on, completing a set refreshes untouched later-set defaults.',
          ),
          _switch(
            context,
            'Keep screen awake',
            s.keepAwake,
            (x, v) => x.keepAwake = v,
            subtitle: 'Stops the screen from turning off while a workout is active.',
          ),
          _switch(
            context,
            'Haptic on set complete',
            s.haptics,
            (x, v) => x.haptics = v,
            subtitle: 'A light tap when you complete a set.',
          ),
          _switch(
            context,
            'Show previous reps in mesocycles',
            s.showPreviousReps,
            (x, v) => x.showPreviousReps = v,
            subtitle:
                'Off by default. When enabled, historical rep counts may appear as workout placeholders during a mesocycle.',
          ),
        ]),
        const SectionLabel('Set keyboard navigation'),
        _group([
          _switch(
            context,
            'Enter completes set',
            s.enterCompletesSet,
            (x, v) => x.enterCompletesSet = v,
            subtitle: 'Enter on the last editable box completes the set.',
          ),
          _switch(context, 'Enter moves to next set', s.enterMovesToNextSet, (x, v) => x.enterMovesToNextSet = v),
          _switch(
            context,
            'Enter closes keyboard',
            s.enterClosesKeyboard,
            (x, v) => x.enterClosesKeyboard = v,
            subtitle: 'Enter on the last box of a set hides the keyboard, unless it moves to the next set.',
          ),
          _switch(
            context,
            'Backspace moves to previous set',
            s.backspaceMovesToPreviousSet,
            (x, v) => x.backspaceMovesToPreviousSet = v,
          ),
        ]),
      ],
    );
  }
}

class _DatabaseSettings extends StatelessWidget {
  const _DatabaseSettings();

  @override
  Widget build(BuildContext context) {
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return _Page(
      title: 'Databases',
      children: [
        const SizedBox(height: 8),
        _group([
          ListTile(
            title: const Text('Exercise database'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(const ExercisesScreen()),
          ),
          ListTile(
            title: const Text('Rep max table'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(const RepMaxScreen()),
          ),
          ListTile(
            title: const Text('Set type database'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(const SetTypesScreen()),
          ),
        ]),
      ],
    );
  }
}

void showRirInfo(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Using RIR'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (title, body) in const [
              (
                'Rate the set after you finish it',
                'RIR is how many clean reps you believe you still had left. If you could have done about three more '
                    'reps, log 3 RIR. If only one good rep remained, log 1 RIR.',
              ),
              (
                'Use it to judge whether the load was right',
                'If your target was 2 RIR but the set felt like 4 RIR, the load was probably conservative. If it felt '
                    'like 0 RIR, it was harder than planned. Use that difference to guide the next session rather than '
                    'chasing a number during the set itself.',
              ),
              (
                'Use higher RIR when you want more margin',
                'Around 3 RIR is useful when you want productive work without pushing close to failure. Around 1 RIR '
                    'is a much harder set. Keep technique consistent and stop the set if form breaks down, regardless '
                    'of the target.',
              ),
              (
                'Look for trends',
                'The most useful signal is repeated performance. If the same weight and reps begin to feel easier over '
                    'time, that is a good reason to progress the load or reps.',
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
