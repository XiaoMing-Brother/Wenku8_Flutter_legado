import 'catalog.dart';
import 'official_books.dart';

/// 将同一本书在不同书源中的结果合并为一行，并保持 Legado 的搜索排序语义。
class NovelSearchMerger {
  NovelSearchMerger(String query)
    : _query = _normalize(query.trim().replaceFirst(RegExp(r'^#'), ''));

  static const maxRetainedResults = 1000;

  final String _query;
  final Map<String, _MergedSearchBook> _books = {};
  final Map<String, String> _urlIndex = {};
  final Set<String> _pinned = {};
  final Map<String, int> _pinnedOrder = {};
  var _nextOrder = 0;
  var _resultLimitReached = false;

  int get count => _books.length;
  bool get resultLimitReached => _resultLimitReached;

  List<Novel> merge(
    Iterable<Novel> incoming, {
    Iterable<Novel> pinned = const [],
  }) {
    for (final book in pinned) {
      _mergeBook(book, pin: true);
    }
    for (final book in incoming) {
      _mergeBook(book, pin: _officialRank(book) < OfficialBookService.searchSites.length);
    }
    return _sortedItems();
  }

  void _mergeBook(Novel book, {required bool pin}) {
    final urlKey = _bookUrlKey(book);
    final existingKey = urlKey == null ? null : _urlIndex[urlKey];
    final key = existingKey ?? _bookKey(book);
    final current = _books[key];
    if (current == null) {
      _books[key] = _MergedSearchBook(book, _nextOrder++);
    } else if (pin && (!_pinned.contains(key) || _officialRank(book) <= _officialRank(current.novel))) {
      // 官网结果与书源命中同一本书时，保留官网的书籍信息作为展示行。
      current.novel = book;
    }
    _books[key]!.origins.add(_origin(book));
    if (urlKey != null) _urlIndex[urlKey] = key;
    if (pin) {
      if (_pinned.add(key)) _pinnedOrder[key] = _pinnedOrder.length;
    }
  }

  List<Novel> _sortedItems() {
    final pinnedRows = <MapEntry<String, _MergedSearchBook>>[];
    final rows = <MapEntry<String, _MergedSearchBook>>[];
    for (final entry in _books.entries) {
      if (_pinned.contains(entry.key)) {
        pinnedRows.add(entry);
      } else {
        rows.add(entry);
      }
    }
    pinnedRows.sort((left, right) {
      final leftRank = _officialRank(left.value.novel);
      final rightRank = _officialRank(right.value.novel);
      final count = OfficialBookService.searchSites.length;
      if (leftRank < count && rightRank < count) {
        final match = left.value.bucket(_query).compareTo(right.value.bucket(_query));
        if (match != 0) return match;
      }
      final site = leftRank.compareTo(rightRank);
      return site != 0 ? site : (_pinnedOrder[left.key] ?? 0).compareTo(_pinnedOrder[right.key] ?? 0);
    });
    rows.sort((a, b) {
      final left = a.value;
      final right = b.value;
      final leftBucket = left.bucket(_query);
      final bucket = leftBucket.compareTo(right.bucket(_query));
      if (bucket != 0) return bucket;
      // Legado 只对精确、标签、包含三组按来源数排序，其余结果保持发现顺序。
      if (leftBucket != 3) {
        final origins = right.origins.length.compareTo(left.origins.length);
        if (origins != 0) return origins;
      }
      return left.order.compareTo(right.order);
    });
    final sortedRows = [...pinnedRows, ...rows];
    if (sortedRows.length > maxRetainedResults) {
      _resultLimitReached = true;
      final retained = sortedRows
          .take(maxRetainedResults)
          .toList(growable: false);
      final retainedKeys = {for (final row in retained) row.key};
      _books.removeWhere((key, _) => !retainedKeys.contains(key));
      _urlIndex.removeWhere((_, key) => !retainedKeys.contains(key));
      return List.unmodifiable(retained.map((row) => row.value.novel));
    }
    return List.unmodifiable(sortedRows.map((row) => row.value.novel));
  }

  static String _bookKey(Novel book) =>
      '${_normalize(book.title)}\u0000${_normalize(book.author)}';

  static String? _bookUrlKey(Novel book) {
    final source = book.source;
    if (source == null || source.bookUrl.trim().isEmpty) return null;
    return '${source.sourceKey}\u0000${source.bookUrl}';
  }

  static String _origin(Novel book) => book.source?.sourceKey ?? 'wenku8';

  static int _officialRank(Novel book) {
    final sites = OfficialBookService.searchSites;
    final sourceKey = book.source?.sourceKey;
    for (var index = 0; index < sites.length; index++) {
      if (sourceKey == OfficialBookService.sourceKey(sites[index])) return index;
    }
    return sites.length;
  }

  static final _spacing = RegExp(r'[\s\u3000·・_\-—–，,。.:：()（）\[\]【】「」『』《》]');

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(_spacing, '');
}

class _MergedSearchBook {
  _MergedSearchBook(this.novel, this.order);

  Novel novel;
  final int order;
  final Set<String> origins = {};

  int bucket(String query) {
    if (query.isEmpty) return 3;
    final title = NovelSearchMerger._normalize(novel.title);
    final author = NovelSearchMerger._normalize(novel.author);
    final tags = NovelSearchMerger._normalize(novel.genre);
    if (title == query || author == query) return 0;
    if (tags.contains(query)) return 1;
    if (title.contains(query) || author.contains(query)) return 2;
    return 3;
  }
}
