import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'reader_preferences.dart';

/// 页眉 / 页脚边距配置（信息位固定，只允许调整三区内边距）。
///
/// 页眉左侧固定「第几章 章节名」、右侧时间；页脚左进度、中书名、右电量。
class ReaderHeaderFooterConfig extends StatefulWidget {
  const ReaderHeaderFooterConfig({
    super.key,
    required this.preferences,
    required this.onChanged,
  });

  final ReaderPreferences preferences;

  /// 每次修改后回调最新偏好，由调用方持久化并刷新阅读页。
  final ValueChanged<ReaderPreferences> onChanged;

  @override
  State<ReaderHeaderFooterConfig> createState() =>
      _ReaderHeaderFooterConfigState();
}

class _ReaderHeaderFooterConfigState extends State<ReaderHeaderFooterConfig> {
  late ReaderPreferences _prefs = widget.preferences;

  void _apply(ReaderPreferences next) {
    setState(() => _prefs = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        const ArchiveSection(title: '页边距', code: 'READER / PADDING'),
        const SizedBox(height: 8),
        const AppText(
          '页眉与页脚的信息位固定：页眉左侧「第几章 章节名」、右侧时间；页脚左侧进度、中间书名、右侧电量电池。此处只调整三区内边距。',
          style: TextStyle(fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 8),
        const ArchiveSection(title: '页眉内边距', code: 'READER / HEADER PADDING'),
        const SizedBox(height: 4),
        ..._headerPadFields(),
        const SizedBox(height: 8),
        const ArchiveSection(title: '页脚内边距', code: 'READER / FOOTER PADDING'),
        const SizedBox(height: 4),
        ..._footerPadFields(),
        const SizedBox(height: 8),
        const ArchiveSection(title: '正文边距', code: 'READER / BODY PADDING'),
        const SizedBox(height: 4),
        ..._bodyPadFields(),
      ],
    );
  }

  List<Widget> _headerPadFields() {
    final p = _prefs.headerPadding;
    Widget f(String l, double v, EdgeInsets Function(double) m) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _PadField(
        label: l,
        value: v,
        min: 0,
        max: 300,
        onChanged: (x) =>
            setState(() => _prefs = _prefs.copyWith(headerPadding: m(x))),
        onCommitted: (x) {
          final n = _prefs.copyWith(headerPadding: m(x));
          setState(() => _prefs = n);
          _apply(n);
        },
      ),
    );
    return [
      f('上', p.top, (x) => p.copyWith(top: x)),
      f('下', p.bottom, (x) => p.copyWith(bottom: x)),
      f('左', p.left, (x) => p.copyWith(left: x)),
      f('右', p.right, (x) => p.copyWith(right: x)),
    ];
  }

  List<Widget> _footerPadFields() {
    final p = _prefs.footerPadding;
    Widget f(String l, double v, EdgeInsets Function(double) m) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _PadField(
        label: l,
        value: v,
        min: 0,
        max: 300,
        onChanged: (x) =>
            setState(() => _prefs = _prefs.copyWith(footerPadding: m(x))),
        onCommitted: (x) {
          final n = _prefs.copyWith(footerPadding: m(x));
          setState(() => _prefs = n);
          _apply(n);
        },
      ),
    );
    return [
      f('上', p.top, (x) => p.copyWith(top: x)),
      f('下', p.bottom, (x) => p.copyWith(bottom: x)),
      f('左', p.left, (x) => p.copyWith(left: x)),
      f('右', p.right, (x) => p.copyWith(right: x)),
    ];
  }

  List<Widget> _bodyPadFields() {
    Widget f(String l, double v, ReaderPreferences Function(double) m) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _PadField(
            label: l,
            value: v,
            min: 0,
            max: 200,
            onChanged: (x) => setState(() => _prefs = m(x)),
            onCommitted: (x) {
              final n = m(x);
              setState(() => _prefs = n);
              _apply(n);
            },
          ),
        );
    return [
      f('上', _prefs.marginTop, (x) => _prefs.copyWith(marginTop: x)),
      f('下', _prefs.marginBottom, (x) => _prefs.copyWith(marginBottom: x)),
      f('左', _prefs.leftMargin, (x) => _prefs.copyWith(marginLeft: x)),
      f('右', _prefs.rightMargin, (x) => _prefs.copyWith(marginRight: x)),
    ];
  }
}

/// 带滑杆 + 手动输入（限制范围）的边距/内边距编辑行。
class _PadField extends StatelessWidget {
  const _PadField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onCommitted,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommitted;

  double get _clamped => value.clamp(min, max).toDouble();

  void _step(double delta) {
    final next = (value + delta).clamp(min, max).toDouble();
    onChanged(next);
    onCommitted(next);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: AppText(label, style: const TextStyle(fontSize: 13)),
        ),
        SizedBox(
          width: 30,
          height: 30,
          child: IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            onPressed: () => _step(-1),
            icon: const Icon(CupertinoIcons.minus),
          ),
        ),
        Expanded(
          child: AppControls.slider(
            context,
            value: _clamped,
            min: min,
            max: max,
            divisions: (max - min).round().clamp(1, 400),
            onChanged: (x) => onChanged(x.clamp(min, max).toDouble()),
            onChangeEnd: (x) => onCommitted(x.clamp(min, max).toDouble()),
          ),
        ),
        SizedBox(
          width: 30,
          height: 30,
          child: IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            onPressed: () => _step(1),
            icon: const Icon(CupertinoIcons.plus),
          ),
        ),
        SizedBox(
          width: 46,
          child: AppText(
            '${_clamped.round()} px',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
