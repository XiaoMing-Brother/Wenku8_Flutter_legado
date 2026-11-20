import 'dart:convert';

/// 段评（章评）规则，字段对齐 legado `ReviewRule`。
///
/// Legado 书源里该字段名为 `ruleReview`，值可能是对象，也可能是 JSON 字符串。
/// 前五项为已实现的抓取所需：`reviewUrl` 段评地址、`avatarRule` 头像、
/// `contentRule` 内容、`postTimeRule` 发布时间、`reviewQuoteUrl` 回复地址；
/// 其余为互动预留（点赞/点踩/发评/删评），暂不参与抓取。
class ReviewRule {
  const ReviewRule({
    this.reviewUrl = '',
    this.avatarRule = '',
    this.contentRule = '',
    this.postTimeRule = '',
    this.reviewQuoteUrl = '',
    this.paraIndexRule = '',
    this.voteUpUrl = '',
    this.voteDownUrl = '',
    this.postReviewUrl = '',
    this.postQuoteUrl = '',
    this.deleteUrl = '',
  });

  final String reviewUrl;
  final String avatarRule;
  final String contentRule;
  final String postTimeRule;
  final String reviewQuoteUrl;

  /// 段落号规则：从段评条目里取所属段落索引（用于「第 N 段」/气泡定位）。
  final String paraIndexRule;
  final String voteUpUrl;
  final String voteDownUrl;
  final String postReviewUrl;
  final String postQuoteUrl;
  final String deleteUrl;

  /// 是否配置了段评地址（只有配置了才可能抓取到段评）。
  bool get isConfigured => reviewUrl.trim().isNotEmpty;

  static const empty = ReviewRule();

  Map<String, Object?> toMap() => {
    'reviewUrl': reviewUrl,
    'avatarRule': avatarRule,
    'contentRule': contentRule,
    'postTimeRule': postTimeRule,
    'reviewQuoteUrl': reviewQuoteUrl,
    'paraIndexRule': paraIndexRule,
    'voteUpUrl': voteUpUrl,
    'voteDownUrl': voteDownUrl,
    'postReviewUrl': postReviewUrl,
    'postQuoteUrl': postQuoteUrl,
    'deleteUrl': deleteUrl,
  };

  /// 接受 Map 或 JSON 字符串；`null` / `"null"` / 解析失败均回落空规则。
  factory ReviewRule.fromMap(Object? value) {
    Map<String, dynamic> map;
    if (value is Map) {
      map = {for (final entry in value.entries) '${entry.key}': entry.value};
    } else if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text == 'null') return const ReviewRule();
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        return const ReviewRule();
      }
      if (decoded is! Map) return const ReviewRule();
      map = {for (final entry in decoded.entries) '${entry.key}': entry.value};
    } else {
      return const ReviewRule();
    }
    String read(String key) {
      final raw = map[key];
      return raw is String ? raw.trim() : '';
    }

    return ReviewRule(
      reviewUrl: read('reviewUrl'),
      avatarRule: read('avatarRule'),
      contentRule: read('contentRule'),
      postTimeRule: read('postTimeRule'),
      reviewQuoteUrl: read('reviewQuoteUrl'),
      paraIndexRule: read('paraIndexRule'),
      voteUpUrl: read('voteUpUrl'),
      voteDownUrl: read('voteDownUrl'),
      postReviewUrl: read('postReviewUrl'),
      postQuoteUrl: read('postQuoteUrl'),
      deleteUrl: read('deleteUrl'),
    );
  }
}
