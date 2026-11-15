import 'dart:io';

import 'package:flutter/material.dart';

import 'screens/home.dart';
import 'services/app_dir.dart';
import 'services/platform_alerts.dart';
import 'models.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await appDataDirectory();
  final alerts = PlatformAlerts();
  // Notifications are optional: a failure here must never keep the app on the splash screen.
  try {
    await alerts.init();
  } catch (e) {
    debugPrint('gymer: notifications unavailable: $e');
  }
  final store = AppStore(file: File('${dir.path}/gymer.json'), alerts: alerts);
  await store.load();
  runApp(GymerApp(store: store));
}

class GymerApp extends StatefulWidget {
  final AppStore store;
  const GymerApp({super.key, required this.store});

  @override
  State<GymerApp> createState() => _GymerAppState();
}

class _GymerAppState extends State<GymerApp> {
  late final AppLifecycleListener _lifecycle;
  final _themes = <Object, ThemeData>{};

  ThemeData _theme(Brightness b, Settings s) => _themes.putIfAbsent(themeKey(b, s), () => buildTheme(b, s));

  /// What the app root depends on. The root rebuilds only when this changes, not on every keystroke or set:
  /// screens listen to the store themselves through [StoreScope].
  Object _rootKey() {
    final s = widget.store.settings;
    return (themeKey(Brightness.light, s), s.themeMode, s.uiScale, s.fontScale);
  }

  late Object _root = _rootKey();

  void _onStore() {
    final key = _rootKey();
    if (key != _root) setState(() => _root = key);
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    final alerts = widget.store.alerts;
    _lifecycle = AppLifecycleListener(
      onPause: widget.store.flush,
      onDetach: widget.store.flush,
      // The status-bar timer only shows while Gymer is in the background.
      onShow: () => alerts.setForeground(true),
      onHide: () => alerts.setForeground(false),
    );
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: widget.store,
      child: Builder(
        builder: (context) {
          final s = widget.store.settings;
          return MaterialApp(
            title: 'Gymer',
            debugShowCheckedModeBanner: false,
            theme: _theme(Brightness.light, s),
            darkTheme: _theme(Brightness.dark, s),
            themeMode: switch (s.themeMode) {
              'light' => ThemeMode.light,
              'dark' => ThemeMode.dark,
              _ => ThemeMode.system,
            },
            builder: (context, child) => _Scaled(uiScale: s.uiScale, fontScale: s.fontScale, child: child!),
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}

/// Interface scale shrinks or grows the whole layout (like Android display
/// size); font scale multiplies on top of the system text size.
class _Scaled extends StatelessWidget {
  final double uiScale;
  final double fontScale;
  final Widget child;
  const _Scaled({required this.uiScale, required this.fontScale, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final k = uiScale.clamp(0.7, 1.2);
    final data = mq.copyWith(
      size: mq.size / k,
      padding: mq.padding / k,
      viewPadding: mq.viewPadding / k,
      viewInsets: mq.viewInsets / k,
      textScaler: _MultipliedScaler(mq.textScaler, fontScale.clamp(0.8, 1.4)),
    );
    if (k == 1.0) return MediaQuery(data: data, child: child);
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: data.size,
        child: MediaQuery(data: data, child: child),
      ),
    );
  }
}

class _MultipliedScaler extends TextScaler {
  final TextScaler base;
  final double factor;
  const _MultipliedScaler(this.base, this.factor);

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is _MultipliedScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
