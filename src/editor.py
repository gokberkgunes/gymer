import ast
import asyncio
import math
import time
import uuid
from datetime import datetime

import flet as ft

import storage


class EditorMixin:

    def create_workout(self, e=None):
        self.selected_tab = 0
        self.page.navigation_bar.selected_index = 0

        workout_id = storage.create_workout(
            "New Workout"
        )
        self.show_edit(
            workout_id,
            is_new=True,
        )

    def show_edit(self, workout_id, is_new=False):
        workout = storage.read_workout(workout_id)

        if workout is None:
            self.show_saved_workouts()
            return

        settings = storage.read_settings()
        default_sets = int(settings.get("default_sets", "3") or 3)
        default_rest = int(settings.get("default_rest_seconds", "180") or 180)
        workout_details = storage.read_workout_details(workout_id)

        # Returning from an exercise's pencil/details editor must not discard
        # unsaved workout edits. A one-shot in-memory draft is restored here.
        editor_draft = getattr(self, "workout_editor_draft", None)
        if editor_draft and editor_draft.get("workout_id") == workout_id:
            workout = {
                **workout,
                "name": editor_draft.get("name", workout.get("name", "Workout")),
                "exercises": editor_draft.get("exercises", workout.get("exercises", [])),
            }
            workout_details = {
                **workout_details,
                **editor_draft.get("details", {}),
            }
            self.workout_editor_draft = None

        active_cycle = storage.active_mesocycle()
        rest_locked_by_cycle = bool(
            active_cycle and active_cycle.get("rest_timer_lock", "0") == "1"
        )

        name_field = self.text_field(
            label="Workout name",
            value=workout["name"],
            dense=True,
        )
        name_field.expand = 1
        workout_description = self.text_field(
            hint_text="Description",
            value=workout_details.get("description", ""),
            multiline=True,
            min_lines=1,
            max_lines=2,
            dense=True,
        )
        workout_description.expand = 1

        # Timing controls live on the dedicated approximator page, but stay in
        # this closure so edits survive moving back and forth before Save.
        workout_set_seconds = self.text_field(
            label="Default set duration (seconds)",
            value=workout_details.get("set_seconds", "45") or "45",
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="seconds",
        )
        workout_set_overhead = self.text_field(
            label="Setup / logging per set",
            value=storage.format_duration(
                workout_details.get("set_overhead_seconds", "30") or "30"
            ),
            hint_text="0:30",
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
        )
        workout_transition = self.text_field(
            label="Between exercises",
            value=storage.format_duration(
                workout_details.get("transition_seconds", "300") or "300"
            ),
            hint_text="5:00",
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
        )
        workout_session_overhead = self.text_field(
            label="Session overhead",
            value=storage.format_duration(
                workout_details.get("session_overhead_seconds", "300") or "300"
            ),
            hint_text="5:00",
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
        )
        # Duration boxes keep the familiar m:ss display, but switch to raw
        # seconds while focused so Android can use the numeric keypad.
        def attach_duration_numpad(field, default_seconds):
            def focus_duration(e):
                field.value = str(
                    storage.parse_duration(field.value, default=default_seconds)
                )
                self.page.update()

            def blur_duration(e):
                seconds = storage.parse_duration(
                    field.value, default=default_seconds
                )
                field.value = storage.format_duration(seconds)
                self.page.update()

            field.keyboard_type = ft.KeyboardType.NUMBER
            field.on_focus = focus_duration
            field.on_blur = blur_duration

        attach_duration_numpad(workout_set_overhead, 30)
        attach_duration_numpad(workout_transition, 300)
        attach_duration_numpad(workout_session_overhead, 300)

        self.chain_text_fields(
            workout_set_seconds,
            workout_set_overhead,
            workout_transition,
            workout_session_overhead,
        )

        exercise_fields = ft.Column(spacing=self.ui(12))
        exercise_edit_rows = []
        muscle_summary = ft.Column(spacing=self.ui(5))
        time_target_text = ft.Text(
            weight=ft.FontWeight.BOLD,
            color=self.accent_color(),
        )
        time_target_large = ft.Text(
            size=self.fs(28),
            weight=ft.FontWeight.BOLD,
        )
        time_breakdown_text = ft.Text(size=self.fs(12))

        def make_default_sets():
            return [
                {
                    "weight": "",
                    "reps": "",
                    "rest_seconds": default_rest,
                    "set_type": "Normal",
                }
                for _ in range(default_sets)
            ]

        def new_row_data(exercise=None):
            exercise = exercise or {
                "exercise_name": "",
                "sets": make_default_sets(),
            }
            return {
                "id": uuid.uuid4().hex,
                "exercise_name": exercise.get("exercise_name", ""),
                "sets": [
                    {
                        "weight": str(set_row.get("weight", "") or ""),
                        "reps": str(set_row.get("reps", "") or ""),
                        "rest_seconds": storage.parse_duration(
                            set_row.get("rest_seconds", default_rest),
                            default=default_rest,
                        ),
                        "set_type": set_row.get("set_type", "Normal") or "Normal",
                    }
                    for set_row in (exercise.get("sets") or make_default_sets())
                ],
            }

        def snapshot_row_controls():
            for row in exercise_edit_rows:
                for set_row in row["sets"]:
                    weight = set_row.get("_weight_field")
                    reps = set_row.get("_reps_field")
                    rest = set_row.get("_rest_field")
                    if isinstance(weight, ft.TextField):
                        set_row["weight"] = weight.value or ""
                    if isinstance(reps, ft.TextField):
                        set_row["reps"] = reps.value or ""
                    if isinstance(rest, ft.TextField):
                        set_row["rest_seconds"] = storage.parse_duration(
                            rest.value,
                            default=set_row.get("rest_seconds", default_rest),
                        )

        def build_editor_draft():
            snapshot_row_controls()
            exercises = []
            for row in exercise_edit_rows:
                exercises.append(
                    {
                        "exercise_name": row.get("exercise_name", ""),
                        "sets": [
                            {
                                "weight": set_row.get("weight", ""),
                                "reps": set_row.get("reps", ""),
                                "rest_seconds": set_row.get("rest_seconds", default_rest),
                                "set_type": set_row.get("set_type", "Normal") or "Normal",
                            }
                            for set_row in row.get("sets", [])
                        ],
                    }
                )
            return {
                "workout_id": workout_id,
                "name": name_field.value or workout.get("name", "Workout"),
                "details": {
                    "description": workout_description.value or "",
                    "note": workout_details.get("note", ""),
                    "set_seconds": workout_set_seconds.value or "",
                    "set_overhead_seconds": workout_set_overhead.value or "",
                    "transition_seconds": workout_transition.value or "",
                    "session_overhead_seconds": workout_session_overhead.value or "",
                },
                "exercises": exercises,
            }

        def open_exercise_details_from_editor(row):
            exercise_name = str(row.get("exercise_name", "") or "").strip()
            if not exercise_name:
                choose_exercise(row)
                return
            self.workout_editor_draft = build_editor_draft()
            self.show_exercise_details(
                exercise_name,
                back_action=lambda: self.show_edit(workout_id, is_new=is_new),
            )

        def timing_breakdown():
            snapshot_row_controls()
            parsed_set_time = self.evaluate_numeric_expression(workout_set_seconds.value)
            default_set_time = (
                max(1, int(round(parsed_set_time)))
                if parsed_set_time is not None
                else 45
            )

            per_set_overhead = storage.parse_duration(
                workout_set_overhead.value,
                default=30,
            )
            transition = storage.parse_duration(
                workout_transition.value,
                default=300,
            )
            session_overhead = storage.parse_duration(
                workout_session_overhead.value,
                default=300,
            )

            lifting = 0
            rest = 0
            set_count = 0
            exercise_count = 0

            for row in exercise_edit_rows:
                name = (row.get("exercise_name") or "").strip()
                if not name or not row.get("sets"):
                    continue
                exercise_count += 1
                details = storage.read_exercise_details(name)
                try:
                    exercise_set_time = int(float(details.get("set_seconds", "") or 0))
                except (TypeError, ValueError):
                    exercise_set_time = 0
                if exercise_set_time <= 0:
                    exercise_set_time = default_set_time

                set_count += len(row["sets"])
                lifting += len(row["sets"]) * exercise_set_time
                for set_row in row["sets"][:-1]:
                    rest += storage.parse_duration(
                        set_row.get("rest_seconds", default_rest),
                        default=default_rest,
                    )

            setup = set_count * per_set_overhead
            transitions = max(0, exercise_count - 1) * transition
            total = lifting + setup + rest + transitions + session_overhead
            return {
                "lifting": lifting,
                "setup": setup,
                "rest": rest,
                "transitions": transitions,
                "session": session_overhead,
                "total": total,
                "sets": set_count,
                "exercises": exercise_count,
            }

        def compact_minutes(seconds):
            seconds = max(0, int(seconds or 0))
            minutes = seconds // 60
            remainder = seconds % 60
            if remainder == 0:
                return f"{minutes}m"
            return f"{minutes}m {remainder}s"

        def refresh_summaries(update_page=False):
            counts = {name: 0 for name in storage.BODYBUILDING_MUSCLE_GROUPS}
            for row in exercise_edit_rows:
                name = (row.get("exercise_name") or "").strip()
                if not name:
                    continue
                details = storage.read_exercise_details(name)
                for muscle in storage.normalize_muscle_list(
                    details.get("primary_muscles", "")
                ):
                    counts[muscle] += len(row.get("sets", []))

            chips = []
            for muscle in storage.BODYBUILDING_MUSCLE_GROUPS:
                count = counts[muscle]
                if not count:
                    continue
                chips.append(
                    ft.Container(
                        padding=ft.Padding(left=self.ui(8), top=self.ui(4), right=self.ui(8), bottom=self.ui(4)),
                        border=ft.Border.all(1, ft.Colors.GREY_700),
                        border_radius=self.rounding(),
                        content=ft.Text(
                            f"{muscle}  {count}",
                            size=self.fs(11),
                            weight=ft.FontWeight.BOLD,
                        ),
                    )
                )

            muscle_summary.controls = [
                (
                    ft.Row(controls=chips, spacing=self.ui(5), wrap=True)
                    if chips
                    else ft.Text(
                        "Assign Primary muscles in Exercise Database → Details to see direct-set totals.",
                        size=self.fs(11),
                        color=ft.Colors.GREY_500,
                    )
                )
            ]

            breakdown = timing_breakdown()
            target = self.format_target_duration(breakdown["total"])
            compact_target = target.replace(" min", "m")
            time_target_text.value = f"~{compact_target}"
            time_target_large.value = f"Target ~{target}"
            time_breakdown_text.value = (
                f"Lifting {compact_minutes(breakdown['lifting'])} · "
                f"setup/logging {compact_minutes(breakdown['setup'])} · "
                f"programmed rest {compact_minutes(breakdown['rest'])} · "
                f"exercise changes {compact_minutes(breakdown['transitions'])} · "
                f"session overhead {compact_minutes(breakdown['session'])} = "
                f"{compact_minutes(breakdown['total'])}. The displayed target rounds up to the next 5 minutes."
            )

            if update_page:
                self.page.update()

        def move_by(row_id, delta):
            snapshot_row_controls()
            index = next(
                (i for i, row in enumerate(exercise_edit_rows) if row["id"] == row_id),
                None,
            )
            if index is None:
                return
            new_index = max(0, min(len(exercise_edit_rows) - 1, index + delta))
            if new_index == index:
                return
            row = exercise_edit_rows.pop(index)
            exercise_edit_rows.insert(new_index, row)
            render_rows()

        def remove_row(row_id):
            snapshot_row_controls()
            exercise_edit_rows[:] = [
                row for row in exercise_edit_rows if row["id"] != row_id
            ]
            render_rows()

        def choose_exercise(row):
            self.open_exercise_picker(
                lambda selected: update_exercise_name(row, selected)
            )

        def update_exercise_name(row, selected):
            snapshot_row_controls()
            selected = str(selected or "").strip()
            if not selected:
                return

            old_name = str(row.get("exercise_name", "") or "").strip()
            if old_name.casefold() == selected.casefold():
                return

            # A workout-editor substitution should never carry an unrelated
            # exercise's load into the replacement. Reuse the replacement's own
            # latest values when available; otherwise leave load/reps blank while
            # preserving the programmed set count, rests and set types.
            previous = storage.latest_exercise_values(selected)
            for set_number, set_row in enumerate(row.get("sets", []), start=1):
                known = previous.get(set_number, {})
                set_row["weight"] = str(known.get("weight", "") or "")
                set_row["reps"] = str(known.get("reps", "") or "")

            row["exercise_name"] = selected
            render_rows()

        def choose_set_type(set_row):
            self.open_set_type_picker(
                set_row.get("set_type", "Normal"),
                lambda selected: update_set_type(set_row, selected),
            )

        def update_set_type(set_row, selected):
            snapshot_row_controls()
            set_row["set_type"] = selected
            render_rows()

        def add_set_to_exercise(row):
            snapshot_row_controls()
            previous = row["sets"][-1] if row["sets"] else {}
            row["sets"].append(
                {
                    "weight": previous.get("weight", ""),
                    "reps": previous.get("reps", ""),
                    "rest_seconds": previous.get("rest_seconds", default_rest),
                    "set_type": previous.get("set_type", "Normal"),
                }
            )
            render_rows()

        def remove_set_from_exercise(row):
            snapshot_row_controls()
            if len(row["sets"]) <= 1:
                return
            row["sets"].pop()
            render_rows()

        def rest_changed(e, set_row):
            set_row["rest_seconds"] = storage.parse_duration(
                e.control.value,
                default=set_row.get("rest_seconds", default_rest),
            )
            refresh_summaries(update_page=True)

        def render_rows():
            snapshot_row_controls()
            exercise_fields.controls.clear()

            # Author this editor against the same 430-logical-pixel canvas as
            # the large-phone layout, then scale the *whole card geometry*
            # together on narrower Android viewports.  Do not reflow a set into
            # extra rows: that made fields larger relative to the exercise name
            # and produced the crushed layout seen on small-width devices.
            try:
                page_width = float(getattr(self.page, "width", 0) or 0)
            except (TypeError, ValueError):
                page_width = 0.0
            if page_width <= 0:
                page_width = 430.0

            outer_padding = self.ui(self.PAGE_PADDING)
            available_width = max(1.0, page_width - (2 * outer_padding))
            editor_scale = max(0.54, min(1.0, available_width / 418.0))

            def es(value):
                return float(value) * editor_scale

            def efs(value):
                return float(value) * self.font_scale() * editor_scale

            field_gap = es(5)
            weight_width = es(94)
            reps_width = es(82)
            rest_width = es(80)
            type_width = es(94)
            field_height = es(50)

            def editor_action(
                icon,
                on_click,
                tooltip,
                color=None,
                enabled=True,
                bgcolor=None,
                border_color=None,
            ):
                color = color or self.foreground_color()
                if not enabled:
                    color = ft.Colors.with_opacity(0.30, color)
                    bgcolor = None
                return ft.Container(
                    width=es(36),
                    height=es(42),
                    alignment=ft.Alignment.CENTER,
                    ink=bool(enabled),
                    bgcolor=bgcolor,
                    border=ft.Border.all(
                        1, border_color or self.field_border_color()
                    ),
                    border_radius=self.rounding(),
                    tooltip=tooltip,
                    on_click=on_click if enabled else None,
                    content=ft.Icon(
                        icon,
                        size=es(22),
                        color=color,
                    ),
                )

            def editor_numeric_field(
                *,
                label,
                value,
                width,
                kind=None,
                read_only=False,
                tooltip=None,
            ):
                return self.text_field(
                    label=label,
                    value=value,
                    width=width,
                    height=field_height,
                    dense=True,
                    text_size=efs(15),
                    label_style=ft.TextStyle(size=efs(11)),
                    content_padding=ft.Padding(
                        left=es(9),
                        top=es(7),
                        right=es(9),
                        bottom=es(7),
                    ),
                    keyboard_type=(
                        ft.KeyboardType.NUMBER if kind is not None else None
                    ),
                    numeric_kind=kind,
                    read_only=read_only,
                    tooltip=tooltip,
                )

            for row_index, row in enumerate(exercise_edit_rows):
                row_id = row["id"]
                set_controls = []

                for set_row in row["sets"]:
                    weight = editor_numeric_field(
                        label="Weight",
                        value=set_row.get("weight", ""),
                        width=weight_width,
                        kind="weight",
                    )
                    # Keep the unit inside the compact weight box without using
                    # the generic wrapper's phone-scale padding; this card has
                    # its own proportional editor scale.
                    weight.content_padding = ft.Padding(
                        left=es(9),
                        top=es(7),
                        right=es(25),
                        bottom=es(7),
                    )
                    unit_label = ft.Text(
                        self.settings.get("unit", "kg"),
                        size=efs(9),
                        weight=ft.FontWeight.W_500,
                        color=ft.Colors.GREY_500,
                        visible=bool((weight.value or "").strip()),
                    )
                    weight_display = ft.Stack(
                        controls=[
                            weight,
                            ft.Container(
                                right=es(6),
                                top=0,
                                bottom=0,
                                alignment=ft.Alignment.CENTER,
                                ignore_interactions=True,
                                content=unit_label,
                            ),
                        ],
                        width=weight_width,
                        height=field_height,
                    )

                    def sync_weight(e, label=unit_label, field=weight):
                        label.visible = bool((field.value or "").strip())
                        if (field.value or "").strip():
                            self.clear_field_invalid(field)
                        self.page.update()

                    weight.on_change = sync_weight

                    reps = editor_numeric_field(
                        label="Reps",
                        value=set_row.get("reps", ""),
                        width=reps_width,
                        kind="reps",
                    )
                    rest = editor_numeric_field(
                        label="Rest",
                        value=storage.format_duration(
                            set_row.get("rest_seconds", default_rest)
                        ),
                        width=rest_width,
                        read_only=rest_locked_by_cycle,
                        tooltip=(
                            "Rest time is locked by the active mesocycle"
                            if rest_locked_by_cycle
                            else None
                        ),
                    )
                    rest.hint_text = "3:00"
                    rest.keyboard_type = ft.KeyboardType.NUMBER
                    rest.on_change = lambda e, target=set_row: rest_changed(e, target)

                    if not rest.read_only:
                        def focus_rest(
                            e, field=rest, target=set_row
                        ):
                            seconds = storage.parse_duration(
                                field.value,
                                default=target.get("rest_seconds", default_rest),
                            )
                            field.value = str(seconds)
                            self.page.update()

                        def blur_rest(
                            e, field=rest, target=set_row
                        ):
                            seconds = storage.parse_duration(
                                field.value,
                                default=target.get("rest_seconds", default_rest),
                            )
                            target["rest_seconds"] = seconds
                            field.value = storage.format_duration(seconds)
                            refresh_summaries(update_page=True)

                        rest.on_focus = focus_rest
                        rest.on_blur = blur_rest

                    self.chain_text_fields(
                        weight,
                        reps,
                        None if rest.read_only else rest,
                    )

                    set_row["_weight_field"] = weight
                    set_row["_reps_field"] = reps
                    set_row["_rest_field"] = rest

                    # Dense TextFields reserve vertical room for the floating
                    # label, so their *visible outline* is shorter than the
                    # control's outer height.  Give set type the same row height
                    # for alignment/touch area, but keep its visible box at the
                    # same height as the outlined Weight/Reps/Rest boxes.
                    type_button = ft.Container(
                        width=type_width,
                        height=field_height,
                        alignment=ft.Alignment.TOP_CENTER,
                        content=ft.Container(
                            width=type_width,
                            height=es(32),
                            alignment=ft.Alignment.CENTER,
                            padding=ft.Padding(
                                left=es(5),
                                top=0,
                                right=es(5),
                                bottom=0,
                            ),
                            border=ft.Border.all(1, self.accent_color()),
                            border_radius=self.rounding(),
                            ink=True,
                            tooltip="Change set type",
                            on_click=lambda e, target=set_row: choose_set_type(target),
                            content=ft.Text(
                                set_row.get("set_type", "Normal"),
                                size=efs(11),
                                max_lines=1,
                                overflow=ft.TextOverflow.ELLIPSIS,
                                text_align=ft.TextAlign.CENTER,
                            ),
                        ),
                    )

                    set_controls.append(
                        ft.Row(
                            controls=[
                                weight_display,
                                reps,
                                rest,
                                type_button,
                            ],
                            spacing=field_gap,
                            vertical_alignment=ft.CrossAxisAlignment.CENTER,
                        )
                    )

                exercise_name = row["exercise_name"] or "Choose exercise"
                is_placeholder = not bool((row.get("exercise_name") or "").strip())
                name_button = ft.Container(
                    height=es(42),
                    expand=True,
                    alignment=ft.Alignment.CENTER_LEFT,
                    padding=ft.Padding(
                        left=es(10),
                        top=0,
                        right=es(7),
                        bottom=0,
                    ),
                    border=ft.Border.all(
                        1,
                        self.accent_color()
                        if is_placeholder
                        else self.field_border_color(),
                    ),
                    border_radius=self.rounding(),
                    ink=True,
                    on_click=lambda e, target=row: choose_exercise(target),
                    tooltip="Choose / change exercise",
                    content=ft.Row(
                        controls=[
                            ft.Text(
                                exercise_name,
                                size=efs(14),
                                weight=ft.FontWeight.BOLD,
                                color=(
                                    self.accent_color()
                                    if is_placeholder
                                    else self.foreground_color()
                                ),
                                max_lines=1,
                                no_wrap=True,
                                overflow=ft.TextOverflow.ELLIPSIS,
                                expand=True,
                            ),
                            ft.Icon(
                                ft.Icons.SWAP_HORIZ,
                                size=es(20),
                                color=self.accent_color(),
                            ),
                        ],
                        spacing=es(4),
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                )
                row["name_button"] = name_button

                # Reordering is intentionally arrow-only.  Drag-and-drop was
                # removed completely so the exercise name and actions stay on
                # one predictable row on every phone width.
                header_row = ft.Row(
                    controls=[
                        name_button,
                        editor_action(
                            ft.Icons.EDIT_OUTLINED,
                            on_click=lambda e, target=row: open_exercise_details_from_editor(target),
                            tooltip="Edit exercise details",
                            enabled=not is_placeholder,
                        ),
                        editor_action(
                            ft.Icons.ARROW_UPWARD,
                            on_click=lambda e, rid=row_id: move_by(rid, -1),
                            tooltip="Move exercise up",
                            enabled=row_index > 0,
                        ),
                        editor_action(
                            ft.Icons.ARROW_DOWNWARD,
                            on_click=lambda e, rid=row_id: move_by(rid, 1),
                            tooltip="Move exercise down",
                            enabled=row_index < len(exercise_edit_rows) - 1,
                        ),
                        editor_action(
                            ft.Icons.DELETE_OUTLINE,
                            on_click=lambda e, rid=row_id: remove_row(rid),
                            tooltip="Remove exercise",
                            color=ft.Colors.WHITE,
                            bgcolor=ft.Colors.RED_700,
                            border_color=ft.Colors.RED_700,
                        ),
                    ],
                    spacing=es(5),
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                )

                card = ft.Container(
                    padding=ft.Padding(
                        left=es(8),
                        top=es(8),
                        right=es(8),
                        bottom=es(8),
                    ),
                    border=ft.Border.all(
                        1,
                        ft.Colors.with_opacity(
                            0.44,
                            self.field_border_color(),
                        ),
                    ),
                    border_radius=self.rounding(),
                    content=ft.Column(
                        controls=[
                            header_row,
                            ft.Column(controls=set_controls, spacing=es(6)),
                            ft.Row(
                                controls=[
                                    self.set_adjust_button(
                                        "+",
                                        "Add set",
                                        lambda e, target=row: add_set_to_exercise(target),
                                    ),
                                    self.set_adjust_button(
                                        "−",
                                        "Remove last set",
                                        lambda e, target=row: remove_set_from_exercise(target),
                                    ),
                                ],
                                spacing=es(7),
                            ),
                        ],
                        spacing=es(8),
                    ),
                )
                exercise_fields.controls.append(card)

            refresh_summaries()
            self.page.update()

        def add_exercise_field(exercise=None):
            snapshot_row_controls()
            exercise_edit_rows.append(new_row_data(exercise))
            render_rows()

        for exercise in workout["exercises"]:
            exercise_edit_rows.append(new_row_data(exercise))

        def save(e):
            numeric_valid = self.normalize_numeric_control(
                workout_set_seconds,
                kind="seconds",
                allow_empty=False,
            )
            for row in exercise_edit_rows:
                for set_row in row.get("sets", []):
                    weight_field = set_row.get("_weight_field")
                    reps_field = set_row.get("_reps_field")
                    if weight_field is not None and not self.normalize_numeric_control(
                        weight_field,
                        kind="weight",
                        allow_empty=True,
                    ):
                        numeric_valid = False
                    if reps_field is not None and not self.normalize_numeric_control(
                        reps_field,
                        kind="reps",
                        allow_empty=True,
                    ):
                        numeric_valid = False
            if not numeric_valid:
                self.page.update()
                return

            snapshot_row_controls()

            valid = True
            if not (name_field.value or "").strip():
                self.mark_field_invalid(name_field)
                valid = False
            else:
                self.clear_field_invalid(name_field)

            if not exercise_edit_rows:
                exercise_edit_rows.append(new_row_data())
                render_rows()

            for row in exercise_edit_rows:
                if (row.get("exercise_name") or "").strip():
                    continue
                valid = False
                button = row.get("name_button")
                if button is not None:
                    button.style = ft.ButtonStyle(
                        shape=ft.RoundedRectangleBorder(radius=self.rounding()),
                        side=ft.BorderSide(2.2, ft.Colors.RED_500),
                    )

            if not valid:
                self.page.update()
                return

            output_exercises = []
            for row in exercise_edit_rows:
                if not row["exercise_name"]:
                    continue
                output_sets = []
                for set_row in row["sets"]:
                    output_sets.append(
                        {
                            "weight": set_row.get("weight", ""),
                            "reps": set_row.get("reps", ""),
                            "rest_seconds": set_row.get("rest_seconds", default_rest),
                            "set_type": set_row.get("set_type", "Normal"),
                        }
                    )
                output_exercises.append(
                    {
                        "exercise_name": row["exercise_name"],
                        "sets": output_sets,
                    }
                )

            def commit_save():
                self.workout_editor_draft = None
                storage.save_workout(
                    workout_id=workout_id,
                    name=name_field.value,
                    exercises=output_exercises,
                )
                storage.save_workout_details(
                    workout_id,
                    workout_description.value,
                    workout_details.get("note", ""),
                    workout_set_seconds.value,
                    workout_set_overhead.value,
                    workout_transition.value,
                    workout_session_overhead.value,
                )
                self.show_saved_workouts()

            if active_cycle and not is_new:
                dialog = ft.AlertDialog(
                    modal=True,
                    title=ft.Text("Change workout during active mesocycle?"),
                    content=ft.Text(
                        "Changing exercises, set counts, rep/load targets or other workout settings can make progressive-overload comparisons less clean. The change is allowed, but treat it as a deliberate program change rather than normal progression."
                    ),
                    actions=[
                        self.outlined_button(
                            "Cancel",
                            on_click=lambda e: self.close_dialog(dialog),
                        ),
                        self.filled_button(
                            "Save change",
                            on_click=lambda e: (
                                self.close_dialog(dialog),
                                commit_save(),
                            ),
                        ),
                    ],
                )
                self.page.show_dialog(dialog)
            else:
                commit_save()

        def delete(e):
            self.workout_editor_draft = None
            if self.active_workout and self.active_workout["workout_id"] == workout_id:
                self.notify("Finish or discard the active workout before deleting it.")
                return
            storage.delete_workout(workout_id)
            self.show_saved_workouts()

        footer_controls = [
            self.filled_button("Save", on_click=save, expand=True)
        ]
        if not is_new:
            footer_controls.append(
                ft.FilledButton(
                    content="Delete",
                    on_click=delete,
                    color=ft.Colors.WHITE,
                    bgcolor=ft.Colors.RED_700,
                    style=self.button_style(),
                )
            )
        editor_footer = ft.Row(controls=footer_controls, spacing=self.ui(10))

        def show_time_approximator():
            snapshot_row_controls()
            refresh_summaries()

            for field in (
                workout_set_seconds,
                workout_set_overhead,
                workout_transition,
                workout_session_overhead,
            ):
                field.on_change = lambda e: refresh_summaries(update_page=True)

            controls = [
                ft.Text(
                    "Workout Time Approximator",
                    size=self.fs(28),
                    weight=ft.FontWeight.BOLD,
                ),
                time_target_large,
                ft.Text(
                    "Use this estimate to check whether the workout fits the time "
                    "you actually have. If your real sessions consistently run "
                    "longer or shorter, adjust the values below until the estimate "
                    "matches your normal pace.",
                    size=self.fs(12),
                ),
                workout_set_seconds,
                workout_set_overhead,
                workout_transition,
                workout_session_overhead,
                ft.Container(
                    padding=ft.Padding(left=self.ui(10), top=self.ui(10), right=self.ui(10), bottom=self.ui(10)),
                    border=ft.Border.all(1, ft.Colors.GREY_700),
                    border_radius=self.rounding(),
                    content=ft.Column(
                        controls=[
                            ft.Text("Tune it to your routine", weight=ft.FontWeight.BOLD),
                            ft.Text(
                                "If your sets usually take longer, increase Set duration. "
                                "If changing plates or logging takes time, increase Setup / logging.",
                                size=self.fs(12),
                            ),
                            ft.Text(
                                "Use Between exercises for walking, waiting for equipment, "
                                "and setting up the next station. Session overhead covers "
                                "everything else that regularly adds a few minutes.",
                                size=self.fs(12),
                            ),
                            ft.Text(
                                "Keep your programmed Rest values realistic. The goal is not "
                                "to make the estimate smaller; it is to make it resemble your "
                                "actual sessions.",
                                size=self.fs(12),
                            ),
                            time_breakdown_text,
                        ],
                        spacing=self.ui(7),
                    ),
                ),
                ft.Text(
                    "After a few real workouts, adjust these values once and leave them alone. "
                    "The estimate becomes most useful when it reflects your normal pace.",
                    size=self.fs(12),
                ),
            ]
            self.set_view(
                controls,
                footer=self.filled_button(
                    "Done",
                    on_click=lambda e: show_editor_view(),
                    expand=True,
                ),
                back_action=show_editor_view,
            )

        time_link = ft.Container(
            width=self.ui(66),
            height=self.ui(44),
            alignment=ft.Alignment.CENTER,
            ink=True,
            tooltip="Workout Time Approximator",
            on_click=lambda e: show_time_approximator(),
            content=ft.Row(
                controls=[
                    ft.Icon(
                        ft.Icons.TIMER_OUTLINED,
                        size=self.ui(17),
                        color=self.accent_color(),
                    ),
                    time_target_text,
                ],
                spacing=self.ui(2),
                alignment=ft.MainAxisAlignment.CENTER,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

        def show_editor_view():
            snapshot_row_controls()
            refresh_summaries()

            warning = None
            if active_cycle and not is_new:
                warning_text = (
                    "Active mesocycle — changing the program can make progressive-overload "
                    "comparisons less consistent."
                )
                if rest_locked_by_cycle:
                    warning_text += " Rest times are locked from Cycle."
                warning = ft.Text(
                    warning_text,
                    size=self.fs(11),
                    color=ft.Colors.ORANGE_400,
                    weight=ft.FontWeight.W_500,
                )

            top_controls = [
                ft.Text(
                    "New Workout" if is_new else "Edit Workout",
                    size=self.fs(28),
                    weight=ft.FontWeight.BOLD,
                ),
            ]
            if warning is not None:
                top_controls.append(warning)

            top_controls.extend(
                [
                    ft.Row(
                        controls=[
                            name_field,
                            workout_description,
                            time_link,
                        ],
                        spacing=self.ui(6),
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    muscle_summary,
                    ft.Text(
                        "Exercises",
                        size=self.fs(18),
                        weight=ft.FontWeight.BOLD,
                    ),
                    exercise_fields,
                    self.outlined_button(
                        "+ Exercise",
                        on_click=lambda e: add_exercise_field(),
                    ),
                ]
            )

            self.set_view(
                top_controls,
                footer=editor_footer,
                back_action=self.show_saved_workouts,
            )

        render_rows()
        show_editor_view()
