import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

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
    // A timer posted before Android stopped the app is unknown to this run, so it could never be removed:
    // it stayed up in the foreground and its backup alarm still announced "Rest over" after the set began.
    if (Platform.isAndroid) unawaited(_live.invokeMethod<void>('clear').catchError((_) {}));
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
    if (kIsWeb || !Platform.isAndroid) return;
    unawaited(
      _live.invokeMethod<void>('keepAwake', on).catchError((Object e) {
        debugPrint('gymer: keep-awake unavailable: $e');
      }),
    );
  }

  String? _widgetPlan;

  @override
  void todayWidget(String plan) {
    if (kIsWeb || !Platform.isAndroid || plan == _widgetPlan) return;
    _widgetPlan = plan;
    unawaited(_live.invokeMethod<void>('todayWidget', plan).catchError((_) {}));
  }

  @override
  void scheduleRest(DateTime at, String exercise) => _alarm(() => _schedule(at, exercise, _alarmRequest));

  /// Scheduling takes several awaited platform calls, so requests run one after another and each carries a
  /// number: a schedule that has been overtaken by a newer schedule or a cancel stops before it posts, and a
  /// cancelled alarm can never be scheduled afterwards.
  int _alarmRequest = 0;
  Future<void> _alarmQueue = Future.value();

  void _alarm(Future<void> Function() step) {
    _alarmRequest++;
    _alarmQueue = _alarmQueue.then((_) => step()).catchError((Object e) {
      debugPrint('gymer: rest alarm failed: $e');
    });
  }

  Future<void> _schedule(DateTime at, String exercise, int request) async {
    if (!_ready || request != _alarmRequest) return;
    await _askOnce();
    final exact = await canScheduleExact() ?? true;
    await _plugin.cancel(id: _restId);
    if (request != _alarmRequest || !at.isAfter(DateTime.now())) return;
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

  @override
  void setDone() => HapticFeedback.lightImpact();

  /// Three heavy pulses 200 ms apart.
  @override
  void restDone({required bool haptics}) {
    // While the status-bar timer is up, the native side vibrates when rest ends; avoid a second buzz.
    if (haptics && _liveKey == null) {
      for (var i = 0; i < 3; i++) {
        Timer(Duration(milliseconds: 200 * i), HapticFeedback.heavyImpact);
      }
    }
  }

  @override
  void cancelRest() {
    if (_ready) _alarm(() => _plugin.cancel(id: _restId));
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
