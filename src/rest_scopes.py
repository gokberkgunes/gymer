"""Explicit planned-rest targets; uncertain protocol boundaries stay unclassified."""
import re
import volume_accounting as volume

LABELS = {
    'warmup': 'Warmups',
    'conventional': 'Conventional sets',
    'within_protocol': 'Within protocol groups',
    'after_protocol': 'After protocol groups',
    'all_pending': 'All unfinished entries',
}
PROTOCOL_ROLES = {'anchor', 'continuation', 'cluster_fragment'}


def duration(value):
    """Whole seconds or m:ss, with the same 24-hour bound as seconds fields."""
    text = str(value if value is not None else '').strip()
    if len(text) > 40:
        raise ValueError('Rest duration is too long.')
    if re.fullmatch(r'\d+:\d{2}', text):
        minutes, seconds = map(int, text.split(':'))
        if seconds >= 60:
            raise ValueError('Use seconds or m:ss (seconds must be 00–59).')
        result = minutes * 60 + seconds
    elif re.fullmatch(r'\d+(?:\.0+)?', text):
        result = int(text.split('.')[0])
    else:
        raise ValueError('Enter whole seconds or m:ss, for example 90 or 1:30.')
    if result > 86400:
        raise ValueError('Rest must be between 0 and 86400 seconds.')
    return result


def targets(rows):
    """For one exercise in row order, select unfinished set numbers without inference."""
    result = {key: [] for key in LABELS}
    classified = {}
    groups = {}
    for index, row in enumerate(rows):
        kind = volume.role(row)
        if kind == 'warmup':
            classified[index] = 'warmup'
        elif kind == 'conventional':
            classified[index] = 'conventional'
        elif kind in PROTOCOL_ROLES and row.get('group_id'):
            groups.setdefault(row['group_id'], []).append(index)
    for indices in groups.values():
        members = [rows[index] for index in indices]
        roles = [volume.role(row) for row in members]
        sizes = {str(row.get('group_planned_count', '')) for row in members}
        valid_roles = (all(role == 'cluster_fragment' for role in roles)
                       or (roles[0] == 'anchor' and len(roles) > 1
                           and all(role == 'continuation' for role in roles[1:])))
        known = (sizes == {str(len(members))}
                 and all(row.get('segment_role') == kind for row, kind in zip(members, roles))
                 and indices == list(range(indices[0], indices[-1] + 1))
                 and not any(row.get('protocol_group_start') == '1' for row in members[1:]))
        if known and valid_roles:
            for index in indices[:-1]:
                classified[index] = 'within_protocol'
            classified[indices[-1]] = 'after_protocol'
    for index, row in enumerate(rows):
        if volume.completed(row):
            continue
        number = int(row['set_number'])
        result['all_pending'].append(number)
        result[f'set:{number}'] = [number]
        if index in classified:
            result[classified[index]].append(number)
    return {key: numbers for key, numbers in result.items() if numbers}


def signature(rows):
    """Fields that determine selection and its current planned-rest preview."""
    fields = ('set_number', 'set_type', 'training_method', 'group_id', 'segment_role',
              'group_planned_count', 'protocol_group_start', 'rest_seconds')
    return [(tuple(str(row.get(key, '')) for key in fields), volume.completed(row)) for row in rows]
