import ast
import asyncio
import math
import time
import uuid
from datetime import datetime

import flet as ft

import storage


class HistoryMixin:

    def show_workout_history(self, workout_id=None):
        self.selected_tab = 1
        self.page.navigation_bar.selected_index = 1

        sessions = (
            storage.workout_sessions(workout_id, limit=100)
            if workout_id
            else storage.all_sessions(limit=100)
        )

        controls = []

        # Only show the clock when it helps distinguish multiple workouts on
        # the same calendar day in the currently displayed history list.
        session_day_counts = {}
        session_day_keys = {}
        for session in sessions:
            raw_date = session.get("date", "")
            try:
                day_key = datetime.fromisoformat(raw_date).date().isoformat()
            except (TypeError, ValueError):
                day_key = str(raw_date).split("T", 1)[0].split(" ", 1)[0]
            session_day_keys[session.get("session_id", "")] = day_key
            session_day_counts[day_key] = session_day_counts.get(day_key, 0) + 1

        if workout_id:
            workout = storage.read_workout(workout_id)
            title = (
                f'{workout["name"]} History'
                if workout is not None
                else "Workout History"
            )

            controls.append(
                ft.Row(
                    controls=[
                        ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="All history",
                            on_click=lambda e: self.show_workout_history(),
                        ),
                        ft.Text(
                            title,
                            size=self.fs(25),
                            weight=ft.FontWeight.BOLD,
                        ),
                    ]
                )
            )
        else:
            controls.append(
                ft.Text(
                    "History",
                    size=self.fs(28),
                    weight=ft.FontWeight.BOLD,
                )
            )

        if not workout_id:
            controls.append(
                ft.Text(
                    "Workout History",
                    size=self.fs(18),
                    weight=ft.FontWeight.BOLD,
                )
            )

        if not sessions:
            controls.append(ft.Text("No completed workouts yet."))
        else:
            for session in sessions:
                session_id = session["session_id"]

                controls.append(
                    ft.Container(
                        width=float("inf"),
                        padding=ft.Padding(
                            left=self.ui(10),
                            top=self.ui(8),
                            right=self.ui(8),
                            bottom=self.ui(8),
                        ),
                        border=ft.Border.all(1, ft.Colors.GREY_700),
                        border_radius=self.rounding(),
                        ink=True,
                        on_click=lambda e, sid=session_id, wid=workout_id: self.show_history_session(
                            sid,
                            back_target="history",
                            history_workout_id=wid,
                        ),
                        content=ft.Row(
                            controls=[
                                ft.Text(
                                    session["workout_name"],
                                    weight=ft.FontWeight.BOLD,
                                    expand=True,
                                ),
                                ft.Text(
                                    self.format_recent_datetime(
                                        session["date"],
                                        include_time=(
                                            session_day_counts.get(
                                                session_day_keys.get(session_id, ""),
                                                0,
                                            ) > 1
                                        ),
                                    ),
                                    size=self.fs(12),
                                ),
                            ],
                            vertical_alignment=ft.CrossAxisAlignment.CENTER,
                        ),
                    )
                )

        if not workout_id:
            controls.extend(self.previous_mesocycle_controls(limit=6))

        self.set_view(
            controls,
            back_action=(lambda: self.show_workout_history()) if workout_id else None,
            root_back_to_active=(workout_id is None),
        )

    def show_exercise_history(self, exercise_name, back_to_active=False):
        """Show completed history for one exercise without leaving the workout flow."""
        exercise_name = str(exercise_name or "").strip()
        if not exercise_name:
            return

        if back_to_active and self.active_workout and self.set_controls:
            # Preserve anything typed into the running workout before replacing
            # its controls with the history screen.
            self.capture_active_controls()

        if back_to_active:
            self.selected_tab = 0
            self.page.navigation_bar.selected_index = 0
            back_action = self.show_active_workout
        else:
            self.selected_tab = 1
            self.page.navigation_bar.selected_index = 1
            back_action = self.show_workout_history

        sessions = storage.exercise_sessions(exercise_name, limit=100)

        controls = [
            ft.Row(
                controls=[
                    ft.IconButton(
                        icon=ft.Icons.ARROW_BACK,
                        tooltip="Back",
                        on_click=lambda e: back_action(),
                    ),
                    ft.Column(
                        controls=[
                            ft.Text(
                                exercise_name,
                                size=self.fs(23),
                                weight=ft.FontWeight.BOLD,
                                max_lines=1,
                                overflow=ft.TextOverflow.ELLIPSIS,
                            ),
                            ft.Text(
                                "Exercise History",
                                size=self.fs(11),
                                color=ft.Colors.GREY_500,
                            ),
                        ],
                        spacing=0,
                        expand=True,
                    ),
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            )
        ]

        if not sessions:
            controls.append(
                ft.Text(
                    "No completed history for this exercise yet.",
                    color=ft.Colors.GREY_500,
                )
            )
        else:
            for session in sessions:
                set_lines = []
                for row in session.get("rows", []):
                    raw_weight = str(row.get("weight", "") or "").strip()
                    weight = self.format_weight_text(raw_weight) if raw_weight else "—"
                    unit = str(row.get("weight_unit", "") or "").strip()
                    reps = str(row.get("reps", "") or "").strip() or "—"
                    rir = str(row.get("rir", "") or "").strip()
                    set_type = str(row.get("set_type", "Normal") or "Normal").strip()

                    text = (
                        f"{weight}{(' ' + unit) if unit else ''} × {reps} reps"
                    )
                    if rir and not storage.is_warmup_set_type(set_type):
                        text += f" · {rir} RIR"
                    if not storage.is_straight_set_type(set_type):
                        text += f" · {set_type}"
                    set_lines.append(text)

                controls.append(
                    ft.Container(
                        width=float("inf"),
                        padding=ft.Padding(
                            left=self.ui(10),
                            top=self.ui(8),
                            right=self.ui(10),
                            bottom=self.ui(8),
                        ),
                        border=ft.Border.all(1, ft.Colors.GREY_700),
                        border_radius=self.rounding(),
                        content=ft.Column(
                            controls=[
                                ft.Row(
                                    controls=[
                                        ft.Text(
                                            session.get("workout_name", "Workout") or "Workout",
                                            weight=ft.FontWeight.BOLD,
                                            expand=True,
                                            max_lines=1,
                                            overflow=ft.TextOverflow.ELLIPSIS,
                                        ),
                                        ft.Text(
                                            self.format_recent_datetime(
                                                session.get("date", ""),
                                                include_time=False,
                                            ),
                                            size=self.fs(11),
                                            color=ft.Colors.GREY_500,
                                        ),
                                    ],
                                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                                ),
                                *[
                                    ft.Text(
                                        line,
                                        size=self.fs(12),
                                        max_lines=1,
                                        overflow=ft.TextOverflow.ELLIPSIS,
                                    )
                                    for line in set_lines
                                ],
                            ],
                            spacing=self.ui(3),
                            tight=True,
                        ),
                    )
                )

        self.set_view(
            controls,
            back_action=back_action,
            hide_active_return_bar=back_to_active,
        )

    def show_history_session(
        self,
        session_id,
        back_target="history",
        history_workout_id=None,
    ):
        session = storage.read_session(session_id)

        if session is None:
            self.notify("Historical workout not found.")

            if back_target == "main":
                self.show_saved_workouts()
            else:
                self.show_workout_history(history_workout_id)
            return

        if back_target == "main":
            self.selected_tab = 0
            self.page.navigation_bar.selected_index = 0
        else:
            self.selected_tab = 1
            self.page.navigation_bar.selected_index = 1

        session_rows = []
        grouped = []

        # Preserve exercise order from the original saved session.
        by_name = {}
        for row in session["rows"]:
            name = row["exercise_name"]

            if name not in by_name:
                group = {
                    "exercise_name": name,
                    "training_method": "",
                    "sets": [],
                }
                by_name[name] = group
                grouped.append(group)

            by_name[name]["sets"].append(dict(row))
            if row.get("training_method"):
                by_name[name]["training_method"] = storage.canonical_training_method(
                    row.get("training_method")
                )

        for group in grouped:
            group["training_method"] = storage.resolve_training_method(
                group.get("training_method", ""), group.get("sets", [])
            )
            group["sets"] = storage.reconcile_method_sets(
                group["training_method"], group.get("sets", [])
            )

        controls_column = ft.Column(spacing=self.ui(12))

        def choose_exercise(group):
            self.open_exercise_picker(
                lambda selected: change_exercise(group, selected)
            )

        def change_exercise(group, selected):
            group["exercise_name"] = selected
            render()

        def choose_set_type(group, set_row):
            try:
                row_index = group["sets"].index(set_row)
            except ValueError:
                row_index = 0
            choices = storage.set_type_choices_for_method_row(
                group.get("training_method", "Straight"),
                group.get("sets", []),
                row_index,
            )
            self.open_set_type_picker(
                set_row.get("set_type", "Normal"),
                lambda selected: change_type(group, set_row, selected),
                choices=choices,
            )

        def change_type(group, set_row, selected):
            snapshot()
            set_row["set_type"] = selected
            group["sets"] = storage.reconcile_method_sets(
                group.get("training_method", "Straight"), group.get("sets", [])
            )
            for row in group["sets"]:
                if not storage.method_set_uses_rir(
                    group.get("training_method", "Straight"), row.get("set_type")
                ):
                    row["rir"] = ""
            render()

        def snapshot():
            for group in grouped:
                for row in group["sets"]:
                    for field_name, key in (
                        ("weight_control", "weight"),
                        ("reps_control", "reps"),
                        ("rir_control", "rir"),
                        ("note_control", "note"),
                    ):
                        control = row.get(field_name)
                        if isinstance(control, ft.TextField):
                            row[key] = control.value or ""

        def remove_set(group, row):
            snapshot()

            if row in group["sets"]:
                group["sets"].remove(row)

            if not group["sets"] and group in grouped:
                grouped.remove(group)
            elif group in grouped:
                group["sets"] = storage.reconcile_method_sets(
                    group.get("training_method", "Straight"), group.get("sets", [])
                )

            render()

        def add_set(group):
            snapshot()

            previous = group["sets"][-1] if group["sets"] else {}
            method = group.get("training_method", "Straight")
            next_type = storage.default_next_set_type(method, group.get("sets", []))

            group["sets"].append(
                {
                    "weight": previous.get("weight", ""),
                    "reps": previous.get("reps", ""),
                    "rir": (
                        previous.get("rir", "")
                        if storage.method_set_uses_rir(method, next_type)
                        else ""
                    ),
                    "set_type": next_type,
                    "note": "",
                    "completed": False,
                }
            )
            group["sets"] = storage.reconcile_method_sets(method, group["sets"])

            render()

        def add_exercise():
            def selected(name):
                grouped.append(
                    {
                        "exercise_name": name,
                        "training_method": "Straight",
                        "sets": [
                            {
                                "weight": "",
                                "reps": "",
                                "rir": "",
                                "set_type": "Normal",
                                "note": "",
                                "completed": False,
                            }
                        ],
                    }
                )
                render()

            self.open_exercise_picker(selected)

        def render():
            snapshot()
            controls_column.controls.clear()

            for group in grouped:
                exercise_name = group["exercise_name"]
                training_method = group.get("training_method", "Straight")
                note_containers = []
                history_done = sum(
                    1 for row in group["sets"] if row.get("completed", True)
                )
                history_total = len(group["sets"])

                notes_visible = any(
                    bool((row.get("note", "") or "").strip())
                    for row in group["sets"]
                )

                notes_button = ft.IconButton(
                    icon=(
                        ft.Icons.NOTES
                        if notes_visible
                        else ft.Icons.NOTES_OUTLINED
                    ),
                    tooltip="Show/hide notes",
                )

                def toggle_notes(e, containers=note_containers, button=notes_button):
                    visible = not any(
                        container.visible
                        for container in containers
                    )

                    for container in containers:
                        container.visible = visible

                    button.icon = (
                        ft.Icons.NOTES
                        if visible
                        else ft.Icons.NOTES_OUTLINED
                    )
                    self.page.update()

                notes_button.on_click = toggle_notes

                set_controls = []

                for index, row in enumerate(group["sets"], start=1):
                    weight = self.text_field(
                        value=row.get("weight", ""),
                        hint_text="Weight",
                        width=self.SET_WEIGHT_WIDTH,
                        dense=True,
                        text_align=ft.TextAlign.CENTER,
                        keyboard_type=ft.KeyboardType.NUMBER,
                        numeric_kind="weight",
                    )
                    weight_display, _ = self.weight_field_with_unit(
                        weight,
                        self.SET_WEIGHT_WIDTH,
                    )
                    reps = self.text_field(
                        value=row.get("reps", ""),
                        hint_text="Reps",
                        width=self.SET_SMALL_WIDTH,
                        dense=True,
                        text_align=ft.TextAlign.CENTER,
                        keyboard_type=ft.KeyboardType.NUMBER,
                        numeric_kind="reps",
                    )
                    reps_display, _ = self.field_with_suffix(
                        reps,
                        self.SET_SMALL_WIDTH,
                        "reps",
                    )
                    set_type = row.get("set_type", "Normal") or "Normal"
                    warmup_set = storage.is_warmup_set_type(set_type)
                    uses_rir = storage.method_set_uses_rir(training_method, set_type)
                    if not uses_rir:
                        row["rir"] = ""
                    rir = self.text_field(
                        value=row.get("rir", "") if uses_rir else "",
                        hint_text="RIR",
                        width=self.SET_SMALL_WIDTH,
                        dense=True,
                        text_align=ft.TextAlign.CENTER,
                        keyboard_type=ft.KeyboardType.NUMBER,
                        numeric_kind="rir",
                    )
                    if not uses_rir:
                        rir_display = ft.Container(width=0, visible=False)
                    else:
                        rir_display, _ = self.field_with_suffix(
                            rir,
                            self.SET_SMALL_WIDTH,
                            "RIR",
                        )
                    note = self.text_field(
                        value=row.get("note", ""),
                        hint_text="Note",
                        expand=True,
                        dense=True,
                    )

                    if uses_rir:
                        self.chain_text_fields(weight, reps, rir)
                    else:
                        self.chain_text_fields(weight, reps)

                    row["weight_control"] = weight
                    row["reps_control"] = reps
                    row["rir_control"] = rir
                    row["note_control"] = note

                    type_button = self.active_set_type_button(
                        set_type,
                        index,
                    )
                    type_button.on_click = (
                        lambda e, g=group, target=row: choose_set_type(g, target)
                    )

                    note_container = ft.Container(
                        visible=notes_visible,
                        padding=ft.Padding(
                            left=self.ui(52),
                            top=2,
                            right=0,
                            bottom=0,
                        ),
                        content=note,
                    )
                    note_containers.append(note_container)

                    done_button = self.set_ok_button(
                        bool(row.get("completed", True))
                    )

                    def toggle_history_done(
                        e, target=row, button=done_button, method=training_method
                    ):
                        making_complete = not bool(target.get("completed", True))

                        if making_complete:
                            required = [
                                target.get("weight_control"),
                                target.get("reps_control"),
                            ]
                            if (
                                self.track_rir_enabled()
                                and storage.method_set_uses_rir(
                                    method, target.get("set_type")
                                )
                            ):
                                required.append(target.get("rir_control"))

                            missing = [
                                field
                                for field in required
                                if isinstance(field, ft.TextField)
                                and not (field.value or "").strip()
                            ]
                            if missing:
                                for field in missing:
                                    self.mark_field_invalid(field)
                                self.page.update()
                                return

                        target["completed"] = making_complete
                        button.bgcolor = ft.Colors.GREEN_700 if making_complete else None
                        button.content.color = (
                            ft.Colors.WHITE if making_complete else ft.Colors.GREEN_500
                        )
                        self.page.update()

                    done_button.on_click = toggle_history_done

                    delete_set = ft.IconButton(
                        icon=ft.Icons.DELETE_OUTLINE,
                        icon_color=ft.Colors.RED_400,
                        tooltip="Delete set",
                        on_click=lambda e, g=group, target=row: remove_set(
                            g, target
                        ),
                    )

                    set_controls.append(
                        ft.Column(
                            controls=[
                                ft.Row(
                                    controls=[
                                        type_button,
                                        weight_display,
                                        reps_display,
                                        rir_display,
                                        ft.Container(expand=True),
                                        done_button,
                                        delete_set,
                                    ],
                                    spacing=self.ui(4),
                                ),
                                note_container,
                            ],
                            spacing=self.ui(4),
                        )
                    )

                controls_column.controls.append(
                    ft.Container(
                        padding=ft.Padding(
                            left=0,
                            top=self.ui(4),
                            right=0,
                            bottom=self.ui(10),
                        ),
                        content=ft.Column(
                            controls=[
                                ft.Row(
                                    controls=[
                                        ft.Container(
                                            expand=True,
                                            ink=True,
                                            on_click=lambda e, g=group: choose_exercise(
                                                g
                                            ),
                                            content=ft.Text(
                                                exercise_name,
                                                size=self.fs(19),
                                                weight=ft.FontWeight.BOLD,
                                            ),
                                        ),
                                        ft.Text(
                                            f"{history_done}/{history_total} done",
                                            size=self.fs(10),
                                            color=(
                                                ft.Colors.GREY_500
                                                if history_done == history_total
                                                else ft.Colors.ORANGE_400
                                            ),
                                        ),
                                        notes_button,
                                    ]
                                ),
                                ft.Column(
                                    controls=set_controls,
                                    spacing=self.ui(self.set_spacing()),
                                ),
                                self.set_adjust_button(
                                    "+",
                                    "Add set",
                                    lambda e, g=group: add_set(g),
                                ),
                                ft.Divider(),
                            ],
                            spacing=self.ui(8),
                        ),
                    )
                )

            controls_column.controls.append(
                self.outlined_button(
                    "+ Exercise",
                    on_click=lambda e: add_exercise(),
                )
            )

            self.page.update()

        render()

        workout_name = self.text_field(
            value=session["workout_name"],
            hint_text="Workout name",
            dense=True,
        )
        try:
            workout_date_value = datetime.fromisoformat(
                str(session.get("date", "") or "")
            ).date().isoformat()
        except (TypeError, ValueError):
            workout_date_value = str(session.get("date", "") or "")[:10]

        workout_date = self.text_field(
            label="Workout date",
            value=workout_date_value,
            hint_text="YYYY-MM-DD",
            dense=True,
        )

        def save(e):
            numeric_valid = True
            for group in grouped:
                for row in group["sets"]:
                    for key, kind in (
                        ("weight_control", "weight"),
                        ("reps_control", "reps"),
                        ("rir_control", "rir"),
                    ):
                        if kind == "rir" and not storage.method_set_uses_rir(
                            group.get("training_method", "Straight"), row.get("set_type")
                        ):
                            continue
                        field = row.get(key)
                        if field is not None and not self.normalize_numeric_control(
                            field,
                            kind=kind,
                            allow_empty=True,
                        ):
                            numeric_valid = False
            if not numeric_valid:
                self.page.update()
                return

            requested_date = str(workout_date.value or "").strip()
            try:
                requested_date = datetime.fromisoformat(requested_date).date().isoformat()
            except (TypeError, ValueError):
                self.mark_field_invalid(workout_date)
                self.notify("Workout date must use YYYY-MM-DD.")
                self.page.update()
                return
            self.clear_field_invalid(workout_date)

            snapshot()
            rows = []

            for group in grouped:
                for row in group["sets"]:
                    rows.append(
                        {
                            "exercise_name": group["exercise_name"],
                            "weight": row.get("weight", ""),
                            "reps": row.get("reps", ""),
                            "rir": (
                                row.get("rir", "")
                                if storage.method_set_uses_rir(
                                    group.get("training_method", "Straight"),
                                    row.get("set_type"),
                                )
                                else ""
                            ),
                            "set_type": row.get("set_type", "Normal"),
                            "training_method": group.get("training_method", "Straight"),
                            "note": row.get("note", ""),
                            "completed": bool(row.get("completed", True)),
                        }
                    )

            count = storage.save_session(
                session_id,
                workout_name.value,
                rows,
                session_date=requested_date,
            )

            self.notify(f"Saved {count} historical set(s).")
            self.show_history_session(
                session_id,
                back_target=back_target,
                history_workout_id=history_workout_id,
            )

        def delete(e):
            storage.delete_session(session_id)
            self.notify("Historical workout deleted.")

            if back_target == "main":
                self.show_saved_workouts()
            else:
                self.show_workout_history(history_workout_id)

        header = ft.Container(
            bgcolor=self.nav_surface_color(),
            padding=ft.Padding(
                left=self.ui(12),
                top=self.ui(8),
                right=self.ui(12),
                bottom=self.ui(8),
            ),
            content=ft.Row(
                controls=[
                    ft.IconButton(
                        icon=ft.Icons.ARROW_BACK,
                        on_click=lambda e: (
                            self.show_saved_workouts()
                            if back_target == "main"
                            else self.show_workout_history(history_workout_id)
                        ),
                    ),
                    ft.Column(
                        controls=[
                            ft.Text(
                                "History",
                                weight=ft.FontWeight.BOLD,
                            ),
                            ft.Text(
                                self.format_recent_datetime(session["date"]),
                                size=self.fs(11),
                            ),
                        ],
                        spacing=0,
                        expand=True,
                    ),
                    self.icon_action(
                        ft.Icons.SAVE,
                        ft.Colors.GREEN_700,
                        save,
                        width=48,
                        height=42,
                        tooltip="Save historical workout",
                    ),
                    self.icon_action(
                        ft.Icons.DELETE,
                        ft.Colors.RED_700,
                        delete,
                        width=42,
                        height=42,
                        tooltip="Delete historical workout",
                    ),
                ]
            ),
        )

        history_back = (
            self.show_saved_workouts
            if back_target == "main"
            else lambda: self.show_workout_history(history_workout_id)
        )

        self.set_view(
            [
                workout_name,
                workout_date,
                controls_column,
            ],
            header=header,
            back_action=history_back,
        )

    def workout_start_tile(
        self,
        workout,
        summary=None,
        cycle_rir=None,
        is_featured=False,
        featured_label="",
    ):
        workout_id = workout["workout_id"]
        summary = summary or storage.workout_list_summaries().get(workout_id, {})

        exercise_rows = []
        has_sets = bool(summary.get("has_sets", False))
        muscle_summary = summary.get("primary_muscles", [])

        for exercise in summary.get("exercises", []):
            set_count = int(exercise.get("set_count", 0) or 0)
            prescription = f"{set_count} set" if set_count == 1 else f"{set_count} sets"
            exercise_rows.append(
                ft.Container(
                    padding=ft.Padding(
                        left=self.ui(18),
                        top=1,
                        right=self.ui(4),
                        bottom=1,
                    ),
                    content=ft.Row(
                        controls=[
                            ft.Text(
                                exercise.get("exercise_name", ""),
                                size=self.fs(12.5),
                                weight=ft.FontWeight.W_500,
                                expand=True,
                            ),
                            ft.Text(
                                prescription,
                                size=self.fs(12),
                                weight=ft.FontWeight.BOLD,
                            )
                            if set_count
                            else ft.Container(),
                        ],
                        spacing=self.ui(8),
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                )
            )

        def primary_action(e):
            if has_sets:
                self.start_workout(workout_id)
            else:
                self.edit_workout_from_workout_tab(workout_id)

        # Full-width strip so blank space on either side is also tappable.
        card = ft.Container(
            width=float("inf"),
            padding=ft.Padding(
                left=self.ui(13),
                top=self.ui(11),
                right=self.ui(13),
                bottom=self.ui(11),
            ),
            bgcolor=ft.Colors.with_opacity(
                0.13 if is_featured else 0.055,
                self.accent_color(),
            ),
            border=(
                ft.Border.all(1.5, self.accent_color())
                if is_featured
                else None
            ),
            border_radius=self.rounding(),
            ink=True,
            on_click=primary_action,
            content=ft.Column(
                controls=[
                    ft.Row(
                        controls=[
                            ft.Text(
                                workout["name"],
                                size=self.fs(24),
                                weight=ft.FontWeight.BOLD,
                                expand=True,
                            ),
                            *(
                                [
                                    ft.Container(
                                        padding=ft.Padding(
                                            left=self.ui(7),
                                            top=self.ui(3),
                                            right=self.ui(7),
                                            bottom=self.ui(3),
                                        ),
                                        bgcolor=self.accent_color(),
                                        border_radius=self.rounding(),
                                        content=ft.Text(
                                            featured_label or "ACTIVE",
                                            size=self.fs(9.5),
                                            weight=ft.FontWeight.BOLD,
                                            color=ft.Colors.WHITE,
                                        ),
                                    )
                                ]
                                if is_featured
                                else []
                            ),
                            ft.IconButton(
                                icon=ft.Icons.EDIT_OUTLINED,
                                tooltip="Edit workout",
                                icon_size=self.ui(20),
                                on_click=lambda e, wid=workout_id: self.edit_workout_from_workout_tab(
                                    wid
                                ),
                            ),
                        ],
                        spacing=self.ui(4),
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    *([
                        ft.Text(
                            f"{cycle_rir} RIR",
                            size=self.fs(11.5),
                            weight=ft.FontWeight.BOLD,
                            color=self.accent_color(),
                        )
                    ] if cycle_rir is not None else []),
                    *([
                        ft.Text(
                            " · ".join(muscle_summary),
                            size=self.fs(11),
                            weight=ft.FontWeight.W_500,
                            color=ft.Colors.GREY_500,
                        )
                    ] if muscle_summary else []),
                    ft.Container(height=2),
                    *exercise_rows,
                ],
                spacing=1,
            ),
        )

        menu_items = []

        if has_sets:
            menu_items.append(
                ft.PopupMenuItem(
                    icon=ft.Icons.PLAY_ARROW,
                    content="Start",
                    on_click=lambda e, wid=workout_id: self.start_workout(wid),
                )
            )

        menu_items.extend(
            [
                ft.PopupMenuItem(
                    icon=ft.Icons.EDIT,
                    content="Edit",
                    on_click=lambda e, wid=workout_id: self.edit_workout_from_workout_tab(
                        wid
                    ),
                ),
                ft.PopupMenuItem(
                    icon=ft.Icons.HISTORY,
                    content="History",
                    on_click=lambda e, wid=workout_id: self.show_workout_history(
                        wid
                    ),
                ),
            ]
        )

        return ft.Container(
            width=float("inf"),
            content=ft.ContextMenu(
                primary_trigger=ft.ContextMenuTrigger.LONG_PRESS,
                primary_items=menu_items,
                content=card,
            ),
        )
