import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';

/// 阅读器「更多」里的一个入口定义。
class ReaderMoreEntry {
  const ReaderMoreEntry({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

/// 阅读器右上角「⋯ 更多」弹窗：列出所有入口，点按执行；开关固定到底部栏；
/// 拖动右侧手柄可调整顺序（该顺序即底部栏顺序）。
class ReaderMoreSheet extends StatefulWidget {
  const ReaderMoreSheet({
    super.key,
    required this.entries,
    required this.dockActions,
    required this.onChanged,
  });

  final List<ReaderMoreEntry> entries;

  /// 当前固定的底部栏动作（有序）。
  final List<String> dockActions;

  /// 用户调整（开/关固定、拖动排序）后回调最新的底部栏动作顺序。
  final ValueChanged<List<String>> onChanged;

  @override
  State<ReaderMoreSheet> createState() => _ReaderMoreSheetState();
}

class _ReaderMoreSheetState extends State<ReaderMoreSheet> {
  late List<String> _order = _initialOrder();
  late final Set<String> _enabled = widget.dockActions.toSet();

  List<String> _initialOrder() {
    final known = widget.entries.map((e) => e.id).toSet();
    final ids = <String>[
      for (final id in widget.dockActions)
        if (known.contains(id)) id,
    ];
    for (final entry in widget.entries) {
      if (!ids.contains(entry.id)) ids.add(entry.id);
    }
    return ids;
  }

  ReaderMoreEntry _meta(String id) =>
      widget.entries.firstWhere((e) => e.id == id);

  /// 固定项按拖动的可见顺序即为底部栏顺序。
  List<String> get _dock => [
    for (final id in _order)
      if (_enabled.contains(id)) id,
  ];

  void _commit() => widget.onChanged(_dock);

  void _toggle(String id, bool show) {
    setState(() {
      if (show) {
        _enabled.add(id);
      } else {
        _enabled.remove(id);
      }
    });
    _commit();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final id = _order.removeAt(oldIndex);
      _order.insert(newIndex, id);
    });
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ReorderableListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      buildDefaultDragHandles: false,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ArchiveSection(title: '所有入口', code: 'READER / ACTIONS'),
          const SizedBox(height: 4),
          AppText(
            '点按立即执行；开关固定到底部栏；拖动右侧手柄可调整顺序。',
            style: TextStyle(fontSize: 12, height: 1.5, color: muted),
          ),
          const SizedBox(height: 8),
        ],
      ),
      itemCount: _order.length,
      onReorder: _reorder,
      itemBuilder: (context, index) {
        final id = _order[index];
        final entry = _meta(id);
        return Padding(
          key: ValueKey(id),
          padding: const EdgeInsets.only(bottom: 12),
          child: ContentPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            onTap: () => Navigator.pop(context, id),
            child: Row(
              children: [
                ArchiveIcon(entry.icon, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: AppText(
                    entry.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AppControls.toggle(
                  context,
                  value: _enabled.contains(id),
                  onChanged: (value) => _toggle(id, value),
                ),
                const SizedBox(width: 10),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ArchiveIcon(
                      CupertinoIcons.line_horizontal_3,
                      size: 18,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
