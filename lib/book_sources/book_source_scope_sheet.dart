import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_interactions.dart';
import '../app_palette.dart';
import '../app_ui.dart';
import 'book_source.dart';
import 'book_source_library.dart';
import 'book_source_search_scope.dart';

Future<BookSourceSearchScope?> showBookSourceScopeSheet({
  required BuildContext context,
  required BookSourceLibrary library,
  bool reduceMotion = false,
  BookSourceSearchScope? initialScope,
  bool persist = true,
}) => showJellySheet<BookSourceSearchScope>(
  context: context,
  reduceMotion: reduceMotion,
  heightFactor: .84,
  maxWidth: 720,
  builder: (_) => BookSourceScopeSheet(
    library: library,
    initialScope: initialScope,
    persist: persist,
  ),
);

/// Mirrors Legado's search scope sheet: all sources, groups, or individual
/// sources. Group and source selections are mutually exclusive.
class BookSourceScopeSheet extends StatefulWidget {
  const BookSourceScopeSheet({
    super.key,
    required this.library,
    this.initialScope,
    this.persist = true,
  });

  final BookSourceLibrary library;
  final BookSourceSearchScope? initialScope;
  final bool persist;

  @override
  State<BookSourceScopeSheet> createState() => _BookSourceScopeSheetState();
}

class _BookSourceScopeSheetState extends State<BookSourceScopeSheet> {
  late BookSourceSearchScope _scope =
      widget.initialScope ?? widget.library.searchScope;
  bool _preparing = true;
  bool _saving = false;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await widget.library.prepare();
    } finally {
      if (mounted) {
        setState(() {
          if (!_edited && widget.initialScope == null) {
            _scope = widget.library.searchScope;
          }
          _preparing = false;
        });
      }
    }
  }

  List<BookSource> get _enabled => [
    for (final source in widget.library.sources)
      if (source.enabled && source.supported && source.canSearch) source,
  ];

  List<String> get _groups {
    final groups = <String>{};
    for (final source in _enabled) {
      groups.addAll(source.groups);
    }
    return groups.toList()..sort();
  }

  void _selectAll() {
    setState(() {
      _edited = true;
      _scope = const BookSourceSearchScope.all();
    });
  }

  void _toggleGroup(String group) {
    final groups = Set<String>.of(_scope.groupNames);
    if (!groups.remove(group)) groups.add(group);
    setState(() {
      _edited = true;
      _scope = groups.isEmpty
          ? const BookSourceSearchScope.all()
          : BookSourceSearchScope.groups(groups);
    });
  }

  void _toggleSource(String key) {
    final keys = Set<String>.of(_scope.sourceKeys);
    if (!keys.remove(key)) keys.add(key);
    setState(() {
      _edited = true;
      _scope = keys.isEmpty
          ? const BookSourceSearchScope.all()
          : BookSourceSearchScope.sources(keys);
    });
  }

  Future<void> _apply() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (widget.persist) await widget.library.setSearchScope(_scope);
      if (mounted) Navigator.pop(context, _scope);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showNovelFeedback(context, '搜索范围保存失败，请稍后重试', haptic: HapticCue.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final sources = _enabled;
    final groups = _groups;
    return SizedBox(
      height: math.min(680, MediaQuery.sizeOf(context).height * .78),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: Row(
              children: [
                const Expanded(
                  child: ArchiveSection(
                    title: '搜索范围',
                    code: 'SOURCE / SEARCH SCOPE',
                  ),
                ),
                if (_preparing)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: CupertinoActivityIndicator(radius: 8),
                  ),
                GlassIconButton(
                  icon: CupertinoIcons.xmark,
                  label: '关闭搜索范围',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: AppText(
              '当前：${_scope.describe(widget.library.sources)} · '
              '${sources.length} 个可搜索书源 · 仅影响导入书源',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.5, color: muted),
            ),
          ),
          Expanded(
            child: sources.isEmpty
                ? SizedBox(
                    height: 180,
                    child: ContentNotice(
                      icon: CupertinoIcons.search,
                      title: '还没有可用书源',
                      message: '先在书源页导入并启用文字书源，再回来设置搜索范围。',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                    children: [
                      _scopeRow(
                        title: '全部书源',
                        subtitle: '包含所有已启用且支持搜索的书源',
                        selected: _scope.isAll,
                        onTap: _selectAll,
                      ),
                      if (groups.isNotEmpty) ...[
                        _sectionTitle(context, '按分组'),
                        for (final group in groups)
                          _scopeRow(
                            title: group,
                            subtitle: _groupSubtitle(group),
                            selected: _scope.groupNames.contains(group),
                            onTap: () => _toggleGroup(group),
                          ),
                      ],
                      _sectionTitle(context, '按书源'),
                      for (final source in sources)
                        _scopeRow(
                          title: source.name,
                          subtitle: source.group.isEmpty
                              ? source.typeLabel
                              : '${source.typeLabel} · ${source.group}',
                          selected: _scope.sourceKeys.contains(source.key),
                          onTap: () => _toggleSource(source.key),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
            child: Row(
              children: [
                Expanded(
                  child: AppText(
                    _scope.isAll
                        ? '将查询全部书源'
                        : _scope.isSource
                        ? '将查询 ${_scope.sourceKeys.length} 个书源'
                        : '将查询 ${_scope.groupNames.length} 个分组',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                GlassTextButton(
                  compact: true,
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const AppText('取消'),
                ),
                const SizedBox(width: 8),
                GlassTextButton(
                  compact: true,
                  onPressed: _saving ? null : _apply,
                  child: AppText(_saving ? '正在保存' : '应用'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _groupSubtitle(String group) {
    final count = _enabled
        .where((source) => source.groups.contains(group))
        .length;
    return '$count 个书源';
  }

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
    child: Text(title, style: ArchiveDesign.codeStyle(context)),
  );

  Widget _scopeRow({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ContentPanel(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AppText(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ArchiveIcon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              size: 20,
              color: selected
                  ? Theme.of(context).extension<AppTonalColors>()?.action
                  : scheme.onSurfaceVariant.withValues(alpha: .5),
            ),
          ],
        ),
      ),
    );
  }
}
