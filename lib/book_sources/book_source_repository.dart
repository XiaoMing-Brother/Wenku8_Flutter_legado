import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException, rootBundle;

import '../book_identity.dart';
import '../catalog.dart';
import '../official_books.dart';
import 'book_source.dart';
import 'book_source_downloader.dart';
import 'book_source_images.dart';
import 'inline_review.dart';
import 'book_source_identity_store.dart';
import 'book_source_library.dart';
import 'book_source_reference.dart';
import 'book_source_search_scope.dart';
import 'book_source_store.dart';
import 'book_source_transport.dart';

/// Adapts the Android Legado engine to the app's existing repository contract.
/// This layer only converts data and identity; it never interprets rule syntax.
class BookSourceRepository extends NovelRepository
    implements BookSourceLibrary {
  /// 内置榜单来源的规则版本；修改 [assets/book_sources/builtin_sources.json]
  /// 后需要递增，已写入旧版本的用户才会重新导入。
  static const builtinSourcesVersion = 4;

  BookSourceRepository({
    required this.store,
    required this.identities,
    this.transport = const BookSourceTransport(),
    this.requestTimeout = const Duration(seconds: 15),
    this.concurrency = 8,
    BookSourceDownloader? downloader,
  }) : downloader = downloader ?? BookSourceDownloader();

  final BookSourceStore store;
  final BookSourceIdentityStore identities;
  final BookSourceTransport transport;
  final BookSourceDownloader downloader;
  final Duration requestTimeout;
  final int concurrency;
  final Map<int, Novel> _books = {};
  final Map<int, List<NovelChapter>> _chapters = {};
  Future<Map<int, String>>? _fanqieFontMap;
  bool _prepared = false;
  bool _engineAvailable = false;
  Object? _prepareError;
  Future<void>? _preparing;
  Object? _activeSearch;
  Object? _activeCandidateSearch;

  @override
  Listenable get changes => store;
  @override
  bool get engineAvailable => _engineAvailable;
  @override
  Object? get prepareError => _prepareError;
  @override
  int get enabledCount =>
      store.enabled.where((source) => source.supported).length;
  @override
  List<BookSource> get sources => store.sources;
  @override
  BookSourceSearchScope get searchScope => store.searchScope;
  @override
  String get searchScopeLabel => searchScope.describe(store.sources);
  @override
  BookSourceSearchScope get changeSourceScope => store.changeSourceScope;
  @override
  bool get changeSourceCheckAuthor => store.changeSourceCheckAuthor;

  static Future<BookSourceRepository> open() async {
    final store = await BookSourceStore.forApp();
    Object? loadError;
    try {
      await store.load();
    } on Object catch (error) {
      loadError = error;
    }
    final identities = await BookSourceIdentityStore.forApp();
    try {
      await identities.load();
    } on Object catch (error) {
      loadError ??= error;
    }
    final repository = BookSourceRepository(
      store: store,
      identities: identities,
    );
    if (loadError != null) {
      repository
        .._prepared = true
        .._prepareError = loadError;
    } else {
      // Sources are registered before the first search, without holding the
      // first frame or the first request on the whole source library.
      unawaited(repository.prepare());
    }
    return repository;
  }

  @override
  Future<void> prepare({bool force = false}) {
    if (_prepared && !force && _engineAvailable && _prepareError == null) {
      return Future.value();
    }
    final active = _preparing;
    if (active != null) {
      return force ? active.then((_) => prepare(force: true)) : active;
    }
    final pending = _prepare();
    _preparing = pending;
    return pending.whenComplete(() {
      if (identical(_preparing, pending)) _preparing = null;
    });
  }

  Future<void> _prepare() async {
    try {
      await store.load();
      await identities.load();
      await _seedBuiltinSources();
      _engineAvailable = await transport.available();
      _prepareError = null;
      if (_engineAvailable) {
        for (final source in store.sources.where(
          (source) => source.supported,
        )) {
          try {
            await transport.upsertSource(source);
          } on Object catch (error) {
            _prepareError ??= error;
          }
        }
      }
    } on Object catch (error) {
      _engineAvailable = false;
      _prepareError = error;
    } finally {
      _prepared = true;
    }
  }

  /// 内置榜单缺失或损坏时静默跳过，不影响用户已导入的书源。
  Future<void> _seedBuiltinSources() async {
    try {
      final text = await rootBundle.loadString(
        'assets/book_sources/builtin_sources.json',
      );
      await store.seedBuiltinSources(text, version: builtinSourcesVersion);
    } on Object {
      // 只影响内置榜单是否出现。
    }
  }

  Future<void> refreshSources() => prepare(force: true);

  @override
  Future<BookSourceImportResult> importSources(String text) async {
    final result = await store.importText(text);
    await prepare(force: true);
    return result;
  }

  @override
  Future<BookSourceImportResult> importFromUrl(String url) async {
    final text = await downloader.fetch(url);
    return importSources(text);
  }

  @override
  Future<void> updateSource(BookSource source) async {
    await store.updateSource(source);
    if (!_engineAvailable || !source.supported) return;
    try {
      await transport.upsertSource(source);
    } on Object catch (error) {
      _prepareError ??= error;
    }
  }

  @override
  Future<void> setSourceEnabled(String key, bool enabled) async {
    await store.setEnabled(key, enabled);
  }

  @override
  Future<void> setSourcesEnabled(Iterable<String> keys, bool enabled) =>
      store.setEnabledMany(keys, enabled);

  @override
  Future<void> removeSource(String key) async {
    final removed = store.source(key);
    await store.remove(key);
    await BookSourceImages.invalidateSource(key);
    if (removed != null && _engineAvailable) {
      try {
        await transport.removeSource(key);
      } on Object {
        // The source is already gone from the app library. A stale native
        // entry cannot be reached because Flutter only queries enabled keys.
      }
    }
  }

  @override
  Future<void> removeSources(Iterable<String> keys) async {
    final removed = [
      for (final key in keys.toSet())
        if (store.source(key) case final source?) source.key,
    ];
    await store.removeMany(removed);
    for (final key in removed) {
      await BookSourceImages.invalidateSource(key);
    }
    if (!_engineAvailable) return;
    for (final key in removed) {
      try {
        await transport.removeSource(key);
      } on Object {
        // Same best-effort cleanup as removeSource.
      }
    }
  }

  @override
  Future<void> updateSourceGroups(
    Iterable<String> keys, {
    String? addGroup,
    String? removeGroup,
  }) => store.updateGroups(keys, addGroup: addGroup, removeGroup: removeGroup);

  @override
  Future<void> setSearchScope(BookSourceSearchScope scope) async {
    await store.setSearchScope(scope);
    _activeSearch = Object();
    _activeCandidateSearch = Object();
    try {
      await transport.cancelSearches();
    } on Object {
      // Cancellation is best-effort; the changed scope still applies to the
      // next search and stale workers are ignored by their generation token.
    }
  }

  @override
  Future<void> setChangeSourceScope(BookSourceSearchScope scope) =>
      store.setChangeSourceScope(scope);

  @override
  Future<void> setChangeSourceCheckAuthor(bool value) =>
      store.setChangeSourceCheckAuthor(value);

  @override
  String exportSources({Set<String>? keys}) => store.exportJson(keys: keys);

  @override
  Future<List<Novel>> list() async => const [];

  @override
  Future<NovelPage> browse({
    NovelSort sort = NovelSort.lastUpdate,
    int page = 1,
    bool refresh = false,
  }) async => NovelPage(items: const [], page: page, totalPages: page);

  @override
  Future<List<Novel>> search(String query) async =>
      (await searchPage(query)).items;

  @override
  Future<List<BookSourceExploreKind>> exploreKinds(
    BookSource source, {
    Map<String, String> values = const {},
  }) async {
    await prepare();
    _requireEngine();
    final kinds = await transport
        .exploreKinds(source.key, values: values)
        .timeout(requestTimeout);
    return [
      for (final value in kinds)
        if (BookSourceExploreKind.fromMap(value).title.isNotEmpty)
          BookSourceExploreKind.fromMap(value),
    ];
  }

  @override
  Future<NovelPage> explore(
    BookSource source,
    String url, {
    int page = 1,
    String keyword = '',
    Map<String, String> values = const {},
  }) async {
    await prepare();
    _requireEngine();
    final result = await transport
        .explore(
          sourceKey: source.key,
          url: url,
          page: page,
          keyword: keyword,
          values: values,
        )
        .timeout(requestTimeout);
    return _pageFromRows(source, result, page);
  }

  @override
  Future<BookSourceExploreAction> exploreAction(
    BookSource source,
    String action, {
    Map<String, String> values = const {},
  }) async {
    await prepare();
    _requireEngine();
    return transport
        .exploreAction(sourceKey: source.key, action: action, values: values)
        .timeout(requestTimeout);
  }

  @override
  Future<BookSourceLoginState> loginInfo(BookSource source) async {
    await prepare();
    _requireEngine();
    return transport.loginInfo(source.key).timeout(requestTimeout);
  }

  @override
  Future<BookSourceLoginState> login(
    BookSource source,
    Map<String, String> values,
  ) async {
    await prepare();
    _requireEngine();
    final state = await transport
        .login(source.key, values)
        .timeout(_loginTimeout);
    await BookSourceImages.invalidateSource(source.key);
    return state;
  }

  @override
  Future<BookSourceLoginState> logout(BookSource source) async {
    await prepare();
    _requireEngine();
    final state = await transport.logout(source.key).timeout(requestTimeout);
    await BookSourceImages.invalidateSource(source.key);
    return state;
  }

  @override
  Future<BookSourceLoginState?> webLogin(
    BookSource source, {
    String url = '',
  }) async {
    await prepare();
    _requireEngine();
    final state = await transport
        .webLogin(source.key, url: url)
        .timeout(const Duration(minutes: 10));
    if (state != null) await BookSourceImages.invalidateSource(source.key);
    return state;
  }

  @override
  Future<BookSourceLoginState> checkLogin(BookSource source) async {
    await prepare();
    _requireEngine();
    final state = await transport.checkLogin(source.key).timeout(_loginTimeout);
    await BookSourceImages.invalidateSource(source.key);
    return state;
  }

  @override
  Future<BookSourceLoginAction> loginAction(
    BookSource source,
    String action, {
    Map<String, String> values = const {},
  }) async {
    await prepare();
    _requireEngine();
    final result = await transport
        .loginAction(sourceKey: source.key, action: action, values: values)
        .timeout(_loginTimeout);
    await BookSourceImages.invalidateSource(source.key);
    return result;
  }

  Duration get _loginTimeout => requestTimeout * 2;

  @override
  Future<String?> checkTextSource(
    BookSource source,
    String keyword, {
    required bool Function() cancelled,
    required void Function(String) onStage,
  }) async {
    if (cancelled()) return null;
    if (source.type != 0) return '跳过：非文字书源';
    if (!source.canSearch) return '跳过：未配置搜索地址';
    final term = source.checkKeyword(keyword);
    if (term.isEmpty) return '跳过：缺少校验关键词';
    var stage = '准备';
    try {
      await prepare();
      if (cancelled()) return null;
      _requireEngine();
      stage = '搜索';
      onStage('$stage「$term」');
      final page = await transport
          .search(sourceKey: source.key, keyword: term, page: 1)
          .timeout(requestTimeout);
      if (cancelled()) return null;
      if (page.items.isEmpty) return '未命中：「$term」没有搜索结果';
      final bookUrl = _string(page.items.first['bookUrl']);
      if (bookUrl.isEmpty) throw const FormatException('首本书缺少详情地址');
      stage = '详情';
      onStage(stage);
      final detail = await transport
          .detail(
            sourceKey: source.key,
            bookUrl: bookUrl,
            book: page.items.first,
          )
          .timeout(requestTimeout);
      if (cancelled()) return null;
      if (detail == null) throw const FormatException('没有返回书籍详情');
      stage = '目录';
      onStage(stage);
      final rows = await transport
          .chapters(
            sourceKey: source.key,
            bookUrl: bookUrl,
            tocUrl: _string(detail['tocUrl']),
            book: detail,
          )
          .timeout(requestTimeout);
      if (cancelled()) return null;
      final index = rows.indexWhere((row) => row['isVolume'] != true);
      if (index < 0) throw const FormatException('目录没有可读章节');
      final url = _string(rows[index]['url']);
      if (url.isEmpty) throw const FormatException('首章缺少正文地址');
      stage = '正文';
      onStage(stage);
      final content = await transport
          .content(
            sourceKey: source.key,
            bookUrl: bookUrl,
            chapterUrl: url,
            chapterTitle: _string(rows[index]['title']),
            book: detail,
            nextChapterUrl: _nextChapterUrl(rows, index),
          )
          .timeout(requestTimeout * 4);
      if (cancelled()) return null;
      final body = await _readerBody(content ?? '', url, source.key);
      return cancelled()
          ? null
          : '通过：${_string(detail['name'])} · ${_string(rows[index]['title'])}（${body.length} 字符）';
    } on Object catch (error) {
      if (cancelled()) return null;
      final message = switch (error) {
        TimeoutException() => '请求超时',
        FormatException() => error.message,
        PlatformException() => error.message ?? error.code,
        _ => error.toString(),
      };
      return '$stage失败：$message';
    }
  }

  @override
  Future<NovelPage> searchInSource(
    BookSource source,
    String query, {
    int page = 1,
  }) async {
    await prepare();
    _requireEngine();
    final term = query.trim();
    if (term.isEmpty) {
      return NovelPage(items: const [], page: page, totalPages: page);
    }
    final result = await transport
        .search(sourceKey: source.key, keyword: term, page: page)
        .timeout(requestTimeout);
    return _pageFromRows(source, result, page);
  }

  @override
  Future<Novel?> importBookReference({
    required String sourceKey,
    String sourceName = '',
    required String bookUrl,
    String title = '',
    String author = '',
    String intro = '',
    String coverUrl = '',
    String customCoverUrl = '',
  }) async {
    final url = bookUrl.trim();
    if (url.isEmpty) return null;
    await prepare();
    _requireEngine();
    final source = _sourceForReference(sourceKey, sourceName);
    if (source == null || !source.supported) return null;
    final cleanTitle = sourceSearchTitle(title);
    final cleanAuthor = sourceAuthorName(author);
    final cover = coverUrl.trim();
    final custom = BookSourceRef.webCover(customCoverUrl);
    final ref = await identities.refFor(
      source,
      url,
      title: cleanTitle,
      author: cleanAuthor,
      coverUrl: cover,
      customCoverUrl: custom.isEmpty ? null : custom,
    );
    final id = identities.idFor(source.key, url);
    if (id == null) return null;
    return Novel(
      id: id,
      title: cleanTitle.isEmpty ? source.name : cleanTitle,
      author: cleanAuthor,
      genre: '书源',
      summary: intro.trim(),
      colors: _bookColors(source.key, url),
      coverUrl: ref.displayCover,
      source: ref,
    );
  }

  BookSource? _sourceForReference(String sourceKey, String sourceName) {
    final key = sourceKey.trim();
    final direct = store.source(key);
    if (direct != null) return direct;
    final normalized = _normalizedSourceKey(key);
    if (normalized.isNotEmpty) {
      for (final source in store.sources) {
        if (_normalizedSourceKey(source.key) == normalized) {
          return source;
        }
      }
    }
    final name = sourceName.trim();
    if (name.isEmpty) return null;
    for (final source in store.sources) {
      if (source.name == name) return source;
    }
    return null;
  }

  static String _normalizedSourceKey(String value) => value
      .trim()
      .replaceFirst(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');

  Future<NovelPage> _pageFromRows(
    BookSource source,
    BookSourceSearchPage result,
    int page,
  ) async {
    final items = <Novel>[];
    for (final row in result.items) {
      final novel = await _novelFromSearch(source, row);
      if (novel != null) items.add(novel);
    }
    return NovelPage(
      items: List.unmodifiable(items),
      page: page,
      totalPages: result.hasMore ? page + 1 : page,
      totalItems: items.length,
    );
  }

  @override
  Future<NovelPage> searchPage(
    String query, {
    int page = 1,
    bool refresh = false,
  }) => searchPageProgressively(query, page: page);

  @override
  Future<void> cancelSearch() async {
    _activeSearch = null;
    try {
      await transport.cancelSearches();
    } on Object {
      // Native cancellation is best-effort; the run token still rejects late
      // results when an older engine build cannot cancel its requests.
    }
  }

  Future<NovelPage> searchPageProgressively(
    String query, {
    int page = 1,
    bool Function()? current,
    NovelSearchProgressCallback? onProgress,
  }) async {
    final term = query.trim();
    if (term.isEmpty) {
      // Opening search shows saved history or recommendations. Do not fan out
      // an empty keyword across every enabled source.
      _activeSearch = Object();
      await transport.cancelSearches();
      return NovelPage(items: const [], page: page, totalPages: page);
    }
    await prepare();
    _requireEngine();
    final sources = store.enabled
        .where(
          (source) =>
              source.supported &&
              searchScope.matches(source) &&
              source.canSearch,
        )
        .toList(growable: false);
    if (sources.isEmpty) {
      return NovelPage(items: const [], page: page, totalPages: page);
    }
    final run = Object();
    _activeSearch = run;
    await transport.cancelSearches();
    if (!identical(_activeSearch, run)) {
      return NovelPage(items: const [], page: page, totalPages: page);
    }
    final pendingSources = sources.toList();
    final found = <int, Novel>{};
    final failures = <String, Object>{};
    var hasMore = false;
    final done = Completer<void>();
    var completed = 0;

    bool stopped() {
      if (done.isCompleted) return true;
      if (!identical(_activeSearch, run) || current?.call() == false) {
        done.complete();
        return true;
      }
      return false;
    }

    final reportClock = Stopwatch()..start();
    var lastReportedAt = Duration.zero;
    const reportInterval = Duration(milliseconds: 80);

    void report({bool force = false}) {
      if (stopped() || onProgress == null) return;
      final now = reportClock.elapsed;
      if (!force && now - lastReportedAt < reportInterval) return;
      lastReportedAt = now;
      onProgress(
        NovelSearchProgress(
          items: List<Novel>.unmodifiable(found.values),
          completedSources: completed,
          totalSources: sources.length,
        ),
      );
    }

    void finishOne() {
      completed++;
      report(force: completed == sources.length);
      if (completed == sources.length && !done.isCompleted) done.complete();
    }

    Future<void> worker() async {
      while (!stopped()) {
        if (pendingSources.isEmpty) return;
        final source = pendingSources.removeAt(0);
        try {
          final result = await transport
              .search(sourceKey: source.key, keyword: term, page: page)
              .timeout(requestTimeout);
          if (stopped()) return;
          hasMore = hasMore || result.hasMore;
          for (final row in result.items) {
            if (stopped()) return;
            final novel = await _novelFromSearch(source, row);
            if (novel == null) continue;
            found[novel.id] = novel;
            // 单个书源可能一次返回较多书籍；逐本刷新让长请求也能尽早看到结果。
            report();
          }
        } on Object catch (error) {
          if (!stopped()) {
            failures[source.name] = error;
          }
        } finally {
          finishOne();
        }
      }
    }

    final workerCount = math.min(concurrency, sources.length);
    for (var i = 0; i < workerCount; i++) {
      unawaited(worker());
    }
    report(force: true);
    if (stopped() && !done.isCompleted) done.complete();
    await done.future;
    if (identical(_activeSearch, run)) _activeSearch = null;
    return NovelPage(
      items: List<Novel>.unmodifiable(found.values),
      page: page,
      totalPages: hasMore ? page + 1 : page,
      totalItems: found.length,
      sourceFailures: Map<String, Object>.unmodifiable(failures),
    );
  }

  @override
  List<Novel> cachedCoverCandidates(
    Novel book,
    BookSourceSearchScope scope, {
    String? keyword,
    bool checkAuthor = true,
  }) {
    final enabled = store.enabled
        .where((source) => source.supported && scope.matches(source))
        .map((source) => source.key)
        .toSet();
    final title = sourceSearchTitleKey(
      sourceSearchKeyword(
        keyword ??
            (book.source?.title.isNotEmpty == true
                ? book.source!.title
                : book.title),
      ),
    );
    if (title.isEmpty) return [];
    final items = <Novel>[];
    for (final entry in identities.entries) {
      final ref = entry.value;
      if (ref.coverUrl.isEmpty ||
          !enabled.contains(ref.sourceKey) ||
          (keyword == null
              ? sourceSearchTitleKey(ref.title) != title
              : !sourceSearchTitleKey(ref.title).contains(title)) ||
          (checkAuthor &&
              book.author.trim().isNotEmpty &&
              !sameSourceAuthor(book.author, ref.author))) {
        continue;
      }
      items.add(
        Novel(
          id: entry.key,
          title: ref.title,
          author: ref.author,
          genre: '书源',
          summary: '',
          colors: book.colors,
          coverUrl: ref.coverUrl,
          source: ref,
        ),
      );
    }
    sortSourceCandidates(items, store.sources);
    return items;
  }

  @override
  Future<BookSourceCandidateSearchResult> searchSourceCandidates(
    Novel book, {
    required bool checkAuthor,
    String? keyword,
    BookSourceSearchScope scope = const BookSourceSearchScope.all(),
    bool Function()? current,
    NovelSearchProgressCallback? onProgress,
  }) async {
    final sourceTitle = book.source?.title.trim() ?? '';
    final term = sourceSearchKeyword(
      keyword ?? (sourceTitle.isEmpty ? book.title : sourceTitle),
    );
    if (term.isEmpty) {
      return const BookSourceCandidateSearchResult(
        items: [],
        failedSources: 0,
        totalSources: 0,
      );
    }
    final previous = _activeCandidateSearch;
    final run = Object();
    _activeCandidateSearch = run;
    if (previous != null) {
      await transport.cancelSearches();
      if (!identical(_activeCandidateSearch, run)) {
        return const BookSourceCandidateSearchResult(
          items: [],
          failedSources: 0,
          totalSources: 0,
        );
      }
    }
    try {
      await prepare();
      _requireEngine();
    } on Object {
      if (identical(_activeCandidateSearch, run)) {
        _activeCandidateSearch = null;
      }
      rethrow;
    }
    if (!identical(_activeCandidateSearch, run)) {
      return const BookSourceCandidateSearchResult(
        items: [],
        failedSources: 0,
        totalSources: 0,
      );
    }
    final currentRef = book.source;
    final sources = store.enabled
        .where(
          (source) =>
              source.supported && source.canSearch && scope.matches(source),
        )
        .toList(growable: false);
    if (sources.isEmpty) {
      if (identical(_activeCandidateSearch, run)) {
        _activeCandidateSearch = null;
      }
      return BookSourceCandidateSearchResult(
        items: const [],
        failedSources: 0,
        totalSources: 0,
      );
    }

    final titleKey = sourceSearchTitleKey(term);
    final pending = sources.toList();
    final found = <String, Novel>{};
    final done = Completer<void>();
    var completed = 0;
    var failures = 0;

    bool stopped() {
      if (done.isCompleted) return true;
      if (!identical(_activeCandidateSearch, run) || current?.call() == false) {
        done.complete();
        return true;
      }
      return false;
    }

    void report() {
      if (stopped() || onProgress == null) return;
      onProgress(
        NovelSearchProgress(
          items: List<Novel>.unmodifiable(found.values),
          completedSources: completed,
          totalSources: sources.length,
        ),
      );
    }

    void finishOne() {
      completed++;
      report();
      if (completed == sources.length && !done.isCompleted) done.complete();
    }

    Future<void> worker() async {
      while (!stopped()) {
        if (pending.isEmpty) return;
        final source = pending.removeAt(0);
        try {
          final result = await transport
              .search(sourceKey: source.key, keyword: term, page: 1)
              .timeout(requestTimeout);
          if (stopped()) return;
          for (final row in result.items) {
            final candidateTitle = sourceSearchTitleKey(_string(row['name']));
            // 换源仍要求同名；封面关键词允许命中分卷或带后缀的书名。
            if (keyword == null
                ? candidateTitle != titleKey
                : !candidateTitle.contains(titleKey)) {
              continue;
            }
            final author = _string(row['author']);
            if (checkAuthor &&
                book.author.trim().isNotEmpty &&
                !sameSourceAuthor(author, book.author)) {
              continue;
            }
            final candidate = await _novelFromSearch(source, row);
            final ref = candidate?.source;
            if (candidate == null || ref == null) continue;
            if (currentRef != null &&
                ref.sourceKey == currentRef.sourceKey &&
                ref.bookUrl == currentRef.bookUrl) {
              continue;
            }
            found['${ref.sourceKey}\u0000${ref.bookUrl}'] = candidate;
          }
        } on Object {
          if (!stopped()) failures++;
        } finally {
          finishOne();
        }
      }
    }

    final workerCount = math.min(concurrency, sources.length);
    for (var i = 0; i < workerCount; i++) {
      unawaited(worker());
    }
    report();
    if (stopped() && !done.isCompleted) done.complete();
    await done.future;
    if (identical(_activeCandidateSearch, run)) _activeCandidateSearch = null;
    final items = found.values.toList();
    sortSourceCandidates(items, store.sources);
    return BookSourceCandidateSearchResult(
      items: List<Novel>.unmodifiable(items),
      failedSources: failures,
      totalSources: sources.length,
    );
  }

  @override
  Future<void> cancelSourceCandidateSearch() async {
    if (_activeCandidateSearch == null) return;
    _activeCandidateSearch = null;
    try {
      await transport.cancelSearches();
    } on Object {
      // Cancellation is best-effort; the run token still rejects late results.
    }
  }

  @override
  Future<Novel?> find(int id) async {
    if (!isBookSourceBook(id)) return null;
    await prepare();
    _requireEngine();
    final ref = identities.byId(id);
    if (ref == null) return null;
    final cached = _books[id];
    if (cached != null) return cached;
    return detail(
      Novel(
        id: id,
        title: ref.title.isEmpty ? ref.sourceName : ref.title,
        author: ref.author,
        genre: '书源',
        summary: '',
        colors: _bookColors(ref.sourceKey, ref.bookUrl),
        coverUrl: ref.displayCover,
        source: ref,
      ),
    );
  }

  @override
  Future<Novel> detail(Novel novel) async {
    await prepare();
    _requireEngine();
    final stored = _refForNovel(novel);
    final resourceType = store.source(stored.sourceKey)?.resourceType;
    // 未变的坐标沿用原对象，避免每次点书都等待整份索引的延迟保存。
    final ref = resourceType == null || resourceType == stored.resourceType
        ? stored
        : stored.copyWith(resourceType: resourceType);
    if (OfficialBookService.isOfficialKey(ref.sourceKey)) {
      await identities.remember(novel.id, ref, waitForSave: false);
      final data = await OfficialBookService.detail(ref);
      final nextRef = await identities.updateMeta(
        ref,
        tocUrl: data.tocUrl,
        title: data.title,
        author: novel.author.trim().isNotEmpty
            ? novel.author
            : sourceAuthorName(data.author),
        coverUrl: data.coverUrl,
        waitForSave: false,
      );
      final book = Novel(
        id: novel.id,
        title: sourceSearchTitle(data.title),
        author: novel.author.trim().isNotEmpty
            ? novel.author
            : sourceAuthorName(data.author),
        genre: data.kind,
        summary: data.intro,
        colors: novel.colors,
        isComplete: data.isComplete,
        coverUrl: nextRef.displayCover,
        lastUpdate: data.updateTime,
        chapterCount: data.chapterCount,
        wordCount: data.wordCount,
        source: nextRef,
      );
      _books[book.id] = book;
      return book;
    }
    _sourceFor(ref);
    await identities.remember(novel.id, ref, waitForSave: false);
    final loaded = await transport
        .detail(
          sourceKey: ref.sourceKey,
          bookUrl: ref.bookUrl,
          book: _ruleBook(ref, novel),
        )
        .timeout(requestTimeout);
    final tocUrl = _string(loaded?['tocUrl']);
    final title = sourceSearchTitle(
      _prefer(_string(loaded?['name']), novel.title),
    );
    // 书架内已有作者名视为本书身份的一部分，刷新详情不随书源改名。
    final author = novel.author.trim().isNotEmpty
        ? novel.author
        : sourceAuthorName(_prefer(_string(loaded?['author']), novel.author));
    final coverUrl = _prefer(
      _string(loaded?['coverUrl']),
      ref.customCoverUrl.isEmpty
          ? _prefer(novel.coverUrl ?? '', ref.coverUrl)
          : ref.coverUrl,
    );
    final lastUpdate = _prefer(
      _string(loaded?['updateTime']),
      _prefer(_string(loaded?['lastUpdate']), novel.lastUpdate ?? ''),
    );
    final nextRef = await identities.updateMeta(
      ref,
      tocUrl: tocUrl,
      title: title,
      author: author,
      coverUrl: coverUrl,
      waitForSave: false,
    );
    final book = Novel(
      id: novel.id,
      title: title,
      author: author,
      genre: _prefer(_string(loaded?['kind']), novel.genre),
      summary: _prefer(_string(loaded?['intro']), novel.summary),
      colors: novel.colors,
      chapters: novel.chapters,
      isComplete: _isComplete(loaded?['status']) || novel.isComplete,
      coverUrl: nextRef.displayCover,
      lastUpdate: lastUpdate.isEmpty ? null : lastUpdate,
      chapterCount: _int(loaded?['totalChapterNum']) ?? novel.chapterCount,
      wordCount: _int(loaded?['wordCount']) ?? novel.wordCount,
      source: nextRef,
    );
    _books[book.id] = book;
    return book;
  }

  @override
  Future<Novel> switchSource(Novel current, Novel candidate) async {
    await prepare();
    _requireEngine();
    final candidateRef = candidate.source;
    if (candidateRef == null) {
      throw const FormatException('候选书籍缺少书源坐标');
    }
    final source = _sourceFor(candidateRef);
    final currentRef = current.source ?? identities.byId(current.id);
    if (currentRef != null &&
        currentRef.sourceKey == candidateRef.sourceKey &&
        currentRef.bookUrl == candidateRef.bookUrl) {
      return current;
    }
    final ref = candidateRef.copyWith(
      sourceName: source.name,
      resourceType: source.resourceType,
    );
    final loaded = await transport
        .detail(
          sourceKey: ref.sourceKey,
          bookUrl: ref.bookUrl,
          book: _ruleBook(ref, candidate),
        )
        .timeout(requestTimeout);
    final tocUrl = _string(loaded?['tocUrl']);
    final title = sourceSearchTitle(
      _prefer(_string(loaded?['name']), candidate.title),
    );
    final author = sourceAuthorName(
      _prefer(_string(loaded?['author']), candidate.author),
    );
    final coverUrl = _prefer(
      _string(loaded?['coverUrl']),
      ref.customCoverUrl.isEmpty
          ? _prefer(candidate.coverUrl ?? '', ref.coverUrl)
          : ref.coverUrl,
    );
    // 换源后封面跟随新书源，作者名保持本书原值，避免书架作者被来源改写。
    final effectiveAuthor = current.author.trim().isNotEmpty
        ? current.author
        : author;
    final effectiveCover = coverUrl;
    final lastUpdate = _prefer(
      _string(loaded?['updateTime']),
      _prefer(_string(loaded?['lastUpdate']), candidate.lastUpdate ?? ''),
    );
    final nextRef = ref.copyWith(
      tocUrl: tocUrl.isEmpty ? ref.tocUrl : tocUrl,
      title: title.isEmpty ? ref.title : title,
      author: effectiveAuthor.isEmpty ? ref.author : effectiveAuthor,
      coverUrl: effectiveCover.isEmpty ? ref.coverUrl : effectiveCover,
      customCoverUrl: currentRef?.customCoverUrl ?? '',
    );
    // Load both halves before committing the identity so a broken candidate
    // leaves the original source and directory untouched.
    final chapters = await _loadChapters(current.id, nextRef);
    if (chapters.isEmpty) {
      throw const FormatException('新书源目录为空，未切换');
    }
    final book = Novel(
      id: current.id,
      title: title,
      author: effectiveAuthor,
      genre: _prefer(_string(loaded?['kind']), candidate.genre),
      summary: _prefer(_string(loaded?['intro']), candidate.summary),
      colors: current.colors,
      chapters: chapters,
      isComplete: _isComplete(loaded?['status']) || candidate.isComplete,
      coverUrl: nextRef.displayCover,
      lastUpdate: lastUpdate.isEmpty ? null : lastUpdate,
      chapterCount: _int(loaded?['totalChapterNum']) ?? chapters.length,
      wordCount: _int(loaded?['wordCount']) ?? candidate.wordCount,
      source: nextRef,
    );
    await identities.replace(current.id, nextRef);
    _books[current.id] = book;
    _chapters[current.id] = chapters;
    return book;
  }

  @override
  Future<List<NovelChapter>> chapters(int id) async {
    await prepare();
    _requireEngine();
    final ref = _refForId(id);
    if (OfficialBookService.isOfficialKey(ref.sourceKey)) {
      final official = await OfficialBookService.chapters(ref);
      final usedIds = <int>{};
      final result = <NovelChapter>[];
      for (var index = 0; index < official.length; index++) {
        final chapter = official[index];
        result.add(
          NovelChapter(
            chapter.title,
            '',
            id: _stableChapterId('${ref.bookUrl}#$index', usedIds),
            sourceUrl: chapter.url,
            sourceNextUrl: index + 1 < official.length
                ? official[index + 1].url
                : null,
          ),
        );
      }
      final chapters = List<NovelChapter>.unmodifiable(result);
      _chapters[id] = chapters;
      final known = _books[id];
      if (known != null) _books[id] = known.withChapters(chapters);
      return chapters;
    }
    final result = await _loadChapters(id, ref);
    _chapters[id] = result;
    final known = _books[id];
    if (known != null) {
      _books[id] = known.withChapters(result);
    }
    return result;
  }

  Future<List<NovelChapter>> _loadChapters(int id, BookSourceRef ref) async {
    _sourceFor(ref);
    final rows = await transport
        .chapters(
          sourceKey: ref.sourceKey,
          bookUrl: ref.bookUrl,
          tocUrl: ref.tocUrl,
          book: _ruleBook(ref, _books[id]),
        )
        .timeout(requestTimeout);
    final usedIds = <int>{};
    final chapters = <NovelChapter>[];
    var volumeId = 0;
    var volumeTitle = '';
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (row['isVolume'] == true) {
        volumeId++;
        volumeTitle = _string(row['title']);
        continue;
      }
      final chapterIndex = chapters.length;
      final url = _string(row['url']);
      final title = _prefer(_string(row['title']), '第 ${chapterIndex + 1} 章');
      final chapterId = _stableChapterId(
        url.isEmpty ? '$id\u0000$chapterIndex\u0000$title' : url,
        usedIds,
      );
      chapters.add(
        NovelChapter(
          title,
          '',
          id: chapterId,
          volumeId: volumeId,
          volumeTitle: volumeTitle,
          sourceUrl: url.isEmpty ? null : url,
          sourceNextUrl: _nextChapterUrl(rows, index),
        ),
      );
    }
    return List<NovelChapter>.unmodifiable(chapters);
  }

  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) async {
    await prepare();
    _requireEngine();
    final ref = _refForId(novelId);
    var chapterUrl = chapter.sourceUrl;
    var nextChapterUrl = chapter.sourceNextUrl;
    final knownChapters = _chapters[novelId] ?? const <NovelChapter>[];
    final chapterIndex = knownChapters.indexWhere(
      (item) => item.id == chapter.id,
    );
    if (chapterUrl == null || chapterUrl.isEmpty) {
      final saved = _chapters[novelId] ?? await chapters(novelId);
      NovelChapter? match;
      for (final item in saved) {
        if (item.id == chapter.id) {
          match = item;
          break;
        }
      }
      chapterUrl = match?.sourceUrl;
      nextChapterUrl ??= match?.sourceNextUrl;
    }
    if (chapterUrl == null || chapterUrl.isEmpty) {
      throw const FormatException('书源章节缺少正文地址');
    }
    if (OfficialBookService.isOfficialKey(ref.sourceKey)) {
      final raw = await OfficialBookService.content(ref, chapterUrl);
      return _readerBody(raw, chapterUrl, ref.sourceKey);
    }
    final text = await transport
        .content(
          sourceKey: ref.sourceKey,
          bookUrl: ref.bookUrl,
          chapterUrl: chapterUrl,
          nextChapterUrl: nextChapterUrl,
          chapterTitle: chapter.title,
          chapterIndex: chapterIndex,
          book: _ruleBook(ref, _books[novelId]),
        )
        // 正文可能串行翻多页，按单页超时会把后半章直接掐断。
        .timeout(requestTimeout * 4);
    return _readerBody(text ?? '', chapterUrl, ref.sourceKey);
  }

  Map<String, Object?> _ruleBook(BookSourceRef ref, Novel? novel) => {
    'name': ref.title.isNotEmpty ? ref.title : novel?.title,
    'author': ref.author.isNotEmpty ? ref.author : novel?.author,
    'coverUrl': ref.coverUrl,
    'tocUrl': ref.tocUrl,
    'kind': novel?.genre,
    'intro': novel?.summary,
    'wordCount': novel?.wordCount?.toString(),
    'updateTime': novel?.lastUpdate,
  };

  Future<String> _readerBody(
    String raw,
    String chapterUrl,
    String sourceKey,
  ) async {
    var body = legadoContentToReader(
      raw,
      baseUrl: chapterUrl,
      sourceKey: sourceKey,
    );
    if (body.trim().isEmpty) {
      throw const FormatException('书源正文为空');
    }
    if (_isFanqieSource(sourceKey)) {
      body = await _decodeFanqieText(body);
    }
    return body;
  }

  static bool _isFanqieSource(String sourceKey) =>
      sourceKey.toLowerCase().contains('fanqie');

  Future<Map<int, String>> _loadFanqieFontMap() =>
      _fanqieFontMap ??= _readFanqieFontMap();

  Future<Map<int, String>> _readFanqieFontMap() async {
    try {
      final text = await rootBundle.loadString(
        'assets/book_sources/fanqie_font_map.json',
      );
      final decoded = jsonDecode(text);
      final raw = decoded is Map ? decoded['map'] : decoded;
      if (raw is! Map) return const {};
      final result = <int, String>{};
      raw.forEach((key, value) {
        if (key is! String || value is! String || value.isEmpty) return;
        final codePoint = key.startsWith('0x')
            ? int.tryParse(key.substring(2), radix: 16)
            : int.tryParse(key);
        if (codePoint != null) result[codePoint] = value;
      });
      return result;
    } on Object {
      return const {};
    }
  }

  /// 番茄免费章节用随机字体把常用字映射到私用区码点，这里按随包字体表还原。
  Future<String> _decodeFanqieText(String text) async {
    final map = await _loadFanqieFontMap();
    if (map.isEmpty) return text;
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      buffer.write(map[rune] ?? String.fromCharCode(rune));
    }
    var decoded = buffer.toString();
    const fixes = {
      '硕土': '硕士',
      '人土': '人士',
      '博土': '博士',
      '将土': '将士',
      '烈土': '烈士',
      '战土': '战士',
    };
    for (final entry in fixes.entries) {
      decoded = decoded.replaceAll(entry.key, entry.value);
    }
    return decoded;
  }

  Future<Novel?> _novelFromSearch(
    BookSource source,
    Map<String, Object?> row,
  ) async {
    final bookUrl = _string(row['bookUrl']);
    if (bookUrl.isEmpty) return null;
    final title = sourceSearchTitle(_string(row['name']));
    final author = sourceAuthorName(_string(row['author']));
    final ref = await identities.refFor(
      source,
      bookUrl,
      tocUrl: _string(row['tocUrl']),
      title: title,
      author: author,
      coverUrl: _string(row['coverUrl']),
    );
    final id = identities.idFor(source.key, bookUrl);
    if (id == null) return null;
    final lastUpdate = _string(row['updateTime']);
    return Novel(
      id: id,
      title: _prefer(title, '未命名书籍'),
      author: author,
      genre: _prefer(_string(row['kind']), '书源'),
      summary: _string(row['intro']),
      colors: _bookColors(source.key, bookUrl),
      isComplete: _isComplete(row['status']),
      coverUrl: ref.displayCover,
      lastUpdate: lastUpdate.isEmpty ? null : lastUpdate,
      chapterCount: _int(row['totalChapterNum']) ?? 0,
      source: ref,
    );
  }

  BookSourceRef _refForNovel(Novel novel) {
    // The identity store is authoritative after a source switch. A stale list
    // row must not silently restore the previous source.
    final ref = identities.byId(novel.id) ?? novel.source;
    if (ref == null) {
      throw const FormatException('书籍缺少书源坐标，请重新搜索后打开');
    }
    return ref;
  }

  BookSourceRef _refForId(int id) {
    final ref = identities.byId(id);
    if (ref == null) {
      throw const FormatException('书源书籍记录不存在，请重新搜索后打开');
    }
    return ref;
  }

  BookSource _sourceFor(BookSourceRef ref) {
    final source = store.source(ref.sourceKey);
    if (source == null) {
      throw const FormatException('书源已删除，请重新导入后再打开');
    }
    if (!source.supported) {
      throw FormatException('暂不支持${source.typeLabel}书源');
    }
    return source;
  }

  void _requireEngine() {
    if (_engineAvailable) return;
    final error = _prepareError;
    throw FormatException(
      error is BookSourceEngineUnavailable
          ? '当前构建未接入 Android 书源引擎'
          : '书源初始化失败，请稍后重试',
    );
  }

  static String? _nextChapterUrl(List<Map<String, Object?>> rows, int index) {
    for (var next = index + 1; next < rows.length; next++) {
      if (rows[next]['isVolume'] == true) continue;
      final url = _string(rows[next]['url']);
      if (url.isNotEmpty) return url;
    }
    return null;
  }

  static int _stableChapterId(String value, Set<int> used) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    var id = hash == 0 ? 1 : hash;
    while (!used.add(id)) {
      id = id == 0x7fffffff ? 1 : id + 1;
    }
    return id;
  }

  static List<Color> _bookColors(String sourceKey, String bookUrl) {
    final seed = _stableChapterId('$sourceKey\u0000$bookUrl', <int>{});
    final hue = (seed % 360).toDouble();
    return [
      HSLColor.fromAHSL(1, hue, .48, .48).toColor(),
      HSLColor.fromAHSL(1, (hue + 28) % 360, .52, .28).toColor(),
    ];
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static String _prefer(String value, String fallback) =>
      value.isEmpty ? fallback : value;

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static bool _isComplete(Object? value) {
    final text = '$value'.toLowerCase();
    return text.contains('完结') ||
        text.contains('完本') ||
        text.contains('completed') ||
        text == 'true';
  }
}

/// Converts the Android engine's HTML/text response into the reader's paragraph
/// format. Images use the app's existing standalone marker.
String legadoContentToReader(
  String source, {
  required String baseUrl,
  required String sourceKey,
}) {
  if (source.trim().isEmpty) return '';
  final images = <String>[];
  final reviews = <InlineReview>[];
  var text = source.replaceAllMapped(
    RegExp(r'<img\b[^>]*>', caseSensitive: false),
    (match) {
      final tag = match.group(0)!;
      final review = InlineReview.fromImage(tag);
      if (review != null) {
        final token = '\u0000REVIEW${reviews.length}\u0000';
        reviews.add(review);
        return token;
      }
      final src =
          RegExp(
            r'''(?:data-src|data-original|src)\s*=\s*(['"])(.*?)\1''',
            caseSensitive: false,
          ).firstMatch(tag)?.group(2) ??
          '';
      final url = _absoluteImageUrl(src, baseUrl);
      if (url == null) return '';
      final token = '\u0000IMG${images.length}\u0000';
      images.add(
        BookSourceImages.markerUrl(
          sourceKey: sourceKey,
          url: _decodeEntities(url),
        ),
      );
      return '\n\n$token\n\n';
    },
  );
  text = text.replaceAll(
    RegExp(
      r'<(script|style|iframe|noscript)\b[^>]*>.*?</\1>',
      caseSensitive: false,
      dotAll: true,
    ),
    '',
  );
  text = text.replaceAll(
    RegExp(
      r'</?(?:p|div|section|article|header|footer|main|aside|h[1-6]|li|ul|ol|dl|dt|dd|table|tr|td|th|blockquote|pre|figure|figcaption)\b[^>]*>',
      caseSensitive: false,
    ),
    '\n\n',
  );
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  text = _decodeEntities(text);
  text = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  // @text / JS 规则常返回按单换行分段的纯文本，阅读器按空行分段，
  // 整章没有空行时补成段落，避免所有内容挤在一段里。
  if (!text.contains('\n\n') && text.contains('\n')) {
    text = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n\n');
  }
  for (var index = 0; index < images.length; index++) {
    text = text.replaceAll(
      '\u0000IMG$index\u0000',
      '<!--image-->${images[index]}<!--image-->',
    );
  }
  return text.replaceAllMapped(RegExp('\u0000REVIEW(\\d+)\u0000'), (match) {
    final index = int.tryParse(match[1]!);
    return index != null && index < reviews.length
        ? reviews[index].encode()
        : '';
  });
}

String? _absoluteImageUrl(String value, String baseUrl) {
  final text = value.trim();
  if (text.isEmpty || text.startsWith('data:')) return null;
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.hasScheme) {
    return uri.scheme == 'http' || uri.scheme == 'https'
        ? uri.toString()
        : null;
  }
  final base = Uri.tryParse(baseUrl);
  if (base == null) return null;
  final resolved = base.resolveUri(uri);
  return resolved.scheme == 'http' || resolved.scheme == 'https'
      ? resolved.toString()
      : null;
}

String _decodeEntities(String value) {
  const named = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'ensp': ' ',
    'emsp': ' ',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'ldquo': '“',
    'rdquo': '”',
    'lsquo': '‘',
    'rsquo': '’',
  };
  var text = value.replaceAllMapped(
    RegExp(r'&([a-zA-Z]+);'),
    (match) => named[match.group(1)!.toLowerCase()] ?? match.group(0)!,
  );
  text = text.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (match) => String.fromCharCode(int.parse(match.group(1)!)),
  );
  return text.replaceAllMapped(
    RegExp(r'&#x([0-9a-fA-F]+);'),
    (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
  );
}
