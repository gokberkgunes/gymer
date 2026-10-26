import math
import statistics
import load_modes
import protocols
import set_context


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
MAX_AUTOMATIC_CHANGE = 0.10


def wathan_percent_1rm(reps):
    """Estimated percentage of 1RM for a repetition maximum."""
    reps = float(reps)
    if reps <= 1:
        return 100.0
    return 48.8 + 53.8 * math.exp(-0.075 * reps)


def _number(value):
    try:
        value = float(str("" if value is None else value).strip())
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


def _bounded_load(current, proposed, intended_action, step, reason):
    """Keep direction honest and cap automatic changes to available increments."""
    delta = proposed - current
    direction = 1 if intended_action == "increase" else -1
    if intended_action == "hold":
        return current, "hold", reason
    if delta * direction <= 1e-9:
        return current, "hold", (
            "The rep-based direction conflicts with the effort-based estimate or "
            "rounding; keep the load and review the observation."
        )
    available_steps = math.floor((current * MAX_AUTOMATIC_CHANGE + 1e-9) / step)
    if available_steps < 1:
        return current, "hold", (
            "The smallest configured increment exceeds the 10% automatic-change "
            "limit; choose a suitable load manually."
        )
    bounded = current + direction * min(abs(delta), available_steps * step)
    if bounded <= 0:
        return current, "hold", "No positive load fits this automatic change; choose manually."
    if abs(bounded - proposed) > 1e-9:
        reason += " The change is capped at 10% using available increments."
    action = "increase" if bounded > current else "decrease"
    return bounded, action, reason


def _descending_drop_weights(anchor, ratios, *, unit, step):
    """Use the known anchor's load lattice, never the calculated drop as anchor."""
    previous = anchor
    values = []
    for ratio in ratios:
        candidate = practical_weight(anchor * ratio, unit, anchor, configured_step=step)
        candidate = min(candidate, previous - step)
        if candidate <= 1e-9:
            # No positive, lower equipment load exists; require manual selection.
            values.append(None)
            previous = 0.0
        else:
            values.append(candidate)
            previous = candidate
    return values


def format_weight(value):
    value = float(value)
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    # Keep fractional equipment increments (for example 0.125) attainable in
    # the actual input text, rather than rounding them back to hundredths.
    return f"{value:.12g}"


def estimated_one_rm(weight, reps, rir=None):
    """Estimate 1RM using the Wathan curve and effective reps (reps + RIR)."""
    weight = _number(weight)
    reps = _number(reps)
    rir = _number(rir)
    if weight is None or reps is None or weight <= 0 or reps <= 0:
        return None
    if rir is None or rir < 0:
        return None
    effective_rm = max(1.0, reps + rir)
    percent = wathan_percent_1rm(effective_rm) / 100.0
    if percent <= 0:
        return None
    return weight / percent


def calibration_recommendation(
    weight, reps, rir, *, target_rir, unit="kg", weight_increment=None,
    target_reps=CALIBRATION_TARGET_REPS,
):
    """Suggest a mid-window Straight calibration load from a prior straight set."""
    weight = _number(weight)
    reps = _number(reps)
    prior_rir = _number(rir)
    target_rir = _number(target_rir)
    if weight is None or reps is None or weight <= 0 or reps <= 0:
        return None
    if prior_rir is None or prior_rir < 0:
        return None
    if target_rir is None or target_rir < 0:
        target_rir = 0.0

    one_rm = estimated_one_rm(weight, reps, prior_rir)
    if one_rm is None:
        return None
    effective_rm = target_reps + target_rir
    raw = one_rm * (wathan_percent_1rm(effective_rm) / 100.0)
    suggested = practical_weight(
        raw, unit, reference_weight=weight, configured_step=weight_increment
    )
    if suggested <= 0:
        return None
    return {
        "weight": suggested,
        "weight_text": format_weight(suggested),
        "target_reps": target_reps,
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
    return str("1" if value is None or value == "" else value).strip().casefold() not in {"0", "false", "no", "off"}


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
    rir=None,
    *,
    method="Straight",
    target_rir=0,
    unit="kg",
    weight_increment=None,
    rep_min=LOW_REP_LIMIT,
    rep_max=HIGH_REP_LIMIT,
):
    """Return a calibration load appropriate to the selected exercise method."""
    method = _canonical_method(method)
    if method == "Straight":
        config = straight_settings(rep_min, rep_max)
        return calibration_recommendation(
            weight,
            reps,
            rir,
            target_rir=target_rir,
            unit=unit,
            weight_increment=weight_increment,
            target_reps=(int(config["straight_rep_min"]) + int(config["straight_rep_max"])) // 2,
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

    # Anchor estimates require recorded effort; the protocol name does not
    # establish whether the lifter reached failure.
    source_rir = _number(rir)
    if source_rir is None or source_rir < 0:
        return None
    one_rm = estimated_one_rm(weight_value, reps_value, source_rir)
    if one_rm is None:
        return None
    effort_target = _number(target_rir)
    if effort_target is None or effort_target < 0:
        return None
    raw = one_rm * (wathan_percent_1rm(CALIBRATION_TARGET_REPS + effort_target) / 100.0)
    suggested = practical_weight(
        raw,
        unit,
        reference_weight=weight_value,
        configured_step=weight_increment,
    )
    if suggested <= 0:
        return None
    return {
        "weight": suggested,
        "weight_text": format_weight(suggested),
        "target_reps": CALIBRATION_TARGET_REPS,
        "target_rir": effort_target,
        "estimated_1rm": one_rm,
        "uses_rir": True,
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


def straight_settings(rep_min=None, rep_max=None, policy=None):
    """Validate user-authored Straight policy settings; blanks use defaults."""
    values = []
    for value, default in ((rep_min, LOW_REP_LIMIT), (rep_max, HIGH_REP_LIMIT)):
        text = str(value if value is not None else "").strip()
        try:
            number = int(text) if text else default
        except (TypeError, ValueError):
            raise ValueError("Straight rep limits must be whole numbers from 1 to 9999.") from None
        if not 1 <= number <= 9999:
            raise ValueError("Straight rep limits must be whole numbers from 1 to 9999.")
        values.append(number)
    if values[0] > values[1]:
        raise ValueError("Straight minimum reps must not exceed maximum reps.")
    policy = str(policy or "double_progression").strip()
    if policy not in {"double_progression", "manual"}:
        raise ValueError("Straight progression must be double_progression or manual.")
    return {"straight_rep_min": str(values[0]), "straight_rep_max": str(values[1]),
            "straight_progression": policy}


def progression_recommendation(
    rows, *, target_rir, unit="kg", phase="Build", weight_increment=None,
    rep_min=LOW_REP_LIMIT, rep_max=HIGH_REP_LIMIT, policy="double_progression",
    expected_set_count=None, planned_rows=None,
):
    """All-set double progression, with optional effort observations and rep goals."""
    if str(phase or "Build").strip().casefold() == "deload":
        return None  # Recovery plans are created once from a fixed Build reference.
    config = straight_settings(rep_min, rep_max, policy)
    if config["straight_progression"] == "manual":
        return None
    low, high = int(config["straight_rep_min"]), int(config["straight_rep_max"])
    planned = [row for row in rows or [] if _set_type(row).casefold() in STRAIGHT_SET_TYPES]
    if any(load_modes.normalize(row.get("load_mode", "external")) != "external" for row in planned):
        return None
    sets = _usable_straight_sets(planned)
    if not sets:
        return None  # Do not fabricate a performed reference from all-missed rows.
    current = sets[0]["weight"]
    step = practical_weight_step(current, unit, configured_step=weight_increment)
    actual_target = _number(target_rir)
    if actual_target is not None and actual_target < 0:
        actual_target = None
    estimates = [estimated_one_rm(item["weight"], item["reps"], item["rir"]) for item in sets]
    estimates = [value for value in estimates if value is not None]
    rirs = [item["rir"] for item in sets if item["rir"] is not None and item["rir"] >= 0]
    targets = [max(low, min(high, int(_number(row.get("reps")) or low))) for row in planned]
    suggested, intended = current, "hold"
    apply_weight = True
    context_error = set_context.comparison_error(planned, planned_rows)
    if context_error:
        apply_weight = False
        estimates = []
        reason = context_error
    elif any(row.get("segment_role") and row["segment_role"] != "conventional" for row in planned):
        apply_weight = False
        reason = "Recorded roles identify protocol fragments; review grouping before ordinary set progression."
    elif expected_set_count is not None and len(planned) != expected_set_count:
        apply_weight = False
        reason = "The planned working-set count changed; establish a complete baseline before increasing load."
    elif len(sets) != len(planned):
        reason = "A planned working set was missed or has invalid observations; repeat the load before progressing."
    elif any(abs(item["weight"] - current) > 1e-6 for item in sets):
        apply_weight = False
        reason = "Working loads differ; preserve the individual loads and choose progression manually."
    elif actual_target is None:
        reason = "Target RIR is unknown; choose an effort target before automatic progression."
    elif any(item["rir"] is None or item["rir"] < 0 for item in sets):
        reason = "Actual RIR is unknown for a working set; record effort before progressing."
    else:
        capacity = [item["reps"] + item["rir"] - actual_target for item in sets]
        if all(item["reps"] >= high and item["rir"] >= actual_target for item in sets):
            suggested, intended = current + step, "increase"
            targets = [low] * len(planned)
            reason = f"Every planned set reached {high} reps at or above {actual_target:g} RIR; add one increment and restart at {low} reps."
        elif min(capacity) < low or any(item["reps"] < low for item in sets):
            weakest = sets[capacity.index(min(capacity))]
            one_rm = estimated_one_rm(current, weakest["reps"], weakest["rir"])
            estimate = one_rm * wathan_percent_1rm(low + actual_target) / 100
            if estimate >= current:
                reason = "The low-rep observation conflicts with its recorded effort; keep the load and review the observation."
            else:
                suggested, intended = max(0, current - step), "decrease"
                reason = f"A working set does not support {low} reps at {actual_target:g} RIR; try one increment lower."
            targets = [low] * len(planned)
        elif any(item["rir"] < actual_target for item in sets):
            targets = [max(low, min(high, math.floor(value + 1e-9))) for value in capacity]
            reason = f"Effort exceeded the {actual_target:g} RIR target; keep the load and reduce reps to meet that target."
        else:
            targets = [min(high, int(item["reps"]) + 1) for item in sets]
            reason = f"Keep the load and build reps within {low}–{high}, stopping at {actual_target:g} RIR; increase only after every planned set reaches {high}."
    # A mixed-load session must never be flattened into one prescribed load.
    if any(abs(item["weight"] - current) > 1e-6 for item in sets):
        apply_weight = False
    suggested, action, reason = _bounded_load(current, suggested, intended, step, reason)
    if intended == "increase" and action == "hold":
        targets = [high] * len(planned)
    return {
        "method": "Straight", "policy": "double_progression", "action": action,
        "weight": suggested, "weight_text": format_weight(suggested),
        "apply_weight": apply_weight, "target_reps": min(targets),
        "set_rep_targets": targets, "rep_range": (low, high), "target_rir": actual_target,
        "previous_weight": current, "previous_reps": statistics.median(item["reps"] for item in sets),
        "previous_rir": statistics.median(rirs) if rirs else None,
        "estimated_1rm": statistics.median(estimates) if estimates else None,
        "step": step, "unit": unit, "reason": reason,
        "set_count": len(sets), "planned_set_count": len(planned),
        "uses_rir": True, "continuation_weights": [],
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


def _quality_gate(method, rows, *, planned_rows=None, expected_set_count=None, target_rir=0):
    """Conservative eligibility checks; no missing protocol evidence is a pass."""
    work = [row for row in rows if not _warmup(row)]
    if method in METHODS_WITH_ACTIVATION | {"Cluster"}:
        ids = {row.get("group_id") for row in work if row.get("group_id")}
        plan_work = [row for row in (planned_rows or []) if not _warmup(row)]
        plan_ids = {row.get("group_id") for row in plan_work if row.get("group_id")}
        if (len(ids) > 1 or len(plan_ids) > 1
                or any(row.get("protocol_group_start") == "1" for row in work[1:])
                or any(row.get("protocol_group_start") == "1" for row in plan_work[1:])):
            return False, "multiple protocol groups require manual progression"
        if any(row.get("segment_role") and row["segment_role"] != ("cluster_fragment" if method == "Cluster" else "anchor" if index == 0 else "continuation")
               for index, row in enumerate(work)):
            return False, "recorded group roles differ from the current sequence"
    context_error = set_context.comparison_error(work, planned_rows)
    if method != "Mechanical Drop Set" and context_error:
        return False, context_error
    counts = [_number(row.get("planned_work_count")) for row in work]
    if not counts or any(value is None or value < 1 or not value.is_integer() for value in counts):
        return False, "the original planned segment count is unknown"
    if len(set(counts)) != 1 or counts[0] != len(work):
        return False, "a planned segment was removed or the saved plan is inconsistent"
    if expected_set_count is not None and len(work) != expected_set_count:
        return False, "the planned segment count changed; establish a comparable baseline"
    if method in METHODS_WITH_ACTIVATION and len(work) < 2:
        return False, "activation only was recorded; no continuation protocol was completed"
    expected_type = {"Myo-Reps": "myo-set", "Rest-Pause": "rest-pause", "Drop Set": "drop set",
                     "Mechanical Drop Set": "mechanical drop set", "Myo-Rep Match": "myo-rep match"}
    roles = [_set_type(row).casefold() for row in work]
    expected = [_anchor_type(method).casefold()] * len(work)
    if method in METHODS_WITH_ACTIVATION:
        expected = ["activation"] + [expected_type[method]] * (len(work) - 1)
    if roles != expected:
        return False, "the segment roles do not match this method"
    if any(not _completed(row) for row in work):
        return False, "not all planned segments were completed"
    weights, reps = ([_number(row.get(key)) for row in work] for key in ("weight", "reps"))
    if any(value is None or value <= 0 for value in weights + reps):
        return False, "a segment has invalid load or reps"
    setups = [str(row.get("setup", "")).strip() for row in work]
    if any(not value for value in setups):
        return False, "setup/variation is not recorded for every segment"
    if planned_rows is not None:
        plan = [row for row in planned_rows if not _warmup(row)]
        if len(plan) != len(work) or [_set_type(row).casefold() for row in plan] != roles:
            return False, "the current segment sequence differs from the recorded protocol"
        if [str(row.get("setup", "")).strip() for row in plan] != setups:
            return False, "the current setup/variation differs or is unknown"
    else:
        plan = work
    # Rest after the final segment is not an intra-protocol comparison.
    for row, current in zip(work[:-1], plan[:-1]):
        intended, actual, now = (_number(row.get("rest_seconds")), _number(row.get("actual_rest_seconds")), _number(current.get("rest_seconds")))
        if intended is None or actual is None or now is None:
            return False, "inter-segment rest is unknown; record actual rest after each preceding segment"
        if min(intended, actual, now) < 0 or abs(actual - intended) > 1e-6 or abs(now - intended) > 1e-6:
            return False, "recorded or planned inter-segment rests differ; progress manually"
    if method == "Mechanical Drop Set":
        return False, "mechanical leverage changes require manual progression; setup labels alone do not establish equivalence"
    if method in SAME_LOAD_METHODS and any(abs(value - weights[0]) > 1e-6 for value in weights):
        return False, "this same-load method used different segment loads"
    if method == "Drop Set" and any(after >= before for before, after in zip(weights, weights[1:])):
        return False, "drop loads did not strictly decrease between segments"
    if method in {"Myo-Reps", "Rest-Pause", "Drop Set"} and any(value < MINI_SET_MIN_REPS for value in reps[1:]):
        return False, f"a continuation segment fell below {MINI_SET_MIN_REPS} reps"
    if method == "Myo-Rep Match" and any(value < reps[0] for value in reps[1:]):
        return False, "not every match segment reached the activation rep count"
    if method != "Cluster":
        anchors = work if method == "AMRAP" else work[:1]
        if any(row.get("stop_reason", "") not in {"target_rir", "technical_failure", "muscular_failure"} for row in anchors):
            return False, "an anchor stop reason is unknown, safety-limited or requires manual review"
        if any(row.get("stop_reason") == "muscular_failure" and _number(row.get("rir")) not in {None, 0} for row in anchors):
            return False, "muscular failure conflicts with the recorded nonzero actual RIR"
        target = _number(target_rir)
        if target is None or target < 0:
            return False, "the anchor effort target is unknown"
        if any(_number(row.get("rir")) is None or _number(row.get("rir")) < target for row in anchors):
            return False, "actual anchor RIR is unknown or effort exceeded the target"
    return True, ""


def _drop_weights(anchor_weight, continuation_rows, suggested_anchor, unit, step):
    ratios = []
    for index, row in enumerate(continuation_rows):
        actual = _number(row.get("weight"))
        if actual is not None and actual > 0 and anchor_weight > 0:
            ratio = actual / anchor_weight
            if not 0.20 <= ratio < 1.0:
                ratio = DEFAULT_DROP_RATIO ** (index + 1)
        else:
            ratio = DEFAULT_DROP_RATIO ** (index + 1)
        ratios.append(ratio)
    # suggested_anchor is already on the observed anchor's lattice.
    return _descending_drop_weights(suggested_anchor, ratios, unit=unit, step=step)


def method_progression_recommendation(
    rows,
    *,
    method="Straight",
    target_rir=0,
    unit="kg",
    phase="Build",
    weight_increment=None,
    rep_min=LOW_REP_LIMIT, rep_max=HIGH_REP_LIMIT, policy="double_progression",
    expected_set_count=None,
    planned_rows=None,
):
    """Dispatch progression according to the exercise-level Training Method."""
    if str(phase or "Build").strip().casefold() == "deload":
        return None  # Never discount the latest recovery observation again.
    method = _canonical_method(method)
    if any(load_modes.normalize(row.get("load_mode", "external")) != "external" for row in rows or []):
        return None
    if method == "Straight":
        return progression_recommendation(
            rows,
            target_rir=target_rir,
            unit=unit,
            phase=phase,
            weight_increment=weight_increment,
            rep_min=rep_min, rep_max=rep_max, policy=policy,
            expected_set_count=expected_set_count, planned_rows=planned_rows,
        )

    anchor_row, anchor_weight, anchor_reps = _valid_anchor(rows, method)
    if anchor_row is None:
        return None

    step = practical_weight_step(anchor_weight, unit, configured_step=weight_increment)
    current = practical_weight(anchor_weight, unit, anchor_weight, configured_step=step)
    continuations = _continuations(rows, anchor_row)
    quality_ok, quality_reason = _quality_gate(method, rows, planned_rows=planned_rows,
                                              expected_set_count=expected_set_count, target_rir=target_rir)

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
        if not quality_ok:
            suggested, action = current, "hold"
            reason = f"Hold cluster load: {quality_reason}."
        elif not all_completed:
            suggested = current
            action = "hold"
            reason = "Hold cluster load because not all planned clusters were completed."
        elif all(value > CLUSTER_HIGH_REPS for value in reps_values):
            suggested = current + step
            action = "increase"
            reason = f"Cluster reps rose above the {CLUSTER_LOW_REPS}-{CLUSTER_HIGH_REPS} working window."
        elif any(value < CLUSTER_LOW_REPS for value in reps_values):
            suggested = max(step, current - step)
            action = "decrease"
            reason = f"Cluster reps fell below the {CLUSTER_LOW_REPS}-{CLUSTER_HIGH_REPS} working window."
        else:
            suggested = current
            action = "hold"
            reason = f"Cluster reps remain inside the {CLUSTER_LOW_REPS}-{CLUSTER_HIGH_REPS} working window."
        suggested, action, reason = _bounded_load(current, suggested, action, step, reason)
        return {
            "method": method,
            "apply_weight": quality_ok,
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
            "unit": unit,
            "reason": reason,
            "uses_rir": False,
            "continuation_weights": [],
            "continuation_rep_range": (CLUSTER_LOW_REPS, CLUSTER_HIGH_REPS),
        }

    estimated_1rm = estimated_one_rm(anchor_weight, anchor_reps, anchor_row.get("rir"))

    if not quality_ok:
        suggested, action = current, "hold"
        reason = f"Hold {method} load: {quality_reason}."
    elif estimated_1rm is None:
        suggested, action = current, "hold"
        reason = "The anchor's actual RIR is unknown; do not infer failure or increase load."
    elif (min(_number(row.get("reps")) for row in rows if not _warmup(row)) if method == "AMRAP" else anchor_reps) > HIGH_REP_LIMIT:
        raw = (
            estimated_1rm * (wathan_percent_1rm(TARGET_REPS + (_number(target_rir) or 0)) / 100.0)
            if estimated_1rm is not None
            else current + step
        )
        suggested = practical_weight(raw, unit, anchor_weight, configured_step=step)
        if raw > anchor_weight and suggested <= current:
            suggested = current + step
        action = "increase"
        reason = f"The {method} anchor exceeded {HIGH_REP_LIMIT} reps and continuation quality was maintained."
    elif anchor_reps < LOW_REP_LIMIT:
        raw = (
            estimated_1rm * (wathan_percent_1rm(TARGET_REPS + (_number(target_rir) or 0)) / 100.0)
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

    suggested, action, reason = _bounded_load(current, suggested, action, step, reason)
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
        "apply_weight": quality_ok,
        "action": action,
        "weight": suggested,
        "weight_text": format_weight(suggested),
        "target_reps": TARGET_REPS,
        "target_rir": _number(target_rir),
        "previous_weight": anchor_weight,
        "previous_reps": anchor_reps,
        "previous_rir": _number(anchor_row.get("rir")),
        "estimated_1rm": estimated_1rm,
        "step": step,
        "unit": unit,
        "reason": reason,
        "uses_rir": True,
        "continuation_weights": continuation_weights,
        "continuation_rep_range": continuation_rep_range,
    }


def recommendation_weight_for_set(recommendation, set_type, work_index=0):
    """Return the recommended load for a specific working segment."""
    if not recommendation or not recommendation.get("apply_weight", True):
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
            return "" if values[index] is None else format_weight(values[index])
        anchor = _number(recommendation.get("weight"))
        if anchor is not None:
            if any(value is None for value in values) or anchor <= 0:
                return ""
            ratios = [value / anchor for value in values]
            ratios.extend(DEFAULT_DROP_RATIO ** index for index in range(len(values) + 1, work_index + 1))
            unit = recommendation.get("unit", "kg")
            step = practical_weight_step(anchor, unit, recommendation.get("step"))
            weights = _descending_drop_weights(
                anchor, ratios, unit=unit, step=step,
            )
            return "" if weights[-1] is None else format_weight(weights[-1])
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
        count = max(1, int(work_index))
        step = practical_weight_step(anchor, unit, configured_step=weight_increment)
        values = _descending_drop_weights(
            anchor, [DEFAULT_DROP_RATIO ** index for index in range(1, count + 1)],
            unit=unit, step=step,
        )
        return "" if values[-1] is None else format_weight(values[-1])
    return ""
