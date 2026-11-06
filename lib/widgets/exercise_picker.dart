import 'package:flutter/material.dart';

import 'common.dart';

Future<String?> pickExercise(BuildContext context) {
  final store = StoreScope.read(context);
  return pickName(
    context,
    title: 'Exercise',
    values: () => [for (final e in store.exercises) e.name],
    subtitle: (name) {
      final e = store.exercise(name);
      return e == null || e.primary.isEmpty ? null : e.primary.join(' · ');
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
  const _Picker({
    required this.title,
    required this.values,
    this.subtitle,
    this.onAdd,
    this.isFavourite,
    this.toggleFavourite,
    this.recent,
  });

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final _query = TextEditingController();

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
    final matches = filterNames(widget.values(), raw);
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

    Widget row(String name) => ListTile(
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
    Widget section(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(label, style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
    );
    final entries = <(String, bool)>[
      if (favourites.isNotEmpty) ...[('Favourites', true), for (final name in favourites) (name, false)],
      if (recent.isNotEmpty) ...[('Recent', true), for (final name in recent) (name, false)],
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
                decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search_rounded)),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 2, 20, 8),
              child: Text(
                'Fuzzy search · start with a space for exact text',
                style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: entries.length + (canAdd || matches.isEmpty ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < entries.length) {
                    final (label, isSection) = entries[index];
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
