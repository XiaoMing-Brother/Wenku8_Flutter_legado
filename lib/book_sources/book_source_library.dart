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
  BookSourceSearchScope get changeSourceScope;
  bool get changeSourceCheckAuthor;

  Future<void> prepare({bool force = false});
  Future<String?> checkTextSource(
    BookSource source,
    String keyword, {
    required bool Function() cancelled,
    required void Function(String) onStage,
  });
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
  Future<void> setChangeSourceScope(BookSourceSearchScope scope);
  Future<void> setChangeSourceCheckAuthor(bool value);
  Future<void> cancelSearch();
  String exportSources({Set<String>? keys});
  Future<Novel> switchSource(Novel current, Novel candidate);
  List<Novel> cachedCoverCandidates(Novel book, BookSourceSearchScope scope);
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
    String customCoverUrl = '',
  });
}

/// 换源候选按书源库顺序排序（`customOrder`，其次书源名），与原书源列表
/// 保持一致，也对应 Legado 换源结果按书源评分配置与 `originOrder` 排序。
void sortSourceCandidates(List<Novel> items, Iterable<BookSource> sources) {
  final byKey = {for (final source in sources) source.key: source};
  items.sort((a, b) {
    final left = byKey[a.source?.sourceKey];
    final right = byKey[b.source?.sourceKey];
    final order = (left?.customOrder ?? 0).compareTo(right?.customOrder ?? 0);
    if (order != 0) return order;
    final names = (left?.name ?? a.source?.sourceName ?? '').compareTo(
      right?.name ?? b.source?.sourceName ?? '',
    );
    if (names != 0) return names;
    return a.title.compareTo(b.title);
  });
}
