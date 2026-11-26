import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'book_documents.dart';
import 'book_list_import.dart';
import 'catalog.dart';
import 'feature_pages.dart';
import 'library_state.dart';
import 'pending_book.dart';

class BookListImportPage extends StatefulWidget {
  const BookListImportPage({
    super.key,
    required this.state,
    required this.repository,
  });

  final LibraryState state;
  final NovelRepository repository;

  @override
  State<BookListImportPage> createState() => _BookListImportPageState();
}

class _BookListImportPageState extends State<BookListImportPage> {
  bool _busy = false;
  bool _reading = false;
  String? _error;
  String? _sourceLabel;
  BookListDocument? _preview;
  _BookListImportResult? _result;

  Future<void> _chooseFile() async {
    if (_busy || _reading) return;
    final documents = BookDocuments();
    BookDocumentSelection? selected;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      selected = await documents.pickBookSource();
      if (!mounted || selected == null) return;
      final path = selected.path;
      if (path == null) throw const FormatException('无法读取所选文件');
      final file = File(path);
      final length = await file.length();
      if (length <= 0) throw const FormatException('书籍列表文件为空');
      if (length > maxBookListBytes) {
        throw const FormatException('书籍列表超过 16 MB，请分批导入');
      }
      final String text;
      try {
        text = utf8.decode(await file.readAsBytes());
      } on FormatException {
        throw const FormatException('书籍列表不是 UTF-8 编码的 JSON');
      }
      _loadText(text, source: selected.name);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _preview = null;
          _sourceLabel = null;
          _result = null;
          _error = _errorText(error);
        });
      }
    } finally {
      if (selected != null) {
        try {
          await documents.releaseBooks([selected]);
        } on Object {
          // The parsed preview is already in memory; cache cleanup is best effort.
        }
      }
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _paste() async {
    if (_busy || _reading) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) throw const FormatException('剪贴板中没有书籍列表 JSON');
      _loadText(text, source: '剪贴板');
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _preview = null;
          _sourceLabel = null;
          _result = null;
          _error = _errorText(error);
        });
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _loadText(String text, {required String source}) {
    try {
      final preview = parseBookList(text);
      setState(() {
        _preview = preview;
        _sourceLabel = source;
        _result = null;
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _preview = null;
        _sourceLabel = null;
        _result = null;
        _error = _errorText(error);
      });
    }
  }

  Future<void> _startImport() async {
    final preview = _preview;
    if (_busy || _reading || preview == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final shelfKeys = _shelfKeys();
      final pendingIds = <int>{};
      final pending = <PendingBook>[];
      var skipped = 0;
      for (final entry in preview.entries) {
        final key = _bookKey(entry.title, entry.author);
        if (shelfKeys.contains(key)) {
          skipped++;
          continue;
        }
        var id = pendingBookIdFor(entry.title, entry.author);
        for (var attempt = 0; attempt < 4096; attempt++) {
          final existing = widget.state.cachedNovel(id);
          final available =
              !pendingIds.contains(id) &&
              (existing == null ||
                  _bookKey(existing.title, existing.author) == key);
          if (available) break;
          id = nextPendingBookId(id);
        }
        pendingIds.add(id);
        pending.add(
          PendingBook(
            id: id,
            title: entry.title,
            author: entry.author,
            coverUrl: entry.coverUrl,
            customCoverUrl: entry.customCoverUrl,
            origin: entry.origin,
            originName: entry.originName,
            bookUrl: entry.bookUrl,
            addedAt: now - pending.length,
          ),
        );
        shelfKeys.add(key);
      }
      final added = pending.isEmpty
          ? 0
          : await widget.state.addPendingShelfBooks(pending);
      if (!mounted) return;
      setState(() {
        _result = _BookListImportResult(
          added: added,
          skipped: skipped,
          total: preview.entries.length,
        );
      });
      showNovelFeedback(
        context,
        added > 0 ? '已加入书架，点开时再匹配书源' : '书单中的书都已在书架',
        haptic: HapticCue.selection,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Set<String> _shelfKeys() {
    final keys = <String>{};
    for (final id in widget.state.shelf) {
      final book = widget.state.cachedNovel(id);
      if (book != null) keys.add(_bookKey(book.title, book.author));
    }
    return keys;
  }

  String _bookKey(String title, String author) =>
      '${sourceSearchTitleKey(title)}\u0000${_authorKey(author)}';

  String _authorKey(String value) => sourceAuthorName(
    value,
  ).replaceAll(RegExp(r'[\s\u3000]+'), '').toLowerCase();

  String _errorText(Object error) {
    if (error is FormatException && error.message.isNotEmpty) {
      return error.message;
    }
    return '无法读取书籍列表，请检查文件或剪贴板内容';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: ArchiveFeaturePage(
      title: '导入书籍列表',
      code: 'MIGRATION / BOOK LIST',
      canPop: !_busy,
      child: ListView(
        padding: featurePadding(context),
        children: [
          const ArchiveSection(
            title: '把 Legado 书架带过来',
            code: 'MIGRATION / INTRODUCTION',
          ),
          const SizedBox(height: 12),
          const AppText('支持 Legado 导出的完整书架 JSON，也支持 legado_md3 导出的书名、作者和简介列表。'),
          const SizedBox(height: 10),
          const AppText(
            '书单会先全部加入书架并标记为「待匹配」，导入时不联网。点开某一本时再优先使用原书源坐标；没有坐标则按书名、作者自动搜索。',
          ),
          const SizedBox(height: 24),
          FeatureEntry(
            key: const ValueKey('book-list-file'),
            title: '选择 JSON 文件',
            icon: CupertinoIcons.folder,
            subtitle: 'bookshelf.json / books.json',
            onTap: _busy || _reading ? null : _chooseFile,
          ),
          const SizedBox(height: 14),
          FeatureEntry(
            key: const ValueKey('book-list-paste'),
            title: '从剪贴板读取',
            icon: CupertinoIcons.doc_on_doc,
            subtitle: '粘贴 Legado 或 legado_md3 导出的 JSON',
            onTap: _busy || _reading ? null : _paste,
          ),
          if (_reading || _busy)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          FeatureError(_error),
          if (_preview case final preview?) ...[
            const SizedBox(height: 24),
            _previewPanel(context, preview),
          ],
          if (_result case final result?) ...[
            const SizedBox(height: 24),
            _resultPanel(context, result),
          ],
        ],
      ),
    ),
  );

  Widget _previewPanel(
    BuildContext context,
    BookListDocument preview,
  ) => ContentPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionHeader(context, '识别结果', '', code: 'MIGRATION / BOOK LIST'),
        const SizedBox(height: 12),
        AppText(
          '${preview.entries.length} 本可加入书架'
          '${preview.ignored > 0 ? ' · 跳过 ${preview.ignored} 条无效或重复记录' : ''}',
        ),
        if (_sourceLabel case final source?) ...[
          const SizedBox(height: 6),
          AppText(
            '来源：$source',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 10),
        AppText(
          preview.hasSourceCoordinates
              ? '已识别到 Legado 书源和书籍地址，点开时会优先按原坐标匹配。'
              : '未识别到书源地址，点开时会按书名和作者搜索。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        AppText(
          '导入后书架会显示「待匹配」，不需要等待搜索。',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        const AppText('书单预览', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (final entry in preview.entries.take(12))
          AppText(
            '· 《${entry.title}》'
            '${entry.author.isEmpty ? '' : ' / ${entry.author}'}',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        if (preview.entries.length > 12)
          AppText(
            '还有 ${preview.entries.length - 12} 本',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 18),
        GlassTextButton(
          key: const ValueKey('book-list-start'),
          onPressed: _busy || _reading ? null : _startImport,
          child: AppText(_result == null ? '加入书架' : '再次加入书架'),
        ),
      ],
    ),
  );

  Widget _resultPanel(
    BuildContext context,
    _BookListImportResult result,
  ) => ContentPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionHeader(context, '导入结果', '', code: 'MIGRATION / RESULT'),
        const SizedBox(height: 12),
        AppText(
          '已加入 ${result.added} 本 · 已在书架 ${result.skipped} 本'
          '${result.added + result.skipped == result.total ? '' : ' · 共 ${result.total} 本'}',
        ),
        const SizedBox(height: 6),
        AppText(
          result.added > 0 ? '待匹配书籍会在点开时自动搜索书源；也可以从行尾菜单重新匹配。' : '没有新增待匹配书籍。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _BookListImportResult {
  const _BookListImportResult({
    required this.added,
    required this.skipped,
    required this.total,
  });

  final int added;
  final int skipped;
  final int total;
}
