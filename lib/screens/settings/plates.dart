part of '../settings.dart';

Future<void> _addPlate(BuildContext context, AppStore store, bool lb) async {
  double? size;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Add a plate size'),
      content: NumField(
        value: null,
        kind: NumKind.weight,
        placeholder: 'Weight of one plate',
        suffix: store.settings.unit,
        dense: false,
        onChanged: (v) => size = v,
        onSubmitted: () => Navigator.pop(c, true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
      ],
    ),
  );
  final v = size;
  if (ok != true || v == null || v <= 0) return;
  store.updateSettings((x) {
    final list = lb ? x.platesLb : x.platesKg;
    if (!list.contains(v)) list.add(v);
    list.sort((a, b) => b.compareTo(a));
  });
}

Route<void> plateSettingsRoute() => MaterialPageRoute(builder: (_) => const _PlateSettings());

Future<void> _editPlateProfile(BuildContext context, {bool rename = false}) async {
  final store = StoreScope.read(context);
  final current = store.settings.plateProfile;
  var text = rename ? current.name : '';
  final name = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(rename ? 'Rename profile' : 'New plate profile'),
        content: TextFormField(
          initialValue: text,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 32,
          decoration: const InputDecoration(hintText: 'Home, gym, …', counterText: ''),
          onChanged: (value) => setState(() => text = value),
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(c, value.trim());
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(
            onPressed: text.trim().isEmpty ? null : () => Navigator.pop(c, text.trim()),
            child: Text(rename ? 'Save' : 'Create'),
          ),
        ],
      ),
    ),
  );
  if (context.mounted) {
    FocusScope.of(context).unfocus();
    if (name != null) {
      store.updateSettings((settings) {
        if (rename) {
          current.name = name;
        } else {
          final profile = PlateProfile.fromJson({
            ...current.toJson(),
            'id': 'P${DateTime.now().microsecondsSinceEpoch}',
            'name': name,
          });
          settings.plateProfiles.add(profile);
          settings.selectedPlateProfile = profile.id;
        }
      });
    }
  }
}

Future<void> _editPlatePairs(BuildContext context, double plate) async {
  final store = StoreScope.read(context);
  final settings = store.settings;
  final profile = settings.plateProfile;
  final unit = settings.unit;
  var text = '${profile.pairsFor(plate, unit)}';
  final count = await showDialog<int>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final value = int.tryParse(text);
        final valid = value != null && value >= 1 && value <= 9999;
        return AlertDialog(
          title: Text('${formatNumber(plate, NumKind.load)} $unit pairs'),
          content: TextFormField(
            initialValue: text,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            decoration: const InputDecoration(hintText: 'Number of pairs'),
            onChanged: (value) => setState(() => text = value),
            onFieldSubmitted: (_) {
              if (valid) Navigator.pop(c, value);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 0), child: const Text('Remove')),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            TextButton(onPressed: valid ? () => Navigator.pop(c, value) : null, child: const Text('Save')),
          ],
        );
      },
    ),
  );
  if (count != null) {
    store.updateSettings((_) {
      final plates = unit == 'lb' ? profile.platesLb : profile.platesKg;
      final pairs = unit == 'lb' ? profile.pairsLb : profile.pairsKg;
      if (count == 0) {
        plates.remove(plate);
        pairs.remove(plate); // re-adding the size later starts from the default again
      } else {
        pairs[plate] = count;
      }
    });
  }
}

/// Each location keeps its own bar, plate sizes and optional pair limits.
class _PlateSettings extends StatelessWidget {
  const _PlateSettings();

  static const _candidatesKg = [50.0, 25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 2.0, 1.25, 1.0, 0.5, 0.25];
  static const _candidatesLb = [55.0, 45.0, 35.0, 25.0, 15.0, 10.0, 5.0, 2.5, 1.25];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final lb = s.unit == 'lb';
    return _Page(
      title: 'Plates',
      children: [
        const SizedBox(height: 8),
        _group([
          _row(
            context,
            'Profile',
            SizedBox(
              width: 180,
              child: Row(
                children: [
                  const Expanded(child: PlateProfilePicker()),
                  PopupMenuButton<String>(
                    tooltip: 'Manage plate profiles',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (action) async {
                      if (action == 'add' || action == 'rename') {
                        await _editPlateProfile(context, rename: action == 'rename');
                      } else {
                        final profile = s.plateProfile;
                        if (s.plateProfiles.length < 2) return;
                        final remove = await confirm(
                          context,
                          'Delete ${profile.name}?',
                          'Its bar and plate setup will be removed.',
                          action: 'Delete',
                          destructive: true,
                        );
                        if (!remove) return;
                        store.updateSettings((settings) {
                          settings.plateProfiles.remove(profile);
                          settings.selectedPlateProfile = settings.plateProfiles.first.id;
                        });
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'add', child: Text('New profile')),
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', enabled: s.plateProfiles.length > 1, child: const Text('Delete')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _row(
            context,
            'Bar',
            SizedBox(
              width: 100,
              child: NumField(
                key: ValueKey('${s.plateProfile.id}-${s.unit}-bar'),
                value: s.bar,
                kind: NumKind.load,
                suffix: s.unit,
                align: TextAlign.center,
                onChanged: (v) {
                  if (v == null) return;
                  store.updateSettings((x) {
                    if (lb) {
                      x.barLb = v;
                    } else {
                      x.barKg = v;
                    }
                  });
                },
              ),
            ),
            subtitle: 'Exercises can set their own, e.g. an EZ bar',
          ),
          _row(
            context,
            'Limit plate pairs',
            Switch(
              value: s.plateProfile.limitedPairs,
              onChanged: (value) => store.updateSettings((settings) => settings.plateProfile.limitedPairs = value),
            ),
            subtitle: 'Off: unlimited pairs',
            info: InfoDot(
              tooltip: 'Plate pairs',
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Plate pairs'),
                  content: const Text(
                    'One pair is one plate on each side. Tap a selected size to edit its pair count or remove it.',
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
                ),
              ),
            ),
          ),
          _row(
            context,
            'Group repeated plates',
            Switch(
              value: s.groupRepeatedPlates,
              onChanged: (value) => store.updateSettings((settings) => settings.groupRepeatedPlates = value),
            ),
            subtitle: 'One plate per size, count centred at the top',
            info: InfoDot(
              tooltip: 'Grouped plate display',
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Grouped plate display'),
                  content: const Text(
                    'Repeated plates share one full-size drawing. A plain number centred at the top shows how many go on each side. Plates keep their normal spacing. Applies to every profile.',
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
                ),
              ),
            ),
          ),
        ]),
        SectionLabel('Plates you have · ${s.unit}'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            // Common sizes plus any custom size the user added; a custom size disappears when switched off.
            for (final p in {
              ...(lb ? _candidatesLb : _candidatesKg),
              ...s.plates,
            }.toList()..sort((a, b) => b.compareTo(a)))
              FilterChip(
                label: Text(
                  '${formatNumber(p, NumKind.load)}${s.plateProfile.limitedPairs && s.plates.contains(p) ? ' ×${s.plateProfile.pairsFor(p, s.unit)}' : ''}',
                  style: const TextStyle(fontFeatures: tabular),
                ),
                showCheckmark: false,
                selected: s.plates.contains(p),
                onSelected: (on) {
                  if (!on && s.plateProfile.limitedPairs) {
                    _editPlatePairs(context, p);
                    return;
                  }
                  store.updateSettings((x) {
                    final list = lb ? x.platesLb : x.platesKg;
                    on ? list.add(p) : list.remove(p);
                    list.sort((a, b) => b.compareTo(a));
                  });
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Other size'),
              onPressed: () => _addPlate(context, store, lb),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => store.updateSettings((x) {
            if (lb) {
              x
                ..barLb = defaultBarLb
                ..platesLb = List.of(defaultPlatesLb);
              x.plateProfile.pairsLb.clear();
            } else {
              x
                ..barKg = defaultBarKg
                ..platesKg = List.of(defaultPlatesKg);
              x.plateProfile.pairsKg.clear();
            }
          }),
          child: const Text('Reset bar and plates'),
        ),
      ],
    );
  }
}
