import '../reader_paragraph_review.dart';
import 'book_source_transport.dart';

/// 段评抓取服务（Dart 侧桥）。
///
/// 负责：调用 [BookSourceTransport.review] → 把返回的原始映射映射为
/// [ParagraphReview] → 写入 [ChapterReviewCache]。真正的规则执行（`ruleReview`）
/// 在 Android 原生引擎完成；native 未实现或失败时 [BookSourceTransport.review]
/// 返回空，本服务据此不写缓存并返回 null。
class ParagraphReviewService {
  ParagraphReviewService({BookSourceTransport? transport})
    : transport = transport ?? const BookSourceTransport();

  final BookSourceTransport transport;

  Future<ChapterReviewData?> fetch({
    required int bookId,
    required int chapterId,
    required String sourceKey,
    required String bookUrl,
    required String chapterUrl,
    required Map<String, Object?> rule,
  }) async {
    final rows = await transport.review(
      sourceKey: sourceKey,
      bookUrl: bookUrl,
      chapterUrl: chapterUrl,
      rule: rule,
    );
    if (rows.isEmpty) return null;
    final items = <ParagraphReview>[
      for (final row in rows)
        ParagraphReview(
          avatarUrl: _str(row['avatarUrl'] ?? row['avatar']),
          content: _str(row['content']),
          postTime: _str(row['postTime']),
          quoteUrl: _str(row['quoteUrl']),
          paraIndex: _int(row['paraIndex']),
          paraOffset: _int(row['paraOffset']),
        ),
    ];
    final data = ChapterReviewData(
      chapterId: chapterId,
      reviewUrl: _str(rows.first['reviewUrl']),
      items: items,
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
    );
    ChapterReviewCache.shared.put(bookId, data);
    return data;
  }

  static String _str(Object? value) => value is String ? value.trim() : '';

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
