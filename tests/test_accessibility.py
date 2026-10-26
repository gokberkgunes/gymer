"""Interaction contracts for dense workout controls and stable timer status."""
from types import SimpleNamespace
from unittest import TestCase, mock
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import flet as ft
from ui_core import UICoreMixin
from test_rest_timer_recovery import TimerApp
from test_data_integrity import TemporaryStorageTestCase
import storage


class UI(UICoreMixin):
    BACKGROUND_MAP = {"charcoal": ("#15171A", "#F3F4F6"), "default": ("#1C1B1F", "#FFFBFE")}
    SET_OK_WIDTH = 36
    SET_OK_HEIGHT = 36
    def __init__(self, width, font_scale=1):
        self.page = SimpleNamespace(width=width, platform_brightness=ft.Brightness.LIGHT)
        self.settings = {'font_scale': str(font_scale)}
    def field_border_color(self): return '#000000'


class AccessibilityTests(TestCase):
    def test_primary_targets_do_not_shrink_on_narrow_screens(self):
        for width in (250, 320, 430):
            app = UI(width)
            controls = [app.set_ok_button(), app.active_set_type_button('Normal', 1),
                        app.set_adjust_button('+', 'Add set', mock.Mock()),
                        app.compact_outline_icon(ft.Icons.ADD, mock.Mock()),
                        app.icon_action(ft.Icons.SAVE, '#000000', mock.Mock())]
            for control in controls:
                self.assertGreaterEqual(control.width, 48)
                self.assertGreaterEqual(control.height, 48)

    def test_semantics_exposes_state_identity_and_shared_activation(self):
        app = UI(320)
        button = app.set_ok_button()
        button.on_click = mock.Mock()
        semantics = app.completion_semantics(button, 'Bench Press', 2, False)
        self.assertTrue(semantics.button)
        self.assertFalse(semantics.checked)
        self.assertIn('Bench Press, set 2', semantics.label)
        semantics.on_tap(None)
        button.on_click.assert_called_once_with(None)
        app.describe_completion(semantics, 'Bench Press', 2, True)
        self.assertTrue(semantics.checked)
        self.assertEqual('Mark not completed', semantics.on_tap_hint_text)

    def test_warning_style_is_stable_and_stale_fields_are_removed(self):
        app = UI(320)
        field, stale = ft.TextField(), ft.TextField()
        app.set_controls = [{'reps': field}]
        app.numeric_warning_fields = {
            id(field): {'field': field, 'acknowledged': False},
            id(stale): {'field': stale, 'acknowledged': False},
        }
        app.refresh_numeric_warning_styles()
        first = field.text_style.color
        app.refresh_numeric_warning_styles()
        self.assertEqual(first, field.text_style.color)
        self.assertNotIn(id(stale), app.numeric_warning_fields)
        self.assertFalse(app.numeric_warning_pulse)


class StableTimerTests(TemporaryStorageTestCase):
    def app(self):
        return TimerApp(storage.build_active_workout(storage.read_workout('A')))

    def test_paused_status_and_foreground_remain_stable(self):
        app = self.app()
        app.active_workout.update(timer_started=True, started_at='', timer_elapsed_seconds=25)
        app.workout_elapsed_text = ft.Text()
        app.workout_timer_play_icon = ft.Icon(ft.Icons.PLAY_ARROW)
        app.workout_timer_pause_icon = ft.Icon(ft.Icons.PAUSE)
        app.workout_clock_status_text = ft.Text()
        for pulse in (True, False):
            app.workout_clock_pulse = pulse
            app.refresh_workout_clock_controls()
            self.assertEqual('Paused', app.workout_clock_status_text.value)
            self.assertEqual(app.foreground_color(), app.workout_elapsed_text.color)
            self.assertTrue(app.workout_timer_pause_icon.visible)

    def test_overdue_rest_has_written_status_and_no_color_alternation(self):
        app = self.app()
        app.active_workout['rows'][0]['completed'] = True
        app.active_workout['rows'][0]['timer_label'] = ft.Text()
        with mock.patch('timers.time.monotonic', return_value=100):
            app.start_rest_timer(app.active_workout['rows'][0]['exercise_name'], 60,
                                 inline_item=app.active_workout['rows'][0])
        with mock.patch('timers.time.monotonic', return_value=170):
            app.refresh_timer_display()
            color = app.timer_value_text.color
            app.refresh_timer_display()
        self.assertIn('Rest complete', app.timer_name_text.value)
        self.assertEqual(color, app.timer_value_text.color)
        self.assertFalse(app.timer_pulse)
        label = app.active_workout['rows'][0]['timer_label']
        self.assertEqual('Rest complete', label.tooltip)
        with mock.patch('timers.time.monotonic', return_value=110):
            app.refresh_timer_display()
        self.assertEqual('Rest remaining', label.tooltip)
        app.dismiss_timer()
        self.assertIsNone(label.tooltip)
