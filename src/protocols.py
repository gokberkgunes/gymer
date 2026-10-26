"""Recorded protocol context; blanks mean unknown, never inferred observations."""

import set_context

FIELDS = ("planned_work_count", "setup", "stop_reason", "actual_rest_seconds", "context_override", *set_context.OPTIONS)
STOP_REASONS = {
    "": "Unknown / not recorded",
    "target_rir": "Chosen RIR target",
    "technical_failure": "Technical failure",
    "muscular_failure": "Muscular failure",
    "safety_limit": "Safety limit / discomfort",
    "other": "Other stop",
}


def metadata(row):
    return {key: "" if row.get(key) is None else str(row.get(key, "")).strip() for key in FIELDS}


def summary(row):
    parts = []
    if row.get("protocol_group_start") == "1":
        parts.append("New protocol group starts here")
    if row.get("planned_work_count"):
        parts.append(f"Planned segments: {row['planned_work_count']}")
    if set_context.summary(row):
        parts.append(set_context.summary(row))
    if row.get("stop_reason"):
        parts.append(f"Stop: {STOP_REASONS.get(row['stop_reason'], row['stop_reason'])}")
    if row.get("rest_seconds") not in {None, ""}:
        parts.append(f"Planned rest after: {row['rest_seconds']}s")
    if row.get("actual_rest_seconds") not in {None, ""}:
        parts.append(f"Actual rest after: {row['actual_rest_seconds']}s")
    return " · ".join(parts)
