/// Port of volume_accounting.py: conventional sets and protocol groups are
/// separate units; primary tags are direct work, secondary tags indirect.
///
/// Special methods are also given an estimate in straight-set equivalents ([VolumeMetrics.equivalent]) so they
/// can sit on the same weekly scale:
/// - Activation set: 1. It is an ordinary set taken close to failure.
/// - Each myo-set, rest-pause segment or drop after it: [continuationSets] (0.5). Trials that matched one
///   drop-set group of an opening set plus three or four drops against three straight sets found similar
///   growth, and the usual rule for myo-reps (an activation set plus four or five mini-sets for about three
///   straight sets) gives the same half set per segment.
/// - One whole group counts at most [groupSetCap] (3): nothing shows that piling on more segments keeps adding.
/// - A cluster group (all its fragments): 1, scaled by the fragments completed. With sets, reps and effort
///   matched, cluster sets grew muscle like straight sets, set for set.
/// These are estimates from small studies, not measurements.
library;

import 'methods.dart';

class VolumeMetrics {
  double conventional = 0;
  double protocolGroups = 0;
  double completeGroups = 0;
  double partialGroups = 0;
  double activations = 0;
  double continuations = 0;
  double clusterFragments = 0;
  double unclassified = 0;

  /// Special-method work in straight-set equivalents; see the library comment.
  double equivalent = 0;

  /// Everything on one scale: straight sets plus the estimate for special methods.
  double get sets => conventional + equivalent;

  VolumeMetrics scaled(double factor) => VolumeMetrics()
    ..conventional = conventional * factor
    ..protocolGroups = protocolGroups * factor
    ..completeGroups = completeGroups * factor
    ..partialGroups = partialGroups * factor
    ..activations = activations * factor
    ..continuations = continuations * factor
    ..clusterFragments = clusterFragments * factor
    ..unclassified = unclassified * factor
    ..equivalent = equivalent * factor;

  bool get hasProtocols => protocolGroups + activations + continuations + clusterFragments + unclassified > 0;

  String describe() {
    String n(double v) => v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    final parts = [
      for (final (v, label) in [
        (conventional, 'conventional sets'),
        (protocolGroups, 'protocol groups'),
        (activations, 'activations'),
        (continuations, 'continuations'),
        (clusterFragments, 'cluster fragments'),
        (unclassified, 'unclassified segments'),
      ])
        if (v > 0) '${n(v)} ${v == 1 ? label.substring(0, label.length - 1) : label}',
    ];
    return parts.isEmpty ? '0 conventional sets' : parts.join(' · ');
  }
}

/// Straight-set equivalents of one continuation segment, and the most one protocol group can count.
const continuationSets = 0.5;
const groupSetCap = 3.0;

class VolumeRow {
  final String scope;
  final String type;
  final bool active;
  final bool groupStart;
  final List<String> primary;
  final List<String> secondary;

  const VolumeRow({
    required this.scope,
    required this.type,
    required this.active,
    this.groupStart = false,
    required this.primary,
    required this.secondary,
  });
}

class VolumeReport {
  final totals = VolumeMetrics();
  final direct = <String, VolumeMetrics>{};
  final indirect = <String, VolumeMetrics>{};
}

VolumeReport summarizeVolume(List<VolumeRow> rows) {
  final report = VolumeReport();
  void add(void Function(VolumeMetrics m) bump, Iterable<VolumeRow> members) {
    bump(report.totals);
    final primary = {for (final r in members) ...r.primary};
    final secondary = {for (final r in members) ...r.secondary}..removeAll(primary);
    for (final t in primary) {
      bump(report.direct.putIfAbsent(t, VolumeMetrics.new));
    }
    for (final t in secondary) {
      bump(report.indirect.putIfAbsent(t, VolumeMetrics.new));
    }
  }

  final groups = <List<(VolumeRow, String)>>[];
  final current = <String, List<(VolumeRow, String)>>{};
  for (final row in rows) {
    final role = setRole(row.type);
    if (role == 'warmup') continue;
    if (row.groupStart) current.remove(row.scope);
    if (row.active) {
      add(
        (m) => switch (role) {
          'conventional' => m.conventional++,
          'anchor' => m.activations++,
          'continuation' => m.continuations++,
          'cluster_fragment' => m.clusterFragments++,
          _ => m.unclassified++,
        },
        [row],
      );
    }
    if (role == 'anchor' || role == 'continuation' || role == 'cluster_fragment') {
      var group = current[row.scope];
      if (group == null || role == 'anchor' || (role == 'cluster_fragment' && row.groupStart)) {
        group = [];
        groups.add(group);
        current[row.scope] = group;
      }
      group.add((row, role));
    } else {
      current.remove(row.scope);
    }
  }
  for (final group in groups) {
    final performed = [
      for (final (r, _) in group)
        if (r.active) r,
    ];
    if (performed.isEmpty) continue;
    final roles = [for (final (_, role) in group) role];
    final structured =
        (roles.first == 'anchor' && roles.length > 1 && roles.skip(1).every((r) => r == 'continuation')) ||
        roles.every((r) => r == 'cluster_fragment');
    final complete = structured && performed.length == group.length;
    add((m) => m.protocolGroups++, performed);
    add((m) => complete ? m.completeGroups++ : m.partialGroups++, performed);
    final done = [
      for (final (r, role) in group)
        if (r.active) role,
    ];
    final worth = roles.every((r) => r == 'cluster_fragment')
        ? performed.length / group.length
        : (done.where((r) => r == 'anchor').length + continuationSets * done.where((r) => r != 'anchor').length).clamp(
            0.0,
            groupSetCap,
          );
    add((m) => m.equivalent += worth, performed);
  }
  return report;
}
