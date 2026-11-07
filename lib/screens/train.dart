import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/cycle.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'cycle.dart';
import 'history.dart';
import 'home.dart' show openSession;
import 'template_editor.dart';
import '../store.dart';

/// The Workout tab: cycle status and calendar on top, then workouts, with the
/// active or today's workout first behind an animated rainbow border.
class TrainScreen extends StatelessWidget {
  final VoidCallback onOpenCycle;
  const TrainScreen({super.key, required this.onOpenCycle});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cycle = store.activeCycle;
    final status = cycle == null ? null : cycleStatus(cycle);
    String? featured;
    var label = '';
    if (store.active?.templateId != null) {
      featured = store.active!.templateId;
      label = 'ACTIVE';
    } else if (cycle != null && status!.running) {
      featured = cycle.schedule[status.dayInMicro];
      if (featured != null) label = 'TODAY';
    }
    final workouts = [...store.templates]
      ..sort((a, b) => (a.id == featured ? 0 : 1).compareTo(b.id == featured ? 0 : 1));
    final cycleRir = status != null && status.running ? status.suggestedRir : null;

    return ListView(
      padding: pageInsets,
      children: [
        PageHeader(
          'Train',
          overline: fmtDate(DateTime.now()),
          actions: [
            IconButton.filled(
              tooltip: 'New workout',
              onPressed: () => editTemplate(context, store.newTemplate()),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        if (store.active == null) ...[const _QuickStart(), const SizedBox(height: 8)],
        if (cycle != null) ...[
          CycleStatusCard(cycle: cycle, compact: true, onTap: onOpenCycle),
          const SizedBox(height: 8),
          CycleHeatmap(cycle: cycle, compact: true),
          const SizedBox(height: 8),
        ],
        const SectionLabel('Workouts'),
        if (workouts.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Text('No workouts yet. Create one with +.')),
        for (final w in workouts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _WorkoutTile(template: w, featured: w.id == featured, label: label, cycleRir: cycleRir),
          ),
      ],
    );
  }
}

/// Start an unplanned workout and add exercises on the way.
class _QuickStart extends StatelessWidget {
  const _QuickStart();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final st = context.style;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: st.br,
      child: InkWell(
        borderRadius: st.br,
        onTap: () {
          store.startSession(null);
          openSession(context);
        },
        child: Padding(
          padding: EdgeInsets.all(st.sp(16)),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                // Subtle tint: the header's "+" stays the only strong accent on the page.
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.16), borderRadius: st.brSmall),
                child: Icon(Icons.play_arrow_rounded, color: cs.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Empty workout', style: t.titleMedium),
                  Text('Add exercises as you go', style: t.bodyMedium),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkoutTile extends StatefulWidget {
  final WorkoutTemplate template;
  final bool featured;
  final String label;
  final int? cycleRir;
  const _WorkoutTile({required this.template, required this.featured, required this.label, required this.cycleRir});

  @override
  State<_WorkoutTile> createState() => _WorkoutTileState();
}

class _WorkoutTileState extends State<_WorkoutTile> with SingleTickerProviderStateMixin {
  AnimationController? _rainbow;

  bool get _isRainbow => widget.featured && widget.label == 'TODAY';

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _WorkoutTile old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_isRainbow && _rainbow == null) {
      _rainbow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    } else if (!_isRainbow && _rainbow != null) {
      _rainbow!.dispose();
      _rainbow = null;
    }
  }

  @override
  void dispose() {
    _rainbow?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final t = widget.template;
    if (!t.exercises.any((e) => e.sets.isNotEmpty)) return editTemplate(context, t);
    await startPlanned(context, t.id);
  }

  void _menu() async {
    final t = widget.template;
    final hasSets = t.exercises.any((e) => e.sets.isNotEmpty);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasSets)
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('Start'),
                onTap: () => Navigator.pop(sheet, 'start'),
              ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(sheet, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('History'),
              onTap: () => Navigator.pop(sheet, 'history'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'start':
        _start();
      case 'edit':
        editTemplate(context, t);
      case 'history':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryScreen(templateId: t.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    final w = widget.template;
    final muscles = {for (final e in w.exercises) ...?store.exercise(e.name)?.primary};
    final orderedMuscles = [
      for (final m in rpLandmarks.keys)
        if (muscles.contains(m)) m,
    ];

    final last = store.history
        .where((h) => h.templateId == w.id)
        .map((h) => h.startedAt)
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final ago = last == null ? null : _ago(last);
    final sets = w.exercises.fold(0, (a, e) => a + e.sets.length);

    final card = Material(
      color: widget.featured ? Color.alphaBlend(cs.primary.withValues(alpha: 0.08), cs.surface) : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: st.br,
        side: BorderSide(
          color: widget.featured && !_isRainbow ? cs.primary : cs.outlineVariant,
          width: widget.featured ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: st.br,
        onTap: _start,
        onLongPress: _menu,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, st.sp(16), 16, st.sp(16)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            w.name.isEmpty ? 'Untitled' : w.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleMedium?.copyWith(fontSize: 18),
                          ),
                        ),
                        if (widget.featured) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(99)),
                            child: Text(
                              widget.label.isEmpty ? 'ACTIVE' : widget.label,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onPrimary),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      w.exercises.isEmpty ? 'No exercises yet' : w.exercises.map((e) => e.name).join(' · '),
                      maxLines: widget.featured ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (widget.featured && (orderedMuscles.isNotEmpty || widget.cycleRir != null)) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (widget.cycleRir != null) '${widget.cycleRir} RIR',
                          '$sets sets',
                          ...orderedMuscles.take(4),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              // Only real dates; never-done workouts stay clean. Edit is in the long-press menu.
              if (ago != null) ...[
                const SizedBox(width: 8),
                // Level with the workout's name, not floating in the middle of the tile.
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(ago, style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!_isRainbow) return card;
    return AnimatedBuilder(
      animation: _rainbow!,
      builder: (context, child) => Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: st.br,
          gradient: rainbowGradient(Theme.of(context).brightness == Brightness.dark, _rainbow!.value * 2),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: st.br),
          child: child,
        ),
      ),
      child: card,
    );
  }
}

/// The Flet app's rainbow border: six hues at 45°, slowly shifting.
LinearGradient rainbowGradient(bool dark, double offset) {
  final colors = dark
      ? const [
          Color(0xFFFF5C74),
          Color(0xFFFF9A3C),
          Color(0xFFF5D742),
          Color(0xFF53D785),
          Color(0xFF56B9FF),
          Color(0xFFB783FF),
        ]
      : const [
          Color(0xFFE0405E),
          Color(0xFFE8802A),
          Color(0xFFD1A800),
          Color(0xFF2FB36B),
          Color(0xFF2D93E0),
          Color(0xFF8E5CE6),
        ];
  return LinearGradient(
    colors: [...colors, colors.first],
    begin: Alignment(-1 + offset, 0),
    end: Alignment(1 + offset, 0),
    transform: const GradientRotation(math.pi / 4),
    tileMode: TileMode.repeated,
  );
}

String _ago(DateTime d) {
  final days = daysBetween(dateOnly(d), dateOnly(DateTime.now()));
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return '1 week ago';
  if (days < 60) return '${days ~/ 7} weeks ago';
  return fmtShortDate(d);
}
