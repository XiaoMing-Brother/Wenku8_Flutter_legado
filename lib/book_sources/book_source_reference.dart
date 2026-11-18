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
  });

  final String sourceKey;
  final String sourceName;
  final String bookUrl;
  final String? tocUrl;
  final String title;
  final String author;
  final String coverUrl;

  BookSourceRef copyWith({
    String? sourceKey,
    String? sourceName,
    String? bookUrl,
    String? tocUrl,
    String? title,
    String? author,
    String? coverUrl,
  }) => BookSourceRef(
    sourceKey: sourceKey ?? this.sourceKey,
    sourceName: sourceName ?? this.sourceName,
    bookUrl: bookUrl ?? this.bookUrl,
    tocUrl: tocUrl ?? this.tocUrl,
    title: title ?? this.title,
    author: author ?? this.author,
    coverUrl: coverUrl ?? this.coverUrl,
  );

  Map<String, Object?> toJson() => {
    'sourceKey': sourceKey,
    'sourceName': sourceName,
    'bookUrl': bookUrl,
    if (tocUrl != null && tocUrl!.isNotEmpty) 'tocUrl': tocUrl,
    if (title.isNotEmpty) 'title': title,
    if (author.isNotEmpty) 'author': author,
    if (coverUrl.isNotEmpty) 'coverUrl': coverUrl,
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
    );
  }
}
