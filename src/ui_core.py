import ast
import asyncio
import math
import statistics
import time
import uuid
from datetime import datetime

import flet as ft

import storage
import progression


class UICoreMixin:

    @staticmethod
    def wathan_percent_1rm(reps):
        """Use the shared Wathan curve used by progression and Rep Max."""
        return progression.wathan_percent_1rm(reps)

    @classmethod
    def rep_max_percentages(cls):
        """Full-precision %1RM values for the displayed 1RM–20RM table."""
        return [
            cls.wathan_percent_1rm(reps)
            for reps in range(1, 21)
        ]


    def font_scale(self):
        try:
            return float(self.settings.get("font_scale", "1.0"))
        except ValueError:
            return 1.0

    def phone_layout_scale(self):
        """Normalize the whole UI when Android changes its logical display width."""
        # Android's Display size setting changes the logical width Flutter/Flet
        # reports. Gymer intentionally uses a dense, phone-first layout, so every
        # authored dimension must shrink together rather than allowing individual
        # Material controls to wrap or overflow. 430 is only the authored logical
        # canvas; it is not a claim about the phone's physical pixel width.
        try:
            width = float(getattr(self.page, "width", 0) or 0)
        except (TypeError, ValueError):
            width = 0.0

        if width <= 0:
            return 1.0

        return max(0.58, min(1.0, width / 430.0))

    def ui(self, value):
        """Scale one authored layout dimension for the current logical width."""
        return float(value) * self.phone_layout_scale()

    def fit_layout_scale(self, designed_width, outer_inset=0, minimum=0.58):
        """Return a local scale that guarantees one dense row fits the viewport.

        Most screens can use ui(). Exceptionally dense rows (the workout editor,
        rep-max tables, etc.) know their authored footprint and use this helper so
        they preserve their proportions without wrapping on narrow Android widths.
        """
        try:
            width = float(getattr(self.page, "width", 0) or 0)
        except (TypeError, ValueError):
            width = 0.0
        if width <= 0:
            return self.phone_layout_scale()

        available = max(1.0, width - self.ui(outer_inset))
        fitted = available / max(1.0, float(designed_width))
        return max(float(minimum), min(self.phone_layout_scale(), fitted, 1.0))

    def dialog_width(self, preferred=420, horizontal_inset=28, minimum=260):
        """Clamp dialog content to the current phone width."""
        try:
            page_width = float(getattr(self.page, "width", 0) or 0)
        except (TypeError, ValueError):
            page_width = 0.0
        preferred = self.ui(preferred)
        if page_width <= 0:
            return preferred
        available = max(self.ui(minimum), page_width - self.ui(horizontal_inset))
        return min(preferred, available)

    def dialog_height(self, preferred=420, vertical_inset=190, minimum=260):
        """Clamp tall dialog content to the current phone height."""
        try:
            page_height = float(getattr(self.page, "height", 0) or 0)
        except (TypeError, ValueError):
            page_height = 0.0
        preferred = self.ui(preferred)
        if page_height <= 0:
            return preferred
        available = max(self.ui(minimum), page_height - self.ui(vertical_inset))
        return min(preferred, available)

    def fs(self, size):
        # Scale text together with its boxes. This counteracts Android Display
        # Size changing Flutter's logical width while preserving Gymer's own font
        # scale setting on top of the normalized phone layout.
        return size * self.font_scale() * self.phone_layout_scale()

    def rounding(self):
        try:
            return max(0, int(float(self.settings.get("rounding", "0"))))
        except ValueError:
            return 0

    def density(self):
        return self.DENSITY_MAP.get(
            self.settings.get("density", "normal"),
            self.DENSITY_MAP["normal"],
        )

    def base_set_spacing(self):
        try:
            return max(0, min(12, int(float(self.settings.get("set_spacing", "3")))))
        except ValueError:
            return 3

    def set_spacing(self):
        base = self.base_set_spacing()
        offset = self.SET_DENSITY_OFFSET.get(
            self.settings.get("density", "normal"),
            0,
        )
        return max(0, min(18, base + offset))

    def is_dark_mode(self):
        mode = self.settings.get("theme_mode", "system")

        if mode == "dark":
            return True
        if mode == "light":
            return False

        return self.page.platform_brightness != ft.Brightness.LIGHT

    def effective_background_name(self, dark=None):
        if dark is None:
            dark = self.is_dark_mode()

        name = self.settings.get("background_color", "auto")
        if name == "auto":
            return "charcoal" if dark else "default"
        return name

    def background_color(self, name=None, dark=None):
        if dark is None:
            dark = self.is_dark_mode()
        if name is None:
            name = self.effective_background_name(dark=dark)

        dark_color, light_color = self.BACKGROUND_MAP.get(
            name,
            self.BACKGROUND_MAP["charcoal"],
        )
        return dark_color if dark else light_color

    def foreground_color(self):
        return ft.Colors.WHITE if self.is_dark_mode() else ft.Colors.BLACK

    def track_rir_enabled(self):
        return self.settings.get("track_rir", "1") == "1"

    def cycle_locks(self):
        return storage.active_cycle_locks()

    def cycle_rir_target(self):
        locks = self.cycle_locks()
        value = locks.get("suggested_rir")
        if value is None:
            return None
        return f"{float(value):.1f}".rstrip("0").rstrip(".")

    def cycle_rir_lock_enabled(self):
        if self.cycle_rir_target() is None:
            return False
        # Unlocking RIR is an Advanced Mode override. With Advanced Mode off,
        # use the recommended locked behavior even if an older cycle stored an
        # unlocked flag.
        if not self.advanced_mode_enabled():
            return True
        return bool(self.cycle_locks().get("rir_lock"))

    def cycle_rest_lock_enabled(self):
        return bool(self.cycle_locks().get("rest_timer_lock"))

    def dim_completed_sets_enabled(self):
        return self.settings.get("dim_completed_sets", "1") == "1"

    def collapse_completed_exercises_enabled(self):
        return self.settings.get("collapse_completed_exercises", "1") == "1"

    def timer_tracker_mode(self):
        mode = self.settings.get("timer_tracker_mode", "both")
        return mode if mode in {"both", "floating", "nearset", "off"} else "both"

    def floating_timer_enabled(self):
        return self.timer_tracker_mode() in {"both", "floating"}

    def nearset_timer_enabled(self):
        return self.timer_tracker_mode() in {"both", "nearset"}

    def planned_rest_display_mode(self):
        mode = self.settings.get("planned_rest_display_mode", "hide")
        return mode if mode in {"hide", "smart", "always"} else "hide"

    def show_rest_time_near_sets_enabled(self):
        # Legacy compatibility helper. New UI uses planned_rest_display_mode().
        return self.planned_rest_display_mode() != "hide"

    def advanced_mode_enabled(self):
        return self.settings.get("advanced_mode", "0") == "1"

    def update_following_set_defaults_enabled(self):
        return (
            self.advanced_mode_enabled()
            and self.settings.get("update_following_set_defaults", "0") == "1"
        )

    def advanced_rep_max_mode_enabled(self):
        # Rep Max customization follows the main Advanced Mode switch.
        return self.advanced_mode_enabled()

    def enter_completes_set_enabled(self):
        if not self.advanced_mode_enabled():
            return True
        return self.settings.get("enter_completes_set", "1") == "1"

    def enter_moves_to_next_set_enabled(self):
        if not self.advanced_mode_enabled():
            return False
        return self.settings.get("enter_moves_to_next_set", "0") == "1"

    def backspace_moves_to_previous_set_enabled(self):
        if not self.advanced_mode_enabled():
            return False
        return self.settings.get("backspace_moves_to_previous_set", "0") == "1"

    def require_previous_sets_completed_enabled(self):
        return (
            self.advanced_mode_enabled()
            and self.settings.get("require_previous_sets_completed", "0") == "1"
        )

    def timer_tap_action(self):
        if not self.advanced_mode_enabled():
            return "switch"
        value = self.settings.get("timer_tap_action", "switch")
        return value if value in {"switch", "hide"} else "switch"

    def default_timer_display_mode(self):
        if not self.advanced_mode_enabled():
            return "elapsed"
        value = self.settings.get("default_timer_display_mode", "elapsed")
        return value if value in {"elapsed", "countdown"} else "elapsed"

    def format_target_duration(self, seconds):
        # Targets are estimates, so round up to the next five minutes rather
        # than showing fake precision such as 59:00.
        seconds = max(0, int(seconds or 0))
        if seconds == 0:
            return "0 min"
        minutes = ((seconds + 299) // 300) * 5
        return f"{minutes} min"

    def mark_field_invalid(self, field):
        field.border_color = ft.Colors.RED_500
        field.focused_border_color = ft.Colors.RED_500
        field.border_width = 2.2
        field.focused_border_width = 2.4

    def clear_field_invalid(self, field):
        if getattr(field, "data", None) == "locked_rir":
            field.border_color = ft.Colors.GREEN_500
            field.focused_border_color = ft.Colors.GREEN_400
            field.border_width = 1.8
            field.focused_border_width = 2.0
            return

        field.border_color = self.field_border_color()
        field.focused_border_color = self.field_focused_border_color()
        field.border_width = 1
        field.focused_border_width = 2

    def logical_text_value(self, value):
        """Return user-visible text with the invisible Backspace sentinel removed."""
        return str(value or "").replace(self.EMPTY_BACKSPACE_SENTINEL, "").strip()

    def arm_android_empty_backspace(self, field):
        """
        Put an invisible character into an empty focused numeric field.

        Deleting it with the Android soft keyboard produces TextField.on_change,
        unlike relying on a global hardware-style keyboard event.
        """
        if field is None or getattr(field, "read_only", False):
            return
        if self.logical_text_value(field.value):
            self.android_backspace_last_values[id(field)] = str(field.value or "")
            return

        field.value = self.EMPTY_BACKSPACE_SENTINEL
        self.android_backspace_last_values[id(field)] = self.EMPTY_BACKSPACE_SENTINEL

        # Keep the caret after the invisible character so Backspace deletes it.
        field.selection = ft.TextSelection(base_offset=1, extent_offset=1)
        field.update()

    async def focus_text_field_at_end(self, field):
        """
        Focus a TextField and explicitly place the caret after its last
        character. This prevents Android/Flet from restoring an old selection
        position such as 4|5 when Backspace navigates to a previous field.
        """
        if field is None:
            return

        await field.focus()

        # Let the focus/on_focus event settle first. An empty active numeric
        # field may arm the invisible Backspace sentinel during that event.
        await asyncio.sleep(0)

        raw = str(field.value or "")
        offset = len(raw)
        field.selection = ft.TextSelection(
            base_offset=offset,
            extent_offset=offset,
        )
        field.update()

    def process_android_empty_backspace_change(self, field):
        """
        Normalize the invisible sentinel after an IME edit.

        Returns True only when Backspace was pressed while the field was
        logically empty and focus should move to the previous linked field.
        """
        field_id = id(field)
        raw = str(field.value or "")
        previous_raw = self.android_backspace_last_values.get(field_id, "")

        # Keep the invisible sentinel in the live TextField while it has
        # focus. Rewriting field.value here makes Android restore the caret at
        # the wrong offset (for example 2|5, so typing 6 becomes 265). All
        # validation/persistence uses logical_text_value(), so the sentinel is
        # invisible to the rest of the app and is stripped on blur/submit.
        if self.EMPTY_BACKSPACE_SENTINEL in raw and raw != self.EMPTY_BACKSPACE_SENTINEL:
            self.android_backspace_last_values[field_id] = raw
            return False

        # Sentinel -> empty means Backspace was pressed on an already-empty
        # field. This is the Android path we need.
        if raw == "" and previous_raw == self.EMPTY_BACKSPACE_SENTINEL:
            self.android_backspace_last_values[field_id] = ""
            previous = self.focus_previous_fields.get(field_id)

            # Backspace always moves within the current set (RIR -> Reps ->
            # Weight). Crossing from this set's Weight into the previous set
            # is optional and disabled by default.
            current_context = self.active_numeric_context.get(field_id)
            previous_context = (
                self.active_numeric_context.get(id(previous))
                if previous is not None
                else None
            )
            if (
                previous is not None
                and current_context is not None
                and previous_context is not None
                and current_context[0].get("set_number")
                != previous_context[0].get("set_number")
                and not self.backspace_moves_to_previous_set_enabled()
            ):
                previous = None

            if previous is not None:
                self.page.run_task(self.focus_text_field_at_end, previous)
            else:
                # Stay at the boundary, but immediately re-arm the invisible
                # character so repeated Backspace presses remain stable.
                field.value = self.EMPTY_BACKSPACE_SENTINEL
                field.selection = ft.TextSelection(base_offset=1, extent_offset=1)
                self.android_backspace_last_values[field_id] = (
                    self.EMPTY_BACKSPACE_SENTINEL
                )
            return True

        # Deleting the final real character should leave the user in the same
        # field. Arm the sentinel so *another* Backspace moves backward.
        if raw == "" and previous_raw != self.EMPTY_BACKSPACE_SENTINEL:
            field.value = self.EMPTY_BACKSPACE_SENTINEL
            field.selection = ft.TextSelection(base_offset=1, extent_offset=1)
            self.android_backspace_last_values[field_id] = self.EMPTY_BACKSPACE_SENTINEL
            return False

        self.android_backspace_last_values[field_id] = raw
        return False

    def disarm_android_empty_backspace(self, field):
        """Remove every sentinel when a field loses focus."""
        if field is None:
            return
        raw = str(field.value or "")
        if self.EMPTY_BACKSPACE_SENTINEL in raw:
            field.value = raw.replace(self.EMPTY_BACKSPACE_SENTINEL, "")
        self.android_backspace_last_values[id(field)] = str(field.value or "")

    def numeric_kind_spec(self, kind):
        specs = {
            "weight": {"integer": False, "minimum": 0.000001, "maximum": 10000},
            "reps": {"integer": True, "minimum": 1, "maximum": 999},
            "rir": {"integer": False, "minimum": 0, "maximum": 99},
            "rm": {"integer": True, "minimum": 1, "maximum": 999},
            "target_reps": {"integer": True, "minimum": 1, "maximum": 999},
            "count": {"integer": True, "minimum": 1, "maximum": 9999},
            "nonnegative_count": {"integer": True, "minimum": 0, "maximum": 9999},
            "seconds": {"integer": True, "minimum": 0, "maximum": 86400},
            "number": {"integer": False, "minimum": -1000000, "maximum": 1000000},
        }
        return specs.get(kind, specs["number"])

    def evaluate_numeric_expression(self, text):
        """Safely evaluate a small arithmetic expression such as 45+45."""
        text = self.logical_text_value(text)
        if not text or len(text) > 40:
            return None

        try:
            tree = ast.parse(text, mode="eval")
        except (SyntaxError, ValueError):
            return None

        def evaluate(node):
            if isinstance(node, ast.Expression):
                return evaluate(node.body)
            if isinstance(node, ast.Constant):
                if isinstance(node.value, bool) or not isinstance(node.value, (int, float)):
                    raise ValueError
                return float(node.value)
            if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
                value = evaluate(node.operand)
                return value if isinstance(node.op, ast.UAdd) else -value
            if isinstance(node, ast.BinOp) and isinstance(
                node.op, (ast.Add, ast.Sub, ast.Mult, ast.Div)
            ):
                left = evaluate(node.left)
                right = evaluate(node.right)
                if isinstance(node.op, ast.Add):
                    return left + right
                if isinstance(node.op, ast.Sub):
                    return left - right
                if isinstance(node.op, ast.Mult):
                    return left * right
                if right == 0:
                    raise ValueError
                return left / right
            raise ValueError

        try:
            value = evaluate(tree)
        except (ValueError, ZeroDivisionError, OverflowError):
            return None

        if not math.isfinite(value) or abs(value) > 1_000_000:
            return None
        return value

    def format_numeric_value(self, value, kind="number"):
        spec = self.numeric_kind_spec(kind)
        if spec["integer"]:
            if abs(value - round(value)) > 1e-9:
                return None
            return str(int(round(value)))

        if abs(value - round(value)) < 1e-9:
            return str(int(round(value)))
        return f"{value:.2f}".rstrip("0").rstrip(".")

    def numeric_value_is_allowed(self, value, kind="number"):
        spec = self.numeric_kind_spec(kind)
        if spec["integer"] and abs(value - round(value)) > 1e-9:
            return False
        return spec["minimum"] <= value <= spec["maximum"]

    def normalize_numeric_control(self, field, kind=None, allow_empty=True):
        """Evaluate/validate a numeric field. Invalid input stays in place."""
        raw = self.logical_text_value(field.value)
        if not raw:
            if allow_empty:
                return True
            self.mark_field_invalid(field)
            return False

        kind = kind or self.numeric_field_kinds.get(id(field), "number")
        value = self.evaluate_numeric_expression(raw)
        if value is None or not self.numeric_value_is_allowed(value, kind):
            self.mark_field_invalid(field)
            return False

        shown = self.format_numeric_value(value, kind)
        if shown is None:
            self.mark_field_invalid(field)
            return False

        field.value = shown
        self.clear_field_invalid(field)
        return True

    def numeric_warning_reason(self, kind, value, reference=None):
        if kind == "reps" and value >= 30:
            return "Unusually high rep count"
        if kind == "rir" and value >= 5:
            return "Unusually high RIR"
        if kind == "weight":
            if value >= 1000:
                return "Unusually high weight"
            if reference is not None and reference > 0:
                difference = abs(value - reference)
                if difference >= 10 and (
                    value >= reference * 2 or value <= reference * 0.5
                ):
                    return "Large change from your usual weight"
        return ""

    def active_numeric_reference(self, item, key):
        if key != "weight":
            previous_key = {
                "reps": "previous_reps",
                "rir": "previous_rir",
            }.get(key)
            if previous_key:
                value = self.evaluate_numeric_expression(item.get(previous_key, ""))
                if value is not None and value > 0:
                    return value
            return None

        # Weight warnings need robust evidence. A missing history value for set 3
        # must not make set 2 the sole definition of "usual weight", and a
        # mesocycle-prescribed ghost value must never count as user history.
        # Compare against real historical/entered weights across compatible sets
        # of this exercise instead.
        exercise_name = item.get("exercise_name")
        current_type = str(item.get("set_type", "Normal") or "Normal").strip().casefold()
        straight_types = {"normal", "straight"}

        def compatible(row):
            row_type = str(row.get("set_type", "Normal") or "Normal").strip().casefold()
            if current_type in straight_types:
                return row_type in straight_types
            return row_type == current_type

        references = []
        own_history = self.evaluate_numeric_expression(
            item.get("weight_warning_reference", "")
        )
        if own_history is not None and own_history > 0:
            references.append(own_history)

        for row in self.set_controls:
            if row is item or row.get("exercise_name") != exercise_name or not compatible(row):
                continue

            historical = self.evaluate_numeric_expression(
                row.get("weight_warning_reference", "")
            )
            if historical is not None and historical > 0:
                references.append(historical)

            field = row.get("weight")
            if field is not None:
                live = self.evaluate_numeric_expression(field.value)
                if live is not None and live > 0:
                    references.append(live)

        # One unrelated neighboring set is not enough evidence for an orange
        # warning when this set has no own history. Two independent references,
        # or this set's own historical value, are required.
        if own_history is None and len(references) < 2:
            return None
        if not references:
            return None
        return statistics.median(references)

    def numeric_warning_key(self, item, key, value=None):
        field = item.get(key)
        if value is None and field is not None:
            value = self.evaluate_numeric_expression(field.value)
        if value is None:
            return None

        kind = {"weight": "weight", "reps": "reps", "rir": "rir"}[key]
        shown = self.format_numeric_value(value, kind)
        if shown is None:
            return None

        workout_id = ""
        if self.active_workout:
            workout_id = str(self.active_workout.get("workout_id", ""))
        return (
            workout_id,
            str(item.get("exercise_name", "")),
            int(item.get("set_number", 0) or 0),
            key,
            shown,
        )

    def clear_numeric_warning_acknowledgement(self, item, key):
        prefix = (
            str(self.active_workout.get("workout_id", ""))
            if self.active_workout
            else "",
            str(item.get("exercise_name", "")),
            int(item.get("set_number", 0) or 0),
            key,
        )
        self.numeric_warning_acknowledged = {
            warning_key
            for warning_key in self.numeric_warning_acknowledged
            if warning_key[:4] != prefix
        }

    def acknowledge_numeric_value(self, exercise_name, set_number, key, value):
        kind = {"weight": "weight", "reps": "reps", "rir": "rir"}[key]
        numeric = self.evaluate_numeric_expression(value)
        if numeric is None:
            return
        shown = self.format_numeric_value(numeric, kind)
        if shown is None:
            return
        workout_id = (
            str(self.active_workout.get("workout_id", ""))
            if self.active_workout
            else ""
        )
        self.numeric_warning_acknowledged.add(
            (workout_id, str(exercise_name), int(set_number or 0), key, shown)
        )

    def accept_active_numeric_warning(self, item, key):
        warning_key = self.numeric_warning_key(item, key)
        if warning_key is None:
            return
        record = self.numeric_warning_fields.get(id(item.get(key)))
        if record is None:
            return

        self.numeric_warning_acknowledged.add(warning_key)
        record["acknowledged"] = True
        # Accepted unusual input remains visibly orange, but no longer pulses.
        record["field"].text_style = ft.TextStyle(color=ft.Colors.ORANGE_400)

    def restore_numeric_field_style(self, field):
        field.text_style = None
        if getattr(field, "data", None) == "locked_rir":
            field.label_style = ft.TextStyle(
                size=self.fs(12),
                weight=ft.FontWeight.BOLD,
                color=ft.Colors.GREEN_400,
            )

        for item in self.set_controls:
            if field not in (item.get("weight"), item.get("reps"), item.get("rir")):
                continue
            if item.get("completed"):
                field.border_color = ft.Colors.GREEN_500
                field.focused_border_color = ft.Colors.GREEN_400
                field.border_width = 1.8
                field.focused_border_width = 2.0
            else:
                self.clear_field_invalid(field)
            return

        self.clear_field_invalid(field)

    def update_active_numeric_warning(self, item, key):
        field = item.get(key)
        if field is None:
            return
        kind = {"weight": "weight", "reps": "reps", "rir": "rir"}[key]
        value = self.evaluate_numeric_expression(field.value)
        warning_id = id(field)

        if value is None:
            self.numeric_warning_fields.pop(warning_id, None)
            self.restore_numeric_field_style(field)
            return

        reference = self.active_numeric_reference(item, key) if key == "weight" else None
        reason = self.numeric_warning_reason(kind, value, reference)
        if reason:
            warning_key = self.numeric_warning_key(item, key, value)
            acknowledged = warning_key in self.numeric_warning_acknowledged
            self.numeric_warning_fields[warning_id] = {
                "field": field,
                "reason": reason,
                "acknowledged": acknowledged,
            }
            # Orange text only. Borders keep their normal/completed/locked style.
            field.text_style = ft.TextStyle(color=ft.Colors.ORANGE_400)
        else:
            self.numeric_warning_fields.pop(warning_id, None)
            self.restore_numeric_field_style(field)

    def refresh_numeric_warning_styles(self):
        attached = {
            id(field)
            for item in self.set_controls
            for field in (item.get("weight"), item.get("reps"), item.get("rir"))
            if field is not None
        }
        stale = [key for key in self.numeric_warning_fields if key not in attached]
        for key in stale:
            self.numeric_warning_fields.pop(key, None)

        unacknowledged = [
            record
            for record in self.numeric_warning_fields.values()
            if not record.get("acknowledged", False)
        ]
        if not unacknowledged:
            self.numeric_warning_pulse = False
            # Accepted warnings stay solid orange.
            for record in self.numeric_warning_fields.values():
                record["field"].text_style = ft.TextStyle(
                    color=ft.Colors.ORANGE_400
                )
            return False

        self.numeric_warning_pulse = not self.numeric_warning_pulse
        for record in self.numeric_warning_fields.values():
            field = record["field"]
            if record.get("acknowledged", False):
                field.text_style = ft.TextStyle(color=ft.Colors.ORANGE_400)
            else:
                # Slow pulse between two orange shades; the box itself never blinks.
                field.text_style = ft.TextStyle(
                    color=(
                        ft.Colors.ORANGE_300
                        if self.numeric_warning_pulse
                        else ft.Colors.ORANGE_700
                    )
                )
        return True

    def active_numeric_field(
        self,
        value,
        previous,
        label,
        width,
        visible=True,
        suffix_text=None,
        numeric_kind="number",
    ):
        """Typed value starts left; previous/placeholder value stays centered."""
        value = str(value or "")
        previous = str(previous or "")
        width = self.ui(width)
        numeric_text_size = self.fs(15)

        ghost = ft.Text(
            previous or label,
            size=numeric_text_size,
            color=ft.Colors.GREY_500,
            text_align=ft.TextAlign.CENTER,
            max_lines=1,
        )
        ghost.visible = not bool(value.strip())

        # Outlined dense fields otherwise use asymmetric top/bottom padding,
        # which visually pushes the text baseline downward. Keep Flet's
        # natural field height, but use symmetric vertical padding.
        field = self.text_field(
            value=value,
            width=width,
            dense=True,
            text_size=numeric_text_size,
            text_align=ft.TextAlign.LEFT,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind=numeric_kind,
            content_padding=ft.Padding(
                left=self.ui(10),
                top=self.ui(8),
                right=self.ui(27 if suffix_text else 10),
                bottom=self.ui(8),
            ),
            visible=visible,
        )

        stack_controls = [
            ft.Container(
                width=width,
                top=0,
                bottom=0,
                alignment=ft.Alignment.CENTER,
                content=ghost,
            ),
            field,
        ]

        suffix_control = None
        if suffix_text:
            suffix_control = ft.Text(
                suffix_text,
                size=self.fs(10),
                weight=ft.FontWeight.W_500,
                color=ft.Colors.GREY_500,
                visible=bool(value.strip() or previous.strip()),
            )
            stack_controls.append(
                ft.Container(
                    right=self.ui(7),
                    top=0,
                    bottom=0,
                    alignment=ft.Alignment.CENTER,
                    ignore_interactions=True,
                    content=suffix_control,
                )
            )

        wrapper = ft.Stack(
            controls=stack_controls,
            width=width,
            visible=visible,
        )

        def active_numeric_focus(e, target=field):
            self.focused_text_field = target
            self.arm_android_empty_backspace(target)

        field.on_focus = active_numeric_focus
        return field, wrapper, ghost, suffix_control

    def completed_set_bgcolor(self):
        opacity = 0.11 if self.is_dark_mode() else 0.075
        return ft.Colors.with_opacity(opacity, ft.Colors.GREY_500)

    def platform_brightness_changed(self, e):
        if self.settings.get("theme_mode", "system") != "system":
            return

        old_background = self.current_background_color or self.page.bgcolor
        self.apply_settings(
            transition_from=old_background,
            update_page=False,
        )

        # Rebuild the current screen so adaptive custom backgrounds/tints are
        # recalculated along with the Material theme.
        if self.selected_tab == 0:
            if self.active_workout and self.native_back_action is not None:
                self.show_active_workout()
            else:
                self.show_saved_workouts()
        elif self.selected_tab == 1:
            self.show_workout_history()
        elif self.selected_tab == 2:
            self.show_mesocycle()
        elif self.selected_tab == 3:
            self.show_rep_max_table(as_tab=True)
        else:
            self.show_settings()

    def accent_color(self):
        return self.COLOR_MAP.get(
            self.settings.get("accent_color", "purple"),
            ft.Colors.PURPLE,
        )

    def nav_surface_color(self):
        # The sticky workout banner and bottom nav intentionally use
        # exactly the same surface.
        return ft.Colors.with_opacity(0.12, self.accent_color())

    def button_style(self):
        return ft.ButtonStyle(
            shape=ft.RoundedRectangleBorder(radius=self.rounding()),
        )

    def filled_button(self, text, on_click=None, expand=False, **kwargs):
        return ft.FilledButton(
            content=text,
            on_click=on_click,
            expand=expand,
            style=self.button_style(),
            **kwargs,
        )

    def outlined_button(self, text, on_click=None, expand=False, **kwargs):
        return ft.OutlinedButton(
            content=text,
            on_click=on_click,
            expand=expand,
            style=self.button_style(),
            **kwargs,
        )

    def field_border_color(self):
        if self.is_dark_mode():
            return ft.Colors.with_opacity(0.62, ft.Colors.WHITE)
        return ft.Colors.GREY_600

    def field_focused_border_color(self):
        if self.is_dark_mode():
            return ft.Colors.WHITE
        return ft.Colors.GREY_800

    def text_field(self, **kwargs):
        numeric_kind = kwargs.pop("numeric_kind", None)
        kwargs.setdefault("border_radius", self.rounding())
        kwargs.setdefault("border_color", self.field_border_color())
        kwargs.setdefault(
            "focused_border_color",
            self.field_focused_border_color(),
        )
        field = ft.TextField(**kwargs)

        # Track focused TextFields so an empty Backspace can move backward.
        field.on_focus = lambda e, target=field: setattr(
            self, "focused_text_field", target
        )

        if numeric_kind is not None:
            self.numeric_field_kinds[id(field)] = numeric_kind
        elif kwargs.get("keyboard_type") == ft.KeyboardType.NUMBER:
            self.numeric_field_kinds[id(field)] = "number"
        return field

    def register_focus_sequence(self, *fields):
        editable = [
            field
            for field in fields
            if field is not None
            and not getattr(field, "read_only", False)
            and getattr(field, "visible", True)
        ]
        for index, field in enumerate(editable):
            previous = editable[index - 1] if index > 0 else None
            if previous is None:
                self.focus_previous_fields.pop(id(field), None)
            else:
                self.focus_previous_fields[id(field)] = previous
        return editable

    async def handle_keyboard_event(self, e):
        # Flet exposes per-field Submit/Change events, but no TextField key-down
        # callback. Page.on_keyboard_event is therefore used for empty Backspace.
        if str(getattr(e, "key", "")).casefold() != "backspace":
            return

        field = self.focused_text_field
        if field is None:
            return

        # Active numeric fields use the Android-safe sentinel/on_change path.
        if id(field) in self.android_backspace_last_values:
            return

        if self.logical_text_value(field.value):
            return

        previous = self.focus_previous_fields.get(id(field))
        if previous is not None:
            await previous.focus()

    def chain_text_fields(self, *fields):
        """Validate numeric input, then move to the next editable field."""
        editable = self.register_focus_sequence(*fields)

        for index, current in enumerate(editable):
            next_field = editable[index + 1] if index + 1 < len(editable) else None

            async def advance(e, field=current, target=next_field):
                if id(field) in self.numeric_field_kinds:
                    if not self.normalize_numeric_control(field, allow_empty=True):
                        self.page.update()
                        return
                if target is not None:
                    # Direct focus handoff avoids a page rebuild between fields.
                    await target.focus()

            current.on_submit = advance

    def weight_field_with_unit(self, field, width):
        unit_label = ft.Text(
            self.settings.get("unit", "kg"),
            size=self.fs(10),
            weight=ft.FontWeight.W_500,
            color=ft.Colors.GREY_500,
            visible=bool((field.value or "").strip()),
        )

        wrapper = ft.Stack(
            controls=[
                field,
                ft.Container(
                    right=self.ui(7),
                    top=0,
                    bottom=0,
                    alignment=ft.Alignment.CENTER,
                    ignore_interactions=True,
                    content=unit_label,
                ),
            ],
            width=width,
        )

        def sync_unit(e):
            unit_label.visible = bool((field.value or "").strip())
            if (field.value or "").strip():
                self.clear_field_invalid(field)
            self.page.update()

        field.on_change = sync_unit
        return wrapper, unit_label

    def color_swatch(self, name, color, selected, on_click):
        return ft.Container(
            width=38,
            height=38,
            bgcolor=color,
            border_radius=self.rounding(),
            border=ft.Border.all(
                3 if selected else 1,
                self.foreground_color() if selected else ft.Colors.GREY_700,
            ),
            alignment=ft.Alignment.CENTER,
            ink=True,
            on_click=on_click,
            content=(
                ft.Icon(ft.Icons.CHECK, color=self.foreground_color(), size=18)
                if selected
                else None
            ),
        )

    def apply_settings(self, transition_from=None, update_page=True):
        self.settings = storage.read_settings()

        accent = self.accent_color()
        scale = self.font_scale() * self.phone_layout_scale()

        mode_map = {
            "dark": ft.ThemeMode.DARK,
            "light": ft.ThemeMode.LIGHT,
            "system": ft.ThemeMode.SYSTEM,
        }
        self.page.theme_mode = mode_map.get(
            self.settings.get("theme_mode", "system"),
            ft.ThemeMode.SYSTEM,
        )

        def make_text_theme(color):
            return ft.TextTheme(
                body_small=ft.TextStyle(size=12 * scale, color=color),
                body_medium=ft.TextStyle(size=14 * scale, color=color),
                body_large=ft.TextStyle(size=16 * scale, color=color),
                label_large=ft.TextStyle(size=14 * scale, color=color),
                title_medium=ft.TextStyle(size=16 * scale, color=color),
                title_large=ft.TextStyle(size=20 * scale, color=color),
            )

        def overlay_style(dark):
            background = self.background_color(dark=dark)

            # This styles a visible status bar. Actual hide/show on Android is
            # handled natively through WindowInsets below.
            status_icons = (
                ft.Brightness.LIGHT if dark else ft.Brightness.DARK
            )
            navigation_icons = (
                ft.Brightness.LIGHT if dark else ft.Brightness.DARK
            )

            return ft.SystemOverlayStyle(
                status_bar_color=background,
                status_bar_brightness=(
                    ft.Brightness.DARK if dark else ft.Brightness.LIGHT
                ),
                status_bar_icon_brightness=status_icons,
                system_navigation_bar_color=background,
                system_navigation_bar_divider_color=background,
                system_navigation_bar_icon_brightness=navigation_icons,
                enforce_system_status_bar_contrast=False,
                enforce_system_navigation_bar_contrast=False,
            )

        # Keep foreground colors explicit per theme. This prevents stale white
        # text after switching to Light on mobile.
        self.page.theme = ft.Theme(
            color_scheme_seed=accent,
            text_theme=make_text_theme(ft.Colors.BLACK),
            system_overlay_style=overlay_style(False),
        )
        self.page.dark_theme = ft.Theme(
            color_scheme_seed=accent,
            text_theme=make_text_theme(ft.Colors.WHITE),
            system_overlay_style=overlay_style(True),
        )

        target_background = self.background_color()
        self.current_background_color = target_background

        if (
            transition_from is not None
            and transition_from != target_background
        ):
            self.pending_background_from = transition_from
            self.background_transition_generation += 1
            # Keep the native/page surface on the old color until the animated
            # app layer has reached the new one. This avoids the white/black
            # flash that was visible during theme changes.
            self.page.bgcolor = transition_from
        else:
            self.pending_background_from = None
            self.page.bgcolor = target_background

        if self.page.navigation_bar is not None:
            self.page.navigation_bar.indicator_shape = ft.RoundedRectangleBorder(
                radius=self.rounding()
            )
            self.page.navigation_bar.bgcolor = self.nav_surface_color()

        if hasattr(self, "timer_popup"):
            self.update_timer_popup_style()

        if update_page:
            self.page.update()

    def icon_action(
        self,
        icon,
        bgcolor,
        on_click,
        width=44,
        height=44,
        tooltip=None,
    ):
        return ft.Container(
            width=self.ui(width),
            height=self.ui(height),
            bgcolor=bgcolor,
            border_radius=self.rounding(),
            alignment=ft.Alignment.CENTER,
            ink=True,
            on_click=on_click,
            tooltip=tooltip,
            content=ft.Icon(icon, color=ft.Colors.WHITE, size=self.ui(24)),
        )

    def compact_outline_icon(self, icon, on_click, tooltip=None, size=38, icon_size=22):
        """Square icon action for dense rows; avoids Material text-button padding."""
        side = max(self.ui(size), 30.0)
        return ft.Container(
            width=side,
            height=side,
            alignment=ft.Alignment.CENTER,
            ink=True,
            border=ft.Border.all(1, self.field_border_color()),
            border_radius=self.rounding(),
            tooltip=tooltip,
            on_click=on_click,
            content=ft.Icon(
                icon,
                size=max(self.ui(icon_size), 17.0),
                color=self.foreground_color(),
            ),
        )

    def set_ok_button(self, completed=False):
        # Deliberately independent of accent color.
        return ft.Container(
            width=self.ui(self.SET_OK_WIDTH),
            height=self.ui(self.SET_OK_HEIGHT),
            margin=ft.Margin(left=self.ui(8), top=0, right=0, bottom=0),
            alignment=ft.Alignment.CENTER,
            ink=True,
            border_radius=self.rounding(),
            bgcolor=ft.Colors.GREEN_700 if completed else None,
            border=ft.Border.all(1.6, ft.Colors.GREEN_600),
            content=ft.Icon(
                ft.Icons.CHECK,
                size=self.ui(19),
                color=ft.Colors.WHITE if completed else ft.Colors.GREEN_500,
            ),
        )

    def tag_button(self, label, on_click, width=124):
        return ft.Container(
            width=self.ui(width),
            height=self.ui(34),
            alignment=ft.Alignment.CENTER,
            padding=ft.Padding(left=self.ui(7), top=0, right=self.ui(7), bottom=0),
            border=ft.Border.all(1, self.accent_color()),
            border_radius=self.rounding(),
            ink=True,
            tooltip="Change set type",
            on_click=on_click,
            content=ft.Text(
                label,
                size=self.fs(11),
                max_lines=1,
                overflow=ft.TextOverflow.ELLIPSIS,
            ),
        )

    def set_adjust_button(self, symbol, tooltip, on_click):
        return ft.Container(
            width=self.ui(48),
            height=self.ui(38),
            alignment=ft.Alignment.CENTER,
            border=ft.Border.all(
                1,
                ft.Colors.GREY_700,
            ),
            border_radius=self.rounding(),
            ink=True,
            tooltip=tooltip,
            on_click=on_click,
            content=ft.Text(
                symbol,
                size=self.fs(22),
                weight=ft.FontWeight.BOLD,
                text_align=ft.TextAlign.CENTER,
            ),
        )

    def active_set_type_label(self, set_type):
        labels = {
            "Normal": "Straight",
            "Warm-up": "Warmup",
            "Top Set": "Top",
            "Back-off": "Backoff",
            "AMRAP": "AMRAP",
            "Failure": "Failure",
            "Drop Set": "Drop",
            "Mechanical Drop Set": "Mech Drop",
            "Rest-Pause": "RestPause",
            "Myo-Reps": "Myo",
            "Myo-Rep Match": "MyoMatch",
            "Cluster Set": "Cluster",
            "Paused": "Paused",
            "Tempo": "Tempo",
            "Partial": "Partial",
            "Burnout": "Burnout",
        }
        return labels.get(set_type, set_type)

    def active_set_type_content(self, set_type, set_number):
        return ft.Column(
            controls=[
                ft.Text(
                    self.active_set_type_label(set_type),
                    size=self.fs(9),
                    max_lines=1,
                    overflow=ft.TextOverflow.ELLIPSIS,
                    text_align=ft.TextAlign.CENTER,
                ),
                ft.Text(
                    str(set_number),
                    size=self.fs(14),
                    weight=ft.FontWeight.BOLD,
                    text_align=ft.TextAlign.CENTER,
                ),
            ],
            spacing=-2,
            tight=True,
            horizontal_alignment=ft.CrossAxisAlignment.CENTER,
        )

    def active_set_type_button(self, set_type, set_number):
        # Plain text/click target: intentionally no outline or filled background.
        return ft.Container(
            width=self.ui(48),
            height=self.ui(40),
            alignment=ft.Alignment.CENTER,
            ink=True,
            tooltip=f"{set_type} — Set {set_number}",
            content=self.active_set_type_content(set_type, set_number),
        )
