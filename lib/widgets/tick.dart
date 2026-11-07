import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds its child once per second, aligned to wall-clock seconds, or to whole seconds after [anchor] when
/// given. A rest timer counts from its own start, so ticking on its boundaries shows each new second as it
/// begins (in step with Android's status-bar chip) instead of up to a second late.
class TickBuilder extends StatefulWidget {
  final WidgetBuilder builder;
  final DateTime? anchor;
  const TickBuilder({super.key, required this.builder, this.anchor});

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
    final anchor = widget.anchor;
    final now = DateTime.now();
    final phase = anchor == null ? now.millisecond : now.difference(anchor).inMilliseconds % 1000;
    // A few milliseconds late, so the second has certainly turned when the value is read.
    final ms = 1000 - phase + 5;
    _timer = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void didUpdateWidget(covariant TickBuilder old) {
    super.didUpdateWidget(old);
    if (old.anchor != widget.anchor) {
      _timer?.cancel();
      _schedule();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
