import 'package:flutter/foundation.dart';

import '../catalog.dart';
import 'book_source.dart';
import 'book_source_search_scope.dart';
import 'book_source_store.dart';

class BookSourceCandidateSearchResult {
  const BookSourceCandidateSearchResult({
    required this.items,
    required this.failedSources,
    required this.totalSources,
  });

  final List<Novel> items;
  final int failedSources;
  final int totalSources;
}

/// UI-facing contract for the app-owned book source library.
///
/// Keeping this separate from the repository lets the existing pages discover
/// source management through [OfflineNovelRepository] without depending on the
/// Android transport.
abstract interface class BookSourceLibrary {
  Listenable get changes;
  bool get engineAvailable;
  Object? get prepareError;
  int get enabledCount;
  List<BookSource> get sources;
  BookSourceSearchScope get searchScope;
  String get searchScopeLabel;

  Future<void> prepare({bool force = false});
  Future<BookSourceImportResult> importSources(String text);
  Future<BookSourceImportResult> importFromUrl(String url);
  Future<void> updateSource(BookSource source);
  Future<void> setSourceEnabled(String key, bool enabled);
  Future<void> setSourcesEnabled(Iterable<String> keys, bool enabled);
  Future<void> removeSource(String key);
  Future<void> removeSources(Iterable<String> keys);
  Future<void> updateSourceGroups(
    Iterable<String> keys, {
    String? addGroup,
    String? removeGroup,
  });
  Future<void> setSearchScope(BookSourceSearchScope scope);
  Future<void> cancelSearch();
  String exportSources({Set<String>? keys});
  Future<Novel> switchSource(Novel current, Novel candidate);
  Future<BookSourceCandidateSearchResult> searchSourceCandidates(
    Novel book, {
    required bool checkAuthor,
    BookSourceSearchScope scope = const BookSourceSearchScope.all(),
    bool Function()? current,
    NovelSearchProgressCallback? onProgress,
  });
  Future<void> cancelSourceCandidateSearch();
  Future<List<BookSourceExploreKind>> exploreKinds(
    BookSource source, {
    Map<String, String> values = const {},
  });
  Future<NovelPage> explore(
    BookSource source,
    String url, {
    int page = 1,
    String keyword = '',
    Map<String, String> values = const {},
  });
  Future<BookSourceExploreAction> exploreAction(
    BookSource source,
    String action, {
    Map<String, String> values = const {},
  });
  Future<BookSourceLoginState> loginInfo(BookSource source);
  Future<BookSourceLoginState> login(
    BookSource source,
    Map<String, String> values,
  );
  Future<BookSourceLoginState> logout(BookSource source);
  Future<BookSourceLoginState?> webLogin(BookSource source);
  Future<BookSourceLoginState> checkLogin(BookSource source);
  Future<void> loginAction(
    BookSource source,
    String action, {
    Map<String, String> values = const {},
  });
  Future<NovelPage> searchInSource(
    BookSource source,
    String query, {
    int page = 1,
  });

  /// Creates or finds the app identity for a Legado book URL. Imported
  /// bookshelf JSON can use this without spending a search request.
  Future<Novel?> importBookReference({
    required String sourceKey,
    String sourceName = '',
    required String bookUrl,
    String title = '',
    String author = '',
    String intro = '',
    String coverUrl = '',
  });
}
