import ast
import asyncio
import math
import time
import uuid
from datetime import datetime, timezone

import flet as ft

import storage
import rest_timer_state


class TimerMixin:

    def init_timer_popup(self):
        self.timer_name_text = ft.Text(
            "",
            size=self.fs(10),
            weight=ft.FontWeight.BOLD,
            color=ft.Colors.WHITE,
            max_lines=1,
            overflow=ft.TextOverflow.ELLIPSIS,
        )
        self.timer_value_text = ft.Text(
            "0:00 / 0:00",
            size=self.fs(15),
            weight=ft.FontWeight.BOLD,
            color=ft.Colors.WHITE,
        )

        self.timer_popup = ft.Container(
            visible=False,
            right=self.ui(14),
            bottom=self.ui(14),
            padding=ft.Padding(left=self.ui(6), top=16, right=self.ui(6), bottom=16),
            bgcolor="#202124",
            border=ft.Border.all(1.5, self.accent_color()),
            border_radius=self.rounding(),
            alignment=ft.Alignment.CENTER_LEFT,
            ink=True,
            tooltip="Tap: active workout · Hold: countdown",
            on_click=lambda e: self.handle_floating_timer_tap(),
            on_long_press=lambda e: self.handle_floating_timer_hold(),
            content=ft.Column(
                controls=[
                    self.timer_name_text,
                    self.timer_value_text,
                ],
                spacing=0,
                tight=True,
            ),
        )

    def update_timer_popup_style(self):
        if not hasattr(self, "timer_popup"):
            return

        self.timer_popup.border_radius = self.rounding()
        self.timer_name_text.size = self.fs(10)
        self.timer_value_text.size = self.fs(15)

        if self.timer_started_at is not None:
            self.timer_popup.border = ft.Border.all(1.5, self.accent_color())

    def format_timer(self, seconds):
        seconds = max(0, int(seconds))
        minutes, seconds = divmod(seconds, 60)
        return f"{minutes}:{seconds:02d}"

    def format_elapsed_timer(self, seconds):
        seconds = max(0, int(seconds))
        minutes, seconds = divmod(seconds, 60)
        return f"{minutes:02d}:{seconds:02d}"

    def format_signed_timer(self, seconds):
        seconds = int(seconds)
        sign = "-" if seconds < 0 else ""
        seconds = abs(seconds)
        minutes, seconds = divmod(seconds, 60)
        return f"{sign}{minutes}:{seconds:02d}"

    def handle_floating_timer_tap(self):
        """The floating rest timer is the global shortcut back to the workout."""
        if self.timer_started_at is None or not self.active_workout:
            return
        self.return_to_active_workout_from_root()

    def handle_floating_timer_hold(self):
        """Long-press the floating timer to view the remaining countdown."""
        if self.timer_started_at is None:
            return
        self.timer_display_mode = "countdown"
        self.persist_rest_timer()
        self.refresh_timer_display(update_page=True)

    def reset_inline_timer_item(self, item):
        if not item:
            return

        label = item.get("timer_label")
        if label is None:
            return

        label.color = self.foreground_color()
        label.opacity = 1.0
        label.weight = ft.FontWeight.BOLD
        label.tooltip = None

        if item.get("completed"):
            label.visible = False
            return

        label.visible = bool(item.get("show_planned_rest", False))
        label.value = storage.format_duration(item.get("rest_seconds", 0))

    def find_set_item(self, exercise_name, set_number):
        for item in self.set_controls:
            if (
                item.get("exercise_name") == exercise_name
                and item.get("set_number") == set_number
            ):
                return item
        return None

    def sync_inline_timer(self):
        # Set rows are rebuilt when returning to the workout screen. Reattach
        # the timer to the set that actually started the rest period.
        self.timer_inline_item = None

        if self.timer_started_at is None:
            return

        item = self.find_set_item(
            self.timer_exercise_name,
            self.timer_set_number,
        )
        if item is None:
            return

        self.timer_inline_item = item
        self.refresh_timer_display(update_page=False)

    def persist_rest_timer(self):
        if not self.active_workout:
            return
        if self.timer_started_at is None:
            raw = ""
        else:
            if self.timer_set_number is None:
                return
            raw = rest_timer_state.encode({
                "version": 1,
                "session_id": self.active_workout["session_id"],
                "exercise_name": self.timer_exercise_name,
                "set_number": int(self.timer_set_number),
                "total_seconds": self.timer_total_seconds,
                "started_epoch": self.timer_started_epoch,
                "display_mode": self.timer_display_mode,
            })
        if self.active_workout.get("rest_timer_state", "") != raw:
            self.active_workout["rest_timer_state"] = raw
            storage.save_active_workout(self.active_workout)

    def restore_rest_timer(self):
        # Clear the previous session's UI/task without writing over restored data.
        self.dismiss_timer(silent=True, persist=False)
        if not self.active_workout:
            return
        try:
            state = rest_timer_state.decode(self.active_workout.get("rest_timer_state", ""))
        except ValueError:
            return
        if not rest_timer_state.matches(state, self.active_workout):
            return
        self.start_rest_timer(state["exercise_name"], state["total_seconds"],
                              _restored=state)
        self.sync_inline_timer()

    def start_rest_timer(self, exercise_name, total_seconds, inline_item=None, *, _restored=None):
        try:
            total_seconds = int(total_seconds)
        except (TypeError, ValueError):
            total_seconds = 0

        if self.timer_inline_item is not None:
            self.reset_inline_timer_item(self.timer_inline_item)
        self.timer_inline_item = None

        if total_seconds <= 0:
            self.dismiss_timer(silent=True)
            return

        self.timer_generation += 1
        generation = self.timer_generation

        self.timer_started_epoch = _restored["started_epoch"] if _restored else time.time()
        elapsed = max(0, time.time() - self.timer_started_epoch) if _restored else 0
        self.timer_started_at = time.monotonic() - elapsed
        self.timer_total_seconds = total_seconds
        self.timer_exercise_name = exercise_name
        self.timer_set_number = (
            _restored["set_number"] if _restored else (
                inline_item.get("set_number") if inline_item is not None else None
            )
        )
        self.timer_display_mode = _restored["display_mode"] if _restored else self.default_timer_display_mode()
        self.timer_pulse = False
        self.timer_popup_dismissed = False

        self.timer_popup.visible = self.floating_timer_enabled()
        self.timer_popup.opacity = 1.0
        self.timer_popup.bgcolor = "#202124"
        self.timer_popup.border = ft.Border.all(1.5, self.accent_color())
        self.timer_name_text.value = exercise_name
        self.timer_name_text.visible = True

        if inline_item is not None:
            label = inline_item.get("timer_label")
            if label is not None:
                label.visible = self.nearset_timer_enabled()
                label.color = self.foreground_color()
                label.weight = ft.FontWeight.BOLD
                label.opacity = 1.0
                label.value = self.format_timer(total_seconds)
                self.timer_inline_item = inline_item

        if not _restored:
            self.persist_rest_timer()
        self.refresh_timer_display(update_page=False)
        self.page.update()
        self.page.run_task(self.timer_loop, generation)

    def refresh_timer_display(self, update_page=True):
        if self.timer_started_at is None:
            return

        elapsed = max(0, int(time.monotonic() - self.timer_started_at))
        remaining = self.timer_total_seconds - elapsed
        overdue = remaining <= 0 and elapsed >= self.timer_total_seconds

        # The floating timer remains visible across the app while the rest
        # period is active. It is the single global return control; no separate
        # bottom timer bar is rendered.
        self.timer_popup.visible = (
            self.floating_timer_enabled()
            and not self.timer_popup_dismissed
        )
        self.timer_name_text.visible = True
        self.timer_name_text.value = (
            f"Rest complete · {self.timer_exercise_name}" if overdue
            else self.timer_exercise_name
        )
        self.timer_popup.tooltip = "Rest complete. Tap to return to workout" if overdue else "Tap: active workout · Hold: countdown"

        if self.timer_display_mode == "countdown":
            self.timer_value_text.value = self.format_signed_timer(remaining)
        else:
            self.timer_value_text.value = (
                f"{self.format_elapsed_timer(elapsed)} / "
                f"{self.format_timer(self.timer_total_seconds)}"
            )

        self.timer_name_text.weight = ft.FontWeight.BOLD
        self.timer_value_text.weight = ft.FontWeight.BOLD

        inline_item = self.timer_inline_item
        label = inline_item.get("timer_label") if inline_item is not None else None
        if label is not None:
            label.visible = self.nearset_timer_enabled()
            label.value = self.format_signed_timer(remaining)
            label.weight = ft.FontWeight.BOLD
            label.opacity = 1.0
            label.tooltip = "Rest complete" if overdue else "Rest remaining"

        if overdue:
            self.timer_pulse = False
            self.timer_popup.bgcolor = "#202124"
            self.timer_popup.border = ft.Border.all(1.5, ft.Colors.RED_500)
            self.timer_popup.opacity = 1.0
            self.timer_value_text.color = ft.Colors.WHITE
            self.timer_name_text.color = ft.Colors.WHITE
            if label is not None:
                label.color = self.foreground_color()
        else:
            self.timer_popup.bgcolor = "#202124"
            self.timer_popup.border = ft.Border.all(1.5, self.accent_color())
            self.timer_popup.opacity = 1.0
            self.timer_value_text.color = ft.Colors.WHITE
            self.timer_name_text.color = ft.Colors.WHITE
            if label is not None:
                label.color = self.foreground_color()

        if update_page:
            self.page.update()

    async def timer_loop(self, generation):
        while (
            generation == self.timer_generation
            and self.timer_started_at is not None
        ):
            self.refresh_timer_display(update_page=True)
            await asyncio.sleep(1)

    def dismiss_timer(self, silent=False, *, persist=True):
        self.timer_generation += 1
        self.timer_started_at = None
        self.timer_total_seconds = 0
        self.timer_exercise_name = ""
        self.timer_set_number = None
        self.timer_display_mode = self.default_timer_display_mode()
        self.timer_pulse = False
        self.timer_popup_dismissed = False

        if self.timer_inline_item is not None:
            self.reset_inline_timer_item(self.timer_inline_item)
        self.timer_inline_item = None

        if hasattr(self, "timer_popup"):
            self.timer_popup.visible = False
            self.timer_popup.opacity = 1.0

        if persist:
            self.persist_rest_timer()
        if not silent:
            self.page.update()

    def workout_clock_has_started(self):
        if not self.active_workout:
            return False
        return bool(
            self.active_workout.get("timer_started", False)
            or (self.active_workout.get("started_at", "") or "").strip()
        )

    def workout_clock_is_running(self):
        if not self.active_workout:
            return False
        return bool((self.active_workout.get("started_at", "") or "").strip())

    def workout_clock_is_paused(self):
        return (
            self.workout_clock_has_started()
            and not self.workout_clock_is_running()
        )

    def workout_elapsed_seconds(self):
        if not self.active_workout:
            return 0

        try:
            elapsed = max(
                0,
                int(self.active_workout.get("timer_elapsed_seconds", 0) or 0),
            )
        except (TypeError, ValueError):
            elapsed = 0

        started_at = (self.active_workout.get("started_at", "") or "").strip()
        if not started_at:
            return elapsed

        key = (self.active_workout.get("session_id"), started_at, elapsed)
        anchor = getattr(self, "_workout_clock_anchor", None)
        if anchor is None or anchor[0] != key:
            try:
                started = datetime.fromisoformat(started_at)
                # Legacy naive timestamps use local time; their original offset
                # was not stored and cannot be reconstructed after travel.
                if started.tzinfo is None:
                    started = started.astimezone()
                recovered = max(0, (datetime.now(timezone.utc) - started).total_seconds())
            except (TypeError, ValueError, OverflowError, OSError):
                return elapsed
            anchor = (key, time.monotonic(), recovered)
            self._workout_clock_anchor = anchor
        return elapsed + max(0, int(anchor[2] + time.monotonic() - anchor[1]))

    def begin_workout_clock_interval(self):
        self.active_workout["started_at"] = datetime.now(timezone.utc).isoformat(
            timespec="microseconds"
        )
        key = (self.active_workout.get("session_id"),
               self.active_workout["started_at"],
               self.active_workout.get("timer_elapsed_seconds", 0))
        self._workout_clock_anchor = (key, time.monotonic(), 0)

    def start_workout_clock(self, e=None):
        """
        Start the session timer only if it has never been started.

        Set completion uses this method, so completing later sets must never
        accidentally resume a timer the user intentionally paused.
        """
        if not self.active_workout or self.workout_clock_has_started():
            return

        self.active_workout["timer_started"] = True
        self.active_workout["timer_elapsed_seconds"] = 0
        self.begin_workout_clock_interval()
        storage.save_active_workout(self.active_workout)
        self.refresh_workout_clock_controls()
        self.page.update()

    def toggle_workout_clock(self, e=None):
        if not self.active_workout:
            return

        if not self.workout_clock_has_started():
            self.start_workout_clock()
            return

        if self.workout_clock_is_running():
            # Freeze the accumulated time and enter the paused state.
            self.active_workout["timer_elapsed_seconds"] = (
                self.workout_elapsed_seconds()
            )
            self.active_workout["started_at"] = ""
        else:
            # Resume from the stored accumulated time.
            self.begin_workout_clock_interval()

        self.active_workout["timer_started"] = True
        storage.save_active_workout(self.active_workout)
        self.workout_clock_pulse = False
        self.refresh_workout_clock_controls()
        self.page.update()

    def reset_workout_clock(self):
        if not self.active_workout:
            return

        self.active_workout["started_at"] = ""
        self.active_workout["timer_started"] = False
        self.active_workout["timer_elapsed_seconds"] = 0
        self._workout_clock_anchor = None
        storage.save_active_workout(self.active_workout)

        self.workout_clock_pulse = False
        self.refresh_workout_clock_controls()
        self.page.update()

    def format_workout_elapsed(self):
        seconds = self.workout_elapsed_seconds()
        hours, remainder = divmod(seconds, 3600)
        minutes, seconds = divmod(remainder, 60)

        if hours:
            return f"{hours}:{minutes:02d}:{seconds:02d}"

        # Keep the initial/stopped display and the first ten minutes stable:
        # 00:00, 00:01, ... 09:59 rather than shifting to 0:00.
        return f"{minutes:02d}:{seconds:02d}"

    def refresh_workout_clock_controls(self):
        status = getattr(self, "workout_clock_status_text", None)
        if status is not None:
            status.value = ("Running" if self.workout_clock_is_running() else
                            "Paused" if self.workout_clock_has_started() else "Not started")
            status.color = self.foreground_color()
        if self.workout_elapsed_text is not None:
            self.workout_elapsed_text.value = self.format_workout_elapsed()

        if (
            self.workout_timer_play_icon is None
            or self.workout_timer_pause_icon is None
        ):
            return

        if not self.workout_clock_has_started():
            self.workout_timer_play_icon.visible = True
            self.workout_timer_play_icon.color = self.foreground_color()
            self.workout_timer_pause_icon.visible = False
            if self.workout_elapsed_text is not None:
                self.workout_elapsed_text.color = self.foreground_color()
            return

        if self.workout_clock_is_running():
            # Both controls are hidden, but their fixed slot remains reserved,
            # so the elapsed text never shifts horizontally.
            self.workout_timer_play_icon.visible = False
            self.workout_timer_pause_icon.visible = False
            if self.workout_elapsed_text is not None:
                self.workout_elapsed_text.color = self.foreground_color()
            return

        # Keep paused state stable, with both the pause glyph and status text.
        self.workout_timer_play_icon.visible = False
        self.workout_timer_pause_icon.visible = True
        self.workout_timer_pause_icon.color = self.foreground_color()
        if self.workout_elapsed_text is not None:
            self.workout_elapsed_text.color = self.foreground_color()

    async def workout_clock_loop(self, generation):
        while generation == self.workout_clock_generation and self.active_workout:
            if self.workout_clock_visible and self.workout_elapsed_text is not None:
                self.workout_clock_pulse = False
                self.refresh_workout_clock_controls()
                self.refresh_numeric_warning_styles()
                self.page.update()
            await asyncio.sleep(1)
