import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/legacy_import.dart';
import 'package:gymer/store.dart';

import 'import_test.dart' show fletBackup;

Future<(AppStore, Directory)> savedStore() async {
  final dir = await Directory.systemTemp.createTemp('gymer-safety-backup');
  final store = AppStore(file: File('${dir.path}/gymer.json'));
  addTearDown(() async {
    await store.flush();
    store.dispose();
    await dir.delete(recursive: true);
  });
  await store.load();
  return (store, dir);
}

String replacement(AppStore store) => jsonEncode({
  ...store.toJson(),
  'templates': [
    {'id': 'replacement', 'name': 'Imported workout', 'exercises': []},
  ],
  'active': null,
  'rest': null,
});

Future<void> replace(AppStore store, Directory dir, String source) async {
  switch (source) {
    case 'JSON':
      await store.importJson(replacement(store));
    case 'legacy ZIP':
      await store.importLegacy(convertLegacy(readBackupZip(fletBackup())));
    case 'automatic':
      final file = File('${dir.path}/incoming.json');
      await file.writeAsString(replacement(store));
      await store.restoreSnapshot(file);
  }
}

Future<List<File>> backupFiles(Directory dir) =>
    Directory('${dir.path}/backups').list().where((entry) => entry.path.endsWith('.json')).cast<File>().toList();

void main() {
  for (final source in ['JSON', 'legacy ZIP', 'automatic']) {
    test('$source replacement saves a safety backup including unsaved workout changes', () async {
      final (store, dir) = await savedStore();
      store.startSession(store.templates.first);
      store.active!.exercises.first.sets.first.weight = 42.5;
      store.updateSettings((settings) => settings.accent = 2);
      final before = store.toJson();

      await replace(store, dir, source);

      final backup = (await backupFiles(dir)).single;
      expect(jsonDecode(await backup.readAsString()), before);
      expect(store.active, isNull);
      expect(store.templates.single.name, source == 'legacy ZIP' ? 'Legs' : 'Imported workout');

      // The copy can actually recover the complete previous state.
      await store.restoreSnapshot(backup);
      expect(store.toJson(), before);
    });

    test('$source replacement stops if its safety backup cannot be written', () async {
      final (store, dir) = await savedStore();
      store.startSession(store.templates.first);
      await store.flush();
      final before = store.toJson();
      final originalFile = await File('${dir.path}/gymer.json').readAsString();
      // A file in place of the directory makes backup creation fail on every platform.
      await File('${dir.path}/backups').writeAsString('not a directory');

      await expectLater(replace(store, dir, source), throwsA(isA<FileSystemException>()));

      expect(store.toJson(), before);
      expect(await File('${dir.path}/gymer.json').readAsString(), originalFile);
      await store.flush();
      expect(jsonDecode(await File('${dir.path}/gymer.json').readAsString()), before);
    });
  }

  test('a damaged backup is rejected before creating a safety copy', () async {
    final (store, dir) = await savedStore();
    final before = store.toJson();
    final damaged = {
      ...before,
      'history': ['not a session'],
    };

    await expectLater(store.importJson(jsonEncode(damaged)), throwsFormatException);

    expect(store.toJson(), before);
    expect(await Directory('${dir.path}/backups').exists(), isFalse);
  });

  test('rapid backups keep distinct recovery points and skip unchanged data', () async {
    final (store, dir) = await savedStore();
    await store.snapshot();
    final first = (await backupFiles(dir)).single;
    final original = await first.readAsString();

    store.updateSettings((settings) => settings.accent = 2);
    await store.snapshot();
    await store.snapshot();

    expect(await backupFiles(dir), hasLength(2));
    expect(await first.readAsString(), original);
    final second = (await backupFiles(dir)).singleWhere((file) => file.path != first.path);
    expect(jsonDecode(await second.readAsString()), store.toJson());
  });
}
