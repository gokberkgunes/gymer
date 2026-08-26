import math
import statistics


TARGET_REPS = 8
LOW_REP_LIMIT = 8
HIGH_REP_LIMIT = 12
CALIBRATION_TARGET_REPS = 10
STRAIGHT_SET_TYPES = {"normal", "straight", "straight (normal)"}

METHODS_WITH_ACTIVATION = {
    "Myo-Reps",
    "Rest-Pause",
    "Drop Set",
    "Mechanical Drop Set",
    "Myo-Rep Match",
}
SAME_LOAD_METHODS = {
    "AMRAP",
    "Myo-Reps",
    "Rest-Pause",
    "Mechanical Drop Set",
    "Cluster",
    "Myo-Rep Match",
}
MINI_SET_MIN_REPS = 2
MINI_SET_MAX_REPS = 4
CLUSTER_LOW_REPS = 2
CLUSTER_HIGH_REPS = 5
CLUSTER_TARGET_REPS = 3
DEFAULT_DROP_RATIO = 0.75


def wathan_percent_1rm(reps):
    """Estimated percentage of 1RM for a repetition maximum."""
    reps = float(reps)
    if reps <= 1:
        return 100.0
    return 48.8 + 53.8 * math.exp(-0.075 * reps)


def _number(value):
    try:
        value = float(str(value or "").strip())
    except (TypeError, ValueError):
        return None
    return value if math.isfinite(value) else None


def _round_half_up(value, step):
    if step <= 0:
        return value
    return math.floor(value / step + 0.5) * step


def practical_weight_step(weight, unit, configured_step=None):
    """Return the exercise's available load jump, with a legacy fallback."""
    if configured_step is not None:
        try:
            configured_step = float(configured_step)
        except (TypeError, ValueError):
            configured_step = None
        if configured_step is not None and math.isfinite(configured_step) and configured_step > 0:
            return configured_step

    weight = max(0.0, float(weight or 0))
    unit = str(unit or "kg").strip().lower()
    if unit == "lb":
        return 2.5 if weight < 20 else 5.0
    return 1.0 if weight < 10 else 2.5


def practical_weight(value, unit, reference_weight=None, configured_step=None):
    """Round a calculator result to a load reachable from the current load."""
    value = float(value)
    anchor = 0.0 if reference_weight is None else float(reference_weight)
    step = practical_weight_step(anchor, unit, configured_step=configured_step)
    delta = value - anchor
    return max(0.0, anchor + _round_half_up(delta, step))


def format_weight(value):
    value = float(value)
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return f"{value:.2f}".rstrip("0").rstrip(".")


def estimated_one_rm(weight, reps, rir=0):
    """Estimate 1RM using the Wathan curve and effective reps (reps + RIR)."""
    weight = _number(weight)
    reps = _number(reps)
    rir = _number(rir)
    if weight is None or reps is None or weight <= 0 or reps <= 0:
        return None
    if rir is None or rir < 0:
        rir = 0.0
    effective_rm = max(1.0, reps + rir)
    percent = wathan_percent_1rm(effective_rm) / 100.0
    if percent <= 0:
        return None
    return weight / percent


def calibration_recommendation(
    weight, reps, rir, *, target_rir, unit="kg", weight_increment=None
):
    """Suggest a mid-window Straight calibration load from a prior straight set."""
    weight = _number(weight)
    reps = _number(reps)
    prior_rir = _number(rir)
    target_rir = _number(target_rir)
    if weight is None or reps is None or weight <= 0 or reps <= 0:
        return None
    if prior_rir is None or prior_rir < 0:
        prior_rir = 0.0
    if target_rir is None or target_rir < 0:
        target_rir = 0.0

    one_rm = estimated_one_rm(weight, reps, prior_rir)
    if one_rm is None:
        return None
    effective_rm = CALIBRATION_TARGET_REPS + target_rir
    raw = one_rm * (wathan_percent_1rm(effective_rm) / 100.0)
    suggested = practical_weight(
        raw, unit, reference_weight=weight, configured_step=weight_increment
    )
    return {
        "weight": suggested,
        "weight_text": format_weight(suggested),
        "target_reps": CALIBRATION_TARGET_REPS,
        "target_rir": target_rir,
        "estimated_1rm": one_rm,
        "uses_rir": True,
    }


def _canonical_method(method):
    key = str(method or "Straight").strip().casefold()
    aliases = {
        "": "Straight",
        "normal": "Straight",
        "straight (normal)": "Straight",
        "straight": "Straight",
        "amrap": "AMRAP",
        "myoreps": "Myo-Reps",
        "myo reps": "Myo-Reps",
        "myo-reps": "Myo-Reps",
        "rest-pause": "Rest-Pause",
        "drop set": "Drop Set",
        "mechanical drop set": "Mechanical Drop Set",
        "cluster": "Cluster",
        "cluster set": "Cluster",
        "myo-rep match": "Myo-Rep Match",
        "myo rep match": "Myo-Rep Match",
    }
    return aliases.get(key, str(method or "Straight").strip() or "Straight")


def _set_type(row):
    value = str((row or {}).get("set_type", "Normal") or "Normal").strip()
    if value.casefold() in STRAIGHT_SET_TYPES:
        return "Normal"
    return value


def _completed(row):
    value = (row or {}).get("completed", True)
    if isinstance(value, bool):
        return value
    return str(value or "1").strip().casefold() not in {"0", "false", "no", "off"}


def _warmup(row):
    return _set_type(row).casefold() in {"warm-up", "warmup", "warm up"}


def _anchor_type(method):
    method = _canonical_method(method)
    if method == "Straight":
        return "Normal"
    if method == "AMRAP":
        return "AMRAP"
    if method == "Cluster":
        return "Cluster Set"
    if method in METHODS_WITH_ACTIVATION:
        return "Activation"
    return "Normal"


def method_calibration_recommendation(
    weight,
    reps,
    rir=0,
    *,
    method="Straight",
    target_rir=0,
    unit="kg",
    weight_increment=None,
):
    """Return a calibration load appropriate to the selected exercise method."""
    method = _canonical_method(method)
    if method == "Straight":
        return calibration_recommendation(
            weight,
            reps,
            rir,
            target_rir=target_rir,
            unit=unit,
            weight_increment=weight_increment,
        )

    weight_value = _number(weight)
    reps_value = _number(reps)
    if weight_value is None or reps_value is None or weight_value <= 0 or reps_value <= 0:
        return None

    if method == "Cluster":
        # Cluster mini-rests break the ordinary reps-to-1RM relationship. Reuse
        # method-specific load history, but do not pretend a cluster triple is a 3RM.
        suggested = practical_weight(
            weight_value,
            unit,
            reference_weight=weight_value,
            configured_step=weight_increment,
        )
        return {
            "weight": suggested,
            "weight_text": format_weight(suggested),
            "target_reps": CLUSTER_TARGET_REPS,
            "target_rir": None,
            "estimated_1rm": None,
            "uses_rir": False,
        }

    # AMRAP and activation-based methods treat the anchor as an all-out/near-
    # failure strength observation. If the source row was a Straight set, its
    # recorded RIR is still useful when estimating the underlying 1RM.
    source_rir = _number(rir)
    if source_rir is None or source_rir < 0:
        source_rir = 0.0
    one_rm = estimated_one_rm(weight_value, reps_value, source_rir)
    if one_rm is None:
        return None
    raw = one_rm * (wathan_percent_1rm(CALIBRATION_TARGET_REPS) / 100.0)
    suggested = practical_weight(
        raw,
        unit,
        reference_weight=weight_value,
        configured_step=weight_increment,
    )
    return {
        "weight": suggested,
        "weight_text": format_weight(suggested),
        "target_reps": CALIBRATION_TARGET_REPS,
        "target_rir": None,
        "estimated_1rm": one_rm,
        "uses_rir": False,
    }


def _usable_straight_sets(rows):
    usable = []
    for row in rows or []:
        if not _completed(row):
            continue
        set_type = _set_type(row).casefold()
        if set_type not in STRAIGHT_SET_TYPES:
            continue
        weight = _number(row.get("weight"))
        reps = _number(row.get("reps"))
        rir = _number(row.get("rir"))
        if weight is None or reps is None or weight <= 0 or reps <= 0:
            continue
        usable.append({"weight": weight, "reps": reps, "rir": rir})
    return usable


def progression_recommendation(
    rows, *, target_rir, unit="kg", phase="Build", weight_increment=None
):
    """Straight-method 8-12 double progression with RIR-aware Wathan sizing."""
    sets = _usable_straight_sets(rows)
    if not sets:
        return None

    target_rir_value = _number(target_rir)
    if target_rir_value is None or target_rir_value < 0:
        target_rir_value = 0.0

    median_weight = statistics.median(item["weight"] for item in sets)
    median_reps = statistics.median(item["reps"] for item in sets)
    valid_rirs = [item["rir"] for item in sets if item["rir"] is not None and item["rir"] >= 0]
    median_rir = statistics.median(valid_rirs) if valid_rirs else None

    estimates = []
    for item in sets:
        estimate = estimated_one_rm(
            item["weight"], item["reps"], item["rir"] if item["rir"] is not None else 0
        )
        if estimate is not None:
            estimates.append(estimate)
    estimated_1rm = statistics.median(estimates) if estimates else None

    step = practical_weight_step(median_weight, unit, configured_step=weight_increment)
    current_practical = practical_weight(
        median_weight, unit, median_weight, configured_step=step
    )
    phase_name = str(phase or "Build").strip().casefold()

    if phase_name == "deload":
        raw = median_weight * 0.90
        suggested = practical_weight(raw, unit, median_weight, configured_step=step)
        if current_practical > step:
            suggested = min(suggested, current_practical - step)
        suggested = max(step, suggested)
        action = "deload"
        reason = "Deload week: reduce the load and keep several reps in reserve."
        target_reps = 8
    elif median_reps > HIGH_REP_LIMIT:
        target_effective_rm = TARGET_REPS + target_rir_value
        raw = (
            estimated_1rm * (wathan_percent_1rm(target_effective_rm) / 100.0)
            if estimated_1rm is not None
            else current_practical + step
        )
        suggested = practical_weight(raw, unit, median_weight, configured_step=step)
        if raw > median_weight and suggested <= current_practical:
            suggested = current_practical + step
        action = "increase"
        reason = (
            f"Last session was about {median_reps:g} reps per straight set, above "
            f"the {LOW_REP_LIMIT}-{HIGH_REP_LIMIT} rep window."
        )
        target_reps = TARGET_REPS
    elif median_reps < LOW_REP_LIMIT:
        target_effective_rm = TARGET_REPS + target_rir_value
        raw = (
            estimated_1rm * (wathan_percent_1rm(target_effective_rm) / 100.0)
            if estimated_1rm is not None
            else max(step, current_practical - step)
        )
        suggested = practical_weight(raw, unit, median_weight, configured_step=step)
        if raw < median_weight and suggested >= current_practical:
            suggested = max(step, current_practical - step)
        action = "decrease"
        reason = (
            f"Last session was about {median_reps:g} reps per straight set, below "
            f"the {LOW_REP_LIMIT}-{HIGH_REP_LIMIT} rep window."
        )
        target_reps = TARGET_REPS
    else:
        suggested = current_practical
        action = "hold"
        reason = (
            f"Last session was about {median_reps:g} reps per straight set, inside "
            f"the {LOW_REP_LIMIT}-{HIGH_REP_LIMIT} rep window."
        )
        target_reps = TARGET_REPS

    return {
        "method": "Straight",
        "action": action,
        "weight": suggested,
        "weight_text": format_weight(suggested),
        "target_reps": int(target_reps),
        "target_rir": target_rir_value,
        "previous_weight": median_weight,
        "previous_reps": median_reps,
        "previous_rir": median_rir,
        "estimated_1rm": estimated_1rm,
        "step": step,
        "reason": reason,
        "set_count": len(sets),
        "uses_rir": True,
        "continuation_weights": [],
    }


def _valid_anchor(rows, method):
    anchor_type = _anchor_type(method).casefold()
    for row in rows or []:
        if not _completed(row) or _warmup(row):
            continue
        if _set_type(row).casefold() != anchor_type:
            continue
        weight = _number(row.get("weight"))
        reps = _number(row.get("reps"))
        if weight is not None and reps is not None and weight > 0 and reps > 0:
            return row, weight, reps
    return None, None, None


def _continuations(rows, anchor_row):
    found = False
    output = []
    for row in rows or []:
        if row is anchor_row:
            found = True
            continue
        if not found or _warmup(row):
            continue
        output.append(row)
    return output


def _quality_gate(method, anchor_reps, continuation_rows):
    method = _canonical_method(method)
    if method == "AMRAP":
        return True, ""
    if not continuation_rows:
        return True, ""
    if any(not _completed(row) for row in continuation_rows):
        return False, "not all continuation segments were completed"

    reps = [_number(row.get("reps")) for row in continuation_rows]
    if method in {"Myo-Reps", "Rest-Pause"}:
        if any(value is None or value < MINI_SET_MIN_REPS for value in reps):
            return False, f"a continuation segment fell below {MINI_SET_MIN_REPS} reps"
    elif method == "Myo-Rep Match":
        if any(value is None or value < anchor_reps for value in reps):
            return False, "not every match set reached the activation-set rep target"
    return True, ""


def _drop_weights(anchor_weight, continuation_rows, suggested_anchor, unit, step):
    weights = []
    previous_ratio = DEFAULT_DROP_RATIO
    for index, row in enumerate(continuation_rows):
        actual = _number(row.get("weight"))
        if actual is not None and actual > 0 and anchor_weight > 0:
            ratio = actual / anchor_weight
            if 0.20 <= ratio < 1.0:
                previous_ratio = ratio
            else:
                ratio = DEFAULT_DROP_RATIO ** (index + 1)
        else:
            ratio = DEFAULT_DROP_RATIO ** (index + 1)
        raw = suggested_anchor * ratio
        reference = actual if actual is not None and actual > 0 else raw
        value = practical_weight(raw, unit, reference_weight=reference, configured_step=step)
        weights.append(value)
    return weights


def method_progression_recommendation(
    rows,
    *,
    method="Straight",
    target_rir=0,
    unit="kg",
    phase="Build",
    weight_increment=None,
):
    """Dispatch progression according to the exercise-level Training Method."""
    method = _canonical_method(method)
    if method == "Straight":
        return progression_recommendation(
            rows,
            target_rir=target_rir,
            unit=unit,
            phase=phase,
            weight_increment=weight_increment,
        )

    anchor_row, anchor_weight, anchor_reps = _valid_anchor(rows, method)
    if anchor_row is None:
        return None

    step = practical_weight_step(anchor_weight, unit, configured_step=weight_increment)
    current = practical_weight(anchor_weight, unit, anchor_weight, configured_step=step)
    phase_name = str(phase or "Build").strip().casefold()
    continuations = _continuations(rows, anchor_row)

    if method == "Cluster":
        completed_rows = [
            row for row in rows or []
            if not _warmup(row) and _set_type(row).casefold() == "cluster set" and _completed(row)
        ]
        reps_values = [_number(row.get("reps")) for row in completed_rows]
        reps_values = [value for value in reps_values if value is not None and value > 0]
        median_reps = statistics.median(reps_values) if reps_values else anchor_reps
        all_completed = all(
            _completed(row) for row in rows or [] if not _warmup(row)
        )
        if phase_name == "deload":
            raw = anchor_weight * 0.90
            suggested = practical_weight(raw, unit, anchor_weight, configured_step=step)
            if current > step:
                suggested = min(suggested, current - step)
            action = "deload"
            reason = "Deload week: reduce cluster load; intra-set rests make e1RM conversion inappropriate."
        elif not all_completed:
            suggested = current
            action = "hold"
            reason = "Hold cluster load because not all planned clusters were completed."
        elif median_reps > CLUSTER_HIGH_REPS:
            suggested = current + step
            action = "increase"
            reason = f"Cluster reps rose above the {CLUSTER_LOW_REPS}-{CLUSTER_HIGH_REPS} working window."
        elif median_reps < CLUSTER_LOW_REPS:
            suggested = max(step, current - step)
            action = "decrease"
            reason = f"Cluster reps fell below the {CLUSTER_LOW_REPS}-{CLUSTER_HIGH_REPS} working window."
        else:
            suggested = current
            action = "hold"
            reason = f"Cluster reps remain inside the {CLUSTER_LOW_REPS}-{CLUSTER_HIGH_REPS} working window."
        return {
            "method": method,
            "action": action,
            "weight": suggested,
            "weight_text": format_weight(suggested),
            "target_reps": CLUSTER_TARGET_REPS,
            "target_rir": None,
            "previous_weight": anchor_weight,
            "previous_reps": median_reps,
            "previous_rir": None,
            "estimated_1rm": None,
            "step": step,
            "reason": reason,
            "uses_rir": False,
            "continuation_weights": [],
            "continuation_rep_range": (CLUSTER_LOW_REPS, CLUSTER_HIGH_REPS),
        }

    quality_ok, quality_reason = _quality_gate(method, anchor_reps, continuations)
    estimated_1rm = estimated_one_rm(anchor_weight, anchor_reps, 0)

    if phase_name == "deload":
        raw = anchor_weight * 0.90
        suggested = practical_weight(raw, unit, anchor_weight, configured_step=step)
        if current > step:
            suggested = min(suggested, current - step)
        suggested = max(step, suggested)
        action = "deload"
        reason = "Deload week: reduce the method's anchor load."
    elif anchor_reps > HIGH_REP_LIMIT and quality_ok:
        raw = (
            estimated_1rm * (wathan_percent_1rm(TARGET_REPS) / 100.0)
            if estimated_1rm is not None
            else current + step
        )
        suggested = practical_weight(raw, unit, anchor_weight, configured_step=step)
        if raw > anchor_weight and suggested <= current:
            suggested = current + step
        action = "increase"
        reason = f"The {method} anchor exceeded {HIGH_REP_LIMIT} reps and continuation quality was maintained."
    elif anchor_reps > HIGH_REP_LIMIT and not quality_ok:
        suggested = current
        action = "hold"
        reason = f"Anchor reps were high, but {quality_reason}; keep the load until the whole method is completed cleanly."
    elif anchor_reps < LOW_REP_LIMIT:
        raw = (
            estimated_1rm * (wathan_percent_1rm(TARGET_REPS) / 100.0)
            if estimated_1rm is not None
            else max(step, current - step)
        )
        suggested = practical_weight(raw, unit, anchor_weight, configured_step=step)
        if raw < anchor_weight and suggested >= current:
            suggested = max(step, current - step)
        action = "decrease"
        reason = f"The {method} anchor fell below {LOW_REP_LIMIT} reps."
    else:
        suggested = current
        action = "hold"
        reason = f"The {method} anchor remains inside the {LOW_REP_LIMIT}-{HIGH_REP_LIMIT} rep window."

    continuation_weights = []
    if method == "Drop Set":
        continuation_weights = _drop_weights(
            anchor_weight, continuations, suggested, unit, step
        )

    continuation_rep_range = None
    if method == "Myo-Reps":
        continuation_rep_range = (2, 4)
    elif method == "Rest-Pause":
        continuation_rep_range = (2, 5)
    elif method == "Myo-Rep Match":
        continuation_rep_range = (int(round(anchor_reps)), int(round(anchor_reps)))

    return {
        "method": method,
        "action": action,
        "weight": suggested,
        "weight_text": format_weight(suggested),
        "target_reps": TARGET_REPS,
        "target_rir": None,
        "previous_weight": anchor_weight,
        "previous_reps": anchor_reps,
        "previous_rir": None,
        "estimated_1rm": estimated_1rm,
        "step": step,
        "reason": reason,
        "uses_rir": False,
        "continuation_weights": continuation_weights,
        "continuation_rep_range": continuation_rep_range,
    }


def recommendation_weight_for_set(recommendation, set_type, work_index=0):
    """Return the recommended load for a specific working segment."""
    if not recommendation:
        return ""
    method = _canonical_method(recommendation.get("method", "Straight"))
    set_type_key = str(set_type or "").strip().casefold()
    if set_type_key in {"warm-up", "warmup", "warm up"}:
        return ""
    if method == "Straight" and set_type_key not in STRAIGHT_SET_TYPES:
        return ""
    if method == "Drop Set" and work_index > 0:
        values = recommendation.get("continuation_weights") or []
        index = work_index - 1
        if 0 <= index < len(values):
            return format_weight(values[index])
        anchor = _number(recommendation.get("weight"))
        if anchor is not None:
            return format_weight(anchor * (DEFAULT_DROP_RATIO ** work_index))
        return ""
    return str(recommendation.get("weight_text", "") or "")


def calibrated_followup_weight(
    anchor_weight,
    *,
    method="Straight",
    work_index=1,
    unit="kg",
    weight_increment=None,
):
    """Seed later segments immediately after a first-session calibration."""
    method = _canonical_method(method)
    anchor = _number(anchor_weight)
    if anchor is None or anchor <= 0:
        return ""
    if method == "Straight" or method in SAME_LOAD_METHODS or method == "Mechanical Drop Set":
        return format_weight(anchor)
    if method == "Drop Set":
        raw = anchor * (DEFAULT_DROP_RATIO ** max(1, int(work_index)))
        value = practical_weight(
            raw,
            unit,
            reference_weight=raw,
            configured_step=weight_increment,
        )
        return format_weight(value)
    return ""
