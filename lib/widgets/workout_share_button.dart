import 'package:flutter/material.dart';

import '../services/workout_share.dart';
import '../store.dart';
import 'common.dart';

class WorkoutShareButton extends StatefulWidget {
  final FinishSummary summary;
  const WorkoutShareButton({super.key, required this.summary});

  @override
  State<WorkoutShareButton> createState() => _WorkoutShareButtonState();
}

class _WorkoutShareButtonState extends State<WorkoutShareButton> {
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await WorkoutSharing.share(widget.summary, Theme.of(context));
    } catch (_) {
      if (mounted) notify(context, 'Could not open sharing. Try again.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!WorkoutSharing.available) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Share workout',
      onPressed: _sharing ? null : _share,
      icon: _sharing
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.share_outlined),
    );
  }
}
