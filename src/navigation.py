import ast
import asyncio
import math
import time
import uuid
from datetime import datetime

import flet as ft

import storage


class NavigationMixin:

    def bind_native_back(self):
        if self.page.views:
            view = self.page.views[0]
            view.on_confirm_pop = self.handle_native_back
            view.can_pop = True

    async def handle_native_back(self, e):
        action = self.native_back_action

        if action is None:
            await e.control.confirm_pop(True)
            return

        # The current View has can_pop=False, so Android Back reaches this
        # handler instead of immediately sending the app to the launcher.
        await e.control.confirm_pop(False)
        self.native_back_action = None
        action()

    def build_navigation(self):
        self.page.navigation_bar = ft.NavigationBar(
            selected_index=self.selected_tab,
            bgcolor=self.nav_surface_color(),
            indicator_shape=ft.RoundedRectangleBorder(
                radius=self.rounding()
            ),
            destinations=[
                ft.NavigationBarDestination(
                    icon=ft.Icons.FITNESS_CENTER_OUTLINED,
                    selected_icon=ft.Icons.FITNESS_CENTER,
                    label="Workout",
                ),
                ft.NavigationBarDestination(
                    icon=ft.Icons.HISTORY_OUTLINED,
                    selected_icon=ft.Icons.HISTORY,
                    label="History",
                ),
                ft.NavigationBarDestination(
                    icon=ft.Icons.REPEAT,
                    label="Cycle",
                ),
                ft.NavigationBarDestination(
                    icon=ft.Icons.FITNESS_CENTER,
                    selected_icon=ft.Icons.FITNESS_CENTER,
                    label="Rep Max",
                ),
                ft.NavigationBarDestination(
                    icon=ft.Icons.SETTINGS_OUTLINED,
                    selected_icon=ft.Icons.SETTINGS,
                    label="Settings",
                ),
            ],
            on_change=self.change_tab,
        )

    async def animate_background_layer(self, layer, target, generation):
        # Let the first frame arrive with the old color, then animate the same
        # Container to the new color. Container.animate interpolates bgcolor.
        await asyncio.sleep(0.03)
        if generation != self.background_transition_generation:
            return

        layer.bgcolor = target
        self.page.update()

        await asyncio.sleep(0.38)
        if generation != self.background_transition_generation:
            return

        self.page.bgcolor = target
        self.page.update()

    def set_view(
        self,
        controls,
        footer=None,
        header=None,
        floating=None,
        back_action=None,
        workout_clock=False,
        scroll_on_scroll=None,
        restore_scroll_offset=None,
        root_back_to_active=False,
        hide_active_return_bar=False,
    ):
        self.page.controls.clear()

        # Main tabs are roots, but while a workout is running Android Back from
        # History/Cycle/Rep Max/Settings should first return to that global
        # session.  The Workout list is deliberately excluded by callers so a
        # normal Workout -> Active -> Back -> Workout -> Back flow can still
        # exit naturally.
        if back_action is None and root_back_to_active and self.active_workout:
            back_action = self.return_to_active_workout_from_root

        self.native_back_action = back_action
        self.workout_clock_visible = workout_clock

        # Android system Back must not auto-pop when this screen has an
        # in-app parent. Flet then raises on_confirm_pop, where we perform the
        # requested navigation ourselves.
        if self.page.views:
            root_view = self.page.views[0]
            root_view.on_confirm_pop = self.handle_native_back
            root_view.can_pop = back_action is None

        padding = self.ui(self.PAGE_PADDING)
        spacing = self.ui(self.density())

        scroll_content = ft.Column(
            controls=controls,
            spacing=spacing,
            expand=True,
            scroll=ft.Scrollbar(
                thumb_visibility=False,
                track_visibility=False,
                interactive=False,
            ),
            on_scroll=scroll_on_scroll,
            scroll_interval=0 if scroll_on_scroll is not None else 10,
        )

        if floating is not None:
            content_body = ft.Stack(
                controls=[
                    scroll_content,
                    floating,
                ],
                expand=True,
            )
        else:
            content_body = scroll_content

        content = ft.Container(
            content=content_body,
            padding=ft.Padding(
                left=padding,
                top=padding,
                right=padding,
                bottom=padding,
            ),
            expand=True,
        )

        page_controls = []

        if header is not None:
            page_controls.append(header)

        page_controls.append(content)

        # Keep an in-progress workout globally reachable even while the user is
        # browsing another tab or a nested editor.  This is intentionally not
        # shown on the active workout itself.
        if self.active_workout and not hide_active_return_bar:
            page_controls.append(self.active_workout_return_bar())

        if footer is not None:
            page_controls.append(
                ft.Container(
                    content=footer,
                    padding=ft.Padding(
                        left=padding,
                        top=self.ui(8),
                        right=padding,
                        bottom=self.ui(12),
                    ),
                )
            )

        base = ft.Column(
            controls=page_controls,
            spacing=0,
            expand=True,
        )

        target_background = (
            self.current_background_color or self.background_color()
        )
        start_background = (
            self.pending_background_from
            if self.pending_background_from is not None
            else target_background
        )
        transition_generation = self.background_transition_generation

        background_layer = ft.Container(
            expand=True,
            bgcolor=start_background,
            animate=350,
        )

        app_stack = ft.Stack(
            controls=[
                background_layer,
                base,
                self.timer_popup,
            ],
            expand=True,
        )

        self.page.add(
            ft.SafeArea(
                content=app_stack,
                expand=True,
                avoid_intrusions_top=True,
                avoid_intrusions_left=True,
                avoid_intrusions_right=True,
                avoid_intrusions_bottom=False,
            )
        )

        self.page.update()

        if restore_scroll_offset is not None and float(restore_scroll_offset or 0) > 0:
            self.page.run_task(
                self.restore_scroll_control,
                scroll_content,
                float(restore_scroll_offset),
            )

        if (
            self.pending_background_from is not None
            and start_background != target_background
        ):
            self.pending_background_from = None
            self.page.run_task(
                self.animate_background_layer,
                background_layer,
                target_background,
                transition_generation,
            )
        else:
            self.page.bgcolor = target_background

    def active_workout_return_bar(self):
        """Compact global entry point back into the in-progress workout."""
        if not self.active_workout:
            return ft.Container(height=0)

        workout_name = str(
            self.active_workout.get("workout_name", "Active workout")
            or "Active workout"
        )
        secondary = "ACTIVE"

        return ft.Container(
            width=float("inf"),
            bgcolor=ft.Colors.with_opacity(0.18, self.accent_color()),
            border=ft.Border(
                top=ft.BorderSide(
                    1,
                    ft.Colors.with_opacity(0.42, self.accent_color()),
                )
            ),
            padding=ft.Padding(
                left=self.ui(14),
                top=self.ui(7),
                right=self.ui(10),
                bottom=self.ui(7),
            ),
            ink=True,
            tooltip="Return to active workout",
            on_click=lambda e: self.return_to_active_workout_from_root(),
            content=ft.Row(
                controls=[
                    ft.Icon(
                        ft.Icons.FITNESS_CENTER,
                        size=self.ui(18),
                        color=self.accent_color(),
                    ),
                    ft.Text(
                        workout_name,
                        size=self.fs(13),
                        weight=ft.FontWeight.BOLD,
                        max_lines=1,
                        overflow=ft.TextOverflow.ELLIPSIS,
                        expand=True,
                    ),
                    ft.Text(
                        secondary,
                        size=self.fs(10),
                        weight=ft.FontWeight.BOLD,
                        color=self.accent_color(),
                    ),
                    ft.Icon(
                        ft.Icons.CHEVRON_RIGHT,
                        size=self.ui(20),
                        color=self.accent_color(),
                    ),
                ],
                spacing=self.ui(7),
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

    def return_to_active_workout_from_root(self):
        """Return from a main/root screen to the global active session.

        The next Android Back from the active workout is allowed to exit rather
        than bouncing the user back to the root tab they just left.
        """
        if not self.active_workout:
            self.show_saved_workouts()
            return

        self.active_workout_back_mode = "exit"
        self.show_active_workout()

    async def restore_scroll_control(self, control, offset):
        """Restore a rebuilt scrollable view without visible animation."""
        await control.scroll_to(offset=max(0.0, float(offset or 0)), duration=0)

    def change_tab(self, e):
        if self.active_workout and self.set_controls:
            self.capture_active_controls()

        next_tab = e.control.selected_index
        if self.pending_cycle_setup_id and next_tab != 2:
            self.finish_pending_cycle_setup()

        self.selected_tab = next_tab

        if self.selected_tab == 0:
            if self.active_workout:
                # Selecting Workout from the bottom bar opens the global active
                # session directly; Back from there should exit, not manufacture
                # an extra parent screen.
                self.active_workout_back_mode = "exit"
            self.show_workout_tab()
        elif self.selected_tab == 1:
            self.show_workout_history()
        elif self.selected_tab == 2:
            self.show_mesocycle()
        elif self.selected_tab == 3:
            self.show_rep_max_table(as_tab=True)
        else:
            self.show_settings()

    def finish_pending_cycle_setup(self):
        cycle_id = self.pending_cycle_setup_id
        if not cycle_id:
            return True

        # A new mesocycle is not committed until the user explicitly presses
        # Start on the calendar page. Leaving setup before that cancels it.
        storage.delete_mesocycle(cycle_id)
        self.pending_cycle_setup_id = None
        self.notify("Mesocycle setup canceled before Start was pressed.")
        return False

    def leave_mesocycle_calendar(self):
        self.finish_pending_cycle_setup()
        self.show_mesocycle()

    def notify(self, message):
        self.page.show_dialog(
            ft.SnackBar(content=ft.Text(message))
        )

    def open_name_picker(
        self,
        title,
        values_getter,
        on_select,
        *,
        allow_new=False,
        add_new=None,
    ):
        search = self.text_field(
            label="Search",
            autofocus=True,
            dense=True,
        )

        results = ft.ListView(spacing=self.ui(4), expand=True)

        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text(title),
            content=ft.Container(
                width=self.dialog_width(420),
                height=self.dialog_height(420),
                clip_behavior=ft.ClipBehavior.HARD_EDGE,
                content=ft.Column(
                    controls=[
                        search,
                        ft.Text(
                            "Fuzzy search · start with a space for exact text",
                            size=self.fs(10.5),
                            italic=True,
                        ),
                        ft.Container(content=results, expand=True),
                    ],
                    expand=True,
                    spacing=self.ui(6),
                ),
            ),
            actions=[
                self.outlined_button(
                    "Cancel",
                    on_click=lambda e: self.close_dialog(dialog),
                )
            ],
        )

        def choose(value):
            self.close_dialog(dialog)
            on_select(value)

        def clean_for_add(raw):
            raw = str(raw or "")
            if raw.startswith(" "):
                raw = raw[1:]
            return raw.strip()

        def render(e=None):
            raw_query = search.value or ""
            query_for_add = clean_for_add(raw_query)
            values = values_getter(raw_query)

            results.controls.clear()

            for value in values[:60]:
                results.controls.append(
                    ft.Container(
                        padding=ft.Padding(left=self.ui(10), top=self.ui(8), right=self.ui(10), bottom=self.ui(8)),
                        border=ft.Border.all(
                            1,
                            ft.Colors.with_opacity(0.30, self.accent_color()),
                        ),
                        border_radius=self.rounding(),
                        ink=True,
                        on_click=lambda event, selected=value: choose(selected),
                        content=ft.Text(value),
                    )
                )

            if (
                allow_new
                and query_for_add
                and all(value.casefold() != query_for_add.casefold() for value in values)
            ):
                results.controls.append(
                    ft.Container(
                        padding=self.ui(10),
                        bgcolor=ft.Colors.with_opacity(0.14, self.accent_color()),
                        border_radius=self.rounding(),
                        ink=True,
                        on_click=lambda event: add_and_choose(query_for_add),
                        content=ft.Text(
                            f'Add new: "{query_for_add}"',
                            weight=ft.FontWeight.BOLD,
                        ),
                    )
                )

            if not results.controls:
                results.controls.append(ft.Text("No matches."))

            self.page.update()

        def add_and_choose(value):
            if add_new is not None:
                add_new(value)
            choose(value)

        search.on_change = render
        render()
        self.page.show_dialog(dialog)

    def close_dialog(self, dialog):
        dialog.open = False
        self.page.update()

    def open_exercise_picker(self, on_select):
        self.open_name_picker(
            "Exercise",
            lambda query: storage.catalog_exercises(query),
            on_select,
            allow_new=True,
            add_new=storage.add_catalog_exercise,
        )

    def open_set_type_picker(self, current, on_select):
        self.open_name_picker(
            "Set type",
            lambda query: storage.set_types(query),
            on_select,
            allow_new=False,
        )

    def format_recent_datetime(self, value, include_time=True):
        try:
            moment = datetime.fromisoformat(value)
        except (TypeError, ValueError):
            return value or ""

        date_text = f"{moment.day} {moment.strftime('%B')}"

        if moment.year != datetime.now().year:
            date_text += f" {moment.year}"

        if not include_time:
            return date_text

        # Keep the user's existing unit convention:
        # kg -> 24-hour clock, lb -> 12-hour clock.
        if self.settings.get("unit", "kg") == "lb":
            hour = moment.strftime("%I").lstrip("0") or "12"
            suffix = moment.strftime("%p")

            if moment.minute == 0:
                time_text = f"{hour}{suffix}"
            else:
                time_text = f"{hour}:{moment.minute:02d}{suffix}"
        else:
            time_text = moment.strftime("%H:%M")

        return f"{date_text}, {time_text}"

    def edit_workout_from_workout_tab(self, workout_id):
        workout = storage.read_workout(workout_id)

        if workout is None:
            self.notify("This workout template no longer exists.")
            return

        self.selected_tab = 0
        self.page.navigation_bar.selected_index = 0
        self.show_edit(workout_id)
