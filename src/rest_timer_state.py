"""Versioned persisted rest countdown; runtime elapsed uses a monotonic clock."""
import json
import math


def decode(raw):
    if not raw:
        return None
    try:
        state = json.loads(raw)
        if not isinstance(state, dict) or type(state.get('version')) is not int or state['version'] != 1:
            raise ValueError
        for key in ('session_id', 'exercise_name'):
            if not isinstance(state.get(key), str) or not state[key].strip():
                raise ValueError
        for key in ('set_number', 'total_seconds'):
            if type(state.get(key)) is not int or state[key] <= 0:
                raise ValueError
        stamp = state.get('started_epoch')
        if type(stamp) not in (int, float) or not math.isfinite(stamp) or stamp < 0:
            raise ValueError
        if state.get('display_mode') not in ('elapsed', 'countdown'):
            raise ValueError
    except (ValueError, TypeError, OverflowError):
        raise ValueError('Invalid persisted rest timer.') from None
    return state


def encode(state):
    raw = json.dumps(state, separators=(',', ':'), allow_nan=False)
    decode(raw)
    return raw


def matches(state, active):
    return bool(state and active and state['session_id'] == active.get('session_id')
                and any(row.get('exercise_name') == state['exercise_name']
                        and str(row.get('set_number')) == str(state['set_number'])
                        and row.get('completed') in (True, '1')
                        for row in active.get('rows', [])))
