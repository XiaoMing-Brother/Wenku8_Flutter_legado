import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'book_sources/book_source_reference.dart';

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
  });

  final String id;
  final String title;
  final OfficialSite site;
  final String kind;
  final String? gender;
  final String? rankMold;
  final String? categoryId;

  OfficialRanking copyWith({String? categoryId}) => OfficialRanking(
    id: id,
    title: title,
    site: site,
    kind: kind,
    gender: gender,
    rankMold: rankMold,
    categoryId: categoryId ?? this.categoryId,
  );
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
  OfficialRanking(id: 'qidian-yuepiao', title: '月票榜', site: OfficialSite.qidian, kind: 'yuepiao'),
  OfficialRanking(id: 'qidian-hotsales', title: '畅销榜', site: OfficialSite.qidian, kind: 'hotsales'),
  OfficialRanking(id: 'qidian-readindex', title: '阅读榜', site: OfficialSite.qidian, kind: 'readindex'),
  OfficialRanking(id: 'qidian-newfans', title: '书友榜', site: OfficialSite.qidian, kind: 'newfans'),
  OfficialRanking(id: 'qidian-rec', title: '推荐榜', site: OfficialSite.qidian, kind: 'rec'),
  OfficialRanking(id: 'qidian-update', title: '更新榜', site: OfficialSite.qidian, kind: 'update'),
  OfficialRanking(id: 'qidian-sign', title: '签约榜', site: OfficialSite.qidian, kind: 'sign'),
  OfficialRanking(id: 'qidian-newbook', title: '新书榜', site: OfficialSite.qidian, kind: 'newbook'),
  OfficialRanking(id: 'qidian-newauthor', title: '新人榜', site: OfficialSite.qidian, kind: 'newauthor'),
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
  const OfficialChapter({
    required this.title,
    required this.url,
    this.isLocked = false,
  });

  final String title;
  final String url;
  final bool isLocked;
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

  static int idFor(OfficialBook book) => _stableId(
    'official:${book.site.name}:${book.bookId}',
  );

  static final Map<String, Uint8List> _coverCache = {};

  static Future<Map<int, String>>? _fanqieFontMapFuture;

  static Future<Map<int, String>> _fanqieFontMap() =>
      _fanqieFontMapFuture ??= _loadFanqieFontMap();

  static Future<Map<int, String>> _loadFanqieFontMap() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/book_sources/fanqie_font_map.json',
      );
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

  static Uint8List? peekCover(String url) => _coverCache[url];

  static Future<Uint8List> coverBytes(String url) async {
    final cached = _coverCache[url];
    if (cached != null) return cached;
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
    if (_coverCache.length > 160) _coverCache.remove(_coverCache.keys.first);
    _coverCache[url] = bytes;
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

  /// 返回官网原始正文 HTML；VIP/锁定章节返回占位标记，由仓库层转成可见提示。
  static Future<String> content(
    BookSourceRef ref,
    String chapterUrl,
  ) async {
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
      if ((ranking.categoryId ?? '').isNotEmpty)
        'catId': ranking.categoryId!,
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
      hasMore:
          books.length >= 20 && (total <= 0 || page * 20 < total),
      page: page,
    );
  }

  static Future<OfficialRankingPage> _qimaoRanking(
    OfficialRanking ranking,
    int page,
  ) async {
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
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
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
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
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
      final author =
          info.querySelector('.ranklist-autor a')?.text.trim() ?? '';
      final category = info.querySelector('.bkcate-icon')?.text.trim() ?? '';
      final intro = info.querySelector('.ranklist-des')?.text.trim() ?? '';
      final img =
          li.querySelector('.ranklinst-bk img') ?? li.querySelector('img');
      var cover =
          (img?.attributes['src'] ?? img?.attributes['data-src'] ?? '').trim();
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
    final updateDate =
        RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(updateRaw)?.group(0);
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

  static Future<List<OfficialChapter>> _qimaoChapters(
    BookSourceRef ref,
  ) async {
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
          isLocked: _string(item['is_vip']) == '1',
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
    for (final node in article?.querySelectorAll('p') ?? const <dom.Element>[]) {
      final text = node.text.trim();
      if (text.isNotEmpty) paragraphs.add('<p>$text</p>');
    }
    if (paragraphs.isEmpty) return '[[QIMAO_VIP]]';
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
        doc.querySelector('.view-book-info-book-title-box .bname')?.text.trim() ??
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
    final img = doc.querySelector('img.cover') ?? doc.querySelector('.cover img');
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

  static Future<List<OfficialChapter>> _shuqiChapters(
    BookSourceRef ref,
  ) async {
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
        chapters.add(
          OfficialChapter(title: title, url: url, isLocked: !isFree),
        );
      }
    }
    if (chapters.isEmpty) throw const FormatException('书旗目录为空');
    return chapters;
  }

  static Future<String> _shuqiContent(String chapterUrl) async {
    if (chapterUrl.isEmpty ||
        chapterUrl.contains('/contentcharge/') ||
        !chapterUrl.contains('/content')) {
      return '[[SHUQI_LOCKED]]';
    }
    final json = await _getJson(
      Uri.parse(chapterUrl),
      headers: _shuqiHeaders,
    );
    final state = _int(json['state']) ?? _int(json['status']);
    if (state != 200) return '[[SHUQI_LOCKED]]';
    final raw = _string(json['ChapterContent'] ?? json['chapterContent']);
    if (raw.isEmpty) return '[[SHUQI_LOCKED]]';
    final decoded = _shuqiDecodeCont(raw);
    if (decoded.trim().isEmpty) return '[[SHUQI_LOCKED]]';
    return decoded;
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
      final ok = (rune >= 65 && rune <= 90) ||
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
        final name = _decodeFanqieText(
          _string(_map(value)?['Name']),
          fontMap,
        );
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

  static Future<List<OfficialChapter>> _qidianChapters(
    BookSourceRef ref,
  ) async {
    final html = await _getText(
      Uri.parse(ref.tocUrl ?? ref.bookUrl),
      headers: const {
        'Cookie': _qidianCookie,
        'Referer': 'https://m.qidian.com/',
      },
    );
    final document = html_parser.parse(html);
    final chapters = <OfficialChapter>[];
    final seen = <String>{};
    for (final anchor in document.querySelectorAll('a[data-cid]')) {
      final cid = anchor.attributes['data-cid']?.trim() ?? '';
      if (cid.isEmpty || !seen.add(cid)) continue;
      final title = anchor.querySelector('h2')?.text.trim() ??
          anchor.text.trim();
      final href = anchor.attributes['href']?.trim() ?? '';
      final url = href.startsWith('//') ? 'https:$href' : href;
      if (title.isEmpty || url.isEmpty) continue;
      chapters.add(
        OfficialChapter(
          title: title,
          url: url,
          isLocked: anchor.outerHtml.contains('_lockIcon_'),
        ),
      );
    }
    if (chapters.isEmpty) throw const FormatException('起点目录为空');
    return chapters;
  }

  static Future<List<OfficialChapter>> _fanqieChapters(
    BookSourceRef ref,
  ) async {
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
            isLocked:
                _truthy(item['isChapterLock']) ||
                (_int(item['needPay']) ?? 0) > 0,
          ),
        );
      }
    }
    if (chapters.isEmpty) throw const FormatException('番茄目录为空');
    return chapters;
  }

  static Future<String> _qidianContent(String chapterUrl) async {
    final html = await _getText(
      Uri.parse(chapterUrl),
      headers: const {
        'Cookie': _qidianCookie,
        'Referer': 'https://m.qidian.com/',
      },
    );
    final data = _pageContext(html);
    final info = _map(data['chapterInfo']);
    if (_string(info?['vipStatus']) != '0') return '[[QIDIAN_VIP]]';
    return _string(info?['content']);
  }

  static Future<String> _fanqieContent(String chapterUrl) async {
    final html = await _getText(
      Uri.parse(chapterUrl),
      headers: _fanqieHeaders,
    );
    if (RegExp(
      r'购买|登录后阅读|本章为付费|isChapterLock[\s\S]{0,40}true',
    ).hasMatch(html)) {
      return '[[FANQIE_LOCKED]]';
    }
    final match = RegExp(
      r'<div class="muye-reader-content noselect">([\s\S]*?)</div></div>',
    ).firstMatch(html);
    return match?.group(1) ?? '';
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
      r'<script id="vite-plugin-ssr_pageContext" type="application/json">([\s\S]*?)</script>',
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
