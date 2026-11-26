import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_ui.dart';
import '../app_interactions.dart';
import '../catalog.dart';
import '../feature_pages.dart';
import '../offline_repository.dart';
import 'batch_change_source.dart';
import 'book_source_library.dart';

/// 批量换源页面：勾选书籍 → 搜索候选 → 预览推荐来源与状态 → 批量切换。
///
/// 复用 [BatchChangeSourceRunner] 做调度；书籍以 id 为键，切换后进度、书签、
/// 分类与阅读配置按书保留（与单本换源一致）。
class BatchChangeSourcePage extends StatefulWidget {
  const BatchChangeSourcePage({
    super.key,
    required this.books,
    required this.library,
    required this.repository,
    this.onSwitched,
  });

  final List<Novel> books;
  final BookSourceLibrary library;
  final NovelRepository repository;
  final Future<void> Function(Novel previous, Novel switched)? onSwitched;

  @override
  State<BatchChangeSourcePage> createState() => _BatchChangeSourcePageState();
}

class _BatchChangeSourcePageState extends State<BatchChangeSourcePage> {
  late final List<BatchChangeSourceItem<Novel, Novel>> _items = [
    for (final book in widget.books)
      BatchChangeSourceItem<Novel, Novel>(book: book),
  ];
  late final Set<int> _selected = {
    for (var i = 0; i < _items.length; i++) i,
  };
  bool _busy = false;
  String _status = '';
  BatchChangeSourceResult? _result;

  BatchChangeSourceRunner<Novel, Novel> get _runner =>
      BatchChangeSourceRunner<Novel, Novel>(
        search: (book) async => (await widget.library.searchSourceCandidates(
          book,
          checkAuthor: true,
          scope: widget.library.changeSourceScope,
        )).items,
        apply: (book, candidate) async {
          final Novel switched;
          final repository = widget.repository;
          if (repository is OfflineNovelRepository) {
            switched = await repository.switchSource(book, candidate);
          } else {
            switched = await widget.library.switchSource(book, candidate);
          }
          try {
            await widget.onSwitched?.call(book, switched);
          } on Object {
            // 换源已经完成；书架状态同步失败不影响本批结果。
          }
        },
      );

  Future<void> _search() async {
    if (_busy) return;
    final indexes = _selected.toList()..sort();
    if (indexes.isEmpty) {
      _feedback('请先勾选要换源的书籍', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
      _status = '正在搜索候选…';
    });
    var done = 0;
    for (final i in indexes) {
      final resolved = await _runner.resolve(_items[i].book);
      done++;
      if (!mounted) return;
      setState(() {
        _items[i] = resolved;
        _status = '正在搜索候选… $done/${indexes.length}';
      });
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '搜索完成';
    });
  }

  Future<void> _applyAll() async {
    if (_busy) return;
    final indexes = _selected.toList()..sort();
    final toRun = [for (final i in indexes) _items[i]];
    if (toRun.every((item) => !item.canApply)) {
      _feedback('没有已匹配的候选，请先搜索候选', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在换源…';
      _result = null;
    });
    final result = await _runner.run(toRun);
    if (!mounted) return;
    setState(() {
      for (var k = 0; k < indexes.length; k++) {
        _items[indexes[k]] = toRun[k];
      }
      _busy = false;
      _result = result;
      _status = '完成';
    });
    _feedback(
      '已换源 ${result.changed} · 失败 ${result.failed} · 跳过 ${result.skipped}',
      error: result.failed > 0,
    );
  }

  void _feedback(String message, {bool error = false}) {
    if (!mounted) return;
    showNovelFeedback(
      context,
      message,
      haptic: error ? HapticCue.error : HapticCue.success,
    );
  }

  Future<void> _openActions(BuildContext anchor) async {
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassMenuItem(
            label: '全选',
            icon: CupertinoIcons.checkmark_square,
            order: 0,
            onPressed: () => Navigator.pop(menu, 'all'),
          ),
          GlassMenuItem(
            label: '全不选',
            icon: CupertinoIcons.square,
            order: 1,
            onPressed: () => Navigator.pop(menu, 'none'),
          ),
          GlassMenuItem(
            label: '搜索候选',
            icon: CupertinoIcons.search,
            order: 2,
            onPressed: () => Navigator.pop(menu, 'search'),
          ),
          GlassMenuItem(
            label: '开始换源',
            icon: CupertinoIcons.arrow_swap,
            order: 3,
            onPressed: () => Navigator.pop(menu, 'apply'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'all':
        setState(() => _selected.addAll([for (var i = 0; i < _items.length; i++) i]));
      case 'none':
        setState(_selected.clear);
      case 'search':
        await _search();
      case 'apply':
        await _applyAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ArchiveFeaturePage(
      title: '批量换源',
      code: 'SOURCE / BATCH',
      actions: [
        GlassMenuAnchor(
          child: Builder(
            builder: (anchor) => GlassIconButton(
              key: const ValueKey('batch-change-source-actions'),
              icon: CupertinoIcons.ellipsis,
              label: '批量换源操作',
              onPressed: () => _openActions(anchor),
            ),
          ),
        ),
      ],
      child: ListView(
        padding: featurePadding(context),
        children: [
          const ArchiveSection(title: '选择书籍', code: 'SOURCE / BOOKS'),
          const SizedBox(height: 8),
          AppText(
            '勾选要换源的书籍，搜索候选后确认每本推荐来源，再批量切换。'
            '切源后阅读进度、书签、分类与阅读配置按书保留。',
            style: TextStyle(fontSize: 12, height: 1.7, color: muted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppText(
                  '已选 ${_selected.length}/${_items.length} · '
                  '${_busy ? _status : (_result == null ? _status : '完成')}',
                  style: TextStyle(fontSize: 12, height: 1.4, color: muted),
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CupertinoActivityIndicator(radius: 8),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _row(context, i, muted),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int index, Color muted) {
    final item = _items[index];
    final selected = _selected.contains(index);
    final accent = Theme.of(context).colorScheme.primary;
    final subtitle = switch (item.status) {
      BatchChangeSourceStatus.pending => '未搜索',
      BatchChangeSourceStatus.matched =>
        '推荐：${item.selected?.source?.sourceName ?? '候选来源'}'
            '${item.candidates.length > 1 ? ' · 共 ${item.candidates.length} 个候选' : ''}',
      BatchChangeSourceStatus.notFound => '未找到候选',
      BatchChangeSourceStatus.done => '已切换',
      BatchChangeSourceStatus.failed => item.error ?? '换源失败',
    };
    return ContentPanel(
      onTap: _busy
          ? null
          : () => setState(() {
              if (selected) {
                _selected.remove(index);
              } else {
                _selected.add(index);
              }
            }),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  item.book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                AppText(
                  '${item.book.author} · $subtitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted),
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
            color: selected ? accent : muted,
          ),
        ],
      ),
    );
  }
}
