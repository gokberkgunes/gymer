import 'dart:io';

import 'package:flutter/services.dart';

/// The folder that holds `gymer.json`, its backups and the progress photos.
///
/// These are the folders the app has always used, so existing data is found again: Android's own files
/// directory, and on Linux `$XDG_DATA_HOME/com.gymer.gymer` (`~/.local/share` when unset), or the older
/// `gymer` folder there when only that one exists.
Future<Directory> appDataDirectory() async {
  if (Platform.isAndroid) {
    final path = await const MethodChannel('gymer/live_timer').invokeMethod<String>('filesDir');
    if (path == null || path.isEmpty) throw StateError('Android gave no files directory');
    return Directory(path);
  }
  return linuxDataDirectory(Platform.environment);
}

Future<Directory> linuxDataDirectory(Map<String, String> env) async {
  final xdg = env['XDG_DATA_HOME'] ?? '';
  final home = env['HOME'] ?? '';
  if (xdg.isEmpty && home.isEmpty) throw StateError('HOME is not set');
  final base = xdg.isEmpty ? '$home/.local/share' : xdg;
  final dir = Directory('$base/com.gymer.gymer');
  if (dir.existsSync()) return dir;
  final old = Directory('$base/gymer');
  if (old.existsSync()) return old;
  return dir.create(recursive: true);
}
