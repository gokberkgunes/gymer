"""Discarded editor controls cannot retain keyboard routing or numeric state."""
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest import IsolatedAsyncioTestCase, TestCase, mock
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import flet as ft
from ui_core import UICoreMixin


class UI(UICoreMixin):
    EMPTY_BACKSPACE_SENTINEL = "\u200b"
    def __init__(self):
        self.numeric_field_kinds = {}
        self.numeric_warning_fields = {}
        self.android_backspace_last_values = {}
        self.active_numeric_context = {}
        self.focus_previous_fields = {}
        self.focused_text_field = None
        self.page = SimpleNamespace(update=mock.Mock())


class EditorFocusTests(TestCase):
    def test_unregister_clears_owned_maps_and_predecessors_to_removed_controls(self):
        app = UI()
        removed, retained = ft.TextField(), ft.TextField()
        for mapping in (app.numeric_field_kinds, app.numeric_warning_fields,
                        app.android_backspace_last_values, app.active_numeric_context):
            mapping.update({id(removed): 'old', id(retained): 'keep'})
        app.focus_previous_fields.update({id(removed): retained, id(retained): removed})
        app.focused_text_field = removed
        app.unregister_text_fields(removed, None)
        for mapping in (app.numeric_field_kinds, app.numeric_warning_fields,
                        app.android_backspace_last_values, app.active_numeric_context):
            self.assertNotIn(id(removed), mapping)
            self.assertEqual('keep', mapping[id(retained)])
        self.assertEqual({}, app.focus_previous_fields)
        self.assertIsNone(app.focused_text_field)

    def test_unregister_preserves_unrelated_focus_and_sequences(self):
        app = UI()
        removed, first, second = ft.TextField(), ft.TextField(), ft.TextField()
        app.focus_previous_fields[id(second)] = first
        app.focused_text_field = second
        app.unregister_text_fields(removed)
        self.assertIs(app.focused_text_field, second)
        self.assertIs(app.focus_previous_fields[id(second)], first)


class EditorKeyboardTests(IsolatedAsyncioTestCase):
    async def test_enter_and_empty_backspace_cross_rows_skipping_locked_rest(self):
        app = UI()
        first, locked, next_row = ft.TextField(value='8'), ft.TextField(value='90', read_only=True), ft.TextField(value='')
        first.focus = mock.AsyncMock()
        next_row.focus = mock.AsyncMock()
        app.chain_text_fields(first, locked, next_row)
        await first.on_submit(None)
        next_row.focus.assert_awaited_once()
        app.focused_text_field = next_row
        await app.handle_keyboard_event(SimpleNamespace(key='Backspace'))
        first.focus.assert_awaited_once()
        self.assertNotIn(id(locked), app.focus_previous_fields)
