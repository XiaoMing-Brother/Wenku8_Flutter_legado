import 'fanqie_core_service.dart';

/// 番茄「官方 App 协议」数据源（走内嵌 Rust 核心）。
///
/// 这里是 route A 的业务适配层：把本仓库需要的能力（搜索 / 榜单 / 段评 / 正文）
/// 映射到 novel-sound 的本地 `/api/v1/*` 端点。返回原始 JSON Map 以便复用现有
/// 模型解析（parseSearchTabs / ChapterIdeas.fromPayload / parseParagraphComments /
/// parseChapterContent 等），从而逐步替换 official_books.dart 里的 web 抓取。
///
/// 端点 ← Rust handler（rust/src/endpoints/）：
/// - 搜索     GET  /api/v1/search            ← search.rs（fqnovel reading search）
/// - 热搜     GET  /api/v1/search/hot        ← search.rs hot_search
/// - 分类     GET  /api/v1/category          ← search.rs category_front
/// - 榜单     GET  /api/v1/rank/{id}         ← author.rs rank_data
/// - 目录     GET  /api/v1/books/{id}/directory ← book.rs directory
/// - 详情     GET  /api/v1/books/{id}/detail    ← book.rs book_detail_legacy
/// - 段评计数 GET  /api/v1/chapters/{id}/reviews ← comments.rs idea_list
/// - 段落评论 GET  /api/v1/books/{id}/reviews    ← comments.rs book_reviews(channel 38)
/// - 正文     GET  /api/v1/chapters/{id}/novel   ← dhcontent.rs（DH 解密）
///
/// 付费/VIP：核心不做解锁。取不到正文时 `data.content_decrypted != true` 或
/// content 为空，本层抛 [FanqieContentUnavailable]，调用方按「试读/需官方阅读」提示。
class FanqieCoreSource {
  FanqieCoreSource(this.core);

  final FanqieCoreService core;

  factory FanqieCoreSource.shared() => FanqieCoreSource(FanqieCoreService.instance);

  // --- 搜索 / 发现 --------------------------------------------------------

  Future<Map<String, dynamic>> search(
    String query, {
    int page = 1,
    int count = 10,
  }) {
    final offset = (page > 1 ? page - 1 : 0) * count;
    return core.requestJson(
      'GET',
      '/api/v1/search',
      query: 'query=${Uri.encodeQueryComponent(query)}&offset=$offset&count=$count',
    );
  }

  Future<Map<String, dynamic>> hotSearch({int showType = 472}) =>
      core.requestJson('GET', '/api/v1/search/hot', query: 'show_type=$showType');

  Future<Map<String, dynamic>> categoryFront({int tab = 1}) =>
      core.requestJson('GET', '/api/v1/category', query: 'category_tab=$tab');

  Future<Map<String, dynamic>> searchSuggestions(String keyword) =>
      core.requestJson('GET', '/api/v1/search/suggest',
          query: 'q=${Uri.encodeQueryComponent(keyword)}');

  // --- 榜单 ---------------------------------------------------------------

  /// [rankId] 是榜单 cell id；[algo] 是目录里的 rank_algo；[subInfoId] 是子分类 id。
  Future<Map<String, dynamic>> rank(
    String rankId, {
    int algo = 101,
    int subInfoId = 2,
    int genreTab = 2,
    int offset = 0,
  }) {
    return core.requestJson(
      'GET',
      '/api/v1/rank/${Uri.encodeComponent(rankId)}',
      query: 'algo_type=$algo&rank_sub_info_id=$subInfoId'
          '&genre_tab=$genreTab&offset=$offset',
    );
  }

  // --- 详情 / 目录 --------------------------------------------------------

  Future<Map<String, dynamic>> bookDetail(String bookId) =>
      core.requestJson('GET', '/api/v1/books/${Uri.encodeComponent(bookId)}/detail');

  Future<Map<String, dynamic>> directory(String bookId) => core.requestJson(
        'GET',
        '/api/v1/books/${Uri.encodeComponent(bookId)}/directory',
      );

  // --- 段评 ---------------------------------------------------------------

  /// 每段评论计数（idea list）。[itemVersion] 建议传目录里的章节 version。
  Future<Map<String, dynamic>> chapterIdeas(
    String itemId, {
    String itemVersion = '',
    int commentSource = 3,
  }) {
    final query = StringBuffer('comment_source=$commentSource');
    if (itemVersion.isNotEmpty) {
      query.write('&item_version=${Uri.encodeQueryComponent(itemVersion)}');
    }
    return core.requestJson(
      'GET',
      '/api/v1/chapters/${Uri.encodeComponent(itemId)}/reviews',
      query: query.toString(),
    );
  }

  /// 指定段落的评论正文。
  ///
  /// 官方配方（novel-sound 实测结论）：容器 `group_id`=章节 item_id、
  /// `business_param.book_id`=真实书 id、`group_type=15`、`comment_source=2`、
  /// `comment_type=1`、**`server_channel=38`**（43/39 都不对），外加 `para_index`
  /// 与 `item_version`（三者缺一上游报 103001）。
  Future<Map<String, dynamic>> paragraphComments(
    String bookId,
    String itemId, {
    required String itemVersion,
    required int paraIndex,
    int count = 20,
    String cursor = '',
  }) {
    final query = StringBuffer()
      ..write('book_id=${Uri.encodeQueryComponent(bookId)}')
      ..write('&group_id=${Uri.encodeQueryComponent(itemId)}')
      ..write('&group_type=15&comment_source=2&comment_type=1&server_channel=38')
      ..write('&para_index=$paraIndex')
      ..write('&item_version=${Uri.encodeQueryComponent(itemVersion)}')
      ..write('&count=$count');
    if (cursor.isNotEmpty) query.write('&cursor=${Uri.encodeQueryComponent(cursor)}');
    return core.requestJson(
      'GET',
      '/api/v1/books/${Uri.encodeComponent(bookId)}/reviews',
      query: query.toString(),
    );
  }

  // --- 正文 ---------------------------------------------------------------

  /// 原始正文响应（含 `content_decrypted` 标记），供需要插图等结构化信息的场景。
  Future<Map<String, dynamic>> chapterRaw(String itemId) => core.requestJson(
        'GET',
        '/api/v1/chapters/${Uri.encodeComponent(itemId)}/novel',
      );

  /// 纯文本正文。
  ///
  /// 主路走 DH 阅读正文；若核心报「未解密/为空」，再退回默认 `/chapters/{id}`
  /// （阅读全文 AES 链路），与 novel-sound 的 chapterContent→contentText 级联一致。
  /// 都取不到时抛 [FanqieContentUnavailable]（VIP/付费/受限章节即走这里）。
  Future<String> chapterText(String itemId) async {
    Map<String, dynamic> payload;
    try {
      payload = await chapterRaw(itemId);
    } on FanqieCoreException {
      payload = const <String, dynamic>{};
    }
    final data = payload['data'];
    if (data is Map && data['content_decrypted'] == true && data['content'] is String) {
      final text = _extractText(data['content'] as String);
      if (text.isNotEmpty) return text;
    }
    // 兜底：默认章节端点（full AES 链路）。
    final fallback = await core.requestJson(
      'GET',
      '/api/v1/chapters/${Uri.encodeComponent(itemId)}',
    );
    final text = _extractText(fallback);
    if (text.isEmpty) {
      throw const FanqieContentUnavailable('番茄正文为空');
    }
    return text;
  }

  // --- 榜单（App 榜 catalogue）--------------------------------------------

  /// 拉首页并抽取 `rank_with_category_data` 榜单目录。
  Future<FanqieRankCatalog> rankCatalog({int tabType = 2}) async {
    final payload = await core.requestJson(
      'GET',
      '/api/v1/recommend/homepage',
      query: 'tab_type=$tabType&offset=0',
    );
    final card = _findMapWithKey(payload, 'rank_with_category_data', 0);
    if (card == null) {
      return const FanqieRankCatalog(cellId: '', tabs: [], categories: []);
    }
    final data = _asMap(card['rank_with_category_data']);
    final tabs = <FanqieRankTab>[];
    final rawTabs = data?['rank_algo_list'];
    if (rawTabs is List) {
      for (final entry in rawTabs) {
        final m = _asMap(entry);
        final name = _str(m?['rank_name']);
        final algo = _intOr(m?['rank_algo'], -1);
        if (name.isNotEmpty && algo >= 0) {
          tabs.add(FanqieRankTab(name: name, algo: algo));
        }
      }
    }
    final categories = <FanqieRankCategory>[];
    final rawCats = data?['sub_info_list'];
    if (rawCats is List) {
      for (final entry in rawCats) {
        final m = _asMap(entry);
        final name = _str(m?['info_name']);
        if (name.isNotEmpty) {
          categories.add(
            FanqieRankCategory(name: name, id: _intOr(m?['info_id'], 0)),
          );
        }
      }
    }
    final cellStr = _str(card['cell_id_str']);
    final cellId = cellStr.isNotEmpty ? cellStr : _str(card['cell_id']);
    return FanqieRankCatalog(
      cellId: cellId,
      tabs: List.unmodifiable(tabs),
      categories: List.unmodifiable(categories),
    );
  }

  /// 拉某个榜单 cell 的条目（`bookmall/cell/change`）。
  Future<List<FanqieRankItem>> rankEntries(
    String cellId, {
    required int algo,
    int subInfoId = 2,
    int genreTab = 2,
    int offset = 0,
  }) async {
    final payload = await core.requestJson(
      'GET',
      '/api/v1/rank/${Uri.encodeComponent(cellId)}',
      query: 'algo_type=$algo&rank_sub_info_id=$subInfoId'
          '&genre_tab=$genreTab&offset=$offset',
    );
    final data = _asMap(payload['data']);
    final cellView = _asMap(data?['cell_view']);
    final cells = cellView?['cell_data'];
    final out = <FanqieRankItem>[];
    final seen = <String>{};

    Map<dynamic, dynamic>? firstBook(Map<dynamic, dynamic> cell) {
      final raw = cell['book_data'];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) return e;
        }
      } else if (raw is Map) {
        return raw;
      }
      if (cell['book_name'] != null) return cell;
      return null;
    }

    void addBook(Map<dynamic, dynamic> book) {
      final id = _str(book['book_id']);
      final title = _str(book['book_name']);
      if (id.isEmpty || title.isEmpty) return;
      if (!seen.add(id)) return;
      out.add(
        FanqieRankItem(
          id: id,
          title: title,
          cover: _str(book['thumb_url']),
          author: _str(book['author']),
          abstract: _str(book['abstract']),
          category: _str(book['category']),
          wordNumber: _intOrNull(book['word_number']),
        ),
      );
    }

    if (cells is List) {
      for (final cell in cells) {
        if (cell is! Map) continue;
        final book = firstBook(cell);
        if (book != null) addBook(book);
        final nested = cell['cell_data'];
        if (nested is List) {
          for (final sub in nested) {
            if (sub is! Map) continue;
            final subBook = firstBook(sub);
            if (subBook != null) addBook(subBook);
          }
        }
      }
    }
    return out;
  }

  // --- 通用 JSON 容错助手 -------------------------------------------------

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry('$key', item));
  }

  static String _str(Object? value) => value == null ? '' : '$value'.trim();

  static int _intOr(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static int? _intOrNull(Object? value) =>
      value == null ? null : _intOr(value, 0);

  static Map<dynamic, dynamic>? _findMapWithKey(
    Object? node,
    String key,
    int depth,
  ) {
    if (depth > 14 || node == null) return null;
    if (node is List) {
      for (final child in node) {
        final found = _findMapWithKey(child, key, depth + 1);
        if (found != null) return found;
      }
      return null;
    }
    if (node is Map) {
      if (node[key] is Map) return node;
      for (final child in node.values) {
        final found = _findMapWithKey(child, key, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// 递归找第一个非空的正文串（对齐 novel-sound 的 `_extractChapterText`）。
  static String _extractText(Object? root) {
    String visit(Object? value, [int depth = 0]) {
      if (depth > 7 || value == null) return '';
      if (value is Map) {
        for (final key in const ['content', 'text', 'article_content', 'body']) {
          final candidate = value[key];
          if (candidate is String && candidate.trim().isNotEmpty) {
            return _normalize(candidate);
          }
        }
        for (final nested in value.values) {
          final result = visit(nested, depth + 1);
          if (result.isNotEmpty) return result;
        }
      } else if (value is List) {
        for (final nested in value) {
          final result = visit(nested, depth + 1);
          if (result.isNotEmpty) return result;
        }
      }
      return '';
    }

    return visit(root);
  }

  static String _normalize(String raw) {
    var text = raw
        .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\s*p[^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\s*/\s*p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }
}

/// 正文不可用（付费/VIP/受限/空章）。调用方应提示「试读」或引导官方阅读。
class FanqieContentUnavailable implements Exception {
  const FanqieContentUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 番茄榜单目录（来自首页 `rank_with_category_data`）。
class FanqieRankCatalog {
  const FanqieRankCatalog({
    required this.cellId,
    required this.tabs,
    required this.categories,
  });

  final String cellId;
  final List<FanqieRankTab> tabs;
  final List<FanqieRankCategory> categories;

  bool get isEmpty => cellId.isEmpty && tabs.isEmpty;
}

class FanqieRankTab {
  const FanqieRankTab({required this.name, required this.algo});

  final String name;
  final int algo;
}

class FanqieRankCategory {
  const FanqieRankCategory({required this.name, required this.id});

  final String name;
  final int id;
}

/// 番茄榜单条目（`cell_data[].book_data`）。
class FanqieRankItem {
  const FanqieRankItem({
    required this.id,
    required this.title,
    required this.cover,
    required this.author,
    required this.abstract,
    required this.category,
    this.wordNumber,
  });

  final String id;
  final String title;
  final String cover;
  final String author;
  final String abstract;
  final String category;
  final int? wordNumber;
}
