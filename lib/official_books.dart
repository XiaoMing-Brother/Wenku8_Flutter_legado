import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'book_sources/book_source_reference.dart';
import 'book_sources/qidian_search_webview.dart';
import 'catalog.dart';
import 'cover_disk_cache.dart';
import 'services/fanqie_core_source.dart';

enum OfficialSite { qidian, fanqie, qimao, shuqi }

extension OfficialSiteLabel on OfficialSite {
  String get label => switch (this) {
    OfficialSite.qidian => '起点',
    OfficialSite.fanqie => '番茄',
    OfficialSite.qimao => '七猫',
    OfficialSite.shuqi => '书旗',
  };

  /// 起点/番茄/七猫/书旗均支持应用内直读（详情、目录、正文都走官方）。
  bool get supportsDirectReading => true;
}

class OfficialRanking {
  const OfficialRanking({
    required this.id,
    required this.title,
    required this.site,
    required this.kind,
    this.gender,
    this.rankMold,
    this.categoryId,
    this.cellId,
    this.algo,
  });

  final String id;
  final String title;
  final OfficialSite site;
  final String kind;
  final String? gender;
  final String? rankMold;
  final String? categoryId;

  /// 动态目录（番茄官方 App 榜单）专用：榜单 cell id 与 rank_algo。
  /// 为 null 表示这是写死/网页榜单，走旧路径。
  final String? cellId;
  final int? algo;

  bool get isDynamicCore => cellId != null && algo != null;

  OfficialRanking copyWith({
    String? categoryId,
    bool clearCategoryId = false,
  }) => OfficialRanking(
    id: id,
    title: title,
    site: site,
    kind: kind,
    gender: gender,
    rankMold: rankMold,
    categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
    cellId: cellId,
    algo: algo,
  );
}

/// 番茄官方榜单目录（动态）：`boards` 为榜单列表，`categories` 为子分类。
class FanqieCoreRankSet {
  const FanqieCoreRankSet({required this.boards, required this.categories});

  final List<OfficialRanking> boards;
  final List<OfficialCategory> categories;
}

class OfficialCategory {
  const OfficialCategory({required this.id, required this.name});

  final String id;
  final String name;
}

const fanqieMaleCategories = <OfficialCategory>[
  OfficialCategory(id: '1141', name: '西方奇幻'),
  OfficialCategory(id: '1140', name: '东方仙侠'),
  OfficialCategory(id: '8', name: '科幻末世'),
  OfficialCategory(id: '261', name: '都市日常'),
  OfficialCategory(id: '124', name: '都市修真'),
  OfficialCategory(id: '1014', name: '都市高武'),
  OfficialCategory(id: '273', name: '历史古代'),
  OfficialCategory(id: '27', name: '战神赘婿'),
  OfficialCategory(id: '263', name: '都市种田'),
  OfficialCategory(id: '258', name: '传统玄幻'),
  OfficialCategory(id: '272', name: '历史脑洞'),
  OfficialCategory(id: '539', name: '悬疑脑洞'),
  OfficialCategory(id: '262', name: '都市脑洞'),
  OfficialCategory(id: '257', name: '玄幻脑洞'),
  OfficialCategory(id: '751', name: '悬疑灵异'),
  OfficialCategory(id: '504', name: '抗战谍战'),
  OfficialCategory(id: '746', name: '游戏体育'),
  OfficialCategory(id: '718', name: '动漫衍生'),
  OfficialCategory(id: '1016', name: '男频衍生'),
];

const fanqieFemaleCategories = <OfficialCategory>[
  OfficialCategory(id: '1139', name: '古风世情'),
  OfficialCategory(id: '8', name: '科幻末世'),
  OfficialCategory(id: '746', name: '游戏体育'),
  OfficialCategory(id: '1015', name: '女频衍生'),
  OfficialCategory(id: '248', name: '玄幻言情'),
  OfficialCategory(id: '23', name: '种田'),
  OfficialCategory(id: '79', name: '年代'),
  OfficialCategory(id: '267', name: '现言脑洞'),
  OfficialCategory(id: '246', name: '宫斗宅斗'),
  OfficialCategory(id: '539', name: '悬疑脑洞'),
  OfficialCategory(id: '253', name: '古言脑洞'),
  OfficialCategory(id: '24', name: '快穿'),
  OfficialCategory(id: '749', name: '青春甜宠'),
  OfficialCategory(id: '745', name: '星光璀璨'),
  OfficialCategory(id: '747', name: '女频悬疑'),
  OfficialCategory(id: '750', name: '职场婚恋'),
  OfficialCategory(id: '748', name: '豪门总裁'),
  OfficialCategory(id: '1017', name: '民国言情'),
];

/// 七猫分类使用 `频道:一级分类` 编码：0 男生原创、1 女生原创。
/// 选择「全部」时保持空串，继续走官方榜单页。
const qimaoMaleCategories = <OfficialCategory>[
  OfficialCategory(id: '', name: '全部'),
  OfficialCategory(id: '0:202', name: '玄幻奇幻'),
  OfficialCategory(id: '0:203', name: '都市'),
  OfficialCategory(id: '0:204', name: '奇闻异事'),
  OfficialCategory(id: '0:205', name: '武侠仙侠'),
  OfficialCategory(id: '0:56', name: '历史'),
  OfficialCategory(id: '0:60', name: '军事'),
  OfficialCategory(id: '0:64', name: '科幻'),
  OfficialCategory(id: '0:75', name: '游戏'),
  OfficialCategory(id: '0:206', name: '体育'),
  OfficialCategory(id: '0:207', name: 'N次元'),
  OfficialCategory(id: '0:306', name: '现实题材'),
];

const qimaoFemaleCategories = <OfficialCategory>[
  OfficialCategory(id: '', name: '全部'),
  OfficialCategory(id: '1:1', name: '现代言情'),
  OfficialCategory(id: '1:2', name: '古代言情'),
  OfficialCategory(id: '1:4', name: '幻想言情'),
  OfficialCategory(id: '1:200', name: '游戏竞技'),
  OfficialCategory(id: '1:277', name: '衍生言情'),
  OfficialCategory(id: '1:307', name: '现实主义'),
];

const qidianCategories = <OfficialCategory>[
  OfficialCategory(id: '', name: '全部'),
  OfficialCategory(id: '21', name: '玄幻'),
  OfficialCategory(id: '1', name: '奇幻'),
  OfficialCategory(id: '2', name: '武侠'),
  OfficialCategory(id: '22', name: '仙侠'),
  OfficialCategory(id: '4', name: '都市'),
  OfficialCategory(id: '5', name: '历史'),
  OfficialCategory(id: '6', name: '军事'),
  OfficialCategory(id: '7', name: '游戏'),
  OfficialCategory(id: '8', name: '体育'),
  OfficialCategory(id: '9', name: '科幻'),
  OfficialCategory(id: '10', name: '悬疑灵异'),
  OfficialCategory(id: '12', name: '轻小说'),
  OfficialCategory(id: '15', name: '现实'),
];

const officialRankings = <OfficialRanking>[
  OfficialRanking(
    id: 'qidian-yuepiao',
    title: '月票榜',
    site: OfficialSite.qidian,
    kind: 'yuepiao',
  ),
  OfficialRanking(
    id: 'qidian-hotsales',
    title: '畅销榜',
    site: OfficialSite.qidian,
    kind: 'hotsales',
  ),
  OfficialRanking(
    id: 'qidian-readindex',
    title: '阅读榜',
    site: OfficialSite.qidian,
    kind: 'readindex',
  ),
  OfficialRanking(
    id: 'qidian-newfans',
    title: '书友榜',
    site: OfficialSite.qidian,
    kind: 'newfans',
  ),
  OfficialRanking(
    id: 'qidian-rec',
    title: '推荐榜',
    site: OfficialSite.qidian,
    kind: 'rec',
  ),
  OfficialRanking(
    id: 'qidian-update',
    title: '更新榜',
    site: OfficialSite.qidian,
    kind: 'update',
  ),
  OfficialRanking(
    id: 'qidian-sign',
    title: '签约榜',
    site: OfficialSite.qidian,
    kind: 'sign',
  ),
  OfficialRanking(
    id: 'qidian-newbook',
    title: '新书榜',
    site: OfficialSite.qidian,
    kind: 'newbook',
  ),
  OfficialRanking(
    id: 'qidian-newauthor',
    title: '新人榜',
    site: OfficialSite.qidian,
    kind: 'newauthor',
  ),
  OfficialRanking(
    id: 'fanqie-male-read',
    title: '男频阅读榜',
    site: OfficialSite.fanqie,
    kind: 'male-read',
    gender: '1',
    rankMold: '2',
    categoryId: '1141',
  ),
  OfficialRanking(
    id: 'fanqie-male-new',
    title: '男频新书榜',
    site: OfficialSite.fanqie,
    kind: 'male-new',
    gender: '1',
    rankMold: '1',
    categoryId: '1141',
  ),
  OfficialRanking(
    id: 'fanqie-female-read',
    title: '女频阅读榜',
    site: OfficialSite.fanqie,
    kind: 'female-read',
    gender: '0',
    rankMold: '2',
    categoryId: '1139',
  ),
  OfficialRanking(
    id: 'fanqie-female-new',
    title: '女频新书榜',
    site: OfficialSite.fanqie,
    kind: 'female-new',
    gender: '0',
    rankMold: '1',
    categoryId: '1139',
  ),
  OfficialRanking(
    id: 'fanqie-male-complete',
    title: '男频完本榜',
    site: OfficialSite.fanqie,
    kind: 'complete',
    gender: '1',
    rankMold: '2',
    categoryId: '1141',
  ),
  OfficialRanking(
    id: 'fanqie-female-complete',
    title: '女频完本榜',
    site: OfficialSite.fanqie,
    kind: 'complete',
    gender: '0',
    rankMold: '2',
    categoryId: '1139',
  ),
  // 七猫：榜单页按 /paihang/{boy|girl}/{hot|collect|new|over|update}/date/ 渲染，
  // 仅用于发现页浏览，点书走书源搜索。
  OfficialRanking(
    id: 'qimao-boy-hot',
    title: '男生大热榜',
    site: OfficialSite.qimao,
    kind: 'hot',
    gender: 'boy',
  ),
  OfficialRanking(
    id: 'qimao-boy-new',
    title: '男生新书榜',
    site: OfficialSite.qimao,
    kind: 'new',
    gender: 'boy',
  ),
  OfficialRanking(
    id: 'qimao-boy-over',
    title: '男生完结榜',
    site: OfficialSite.qimao,
    kind: 'over',
    gender: 'boy',
  ),
  OfficialRanking(
    id: 'qimao-boy-collect',
    title: '男生收藏榜',
    site: OfficialSite.qimao,
    kind: 'collect',
    gender: 'boy',
  ),
  OfficialRanking(
    id: 'qimao-boy-update',
    title: '男生更新榜',
    site: OfficialSite.qimao,
    kind: 'update',
    gender: 'boy',
  ),
  OfficialRanking(
    id: 'qimao-girl-hot',
    title: '女生大热榜',
    site: OfficialSite.qimao,
    kind: 'hot',
    gender: 'girl',
  ),
  OfficialRanking(
    id: 'qimao-girl-new',
    title: '女生新书榜',
    site: OfficialSite.qimao,
    kind: 'new',
    gender: 'girl',
  ),
  OfficialRanking(
    id: 'qimao-girl-over',
    title: '女生完结榜',
    site: OfficialSite.qimao,
    kind: 'over',
    gender: 'girl',
  ),
  OfficialRanking(
    id: 'qimao-girl-collect',
    title: '女生收藏榜',
    site: OfficialSite.qimao,
    kind: 'collect',
    gender: 'girl',
  ),
  OfficialRanking(
    id: 'qimao-girl-update',
    title: '女生更新榜',
    site: OfficialSite.qimao,
    kind: 'update',
    gender: 'girl',
  ),
  // 书旗：榜单页 /ranklist?rank={kind}&page={n}，kind 已含性别与维度。
  OfficialRanking(
    id: 'shuqi-boy-hot',
    title: '男生热榜',
    site: OfficialSite.shuqi,
    kind: 'boyhot',
  ),
  OfficialRanking(
    id: 'shuqi-boy-click',
    title: '男生点击榜',
    site: OfficialSite.shuqi,
    kind: 'boyClick',
  ),
  OfficialRanking(
    id: 'shuqi-boy-store',
    title: '男生收藏榜',
    site: OfficialSite.shuqi,
    kind: 'boyStore',
  ),
  OfficialRanking(
    id: 'shuqi-boy-update',
    title: '男生更新榜',
    site: OfficialSite.shuqi,
    kind: 'boyUpdate',
  ),
  OfficialRanking(
    id: 'shuqi-boy-end',
    title: '男生完本榜',
    site: OfficialSite.shuqi,
    kind: 'boyEnd',
  ),
  OfficialRanking(
    id: 'shuqi-girl-hot',
    title: '女生热榜',
    site: OfficialSite.shuqi,
    kind: 'girlhot',
  ),
  OfficialRanking(
    id: 'shuqi-girl-click',
    title: '女生点击榜',
    site: OfficialSite.shuqi,
    kind: 'girlClick',
  ),
  OfficialRanking(
    id: 'shuqi-girl-store',
    title: '女生收藏榜',
    site: OfficialSite.shuqi,
    kind: 'girlStore',
  ),
  OfficialRanking(
    id: 'shuqi-girl-end',
    title: '女生完本榜',
    site: OfficialSite.shuqi,
    kind: 'girlEnd',
  ),
];

class OfficialBook {
  const OfficialBook({
    required this.site,
    required this.bookId,
    required this.title,
    required this.author,
    required this.kind,
    required this.summary,
    required this.coverUrl,
    required this.bookUrl,
    this.rank,
    this.wordCount,
    this.votes,
  });

  final OfficialSite site;
  final String bookId;
  final String title;
  final String author;
  final String kind;
  final String summary;
  final String coverUrl;
  final String bookUrl;
  final int? rank;
  final String? wordCount;
  final String? votes;

  Novel toNovel() {
    final count = RegExp(r'([\d.]+)\s*(万)?字?').firstMatch(wordCount ?? '');
    final amount = double.tryParse(count?.group(1) ?? '');
    return Novel(
      id: OfficialBookService.idFor(this),
      title: title,
      author: author,
      genre: kind,
      summary: summary,
      colors: const [Color(0xFF31405A), Color(0xFF1B2333)],
      coverUrl: coverUrl.isEmpty ? null : coverUrl,
      wordCount: amount == null
          ? null
          : (amount * (count?.group(2) == null ? 1 : 10000)).round(),
      source: OfficialBookService.refFor(this),
    );
  }
}

class OfficialRankingPage {
  const OfficialRankingPage({
    required this.books,
    required this.hasMore,
    required this.page,
  });

  final List<OfficialBook> books;
  final bool hasMore;
  final int page;
}

class OfficialChapter {
  const OfficialChapter({required this.title, required this.url});

  final String title;
  final String url;
}

class OfficialBookData {
  const OfficialBookData({
    required this.title,
    required this.author,
    required this.intro,
    required this.kind,
    required this.coverUrl,
    required this.tocUrl,
    required this.status,
    required this.isComplete,
    required this.chapterCount,
    this.wordCount,
    this.updateTime,
  });

  final String title;
  final String author;
  final String intro;
  final String kind;
  final String coverUrl;
  final String tocUrl;
  final String status;
  final bool isComplete;
  final int chapterCount;
  final int? wordCount;
  final String? updateTime;
}

/// 直接访问起点/番茄官网接口；这条链路不经过书源规则，也不要求用户导入书源。
class OfficialBookService {
  static const _qidianToken = 'wenku-official';
  static const _qidianCookie = '_csrfToken=$_qidianToken';
  static const _mobileUa =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';
  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120 Safari/537.36';

  static bool isOfficialKey(String key) => key.startsWith('official:');

  static OfficialSite siteForKey(String key) {
    for (final site in OfficialSite.values) {
      if (key == 'official:${site.name}') return site;
    }
    return key.endsWith(OfficialSite.fanqie.name)
        ? OfficialSite.fanqie
        : OfficialSite.qidian;
  }

  static String sourceKey(OfficialSite site) => 'official:${site.name}';

  static BookSourceRef refFor(OfficialBook book) => BookSourceRef(
    sourceKey: sourceKey(book.site),
    sourceName: '${book.site.label}官方',
    bookUrl: book.bookUrl,
    title: book.title,
    author: book.author,
    coverUrl: book.coverUrl,
  );

  static int idFor(OfficialBook book) =>
      _stableId('official:${book.site.name}:${book.bookId}');

  static final Map<String, Uint8List> _coverCache = {};

  static const searchSites = OfficialSite.values;

  static Future<OfficialRankingPage> search(
    OfficialSite site,
    String query,
    int page,
  ) async {
    if (query.trim().isEmpty || (site == OfficialSite.qidian && page != 1)) {
      return OfficialRankingPage(books: const [], hasMore: false, page: page);
    }
    // 番茄搜索需要签名的 v1 接口在无 a_bogus/msToken 时只回 HTTP 200 + 空正文，
    // 改走无需签名的 v0 列表 + /api/book/info 明文补全，逻辑见 _fanqieSearch。
    if (site == OfficialSite.fanqie) {
      return _fanqieSearch(query.trim(), page);
    }
    if (site == OfficialSite.qidian) {
      return _qidianSearch(query.trim(), page);
    }
    final uri = switch (site) {
      OfficialSite.qimao => Uri.https(
        'api-www.qimao.com',
        '/api/search/result',
        {'keyword': query, 'page': '$page'},
      ),
      OfficialSite.shuqi => Uri.https('www.shuqi.com', '/search', {
        'keyword': query,
        'page': '$page',
      }),
      OfficialSite.qidian => Uri.https('m.qidian.com', '/search', {
        'kw': query.trim(),
      }),
      // 番茄在上方已提前 return，此分支仅为让 switch 覆盖全部枚举值。
      OfficialSite.fanqie =>
        Uri.https('fanqienovel.com', '/api/author/search/search_book/v0', {
          'query_word': query.trim(),
          'query_type': '0',
          'filter': '127,127,127,127',
          'page_index': '${page - 1}',
          'page_count': '10',
        }),
    };
    final text = await _getText(
      uri,
      headers: {
        'Referer': site == OfficialSite.qimao
            ? 'https://www.qimao.com/'
            : '${uri.origin}/',
      },
    );
    return parseSearchPage(site, text, page);
  }

  static OfficialRankingPage parseSearchPage(
    OfficialSite site,
    String text,
    int page,
  ) {
    final books = <OfficialBook>[];
    final ids = <String>{};
    var hasMore = false;
    void add(
      String id,
      String title,
      String author,
      String kind,
      String intro,
      String cover,
      String url,
    ) {
      if (!RegExp(r'^\d+$').hasMatch(id) || title.isEmpty || !ids.add(id)) {
        return;
      }
      books.add(
        OfficialBook(
          site: site,
          bookId: id,
          title: title,
          author: author,
          kind: kind,
          summary: intro,
          coverUrl: cover.startsWith('//') ? 'https:$cover' : cover,
          bookUrl: url,
        ),
      );
    }

    switch (site) {
      case OfficialSite.qimao:
        final data = _map(_map(jsonDecode(text))?['data']);
        if (data?['search_list'] is! List) {
          throw const FormatException('七猫搜索结果结构已变化');
        }
        for (final item in _list(data?['search_list']).whereType<Map>()) {
          final id = _string(item['book_id']);
          add(
            id,
            _string(item['title']),
            _string(item['author']),
            _string(item['category2_name']),
            _string(item['intro']),
            _string(item['image_link']),
            'https://www.qimao.com/shuku/$id/',
          );
        }
        final meta = _map(data?['page_data']);
        hasMore =
            _int(meta?['page']) == page &&
            page * (_int(meta?['page_size']) ?? 15) <
                (_int(meta?['count']) ?? 0);
      case OfficialSite.shuqi:
        final document = html_parser.parse(text);
        if (document.querySelector('.searchlist-main, .matchbook') == null) {
          throw const FormatException('书旗搜索结果结构已变化');
        }
        for (final row in document.querySelectorAll(
          '.matchbook, .searchlist-main li',
        )) {
          final link = row.querySelector('a.bname, a.ellipsis');
          final id = _shuqiBookId(link?.attributes['href'] ?? '');
          final author =
              row.querySelector('.bauthor, .book-autor')?.text.trim() ?? '';
          add(
            id,
            link?.text.trim() ?? '',
            author.replaceFirst(RegExp(r'^作者[：:]\s*'), ''),
            row.querySelector('.category, .lastchapter li')?.text.trim() ?? '',
            row.querySelector('.bookDesc, .book-newc')?.text.trim() ?? '',
            row.querySelector('img')?.attributes['src'] ?? '',
            'https://www.shuqi.com/book/$id.html',
          );
        }
        hasMore = document
            .querySelectorAll('.cp-wp-page a')
            .any((link) => link.text.trim() == '下一页');
      case OfficialSite.qidian:
        final info = _map(_pageContext(text)['bookInfo']);
        final records = info?['records'];
        if (records is! List) throw const FormatException('起点搜索页缺少书籍列表');
        for (final item in records.whereType<Map>()) {
          final id = _string(item['bid']);
          add(
            id,
            _plainText(_string(item['bName'])),
            _plainText(_string(item['bAuth'])),
            _string(item['cat']),
            _plainText(_string(item['desc'])),
            _string(item['imgUrl']),
            'https://m.qidian.com/book/$id/',
          );
        }
      case OfficialSite.fanqie:
        if (text.trim().isEmpty) throw const FormatException('番茄搜索接口返回空响应');
        final response = _map(jsonDecode(text));
        final data = _map(response?['data']);
        final records = data?['search_book_data_list'];
        if (_int(response?['code']) != 0 || records is! List) {
          throw const FormatException('番茄搜索接口未返回书籍列表');
        }
        for (final item in records.whereType<Map>()) {
          final id = _string(item['book_id']);
          add(
            id,
            _string(item['book_name']),
            _string(item['author']),
            _string(item['category']),
            _string(item['book_abstract']),
            _string(item['thumb_url']),
            'https://fanqienovel.com/page/$id',
          );
        }
        hasMore = page * 10 < (_int(data?['total_count']) ?? 0);
    }
    return OfficialRankingPage(
      books: books,
      hasMore: books.isNotEmpty && hasMore,
      page: page,
    );
  }

  /// 起点关键词搜索。
  ///
  /// 起点 `m.qidian.com/search` 对裸 HTTP 与真机 WebView 都会返回
  /// “页面无法访问”错误页；而桌面页 `www.qidian.com/so/<关键词>.html` 能在真实
  /// 浏览器内核里过 argus 并渲染结果。故优先用 [QidianSearchWebView] 的无头
  /// 浏览器抓取桌面搜索页的结构化结果；无头不可用（非移动端/失败）时回退到
  /// 原有裸 HTTP。
  static Future<OfficialRankingPage> _qidianSearch(
    String query,
    int page,
  ) async {
    try {
      final items = await QidianSearchWebView.instance.fetchSearchResults(
        query,
      );
      if (items != null && items.isNotEmpty) {
        final books = <OfficialBook>[];
        final ids = <String>{};
        for (final item in items) {
          final id = _idFromUrl(_string(item['href']), RegExp(r'/book/(\d+)'));
          final title = _string(item['name']);
          if (id.isEmpty || title.isEmpty || !ids.add(id)) continue;
          books.add(
            OfficialBook(
              site: OfficialSite.qidian,
              bookId: id,
              title: title,
              author: _string(item['author']),
              kind: '',
              summary: _string(item['intro']),
              coverUrl: 'https://bookcover.yuewen.com/qdbimg/349573/$id/180',
              bookUrl: 'https://m.qidian.com/book/$id/',
            ),
          );
        }
        if (books.isNotEmpty) {
          return OfficialRankingPage(books: books, hasMore: false, page: page);
        }
      }
    } on Object {
      // 无头失败，回退裸 HTTP。
    }
    final uri = Uri.https('m.qidian.com', '/search', {'kw': query});
    final text = await _getText(
      uri,
      headers: const {'Referer': 'https://m.qidian.com/'},
    );
    return parseSearchPage(OfficialSite.qidian, text, page);
  }

  // 番茄关键词搜索（web 降级路径，核心不可用时使用）。
  //
  // 官网使用的 `/api/author/search/search_book/v1` 需要字节跳动的
  // `a_bogus` + `msToken` 签名（且与 query、UA、Cookie、时间戳严格绑定），
  // 裸请求只会得到 HTTP 200 + 0 字节正文。这里改用无需签名的旧版
  // `/api/author/search/search_book/v0`，先用它拿到书籍 ID 列表，再逐本调用
  // 同样无需签名的 `/api/book/info` 取回**明文**书名、作者、分类和简介。
  //
  // 之所以不能直接展示 v0 列表里的 `book_name`/`author`/`book_abstract`：
  // 这些文字用私用区字体做了置换混淆（例如「十日终焉」会变成「文打终焉」），
  // 只有渲染对应 woff 字体时才还原，正则/纯文本取到的是乱码。
  // ---- 内嵌 Rust 核心（官方 App 协议，route A）适配 ------------------------
  //
  // 所有 core 路径都是「尽力而为」：核心没构建/初始化失败/解析为空一律返回
  // null 或抛，由调用方降级到现有 web 抓取。因此未编译 Rust 核心时行为与改动前
  // 完全一致，不会破坏可读性。文档见 docs/fanqie-embedded-core.md。

  /// 核心搜索：命中则返回；不可用/解析为空返回 null（降级 web）。
  static Future<OfficialRankingPage?> _fanqieCoreSearch(
    String query,
    int page,
  ) async {
    try {
      final payload = await FanqieCoreSource.shared().search(query, page: page);
      final data = _map(payload['data']);
      if (data == null) return null;
      final books = _booksFromCoreRecords(data);
      if (books.isEmpty) return null;
      final total = _int(data['total_count']) ?? _int(data['total']) ?? 0;
      final hasMore = total > 0 ? page * 10 < total : books.length >= 10;
      return OfficialRankingPage(books: books, hasMore: hasMore, page: page);
    } on Object {
      return null;
    }
  }

  /// 核心不可用时返回 null，沿用网页兜底。
  static Future<String?> _fanqieCoreContent(String chapterUrl) async {
    final itemId =
        RegExp(r'/reader/(\d+)').firstMatch(chapterUrl)?.group(1) ?? '';
    if (itemId.isEmpty) return null;
    try {
      return await FanqieCoreSource.shared().chapterText(itemId);
    } on FanqieContentUnavailable {
      return '';
    } on Object {
      // 核心未构建/初始化失败/瞬时错误：交给 web 抓取。
      return null;
    }
  }

  /// 容忍式地从核心返回体里抽取书目记录。不依赖固定 schema：递归找「同时具备
  /// 数字 book id 与标题」的 Map，按 id 去重；找不到返回空（调用方降级 web）。
  static List<OfficialBook> _booksFromCoreRecords(Map<String, dynamic> data) {
    final seen = <String>{};
    final books = <OfficialBook>[];

    String pick(Map<dynamic, dynamic> m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        if (v is num) return '$v';
      }
      return '';
    }

    void walk(Object? node, int depth) {
      if (depth > 8 || node == null) return;
      if (node is List) {
        for (final e in node) {
          walk(e, depth + 1);
        }
      } else if (node is Map) {
        final bid = pick(node, const [
          'book_id',
          'bookId',
          'book_id_str',
          'bookid',
          'id',
        ]);
        final title = pick(node, const [
          'book_name',
          'bookName',
          'title',
          'name',
          'raw_book_name',
        ]);
        if (RegExp(r'^\d{4,}$').hasMatch(bid) &&
            title.isNotEmpty &&
            seen.add(bid)) {
          var cover = _string(
            pick(node, const [
              'thumb_url',
              'thumbUrl',
              'thumbUri',
              'cover',
              'cover_url',
            ]),
          );
          if (cover.startsWith('http://')) {
            cover = 'https://${cover.substring(7)}';
          }
          books.add(
            OfficialBook(
              site: OfficialSite.fanqie,
              bookId: bid,
              title: _plainText(title),
              author: _plainText(
                pick(node, const ['author', 'authorName', 'author_name']),
              ),
              kind: _plainText(
                pick(node, const ['category', 'categoryName', 'kind']),
              ),
              summary: _plainText(
                pick(node, const [
                  'book_abstract',
                  'abstract',
                  'description',
                  'summary',
                ]),
              ),
              coverUrl: cover,
              bookUrl: 'https://fanqienovel.com/page/$bid',
              wordCount: pick(node, const [
                'word_count',
                'wordNumber',
                'wordCount',
              ]),
            ),
          );
        }
        for (final v in node.values) {
          walk(v, depth + 1);
        }
      }
    }

    walk(data, 0);
    return books;
  }

  /// 核心榜单：拉首页目录 → 匹配榜名 → 拉条目 → 映射 OfficialBook。
  /// 目录取不到/匹配不到/无条目返回 null（降级 web）。
  static Future<OfficialRankingPage?> _fanqieCoreRank(
    OfficialRanking ranking,
    int page,
  ) async {
    try {
      final src = FanqieCoreSource.shared();
      final catalog = await src.rankCatalog();
      if (catalog.isEmpty) return null;
      final tab = _matchRankTab(catalog, ranking.title);
      if (tab == null) return null;
      final items = await src.rankEntries(
        catalog.cellId,
        algo: tab.algo,
        offset: (page - 1) * 20,
      );
      if (items.isEmpty) return null;
      final books = <OfficialBook>[];
      for (final e in items) {
        if (e.id.isEmpty || e.title.isEmpty) continue;
        var cover = e.cover;
        if (cover.startsWith('http://')) {
          cover = 'https://${cover.substring(7)}';
        }
        books.add(
          OfficialBook(
            site: OfficialSite.fanqie,
            bookId: e.id,
            title: _plainText(e.title),
            author: _plainText(e.author),
            kind: _plainText(e.category),
            summary: _plainText(e.abstract),
            coverUrl: cover,
            bookUrl: 'https://fanqienovel.com/page/${e.id}',
            wordCount: e.wordNumber == null ? null : '${e.wordNumber}',
          ),
        );
      }
      if (books.isEmpty) return null;
      return OfficialRankingPage(
        books: books,
        hasMore: books.length >= 20,
        page: page,
      );
    } on Object {
      return null;
    }
  }

  /// 按榜名 token 在目录里找对应 tab（阅读/新书/完本/推荐）。
  /// 首页 `rank_with_category_data` 这张卡是男频榜（推荐/完本/巅峰/口碑），与 app 内置的
  /// 「阅读/新书」榜命名并非一一对应。仅对**能确定对应**的榜走核心，其余回落 web，避免
  /// 展示错误的榜：完本→完本榜；阅读≈推荐榜；新书/巅峰/口碑 及女频 → web。
  static FanqieRankTab? _matchRankTab(FanqieRankCatalog catalog, String title) {
    if (title.contains('女频')) return null;
    if (title.contains('完本') || title.contains('完结')) {
      for (final tab in catalog.tabs) {
        if (tab.name.contains('完本') || tab.name.contains('完结')) return tab;
      }
      return null;
    }
    final target = title.contains('阅读') ? '推荐' : '';
    if (target.isEmpty) return null;
    for (final tab in catalog.tabs) {
      if (tab.name.contains(target)) return tab;
    }
    return null;
  }

  static Future<FanqieCoreRankSet?>? _fanqieRankSetFuture;

  /// 动态读取番茄官方榜单目录（首页 `rank_with_category_data` 的
  /// `rank_algo_list` + `sub_info_list`）。返回 null 表示核心不可用，调用方应回落
  /// 到写死的 `officialRankings`。结果进程内缓存；`refresh` 可强制重取。
  static Future<FanqieCoreRankSet?> fanqieRankCatalog({bool refresh = false}) {
    if (!refresh && _fanqieRankSetFuture != null) return _fanqieRankSetFuture!;
    return _fanqieRankSetFuture = _fetchFanqieRankSet();
  }

  static Future<FanqieCoreRankSet?> _fetchFanqieRankSet() async {
    try {
      final catalog = await FanqieCoreSource.shared().rankCatalog();
      if (catalog.isEmpty || catalog.tabs.isEmpty) return null;
      final boards = <OfficialRanking>[
        for (final tab in catalog.tabs)
          OfficialRanking(
            id: 'fanqie-core-${tab.algo}',
            title: tab.name,
            site: OfficialSite.fanqie,
            kind: 'core',
            cellId: catalog.cellId,
            algo: tab.algo,
          ),
      ];
      final categories = <OfficialCategory>[
        for (final c in catalog.categories)
          OfficialCategory(id: '${c.id}', name: c.name),
      ];
      return FanqieCoreRankSet(boards: boards, categories: categories);
    } on Object {
      return null;
    }
  }

  /// 动态榜单条目：直接按 cell id + rank_algo（+ 可选子分类 subInfo）取 `cell/change`。
  static Future<OfficialRankingPage?> _fanqieCoreRankByCell(
    String cellId,
    int algo,
    int page,
    String? subInfo,
  ) async {
    try {
      final sub = int.tryParse(subInfo ?? '') ?? 2;
      final items = await FanqieCoreSource.shared().rankEntries(
        cellId,
        algo: algo,
        subInfoId: sub,
        offset: (page - 1) * 20,
      );
      if (items.isEmpty) return null;
      final books = <OfficialBook>[];
      for (final e in items) {
        if (e.id.isEmpty || e.title.isEmpty) continue;
        var cover = e.cover;
        if (cover.startsWith('http://')) {
          cover = 'https://${cover.substring(7)}';
        }
        books.add(
          OfficialBook(
            site: OfficialSite.fanqie,
            bookId: e.id,
            title: _plainText(e.title),
            author: _plainText(e.author),
            kind: _plainText(e.category),
            summary: _plainText(e.abstract),
            coverUrl: cover,
            bookUrl: 'https://fanqienovel.com/page/${e.id}',
            wordCount: e.wordNumber == null ? null : '${e.wordNumber}',
          ),
        );
      }
      if (books.isEmpty) return null;
      return OfficialRankingPage(
        books: books,
        hasMore: books.length >= 20,
        page: page,
      );
    } on Object {
      return null;
    }
  }

  static Future<OfficialRankingPage> _fanqieSearch(
    String query,
    int page,
  ) async {
    // 优先走内嵌 Rust 核心（官方 App 协议）；核心不可用/解析为空则降级 web。
    final core = await _fanqieCoreSearch(query, page);
    if (core != null) return core;
    final uri =
        Uri.https('fanqienovel.com', '/api/author/search/search_book/v0', {
          'query_word': query,
          'query_type': '0',
          'filter': '127,127,127,127',
          'page_index': '${page - 1}',
          'page_count': '10',
        });
    final json = await _getJson(uri, headers: _fanqieHeaders);
    final data = _map(json['data']);
    final records = data?['search_book_data_list'];
    if ((_int(json['code']) ?? -1) != 0 || records is! List) {
      throw const FormatException('番茄搜索接口未返回书籍列表');
    }
    final items = [for (final value in records) ?_map(value)];
    final books = await Future.wait(items.map(_fanqieSearchBook));
    final total = _int(data?['total_count']) ?? 0;
    final result = books.whereType<OfficialBook>().toList(growable: false);
    return OfficialRankingPage(
      books: result,
      hasMore: result.isNotEmpty && page * 10 < total,
      page: page,
    );
  }

  /// 把 v0 搜索列表中的一条记录补全成展示用的 [OfficialBook]。
  ///
  /// 先用本地搜索字体映射把 v0 的 `book_name`/`author`/`book_abstract` 解密回
  /// 明文；只有映射没覆盖到、仍残留私用区字符时，才逐本回退到
  /// `/api/book/info`（明文 JSON）和详情页 SSR（明文兜底）。绝大多数情况下
  /// 只需 1 次 v0 请求，无需 N+1。
  static Future<OfficialBook?> _fanqieSearchBook(
    Map<String, dynamic> item,
  ) async {
    final id = _string(item['book_id']);
    if (!RegExp(r'^\d+$').hasMatch(id)) return null;
    final fontMap = await _fanqieSearchFontMap();
    var title = _decodeFanqieText(_string(item['book_name']), fontMap);
    var author = _decodeFanqieText(_string(item['author']), fontMap);
    var kind = _decodeFanqieText(_string(item['category']), fontMap);
    var intro = _decodeFanqieText(
      _plainText(_string(item['book_abstract'])),
      fontMap,
    );
    var cover = _httpsUrl(_string(item['thumb_url']));
    String? wordCount;

    if (title.isEmpty ||
        _hasFanqiePua(title) ||
        _hasFanqiePua(author) ||
        _hasFanqiePua(kind) ||
        _hasFanqiePua(intro)) {
      // 1) 明文书籍信息接口（无需签名）。
      try {
        final info = await _getJson(
          Uri.https('fanqienovel.com', '/api/book/info', {'bookId': id}),
          headers: _fanqieHeaders,
        );
        final data = _map(info['data']);
        if ((_int(info['code']) ?? -1) == 0 &&
            data != null &&
            _string(data['bookName']).isNotEmpty) {
          title = _string(data['bookName']);
          author = _string(data['authorName']);
          final categories = _fanqieCategoryNames(data['categoryV2'], const {});
          final fallback = _string(data['category']);
          kind = categories.isNotEmpty
              ? categories.toSet().join(' · ')
              : fallback;
          final abstract = _string(data['abstract']);
          intro = _plainText(
            abstract.isNotEmpty ? abstract : _string(data['description']),
          );
          final infoCover = _httpsUrl(_string(data['thumbUrl']));
          if (infoCover.isNotEmpty) cover = infoCover;
          final words = _int(data['wordNumber']);
          if (words != null && words > 0) wordCount = '$words';
        }
      } on Object {
        // 单本接口偶发失败时继续走详情页兜底。
      }

      // 2) 详情页 SSR 明文兜底。
      if (title.isEmpty || _hasFanqiePua(title)) {
        try {
          final html = await _getText(
            Uri.parse('https://fanqienovel.com/page/$id'),
            headers: _fanqieHeaders,
          );
          final page = _initialPage(html);
          final name = _string(page['bookName']);
          if (name.isNotEmpty) {
            title = name;
            author = _string(page['author']);
            final categories = _fanqieCategoryNames(
              page['categoryV2'],
              const {},
            );
            kind = categories.isNotEmpty
                ? categories.toSet().join(' · ')
                : _string(page['category']);
            intro = _plainText(_string(page['abstract']));
            final detailCover = _httpsUrl(_string(page['thumbUri']));
            if (detailCover.isNotEmpty) cover = detailCover;
          }
        } on Object {
          // 兜底也失败则丢弃该条。
        }
      }
    }

    if (title.isEmpty) return null;
    return OfficialBook(
      site: OfficialSite.fanqie,
      bookId: id,
      title: title,
      author: author,
      kind: kind,
      summary: intro,
      coverUrl: cover,
      bookUrl: 'https://fanqienovel.com/page/$id',
      wordCount: wordCount,
    );
  }

  static Future<Map<int, String>>? _fanqieFontMapFuture;
  static Future<Map<int, String>>? _fanqieLibraryFontMapFuture;

  static Future<Map<int, String>> _fanqieFontMap() => _fanqieFontMapFuture ??=
      _loadFanqieFontMap('assets/book_sources/fanqie_font_map.json');

  static Future<Map<int, String>>? _fanqieSearchFontMapFuture;

  /// 番茄**搜索接口**的字体置换表（PUA → 汉字）。
  ///
  /// 它与榜单（fanqie_font_map）和书库（fanqie_library_font_map）都不是同一套，
  /// 例如「十」在榜单字体里是 U+E41F，在搜索字体里是 U+E410，必须单独维护。
  static Future<Map<int, String>> _fanqieSearchFontMap() =>
      _fanqieSearchFontMapFuture ??= _loadFanqieFontMap(
        'assets/book_sources/fanqie_search_font_map.json',
      );

  /// 分类书库接口使用与榜单不同的字体置换表，不能共用榜单映射。
  static Future<Map<int, String>> _fanqieLibraryFontMap() =>
      _fanqieLibraryFontMapFuture ??= _loadFanqieFontMap(
        'assets/book_sources/fanqie_library_font_map.json',
      );

  static Future<Map<int, String>> _loadFanqieFontMap(String asset) async {
    try {
      final raw = await rootBundle.loadString(asset);
      final decoded = jsonDecode(raw);
      final mapping = decoded is Map ? _map(decoded['map']) : null;
      if (mapping == null) return const {};
      return {
        for (final entry in mapping.entries)
          if (entry.key.toString().startsWith('0x'))
            int.parse(entry.key.toString().substring(2), radix: 16):
                '${entry.value}',
      };
    } on Object {
      return const {};
    }
  }

  static String _decodeFanqieText(String value, Map<int, String> fontMap) {
    if (value.isEmpty || fontMap.isEmpty) return value;
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      buffer.write(fontMap[rune] ?? String.fromCharCode(rune));
    }
    return buffer.toString();
  }

  // 私用区（U+E000–U+F8FF）字符：字体映射没覆盖到的残留会落在这里。
  static final RegExp _fanqiePuaPattern = RegExp(r'[\uE000-\uF8FF]');

  static bool _hasFanqiePua(String value) => _fanqiePuaPattern.hasMatch(value);

  static Uint8List? peekCover(String url) => _coverCache[url];

  static Future<Uint8List> coverBytes(String url, {String? bookKey}) async {
    final cached = _coverCache[url];
    if (cached != null) return cached;
    final bytes = await CoverDiskCache.shared.load(
      'official',
      url,
      () => _downloadCover(url),
      bookKey: bookKey,
    );
    if (_coverCache.length > 160) _coverCache.remove(_coverCache.keys.first);
    return _coverCache[url] = bytes;
  }

  static Future<Uint8List> _downloadCover(String url) async {
    final uri = Uri.parse(url);
    final host = uri.host;
    final qidian = host.contains('qidian') || host.contains('yuewen');
    final String referer;
    if (qidian) {
      referer = 'https://m.qidian.com/';
    } else if (host.contains('qimao') || host.contains('wtzw')) {
      referer = 'https://www.qimao.com/';
    } else if (host.contains('shuqi') || host.contains('11222')) {
      referer = 'https://www.shuqi.com/';
    } else {
      referer = 'https://fanqienovel.com/';
    }
    final bytes = await _getBytes(
      uri,
      headers: {
        'User-Agent': qidian ? _mobileUa : _desktopUa,
        'Referer': referer,
      },
    );
    if (bytes.isEmpty) throw const FormatException('官方封面为空');
    return bytes;
  }

  static Future<OfficialRankingPage> ranking(
    OfficialRanking ranking,
    int page,
  ) async {
    return switch (ranking.site) {
      OfficialSite.qidian => _qidianRanking(ranking, page),
      OfficialSite.fanqie => _fanqieRanking(ranking, page),
      OfficialSite.qimao => _qimaoRanking(ranking, page),
      OfficialSite.shuqi => _shuqiRanking(ranking, page),
    };
  }

  /// 番茄分类书库：与榜单接口不同，使用独立的 author/library/book_list。
  ///
  /// [gender] 为 -1 全部、1 男生、0 女生；[categoryId] 为 -1 时表示全部书籍。
  ///
  /// 该 web 接口返回的书名/作者是**私用区字体混淆**的；静态字体映射覆盖不到时
  /// （上游字体会轮换）会显示成 `□`。因此对仍残留 PUA 的条目逐本回退到
  /// `/api/book/info`（明文 JSON）补全，保证可读——与搜索的明文兜底同一套。
  static Future<OfficialBook?> _fanqieLibraryBook(
    Map<String, dynamic> item,
    String categoryName,
    Map<int, String> fontMap,
  ) async {
    final bid = _string(item['book_id']);
    if (bid.isEmpty) return null;
    var title = _decodeFanqieText(_string(item['book_name']), fontMap);
    var author = _decodeFanqieText(_string(item['author']), fontMap);
    var intro = _decodeFanqieText(
      _plainText(_string(item['abstract'])),
      fontMap,
    );
    var cover = _httpsUrl(_string(item['thumb_url']));
    var wordCount = _decodeFanqieText(_string(item['word_count']), fontMap);

    if (title.isEmpty ||
        _hasFanqiePua(title) ||
        _hasFanqiePua(author) ||
        _hasFanqiePua(intro)) {
      try {
        final info = await _getJson(
          Uri.https('fanqienovel.com', '/api/book/info', {'bookId': bid}),
          headers: _fanqieHeaders,
        );
        final data = _map(info['data']);
        if ((_int(info['code']) ?? -1) == 0 &&
            data != null &&
            _string(data['bookName']).isNotEmpty) {
          title = _string(data['bookName']);
          author = _string(data['authorName']);
          final abstract = _string(data['abstract']);
          intro = _plainText(
            abstract.isNotEmpty ? abstract : _string(data['description']),
          );
          final infoCover = _httpsUrl(_string(data['thumbUrl']));
          if (infoCover.isNotEmpty) cover = infoCover;
          final words = _int(data['wordNumber']);
          if (words != null && words > 0) wordCount = '$words';
        }
      } on Object {
        // 单本明文接口失败就保留字体解码结果（可能仍有 □），不拖垮整页。
      }
    }

    if (title.isEmpty) return null;
    return OfficialBook(
      site: OfficialSite.fanqie,
      bookId: bid,
      title: title,
      author: author,
      kind: categoryName,
      summary: intro,
      coverUrl: cover,
      bookUrl: 'https://fanqienovel.com/page/$bid',
      wordCount: wordCount.isNotEmpty ? wordCount : null,
      votes: _decodeFanqieText(_string(item['read_count']), fontMap),
    );
  }

  static Future<OfficialRankingPage> fanqieLibrary({
    required String gender,
    required String categoryId,
    required String categoryName,
    required int page,
  }) async {
    final uri =
        Uri.https('fanqienovel.com', '/api/author/library/book_list/v0/', {
          'page_count': '18',
          'page_index': '${page - 1}',
          'gender': gender,
          'category_id': categoryId,
          'book_type': '-1',
          'creation_status': '-1',
          'word_count': '-1',
          'sort': '0',
        });
    final json = await _getJson(uri, headers: _fanqieHeaders);
    if ((_int(json['code']) ?? -1) != 0) {
      throw FormatException('番茄书库接口返回 code=${json['code']}');
    }
    final data = _map(json['data']);
    final records = _list(data?['book_list']);
    final fontMap = await _fanqieLibraryFontMap();
    final items = [for (final value in records) ?_map(value)];
    final books = (await Future.wait(
      items.map((item) => _fanqieLibraryBook(item, categoryName, fontMap)),
    )).whereType<OfficialBook>().toList(growable: false);
    final total = _int(data?['total_count']) ?? 0;
    return OfficialRankingPage(
      books: books,
      hasMore: _truthy(data?['has_more']) && (total <= 0 || page * 18 < total),
      page: page,
    );
  }

  static Future<OfficialBookData> detail(BookSourceRef ref) async {
    return switch (siteForKey(ref.sourceKey)) {
      OfficialSite.qidian => _qidianDetail(ref),
      OfficialSite.fanqie => _fanqieDetail(ref),
      OfficialSite.qimao => _qimaoDetail(ref),
      OfficialSite.shuqi => _shuqiDetail(ref),
    };
  }

  static Future<List<OfficialChapter>> chapters(BookSourceRef ref) async {
    return switch (siteForKey(ref.sourceKey)) {
      OfficialSite.qidian => _qidianChapters(ref),
      OfficialSite.fanqie => _fanqieChapters(ref),
      OfficialSite.qimao => _qimaoChapters(ref),
      OfficialSite.shuqi => _shuqiChapters(ref),
    };
  }

  /// 返回官网提供的正文文本或 HTML。
  static Future<String> content(BookSourceRef ref, String chapterUrl) async {
    return switch (siteForKey(ref.sourceKey)) {
      OfficialSite.qidian => _qidianContent(chapterUrl),
      OfficialSite.fanqie => _fanqieContent(chapterUrl),
      OfficialSite.qimao => _qimaoContent(chapterUrl),
      OfficialSite.shuqi => _shuqiContent(chapterUrl),
    };
  }

  static Future<OfficialRankingPage> _qidianRanking(
    OfficialRanking ranking,
    int page,
  ) async {
    final path = switch (ranking.kind) {
      'readindex' => '/webcommon/rank/readIndexlist',
      _ => '/webcommon/rank/${ranking.kind}list',
    };
    final uri = Uri.https('m.qidian.com', path, {
      'gender': 'male',
      'pageNum': '$page',
      '_csrfToken': 'wenku-official',
      if ((ranking.categoryId ?? '').isNotEmpty) 'catId': ranking.categoryId!,
    });
    final json = await _getJson(
      uri,
      headers: const {
        'Cookie': _qidianCookie,
        'Referer': 'https://m.qidian.com/',
      },
    );
    final data = _map(json['data']);
    final records = _list(data?['records']);
    final books = <OfficialBook>[];
    for (final value in records) {
      final item = _map(value);
      if (item == null) continue;
      final bid = _string(item['bid']);
      if (bid.isEmpty) continue;
      books.add(
        OfficialBook(
          site: OfficialSite.qidian,
          bookId: bid,
          title: _string(item['bName']),
          author: _string(item['bAuth']),
          kind: _string(item['cat']),
          summary: _string(item['desc']),
          coverUrl: 'https://bookcover.yuewen.com/qdbimg/349573/$bid/180',
          bookUrl: 'https://m.qidian.com/book/$bid/',
          rank: _int(item['rankNum']),
          wordCount: _string(item['cnt']),
          votes: _string(item['rankCnt']),
        ),
      );
    }
    final total = _int(data?['total']) ?? 0;
    return OfficialRankingPage(
      books: books,
      hasMore:
          books.isNotEmpty &&
          !_truthy(data?['isLast']) &&
          (total <= 0 || page * 20 < total),
      page: page,
    );
  }

  static Future<OfficialRankingPage> _fanqieRanking(
    OfficialRanking ranking,
    int page,
  ) async {
    // 动态官方榜：直接按 cell id + rank_algo 取条目（不再依赖写死榜名）。
    if (ranking.isDynamicCore) {
      final dynamicPage = await _fanqieCoreRankByCell(
        ranking.cellId!,
        ranking.algo!,
        page,
        ranking.categoryId,
      );
      if (dynamicPage != null) return dynamicPage;
    }
    // 核心优先（首页 catalogue → cell/change）；不可用/匹配不到则降级 web。
    final core = await _fanqieCoreRank(ranking, page);
    if (core != null) return core;
    final complete = ranking.kind == 'complete';
    final uri = Uri.https('fanqienovel.com', '/api/rank/category/list', {
      'app_id': '2503',
      'rank_list_type': '3',
      'offset': complete ? '0' : '${(page - 1) * 20}',
      'limit': complete ? '100' : '20',
      'category_id': ranking.categoryId ?? '1139',
      'rank_version': '',
      'gender': ranking.gender ?? '0',
      'rankMold': ranking.rankMold ?? '2',
    });
    final json = await _getJson(uri, headers: _fanqieHeaders);
    final data = _map(json['data']);
    final records = _list(data?['book_list']);
    final fontMap = await _fanqieFontMap();
    final allBooks = <OfficialBook>[];
    for (final value in records) {
      final item = _map(value);
      if (item == null) continue;
      if (complete && _string(item['creationStatus']) != '0') continue;
      final bid = _string(item['bookId']);
      if (bid.isEmpty) continue;
      allBooks.add(
        OfficialBook(
          site: OfficialSite.fanqie,
          bookId: bid,
          title: _decodeFanqieText(_string(item['bookName']), fontMap),
          author: _decodeFanqieText(_string(item['author']), fontMap),
          kind: _decodeFanqieText(
            _string(item['category'] ?? item['categoryV2']),
            fontMap,
          ),
          summary: _decodeFanqieText(_string(item['abstract']), fontMap),
          coverUrl: _string(item['thumbUri']),
          bookUrl: 'https://fanqienovel.com/page/$bid',
          wordCount: _string(item['wordNumber']),
        ),
      );
    }
    final books = complete
        ? allBooks.skip((page - 1) * 20).take(20).toList(growable: false)
        : allBooks;
    final total = complete ? allBooks.length : (_int(data?['total_num']) ?? 0);
    return OfficialRankingPage(
      books: books,
      hasMore: books.length >= 20 && (total <= 0 || page * 20 < total),
      page: page,
    );
  }

  static Future<OfficialRankingPage> _qimaoRanking(
    OfficialRanking ranking,
    int page,
  ) async {
    final categoryId = ranking.categoryId ?? '';
    if (categoryId.isNotEmpty) {
      return _qimaoCategoryRanking(ranking, categoryId, page);
    }
    // 七猫榜单为服务端渲染，单页固定前 20 本，不做翻页。
    if (page > 1) {
      return const OfficialRankingPage(books: [], hasMore: false, page: 1);
    }
    final gender = ranking.gender ?? 'boy';
    final uri = Uri.https(
      'www.qimao.com',
      '/paihang/$gender/${ranking.kind}/date/',
    );
    final html = await _getText(
      uri,
      headers: const {
        'User-Agent': _desktopUa,
        'Referer': 'https://www.qimao.com/paihang/',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );
    final document = html_parser.parse(html);
    final books = <OfficialBook>[];
    for (final li in document.querySelectorAll('li.rank-list-item')) {
      final titleEl = li.querySelector('.s-book-title');
      if (titleEl == null) continue;
      final title = titleEl.text.trim();
      final href = (titleEl.attributes['href'] ?? '').trim();
      final bookId = _qimaoBookId(href);
      if (title.isEmpty || bookId.isEmpty) continue;
      final infoEl = li.querySelector('.s-book-info');
      final anchors = infoEl?.querySelectorAll('a') ?? const <dom.Element>[];
      final author = anchors.isNotEmpty ? anchors.first.text.trim() : '';
      final categories = <String>[];
      for (var i = 1; i < anchors.length; i++) {
        final name = anchors[i].text.trim();
        if (name.isNotEmpty && !categories.contains(name)) {
          categories.add(name);
        }
      }
      var wordCount = '';
      if (infoEl != null) {
        for (final mark in infoEl.querySelectorAll('em')) {
          final text = mark.text.trim();
          if (text.contains('字')) {
            wordCount = text;
            break;
          }
        }
      }
      var cover = (li.querySelector('img')?.attributes['src'] ?? '').trim();
      if (cover.startsWith('//')) cover = 'https:$cover';
      books.add(
        OfficialBook(
          site: OfficialSite.qimao,
          bookId: bookId,
          title: title,
          author: author,
          kind: categories.join(' · '),
          summary: li.querySelector('.s-book-intro')?.text.trim() ?? '',
          coverUrl: cover,
          bookUrl: 'https://www.qimao.com/shuku/$bookId/',
          wordCount: wordCount.isEmpty ? null : wordCount,
        ),
      );
    }
    return OfficialRankingPage(books: books, hasMore: false, page: page);
  }

  static Future<OfficialRankingPage> _qimaoCategoryRanking(
    OfficialRanking ranking,
    String categoryId,
    int page,
  ) async {
    final parts = categoryId.split(':');
    final channel = parts.isNotEmpty ? parts.first : '0';
    final category1 = parts.length > 1 ? parts[1] : 'a';
    // 官方分类页只有点击/字数/更新/收藏四种排序，这里按榜单类型取最接近的维度。
    final order = switch (ranking.kind) {
      'collect' => 'favorite_uv',
      'update' => 'update_time',
      _ => 'click',
    };
    final json = await _getJson(
      Uri.https('api-www.qimao.com', '/api/classify/book-list', {
        'channel': channel,
        'category1': category1,
        'category2': 'a',
        'words': 'a',
        'update_time': 'a',
        'is_vip': 'a',
        'is_over': ranking.kind == 'over' ? '1' : 'a',
        'order': order,
        'page': '$page',
      }),
      headers: _qimaoHeaders,
    );
    final data = _map(json['data']);
    final pageData = _map(data?['page_data']);
    final pageSize = _int(pageData?['page_size']) ?? 15;
    final total = _int(pageData?['count']) ?? 0;
    final books = <OfficialBook>[];
    for (final value in _list(data?['book_list'])) {
      final item = _map(value);
      if (item == null) continue;
      final title = _string(item['title']);
      final readUrl = _string(item['read_url']);
      var bookId = _string(item['book_id']);
      if (bookId.isEmpty) bookId = _qimaoBookId(readUrl);
      if (title.isEmpty || bookId.isEmpty) continue;
      var cover = _string(item['image_link']);
      if (cover.startsWith('//')) cover = 'https:$cover';
      books.add(
        OfficialBook(
          site: OfficialSite.qimao,
          bookId: bookId,
          title: title,
          author: _string(item['author']),
          kind: _string(item['category2_name']),
          summary: _string(item['intro']),
          coverUrl: cover,
          bookUrl: readUrl.isEmpty
              ? 'https://www.qimao.com/shuku/$bookId/'
              : readUrl,
          wordCount: _string(item['words_num']),
        ),
      );
    }
    return OfficialRankingPage(
      books: books,
      hasMore: books.isNotEmpty && (total <= 0 || page * pageSize < total),
      page: page,
    );
  }

  static Future<OfficialRankingPage> _shuqiRanking(
    OfficialRanking ranking,
    int page,
  ) async {
    final uri = Uri.https('www.shuqi.com', '/ranklist', {
      'rank': ranking.kind,
      'page': '$page',
    });
    final html = await _getText(
      uri,
      headers: const {
        'User-Agent': _desktopUa,
        'Referer': 'https://www.shuqi.com/ranklist',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );
    final document = html_parser.parse(html);
    final books = <OfficialBook>[];
    for (final li in document.querySelectorAll('li.clearfix')) {
      final info = li.querySelector('.ranklinst-bk');
      if (info == null) continue;
      final titleEl = info.querySelector('h3');
      if (titleEl == null) continue;
      final title = titleEl.text.trim();
      var href = '';
      for (final anchor in li.querySelectorAll('a')) {
        final value = (anchor.attributes['href'] ?? '').trim();
        if (value.contains('/book/')) {
          href = value;
          break;
        }
      }
      final bookId = _shuqiBookId(href);
      if (title.isEmpty || bookId.isEmpty) continue;
      final author = info.querySelector('.ranklist-autor a')?.text.trim() ?? '';
      final category = info.querySelector('.bkcate-icon')?.text.trim() ?? '';
      final intro = info.querySelector('.ranklist-des')?.text.trim() ?? '';
      final img =
          li.querySelector('.ranklinst-bk img') ?? li.querySelector('img');
      var cover = (img?.attributes['src'] ?? img?.attributes['data-src'] ?? '')
          .trim();
      if (cover.startsWith('//')) cover = 'https:$cover';
      books.add(
        OfficialBook(
          site: OfficialSite.shuqi,
          bookId: bookId,
          title: title,
          author: author,
          kind: category,
          summary: intro,
          coverUrl: cover,
          bookUrl: 'https://www.shuqi.com/book/$bookId.html',
        ),
      );
    }
    return OfficialRankingPage(
      books: books,
      hasMore: books.length >= 10 && page < 50,
      page: page,
    );
  }

  static String _qimaoBookId(String href) =>
      RegExp(r'/shuku/(\d+)').firstMatch(href)?.group(1) ?? '';

  static String _shuqiBookId(String href) =>
      RegExp(r'/book/(\d+)\.html').firstMatch(href)?.group(1) ?? '';

  // ───────────────────────── 七猫：详情 / 目录 / 正文 ─────────────────────────

  static Future<OfficialBookData> _qimaoDetail(BookSourceRef ref) async {
    final bookId = _idFromUrl(ref.bookUrl, RegExp(r'/shuku/(\d+)'));
    if (bookId.isEmpty) throw const FormatException('七猫书籍地址无效');
    final main = await _getJson(
      Uri.https('api-www.qimao.com', '/api/book-detail/main-info', {
        'book_id': bookId,
      }),
      headers: _qimaoHeaders,
    );
    final introJson = await _getJson(
      Uri.https('api-www.qimao.com', '/api/book-detail/intro', {
        'book_id': bookId,
      }),
      headers: _qimaoHeaders,
    );
    final bd = _map(_map(main['data'])?['book_detail']);
    final intro = _string(_map(introJson['data'])?['intro']);
    final kind = [
      _string(bd?['category_1_name']),
      _string(bd?['category_2_name']),
    ].where((value) => value.isNotEmpty).join(' · ');
    final upStatus = _string(bd?['up_status']);
    final complete = _truthy(bd?['is_over']) || upStatus.contains('完');
    final words = _num(bd?['words_num']);
    final updateRaw = _string(bd?['update_time']);
    final updateDate = RegExp(
      r'\d{4}-\d{2}-\d{2}',
    ).firstMatch(updateRaw)?.group(0);
    return OfficialBookData(
      title: _string(bd?['title']),
      author: _string(bd?['author']),
      intro: _plainText(intro),
      kind: kind,
      coverUrl: _string(bd?['image_link']),
      tocUrl: 'https://www.qimao.com/shuku/$bookId/',
      status: complete ? '已完结' : '连载中',
      isComplete: complete,
      chapterCount: _int(bd?['catalogue_num']) ?? 0,
      wordCount: words == null ? null : (words * 10000).round(),
      updateTime: updateDate,
    );
  }

  static Future<List<OfficialChapter>> _qimaoChapters(BookSourceRef ref) async {
    final bookId = _idFromUrl(ref.bookUrl, RegExp(r'/shuku/(\d+)'));
    if (bookId.isEmpty) throw const FormatException('七猫书籍地址无效');
    final json = await _getJson(
      Uri.https('api-www.qimao.com', '/api/book/chapter-list', {
        'book_id': bookId,
      }),
      headers: _qimaoHeaders,
    );
    final chapters = <OfficialChapter>[];
    for (final value in _list(_map(json['data'])?['chapters'])) {
      final item = _map(value);
      if (item == null) continue;
      final id = _string(item['id']);
      final title = _string(item['title']);
      if (id.isEmpty || title.isEmpty) continue;
      chapters.add(
        OfficialChapter(
          title: title,
          url: 'https://www.qimao.com/shuku/$bookId-$id/',
        ),
      );
    }
    if (chapters.isEmpty) throw const FormatException('七猫目录为空');
    return chapters;
  }

  static Future<String> _qimaoContent(String chapterUrl) async {
    final html = await _getText(
      Uri.parse(chapterUrl),
      headers: const {
        'User-Agent': _desktopUa,
        'Referer': 'https://www.qimao.com/paihang/',
      },
    );
    final article = html_parser.parse(html).querySelector('.article');
    final paragraphs = <String>[];
    for (final node
        in article?.querySelectorAll('p') ?? const <dom.Element>[]) {
      final text = node.text.trim();
      if (text.isNotEmpty) paragraphs.add('<p>$text</p>');
    }
    if (paragraphs.isEmpty) return article?.innerHtml ?? '';
    return paragraphs.join('\n');
  }

  // ───────────────────────── 书旗：详情 / 目录 / 正文 ─────────────────────────

  static Future<OfficialBookData> _shuqiDetail(BookSourceRef ref) async {
    final bookId = _idFromUrl(ref.bookUrl, RegExp(r'/book/(\d+)'));
    if (bookId.isEmpty) throw const FormatException('书旗书籍地址无效');
    final html = await _getText(
      Uri.https('www.shuqi.com', '/book/$bookId.html'),
      headers: _shuqiHeaders,
    );
    final doc = html_parser.parse(html);
    final title =
        doc
            .querySelector('.view-book-info-book-title-box .bname')
            ?.text
            .trim() ??
        doc.querySelector('h1')?.text.trim() ??
        '';
    final author = doc.querySelector('.bauthor a')?.text.trim() ?? '';
    final tags = [
      for (final a in doc.querySelectorAll('.tags li a')) a.text.trim(),
    ].where((value) => value.isNotEmpty).toList();
    var wordLabel = '';
    var status = '';
    var update = '';
    for (final li in doc.querySelectorAll('.lastchapter li')) {
      final text = li.text.trim();
      if (text.contains('字')) {
        wordLabel = text;
      } else if (text.contains('完') || text.contains('连载')) {
        status = text;
      } else if (text.contains('更新') || RegExp(r'\d{4}-\d').hasMatch(text)) {
        update = text;
      }
    }
    final titleText = doc.querySelector('.lastchapter .title')?.text ?? '';
    final countMatch = RegExp(r'共\s*(\d+)\s*章').firstMatch(titleText);
    final img =
        doc.querySelector('img.cover') ?? doc.querySelector('.cover img');
    var cover = (img?.attributes['src'] ?? '').trim();
    if (cover.startsWith('//')) cover = 'https:$cover';
    final complete = status.contains('完');
    return OfficialBookData(
      title: title,
      author: author,
      intro: doc.querySelector('.bookDesc .js-descContent')?.text.trim() ?? '',
      kind: tags.join(' · '),
      coverUrl: cover,
      tocUrl: 'https://www.shuqi.com/reader?bid=$bookId',
      status: status.isEmpty ? (complete ? '已完结' : '连载中') : status,
      isComplete: complete,
      chapterCount: int.tryParse(countMatch?.group(1) ?? '') ?? 0,
      wordCount: _labelToWordCount(wordLabel),
      updateTime: update.isEmpty ? null : update,
    );
  }

  static Future<List<OfficialChapter>> _shuqiChapters(BookSourceRef ref) async {
    final bookId = _idFromUrl(ref.bookUrl, RegExp(r'/book/(\d+)'));
    if (bookId.isEmpty) throw const FormatException('书旗书籍地址无效');
    final html = await _getText(
      Uri.https('www.shuqi.com', '/reader', {'bid': bookId}),
      headers: _shuqiHeaders,
    );
    final data = _shuqiBookJson(html);
    if (data == null) throw const FormatException('书旗目录页结构已变化');
    final freePrefix = _string(data['freeContUrlPrefix']);
    final shortPrefix = _string(data['shortContUrlPrefix']);
    final chapters = <OfficialChapter>[];
    for (final volume in _list(data['chapterList'])) {
      final volumeMap = _map(volume);
      if (volumeMap == null) continue;
      for (final value in _list(volumeMap['volumeList'])) {
        final item = _map(value);
        if (item == null) continue;
        final id = _string(item['chapterId']);
        final title = _string(item['chapterName']);
        if (id.isEmpty || title.isEmpty) continue;
        final isFree = _truthy(item['isFreeRead']);
        final prefix = isFree ? freePrefix : shortPrefix;
        final suffix = _string(
          isFree ? item['contUrlSuffix'] : item['shortContUrlSuffix'],
        );
        final url = prefix.isNotEmpty && suffix.isNotEmpty
            ? '$prefix$suffix'
            : 'https://www.shuqi.com/reader?bid=$bookId&cid=$id';
        chapters.add(OfficialChapter(title: title, url: url));
      }
    }
    if (chapters.isEmpty) throw const FormatException('书旗目录为空');
    return chapters;
  }

  static Future<String> _shuqiContent(String chapterUrl) async {
    final json = await _getJson(Uri.parse(chapterUrl), headers: _shuqiHeaders);
    final raw = _string(json['ChapterContent'] ?? json['chapterContent']);
    if (raw.isEmpty) return _string(json['message'] ?? json['msg']);
    return _shuqiDecodeCont(raw);
  }

  /// 书旗正文：字母位移 → Base64 → UTF-8，移植自 reader.js 的 `_decodeCont`。
  static String _shuqiDecodeCont(String input) {
    final shifted = StringBuffer();
    for (final rune in input.runes) {
      if ((rune >= 65 && rune <= 90) || (rune >= 97 && rune <= 122)) {
        final upper = rune <= 90;
        final low = upper ? rune + 32 : rune;
        var index = (low - 83) % 26;
        if (index == 0) index = 26;
        shifted.writeCharCode(index + (upper ? 64 : 96));
      } else {
        shifted.writeCharCode(rune);
      }
    }
    final base = StringBuffer();
    for (final rune in shifted.toString().runes) {
      final ok =
          (rune >= 65 && rune <= 90) ||
          (rune >= 97 && rune <= 122) ||
          (rune >= 48 && rune <= 57) ||
          rune == 43 ||
          rune == 47 ||
          rune == 61;
      if (ok) base.writeCharCode(rune);
    }
    var text = base.toString();
    final pad = (4 - text.length % 4) % 4;
    if (pad > 0) text = text + '=' * pad;
    try {
      return utf8.decode(base64Decode(text), allowMalformed: true);
    } on Object {
      return '';
    }
  }

  /// 书旗阅读页把整本书的章节与正文前缀塞进一段被 HTML 转义的 JSON 里。
  static Map<String, dynamic>? _shuqiBookJson(String html) {
    final text = html
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&amp;', '&');
    final start = text.indexOf('{"bookName":');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5C) {
          escaped = true;
        } else if (code == 0x22) {
          inString = false;
        }
      } else if (code == 0x22) {
        inString = true;
      } else if (code == 0x7B) {
        depth++;
      } else if (code == 0x7D) {
        depth--;
        if (depth == 0) {
          try {
            final decoded = jsonDecode(text.substring(start, i + 1));
            return decoded is Map ? _map(decoded) : null;
          } on Object {
            return null;
          }
        }
      }
    }
    return null;
  }

  static const _qimaoHeaders = {
    'User-Agent': _desktopUa,
    'Referer': 'https://www.qimao.com/',
  };

  static const _shuqiHeaders = {
    'User-Agent': _desktopUa,
    'Referer': 'https://www.shuqi.com/',
    'Accept': 'application/json, text/plain, */*',
  };

  static String _idFromUrl(String url, RegExp pattern) =>
      pattern.firstMatch(url)?.group(1) ?? '';

  static double? _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static int? _labelToWordCount(String label) {
    final text = label.trim();
    if (text.isEmpty) return null;
    final tenK = RegExp(r'([\d.]+)\s*万字').firstMatch(text);
    if (tenK != null) {
      final amount = double.tryParse(tenK.group(1)!);
      return amount == null ? null : (amount * 10000).round();
    }
    final chars = RegExp(r'([\d.]+)\s*字').firstMatch(text);
    if (chars != null) return double.tryParse(chars.group(1)!)?.round();
    return int.tryParse(text);
  }

  static Future<OfficialBookData> _qidianDetail(BookSourceRef ref) async {
    final html = await _getText(
      Uri.parse(ref.bookUrl),
      headers: const {
        'Cookie': _qidianCookie,
        'Referer': 'https://m.qidian.com/',
      },
    );
    final data = _pageContext(html);
    final info = _map(data['bookInfo']);
    final author = _map(data['authorInfo']);
    final bookId = _string(info?['bookId']);
    final status = _string(info?['bookStatus']);
    final labels = <String>[
      _string(info?['chanName']),
      _string(info?['subCateName']),
      for (final value in _list(info?['bookLabels']))
        _string(_map(value)?['tag']),
    ].where((value) => value.isNotEmpty).toSet().toList();
    return OfficialBookData(
      title: _string(info?['bookName']),
      author: _string(author?['authorName']),
      intro: _plainText(_string(info?['desc'])),
      kind: labels.join(' · '),
      coverUrl: 'https://bookcover.yuewen.com/qdbimg/349573/$bookId/180',
      tocUrl: 'https://m.qidian.com/book/$bookId/catalog/',
      status: status,
      isComplete: status.contains('完'),
      chapterCount: _int(data['cTCnt']) ?? 0,
      wordCount: _int(info?['wordsCnt']),
      updateTime: _epoch(_int(info?['updTimes'])),
    );
  }

  static Future<OfficialBookData> _fanqieDetail(BookSourceRef ref) async {
    final bookId = _fanqieBookId(ref.bookUrl);
    if (bookId.isNotEmpty) {
      try {
        final json = await _getJson(
          Uri.https('fanqienovel.com', '/api/book/info', {'bookId': bookId}),
          headers: _fanqieHeaders,
        );
        if ((_int(json['code']) ?? -1) == 0) {
          final data = _map(json['data']);
          if (data != null && _string(data['bookName']).isNotEmpty) {
            return _fanqieDetailFromApi(data, ref);
          }
        }
      } on Object {
        // 老页面仍可解析时继续走 HTML 兜底。
      }
    }
    final html = await _getText(
      Uri.parse(ref.bookUrl),
      headers: _fanqieHeaders,
    );
    final page = _initialPage(html);
    final fontMap = await _fanqieFontMap();
    final category = <String>[];
    try {
      final raw = page['categoryV2'];
      final decoded = raw is String ? jsonDecode(raw) : raw;
      for (final value in _list(decoded)) {
        final name = _decodeFanqieText(_string(_map(value)?['Name']), fontMap);
        if (name.isNotEmpty) category.add(name);
      }
    } on Object {
      // 接口偶发没有 categoryV2 时退回 category 字段。
    }
    final categoryFallback = _decodeFanqieText(
      _string(page['category']),
      fontMap,
    );
    if (category.isEmpty && categoryFallback.isNotEmpty) {
      category.add(categoryFallback);
    }
    final volumes = _list(page['chapterListWithVolume']);
    var chapterCount = 0;
    for (final volume in volumes) {
      chapterCount += _list(volume).length;
    }
    final lastTitle = _decodeFanqieText(
      _string(page['lastChapterTitle']),
      fontMap,
    );
    final status = lastTitle.contains('完') || lastTitle.contains('尾声')
        ? '已完结'
        : '连载中';
    return OfficialBookData(
      title: _decodeFanqieText(_string(page['bookName']), fontMap),
      author: _decodeFanqieText(_string(page['author']), fontMap),
      intro: _decodeFanqieText(_plainText(_string(page['abstract'])), fontMap),
      kind: category.toSet().join(' · '),
      coverUrl: _string(page['thumbUri']),
      tocUrl: ref.bookUrl,
      status: status,
      isComplete: status == '已完结',
      chapterCount: chapterCount,
      updateTime: _epoch(_int(page['lastPublishTime'])),
    );
  }

  static OfficialBookData _fanqieDetailFromApi(
    Map<String, dynamic> data,
    BookSourceRef ref,
  ) {
    final categories = _fanqieCategoryNames(data['categoryV2'], const {});
    final fallback = _string(data['category']);
    if (categories.isEmpty && fallback.isNotEmpty) {
      categories.add(fallback);
    }
    final lastTitle = _string(data['lastChapterTitle']);
    final complete =
        _string(data['creationStatus']) == '0' || lastTitle.contains('完');
    final cover = _httpsUrl(_string(data['thumbUrl']));
    return OfficialBookData(
      title: _string(data['bookName']),
      author: _string(data['author']),
      intro: _plainText(_string(data['abstract'])),
      kind: categories.toSet().join(' · '),
      coverUrl: cover.isEmpty ? _httpsUrl(_string(data['thumbUri'])) : cover,
      tocUrl: ref.bookUrl,
      status: complete ? '已完结' : '连载中',
      isComplete: complete,
      chapterCount: 0,
      wordCount: _int(data['wordNumber']),
      updateTime: _epoch(_int(data['lastPublishTime'])),
    );
  }

  static List<String> _fanqieCategoryNames(
    Object? raw,
    Map<int, String> fontMap,
  ) {
    final result = <String>[];
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      for (final value in _list(decoded)) {
        final name = _decodeFanqieText(_string(_map(value)?['Name']), fontMap);
        if (name.isNotEmpty) result.add(name);
      }
    } on Object {
      // 接口偶发没有 categoryV2 时由调用方退回 category 字段。
    }
    return result;
  }

  static String _httpsUrl(String value) =>
      value.startsWith('http://') ? 'https://${value.substring(7)}' : value;

  static Future<List<OfficialChapter>> _qidianChapters(
    BookSourceRef ref,
  ) async {
    final bookId = _idFromUrl(
      ref.tocUrl ?? ref.bookUrl,
      RegExp(r'/book/(\d+)'),
    );
    final tocText = ref.tocUrl?.trim() ?? '';
    final tocUrl = Uri.tryParse(tocText);
    Future<List<OfficialChapter>?> mobileCatalog() async {
      final uri = tocUrl ?? Uri.parse(ref.bookUrl);
      try {
        final html = await _getText(
          uri,
          headers: const {
            'Cookie': _qidianCookie,
            'Referer': 'https://m.qidian.com/',
          },
        );
        final chapters = html.length > 64 * 1024
            ? await compute(_parseQidianCatalog, html)
            : _parseQidianCatalog(html);
        return chapters.isEmpty ? null : chapters;
      } on Object {
        return null;
      }
    }

    // 移动目录页是静态 SSR，HTTP 即可拿到完整章节，且不必在进入详情时
    // 初始化 Android 无头 WebView（其创建会占用 UI 线程）。WebView 仅作为
    // 移动页被反爬拦截时的兜底。
    // 书籍页也可能带几章“最新章节”，只有 /catalog/ 才是完整目录。
    if (tocUrl != null && tocUrl.path.contains('/catalog')) {
      final chapters = await mobileCatalog();
      if (chapters != null) return chapters;
    }
    if (bookId.isNotEmpty) {
      try {
        final rows = await QidianSearchWebView.instance.fetchChapterCatalog(
          bookId,
        );
        if (rows != null && rows.isNotEmpty) {
          final chapters = <OfficialChapter>[];
          final seen = <String>{};
          for (final row in rows) {
            final title = _string(row['t']);
            final url = _string(row['h']);
            if (title.isEmpty || url.isEmpty || !seen.add(url)) continue;
            chapters.add(OfficialChapter(title: title, url: url));
          }
          if (chapters.isNotEmpty) return chapters;
        }
      } on Object {
        // 无头目录同样失败时按空目录处理。
      }
    }
    final chapters = await mobileCatalog();
    if (chapters != null) return chapters;
    throw const FormatException('起点目录为空');
  }

  static Future<List<OfficialChapter>> _fanqieChapters(
    BookSourceRef ref,
  ) async {
    final bookId = _fanqieBookId(ref.tocUrl ?? ref.bookUrl);
    if (bookId.isNotEmpty) {
      try {
        final json = await _getJson(
          Uri.https('fanqienovel.com', '/api/reader/directory/detail', {
            'bookId': bookId,
          }),
          headers: _fanqieHeaders,
        );
        if ((_int(json['code']) ?? -1) == 0) {
          final data = _map(json['data']);
          final chapters = _fanqieChaptersFromApi(data);
          if (chapters.isNotEmpty) return chapters;
        }
      } on Object {
        // 详情/目录接口不可用时保留原来的 HTML 解析。
      }
    }
    final html = await _getText(
      Uri.parse(ref.tocUrl ?? ref.bookUrl),
      headers: _fanqieHeaders,
    );
    final page = _initialPage(html);
    final fontMap = await _fanqieFontMap();
    final chapters = <OfficialChapter>[];
    for (final volume in _list(page['chapterListWithVolume'])) {
      for (final value in _list(volume)) {
        final item = _map(value);
        if (item == null) continue;
        final itemId = _string(item['itemId']);
        final title = _decodeFanqieText(_string(item['title']), fontMap);
        if (itemId.isEmpty || title.isEmpty) continue;
        chapters.add(
          OfficialChapter(
            title: title,
            url: 'https://fanqienovel.com/reader/$itemId',
          ),
        );
      }
    }
    if (chapters.isEmpty) throw const FormatException('番茄目录为空');
    return chapters;
  }

  static List<OfficialChapter> _fanqieChaptersFromApi(
    Map<String, dynamic>? data,
  ) {
    final chapters = <OfficialChapter>[];
    for (final volume in _list(data?['chapterListWithVolume'])) {
      for (final value in _list(volume)) {
        final item = _map(value);
        if (item == null) continue;
        final itemId = _string(item['itemId']);
        final title = _string(item['title']);
        if (itemId.isEmpty || title.isEmpty) continue;
        chapters.add(
          OfficialChapter(
            title: title,
            url: 'https://fanqienovel.com/reader/$itemId',
          ),
        );
      }
    }
    return chapters;
  }

  static String _fanqieBookId(String url) {
    final path = RegExp(r'/(?:page|book)/(\d+)').firstMatch(url)?.group(1);
    if (path != null && path.isNotEmpty) return path;
    return RegExp(r'[?&]bookId=(\d+)').firstMatch(url)?.group(1) ?? '';
  }

  static Future<String> _qidianContent(String chapterUrl) async {
    if (chapterUrl.contains('www.qidian.com/chapter/')) {
      return await QidianSearchWebView.instance.fetchChapterContent(
            chapterUrl,
          ) ??
          '';
    }
    final html = await _getText(
      Uri.parse(chapterUrl),
      headers: const {
        'Cookie': _qidianCookie,
        'Referer': 'https://m.qidian.com/',
      },
    );
    final data = _pageContext(html);
    final info = _map(data['chapterInfo']);
    return _string(info?['content']);
  }

  static Future<String> _fanqieContent(String chapterUrl) async {
    // 优先走内嵌 Rust 核心（DH/AES 解密，纯文本更干净）；核心不可用降级 web。
    final core = await _fanqieCoreContent(chapterUrl);
    if (core != null) return core;
    final html = await _getText(Uri.parse(chapterUrl), headers: _fanqieHeaders);
    final match = RegExp(
      r'<div class="muye-reader-content noselect">([\s\S]*?)</div></div>',
    ).firstMatch(html);
    final body = match?.group(1) ?? '';
    if (body.isEmpty) return body;
    // 番茄阅读页正文同样使用私用区字体编码，不解码会显示为方框。
    final fontMap = await _fanqieFontMap();
    return _decodeFanqieText(body, fontMap);
  }

  static const _fanqieHeaders = {
    'User-Agent': _desktopUa,
    'Referer': 'https://fanqienovel.com/',
  };

  static Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final text = await _getText(uri, headers: headers);
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('官方接口返回格式异常');
    return decoded.map((key, value) => MapEntry('$key', value));
  }

  static Future<String> _getText(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final bytes = await _getBytes(uri, headers: headers);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<Uint8List> _getBytes(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, _mobileUa);
      headers?.forEach((key, value) => request.headers.set(key, value));
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('官方接口 HTTP ${response.statusCode}', uri: uri);
      }
      return Uint8List.fromList(bytes);
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic> _pageContext(String html) {
    final match = RegExp(
      r'<script[^>]*\bid="vite-plugin-ssr_pageContext"[^>]*>([\s\S]*?)</script>',
    ).firstMatch(html);
    if (match == null) throw const FormatException('官方详情页结构已变化');
    final root = jsonDecode(match.group(1)!);
    final pageContext = _map(_map(_map(root)?['pageContext'])?['pageProps']);
    final data = _map(pageContext?['pageData']);
    if (data == null) throw const FormatException('官方详情页缺少数据');
    return data;
  }

  static Map<String, dynamic> _initialPage(String html) {
    final match = RegExp(
      r'window\.__INITIAL_STATE__=(\{[\s\S]*?\});',
    ).firstMatch(html);
    if (match == null) throw const FormatException('番茄详情页结构已变化');
    final page = _map(_map(jsonDecode(match.group(1)!))?['page']);
    if (page == null) throw const FormatException('番茄详情页缺少数据');
    return page;
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry('$key', item));
  }

  static List<Object?> _list(Object? value) =>
      value is List ? value.cast<Object?>() : const [];

  static String _string(Object? value) => value == null ? '' : '$value'.trim();

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static bool _truthy(Object? value) {
    if (value is bool) return value;
    if (value is num) return value.toInt() != 0;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  static String _plainText(String value) {
    if (value.isEmpty || !value.contains('<')) return value;
    final withBreaks = value.replaceAll(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      '\n',
    );
    var text = withBreaks.replaceAll(RegExp(r'<[^>]+>'), '');
    const entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&#x27;': "'",
    };
    for (final entry in entities.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String? _epoch(int? value) {
    if (value == null || value <= 0) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(value * 1000);
    String two(int part) => part.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static int _stableId(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 0x50000000 | (hash & 0x0fffffff);
  }
}

/// 大目录页的 DOM 解析放到后台 isolate，避免首次进入详情时阻塞 UI 线程。
List<OfficialChapter> _parseQidianCatalog(String html) {
  final document = html_parser.parse(html);
  final chapters = <OfficialChapter>[];
  final seen = <String>{};
  for (final anchor in document.querySelectorAll('a[data-cid]')) {
    // 目录页顶部还有一张带 h3 的“最新章节”卡片，它复用同一章节地址，
    // 但不是目录项；只收 h2 章节行。
    final title = anchor.querySelector('h2')?.text.trim() ?? '';
    if (title.isEmpty) continue;
    final href = anchor.attributes['href']?.trim() ?? '';
    final url = href.startsWith('//') ? 'https:$href' : href;
    if (url.isEmpty) continue;
    final cid = anchor.attributes['data-cid']?.trim() ?? '';
    if (cid.isEmpty || !seen.add(cid)) continue;
    chapters.add(OfficialChapter(title: title, url: url));
  }
  return chapters;
}
