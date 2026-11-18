import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_interactions.dart';
import 'app_search_field.dart';
import 'app_ui.dart';
import 'book_collection_layout.dart';
import 'catalog.dart';
import 'dock_layout.dart';
import 'feature_pages.dart';
import 'library_state.dart';
import 'book_categories.dart';
import 'local_book_removal.dart';
import 'local_books.dart';
import 'local_maintenance_page.dart';

Future<void> openLocalBookBatch(
  BuildContext context, {
  required LocalBookStore books,
  required LibraryState library,
  Set<int> selected = const {},
}) => pushNovelPage<void>(
  context,
  LocalBookBatchPage(books: books, library: library, selected: selected),
  reduceMotion: library.reduceMotion,
);

class LocalBookBatchPage extends StatefulWidget {
  const LocalBookBatchPage({
    super.key,
    required this.books,
    required this.library,
    this.selected = const {},
  });
  final LocalBookStore books;
  final LibraryState library;
  final Set<int> selected;
  @override
  State<LocalBookBatchPage> createState() => _LocalBookBatchPageState();
}

class _LocalBookBatchPageState extends State<LocalBookBatchPage> {
  final _query = TextEditingController();
  late final _selected = {...widget.selected};
  bool _busy = false;
  (int, int)? _progress;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _toggle(int id) => setState(() {
    _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
  });

  Future<void> _move(Set<int> ids) async {
    if (_busy || ids.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final organization = widget.library.organization;
      final group = await chooseBookCategory(
        context,
        organization,
        bookIds: ids,
        reduceMotion: widget.library.reduceMotion,
      );
      if (group == null || !mounted) return;
      await organization.assignMany(ids, group);
      if (!mounted) return;
      setState(() => _selected.removeAll(ids));
      showNovelFeedback(
        context,
        '已将 ${ids.length} 本书移至「${organization.nameOf(group)}」',
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? '${error.message}，选择已保留'
              : '分类保存失败，选择已保留，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Set<int> ids) async {
    if (_busy || ids.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await chooseLocalBooksRemoval(
        context,
        ids: ids,
        books: widget.books,
        library: widget.library,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = (done, total));
        },
      );
      if (!mounted || result == null) return;
      setState(() {
        _selected.removeAll(result.removed);
        if (result.failed.isNotEmpty) {
          _error = '${result.failed.length} 本未能完成，已保留选择，请重试。';
        }
      });
      if (result.removed.isNotEmpty) {
        showNovelFeedback(
          context,
          result.choice == LocalBookRemoval.shelfOnly
              ? '已移出 ${result.removed.length} 本书'
              : '已删除 ${result.removed.length} 本书的本机文件',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '移除未完成，书籍选择已保留，请重试。');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Widget _dockActions(
    BuildContext context,
    Set<int> selected,
    String removeLabel,
    ({bool stacked, double height, double extent}) geometry,
  ) {
    final category = GlassPillButton(
      key: const ValueKey('local-batch-category'),
      icon: CupertinoIcons.folder,
      label: '移动分类',
      height: DockLayout.heightOf(context),
      iconSize: DockLayout.iconSize,
      fontSize: DockLayout.labelFontSize,
      onPressed: _busy || selected.isEmpty ? null : () => _move(selected),
    );
    final remove = GlassPillButton(
      key: const ValueKey('local-batch-remove'),
      icon: CupertinoIcons.trash,
      label: removeLabel,
      height: DockLayout.heightOf(context),
      iconSize: DockLayout.iconSize,
      fontSize: DockLayout.labelFontSize,
      onPressed: _busy || selected.isEmpty ? null : () => _remove(selected),
    );
    return ControlMaterialScope.chrome(
      child: SizedBox(
        key: const ValueKey('local-batch-action-dock'),
        height: geometry.height,
        child: geometry.stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  remove,
                  const SizedBox(height: DockLayout.actionGap),
                  category,
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 5, child: category),
                  const SizedBox(width: DockLayout.actionGap),
                  Expanded(flex: 7, child: remove),
                ],
              ),
      ),
    );
  }

  Future<void> _openPageMenu(
    BuildContext anchor, {
    required bool allSelected,
    required List<Novel> visible,
    required Set<int> selected,
  }) async {
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: widget.library.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_busy && selected.isNotEmpty)
            GlassMenuItem(
              label: '修复与整理',
              icon: CupertinoIcons.wand_stars,
              order: 0,
              onPressed: () => Navigator.pop(menu, 'maintenance'),
            ),
          if (!_busy && visible.isNotEmpty)
            GlassMenuItem(
              label: allSelected ? '取消全选' : '全选结果',
              icon: allSelected
                  ? CupertinoIcons.xmark_circle
                  : CupertinoIcons.checkmark_circle,
              order: 1,
              onPressed: () => Navigator.pop(menu, 'select-all'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'maintenance':
        await pushNovelPage<void>(
          context,
          LocalMaintenancePage(
            books: widget.books,
            library: widget.library,
            selected: selected,
          ),
          reduceMotion: widget.library.reduceMotion,
        );
      case 'select-all':
        setState(() {
          final ids = visible.map((book) => book.id);
          allSelected ? _selected.removeAll(ids) : _selected.addAll(ids);
        });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.books,
      widget.library.shelfViewChanges,
      widget.library.organization,
    ]),
    builder: (context, _) {
      final all = widget.books.books
          .where((book) => widget.library.localBookVisible(book.id))
          .toList(growable: false);
      final term = _query.text.trim().toLowerCase();
      final visible = all
          .where(
            (book) =>
                '${book.title}\n${book.author}'.toLowerCase().contains(term),
          )
          .toList();
      final selected = _selected.intersection(all.map((b) => b.id).toSet());
      final allSelected =
          visible.isNotEmpty &&
          visible.every((book) => selected.contains(book.id));
      final removeLabel = switch (_progress) {
        (final done, final total) => '正在处理 $done/$total',
        null => selected.isEmpty ? '请选择书籍' : '移除 ${selected.length} 本书',
      };
      final geometry = glassActionDockGeometry(
        context,
        primary: removeLabel,
        secondary: '移动分类',
      );
      final safe = MediaQuery.viewPaddingOf(context);
      return PopScope(
        canPop: !_busy,
        child: ArchiveFeaturePage(
          title: '批量整理',
          code: 'LOCAL / ORGANIZE',
          canPop: !_busy,
          actions: [
            GlassMenuAnchor(
              child: Builder(
                builder: (anchor) => GlassIconButton(
                  key: const ValueKey('local-batch-actions'),
                  icon: CupertinoIcons.ellipsis,
                  label: '批量整理操作',
                  onPressed: _busy
                      ? null
                      : () => _openPageMenu(
                          anchor,
                          allSelected: allSelected,
                          visible: visible,
                          selected: selected,
                        ),
                ),
              ),
            ),
          ],
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: featurePadding(context).copyWith(bottom: 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppSearchField(
                            inputKey: const ValueKey('local-batch-search'),
                            controller: _query,
                            hint: '搜索本地书名、作者',
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: AppText(
                                  '${visible.length} 本 · 已选 ${selected.length} 本',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Visibility(
                                visible: selected.isNotEmpty,
                                maintainSize: true,
                                maintainState: true,
                                maintainAnimation: true,
                                child: GlassTextButton(
                                  compact: true,
                                  onPressed: _busy || selected.isEmpty
                                      ? null
                                      : () => setState(_selected.clear),
                                  child: const AppText('清空选择'),
                                ),
                              ),
                            ],
                          ),
                          FeatureError(_error),
                          if (visible.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: ContentNotice(
                                icon: all.isEmpty
                                    ? CupertinoIcons.tray
                                    : CupertinoIcons.search,
                                title: all.isEmpty ? '没有可整理的本地书籍' : '没有匹配的书籍',
                                message: all.isEmpty
                                    ? '导入本地书籍后可在这里批量分类或移除。'
                                    : '调整搜索词后再试。',
                                secondaryAction: all.isEmpty
                                    ? null
                                    : GlassTextButton(
                                        compact: true,
                                        onPressed: () => setState(_query.clear),
                                        child: const AppText('清除搜索'),
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: BookCollectionSliver(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final book = visible[index],
                            chosen = selected.contains(book.id);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Semantics(
                            selected: chosen,
                            child: ContentPanel(
                              key: ValueKey('local-batch-book-${book.id}'),
                              onTap: _busy ? null : () => _toggle(book.id),
                              child: Row(
                                children: [
                                  NovelCover(book, width: 40, height: 56),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _BookLabel(
                                      book,
                                      category: widget.library.organization
                                          .nameOf(
                                            widget.library.organization.groupOf(
                                              book.id,
                                            ),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ArchiveIcon(
                                    chosen
                                        ? CupertinoIcons.checkmark_circle_fill
                                        : CupertinoIcons.circle,
                                    size: 23,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: geometry.extent + 20),
                  ),
                ],
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DockUnderlay(contentHeight: geometry.height),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    DockLayout.actionSideInset + safe.left,
                    0,
                    DockLayout.actionSideInset + safe.right,
                    DockLayout.bottomPaddingOf(context, viewPadding: true),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: DockLayout.actionMaxWidth,
                    ),
                    child: _dockActions(
                      context,
                      selected,
                      removeLabel,
                      geometry,
                    ),
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

class _BookLabel extends StatelessWidget {
  const _BookLabel(this.book, {required this.category});
  final Novel book;
  final String category;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppText(
        book.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
      if (book.author.isNotEmpty) ...[
        const SizedBox(height: 4),
        AppText(
          book.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: 4),
      AppText(
        category,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
