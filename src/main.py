import flet as ft

import storage
from ui_core import UICoreMixin
from timers import TimerMixin
from navigation import NavigationMixin
from history import HistoryMixin
from mesocycles import MesocycleMixin
from workouts import WorkoutMixin
from editor import EditorMixin
from settings_ui import SettingsMixin


class RepsApp(
    UICoreMixin,
    TimerMixin,
    NavigationMixin,
    HistoryMixin,
    MesocycleMixin,
    WorkoutMixin,
    EditorMixin,
    SettingsMixin,
):
    # Put the preferred defaults first so Settings presents them first.
    COLOR_MAP = {
        "purple": ft.Colors.PURPLE,
        "blue": ft.Colors.BLUE,
        "teal": ft.Colors.TEAL,
        "green": ft.Colors.GREEN,
        "orange": ft.Colors.ORANGE,
        "red": ft.Colors.RED,
        "pink": ft.Colors.PINK,
    }

    # Each background has a dark and light counterpart.  "auto" is kept as
    # a settings-only value: dark defaults to the first swatch (charcoal),
    # while light defaults to the second swatch (default).
    BACKGROUND_MAP = {
        "charcoal": ("#15171A", "#F3F4F6"),
        "default": ("#1C1B1F", "#FFFBFE"),
        "black": (ft.Colors.BLACK, ft.Colors.WHITE),
        "slate": ("#20252D", "#E9EDF2"),
        "navy": ("#111827", "#EEF2FF"),
    }

    # Density changes internal rhythm only.  Edge padding is deliberately
    # fixed and never depends on Compact/Normal/Roomy.
    DENSITY_MAP = {
        "compact": 4,
        "normal": 8,
        "roomy": 12,
    }

    SET_DENSITY_OFFSET = {
        "compact": -3,
        "normal": 0,
        "roomy": 5,
    }

    PAGE_PADDING = 12

    # Invisible character used only while an empty active numeric TextField is
    # focused. Android IMEs report deleting this as a normal text change.
    EMPTY_BACKSPACE_SENTINEL = "\u200b"

    SET_WEIGHT_WIDTH = 100
    SET_SMALL_WIDTH = 72
    SET_OK_WIDTH = 36
    SET_OK_HEIGHT = 36

    def __init__(self, page: ft.Page):
        self.page = page
        self.page.title = "GYMER"
        self.page.scroll = None
        self.page.window_width = 430
        self.page.window_height = 760

        storage.ensure_data()

        # A brand-new mesocycle is provisional until at least one training day
        # is assigned. If the app was closed during that initial calendar setup,
        # discard the unfinished cycle on the next launch.
        startup_cycle = storage.active_mesocycle()
        if (
            startup_cycle
            and startup_cycle.get("setup_complete", "1") == "0"
        ):
            storage.delete_mesocycle(startup_cycle.get("cycle_id", ""))

        self.settings = storage.read_settings()
        self.active_workout = storage.load_active_workout()
        self._workout_clock_anchor = None
        self.workout_elapsed_seconds()
        self.set_controls = []
        self.selected_tab = 0
        self.active_progress_text = None
        self.native_back_action = None
        # The active workout is global session state, not a child screen that
        # must be destroyed when Android Back exits the app.  This transient
        # mode only decides what Back should do while the active session itself
        # is visible: return to the workout list when it was opened normally,
        # or exit when a root tab returned the user to the global session.
        self.active_workout_back_mode = "saved"
        self.settings_subpage = "main"

        self.timer_generation = 0
        self.timer_started_at = None
        self.timer_total_seconds = 0
        self.timer_exercise_name = ""
        self.timer_inline_item = None
        self.timer_set_number = None
        self.timer_display_mode = "elapsed"
        self.timer_pulse = False
        self.timer_popup_dismissed = False

        self.workout_clock_generation = 0
        self.workout_clock_visible = False
        self.workout_elapsed_text = None
        self.workout_timer_play_icon = None
        self.workout_timer_pause_icon = None
        self.workout_clock_pulse = False
        self.numeric_field_kinds = {}
        self.numeric_warning_fields = {}
        self.numeric_warning_pulse = False
        self.numeric_warning_acknowledged = set()
        self.focused_text_field = None
        self.focus_previous_fields = {}
        self.android_backspace_last_values = {}
        self.active_numeric_context = {}
        self.pending_cycle_setup_id = None

        # Warn at most three times per active workout when a locked RIR field
        # is tapped.  The field itself remains immutable until the Cycle lock
        # is turned off.
        self.rir_lock_warning_workout_id = None
        self.rir_lock_warning_count = 0

        self.current_background_color = None
        self.pending_background_from = None
        self.background_transition_generation = 0

        self.apply_settings()
        self.init_timer_popup()
        self.build_navigation()
        self.bind_native_back()
        self.page.on_platform_brightness_change = self.platform_brightness_changed
        self.page.on_keyboard_event = self.handle_keyboard_event
        self.show_workout_tab()
        self.restore_rest_timer()


def main(page: ft.Page):
    RepsApp(page)


if __name__ == "__main__":
    ft.run(main)
