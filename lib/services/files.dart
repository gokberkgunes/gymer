import 'dart:io';

import 'package:flutter/services.dart';

/// The system's own file dialogs: Android's document picker and the desktop's GTK dialog, both reached
/// through the app's `gymer/files` channel (MainActivity.kt, linux/runner/my_application.cc).
const _files = MethodChannel('gymer/files');

class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);

  /// The text after the last dot of the name, or null without one.
  String? get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 || dot == name.length - 1 ? null : name.substring(dot + 1);
  }
}

/// Lets the user choose one file and reads it. Null when cancelled.
Future<PickedFile?> pickFile({bool image = false}) async {
  if (Platform.isAndroid) {
    // Android hands over the content itself: a document has no path the app could open.
    final picked = await _files.invokeMapMethod<String, Object?>('pick', {'image': image});
    final bytes = picked?['bytes'];
    if (picked == null || bytes is! Uint8List) return null;
    return PickedFile(picked['name'] as String? ?? '', bytes);
  }
  final path = await _files.invokeMethod<String>('pick', {'image': image});
  if (path == null) return null;
  return PickedFile(path.substring(path.lastIndexOf('/') + 1), await File(path).readAsBytes());
}

/// Lets the user choose where to save [bytes], suggesting [name]. False when cancelled.
Future<bool> saveFile(String name, List<int> bytes, String mimeType) async {
  if (Platform.isAndroid) {
    final saved = await _files.invokeMethod<bool>('save', {
      'name': name,
      'bytes': bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      'mime': mimeType,
    });
    return saved ?? false;
  }
  final path = await _files.invokeMethod<String>('save', {'name': name});
  if (path == null) return false;
  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}
