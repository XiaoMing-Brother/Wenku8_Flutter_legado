import 'dart:convert';

class InlineReview {
  const InlineReview(
    this.book,
    this.chapter,
    this.paragraph,
    this.version,
    this.count, {
    this.webPlatform,
  });

  final String book, chapter, version;
  final int paragraph;
  final int? count;
  final String? webPlatform;

  static const prefix = '<!--fq-review:';
  static final marker = RegExp(
    r'<!--fq-review:(\d{1,24}):(\d{1,24}):(\d{1,9}):(\d{1,24}):(\d{1,9}|x)(?::(fq|qm|qd))?-->',
  );
  String encode() {
    final platform = webPlatform == null ? '' : ':$webPlatform';
    return '$prefix$book:$chapter:$paragraph:$version:${count ?? 'x'}$platform-->';
  }

  static InlineReview fromMarker(RegExpMatch match) => InlineReview(
    match[1]!,
    match[2]!,
    int.parse(match[3]!),
    match[4]!,
    int.tryParse(match[5]!),
    webPlatform: match[6],
  );

  static final _image = RegExp(
    r'''^<img\s+src=["']data:image/svg\+xml;base64,([A-Za-z0-9+/=]+),(\{.*\})["']\s*/?>$''',
    caseSensitive: false,
  );
  static final _action = RegExp(
    r'^fqOpenReviewPayload\("([A-Za-z0-9+/=]+)",\s*java\)$',
  );
  static final _webAction = RegExp(
    r"^show(Fq|Qm|Qd)Cmt\('(\d{1,24})','(\d{1,24})','(\d{1,9})',(?:'(\d{1,24})',)?'\d{1,24}'\)$",
  );
  static final _id = RegExp(r'^\d{1,24}$');
  static final _paragraph = RegExp(r'^\d{1,9}$');
  static final _label = RegExp(r'<text\b[^>]*>\s*(\d{1,9}|评)\s*</text>');

  static InlineReview? fromImage(String tag) {
    if (tag.length > 65536 || !tag.contains('data:image/svg+xml;base64,')) {
      return null;
    }
    final image = _image.firstMatch(tag);
    if (image == null) return null;
    try {
      final options = jsonDecode(image[2]!);
      if (options is! Map ||
          options['style'] != 'TEXT' ||
          options['click'] is! String) {
        return null;
      }
      final click = options['click'] as String;
      final web = _webAction.firstMatch(click);
      final action = _action.firstMatch(click);
      if (web == null && action == null) return null;
      final label = _label.firstMatch(
        utf8.decode(base64.decode(image[1]!)),
      )?[1];
      if (web != null) {
        final platform = web[1]!.toLowerCase();
        if (options['type'] != platform ||
            (platform == 'fq') != (web[5] != null)) {
          return null;
        }
        return InlineReview(
          web[2]!,
          web[3]!,
          int.parse(web[4]!),
          web[5] ?? '0',
          label == null ? null : int.tryParse(label),
          webPlatform: platform,
        );
      }
      final payload = jsonDecode(utf8.decode(base64.decode(action![1]!)));
      if (payload is! Map || payload['kind'] != 'paragraph') return null;
      final book = '${payload['bookId']}', chapter = '${payload['chapterId']}';
      final version = '${payload['version']}',
          paragraph = '${payload['paragraph']}';
      if (!_id.hasMatch(book) ||
          !_id.hasMatch(chapter) ||
          !_id.hasMatch(version) ||
          !_paragraph.hasMatch(paragraph)) {
        return null;
      }
      if (label == null) return null;
      return InlineReview(
        book,
        chapter,
        int.parse(paragraph),
        version,
        int.tryParse(label),
      );
    } on FormatException {
      return null;
    }
  }

  Uri? webUrl(String jsLib) {
    final (function, path, query) = switch (webPlatform) {
      'fq' => (
        'showFqCmt',
        '/fqdlpl.php',
        {
          'item_id': (r'${cid}', chapter),
          'book_id': (r'${bid}', book),
          'para': (r'${para}', '$paragraph'),
          'version': (r'${version}', version),
        },
      ),
      'qm' => (
        'showQmCmt',
        '/qmdlpl.php',
        {
          'book_id': (r'${bid}', book),
          'chapter_id': (r'${cid}', chapter),
          'paragraph_id': (r'${para}', '$paragraph'),
        },
      ),
      'qd' => (
        'showQdCmt',
        '/qddp.php',
        {
          'bookId': (r'${bid}', book),
          'chapterId': (r'${cid}', chapter),
          'paragraphId': (r'${para}', '$paragraph'),
        },
      ),
      _ => ('', '', const <String, (String, String)>{}),
    };
    if (function.isEmpty) return null;
    final declaration = RegExp(
      '\\bfunction\\s+$function'
      r'\s*\([^)]*\)\s*\{\s*(?:let|const|var)\s+u\s*=\s*`([^`\r\n]+)`',
    ).firstMatch(jsLib)?[1];
    if (declaration == null) return null;
    final expectedQuery = [
      for (final entry in query.entries) '${entry.key}=${entry.value.$1}',
      r'ms=${this.ms()}',
    ].join('&');
    final suffix = '$path?$expectedQuery';
    if (!declaration.endsWith(suffix)) return null;
    final origin = declaration.substring(0, declaration.length - suffix.length);
    if (!_webOrigin.hasMatch(origin)) return null;
    final uri = Uri.tryParse('$origin$path');
    if (uri == null || !uri.hasAuthority) return null;
    return uri.replace(
      queryParameters: {
        for (final entry in query.entries) entry.key: entry.value.$2,
        'ms': '6',
      },
    );
  }

  static final _webOrigin = RegExp(
    r'^https?://(?:[a-zA-Z0-9.-]+|\[[0-9a-fA-F:]+\])(?::[0-9]{1,5})?$',
  );
}
