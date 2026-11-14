import 'package:flutter/material.dart';

import '../logic/cycle.dart' show rpLandmarks;
import 'common.dart';
import '../store.dart';

/// [inWorkout]: exercises already in the workout being edited. They stay listed (and selectable, so the caller can
/// explain why it cannot be added again) but are dimmed on a different background.
///
/// One row of filter chips narrows the list to a primary muscle or an equipment type; [muscle] starts with that
/// muscle selected (substitutions) and [musclesFirst] puts those muscles at the front of the row (the workout
/// editor passes the ones still under their minimum effective volume).
Future<String?> pickExercise(
  BuildContext context, {
  Iterable<String> inWorkout = const [],
  String? muscle,
  List<String> musclesFirst = const [],
}) {
  final store = StoreScope.read(context);
  final present = {for (final name in inWorkout) name.trim().toLowerCase()};
  final used = {for (final e in store.exercises) ...e.primary};
  final muscles = [
    for (final m in musclesFirst)
      if (used.contains(m)) m,
    for (final m in [...rpLandmarks.keys, ...used.where((m) => !rpLandmarks.containsKey(m))])
      if (used.contains(m) && !musclesFirst.contains(m)) m,
  ];
  final equipment = {
    for (final e in store.exercises)
      if (e.equipment.isNotEmpty) e.equipment,
  }.toList()..sort();
  return pickName(
    context,
    title: 'Exercise',
    present: (name) => present.contains(name.trim().toLowerCase()),
    values: () => [for (final e in store.exercises) e.name],
    aliases: store.aliasesOf,
    filters: [...muscles, ...equipment],
    initialFilter: muscles.contains(muscle) ? muscle : null,
    matchesFilter: (name, filter) {
      final e = store.exercise(name);
      return e != null && (e.primary.contains(filter) || e.equipment == filter);
    },
    subtitle: (name) {
      final e = store.exercise(name);
      if (e == null) return null;
      final parts = [...e.primary, if (e.equipment.isNotEmpty) e.equipment];
      return parts.isEmpty ? null : parts.join(' · ');
    },
    onAdd: (name) => store.addExercise(name).name,
    isFavourite: (name) => store.exercise(name)?.favourite ?? false,
    toggleFavourite: store.toggleExerciseFavourite,
    recent: store.recentExercises,
  );
}

/// Searchable name picker (fuzzy; leading space = exact) with optional "Add new".
Future<String?> pickName(
  BuildContext context, {
  required String title,
  required List<String> Function() values,
  String? Function(String)? subtitle,
  String Function(String)? onAdd,
  bool Function(String)? isFavourite,
  void Function(String)? toggleFavourite,
  List<String> Function()? recent,
  bool Function(String)? present,
  List<String> filters = const [],
  String? initialFilter,
  bool Function(String name, String filter)? matchesFilter,
  List<String> Function(String)? aliases,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _Picker(
      title: title,
      values: values,
      subtitle: subtitle,
      onAdd: onAdd,
      isFavourite: isFavourite,
      toggleFavourite: toggleFavourite,
      recent: recent,
      present: present,
      filters: filters,
      initialFilter: initialFilter,
      matchesFilter: matchesFilter,
      aliases: aliases,
    ),
  );
}

class _Picker extends StatefulWidget {
  final String title;
  final List<String> Function() values;
  final String? Function(String)? subtitle;
  final String Function(String)? onAdd;
  final bool Function(String)? isFavourite;
  final void Function(String)? toggleFavourite;
  final List<String> Function()? recent;
  final bool Function(String)? present;
  final List<String> filters;
  final String? initialFilter;
  final bool Function(String name, String filter)? matchesFilter;
  final List<String> Function(String)? aliases;
  const _Picker({
    required this.title,
    required this.values,
    this.subtitle,
    this.onAdd,
    this.isFavourite,
    this.toggleFavourite,
    this.recent,
    this.present,
    this.filters = const [],
    this.initialFilter,
    this.matchesFilter,
    this.aliases,
  });

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final _query = TextEditingController();
  late String? _filter = widget.initialFilter;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final raw = _query.text;
    final filter = _filter;
    final matches = [
      for (final name
          in widget.aliases == null
              ? filterNames(widget.values(), raw)
              : filterNamesWithAliases(widget.values(), raw, widget.aliases!))
        if (filter == null || (widget.matchesFilter?.call(name, filter) ?? true)) name,
    ];
    final addable = (raw.startsWith(' ') ? raw.substring(1) : raw).trim();
    final canAdd =
        widget.onAdd != null &&
        addable.isNotEmpty &&
        !widget.values().any((v) => v.toLowerCase() == addable.toLowerCase());
    final grouped = raw.trim().isEmpty && widget.isFavourite != null;
    final favourites = grouped ? matches.where((n) => widget.isFavourite!(n)).toList() : <String>[];
    final available = {for (final n in matches) n.toLowerCase(): n};
    final recent = grouped
        ? [
            for (final n in widget.recent?.call() ?? <String>[])
              if (available[n.toLowerCase()] case final name?)
                if (!widget.isFavourite!(name)) name,
          ].take(8).toList()
        : <String>[];
    final promoted = {
      for (final n in [...favourites, ...recent]) n.toLowerCase(),
    };
    final remaining = grouped ? matches.where((n) => !promoted.contains(n.toLowerCase())).toList() : matches;

    Widget tileFor(String name) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(name),
      subtitle: switch (widget.subtitle?.call(name)) {
        final s? => Text(s, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        _ => null,
      },
      trailing: widget.toggleFavourite == null
          ? null
          : IconButton(
              tooltip: widget.isFavourite!(name) ? 'Remove from favourites' : 'Add to favourites',
              icon: Icon(
                widget.isFavourite!(name) ? Icons.star_rounded : Icons.star_outline_rounded,
                color: widget.isFavourite!(name) ? cs.primary : cs.onSurfaceVariant,
              ),
              onPressed: () => setState(() => widget.toggleFavourite!(name)),
            ),
      onTap: () => Navigator.pop(context, name),
    );
    Widget row(String name) {
      final tile = tileFor(name);
      if (!(widget.present?.call(name) ?? false)) return tile;
      // Already in this workout: a different background with the row dimmed on top of it.
      return Tooltip(
        message: 'Already in this workout',
        child: ColoredBox(
          color: cs.surfaceContainerHigh,
          child: Opacity(opacity: 0.45, child: tile),
        ),
      );
    }

    Widget section(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(label, style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
    );
    final entries = <(String, bool)>[
      if (favourites.isNotEmpty) ...[('Favourites', true), for (final name in favourites) (name, false)],
      if (favourites.isNotEmpty && (recent.isNotEmpty || remaining.isNotEmpty)) ('', true),
      if (recent.isNotEmpty) ...[('Recent', true), for (final name in recent) (name, false)],
      if (recent.isNotEmpty && remaining.isNotEmpty) ('', true),
      if (grouped && promoted.isNotEmpty && remaining.isNotEmpty) ('All exercises', true),
      for (final name in remaining) (name, false),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(widget.title, style: t.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: TextField(
                controller: _query,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Search · a leading space for exact text',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (widget.filters.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                  children: [
                    for (final f in widget.filters)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(f),
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          selected: _filter == f,
                          onSelected: (on) => setState(() => _filter = on ? f : null),
                        ),
                      ),
                  ],
                ),
              )
            else
              const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: entries.length + (canAdd || matches.isEmpty ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < entries.length) {
                    final (label, isSection) = entries[index];
                    if (isSection && label.isEmpty) return const Divider(indent: 20, endIndent: 20, height: 16);
                    return isSection ? section(label) : row(label);
                  }
                  if (canAdd) {
                    return ListTile(
                      leading: Icon(Icons.add_rounded, color: cs.primary),
                      title: Text(
                        'Add new: "$addable"',
                        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                      ),
                      onTap: () => Navigator.pop(context, widget.onAdd!(addable)),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('No matches.', style: TextStyle(color: cs.onSurfaceVariant)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
