import ast
import asyncio
import math
import time
import uuid
from datetime import datetime

import flet as ft

import storage


class SettingsMixin:
    async def export_user_data(self, e=None):
        try:
            archive_bytes = storage.export_data_zip_bytes()
            saved_path = await ft.FilePicker().save_file(
                dialog_title="Export GYMER data",
                file_name="gymer_data.zip",
                file_type=ft.FilePickerFileType.CUSTOM,
                allowed_extensions=["zip"],
                src_bytes=archive_bytes,
            )
        except Exception as exc:
            self.notify(f"Export failed: {exc}")
            return

        if saved_path:
            self.notify("GYMER data exported.")

    async def import_user_data(self, e=None):
        try:
            picked = await ft.FilePicker().pick_files(
                dialog_title="Import GYMER data",
                file_type=ft.FilePickerFileType.CUSTOM,
                allowed_extensions=["zip"],
                allow_multiple=False,
                with_data=True,
            )
        except Exception as exc:
            self.notify(f"Import failed: {exc}")
            return

        if not picked:
            return

        selected = picked[0]
        archive_bytes = selected.bytes
        if archive_bytes is None:
            self.notify("Could not read the selected ZIP file.")
            return

        self.confirm_user_data_import(archive_bytes, selected.name)

    def confirm_user_data_import(self, archive_bytes, file_name):
        def do_import(e):
            self.close_dialog(dialog)
            try:
                imported = storage.import_data_zip_bytes(archive_bytes)
            except Exception as exc:
                self.notify(f"Import failed: {exc}")
                return

            # Discard stale in-memory controls and reload all state from the
            # imported CSV files. Timers/tasks use generation counters, so bump
            # them before rebuilding the Settings page.
            self.timer_generation += 1
            self.workout_clock_generation += 1
            self.set_controls = []
            self.numeric_field_kinds = {}
            self.numeric_warning_fields = {}
            self.active_workout = storage.load_active_workout()
            self.settings = storage.read_settings()
            self.apply_settings(update_page=False)
            self.show_settings(force_root=True)
            self.notify(f"Imported {len(imported)} CSV files from {file_name}.")

        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text("Import GYMER data?"),
            content=ft.Text(
                "This replaces the app's current CSV data with the selected "
                "backup. workout_set_templates.csv is not imported and will "
                "be regenerated automatically."
            ),
            actions=[
                self.outlined_button("Cancel", on_click=lambda e: self.close_dialog(dialog)),
                self.filled_button("Import", on_click=do_import),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.show_dialog(dialog)


    def show_settings(self, force_root=False, preserve_scroll=False):
        if not force_root and self.settings_subpage == "appearance":
            self.show_appearance_settings()
            return

        self.settings_subpage = "main"
        if not preserve_scroll:
            self.settings_main_scroll_offset = 0.0
        self.page.navigation_bar.selected_index = 4
        self.selected_tab = 4
        self.settings = storage.read_settings()

        unit = self.settings.get("unit", "kg")
        show_recent = self.settings.get("show_recent", "1")
        track_rir = self.settings.get("track_rir", "1")
        dim_completed_sets = self.settings.get("dim_completed_sets", "1")
        collapse_completed_exercises = self.settings.get("collapse_completed_exercises", "1")
        timer_tracker_mode = self.settings.get("timer_tracker_mode", "both")
        planned_rest_display_mode = self.settings.get(
            "planned_rest_display_mode",
            "hide",
        )
        update_following_set_defaults = self.settings.get(
            "update_following_set_defaults",
            "0",
        )
        enter_completes_set = self.settings.get("enter_completes_set", "1")
        enter_moves_to_next_set = self.settings.get("enter_moves_to_next_set", "0")
        backspace_moves_to_previous_set = self.settings.get(
            "backspace_moves_to_previous_set",
            "0",
        )
        advanced_mode = self.settings.get("advanced_mode", "0")
        show_previous_reps = self.settings.get("show_previous_reps", "0")
        require_previous_sets_completed = self.settings.get(
            "require_previous_sets_completed",
            "0",
        )
        timer_tap_action = self.settings.get("timer_tap_action", "switch")
        default_timer_display_mode = self.settings.get(
            "default_timer_display_mode",
            "elapsed",
        )

        def save_setting(key, value, rerender=True):
            value = str(value)
            if key == "unit":
                old_unit = self.settings.get("unit", "kg")
                if old_unit != value:
                    # Persist whatever is currently typed before conversion, then
                    # reload the active workout immediately in the new unit. This
                    # includes real values and historical ghost/reference weights,
                    # so an in-progress session follows kg <-> lb changes instead
                    # of retaining stale numbers until the next workout.
                    if self.active_workout and self.set_controls:
                        self.capture_active_controls()
                    storage.convert_all_weights(old_unit, value)
                    self.active_workout = storage.load_active_workout()

                    # Warning keys contain the displayed numeric value. They are no
                    # longer valid after a unit conversion and could otherwise keep
                    # a converted value orange for the wrong reason.
                    self.numeric_warning_fields.clear()
                    self.numeric_warning_acknowledged.clear()

            self.settings[key] = value
            storage.save_settings(self.settings)
            self.apply_settings()
            if rerender:
                self.show_settings(preserve_scroll=True)

        def compact_choice(label, selected, value, key):
            make = self.filled_button if selected else self.outlined_button
            return make(
                label,
                width=self.ui(88),
                on_click=lambda e: save_setting(key, value),
            )

        def planned_rest_choice(label, selected, value):
            return ft.Container(
                expand=True,
                height=self.ui(36),
                alignment=ft.Alignment.CENTER,
                border=ft.Border.all(
                    1.4 if selected else 1,
                    self.accent_color() if selected else ft.Colors.GREY_700,
                ),
                border_radius=self.rounding(),
                bgcolor=(
                    ft.Colors.with_opacity(0.22, self.accent_color())
                    if selected
                    else None
                ),
                ink=True,
                on_click=lambda e: save_setting(
                    "planned_rest_display_mode",
                    value,
                ),
                content=ft.Text(
                    label,
                    size=self.fs(11),
                    weight=(
                        ft.FontWeight.BOLD
                        if selected
                        else ft.FontWeight.W_500
                    ),
                    text_align=ft.TextAlign.CENTER,
                    max_lines=1,
                    no_wrap=True,
                ),
            )

        def timer_mode_choice(label, selected, value):
            return ft.Container(
                expand=True,
                height=self.ui(34),
                alignment=ft.Alignment.CENTER,
                border=ft.Border.all(
                    1.4 if selected else 1,
                    self.accent_color() if selected else ft.Colors.GREY_700,
                ),
                border_radius=self.rounding(),
                bgcolor=(
                    ft.Colors.with_opacity(0.22, self.accent_color())
                    if selected
                    else None
                ),
                ink=True,
                on_click=lambda e: save_setting(
                    "timer_tracker_mode",
                    value,
                ),
                content=ft.Text(
                    label,
                    size=self.fs(11),
                    weight=(
                        ft.FontWeight.BOLD
                        if selected
                        else ft.FontWeight.W_500
                    ),
                    text_align=ft.TextAlign.CENTER,
                    max_lines=1,
                    no_wrap=True,
                ),
            )

        def advanced_choice(label, selected, value, key, width=self.ui(110)):
            make = self.filled_button if selected else self.outlined_button
            return make(
                label,
                width=width,
                on_click=lambda e: save_setting(key, value),
            )

        default_sets = self.text_field(
            value=self.settings.get("default_sets", "3"),
            width=self.ui(90),
            dense=True,
            text_align=ft.TextAlign.CENTER,
            keyboard_type=ft.KeyboardType.NUMBER,
            numeric_kind="count",
        )

        def save_default_sets(e):
            if not self.normalize_numeric_control(
                default_sets,
                kind="count",
                allow_empty=False,
            ):
                self.page.update()
                return
            self.settings["default_sets"] = default_sets.value
            storage.save_settings(self.settings)

        default_sets.on_change = lambda e: None
        default_sets.on_blur = save_default_sets

        default_rest = self.text_field(
            value=storage.format_duration(self.settings.get("default_rest_seconds", "180")),
            hint_text="3:00",
            width=self.ui(90),
            dense=True,
            text_align=ft.TextAlign.CENTER,
        )

        def save_default_rest(e):
            seconds = storage.parse_duration(
                default_rest.value,
                default=int(self.settings.get("default_rest_seconds", "180") or 180),
            )
            self.settings["default_rest_seconds"] = str(seconds)
            storage.save_settings(self.settings)
            default_rest.value = storage.format_duration(seconds)
            self.page.update()

        default_rest.on_blur = save_default_rest
        self.chain_text_fields(default_sets, default_rest)

        weight_increment_fields = {}
        weight_increment_rows = []

        def save_weight_increment(field, key):
            if not self.normalize_numeric_control(
                field, kind="weight", allow_empty=False
            ):
                self.page.update()
                return
            self.settings[key] = field.value
            storage.save_settings(self.settings)
            self.page.update()

        for equipment_type in storage.EQUIPMENT_TYPES:
            key = storage.weight_increment_setting_key(equipment_type, unit)
            fallback = storage.format_increment(
                storage.default_weight_increment(equipment_type, unit)
            )
            field = self.text_field(
                value=self.settings.get(key, fallback),
                width=self.ui(104),
                dense=True,
                text_align=ft.TextAlign.CENTER,
                keyboard_type=ft.KeyboardType.NUMBER,
                numeric_kind="weight",
            )
            field.on_change = lambda e: None
            field.on_blur = (
                lambda e, target=field, setting_key=key:
                save_weight_increment(target, setting_key)
            )
            weight_increment_fields[equipment_type] = field
            weight_increment_rows.append(
                ft.Row(
                    controls=[
                        ft.Text(equipment_type, expand=True),
                        field,
                        ft.Text(unit, size=self.fs(11)),
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                )
            )

        def reset_weight_increments(e):
            self.settings = storage.reset_weight_increment_defaults(self.settings)
            self.show_settings(preserve_scroll=True)

        appearance_link = ft.Container(
            width=float("inf"),
            padding=ft.Padding(left=self.ui(12), top=self.ui(11), right=self.ui(8), bottom=self.ui(11)),
            border=ft.Border.all(1, ft.Colors.GREY_700),
            border_radius=self.rounding(),
            ink=True,
            on_click=lambda e: self.show_appearance_settings(),
            content=ft.Row(
                controls=[
                    ft.Icon(ft.Icons.PALETTE_OUTLINED),
                    ft.Column(
                        controls=[
                            ft.Text("Appearance", size=self.fs(17), weight=ft.FontWeight.BOLD),
                            ft.Text("Theme, colors, density and system bar", size=self.fs(11)),
                        ],
                        spacing=1,
                        expand=True,
                    ),
                    ft.Icon(ft.Icons.CHEVRON_RIGHT),
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

        rir_info = ft.IconButton(
            icon=ft.Icons.INFO_OUTLINE,
            icon_size=self.ui(18),
            width=self.ui(32),
            height=self.ui(32),
            padding=0,
            tooltip="What is RIR?",
            on_click=lambda e: self.show_rir_info(),
        )

        advanced_panel = ft.Column(
            visible=advanced_mode == "1",
            spacing=self.ui(8),
            controls=[
                ft.Divider(),
                ft.Text(
                    "Advanced Workout Controls",
                    size=self.fs(18),
                    weight=ft.FontWeight.BOLD,
                ),
                ft.Text("Require Previous Set", weight=ft.FontWeight.BOLD),
                ft.Row(
                    controls=[
                        compact_choice(
                            "On",
                            require_previous_sets_completed == "1",
                            "1",
                            "require_previous_sets_completed",
                        ),
                        compact_choice(
                            "Off",
                            require_previous_sets_completed == "0",
                            "0",
                            "require_previous_sets_completed",
                        ),
                    ],
                    spacing=self.ui(8),
                ),
                ft.Text(
                    "When on, a set can only be completed after earlier sets "
                    "of that same exercise are complete. Other exercises do not matter.",
                    size=self.fs(11),
                ),
                ft.Text("Update Following Set Defaults", weight=ft.FontWeight.BOLD),
                ft.Row(
                    controls=[
                        compact_choice("On", update_following_set_defaults == "1", "1", "update_following_set_defaults"),
                        compact_choice("Off", update_following_set_defaults == "0", "0", "update_following_set_defaults"),
                    ],
                    spacing=self.ui(8),
                ),
                ft.Text(
                    "When on, completing a set refreshes untouched later-set defaults.",
                    size=self.fs(11),
                ),
                ft.Text("Show Previous Reps in Mesocycles", weight=ft.FontWeight.BOLD),
                ft.Row(
                    controls=[
                        compact_choice("On", show_previous_reps == "1", "1", "show_previous_reps"),
                        compact_choice("Off", show_previous_reps == "0", "0", "show_previous_reps"),
                    ],
                    spacing=self.ui(8),
                ),
                ft.Text(
                    "Off by default. When enabled, historical rep counts may appear "
                    "as workout placeholders during a mesocycle.",
                    size=self.fs(11),
                ),
                ft.Text("Set Keyboard Navigation", size=self.fs(17), weight=ft.FontWeight.BOLD),
                ft.Text("Enter Completes Set", weight=ft.FontWeight.BOLD),
                ft.Row(
                    controls=[
                        compact_choice("On", enter_completes_set == "1", "1", "enter_completes_set"),
                        compact_choice("Off", enter_completes_set == "0", "0", "enter_completes_set"),
                    ],
                    spacing=self.ui(8),
                ),
                ft.Text(
                    "Enter on the last editable box can complete the set. This shortcut never starts or resumes the workout clock.",
                    size=self.fs(11),
                ),
                ft.Text("Enter Moves to Next Set", weight=ft.FontWeight.BOLD),
                ft.Row(
                    controls=[
                        compact_choice("On", enter_moves_to_next_set == "1", "1", "enter_moves_to_next_set"),
                        compact_choice("Off", enter_moves_to_next_set == "0", "0", "enter_moves_to_next_set"),
                    ],
                    spacing=self.ui(8),
                ),
                ft.Text("Backspace Moves to Previous Set", weight=ft.FontWeight.BOLD),
                ft.Row(
                    controls=[
                        compact_choice("On", backspace_moves_to_previous_set == "1", "1", "backspace_moves_to_previous_set"),
                        compact_choice("Off", backspace_moves_to_previous_set == "0", "0", "backspace_moves_to_previous_set"),
                    ],
                    spacing=self.ui(8),
                ),
                ft.Text("Tap Floating Timer", weight=ft.FontWeight.BOLD),
                ft.Row(
                    controls=[
                        advanced_choice("Switch view", timer_tap_action == "switch", "switch", "timer_tap_action", 120),
                        advanced_choice("Hide", timer_tap_action == "hide", "hide", "timer_tap_action", 88),
                    ],
                    spacing=self.ui(8),
                ),
                ft.Text(
                    "Hide dismisses the floating rest timer until the next rest timer starts; timing continues in the background.",
                    size=self.fs(11),
                ),
                ft.Text("Default Rest Timer View", weight=ft.FontWeight.BOLD),
                ft.Row(
                    controls=[
                        advanced_choice("Elapsed", default_timer_display_mode == "elapsed", "elapsed", "default_timer_display_mode", 100),
                        advanced_choice("Countdown", default_timer_display_mode == "countdown", "countdown", "default_timer_display_mode", 112),
                    ],
                    spacing=self.ui(8),
                ),
            ],
        )

        controls = [
            ft.Text("Settings", size=self.fs(30), weight=ft.FontWeight.BOLD),
            appearance_link,
            ft.Divider(),
            ft.Text("Advanced Mode", size=self.fs(20), weight=ft.FontWeight.BOLD),
            ft.Row(
                controls=[
                    compact_choice("On", advanced_mode == "1", "1", "advanced_mode"),
                    compact_choice("Off", advanced_mode == "0", "0", "advanced_mode"),
                ],
                spacing=self.ui(8),
            ),
            ft.Text(
                "Off keeps the recommended workout behavior. Turn this on to customize keyboard navigation, set order, Rep Max behavior, and timer interactions.",
                size=self.fs(11),
            ),
            ft.Divider(),
            ft.Text("Workout", size=self.fs(20), weight=ft.FontWeight.BOLD),
            ft.Text("Units", weight=ft.FontWeight.BOLD),
            ft.Row(
                controls=[
                    compact_choice("kg", unit == "kg", "kg", "unit"),
                    compact_choice("lb", unit == "lb", "lb", "unit"),
                ],
                spacing=self.ui(8),
            ),
            ft.Text("Default Number of Sets", weight=ft.FontWeight.BOLD),
            default_sets,
            ft.Text("Default Rest Timer", weight=ft.FontWeight.BOLD),
            default_rest,
            ft.Text("Live Rest Timer", weight=ft.FontWeight.BOLD),
            ft.Row(
                controls=[
                    timer_mode_choice(
                        "Both",
                        timer_tracker_mode == "both",
                        "both",
                    ),
                    timer_mode_choice(
                        "Floating",
                        timer_tracker_mode == "floating",
                        "floating",
                    ),
                    timer_mode_choice(
                        "Near set",
                        timer_tracker_mode == "nearset",
                        "nearset",
                    ),
                    timer_mode_choice(
                        "Off",
                        timer_tracker_mode == "off",
                        "off",
                    ),
                ],
                spacing=self.ui(4),
            ),
            ft.Text("Planned Rest Labels", weight=ft.FontWeight.BOLD),
            ft.Row(
                controls=[
                    planned_rest_choice(
                        "Hide",
                        planned_rest_display_mode == "hide",
                        "hide",
                    ),
                    planned_rest_choice(
                        "Smart",
                        planned_rest_display_mode == "smart",
                        "smart",
                    ),
                    planned_rest_choice(
                        "Always",
                        planned_rest_display_mode == "always",
                        "always",
                    ),
                ],
                spacing=self.ui(8),
            ),
            ft.Text(
                "Hide is the default. Smart only shows planned rest when an exercise uses different rest times or a special set type; Always shows it beside every set.",
                size=self.fs(11),
            ),
            ft.Row(
                controls=[
                    ft.Text(
                        "Track RIR",
                        weight=ft.FontWeight.BOLD,
                        expand=True,
                    ),
                    rir_info,
                ],
                spacing=self.ui(4),
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            ft.Row(
                controls=[
                    compact_choice("On", track_rir == "1", "1", "track_rir"),
                    compact_choice("Off", track_rir == "0", "0", "track_rir"),
                ],
                spacing=self.ui(8),
            ),
            ft.Text(
                "Turn this off if you do not want to rate effort after each set. "
                "Weight and reps will still be tracked normally.",
                size=self.fs(11),
            ),
            advanced_panel,
            ft.Text("Dim Completed Sets", weight=ft.FontWeight.BOLD),
            ft.Row(
                controls=[
                    compact_choice("On", dim_completed_sets == "1", "1", "dim_completed_sets"),
                    compact_choice("Off", dim_completed_sets == "0", "0", "dim_completed_sets"),
                ],
                spacing=self.ui(8),
            ),
            ft.Text("Adds a subtle grey tint to completed set rows.", size=self.fs(11)),
            ft.Text("Collapse Completed Exercises", weight=ft.FontWeight.BOLD),
            ft.Row(
                controls=[
                    compact_choice("On", collapse_completed_exercises == "1", "1", "collapse_completed_exercises"),
                    compact_choice("Off", collapse_completed_exercises == "0", "0", "collapse_completed_exercises"),
                ],
                spacing=self.ui(8),
            ),
            ft.Text(
                "Automatically folds an exercise after all of its sets are complete. Use the chevron to reopen it.",
                size=self.fs(11),
            ),
            ft.Text("Show Recent Workouts", weight=ft.FontWeight.BOLD),
            ft.Row(
                controls=[
                    compact_choice("On", show_recent == "1", "1", "show_recent"),
                    compact_choice("Off", show_recent == "0", "0", "show_recent"),
                ],
                spacing=self.ui(8),
            ),
            ft.Divider(),
            ft.Text("Progression Weight Increments", size=self.fs(20), weight=ft.FontWeight.BOLD),
            ft.Text(
                "These are the default smallest available jumps. Each exercise can override its own increment in Exercise Database → Details.",
                size=self.fs(11),
            ),
            *weight_increment_rows,
            ft.Text(
                (
                    "Barbell default: 10 lb total (+5/+5). "
                    if unit == "lb"
                    else "Barbell default: 5 kg total (+2.5/+2.5). "
                )
                + "Dumbbell is per dumbbell; Plate loaded is total logged load; "
                + "Weight-stack machine uses the displayed stack value.",
                size=self.fs(10),
            ),
            self.outlined_button(
                "Reset Weight Increments",
                on_click=reset_weight_increments,
            ),
            ft.Divider(),
            ft.Text("Databases", size=self.fs(20), weight=ft.FontWeight.BOLD),
            ft.Row(
                controls=[
                    self.filled_button(
                        "Exercise Database",
                        on_click=lambda e: self.show_exercise_database(),
                        expand=True,
                    ),
                    self.filled_button(
                        "Rep Max Table",
                        on_click=lambda e: self.show_rep_max_table(
                            from_settings=True,
                        ),
                        expand=True,
                    ),
                ],
                spacing=self.ui(8),
            ),
            self.filled_button(
                "Set Type Database",
                on_click=lambda e: self.show_set_type_database(),
            ),
            ft.Divider(),
            ft.Text("Data", size=self.fs(20), weight=ft.FontWeight.BOLD),
            ft.Text(
                "Export or restore your data as one ZIP of normal CSV files.",
                size=self.fs(11),
            ),
            ft.Row(
                controls=[
                    self.filled_button(
                        "Export ZIP",
                        on_click=self.export_user_data,
                        expand=True,
                    ),
                    self.outlined_button(
                        "Import ZIP",
                        on_click=self.import_user_data,
                        expand=True,
                    ),
                ],
                spacing=self.ui(8),
            ),
            ft.Text(
                "Workout set templates are intentionally excluded and are "
                "regenerated after import.",
                size=self.fs(10),
                italic=True,
            ),
            ft.Text(str(storage.data_path()), size=self.fs(10)),
        ]

        def remember_settings_scroll(e):
            self.settings_main_scroll_offset = max(0.0, float(e.pixels))

        self.set_view(
            controls,
            scroll_on_scroll=remember_settings_scroll,
            restore_scroll_offset=(
                getattr(self, "settings_main_scroll_offset", 0.0)
                if preserve_scroll
                else None
            ),
            root_back_to_active=True,
        )

    def leave_appearance_settings(self):
        self.settings_subpage = "main"
        self.show_settings(force_root=True)

    def show_appearance_settings(self, preserve_scroll=False):
        self.settings_subpage = "appearance"
        if not preserve_scroll:
            self.settings_appearance_scroll_offset = 0.0
        self.page.navigation_bar.selected_index = 4
        self.selected_tab = 4
        self.settings = storage.read_settings()

        accent = self.settings.get("accent_color", "purple")
        background = self.effective_background_name()
        theme_mode = self.settings.get("theme_mode", "system")
        density = self.settings.get("density", "normal")
        font_value = self.font_scale()
        rounding_value = self.rounding()
        base_set_spacing = self.base_set_spacing()

        def save_setting(key, value):
            old_background = self.current_background_color or self.background_color()
            self.settings[key] = str(value)
            storage.save_settings(self.settings)
            self.apply_settings(
                transition_from=(
                    old_background
                    if key in ("theme_mode", "background_color")
                    else None
                ),
                update_page=False,
            )
            self.show_appearance_settings(preserve_scroll=True)

        def choice(label, selected, value, key):
            return ft.Container(
                expand=True,
                height=self.ui(40),
                alignment=ft.Alignment.CENTER,
                border_radius=self.rounding(),
                border=ft.Border.all(
                    1.5 if selected else 1,
                    self.accent_color() if selected else ft.Colors.GREY_700,
                ),
                bgcolor=(
                    ft.Colors.with_opacity(0.16, self.accent_color())
                    if selected
                    else None
                ),
                ink=True,
                on_click=lambda e: save_setting(key, value),
                content=ft.Text(
                    label,
                    size=self.fs(12),
                    weight=ft.FontWeight.BOLD if selected else ft.FontWeight.W_500,
                    max_lines=1,
                    text_align=ft.TextAlign.CENTER,
                ),
            )

        accent_swatches = ft.Row(
            controls=[
                self.color_swatch(
                    name,
                    color,
                    accent == name,
                    lambda e, color_name=name: save_setting("accent_color", color_name),
                )
                for name, color in self.COLOR_MAP.items()
            ],
            wrap=True,
            spacing=self.ui(8),
        )

        background_swatches = ft.Row(
            controls=[
                self.color_swatch(
                    name,
                    self.background_color(name),
                    background == name,
                    lambda e, background_name=name: save_setting(
                        "background_color", background_name
                    ),
                )
                for name in self.BACKGROUND_MAP
            ],
            wrap=True,
            spacing=self.ui(8),
        )

        font_slider = ft.Slider(
            min=0.80,
            max=1.40,
            divisions=6,
            value=font_value,
            label="{value}×",
            on_change_end=lambda e: save_setting(
                "font_scale", f"{float(e.control.value):.2f}"
            ),
        )

        rounding_slider = ft.Slider(
            min=0,
            max=24,
            divisions=6,
            value=rounding_value,
            label="{value}px",
            on_change_end=lambda e: save_setting(
                "rounding", str(int(float(e.control.value)))
            ),
        )

        set_spacing_slider = ft.Slider(
            min=0,
            max=12,
            divisions=6,
            value=base_set_spacing,
            label="{value}px",
            on_change_end=lambda e: save_setting(
                "set_spacing", str(int(float(e.control.value)))
            ),
        )

        def reset_appearance(e):
            old_background = self.current_background_color or self.background_color()
            self.settings.update(
                {
                    "accent_color": "purple",
                    "font_scale": "1.0",
                    "rounding": "0",
                    "background_color": "auto",
                    "theme_mode": "system",
                    "density": "normal",
                    "set_spacing": "3",
                }
            )
            storage.save_settings(self.settings)
            self.apply_settings(
                transition_from=old_background,
                update_page=False,
            )
            self.show_appearance_settings(preserve_scroll=True)

        controls = [
            ft.Row(
                controls=[
                    ft.IconButton(
                        icon=ft.Icons.ARROW_BACK,
                        tooltip="Back to Settings",
                        on_click=lambda e: self.leave_appearance_settings(),
                    ),
                    ft.Text(
                        "Appearance",
                        size=self.fs(27),
                        weight=ft.FontWeight.BOLD,
                        expand=True,
                    ),
                ]
            ),
            ft.Text("Accent Color", weight=ft.FontWeight.BOLD),
            accent_swatches,
            ft.Text("Background Color", weight=ft.FontWeight.BOLD),
            background_swatches,
            ft.Text("Theme", weight=ft.FontWeight.BOLD),
            ft.Row(
                controls=[
                    choice("System", theme_mode == "system", "system", "theme_mode"),
                    choice("Dark", theme_mode == "dark", "dark", "theme_mode"),
                    choice("Light", theme_mode == "light", "light", "theme_mode"),
                ],
                spacing=self.ui(6),
            ),
            ft.Text(
                f"Font Size: {font_value:.2f}×",
                weight=ft.FontWeight.BOLD,
            ),
            font_slider,
            ft.Text(
                f"Roundedness: {rounding_value}px",
                weight=ft.FontWeight.BOLD,
            ),
            rounding_slider,
            ft.Text(
                f"Base Set Spacing: {base_set_spacing}px",
                weight=ft.FontWeight.BOLD,
            ),
            set_spacing_slider,
            ft.Text(
                "Layout Density",
                weight=ft.FontWeight.BOLD,
            ),
            ft.Row(
                controls=[
                    choice("Compact", density == "compact", "compact", "density"),
                    choice("Normal", density == "normal", "normal", "density"),
                    choice("Roomy", density == "roomy", "roomy", "density"),
                ],
                spacing=self.ui(6),
            ),
            ft.Text(
                f"Effective set gap: {self.set_spacing()}px",
                size=self.fs(11),
            ),
            self.outlined_button(
                "Reset Appearance",
                on_click=reset_appearance,
            ),
        ]

        def remember_appearance_scroll(e):
            self.settings_appearance_scroll_offset = max(0.0, float(e.pixels))

        self.set_view(
            controls,
            back_action=self.leave_appearance_settings,
            scroll_on_scroll=remember_appearance_scroll,
            restore_scroll_offset=(
                getattr(self, "settings_appearance_scroll_offset", 0.0)
                if preserve_scroll
                else None
            ),
        )

    def database_page(
        self,
        title,
        search_label,
        values_getter,
        contains,
        add_item,
        delete_item,
        edit_item=None,
    ):
        self.page.navigation_bar.selected_index = 4
        self.selected_tab = 4
        self.settings = storage.read_settings()

        search = self.text_field(
            label=search_label,
            hint_text="Type to filter or add a new item",
            expand=True,
            dense=True,
        )
        add_button = self.filled_button("Add", on_click=None)
        results = ft.Column(spacing=self.ui(4))

        accent_tint = ft.Colors.with_opacity(0.14, self.accent_color())
        neutral_base = ft.Colors.WHITE if self.is_dark_mode() else ft.Colors.BLACK
        background_tint = ft.Colors.with_opacity(0.045, neutral_base)

        def cleaned_query(raw):
            raw = str(raw or "")
            if raw.startswith(" "):
                raw = raw[1:]
            return raw.strip()

        def refresh(e=None):
            raw_query = search.value or ""
            add_value = cleaned_query(raw_query)
            matches = values_getter(raw_query)
            exact_exists = contains(add_value)

            results.controls.clear()

            if not matches:
                results.controls.append(ft.Container(padding=self.ui(12), content=ft.Text("No matching items.")))
            else:
                for index, name in enumerate(matches):
                    row_bg = accent_tint if index % 2 == 0 else background_tint
                    row_controls = [ft.Text(name, expand=True)]
                    if edit_item is not None:
                        row_controls.append(
                            ft.IconButton(
                                icon=ft.Icons.INFO_OUTLINE,
                                tooltip="Details",
                                on_click=lambda event, item_name=name: edit_item(item_name),
                            )
                        )
                    row_controls.append(
                        ft.IconButton(
                            icon=ft.Icons.DELETE_OUTLINE,
                            tooltip="Remove",
                            on_click=lambda event, item_name=name: remove(item_name),
                        )
                    )
                    results.controls.append(
                        ft.Container(
                            bgcolor=row_bg,
                            border_radius=self.rounding(),
                            padding=ft.Padding(left=self.ui(12), top=self.ui(8), right=self.ui(6), bottom=self.ui(8)),
                            content=ft.Row(
                                controls=row_controls,
                                vertical_alignment=ft.CrossAxisAlignment.CENTER,
                            ),
                        )
                    )

            add_button.visible = bool(add_value and not exact_exists)
            self.page.update()

        def add(e):
            value = cleaned_query(search.value)
            if not value:
                return
            add_item(value)
            search.value = ""
            refresh()

        def remove(value):
            delete_item(value)
            refresh()

        add_button.on_click = add
        search.on_change = refresh
        refresh()

        controls = [
            ft.Row(
                controls=[
                    ft.IconButton(
                        icon=ft.Icons.ARROW_BACK,
                        tooltip="Back to Settings",
                        on_click=lambda e: self.show_settings(),
                    ),
                    ft.Text(title, size=self.fs(27), weight=ft.FontWeight.BOLD, expand=True),
                ]
            ),
            ft.Text(
                "Fuzzy search · start with a space for exact text",
                size=self.fs(11),
                italic=True,
            ),
            ft.Row(
                controls=[search, add_button],
                spacing=self.ui(8),
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            results,
        ]

        self.set_view(controls, back_action=self.show_settings)

    def show_exercise_database(self):
        self.database_page(
            "Exercise Database",
            "Search exercises",
            storage.catalog_exercises,
            storage.catalog_contains,
            storage.add_catalog_exercise,
            storage.delete_catalog_exercise,
            edit_item=lambda name: self.show_exercise_details(
                name,
                back_action=self.show_exercise_database,
            ),
        )

    def show_set_type_database(self):
        self.database_page(
            "Set Type Database",
            "Search set types",
            storage.set_types,
            storage.set_type_contains,
            storage.add_set_type,
            storage.delete_set_type,
        )
