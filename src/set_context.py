"""Declared logging meanings; blanks are unknown and values are never converted."""
OPTIONS = {
    'load_convention': {'':'Unknown / not recorded', 'total':'Total load',
                        'per_implement':'Per implement (e.g. one dumbbell)', 'per_side':'Load per side'},
    'rep_convention': {'':'Unknown / not recorded', 'total':'Total repetitions', 'per_side':'Repetitions per side'},
    'side': {'':'Unknown / not recorded', 'bilateral':'Bilateral', 'left':'Left', 'right':'Right',
             'both_separately':'Both sides in one entry'},
}
LABELS = {'load_convention':'Load basis', 'rep_convention':'Rep count basis', 'side':'Side'}
FIELDS = ('setup', *OPTIONS)


def metadata(row):
    return {key:str(row.get(key) or '').strip() for key in FIELDS}


def validate(row):
    result=metadata(row)
    for key, options in OPTIONS.items():
        if result[key] not in options:
            raise ValueError(f'{LABELS[key]} is not supported.')
    return result


def matches(source, target):
    return metadata(source) == metadata(target)


def comparison_error(rows, planned_rows=None):
    def contexts(items):
        return {tuple(metadata(row).values()) for row in items
                if str(row.get('set_type') or '').casefold() not in {'warm-up','warmup','warm up'}}
    if any(row.get("side") == "both_separately" for row in [*(rows or []), *(planned_rows or [])]):
        return "Both sides in one entry require manual progression; separate left/right outcomes are not recorded."
    recorded=contexts(rows or [])
    planned=contexts(planned_rows) if planned_rows is not None else recorded
    if len(recorded)>1 or len(planned)>1 or recorded != planned:
        return 'The setup, side or logging conventions differ or changed; establish a comparable baseline or progress manually.'
    return ''


def summary(row):
    context=metadata(row)
    parts=[f'Setup: {context["setup"]}'] if context['setup'] else []
    parts.extend(f'{LABELS[key]}: {options[context[key]]}' for key,options in OPTIONS.items() if context[key] in options and context[key])
    return ' · '.join(parts)


def template_metadata(row):
    """An explicit blank is unknown; an inherited plan stores no frozen defaults."""
    flag=str(row.get('context_override') or '').strip()
    if flag not in {'','0','1'}:
        raise ValueError('context_override must be blank, 0 or 1.')
    return {'context_override':'1' if flag=='1' else '',
            **(validate(row) if flag=='1' else metadata({}))}


def resolve(row, defaults):
    plan=template_metadata(row)
    return validate(plan if plan['context_override']=='1' else defaults)


def template_key(row):
    plan=template_metadata(row)
    return tuple(plan[key] for key in FIELDS) if plan['context_override']=='1' else None
