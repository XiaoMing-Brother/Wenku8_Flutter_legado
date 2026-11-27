import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_interactions.dart';
import 'app_search_field.dart';
import 'app_ui.dart';
import 'book_documents.dart';
import 'book_sources/book_source_library.dart';
import 'book_sources/book_source_scope_sheet.dart';
import 'book_sources/book_source_search_scope.dart';
import 'catalog.dart';
import 'cover_images.dart';
import 'feature_pages.dart' show confirmNovelAction;
import 'personal_images.dart';
import 'reader_illustrations.dart';

class ChangeCoverSheet extends StatefulWidget {
  const ChangeCoverSheet({
    super.key,
    required this.book,
    required this.library,
    required this.offline,
    required this.reduceMotion,
  });
  final Novel book;
  final BookSourceLibrary? library;
  final bool offline, reduceMotion;

  @override
  State<ChangeCoverSheet> createState() => _ChangeCoverSheetState();
}

class _ChangeCoverSheetState extends State<ChangeCoverSheet> {
  static const _scopeKey = 'coverSearch.scope.v1';
  final store = PersonalCovers.shared;
  late final _query = TextEditingController(text: _initialKeyword);
  late final _previews = ReaderIllustrationCache(request: _loadPreview);
  final _candidates = <String, Novel>{};
  final _imageHashes = <String, String>{};
  var _scope = const BookSourceSearchScope.all();
  String _album = '我的封面';
  String _status = '正在读取候选';
  List<Novel> _items = [];
  bool _searching = false, _saving = false, _ready = false;
  bool _checkAuthor = false, _showPersonal = false, _tabChosen = false;
  int _generation = 0;

  String get _initialKeyword => widget.book.source?.title.isNotEmpty == true
      ? widget.book.source!.title
      : widget.book.title;
  bool get _hasSources =>
      widget.library?.sources.any(
        (source) => source.enabled && source.supported,
      ) ??
      false;
  bool get _canSearch =>
      !widget.offline &&
      (widget.library?.sources.any(
            (source) => source.enabled && source.supported && source.canSearch,
          ) ??
          false);

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final text = (await SharedPreferences.getInstance()).getString(_scopeKey);
      await store.load();
      if (!mounted) return;
      if (text != null) {
        _scope = BookSourceSearchScope.fromJson(jsonDecode(text));
      }
    } on Object catch (error) {
      debugPrint('封面候选初始化失败：$error');
    }
    if (!mounted) return;
    _refresh(search: false);
    final generation = _generation;
    try {
      if (!widget.offline) await widget.library?.prepare();
    } on Object catch (error) {
      debugPrint('封面书源初始化失败：$error');
    }
    if (mounted && generation == _generation) _refresh();
  }

  List<Novel> _cached() =>
      widget.library?.cachedCoverCandidates(
        widget.book,
        _scope,
        keyword: _query.text.trim(),
        checkAuthor: _checkAuthor,
      ) ??
      [];

  void _refresh({bool search = true}) {
    setState(() {
      _ready = true;
      _items = _merge(_cached());
      if (!_tabChosen) {
        _showPersonal = !_hasSources || (widget.offline && _items.isEmpty);
      }
      _status = widget.offline
          ? '当前离线，仅显示本机候选'
          : !_hasSources
          ? '当前没有可用书源'
          : '已读取本机候选 · 同作者优先';
    });
    if (search && _canSearch) unawaited(_search());
  }

  String _key(Novel book) => '${book.source?.sourceKey}\u0000${book.coverUrl}';
  List<Novel> _merge(Iterable<Novel> books) {
    final unique = {
      for (final book in books)
        if (book.coverUrl?.isNotEmpty == true) _key(book): book,
    };
    _candidates.addAll(unique);
    final indexed = unique.values.indexed.toList();
    bool sameAuthor(Novel book) =>
        widget.book.author.trim().isNotEmpty &&
        sameSourceAuthor(book.author, widget.book.author);
    indexed.sort((a, b) {
      final author = (sameAuthor(a.$2) ? 0 : 1).compareTo(
        sameAuthor(b.$2) ? 0 : 1,
      );
      return author != 0 ? author : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  List<Novel> get _visibleItems {
    final seen = <String>{};
    return [
      for (final book in _items)
        if (_imageHashes[_key(book)] == null ||
            seen.add(_imageHashes[_key(book)]!))
          book,
    ];
  }

  Future<Uint8List> _loadPreview(String key) async {
    final book = _candidates[key];
    final bytes = book == null
        ? await store.read(key)
        : await novelCoverBytes(
            book,
            original: true,
            cachedOnly: widget.offline,
          );
    if (mounted && book != null) {
      final hash = sha256.convert(bytes).toString();
      if (_imageHashes[key] != hash) {
        setState(() => _imageHashes[key] = hash);
      }
    }
    return bytes;
  }

  Future<void> _search() async {
    final library = widget.library;
    if (library == null || !_canSearch) return;
    final keyword = _query.text.trim();
    if (keyword.isEmpty) {
      showNovelFeedback(context, '请输入书名后搜索');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final generation = ++_generation;
    bool current() => mounted && generation == _generation;
    final cached = _cached();
    setState(() {
      _items = _merge(cached);
      _searching = true;
      _status = '正在搜索封面';
    });
    try {
      final result = await library.searchSourceCandidates(
        widget.book,
        keyword: keyword,
        checkAuthor: _checkAuthor,
        scope: _scope,
        current: current,
        onProgress: (progress) {
          if (current()) {
            setState(() {
              _items = _merge([...cached, ...progress.items]);
              _status =
                  '正在搜索 · ${progress.completedSources} / ${progress.totalSources}';
            });
          }
        },
      );
      if (current()) {
        setState(() {
          _items = _merge([...cached, ...result.items]);
          _status = result.failedSources > 0
              ? '${result.failedSources} 个书源失败 · 可重试'
              : '搜索完成 · 同作者优先';
        });
      }
    } on Object {
      if (current()) setState(() => _status = '搜索失败，可重新搜索');
    } finally {
      if (current()) setState(() => _searching = false);
    }
  }

  void _stop() {
    ++_generation;
    if (_searching) unawaited(widget.library?.cancelSourceCandidateSearch());
    _searching = false;
  }

  @override
  void dispose() {
    _stop();
    _query.dispose();
    _previews.clearMemory();
    super.dispose();
  }

  Future<void> _chooseScope() async {
    final result = await showBookSourceScopeSheet(
      context: context,
      library: widget.library!,
      initialScope: _scope,
      persist: false,
      reduceMotion: widget.reduceMotion,
    );
    if (!mounted || result == null) return;
    _stop();
    _scope = result;
    _refresh();
    await _saveScope();
  }

  Future<String?> _input({required bool url}) async {
    var value = '';
    return showJellySheet<String>(
      context: context,
      reduceMotion: widget.reduceMotion,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          ArchiveSection(
            title: url ? '使用图片地址' : '新建封面图集',
            code: url ? 'COVER / URL' : 'COVER / ALBUM',
          ),
          const SizedBox(height: 16),
          TextField(
            autofocus: true,
            maxLength: url ? 4096 : 40,
            keyboardType: url ? TextInputType.url : TextInputType.text,
            decoration: InputDecoration(
              labelText: url ? 'HTTP 或 HTTPS 图片地址' : '图集名称',
            ),
            onChanged: (text) => value = text.trim(),
          ),
          GlassTextButton(
            onPressed: () {
              if (value.isNotEmpty) Navigator.pop(sheet, value);
            },
            child: AppText(url ? '使用这张图片' : '选择图片加入图集'),
          ),
        ],
      ),
    );
  }

  Future<String?> _import(String album) async {
    final documents = BookDocuments();
    final selection = await documents.pickImage();
    if (selection == null) return null;
    try {
      final bytes = await preparePersonalImage(selection.path!, cover: true);
      return await store.save(bytes, albumName: album);
    } finally {
      await documents.releaseBooks([selection]);
    }
  }

  Future<void> _deleteAlbum() async {
    final name = _album;
    if (!await confirmNovelAction(
      context,
      title: '删除图集？',
      confirmLabel: '删除图集',
      reduceMotion: widget.reduceMotion,
      message:
          '「$name」的 ${store.album(name).length} 张图片将从本机封面图集移除。已选作书籍封面或收录在其他图集中的图片会保留；如需重建此图集，请重新导入。',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      await store.removeAlbum(name);
      if (mounted) setState(() => _album = '我的封面');
    } on Object {
      if (mounted) showNovelFeedback(context, '图集删除失败，请重试');
    }
  }

  Future<void> _menu(BuildContext anchor) async {
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: widget.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassMenuItem(
            label: '从相册选择',
            icon: CupertinoIcons.photo,
            onPressed: () => Navigator.pop(menu, 'pick'),
          ),
          GlassMenuItem(
            label: '恢复原封面',
            icon: CupertinoIcons.arrow_counterclockwise,
            order: 1,
            onPressed: () => Navigator.pop(menu, 'original'),
          ),
          GlassMenuItem(
            label: '使用默认文字封面',
            icon: CupertinoIcons.textformat,
            order: 2,
            onPressed: () => Navigator.pop(menu, 'default'),
          ),
          if (!widget.offline)
            GlassMenuItem(
              label: '输入图片地址',
              icon: CupertinoIcons.link,
              order: 3,
              onPressed: () => Navigator.pop(menu, 'url'),
            ),
          GlassMenuItem(
            label: '新建图集',
            icon: CupertinoIcons.folder_badge_plus,
            order: 4,
            onPressed: () => Navigator.pop(menu, 'album'),
          ),
          if (_hasSources) ...[
            GlassMenuItem(
              label: '搜索范围：${_scope.describe(widget.library!.sources)}',
              icon: CupertinoIcons.slider_horizontal_3,
              order: 5,
              onPressed: () => Navigator.pop(menu, 'scope'),
            ),
            if (widget.book.author.trim().isNotEmpty)
              GlassMenuItem(
                label: '仅同作者',
                selected: _checkAuthor,
                icon: CupertinoIcons.person,
                order: 6,
                onPressed: () => Navigator.pop(menu, 'author'),
              ),
          ],
          if (_showPersonal && store.album(_album).isNotEmpty)
            GlassMenuItem(
              label: '删除图集',
              icon: CupertinoIcons.trash,
              order: 7,
              onPressed: () => Navigator.pop(menu, 'delete'),
            ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'pick':
        await _choose(() => _import(_album));
      case 'original':
        Navigator.pop(context, PersonalCovers.original);
      case 'default':
        Navigator.pop(context, PersonalCovers.defaultCover);
      case 'url':
        await _choose(() async {
          final url = await _input(url: true);
          return url == null
              ? null
              : store.save(await prepareCoverFromUrl(url));
        });
      case 'album':
        await _choose(() async {
          final name = await _input(url: false);
          return name == null ? null : _import(name);
        });
      case 'scope':
        await _chooseScope();
      case 'author':
        _stop();
        _checkAuthor = !_checkAuthor;
        _refresh();
      case 'delete':
        await _deleteAlbum();
    }
  }

  void _resetSearch() {
    _stop();
    _query.text = _initialKeyword;
    _checkAuthor = false;
    _scope = const BookSourceSearchScope.all();
    _refresh();
    unawaited(_saveScope());
  }

  Future<void> _saveScope() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _scopeKey,
        jsonEncode(_scope.toJson()),
      );
    } on Object {
      if (mounted) showNovelFeedback(context, '本次范围已应用，但未保存');
    }
  }

  Future<void> _preview(String key) async {
    final urls = _showPersonal
        ? store.album(_album)
        : [for (final book in _visibleItems) _key(book)];
    await pushNovelPage<void>(
      context,
      ReaderIllustrationGallery(
        urls: urls,
        initialUrl: key,
        cache: _previews,
        title: '封面预览',
        fileNamePrefix: widget.book.title,
      ),
      reduceMotion: widget.reduceMotion,
    );
  }

  Future<void> _choose(Future<String?> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final key = await action();
      if (mounted && key != null) Navigator.pop(context, key);
    } on Object catch (error) {
      if (mounted) {
        showNovelFeedback(
          context,
          error is FormatException ? error.message : '封面读取失败，原封面未更改',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _grid(
    int count,
    Widget Function(int index) tile,
  ) => SliverGrid.builder(
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent:
          145 * (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(1, 1.4),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: .58 / (MediaQuery.textScalerOf(context).scale(12) / 12),
    ),
    itemCount: count,
    itemBuilder: (_, index) => tile(index),
  );

  Widget _tile(
    String key,
    String label,
    Future<String?> Function() choose, {
    String? subtitle,
  }) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      key: ValueKey('cover-tile-$key'),
      onTap: () => _choose(choose),
      onLongPress: () => _preview(key),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _CoverPreview(
                key: ValueKey(key),
                read: () => _previews.load(key),
                retry: () => _previews.evict(key),
              ),
            ),
          ),
          const SizedBox(height: 6),
          AppText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          if (subtitle != null)
            AppText(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final albums = {_album, ...store.albums};
    final images = store.album(_album);
    final items = _visibleItems;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AbsorbPointer(
      absorbing: _saving,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .75,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: ArchiveSection(
                              title: '更换封面',
                              code: 'BOOK / COVER',
                            ),
                          ),
                          GlassMenuAnchor(
                            child: Builder(
                              builder: (anchor) => GlassIconButton(
                                icon: CupertinoIcons.ellipsis,
                                label: '更多封面操作',
                                onPressed: () => _menu(anchor),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_hasSources)
                            AppControls.segments<bool>(
                              context,
                              groupValue: _showPersonal,
                              children: const {
                                false: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: AppText('推荐封面'),
                                ),
                                true: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: AppText('我的图片'),
                                ),
                              },
                              onValueChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _showPersonal = value;
                                  _tabChosen = true;
                                });
                              },
                            ),
                        ],
                      ),
                      if (!_showPersonal && _hasSources) ...[
                        const SizedBox(height: 12),
                        if (!widget.offline)
                          AppSearchField(
                            inputKey: const ValueKey('cover-search-keyword'),
                            controller: _query,
                            hint: '输入书名搜索封面',
                            onSubmitted: (_) => _search(),
                            trailing: GlassIconButton(
                              icon: _searching
                                  ? CupertinoIcons.stop
                                  : CupertinoIcons.search,
                              label: _searching ? '停止搜索' : '搜索封面',
                              onPressed: _searching
                                  ? () => setState(() {
                                      _stop();
                                      _status = '搜索已停止';
                                    })
                                  : _search,
                            ),
                          ),
                        const SizedBox(height: 8),
                        AppText(
                          '${items.length} 张 · $_status${_checkAuthor ? ' · 仅同作者' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: muted,
                          ),
                        ),
                      ],
                      if (_showPersonal) ...[
                        const SizedBox(height: 8),
                        if (albums.length > 1)
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final name in albums)
                                GlassTextButton(
                                  compact: true,
                                  selected: _album == name,
                                  onPressed: () =>
                                      setState(() => _album = name),
                                  child: AppText(name),
                                ),
                            ],
                          )
                        else
                          AppText(
                            '我的图片 · ${images.length} 张',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                      ],
                      const SizedBox(height: 6),
                      AppText(
                        '点按应用 · 长按预览',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      if (_saving || (_searching && !_showPersonal)) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                key: ValueKey(_showPersonal),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        if (_showPersonal)
                          if (images.isNotEmpty)
                            _grid(
                              images.length,
                              (index) => _tile(
                                images[index],
                                '图集封面 ${index + 1}',
                                () async => images[index],
                              ),
                            )
                          else
                            const SliverToBoxAdapter(
                              child: ContentNotice(
                                icon: CupertinoIcons.photo,
                                title: '还没有收藏的图片',
                                message: '从相册选择后即可用于当前书籍，也可在其他书籍中复用。',
                              ),
                            )
                        else ...[
                          if (items.isEmpty && !_searching && _ready)
                            SliverToBoxAdapter(
                              child: ContentNotice(
                                icon: CupertinoIcons.photo,
                                title: '没有找到候选封面',
                                message: widget.offline
                                    ? '可切换到我的图片，或从相册选择。'
                                    : '可修改书名、放宽匹配条件，或从相册选择。',
                                onRetry: widget.offline ? null : _search,
                                actionLabel: '重新搜索',
                                secondaryAction:
                                    _checkAuthor ||
                                        !_scope.isAll ||
                                        _query.text.trim() !=
                                            _initialKeyword.trim()
                                    ? GlassTextButton(
                                        onPressed: _resetSearch,
                                        child: const AppText('清除搜索条件'),
                                      )
                                    : null,
                              ),
                            ),
                          _grid(items.length, (index) {
                            final book = items[index];
                            final key = _key(book);
                            return _tile(
                              key,
                              book.title,
                              () async => store.save(
                                await preparePersonalImageBytes(
                                  await _previews.load(key),
                                  cover: true,
                                ),
                              ),
                              subtitle: [
                                if (book.author.isNotEmpty) book.author,
                                if (book.source != null)
                                  book.source!.sourceName,
                              ].join(' · '),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverPreview extends StatefulWidget {
  const _CoverPreview({
    required super.key,
    required this.read,
    required this.retry,
  });
  final Future<Uint8List> Function() read;
  final VoidCallback retry;
  @override
  State<_CoverPreview> createState() => _CoverPreviewState();
}

class _CoverPreviewState extends State<_CoverPreview> {
  late var _bytes = widget.read();
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (_, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: GlassTextButton(
            onPressed: () {
              widget.retry();
              setState(() => _bytes = widget.read());
            },
            child: const AppText('重试'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CupertinoActivityIndicator());
      }
      return Image.memory(
        snapshot.data!,
        cacheWidth: 240,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(CupertinoIcons.photo),
      );
    },
  );
}
