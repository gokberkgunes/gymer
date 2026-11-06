import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// A compact location switch, shared by plate settings and the calculator's existing footer.
class PlateProfilePicker extends StatelessWidget {
  const PlateProfilePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final settings = store.settings;
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Plate profile',
      onSelected: (id) => store.updateSettings((settings) => settings.selectedPlateProfile = id),
      itemBuilder: (_) => [
        for (final profile in settings.plateProfiles)
          CheckedPopupMenuItem(
            value: profile.id,
            checked: profile.id == settings.plateProfile.id,
            child: Text(profile.name),
          ),
      ],
      child: Container(
        constraints: BoxConstraints(minHeight: compactButton.height),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                settings.plateProfile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
