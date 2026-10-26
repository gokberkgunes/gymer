"""Measured text colors cover the supported theme/background/accent matrix."""
from types import SimpleNamespace
from unittest import TestCase
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import flet as ft
import text_contrast as contrast
from main import RepsApp


def app(theme='light', background='default', accent='purple'):
    result = object.__new__(RepsApp)
    result.settings = {'theme_mode': theme, 'background_color': background, 'accent_color': accent}
    result.page = SimpleNamespace(platform_brightness=ft.Brightness.LIGHT)
    return result


class TextContrastTests(TestCase):
    def test_known_reference_ratios_and_previous_light_theme_failure(self):
        self.assertEqual(21, contrast.ratio('#FFFFFF', '#000000'))
        self.assertEqual(1, contrast.ratio('#808080', '#808080'))
        self.assertEqual(contrast.ratio('#15171A', '#CBD5E1'), contrast.ratio('#CBD5E1', '#15171A'))
        self.assertLess(contrast.ratio('#9E9E9E', '#FFFBFE'), 4.5)
        self.assertLess(contrast.ratio('#FFA726', '#FFFBFE'), 4.5)

    def test_compositing_limits_and_invalid_inputs(self):
        self.assertEqual('#FFFFFF', contrast.composite('#000000', '#FFFFFF', 0))
        self.assertEqual('#000000', contrast.composite('#000000', '#FFFFFF', 1))
        self.assertEqual('#808080', contrast.composite('#000000', '#FFFFFF', 0.5))
        for color in ('#12', 'transparent', '#zzzzzz'):
            with self.assertRaises(ValueError): contrast.rgb(color)
        for opacity in (-1, 2, float('nan')):
            with self.assertRaises(ValueError): contrast.composite('#000000', '#FFFFFF', opacity)

    def test_all_builtin_text_roles_clear_threshold_on_measured_surfaces(self):
        self.assertEqual(set(RepsApp.COLOR_MAP), set(contrast.ACCENTS))
        for theme in ('light', 'dark'):
            for background in RepsApp.BACKGROUND_MAP:
                for accent in RepsApp.COLOR_MAP:
                    ui = app(theme, background, accent)
                    surfaces = contrast.surfaces(ui.background_color(), accent, theme == 'dark')
                    for role in (*contrast.ROLES, 'accent'):
                        for surface in surfaces:
                            self.assertGreaterEqual(contrast.ratio(ui.contrast_text_color(role), surface), 4.5,
                                                    (theme, background, accent, role, surface))

    def test_system_theme_and_auto_background_follow_platform_brightness(self):
        ui = app('system', 'auto')
        light = ui.contrast_text_color('warning')
        ui.page.platform_brightness = ft.Brightness.DARK
        dark = ui.contrast_text_color('warning')
        self.assertNotEqual(light, dark)
        self.assertGreaterEqual(contrast.ratio(dark, ui.background_color()), 4.5)

    def test_unknown_accent_fallback_does_not_mutate_user_preferences(self):
        ui = app(accent='unrecognized')
        before = dict(ui.settings)
        self.assertEqual(app().contrast_text_color(), ui.contrast_text_color())
        self.assertEqual(before, ui.settings)

    def test_warning_numbers_and_helper_refresh_together_across_theme_change(self):
        ui = app()
        ui.active_workout = None
        ui.numeric_warning_fields = {}
        ui.numeric_warning_acknowledged = set()
        field = ft.TextField(value='40')
        item = {'exercise_name': 'Test', 'set_number': 1, 'reps': field, 'completed': False}
        ui.set_controls = [item]
        ui.update_active_numeric_warning(item, 'reps')
        light = field.text_style.color
        self.assertEqual(light, field.helper_style.color)
        self.assertEqual('Unusually high rep count', field.helper_text)
        ui.settings['theme_mode'] = 'dark'
        ui.refresh_numeric_warning_styles()
        self.assertNotEqual(light, field.text_style.color)
        self.assertEqual(field.text_style.color, field.helper_style.color)
        field.value = '10'
        ui.update_active_numeric_warning(item, 'reps')
        self.assertIsNone(field.helper_style)
        self.assertIsNone(field.helper_text)
