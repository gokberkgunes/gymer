import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../store.dart';

/// Keep-awake and the rest-over notification that fires on a locked phone.
class PlatformAlerts extends Alerts {
  static const _restId = 1;
  static const _live = MethodChannel('gymer/live_timer');
  String? _liveKey;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _asked = false;

  bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> init() async {
    if (!_mobile) return;
    tzdata.initializeTimeZones();
    _ready =
        await _plugin.initialize(
          settings: const InitializationSettings(
            // Status-bar icons must be monochrome; the coloured launcher icon would show as a blob.
            android: AndroidInitializationSettings('@drawable/ic_stat_timer'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
        ) ??
        false;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _askOnce() async {
    if (_asked) return;
    _asked = true;
    await _android?.requestNotificationsPermission();
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
      alert: true,
      sound: true,
    );
  }

  /// Whether Android lets us fire at the exact second (null off Android).
  Future<bool?> canScheduleExact() async => _android?.canScheduleExactNotifications();

  Future<void> requestExact() async => _android?.requestExactAlarmsPermission();

  /// Null on platforms where Android notification settings are unavailable.
  Future<bool?> notificationsEnabled() async => _android?.areNotificationsEnabled();

  Future<void> openNotificationSettings() async => _android?.openAppNotificationSettings();

  @override
  void keepAwake(bool on) {
    if (!_mobile) return;
    WakelockPlus.toggle(enable: on);
  }

  @override
  void scheduleRest(DateTime at, String exercise) => _schedule(at, exercise);

  Future<void> _schedule(DateTime at, String exercise) async {
    if (!_ready) return;
    await _askOnce();
    final exact = await canScheduleExact() ?? true;
    await _plugin.cancel(id: _restId);
    await _plugin.zonedSchedule(
      id: _restId,
      title: 'Rest over',
      body: exercise.isEmpty ? 'Time for the next set.' : 'Next set: $exercise',
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'rest',
          'Rest timer',
          channelDescription: 'Alerts when a rest period ends',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  AudioPlayer? _player;

  @override
  void setDone() => HapticFeedback.lightImpact();

  /// Three heavy pulses 200 ms apart, plus the optional two-tone beep.
  @override
  void restDone({required bool haptics, required bool sound}) {
    // While the status-bar timer is up, the native side vibrates when rest ends; avoid a second buzz.
    if (haptics && _liveKey == null) {
      for (var i = 0; i < 3; i++) {
        Timer(Duration(milliseconds: 200 * i), HapticFeedback.heavyImpact);
      }
    }
    if (sound) {
      _player ??= AudioPlayer();
      _player!.play(BytesSource(beepWav(), mimeType: 'audio/wav')).catchError((_) {});
    }
  }

  @override
  void cancelRest() {
    if (_ready) _plugin.cancel(id: _restId);
  }

  /// The live timer is only posted while the app is in the background; inside the app the in-app timer
  /// is already visible. [_pending] holds the latest timer so it can be posted when the app is left.
  bool _foreground = true;
  ({String key, Map<String, Object> args})? _pending;

  @override
  void showLiveRest(
    DateTime endsAt,
    String exercise, {
    required bool endAtZero,
    String icon = 'muscle',
    String overtimeIcon = 'warning',
    String chipText = '',
    bool vibrate = false,
  }) {
    if (kIsWeb || !Platform.isAndroid) return;
    _askOnce(); // while the app is open, so the permission prompt can appear
    _pending = (
      key: '${endsAt.millisecondsSinceEpoch}|$exercise|$endAtZero|$icon|$overtimeIcon|$chipText|$vibrate',
      args: {
        'endsAt': endsAt.millisecondsSinceEpoch,
        'title': 'Rest',
        'text': exercise.isEmpty ? 'Next set coming up' : 'Next: $exercise',
        'endAtZero': endAtZero,
        'icon': icon,
        'overtimeIcon': overtimeIcon,
        'chipText': chipText,
        'vibrate': vibrate,
      },
    );
    if (!_foreground) _postLive();
  }

  void _postLive() {
    final p = _pending;
    if (p == null || p.key == _liveKey) return; // the store syncs often; Android ticks the timer itself
    _liveKey = p.key;
    _live.invokeMethod('show', p.args).catchError((_) => null);
  }

  void _removeLive() {
    if (_liveKey == null) return;
    _liveKey = null;
    _live.invokeMethod('clear').catchError((_) => null);
  }

  @override
  void clearLiveRest() {
    if (kIsWeb || !Platform.isAndroid) return;
    _pending = null;
    _removeLive();
  }

  @override
  void setForeground(bool foreground) {
    if (kIsWeb || !Platform.isAndroid) return;
    _foreground = foreground;
    foreground ? _removeLive() : _postLive();
  }
}

/// Two short sine beeps (880 Hz, 1175 Hz) as an in-memory WAV, like the Flet app.
Uint8List beepWav() {
  const rate = 22050;
  final samples = <int>[];
  for (final freq in [880.0, 1175.0]) {
    final count = (rate * 0.16).round();
    final fade = (rate * 0.01).round();
    for (var i = 0; i < count; i++) {
      final gain = math.min(1.0, math.min(i / fade, (count - i) / fade));
      samples.add((18000 * gain * math.sin(2 * math.pi * freq * i / rate)).round());
    }
    samples.addAll(List.filled((rate * 0.08).round(), 0));
  }
  final data = ByteData(44 + samples.length * 2);
  void ascii(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}
