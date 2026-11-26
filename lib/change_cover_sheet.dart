import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'book_documents.dart';
import 'book_sources/book_source_library.dart';
import 'book_sources/book_source_scope_sheet.dart';
import 'book_sources/book_source_search_scope.dart';
import 'catalog.dart';
import 'cover_images.dart';
import 'feature_pages.dart' show confirmNovelAction;
import 'personal_images.dart';

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
  var _scope = const BookSourceSearchScope.all();
  String _album = '我的封面';
  String _status = '正在读取候选';
  List<Novel> _items = [];
  bool _searching = false, _saving = false, _ready = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final text = (await SharedPreferences.getInstance()).getString(_scopeKey);
      if (!mounted) return;
      if (text != null) {
        _scope = BookSourceSearchScope.fromJson(jsonDecode(text));
      }
      if (!widget.offline) await widget.library?.prepare();
    } on Object catch (error) {
      debugPrint('封面候选初始化失败：$error');
    }
    if (mounted) _refresh();
  }

  void _refresh() {
    final library = widget.library;
    final cached = library?.cachedCoverCandidates(widget.book, _scope) ?? [];
    setState(() {
      _ready = true;
      _items = _merge(cached);
      _status = widget.offline
          ? '当前离线'
          : library == null
          ? '当前没有可用书源'
          : '已读取本机候选';
    });
    if (!widget.offline && library != null && _items.length <= 1) {
      unawaited(_search());
    }
  }

  String _key(Novel book) => '${book.source?.sourceKey}\u0000${book.coverUrl}';
  List<Novel> _merge(Iterable<Novel> books) => {
    for (final book in books)
      if (book.coverUrl?.isNotEmpty == true) _key(book): book,
  }.values.toList();

  Future<void> _search() async {
    final library = widget.library;
    if (library == null || widget.offline) return;
    final generation = ++_generation;
    bool current() => mounted && generation == _generation;
    final cached = library.cachedCoverCandidates(widget.book, _scope);
    setState(() {
      _searching = true;
      _status = '正在搜索同名同作者的封面';
    });
    try {
      final result = await library.searchSourceCandidates(
        widget.book,
        checkAuthor: true,
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
          _status =
              '找到 ${_items.length} 张候选封面${result.failedSources > 0 ? ' · ${result.failedSources} 个书源失败' : ''}';
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
    try {
      await (await SharedPreferences.getInstance()).setString(
        _scopeKey,
        jsonEncode(result.toJson()),
      );
    } on Object {
      if (mounted) showNovelFeedback(context, '本次范围已应用，但未保存');
    }
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

  Future<void> _albumMenu(BuildContext anchor) async {
    final name = _album;
    final action = await showGlassMenu<bool>(
      context: anchor,
      reduceMotion: widget.reduceMotion,
      builder: (menu) => GlassMenuItem(
        label: '删除图集',
        icon: CupertinoIcons.trash,
        onPressed: () => Navigator.pop(menu, true),
      ),
    );
    if (!mounted || action != true) return;
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

  Widget _grid(int count, Widget Function(int index) tile) =>
      SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: .66,
        ),
        itemCount: count,
        itemBuilder: (_, index) => tile(index),
      );

  Widget _tile(
    String key,
    String label,
    Future<Uint8List> Function() read,
    Future<String?> Function() choose,
  ) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      onTap: () => _choose(choose),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _CoverPreview(
                key: ValueKey((key, _generation)),
                read: read,
              ),
            ),
          ),
          AppText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final albums = {_album, ...store.albums};
    final images = store.album(_album);
    final library = widget.library;
    return AbsorbPointer(
      absorbing: _saving,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ArchiveSection(title: '更换封面', code: 'BOOK / COVER'),
                      if (_saving) const LinearProgressIndicator(),
                      Wrap(
                        spacing: 8,
                        children: [
                          GlassTextButton(
                            onPressed: () =>
                                Navigator.pop(context, PersonalCovers.original),
                            child: const AppText('恢复原封面'),
                          ),
                          GlassTextButton(
                            onPressed: () => Navigator.pop(
                              context,
                              PersonalCovers.defaultCover,
                            ),
                            child: const AppText('使用默认文字封面'),
                          ),
                          if (!widget.offline)
                            GlassTextButton(
                              onPressed: () => _choose(() async {
                                final url = await _input(url: true);
                                return url == null
                                    ? null
                                    : store.save(
                                        await prepareCoverFromUrl(url),
                                      );
                              }),
                              child: const AppText('输入图片地址'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const ArchiveSection(
                        title: '封面图集',
                        code: 'COVER / ALBUMS',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final name in albums)
                            GlassTextButton(
                              compact: true,
                              selected: _album == name,
                              onPressed: () => setState(() => _album = name),
                              child: AppText(name),
                            ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          GlassTextButton(
                            onPressed: () => _choose(() => _import(_album)),
                            child: const AppText('从手机选图'),
                          ),
                          GlassTextButton(
                            onPressed: () => _choose(() async {
                              final name = await _input(url: false);
                              return name == null ? null : _import(name);
                            }),
                            child: const AppText('新建图集'),
                          ),
                          if (images.isNotEmpty)
                            GlassMenuAnchor(
                              child: Builder(
                                builder: (anchor) => CompactRowMenuButton(
                                  label: '图集操作',
                                  onPressed: () => _albumMenu(anchor),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (images.isNotEmpty)
                  _grid(
                    images.length,
                    (index) => _tile(
                      images[index],
                      '图集封面 ${index + 1}',
                      () => store.read(images[index]),
                      () async => images[index],
                    ),
                  )
                else
                  const SliverToBoxAdapter(
                    child: ContentNotice(
                      icon: CupertinoIcons.photo,
                      title: '图集暂无图片',
                      message: '从手机选图后即可在其他书籍中复用。',
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      const ArchiveSection(
                        title: '其他书源封面',
                        code: 'COVER / SOURCES',
                      ),
                      if (_ready && library != null)
                        Wrap(
                          spacing: 8,
                          children: [
                            GlassTextButton(
                              onPressed: _chooseScope,
                              child: AppText(_scope.describe(library.sources)),
                            ),
                            if (!widget.offline)
                              GlassTextButton(
                                onPressed: _searching
                                    ? () => setState(() {
                                        _stop();
                                        _status = '搜索已停止';
                                      })
                                    : _search,
                                child: AppText(_searching ? '停止搜索' : '重新搜索'),
                              ),
                          ],
                        ),
                      AppText(_status),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                if (_items.isEmpty && !_searching && _ready)
                  const SliverToBoxAdapter(
                    child: ContentNotice(
                      icon: CupertinoIcons.photo,
                      title: '没有候选封面',
                    ),
                  ),
                _grid(_items.length, (index) {
                  final book = _items[index];
                  return _tile(
                    _key(book),
                    book.source!.sourceName,
                    () => novelCoverBytes(
                      book,
                      original: true,
                      cachedOnly: widget.offline,
                    ),
                    () async => store.save(
                      await preparePersonalImageBytes(
                        await novelCoverBytes(
                          book,
                          original: true,
                          cachedOnly: widget.offline,
                        ),
                        cover: true,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverPreview extends StatefulWidget {
  const _CoverPreview({required super.key, required this.read});
  final Future<Uint8List> Function() read;
  @override
  State<_CoverPreview> createState() => _CoverPreviewState();
}

class _CoverPreviewState extends State<_CoverPreview> {
  late final _bytes = widget.read();
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (_, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Icon(CupertinoIcons.photo));
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
