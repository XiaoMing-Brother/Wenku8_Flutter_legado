/// External identity for a book served by a Legado-compatible book source.
///
/// The numeric [Novel.id] remains the app-wide key. Source identifiers stay
/// strings because Legado uses URLs as stable book/chapter identities.
class BookSourceRef {
  const BookSourceRef({
    required this.sourceKey,
    required this.sourceName,
    required this.bookUrl,
    this.tocUrl,
    this.title = '',
    this.author = '',
    this.coverUrl = '',
    this.customCoverUrl = '',
    this.resourceType = 0,
  });

  final String sourceKey;
  final String sourceName;
  final String bookUrl;
  final String? tocUrl;
  final String title;
  final String author;
  final String coverUrl;
  final String customCoverUrl;
  final int resourceType;
  String? get displayCover => customCoverUrl.isNotEmpty ? customCoverUrl : (coverUrl.isEmpty ? null : coverUrl);

  static String webCover(Object? value) {
    if (value is! String || value.length > 4096) return '';
    final url = Uri.tryParse(value.trim());
    if (url == null || !url.hasAuthority || url.host.isEmpty || url.userInfo.isNotEmpty ||
        (url.scheme != 'https' && url.scheme != 'http') || RegExp(r'[,，]\s*\{').hasMatch(value)) {
      return '';
    }
    return url.toString();
  }

  BookSourceRef copyWith({
    String? sourceKey,
    String? sourceName,
    String? bookUrl,
    String? tocUrl,
    String? title,
    String? author,
    String? coverUrl,
    String? customCoverUrl,
    int? resourceType,
  }) => BookSourceRef(
    sourceKey: sourceKey ?? this.sourceKey,
    sourceName: sourceName ?? this.sourceName,
    bookUrl: bookUrl ?? this.bookUrl,
    tocUrl: tocUrl ?? this.tocUrl,
    title: title ?? this.title,
    author: author ?? this.author,
    coverUrl: coverUrl ?? this.coverUrl,
    customCoverUrl: customCoverUrl ?? this.customCoverUrl,
    resourceType: resourceType ?? this.resourceType,
  );

  Map<String, Object?> toJson() => {
    'sourceKey': sourceKey,
    'sourceName': sourceName,
    'bookUrl': bookUrl,
    if (tocUrl != null && tocUrl!.isNotEmpty) 'tocUrl': tocUrl,
    if (title.isNotEmpty) 'title': title,
    if (author.isNotEmpty) 'author': author,
    if (coverUrl.isNotEmpty) 'coverUrl': coverUrl,
    if (customCoverUrl.isNotEmpty) 'customCoverUrl': customCoverUrl,
    if (resourceType != 0) 'resourceType': resourceType,
  };

  factory BookSourceRef.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('书源坐标格式无效');
    }
    final sourceKey = value['sourceKey'];
    final sourceName = value['sourceName'];
    final bookUrl = value['bookUrl'];
    final tocUrl = value['tocUrl'];
    final title = value['title'];
    final author = value['author'];
    final coverUrl = value['coverUrl'];
    if (sourceKey is! String ||
        sourceKey.trim().isEmpty ||
        sourceName is! String ||
        bookUrl is! String ||
        bookUrl.trim().isEmpty) {
      throw const FormatException('书源坐标缺少来源或书籍地址');
    }
    return BookSourceRef(
      sourceKey: sourceKey,
      sourceName: sourceName,
      bookUrl: bookUrl,
      tocUrl: tocUrl is String && tocUrl.trim().isNotEmpty ? tocUrl : null,
      title: title is String ? title : '',
      author: author is String ? author : '',
      coverUrl: coverUrl is String ? coverUrl : '',
      customCoverUrl: webCover(value['customCoverUrl']),
      resourceType: const {1, 3, 4}.contains(value['resourceType']) ? value['resourceType'] as int : 0,
    );
  }
}
