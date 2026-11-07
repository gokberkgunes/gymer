import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/numbers.dart';
import '../theme.dart';

/// Invisible character kept in an empty focused field, so the Android soft
/// keyboard reports Backspace there (deleting it is an ordinary text change).
const sentinel = '​';

String stripSentinel(String s) => s.replaceAll(sentinel, '').trim();

/// Numeric input with the Flet app's behaviour: arithmetic ("45+45"), range
/// checks, unusual-value warnings, a centred placeholder, a unit suffix,
/// Enter to advance and Backspace-on-empty to go back.
class NumField extends StatefulWidget {
  final double? value;
  final NumKind kind;
  final String? placeholder;
  final String? suffix;
  final bool readOnly;
  final bool invalid;
  final bool completed;

  /// Box colour when not completed (defaults to the theme's input fill).
  final Color? fill;

  /// Orange warning reason for the current value (already computed).
  final String? warning;
  final String? tooltip;
  final IconData? cornerIcon;
  final FocusNode? focusNode;
  final bool dense;
  final TextAlign align;

  /// Called with the parsed value on every valid edit (null when emptied).
  final ValueChanged<double?> onChanged;

  /// Enter/OK after a valid value. Return value ignored.
  final VoidCallback? onSubmitted;
  final VoidCallback? onBackspaceEmpty;
  final VoidCallback? onBlur;

  const NumField({
    super.key,
    required this.value,
    required this.kind,
    required this.onChanged,
    this.placeholder,
    this.suffix,
    this.readOnly = false,
    this.invalid = false,
    this.completed = false,
    this.fill,
    this.warning,
    this.tooltip,
    this.cornerIcon,
    this.focusNode,
    this.onSubmitted,
    this.onBackspaceEmpty,
    this.onBlur,
    this.dense = true,
    this.align = TextAlign.left,
  });

  @override
  State<NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<NumField> {
  late final TextEditingController _c = TextEditingController(text: _format(widget.value));
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  String _last = '';
  bool _badInput = false;

  /// Keeps the field (and its focus and keyboard) alive when a warning
  /// tooltip appears or disappears around it mid-edit.
  final _fieldKey = GlobalKey();

  String _format(double? v) => v == null ? '' : formatNumber(v, widget.kind);

  @override
  void initState() {
    super.initState();
    _last = _c.text;
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant NumField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
    // Follow external changes (fallbacks, conversions) unless the user is
    // mid-edit with an equivalent expression.
    final shown = evaluateExpression(stripSentinel(_c.text));
    final current = stripSentinel(_c.text);
    final differs = widget.value == null ? current.isNotEmpty && shown != null : shown != widget.value;
    if (differs && !(_focus.hasFocus && current.isNotEmpty && shown == null)) {
      _setText(_format(widget.value) + (_focus.hasFocus && widget.value == null ? sentinel : ''));
    }
  }

  void _setText(String t) {
    _c.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
    _last = t;
  }

  void _onFocus() {
    if (mounted) setState(() {}); // the placeholder hides while focused
    if (_focus.hasFocus) {
      if (!widget.readOnly && stripSentinel(_c.text).isEmpty) _setText(sentinel);
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
    } else {
      _normalize();
      widget.onBlur?.call();
    }
  }

  /// Evaluate and pretty-print; invalid input stays in place, marked red.
  bool _normalize() {
    // Focus can be lost while the field is being torn down (e.g. its exercise collapses); nothing to tidy then.
    if (!mounted) return false;
    final raw = stripSentinel(_c.text);
    if (raw.isEmpty) {
      if (_c.text.isNotEmpty) _setText('');
      setState(() => _badInput = false);
      return true;
    }
    final v = evaluateExpression(raw);
    if (v == null || !numberAllowed(v, widget.kind)) {
      setState(() => _badInput = true);
      return false;
    }
    _setText(formatNumber(v, widget.kind));
    setState(() => _badInput = false);
    widget.onChanged(v);
    return true;
  }

  void _changed(String text) {
    final prev = _last;
    _last = text;
    // Sentinel deleted on an already-empty field: this is Backspace.
    if (text.isEmpty && prev == sentinel) {
      _setText(sentinel);
      widget.onBackspaceEmpty?.call();
      return;
    }
    // Deleting the last real character keeps focus; re-arm for the next press.
    if (text.isEmpty && _focus.hasFocus) _setText(sentinel);
    final raw = stripSentinel(text);
    if (_badInput) setState(() => _badInput = false);
    if (raw.isEmpty) {
      widget.onChanged(null);
      return;
    }
    final v = evaluateExpression(raw);
    if (v != null && numberAllowed(v, widget.kind)) widget.onChanged(v);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = context.style;
    final warn = widget.warning != null && !_badInput && !widget.invalid;
    final orange = cs.warning;
    final red = cs.error;
    final empty = widget.value == null && stripSentinel(_c.text).isEmpty;
    // The centred placeholder would sit under the caret, so it hides while editing.
    final showPlaceholder = empty && !_focus.hasFocus;
    // Completed values sit on the card without a box, as plain bold text.
    final borderColor = widget.invalid || _badInput ? red : null;

    OutlineInputBorder border(Color? c, double w) => OutlineInputBorder(
      borderRadius: st.brSmall,
      borderSide: c == null ? BorderSide.none : BorderSide(color: c, width: w),
    );

    final field = TextField(
      controller: _c,
      focusNode: _focus,
      readOnly: widget.readOnly,
      textAlign: widget.align,
      keyboardType: TextInputType.numberWithOptions(decimal: !isIntegerKind(widget.kind), signed: false),
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.,+\\-*/() $sentinel]'))],
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        fontFeatures: tabular,
        color: warn ? orange : (widget.readOnly ? cs.onSurfaceVariant : null),
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.fromLTRB(
          10,
          st.sp(widget.dense ? 10 : 12),
          widget.suffix == null ? 8 : 30,
          st.sp(widget.dense ? 10 : 12),
        ),
        fillColor: widget.completed ? Colors.transparent : widget.fill,
        // The ghost value is the field's own hint, so it lines up exactly with typed values.
        hintText: showPlaceholder ? widget.placeholder : null,
        hintMaxLines: 1,
        hintStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          fontFeatures: tabular,
          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        enabledBorder: border(borderColor, 1.8),
        focusedBorder: border(borderColor ?? cs.primary, 2),
        border: border(borderColor, 1.2),
      ),
      onChanged: _changed,
      // Focus moves are ours (Enter flow), not the framework's "next".
      onEditingComplete: () {},
      onSubmitted: (_) {
        if (_normalize()) widget.onSubmitted?.call();
      },
      onTapOutside: (_) => _focus.unfocus(),
    );

    final stack = Stack(
      key: _fieldKey,
      alignment: Alignment.center,
      children: [
        field,
        if (widget.cornerIcon != null && !warn && !_badInput && !widget.invalid && !_focus.hasFocus)
          Positioned(
            top: 4,
            right: 4,
            child: IgnorePointer(child: Icon(widget.cornerIcon, size: 12, color: cs.primary.withValues(alpha: 0.75))),
          ),
        // The unit shows beside a value or a numeric placeholder, not a label like "Reps".
        if (widget.suffix != null && (!empty || evaluateExpression(widget.placeholder) != null))
          Positioned(
            right: 7,
            child: IgnorePointer(
              child: Text(
                widget.suffix!,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
            ),
          ),
      ],
    );
    final tip = [?widget.tooltip, if (warn) widget.warning!].join('\n');
    return tip.isEmpty ? stack : Tooltip(message: tip, triggerMode: TooltipTriggerMode.longPress, child: stack);
  }
}

/// Text field for durations: shows m:ss, edits as plain seconds so Android
/// offers the number pad, and accepts "90" or "1:30".
class DurationField extends StatefulWidget {
  final int seconds;
  final ValueChanged<int> onChanged;
  final bool readOnly;
  final String? label;
  final String? tooltip;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  /// Box colour (defaults to the theme's input fill).
  final Color? fill;

  const DurationField({
    super.key,
    required this.seconds,
    required this.onChanged,
    this.readOnly = false,
    this.label,
    this.tooltip,
    this.focusNode,
    this.onSubmitted,
    this.fill,
  });

  @override
  State<DurationField> createState() => _DurationFieldState();
}

class _DurationFieldState extends State<DurationField> {
  late final _c = TextEditingController(text: formatDuration(widget.seconds));
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant DurationField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.seconds != widget.seconds) _c.text = formatDuration(widget.seconds);
  }

  void _onFocus() {
    if (widget.readOnly) return;
    if (_focus.hasFocus) {
      _c.text = '${parseDuration(_c.text, widget.seconds)}';
      _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
    } else {
      final v = parseDuration(_c.text, widget.seconds);
      _c.text = formatDuration(v);
      widget.onChanged(v);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _own?.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _c,
      focusNode: _focus,
      readOnly: widget.readOnly,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9:]'))],
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontFeatures: tabular,
        color: widget.readOnly ? Theme.of(context).colorScheme.onSurfaceVariant : null,
      ),
      decoration: InputDecoration(labelText: widget.label, hintText: '3:00', fillColor: widget.fill),
      onEditingComplete: () {},
      onSubmitted: (_) {
        _focus.unfocus();
        widget.onSubmitted?.call();
      },
    );
    return widget.tooltip == null ? field : Tooltip(message: widget.tooltip!, child: field);
  }
}
