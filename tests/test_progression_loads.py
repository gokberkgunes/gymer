"""Equipment availability and honest load direction, audit findings 8 and 9."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
import progression as p


class ProgressionLoadTests(unittest.TestCase):
    def rows(self, method, weight=100, reps=13, rir=2):
        anchor = {"Straight": "Normal", "AMRAP": "AMRAP", "Cluster": "Cluster Set"}.get(method, "Activation")
        rows = [dict(weight=weight, reps=reps, rir=rir, set_type=anchor, completed=True)]
        if method in p.METHODS_WITH_ACTIVATION:
            rows.append(dict(weight=weight if method != "Drop Set" else weight * .75,
                             reps=reps, rir="", set_type="Myo-set" if method == "Myo-Reps" else method, completed=True))
        for row in rows:
            row.update(planned_work_count=str(len(rows)), setup="Same machine and position", stop_reason="target_rir",
                       rest_seconds="20", actual_rest_seconds="20")
        return rows

    def assert_direction_and_grid(self, rec):
        current, actual, step = rec["previous_weight"], rec["weight"], rec["step"]
        expected = "hold" if abs(actual - current) < 1e-8 else "increase" if actual > current else "decrease"
        self.assertEqual(expected, rec["action"])
        self.assertGreater(actual, 0)
        self.assertLessEqual(abs(actual - current), current * .10 + 1e-8)
        self.assertAlmostEqual(round((actual - current) / step), (actual - current) / step)

    def test_reported_low_rep_high_rir_contradiction_holds_for_review(self):
        rec = p.progression_recommendation(self.rows("Straight", reps=6, rir=10), target_rir=2, weight_increment=5)
        self.assertEqual(("hold", 100), (rec["action"], rec["weight"]))
        self.assertIn("conflicts", rec["reason"])

    def test_direction_bound_and_grid_across_methods_observations_and_phases(self):
        for method in ["Straight", "AMRAP", "Cluster", *sorted(p.METHODS_WITH_ACTIVATION)]:
            for reps in [1, 6, 8, 12, 13, 30]:
                for rir in [None, 0, 2, 10]:
                    for phase in ["Build", "Deload"]:
                        for weight, step in [(100, 5), (12, 5), (110.23, 10), (50, 60)]:
                            with self.subTest(method=method, reps=reps, rir=rir, phase=phase, weight=weight):
                                rec = p.method_progression_recommendation(
                                    self.rows(method, weight, reps, rir), method=method,
                                    target_rir=2, phase=phase, weight_increment=step)
                                if phase == "Deload":
                                    self.assertIsNone(rec)
                                    continue
                                self.assert_direction_and_grid(rec)

    def test_large_proposals_are_limited_to_available_steps_with_explanation(self):
        rec = p.method_progression_recommendation(self.rows("AMRAP", reps=30, rir=2), method="AMRAP", target_rir=2, weight_increment=5)
        self.assertEqual(110, rec["weight"])
        self.assertIn("capped", rec["reason"])

    def test_coarse_increment_requires_manual_load_selection(self):
        rec = p.progression_recommendation(self.rows("Straight", weight=12, reps=15), target_rir=2, weight_increment=5)
        self.assertEqual(("hold", 12), (rec["action"], rec["weight"]))
        self.assertIn("manually", rec["reason"])

    def test_even_number_of_straight_sets_does_not_invent_a_lattice_anchor(self):
        rows = self.rows("Straight", weight=100) + self.rows("Straight", weight=105)
        rec = p.progression_recommendation(rows, target_rir=2, weight_increment=5)
        self.assertEqual(100, rec["previous_weight"])
        self.assert_direction_and_grid(rec)

    def test_calibrated_drop_rounds_on_equipment_grid(self):
        self.assertEqual("40", p.calibrated_followup_weight(50, method="Drop Set", weight_increment=5))
        previous = 50
        for index in range(1, 8):
            text = p.calibrated_followup_weight(50, method="Drop Set", work_index=index, weight_increment=5)
            if not text:
                continue
            value = float(text)
            self.assertEqual(0, value % 5)
            self.assertGreater(value, 0)
            self.assertLess(value, previous)
            previous = value

    def test_coarse_grid_never_repeats_a_drop_or_returns_zero(self):
        self.assertEqual("", p.calibrated_followup_weight(5, method="Drop Set", weight_increment=5))
        self.assertEqual("", p.calibrated_followup_weight(50, method="Drop Set", weight_increment=60))

    def test_offset_converted_load_keeps_known_equipment_lattice(self):
        anchor, step = 110.23, 10
        for index in range(1, 5):
            value = float(p.calibrated_followup_weight(anchor, method="Drop Set", work_index=index, unit="lb", weight_increment=step))
            self.assertAlmostEqual(round((value - anchor) / step), (value - anchor) / step)
            self.assertLess(value, anchor)

    def test_fractional_increment_survives_the_suggested_input_text(self):
        text = p.calibrated_followup_weight(10.125, method="Drop Set", weight_increment=.125)
        self.assertEqual("7.625", text)
        self.assertEqual(0, (float(text) - 10.125) % .125)

    def test_history_drop_ratios_are_rounded_and_strictly_descending(self):
        rows = self.rows("Drop Set", weight=50, reps=10)
        rows[1]["weight"] = 37.5
        rows.append(dict(weight=37, reps=5, set_type="Drop Set", completed=True))
        rec = p.method_progression_recommendation(rows, method="Drop Set", weight_increment=5)
        self.assertEqual([40, 35], rec["continuation_weights"])

    def test_fallback_drop_rounds_and_remains_below_existing_segments(self):
        rec = dict(method="Drop Set", weight=50, weight_text="50", step=5, unit="kg", continuation_weights=[])
        self.assertEqual("40", p.recommendation_weight_for_set(rec, "Drop Set", work_index=1))
        rec["continuation_weights"] = [10]
        self.assertEqual("5", p.recommendation_weight_for_set(rec, "Drop Set", work_index=2))
        self.assertEqual("", p.recommendation_weight_for_set(rec, "Drop Set", work_index=3))


if __name__ == "__main__":
    unittest.main()
