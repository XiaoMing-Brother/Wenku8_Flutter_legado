import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../book_identity.dart';
import '../catalog.dart';
import 'book_source.dart';
import 'book_source_downloader.dart';
import 'book_source_images.dart';
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
    return transport.login(source.key, values).timeout(_loginTimeout);
  }

  @override
  Future<BookSourceLoginState> logout(BookSource source) async {
    await prepare();
    _requireEngine();
    return transport.logout(source.key).timeout(requestTimeout);
  }

  @override
  Future<BookSourceLoginState?> webLogin(BookSource source) async {
    await prepare();
    _requireEngine();
    return transport.webLogin(
      source.key,
    ).timeout(const Duration(minutes: 10));
  }

  @override
  Future<BookSourceLoginState> checkLogin(BookSource source) async {
    await prepare();
    _requireEngine();
    return transport.checkLogin(source.key).timeout(_loginTimeout);
  }

  @override
  Future<void> loginAction(
    BookSource source,
    String action, {
    Map<String, String> values = const {},
  }) async {
    await prepare();
    _requireEngine();
    await transport
        .loginAction(sourceKey: source.key, action: action, values: values)
        .timeout(_loginTimeout);
  }

  Duration get _loginTimeout => requestTimeout * 2;

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
    final ref = await identities.refFor(
      source,
      url,
      title: cleanTitle,
      author: cleanAuthor,
      coverUrl: cover,
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
      coverUrl: cover.isEmpty ? null : cover,
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

    final reportStep = math.max(1, (sources.length / 12).ceil());
    var lastReported = 0;

    void report({bool force = false}) {
      if (stopped() || onProgress == null) return;
      final complete = completed == sources.length;
      if (!force &&
          !complete &&
          completed > 3 &&
          completed - lastReported < reportStep) {
        return;
      }
      lastReported = completed;
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
            final novel = await _novelFromSearch(source, row);
            if (novel != null) found[novel.id] = novel;
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
  Future<BookSourceCandidateSearchResult> searchSourceCandidates(
    Novel book, {
    required bool checkAuthor,
    BookSourceSearchScope scope = const BookSourceSearchScope.all(),
    bool Function()? current,
    NovelSearchProgressCallback? onProgress,
  }) async {
    final sourceTitle = book.source?.title.trim() ?? '';
    final term = sourceSearchKeyword(
      sourceTitle.isEmpty ? book.title : sourceTitle,
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
            if (sourceSearchTitleKey(_string(row['name'])) != titleKey) {
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
    final items = found.values.toList()
      ..sort((a, b) {
        final chapters = b.chapterCount.compareTo(a.chapterCount);
        if (chapters != 0) return chapters;
        final source = (a.source?.sourceName ?? '').compareTo(
          b.source?.sourceName ?? '',
        );
        if (source != 0) return source;
        return a.title.compareTo(b.title);
      });
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
        coverUrl: ref.coverUrl.isEmpty ? null : ref.coverUrl,
        source: ref,
      ),
    );
  }

  @override
  Future<Novel> detail(Novel novel) async {
    await prepare();
    _requireEngine();
    final ref = _refForNovel(novel);
    _sourceFor(ref);
    await identities.remember(novel.id, ref);
    final loaded = await transport
        .detail(sourceKey: ref.sourceKey, bookUrl: ref.bookUrl)
        .timeout(requestTimeout);
    final tocUrl = _string(loaded?['tocUrl']);
    final title = sourceSearchTitle(
      _prefer(_string(loaded?['name']), novel.title),
    );
    final author = sourceAuthorName(
      _prefer(_string(loaded?['author']), novel.author),
    );
    final coverUrl = _prefer(
      _string(loaded?['coverUrl']),
      novel.coverUrl ?? '',
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
      coverUrl: coverUrl.isEmpty ? null : coverUrl,
      lastUpdate: lastUpdate.isEmpty ? null : lastUpdate,
      chapterCount: _int(loaded?['totalChapterNum']) ?? novel.chapterCount,
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
    final ref = candidateRef.copyWith(sourceName: source.name);
    final loaded = await transport
        .detail(sourceKey: ref.sourceKey, bookUrl: ref.bookUrl)
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
      candidate.coverUrl ?? '',
    );
    final lastUpdate = _prefer(
      _string(loaded?['updateTime']),
      _prefer(_string(loaded?['lastUpdate']), candidate.lastUpdate ?? ''),
    );
    final nextRef = ref.copyWith(
      tocUrl: tocUrl.isEmpty ? ref.tocUrl : tocUrl,
      title: title.isEmpty ? ref.title : title,
      author: author.isEmpty ? ref.author : author,
      coverUrl: coverUrl.isEmpty ? ref.coverUrl : coverUrl,
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
      author: author,
      genre: _prefer(_string(loaded?['kind']), candidate.genre),
      summary: _prefer(_string(loaded?['intro']), candidate.summary),
      colors: current.colors,
      chapters: chapters,
      isComplete: _isComplete(loaded?['status']) || candidate.isComplete,
      coverUrl: coverUrl.isEmpty ? null : coverUrl,
      lastUpdate: lastUpdate.isEmpty ? null : lastUpdate,
      chapterCount: _int(loaded?['totalChapterNum']) ?? chapters.length,
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
        )
        .timeout(requestTimeout);
    final filtered = <Map<String, Object?>>[];
    var nextVolumeId = 0;
    var volumeTitle = '';
    for (final row in rows) {
      if (row['isVolume'] == true) {
        nextVolumeId++;
        volumeTitle = _string(row['title']);
        continue;
      }
      filtered.add(row);
    }
    final usedIds = <int>{};
    final chapters = <NovelChapter>[];
    for (var index = 0; index < filtered.length; index++) {
      final row = filtered[index];
      final url = _string(row['url']);
      final title = _prefer(_string(row['title']), '第 ${index + 1} 章');
      final chapterId = _stableChapterId(
        url.isEmpty ? '$id\u0000$index\u0000$title' : url,
        usedIds,
      );
      chapters.add(
        NovelChapter(
          title,
          '',
          id: chapterId,
          volumeId: nextVolumeId,
          volumeTitle: volumeTitle,
          sourceUrl: url.isEmpty ? null : url,
          sourceNextUrl: _nextChapterUrl(filtered, index),
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
    final text = await transport
        .content(
          sourceKey: ref.sourceKey,
          bookUrl: ref.bookUrl,
          chapterUrl: chapterUrl,
          nextChapterUrl: nextChapterUrl,
        )
        .timeout(requestTimeout);
    final body = legadoContentToReader(
      text ?? '',
      baseUrl: chapterUrl,
      sourceKey: ref.sourceKey,
    );
    if (body.trim().isEmpty) {
      throw const FormatException('书源正文为空');
    }
    return body;
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
    final coverUrl = _string(row['coverUrl']);
    final lastUpdate = _string(row['updateTime']);
    return Novel(
      id: id,
      title: _prefer(title, '未命名书籍'),
      author: author,
      genre: _prefer(_string(row['kind']), '书源'),
      summary: _string(row['intro']),
      colors: _bookColors(source.key, bookUrl),
      isComplete: _isComplete(row['status']),
      coverUrl: coverUrl.isEmpty ? null : coverUrl,
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
          : '书源引擎暂不可用，请稍后重试',
    );
  }

  static String? _nextChapterUrl(List<Map<String, Object?>> rows, int index) {
    for (var next = index + 1; next < rows.length; next++) {
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
  var text = source.replaceAllMapped(
    RegExp(r'<img\b[^>]*>', caseSensitive: false),
    (match) {
      final tag = match.group(0)!;
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
  for (var index = 0; index < images.length; index++) {
    text = text.replaceAll(
      '\u0000IMG$index\u0000',
      '<!--image-->${images[index]}<!--image-->',
    );
  }
  return text;
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
