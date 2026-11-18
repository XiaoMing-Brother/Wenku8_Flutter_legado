import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'app_search_field.dart';
import 'book_documents.dart';
import 'book_import_limits.dart';
import 'feature_pages.dart';

class LocalScanSelection extends StatefulWidget {
  const LocalScanSelection({super.key, required this.snapshot});
  final BookScanSnapshot snapshot;
  @override
  State<LocalScanSelection> createState() => _LocalScanSelectionState();
}

class _LocalScanSelectionState extends State<LocalScanSelection> {
  final selected = <String>{}, formats = <String>{};
  final query = TextEditingController();
  late final searchIndex = {
    for (final book in widget.snapshot.books)
      book.token:
          '${book.name}\n${widget.snapshot.details[book.token]?.folder ?? ''}'
              .toLowerCase(),
  };
  late final counts = () {
    final result = <String, int>{};
    for (final book in widget.snapshot.books) {
      result.update(bookFormatKey(book.name), (n) => n + 1, ifAbsent: () => 1);
    }
    return result;
  }();
  late List<BookScanEntry> visible = widget.snapshot.books;
  void refilter() {
    final terms = query.text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    visible = widget.snapshot.books
        .where(
          (book) =>
              (formats.isEmpty || formats.contains(bookFormatKey(book.name))) &&
              terms.every(searchIndex[book.token]!.contains),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allVisibleSelected =
        visible.isNotEmpty && visible.every((e) => selected.contains(e.token));
    return ArchiveFeaturePage(
      title: '选择要导入的书籍',
      code: 'LOCAL / IMPORT SELECTION',
      actions: [
        GlassMenuAnchor(
          child: Builder(
            builder: (anchor) => GlassIconButton(
              key: const ValueKey('scan-select-all'),
              icon: CupertinoIcons.checkmark_circle,
              label: allVisibleSelected ? '取消全选' : '全选结果',
              onPressed: visible.isEmpty
                  ? null
                  : () async {
                      final action = await showGlassMenu<String>(
                        context: anchor,
                        reduceMotion: MediaQuery.disableAnimationsOf(context),
                        builder: (menu) => GlassMenuItem(
                          label: allVisibleSelected ? '取消全选' : '全选结果',
                          icon: allVisibleSelected
                              ? CupertinoIcons.xmark_circle
                              : CupertinoIcons.checkmark_circle,
                          onPressed: () => Navigator.pop(menu, 'toggle'),
                        ),
                      );
                      if (!mounted || action != 'toggle') return;
                      setState(() {
                        final tokens = visible.map((e) => e.token);
                        allVisibleSelected
                            ? selected.removeAll(tokens)
                            : selected.addAll(tokens);
                      });
                    },
            ),
          ),
        ),
      ],
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    featurePadding(context).top,
                    24,
                    16,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppSearchField(
                          inputKey: const ValueKey('scan-candidate-search'),
                          controller: query,
                          hint: '搜索文件名或文件夹',
                          onChanged: (_) => setState(refilter),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            GlassTextButton(
                              compact: true,
                              selected: formats.isEmpty,
                              key: const ValueKey('scan-filter-all'),
                              onPressed: () => setState(() {
                                formats.clear();
                                refilter();
                              }),
                              child: const AppText(
                                '全部格式',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            for (final entry in bookFormatLabels.entries)
                              if ((counts[entry.key] ?? 0) > 0)
                                GlassTextButton(
                                  compact: true,
                                  selected: formats.contains(entry.key),
                                  key: ValueKey('scan-filter-${entry.key}'),
                                  onPressed: () => setState(() {
                                    formats.contains(entry.key)
                                        ? formats.remove(entry.key)
                                        : formats.add(entry.key);
                                    refilter();
                                  }),
                                  child: AppText(
                                    '${entry.value} ${counts[entry.key]}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AppText(
                          '显示 ${visible.length} / ${widget.snapshot.books.length} 个文件 · 已选 ${selected.length} 个',
                          style: const TextStyle(fontSize: 12, height: 1.4),
                        ),
                        if (visible.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: ContentNotice(
                              icon: CupertinoIcons.search,
                              title: '没有匹配的文件',
                              message: '调整搜索词或格式筛选后再试。',
                              secondaryAction: GlassTextButton(
                                compact: true,
                                onPressed: () => setState(() {
                                  query.clear();
                                  formats.clear();
                                  refilter();
                                }),
                                child: const AppText('清除搜索和筛选'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final entry = visible[index],
                          details =
                              widget.snapshot.details[visible[index].token];
                      final chosen = selected.contains(entry.token),
                          size = details?.size;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Semantics(
                          selected: chosen,
                          child: ContentPanel(
                            key: ValueKey('scan-candidate-${entry.token}'),
                            onTap: () => setState(
                              () => chosen
                                  ? selected.remove(entry.token)
                                  : selected.add(entry.token),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ArchiveIcon(
                                  chosen
                                      ? CupertinoIcons.checkmark_circle_fill
                                      : CupertinoIcons.circle,
                                  size: 23,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AppText(
                                        entry.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.6,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      AppText(
                                        '${entry.name.split('.').last.toUpperCase()}${size == null || size < 0 ? '' : ' · ${(size / 1048576).toStringAsFixed(1)} MiB'}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.4,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (details?.folder.isNotEmpty ==
                                          true) ...[
                                        const SizedBox(height: 4),
                                        AppText(
                                          details!.folder,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: GlassPillButton(
                  key: const ValueKey('scan-import-selected'),
                  icon: CupertinoIcons.square_arrow_down,
                  label: selected.isEmpty
                      ? '请选择书籍'
                      : '导入 ${selected.length} 个文件',
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, selected.toSet()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
