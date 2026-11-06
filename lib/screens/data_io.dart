import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../logic/legacy_import.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';

void _say(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<void> importFletBackup(BuildContext context) async {
  final store = StoreScope.read(context);
  final ok = await confirm(
    context,
    'Import from old Gymer',
    'Replaces all workouts, history, mesocycles and settings here with the backup\'s contents.'
        ' Your current data is backed up first.'
        '${store.active != null ? ' The workout in progress is discarded.' : ''}',
    action: 'Choose ZIP',
  );
  if (!ok) return;
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['zip']);
  if (file == null || !context.mounted) return;
  try {
    final data = convertLegacy(readBackupZip(await file.readAsBytes()));
    if (!context.mounted) return;
    final lines = await store.importLegacy(data);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import complete'),
        content: Text(lines.join('\n\n')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  } on FormatException catch (e) {
    if (context.mounted) _say(context, e.message);
  } on FileSystemException catch (e) {
    if (context.mounted) _say(context, e.message);
  } catch (e) {
    if (context.mounted) _say(context, 'Could not read this backup: $e');
  }
}

Future<void> exportBackup(BuildContext context) async {
  final store = StoreScope.read(context);
  final bytes = utf8.encode(const JsonEncoder.withIndent(' ').convert(store.toJson()));
  final name = 'gymer-${dateKey(DateTime.now())}.json';
  final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: 'application/json');
  if (uri != null && context.mounted) _say(context, 'Backup saved.');
}

Future<void> restoreBackup(BuildContext context) async {
  final store = StoreScope.read(context);
  final ok = await confirm(
    context,
    'Restore backup',
    'Replaces all data here with the backup\'s contents.'
        ' Your current data is backed up first.'
        '${store.active != null ? ' The workout in progress is discarded.' : ''}',
    action: 'Choose file',
    destructive: true,
  );
  if (!ok) return;
  final file = await FilePicker.pickFile();
  if (file == null || !context.mounted) return;
  try {
    final String text;
    try {
      text = utf8.decode(await file.readAsBytes());
    } on FormatException {
      throw const FormatException('This file is not a Gymer backup.');
    }
    await store.importJson(text);
    if (context.mounted) _say(context, 'Backup restored.');
  } on FormatException catch (e) {
    if (context.mounted) _say(context, e.message);
  } on FileSystemException catch (e) {
    if (context.mounted) _say(context, e.message);
  } catch (e) {
    if (context.mounted) _say(context, 'Could not read this file: $e');
  }
}

/// Shown once after launch when the data file could not be read and the app started fresh. The unreadable
/// file was kept aside; this lets the user save it somewhere they can reach, so it can be repaired.
Future<void> reportUnreadableData(BuildContext context) async {
  final store = StoreScope.read(context);
  final path = store.unreadableCopy;
  if (path == null) return;
  store.unreadableCopy = null;
  final save = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: const Text('Saved data could not be read'),
      content: const Text(
        'Gymer started with fresh data. Your previous file was kept unchanged: restore an automatic backup, '
        'or save a copy of the file so it can be repaired.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Skip')),
        TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Backups')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save copy')),
      ],
    ),
  );
  if (!context.mounted) return;
  if (save == null) return openAutoBackups(context);
  if (!save) return;
  try {
    final bytes = await File(path).readAsBytes();
    final uri = await FilePicker.saveFile(
      fileName: 'gymer-unreadable-${dateKey(DateTime.now())}.json',
      bytes: bytes,
      mimeType: 'application/json',
    );
    if (uri != null && context.mounted) _say(context, 'Copy saved.');
  } catch (e) {
    if (context.mounted) _say(context, 'Could not save the copy: $e');
  }
}

void openAutoBackups(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AutoBackupsScreen()));

/// The automatic copies kept in app storage (see `snapshotsToKeep`), newest first. Tapping one restores it
/// after a confirmation; the current data is backed up first, so a restore can itself be undone.
class AutoBackupsScreen extends StatefulWidget {
  const AutoBackupsScreen({super.key});

  @override
  State<AutoBackupsScreen> createState() => _AutoBackupsScreenState();
}

class _AutoBackupsScreenState extends State<AutoBackupsScreen> {
  late Future<List<BackupInfo>> _list = StoreScope.read(context).backups();

  static String _when(DateTime d) =>
      '${fmtDate(d)} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _restore(BackupInfo b) async {
    final store = StoreScope.read(context);
    final ok = await confirm(
      context,
      'Restore this backup?',
      'Replaces all data with the copy from ${_when(b.at)}. Your current data is backed up first.'
          '${store.active != null ? ' The workout in progress is discarded.' : ''}',
      action: 'Restore',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await store.restoreSnapshot(b.file);
      if (mounted) _say(context, 'Backup restored.');
    } on FormatException catch (e) {
      if (mounted) _say(context, e.message);
    } on FileSystemException catch (e) {
      if (mounted) _say(context, e.message);
    } catch (e) {
      if (mounted) _say(context, 'Could not restore: $e');
    }
    if (mounted) setState(() => _list = store.backups());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Automatic backups')),
      body: FutureBuilder(
        future: _list,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) return const SizedBox.shrink();
          return ListView(
            padding: subPageInsets,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                child: Text(
                  'Saved after workouts, daily, and before restores or imports. Kept: the last 3 days, 4 weeks and 6 months.',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('No backups yet.', style: t.bodyMedium),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final (i, b) in list.indexed) ...[
                        if (i > 0) const Divider(indent: 16, endIndent: 16),
                        ListTile(
                          title: Text(_when(b.at)),
                          subtitle: Text(
                            b.sessions < 0
                                ? 'Unreadable'
                                : '${plural(b.sessions, 'workout')} logged · ${plural(b.workouts, 'plan')}',
                            style: TextStyle(color: b.sessions < 0 ? cs.error : cs.onSurfaceVariant),
                          ),
                          trailing: Icon(Icons.restore_rounded, color: cs.onSurfaceVariant),
                          enabled: b.sessions >= 0,
                          onTap: () => _restore(b),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
