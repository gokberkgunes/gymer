"""Separate recorded work categories without inventing set-equivalence credit."""

import uuid
import math

FIELDS = ("protocol_group_start", "group_id", "segment_role", "group_planned_count", "primary_muscles_snapshot",
          "secondary_muscles_snapshot", "muscle_metadata_recorded")
ROLES = {"conventional", "anchor", "continuation", "cluster_fragment", "warmup", "unknown"}
METRICS = ("conventional_sets", "protocol_groups", "complete_protocol_groups", "partial_protocol_groups",
           "activations", "continuations", "cluster_fragments", "unclassified", "working_segments")


def metadata(row):
    return {key: "" if row.get(key) is None else str(row.get(key, "")).strip() for key in FIELDS}


def role(row):
    kind = str(row.get("set_type") or "Normal").strip().casefold()
    if kind in {"warm-up", "warmup", "warm up"}: return "warmup"
    if kind in {"normal", "straight", "straight (normal)", "top set", "back-off", "amrap"}: return "conventional"
    if kind == "activation": return "anchor"
    if kind in {"myo-set", "myo-reps", "rest-pause", "drop set", "mechanical drop set", "myo-rep match"}: return "continuation"
    if kind in {"cluster", "cluster set"}: return "cluster_fragment"
    return "unknown"


def assign_groups(rows):
    """Assign IDs only to new work; retain existing IDs, roles and planned sizes."""
    current = {}
    last_number = {}
    for row in rows:
        scope = (row.get("volume_scope") or row.get("session_id", ""), row.get("exercise_name", "").casefold())
        number = row.get("set_number")
        if number is not None:
            if scope in last_number and int(number) <= last_number[scope] and not row.get("group_id"):
                current.pop(scope, None)  # A new template placement starts a new cluster group.
            last_number[scope] = int(number)
        recorded_role = row.get("segment_role") or role(row)
        row["segment_role"] = recorded_role
        if recorded_role == "warmup":
            continue
        if row.get("protocol_group_start") == "1":
            current.pop(scope, None)
        if not row.get("group_id"):
            if recorded_role in {"continuation", "cluster_fragment"} and current.get(scope):
                row["group_id"] = current[scope]
            else:
                row["group_id"] = uuid.uuid4().hex
        if recorded_role in {"anchor", "continuation", "cluster_fragment"}:
            current[scope] = row["group_id"]
        else:
            current.pop(scope, None)
    groups = {}
    for row in rows:
        if row.get("group_id"):
            groups.setdefault((row.get("volume_scope") or row.get("session_id", ""), row.get("exercise_name", "").casefold(), row["group_id"]), []).append(row)
    for group in groups.values():
        known = [int(row["group_planned_count"]) for row in group if str(row.get("group_planned_count", "")).isdigit()]
        # New group sizes come from the actual plan. Removing rows never shrinks a snapshot.
        count = max([len(group)] + known)
        for row in group: row["group_planned_count"] = str(count)
    return rows


def empty_metrics():
    return dict.fromkeys(METRICS, 0)


def completed(row):
    return str(row.get("completed", "1")).casefold() not in {"0", "false", "no", "off"}


def summarize(rows, *, planned=False):
    totals, direct, indirect = empty_metrics(), {}, {}
    protocol_groups, current, counters = {}, {}, {}
    inferred = legacy_tags = 0

    def increment(key, members):
        totals[key] += 1
        primary = set().union(*(set(row.get("_primary", [])) for row in members))
        secondary = set().union(*(set(row.get("_secondary", [])) for row in members)) - primary
        for tag in primary: direct.setdefault(tag, empty_metrics())[key] += 1
        for tag in secondary: indirect.setdefault(tag, empty_metrics())[key] += 1

    for row in rows:
        observed_role = role(row)
        recorded = row.get("segment_role") or observed_role
        if recorded != observed_role: recorded = "unknown"
        if observed_role == "warmup": continue
        scope = (row.get("volume_scope") or row.get("session_id", ""), row.get("exercise_name", "").casefold())
        if row.get("protocol_group_start") == "1":
            current.pop(scope, None)
        active = planned or completed(row)
        if active:
            inferred += int(not row.get("group_id") or not row.get("segment_role"))
            legacy_tags += int(row.get("muscle_metadata_recorded") != "1")
            increment("working_segments", [row])
            category = {"conventional": "conventional_sets", "anchor": "activations", "continuation": "continuations",
                        "cluster_fragment": "cluster_fragments"}.get(recorded, "unclassified")
            increment(category, [row])
        if recorded in {"anchor", "continuation", "cluster_fragment"}:
            group_id = row.get("group_id")
            if not group_id:
                if recorded == "anchor" or scope not in current:
                    counters[scope] = counters.get(scope, 0) + 1
                    current[scope] = f"inferred-{counters[scope]}"
                group_id = current[scope]
            else:
                current[scope] = group_id
            protocol_groups.setdefault((*scope, group_id), []).append((row, recorded, active))
        else:
            current.pop(scope, None)

    for group in protocol_groups.values():
        performed = [row for row, _, active in group if active]
        if not performed: continue
        increment("protocol_groups", performed)
        roles = [recorded for _, recorded, _ in group]
        counts = {str(row.get("group_planned_count") or row.get("planned_work_count") or "") for row, _, _ in group}
        known_size = len(counts) == 1 and next(iter(counts)).isdigit() and int(next(iter(counts))) == len(group)
        structure = (roles.count("anchor") == 1 and roles[0] == "anchor" and all(value == "continuation" for value in roles[1:]) and len(group) > 1) or all(value == "cluster_fragment" for value in roles)
        complete = all(active for _, _, active in group) and known_size and structure
        increment("complete_protocol_groups" if complete else "partial_protocol_groups", performed)
    return {"totals": totals, "direct": direct, "indirect": indirect,
            "inferred_group_rows": inferred, "legacy_metadata_rows": legacy_tags}


def scaled(metrics, days):
    if not math.isfinite(float(days)) or float(days) <= 0: raise ValueError("Reporting period must be finite and positive.")
    return {key: value * 7 / float(days) for key, value in metrics.items()}


def describe(metrics):
    labels = (("conventional_sets", "conventional sets"), ("protocol_groups", "protocol groups"),
              ("activations", "activations"), ("continuations", "continuations"),
              ("cluster_fragments", "cluster fragments"), ("unclassified", "unclassified segments"))
    parts = [f"{metrics.get(key, 0):.1f}".rstrip("0").rstrip(".") + " " + (label[:-1] if metrics.get(key) == 1 else label)
             for key, label in labels if metrics.get(key)]
    return " · ".join(parts) if parts else "0 conventional sets"


def context_summary(row):
    recorded = row.get("segment_role")
    text = f"Recorded role: {recorded.replace('_', ' ')}" if recorded else f"Inferred role: {role(row).replace('_', ' ')}"
    if row.get("group_planned_count"):
        text += f" · {row['group_planned_count']} planned group segments"
    if row.get("protocol_group_start") == "1":
        text += " · New protocol group starts here"
    return text
