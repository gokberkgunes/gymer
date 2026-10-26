"""Explicit recovery prescriptions; defaults are policy choices, not physiology."""

import math
import progression

FIELDS = ("prescription_kind", "source_method", "reference_session_id", "reference_weight",
          "reference_weight_unit", "prescribed_weight", "target_reps", "deload_load_percent",
          "deload_volume_percent", "original_work_count")


def metadata(row):
    return {key: "" if row.get(key) is None else str(row.get(key, "")).strip() for key in FIELDS}


def is_recovery(row):
    return str(row.get("prescription_kind", "")).startswith("deload")


def settings(config):
    policy = str(config.get("deload_policy") or "recovery").strip()
    if policy not in {"recovery", "manual"}:
        raise ValueError("Deload policy must be recovery or manual.")
    result = {"deload_policy": policy}
    for key, default in (("deload_load_percent", 90), ("deload_volume_percent", 50)):
        raw = config.get(key)
        try:
            number = float(default if raw is None or str(raw).strip() == "" else raw)
        except (TypeError, ValueError):
            raise ValueError("Deload load and volume percentages must be numbers from 1 to 100.") from None
        if not math.isfinite(number) or not 1 <= number <= 100:
            raise ValueError("Deload load and volume percentages must be numbers from 1 to 100.")
        result[key] = progression.format_weight(number)
    return result


def effort_error(config):
    if settings(config)["deload_policy"] == "manual" or str(config.get("deload_microcycles", "1")) == "0":
        return None
    try:
        target, build = float(config.get("deload_rir", 4)), float(config.get("end_rir", 1))
    except (TypeError, ValueError):
        return "Set a valid deload RIR target."
    if not math.isfinite(target) or not math.isfinite(build) or round(target) < 1 or round(target) <= round(build):
        return "Recovery deload RIR must be at least 1 and higher than final-build RIR."
    return None


def recovery_count(method, working_count, percent):
    if working_count <= 0:
        return 0
    if method in progression.METHODS_WITH_ACTIVATION or method == "Cluster":
        return 1
    return max(1, math.floor(working_count * float(percent) / 100))


def recovery_weight(reference, *, percent, unit, step):
    """Round down on the reference lattice; never turn a reduction into a rise."""
    if reference <= 0:
        return ""
    raw = reference * float(percent) / 100
    drops = math.ceil((reference - raw) / step - 1e-9)
    candidate = reference - max(0, drops) * step
    return progression.format_weight(candidate) if candidate > 0 else ""


def summary(row):
    if not is_recovery(row):
        return ""
    if row.get("prescription_kind") == "deload_manual":
        return "Manual deload: choose recovery volume, load and effort; automatic progression is paused."
    text = f"Recovery from {row.get('source_method') or 'the Build plan'}; {row.get('planned_work_count', '?')} planned recovery sets (Build plan: {row.get('original_work_count', '?')} segments). "
    text += f"Target {row.get('target_reps') or '?'} reps at {row.get('target_rir') or '?'} RIR. "
    if row.get("prescribed_weight"):
        text += f"Load hint {row['prescribed_weight']} {row.get('weight_unit', 'kg')} from the fixed pre-deload reference."
    else:
        text += "Choose the load manually; no automatic load hint is available."
    return text
