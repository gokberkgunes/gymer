"""WCAG sRGB contrast for explicitly defined app text/surface colors.

References: https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
https://www.w3.org/WAI/GL/wiki/Relative_luminance
This measures color pairs, not rendered/native accessibility compliance.
"""
from functools import lru_cache
from types import MappingProxyType

ACCENTS = {
    'purple': '#9C27B0', 'blue': '#2196F3', 'teal': '#009688',
    'green': '#4CAF50', 'orange': '#FF9800', 'red': '#F44336', 'pink': '#E91E63',
}
ACCENT_TEXT = {
    'purple': ('#E9D5FF', '#6B21A8'), 'blue': ('#BFDBFE', '#1E40AF'),
    'teal': ('#99F6E4', '#115E59'), 'green': ('#BBF7D0', '#166534'),
    'orange': ('#FED7AA', '#9A3412'), 'red': ('#FECACA', '#991B1B'),
    'pink': ('#FBCFE8', '#9D174D'),
}
ROLES = {
    'muted': ('#CBD5E1', '#475569'), 'warning': ('#FDE68A', '#854D0E'),
    'success': ('#BBF7D0', '#166534'), 'error': ('#FECACA', '#991B1B'),
}


def rgb(color):
    color = str(getattr(color, 'value', color)).lower()
    color = {'white': '#ffffff', 'black': '#000000'}.get(color, color)
    if len(color) != 7 or not color.startswith('#'):
        raise ValueError('Expected an opaque #RRGGBB color.')
    try:
        return tuple(int(color[index:index + 2], 16) / 255 for index in (1, 3, 5))
    except ValueError:
        raise ValueError('Expected an opaque #RRGGBB color.') from None


def luminance(color):
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb(color)]
    return sum(c * weight for c, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def ratio(first, second):
    bright, dark = sorted((luminance(first), luminance(second)), reverse=True)
    return (bright + 0.05) / (dark + 0.05)


def composite(foreground, background, opacity):
    if not 0 <= opacity <= 1:
        raise ValueError('Opacity must be between zero and one.')
    channels = [round(255 * (f * opacity + b * (1 - opacity)))
                for f, b in zip(rgb(foreground), rgb(background))]
    return '#' + ''.join(f'{channel:02X}' for channel in channels)


def surfaces(background, accent_name, dark):
    accent = ACCENTS.get(accent_name, ACCENTS['purple'])
    return (
        background,
        composite(accent, background, 0.12),
        composite('#9E9E9E', background, 0.11 if dark else 0.075),
        composite('#FFFFFF' if dark else '#000000', background, 0.10),
    )


@lru_cache(maxsize=128)
def palette(background, accent_name, dark):
    backgrounds = surfaces(background, accent_name, dark)
    candidates = {**ROLES, 'accent': ACCENT_TEXT.get(accent_name, ACCENT_TEXT['purple'])}
    colors = {}
    for role, variants in candidates.items():
        preferred = variants[0 if dark else 1]
        if min(ratio(preferred, surface) for surface in backgrounds) >= 4.5:
            colors[role] = preferred
        else:
            colors[role] = max(('#FFFFFF', '#000000'),
                               key=lambda color: min(ratio(color, surface) for surface in backgrounds))
            if min(ratio(colors[role], surface) for surface in backgrounds) < 4.5:
                raise ValueError('No common text color meets the measured surface target.')
    return MappingProxyType(colors)
