import ast
import asyncio
import math
import time
import uuid
from datetime import datetime

import flet as ft

import storage
import progression


class WorkoutMixin:

    def show_workout_tab(self):
        self.page.navigation_bar.selected_index = 0
        self.selected_tab = 0

        if self.active_workout:
            self.show_active_workout()
        else:
            self.show_saved_workouts()

    def show_saved_workouts(self):
        # If the user leaves an exercise-details detour instead of returning to
        # Edit Workout, discard that one-shot unsaved editor draft.
        self.workout_editor_draft = None
        self.set_controls = []
        controls = []

        cycle_card = self.mesocycle_status_card()
        active_cycle = None
        if cycle_card is not None:
            controls.append(cycle_card)
            active_cycle = storage.active_mesocycle()

        workout_summaries = storage.workout_list_summaries()
        workouts = [
            {"workout_id": row.get("workout_id", ""), "name": row.get("name", "Workout")}
            for row in workout_summaries.values()
        ]
        cycle_rir = self.cycle_rir_target() if active_cycle is not None else None

        # Feature the workout that is actually in progress. If there is no
        # in-progress session, feature today's mesocycle workout instead. This
        # keeps the next/current action at the top without changing saved order.
        featured_workout_id = ""
        featured_label = ""
        if self.active_workout:
            featured_workout_id = str(
                self.active_workout.get("workout_id", "") or ""
            )
            featured_label = "ACTIVE"
        elif active_cycle is not None:
            status = storage.mesocycle_status(active_cycle)
            schedule = storage.mesocycle_day_schedule(
                active_cycle.get("cycle_id", "")
            )
            featured_workout_id = str(
                schedule.get(status.get("day_in_microcycle", 1), "") or ""
            )
            if featured_workout_id:
                featured_label = "TODAY"

        if featured_workout_id:
            workouts.sort(
                key=lambda workout: (
                    0
                    if workout.get("workout_id", "") == featured_workout_id
                    else 1
                )
            )

        if not workouts:
            controls.append(
                ft.Text("No workouts yet. Create one in Manage.")
            )
        else:
            controls.append(
                ft.Column(
                    controls=[
                        self.workout_start_tile(
                            workout,
                            summary=workout_summaries.get(workout.get("workout_id", ""), {}),
                            cycle_rir=cycle_rir,
                            is_featured=(
                                workout.get("workout_id", "")
                                == featured_workout_id
                            ),
                            featured_label=featured_label,
                        )
                        for workout in workouts
                    ],
                    spacing=self.ui(4),
                )
            )

        # Keep cycle progress visually secondary: place the compact heatmap at
        # the bottom of the main Workout content rather than above the workouts.
        if active_cycle is not None:
            controls.extend(
                [
                    ft.Container(height=self.ui(4)),
                    self.cycle_heatmap(active_cycle, compact=True),
                ]
            )

        recent_rows = []

        if self.settings.get("show_recent", "1") == "1":
            recent = storage.recent_sessions(limit=5)

            if recent:

                for session in recent:
                    session_id = session.get("session_id", "")

                    recent_rows.append(
                        ft.Container(
                            width=float("inf"),
                            padding=ft.Padding(
                                left=self.ui(6),
                                top=self.ui(7),
                                right=self.ui(6),
                                bottom=self.ui(7),
                            ),
                            ink=True,
                            on_click=lambda e, sid=session_id: self.show_history_session(
                                sid,
                                back_target="main",
                            ),
                            content=ft.Row(
                                controls=[
                                    ft.Text(
                                        session["workout_name"],
                                        expand=True,
                                    ),
                                    ft.Text(
                                        self.format_recent_datetime(
                                            session["date"]
                                        ),
                                        size=self.fs(11),
                                    ),
                                ],
                                vertical_alignment=ft.CrossAxisAlignment.CENTER,
                            ),
                        )
                    )

        footer_controls = []

        if recent_rows:
            footer_controls.extend(
                [
                    ft.Divider(height=1),
                    ft.Row(
                        controls=[
                            ft.Text(
                                "Recent",
                                size=self.fs(18),
                                weight=ft.FontWeight.BOLD,
                                expand=True,
                            ),
                            ft.Container(
                                padding=ft.Padding(
                                    left=self.ui(8),
                                    top=self.ui(4),
                                    right=self.ui(8),
                                    bottom=self.ui(4),
                                ),
                                ink=True,
                                on_click=lambda e: self.show_workout_history(),
                                content=ft.Text(
                                    "History",
                                    size=self.fs(12),
                                    weight=ft.FontWeight.BOLD,
                                ),
                            ),
                        ],
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    ft.Column(
                        controls=recent_rows,
                        spacing=0,
                    ),
                ]
            )

        workout_footer = (
            ft.Container(
                content=ft.Column(
                    controls=footer_controls,
                    spacing=2,
                ),
            )
            if footer_controls
            else None
        )

        new_workout_button = ft.Container(
            right=self.ui(8),
            bottom=self.ui(8),
            width=46,
            height=46,
            bgcolor=self.accent_color(),
            border_radius=self.rounding(),
            alignment=ft.Alignment.CENTER,
            ink=True,
            tooltip="New workout",
            on_click=self.create_workout,
            content=ft.Icon(
                ft.Icons.ADD,
                color=ft.Colors.WHITE,
                size=26,
            ),
        )

        self.set_view(
            controls,
            footer=workout_footer,
            floating=new_workout_button,
            hide_active_return_bar=True,
        )

    def start_workout(self, workout_id):
        workout = storage.read_workout(workout_id)

        if workout is None:
            self.notify("Workout not found.")
            return

        if not any(exercise.get("sets") for exercise in workout["exercises"]):
            self.edit_workout_from_workout_tab(workout_id)
            return

        if self.active_workout:
            if self.active_workout.get("workout_id") == workout_id:
                # The user explicitly opened the active workout from the saved
                # workout list, so Back should return to that list.
                self.active_workout_back_mode = "saved"
                self.show_active_workout()
            else:
                self.notify("Finish or discard the current workout before starting another one.")
            return

        self.active_workout = storage.build_active_workout(workout)
        self.active_workout_back_mode = "saved"
        self.rir_lock_warning_workout_id = workout_id
        self.rir_lock_warning_count = 0
        storage.save_active_workout(self.active_workout)
        self.show_active_workout()

    def active_workout_header(self):
        cycle_rir = self.cycle_rir_target()

        edit_button = self.icon_action(
            ft.Icons.EDIT,
            ft.Colors.BLUE_700,
            self.show_active_workout_editor,
            width=46,
            height=46,
            tooltip="Edit current workout",
        )

        save_button = self.icon_action(
            ft.Icons.SAVE,
            ft.Colors.GREEN_700,
            self.finish_workout,
            width=54,
            height=46,
            tooltip="Save workout",
        )

        delete_button = self.icon_action(
            ft.Icons.DELETE,
            ft.Colors.RED_700,
            self.discard_workout,
            width=46,
            height=46,
            tooltip="Discard workout",
        )

        self.workout_timer_play_icon = ft.Icon(
            ft.Icons.PLAY_ARROW,
            size=self.ui(25),
            color=ft.Colors.WHITE,
        )
        self.workout_timer_pause_icon = ft.Icon(
            ft.Icons.PAUSE,
            size=self.ui(24),
            color=ft.Colors.WHITE,
            visible=False,
        )
        self.workout_elapsed_text = ft.Text(
            self.format_workout_elapsed(),
            size=self.fs(18),
            weight=ft.FontWeight.BOLD,
            text_align=ft.TextAlign.CENTER,
            no_wrap=True,
        )
        self.workout_target_text = ft.Text(
            f"~{self.format_target_duration(storage.estimate_active_workout_seconds(self.active_workout))}",
            size=self.fs(9.5),
            color=ft.Colors.GREY_500,
            text_align=ft.TextAlign.CENTER,
        )

        # Fixed icon and time slots prevent 00:00 from moving. The icon
        # slot stays reserved even while the running-state icon is hidden.
        timer_content = ft.Container(
            width=self.ui(108),
            height=self.ui(52),
            alignment=ft.Alignment.CENTER,
            ink=True,
            tooltip="Tap to start/pause/resume · hold to reset",
            on_click=self.toggle_workout_clock,
            on_long_press=lambda e: self.reset_workout_clock(),
            content=ft.Column(
                controls=[
                    ft.Row(
                        controls=[
                            ft.Container(
                                width=self.ui(27),
                                height=self.ui(27),
                                alignment=ft.Alignment.CENTER,
                                content=ft.Stack(
                                    controls=[
                                        ft.Container(
                                            alignment=ft.Alignment.CENTER,
                                            content=self.workout_timer_play_icon,
                                        ),
                                        ft.Container(
                                            alignment=ft.Alignment.CENTER,
                                            content=self.workout_timer_pause_icon,
                                        ),
                                    ],
                                    width=self.ui(27),
                                    height=self.ui(27),
                                ),
                            ),
                            ft.Container(
                                width=self.ui(58),
                                height=self.ui(27),
                                alignment=ft.Alignment.CENTER,
                                content=self.workout_elapsed_text,
                            ),
                        ],
                        spacing=self.ui(1),
                        alignment=ft.MainAxisAlignment.CENTER,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    self.workout_target_text,
                ],
                spacing=-2,
                tight=True,
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )
        self.refresh_workout_clock_controls()
        timer_box = timer_content

        return ft.Container(
            bgcolor=self.nav_surface_color(),
            padding=ft.Padding(
                left=self.ui(12), top=self.ui(8),
                right=self.ui(12), bottom=self.ui(8),
            ),
            content=ft.Row(
                controls=[
                    ft.Column(
                        controls=[
                            ft.Text(
                                self.active_workout["workout_name"],
                                size=self.fs(25),
                                weight=ft.FontWeight.BOLD,
                                max_lines=1,
                                overflow=ft.TextOverflow.ELLIPSIS,
                            ),
                            self.active_progress_text,
                        ],
                        spacing=0,
                        expand=True,
                        alignment=ft.MainAxisAlignment.CENTER,
                    ),
                    timer_box,
                    edit_button,
                    save_button,
                    delete_button,
                ],
                spacing=self.ui(6),
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

    def active_rows_for_added_exercise(self, exercise_name):
        """Build current-session rows without changing the workout template."""
        exercise_name = (exercise_name or "").strip()
        if not exercise_name:
            return []

        settings = storage.read_settings()
        default_sets = max(1, int(settings.get("default_sets", "3") or 3))
        default_rest = int(settings.get("default_rest_seconds", "180") or 180)

        template_sets = []
        template = storage.read_workout(self.active_workout["workout_id"])
        if template is not None:
            for exercise in template.get("exercises", []):
                if exercise.get("exercise_name", "").casefold() == exercise_name.casefold():
                    template_sets = list(exercise.get("sets", []))
                    break

        if not template_sets:
            template_sets = [
                {
                    "weight": "",
                    "reps": "",
                    "rest_seconds": str(default_rest),
                    "set_type": "Normal",
                }
                for _ in range(default_sets)
            ]

        previous = storage.latest_exercise_values(exercise_name)
        rows = []

        for set_number, set_row in enumerate(template_sets, start=1):
            prev = previous.get(set_number, {})
            rows.append(
                {
                    "exercise_name": exercise_name,
                    "set_number": set_number,
                    "weight": "",
                    "reps": "",
                    "rir": "",
                    "previous_weight": str(
                        prev.get("weight", "") or set_row.get("weight", "") or ""
                    ),
                    # Never surface the reps performed in the previous session.
                    # A configured template rep value may still be used internally,
                    # but historical reps are not shown as workout ghost text.
                    "previous_reps": str(set_row.get("reps", "") or ""),
                    "previous_rir": str(prev.get("rir", "") or ""),
                    "set_type": set_row.get("set_type", "Normal") or "Normal",
                    "note": "",
                    "completed": False,
                    "calibration_done": False,
                    "rest_seconds": storage.parse_duration(
                        set_row.get("rest_seconds", ""),
                        default=default_rest,
                    ),
                }
            )

        return rows

    def add_exercise_to_active_workout(self, exercise_name):
        exercise_name = (exercise_name or "").strip()
        if not exercise_name:
            return

        existing = {
            row.get("exercise_name", "").casefold()
            for row in self.active_workout.get("rows", [])
        }
        if exercise_name.casefold() in existing:
            self.notify("That exercise is already in the current workout.")
            return

        storage.add_catalog_exercise(exercise_name)
        self.active_workout["rows"].extend(
            self.active_rows_for_added_exercise(exercise_name)
        )
        storage.save_active_workout(self.active_workout)
        self.show_active_workout_editor()

    def remove_exercise_from_active_workout(self, exercise_name):
        rows = [
            row
            for row in self.active_workout.get("rows", [])
            if row.get("exercise_name") == exercise_name
        ]

        if any(row.get("completed") for row in rows):
            self.notify("Completed exercises cannot be removed from the current session.")
            return

        self.active_workout["rows"] = [
            row
            for row in self.active_workout.get("rows", [])
            if row.get("exercise_name") != exercise_name
        ]
        if self.timer_exercise_name == exercise_name:
            self.dismiss_timer(silent=True)
        storage.save_active_workout(self.active_workout)
        self.show_active_workout_editor()

    def show_active_workout_editor(self, e=None):
        if not self.active_workout:
            self.show_saved_workouts()
            return

        if self.set_controls:
            self.capture_active_controls()
        # The editor works directly on active_workout rows. Do not let stale
        # controls from the workout screen overwrite session-only edits.
        self.set_controls = []

        self.selected_tab = 0
        self.page.navigation_bar.selected_index = 0

        ordered = []
        grouped = {}
        for row in self.active_workout.get("rows", []):
            name = row.get("exercise_name", "")
            if name not in grouped:
                grouped[name] = []
                ordered.append(name)
            grouped[name].append(row)

        controls = [
            ft.Text(
                "Changes here affect only this workout session, not the saved template.",
                size=self.fs(11),
                color=ft.Colors.GREY_500,
            )
        ]

        for name in ordered:
            rows = grouped[name]
            completed = sum(1 for row in rows if row.get("completed"))
            controls.append(
                ft.Container(
                    width=float("inf"),
                    padding=ft.Padding(left=self.ui(12), top=self.ui(10), right=self.ui(6), bottom=self.ui(10)),
                    border=ft.Border.all(1, ft.Colors.with_opacity(0.28, self.foreground_color())),
                    border_radius=self.rounding(),
                    content=ft.Row(
                        controls=[
                            ft.Column(
                                controls=[
                                    ft.Text(
                                        name,
                                        size=self.fs(17),
                                        weight=ft.FontWeight.BOLD,
                                    ),
                                    ft.Text(
                                        f"{len(rows)} sets · {completed} completed",
                                        size=self.fs(11),
                                        color=ft.Colors.GREY_500,
                                    ),
                                ],
                                spacing=0,
                                expand=True,
                            ),
                            ft.IconButton(
                                icon=ft.Icons.DELETE_OUTLINE,
                                icon_color=ft.Colors.RED_400,
                                tooltip="Remove from this session",
                                on_click=lambda e, exercise=name: self.remove_exercise_from_active_workout(
                                    exercise
                                ),
                            ),
                        ],
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                )
            )

        controls.append(
            ft.Container(
                width=float("inf"),
                height=46,
                bgcolor=ft.Colors.BLUE_700,
                border_radius=self.rounding(),
                alignment=ft.Alignment.CENTER,
                ink=True,
                on_click=lambda e: self.open_exercise_picker(
                    self.add_exercise_to_active_workout
                ),
                content=ft.Row(
                    controls=[
                        ft.Icon(ft.Icons.ADD, color=ft.Colors.WHITE, size=20),
                        ft.Text(
                            "Add Exercise",
                            color=ft.Colors.WHITE,
                            weight=ft.FontWeight.BOLD,
                        ),
                    ],
                    alignment=ft.MainAxisAlignment.CENTER,
                    spacing=self.ui(6),
                ),
            )
        )

        header = ft.Container(
            bgcolor=self.nav_surface_color(),
            padding=ft.Padding(left=self.ui(12), top=self.ui(8), right=self.ui(12), bottom=self.ui(8)),
            content=ft.Row(
                controls=[
                    ft.Text(
                        "Edit Current Workout",
                        size=self.fs(21),
                        weight=ft.FontWeight.BOLD,
                        expand=True,
                    ),
                    ft.Container(
                        height=self.ui(40),
                        padding=ft.Padding(left=self.ui(14), top=0, right=self.ui(14), bottom=0),
                        bgcolor=ft.Colors.BLUE_700,
                        border_radius=self.rounding(),
                        alignment=ft.Alignment.CENTER,
                        ink=True,
                        on_click=lambda e: self.show_active_workout(),
                        content=ft.Text(
                            "Done",
                            color=ft.Colors.WHITE,
                            weight=ft.FontWeight.BOLD,
                        ),
                    ),
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

        self.set_view(
            controls,
            header=header,
            back_action=self.show_active_workout,
            hide_active_return_bar=True,
        )

    def show_active_workout(self):
        if not self.active_workout:
            self.show_saved_workouts()
            return

        self.set_controls = []

        completed = sum(
            1
            for row in self.active_workout["rows"]
            if row.get("completed", False)
        )
        total = len(self.active_workout["rows"])

        cycle_rir = self.cycle_rir_target()
        progress_value = f"{completed}/{total} sets"
        if cycle_rir is not None:
            progress_value = f"{cycle_rir} RIR · {progress_value}"

        self.active_progress_text = ft.Text(
            progress_value,
            size=self.fs(13.5),
            weight=ft.FontWeight.W_600,
            color=ft.Colors.WHITE,
        )

        controls = []

        grouped = {}
        for row in self.active_workout["rows"]:
            grouped.setdefault(row["exercise_name"], []).append(row)

        for exercise_name, rows in grouped.items():
            controls.extend(self.active_exercise_block(exercise_name, rows))

        # Any mesocycle-prescribed loads written into previously blank fields are
        # real active-workout values, so persist them immediately.
        self.capture_active_controls()
        self.sync_inline_timer()

        active_back_action = (
            self.show_saved_workouts
            if self.active_workout_back_mode == "saved"
            else None
        )

        self.set_view(
            controls,
            header=self.active_workout_header(),
            back_action=active_back_action,
            workout_clock=True,
            hide_active_return_bar=True,
        )

        self.workout_clock_generation += 1
        self.page.run_task(
            self.workout_clock_loop,
            self.workout_clock_generation,
        )

    def exercise_progression_recommendation(self, exercise_name):
        cycle = storage.active_mesocycle()
        if not cycle:
            return None
        status = storage.mesocycle_status(cycle)
        if status.get("phase") not in {"Build", "Deload"}:
            return None
        rows = storage.latest_completed_straight_session(exercise_name)
        if not rows:
            return None
        unit = self.settings.get("unit", "kg")
        return progression.progression_recommendation(
            rows,
            target_rir=status.get("suggested_rir", 0),
            unit=unit,
            phase=status.get("phase", "Build"),
            weight_increment=storage.exercise_weight_increment(
                exercise_name, unit, settings=self.settings
            ),
        )

    def historical_reps_visible_in_workout(self):
        """Historical reps stay hidden in mesocycles unless Advanced Mode opts in."""
        if not storage.active_mesocycle():
            return True
        return (
            self.advanced_mode_enabled()
            and self.settings.get("show_previous_reps", "0") == "1"
        )

    def first_mesocycle_exercise_intro_available(self, exercise_name):
        """Require one first-set calibration per workout/exercise in a mesocycle."""
        cycle = storage.active_mesocycle()
        if not cycle or not self.active_workout:
            return False

        status = storage.mesocycle_status(cycle)
        # Calibration is a build-phase baseline. If an exercise first appears
        # later in the mesocycle, it still gets calibrated on that first encounter.
        if status.get("phase") != "Build":
            return False

        return not storage.mesocycle_intro_seen(
            cycle.get("cycle_id", ""),
            self.active_workout.get("workout_id", ""),
            exercise_name,
        )

    def active_mesocycle_calibration_done(self, exercise_name):
        """Return whether calibration was entered in this unsaved workout."""
        exercise_key = str(exercise_name or "").strip().casefold()
        if not exercise_key:
            return False

        # Prefer live controls so a just-entered calibration is recognized
        # before the active-workout CSV is rebuilt.
        for item in getattr(self, "set_controls", []):
            if (
                str(item.get("exercise_name", "")).strip().casefold()
                == exercise_key
                and item.get("mesocycle_calibration_first")
                and item.get("calibration_done")
            ):
                return True

        if not self.active_workout:
            return False
        return any(
            str(row.get("exercise_name", "")).strip().casefold()
            == exercise_key
            and bool(row.get("calibration_done", False))
            for row in self.active_workout.get("rows", [])
        )

    def mesocycle_calibration_context(self, exercise_name, recommendation=None):
        """Return compact prior-set context and a practical first-set load hint."""
        unit = self.settings.get("unit", "kg")
        latest = storage.latest_completed_straight_set(exercise_name)

        latest_weight = ""
        latest_reps = ""
        latest_rir = ""
        latest_appropriate = False
        if latest:
            try:
                weight_value = float(str(latest.get("weight", "") or "").strip())
                reps_value = float(str(latest.get("reps", "") or "").strip())
                latest_weight = progression.format_weight(weight_value)
                latest_reps = f"{reps_value:g}"
                raw_rir = str(latest.get("rir", "") or "").strip()
                if raw_rir:
                    rir_value = float(raw_rir)
                    latest_rir = f"{rir_value:g}"
                # Calibration is intentionally not restricted to a rep/RIR
                # window. Any usable prior straight set can seed the load.
                latest_appropriate = bool(latest_weight and latest_reps)
            except (TypeError, ValueError):
                latest_weight = ""
                latest_reps = ""
                latest_rir = ""
                latest_appropriate = False

        suggested_weight = ""
        if latest_appropriate and latest_weight:
            suggested_weight = latest_weight
        elif recommendation:
            suggested_weight = str(recommendation.get("weight_text", "") or "")
        elif latest_weight:
            suggested_weight = latest_weight

        return {
            "unit": unit,
            "latest_weight": latest_weight,
            "latest_reps": latest_reps,
            "latest_rir": latest_rir,
            "latest_appropriate": latest_appropriate,
            "suggested_weight": suggested_weight,
        }

    def show_first_mesocycle_exercise_intro(
        self, exercise_name, target_item, recommendation=None
    ):
        """Open the calibration workflow from the calibration card."""
        if not self.first_mesocycle_exercise_intro_available(exercise_name):
            return

        cycle = storage.active_mesocycle()
        if not cycle or not self.active_workout:
            return

        context = self.mesocycle_calibration_context(
            exercise_name, recommendation=recommendation
        )
        unit = context["unit"]
        latest_weight = context["latest_weight"]
        latest_reps = context["latest_reps"]
        latest_rir = context["latest_rir"]
        latest_appropriate = context["latest_appropriate"]
        suggested_weight = context["suggested_weight"]

        weight_field = self.text_field(
            value=suggested_weight,
            label="Weight",
            width=self.ui(112),
            dense=True,
            text_align=ft.TextAlign.CENTER,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="weight",
        )
        reps_field = self.text_field(
            value="",
            label="Reps",
            width=self.ui(92),
            dense=True,
            text_align=ft.TextAlign.CENTER,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="reps",
        )
        rir_field = self.text_field(
            value="",
            label="RIR",
            width=self.ui(82),
            dense=True,
            text_align=ft.TextAlign.CENTER,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="rir",
        )
        self.chain_text_fields(weight_field, reps_field, rir_field)

        # Keep this copy intentionally stable. It is the fuller calibration
        # explanation shown after the user taps the compact card, while the
        # normal workout screen stays quiet.
        controls = [
            ft.Text(
                "Establish this exercise for the new mesocycle",
                weight=ft.FontWeight.BOLD,
            ),
            ft.Text(
                "Do one honest straight set and record the actual weight, reps, "
                "and RIR below. Calibration has no required rep or RIR window; "
                "Gymer uses the result as the starting point for this mesocycle."
            ),
        ]

        if latest_weight and latest_reps:
            rir_text = latest_rir if latest_rir else "—"
            controls.append(
                ft.Container(
                    width=float("inf"),
                    padding=self.ui(10),
                    border=ft.Border.all(1, ft.Colors.GREY_700),
                    border_radius=self.rounding(),
                    content=ft.Column(
                        controls=[
                            ft.Text(
                                "Latest straight set",
                                size=self.fs(11),
                                weight=ft.FontWeight.BOLD,
                            ),
                            ft.Text(
                                f"{latest_weight} {unit} × {latest_reps} reps · {rir_text} RIR",
                                size=self.fs(13),
                            ),
                        ],
                        spacing=2,
                        tight=True,
                    ),
                )
            )

        if latest_appropriate and suggested_weight:
            controls.append(
                ft.Text(
                    f"Your latest usable straight-set load is "
                    f"{suggested_weight} {unit}.",
                    weight=ft.FontWeight.BOLD,
                )
            )
        elif suggested_weight:
            controls.append(
                ft.Text(
                    f"Suggested starting weight: {suggested_weight} {unit}",
                    weight=ft.FontWeight.BOLD,
                )
            )
        else:
            controls.append(
                ft.Text(
                    "There is not enough useful history to estimate a starting "
                    "weight. Pick a sensible load and use this calibration set "
                    "to establish one.",
                    size=self.fs(11),
                )
            )

        controls.extend(
            [
                ft.Text(
                    "Record the calibration set",
                    weight=ft.FontWeight.BOLD,
                ),
                ft.Row(
                    controls=[
                        weight_field,
                        ft.Text(unit, size=self.fs(11)),
                        reps_field,
                        rir_field,
                    ],
                    spacing=self.ui(6),
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Text(
                    "Use the result you actually achieved; no rep or RIR target "
                    "is required for calibration.",
                    size=self.fs(10),
                    color=ft.Colors.GREY_500,
                ),
            ]
        )

        def use_calibration(e):
            valid = True
            for field, kind in (
                (weight_field, "weight"),
                (reps_field, "reps"),
                (rir_field, "rir"),
            ):
                if not self.normalize_numeric_control(
                    field, kind=kind, allow_empty=False
                ):
                    valid = False

            if not valid:
                self.page.update()
                return

            weight_value = float(weight_field.value)
            reps_value = int(float(reps_field.value))
            rir_value = float(rir_field.value)

            weight_text = progression.format_weight(weight_value)
            reps_text = str(reps_value)
            rir_text = progression.format_weight(rir_value)

            # The dialog records the actual calibration result into set 1.
            # Later sets keep the quieter workflow: they receive only the
            # calibrated weight as ghost guidance from
            # complete_mesocycle_exercise_calibration().
            target_item["weight"].value = weight_text
            target_item["reps"].value = reps_text
            if target_item.get("rir") is not None:
                target_item["rir"].value = rir_text

            for key in ("weight", "reps", "rir"):
                field = target_item.get(key)
                if field is not None:
                    self.clear_field_invalid(field)
                ghost = target_item.get(f"{key}_ghost")
                if ghost is not None:
                    ghost.visible = False

            unit_label = target_item.get("weight_unit")
            if unit_label is not None:
                unit_label.visible = True

            self.complete_mesocycle_exercise_calibration(target_item)
            self.capture_active_controls()
            self.close_dialog(dialog)
            self.page.update()

        def skip_calibration(e):
            # "Skip" only dismisses the explanation for now. The compact card
            # stays until the workout itself is saved.
            self.close_dialog(dialog)

        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text(f"Mesocycle calibration · {exercise_name}"),
            content=ft.Container(
                width=min(self.ui(430), max(self.ui(280), float(getattr(self.page, "width", 430) or 430) - self.ui(28))),
                height=self.ui(520),
                content=ft.Column(
                    controls=controls,
                    spacing=self.ui(10),
                    tight=True,
                    scroll=ft.Scrollbar(
                        thumb_visibility=False,
                        track_visibility=False,
                        interactive=False,
                    ),
                ),
            ),
            actions=[
                self.outlined_button("Skip", on_click=skip_calibration),
                self.filled_button("Use calibration set", on_click=use_calibration),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.show_dialog(dialog)

    def mesocycle_calibration_card(
        self, exercise_name, target_item, recommendation=None
    ):
        """Compact persistent prompt; a normal tap opens calibration."""
        if not self.first_mesocycle_exercise_intro_available(exercise_name):
            return None

        context = self.mesocycle_calibration_context(
            exercise_name, recommendation=recommendation
        )
        unit = context["unit"]
        suggested = context["suggested_weight"]

        calibration_entered = self.active_mesocycle_calibration_done(
            exercise_name
        )
        if calibration_entered:
            instruction = "Calibration entered · save the workout to keep it."
        elif suggested:
            instruction = f"Suggested starting load: ~{suggested} {unit}."
        else:
            instruction = "Record an honest straight set to establish a baseline."

        details = []
        if context["latest_weight"] and context["latest_reps"]:
            rir = context["latest_rir"] or "—"
            details.append(
                ft.Text(
                    f"Last straight set: {context['latest_weight']} {unit} × "
                    f"{context['latest_reps']} · {rir} RIR",
                    size=self.fs(10),
                    color=ft.Colors.GREY_500,
                    max_lines=1,
                    overflow=ft.TextOverflow.ELLIPSIS,
                )
            )

        def open_calibration(e):
            self.show_first_mesocycle_exercise_intro(
                exercise_name,
                target_item,
                recommendation=recommendation,
            )

        calibration_title = ft.Text(
            "Calibration entered" if calibration_entered else "Tap to calibrate",
            size=self.fs(12),
            weight=ft.FontWeight.BOLD,
        )
        calibration_instruction = ft.Text(instruction, size=self.fs(11))

        card = ft.Container(
            width=float("inf"),
            padding=ft.Padding(left=self.ui(10), top=self.ui(8), right=self.ui(10), bottom=self.ui(8)),
            margin=ft.Margin(left=0, top=2, right=0, bottom=self.ui(5)),
            border=ft.Border.all(1, self.accent_color()),
            border_radius=self.rounding(),
            bgcolor=ft.Colors.with_opacity(0.08, self.accent_color()),
            ink=True,
            on_click=open_calibration,
            tooltip="Tap to calibrate this exercise's first straight set",
            content=ft.Column(
                controls=[
                    calibration_title,
                    calibration_instruction,
                    *details,
                ],
                spacing=2,
                tight=True,
            ),
        )
        target_item["calibration_card"] = card
        target_item["calibration_title"] = calibration_title
        target_item["calibration_instruction"] = calibration_instruction
        return card

    def complete_mesocycle_exercise_calibration(self, target):
        """Record unsaved calibration and expose load guidance for later sets."""
        cycle = storage.active_mesocycle()
        if not cycle or not self.active_workout:
            return

        exercise_name = target.get("exercise_name", "")
        # Calibration belongs to the active workout until that workout is saved.
        # Do not mark the mesocycle placement as calibrated yet: otherwise merely
        # entering calibration and leaving an unsaved workout would suppress the
        # prompt (and its first-set RIR field) on the next render.
        target["calibration_done"] = True

        card = target.get("calibration_card")
        if card is not None:
            card.visible = True
        calibration_title = target.get("calibration_title")
        if calibration_title is not None:
            calibration_title.value = "Calibration entered"
        calibration_instruction = target.get("calibration_instruction")
        if calibration_instruction is not None:
            calibration_instruction.value = (
                "Calibration entered · save the workout to keep it."
            )

        weight_text = self.logical_text_value(target.get("weight").value)
        if not weight_text:
            return

        # Before calibration, only set 1 gets a load hint. Once that set is
        # performed successfully, later straight sets may inherit its load as
        # ghost text. Reps/RIR are deliberately not propagated here.
        for item in self.set_controls:
            if (
                item is target
                or item.get("exercise_name") != exercise_name
                or item.get("completed")
                or item.get("set_number", 0) <= target.get("set_number", 0)
            ):
                continue
            if str(item.get("set_type", "Normal") or "Normal").strip().casefold() not in {
                "normal",
                "straight",
            }:
                continue
            if self.logical_text_value(item.get("weight").value):
                continue

            item["previous_weight"] = weight_text
            ghost = item.get("weight_ghost")
            if ghost is not None:
                ghost.value = weight_text
                ghost.visible = True
            unit_label = item.get("weight_unit")
            if unit_label is not None:
                unit_label.visible = True

    def active_exercise_block(self, exercise_name, initial_rows):
        rows_column = ft.Column(spacing=self.ui(self.set_spacing()))
        exercise_items = []
        note_containers = []

        notes_visible = any(
            bool((row.get("note", "") or "").strip())
            for row in initial_rows
        )

        planned_rest_mode = self.planned_rest_display_mode()
        rest_values = {
            storage.parse_duration(row.get("rest_seconds", "180"), default=180)
            for row in initial_rows
        }
        exercise_has_irregular_rest = len(rest_values) > 1

        initially_complete = bool(initial_rows) and all(
            bool(row.get("completed", False)) for row in initial_rows
        )
        block_state = {
            "collapsed": (
                initially_complete
                and self.collapse_completed_exercises_enabled()
            ),
            "body": None,
            "collapse_icon": None,
        }

        notes_icon = ft.IconButton(
            icon=(ft.Icons.NOTES if notes_visible else ft.Icons.NOTES_OUTLINED),
            icon_size=self.ui(20),
            width=self.ui(31),
            height=self.ui(31),
            padding=0,
            tooltip="Show/hide set notes",
        )

        def toggle_notes(e):
            nonlocal notes_visible
            notes_visible = not notes_visible
            notes_icon.icon = (
                ft.Icons.NOTES if notes_visible else ft.Icons.NOTES_OUTLINED
            )
            for container in note_containers:
                container.visible = notes_visible
            self.page.update()

        notes_icon.on_click = toggle_notes

        collapse_icon = ft.IconButton(
            icon=(
                ft.Icons.CHEVRON_RIGHT
                if block_state["collapsed"]
                else ft.Icons.EXPAND_MORE
            ),
            icon_size=self.ui(22),
            width=self.ui(31),
            height=self.ui(31),
            padding=0,
            tooltip="Expand/collapse exercise",
        )
        block_state["collapse_icon"] = collapse_icon

        def toggle_collapse(e):
            block_state["collapsed"] = not block_state["collapsed"]
            body = block_state.get("body")
            if body is not None:
                body.visible = not block_state["collapsed"]
            collapse_icon.icon = (
                ft.Icons.CHEVRON_RIGHT
                if block_state["collapsed"]
                else ft.Icons.EXPAND_MORE
            )
            self.page.update()

        collapse_icon.on_click = toggle_collapse

        exercise_name_control = ft.Text(
            exercise_name,
            size=self.fs(19),
            weight=ft.FontWeight.BOLD,
            expand=True,
            max_lines=1,
            no_wrap=True,
        )

        exercise_info_button = ft.Container(
            width=self.ui(30),
            height=self.ui(30),
            alignment=ft.Alignment.CENTER,
            ink=True,
            tooltip=f"Open {exercise_name} details",
            on_click=lambda e: self.show_exercise_details(exercise_name),
            content=ft.Icon(
                ft.Icons.INFO_OUTLINE,
                size=self.ui(18),
            ),
        )

        rep_max_button = ft.IconButton(
            icon=ft.Icons.CALCULATE_OUTLINED,
            icon_size=self.ui(19),
            width=self.ui(31),
            height=self.ui(31),
            padding=0,
            tooltip=f"{exercise_name} Rep Max Calculator",
            on_click=lambda e: self.open_exercise_rep_max(exercise_name),
        )

        substitute_button = ft.IconButton(
            icon=ft.Icons.REFRESH,
            icon_size=self.ui(20),
            width=self.ui(31),
            height=self.ui(31),
            padding=0,
            tooltip="Substitute exercise",
            on_click=lambda e: self.request_substitution(exercise_name),
        )

        heading = ft.Row(
            controls=[
                collapse_icon,
                exercise_name_control,
                rep_max_button,
                exercise_info_button,
                notes_icon,
                substitute_button,
            ],
            spacing=self.ui(2),
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
        )

        progression_recommendation = self.exercise_progression_recommendation(exercise_name)
        calibration_required = self.first_mesocycle_exercise_intro_available(
            exercise_name
        )
        calibration_context = (
            self.mesocycle_calibration_context(
                exercise_name, recommendation=progression_recommendation
            )
            if calibration_required
            else None
        )
        first_straight_initial = next(
            (
                row
                for row in initial_rows
                if str(row.get("set_type", "Normal") or "Normal").strip().casefold()
                in {"normal", "straight"}
            ),
            None,
        )
        completed_first_weight = ""
        if first_straight_initial and bool(first_straight_initial.get("completed")):
            completed_first_weight = str(
                first_straight_initial.get("weight", "") or ""
            ).strip()
        show_historical_reps = self.historical_reps_visible_in_workout()
        historical_by_set = (
            storage.latest_set_values(
                self.active_workout.get("workout_id", ""), exercise_name
            )
            if show_historical_reps and self.active_workout
            else {}
        )

        def last_editable_numeric_key(current):
            rir_field = current.get("rir")
            if (
                (self.track_rir_enabled() or current.get("mesocycle_calibration_first"))
                and rir_field is not None
                and not rir_field.read_only
            ):
                return "rir"
            return "reps"

        async def focus_next_numeric(current, current_key):
            """Move within a set; crossing to the next set is optional."""
            if current not in exercise_items:
                return

            candidate = None
            if current_key == "weight":
                candidate = current.get("reps")
            elif current_key == "reps":
                rir_field = current.get("rir")
                if (
                    (self.track_rir_enabled() or current.get("mesocycle_calibration_first"))
                    and rir_field is not None
                    and not rir_field.read_only
                ):
                    candidate = rir_field

            if (
                candidate is None
                and current_key == last_editable_numeric_key(current)
                and self.enter_moves_to_next_set_enabled()
            ):
                index = exercise_items.index(current)
                if index + 1 < len(exercise_items):
                    candidate = exercise_items[index + 1].get("weight")

            if candidate is not None:
                await self.focus_text_field_at_end(candidate)

        def make_row(row_data):
            set_number = len(exercise_items) + 1
            item_id = uuid.uuid4().hex

            previous_weight = str(row_data.get("previous_weight", "") or "")
            previous_rir = str(row_data.get("previous_rir", "") or "")
            row_completed = bool(row_data.get("completed", False))
            set_type = row_data.get("set_type", "Normal") or "Normal"
            straight_set = str(set_type).strip().casefold() in {"normal", "straight"}
            first_straight_set = straight_set and not any(
                str(existing.get("set_type", "Normal") or "Normal").strip().casefold()
                in {"normal", "straight"}
                for existing in exercise_items
            )
            calibration_first_set = calibration_required and first_straight_set

            previous_reps = ""
            if show_historical_reps:
                previous_reps = str(row_data.get("previous_reps", "") or "")
                if not previous_reps:
                    previous_reps = str(
                        historical_by_set.get(set_number, {}).get("reps", "") or ""
                    )

            # A new workout/exercise placement must calibrate set 1 before we
            # prescribe later sets. Until then, only set 1 may show a suggested
            # load, and it is ghost text rather than an actual entered value.
            current_weight = str(row_data.get("weight", "") or "")
            weight_placeholder = previous_weight
            if calibration_required and straight_set and not row_completed:
                if calibration_first_set:
                    weight_placeholder = str(
                        (calibration_context or {}).get("suggested_weight", "") or ""
                    )
                else:
                    weight_placeholder = ""
            elif (
                completed_first_weight
                and straight_set
                and not row_completed
                and not current_weight.strip()
            ):
                # After set 1 establishes the session load, preserve that live
                # calibration as the later-set ghost instead of re-injecting an
                # older session's progression prescription on a UI rebuild.
                weight_placeholder = completed_first_weight
            elif (
                progression_recommendation
                and straight_set
                and not row_completed
                and not current_weight.strip()
            ):
                current_weight = str(
                    progression_recommendation.get("weight_text", "") or ""
                )
                if current_weight:
                    row_data["weight"] = current_weight

            # During an active mesocycle the planned RIR remains the effort
            # target. Advanced Mode can deliberately unlock the field.
            planned_rir = self.cycle_rir_target()
            rir_locked = (
                planned_rir is not None
                and self.cycle_rir_lock_enabled()
                and not calibration_first_set
            )
            if planned_rir is not None and not calibration_first_set:
                previous_rir = planned_rir
            elif calibration_first_set:
                # Calibration must record what the user actually achieved; do
                # not let the normal mesocycle RIR target auto-fill this field.
                previous_rir = ""

            weight, weight_wrap, weight_ghost, weight_unit = self.active_numeric_field(
                current_weight,
                weight_placeholder,
                "Weight",
                self.SET_WEIGHT_WIDTH,
                suffix_text=self.settings.get("unit", "kg"),
                numeric_kind="weight",
            )
            reps, reps_wrap, reps_ghost, _ = self.active_numeric_field(
                row_data.get("reps", ""),
                previous_reps,
                "Reps",
                self.SET_SMALL_WIDTH,
                numeric_kind="reps",
            )
            reps_display = reps_wrap
            initial_rir = str(row_data.get("rir", "") or "")

            rir, rir_wrap, rir_ghost, _ = self.active_numeric_field(
                initial_rir,
                previous_rir,
                "RIR",
                self.SET_SMALL_WIDTH,
                visible=(
                    self.track_rir_enabled()
                    or planned_rir is not None
                    or calibration_first_set
                ),
                numeric_kind="rir",
            )
            if planned_rir is not None:
                rir.tooltip = f"Mesocycle target: {planned_rir} RIR"
            if rir_locked:
                # A calibration set may have recorded an actual RIR in an
                # unfinished first set. Preserve that value across rerenders; all
                # other locked rows keep the prescribed mesocycle RIR.
                rir.value = initial_rir or str(planned_rir)
                rir.data = "locked_rir"
                rir.read_only = True
                rir.show_cursor = False
                rir_ghost.visible = False
                rir_wrap = ft.Container(width=0, visible=False)
            note = self.text_field(
                hint_text="Note",
                value=row_data.get("note", ""),
                expand=True,
                dense=True,
            )

            completed = row_completed
            rest_seconds = storage.parse_duration(
                row_data.get("rest_seconds", "180"), default=180
            )
            finish = self.set_ok_button(completed)
            type_button = self.active_set_type_button(set_type, set_number)

            item = {
                "id": item_id,
                "exercise_name": exercise_name,
                "set_number": set_number,
                "weight": weight,
                "reps": reps,
                "rir": rir,
                "weight_wrap": weight_wrap,
                "reps_wrap": reps_wrap,
                "rir_wrap": rir_wrap,
                "weight_ghost": weight_ghost,
                "weight_unit": weight_unit,
                "reps_ghost": reps_ghost,
                "rir_ghost": rir_ghost,
                "previous_weight": (
                    weight_placeholder
                    if calibration_required and straight_set
                    else previous_weight
                ),
                # Keep the real historical value separate from UI ghost/prescribed
                # weights. Numeric warnings must never mistake app guidance for
                # evidence of what the user normally lifts.
                "weight_warning_reference": previous_weight,
                "previous_reps": previous_reps,
                "previous_rir": previous_rir,
                "note": note,
                "completed": completed,
                "rest_seconds": rest_seconds,
                "set_type": set_type,
                "finish": finish,
                "type_button": type_button,
                "block_state": block_state,
                "mesocycle_calibration_first": calibration_first_set,
                "calibration_done": bool(row_data.get("calibration_done", False)),
            }

            self.update_completed_field_outlines(item)

            finish.on_click = lambda e, current=item: self.toggle_set_complete(current)
            type_button.on_click = lambda e, current=item: self.open_set_type_picker(
                current["set_type"],
                lambda selected, target=current: self.change_active_set_type(target, selected),
            )

            exercise_items.append(item)
            self.set_controls.append(item)

            self.active_numeric_context[id(weight)] = (item, "weight")
            self.active_numeric_context[id(reps)] = (item, "reps")
            if (
                (self.track_rir_enabled() or calibration_first_set)
                and rir is not None
                and not rir.read_only
            ):
                self.active_numeric_context[id(rir)] = (item, "rir")

            focus_fields = []
            for focus_item in exercise_items:
                focus_fields.extend([focus_item["weight"], focus_item["reps"]])
                if (
                    (
                        self.track_rir_enabled()
                        or focus_item.get("mesocycle_calibration_first")
                    )
                    and focus_item.get("rir") is not None
                    and not focus_item["rir"].read_only
                ):
                    focus_fields.append(focus_item["rir"])
            self.register_focus_sequence(*focus_fields)

            async def submit_numeric(current, key):
                if not self.resolve_active_numeric_field(current, key):
                    self.page.update()
                    return

                # Enter/OK explicitly accepts a valid unusual value. Keep the
                # text orange as a reminder, but stop its pulse.
                self.accept_active_numeric_warning(current, key)
                self.capture_active_controls()

                is_last = key == last_editable_numeric_key(current)
                if (
                    is_last
                    and not current.get("completed")
                    and self.enter_completes_set_enabled()
                ):
                    # Keyboard completion must never start/resume the workout
                    # clock. The explicit set ✓ keeps its existing timer
                    # behavior. Rest timing still belongs to set completion.
                    self.toggle_set_complete(
                        current,
                        manage_workout_clock=False,
                    )

                await focus_next_numeric(current, key)

            async def submit_weight(e, current=item):
                await submit_numeric(current, "weight")

            async def submit_reps(e, current=item):
                await submit_numeric(current, "reps")

            async def submit_rir(e, current=item):
                await submit_numeric(current, "rir")

            weight.on_submit = submit_weight
            reps.on_submit = submit_reps
            if (self.track_rir_enabled() or calibration_first_set) and not rir.read_only:
                rir.on_submit = submit_rir

            def numeric_change(
                e,
                current,
                key,
                field,
                ghost,
                previous,
                suffix_control=None,
            ):
                moved_back = self.process_android_empty_backspace_change(field)
                logical_value = self.logical_text_value(field.value)

                ghost.visible = not bool(logical_value)
                has_numeric_value = bool(
                    logical_value
                    or self.logical_text_value(previous)
                )
                if suffix_control is not None:
                    suffix_control.visible = has_numeric_value

                if moved_back:
                    # Keep persistence clean and let focus() perform the actual
                    # backward navigation without a full page rebuild.
                    self.capture_active_controls()
                    self.page.schedule_update()
                    return

                # Typing must stay completely presentation-neutral. In
                # particular, do not run unusual-value warnings, validation
                # styling, or a full page update while the IME owns the caret.
                # A page update here could make Android restore an old caret
                # position (for example turning 100 into 001). Warnings and
                # normalization are intentionally deferred to blur/Submit.
                parsed_value = self.evaluate_numeric_expression(logical_value)

                # Save blanks and currently valid expressions so an active
                # workout remains crash-resistant, but do not rewrite the
                # TextField or touch its style while the user is typing.
                if not logical_value or parsed_value is not None:
                    self.capture_active_controls()

                # Only the placeholder/unit chrome needs to react immediately.
                # Updating those controls individually leaves the live
                # TextField/caret alone.
                ghost.update()
                if suffix_control is not None:
                    suffix_control.update()

            weight.on_change = lambda e, current=item, f=weight, g=weight_ghost, p=weight_placeholder, u=weight_unit: numeric_change(e, current, "weight", f, g, p, u)
            reps.on_change = lambda e, current=item, f=reps, g=reps_ghost, p=previous_reps: numeric_change(e, current, "reps", f, g, p)
            rir.on_change = lambda e, current=item, f=rir, g=rir_ghost, p=previous_rir: numeric_change(e, current, "rir", f, g, p)

            def numeric_blur(e, current, key):
                field = current[key]
                self.disarm_android_empty_backspace(field)
                if not self.logical_text_value(field.value):
                    self.capture_active_controls()
                    return
                if self.normalize_numeric_control(
                    field,
                    kind={"weight": "weight", "reps": "reps", "rir": "rir"}[key],
                    allow_empty=True,
                ):
                    self.update_active_numeric_warning(current, key)
                    self.capture_active_controls()
                self.page.update()

            weight.on_blur = lambda e, current=item: numeric_blur(e, current, "weight")
            reps.on_blur = lambda e, current=item: numeric_blur(e, current, "reps")
            if not rir.read_only:
                rir.on_blur = lambda e, current=item: numeric_blur(e, current, "rir")

            self.update_active_numeric_warning(item, "weight")
            self.update_active_numeric_warning(item, "reps")
            if self.track_rir_enabled():
                self.update_active_numeric_warning(item, "rir")
            note.on_change = lambda e: self.capture_active_controls()

            special_set_type = str(set_type or "Normal").casefold() not in {
                "normal",
                "straight",
            }
            show_planned_rest = (
                planned_rest_mode == "always"
                or (
                    planned_rest_mode == "smart"
                    and (exercise_has_irregular_rest or special_set_type)
                )
            )
            timer_label = ft.Text(
                storage.format_duration(rest_seconds),
                width=self.ui(34),
                size=self.fs(10),
                weight=ft.FontWeight.BOLD,
                color=self.foreground_color(),
                visible=(not completed and show_planned_rest),
                text_align=ft.TextAlign.CENTER,
            )
            item["show_planned_rest"] = show_planned_rest
            item["timer_label"] = timer_label

            note_container = ft.Container(
                visible=notes_visible,
                padding=ft.Padding(left=self.ui(52), top=self.ui(2), right=0, bottom=0),
                content=note,
            )
            note_containers.append(note_container)

            set_content = ft.Column(
                controls=[
                    ft.Row(
                        controls=[
                            type_button,
                            weight_wrap,
                            reps_display,
                            rir_wrap,
                            timer_label,
                            ft.Container(expand=True),
                            finish,
                        ],
                        spacing=self.ui(4),
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    note_container,
                ],
                spacing=self.ui(3),
            )

            row_container = ft.Container(
                padding=ft.Padding(
                    left=self.ui(2), top=self.ui(1),
                    right=self.ui(2), bottom=self.ui(1),
                ),
                bgcolor=(
                    self.completed_set_bgcolor()
                    if completed and self.dim_completed_sets_enabled()
                    else None
                ),
                content=set_content,
            )
            item["row_container"] = row_container

            def remove_this_set(e=None, current=item):
                if current not in exercise_items:
                    return
                exercise_items.remove(current)
                if current in self.set_controls:
                    self.set_controls.remove(current)
                note_control = current.get("note_container")
                if note_control is not None and note_control in note_containers:
                    note_containers.remove(note_control)
                dismissible = current.get("dismissible")
                if dismissible is not None and dismissible in rows_column.controls:
                    rows_column.controls.remove(dismissible)
                self.renumber_controls()
                self.capture_active_controls()
                self.update_active_progress()
                self.refresh_exercise_block_state(exercise_name)
                if self.timer_started_at is not None:
                    self.sync_inline_timer()
                self.page.update()

            dismissible = ft.Dismissible(
                key=f"active-set-{item_id}",
                dismiss_direction=ft.DismissDirection.END_TO_START,
                dismiss_thresholds={ft.DismissDirection.END_TO_START: 0.25},
                background=ft.Container(),
                secondary_background=ft.Container(
                    bgcolor=ft.Colors.RED_700,
                    alignment=ft.Alignment.CENTER_RIGHT,
                    padding=ft.Padding(left=0, top=0, right=self.ui(18), bottom=0),
                    content=ft.Icon(ft.Icons.DELETE, color=ft.Colors.WHITE, size=26),
                ),
                content=row_container,
                on_dismiss=remove_this_set,
            )

            item["note_container"] = note_container
            item["dismissible"] = dismissible
            item["remove"] = remove_this_set
            rows_column.controls.append(dismissible)

        def add_set(e):
            if exercise_items:
                previous = exercise_items[-1]
                seed = {
                    "previous_weight": previous["weight"].value or previous.get("previous_weight", ""),
                    "previous_reps": previous["reps"].value or previous.get("previous_reps", ""),
                    "previous_rir": previous["rir"].value or previous.get("previous_rir", ""),
                    "rest_seconds": previous["rest_seconds"],
                    "set_type": previous["set_type"],
                }
            else:
                seed = {
                    "rest_seconds": int(self.settings.get("default_rest_seconds", "180")),
                    "set_type": "Normal",
                }
            make_row(seed)
            block_state["collapsed"] = False
            self.refresh_exercise_block_state(exercise_name, force_expand=True)
            self.capture_active_controls()
            self.update_active_progress()
            if self.timer_started_at is not None:
                self.sync_inline_timer()
            self.page.update()

        def remove_set(e):
            if exercise_items:
                exercise_items[-1]["remove"]()

        for row in initial_rows:
            make_row(row)

        adjustment_row = ft.Container(
            padding=ft.Padding(left=0, top=self.ui(5), right=0, bottom=0),
            content=ft.Row(
                controls=[
                    self.set_adjust_button("+", "Add set", add_set),
                    self.set_adjust_button("−", "Remove last set", remove_set),
                ],
                spacing=self.ui(8),
            ),
        )

        body_controls = []
        if calibration_required:
            calibration_target = next(
                (
                    item
                    for item in exercise_items
                    if item.get("mesocycle_calibration_first")
                ),
                None,
            )
            if calibration_target is not None:
                calibration_card = self.mesocycle_calibration_card(
                    exercise_name,
                    calibration_target,
                    recommendation=progression_recommendation,
                )
                if calibration_card is not None:
                    body_controls.append(calibration_card)

        body_controls.extend([rows_column, adjustment_row])
        body = ft.Column(
            controls=body_controls,
            spacing=self.ui(4),
            visible=not block_state["collapsed"],
        )
        block_state["body"] = body

        output = [heading]
        output.extend([body, ft.Divider(height=self.ui(6))])
        return output

    def change_active_set_type(self, item, selected):
        item["set_type"] = selected
        item["type_button"].content = self.active_set_type_content(
            selected,
            item["set_number"],
        )
        item["type_button"].tooltip = (
            f'{selected} — Set {item["set_number"]}'
        )
        self.capture_active_controls()
        self.page.update()

    def active_field_fallback(self, item, key):
        """Own ghost/default first; immediately-above typed value second."""
        previous_key = {
            "weight": "previous_weight",
            "reps": "previous_reps",
            "rir": "previous_rir",
        }[key]
        ghost_key = {
            "weight": "weight_ghost",
            "reps": "reps_ghost",
            "rir": "rir_ghost",
        }[key]

        candidates = []
        ghost = item.get(ghost_key)
        if ghost is not None:
            candidates.append(getattr(ghost, "value", ""))
        candidates.append(item.get(previous_key, ""))

        kind = {"weight": "weight", "reps": "reps", "rir": "rir"}[key]
        for candidate in candidates:
            value = self.evaluate_numeric_expression(candidate)
            if value is None or not self.numeric_value_is_allowed(value, kind):
                continue
            formatted = self.format_numeric_value(value, kind)
            if formatted is not None:
                return formatted

        above = next(
            (
                row
                for row in self.set_controls
                if row.get("exercise_name") == item.get("exercise_name")
                and row.get("set_number") == item.get("set_number", 0) - 1
            ),
            None,
        )
        if above is not None and above.get(key) is not None:
            value = self.evaluate_numeric_expression(above[key].value)
            if value is not None and self.numeric_value_is_allowed(value, kind):
                return self.format_numeric_value(value, kind)
        return None

    def resolve_active_numeric_field(self, item, key):
        field = item[key]
        kind = {"weight": "weight", "reps": "reps", "rir": "rir"}[key]
        ghost_key = {
            "weight": "weight_ghost",
            "reps": "reps_ghost",
            "rir": "rir_ghost",
        }[key]

        if not self.logical_text_value(field.value):
            fallback = self.active_field_fallback(item, key)
            if fallback is None:
                self.mark_field_invalid(field)
                return False
            field.value = fallback
            self.android_backspace_last_values[id(field)] = fallback
            ghost = item.get(ghost_key)
            if ghost is not None:
                ghost.visible = False
            if key == "weight" and item.get("weight_unit") is not None:
                item["weight_unit"].visible = True

        if not self.normalize_numeric_control(field, kind=kind, allow_empty=False):
            return False

        self.update_active_numeric_warning(item, key)
        return True

    def completion_missing_fields(self, item):
        missing = []
        keys = [("Weight", "weight"), ("Reps", "reps")]
        if self.track_rir_enabled() or item.get("mesocycle_calibration_first"):
            keys.append(("RIR", "rir"))

        for label, key in keys:
            if not self.resolve_active_numeric_field(item, key):
                missing.append((label, item[key]))
        return missing

    def validate_completion_items(self, items):
        valid = True

        for item in items:
            missing = self.completion_missing_fields(item)
            missing_controls = {control for _, control in missing}

            controls = [item["weight"], item["reps"]]
            if self.track_rir_enabled() or item.get("mesocycle_calibration_first"):
                controls.append(item["rir"])

            for control in controls:
                if control in missing_controls:
                    self.mark_field_invalid(control)
                    valid = False
                elif self.logical_text_value(control.value):
                    if id(control) not in self.numeric_warning_fields:
                        self.clear_field_invalid(control)

        if not valid:
            self.page.update()

        return valid

    def refresh_exercise_block_state(self, exercise_name, force_expand=False):
        items = [
            item
            for item in self.set_controls
            if item.get("exercise_name") == exercise_name
        ]
        if not items:
            return

        state = items[0].get("block_state")
        if not state:
            return

        all_complete = all(item.get("completed") for item in items)

        if force_expand:
            state["collapsed"] = False
        elif all_complete and self.collapse_completed_exercises_enabled():
            state["collapsed"] = True
        elif not all_complete:
            state["collapsed"] = False

        body = state.get("body")
        icon = state.get("collapse_icon")
        if body is not None:
            body.visible = not state["collapsed"]
        if icon is not None:
            icon.icon = (
                ft.Icons.CHEVRON_RIGHT
                if state["collapsed"]
                else ft.Icons.EXPAND_MORE
            )

    def copy_previous_completed_set_values_if_empty(self, target):
        """Seed a completely blank set from the immediately previous completed set."""
        fields = [("weight", "weight_ghost"), ("reps", "reps_ghost")]
        if self.track_rir_enabled():
            fields.append(("rir", "rir_ghost"))

        # Only auto-copy when the current set has no typed data at all.  A
        # partially entered set remains intentional user input.
        if any(self.logical_text_value(target[key].value) for key, _ in fields):
            return

        previous = next(
            (
                item
                for item in self.set_controls
                if item.get("exercise_name") == target.get("exercise_name")
                and item.get("set_number") == target.get("set_number", 0) - 1
                and item.get("completed")
            ),
            None,
        )
        if previous is None:
            return

        for key, ghost_key in fields:
            value = self.logical_text_value(previous[key].value)
            if not value:
                continue
            target[key].value = value
            ghost = target.get(ghost_key)
            if ghost is not None:
                ghost.visible = False
            if key == "weight":
                unit_label = target.get("weight_unit")
                if unit_label is not None:
                    unit_label.visible = True
            self.clear_field_invalid(target[key])

    def propagate_completed_values_to_following_sets(self, source):
        """
        Seed later blank sets with the just-completed set's ghost defaults.

        This always fills defaults that do not exist yet. With
        Update Following Set Defaults enabled, existing ghost defaults are
        refreshed too. Typed values are never overwritten.
        """
        exercise_name = source.get("exercise_name")
        source_number = source.get("set_number", 0)
        overwrite_defaults = self.update_following_set_defaults_enabled()

        field_specs = [
            ("weight", "previous_weight", "weight_ghost"),
            ("reps", "previous_reps", "reps_ghost"),
        ]
        if self.track_rir_enabled():
            field_specs.append(("rir", "previous_rir", "rir_ghost"))

        source_values = {
            key: self.logical_text_value(source[key].value)
            for key, _, _ in field_specs
        }

        for item in self.set_controls:
            if (
                item.get("exercise_name") != exercise_name
                or item.get("set_number", 0) <= source_number
            ):
                continue

            # Any typed value means this later set is user-authored. Never
            # modify its defaults automatically.
            if any(
                self.logical_text_value(item.get(key).value)
                for key, _, _ in field_specs
                if item.get(key) is not None
            ):
                continue

            for key, previous_key, ghost_key in field_specs:
                value = source_values.get(key, "")
                if not value:
                    continue

                # OFF = fill only a missing default. ON = refresh the default
                # from every completed set.
                if (
                    not overwrite_defaults
                    and str(item.get(previous_key, "") or "").strip()
                ):
                    continue

                item[previous_key] = value
                ghost = item.get(ghost_key)
                if ghost is not None:
                    ghost.value = value
                    ghost.visible = True

                if key == "weight":
                    unit_label = item.get("weight_unit")
                    if unit_label is not None:
                        unit_label.visible = True

    def earlier_incomplete_set_in_exercise(self, target):
        exercise_name = target.get("exercise_name")
        target_number = target.get("set_number", 0)
        earlier = [
            item
            for item in self.set_controls
            if (
                item.get("exercise_name") == exercise_name
                and item.get("set_number", 0) < target_number
                and not item.get("completed")
            )
        ]
        if not earlier:
            return None
        return min(earlier, key=lambda item: item.get("set_number", 0))

    def set_order_violation(self):
        if not self.require_previous_sets_completed_enabled():
            return None
        for item in self.set_controls:
            if not item.get("completed"):
                continue
            earlier = self.earlier_incomplete_set_in_exercise(item)
            if earlier is not None:
                return item, earlier
        return None

    def toggle_set_complete(self, target, manage_workout_clock=True):
        exercise_name = target["exercise_name"]
        target_number = target["set_number"]
        making_complete = not target["completed"]

        if making_complete:
            calibration_pending = self.first_mesocycle_exercise_intro_available(
                exercise_name
            )
            calibration_ready = self.active_mesocycle_calibration_done(
                exercise_name
            )
            target_is_straight = (
                str(target.get("set_type", "Normal") or "Normal").strip().casefold()
                in {"normal", "straight"}
            )
            if (
                calibration_pending
                and not calibration_ready
                and target_is_straight
                and not target.get("mesocycle_calibration_first")
            ):
                self.notify("Calibrate the first straight set before continuing.")
                return

            if self.require_previous_sets_completed_enabled():
                earlier = self.earlier_incomplete_set_in_exercise(target)
                if earlier is not None:
                    self.notify(
                        f"Complete set {earlier.get('set_number')} of "
                        f"{exercise_name} first."
                    )
                    return
            if not self.validate_completion_items([target]):
                return
            for key in ("weight", "reps", "rir"):
                if (
                    key == "rir"
                    and not self.track_rir_enabled()
                    and not target.get("mesocycle_calibration_first")
                ):
                    continue
                self.accept_active_numeric_warning(target, key)

        # Each checkmark controls only this set. Completing set N must never
        # complete earlier sets, and uncompleting it must not affect later sets.
        target["completed"] = making_complete
        self.update_finish_button(target)

        if making_complete:
            if (
                target.get("mesocycle_calibration_first")
                and self.first_mesocycle_exercise_intro_available(exercise_name)
            ):
                self.complete_mesocycle_exercise_calibration(target)
            else:
                self.propagate_completed_values_to_following_sets(target)

        self.capture_active_controls()
        self.update_active_progress()

        if making_complete:
            if manage_workout_clock:
                if not self.workout_clock_has_started():
                    self.start_workout_clock()
                elif self.workout_clock_is_paused():
                    self.toggle_workout_clock()

            # The inline timer belongs to the set that was just completed.
            self.start_rest_timer(
                exercise_name,
                target.get("rest_seconds", 0),
                inline_item=target,
            )
        elif (
            self.timer_exercise_name == exercise_name
            and self.timer_set_number == target_number
        ):
            self.dismiss_timer(silent=True)

        self.refresh_exercise_block_state(exercise_name)
        self.page.update()

    def update_completed_field_outlines(self, item):
        fields = [
            item.get("weight"),
            item.get("reps"),
        ]
        if self.track_rir_enabled():
            fields.append(item.get("rir"))

        for field in fields:
            if field is None:
                continue

            if item.get("completed"):
                field.border_color = ft.Colors.GREEN_500
                field.focused_border_color = ft.Colors.GREEN_400
                field.border_width = 1.8
                field.focused_border_width = 2.0
            else:
                self.clear_field_invalid(field)

    def update_finish_button(self, item):
        self.update_completed_field_outlines(item)

        button = item["finish"]
        timer_label = item.get("timer_label")
        row_container = item.get("row_container")

        if item["completed"]:
            button.bgcolor = ft.Colors.GREEN_700
            button.border = ft.Border.all(1.6, ft.Colors.GREEN_600)
            button.content = ft.Icon(
                ft.Icons.CHECK,
                size=19,
                color=ft.Colors.WHITE,
            )

            if row_container is not None:
                row_container.bgcolor = (
                    self.completed_set_bgcolor()
                    if self.dim_completed_sets_enabled()
                    else None
                )

            # Keep the countdown visible on the completed set that started the
            # current rest period; completed rows otherwise hide their timer.
            if timer_label is not None:
                timer_label.visible = (
                    self.nearset_timer_enabled()
                    and self.timer_inline_item is item
                    and self.timer_started_at is not None
                )
        else:
            button.bgcolor = None
            button.border = ft.Border.all(1.6, ft.Colors.GREEN_600)
            button.content = ft.Icon(
                ft.Icons.CHECK,
                size=19,
                color=ft.Colors.GREEN_500,
            )

            if row_container is not None:
                row_container.bgcolor = None

            if not (
                self.timer_inline_item is item
                and self.timer_started_at is not None
            ):
                self.reset_inline_timer_item(item)

    def update_active_progress(self):
        if self.active_progress_text is None:
            return

        completed = sum(1 for item in self.set_controls if item["completed"])
        total = len(self.set_controls)
        progress_value = f"{completed}/{total} sets"
        cycle_rir = self.cycle_rir_target()
        if cycle_rir is not None:
            progress_value = f"{cycle_rir} RIR · {progress_value}"
        self.active_progress_text.value = progress_value

        if getattr(self, "workout_target_text", None) is not None and self.active_workout:
            # Capture set additions/removals into the estimate using current rows.
            active_for_estimate = dict(self.active_workout)
            active_for_estimate["rows"] = [
                {
                    "exercise_name": item.get("exercise_name", ""),
                    "rest_seconds": item.get("rest_seconds", 0),
                }
                for item in self.set_controls
            ]
            target = storage.estimate_active_workout_seconds(active_for_estimate)
            self.workout_target_text.value = f"~{self.format_target_duration(target)}"

    def renumber_controls(self):
        counts = {}

        for item in self.set_controls:
            exercise_name = item["exercise_name"]
            counts[exercise_name] = (
                counts.get(exercise_name, 0) + 1
            )
            item["set_number"] = counts[exercise_name]

            if item.get("type_button") is not None:
                item["type_button"].content = self.active_set_type_content(
                    item.get("set_type", "Normal"),
                    item["set_number"],
                )
                item["type_button"].tooltip = (
                    f'{item.get("set_type", "Normal")} — '
                    f'Set {item["set_number"]}'
                )

    def capture_active_controls(self):
        if not self.active_workout:
            return

        self.renumber_controls()

        rows = []

        for item in self.set_controls:
            rows.append(
                {
                    "exercise_name": item["exercise_name"],
                    "set_number": item["set_number"],
                    "weight": self.logical_text_value(item["weight"].value),
                    "weight_unit": self.settings.get("unit", "kg"),
                    "reps": self.logical_text_value(item["reps"].value),
                    "rir": self.logical_text_value(item["rir"].value),
                    "previous_weight": item.get("previous_weight", ""),
                    "previous_reps": item.get("previous_reps", ""),
                    "previous_rir": item.get("previous_rir", ""),
                    "set_type": item.get(
                        "set_type",
                        "Normal",
                    ),
                    "note": item["note"].value or "",
                    "completed": item["completed"],
                    "calibration_done": bool(item.get("calibration_done", False)),
                    "rest_seconds": item.get(
                        "rest_seconds",
                        180,
                    ),
                }
            )

        self.active_workout["rows"] = rows
        storage.save_active_workout(
            self.active_workout
        )

    def show_workout_completion_summary(self, workout_name, saved_count, muscle_counts):
        """Show a quiet post-workout summary before returning to the workout list."""
        self.selected_tab = 0
        self.page.navigation_bar.selected_index = 0

        controls = [
            ft.Text(
                "Workout complete",
                size=self.fs(27),
                weight=ft.FontWeight.BOLD,
            ),
            ft.Text(
                str(workout_name or "Workout"),
                size=self.fs(17),
                weight=ft.FontWeight.W_600,
            ),
            ft.Text(
                f"{int(saved_count or 0)} completed set(s)",
                size=self.fs(12),
                color=ft.Colors.GREY_500,
            ),
            ft.Container(height=self.ui(4)),
            ft.Text(
                "Primary working sets",
                size=self.fs(20),
                weight=ft.FontWeight.BOLD,
            ),
        ]

        if muscle_counts:
            cards = []
            for muscle, count in muscle_counts.items():
                cards.append(
                    ft.Container(
                        width=self.ui(118),
                        padding=ft.Padding(
                            left=self.ui(10),
                            top=self.ui(9),
                            right=self.ui(10),
                            bottom=self.ui(9),
                        ),
                        border=ft.Border.all(1, ft.Colors.GREY_700),
                        border_radius=self.rounding(),
                        content=ft.Column(
                            controls=[
                                ft.Text(
                                    muscle,
                                    size=self.fs(11.5),
                                    weight=ft.FontWeight.W_600,
                                    max_lines=1,
                                    overflow=ft.TextOverflow.ELLIPSIS,
                                ),
                                ft.Text(
                                    f"{count} sets",
                                    size=self.fs(19),
                                    weight=ft.FontWeight.BOLD,
                                ),
                            ],
                            spacing=1,
                            tight=True,
                        ),
                    )
                )
            controls.append(
                ft.Row(
                    controls=cards,
                    spacing=self.ui(7),
                    run_spacing=self.ui(7),
                    wrap=True,
                )
            )
        else:
            controls.append(
                ft.Text(
                    "No primary-muscle working sets are assigned for this workout yet.",
                    size=self.fs(12.5),
                    color=ft.Colors.GREY_500,
                )
            )

        controls.append(
            ft.Text(
                "Warm-up sets are excluded. A completed set counts once for each primary muscle assigned to its exercise.",
                size=self.fs(10.5),
                color=ft.Colors.GREY_500,
            )
        )

        self.set_view(
            controls,
            footer=self.filled_button(
                "Done",
                on_click=lambda e: self.show_saved_workouts(),
                expand=True,
            ),
            back_action=self.show_saved_workouts,
        )

    def finish_workout(self, e):
        self.capture_active_controls()

        violation = self.set_order_violation()
        if violation is not None:
            completed, earlier = violation
            self.notify(
                f"{completed.get('exercise_name')}: complete set "
                f"{earlier.get('set_number')} before saving later sets."
            )
            return

        completed_items = [
            item for item in self.set_controls if item.get("completed")
        ]
        if completed_items and not self.validate_completion_items(completed_items):
            return

        workout = {
            "workout_id": self.active_workout["workout_id"],
            "name": self.active_workout["workout_name"],
        }
        muscle_counts = storage.completed_primary_muscle_set_counts(
            self.active_workout.get("rows", [])
        )

        count = storage.append_session(
            workout,
            self.active_workout["rows"],
        )

        if count == 0:
            self.notify(
                "No completed sets. Mark at least one set first."
            )
            return

        # A calibration becomes mesocycle state only when the workout itself is
        # successfully saved, and only when that calibration set was completed.
        cycle = storage.active_mesocycle()
        if cycle:
            cycle_id = cycle.get("cycle_id", "")
            workout_id = self.active_workout.get("workout_id", "")
            for row in self.active_workout.get("rows", []):
                if not (
                    row.get("calibration_done", False)
                    and row.get("completed", False)
                ):
                    continue
                storage.mark_mesocycle_intro_seen(
                    cycle_id,
                    workout_id,
                    row.get("exercise_name", ""),
                )

        storage.clear_active_workout()
        self.dismiss_timer(silent=True)

        self.active_workout = None
        self.set_controls = []
        self.rir_lock_warning_workout_id = None
        self.rir_lock_warning_count = 0

        self.show_workout_completion_summary(
            workout.get("name", "Workout"),
            count,
            muscle_counts,
        )

    def discard_workout(self, e):
        storage.clear_active_workout()
        self.dismiss_timer(silent=True)

        self.active_workout = None
        self.set_controls = []
        self.rir_lock_warning_workout_id = None
        self.rir_lock_warning_count = 0

        self.show_saved_workouts()

    def show_exercise_details(self, exercise_name, back_action=None):
        if self.active_workout and self.set_controls:
            self.capture_active_controls()

        if back_action is None:
            back_action = self.show_active_workout if self.active_workout else self.show_exercise_database

        details = storage.read_exercise_details(exercise_name)
        primary_selected = set(
            storage.normalize_muscle_list(details.get("primary_muscles", ""))
        )
        secondary_selected = set(
            storage.normalize_muscle_list(details.get("secondary_muscles", ""))
        )
        secondary_selected -= primary_selected

        description = self.text_field(
            value=details.get("description", ""),
            hint_text="Exercise description",
            multiline=True,
            min_lines=4,
            max_lines=7,
        )
        set_seconds = self.text_field(
            value=details.get("set_seconds", ""),
            hint_text="Use workout default",
            width=self.ui(150),
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="seconds",
        )

        unit = self.settings.get("unit", "kg")
        equipment_selected = [
            storage.normalize_equipment_type(details.get("equipment_type", ""))
        ]
        increment_override = self.text_field(
            value=details.get(f"weight_increment_{unit}", ""),
            hint_text=(
                f"Default {storage.format_increment(storage.exercise_weight_increment(exercise_name, unit, settings=self.settings))}"
            ),
            width=self.ui(150),
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="weight",
        )
        equipment_button_refs = {}
        increment_default_text = ft.Text(size=self.fs(11))

        def refresh_equipment_controls():
            selected = equipment_selected[0]
            for equipment_type, (box, label) in equipment_button_refs.items():
                active = equipment_type == selected
                box.bgcolor = (
                    ft.Colors.with_opacity(0.18, self.accent_color())
                    if active
                    else None
                )
                box.border = ft.Border.all(
                    1.4 if active else 1,
                    self.accent_color() if active else ft.Colors.GREY_700,
                )
                label.weight = ft.FontWeight.BOLD if active else ft.FontWeight.W_500

            default_value = storage.default_weight_increment(selected, unit)
            setting_key = storage.weight_increment_setting_key(selected, unit)
            try:
                default_value = float(
                    self.settings.get(setting_key, default_value) or default_value
                )
            except (TypeError, ValueError):
                default_value = storage.default_weight_increment(selected, unit)
            default_text = storage.format_increment(default_value)
            increment_override.hint_text = f"Default {default_text}"
            increment_default_text.value = (
                f"Leave blank to use the {selected} default: {default_text} {unit}."
                if selected
                else f"Choose equipment above, or leave blank to use {default_text} {unit}."
            )

        def choose_equipment(equipment_type):
            equipment_selected[0] = equipment_type
            refresh_equipment_controls()
            self.page.update()

        def equipment_button(equipment_type):
            label = ft.Text(
                equipment_type,
                size=self.fs(11),
                text_align=ft.TextAlign.CENTER,
                max_lines=1,
                overflow=ft.TextOverflow.ELLIPSIS,
            )
            box = ft.Container(
                expand=True,
                height=self.ui(38),
                alignment=ft.Alignment.CENTER,
                padding=ft.Padding(left=self.ui(5), top=0, right=self.ui(5), bottom=0),
                border_radius=self.rounding(),
                ink=True,
                on_click=lambda e, name=equipment_type: choose_equipment(name),
                content=label,
            )
            equipment_button_refs[equipment_type] = (box, label)
            return box

        equipment_controls = ft.Column(
            controls=[
                ft.Row(
                    controls=[
                        equipment_button("Barbell"),
                        equipment_button("Dumbbell"),
                    ],
                    spacing=self.ui(6),
                ),
                ft.Row(
                    controls=[
                        equipment_button("Plate loaded"),
                        equipment_button("Weight-stack machine"),
                    ],
                    spacing=self.ui(6),
                ),
            ],
            spacing=self.ui(6),
        )
        refresh_equipment_controls()

        chip_refs = {}

        def style_chip(section, muscle):
            chip, text = chip_refs[(section, muscle)]
            selected = muscle in (
                primary_selected if section == "primary" else secondary_selected
            )
            chip.bgcolor = (
                ft.Colors.with_opacity(0.18, self.accent_color())
                if selected
                else None
            )
            chip.border = ft.Border.all(
                1.4 if selected else 1,
                self.accent_color() if selected else ft.Colors.GREY_700,
            )
            text.weight = ft.FontWeight.BOLD if selected else ft.FontWeight.W_500

        def toggle_muscle(section, muscle):
            chosen = primary_selected if section == "primary" else secondary_selected
            other = secondary_selected if section == "primary" else primary_selected

            if muscle in chosen:
                chosen.remove(muscle)
            else:
                chosen.add(muscle)
                other.discard(muscle)

            style_chip("primary", muscle)
            style_chip("secondary", muscle)
            self.page.update()

        def muscle_grid(section):
            chips = []
            for muscle in storage.BODYBUILDING_MUSCLE_GROUPS:
                text = ft.Text(
                    muscle,
                    size=self.fs(10.5),
                    text_align=ft.TextAlign.CENTER,
                    max_lines=1,
                    overflow=ft.TextOverflow.ELLIPSIS,
                )
                chip = ft.Container(
                    expand=True,
                    height=self.ui(30),
                    alignment=ft.Alignment.CENTER,
                    padding=ft.Padding(left=self.ui(4), top=0, right=self.ui(4), bottom=0),
                    border_radius=self.rounding(),
                    ink=True,
                    on_click=lambda e, sec=section, name=muscle: toggle_muscle(sec, name),
                    content=text,
                )
                chip_refs[(section, muscle)] = (chip, text)
                chips.append(chip)

            rows = []
            for index in range(0, len(chips), 3):
                rows.append(
                    ft.Row(
                        controls=chips[index:index + 3],
                        spacing=self.ui(6),
                    )
                )

            for muscle in storage.BODYBUILDING_MUSCLE_GROUPS:
                style_chip(section, muscle)

            return ft.Column(controls=rows, spacing=self.ui(6))

        primary_grid = muscle_grid("primary")
        secondary_grid = muscle_grid("secondary")

        def save(e):
            valid = self.normalize_numeric_control(
                set_seconds,
                kind="seconds",
                allow_empty=True,
            )
            if not self.normalize_numeric_control(
                increment_override,
                kind="weight",
                allow_empty=True,
            ):
                valid = False
            if not valid:
                self.page.update()
                return

            increment_lb = details.get("weight_increment_lb", "")
            increment_kg = details.get("weight_increment_kg", "")
            if unit == "lb":
                increment_lb = increment_override.value
            else:
                increment_kg = increment_override.value

            storage.save_exercise_details(
                exercise_name,
                list(primary_selected),
                list(secondary_selected),
                description.value,
                details.get("note", ""),
                set_seconds.value,
                equipment_selected[0],
                increment_lb,
                increment_kg,
            )
            self.notify("Exercise details saved.")
            back_action()

        controls = [
            ft.Text(exercise_name, size=self.fs(28), weight=ft.FontWeight.BOLD),
            ft.Text("Description", size=self.fs(17), weight=ft.FontWeight.BOLD),
            description,
            ft.Text("Primary muscles", size=self.fs(17), weight=ft.FontWeight.BOLD),
            primary_grid,
            ft.Text("Secondary muscles", size=self.fs(17), weight=ft.FontWeight.BOLD),
            secondary_grid,
            ft.Text("Equipment", size=self.fs(17), weight=ft.FontWeight.BOLD),
            equipment_controls,
            ft.Text(
                f"Weight increment override ({unit})",
                size=self.fs(17),
                weight=ft.FontWeight.BOLD,
            ),
            increment_override,
            increment_default_text,
            ft.Text(
                "Barbell and plate-loaded increments are total logged-weight jumps; dumbbell increments are per dumbbell.",
                size=self.fs(10),
            ),
            ft.Text("Approx. time per set (seconds)", size=self.fs(17), weight=ft.FontWeight.BOLD),
            set_seconds,
            ft.Text(
                "Leave blank to use the workout's default set-time estimate.",
                size=self.fs(11),
            ),
        ]

        self.set_view(
            controls,
            footer=self.filled_button("Save", on_click=save, expand=True),
            back_action=back_action,
        )

    def show_rir_info(self):
        def section(title, body):
            return ft.Column(
                controls=[
                    ft.Text(title, weight=ft.FontWeight.BOLD),
                    ft.Text(body),
                ],
                spacing=self.ui(3),
                tight=True,
            )

        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text("Using RIR"),
            content=ft.Container(
                width=min(self.ui(420), max(self.ui(280), float(getattr(self.page, "width", 420) or 420) - self.ui(28))),
                content=ft.Column(
                    controls=[
                        section(
                            "Rate the set after you finish it",
                            "RIR is how many clean reps you believe you still had "
                            "left. If you could have done about three more reps, "
                            "log 3 RIR. If only one good rep remained, log 1 RIR."
                        ),
                        section(
                            "Use it to judge whether the load was right",
                            "If your target was 2 RIR but the set felt like 4 RIR, "
                            "the load was probably conservative. If it felt like "
                            "0 RIR, it was harder than planned. Use that difference "
                            "to guide the next session rather than chasing a number "
                            "during the set itself."
                        ),
                        section(
                            "Use higher RIR when you want more margin",
                            "Around 3 RIR is useful when you want productive work "
                            "without pushing close to failure. Around 1 RIR is a "
                            "much harder set. Keep technique consistent and stop "
                            "the set if form breaks down, regardless of the target."
                        ),
                        section(
                            "Look for trends",
                            "The most useful signal is repeated performance. If the "
                            "same weight and reps begin to feel easier over time, "
                            "that is a good reason to progress the load or reps."
                        ),
                    ],
                    spacing=self.ui(12),
                    tight=True,
                ),
            ),
            actions=[
                self.filled_button(
                    "OK",
                    on_click=lambda e: self.close_dialog(dialog),
                )
            ],
        )
        self.page.show_dialog(dialog)

    def request_substitution(self, old_name):
        self.capture_active_controls()

        completed = [
            row
            for row in self.active_workout["rows"]
            if (
                row["exercise_name"] == old_name
                and row.get("completed")
            )
        ]

        if completed:
            self.notify(
                "Substitute before completing sets for this exercise."
            )
            return

        self.open_exercise_picker(
            lambda new_name: self.apply_substitution(
                old_name,
                new_name,
            )
        )

    def apply_substitution(self, old_name, new_name):
        new_name = (new_name or "").strip()

        if not new_name:
            return

        storage.add_catalog_exercise(new_name)
        previous = storage.latest_exercise_values(
            new_name
        )

        for row in self.active_workout["rows"]:
            if row["exercise_name"] != old_name:
                continue

            row["exercise_name"] = new_name
            set_number = row["set_number"]
            prev = previous.get(set_number, {})

            if prev:
                row["weight"] = prev.get(
                    "weight",
                    row.get("weight", ""),
                )
                row["reps"] = prev.get(
                    "reps",
                    row.get("reps", ""),
                )
                row["rir"] = prev.get(
                    "rir",
                    row.get("rir", ""),
                )

        storage.save_active_workout(
            self.active_workout
        )
        self.show_active_workout()
