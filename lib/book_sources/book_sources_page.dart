import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_interactions.dart';
import '../app_palette.dart';
import '../app_search_field.dart';
import '../app_ui.dart';
import '../book_documents.dart';
import '../dock_layout.dart';
import '../feature_pages.dart';
import 'book_source.dart';
import 'book_source_downloader.dart';
import 'book_source_explore_layout.dart';
import 'book_source_library.dart';
import 'book_source_store.dart';
import 'batch_change_source_page.dart';
import '../catalog.dart';
import '../local_books.dart' show isLocalBook;

/// Source registry using the app's existing archive panels and glass controls.
class BookSourcesPage extends StatefulWidget {
  const BookSourcesPage({
    super.key,
    required this.library,
    this.books,
    this.repository,
    this.onSourceSwitched,
    this.onOpenBook,
  });

  final BookSourceLibrary library;

  /// 可选：书架已知书籍，用于「批量换源」入口；为 null 时不显示该入口。
  final List<Novel>? books;

  /// 可选：书籍仓库，批量换源时执行切换。
  final NovelRepository? repository;

  /// 可选：批量换源完成后同步书架进度、书签与元数据。
  final Future<void> Function(Novel previous, Novel switched)? onSourceSwitched;
  final void Function(BuildContext context, Novel book)? onOpenBook;

  @override
  State<BookSourcesPage> createState() => _BookSourcesPageState();
}

class _BookSourcesPageState extends State<BookSourcesPage> {
  final _text = TextEditingController();
  final _url = TextEditingController();
  final _query = TextEditingController();
  bool _preparing = false;
  bool _importing = false;
  bool _selecting = false;
  final Set<String> _selected = {};
  String _searchQuery = '';
  _SourceFilter _filter = _SourceFilter.all;
  String? _groupFilter;
  _SourceSort _sort = _SourceSort.importOrder;
  BookSource? _expandedSource;
  List<BookSourceExploreKind>? _exploreKinds;
  Object? _exploreError;
  bool _exploreLoading = false;
  BookSourceLoginState? _exploreLogin;
  bool _exploreLoginLoading = false;
  int _exploreRequest = 0;
  int _exploreLoginRequest = 0;
  final Map<String, Map<String, String>> _exploreValues = {};
  final Map<String, TextEditingController> _exploreControllers = {};
  final Map<String, FocusNode> _exploreFocusNodes = {};
  final Map<String, Timer> _exploreTimers = {};

  BookSourceLibrary get _library => widget.library;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    for (final timer in _exploreTimers.values) {
      timer.cancel();
    }
    for (final controller in _exploreControllers.values) {
      controller.dispose();
    }
    for (final focus in _exploreFocusNodes.values) {
      focus.dispose();
    }
    _text.dispose();
    _url.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_preparing) return;
    setState(() => _preparing = true);
    try {
      await _library.prepare();
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _openImportSheet({bool link = false}) async {
    final controller = link ? _url : _text;
    final result = await showJellySheet<BookSourceImportResult>(
      context: context,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      heightFactor: .86,
      maxWidth: 720,
      builder: (_) => _SourceImportSheet(
        link: link,
        controller: controller,
        library: _library,
      ),
    );
    if (!mounted || result == null) return;
    _reportImport(result);
  }

  void _reportImport(BookSourceImportResult result) {
    final skipped = result.skipped > 0 ? ' · 跳过 ${result.skipped}' : '';
    _feedback('新增 ${result.added} · 更新 ${result.updated}$skipped');
  }

  Future<void> _importFromFile() async {
    if (_importing) return;
    final documents = BookDocuments();
    BookDocumentSelection? selected;
    setState(() => _importing = true);
    try {
      selected = await documents.pickBookSource();
      if (!mounted || selected == null) return;
      final path = selected.path;
      if (path == null) throw const FormatException('无法读取所选书源文件');
      final file = File(path);
      final length = await file.length();
      if (length <= 0) throw const FormatException('书源文件为空');
      final text = _decodeBookSource(await file.readAsBytes());
      final result = await _library.importSources(text);
      if (mounted) _reportImport(result);
    } on Object catch (error) {
      if (mounted) _feedback(_sourceErrorMessage(error), error: true);
    } finally {
      if (selected != null) {
        try {
          await documents.releaseBooks([selected]);
        } on Object {
          // The import result is already committed; cache cleanup is best effort.
        }
      }
      if (mounted) setState(() => _importing = false);
    }
  }

  static String _decodeBookSource(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      return text.startsWith('\uFEFF') ? text.substring(1) : text;
    } on FormatException {
      throw const FormatException('书源文件不是 UTF-8 编码的 JSON');
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text ?? '';
    final text = raw.trim();
    if (!mounted) return;
    if (text.isEmpty) {
      _feedback('剪贴板中没有书源 JSON', error: true);
      return;
    }
    final link =
        text.length <= 4096 &&
        !text.contains('\n') &&
        (text.startsWith('https://') || text.startsWith('http://'));
    if (link) {
      _url.text = text;
    } else {
      _text.text = raw;
    }
    await _openImportSheet(link: link);
  }

  Future<void> _export({Set<String>? keys}) async {
    final text = _library.exportSources(keys: keys);
    if (text.trim() == '[]') {
      _feedback('还没有可导出的书源', error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    final count = keys?.length ?? _library.sources.length;
    if (mounted) _feedback('已复制 $count 个书源 JSON');
  }

  Future<void> _remove(BookSource source) async {
    final confirmed = await confirmNovelAction(
      context,
      title: '删除书源？',
      message: '「${source.name}」将从本机书源库中移除，已在本机的书源书籍记录会保留，但重新打开前需要再次导入该书源。',
      confirmLabel: '删除书源',
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
    if (!confirmed || !mounted) return;
    try {
      await _library.removeSource(source.key);
      if (mounted) _feedback('已删除「${source.name}」');
    } catch (error) {
      _feedback(_sourceErrorMessage(error), error: true);
    }
  }

  Future<void> _editSource(BookSource source) async {
    final edited = await showJellySheet<BookSource>(
      context: context,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      heightFactor: .92,
      maxWidth: 720,
      builder: (_) => _SourceEditorSheet(source: source),
    );
    if (!mounted || edited == null) return;
    try {
      await _library.updateSource(edited);
      if (mounted) _feedback('已保存「${edited.name}」');
    } catch (error) {
      _feedback(_sourceErrorMessage(error), error: true);
    }
  }

  Future<void> _removeSelected() async {
    final keys = _selectedKeys;
    if (keys.isEmpty) return;
    final confirmed = await confirmNovelAction(
      context,
      title: '删除书源？',
      message: '选中的 ${keys.length} 个书源将从本机书源库中移除，已在本机的书源书籍记录会保留。',
      confirmLabel: '删除书源',
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
    if (!confirmed || !mounted) return;
    try {
      await _library.removeSources(keys);
      if (!mounted) return;
      setState(() => _selected.removeAll(keys));
      _feedback('已删除 ${keys.length} 个书源');
    } catch (error) {
      _feedback(_sourceErrorMessage(error), error: true);
    }
  }

  List<BookSource> get _visibleSources {
    final query = _searchQuery.trim().toLowerCase();
    final values = [
      for (final source in _library.sources)
        if (_matchesFilter(source) && _matchesQuery(source, query)) source,
    ];
    switch (_sort) {
      case _SourceSort.name:
        values.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _SourceSort.update:
        values.sort((a, b) {
          final updated = b.lastUpdateTime.compareTo(a.lastUpdateTime);
          return updated != 0
              ? updated
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case _SourceSort.enabled:
        values.sort((a, b) {
          if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case _SourceSort.importOrder:
        break;
    }
    return values;
  }

  bool _matchesFilter(BookSource source) {
    if (_groupFilter != null && !source.groups.contains(_groupFilter)) {
      return false;
    }
    return switch (_filter) {
      _SourceFilter.all => true,
      _SourceFilter.enabled => source.enabled,
      _SourceFilter.disabled => !source.enabled,
    };
  }

  bool _matchesQuery(BookSource source, String query) {
    if (query.isEmpty) return true;
    return source.name.toLowerCase().contains(query) ||
        source.key.toLowerCase().contains(query) ||
        source.group.toLowerCase().contains(query) ||
        source.typeLabel.contains(query);
  }

  List<String> get _allGroups {
    final groups = <String>{};
    for (final source in _library.sources) {
      groups.addAll(source.groups);
    }
    return groups.toList()..sort();
  }

  Set<String> get _selectedKeys {
    final existing = {for (final source in _library.sources) source.key};
    return {
      for (final key in _selected)
        if (existing.contains(key)) key,
    };
  }

  void _toggleSelecting() {
    setState(() {
      _selecting = !_selecting;
      if (!_selecting) _selected.clear();
    });
  }

  void _toggleSelected(String key) {
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
    });
  }

  void _selectAllVisible() {
    final visible = _visibleSources.map((source) => source.key).toSet();
    final selected = _selectedKeys;
    setState(() {
      if (visible.isNotEmpty && visible.every(selected.contains)) {
        _selected.removeAll(visible);
      } else {
        _selected.addAll(visible);
      }
    });
  }

  Future<void> _setSelectedEnabled(bool enabled) async {
    final keys = _selectedKeys;
    if (keys.isEmpty) return;
    try {
      await _library.setSourcesEnabled(keys, enabled);
      if (mounted) _feedback('已${enabled ? '启用' : '停用'} ${keys.length} 个书源');
    } catch (error) {
      _feedback(_sourceErrorMessage(error), error: true);
    }
  }

  Future<void> _updateSelectedGroups({required bool add}) async {
    await _changeGroups(_selectedKeys, add: add);
  }

  Future<void> _changeGroups(Iterable<String> keys, {required bool add}) async {
    final selected = keys.toSet();
    if (selected.isEmpty) return;
    final selectedSources = [
      for (final source in _library.sources)
        if (selected.contains(source.key)) source,
    ];
    final List<String> groups;
    if (add) {
      groups = _allGroups;
    } else {
      groups = {for (final source in selectedSources) ...source.groups}.toList()
        ..sort();
    }
    if (!add && groups.isEmpty) {
      _feedback('选中的书源还没有分组', error: true);
      return;
    }
    final group = await showJellySheet<String>(
      context: context,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      heightFactor: .68,
      maxWidth: 560,
      builder: (_) => _GroupInputSheet(
        title: add ? '加入分组' : '移出分组',
        groups: groups,
        allowCreate: add,
      ),
    );
    if (group == null || group.trim().isEmpty || !mounted) return;
    try {
      await _library.updateSourceGroups(
        selected,
        addGroup: add ? group : null,
        removeGroup: add ? null : group,
      );
      if (!mounted) return;
      _feedback(add ? '已加入「$group」' : '已从「$group」移出');
    } catch (error) {
      _feedback(_sourceErrorMessage(error), error: true);
    }
  }

  Future<void> _chooseGroupFilter() async {
    final groups = _allGroups;
    if (groups.isEmpty) {
      _feedback('还没有分组', error: true);
      return;
    }
    final selected = await showJellySheet<String>(
      context: context,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      heightFactor: .66,
      maxWidth: 560,
      builder: (_) => _OptionPickerSheet<String>(
        title: '按分组筛选',
        selected: _groupFilter ?? '',
        options: [('', '全部分组'), for (final group in groups) (group, group)],
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _groupFilter = selected.isEmpty ? null : selected);
  }

  Future<void> _openSourceActions(BuildContext anchor) async {
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassMenuItem(
            label: '导入书源',
            icon: CupertinoIcons.folder,
            order: 0,
            onPressed: () => Navigator.pop(menu, 'file'),
          ),
          GlassMenuItem(
            label: '从链接导入',
            icon: CupertinoIcons.link,
            order: 1,
            onPressed: () => Navigator.pop(menu, 'link'),
          ),
          GlassMenuItem(
            label: '从剪贴板读取',
            icon: CupertinoIcons.doc_on_doc,
            order: 2,
            onPressed: () => Navigator.pop(menu, 'paste'),
          ),
          GlassMenuItem(
            label: '导出全部',
            icon: CupertinoIcons.square_arrow_up,
            order: 3,
            onPressed: () => Navigator.pop(menu, 'export'),
          ),
          GlassMenuItem(
            label: _preparing ? '正在准备书源引擎' : '重新检查书源引擎',
            icon: CupertinoIcons.refresh,
            order: 4,
            onPressed: () => Navigator.pop(menu, 'refresh'),
          ),
          if (widget.books?.isNotEmpty == true && widget.repository != null)
            GlassMenuItem(
              label: '批量换源书籍',
              icon: CupertinoIcons.arrow_swap,
              order: 5,
              onPressed: () => Navigator.pop(menu, 'batch'),
            ),
          if (_visibleSources.isNotEmpty)
            GlassMenuItem(
              label: '校验当前列表',
              icon: CupertinoIcons.checkmark_circle,
              order: 6,
              onPressed: () => Navigator.pop(menu, 'validate'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'file':
        await _importFromFile();
      case 'link':
        await _openImportSheet(link: true);
      case 'paste':
        await _paste();
      case 'export':
        await _export();
      case 'refresh':
        await _prepare();
      case 'batch':
        await _openBatch();
      case 'validate':
        await _openValidation(_visibleSources);
    }
  }

  Future<void> _openValidation(List<BookSource> sources) => showJellySheet<void>(
    context: context,
    reduceMotion: MediaQuery.disableAnimationsOf(context),
    heightFactor: .82,
    builder: (_) => _SourceCheckSheet(library: _library, sources: sources),
  );

  Future<void> _openBatch() async {
    final repository = widget.repository;
    if (repository == null) return;
    final books = (widget.books ?? const <Novel>[])
        .where((book) => book.source != null && !isLocalBook(book.id))
        .toList();
    if (books.isEmpty) {
      _feedback('没有可换源的联网书籍');
      return;
    }
    await pushNovelPage<void>(
      context,
      BatchChangeSourcePage(
        books: books,
        library: _library,
        repository: repository,
        onSwitched: widget.onSourceSwitched,
      ),
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
  }

  Future<void> _openFilterMenu(BuildContext anchor) async {
    final selected = await showGlassMenu<_SourceFilter>(
      context: anchor,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, value) in _SourceFilter.values.indexed)
            GlassMenuItem(
              label: value.label,
              selected: value == _filter,
              order: index,
              onPressed: () => Navigator.pop(menu, value),
            ),
        ],
      ),
    );
    if (mounted && selected != null) setState(() => _filter = selected);
  }

  Future<void> _openSortMenu(BuildContext anchor) async {
    final selected = await showGlassMenu<_SourceSort>(
      context: anchor,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, value) in _SourceSort.values.indexed)
            GlassMenuItem(
              label: value.label,
              selected: value == _sort,
              order: index,
              onPressed: () => Navigator.pop(menu, value),
            ),
        ],
      ),
    );
    if (mounted && selected != null) setState(() => _sort = selected);
  }

  Future<void> _openSourceMenu(BuildContext anchor, BookSource source) async {
    BookSourceLoginState? loginState;
    if (source.needsLogin || source.hasLoginCheck) {
      try {
        loginState = await _library
            .loginInfo(source)
            .timeout(const Duration(seconds: 3));
      } on Object {
        // 登录状态读取失败时仍保留登录入口，具体错误在登录弹层中展示。
      }
    }
    if (!mounted || !anchor.mounted) return;
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassMenuItem(
            label: '复制链接',
            icon: CupertinoIcons.doc_on_doc,
            order: 0,
            onPressed: () => Navigator.pop(menu, 'copy'),
          ),
          GlassMenuItem(
            label: '编辑书源',
            icon: CupertinoIcons.pencil,
            order: 1,
            onPressed: () => Navigator.pop(menu, 'edit'),
          ),
          GlassMenuItem(
            label: '加入分组',
            icon: CupertinoIcons.folder_badge_plus,
            order: 2,
            onPressed: () => Navigator.pop(menu, 'group'),
          ),
          if (source.groups.isNotEmpty)
            GlassMenuItem(
              label: '移出分组',
              icon: CupertinoIcons.folder,
              order: 3,
              onPressed: () => Navigator.pop(menu, 'ungroup'),
            ),
          if (source.needsLogin)
            GlassMenuItem(
              label: '登录书源',
              icon: CupertinoIcons.person_crop_circle,
              order: 4,
              onPressed: () => Navigator.pop(menu, 'login'),
            ),
          if (loginState?.loggedIn == true)
            GlassMenuItem(
              label: '退出登录',
              icon: CupertinoIcons.person_crop_circle_badge_minus,
              order: 5,
              onPressed: () => Navigator.pop(menu, 'logout'),
            ),
          if (source.hasLoginCheck)
            GlassMenuItem(
              label: '运行登录检测',
              icon: CupertinoIcons.checkmark_shield,
              order: 6,
              onPressed: () => Navigator.pop(menu, 'checkLogin'),
            ),
          if (source.supported && source.canSearch)
            GlassMenuItem(
              label: '调试已保存规则',
              icon: CupertinoIcons.search,
              order: 7,
              onPressed: () => Navigator.pop(menu, 'debug'),
            ),
          GlassMenuItem(
            label: '删除书源',
            icon: CupertinoIcons.trash,
            order: 8,
            onPressed: () => Navigator.pop(menu, 'delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: source.key));
        if (mounted) _feedback('已复制书源链接');
      case 'edit':
        await _editSource(source);
      case 'group':
        await _changeGroups([source.key], add: true);
      case 'ungroup':
        await _changeGroups([source.key], add: false);
      case 'login':
        await _login(source);
      case 'logout':
        await _logout(source);
      case 'checkLogin':
        await _checkLogin(source);
      case 'debug':
        await showJellySheet<void>(
          context: context,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          heightFactor: .78,
          builder: (_) => _SourceDebugSheet(library: _library, source: source),
        );
      case 'delete':
        await _remove(source);
    }
  }

  Future<void> _login(BookSource source) async {
    await showBookSourceLoginSheet(
      context,
      library: _library,
      source: source,
      onFeedback: _feedback,
    );
  }

  Future<void> _checkLogin(BookSource source) async {
    try {
      final state = await _library.checkLogin(source);
      if (!mounted) return;
      if (!state.checked) {
        _feedback('该书源没有配置登录检测');
        return;
      }
      _feedback(
        state.loggedIn
            ? '登录检测已执行，当前保存有登录 Header 或 Cookie'
            : '登录检测已执行，当前未保存登录 Header 或 Cookie',
      );
    } on Object catch (error) {
      _feedback(_sourceErrorMessage(error), error: true);
    }
  }

  Future<void> _logout(BookSource source) async {
    try {
      await _library.logout(source);
      if (mounted) _feedback('已退出「${source.name}」的登录');
    } on Object catch (error) {
      _feedback(_sourceErrorMessage(error), error: true);
    }
  }

  void _feedback(String message, {bool error = false}) {
    if (!mounted) return;
    showNovelFeedback(
      context,
      message,
      haptic: error ? HapticCue.error : null,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '书源',
    code: 'SOURCE / REGISTRY',
    actions: [
      GlassMenuAnchor(
        child: Builder(
          builder: (anchor) => GlassIconButton(
            key: const ValueKey('book-source-actions'),
            icon: CupertinoIcons.ellipsis,
            label: '书源操作',
            onPressed: () => _openSourceActions(anchor),
          ),
        ),
      ),
    ],
    child: AnimatedBuilder(
      animation: _library.changes,
      builder: (context, _) {
        final visible = _visibleSources;
        final padding = featurePadding(context).copyWith(bottom: 0);
        return Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSearchField(
                    inputKey: const ValueKey('book-source-search'),
                    controller: _query,
                    hint: '搜索名称、链接或分组',
                    onChanged: (value) =>
                        setState(() => _searchQuery = value.trim()),
                  ),
                  const SizedBox(height: 4),
                  _toolbar(context, visible.length),
                  const SizedBox(height: 6),
                  Expanded(
                    child: visible.isEmpty
                        ? _empty(context)
                        : ListView.separated(
                            key: const PageStorageKey('book-sources-list'),
                            padding: EdgeInsets.only(
                              bottom: _selecting
                                  ? DockLayout.underlayExtentOf(context) + 12
                                  : featurePadding(context).bottom,
                            ),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              final source = visible[index];
                              final expanded =
                                  !_selecting &&
                                  identical(_expandedSource, source);
                              return Column(
                                key: ValueKey(source.key),
                                children: [
                                  _sourcePanel(context, source, expanded),
                                  if (expanded) _sourceRankings(source),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            if (_selecting) ...[
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DockUnderlay(
                  contentHeight: DockLayout.heightOf(context),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    DockLayout.actionSideInset +
                        MediaQuery.viewPaddingOf(context).left,
                    0,
                    DockLayout.actionSideInset +
                        MediaQuery.viewPaddingOf(context).right,
                    DockLayout.bottomPaddingOf(context, viewPadding: true),
                  ),
                  child: SizedBox(
                    width: DockLayout.widthFor(4),
                    child: _selectionDock(context),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );

  Widget _toolbar(BuildContext context, int visibleCount) {
    final action = Theme.of(context).extension<AppTonalColors>()?.action;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final unavailable = !_preparing && !_library.engineAvailable;
    final status = _importing
        ? '正在导入书源'
        : _selecting
        ? '已选 ${_selectedKeys.length}'
        : _preparing
        ? '正在准备书源引擎'
        : unavailable
        ? '书源引擎不可用'
        : '${_library.enabledCount} 个已启用';
    final count = _selecting
        ? '$visibleCount 项可见'
        : '$visibleCount/${_library.sources.length}';
    final group = _groupFilter == null ? '' : ' · 分组：$_groupFilter';
    final scope = _library.searchScope.isAll
        ? ''
        : ' · 范围：${_library.searchScopeLabel}';
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: _engineMessage(),
              child: Text(
                '$status · $count$group$scope',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: unavailable
                      ? Theme.of(context).colorScheme.error
                      : muted,
                ),
              ),
            ),
          ),
          GlassMenuAnchor(
            child: Builder(
              builder: (anchor) => GlassIconButton(
                icon: CupertinoIcons.line_horizontal_3_decrease,
                label: '筛选：${_filter.label}',
                color: _filter == _SourceFilter.all ? null : action,
                onPressed: () => _openFilterMenu(anchor),
              ),
            ),
          ),
          GlassIconButton(
            icon: CupertinoIcons.folder,
            label: _groupFilter == null ? '分组筛选' : '分组：$_groupFilter',
            color: _groupFilter == null ? null : action,
            onPressed: _chooseGroupFilter,
          ),
          GlassMenuAnchor(
            child: Builder(
              builder: (anchor) => GlassIconButton(
                icon: CupertinoIcons.sort_down,
                label: '排序：${_sort.label}',
                color: _sort == _SourceSort.importOrder ? null : action,
                onPressed: () => _openSortMenu(anchor),
              ),
            ),
          ),
          GlassIconButton(
            icon: _selecting
                ? CupertinoIcons.xmark_circle_fill
                : CupertinoIcons.checkmark_circle,
            label: _selecting ? '完成多选' : '多选',
            color: _selecting ? action : null,
            onPressed: _toggleSelecting,
          ),
        ],
      ),
    );
  }

  String _engineMessage() {
    if (_preparing) return '首次打开时会同步已导入的书源。';
    if (!_library.engineAvailable) {
      final error = _library.prepareError;
      return error == null
          ? '当前构建未接入 Android 书源引擎，书源只能导入和管理。'
          : '引擎初始化失败：$error';
    }
    return '已启用 ${_library.enabledCount} 个可解析书源，'
        '搜索范围：${_library.searchScopeLabel}。';
  }

  Widget _empty(BuildContext context) => _library.sources.isEmpty
      ? ContentNotice(
          icon: CupertinoIcons.tray,
          title: appText(context, '还没有书源'),
          message: appText(
            context,
            '从右上角导入阅读（Legado）格式的书源 JSON 后，搜索结果会和文库结果一起显示。',
          ),
        )
      : ContentNotice(
          icon: CupertinoIcons.search,
          title: appText(context, '没有匹配的书源'),
          message: appText(context, '调整搜索词、启用状态或分组筛选后再试。'),
          secondaryAction: GlassTextButton(
            compact: true,
            onPressed: () => setState(() {
              _searchQuery = '';
              _query.clear();
              _filter = _SourceFilter.all;
              _groupFilter = null;
            }),
            child: const AppText('清除筛选'),
          ),
        );

  Widget _selectionDock(BuildContext context) {
    final keys = _selectedKeys;
    final visible = _visibleSources.map((source) => source.key).toSet();
    final allVisible = visible.isNotEmpty && visible.every(keys.contains);
    final selectedSources = [
      for (final source in _library.sources)
        if (keys.contains(source.key)) source,
    ];
    final allEnabled =
        selectedSources.isNotEmpty &&
        selectedSources.every((source) => source.enabled);
    return LiquidGlass(
      key: const ValueKey('book-source-selection-dock'),
      radius: DockLayout.heightOf(context) / 2,
      thickness: 16,
      padding: const EdgeInsets.symmetric(
        horizontal: DockLayout.horizontalInset,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: _selectionDockAction(
              context,
              icon: CupertinoIcons.check_mark,
              label: allVisible ? '取消全选' : '全选',
              onPressed: _selectAllVisible,
            ),
          ),
          Expanded(
            child: _selectionDockAction(
              context,
              icon: allEnabled
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.checkmark_circle,
              label: allEnabled ? '停用' : '启用',
              onPressed: keys.isEmpty
                  ? null
                  : () => _setSelectedEnabled(!allEnabled),
            ),
          ),
          Expanded(
            child: _selectionDockAction(
              context,
              icon: CupertinoIcons.trash,
              label: '删除',
              onPressed: keys.isEmpty ? null : _removeSelected,
              destructive: true,
            ),
          ),
          Expanded(
            child: GlassMenuAnchor(
              child: Builder(
                builder: (anchor) => _selectionDockAction(
                  context,
                  icon: CupertinoIcons.ellipsis,
                  label: '更多',
                  onPressed: () => _openSelectionMenu(anchor),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionDockAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = onPressed == null
        ? Theme.of(context).disabledColor
        : destructive
        ? scheme.error
        : Theme.of(context).extension<AppTonalColors>()?.action ??
              scheme.onSurface;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: JellyTapSurface(
        onTap: onPressed,
        child: SizedBox(
          height: DockLayout.heightOf(context),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ArchiveIcon(icon, size: DockLayout.iconSize, color: color),
                const SizedBox(height: DockLayout.labelGap),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AppText(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: DockLayout.labelFontSize,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSelectionMenu(BuildContext anchor) async {
    final keys = _selectedKeys;
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (keys.isNotEmpty) ...[
            GlassMenuItem(
              label: '启用',
              icon: CupertinoIcons.checkmark_circle,
              order: 0,
              onPressed: () => Navigator.pop(menu, 'enable'),
            ),
            GlassMenuItem(
              label: '停用',
              icon: CupertinoIcons.pause_fill,
              order: 1,
              onPressed: () => Navigator.pop(menu, 'disable'),
            ),
            GlassMenuItem(
              label: '加入分组',
              icon: CupertinoIcons.folder_badge_plus,
              order: 2,
              onPressed: () => Navigator.pop(menu, 'group'),
            ),
            GlassMenuItem(
              label: '移出分组',
              icon: CupertinoIcons.folder,
              order: 3,
              onPressed: () => Navigator.pop(menu, 'ungroup'),
            ),
            GlassMenuItem(
              label: '校验所选书源',
              icon: CupertinoIcons.checkmark_circle,
              order: 5,
              onPressed: () => Navigator.pop(menu, 'validate'),
            ),
            GlassMenuItem(
              label: '导出',
              icon: CupertinoIcons.square_arrow_up,
              order: 4,
              onPressed: () => Navigator.pop(menu, 'export'),
            ),
          ],
          GlassMenuItem(
            label: '完成多选',
            icon: CupertinoIcons.check_mark,
            order: 6,
            onPressed: () => Navigator.pop(menu, 'complete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'enable':
        await _setSelectedEnabled(true);
      case 'disable':
        await _setSelectedEnabled(false);
      case 'group':
        await _updateSelectedGroups(add: true);
      case 'ungroup':
        await _updateSelectedGroups(add: false);
      case 'export':
        await _export(keys: _selectedKeys);
      case 'validate':
        await _openValidation([
          for (final source in _library.sources)
            if (keys.contains(source.key)) source,
        ]);
      case 'complete':
        _toggleSelecting();
    }
  }

  void _toggleRankings(BookSource source) {
    if (identical(_expandedSource, source)) {
      _cancelExploreTimers();
      setState(() {
        _expandedSource = null;
        _exploreKinds = null;
        _exploreError = null;
        _exploreLoading = false;
        _exploreLogin = null;
        _exploreLoginLoading = false;
        _exploreRequest++;
        _exploreLoginRequest++;
      });
    } else {
      _loadRankings(source);
    }
  }

  void _loadRankings(BookSource source) {
    _cancelExploreTimers();
    final request = ++_exploreRequest;
    final loginRequest = ++_exploreLoginRequest;
    final ready = source.supported && source.enabled && source.canExplore;
    setState(() {
      _expandedSource = source;
      _exploreKinds = null;
      _exploreError = null;
      _exploreLoading = ready;
      _exploreLogin = null;
      _exploreLoginLoading = source.needsLogin;
    });
    if (source.needsLogin) {
      unawaited(_loadExploreLogin(source, loginRequest));
    }
    if (ready) unawaited(_fetchExploreKinds(source, request));
  }

  void _cancelExploreTimers() {
    for (final timer in _exploreTimers.values) {
      timer.cancel();
    }
    _exploreTimers.clear();
  }

  Future<void> _fetchExploreKinds(BookSource source, int request) async {
    try {
      final kinds = await _library.exploreKinds(
        source,
        values: _exploreValuesFor(source),
      );
      if (!mounted ||
          request != _exploreRequest ||
          !identical(source, _expandedSource)) {
        return;
      }
      setState(() {
        _exploreKinds = kinds;
        _exploreError = null;
        _exploreLoading = false;
        _syncExploreValues(source, kinds);
      });
    } on Object catch (error) {
      if (!mounted ||
          request != _exploreRequest ||
          !identical(source, _expandedSource)) {
        return;
      }
      setState(() {
        _exploreError = error;
        _exploreLoading = false;
      });
    }
  }

  Future<void> _reloadExploreKinds(BookSource source) async {
    if (!identical(source, _expandedSource)) return;
    final request = ++_exploreRequest;
    try {
      final kinds = await _library.exploreKinds(
        source,
        values: _exploreValuesFor(source),
      );
      if (!mounted ||
          request != _exploreRequest ||
          !identical(source, _expandedSource)) {
        return;
      }
      setState(() {
        _exploreKinds = kinds;
        _exploreError = null;
        _exploreLoading = false;
        _syncExploreValues(source, kinds);
      });
    } on Object catch (error) {
      if (!mounted ||
          request != _exploreRequest ||
          !identical(source, _expandedSource)) {
        return;
      }
      if (_exploreKinds == null) {
        setState(() {
          _exploreError = error;
          _exploreLoading = false;
        });
      } else {
        _feedback(_sourceErrorMessage(error), error: true);
      }
    }
  }

  Future<void> _loadExploreLogin(BookSource source, int request) async {
    try {
      final state = await _library
          .loginInfo(source)
          .timeout(const Duration(seconds: 3));
      if (!mounted ||
          request != _exploreLoginRequest ||
          !identical(source, _expandedSource)) {
        return;
      }
      setState(() => _exploreLogin = state);
    } on Object {
      // 登录状态读取失败时保留登录入口，具体错误在登录弹层中展示。
    } finally {
      if (mounted &&
          request == _exploreLoginRequest &&
          identical(source, _expandedSource)) {
        setState(() => _exploreLoginLoading = false);
      }
    }
  }

  Future<void> _refreshExploreLogin(BookSource source) async {
    if (!identical(source, _expandedSource)) return;
    final request = ++_exploreLoginRequest;
    setState(() => _exploreLoginLoading = true);
    await _loadExploreLogin(source, request);
  }

  Future<void> _loginFromExplore(BookSource source) async {
    await showBookSourceLoginSheet(
      context,
      library: _library,
      source: source,
      onFeedback: _feedback,
    );
    if (!mounted || !identical(source, _expandedSource)) return;
    await _refreshExploreLogin(source);
    await _reloadExploreKinds(source);
  }

  Map<String, String> _exploreValuesFor(BookSource source) =>
      _exploreValues.putIfAbsent(source.key, () => {});

  String _exploreKey(BookSource source, BookSourceExploreKind kind) =>
      '${source.key}\u0000${kind.title}';

  List<String> _exploreOptions(BookSourceExploreKind kind) => [
    for (final value in kind.chars)
      if (value.trim().isNotEmpty) value,
  ];

  TextEditingController _exploreController(
    BookSource source,
    BookSourceExploreKind kind,
  ) {
    final key = _exploreKey(source, kind);
    return _exploreControllers.putIfAbsent(
      key,
      () => TextEditingController(
        text: _exploreValuesFor(source)[kind.title] ?? kind.defaultValue,
      ),
    );
  }

  FocusNode _exploreFocus(BookSource source, BookSourceExploreKind kind) =>
      _exploreFocusNodes.putIfAbsent(
        _exploreKey(source, kind),
        () => FocusNode(),
      );

  void _syncExploreValues(
    BookSource source,
    List<BookSourceExploreKind> kinds,
  ) {
    final values = _exploreValuesFor(source);
    for (final kind in kinds) {
      if (kind.isText) {
        values.putIfAbsent(kind.title, () => kind.defaultValue);
        final key = _exploreKey(source, kind);
        final controller = _exploreControllers[key];
        final focus = _exploreFocusNodes[key];
        final value = values[kind.title] ?? '';
        if (controller != null &&
            focus?.hasFocus != true &&
            controller.text != value) {
          controller.value = TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          );
        }
        continue;
      }
      if (!kind.isSelect && !kind.isToggle) continue;
      final options = _exploreOptions(kind);
      if (options.isEmpty) continue;
      final current = values[kind.title];
      if (current == null || !options.contains(current)) {
        values[kind.title] = options.contains(kind.defaultValue)
            ? kind.defaultValue
            : options.first;
      }
    }
  }

  void _onExploreTextChanged(
    BookSource source,
    BookSourceExploreKind kind,
    String value,
  ) {
    _exploreValuesFor(source)[kind.title] = value;
    final key = _exploreKey(source, kind);
    _exploreTimers.remove(key)?.cancel();
    if (kind.action.trim().isEmpty) return;
    _exploreTimers[key] = Timer(const Duration(milliseconds: 600), () {
      _exploreTimers.remove(key);
      unawaited(_runExploreAction(source, kind));
    });
  }

  void _submitExploreText(BookSource source, BookSourceExploreKind kind) {
    final key = _exploreKey(source, kind);
    _exploreTimers.remove(key)?.cancel();
    unawaited(_runExploreAction(source, kind));
  }

  void _setExploreValue(
    BookSource source,
    BookSourceExploreKind kind,
    String value,
  ) {
    final values = _exploreValuesFor(source);
    if (values[kind.title] == value) return;
    setState(() => values[kind.title] = value);
    unawaited(_runExploreAction(source, kind));
  }

  void _cycleExploreToggle(BookSource source, BookSourceExploreKind kind) {
    final options = _exploreOptions(kind);
    if (options.isEmpty) return;
    final current = _exploreValuesFor(source)[kind.title];
    final index = options.indexOf(current ?? kind.defaultValue);
    final next = options[index < 0 ? 0 : (index + 1) % options.length];
    _setExploreValue(source, kind, next);
  }

  Future<void> _chooseExploreValue(
    BookSource source,
    BookSourceExploreKind kind,
  ) async {
    final options = _exploreOptions(kind);
    if (options.isEmpty) return;
    final selected = await showJellySheet<String>(
      context: context,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      heightFactor: .68,
      maxWidth: 560,
      builder: (_) => _OptionPickerSheet<String>(
        title: kind.label,
        code: 'SOURCE / FILTER',
        selected: _exploreValuesFor(source)[kind.title] ?? kind.defaultValue,
        options: [for (final option in options) (option, option)],
      ),
    );
    if (!mounted || selected == null) return;
    _setExploreValue(source, kind, selected);
  }

  Future<void> _runExploreAction(
    BookSource source,
    BookSourceExploreKind kind,
  ) async {
    final action = kind.action.trim();
    if (action.isEmpty) return;
    if (action.startsWith('http://') || action.startsWith('https://')) {
      final uri = Uri.tryParse(action);
      final opened =
          uri != null &&
          uri.host.isNotEmpty &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) _feedback('无法打开操作链接', error: true);
      return;
    }
    try {
      final result = await _library.exploreAction(
        source,
        action,
        values: _exploreValuesFor(source),
      );
      if (!mounted || !identical(source, _expandedSource)) return;
      if (result.values.isNotEmpty) {
        setState(() {
          _exploreValuesFor(source).addAll(result.values);
        });
      }
      await _reloadExploreKinds(source);
    } on Object catch (error) {
      if (mounted) _feedback(_sourceErrorMessage(error), error: true);
    }
  }

  void _openRanking(BookSource source, BookSourceExploreKind kind) {
    _cancelExploreTimers();
    pushNovelPage<void>(
      context,
      _BookSourceRankingPage(
        source: source,
        kind: kind,
        library: _library,
        values: Map.of(_exploreValuesFor(source)),
        onOpenBook: widget.onOpenBook,
      ),
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
  }

  Widget _sourceRankings(BookSource source) {
    if (!source.supported) {
      return _exploreNotice(
        icon: CupertinoIcons.list_bullet,
        title: '暂不支持此类型的榜单',
      );
    }
    if (!source.enabled) {
      return _exploreNotice(
        icon: CupertinoIcons.pause_circle,
        title: '启用书源后可查看榜单',
      );
    }
    if (source.exploreUrl.isEmpty) {
      return _exploreNotice(
        icon: CupertinoIcons.list_bullet,
        title: '此书源未配置榜单',
      );
    }
    if (!source.canExplore) {
      return _exploreNotice(
        icon: CupertinoIcons.eye_slash,
        title: '启用发现后可查看榜单',
      );
    }
    final error = _exploreError;
    final kinds = _exploreKinds ?? const <BookSourceExploreKind>[];
    final Widget content;
    if (_exploreLoading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CupertinoActivityIndicator()),
      );
    } else if (error != null) {
      content = ContentNotice(
        icon: CupertinoIcons.exclamationmark_circle,
        title: '榜单加载失败',
        message: _sourceErrorMessage(error),
        onRetry: () => _loadRankings(source),
      );
    } else if (kinds.isEmpty) {
      content = const ContentNotice(
        icon: CupertinoIcons.list_bullet,
        title: '此书源没有可用的榜单',
      );
    } else {
      final rows = buildBookSourceExploreRows(kinds);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, cell) in row.indexed) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(
                      flex: cell.span,
                      child: _exploreKindTile(source, cell.kind),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (source.needsLogin)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _exploreLoginNotice(source),
            ),
          content,
        ],
      ),
    );
  }

  Widget _exploreNotice({required IconData icon, required String title}) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: ContentNotice(icon: icon, title: title),
      );

  Widget _exploreLoginNotice(BookSource source) {
    final scheme = Theme.of(context).colorScheme;
    final action = Theme.of(context).extension<AppTonalColors>()?.action;
    final muted = scheme.onSurfaceVariant;
    final loggedIn = _exploreLogin?.loggedIn == true;
    final loading = _exploreLoginLoading;
    return ContentPanel(
      key: ValueKey('book-source-explore-login-${source.key}'),
      radius: 12,
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      backgroundColor: scheme.surfaceContainer,
      onTap: loading || loggedIn ? null : () => _loginFromExplore(source),
      child: Row(
        children: [
          ArchiveIcon(
            loggedIn
                ? CupertinoIcons.checkmark_shield_fill
                : CupertinoIcons.person_crop_circle,
            size: 16,
            color: loggedIn ? action : muted,
            animate: false,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppText(
              loggedIn ? '已登录，发现请求会携带登录信息' : '此书源支持登录，登录后可访问完整榜单',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.4, color: muted),
            ),
          ),
          const SizedBox(width: 8),
          if (loading)
            const CupertinoActivityIndicator(radius: 6)
          else if (!loggedIn)
            ArchiveIcon(
              CupertinoIcons.chevron_right,
              size: 12,
              color: muted,
              animate: false,
            ),
        ],
      ),
    );
  }

  Widget _exploreKindTile(BookSource source, BookSourceExploreKind kind) {
    if (kind.isText) return _exploreTextTile(source, kind);
    final value = _exploreValuesFor(source)[kind.title] ?? '';
    var label = kind.label.trim();
    IconData? trailing;
    VoidCallback? onTap;
    if (kind.isError) {
      onTap = () => _feedback(
        kind.url.isEmpty ? label : '$label\n${kind.url}',
        error: true,
      );
    } else if (kind.isSelect) {
      label = '$label $value'.trim();
      trailing = CupertinoIcons.chevron_down;
      onTap = () => _chooseExploreValue(source, kind);
    } else if (kind.isToggle) {
      label = '$value$label';
      trailing = CupertinoIcons.arrow_2_circlepath;
      onTap = () => _cycleExploreToggle(source, kind);
    } else if (kind.isButton) {
      if (kind.action.trim().isNotEmpty) {
        trailing = CupertinoIcons.chevron_right;
        onTap = () => unawaited(_runExploreAction(source, kind));
      }
    } else if ((kind.type.isEmpty || kind.type == 'url') &&
        kind.url.isNotEmpty) {
      onTap = () => _openRanking(source, kind);
    }
    return _ExploreKindTile(
      label: label,
      onTap: onTap,
      trailing: trailing,
      error: kind.isError,
    );
  }

  Widget _exploreTextTile(BookSource source, BookSourceExploreKind kind) {
    final scheme = Theme.of(context).colorScheme;
    final controller = _exploreController(source, kind);
    return ContentPanel(
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      backgroundColor: scheme.surfaceContainer,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 34),
        child: Center(
          child: TextField(
            key: ValueKey(
              'book-source-explore-text-${source.key}-${kind.title}',
            ),
            controller: controller,
            focusNode: _exploreFocus(source, kind),
            textAlign: TextAlign.center,
            maxLines: 1,
            textInputAction: TextInputAction.search,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: kind.label.trim(),
              hintStyle: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: scheme.onSurfaceVariant,
              ),
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (value) => _onExploreTextChanged(source, kind, value),
            onSubmitted: (_) => _submitExploreText(source, kind),
          ),
        ),
      ),
    );
  }

  Widget _sourcePanel(BuildContext context, BookSource source, bool expanded) {
    final selected = _selected.contains(source.key);
    final action = Theme.of(context).extension<AppTonalColors>()?.action;
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final host = Uri.tryParse(source.key)?.host ?? '';
    final details = <String>[
      if (source.groups.isNotEmpty) source.groups.join(' / '),
      source.typeLabel,
      if (source.supported && source.canExplore) '有榜单',
      if (source.needsLogin) '可登录',
      if (source.hasReviewRule) '支持段评',
      if (host.isNotEmpty) host,
      if (source.lastUpdateTime > 0) '更新 ${_dateLabel(source.lastUpdateTime)}',
      if (!source.supported) '暂不支持',
    ].join(' · ');
    return ContentPanel(
      key: ValueKey('book-source-${source.key}'),
      borderColor: selected
          ? action
          : expanded
          ? action?.withValues(alpha: .55)
          : null,
      borderWidth: selected ? 1.2 : .7,
      backgroundColor: selected
          ? action?.withValues(alpha: .045)
          : expanded
          ? scheme.secondaryContainer.withValues(alpha: .42)
          : null,
      onTap: _selecting
          ? () => _toggleSelected(source.key)
          : () => _toggleRankings(source),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: AppText(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: expanded ? action : null,
                        ),
                      ),
                    ),
                    if (!_selecting &&
                        source.supported &&
                        source.exploreUrl.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Semantics(
                        key: ValueKey('book-source-rankings-${source.key}'),
                        expanded: expanded,
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: Center(
                            child: expanded && _exploreLoading
                                ? const CupertinoActivityIndicator(radius: 5)
                                : AnimatedRotation(
                                    turns: expanded ? .25 : 0,
                                    duration:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : const Duration(milliseconds: 180),
                                    curve: Curves.easeOutCubic,
                                    child: ArchiveIcon(
                                      CupertinoIcons.chevron_right,
                                      size: 12,
                                      color: expanded ? action : muted,
                                      animate: false,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Tooltip(
                  message: source.key,
                  child: AppText(
                    details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.4, color: muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (_selecting)
            ArchiveIcon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              size: 20,
              color: selected ? action : muted,
            )
          else ...[
            if (source.supported)
              AppControls.toggle(
                context,
                value: source.enabled,
                liteGlass: true,
                onChanged: (value) async {
                  try {
                    await _library.setSourceEnabled(source.key, value);
                  } catch (error) {
                    _feedback(_sourceErrorMessage(error), error: true);
                  }
                },
              )
            else
              Tooltip(
                message: appText(context, '暂不支持此类型'),
                child: ArchiveIcon(
                  CupertinoIcons.eye_slash,
                  size: 18,
                  animate: false,
                  color: muted,
                ),
              ),
            GlassMenuAnchor(
              child: Builder(
                builder: (anchor) => CompactRowMenuButton(
                  label: '${source.name} 更多操作',
                  onPressed: () => _openSourceMenu(anchor, source),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _dateLabel(int value) {
    final date = DateTime.fromMillisecondsSinceEpoch(value);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

/// 与 Legado 发现页的 GlassCard 条目一致：胶囊形玻璃底、居中标签和尾部图标。
class _ExploreKindTile extends StatelessWidget {
  const _ExploreKindTile({
    required this.label,
    required this.onTap,
    required this.trailing,
    required this.error,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? trailing;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = error ? scheme.error : scheme.onSurface;
    return ContentPanel(
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      backgroundColor: scheme.surfaceContainer,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 34),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: trailing == null ? 6 : 18,
              ),
              child: AppText(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (trailing != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ArchiveIcon(
                    trailing!,
                    size: 11,
                    color: scheme.onSurfaceVariant,
                    animate: false,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BookSourceRankingPage extends StatefulWidget {
  const _BookSourceRankingPage({
    required this.source,
    required this.kind,
    required this.library,
    required this.values,
    required this.onOpenBook,
  });

  final BookSource source;
  final BookSourceExploreKind kind;
  final BookSourceLibrary library;
  final Map<String, String> values;
  final void Function(BuildContext context, Novel book)? onOpenBook;

  @override
  State<_BookSourceRankingPage> createState() => _BookSourceRankingPageState();
}

class _BookSourceRankingPageState extends State<_BookSourceRankingPage> {
  final _books = <int, Novel>{};
  final _scrollController = ScrollController();
  int _page = 0;
  bool _hasMore = false;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore ||
        _loading ||
        _error != null ||
        !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.hasContentDimensions && position.extentAfter <= 240) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = _page + 1;
      final result = await widget.library.explore(
        widget.source,
        widget.kind.url,
        page: page,
        values: widget.values,
      );
      if (!mounted) return;
      setState(() {
        final previousCount = _books.length;
        for (final book in result.items) {
          _books.putIfAbsent(book.id, () => book);
        }
        _page = page;
        _hasMore = result.hasMore && _books.length > previousCount;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = _books.values.toList();
    final error = _error;
    return ArchiveFeaturePage(
      title: widget.kind.label,
      code: 'SOURCE / RANKING',
      child: books.isEmpty
          ? Padding(
              padding: featurePadding(context),
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : ContentNotice(
                      icon: CupertinoIcons.book,
                      title: error == null ? '榜单暂无书籍' : '榜单加载失败',
                      message: error == null ? null : _sourceErrorMessage(error),
                      onRetry: error == null ? null : _load,
                    ),
            )
          : ListView.separated(
              controller: _scrollController,
              padding: featurePadding(context),
              itemCount: books.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                if (index == books.length) {
                  if (_loading) {
                    return const Center(child: CupertinoActivityIndicator());
                  }
                  if (error != null) {
                    return ContentNotice(
                      icon: CupertinoIcons.exclamationmark_circle,
                      title: '下一页加载失败',
                      message: _sourceErrorMessage(error),
                      onRetry: _load,
                    );
                  }
                  return _hasMore
                      ? Center(
                          child: GlassTextButton(
                            onPressed: _load,
                            child: const AppText('加载更多'),
                          ),
                        )
                      : const SizedBox.shrink();
                }
                final book = books[index];
                final openBook = widget.onOpenBook;
                return ContentPanel(
                  onTap: openBook == null ? null : () => openBook(context, book),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppText(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 5),
                      AppText(
                        [
                          if (book.author.isNotEmpty) book.author,
                          widget.source.name,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

String _sourceErrorMessage(Object error) {
  if (error is BookSourceImportException) return error.message;
  if (error is FormatException && error.message.toString().isNotEmpty) {
    return error.message.toString();
  }
  if (error is PlatformException && error.message != null) {
    return error.message!;
  }
  return '书源操作失败，请检查 JSON 或稍后重试';
}

class _SourceEditorSheet extends StatefulWidget {
  const _SourceEditorSheet({required this.source});

  final BookSource source;

  @override
  State<_SourceEditorSheet> createState() => _SourceEditorSheetState();
}

class _SourceCheckSheet extends StatefulWidget {
  const _SourceCheckSheet({required this.library, required this.sources});

  final BookSourceLibrary library;
  final List<BookSource> sources;

  @override
  State<_SourceCheckSheet> createState() => _SourceCheckSheetState();
}

class _SourceCheckSheetState extends State<_SourceCheckSheet> {
  final _query = TextEditingController(text: '我的');
  final _results = <String>[];
  Object? _run;
  String _status = '';

  @override
  void dispose() {
    _run = null;
    _query.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final term = _query.text.trim();
    if (_run != null || term.isEmpty) return;
    final run = Object();
    bool cancelled() => !mounted || !identical(_run, run);
    setState(() {
      _run = run;
      _results.clear();
      _status = '';
    });
    for (final source in widget.sources) {
      final result = await widget.library.checkTextSource(
        source,
        term,
        cancelled: cancelled,
        onStage: (stage) => setState(() => _status = '${source.name} · $stage'),
      );
      if (cancelled() || result == null) return;
      setState(() => _results.add(result));
    }
    setState(() {
      _run = null;
      _status = '校验完成';
    });
  }

  void _stop() => setState(() {
    _run = null;
    _status = '已停止，未完成的书源不计入结果';
  });

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    itemCount: _results.length + 1,
    separatorBuilder: (_, _) => const SizedBox(height: 14),
    itemBuilder: (context, index) {
      if (index == 0) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ArchiveSection(title: '文字书源校验', code: 'SOURCE / VALIDATION'),
            const SizedBox(height: 12),
            const AppText('逐源搜索并读取首本书的详情、目录和首章。优先用源内校验词；未命中不代表失效，不会更改分组或启用状态。'),
            const SizedBox(height: 14),
            TextField(
              controller: _query,
              enabled: _run == null,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _start(),
              decoration: const InputDecoration(labelText: '默认校验关键词'),
            ),
            const SizedBox(height: 14),
            AppText('已校验 ${_results.length}/${widget.sources.length}　$_status'),
            const SizedBox(height: 8),
            GlassTextButton(
              onPressed: _run != null ? _stop : (_query.text.trim().isEmpty ? null : _start),
              child: AppText(_run != null ? '停止校验' : '开始校验'),
            ),
          ],
        );
      }
      return ContentPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(widget.sources[index - 1].name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            AppText(_results[index - 1], maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 1.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    },
  );
}

class _SourceDebugSheet extends StatefulWidget {
  const _SourceDebugSheet({required this.library, required this.source});
  final BookSourceLibrary library;
  final BookSource source;

  @override
  State<_SourceDebugSheet> createState() => _SourceDebugSheetState();
}

class _SourceDebugSheetState extends State<_SourceDebugSheet> {
  final _query = TextEditingController();
  final _lines = <String>[];
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final term = _query.text.trim();
    if (_busy || term.isEmpty) return;
    setState(() { _busy = true; _lines.clear(); });
    var stage = '搜索';
    void report(String message) => setState(() => _lines.add('$stage：$message'));
    try {
      final library = widget.library;
      final page = await library.searchInSource(widget.source, term);
      if (!mounted) return;
      report('本页 ${page.items.length} 本');
      if (page.items.isEmpty || library is! NovelRepository) return;
      final repository = library as NovelRepository;
      stage = '详情';
      final book = await repository.detail(page.items.first);
      if (!mounted) return;
      report(book.title);
      stage = '目录';
      final chapters = await repository.chapters(book.id);
      if (!mounted) return;
      report('${chapters.length} 章');
      if (chapters.isEmpty) return;
      if (widget.source.resourceType != 0) {
        report('首项：${chapters.first.title}；请从阅读页打开媒体或文件');
        return;
      }
      stage = '正文';
      final body = await repository.chapterContent(book.id, chapters.first);
      if (mounted) report('${chapters.first.title} · ${body.length} 字符');
    } catch (error) {
      if (mounted) report(_sourceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    children: [
      const ArchiveSection(title: '调试已保存规则', code: 'SOURCE / DEBUG'),
      const SizedBox(height: 12),
      AppText('仅请求「${widget.source.name}」。将读取第一本搜索结果的详情、目录和首章；不会加入书架。'),
      const SizedBox(height: 14),
      TextField(controller: _query, enabled: !_busy, onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: '测试关键词'), onSubmitted: (_) => _run()),
      const SizedBox(height: 14),
      GlassTextButton(onPressed: _busy || _query.text.trim().isEmpty ? null : _run,
        child: AppText(_busy ? '正在调试…' : '开始调试')),
      if (_lines.isNotEmpty) ...[
        const SizedBox(height: 14),
        ContentPanel(child: AppText(_lines.join('\n'))),
      ],
    ],
  );
}

class _SourceEditorSheetState extends State<_SourceEditorSheet> {
  late final _name = TextEditingController(text: widget.source.name);
  late final _groups = TextEditingController(
    text: widget.source.groups.join(', '),
  );
  late final _search = TextEditingController(text: widget.source.searchUrl);
  late final _explore = TextEditingController(text: widget.source.exploreUrl);
  late final _initialRules = widget.source.ruleDocument;
  late final _rules = TextEditingController(text: _initialRules);
  String? _ruleError;
  late bool _enabled = widget.source.enabled;
  late bool _enabledExplore = widget.source.enabledExplore;

  @override
  void dispose() {
    _name.dispose();
    _groups.dispose();
    _search.dispose();
    _explore.dispose();
    _rules.dispose();
    super.dispose();
  }

  void _save() {
    var source = widget.source;
    if (_rules.text != _initialRules) {
      try {
        source = source.withRuleDocument(_rules.text);
      } on FormatException catch (error) {
        setState(() => _ruleError = '规则 JSON 无效：${error.message}');
        return;
      }
    }
    final groups = _groups.text
        .split(RegExp(r'[,;，；]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    Navigator.pop(
      context,
      source.withEdits(
        name: _name.text,
        groups: groups,
        searchUrl: _search.text,
        exploreUrl: _explore.text,
        enabled: _enabled,
        enabledExplore: _enabledExplore,
      ),
    );
  }

  Widget _switchRow(
    BuildContext context, {
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(title),
            const SizedBox(height: 3),
            AppText(
              description,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 16),
      AppControls.toggle(context, value: value, onChanged: onChanged),
    ],
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: ArchiveSection(title: '编辑书源', code: 'SOURCE / EDIT'),
            ),
            ArchiveIconButton(
              tooltip: '关闭编辑',
              onPressed: () => Navigator.pop(context),
              icon: const ArchiveIcon(CupertinoIcons.xmark, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const AppText(
          '可修改基本信息和解析规则；书源地址保持不变。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            key: const ValueKey('book-source-editor'),
            children: [
              TextFormField(
                key: const ValueKey('book-source-name'),
                controller: _name,
                maxLength: 500,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '名称',
                  helperText: '留空时使用源地址作为名称',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('book-source-rule-document'),
                controller: _rules,
                minLines: 3,
                maxLines: 12,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) {
                  if (_ruleError != null) setState(() => _ruleError = null);
                },
                decoration: InputDecoration(
                  labelText: '解析规则 JSON',
                  helperText: '可编辑搜索、发现、详情、目录和正文规则。省略规则组保留原值，设为 null 移除。',
                  helperMaxLines: 2,
                  errorText: _ruleError,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('book-source-groups'),
                controller: _groups,
                maxLength: 500,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '分组',
                  helperText: '多个分组用逗号分隔',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('book-source-search-url'),
                controller: _search,
                minLines: 1,
                maxLines: 3,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '搜索地址',
                  helperText: '可保留 {{key}}、{{page}} 等 Legado 模板',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('book-source-explore-url'),
                controller: _explore,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '发现地址',
                  helperText: '留空后该来源不会出现在发现页入口中',
                ),
              ),
              const SizedBox(height: 18),
              _switchRow(
                context,
                title: '启用书源',
                description: '停用后不参与搜索、发现和换源。',
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 12),
              _switchRow(
                context,
                title: '启用发现',
                description: '仅对已填写发现地址的书源生效。',
                value: _enabledExplore,
                onChanged: (value) => setState(() => _enabledExplore = value),
              ),
              const SizedBox(height: 18),
              ContentPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppText(
                      '源地址',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      widget.source.key,
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 6),
                    AppText(
                      '${widget.source.typeLabel}书源',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GlassTextButton(
                onPressed: () => Navigator.pop(context),
                child: const AppText('取消'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassTextButton(
                key: const ValueKey('book-source-editor-save'),
                onPressed: _save,
                child: const AppText('保存'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// 打开书源登录弹层；不支持网页登录或表单为空时通过 [onFeedback] 提示。
Future<void> showBookSourceLoginSheet(
  BuildContext context, {
  required BookSourceLibrary library,
  required BookSource source,
  required void Function(String message, {bool error}) onFeedback,
  bool? reduceMotion,
}) async {
  final animationsDisabled =
      reduceMotion ?? MediaQuery.disableAnimationsOf(context);
  BookSourceLoginState state;
  try {
    state = await library.loginInfo(source);
  } on Object catch (error) {
    if (context.mounted) onFeedback(_sourceErrorMessage(error), error: true);
    return;
  }
  if (!context.mounted) return;
  if (state.needsWebLogin) {
    final result = await showJellySheet<BookSourceLoginState>(
      context: context,
      reduceMotion: animationsDisabled,
      heightFactor: .58,
      maxWidth: 560,
      builder: (_) => BookSourceWebLoginSheet(
        source: source,
        library: library,
        initial: state,
      ),
    );
    if (!context.mounted) return;
    if (result == null) {
      onFeedback('已取消网页登录');
      return;
    }
    onFeedback(
      result.loggedIn ? '已登录「${source.name}」' : '网页登录完成，但未获取到 Cookie',
      error: !result.loggedIn,
    );
    return;
  }
  if (state.fields.isEmpty) {
    onFeedback('该书源没有可用的登录表单', error: true);
    return;
  }
  final result = await showJellySheet<BookSourceLoginState>(
    context: context,
    reduceMotion: animationsDisabled,
    heightFactor: .88,
    maxWidth: 640,
    builder: (_) =>
        BookSourceLoginSheet(source: source, library: library, initial: state),
  );
  if (!context.mounted || result == null) return;
  onFeedback(
    result.loggedIn ? '已登录「${source.name}」' : '已保存「${source.name}」的登录信息',
  );
}

class BookSourceLoginSheet extends StatefulWidget {
  const BookSourceLoginSheet({
    super.key,
    required this.source,
    required this.library,
    required this.initial,
  });

  final BookSource source;
  final BookSourceLibrary library;
  final BookSourceLoginState initial;

  @override
  State<BookSourceLoginSheet> createState() => _BookSourceLoginSheetState();
}

class _BookSourceLoginSheetState extends State<BookSourceLoginSheet> {
  final Map<String, String> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  final _fields = <BookSourceLoginField>[];
  final _selectOptions = <String, List<String>>{};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _values.addAll(widget.initial.values);
    final inputs = <String>{};
    for (final field in widget.initial.fields) {
      if (!field.isButton && !inputs.add(field.name)) continue;
      _fields.add(field);
      if (field.isButton) continue;
      final current = _values[field.name] ?? field.defaultValue;
      if (field.isSelect) {
        final options = field.chars
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList();
        if (options.isNotEmpty) {
          _selectOptions[field.name] = options;
          _values[field.name] = options.contains(current)
              ? current
              : options.contains(field.defaultValue)
              ? field.defaultValue
              : options.first;
          continue;
        }
      }
      if (field.isToggle) {
        final (onValue, offValue) = _toggleValues(field);
        _values[field.name] = current == offValue ? offValue : onValue;
        continue;
      }
      _values[field.name] = current;
      _controllers[field.name] = TextEditingController(text: current);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _runAction(BookSourceLoginField field) async {
    final action = field.action.trim();
    if (action.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (action.startsWith('http://') || action.startsWith('https://')) {
        final uri = Uri.tryParse(action);
        final opened = uri != null &&
            uri.host.isNotEmpty &&
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened && mounted) setState(() => _error = '无法打开登录操作链接');
      } else {
        await widget.library.loginAction(widget.source, action, values: _values);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = _sourceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    for (final entry in _controllers.entries) {
      _values[entry.key] = entry.value.text;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await widget.library.login(widget.source, _values);
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      Navigator.pop(context, state);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _sourceErrorMessage(error);
      });
    }
  }

  Widget _textField(BookSourceLoginField field) => TextField(
    key: ValueKey('book-source-login-${field.name}'),
    controller: _controllers[field.name],
    enabled: !_busy,
    obscureText: field.isPassword,
    autocorrect: false,
    enableSuggestions: !field.isPassword,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      labelText: field.title,
      border: const OutlineInputBorder(),
    ),
    onChanged: (value) => _values[field.name] = value,
  );

  Widget _selectField(BookSourceLoginField field) {
    final options = _selectOptions[field.name];
    if (options == null) return _textField(field);
    return GlassTextButton(
      key: ValueKey('book-source-login-${field.name}'),
      onPressed: _busy
          ? null
          : () async {
              final value = await showJellySheet<String>(
                context: context,
                reduceMotion: MediaQuery.disableAnimationsOf(context),
                heightFactor: .66,
                maxWidth: 560,
                builder: (_) => _OptionPickerSheet<String>(
                  title: field.title,
                  code: 'SOURCE / LOGIN OPTION',
                  selected: _values[field.name],
                  options: [for (final option in options) (option, option)],
                ),
              );
              if (mounted && value != null) {
                setState(() => _values[field.name] = value);
              }
            },
      child: AppText(
        '${field.title}：${_values[field.name]}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  (String, String) _toggleValues(BookSourceLoginField field) {
    final options = field.chars
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final onValue = options.firstOrNull ?? 'true';
    return (
      onValue,
      options.length > 1
          ? options[1]
          : onValue == 'false'
          ? 'true'
          : 'false',
    );
  }

  Widget _toggleField(BookSourceLoginField field) {
    final (onValue, offValue) = _toggleValues(field);
    final value = (_values[field.name] ?? onValue) != offValue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: AppText(field.title)),
          AppControls.toggle(
            context,
            value: value,
            onChanged: _busy
                ? null
                : (next) => setState(
                    () => _values[field.name] = next ? onValue : offValue,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buttonField(BookSourceLoginField field) => Align(
    alignment: Alignment.centerLeft,
    child: GlassTextButton(
      onPressed: _busy || field.action.isEmpty ? null : () => _runAction(field),
      child: AppText(field.title),
    ),
  );

  Widget _field(BookSourceLoginField field) {
    if (field.isButton) return _buttonField(field);
    if (field.isSelect) return _selectField(field);
    if (field.isToggle) return _toggleField(field);
    return _textField(field);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.min(620, MediaQuery.sizeOf(context).height * .86),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ArchiveSection(
                  title: '登录「${widget.source.name}」',
                  code: 'SOURCE / LOGIN',
                ),
              ),
              ArchiveIconButton(
                tooltip: '关闭登录',
                onPressed: _busy ? null : () => Navigator.pop(context),
                icon: const ArchiveIcon(CupertinoIcons.xmark, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppText(
            widget.initial.loggedIn
                ? '当前已保存登录信息。可重新填写并登录，或关闭后在书源菜单退出登录。'
                : '登录信息只保存在本机，并使用系统密钥加密；登录后的请求会自动携带登录 Header 与 Cookie。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              key: const ValueKey('book-source-login-form'),
              children: [
                ContentPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, field) in _fields.indexed) ...[
                        if (index > 0) const SizedBox(height: 12),
                        _field(field),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            AppText(
              _error!,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GlassTextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const AppText('取消'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassTextButton(
                  key: const ValueKey('book-source-login-submit'),
                  onPressed: _busy ? null : _submit,
                  child: AppText(_busy ? '正在登录…' : '登录'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class BookSourceWebLoginSheet extends StatefulWidget {
  const BookSourceWebLoginSheet({
    super.key,
    required this.source,
    required this.library,
    required this.initial,
  });

  final BookSource source;
  final BookSourceLibrary library;
  final BookSourceLoginState initial;

  @override
  State<BookSourceWebLoginSheet> createState() =>
      _BookSourceWebLoginSheetState();
}

class _BookSourceWebLoginSheetState extends State<BookSourceWebLoginSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await widget.library.webLogin(widget.source);
      if (!mounted) return;
      Navigator.pop(context, state);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _sourceErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loginTarget = _loginTarget();
    return SizedBox(
      height: math.min(390, MediaQuery.sizeOf(context).height * .54),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: ArchiveSection(
                    title: '网页登录',
                    code: 'SOURCE / WEB LOGIN',
                  ),
                ),
                ArchiveIconButton(
                  tooltip: '关闭网页登录',
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const ArchiveIcon(CupertinoIcons.xmark, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppText(
              widget.initial.loggedIn
                  ? '当前已保存登录信息。重新登录会覆盖旧 Cookie；应用只保存登录结果，不保存账号密码。'
                  : '登录页会在应用内打开，支持账号密码、验证码和网页内跳转。完成登录后返回并点击「完成」，应用只保存 Cookie；扫码、弹窗等依赖网页或外部 App 的流程可能不完整。',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            ContentPanel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ArchiveIcon(
                    CupertinoIcons.person_crop_circle,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          widget.source.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        AppText(
                          loginTarget,
                          maxLines: 3,
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
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              AppText(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: scheme.error,
                ),
              ),
            ],
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: GlassTextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const AppText('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassTextButton(
                    key: const ValueKey('book-source-web-login-open'),
                    onPressed: _busy ? null : _open,
                    child: AppText(_busy ? '正在打开…' : '打开网页登录'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _loginTarget() {
    final value = widget.initial.loginUrl.trim();
    if (value.startsWith('@js:') || value.startsWith('<js>')) {
      return '登录地址由书源脚本生成';
    }
    final uri = Uri.tryParse(value);
    final host = uri?.host ?? '';
    return host.isNotEmpty ? host : value;
  }
}

class _SourceImportSheet extends StatefulWidget {
  const _SourceImportSheet({
    required this.link,
    required this.controller,
    required this.library,
  });

  final bool link;
  final TextEditingController controller;
  final BookSourceLibrary library;

  @override
  State<_SourceImportSheet> createState() => _SourceImportSheetState();
}

class _SourceImportSheetState extends State<_SourceImportSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy) return;
    final text = widget.controller.text.trim();
    if (text.isEmpty) {
      setState(
        () => _error = widget.link ? '粘贴书源 JSON 链接后再导入' : '粘贴书源 JSON 后再导入',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = widget.link
          ? await widget.library.importFromUrl(text)
          : await widget.library.importSources(text);
      if (!mounted) return;
      widget.controller.clear();
      Navigator.pop(context, result);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _sourceErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.min(560, MediaQuery.sizeOf(context).height * .78),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(
                  widget.link ? '从链接导入' : '从剪贴板导入书源',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GlassIconButton(
                icon: CupertinoIcons.xmark,
                label: '关闭',
                onPressed: _busy ? null : () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.link)
            TextField(
              controller: widget.controller,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: appText(context, '书源 JSON 链接'),
                hintText:
                    'https://www.yckceo.com/yuedu/shuyuans/json/id/1335.json',
                helperText: appText(context, '合集页请打开具体合集，复制其中的“网络导入”地址'),
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            )
          else
            Expanded(
              child: TextField(
                controller: widget.controller,
                autofocus: true,
                enabled: !_busy,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: appText(context, '书源 JSON'),
                  hintText: appText(context, '支持单个书源、书源数组，或包含 sources 的对象'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GlassTextButton(
                compact: true,
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const AppText('取消'),
              ),
              const SizedBox(width: 8),
              GlassTextButton(
                compact: true,
                onPressed: _busy ? null : _submit,
                child: AppText(
                  _busy ? '正在导入' : (widget.link ? '下载并导入' : '确认导入'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _OptionPickerSheet<T> extends StatelessWidget {
  const _OptionPickerSheet({
    required this.title,
    required this.options,
    this.selected,
    this.code,
  });

  final String title;
  final List<(T, String)> options;
  final T? selected;
  final String? code;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.min(560, MediaQuery.sizeOf(context).height * .7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: code == null
                    ? AppText(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : ArchiveSection(title: title, code: code!),
              ),
              GlassIconButton(
                icon: CupertinoIcons.xmark,
                label: '关闭',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options[index];
              final active = option.$1 == selected;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context, option.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: AppText(
                            option.$2,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        if (active)
                          ArchiveIcon(
                            CupertinoIcons.check_mark,
                            size: 18,
                            color: Theme.of(
                              context,
                            ).extension<AppTonalColors>()?.action,
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
  );
}

class _GroupInputSheet extends StatefulWidget {
  const _GroupInputSheet({
    required this.title,
    required this.groups,
    required this.allowCreate,
  });

  final String title;
  final List<String> groups;
  final bool allowCreate;

  @override
  State<_GroupInputSheet> createState() => _GroupInputSheetState();
}

class _GroupInputSheetState extends State<_GroupInputSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.min(520, MediaQuery.sizeOf(context).height * .66),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: AppText(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GlassIconButton(
                icon: CupertinoIcons.xmark,
                label: '关闭',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.groups.isEmpty
              ? Center(
                  child: AppText(
                    widget.allowCreate ? '输入新分组名称' : '没有可用的分组',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: widget.groups.length,
                  itemBuilder: (context, index) {
                    final group = widget.groups[index];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, group),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          child: AppText(
                            group,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (widget.allowCreate)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: appText(context, '新分组名称'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GlassTextButton(
                  compact: true,
                  onPressed: _submit,
                  child: const AppText('添加'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

enum _SourceFilter {
  all('全部'),
  enabled('已启用'),
  disabled('未启用');

  const _SourceFilter(this.label);
  final String label;
}

enum _SourceSort {
  importOrder('导入顺序'),
  name('名称'),
  update('最近更新'),
  enabled('启用状态');

  const _SourceSort(this.label);
  final String label;
}
