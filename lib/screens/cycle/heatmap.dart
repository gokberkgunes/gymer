part of '../cycle.dart';

/// Training heatmap: green as planned, blue on another day, red missed.
class CycleHeatmap extends StatelessWidget {
  final Mesocycle cycle;
  final bool compact;
  const CycleHeatmap({super.key, required this.cycle, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final days = calendarDays(cycle, store.history);
    final perRow = math.max(1, cycle.microDays);
    const weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

    Widget tile(CycleDay d, double cell) {
      final today = dateKey(d.date) == dateKey(DateTime.now());
      final planned = d.templateId != null || d.incoming.isNotEmpty;
      final Color fill = switch (d.status) {
        'missed' => cs.error,
        _ when d.offPlan => cs.info,
        'done' => cs.success,
        _ => cs.onSurface.withValues(alpha: 0.12),
      };
      final strong = d.status == 'missed' || d.status == 'done' || d.offPlan;
      final border = today
          ? cs.onSurface
          : (planned && d.sessions.isEmpty ? cs.primary : cs.onSurface.withValues(alpha: 0.28));
      final label = const {
        'done': 'Completed',
        'moved_done': 'Completed on another day',
        'missed': 'Missed',
        'moved': 'Moved',
        'planned': 'Planned',
        'rest': 'Rest',
      }[d.status];
      return Tooltip(
        message:
            '${fmtRecent(d.date, includeTime: false)} · ${store.template(d.templateId)?.name ?? 'Rest'} · $label'
            '${d.offPlan && d.status != 'moved_done' ? ' · Workout completed off schedule' : ''}',
        child: InkWell(
          onTap: () => _dayActions(context, store, d),
          child: Container(
            width: cell,
            height: cell,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: border, width: today ? 2.5 : 1),
            ),
            child: planned || d.sessions.isNotEmpty
                ? Text(
                    '${d.dayInMicro}',
                    style: TextStyle(
                      fontSize: compact ? 9 : 9.5,
                      fontWeight: today ? FontWeight.bold : FontWeight.w500,
                      color: strong ? Colors.white : null,
                    ),
                  )
                : null,
          ),
        ),
      );
    }

    List<Widget> rows(double cell) => <Widget>[
      Row(
        children: [
          const SizedBox(width: 28),
          for (final d in days.take(perRow))
            Container(
              width: cell + 4,
              alignment: Alignment.center,
              child: Text(
                weekdays[d.date.weekday - 1],
                style: t.labelSmall?.copyWith(fontSize: compact ? 9.5 : 10, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      for (var r = 0; r * perRow < days.length; r++)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${cycle.periodShort}${r + 1}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              for (final d in days.skip(r * perRow).take(perRow))
                Padding(padding: const EdgeInsets.only(right: 4), child: tile(d, cell)),
            ],
          ),
        ),
      if (!compact)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Green: as planned  ·  Blue: another day  ·  Red: missed', style: t.bodySmall),
        ),
    ];
    Widget grid(double cell) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows(cell));
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 12),
        // The squares share the card's width (up to a comfortable size) instead of leaving a gap on the right.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fit = (constraints.maxWidth - 28) / perRow - 4;
            final cell = fit.clamp(compact ? 12.0 : 10.0, 44.0);
            return SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid(cell));
          },
        ),
      ),
    );
  }

  Future<void> _dayActions(BuildContext context, AppStore store, CycleDay d) async {
    final key = dateKey(d.date);
    final todayKey = dateKey(DateTime.now());
    final isToday = key == todayKey;
    final name = store.template(d.templateId)?.name;
    final event = cycle.events[key];
    final running = store.activeCycle?.id == cycle.id;
    final canLog =
        d.sessionId == null &&
        (key.compareTo(todayKey) <= 0 || (d.movedTo != null && dateKey(d.movedTo!).compareTo(todayKey) <= 0));
    final details = <String>[
      name ?? 'Rest',
      switch (d.status) {
        'missed' => 'Missed',
        'moved' => 'Moved to ${fmtRecent(d.movedTo!, includeTime: false)}',
        'moved_done' => 'Completed off schedule',
        'done' => 'Completed as planned',
        _ => '',
      },
      for (final (from, id) in d.incoming)
        '${store.template(id)?.name ?? 'Workout'} · moved from ${fmtRecent(from, includeTime: false)}',
    ].where((x) => x.isNotEmpty).toList();

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmtRecent(d.date, includeTime: false), style: Theme.of(sheet).textTheme.titleLarge),
                    for (final line in details) Text(line),
                  ],
                ),
              ),
              if (d.sessionId != null)
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('Edit recorded workout'),
                  onTap: () => Navigator.pop(sheet, 'session:${d.sessionId}'),
                ),
              for (final s in d.sessions.where((s) => s.id != d.sessionId))
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: Text('Edit ${s.name}'),
                  onTap: () => Navigator.pop(sheet, 'session:${s.id}'),
                ),
              if (d.templateId != null && d.sessionId == null && !d.unplanned) ...[
                if (d.status == 'planned' && isToday && running)
                  ListTile(
                    leading: const Icon(Icons.play_arrow_rounded),
                    title: const Text('Start workout'),
                    onTap: () => Navigator.pop(sheet, 'start:${d.templateId}'),
                  ),
                ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: const Text('Move'),
                  onTap: () => Navigator.pop(sheet, 'move'),
                ),
                ListTile(
                  leading: const Icon(Icons.event_busy_outlined),
                  title: const Text('Mark missed'),
                  onTap: () => Navigator.pop(sheet, 'missed'),
                ),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('Link recorded workout'),
                  onTap: () => Navigator.pop(sheet, 'link'),
                ),
                if (d.status == 'moved' || d.status == 'missed')
                  ListTile(
                    leading: const Icon(Icons.undo_rounded),
                    title: const Text('Undo change'),
                    onTap: () => Navigator.pop(sheet, 'undo'),
                  ),
              ],
              if (canLog)
                ListTile(
                  leading: const Icon(Icons.post_add_rounded),
                  title: const Text('Log past workout'),
                  onTap: () => Navigator.pop(sheet, 'log'),
                ),
              for (final (from, id) in d.incoming) ...[
                if (isToday && running)
                  ListTile(
                    leading: const Icon(Icons.play_arrow_rounded),
                    title: Text('Start ${store.template(id)?.name ?? 'workout'}'),
                    onTap: () => Navigator.pop(sheet, 'start:$id'),
                  ),
                if (key.compareTo(todayKey) <= 0)
                  ListTile(
                    leading: const Icon(Icons.post_add_rounded),
                    title: Text('Log ${store.template(id)?.name ?? 'workout'}'),
                    onTap: () => Navigator.pop(sheet, 'logfrom:${dateKey(from)}:$id'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action.startsWith('session:')) {
      final s = store.history.where((x) => x.id == action.substring(8)).firstOrNull;
      if (s != null) openSessionEditor(context, s);
    } else if (action.startsWith('start:')) {
      unawaited(startPlanned(context, action.substring(6)));
    } else if (action == 'missed') {
      cycle.events[key] = DayEvent(templateId: d.templateId!, status: 'missed', movedTo: event?.movedTo);
      store.changed();
    } else if (action == 'undo') {
      cycle.events.remove(key);
      store.changed();
    } else if (action == 'move') {
      final picked = await showDatePicker(
        context: context,
        initialDate: (d.movedTo ?? dateOnly(DateTime.now())).isBefore(cycleStatus(cycle).start)
            ? cycleStatus(cycle).start
            : (d.movedTo ?? dateOnly(DateTime.now())).isAfter(cycleStatus(cycle).end)
            ? cycleStatus(cycle).end
            : (d.movedTo ?? dateOnly(DateTime.now())),
        // A workout moved outside the cycle would vanish from its calendar.
        firstDate: cycleStatus(cycle).start,
        lastDate: cycleStatus(cycle).end,
      );
      if (picked == null) return;
      cycle.events[key] = DayEvent(templateId: d.templateId!, movedTo: dateKey(picked) == key ? null : picked);
      store.changed();
    } else if (action == 'link') {
      final options = store.history.where((s) => s.templateId == d.templateId && s.doneAll > 0).take(100).toList();
      if (options.isEmpty) return notify(context, 'No recorded workouts found.');
      final picked = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Choose recorded workout', style: Theme.of(sheet).textTheme.titleLarge),
              ),
              for (final s in options)
                ListTile(title: Text(fmtRecent(s.startedAt)), onTap: () => Navigator.pop(sheet, s.id)),
            ],
          ),
        ),
      );
      if (picked == null || !context.mounted) return;
      final error = store.linkRecordedSession(cycle, key, d.templateId!, picked);
      if (error != null) notify(context, error);
    } else if (action == 'log') {
      var templateId = d.templateId;
      var unplanned = d.unplanned;
      if (templateId == null) {
        if (store.templates.isEmpty) return notify(context, 'Create a workout first.');
        templateId = await pickTemplate(context, null, title: 'Choose workout', allowRest: false);
        if (templateId == null || !context.mounted) return;
        unplanned = true;
      }
      _log(context, store, key, templateId, d.movedTo ?? d.date, unplanned: unplanned);
    } else if (action.startsWith('logfrom:')) {
      final parts = action.split(':');
      _log(context, store, parts[1], parts[2], d.date);
    }
  }

  void _log(
    BuildContext context,
    AppStore store,
    String plannedKey,
    String templateId,
    DateTime date, {
    bool unplanned = false,
  }) {
    final tpl = store.template(templateId);
    if (tpl == null) return notify(context, 'This workout is no longer available.');
    if (tpl.exercises.isEmpty) return notify(context, 'Add exercises to this workout first.');
    final day = date.isAfter(DateTime.now()) ? DateTime.now() : date;
    final draft = store.draftPastSession(templateId, day);
    openSessionEditor(context, draft, cycle: cycle, plannedKey: plannedKey, draft: true, unplanned: unplanned);
  }
}
