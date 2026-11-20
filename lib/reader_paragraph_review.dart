/// 段评（章评）数据结构：单条评论与一章的段评结果。
///
/// 这是给后续「抓取解析 → 气泡渲染 → 面板查看」用的数据契约，本文件只定义
/// 纯数据模型，不含网络、缓存与 UI。
class ParagraphReview {
  const ParagraphReview({
    this.avatarUrl = '',
    this.content = '',
    this.postTime = '',
    this.quoteUrl = '',
    this.paraIndex,
    this.paraOffset,
  });

  /// 发布者头像。
  final String avatarUrl;

  /// 段评正文。
  final String content;

  /// 发布时间文案（原始字符串，展示时按需处理）。
  final String postTime;

  /// 该段评的回复地址（用于后续「查看回复」）。
  final String quoteUrl;

  /// 所属段落索引（若书源能定位到段落）。
  final int? paraIndex;

  /// 段内字符偏移（若书源能定位到段落内位置）。
  final int? paraOffset;
}

/// 一章的段评抓取结果。
class ChapterReviewData {
  const ChapterReviewData({
    required this.chapterId,
    required this.reviewUrl,
    this.items = const [],
    this.fetchedAt,
  });

  final int chapterId;

  /// 实际请求的段评地址（已解析）。
  final String reviewUrl;

  final List<ParagraphReview> items;

  /// 抓取时间（毫秒），用于缓存过期判断。
  final int? fetchedAt;

  bool get isEmpty => items.isEmpty;
}

/// 段评的内存缓存：按 书 id + 章 id 保存已抓取结果，避免重复请求。
///
/// 纯 Dart，无持久化与网络；抓取成功后由上层 `put`，阅读时 `lookup`。
/// 段评抓取本身需 Android 原生引擎执行书源规则（Dart 侧 transport 不解释规则），
/// 因此本缓存独立存在，等原生抓取接好后即为唯一写入方。
class ChapterReviewCache {
  ChapterReviewCache();

  static final shared = ChapterReviewCache();

  final _data = <String, ChapterReviewData>{};

  String _key(Object bookId, int chapterId) => '$bookId#$chapterId';

  ChapterReviewData? lookup(Object bookId, int chapterId) =>
      _data[_key(bookId, chapterId)];

  void put(Object bookId, ChapterReviewData data) =>
      _data[_key(bookId, data.chapterId)] = data;

  void remove(Object bookId, int chapterId) =>
      _data.remove(_key(bookId, chapterId));

  void clearBook(Object bookId) {
    final prefix = '$bookId#';
    _data.removeWhere((key, _) => key.startsWith(prefix));
  }

  void clear() => _data.clear();

  int get length => _data.length;
}
