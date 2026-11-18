import 'dart:async';
import 'dart:math' as math;

import '../book_search.dart';
import '../book_identity.dart';
import '../catalog.dart';
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
    return _merged(
      library.searchPage(query, page: page, refresh: refresh),
      _sourceSearchPage(query, page),
      page,
    );
  }

  @override
  Future<void> cancelSearch() async {
    _sourceSearches.clear();
    await bookSources.cancelSearch();
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
    return _merged(
      library.searchFilteredPage(
        query,
        field: field,
        page: page,
        refresh: refresh,
      ),
      _filteredSourcePage(query, field: field, page: page),
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
    final progress = onProgress == null
        ? null
        : (NovelSearchProgress value) {
            if (current?.call() == false) return;
            onProgress(value);
          };
    final primary = field == BookSearchField.all
        ? library.searchPage(query, page: page, refresh: refresh)
        : library.searchFilteredPage(
            query,
            field: field,
            page: page,
            refresh: refresh,
          );
    final external = field == BookSearchField.all
        ? _sourceSearchPage(query, page, onProgress: progress)
        : _filteredSourcePage(
            query,
            field: field,
            page: page,
            onProgress: progress,
          );
    return _merged(primary, external, page);
  }

  @override
  Future<NovelPage> authorPage(
    String author, {
    int page = 1,
    bool refresh = false,
  }) => _merged(
    library.authorPage(author, page: page, refresh: refresh),
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

  Future<NovelPage> _merged(
    Future<NovelPage> libraryPage,
    Future<NovelPage> sourcePage,
    int page,
  ) async {
    NovelPage? primary;
    NovelPage? external;
    Object? primaryError;
    Object? externalError;
    await Future.wait([
      () async {
        try {
          primary = await libraryPage;
        } on Object catch (error) {
          primaryError = error;
        }
      }(),
      () async {
        try {
          external = await sourcePage;
        } on Object catch (error) {
          externalError = error;
        }
      }(),
    ]);
    if (primary == null && external == null) {
      Error.throwWithStackTrace(
        primaryError ?? externalError ?? StateError('搜索失败'),
        StackTrace.current,
      );
    }
    final byId = <int, Novel>{};
    for (final book in primary?.items ?? const <Novel>[]) {
      byId[book.id] = book;
    }
    for (final book in external?.items ?? const <Novel>[]) {
      byId[book.id] = book;
    }
    final failures = <String, Object>{
      ...?external?.sourceFailures,
      if (primaryError != null) '轻小说文库': primaryError!,
      if (externalError != null) '书源': externalError!,
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
