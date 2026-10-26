import ast
import asyncio
import math
import time
import uuid
from datetime import datetime

import flet as ft

import storage
import load_modes
import set_context
import volume_accounting


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

    def show_edit(self, workout_id, is_new=False, return_to_active=False):
        workout = storage.read_workout(workout_id)

        if workout is None:
            if return_to_active and self.active_workout:
                self.show_active_workout()
            else:
                self.show_saved_workouts()
            return

        self.unregister_text_fields(
            *getattr(self, "workout_editor_numeric_fields", []),
            *getattr(self, "workout_editor_form_fields", []),
        )
        self.workout_editor_numeric_fields = []
        self.workout_editor_form_fields = []

        settings = storage.read_settings()
        default_sets = int(settings.get("default_sets", "3") or 3)
        default_rest = int(settings.get("default_rest_seconds", "180") or 180)
        workout_details = storage.read_workout_details(workout_id)
        groups_locked = bool(self.active_workout and self.active_workout.get("workout_id") == workout_id)

        def group_signature(exercises):
            return [(exercise.get("exercise_name", "").casefold(), exercise.get("training_method", "Straight"),
                     tuple(index for index, item in enumerate(exercise.get("sets", []))
                           if item.get("protocol_group_start") == "1"))
                    for exercise in exercises
                    if any(item.get("protocol_group_start") == "1" for item in exercise.get("sets", []))]

        original_groups = group_signature(workout.get("exercises", []))

        def context_signature(exercises):
            return [(exercise.get("exercise_name", "").casefold(), index, set_context.template_key(item))
                    for exercise in exercises for index, item in enumerate(exercise.get("sets", []))
                    if item.get("context_override") == "1"]

        original_contexts = context_signature(workout.get("exercises", []))

        # Returning from an exercise's pencil/details editor must not discard
        # unsaved workout edits. A one-shot in-memory draft is restored here.
        editor_draft = getattr(self, "workout_editor_draft", None)
        if (
            editor_draft
            and editor_draft.get("workout_id") == workout_id
            and bool(editor_draft.get("return_to_active", False)) == bool(return_to_active)
        ):
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

        def action_focused(e):
            self.focused_text_field = None

        name_field = self.text_field(
            label="Workout name",
            value=workout["name"],
            dense=True,
        )
        name_field.expand = False
        workout_description = self.text_field(
            hint_text="Description",
            value=workout_details.get("description", ""),
            multiline=True,
            min_lines=1,
            max_lines=2,
            dense=True,
        )
        workout_description.expand = False

        # Timing controls live on the dedicated approximator page, but stay in
        # this closure so edits survive moving back and forth before Save.
        workout_set_seconds = self.text_field(
            label="Default entry duration (seconds)",
            value=workout_details.get("set_seconds", "45") or "45",
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="seconds",
        )
        workout_set_overhead = self.text_field(
            label="Setup / logging per entry",
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

        self.workout_editor_form_fields = [
            name_field, workout_description, workout_set_seconds,
            workout_set_overhead, workout_transition, workout_session_overhead,
        ]

        exercise_fields = ft.Column(spacing=self.ui(12))
        exercise_edit_rows = []
        muscle_summary = ft.Column(spacing=self.ui(5))
        time_target_text = ft.Text(
            weight=ft.FontWeight.BOLD,
            color=self.contrast_text_color("accent"),
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
                "training_method": "Straight",
                "sets": make_default_sets(),
            }
            raw_sets = [
                {
                    "weight": str(set_row.get("weight", "") or ""),
                    "reps": str(set_row.get("reps", "") or ""),
                    "rest_seconds": storage.parse_duration(
                        set_row.get("rest_seconds", default_rest),
                        default=default_rest,
                    ),
                    "set_type": set_row.get("set_type", "Normal") or "Normal",
                    "protocol_group_start": set_row.get("protocol_group_start", ""),
                    **set_context.template_metadata(set_row),
                }
                for set_row in (exercise.get("sets") or make_default_sets())
            ]
            training_method = storage.resolve_training_method(
                exercise.get("training_method", ""), raw_sets
            )
            return {
                "id": uuid.uuid4().hex,
                "exercise_name": exercise.get("exercise_name", ""),
                "training_method": training_method,
                "sets": storage.reconcile_method_sets(training_method, raw_sets),
            }

        def snapshot_row_controls():
            for row in exercise_edit_rows:
                for set_index, set_row in enumerate(row["sets"]):
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
                        "training_method": row.get("training_method", "Straight"),
                        "sets": [
                            {
                                "weight": set_row.get("weight", ""),
                                "reps": set_row.get("reps", ""),
                                "rest_seconds": set_row.get("rest_seconds", default_rest),
                                "set_type": set_row.get("set_type", "Normal") or "Normal",
                                "protocol_group_start": set_row.get("protocol_group_start", ""),
                                **set_context.template_metadata(set_row),
                            }
                            for set_row in row.get("sets", [])
                        ],
                    }
                )
            return {
                "workout_id": workout_id,
                "return_to_active": bool(return_to_active),
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
                back_action=lambda: self.show_edit(
                    workout_id,
                    is_new=is_new,
                    return_to_active=return_to_active,
                ),
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
            report = storage.workout_volume_report(exercise_edit_rows)
            summary = [
                ft.Text("Planned work per workout", weight=ft.FontWeight.BOLD),
                ft.Text(volume_accounting.describe(report["totals"]), size=self.fs(12)),
                ft.Text(f"Protocol structure: {report['totals']['complete_protocol_groups']} complete; "
                        f"{report['totals']['partial_protocol_groups']} partial or unverified", size=self.fs(11)),
            ]
            for key, title in (("direct", "Direct involvement (primary tags)"),
                               ("indirect", "Indirect involvement (secondary tags)")):
                summary.append(ft.Text(title, size=self.fs(11), weight=ft.FontWeight.BOLD))
                if not report[key]:
                    summary.append(ft.Text("No tagged work", size=self.fs(11), color=self.contrast_text_color()))
                for muscle, metrics in report[key].items():
                    summary.append(ft.Text(f"{muscle}: {volume_accounting.describe(metrics)}", size=self.fs(11)))
            summary.append(ft.Text(
                "Warmups are separate. Protocol groups and segments are not conventional-set equivalents; secondary tags describe involvement. Left/right entries count separately; no automatic side pairing or set-equivalence conversion.",
                size=self.fs(11), color=self.contrast_text_color(),
            ))
            muscle_summary.controls = summary

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
                if not set_context.matches(known, storage.read_exercise_details(selected)):
                    known = {}
                set_row.update(set_context.template_metadata({}))
                set_row["weight"] = str(known.get("weight", "") or "")
                set_row["reps"] = str(known.get("reps", "") or "")

            row["exercise_name"] = selected
            render_rows()

        def choose_set_type(row, set_row, set_index):
            choices = storage.set_type_choices_for_method_row(
                row.get("training_method", "Straight"),
                row.get("sets", []),
                set_index,
            )
            self.open_set_type_picker(
                set_row.get("set_type", "Normal"),
                lambda selected: update_set_type(row, set_row, selected),
                choices=choices,
            )

        def update_set_type(row, set_row, selected):
            snapshot_row_controls()
            set_row["set_type"] = selected
            row["sets"] = storage.reconcile_method_sets(
                row.get("training_method", "Straight"), row.get("sets", [])
            )
            render_rows()

        def change_training_method(row, selected):
            snapshot_row_controls()
            row["training_method"] = storage.canonical_training_method(selected)
            row["sets"] = storage.reconcile_method_sets(
                row["training_method"], row.get("sets", [])
            )
            render_rows()

        def choose_training_method(row):
            self.open_training_method_picker(
                row.get("training_method", "Straight"),
                lambda selected: change_training_method(row, selected),
            )

        def add_set_to_exercise(row):
            snapshot_row_controls()
            previous = row["sets"][-1] if row["sets"] else {}
            row["sets"].append(
                {
                    "weight": previous.get("weight", ""),
                    "reps": previous.get("reps", ""),
                    **set_context.template_metadata(previous),
                    "rest_seconds": previous.get("rest_seconds", default_rest),
                    "set_type": storage.default_next_set_type(
                        row.get("training_method", "Straight"), row.get("sets", [])
                    ),
                }
            )
            row["sets"] = storage.reconcile_method_sets(
                row.get("training_method", "Straight"), row.get("sets", [])
            )
            render_rows()

        def remove_set_from_exercise(row):
            snapshot_row_controls()
            if len(row["sets"]) <= 1:
                return
            row["sets"].pop()
            render_rows()

        def toggle_group_start(row, set_row):
            if groups_locked:
                return
            snapshot_row_controls()
            set_row["protocol_group_start"] = "" if set_row.get("protocol_group_start") == "1" else "1"
            row["sets"] = storage.reconcile_method_sets(row["training_method"], row["sets"])
            render_rows()

        def add_protocol_group(row):
            if groups_locked:
                return
            snapshot_row_controls()
            work = [item for item in row["sets"] if not storage.is_warmup_set_type(item.get("set_type"))]
            # Copy only authored plan values, never control objects or observations.
            start = max((index for index, item in enumerate(work) if item.get("protocol_group_start") == "1"), default=0)
            source = work[start:]
            if not source:
                source = [{"weight": "", "reps": "", "rest_seconds": default_rest}] * 2
            elif len(source) == 1:
                source = source * 2
            for index, item in enumerate(source):
                row["sets"].append({key: item.get(key, "") for key in ("weight", "reps", "rest_seconds")}
                                   | {"protocol_group_start": "1" if index == 0 else "", **set_context.template_metadata(item)})
            row["sets"] = storage.reconcile_method_sets(row["training_method"], row["sets"])
            render_rows()

        def rest_changed(e, set_row):
            set_row["rest_seconds"] = storage.parse_duration(
                e.control.value,
                default=set_row.get("rest_seconds", default_rest),
            )
            refresh_summaries(update_page=True)

        def edit_planned_context(row, set_row):
            if self.active_workout and self.active_workout.get("workout_id") == workout_id:
                return
            snapshot_row_controls()
            defaults = storage.read_exercise_details(row.get("exercise_name", ""))
            previous = set_context.resolve(set_row, defaults)
            inherit = ft.Checkbox(label="Inherit exercise defaults", value=set_row.get("context_override") != "1")
            setup = self.text_field(label="Setup / variation", value=previous["setup"],
                                    hint_text="e.g. cable station 2, high handle, upright position")
            selectors = {key: ft.Dropdown(label=label, value=previous[key],
                options=[ft.DropdownOption(key=value, text=text) for value, text in set_context.OPTIONS[key].items()])
                for key, label in set_context.LABELS.items()}

            def toggle_inheritance(e=None):
                setup.disabled = bool(inherit.value)
                for control in selectors.values():
                    control.disabled = bool(inherit.value)
                if inherit.value:
                    current = storage.read_exercise_details(row.get("exercise_name", ""))
                    setup.value = current.get("setup", "")
                    for key, control in selectors.items():
                        control.value = current.get(key, "")
                self.page.update()

            def close(e=None):
                self.unregister_text_fields(setup)
                self.close_dialog(dialog)

            def save(e):
                if self.active_workout and self.active_workout.get("workout_id") == workout_id:
                    self.notify("Finish or discard this active workout before changing planned segment context.")
                    return
                plan = set_context.template_metadata({
                    "context_override": "" if inherit.value else "1", "setup": setup.value or "",
                    **{key: control.value or "" for key, control in selectors.items()},
                })
                effective = set_context.resolve(plan, storage.read_exercise_details(row.get("exercise_name", "")))
                if not set_context.matches(previous, effective):
                    set_row.update(weight="", reps="")
                    # The rebuild snapshots controls, so keep their values in sync.
                    set_row["_weight_field"].value = ""
                    set_row["_reps_field"].value = ""
                set_row.update(plan)
                close()
                render_rows()

            inherit.on_change = toggle_inheritance
            setup.disabled = bool(inherit.value)
            for control in selectors.values():
                control.disabled = bool(inherit.value)
            dialog = ft.AlertDialog(
                modal=True, title=ft.Text("Planned segment context"),
                content=ft.Column(controls=[inherit, setup, *selectors.values(),
                    ft.Text("An override keeps this segment's context when exercise defaults change. Blank override fields mean unknown. Changing effective context clears this row's load/rep presets; enter them again for the new variation. Mechanical-drop progression remains manual.", size=12 * self.font_scale()),
                ], tight=True, scroll=ft.ScrollMode.AUTO),
                actions=[self.outlined_button("Cancel", on_click=close, height=self.touch_size()),
                         self.filled_button("Save segment context", on_click=save, height=self.touch_size())],
                on_dismiss=lambda e: self.unregister_text_fields(setup),
            )
            self.page.show_dialog(dialog)

        def render_rows():
            snapshot_row_controls()
            exercise_fields.controls.clear()

            self.unregister_text_fields(*getattr(self, "workout_editor_numeric_fields", []))
            self.workout_editor_numeric_fields = []

            # Fields retain readable dimensions; rows wrap instead of shrinking.
            def es(value):
                return float(value)

            def efs(value):
                return float(value) * self.font_scale()

            field_scale = max(1.0, self.font_scale())
            field_gap = es(5)
            weight_width = 94 * field_scale
            reps_width = 82 * field_scale
            rest_width = 80 * field_scale
            type_width = 94 * field_scale
            field_height = 56 * field_scale

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
                return ft.IconButton(
                    width=self.touch_size(), height=self.touch_size(),
                    icon=icon, icon_size=22, icon_color=color,
                    bgcolor=bgcolor, disabled=not enabled,
                    tooltip=tooltip, on_click=on_click, on_focus=action_focused,
                    style=ft.ButtonStyle(
                        side=ft.BorderSide(1, border_color or self.field_border_color()),
                        shape=ft.RoundedRectangleBorder(radius=self.rounding()),
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
                grouped = row.get("training_method") in storage.ACTIVATION_FOLLOWUP or row.get("training_method") == "Cluster"
                group_number = 0

                for set_index, set_row in enumerate(row["sets"]):
                    working = not storage.is_warmup_set_type(set_row.get("set_type"))
                    if grouped and working:
                        can_split = group_number > 0
                        if group_number == 0 or set_row.get("protocol_group_start") == "1":
                            group_number += 1
                            set_controls.append(ft.Text(f"Protocol group {group_number}", weight=ft.FontWeight.BOLD, size=efs(12)))
                        if can_split:
                            joining = set_row.get("protocol_group_start") == "1"
                            set_controls.append(ft.OutlinedButton(
                                content="Join preceding group" if joining else "Start group here",
                                height=max(48, 48 * field_scale), style=self.button_style(),
                                tooltip=f"{row['exercise_name']}, set {set_index + 1}: {'join preceding group' if joining else 'start protocol group'}",
                                disabled=groups_locked, on_focus=action_focused,
                                on_click=lambda e, target=row, item=set_row: toggle_group_start(target, item),
                            ))
                    weight = editor_numeric_field(
                        label=load_modes.suffix(storage.read_exercise_details(row.get("exercise_name", ""))["load_mode"], self.settings.get("unit", "kg")),
                        value=set_row.get("weight", ""),
                        width=weight_width,
                        kind=load_modes.numeric_kind(storage.read_exercise_details(row.get("exercise_name", ""))["load_mode"]),
                    )
                    # Reserve space for the unit inside the weight field.
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
                        color=self.foreground_color(),
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
                            self.focused_text_field = field
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

                    self.workout_editor_numeric_fields.extend([weight, reps, rest])

                    set_row["_weight_field"] = weight
                    set_row["_reps_field"] = reps
                    set_row["_rest_field"] = rest

                    type_button = ft.OutlinedButton(
                        width=type_width, height=field_height,
                        style=self.button_style(), on_focus=action_focused,
                        tooltip=f"{row['exercise_name'] or 'Exercise'}, set {set_index + 1}: change set role",
                        on_click=lambda e, target=row, target_set=set_row, index=set_index: choose_set_type(target, target_set, index),
                        content=ft.Text(
                            storage.display_set_type(set_row.get("set_type", "Normal")),
                            size=efs(11), max_lines=1,
                            overflow=ft.TextOverflow.ELLIPSIS,
                            text_align=ft.TextAlign.CENTER,
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
                            spacing=field_gap, run_spacing=field_gap, wrap=True,
                            vertical_alignment=ft.CrossAxisAlignment.CENTER,
                        )
                    )

                    effective = set_context.resolve(set_row, storage.read_exercise_details(row.get("exercise_name", "")))
                    context_label = ("Override" if set_row.get("context_override") == "1" else "Inherits defaults")
                    context_label += " · " + (set_context.summary(effective) or "Context unknown")
                    if groups_locked:
                        context_label += " · Planned context is fixed while this workout is active."
                    set_controls.append(ft.Row(controls=[
                        ft.OutlinedButton(content="Plan context", height=max(48, 48 * field_scale),
                            style=self.button_style(), disabled=groups_locked, on_focus=action_focused,
                            tooltip=f"{row['exercise_name'] or 'Exercise'}, set {set_index + 1}: edit planned context",
                            on_click=lambda e, target=row, item=set_row: edit_planned_context(target, item)),
                        ft.Text(context_label, size=efs(11), expand=True),
                    ], spacing=es(7), vertical_alignment=ft.CrossAxisAlignment.CENTER))

                exercise_name = row["exercise_name"] or "Choose exercise"
                is_placeholder = not bool((row.get("exercise_name") or "").strip())
                name_button = ft.OutlinedButton(
                    height=max(48, 48 * self.font_scale()), expand=True,
                    style=self.button_style(), on_focus=action_focused,
                    on_click=lambda e, target=row: choose_exercise(target),
                    tooltip=f"Choose / change exercise: {exercise_name}",
                    content=ft.Row(
                        controls=[
                            ft.Text(
                                exercise_name,
                                size=efs(14),
                                weight=ft.FontWeight.BOLD,
                                color=(
                                    self.contrast_text_color("accent")
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

                exercise_note_raw = ""
                if not is_placeholder:
                    exercise_note_raw = str(
                        storage.read_exercise_details(exercise_name).get("note", "") or ""
                    ).strip()
                exercise_note_short = (
                    exercise_note_raw
                    if len(exercise_note_raw) <= 20
                    else exercise_note_raw[:20].rstrip() + "…"
                )
                exercise_note = (
                    ft.Text(
                        exercise_note_short,
                        size=efs(10.5),
                        color=self.foreground_color(),
                        weight=ft.FontWeight.W_600,
                        max_lines=1,
                        no_wrap=True,
                        overflow=ft.TextOverflow.ELLIPSIS,
                    )
                    if exercise_note_raw
                    else None
                )

                # Keep the full exercise name area separate from its actions.
                header_row = ft.Row(
                    controls=[
                        editor_action(
                            ft.Icons.EDIT_OUTLINED,
                            on_click=lambda e, target=row: open_exercise_details_from_editor(target),
                            tooltip=f"Edit exercise details: {exercise_name}",
                            enabled=not is_placeholder,
                        ),
                        editor_action(
                            ft.Icons.ARROW_UPWARD,
                            on_click=lambda e, rid=row_id: move_by(rid, -1),
                            tooltip=f"Move exercise up: {exercise_name}",
                            enabled=row_index > 0,
                        ),
                        editor_action(
                            ft.Icons.ARROW_DOWNWARD,
                            on_click=lambda e, rid=row_id: move_by(rid, 1),
                            tooltip=f"Move exercise down: {exercise_name}",
                            enabled=row_index < len(exercise_edit_rows) - 1,
                        ),
                        editor_action(
                            ft.Icons.DELETE_OUTLINE,
                            on_click=lambda e, rid=row_id: remove_row(rid),
                            tooltip=f"Remove exercise: {exercise_name}",
                            color=ft.Colors.WHITE,
                            bgcolor=ft.Colors.RED_700,
                            border_color=ft.Colors.RED_700,
                        ),
                    ],
                    spacing=es(5), wrap=True,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                )

                header_controls = [ft.Row(controls=[name_button]), header_row]
                if exercise_note is not None:
                    header_controls.append(
                        ft.Container(
                            padding=ft.Padding(
                                left=es(7),
                                top=es(2),
                                right=es(7),
                                bottom=es(2),
                            ),
                            border=ft.Border.all(1.5, ft.Colors.GREEN_600),
                            border_radius=self.rounding(),
                            bgcolor=ft.Colors.with_opacity(0.07, ft.Colors.GREEN_700),
                            tooltip=exercise_note_raw,
                            content=exercise_note,
                        )
                    )
                header_block = ft.Column(
                    controls=header_controls,
                    spacing=es(1),
                    tight=True,
                )

                method_value = storage.canonical_training_method(
                    row.get("training_method", "Straight")
                )
                method_button = ft.OutlinedButton(
                    width=float("inf"), height=max(48, 48 * self.font_scale()),
                    style=self.button_style(), on_focus=action_focused,
                    tooltip=f"Choose training method for {exercise_name}",
                    on_click=lambda e, target=row: choose_training_method(target),
                    content=ft.Row(
                        controls=[
                            ft.Text("Method", size=efs(10), color=self.foreground_color()),
                            ft.Text(
                                method_value,
                                size=efs(11.5),
                                weight=ft.FontWeight.BOLD,
                                expand=True,
                                max_lines=1,
                                overflow=ft.TextOverflow.ELLIPSIS,
                            ),
                            ft.Icon(ft.Icons.ARROW_DROP_DOWN, size=es(18)),
                        ],
                        spacing=es(6),
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                )

                set_rows_block = ft.Container(
                    # Put the breathing room before set 1, not between every set.
                    padding=ft.Padding(left=0, top=es(9), right=0, bottom=0),
                    content=ft.Column(controls=set_controls, spacing=0),
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
                            header_block,
                            method_button,
                            *([ft.Text(
                                "Rest is after each segment. The final segment's rest is the break before the next group. Multi-group progression is manual."
                                + (" Group boundaries are fixed until this workout is finished or discarded." if groups_locked else ""),
                                size=efs(11), color=self.contrast_text_color(),
                            )] if grouped else []),
                            set_rows_block,
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
                                    *([ft.OutlinedButton(
                                        content="Add protocol group", height=max(48, 48 * field_scale),
                                        style=self.button_style(), disabled=groups_locked,
                                        tooltip=f"Add protocol group: {row['exercise_name']}", on_focus=action_focused,
                                        on_click=lambda e, target=row: add_protocol_group(target),
                                    )] if grouped else []),
                                ],
                                spacing=es(7), run_spacing=es(7), wrap=True,
                            ),
                        ],
                        spacing=es(5),
                    ),
                )
                exercise_fields.controls.append(card)

            self.chain_text_fields(*self.workout_editor_numeric_fields)
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
                        kind=load_modes.numeric_kind(storage.read_exercise_details(row.get("exercise_name", ""))["load_mode"]),
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
                row["sets"] = storage.reconcile_method_sets(
                    row.get("training_method", "Straight"), row.get("sets", [])
                )
                method_valid, method_error = storage.validate_method_sets(
                    row.get("training_method", "Straight"), row.get("sets", [])
                )
                if not method_valid:
                    self.notify(f"{row['exercise_name']}: {method_error}")
                    return
                output_sets = []
                for set_row in row["sets"]:
                    output_sets.append(
                        {
                            "weight": set_row.get("weight", ""),
                            "reps": set_row.get("reps", ""),
                            "rest_seconds": set_row.get("rest_seconds", default_rest),
                            "set_type": set_row.get("set_type", "Normal"),
                            "protocol_group_start": set_row.get("protocol_group_start", ""),
                            **set_context.template_metadata(set_row),
                        }
                    )
                output_exercises.append(
                    {
                        "exercise_name": row["exercise_name"],
                        "training_method": row.get("training_method", "Straight"),
                        "sets": output_sets,
                    }
                )

            if (self.active_workout and self.active_workout.get("workout_id") == workout_id
                    and context_signature(output_exercises) != original_contexts):
                self.notify("Finish or discard this active workout before changing planned segment context.")
                return

            if groups_locked and group_signature(output_exercises) != original_groups:
                self.notify("Finish or discard this active workout before changing protocol groups or their method.")
                return

            if return_to_active and self.active_workout and self.active_workout.get("workout_id") == workout_id:
                output_keys = {
                    (str(exercise.get("exercise_name", "") or "").casefold(), set_number)
                    for exercise in output_exercises
                    for set_number, _ in enumerate(exercise.get("sets", []), start=1)
                }
                removed_completed = [
                    row
                    for row in self.active_workout.get("rows", [])
                    if row.get("completed", False)
                    and (
                        str(row.get("exercise_name", "") or "").casefold(),
                        int(row.get("set_number", 0) or 0),
                    )
                    not in output_keys
                ]
                if removed_completed:
                    first = removed_completed[0]
                    self.notify(
                        f"{first.get('exercise_name', 'Exercise')}: completed sets cannot be removed or replaced while the workout is active."
                    )
                    return

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

                if (
                    return_to_active
                    and self.active_workout
                    and self.active_workout.get("workout_id") == workout_id
                ):
                    old_rows = {
                        (
                            str(row.get("exercise_name", "") or "").casefold(),
                            int(row.get("set_number", 0) or 0),
                        ): dict(row)
                        for row in self.active_workout.get("rows", [])
                    }
                    seed_cache = {}
                    rebuilt_rows = []

                    for exercise in output_exercises:
                        exercise_name = str(exercise.get("exercise_name", "") or "").strip()
                        if not exercise_name:
                            continue
                        training_method = storage.canonical_training_method(
                            exercise.get("training_method", "Straight")
                        )

                        key_name = exercise_name.casefold()
                        if key_name not in seed_cache:
                            seed_cache[key_name] = self.active_rows_for_added_exercise(
                                exercise_name
                            )
                        seeds = seed_cache[key_name]

                        for set_number, set_row in enumerate(
                            exercise.get("sets", []), start=1
                        ):
                            key = (key_name, set_number)
                            existing = old_rows.get(key)
                            if existing is not None:
                                active_row = dict(existing)
                                previous_method = storage.canonical_training_method(
                                    active_row.get("training_method", "Straight")
                                )
                                active_row["exercise_name"] = exercise_name
                                active_row["set_number"] = set_number
                                active_row["rest_seconds"] = storage.parse_duration(
                                    set_row.get("rest_seconds", default_rest),
                                    default=default_rest,
                                )
                                active_row["set_type"] = (
                                    set_row.get("set_type", "Normal") or "Normal"
                                )
                                active_row["training_method"] = training_method
                                if previous_method != training_method:
                                    active_row["calibration_done"] = False
                                if not storage.method_set_uses_rir(
                                    training_method, active_row["set_type"]
                                ):
                                    active_row["rir"] = ""
                                    active_row["previous_rir"] = ""

                                template_weight = str(set_row.get("weight", "") or "")
                                template_reps = str(set_row.get("reps", "") or "")
                                if not str(active_row.get("weight", "") or "").strip() and template_weight:
                                    active_row["previous_weight"] = template_weight
                                if not str(active_row.get("reps", "") or "").strip() and template_reps:
                                    active_row["previous_reps"] = template_reps
                            else:
                                if set_number <= len(seeds):
                                    active_row = dict(seeds[set_number - 1])
                                else:
                                    active_row = {
                                        "exercise_name": exercise_name,
                                        "set_number": set_number,
                                        "weight": "",
                                        "reps": "",
                                        "rir": "",
                                        "previous_weight": str(set_row.get("weight", "") or ""),
                                        "previous_reps": str(set_row.get("reps", "") or ""),
                                        "previous_rir": "",
                                        "last_week_reps": "",
                                        "set_type": "Normal",
                                        "training_method": training_method,
                                        "note": "",
                                        "completed": False,
                                        "calibration_done": False,
                                        "rest_seconds": default_rest,
                                    }
                                active_row["exercise_name"] = exercise_name
                                active_row["set_number"] = set_number
                                active_row["rest_seconds"] = storage.parse_duration(
                                    set_row.get("rest_seconds", default_rest),
                                    default=default_rest,
                                )
                                active_row["set_type"] = (
                                    set_row.get("set_type", "Normal") or "Normal"
                                )
                                active_row["training_method"] = training_method

                            for context_key, value in set_context.resolve(set_row, storage.read_exercise_details(exercise_name)).items():
                                active_row.setdefault(context_key, value)
                            active_row.setdefault("context_override", set_row.get("context_override", ""))
                            active_row.setdefault("load_mode", storage.read_exercise_details(exercise_name)["load_mode"])
                            active_row.setdefault("protocol_group_start", set_row.get("protocol_group_start", ""))
                            active_row.setdefault("target_rir", self.cycle_rir_target() or "")
                            rebuilt_rows.append(active_row)

                    self.active_workout["workout_name"] = name_field.value or workout.get("name", "Workout")
                    self.active_workout["rows"] = rebuilt_rows
                    storage.save_active_workout(self.active_workout)
                    self.set_controls = []
                    self.show_active_workout()
                else:
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

        def cancel_edit(e=None):
            # Leave immediately without applying any editor changes. A newly
            # created placeholder workout should not survive a deliberate Cancel.
            self.workout_editor_draft = None
            if is_new:
                storage.delete_workout(workout_id)
            if return_to_active and self.active_workout:
                self.show_active_workout()
            else:
                self.show_saved_workouts()

        def delete(e):
            self.workout_editor_draft = None
            if self.active_workout and self.active_workout["workout_id"] == workout_id:
                self.notify("Finish or discard the active workout before deleting it.")
                return
            storage.delete_workout(workout_id)
            self.show_saved_workouts()

        footer_controls = [
            self.outlined_button("Cancel", on_click=cancel_edit, expand=True),
            self.filled_button("Save", on_click=save, expand=True),
        ]
        if not is_new and not return_to_active:
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
                                "Each programmed row contributes to timing, including warmups and protocol fragments. "
                                "Tune Entry duration to your routine. "
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
                hide_active_return_bar=return_to_active,
            )

        time_link = ft.OutlinedButton(
            width=140 * max(1.0, self.font_scale()),
            height=max(48, 48 * self.font_scale()),
            style=self.button_style(), on_focus=action_focused,
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
                    color=self.contrast_text_color("warning"),
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
                    ft.Column(
                        controls=[name_field, workout_description,
                                  ft.Row(controls=[time_link], alignment=ft.MainAxisAlignment.END)],
                        spacing=self.ui(6),
                        horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
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
                back_action=cancel_edit,
                hide_active_return_bar=return_to_active,
            )

        render_rows()
        show_editor_view()
