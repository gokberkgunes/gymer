import ast
import asyncio
import math
import time
import uuid
from datetime import datetime

import flet as ft

import storage
import volume_landmarks


class MesocycleMixin:

    def format_cycle_date(self, value):
        try:
            moment = datetime.fromisoformat(str(value)).date()
        except (TypeError, ValueError):
            return str(value or "")

        text = f"{moment.day} {moment.strftime('%B')}"
        if moment.year != datetime.now().year:
            text += f" {moment.year}"
        return text

    def cycle_period_noun(self, cycle, plural=False):
        try:
            days = max(1, int(cycle.get("microcycle_days", "7") or 7))
        except (TypeError, ValueError):
            days = 7
        if days == 7:
            return "weeks" if plural else "week"
        return "microcycles" if plural else "microcycle"

    def cycle_period_short(self, cycle):
        return "W" if self.cycle_period_noun(cycle) == "week" else "M"

    def mesocycle_status_card(self):
        cycle = storage.active_mesocycle()
        if not cycle:
            return None

        status = storage.mesocycle_status(cycle)
        phase = status["phase"]
        phase_color = (
            ft.Colors.ORANGE_500
            if phase == "Deload"
            else ft.Colors.GREEN_500
            if phase == "Build"
            else self.accent_color()
        )
        rir = status["suggested_rir"]
        rir_text = f"RIR {int(round(float(rir)))}"
        schedule = storage.mesocycle_day_schedule(cycle.get("cycle_id", ""))
        today_workout_id = schedule.get(status.get("day_in_microcycle", 1), "")
        workout_names = {
            row.get("workout_id", ""): row.get("name", "")
            for row in storage.read_workouts()
        }
        today_name = workout_names.get(today_workout_id, "")
        today_text = f"Today: {today_name}" if today_name else "Today: unplanned"
        period_name = self.cycle_period_noun(cycle).capitalize()

        return ft.Container(
            width=float("inf"),
            padding=ft.Padding(left=self.ui(11), top=self.ui(9), right=self.ui(11), bottom=self.ui(9)),
            border=ft.Border.all(1, ft.Colors.with_opacity(0.45, self.accent_color())),
            border_radius=self.rounding(),
            bgcolor=ft.Colors.with_opacity(0.065, self.accent_color()),
            ink=True,
            on_click=lambda e: self.show_mesocycle(),
            content=ft.Row(
                controls=[
                    ft.Column(
                        controls=[
                            ft.Text(
                                cycle.get("name", "Mesocycle"),
                                size=self.fs(14),
                                weight=ft.FontWeight.BOLD,
                            ),
                            ft.Text(
                                f"{period_name} {status['current_microcycle']}/{status['total_microcycles']} · {phase}",
                                size=self.fs(11),
                            ),
                            ft.Text(
                                today_text,
                                size=self.fs(10.5),
                                color=ft.Colors.GREY_500,
                            ),
                        ],
                        spacing=1,
                        expand=True,
                    ),
                    ft.Column(
                        controls=[
                            ft.Text(
                                rir_text,
                                color=phase_color,
                                weight=ft.FontWeight.BOLD,
                                text_align=ft.TextAlign.RIGHT,
                            ),
                            ft.Text(
                                f"{status['remaining_days']} days left" if not status["complete"] else "Complete",
                                size=self.fs(10),
                                text_align=ft.TextAlign.RIGHT,
                            ),
                        ],
                        spacing=1,
                    ),
                    ft.Icon(ft.Icons.CHEVRON_RIGHT, size=18),
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

    def cycle_heatmap(self, cycle, compact=False):
        days = storage.mesocycle_calendar_days(cycle)
        if not days:
            return ft.Container()

        try:
            micro_days = max(1, int(cycle.get("microcycle_days", "7") or 7))
        except (TypeError, ValueError):
            micro_days = 7

        total_microcycles = max(day["microcycle"] for day in days)

        square = max(
            12 if compact else 10,
            min(28, int(300 / max(1, micro_days))),
        )
        cell_width = square
        cell_height = square

        first_micro = [d for d in days if d["microcycle"] == 1]
        weekday_labels = []
        for day in first_micro:
            try:
                weekday = datetime.fromisoformat(day["date"]).strftime("%a")[:2]
            except (TypeError, ValueError):
                weekday = ""
            weekday_labels.append(weekday)

        rows = []
        if not compact:
            rows.append(
                ft.Text(
                    "Training",
                    size=self.fs(18),
                    weight=ft.FontWeight.BOLD,
                )
            )

        if weekday_labels:
            rows.append(
                ft.Row(
                    controls=[
                        ft.Container(width=self.ui(28)),
                        ft.Row(
                            controls=[
                                ft.Container(
                                    width=cell_width,
                                    alignment=ft.Alignment.CENTER,
                                    content=ft.Text(
                                        label,
                                        size=self.fs(9.5 if compact else 10),
                                        color=ft.Colors.GREY_500,
                                        weight=ft.FontWeight.W_600,
                                        text_align=ft.TextAlign.CENTER,
                                    ),
                                )
                                for label in weekday_labels
                            ],
                            spacing=self.ui(3),
                        ),
                    ],
                    spacing=self.ui(4),
                )
            )

        for microcycle in range(1, total_microcycles + 1):
            micro_days_data = [d for d in days if d["microcycle"] == microcycle]
            cells = []
            for day in micro_days_data:
                count = int(day.get("completed_sessions", 0) or 0)
                if count >= 2:
                    color = ft.Colors.with_opacity(0.95, self.accent_color())
                elif count == 1:
                    color = ft.Colors.with_opacity(0.58, self.accent_color())
                else:
                    color = ft.Colors.with_opacity(0.12, self.foreground_color())

                is_today = bool(day.get("is_today"))
                border_color = (
                    ft.Colors.WHITE
                    if is_today and self.is_dark_mode()
                    else (
                        ft.Colors.BLACK
                        if is_today
                        else (
                            self.accent_color()
                            if day.get("workout_id") and count == 0
                            else ft.Colors.with_opacity(0.28, self.foreground_color())
                        )
                    )
                )
                tooltip = (
                    f"Day {day['day_number']} · {self.format_cycle_date(day['date'])} · "
                    f"{day.get('workout_name') or 'Rest'} · "
                    f"{count} completed"
                )
                day_number_control = (
                    ft.Text(
                        str(day.get("day_in_microcycle", "")),
                        size=self.fs(9 if compact else 9.5),
                        weight=(
                            ft.FontWeight.BOLD
                            if is_today
                            else ft.FontWeight.W_500
                        ),
                        color=self.foreground_color(),
                        text_align=ft.TextAlign.CENTER,
                    )
                    if day.get("workout_id")
                    else ft.Container()
                )

                cell_content = day_number_control

                cells.append(
                    ft.Container(
                        width=cell_width,
                        height=cell_height,
                        alignment=ft.Alignment.CENTER,
                        bgcolor=color,
                        border=ft.Border.all(2.5 if is_today else 1, border_color),
                        border_radius=2,
                        tooltip=tooltip,
                        content=cell_content,
                    )
                )

            rows.append(
                ft.Row(
                    controls=[
                        ft.Text(
                            f"{self.cycle_period_short(cycle)}{microcycle}",
                            width=self.ui(28),
                            size=self.fs(10),
                            weight=ft.FontWeight.BOLD,
                        ),
                        ft.Row(
                            controls=cells,
                            spacing=self.ui(3),
                        ),
                    ],
                    spacing=self.ui(4),
                )
            )

        return ft.Container(
            width=float("inf"),
            padding=ft.Padding(
                left=self.ui(9) if compact else 10,
                top=self.ui(8) if compact else 10,
                right=self.ui(9) if compact else 10,
                bottom=self.ui(8) if compact else 10,
            ),
            border=ft.Border.all(1, ft.Colors.GREY_700),
            border_radius=self.rounding(),
            alignment=ft.Alignment.CENTER_LEFT,
            content=ft.Column(
                controls=rows,
                spacing=self.ui(4) if compact else 5,
                horizontal_alignment=ft.CrossAxisAlignment.START,
            ),
        )

    def choose_cycle_day_workout(self, cycle, day):
        """Choose a workout for one day of the repeating cycle schedule."""
        workouts = storage.read_workouts()
        items = []

        def close_sheet():
            self.page.pop_dialog()

        def choose(workout_id):
            storage.set_mesocycle_day_workout(
                cycle.get("cycle_id", ""),
                day["day_number"],
                workout_id,
                cycle=cycle,
            )
            close_sheet()
            self.show_mesocycle_calendar(cycle.get("cycle_id", ""))

        def option(label, on_click):
            return ft.Container(
                height=self.ui(46),
                padding=ft.Padding(
                    left=self.ui(12),
                    top=self.ui(5),
                    right=self.ui(12),
                    bottom=self.ui(5),
                ),
                alignment=ft.Alignment.CENTER_LEFT,
                ink=True,
                on_click=on_click,
                content=ft.Text(
                    label,
                    size=self.fs(16),
                    weight=ft.FontWeight.W_500,
                    max_lines=1,
                    no_wrap=True,
                ),
            )

        items.append(option("Rest", lambda e: choose("")))
        for workout in workouts:
            items.append(
                option(
                    workout["name"],
                    lambda e, wid=workout["workout_id"]: choose(wid),
                )
            )

        visible_rows = min(6, max(1, len(items)))
        list_height = self.ui(visible_rows * 46)
        sheet = ft.BottomSheet(
            show_drag_handle=True,
            draggable=True,
            scrollable=True,
            content=ft.Container(
                padding=ft.Padding(
                    left=self.ui(8), top=0, right=self.ui(8), bottom=self.ui(10)
                ),
                content=ft.Column(
                    controls=[
                        ft.Text(
                            f"Schedule day {day['day_in_microcycle']}",
                            size=self.fs(18),
                            weight=ft.FontWeight.BOLD,
                        ),
                        ft.ListView(
                            controls=items,
                            height=list_height,
                            spacing=self.ui(2),
                            padding=0,
                        ),
                    ],
                    spacing=self.ui(8),
                    tight=True,
                ),
            ),
        )
        self.page.show_dialog(sheet)

    def show_mesocycle_calendar(self, cycle_id=None, setup_required=False):
        active_cycle = storage.active_mesocycle()
        cycle = storage.get_mesocycle(cycle_id) if cycle_id else active_cycle
        if not cycle:
            self.show_mesocycle()
            return

        is_active_cycle = bool(
            active_cycle
            and active_cycle.get("cycle_id") == cycle.get("cycle_id")
        )
        if setup_required and not is_active_cycle:
            setup_required = False

        # Previous mesocycles live under History; the active calendar lives in Cycle.
        self.selected_tab = 2 if is_active_cycle else 1
        self.page.navigation_bar.selected_index = self.selected_tab
        if setup_required:
            self.pending_cycle_setup_id = cycle.get("cycle_id", "")

        pending_setup = self.pending_cycle_setup_id == cycle.get("cycle_id", "")
        days = storage.mesocycle_calendar_days(cycle)

        # Workouts/exercises are configured once.  Every later microcycle reuses
        # this exact schedule; there is no per-microcycle override UI or data.
        schedule_days = [day for day in days if day.get("microcycle", 1) == 1]

        controls = [
            ft.Text("Cycle Calendar", size=self.fs(28), weight=ft.FontWeight.BOLD),
        ]

        if pending_setup:
            controls.append(
                ft.Text(
                    "Choose the repeating training schedule, then press Start.",
                    size=self.fs(12),
                )
            )

        controls.append(self.cycle_heatmap(cycle))
        controls.extend(
            [
                ft.Text(
                    "Repeating Schedule",
                    size=self.fs(18),
                    weight=ft.FontWeight.BOLD,
                ),
                ft.Text(
                    "This same workout schedule is used for every microcycle in the mesocycle.",
                    size=self.fs(11),
                    color=ft.Colors.GREY_500,
                ),
            ]
        )

        for day in schedule_days:
            assigned = day.get("workout_name") or "Rest"
            controls.append(
                ft.Container(
                    width=float("inf"),
                    padding=ft.Padding(
                        left=self.ui(9),
                        top=self.ui(7),
                        right=self.ui(9),
                        bottom=self.ui(7),
                    ),
                    border=ft.Border.all(1, ft.Colors.GREY_700),
                    border_radius=self.rounding(),
                    ink=True,
                    on_click=lambda e, d=day: self.choose_cycle_day_workout(cycle, d),
                    content=ft.Row(
                        controls=[
                            ft.Text(
                                f"Day {day['day_in_microcycle']}",
                                width=self.ui(66),
                                size=self.fs(11),
                                weight=ft.FontWeight.BOLD,
                            ),
                            ft.Text(
                                assigned,
                                size=self.fs(15),
                                weight=ft.FontWeight.W_500,
                                max_lines=1,
                                no_wrap=True,
                                expand=True,
                            ),
                            ft.Icon(ft.Icons.CHEVRON_RIGHT, size=self.ui(20)),
                        ],
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                )
            )

        footer = None
        if pending_setup:
            ready = storage.mesocycle_has_planned_workouts(cycle.get("cycle_id", ""))

            def start_cycle(e=None):
                if not storage.mesocycle_has_planned_workouts(cycle.get("cycle_id", "")):
                    self.notify("Assign at least one workout day before starting the mesocycle.")
                    return
                storage.mark_mesocycle_setup_complete(cycle.get("cycle_id", ""))
                self.pending_cycle_setup_id = None
                self.notify("Mesocycle started.")
                self.show_mesocycle()

            start_button = ft.FilledButton(
                content="Start",
                on_click=start_cycle,
                expand=True,
                style=ft.ButtonStyle(
                    bgcolor=(self.accent_color() if ready else ft.Colors.RED_600),
                    color=ft.Colors.WHITE,
                ),
            )
            footer = ft.Row(controls=[start_button])

        calendar_back_action = (
            self.leave_mesocycle_calendar
            if is_active_cycle
            else lambda: self.show_previous_mesocycle_editor(cycle.get("cycle_id", ""))
        )
        self.set_view(controls, footer=footer, back_action=calendar_back_action)

    def show_rest_lock_info(self):
        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text("Lock rest times"),
            content=ft.Text(
                "Keeping rest times consistent makes sessions easier to compare. "
                "If rest changes substantially, reps and RIR can change because "
                "you recovered more or less between sets rather than because the "
                "exercise became easier or harder."
            ),
            actions=[
                self.filled_button(
                    "OK",
                    on_click=lambda e: self.close_dialog(dialog),
                )
            ],
        )
        self.page.show_dialog(dialog)

    def show_rir_unlock_info(self):
        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text("Unlock RIR"),
            content=ft.Text(
                "The cycle will still lower its suggested RIR as the training periods get "
                "harder. Unlocking only lets you edit the logged RIR. Keeping it "
                "locked makes every set follow the effort target the cycle was "
                "designed around, so progression and load suggestions stay easier "
                "to interpret."
            ),
            actions=[
                self.filled_button(
                    "OK",
                    on_click=lambda e: self.close_dialog(dialog),
                )
            ],
        )
        self.page.show_dialog(dialog)

    def confirm_rir_unlock(self, switch, on_unlock):
        def keep_locked(e=None):
            switch.value = False
            self.close_dialog(dialog)
            self.page.update()

        def unlock(e=None):
            self.close_dialog(dialog)
            switch.value = True
            on_unlock()
            self.page.update()

        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text("Keep RIR locked?"),
            content=ft.Text(
                "The cycle will keep progressing toward lower RIR targets either "
                "way. If you change the prescribed RIR, however, your logged sets "
                "no longer match the effort target you were supposed to follow, "
                "which can make the cycle and future load suggestions harder to "
                "interpret. Keep it locked unless you intentionally want to override it."
            ),
            actions=[
                self.filled_button("Keep locked", on_click=keep_locked),
                self.outlined_button("Unlock", on_click=unlock),
            ],
        )
        self.page.show_dialog(dialog)

    def mesocycle_rir_logging_card(self):
        return ft.Container(
            width=float("inf"),
            padding=ft.Padding(left=self.ui(11), top=self.ui(10), right=self.ui(11), bottom=self.ui(10)),
            border=ft.Border.all(
                1,
                ft.Colors.with_opacity(0.55, self.accent_color()),
            ),
            border_radius=self.rounding(),
            bgcolor=ft.Colors.with_opacity(0.07, self.accent_color()),
            content=ft.Column(
                controls=[
                    ft.Text(
                        "Log reps at the prescribed RIR",
                        weight=ft.FontWeight.BOLD,
                    ),
                    ft.Text(
                        "The RIR target is fixed during a mesocycle so progress "
                        "can be compared consistently. Record the rep count that "
                        "corresponds to the prescribed RIR, even if the set ended "
                        "harder or easier than planned.",
                        size=self.fs(11),
                    ),
                    ft.Text(
                        "Example: the target is 3 RIR. You perform 8 reps but feel "
                        "you only had 2 reps left. Record 7 reps at 3 RIR. This "
                        "keeps progression tracking and future load suggestions "
                        "based on the same effort target.",
                        size=self.fs(11),
                        weight=ft.FontWeight.W_500,
                    ),
                ],
                spacing=self.ui(5),
            ),
        )

    def show_mesocycle_info(self):
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
            title=ft.Text("How to use a mesocycle"),
            content=ft.Container(
                width=self.dialog_width(430),
                content=ft.Column(
                    controls=[
                        section(
                            "Build the repeating schedule",
                            "Set the microcycle length to match how your training "
                            "actually repeats. Seven days works for a weekly plan, "
                            "but shorter or longer cycles are fine too.",
                        ),
                        section(
                            "Plan the training phase",
                            "Choose how many repeating training periods you want to run "
                            "before resetting or changing the program. With the default "
                            "7-day microcycle these are shown as weeks; Advanced Mode can "
                            "change the microcycle length in days.",
                        ),
                        section(
                            "Follow the prescribed RIR",
                            "Each microcycle gives you a fixed RIR target. Use it as "
                            "the effort standard for that phase. If a set ends harder "
                            "or easier than planned, adjust the rep count you record so "
                            "it represents the prescribed RIR. That keeps comparisons "
                            "between training periods meaningful.",
                        ),
                        section(
                            "Progress reps, then load",
                            "GYMER uses an 8-12 rep working window. When load needs to change, "
                            "it estimates strength with the Wathan rep-max curve, targets 8 reps "
                            "plus the current period's RIR, then rounds only to the exercise's "
                            "available gym-weight increment.",
                        ),
                        section(
                            "Change the plan when needed",
                            "A mesocycle is a planning tool, not a restriction. Edit "
                            "the calendar or targets when your schedule or recovery "
                            "changes, and use the history to remember what you ran."
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

    def rep_max_table_card(self, back_action=None):
        return ft.Container(
            width=float("inf"),
            padding=ft.Padding(left=self.ui(10), top=self.ui(9), right=self.ui(10), bottom=self.ui(9)),
            border=ft.Border.all(1, ft.Colors.GREY_700),
            border_radius=self.rounding(),
            ink=True,
            on_click=lambda e: self.show_rep_max_table(back_action),
            content=ft.Row(
                controls=[
                    ft.Icon(ft.Icons.FITNESS_CENTER),
                    ft.Column(
                        controls=[
                            ft.Text("Rep Max Table", weight=ft.FontWeight.BOLD),
                            ft.Text(
                                "Estimated 1–20 RM target weights",
                                size=self.fs(10.5),
                            ),
                        ],
                        spacing=0,
                        expand=True,
                    ),
                    ft.Icon(ft.Icons.CHEVRON_RIGHT),
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

    def show_rep_max_info(self):
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
            title=ft.Text("How to use Rep Max"),
            content=ft.Container(
                width=self.dialog_width(455),
                content=ft.Column(
                    controls=[
                        section(
                            "Start from a set you already know",
                            "Enter a weight and the repetition maximum that weight "
                            "represents. You can use 1RM, any value shown in the 1–20RM table, "
                            "or a higher RM value. You do not need to test a true one-rep maximum.",
                        ),
                        section(
                            "Use the RIR targets to choose a working weight",
                            "Pick the effort you want for the next set. The target "
                            "rows translate your rep goal and RIR into a suggested "
                            "starting weight. Use the result as a practical first "
                            "choice, then adjust from your actual performance.",
                        ),
                        section(
                            "Prefer your own history",
                            "The estimate is most useful for choosing a sensible "
                            "starting load. If your completed sets repeatedly feel "
                            "easier or harder than predicted, your own logged "
                            "performance should take priority.",
                        ),
                        ft.Divider(),
                        section(
                            "Wathan equation",
                            "The calculator uses the Wathan repetition-max equation "
                            "for RM conversions above 1RM. The 1RM row itself is 100% by definition.",
                        ),
                        ft.Container(
                            padding=ft.Padding(left=self.ui(10), top=self.ui(8), right=self.ui(10), bottom=self.ui(8)),
                            border=ft.Border.all(1, ft.Colors.GREY_700),
                            border_radius=self.rounding(),
                            content=ft.Column(
                                controls=[
                                    ft.Text(
                                        "1RM = weight × 100 / "
                                        "(48.8 + 53.8 × exp(-0.075 × reps))",
                                        weight=ft.FontWeight.BOLD,
                                    ),
                                    ft.Text(
                                        "For reps ≥ 2: %1RM = "
                                        "48.8 + 53.8 × exp(-0.075 × reps)",
                                        weight=ft.FontWeight.BOLD,
                                    ),
                                    ft.Text(
                                        "1RM = 100%",
                                        weight=ft.FontWeight.BOLD,
                                    ),
                                ],
                                spacing=self.ui(5),
                                tight=True,
                            ),
                        ),
                        ft.Text(
                            "The calculator keeps the Wathan percentage at full "
                            "precision when calculating weights. The %1RM column is "
                            "rounded to the nearest whole percent only to keep the "
                            "table easy to read. Calculations can still use RM values above 20."
                        ),
                        ft.Text(
                            "For RIR planning, target reps + RIR selects the "
                            "effective repetition maximum. For example, 8 reps "
                            "with 3 RIR uses the 11RM estimate."
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

    def exercise_rep_max_seed(self, exercise_name):
        unit = self.settings.get("unit", "kg")

        for item in reversed(self.set_controls):
            if (
                item.get("exercise_name") != exercise_name
                or not item.get("completed")
                or (item.get("set_type", "Normal") or "Normal").strip().casefold()
                not in {"straight", "normal"}
            ):
                continue

            weight = self.evaluate_numeric_expression(item["weight"].value)
            reps = self.evaluate_numeric_expression(item["reps"].value)
            if weight is None or reps is None or weight <= 0 or reps <= 0:
                continue

            rir = 0.0
            if self.track_rir_enabled():
                parsed_rir = self.evaluate_numeric_expression(item["rir"].value)
                if parsed_rir is not None:
                    rir = max(0.0, parsed_rir)

            effective_rm = int(round(reps + rir))
            note = f"Using your latest straight set: {weight:g} {unit} × {reps:g}"
            if rir:
                note += f" @ {rir:g} RIR"
            note += "."
            if effective_rm >= 1:
                return f"{weight:g}", str(effective_rm), note
            return f"{weight:g}", "", note

        latest = storage.latest_completed_straight_set(exercise_name)
        if not latest:
            return "", "", "No completed straight set is available yet. Enter a set you know."

        stored_unit = latest.get("weight_unit", unit) or unit
        converted = storage.convert_weight_value(
            latest.get("weight", ""),
            stored_unit,
            unit,
        )
        reps = self.evaluate_numeric_expression(latest.get("reps", "")) or 0
        rir = self.evaluate_numeric_expression(latest.get("rir", "")) or 0
        rir = max(0.0, rir)
        effective_rm = int(round(reps + rir))

        note = f"Using your latest straight set: {converted} {unit} × {reps:g}"
        if rir:
            note += f" @ {rir:g} RIR"
        note += "."

        if effective_rm >= 1:
            return converted, str(effective_rm), note
        return converted, "", note

    def open_exercise_rep_max(self, exercise_name):
        if self.set_controls:
            self.capture_active_controls()

        weight, known_rm, note = self.exercise_rep_max_seed(exercise_name)
        self.show_rep_max_table(
            back_action=self.show_active_workout,
            exercise_name=exercise_name,
            initial_known_weight=weight,
            initial_known_rm=known_rm,
            source_note=note,
        )

    def apply_exercise_rep_max_target(
        self,
        exercise_name,
        target_weight,
        target_reps,
        target_rir,
    ):
        if not self.active_workout:
            return

        target = next(
            (
                row
                for row in self.active_workout.get("rows", [])
                if row.get("exercise_name") == exercise_name
                and not row.get("completed", False)
            ),
            None,
        )
        if target is None:
            self.notify("All sets for this exercise are already completed.")
            return

        target["weight"] = str(target_weight)
        target["weight_unit"] = self.settings.get("unit", "kg")
        target["reps"] = str(target_reps)

        if self.track_rir_enabled():
            planned_rir = self.cycle_rir_target()
            if planned_rir is not None and self.cycle_rir_lock_enabled():
                target["rir"] = str(planned_rir)
            else:
                target["rir"] = str(target_rir)

        # A calculator row is an explicit target choice, not a suspicious
        # accidental entry. Mark the loaded values as accepted before the
        # active workout is rebuilt so the weight cannot start pulsing orange.
        set_number = int(target.get("set_number", 0) or 0)
        self.acknowledge_numeric_value(
            exercise_name, set_number, "weight", target["weight"]
        )
        self.acknowledge_numeric_value(
            exercise_name, set_number, "reps", target["reps"]
        )
        if self.track_rir_enabled():
            self.acknowledge_numeric_value(
                exercise_name, set_number, "rir", target.get("rir", "")
            )

        storage.save_active_workout(self.active_workout)
        self.show_active_workout()
        self.notify(
            f"Loaded {target_weight} {self.settings.get('unit', 'kg')} "
            f"× {target_reps} into the next {exercise_name} set."
        )

    def show_rep_max_table(
        self,
        back_action=None,
        *,
        as_tab=False,
        from_settings=False,
        exercise_name=None,
        initial_known_weight="",
        initial_known_rm="",
        source_note="",
    ):
        if exercise_name:
            self.selected_tab = 0
            self.page.navigation_bar.selected_index = 0
        elif as_tab:
            self.selected_tab = 3
            self.page.navigation_bar.selected_index = 3
        elif from_settings:
            self.selected_tab = 4
            self.page.navigation_bar.selected_index = 4
        else:
            self.selected_tab = 2
            self.page.navigation_bar.selected_index = 2

        unit = self.settings.get("unit", "kg")
        percentages = self.rep_max_percentages()
        advanced = self.advanced_mode_enabled()
        target_reps_value = (
            self.settings.get("rep_max_target_reps", "8")
            if advanced
            else "8"
        )

        known_weight = self.text_field(
            label=f"Known weight ({unit})",
            hint_text="e.g. 100",
            value=str(initial_known_weight or ""),
            width=self.ui(150),
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="weight",
        )
        known_rm = self.text_field(
            label="Known RM",
            hint_text="e.g. 10",
            value=str(initial_known_rm or ""),
            width=self.ui(90),
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="rm",
        )
        target_reps = self.text_field(
            label="Target reps",
            value=target_reps_value,
            width=self.ui(108),
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="target_reps",
            visible=advanced,
        )
        if advanced:
            self.chain_text_fields(known_weight, known_rm, target_reps)
        else:
            self.chain_text_fields(known_weight, known_rm)

        estimated_1rm = ft.Text(
            "—",
            size=self.fs(21),
            weight=ft.FontWeight.BOLD,
            text_align=ft.TextAlign.RIGHT,
            no_wrap=True,
        )
        estimated_1rm_block = ft.Column(
            controls=[
                ft.Text(
                    "Estimated 1RM",
                    size=self.fs(10),
                    color=ft.Colors.GREY_500,
                    text_align=ft.TextAlign.RIGHT,
                ),
                estimated_1rm,
            ],
            spacing=0,
            expand=True,
            horizontal_alignment=ft.CrossAxisAlignment.END,
        )

        def right_text(value, width=None, *, bold=False, expand=False):
            return ft.Text(
                value,
                width=width,
                expand=expand,
                text_align=ft.TextAlign.RIGHT,
                weight=ft.FontWeight.BOLD if bold else ft.FontWeight.W_500,
            )

        rm_target_labels = []
        rm_rows = [
            ft.Container(
                padding=ft.Padding(left=self.ui(8), top=self.ui(7), right=self.ui(8), bottom=self.ui(7)),
                bgcolor=ft.Colors.with_opacity(0.10, self.foreground_color()),
                content=ft.Row(
                    controls=[
                        right_text("RM", 58, bold=True),
                        right_text("% 1RM", 76, bold=True),
                        right_text("Target", expand=True, bold=True),
                    ],
                    spacing=self.ui(8),
                ),
            )
        ]
        emphasized = {1, 2, 3, 8, 9, 10, 11, 12}
        for rm, percent in enumerate(percentages, start=1):
            target = right_text("—", expand=True)
            rm_target_labels.append((rm, percent, target))
            rm_rows.append(
                ft.Container(
                    padding=ft.Padding(left=self.ui(8), top=self.ui(6), right=self.ui(8), bottom=self.ui(6)),
                    bgcolor=(
                        ft.Colors.with_opacity(0.07, self.accent_color())
                        if rm in emphasized
                        else None
                    ),
                    content=ft.Row(
                        controls=[
                            right_text(f"{rm} RM", 58, bold=rm in emphasized),
                            right_text(f"{int(round(percent))}%", 76),
                            target,
                        ],
                        spacing=self.ui(8),
                    ),
                )
            )

        rir_rows = []
        rir_reps_header = right_text(f"{target_reps_value} reps", 68, bold=True)
        rir_controls = [
            ft.Container(
                padding=ft.Padding(left=self.ui(8), top=self.ui(7), right=self.ui(8), bottom=self.ui(7)),
                bgcolor=ft.Colors.with_opacity(0.10, self.foreground_color()),
                content=ft.Row(
                    controls=[
                        right_text("RIR", 52, bold=True),
                        rir_reps_header,
                        right_text("Target weight", expand=True, bold=True),
                        *([ft.Container(width=self.ui(24))] if exercise_name else []),
                    ],
                    spacing=self.ui(8),
                ),
            )
        ]

        for rir_value in (3, 2, 1):
            reps_label = right_text(target_reps_value, 68, bold=True)
            weight_label = right_text("—", expand=True, bold=True)
            row_state = {
                "rir": rir_value,
                "reps_label": reps_label,
                "weight_label": weight_label,
                "target_weight": None,
                "target_reps": None,
            }
            rir_rows.append(row_state)
            controls = [
                right_text(str(rir_value), 52, bold=True),
                reps_label,
                weight_label,
            ]
            if exercise_name:
                controls.append(ft.Icon(ft.Icons.CHEVRON_RIGHT, size=18))
            container = ft.Container(
                padding=ft.Padding(left=self.ui(8), top=self.ui(8), right=self.ui(8), bottom=self.ui(8)),
                ink=bool(exercise_name),
                tooltip=(
                    "Use this target for the next unfinished set"
                    if exercise_name
                    else None
                ),
                content=ft.Row(controls=controls, spacing=self.ui(8)),
            )
            row_state["container"] = container
            rir_controls.append(container)

        def parsed(field):
            return self.evaluate_numeric_expression(field.value)

        def parse_inputs():
            weight_value = parsed(known_weight)
            rm_value_raw = parsed(known_rm)
            if weight_value is None or rm_value_raw is None:
                return None, None
            if abs(rm_value_raw - round(rm_value_raw)) > 1e-9:
                return None, None
            rm_value = int(round(rm_value_raw))
            if weight_value <= 0 or rm_value < 1:
                return None, None
            known_percent = self.wathan_percent_1rm(rm_value) / 100.0
            return weight_value / known_percent, rm_value

        def rounded_weight(value):
            return str(int(round(value)))

        def target_rep_count():
            if not advanced:
                return 8
            value = parsed(target_reps)
            if value is None or abs(value - round(value)) > 1e-9:
                return 0
            value = int(round(value))
            return value if value >= 1 else 0

        def update_calculator(e=None):
            one_rm_value, _ = parse_inputs()
            if one_rm_value is None:
                estimated_1rm.value = "—"
                for _, _, label in rm_target_labels:
                    label.value = "—"
            else:
                estimated_1rm.value = f"{rounded_weight(one_rm_value)} {unit}"
                for _, percent, label in rm_target_labels:
                    label.value = (
                        f"{rounded_weight(one_rm_value * percent / 100.0)} {unit}"
                    )

            reps_count = target_rep_count()
            if advanced and reps_count:
                self.settings["rep_max_target_reps"] = str(reps_count)
                storage.save_settings(self.settings)

            shown_reps = str(reps_count) if reps_count else "—"
            rir_reps_header.value = f"{shown_reps} reps" if reps_count else "Reps"
            for row_state in rir_rows:
                row_state["reps_label"].value = shown_reps
                effective_rm = reps_count + row_state["rir"] if reps_count else 0
                if effective_rm >= 1 and one_rm_value is not None:
                    percent = self.wathan_percent_1rm(effective_rm)
                    shown = rounded_weight(one_rm_value * percent / 100.0)
                    row_state["weight_label"].value = f"{shown} {unit}"
                    row_state["target_weight"] = shown
                    row_state["target_reps"] = reps_count
                elif effective_rm >= 1:
                    row_state["weight_label"].value = "—"
                    row_state["target_weight"] = None
                    row_state["target_reps"] = reps_count
                else:
                    row_state["weight_label"].value = "—"
                    row_state["target_weight"] = None
                    row_state["target_reps"] = reps_count

            self.page.update()

        def finalize(field, kind):
            if self.normalize_numeric_control(field, kind=kind, allow_empty=True):
                update_calculator()
            else:
                self.page.update()

        known_weight.on_change = update_calculator
        known_rm.on_change = update_calculator
        target_reps.on_change = update_calculator if advanced else None
        known_weight.on_blur = lambda e: finalize(known_weight, "weight")
        known_rm.on_blur = lambda e: finalize(known_rm, "rm")
        if advanced:
            target_reps.on_blur = lambda e: finalize(target_reps, "target_reps")

        def use_rir_target(row_state):
            if (
                not exercise_name
                or not row_state.get("target_weight")
                or not row_state.get("target_reps")
            ):
                return
            self.apply_exercise_rep_max_target(
                exercise_name,
                row_state["target_weight"],
                row_state["target_reps"],
                row_state["rir"],
            )

        for row_state in rir_rows:
            if exercise_name:
                row_state["container"].on_click = (
                    lambda e, state=row_state: use_rir_target(state)
                )

        title_controls = [
            ft.Text(
                f"{exercise_name} Rep Max" if exercise_name else "Rep Max Calculator",
                size=self.fs(28),
                weight=ft.FontWeight.BOLD,
                expand=True,
            ),
            ft.IconButton(
                icon=ft.Icons.INFO_OUTLINE,
                icon_size=self.ui(20),
                width=self.ui(34),
                height=self.ui(34),
                padding=0,
                tooltip="How to use this calculator",
                on_click=lambda e: self.show_rep_max_info(),
            ),
        ]

        controls = [
            ft.Row(
                controls=title_controls,
                spacing=2,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            )
        ]
        if source_note:
            controls.append(
                ft.Text(source_note, size=self.fs(11), color=ft.Colors.GREY_500)
            )

        controls.extend(
            [
                ft.Row(
                    controls=[
                        known_weight,
                        known_rm,
                        estimated_1rm_block,
                    ],
                    spacing=self.ui(8),
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Divider(),
                ft.Row(
                    controls=[
                        ft.Text(
                            "RIR Targets",
                            size=self.fs(20),
                            weight=ft.FontWeight.BOLD,
                            expand=True,
                        ),
                        *([target_reps] if advanced else []),
                    ],
                    spacing=self.ui(8),
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
            ]
        )

        controls.extend(
            [
                ft.Container(
                    width=float("inf"),
                    border=ft.Border.all(1, ft.Colors.GREY_700),
                    border_radius=self.rounding(),
                    content=ft.Column(controls=rir_controls, spacing=0),
                ),
            ]
        )
        controls.append(
            ft.Text(
                (
                    "Tap any target number to load that weight and rep target into "
                    "the next unfinished set for this exercise."
                    if exercise_name
                    else "When opened from an exercise, tap a target number to load "
                    "it directly into the next unfinished set."
                ),
                size=self.fs(10.5),
                color=ft.Colors.GREY_500,
            )
        )

        controls.extend(
            [
                ft.Divider(),
                ft.Text("1–20 RM Table", size=self.fs(20), weight=ft.FontWeight.BOLD),
                ft.Container(
                    width=float("inf"),
                    border=ft.Border.all(1, ft.Colors.GREY_700),
                    border_radius=self.rounding(),
                    content=ft.Column(controls=rm_rows, spacing=0),
                ),
                ft.Text(
                    "Use the full table when you want to compare rep ranges. "
                    "Treat the numbers as starting estimates and adjust from "
                    "your own completed sets.",
                    size=self.fs(10.5),
                    color=ft.Colors.GREY_500,
                ),
            ]
        )

        update_calculator()

        if exercise_name:
            resolved_back_action = back_action or self.show_active_workout
        elif as_tab:
            resolved_back_action = None
        elif from_settings:
            resolved_back_action = back_action or (
                lambda: self.show_settings(force_root=True)
            )
        else:
            resolved_back_action = back_action or self.show_mesocycle

        self.set_view(
            controls,
            back_action=resolved_back_action,
            root_back_to_active=as_tab,
        )

    def continue_mesocycle(self, cycle_id):
        """Resume the same mesocycle after it was ended early."""
        source = storage.get_mesocycle(cycle_id)
        if not source:
            self.notify("Mesocycle not found.")
            return

        if getattr(self, "active_workout", None):
            self.notify("Finish or discard the active workout before resuming a mesocycle.")
            return

        # A calendar-complete cycle needs its planned length extended first.
        # Re-activating it unchanged would immediately remain in Complete phase.
        if storage.mesocycle_status(source)["complete"]:
            self.notify("Increase this mesocycle's length first, then resume it.")
            if source.get("active", "0") == "1":
                self.show_mesocycle_plan()
            return

        active = storage.active_mesocycle()
        source_id = str(source.get("cycle_id", "") or "")
        active_id = str((active or {}).get("cycle_id", "") or "")

        def resume(dialog=None):
            if dialog is not None:
                self.close_dialog(dialog)
            resumed_id = storage.continue_mesocycle(source_id)
            if not resumed_id:
                self.notify("Could not resume mesocycle.")
                return
            self.notify("Mesocycle resumed.")
            self.show_mesocycle()

        if active and active_id != source_id:
            dialog = ft.AlertDialog(
                modal=True,
                title=ft.Text("Resume this mesocycle?"),
                content=ft.Text(
                    "A different mesocycle is currently active. Resuming this one "
                    "will end the current active cycle and reactivate this exact "
                    "mesocycle with its original start date, workout rotation, and calibration."
                ),
                actions=[
                    self.outlined_button(
                        "Cancel",
                        on_click=lambda e: self.close_dialog(dialog),
                    ),
                    ft.OutlinedButton(
                        content="Resume mesocycle",
                        on_click=lambda e: resume(dialog),
                        style=self.button_style(),
                    ),
                ],
            )
            self.page.show_dialog(dialog)
            return

        resume()

    def show_previous_mesocycle_editor(self, cycle_id):
        cycle = storage.get_mesocycle(cycle_id)
        if not cycle or cycle.get("active", "0") == "1":
            self.show_workout_history()
            return

        self.selected_tab = 1
        self.page.navigation_bar.selected_index = 1
        advanced = self.advanced_mode_enabled()

        name_field = self.text_field(
            label="Mesocycle name",
            value=cycle.get("name", "Mesocycle"),
            dense=True,
        )
        start_field = self.text_field(
            label="Start date",
            value=cycle.get("start_date", ""),
            hint_text="YYYY-MM-DD",
            dense=True,
        )
        micro_days = self.text_field(
            label="Microcycle length (days)",
            value=cycle.get("microcycle_days", "7"),
            width=self.ui(190),
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="count",
        )
        length_value = self.text_field(
            label="Mesocycle length",
            value=str(storage.mesocycle_length_microcycles(cycle)),
            width=self.ui(190),
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="count",
        )
        deload_count = self.text_field(
            label="Deload",
            value=cycle.get("deload_microcycles", "1"),
            width=self.ui(190),
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="nonnegative_count",
        )
        self.chain_text_fields(
            name_field,
            start_field,
            length_value,
            deload_count,
            micro_days,
        )

        def field_int(field, default=0):
            value = self.evaluate_numeric_expression(field.value)
            if value is None or abs(value - round(value)) > 1e-9:
                return default
            return int(round(value))

        length_suffix = ft.Text(size=self.fs(10.5), color=ft.Colors.GREY_500)
        deload_suffix = ft.Text(size=self.fs(10.5), color=ft.Colors.GREY_500)

        def suffix_wrapper(field, suffix):
            field.content_padding = ft.Padding(
                left=self.ui(10), top=self.ui(8), right=self.ui(76), bottom=self.ui(8)
            )
            return ft.Stack(
                controls=[
                    field,
                    ft.Container(
                        right=self.ui(8),
                        top=0,
                        bottom=0,
                        alignment=ft.Alignment.CENTER,
                        ignore_interactions=True,
                        content=suffix,
                    ),
                ],
                width=self.ui(190),
            )

        length_wrapper = suffix_wrapper(length_value, length_suffix)
        deload_wrapper = suffix_wrapper(deload_count, deload_suffix)

        def refresh_suffixes(e=None):
            days = max(1, field_int(micro_days, 7))
            length_count = max(1, field_int(length_value, 5))
            deload_value = max(0, field_int(deload_count, 1))
            if days == 7:
                length_suffix.value = "week" if length_count == 1 else "weeks"
                deload_suffix.value = "week" if deload_value == 1 else "weeks"
            else:
                length_suffix.value = "microcycle" if length_count == 1 else "microcycles"
                deload_suffix.value = "microcycle" if deload_value == 1 else "microcycles"
            if e is not None:
                self.page.update()

        micro_days.on_blur = refresh_suffixes
        length_value.on_blur = refresh_suffixes
        deload_count.on_blur = refresh_suffixes
        refresh_suffixes()

        def save_previous(e=None, refresh=True):
            valid = True
            fields = [name_field, start_field, length_value, deload_count]
            if advanced:
                fields.append(micro_days)
            for field in fields:
                self.clear_field_invalid(field)

            try:
                datetime.fromisoformat((start_field.value or "").strip()).date()
            except ValueError:
                self.mark_field_invalid(start_field)
                valid = False

            if not (name_field.value or "").strip():
                self.mark_field_invalid(name_field)
                valid = False
            if advanced and field_int(micro_days, 0) <= 0:
                self.mark_field_invalid(micro_days)
                valid = False
            if field_int(length_value, 0) <= 0:
                self.mark_field_invalid(length_value)
                valid = False

            config = dict(cycle)
            config.update({
                "name": (name_field.value or "Mesocycle").strip(),
                "start_date": (start_field.value or "").strip(),
                "microcycle_days": str(max(1, field_int(micro_days, 7))),
                "length_value": str(max(1, field_int(length_value, 5))),
                "length_unit": "microcycles",
                "deload_microcycles": str(max(0, field_int(deload_count, 1))),
            })
            if valid:
                status = storage.mesocycle_status(config)
                if field_int(deload_count, 0) >= status["total_microcycles"]:
                    self.mark_field_invalid(deload_count)
                    valid = False

            if not valid:
                self.page.update()
                return False

            storage.update_mesocycle(cycle_id, config)
            storage.save_mesocycle_day_schedule(
                cycle_id,
                storage.mesocycle_day_schedule(cycle_id),
                microcycle_days=max(1, field_int(micro_days, 7)),
            )
            if refresh:
                self.notify("Previous mesocycle saved.")
                self.show_previous_mesocycle_editor(cycle_id)
            return True

        def continue_previous(e=None):
            # Continue exactly what is visible in the editor, not a stale saved
            # copy if the user changed the plan fields immediately beforehand.
            if save_previous(refresh=False):
                self.continue_mesocycle(cycle_id)

        def confirm_delete(e=None):
            dialog = ft.AlertDialog(
                modal=True,
                title=ft.Text("Delete previous mesocycle?"),
                content=ft.Text(
                    "This removes the mesocycle plan and its calendar assignments. "
                    "Workout history itself is not deleted."
                ),
                actions=[
                    self.outlined_button(
                        "Cancel",
                        on_click=lambda e: self.close_dialog(dialog),
                    ),
                    ft.OutlinedButton(
                        content="Delete",
                        on_click=lambda e: delete_now(dialog),
                        style=self.button_style(),
                    ),
                ],
            )
            self.page.show_dialog(dialog)

        def delete_now(dialog):
            self.close_dialog(dialog)
            storage.delete_mesocycle(cycle_id)
            self.notify("Mesocycle deleted.")
            self.show_workout_history()

        status = storage.mesocycle_status(cycle)
        date_text = (
            f"{self.format_cycle_date(status['start_date'])} – "
            f"{self.format_cycle_date(status['end_date'])}"
        )

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
                        on_click=lambda e: self.show_workout_history(),
                    ),
                    ft.Column(
                        controls=[
                            ft.Text("History", weight=ft.FontWeight.BOLD),
                            ft.Text(date_text, size=self.fs(11)),
                        ],
                        spacing=0,
                        expand=True,
                    ),
                    self.icon_action(
                        ft.Icons.SAVE,
                        ft.Colors.GREEN_700,
                        save_previous,
                        width=48,
                        height=42,
                        tooltip="Save historical mesocycle",
                    ),
                    self.icon_action(
                        ft.Icons.DELETE,
                        ft.Colors.RED_700,
                        confirm_delete,
                        width=42,
                        height=42,
                        tooltip="Delete historical mesocycle",
                    ),
                ]
            ),
        )

        controls = [
            name_field,
            start_field,
            ft.Row(
                controls=[length_wrapper, deload_wrapper],
                spacing=self.ui(8),
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        ]
        if advanced:
            controls.extend([
                ft.Text("Advanced", size=self.fs(18), weight=ft.FontWeight.BOLD),
                micro_days,
            ])
        controls.append(
            ft.Container(
                width=float("inf"),
                padding=ft.Padding(left=self.ui(10), top=self.ui(9), right=self.ui(10), bottom=self.ui(9)),
                border=ft.Border.all(1, ft.Colors.GREY_700),
                border_radius=self.rounding(),
                ink=True,
                on_click=lambda e: self.show_mesocycle_calendar(cycle_id),
                content=ft.Row(
                    controls=[
                        ft.Icon(ft.Icons.CALENDAR_MONTH),
                        ft.Text("Edit Repeating Workout Schedule", expand=True, weight=ft.FontWeight.BOLD),
                        ft.Icon(ft.Icons.CHEVRON_RIGHT),
                    ]
                ),
            )
        )
        self.set_view(
            controls,
            header=header,
            footer=ft.Row(
                controls=[
                    self.outlined_button(
                        "Resume mesocycle",
                        on_click=continue_previous,
                    ),
                    ft.Container(expand=True),
                ]
            ),
            back_action=self.show_workout_history,
        )

    def previous_mesocycle_controls(self, limit=3):
        previous = [
            row
            for row in storage.mesocycle_history(limit=12)
            if row.get("active", "0") != "1"
        ][:limit]
        if not previous:
            return []

        controls = [
            ft.Divider(),
            ft.Text("Mesocycles", size=self.fs(18), weight=ft.FontWeight.BOLD),
        ]
        for row in previous:
            status = storage.mesocycle_status(row)
            controls.append(
                ft.Container(
                    width=float("inf"),
                    padding=ft.Padding(left=self.ui(10), top=self.ui(8), right=self.ui(8), bottom=self.ui(8)),
                    border=ft.Border.all(1, ft.Colors.GREY_700),
                    border_radius=self.rounding(),
                    ink=True,
                    on_click=lambda e, cid=row.get("cycle_id", ""): self.show_previous_mesocycle_editor(cid),
                    content=ft.Row(
                        controls=[
                            ft.Text(
                                row.get("name", "Mesocycle"),
                                expand=True,
                                weight=ft.FontWeight.BOLD,
                            ),
                            ft.Text(
                                f"{self.format_cycle_date(status['start_date'])} · {status['total_microcycles']} microcycles",
                                size=self.fs(11),
                            ),
                            ft.Icon(ft.Icons.EDIT_OUTLINED, size=18),
                        ],
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                )
            )
        return controls

    def show_volume_landmark_info(self, muscle_group):
        """Explain the supplied RP volume landmarks for one planned-volume row."""
        group = str(muscle_group or "").strip()
        landmark = volume_landmarks.landmark_for(group)

        definitions = ft.Column(
            controls=[
                ft.Text("What the landmarks mean", weight=ft.FontWeight.BOLD),
                ft.Text(
                    "MV — Maintenance Volume: the approximate weekly volume needed to maintain current muscle size.",
                    size=self.fs(11),
                ),
                ft.Text(
                    "MEV — Minimum Effective Volume: the lowest weekly volume expected to reliably produce growth.",
                    size=self.fs(11),
                ),
                ft.Text(
                    "MAV — Maximum Adaptive Volume: the productive volume range where most hypertrophy work is typically accumulated.",
                    size=self.fs(11),
                ),
                ft.Text(
                    "MRV — Maximum Recoverable Volume: the most weekly training volume you can recover from before recovery and performance begin to deteriorate.",
                    size=self.fs(11),
                ),
            ],
            spacing=self.ui(5),
            tight=True,
        )

        body = [definitions]
        if landmark:
            body.extend(
                [
                    ft.Divider(height=self.ui(8)),
                    ft.Text("RP volume landmarks", weight=ft.FontWeight.BOLD),
                    ft.Row(
                        controls=[
                            ft.Text("MV", width=self.ui(54), weight=ft.FontWeight.BOLD),
                            ft.Text(landmark.get("mv", "—"), expand=True),
                        ]
                    ),
                    ft.Row(
                        controls=[
                            ft.Text("MEV", width=self.ui(54), weight=ft.FontWeight.BOLD),
                            ft.Text(landmark.get("mev", "—"), expand=True),
                        ]
                    ),
                    ft.Row(
                        controls=[
                            ft.Text("MAV", width=self.ui(54), weight=ft.FontWeight.BOLD),
                            ft.Text(landmark.get("mav", "—"), expand=True),
                        ]
                    ),
                    ft.Row(
                        controls=[
                            ft.Text("MRV", width=self.ui(54), weight=ft.FontWeight.BOLD),
                            ft.Text(landmark.get("mrv", "Not provided"), expand=True),
                        ]
                    ),
                ]
            )

            source_url = str(landmark.get("url", "") or "").strip()
            if source_url:
                body.extend(
                    [
                        ft.Text(
                            "Source",
                            size=self.fs(10.5),
                            color=ft.Colors.GREY_500,
                        ),
                        self.outlined_button(
                            "Open RP Strength article",
                            on_click=lambda e, url=source_url: self.page.launch_url(url),
                        ),
                    ]
                )
        else:
            body.append(
                ft.Text(
                    "No RP volume landmark is stored for this muscle group.",
                    size=self.fs(12),
                )
            )

        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text(group or "Volume landmarks"),
            content=ft.Container(
                width=self.dialog_width(420),
                content=ft.Column(
                    controls=body,
                    spacing=self.ui(8),
                    tight=True,
                    scroll=ft.ScrollMode.AUTO,
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

    def mesocycle_weekly_volume_card(self, cycle):
        """Compact planned primary working sets for the repeating schedule."""
        counts = storage.mesocycle_planned_primary_set_counts(cycle)
        weekly = self.cycle_period_noun(cycle) == "week"

        rows = []
        for group, count in counts.items():
            mev = volume_landmarks.mev_label(group)
            mev_text = "MEV —" if mev == "—" else f"MEV {mev}"
            rows.append(
                ft.Container(
                    width=float("inf"),
                    padding=ft.Padding(
                        left=self.ui(6),
                        top=self.ui(4),
                        right=self.ui(6),
                        bottom=self.ui(4),
                    ),
                    ink=True,
                    on_click=lambda e, name=group: self.show_volume_landmark_info(name),
                    content=ft.Row(
                        controls=[
                            ft.Text(
                                group,
                                size=self.fs(12.5),
                                weight=ft.FontWeight.W_600,
                                expand=True,
                            ),
                            ft.Text(
                                str(int(count or 0)),
                                width=self.ui(34),
                                text_align=ft.TextAlign.RIGHT,
                                size=self.fs(12.5),
                                weight=ft.FontWeight.BOLD,
                            ),
                            ft.Text(
                                mev_text,
                                width=self.ui(68),
                                text_align=ft.TextAlign.RIGHT,
                                size=self.fs(10.5),
                                color=self.accent_color(),
                                weight=ft.FontWeight.W_600,
                            ),
                        ],
                        spacing=self.ui(5),
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                )
            )

        if not rows:
            rows = [
                ft.Text(
                    "Add workouts to the repeating schedule to see planned muscle-group sets.",
                    size=self.fs(11),
                    color=ft.Colors.GREY_500,
                )
            ]

        title = "Planned weekly sets" if weekly else "Planned microcycle sets"
        return ft.Container(
            width=float("inf"),
            padding=ft.Padding(
                left=self.ui(9),
                top=self.ui(8),
                right=self.ui(9),
                bottom=self.ui(7),
            ),
            border=ft.Border.all(1, ft.Colors.GREY_700),
            border_radius=self.rounding(),
            content=ft.Column(
                controls=[
                    ft.Text(
                        title,
                        size=self.fs(16),
                        weight=ft.FontWeight.BOLD,
                    ),
                    ft.Text(
                        "Planned primary working sets · tap a muscle for RP landmarks",
                        size=self.fs(10),
                        color=ft.Colors.GREY_500,
                    ),
                    *rows,
                ],
                spacing=self.ui(1),
                tight=True,
            ),
        )

    def show_mesocycle(self):
        self.selected_tab = 2
        self.page.navigation_bar.selected_index = 2

        cycle = storage.active_mesocycle()
        if not cycle:
            # Ending a cycle is easy to do accidentally.  If the most recent
            # ended cycle has not reached its planned end date, offer a direct
            # same-cycle resume instead of immediately pushing the user into a
            # brand-new mesocycle flow.
            resumable = next(
                (
                    row
                    for row in storage.mesocycle_history(limit=12)
                    if row.get("active", "0") != "1"
                    and not storage.mesocycle_status(row)["complete"]
                ),
                None,
            )
            if resumable:
                name = resumable.get("name", "Mesocycle")
                status = storage.mesocycle_status(resumable)
                controls = [
                    ft.Text("No active mesocycle", size=self.fs(28), weight=ft.FontWeight.BOLD),
                    ft.Container(
                        width=float("inf"),
                        padding=ft.Padding(
                            left=self.ui(11), top=self.ui(10), right=self.ui(11), bottom=self.ui(10)
                        ),
                        border=ft.Border.all(1, ft.Colors.GREY_700),
                        border_radius=self.rounding(),
                        content=ft.Column(
                            controls=[
                                ft.Text(name, size=self.fs(18), weight=ft.FontWeight.BOLD),
                                ft.Text(
                                    f"Ended early · day {status['day_in_microcycle']} of "
                                    f"{resumable.get('microcycle_days', '7')}",
                                    size=self.fs(11.5),
                                    color=ft.Colors.GREY_500,
                                ),
                                ft.Text(
                                    "Resume keeps the same start date, workout rotation, "
                                    "history, and calibration.",
                                    size=self.fs(11),
                                ),
                            ],
                            spacing=self.ui(4),
                        ),
                    ),
                    self.filled_button(
                        f"Resume {name}",
                        on_click=lambda e, cid=resumable.get("cycle_id", ""): self.continue_mesocycle(cid),
                        expand=True,
                    ),
                    self.outlined_button(
                        "Start new mesocycle",
                        on_click=lambda e: self.show_mesocycle_plan(as_tab_root=True),
                        expand=True,
                    ),
                ]
                self.set_view(controls, root_back_to_active=True)
                return
            self.show_mesocycle_plan(as_tab_root=True)
            return
        if cycle.get("setup_complete", "1") == "0":
            self.pending_cycle_setup_id = cycle.get("cycle_id", "")
            self.show_mesocycle_calendar(
                cycle.get("cycle_id", ""),
                setup_required=True,
            )
            return

        status = storage.mesocycle_status(cycle)
        advanced = self.advanced_mode_enabled()

        # Advanced Mode is the only place where the prescribed RIR can be unlocked.
        if not advanced and cycle.get("rir_lock", "1") == "0":
            updated = dict(cycle)
            updated["rir_lock"] = "1"
            storage.save_mesocycle(updated)
            cycle.update(updated)

        unlock_rir = ft.Switch(
            label="Unlock RIR",
            value=cycle.get("rir_lock", "1") == "0",
        )
        rir_lock_info = ft.IconButton(
            icon=ft.Icons.INFO_OUTLINE,
            icon_size=self.ui(18),
            width=self.ui(32),
            height=self.ui(32),
            padding=0,
            tooltip="Why keep RIR locked?",
            on_click=lambda e: self.show_rir_unlock_info(),
        )
        rest_timer_lock = ft.Switch(
            label="Lock rest times",
            value=cycle.get("rest_timer_lock", "0") == "1",
        )
        rest_lock_info = ft.IconButton(
            icon=ft.Icons.INFO_OUTLINE,
            icon_size=self.ui(18),
            width=self.ui(32),
            height=self.ui(32),
            padding=0,
            tooltip="Why lock rest times?",
            on_click=lambda e: self.show_rest_lock_info(),
        )

        def save_cycle_flags():
            updated = dict(cycle)
            updated["rir_lock"] = "0" if unlock_rir.value else "1"
            updated["rest_timer_lock"] = "1" if rest_timer_lock.value else "0"
            updated["show_last_week_reps"] = "0"
            storage.save_mesocycle(updated)
            cycle.update(updated)

        def rir_change(e):
            if unlock_rir.value:
                self.confirm_rir_unlock(unlock_rir, save_cycle_flags)
            else:
                save_cycle_flags()
                self.page.update()

        unlock_rir.on_change = rir_change
        rest_timer_lock.on_change = lambda e: save_cycle_flags()

        rir = status["suggested_rir"]
        rir_text = str(int(round(float(rir))))
        phase = status["phase"]

        status_box = ft.Container(
            width=float("inf"),
            padding=ft.Padding(left=self.ui(12), top=self.ui(10), right=self.ui(12), bottom=self.ui(10)),
            border=ft.Border.all(1, ft.Colors.GREY_700),
            border_radius=self.rounding(),
            content=ft.Row(
                controls=[
                    ft.Column(
                        controls=[
                            ft.Text(
                                phase,
                                size=self.fs(17),
                                weight=ft.FontWeight.BOLD,
                            ),
                            ft.Text(
                                f"Day {status['day_in_microcycle']} of {cycle.get('microcycle_days', '7')} · {rir_text} RIR",
                                size=self.fs(12.5),
                                weight=ft.FontWeight.W_600,
                            ),
                            ft.Text(
                                f"{self.format_cycle_date(status['start_date'])} – {self.format_cycle_date(status['end_date'])}",
                                size=self.fs(10.5),
                                color=ft.Colors.GREY_500,
                            ),
                        ],
                        spacing=1,
                        expand=True,
                    ),
                    ft.Text(
                        (
                            f"{status['remaining_days']} days left"
                            if not status["complete"]
                            else "Complete"
                        ),
                        size=self.fs(11),
                        weight=ft.FontWeight.W_600,
                        text_align=ft.TextAlign.RIGHT,
                    ),
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

        controls = [
            ft.Row(
                controls=[
                    ft.Text(
                        cycle.get("name", "Mesocycle"),
                        size=self.fs(27),
                        weight=ft.FontWeight.BOLD,
                        expand=True,
                        max_lines=1,
                        overflow=ft.TextOverflow.ELLIPSIS,
                    ),
                    ft.IconButton(
                        icon=ft.Icons.INFO_OUTLINE,
                        icon_size=self.ui(20),
                        width=self.ui(34),
                        height=self.ui(34),
                        padding=0,
                        tooltip="Mesocycle guide",
                        on_click=lambda e: self.show_mesocycle_info(),
                    ),
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            status_box,
            self.mesocycle_weekly_volume_card(cycle),
            self.mesocycle_rir_logging_card(),
        ]

        if advanced:
            controls.extend([
                ft.Text("Cycle locks", size=self.fs(20), weight=ft.FontWeight.BOLD),
                ft.Row(
                    controls=[unlock_rir, rir_lock_info],
                    spacing=2,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Row(
                    controls=[rest_timer_lock, rest_lock_info],
                    spacing=2,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
            ])

        controls.extend([
            self.cycle_heatmap(cycle),
            ft.Container(height=self.ui(8)),
            self.outlined_button(
                "Change plan details",
                on_click=lambda e: self.show_mesocycle_plan(),
                expand=True,
            ),
        ])

        def end_cycle(e):
            storage.end_mesocycle(cycle.get("cycle_id", ""))
            self.notify("Mesocycle ended.")
            self.show_mesocycle()

        footer_controls = [ft.Container(expand=True)]
        if status["complete"]:
            footer_controls.append(
                ft.OutlinedButton(
                    content="Extend mesocycle",
                    on_click=lambda e: self.show_mesocycle_plan(),
                    style=self.button_style(),
                )
            )
        footer_controls.append(
            ft.OutlinedButton(
                content="End mesocycle",
                on_click=end_cycle,
                style=self.button_style(),
            )
        )

        self.set_view(
            controls,
            footer=ft.Row(controls=footer_controls),
            root_back_to_active=True,
        )

    def show_mesocycle_plan(self, as_tab_root=False):
        self.selected_tab = 2
        self.page.navigation_bar.selected_index = 2

        active = storage.active_mesocycle()
        cycle = dict(active or storage.mesocycle_defaults())
        advanced = self.advanced_mode_enabled()

        # Legacy week/month plans are converted to the equivalent number of
        # repeating microcycles only when they are opened in the new editor.
        # New plans always store length directly as a microcycle count.
        editor_length = storage.mesocycle_length_microcycles(cycle)

        name_field = self.text_field(
            label="Mesocycle name",
            value=cycle.get("name", "Mesocycle"),
            dense=True,
        )
        length_value = self.text_field(
            label="Mesocycle length",
            value=str(editor_length),
            width=self.ui(190),
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="count",
        )
        deload_count = self.text_field(
            label="Deload",
            value=cycle.get("deload_microcycles", "1"),
            width=self.ui(190),
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="nonnegative_count",
        )
        start_field = self.text_field(
            label="Start date",
            value=cycle.get("start_date", datetime.now().date().isoformat()),
            hint_text="YYYY-MM-DD",
            dense=True,
        )
        micro_days = self.text_field(
            label="Microcycle length (days)",
            value=cycle.get("microcycle_days", "7"),
            width=self.ui(190),
            dense=True,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="count",
        )
        self.chain_text_fields(
            name_field,
            length_value,
            deload_count,
            start_field,
            micro_days,
        )

        def field_int(field, default):
            value = self.evaluate_numeric_expression(field.value)
            if value is None or abs(value - round(value)) > 1e-9:
                return default
            return int(round(value))

        def current_micro_days():
            return max(1, field_int(micro_days, 7))

        length_suffix = ft.Text(
            size=self.fs(10.5),
            weight=ft.FontWeight.W_500,
            color=ft.Colors.GREY_500,
        )
        deload_suffix = ft.Text(
            size=self.fs(10.5),
            weight=ft.FontWeight.W_500,
            color=ft.Colors.GREY_500,
        )

        def suffixed_field(field, suffix_control):
            field.content_padding = ft.Padding(
                left=self.ui(10),
                top=self.ui(8),
                right=self.ui(76),
                bottom=self.ui(8),
            )
            return ft.Stack(
                controls=[
                    field,
                    ft.Container(
                        right=self.ui(8),
                        top=0,
                        bottom=0,
                        alignment=ft.Alignment.CENTER,
                        ignore_interactions=True,
                        content=suffix_control,
                    ),
                ],
                width=self.ui(190),
            )

        length_wrapper = suffixed_field(length_value, length_suffix)
        deload_wrapper = suffixed_field(deload_count, deload_suffix)

        unlock_rir = ft.Switch(
            label="Unlock RIR",
            value=cycle.get("rir_lock", "1") == "0",
        )
        rir_lock_info = ft.IconButton(
            icon=ft.Icons.INFO_OUTLINE,
            icon_size=self.ui(18),
            width=self.ui(32),
            height=self.ui(32),
            padding=0,
            tooltip="Why keep RIR locked?",
            on_click=lambda e: self.show_rir_unlock_info(),
        )
        rest_timer_lock = ft.Switch(
            label="Lock rest times",
            value=cycle.get("rest_timer_lock", "0") == "1",
        )
        rest_lock_info = ft.IconButton(
            icon=ft.Icons.INFO_OUTLINE,
            icon_size=self.ui(18),
            width=self.ui(32),
            height=self.ui(32),
            padding=0,
            tooltip="Why lock rest times?",
            on_click=lambda e: self.show_rest_lock_info(),
        )

        def unlock_change(e):
            if unlock_rir.value:
                self.confirm_rir_unlock(unlock_rir, lambda: None)
            else:
                self.page.update()

        unlock_rir.on_change = unlock_change

        # The creation planner is local until Start is pressed. Existing cycles
        # load their already-saved repeating schedule so changing microcycle
        # length can safely trim/extend it on Save.
        planner_state = dict(
            storage.mesocycle_day_schedule(cycle.get("cycle_id", ""))
            if cycle.get("cycle_id")
            else {}
        )
        planner_title = ft.Text(
            weight=ft.FontWeight.BOLD,
            size=self.fs(18),
        )
        planner_help = ft.Text(
            size=self.fs(11),
            color=ft.Colors.GREY_500,
        )
        planner_error = ft.Text(
            "Assign at least one workout day.",
            size=self.fs(11),
            color=ft.Colors.RED_400,
            visible=False,
        )
        planner_days = ft.Column(spacing=self.ui(6))

        def planner_workout_names():
            return {
                row.get("workout_id", ""): row.get("name", "")
                for row in storage.read_workouts()
            }

        def render_planner(update_page=False):
            days = current_micro_days()
            weekly = days == 7
            planner_title.value = "Weekly planner" if weekly else "Microcycle planner"
            planner_help.value = (
                "Choose the workout for each day. This same weekly schedule repeats "
                "through the whole mesocycle."
                if weekly
                else "Choose the workout for each day. This same microcycle schedule "
                "repeats through the whole mesocycle."
            )
            names = planner_workout_names()
            rows = []
            try:
                start_date = datetime.fromisoformat(
                    (start_field.value or datetime.now().date().isoformat()).strip()
                ).date()
            except ValueError:
                start_date = None

            for day_number in range(1, days + 1):
                workout_id = str(planner_state.get(day_number, "") or "")
                # A deleted workout must not remain as an invisible dangling
                # assignment that still passes the "has a plan" validation.
                if workout_id and workout_id not in names:
                    workout_id = ""
                    planner_state[day_number] = ""
                workout_name = names.get(workout_id, "") or "Rest"
                day_label = f"Day {day_number}"
                if weekly and start_date is not None:
                    weekday = start_date.fromordinal(
                        start_date.toordinal() + day_number - 1
                    ).strftime("%a")
                    day_label = f"{weekday} · Day {day_number}"

                rows.append(
                    ft.Container(
                        width=float("inf"),
                        padding=ft.Padding(
                            left=self.ui(9),
                            top=self.ui(7),
                            right=self.ui(9),
                            bottom=self.ui(7),
                        ),
                        border=ft.Border.all(1, ft.Colors.GREY_700),
                        border_radius=self.rounding(),
                        ink=True,
                        on_click=lambda e, number=day_number: choose_planner_workout(number),
                        content=ft.Row(
                            controls=[
                                ft.Text(
                                    day_label,
                                    width=self.ui(92 if weekly else 70),
                                    size=self.fs(11),
                                    weight=ft.FontWeight.BOLD,
                                ),
                                ft.Text(
                                    workout_name,
                                    size=self.fs(14),
                                    weight=ft.FontWeight.W_500,
                                    max_lines=1,
                                    no_wrap=True,
                                    overflow=ft.TextOverflow.ELLIPSIS,
                                    expand=True,
                                ),
                                ft.Icon(ft.Icons.CHEVRON_RIGHT, size=self.ui(20)),
                            ],
                            vertical_alignment=ft.CrossAxisAlignment.CENTER,
                        ),
                    )
                )
            planner_days.controls = rows
            if update_page:
                self.page.update()

        def choose_planner_workout(day_number):
            items = []

            def close_sheet():
                self.page.pop_dialog()

            def choose(workout_id):
                planner_state[day_number] = str(workout_id or "")
                planner_error.visible = False
                close_sheet()
                render_planner(update_page=True)

            def option(label, workout_id):
                return ft.Container(
                    height=self.ui(46),
                    padding=ft.Padding(
                        left=self.ui(12),
                        top=self.ui(5),
                        right=self.ui(12),
                        bottom=self.ui(5),
                    ),
                    alignment=ft.Alignment.CENTER_LEFT,
                    ink=True,
                    on_click=lambda e, wid=workout_id: choose(wid),
                    content=ft.Text(
                        label,
                        size=self.fs(16),
                        weight=ft.FontWeight.W_500,
                        max_lines=1,
                        no_wrap=True,
                    ),
                )

            items.append(option("Rest", ""))
            for workout in storage.read_workouts():
                items.append(option(workout.get("name", "Workout"), workout.get("workout_id", "")))

            visible_rows = min(6, max(1, len(items)))
            sheet = ft.BottomSheet(
                show_drag_handle=True,
                draggable=True,
                scrollable=True,
                content=ft.Container(
                    padding=ft.Padding(
                        left=self.ui(8),
                        top=0,
                        right=self.ui(8),
                        bottom=self.ui(10),
                    ),
                    content=ft.Column(
                        controls=[
                            ft.Text(
                                f"Plan day {day_number}",
                                size=self.fs(18),
                                weight=ft.FontWeight.BOLD,
                            ),
                            ft.ListView(
                                controls=items,
                                height=self.ui(visible_rows * 46),
                                spacing=self.ui(2),
                                padding=0,
                            ),
                        ],
                        spacing=self.ui(8),
                        tight=True,
                    ),
                ),
            )
            self.page.show_dialog(sheet)

        def refresh_period_labels(update_page=False):
            days = current_micro_days()
            length_count = max(1, field_int(length_value, 5))
            deload_value = max(0, field_int(deload_count, 1))
            if days == 7:
                length_suffix.value = "week" if length_count == 1 else "weeks"
                deload_suffix.value = "week" if deload_value == 1 else "weeks"
            else:
                length_suffix.value = (
                    "microcycle" if length_count == 1 else "microcycles"
                )
                deload_suffix.value = (
                    "microcycle" if deload_value == 1 else "microcycles"
                )
            render_planner(update_page=False)
            if update_page:
                self.page.update()

        def refresh_period_on_blur(e=None):
            refresh_period_labels(update_page=True)

        micro_days.on_blur = refresh_period_on_blur
        length_value.on_blur = refresh_period_on_blur
        deload_count.on_blur = refresh_period_on_blur
        start_field.on_blur = lambda e: render_planner(update_page=True)
        refresh_period_labels(update_page=False)

        def build_config():
            return {
                "cycle_id": cycle.get("cycle_id", ""),
                "name": (name_field.value or "Mesocycle").strip() or "Mesocycle",
                "start_date": (start_field.value or datetime.now().date().isoformat()).strip(),
                "microcycle_days": str(current_micro_days()),
                "length_value": str(max(1, field_int(length_value, 5))),
                "length_unit": "microcycles",
                "deload_microcycles": str(max(0, field_int(deload_count, 1))),
                "start_rir": cycle.get("start_rir", "3"),
                "end_rir": cycle.get("end_rir", "1"),
                "deload_rir": cycle.get("deload_rir", "4"),
                "rir_lock": "0" if (advanced and unlock_rir.value) else "1",
                "rest_timer_lock": "1" if rest_timer_lock.value else "0",
                "show_last_week_reps": "0",
                "setup_complete": "1",
                "active": "1",
            }

        def save_cycle(e):
            valid = True
            validation_fields = [name_field, start_field, length_value, deload_count]
            if advanced:
                validation_fields.append(micro_days)
            for field in validation_fields:
                self.clear_field_invalid(field)

            try:
                datetime.fromisoformat((start_field.value or "").strip()).date()
            except ValueError:
                self.mark_field_invalid(start_field)
                valid = False
            if advanced and field_int(micro_days, 0) <= 0:
                self.mark_field_invalid(micro_days)
                valid = False
            if field_int(length_value, 0) <= 0:
                self.mark_field_invalid(length_value)
                valid = False
            if not (name_field.value or "").strip():
                self.mark_field_invalid(name_field)
                valid = False

            config = build_config()
            if valid:
                status = storage.mesocycle_status(config)
                if field_int(deload_count, 0) >= status["total_microcycles"]:
                    self.mark_field_invalid(deload_count)
                    valid = False
                else:
                    self.clear_field_invalid(deload_count)

            planned = any(
                str(planner_state.get(day, "") or "").strip()
                for day in range(1, current_micro_days() + 1)
            )
            if not planned:
                planner_error.visible = True
                valid = False

            if not valid:
                self.page.update()
                return

            config["cycle_id"] = cycle.get("cycle_id", "")
            cycle_id = storage.save_mesocycle(config)
            storage.save_mesocycle_day_schedule(
                cycle_id,
                planner_state,
                microcycle_days=current_micro_days(),
            )
            self.pending_cycle_setup_id = None
            self.notify("Mesocycle saved." if active else "Mesocycle started.")
            self.show_mesocycle()

        def end_cycle(e):
            if active:
                storage.end_mesocycle(active.get("cycle_id", ""))
                self.notify("Mesocycle ended.")
                self.show_mesocycle()

        controls = [
            ft.Row(
                controls=[
                    ft.Text(
                        cycle.get("name", "Cycle") if active else "New cycle",
                        size=self.fs(22),
                        weight=ft.FontWeight.BOLD,
                        expand=True,
                        max_lines=1,
                        overflow=ft.TextOverflow.ELLIPSIS,
                    ),
                    ft.IconButton(
                        icon=ft.Icons.INFO_OUTLINE,
                        icon_size=self.ui(20),
                        width=self.ui(34),
                        height=self.ui(34),
                        padding=0,
                        tooltip="Mesocycle guide",
                        on_click=lambda e: self.show_mesocycle_info(),
                    ),
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            name_field,
            ft.Row(
                controls=[length_wrapper, deload_wrapper],
                spacing=self.ui(8),
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            start_field,
        ]

        if advanced:
            controls.extend([
                ft.Text("Advanced", size=self.fs(18), weight=ft.FontWeight.BOLD),
                micro_days,
                ft.Text("Cycle locks", size=self.fs(18), weight=ft.FontWeight.BOLD),
                ft.Row(
                    controls=[unlock_rir, rir_lock_info],
                    spacing=2,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Row(
                    controls=[rest_timer_lock, rest_lock_info],
                    spacing=2,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
            ])

        controls.append(self.mesocycle_rir_logging_card())

        controls.append(
            ft.Container(
                width=float("inf"),
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
                        planner_title,
                        planner_help,
                        planner_days,
                        planner_error,
                    ],
                    spacing=self.ui(7),
                ),
            )
        )
        if active:
            controls.extend([
                ft.Container(
                    width=float("inf"),
                    padding=ft.Padding(left=self.ui(10), top=self.ui(9), right=self.ui(10), bottom=self.ui(9)),
                    border=ft.Border.all(1, ft.Colors.GREY_700),
                    border_radius=self.rounding(),
                    ink=True,
                    on_click=lambda e: self.show_mesocycle_calendar(cycle.get("cycle_id", "")),
                    content=ft.Row(
                        controls=[
                            ft.Icon(ft.Icons.CALENDAR_MONTH),
                            ft.Text("View Cycle Calendar", expand=True, weight=ft.FontWeight.BOLD),
                            ft.Icon(ft.Icons.CHEVRON_RIGHT),
                        ]
                    ),
                ),
                self.cycle_heatmap(cycle),
            ])

        footer = [
            self.filled_button(
                "Save" if active else "Start",
                on_click=save_cycle,
                expand=True,
            )
        ]
        if active:
            footer.append(
                ft.OutlinedButton(content="End", on_click=end_cycle, style=self.button_style())
            )

        self.set_view(
            controls,
            footer=ft.Row(controls=footer, spacing=self.ui(10)),
            back_action=(self.show_mesocycle if active else None),
            root_back_to_active=(as_tab_root and not active),
        )

