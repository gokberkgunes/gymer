import flet as ft

import storage


class RepsApp:
    def __init__(self, page: ft.Page):
        self.page = page
        self.page.title = "GYMER"
        self.page.scroll = None
        self.page.theme_mode = ft.ThemeMode.DARK
        self.page.window_width = 430
        self.page.window_height = 760

        self.active_workout = storage.load_active_workout()
        self.set_controls = []
        self.selected_tab = 0

        self.page.navigation_bar = ft.NavigationBar(
            selected_index=0,
            indicator_shape=ft.RoundedRectangleBorder(radius=0),
            destinations=[
                ft.NavigationBarDestination(
                    icon=ft.Icons.FITNESS_CENTER_OUTLINED,
                    selected_icon=ft.Icons.FITNESS_CENTER,
                    label="Workout",
                ),
                ft.NavigationBarDestination(
                    icon=ft.Icons.EDIT_OUTLINED,
                    selected_icon=ft.Icons.EDIT,
                    label="Manage",
                ),
                ft.NavigationBarDestination(
                    icon=ft.Icons.SETTINGS_OUTLINED,
                    selected_icon=ft.Icons.SETTINGS,
                    label="Settings",
                ),
            ],
            on_change=self.change_tab,
        )

        self.show_workout_tab()

    # ------------------------------------------------------------------
    # STYLE HELPERS
    # ------------------------------------------------------------------

    def square_style(self):
        return ft.ButtonStyle(
            shape=ft.RoundedRectangleBorder(radius=0),
        )

    def filled_button(self, text, on_click=None, expand=False, **kwargs):
        return ft.FilledButton(
            content=text,
            on_click=on_click,
            expand=expand,
            style=self.square_style(),
            **kwargs,
        )

    def outlined_button(self, text, on_click=None, expand=False, **kwargs):
        return ft.OutlinedButton(
            content=text,
            on_click=on_click,
            expand=expand,
            style=self.square_style(),
            **kwargs,
        )

    def text_field(self, **kwargs):
        kwargs.setdefault("border_radius", 0)
        return ft.TextField(**kwargs)

    # ------------------------------------------------------------------
    # PAGE / NAVIGATION
    # ------------------------------------------------------------------

    def set_view(self, controls, footer=None):
        self.page.controls.clear()

        content = ft.Container(
            content=ft.Column(
                controls=controls,
                spacing=14,
                expand=True,
                scroll=ft.ScrollMode.AUTO,
            ),
            padding=ft.Padding(left=20, top=20, right=20, bottom=20),
            expand=True,
        )

        page_controls = [content]

        if footer is not None:
            page_controls.append(
                ft.Container(
                    content=footer,
                    padding=ft.Padding(left=20, top=10, right=20, bottom=14),
                )
            )

        self.page.add(
            ft.Column(
                controls=page_controls,
                spacing=0,
                expand=True,
            )
        )

        self.page.update()

    def change_tab(self, e):
        # Save entered values before leaving an active workout screen.
        if self.active_workout and self.set_controls:
            self.capture_active_controls()

        self.selected_tab = e.control.selected_index

        if self.selected_tab == 0:
            self.show_workout_tab()
        elif self.selected_tab == 1:
            self.show_manage()
        else:
            self.show_settings()

    def go_to_tab(self, index):
        self.selected_tab = index
        self.page.navigation_bar.selected_index = index

        if index == 0:
            self.show_workout_tab()
        elif index == 1:
            self.show_manage()
        else:
            self.show_settings()

    def notify(self, message):
        self.page.show_dialog(
            ft.SnackBar(
                content=ft.Text(message),
            )
        )

    # ------------------------------------------------------------------
    # WORKOUT TAB
    # ------------------------------------------------------------------

    def show_workout_tab(self):
        self.page.navigation_bar.selected_index = 0

        if self.active_workout:
            self.show_active_workout()
        else:
            self.show_saved_workouts()

    def show_saved_workouts(self):
        controls = [
            ft.Text("Workout", size=30, weight=ft.FontWeight.BOLD),
            ft.Text("Choose a workout to start."),
        ]

        workouts = storage.read_workouts()

        if not workouts:
            controls.append(ft.Text("No workouts yet. Create one from Manage."))

        for workout in workouts:
            workout_id = workout["workout_id"]

            controls.append(
                ft.Container(
                    padding=ft.Padding(left=0, top=8, right=0, bottom=8),
                    content=ft.Row(
                        controls=[
                            ft.Text(
                                workout["name"],
                                size=24,
                                weight=ft.FontWeight.BOLD,
                                expand=True,
                            ),
                            self.filled_button(
                                "Start",
                                on_click=lambda e, wid=workout_id: self.start_workout(wid),
                            ),
                        ],
                    ),
                )
            )

        recent = storage.recent_sessions(limit=5)

        if recent:
            controls.extend(
                [
                    ft.Divider(),
                    ft.Text("Recent", size=18, weight=ft.FontWeight.BOLD),
                ]
            )

            for session in recent:
                date = session["date"].replace("T", " ")[:16]
                controls.append(
                    ft.Row(
                        controls=[
                            ft.Text(session["workout_name"], expand=True),
                            ft.Text(f'{session["set_count"]} sets'),
                            ft.Text(date, size=11),
                        ],
                    )
                )

        self.set_view(controls)

    def start_workout(self, workout_id):
        workout = storage.read_workout(workout_id)

        if workout is None:
            self.notify("Workout not found.")
            return

        self.active_workout = storage.build_active_workout(workout)
        storage.save_active_workout(self.active_workout)
        self.show_active_workout()

    def show_active_workout(self):
        if not self.active_workout:
            self.show_saved_workouts()
            return

        self.set_controls = []

        controls = [
            ft.Row(
                controls=[
                    ft.Text(
                        self.active_workout["workout_name"],
                        size=28,
                        weight=ft.FontWeight.BOLD,
                        expand=True,
                    ),
                    ft.Text("ACTIVE", weight=ft.FontWeight.BOLD),
                ]
            )
        ]

        grouped = {}
        for row in self.active_workout["rows"]:
            grouped.setdefault(row["exercise_name"], []).append(row)

        for exercise_name, rows in grouped.items():
            controls.extend(self.active_exercise_block(exercise_name, rows))

        footer = ft.Row(
            controls=[
                self.filled_button(
                    "Save Workout",
                    on_click=self.finish_workout,
                    expand=True,
                ),
                self.outlined_button(
                    "Discard",
                    on_click=self.discard_workout,
                ),
            ],
            spacing=10,
        )

        self.set_view(controls, footer=footer)

    def active_exercise_block(self, exercise_name, initial_rows):
        rows_column = ft.Column(spacing=8)
        exercise_items = []

        def make_row(row_data):
            set_number = len(exercise_items) + 1

            weight = self.text_field(
                label="Weight",
                value=row_data.get("weight", ""),
                width=92,
                dense=True,
            )

            reps = self.text_field(
                label="Reps",
                value=row_data.get("reps", ""),
                width=68,
                dense=True,
            )

            rir = self.text_field(
                label="RIR",
                value=row_data.get("rir", ""),
                width=62,
                dense=True,
            )

            note = self.text_field(
                label="Note",
                value=row_data.get("note", ""),
                expand=True,
                dense=True,
            )

            item = {
                "exercise_name": exercise_name,
                "set_number": set_number,
                "weight": weight,
                "reps": reps,
                "rir": rir,
                "note": note,
            }

            exercise_items.append(item)
            self.set_controls.append(item)

            # Save draft whenever the user changes a field.
            for field in (weight, reps, rir, note):
                field.on_change = lambda e: self.capture_active_controls()

            rows_column.controls.append(
                ft.Row(
                    controls=[
                        ft.Text(str(set_number), width=16),
                        weight,
                        reps,
                        rir,
                        note,
                    ],
                    spacing=6,
                )
            )

        def add_set(e):
            make_row({})
            self.capture_active_controls()
            self.page.update()

        def remove_set(e):
            if len(exercise_items) <= 1:
                return

            item = exercise_items.pop()
            self.set_controls.remove(item)
            rows_column.controls.pop()

            self.renumber_controls()
            self.capture_active_controls()
            self.page.update()

        for row in initial_rows:
            make_row(row)

        return [
            ft.Text(exercise_name, size=19, weight=ft.FontWeight.BOLD),
            rows_column,
            ft.Row(
                controls=[
                    self.outlined_button("+ Set", on_click=add_set),
                    self.outlined_button("- Set", on_click=remove_set),
                ],
                spacing=8,
            ),
            ft.Divider(height=10),
        ]

    def renumber_controls(self):
        counts = {}

        for item in self.set_controls:
            exercise_name = item["exercise_name"]
            counts[exercise_name] = counts.get(exercise_name, 0) + 1
            item["set_number"] = counts[exercise_name]

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
                    "weight": item["weight"].value or "",
                    "reps": item["reps"].value or "",
                    "rir": item["rir"].value or "",
                    "note": item["note"].value or "",
                }
            )

        self.active_workout["rows"] = rows
        storage.save_active_workout(self.active_workout)

    def finish_workout(self, e):
        self.capture_active_controls()

        workout = {
            "workout_id": self.active_workout["workout_id"],
            "name": self.active_workout["workout_name"],
        }

        count = storage.append_session(
            workout,
            self.active_workout["rows"],
        )

        if count == 0:
            self.notify("Nothing was saved. Enter at least one set.")
            return

        storage.clear_active_workout()
        self.active_workout = None
        self.set_controls = []

        self.notify(f"Saved {count} set(s).")
        self.show_saved_workouts()

    def discard_workout(self, e):
        storage.clear_active_workout()
        self.active_workout = None
        self.set_controls = []
        self.show_saved_workouts()

    # ------------------------------------------------------------------
    # MANAGE TAB
    # ------------------------------------------------------------------

    def show_manage(self):
        self.page.navigation_bar.selected_index = 1

        controls = [
            ft.Text("Manage", size=30, weight=ft.FontWeight.BOLD),
            ft.Text("Create or edit workout templates."),
            self.filled_button(
                "New Workout",
                on_click=self.create_workout,
            ),
            ft.Divider(),
        ]

        for workout in storage.read_workouts():
            workout_id = workout["workout_id"]

            controls.append(
                ft.Row(
                    controls=[
                        ft.Text(
                            workout["name"],
                            size=22,
                            weight=ft.FontWeight.BOLD,
                            expand=True,
                        ),
                        self.outlined_button(
                            "Edit",
                            on_click=lambda e, wid=workout_id: self.show_edit(wid),
                        ),
                    ]
                )
            )

        self.set_view(controls)

    def create_workout(self, e):
        workout_id = storage.create_workout("New Workout")
        self.show_edit(workout_id, is_new=True)

    def show_edit(self, workout_id, is_new=False):
        workout = storage.read_workout(workout_id)

        if workout is None:
            self.show_manage()
            return

        settings = storage.read_settings()

        name_field = self.text_field(
            label="Workout name",
            value=workout["name"],
        )

        exercise_fields = ft.Column(spacing=12)
        exercise_edit_rows = []

        def remove_exercise(row_data, container):
            if row_data in exercise_edit_rows:
                exercise_edit_rows.remove(row_data)

            if container in exercise_fields.controls:
                exercise_fields.controls.remove(container)

            self.page.update()

        def add_exercise_field(exercise=None):
            exercise = exercise or {
                "exercise_name": "",
                "target_sets": settings.get("default_sets", "3"),
                "default_weight": "",
                "default_reps": "",
            }

            name = self.text_field(
                label="Exercise",
                value=exercise.get("exercise_name", ""),
                expand=True,
                dense=True,
            )

            sets = self.text_field(
                label="Sets",
                value=exercise.get("target_sets", settings.get("default_sets", "3")),
                width=65,
                dense=True,
            )

            weight = self.text_field(
                label="Start weight",
                value=exercise.get("default_weight", ""),
                width=105,
                dense=True,
            )

            reps = self.text_field(
                label="Start reps",
                value=exercise.get("default_reps", ""),
                width=90,
                dense=True,
            )

            row_data = {
                "name": name,
                "sets": sets,
                "weight": weight,
                "reps": reps,
            }

            container = ft.Container(
                content=ft.Column(
                    controls=[
                        ft.Row(
                            controls=[
                                name,
                                self.outlined_button(
                                    "×",
                                    on_click=lambda e: remove_exercise(row_data, container),
                                ),
                            ]
                        ),
                        ft.Row(
                            controls=[
                                sets,
                                weight,
                                reps,
                            ],
                            spacing=8,
                        ),
                    ],
                    spacing=6,
                )
            )

            exercise_edit_rows.append(row_data)
            exercise_fields.controls.append(container)
            self.page.update()

        for exercise in workout["exercises"]:
            add_exercise_field(exercise)

        def save(e):
            storage.save_workout(
                workout_id=workout_id,
                name=name_field.value,
                exercises=[
                    {
                        "exercise_name": row["name"].value or "",
                        "target_sets": row["sets"].value or "",
                        "default_weight": row["weight"].value or "",
                        "default_reps": row["reps"].value or "",
                    }
                    for row in exercise_edit_rows
                ],
            )

            self.show_manage()

        def delete(e):
            if (
                self.active_workout
                and self.active_workout["workout_id"] == workout_id
            ):
                self.notify("Finish or discard the active workout before deleting it.")
                return

            storage.delete_workout(workout_id)
            self.show_manage()

        controls = [
            ft.Text(
                "New Workout" if is_new else "Edit Workout",
                size=28,
                weight=ft.FontWeight.BOLD,
            ),
            name_field,
            ft.Text("Exercises", size=18, weight=ft.FontWeight.BOLD),
            exercise_fields,
            self.outlined_button(
                "+ Exercise",
                on_click=lambda e: add_exercise_field(),
            ),
        ]

        footer_controls = [
            self.filled_button(
                "Save",
                on_click=save,
                expand=True,
            ),
        ]

        if not is_new:
            footer_controls.append(
                ft.FilledButton(
                    content="Delete",
                    on_click=delete,
                    color=ft.Colors.WHITE,
                    bgcolor=ft.Colors.RED_700,
                    style=self.square_style(),
                )
            )

        footer = ft.Row(
            controls=footer_controls,
            spacing=10,
        )

        self.set_view(controls, footer=footer)

    # ------------------------------------------------------------------
    # SETTINGS TAB
    # ------------------------------------------------------------------

    def show_settings(self):
        self.page.navigation_bar.selected_index = 2

        settings = storage.read_settings()
        unit = settings.get("unit", "kg")

        default_sets = self.text_field(
            label="Default sets for new exercises",
            value=settings.get("default_sets", "3"),
            width=170,
            dense=True,
        )

        def set_unit(new_unit):
            settings["unit"] = new_unit
            storage.save_settings(settings)
            self.show_settings()

        def save(e):
            value = (default_sets.value or "").strip()

            if not value.isdigit() or int(value) < 1:
                self.notify("Default sets must be a positive whole number.")
                return

            settings["default_sets"] = value
            storage.save_settings(settings)
            self.notify("Settings saved.")
            self.show_settings()

        unit_row = ft.Row(
            controls=[
                (
                    self.filled_button("kg", on_click=lambda e: set_unit("kg"))
                    if unit == "kg"
                    else self.outlined_button("kg", on_click=lambda e: set_unit("kg"))
                ),
                (
                    self.filled_button("lb", on_click=lambda e: set_unit("lb"))
                    if unit == "lb"
                    else self.outlined_button("lb", on_click=lambda e: set_unit("lb"))
                ),
            ],
            spacing=8,
        )

        controls = [
            ft.Text("Settings", size=30, weight=ft.FontWeight.BOLD),
            ft.Text("Units", size=18, weight=ft.FontWeight.BOLD),
            unit_row,
            ft.Divider(),
            ft.Text("Workout defaults", size=18, weight=ft.FontWeight.BOLD),
            default_sets,
            self.filled_button("Save Settings", on_click=save),
            ft.Divider(),
            ft.Text("Data", size=18, weight=ft.FontWeight.BOLD),
            ft.Text(str(storage.data_path()), size=12),
            ft.Text("Workout history is kept when a workout template is deleted.", size=12),
        ]

        self.set_view(controls)


def main(page: ft.Page):
    RepsApp(page)


if __name__ == "__main__":
    ft.run(main)
