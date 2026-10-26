"""Meaning of logged load; bodyweight modes do not imply a total 1RM."""

LABELS = {"external": "External load", "bodyweight": "Bodyweight + added load", "assisted": "Assisted bodyweight"}


def normalize(value):
    value = str(value or "external").strip().lower()
    if value not in LABELS:
        raise ValueError("Choose external load, bodyweight, or assisted bodyweight.")
    return value


def default_for(exercise_name):
    return "bodyweight" if str(exercise_name).strip().casefold() == "pull-up" else "external"


def numeric_kind(mode):
    return "weight" if normalize(mode) == "external" else "load"


def suffix(mode, unit):
    return {"external": unit, "bodyweight": f"{unit} added", "assisted": f"{unit} assist"}[normalize(mode)]


def guidance(mode):
    return {
        "external": "Record the external load used.",
        "bodyweight": "Record added load only; enter 0 for bodyweight alone. Choose load manually; more added load is harder.",
        "assisted": "Record assistance as a positive load; 0 is unassisted. Choose it manually; less assistance is harder.",
    }[normalize(mode)]
