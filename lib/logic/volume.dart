/// Port of volume_accounting.py: conventional sets and protocol groups are
/// separate units; primary tags are direct work, secondary tags indirect.
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

  VolumeMetrics scaled(double factor) => VolumeMetrics()
    ..conventional = conventional * factor
    ..protocolGroups = protocolGroups * factor
    ..completeGroups = completeGroups * factor
    ..partialGroups = partialGroups * factor
    ..activations = activations * factor
    ..continuations = continuations * factor
    ..clusterFragments = clusterFragments * factor
    ..unclassified = unclassified * factor;

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
  }
  return report;
}
