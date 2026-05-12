import flet as ft

import storage


class RepsApp:
    def __init__(self, page: ft.Page):
        self.page = page
        self.page.title = "GYMER"
        self.page.scroll = ft.ScrollMode.AUTO
        self.page.theme_mode = ft.ThemeMode.DARK
        self.page.window_width = 430
        self.page.window_height = 760

        self.current_workout = None
        self.set_controls = []

        storage.ensure_data()
        self.show_home()

    def set_view(self, controls):
        self.page.controls.clear()
        self.page.add(
            ft.Container(
                content=ft.Column(controls=controls, spacing=14, expand=True),
                padding=ft.Padding(left=20, top=20, right=20, bottom=20),
                expand=True,
            )
        )
        self.page.update()

    def show_home(self):
        rows = []
        for workout in storage.read_workouts():
            rows.append(self.workout_row(workout))

        self.set_view(
            [
                *rows,
                ft.Divider(),
                ft.FilledButton("Add Workout", on_click=lambda e: self.add_workout()),
            ]
        )

    def workout_row(self, workout):
        workout_id = workout["workout_id"]
        name = workout["name"]

        return ft.Container(
            content=ft.Row(
                controls=[
                    ft.Text(name, size=30, weight=ft.FontWeight.BOLD, expand=True),
                    ft.FilledButton("Start", on_click=lambda e: self.show_workout(workout_id)),
                    ft.OutlinedButton("Edit", on_click=lambda e: self.show_edit(workout_id)),
                ],
                alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
            ),
            padding=ft.Padding(left=0, top=8, right=0, bottom=10),
        )

    def add_workout(self):
        workout_id = storage.create_workout("")
        self.show_edit(workout_id)

    def show_workout(self, workout_id):
        workout = storage.read_workout(workout_id)
        self.current_workout = workout
        self.set_controls = []

        controls = [
            ft.Row(
                controls=[
                    ft.FilledIconButton(icon=ft.Icons.ARROW_BACK, width=50, on_click=lambda e: self.show_home()),
                    ft.Divider(),
                    ft.Text(f" {workout['name']}", size=26, weight=ft.FontWeight.BOLD),
                ]
            ),
        ]

        for exercise in workout["exercises"]:
            controls.extend(self.exercise_block(exercise))

        controls.append(
            ft.Row(
                controls = [
                    ft.FilledButton("Save Workout", on_click=self.save_current_workout),
                    ft.OutlinedButton("Cancel", on_click=lambda e: self.show_home()),
                ],
                spacing = 10,
            )
        )

        self.set_view(controls)

    def exercise_block(self, exercise_name):
        rows_column = ft.Column(spacing=6)

        def add_set_row(e=None):
            set_number = len(rows_column.controls) + 1
            weight = ft.TextField(label="Weight", width=100, dense=True)
            reps = ft.TextField(label="Reps", width=72, dense=True)
            rir = ft.TextField(label="RIR", width=72, dense=True)
            note = ft.TextField(label="Note", expand=True, dense=True)

            self.set_controls.append(
                {
                    "exercise_name": exercise_name,
                    "set_number": set_number,
                    "weight": weight,
                    "reps": reps,
                    "rir": rir,
                    "note": note,
                }
            )

            rows_column.controls.append(
                ft.Row(
                    controls=[
                        ft.Text(f"{set_number}", width=10, size=18),
                        weight,
                        reps,
                        rir,
                        note,
                    ],
                    spacing=8,
                )
            )
            self.page.update()

        add_button = ft.OutlinedButton("+", on_click=add_set_row)
        add_set_row()

        return [
            ft.Text(exercise_name, size=19, weight=ft.FontWeight.BOLD),
            rows_column,
            add_button,
            ft.Divider(height=10),
        ]

    def save_current_workout(self, e):
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

        count = storage.append_session(self.current_workout, rows)
        self.page.snack_bar = ft.SnackBar(ft.Text(f"Saved {count} set(s)."))
        self.page.snack_bar.open = True
        self.show_home()

    def show_edit(self, workout_id):
        workout = storage.read_workout(workout_id)
        name_field = ft.TextField(label="Workout name", value=workout["name"])
        exercise_fields = ft.Column(spacing=8)

        def add_exercise_field(value=""):
            field = ft.TextField(label="Exercise", value=value, expand=True)
            exercise_fields.controls.append(field)
            self.page.update()

        for exercise in workout["exercises"]:
            add_exercise_field(exercise)

        def save(e):
            storage.save_workout(
                workout_id=workout_id,
                name=name_field.value,
                exercises=[field.value for field in exercise_fields.controls],
            )
            self.show_home()
        def delete(e):
            storage.delete_workout(workout_id)
            self.show_home()

        self.set_view(
            [
                ft.Row(
                    controls=[
                        ft.IconButton(icon=ft.Icons.ARROW_BACK, on_click=lambda e: self.show_home()),
                        ft.Text("Edit workout", size=26, weight=ft.FontWeight.BOLD),
                    ]
                ),
                name_field,
                ft.Text("Exercises", size=18, weight=ft.FontWeight.BOLD),
                exercise_fields,
                ft.OutlinedButton("Add exercise", on_click=lambda e: add_exercise_field()),

                ft.Row(
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    controls=[
                        ft.FilledButton("Save", on_click=save),
                        ft.FilledButton(
                            "Delete",
                            on_click=delete,
                            color=ft.Colors.WHITE,    # Text color
                            bgcolor=ft.Colors.RED_700  # Button background color
                        ),
                    ]
                )
            ]
        )


def main(page: ft.Page):
    RepsApp(page)


if __name__ == "__main__":
    ft.app(target=main)
