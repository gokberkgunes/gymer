"""RP hypertrophy volume landmark metadata supplied for Gymer.

The range values and source links in this file come from the RP Strength table
supplied by the user. Summary and detail views preserve the supplied ranges;
they are broad references, not personal requirements.
"""

RP_VOLUME_LANDMARKS = {
    "Back": {
        "mv": "2–6",
        "mev": "6–8",
        "mav": "8–20",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/back-hypertrophy-training-tips",
    },
    "Quads": {
        "mv": "2–4",
        "mev": "4–6",
        "mav": "6–14",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/quad-hypertrophy-training-tips",
    },
    "Hamstrings": {
        "mv": "0–2",
        "mev": "2–4",
        "mav": "2–8",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/hamstring-hypertrophy-training-tips",
    },
    "Glutes": {
        "mv": "2–6",
        "mev": "6–8",
        "mav": "8–24",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/glute-hypertrophy-training-tips",
    },
    "Chest": {
        "mv": "2–4",
        "mev": "4–6",
        "mav": "6–16",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/chest-hypertrophy-training-tips",
    },
    "Front Delts": {
        "mv": "0–2",
        "mev": "0–2",
        "mav": "4–8",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/front-delt-hypertrophy-training-tips",
    },
    "Side Delts": {
        "mv": "2–6",
        "mev": "6–8",
        "mav": "8–24",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/side-delt-hypertrophy-training-tips",
    },
    "Rear Delts": {
        "mv": "0–4",
        "mev": "0–4",
        "mav": "4–12",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/rear-delt-hypertrophy-training-tips",
    },
    "Biceps": {
        "mv": "6–8",
        "mev": "8–10",
        "mav": "14–20",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/bicep-hypertrophy-training-tips",
    },
    "Triceps": {
        "mv": "0–4",
        "mev": "4–6",
        "mav": "6–16",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/triceps-hypertrophy-training-tips",
    },
    "Calves": {
        "mv": "2–4",
        "mev": "4–6",
        "mav": "6–16",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/calves-hypertrophy-training-tips",
    },
    "Abs": {
        "mv": "0–4",
        "mev": "0–4",
        "mav": "4–12",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/ab-hypertrophy-training-tips",
    },
    "Traps": {
        "mv": "0–4",
        "mev": "0–4",
        "mav": "4–12",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/trap-hypertrophy-training-tips",
    },
    "Forearms": {
        "mv": "0–4",
        "mev": "0–8",
        "mav": "8–24",
        "mrv": "Not provided",
        "url": "https://rpstrength.com/blogs/articles/forearm-hypertrophy-training-tips",
    },
}

# Retained for compatibility with older callers. Gymer now uses the RP muscle
# taxonomy directly, so these are generally identity mappings.
REPORT_GROUP_MAP = {
    "Lats": "Back",
    "Mid Back": "Back",
}


def report_group_for_muscle(muscle):
    muscle = str(muscle or "").strip()
    return REPORT_GROUP_MAP.get(muscle, muscle)


def landmark_for(group):
    return RP_VOLUME_LANDMARKS.get(str(group or "").strip())


def mev_target(group):
    """Compatibility accessor returning both supplied bounds, never a midpoint."""
    landmark = landmark_for(group)
    if not landmark:
        return None
    try:
        low, high = (float(value.strip()) for value in landmark.get("mev", "").replace("–", "-").split("-", 1))
    except (TypeError, ValueError):
        return None
    return (low, high) if 0 <= low <= high else None


def mev_label(group):
    landmark = landmark_for(group)
    return str(landmark["mev"]) if landmark and mev_target(group) is not None else "—"


def has_rp_landmark(group):
    return landmark_for(group) is not None
