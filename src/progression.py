import math
import statistics


TARGET_REPS = 8
LOW_REP_LIMIT = 8
HIGH_REP_LIMIT = 12
STRAIGHT_SET_TYPES = {"normal", "straight"}


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

    # Legacy fallback for old callers/data that do not yet have equipment info.
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

    # IMPORTANT: equipment increments are *jumps*, not an absolute grid from 0.
    # A 45 lb barbell with a 10 lb total jump can reach 45, 55, 65... rather
    # than only multiples of 10. Round relative to the current real load so the
    # recommendation always corresponds to an actually reachable next setting.
    delta = value - anchor
    return max(0.0, anchor + _round_half_up(delta, step))


def format_weight(value):
    value = float(value)
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return f"{value:.2f}".rstrip("0").rstrip(".")


def estimated_one_rm(weight, reps, rir=0):
    """Estimate 1RM using the same Wathan curve as the Rep Max calculator."""
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


def _usable_straight_sets(rows):
    usable = []
    for row in rows or []:
        if not bool(row.get("completed", True)):
            continue
        set_type = str(row.get("set_type", "Normal") or "Normal").strip().casefold()
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
    """
    Build the next-session prescription from the latest straight-set session.

    The app uses an 8-12 rep working window. Once performance leaves that
    window, use the same Wathan rep-max curve as the Rep Max calculator and
    prescribe the load for 8 reps at the *current mesocycle week's* target RIR.
    Example: at 3 RIR, target effective RM = 8 + 3 = 11RM.
    """
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
            item["weight"],
            item["reps"],
            item["rir"] if item["rir"] is not None else 0,
        )
        if estimate is not None:
            estimates.append(estimate)
    estimated_1rm = statistics.median(estimates) if estimates else None

    step = practical_weight_step(
        median_weight, unit, configured_step=weight_increment
    )
    current_practical = practical_weight(
        median_weight, unit, median_weight, configured_step=step
    )
    phase_name = str(phase or "Build").strip().casefold()

    if phase_name == "deload":
        raw = median_weight * 0.90
        suggested = practical_weight(
            raw, unit, median_weight, configured_step=step
        )
        if current_practical > step:
            suggested = min(suggested, current_practical - step)
        suggested = max(step, suggested)
        action = "deload"
        reason = "Deload week: reduce the load and keep several reps in reserve."
        target_reps = 8
    elif median_reps > HIGH_REP_LIMIT:
        # Do not progress by an arbitrary +2.5 kg / +5 lb step. Estimate 1RM
        # from the work the user actually performed, then ask the shared Wathan
        # curve what load corresponds to 8 reps plus this week's prescribed RIR.
        # At 3 RIR that means an 11RM load (8 performed + 3 in reserve).
        target_effective_rm = TARGET_REPS + target_rir_value
        raw = (
            estimated_1rm * (wathan_percent_1rm(target_effective_rm) / 100.0)
            if estimated_1rm is not None
            else current_practical + step
        )
        suggested = practical_weight(
            raw, unit, median_weight, configured_step=step
        )

        # Practical gym rounding can occasionally round a genuine small increase
        # back to the same selectable load. In that one case, move to the next
        # available increment; otherwise keep the calculator-sized change intact.
        if raw > median_weight and suggested <= current_practical:
            suggested = current_practical + step

        action = "increase"
        reason = (
            f"Last session was about {median_reps:g} reps per straight set, "
            f"above the {LOW_REP_LIMIT}-{HIGH_REP_LIMIT} rep window; "
            f"prescribe the {target_effective_rm:g}RM-equivalent load for "
            f"{TARGET_REPS} reps @ {target_rir_value:g} RIR."
        )
        target_reps = TARGET_REPS
    elif median_reps < LOW_REP_LIMIT:
        # Use the exact same rep-max prescription in the other direction. This
        # avoids arbitrary fixed decrements when the previous load was too heavy.
        target_effective_rm = TARGET_REPS + target_rir_value
        raw = (
            estimated_1rm * (wathan_percent_1rm(target_effective_rm) / 100.0)
            if estimated_1rm is not None
            else max(step, current_practical - step)
        )
        suggested = practical_weight(
            raw, unit, median_weight, configured_step=step
        )
        if raw < median_weight and suggested >= current_practical:
            suggested = max(step, current_practical - step)

        action = "decrease"
        reason = (
            f"Last session was about {median_reps:g} reps per straight set, "
            f"below the {LOW_REP_LIMIT}-{HIGH_REP_LIMIT} rep window; "
            f"prescribe the {target_effective_rm:g}RM-equivalent load for "
            f"{TARGET_REPS} reps @ {target_rir_value:g} RIR."
        )
        target_reps = TARGET_REPS
    else:
        suggested = current_practical
        action = "hold"
        reason = (
            f"Last session was about {median_reps:g} reps per straight set, "
            f"inside the {LOW_REP_LIMIT}-{HIGH_REP_LIMIT} rep window."
        )
        target_reps = TARGET_REPS

    return {
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
    }
