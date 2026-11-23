import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../reader_paragraph_review.dart';
import '../services/fanqie_core_service.dart';
import '../services/fanqie_core_source.dart';
import 'inline_review.dart';

/// 番茄官方段评服务。
///
/// 先按章节拉取每段评论总数，再按需拉取指定段落的首屏评论。官方段评索引
/// 与正文 `<p>` 段落一一对应；接口失败时返回 null，不影响正文阅读。
class FanqieReviewService {
  FanqieReviewService({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  static const _host = 'fanqienovel.com';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120 Safari/537.36';
  static const _maxCommentParagraphs = 8;
  static const _commentWorkers = 3;
  static const _timeout = Duration(seconds: 12);

  Future<ChapterReviewData?> fetchInline(InlineReview target, int chapterId) async {
    final client = _clientFactory()..connectionTimeout = _timeout;
    try {
      final items = await _firstComments(client, target.book, target.chapter, target.version, target.paragraph);
      if (items == null) return null;
      return ChapterReviewData(chapterId: chapterId, reviewUrl: '', items: items,
        paragraphCounts: {if (target.count != null) target.paragraph: target.count!});
    } finally {
      client.close(force: true);
    }
  }

  /// 拉取一章的段评。
  ///
  /// [paragraphs] 必须是阅读器当前实际展示的段落；[focusPara] 指定时只拉该
  /// 段评论。自动加载可传 `loadComments: false`，只更新气泡计数。
  Future<ChapterReviewData?> fetch({
    required int bookId,
    required int chapterId,
    required String bookUrl,
    required String chapterUrl,
    required List<String> paragraphs,
    int? focusPara,
    bool loadComments = true,
  }) async {
    if (paragraphs.isEmpty) return null;
    final fqBookId = _bookIdFromUrl(bookUrl);
    final fqChapterId = _chapterIdFromUrl(chapterUrl);
    if (fqBookId.isEmpty || fqChapterId.isEmpty) return null;

    // 核心优先（内嵌 Rust 官方 App 协议）；不可用/无数据时降级到下面的 web 逻辑。
    final coreData = await _tryCoreReview(
      bookId: bookId,
      chapterId: chapterId,
      chapterUrl: chapterUrl,
      fqBookId: fqBookId,
      fqChapterId: fqChapterId,
      paragraphs: paragraphs,
      focusPara: focusPara,
      loadComments: loadComments,
    );
    if (coreData != null) return coreData;

    final existing = ChapterReviewCache.shared.lookup(bookId, chapterId);
    final client = _clientFactory()..connectionTimeout = _timeout;
    try {
      final stats = await _stats(client, fqBookId, fqChapterId);
      var counts = existing?.paragraphCounts ?? const <int, int>{};
      var statsLoaded = false;
      if (stats != null && stats.supported) {
        counts = _countsInRange(stats.counts, paragraphs.length);
        statsLoaded = true;
      }
      final version = stats?.version ?? '1';

      final merged = <ParagraphReview>[...?existing?.items];
      final fetchedParagraphs = <int>{};
      var commentsLoaded = false;
      if (loadComments) {
        final targets = _commentTargets(
          counts,
          focusPara: focusPara,
          paragraphCount: paragraphs.length,
        );
        if (targets.isNotEmpty) {
          final comments = await _loadComments(
            client,
            fqBookId,
            fqChapterId,
            version,
            targets,
          );
          for (final entry in comments.entries) {
            merged.removeWhere((item) => item.paraIndex == entry.key);
            merged.addAll(entry.value);
            fetchedParagraphs.add(entry.key);
            commentsLoaded = true;
          }
        }
      }

      if (!statsLoaded && !commentsLoaded && existing == null) return null;

      // 自动计数与面板评论可能并发；写缓存前合并期间新增的评论，避免互相覆盖。
      final current = ChapterReviewCache.shared.lookup(bookId, chapterId);
      if (current != null) {
        if (!statsLoaded) counts = current.paragraphCounts;
        for (final item in current.items) {
          final index = item.paraIndex;
          if (index == null || fetchedParagraphs.contains(index)) continue;
          merged.removeWhere((existing) => existing.paraIndex == index);
          merged.addAll(
            current.items.where((existing) => existing.paraIndex == index),
          );
        }
      }

      final data = ChapterReviewData(
        chapterId: chapterId,
        reviewUrl: chapterUrl,
        items: List.unmodifiable(merged),
        paragraphCounts: Map.unmodifiable(counts),
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
      );
      ChapterReviewCache.shared.put(bookId, data);
      return data;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 核心段评：成功则返回完整 [ChapterReviewData]；核心关闭/无数据/异常返回 null。
  Future<ChapterReviewData?> _tryCoreReview({
    required int bookId,
    required int chapterId,
    required String chapterUrl,
    required String fqBookId,
    required String fqChapterId,
    required List<String> paragraphs,
    int? focusPara,
    bool loadComments = true,
  }) async {
    if (!FanqieCoreService.enabled) return null;
    try {
      final src = FanqieCoreSource.shared();

      // 1) 每段 idea 计数（附带 item_version）。
      final ideasPayload = await src.chapterIdeas(fqChapterId);
      final ideas = _map(ideasPayload['data']);
      if (ideas == null) return null;
      final buckets = ideas['data'];
      final version = _string(ideas['item_version']);
      var counts = <int, int>{};
      if (buckets is Map) {
        for (final entry in buckets.entries) {
          final idx = int.tryParse('${entry.key}');
          final bucket = _map(entry.value);
          final count = _int(bucket?['count']);
          if (idx != null && idx >= 0 && count != null && count >= 0) {
            counts[idx] = count;
          }
        }
      }
      counts = _countsInRange(counts, paragraphs.length);

      // 2) 命中段落的首屏评论正文。
      final items = <ParagraphReview>[];
      if (loadComments) {
        final targets = _commentTargets(
          counts,
          focusPara: focusPara,
          paragraphCount: paragraphs.length,
        );
        for (final para in targets) {
          try {
            final page = await src.paragraphComments(
              fqBookId,
              fqChapterId,
              itemVersion: version,
              paraIndex: para,
              count: 20,
            );
            items.addAll(_coreComments(page, para));
          } on Object {
            // 单段失败不影响整章，继续其它段。
          }
        }
      }

      // 核心没给出任何计数与正文：交给 web 兜底（可能 web 段评通道更全）。
      if (counts.isEmpty && items.isEmpty) return null;

      final data = ChapterReviewData(
        chapterId: chapterId,
        reviewUrl: chapterUrl,
        items: List.unmodifiable(items),
        paragraphCounts: Map.unmodifiable(counts),
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
      );
      ChapterReviewCache.shared.put(bookId, data);
      return data;
    } on Object {
      return null;
    }
  }

  /// 把核心 `comment/list` 返回体（`data.data_list[].comment`）映射为段评条目。
  List<ParagraphReview> _coreComments(Map<String, dynamic> page, int paraIndex) {
    final data = _map(page['data']);
    if (data == null) return const [];
    final list = data['data_list'];
    if (list is! List) return const [];
    final out = <ParagraphReview>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final comment = _map(entry['comment']);
      if (comment == null) continue;
      // 有些返回体带 comment_pos，用于跨段锚定；只保留落在本段的。
      final pos = _map(comment['comment_pos']);
      if (pos != null) {
        final start = _int(pos['start_para_index']);
        final end = _int(pos['end_para_index']);
        if ((start != null && start != paraIndex) ||
            (end != null && end != paraIndex)) {
          continue;
        }
      }
      final common = _map(comment['common']);
      if (common == null) continue;
      final contentMap = _map(common['content']);
      final text = _string(contentMap?['text']);
      if (text.isEmpty) continue;
      final user = _map(common['user_info']);
      final base = _map(user?['base_info']);
      var avatar = _string(base?['user_avatar']);
      if (avatar.startsWith('http://')) {
        avatar = 'https://${avatar.substring(7)}';
      }
      out.add(
        ParagraphReview(
          avatarUrl: avatar,
          authorName: _string(base?['user_name']),
          content: text,
          postTime: _formatTime(_int(common['create_timestamp'])),
          paraIndex: paraIndex,
        ),
      );
    }
    return out;
  }

  Map<int, int> _countsInRange(Map<int, int> counts, int paragraphCount) {
    return {
      for (final entry in counts.entries)
        if (entry.key >= 0 && entry.key < paragraphCount && entry.value > 0)
          entry.key: entry.value,
    };
  }

  List<int> _commentTargets(
    Map<int, int> counts, {
    int? focusPara,
    required int paragraphCount,
  }) {
    if (focusPara != null) {
      return focusPara >= 0 && focusPara < paragraphCount
          ? [focusPara]
          : const [];
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final entry in ranked.take(_maxCommentParagraphs)) entry.key];
  }

  Future<Map<int, List<ParagraphReview>>> _loadComments(
    HttpClient client,
    String bookId,
    String chapterId,
    String version,
    List<int> targets,
  ) async {
    final results = <int, List<ParagraphReview>>{};
    var next = 0;
    Future<void> worker() async {
      while (next < targets.length) {
        final paraIndex = targets[next++];
        final items = await _firstComments(
          client,
          bookId,
          chapterId,
          version,
          paraIndex,
        );
        if (items != null) results[paraIndex] = items;
      }
    }

    final workers = math.min(_commentWorkers, targets.length);
    await Future.wait([for (var index = 0; index < workers; index++) worker()]);
    return results;
  }

  Future<_FanqieReviewStats?> _stats(
    HttpClient client,
    String bookId,
    String chapterId,
  ) async {
    final uri = Uri.https(_host, '/reading/ugc/idea/list/v', {
      'aid': '1967',
      'book_id': bookId,
      'item_id': chapterId,
      'item_version': '1',
    });
    final root = await _requestJson(client, uri);
    if (root == null || (_int(root['code']) ?? -1) != 0) return null;
    final data = _map(root['data']);
    if (data == null) return null;
    final version = _string(data['newest_item_version']);
    final ideaData = _map(data['idea_data']);
    // idea_data 为 null 表示官方未开启段评，不能把「不支持」缓存成空结果。
    if (ideaData == null) {
      return _FanqieReviewStats(
        counts: const {},
        version: version.isEmpty ? '1' : version,
        supported: false,
      );
    }
    final counts = <int, int>{};
    for (final entry in ideaData.entries) {
      final index = int.tryParse(entry.key);
      final count = _int(_map(entry.value)?['idea_count']);
      if (index != null && index >= 0 && count != null && count >= 0) {
        counts[index] = count;
      }
    }
    return _FanqieReviewStats(
      counts: counts,
      version: version.isEmpty ? '1' : version,
      supported: true,
    );
  }

  Future<List<ParagraphReview>?> _firstComments(
    HttpClient client,
    String bookId,
    String chapterId,
    String version,
    int paraIndex,
  ) async {
    final uri = Uri.https(_host, '/reading/ugc/idea/comment_list/v', {
      'aid': '1967',
      'book_id': bookId,
      'item_id': chapterId,
      'para_index': '$paraIndex',
      'count': '20',
      'offset': '0',
      'query_type': '0',
      'sort': '1',
      'item_version': version,
    });
    final root = await _requestJson(client, uri);
    if (root == null || (_int(root['code']) ?? -1) != 0) return null;
    final data = _map(root['data']);
    if (data == null) return null;
    final rows = data['comments'];
    if (rows is! List) {
      return _truthy(data['has_more']) ? null : const [];
    }

    final seen = <String>{};
    final items = <ParagraphReview>[];
    for (final value in rows) {
      final item = _map(value);
      if (item == null) continue;
      final pos = _map(item['comment_pos']);
      final start = _int(pos?['start_para_index']);
      final end = _int(pos?['end_para_index']);
      if ((start != null && start != paraIndex) ||
          (end != null && end != paraIndex)) {
        continue;
      }
      final content = _string(item['text']);
      // 图片评论没有正文，当前模型无法展示，先跳过。
      if (content.isEmpty) continue;
      final user = _map(item['user_info']);
      final id = _string(item['comment_id']);
      final key = id.isNotEmpty
          ? id
          : '${_string(user?['user_name'])}:$content';
      if (!seen.add(key)) continue;
      var avatar = _string(user?['user_avatar']);
      if (avatar.startsWith('http://')) {
        avatar = 'https://${avatar.substring(7)}';
      }
      items.add(
        ParagraphReview(
          avatarUrl: avatar,
          authorName: _string(user?['user_name']),
          content: content,
          postTime: _formatTime(_int(item['create_timestamp'])),
          paraIndex: paraIndex,
        ),
      );
    }
    return items;
  }

  static String _bookIdFromUrl(String url) =>
      RegExp(r'/page/(\d+)').firstMatch(url)?.group(1) ?? '';

  static String _chapterIdFromUrl(String url) =>
      RegExp(r'/reader/(\d+)').firstMatch(url)?.group(1) ?? '';

  static String _formatTime(int? epoch) {
    if (epoch == null || epoch <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final time = '${two(date.hour)}:${two(date.minute)}';
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return '今天 $time';
    }
    if (date.year == now.year) {
      return '${two(date.month)}-${two(date.day)} $time';
    }
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static Future<Map<String, Object?>?> _requestJson(
    HttpClient client,
    Uri uri,
  ) async {
    // 番茄偶发在连续请求时断开 TLS 握手，重试一次即可恢复。
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _requestJsonOnce(client, uri);
      } on TimeoutException {
        return null;
      } on Object {
        if (attempt > 0) return null;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    return null;
  }

  static Future<Map<String, Object?>?> _requestJsonOnce(
    HttpClient client,
    Uri uri,
  ) async {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    request.headers.set(HttpHeaders.refererHeader, 'https://$_host/');
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/plain, */*',
    );
    final response = await request.close().timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      return null;
    }
    final text = await utf8.decoder.bind(response).join().timeout(_timeout);
    final decoded = jsonDecode(text);
    if (decoded is! Map) return null;
    return decoded.map((key, value) => MapEntry('$key', value));
  }

  static Map<String, Object?>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry('$key', item));
  }

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
}

class _FanqieReviewStats {
  const _FanqieReviewStats({
    required this.counts,
    required this.version,
    required this.supported,
  });

  final Map<int, int> counts;
  final String version;
  final bool supported;
}
