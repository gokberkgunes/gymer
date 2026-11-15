import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/files.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Optional progress photos: pick an image, keep it in app storage under its date, compare any two.
class ProgressPhotosScreen extends StatefulWidget {
  const ProgressPhotosScreen({super.key});

  @override
  State<ProgressPhotosScreen> createState() => _ProgressPhotosScreenState();
}

class _ProgressPhotosScreenState extends State<ProgressPhotosScreen> {
  late Future<List<(DateTime, File)>> _photos = StoreScope.read(context).progressPhotos();

  /// Up to two photos chosen for the side-by-side comparison, in the order tapped.
  final _chosen = <String>[];

  void _reload() => setState(() => _photos = StoreScope.read(context).progressPhotos());

  Future<void> _add() async {
    final store = StoreScope.read(context);
    final PickedFile? picked;
    try {
      picked = await pickFile(image: true);
    } catch (e) {
      if (mounted) notify(context, 'Could not read that image.');
      return;
    }
    if (picked == null || !mounted) return;
    final day = await showDatePicker(
      context: context,
      initialDate: dateOnly(DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: dateOnly(DateTime.now()),
      helpText: 'When was this taken?',
    );
    if (day == null || !mounted) return;
    final String? error;
    try {
      error = await store.addProgressPhoto(picked.bytes, picked.extension ?? 'jpg', day);
    } catch (e) {
      if (mounted) notify(context, 'Could not read that image.');
      return;
    }
    if (!mounted) return;
    if (error != null) notify(context, error);
    _reload();
  }

  Future<void> _delete(File photo, DateTime date) async {
    final ok = await confirm(
      context,
      'Delete photo',
      'The photo from ${fmtDate(date)} is removed from Gymer. It cannot be restored.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await StoreScope.read(context).deleteProgressPhoto(photo);
    if (!mounted) return;
    _chosen.remove(photo.path);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final enabled = store.settings.trackPhotos && store.photosAvailable;
    return Scaffold(
      appBar: AppBar(
        title: LabelWithInfo(
          const Text('Progress photos'),
          InfoDot(
            tooltip: 'Progress photos',
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Progress photos'),
                content: const Text(
                  'Add a photo with + and give it the date it was taken. Tap two photos to see them side by side; '
                  'hold a photo to delete it.\n\n'
                  'Photos are copied into Gymer\'s own storage. They are not part of backups or exports, are never '
                  'sent anywhere, and are removed when the app is uninstalled, so keep the originals if they '
                  'matter to you. Same light, pose and distance each time make them comparable.',
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
              ),
            ),
          ),
        ),
        actions: [
          if (enabled) IconButton.filled(tooltip: 'Add photo', icon: const Icon(Icons.add_rounded), onPressed: _add),
        ],
      ),
      body: !enabled
          ? null
          : FutureBuilder(
              future: _photos,
              builder: (context, snap) {
                final photos = snap.data;
                if (photos == null) return const SizedBox.shrink();
                if (photos.isEmpty) {
                  return Center(
                    child: Text('No photos.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  );
                }
                final pair = [for (final path in _chosen) ?photos.where((p) => p.$2.path == path).firstOrNull];
                return ListView(
                  padding: subPageInsets,
                  children: [
                    if (pair.length == 2) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, (date, file)) in pair.indexed) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: context.style.br,
                                    child: Image.file(file, fit: BoxFit.contain, cacheWidth: 900),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(fmtDate(date), style: t.labelMedium),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.7,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (final (date, file) in photos.reversed)
                          () {
                            final picked = _chosen.contains(file.path);
                            return Semantics(
                              label: 'Photo from ${fmtDate(date)}${picked ? ', selected' : ''}',
                              child: InkWell(
                                borderRadius: context.style.br,
                                onTap: () => setState(() {
                                  if (!_chosen.remove(file.path)) {
                                    if (_chosen.length == 2) _chosen.removeAt(0);
                                    _chosen.add(file.path);
                                  }
                                }),
                                onLongPress: () => _delete(file, date),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        foregroundDecoration: BoxDecoration(
                                          borderRadius: context.style.br,
                                          border: Border.all(color: picked ? cs.primary : Colors.transparent, width: 3),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: context.style.br,
                                          child: Image.file(
                                            file,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            cacheWidth: 360,
                                            errorBuilder: (_, _, _) => ColoredBox(
                                              color: cs.surfaceContainerHigh,
                                              child: const Center(child: Icon(Icons.broken_image_outlined)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(fmtShortDate(date), style: t.labelSmall),
                                  ],
                                ),
                              ),
                            );
                          }(),
                      ],
                    ),
                  ],
                );
              },
            ),
    );
  }
}
