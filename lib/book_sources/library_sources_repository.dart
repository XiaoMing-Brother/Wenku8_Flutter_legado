import 'dart:async';
import 'dart:math' as math;

import '../book_search.dart';
import '../book_identity.dart';
import '../catalog.dart';
import '../online_component.dart';
import '../tag_catalogue.dart';
import 'book_source_repository.dart';

/// Routes the app's existing library contract to the built-in Wenku source and
/// the optional Legado book-source engine.
///
/// Discovery stays on Wenku. Search is the only merged surface so importing a
/// book source never changes the home catalogue or its paging.
class LibrarySourcesRepository extends NovelRepository
    implements ProgressiveTagCatalogue, ProgressiveNovelSearch {
  LibrarySourcesRepository({required this.library, required this.bookSources});

  final NovelRepository library;
  final BookSourceRepository bookSources;
  final Map<String, _SourceSearchSession> _sourceSearches = {};
  String? _scopeSignature;
  int _searchGeneration = 0;

  bool _isSource(int id, [Novel? novel]) =>
      novel?.source != null || isBookSourceBook(id);

  @override
  Future<List<Novel>> list() => library.list();

  @override
  Future<NovelPage> browse({
    NovelSort sort = NovelSort.lastUpdate,
    int page = 1,
    bool refresh = false,
  }) => library.browse(sort: sort, page: page, refresh: refresh);

  @override
  Future<List<Novel>> search(String query) async =>
      (await searchPage(query)).items;

  @override
  Future<NovelPage> searchPage(
    String query, {
    int page = 1,
    bool refresh = false,
  }) {
    if (refresh) _sourceSearches.clear();
    return _searchPrimaryThenSources(
      () => library.searchPage(query, page: page, refresh: refresh),
      () => _sourceSearchPage(query, page),
      page,
    );
  }

  @override
  Future<void> cancelSearch() async {
    _searchGeneration++;
    _sourceSearches.clear();
    try {
      await Future.wait([bookSources.cancelSearch(), library.cancelSearch()]);
    } on Object {
      // 取消是尽力而为，任一来源失败都不应冒泡到页面生命周期。
    }
  }

  @override
  Future<NovelPage> searchFilteredPage(
    String query, {
    BookSearchField field = BookSearchField.all,
    int page = 1,
    bool refresh = false,
  }) {
    if (field == BookSearchField.all) {
      return searchPage(query, page: page, refresh: refresh);
    }
    if (refresh) _sourceSearches.clear();
    return _searchPrimaryThenSources(
      () => library.searchFilteredPage(
        query,
        field: field,
        page: page,
        refresh: refresh,
      ),
      () => _filteredSourcePage(query, field: field, page: page),
      page,
    );
  }

  @override
  Future<NovelPage> searchFilteredPageProgressively(
    String query, {
    BookSearchField field = BookSearchField.all,
    int page = 1,
    bool refresh = false,
    bool Function()? current,
    NovelSearchProgressCallback? onProgress,
  }) {
    final prefix = '$query\u0000';
    if (refresh || _sourceSearches.keys.any((key) => !key.startsWith(prefix))) {
      _sourceSearches.clear();
    }
    NovelPage? primaryResult;
    NovelSearchProgress? latestSourceProgress;
    NovelSearchProgressCallback? progress;
    if (onProgress != null) {
      progress = (NovelSearchProgress value) {
        if (current?.call() == false) return;
        latestSourceProgress = value;
        onProgress(
          NovelSearchProgress(
            items: _officialFirst(primaryResult?.items, value.items),
            completedSources: value.completedSources,
            totalSources: value.totalSources,
            officialItems: primaryResult?.items ?? const [],
          ),
        );
      };
    }
    void acceptPrimary(NovelPage result) {
      primaryResult = result;
      final latest = latestSourceProgress;
      progress?.call(
        NovelSearchProgress(
          items: _officialFirst(result.items, latest?.items ?? const []),
          completedSources: latest?.completedSources ?? 0,
          totalSources: latest?.totalSources ?? 0,
          officialItems: result.items,
        ),
      );
    }

    return _searchPrimaryThenSources(
      () => field == BookSearchField.all
          ? library.searchPage(query, page: page, refresh: refresh)
          : library.searchFilteredPage(
              query,
              field: field,
              page: page,
              refresh: refresh,
            ),
      () => field == BookSearchField.all
          ? _sourceSearchPage(query, page, onProgress: progress)
          : _filteredSourcePage(
              query,
              field: field,
              page: page,
              onProgress: progress,
            ),
      page,
      current: current,
      onPrimary: progress == null ? null : acceptPrimary,
    );
  }

  @override
  Future<NovelPage> authorPage(
    String author, {
    int page = 1,
    bool refresh = false,
  }) => _searchPrimaryThenSources(
    () => library.authorPage(author, page: page, refresh: refresh),
    () =>
        _filteredSourcePage(author, field: BookSearchField.author, page: page),
    page,
  );

  Future<NovelPage> _filteredSourcePage(
    String query, {
    required BookSearchField field,
    required int page,
    NovelSearchProgressCallback? onProgress,
  }) async {
    final pattern = BookSearch(query, field: field);
    final result = await _sourceSearchPage(
      query,
      page,
      onProgress: onProgress == null
          ? null
          : (progress) => onProgress(
              NovelSearchProgress(
                items: progress.items
                    .where(
                      (book) => pattern.matches(
                        title: book.title,
                        author: book.author,
                        tags: book.genre,
                        summary: book.summary,
                        id: '${book.id}',
                      ),
                    )
                    .toList(growable: false),
                completedSources: progress.completedSources,
                totalSources: progress.totalSources,
              ),
            ),
    );
    final items = result.items
        .where(
          (book) => pattern.matches(
            title: book.title,
            author: book.author,
            tags: book.genre,
            summary: book.summary,
            id: '${book.id}',
          ),
        )
        .toList(growable: false);
    return NovelPage(
      items: items,
      page: result.page,
      totalPages: result.totalPages,
      totalItems: items.length,
      searchFailures: result.searchFailures,
      sourceFailures: result.sourceFailures,
    );
  }

  Future<NovelPage> _sourceSearchPage(
    String query,
    int page, {
    NovelSearchProgressCallback? onProgress,
  }) {
    final signature = bookSources.searchScope.signature;
    if (_scopeSignature != signature) {
      _scopeSignature = signature;
      _sourceSearches.clear();
    }
    final key = '$query\u0000$page\u0000$signature';
    final session = _sourceSearches[key] ??= _startSourceSearch(
      key,
      query,
      page,
    );
    if (onProgress != null) {
      session.addListener(onProgress);
      session.future.then<void>(
        (_) => session.removeListener(onProgress),
        onError: (Object _, StackTrace _) => session.removeListener(onProgress),
      );
    }
    return session.future;
  }

  _SourceSearchSession _startSourceSearch(String key, String query, int page) {
    final session = _SourceSearchSession();
    bookSources
        .searchPageProgressively(query, page: page, onProgress: session.publish)
        .then<void>(
          (result) {
            session.complete(result);
            Timer(const Duration(minutes: 2), () {
              if (identical(_sourceSearches[key], session)) {
                _sourceSearches.remove(key);
              }
            });
          },
          onError: (Object error, StackTrace stack) {
            session.fail(error, stack);
            if (identical(_sourceSearches[key], session)) {
              _sourceSearches.remove(key);
            }
          },
        );
    return session;
  }

  Future<NovelPage> _searchPrimaryThenSources(
    Future<NovelPage> Function() libraryPage,
    Future<NovelPage> Function() sourcePage,
    int page, {
    bool Function()? current,
    void Function(NovelPage primary)? onPrimary,
  }) async {
    final generation = _searchGeneration;
    bool cancelled() =>
        generation != _searchGeneration || current?.call() == false;

    NovelPage? primary;
    Object? primaryError;
    NovelPage? external;
    Object? externalError;
    Future<void> loadPrimary() async {
      try {
        final result = await libraryPage();
        if (cancelled()) return;
        primary = result;
      } on Object catch (error) {
        primaryError = error;
        return;
      }
      final result = primary;
      if (result != null) onPrimary?.call(result);
    }

    Future<void> loadSources() async {
      try {
        final result = await sourcePage();
        if (cancelled()) return;
        external = result;
      } on Object catch (error) {
        externalError = error;
      }
    }

    await Future.wait([loadPrimary(), loadSources()]);
    if (cancelled()) {
      return NovelPage(items: const [], page: page, totalPages: page);
    }
    return _mergePages(primary, external, primaryError, externalError, page);
  }

  static List<Novel> _officialFirst(
    List<Novel>? official,
    List<Novel> sources,
  ) {
    if (official == null || official.isEmpty) {
      return List<Novel>.unmodifiable(sources);
    }
    final byId = <int, Novel>{for (final book in official) book.id: book};
    for (final book in sources) {
      byId.putIfAbsent(book.id, () => book);
    }
    return List<Novel>.unmodifiable(byId.values);
  }

  NovelPage _mergePages(
    NovelPage? primary,
    NovelPage? external,
    Object? primaryError,
    Object? externalError,
    int page,
  ) {
    final primaryFailure = primaryError is OnlineComponentUnavailable
        ? null
        : primaryError;
    if (primary == null && external == null) {
      Error.throwWithStackTrace(
        primaryFailure ?? externalError ?? StateError('搜索失败'),
        StackTrace.current,
      );
    }
    final byId = <int, Novel>{};
    for (final book in primary?.items ?? const <Novel>[]) {
      byId[book.id] = book;
    }
    for (final book in external?.items ?? const <Novel>[]) {
      byId.putIfAbsent(book.id, () => book);
    }
    final failures = <String, Object>{
      ...?external?.sourceFailures,
      '轻小说文库': ?primaryFailure,
      '书源': ?externalError,
    };
    return NovelPage(
      items: List<Novel>.unmodifiable(byId.values),
      page: page,
      totalPages: _mergedTotalPages(primary, external, page),
      totalItems:
          (primary?.totalItems ?? primary?.items.length ?? 0) +
          (external?.totalItems ?? external?.items.length ?? 0),
      searchFailures: {
        ...?primary?.searchFailures,
        ...?external?.searchFailures,
      },
      sourceFailures: failures,
    );
  }

  static int _mergedTotalPages(
    NovelPage? primary,
    NovelPage? external,
    int page,
  ) {
    final primaryPages = primary?.totalPages ?? page;
    final externalPages = external?.totalPages ?? page;
    return math.max(math.max(primaryPages, externalPages), page);
  }

  @override
  Future<Novel?> find(int id) =>
      isBookSourceBook(id) ? bookSources.find(id) : library.find(id);

  @override
  Future<Novel> detail(Novel novel) => _isSource(novel.id, novel)
      ? bookSources.detail(novel)
      : library.detail(novel);

  @override
  Future<List<NovelChapter>> chapters(int id) =>
      isBookSourceBook(id) ? bookSources.chapters(id) : library.chapters(id);

  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) =>
      isBookSourceBook(novelId)
      ? bookSources.chapterContent(novelId, chapter)
      : library.chapterContent(novelId, chapter);

  @override
  Future<NovelPage> tagPage(
    String tag, {
    int page = 1,
    bool refresh = false,
    bool Function()? current,
    TagProgressCallback? onProgress,
  }) {
    final catalogue = library;
    if (catalogue is ProgressiveTagCatalogue) {
      return (catalogue as ProgressiveTagCatalogue).tagPage(
        tag,
        page: page,
        refresh: refresh,
        current: current,
        onProgress: onProgress,
      );
    }
    return library.searchFilteredPage(
      tag,
      field: BookSearchField.tags,
      page: page,
      refresh: refresh,
    );
  }
}

class _SourceSearchSession {
  final _done = Completer<NovelPage>();
  final _listeners = <NovelSearchProgressCallback>{};
  NovelSearchProgress? _latest;

  Future<NovelPage> get future => _done.future;

  void addListener(NovelSearchProgressCallback listener) {
    final latest = _latest;
    if (latest != null) listener(latest);
    if (!_done.isCompleted) _listeners.add(listener);
  }

  void removeListener(NovelSearchProgressCallback listener) {
    _listeners.remove(listener);
  }

  void publish(NovelSearchProgress progress) {
    if (_done.isCompleted) return;
    _latest = progress;
    for (final listener in List<NovelSearchProgressCallback>.of(_listeners)) {
      listener(progress);
    }
  }

  void complete(NovelPage result) {
    if (_done.isCompleted) return;
    final latest = _latest;
    publish(
      NovelSearchProgress(
        items: result.items,
        completedSources: latest?.totalSources ?? 0,
        totalSources: latest?.totalSources ?? 0,
      ),
    );
    _done.complete(result);
    _listeners.clear();
  }

  void fail(Object error, StackTrace stack) {
    if (_done.isCompleted) return;
    _done.completeError(error, stack);
    _listeners.clear();
  }
}
