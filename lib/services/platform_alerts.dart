import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';

import '../store.dart';

/// Keep-awake and the rest-over notification that fires on a locked phone.
class PlatformAlerts extends Alerts {
  static const _live = MethodChannel('gymer/live_timer');
  String? _liveKey;
  bool _ready = false;
  bool _asked = false;

  bool get _android => !kIsWeb && Platform.isAndroid;

  Future<void> init() async {
    if (!_android) return;
    // A timer posted before Android stopped the app is unknown to this run, so it could never be removed:
    // it stayed up in the foreground and its backup alarm still announced "Rest over" after the set began.
    unawaited(_live.invokeMethod<void>('clear').catchError((_) {}));
    _ready = true;
  }

  /// Android's notification prompt, once per run. It does not wait for the answer.
  Future<void> _askOnce() async {
    if (_asked) return;
    _asked = true;
    await _live.invokeMethod<void>('askNotifications');
  }

  /// Whether Android lets us fire at the exact second (null off Android).
  Future<bool?> canScheduleExact() async => _android ? _live.invokeMethod<bool>('exactAllowed') : null;

  Future<void> requestExact() async {
    if (_android) await _live.invokeMethod<void>('requestExact');
  }

  /// Null on platforms where Android notification settings are unavailable.
  Future<bool?> notificationsEnabled() async => _android ? _live.invokeMethod<bool>('notificationsEnabled') : null;

  Future<void> openNotificationSettings() async {
    if (_android) await _live.invokeMethod<void>('notificationSettings');
  }

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
    await _live.invokeMethod<void>('cancelAlarm');
    if (request != _alarmRequest || !at.isAfter(DateTime.now())) return;
    // Android's alarm clock takes the instant itself; no timezone is involved.
    await _live.invokeMethod<void>('alarm', {
      'at': at.millisecondsSinceEpoch,
      'title': 'Rest over',
      'text': exercise.isEmpty ? 'Time for the next set.' : 'Next set: $exercise',
    });
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
    if (_ready) _alarm(() => _live.invokeMethod<void>('cancelAlarm'));
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
    unawaited(_askOnce().catchError((_) {})); // while the app is open, so the permission prompt can appear
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
