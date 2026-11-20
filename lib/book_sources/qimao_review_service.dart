import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../reader_paragraph_review.dart';

/// 七猫官方段评服务。
///
/// 七猫 App 的段评接口需要按固定规则签名：先用章节正文 MD5 拉取整章气泡
/// （每段评论总数），再按需拉取指定段落的首屏评论。接口失败时一律返回
/// null，不能影响正文阅读。
class QimaoReviewService {
  QimaoReviewService({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  static const _secret = String.fromEnvironment('QIMAO_REVIEW_SECRET');
  static const _appVersion = '80400';
  static const _applicationId = 'com.****.reader';
  static const _channel = 'unknown';
  static const _commentsBase = 'https://api-cmnt.wtzw.com';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  static const _maxCommentParagraphs = 8;
  static const _commentWorkers = 3;
  static const _timeout = Duration(seconds: 12);

  static final _paragraphIdPattern = RegExp(r'^[0-9a-f]{8}$');
  static final _htmlPattern = RegExp(
    r'</?(?:p|div|body|img|h[1-6])\b',
    caseSensitive: false,
  );

  /// 拉取一章的段评。
  ///
  /// [paragraphs] 必须是阅读器当前实际展示的段落；[focusPara] 指定时只拉该
  /// 段评论。默认按评论数取前几段拉首屏评论，自动加载时可传
  /// `loadComments: false`，只更新气泡计数。
  Future<ChapterReviewData?> fetch({
    required int bookId,
    required int chapterId,
    required String bookUrl,
    required String chapterUrl,
    required List<String> paragraphs,
    int? focusPara,
    bool loadComments = true,
  }) async {
    if (_secret.isEmpty) return null;
    final qimaoBookId = _bookIdFromUrl(bookUrl);
    final qimaoChapterId = _chapterIdFromUrl(chapterUrl);
    if (qimaoBookId.isEmpty || qimaoChapterId.isEmpty) return null;

    final existing = ChapterReviewCache.shared.lookup(bookId, chapterId);
    final paragraphIds = _paragraphIds(paragraphs);
    final client = _clientFactory()..connectionTimeout = _timeout;
    try {
      final chapterMd5 = await _chapterMd5(client, qimaoBookId, qimaoChapterId);
      var counts = existing?.paragraphCounts ?? const <int, int>{};
      var bubblesLoaded = false;
      if (chapterMd5 != null) {
        final bubbles = await _bubbleCounts(
          client,
          qimaoBookId,
          qimaoChapterId,
          chapterMd5,
        );
        if (bubbles != null) {
          final mapped = _countsForParagraphs(bubbles, paragraphIds);
          // 气泡非空却一个都没映射上，通常是替换规则改了段落文本；
          // 此时不缓存空结果，避免后续章节重载时永久丢失气泡。
          if (bubbles.isEmpty || mapped.isNotEmpty) {
            counts = mapped;
            bubblesLoaded = true;
          }
        }
      }

      final merged = <ParagraphReview>[...?existing?.items];
      final fetchedParagraphs = <int>{};
      var commentsLoaded = false;
      if (loadComments) {
        final targets = _commentTargets(
          counts,
          paragraphIds,
          focusPara: focusPara,
        );
        if (targets.isNotEmpty) {
          final comments = await _loadComments(
            client,
            qimaoBookId,
            qimaoChapterId,
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

      // 气泡和评论都没有成功，且没有旧缓存时视为失败，避免写入空结果。
      if (!bubblesLoaded && !commentsLoaded && existing == null) return null;

      // 自动计数与面板评论可能并发；写缓存前合并期间新增的评论，避免互相覆盖。
      final current = ChapterReviewCache.shared.lookup(bookId, chapterId);
      if (current != null) {
        if (!bubblesLoaded) counts = current.paragraphCounts;
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

  List<MapEntry<int, String>> _commentTargets(
    Map<int, int> counts,
    Map<int, String> paragraphIds, {
    int? focusPara,
  }) {
    if (focusPara != null) {
      final paragraphId = paragraphIds[focusPara];
      return paragraphId == null
          ? const []
          : [MapEntry(focusPara, paragraphId)];
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final targets = <MapEntry<int, String>>[];
    for (final entry in ranked.take(_maxCommentParagraphs)) {
      final paragraphId = paragraphIds[entry.key];
      if (paragraphId != null) targets.add(MapEntry(entry.key, paragraphId));
    }
    return targets;
  }

  Future<Map<int, List<ParagraphReview>>> _loadComments(
    HttpClient client,
    String bookId,
    String chapterId,
    List<MapEntry<int, String>> targets,
  ) async {
    final results = <int, List<ParagraphReview>>{};
    var next = 0;
    Future<void> worker() async {
      while (next < targets.length) {
        final target = targets[next++];
        final items = await _firstComments(
          client,
          bookId,
          chapterId,
          target.key,
          target.value,
        );
        if (items != null) results[target.key] = items;
      }
    }

    final workers = math.min(_commentWorkers, targets.length);
    await Future.wait([for (var index = 0; index < workers; index++) worker()]);
    return results;
  }

  Future<String?> _chapterMd5(
    HttpClient client,
    String bookId,
    String chapterId,
  ) async {
    final params = <String, String>{'id': bookId, 'chapterId': chapterId};
    params['sign'] = _sign(params);
    final data = await _requestJson(
      client,
      Uri.https('api-ks.wtzw.com', '/api/v1/chapter/content', params),
    );
    final value = _string(data?['content_md5']);
    return value.isEmpty ? null : value;
  }

  Future<Map<String, int>?> _bubbleCounts(
    HttpClient client,
    String bookId,
    String chapterId,
    String chapterMd5,
  ) async {
    final params = <String, String>{
      'book_id': bookId,
      'chapters': jsonEncode([
        {'chapter_id': chapterId, 'chapter_md5': chapterMd5},
      ]),
    };
    params['sign'] = _sign(params);
    final data = await _requestJson(
      client,
      Uri.parse('$_commentsBase/api/v1/paragraph/bubbles'),
      form: params,
    );
    for (final value in _list(data?['chapters'])) {
      final chapter = _map(value);
      if (chapter == null || _string(chapter['chapter_id']) != chapterId) {
        continue;
      }
      final counts = <String, int>{};
      for (final value in _list(chapter['bubbles'])) {
        final bubble = _map(value);
        final paragraphId = _string(bubble?['p']).toLowerCase();
        final count = _int(bubble?['c']) ?? 0;
        if (_paragraphIdPattern.hasMatch(paragraphId) && count > 0) {
          counts[paragraphId] = count;
        }
      }
      return counts;
    }
    return null;
  }

  Future<List<ParagraphReview>?> _firstComments(
    HttpClient client,
    String bookId,
    String chapterId,
    int paraIndex,
    String paragraphId,
  ) async {
    final params = <String, String>{
      'book_id': bookId,
      'chapter_id': chapterId,
      'paragraph_id': paragraphId,
      'hot': '1',
      'check_cmt_id': '',
      'exposed_ids': '',
      'need_common': '1',
    };
    params['sign'] = _sign(params);
    final data = await _requestJson(
      client,
      Uri.parse('$_commentsBase/api/v2/paragraph/first'),
      form: params,
    );
    if (data == null) return null;
    final hotZone = _map(data['hot_zone']);
    final timeZone = _map(data['time_zone']);
    if (hotZone == null && timeZone == null) return null;

    final seen = <String>{};
    final items = <ParagraphReview>[];
    for (final value in [
      ..._list(hotZone?['comment_list']),
      ..._list(timeZone?['comment_list']),
    ]) {
      final item = _map(value);
      if (item == null) continue;
      final content = _string(item['content']);
      if (content.isEmpty) continue;
      final user = _map(item['user_info']);
      final id = _string(item['comment_id']);
      final key = id.isNotEmpty
          ? id
          : '${_string(user?['uid'])}:${_string(user?['nickname'])}:$content';
      if (!seen.add(key)) continue;
      items.add(
        ParagraphReview(
          avatarUrl: _string(user?['avatar']),
          authorName: _string(user?['nickname']),
          content: content,
          postTime: _string(item['comment_time']),
          paraIndex: paraIndex,
        ),
      );
    }
    return items;
  }

  Map<int, int> _countsForParagraphs(
    Map<String, int> bubbles,
    Map<int, String> paragraphIds,
  ) {
    final counts = <int, int>{};
    final used = <String>{};
    for (final entry in paragraphIds.entries) {
      final paragraphId = entry.value;
      if (!used.add(paragraphId)) continue;
      final count = bubbles[paragraphId];
      if (count != null && count > 0) counts[entry.key] = count;
    }
    return counts;
  }

  Map<int, String> _paragraphIds(List<String> paragraphs) {
    final ids = <int, String>{};
    for (var index = 0; index < paragraphs.length; index++) {
      final text = paragraphs[index];
      final trimmed = text.trim();
      if (trimmed.isEmpty || trimmed == '[插图]' || _htmlPattern.hasMatch(text)) {
        continue;
      }
      ids[index] = _paragraphId(text);
    }
    return ids;
  }

  static String _paragraphId(String text) =>
      md5.convert(utf8.encode(text)).toString().substring(0, 8);

  static String _bookIdFromUrl(String url) =>
      RegExp(r'/shuku/(\d+)').firstMatch(url)?.group(1) ?? '';

  static String _chapterIdFromUrl(String url) =>
      RegExp(r'/shuku/\d+-(\d+)').firstMatch(url)?.group(1) ??
      RegExp(
        r'[?&](?:chapterId|chapter_id|id)=(\d+)',
      ).firstMatch(url)?.group(1) ??
      '';

  static String _sign(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in keys) {
      buffer.write('$key=${params[key]}');
    }
    return md5.convert(utf8.encode('${buffer.toString()}$_secret')).toString();
  }

  static Map<String, String> _signedHeaders() {
    final headers = <String, String>{
      'AUTHORIZATION': '',
      'app-version': _appVersion,
      'application-id': _applicationId,
      'channel': _channel,
      'net-env': '1',
      'platform': 'android',
      'qm-params': '',
    };
    headers['sign'] = _sign(headers);
    return headers;
  }

  static Future<Map<String, Object?>?> _requestJson(
    HttpClient client,
    Uri uri, {
    Map<String, String>? form,
  }) async {
    try {
      final request = form == null
          ? await client.getUrl(uri)
          : await client.postUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      // 七猫验签要求空值头（AUTHORIZATION、qm-params）也一并发送。
      for (final entry in _signedHeaders().entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (form != null) {
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/x-www-form-urlencoded',
        );
        request.write(_encodeForm(form));
      }
      final response = await request.close().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }
      final text = await utf8.decoder.bind(response).join().timeout(_timeout);
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final root = decoded.map((key, value) => MapEntry('$key', value));
      if (root['errors'] != null) return null;
      final data = root['data'];
      return data is Map
          ? data.map((key, value) => MapEntry('$key', value))
          : null;
    } catch (_) {
      return null;
    }
  }

  static String _encodeForm(Map<String, String> form) => form.entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');

  static Map<String, Object?>? _map(Object? value) {
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
}
