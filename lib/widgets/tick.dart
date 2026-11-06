import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds its child once per second, aligned to wall-clock seconds.
class TickBuilder extends StatefulWidget {
  final WidgetBuilder builder;
  const TickBuilder({super.key, required this.builder});

  @override
  State<TickBuilder> createState() => _TickBuilderState();
}

class _TickBuilderState extends State<TickBuilder> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final ms = 1000 - DateTime.now().millisecond;
    _timer = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
