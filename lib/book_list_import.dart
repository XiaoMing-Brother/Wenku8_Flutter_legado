import 'dart:convert';

import 'book_sources/book_source_reference.dart';

const int maxBookListBytes = 16 * 1024 * 1024;
const int maxBookListChars = maxBookListBytes;
const int maxBookListEntries = 5000;

class BookListEntry {
  const BookListEntry({
    required this.title,
    this.author = '',
    this.summary = '',
    this.bookUrl = '',
    this.origin = '',
    this.originName = '',
    this.coverUrl = '',
    this.customCoverUrl = '',
  });

  final String title;
  final String author;
  final String summary;
  final String bookUrl;
  final String origin;
  final String originName;
  final String coverUrl;
  final String customCoverUrl;
}

class BookListDocument {
  const BookListDocument({
    required this.entries,
    required this.ignored,
    required this.hasSourceCoordinates,
  });

  final List<BookListEntry> entries;
  final int ignored;
  final bool hasSourceCoordinates;
}

/// Accepts the full bookshelf array exported by Legado and the compact
/// name/author/intro array exported by legado_md3.
BookListDocument parseBookList(String input) {
  var text = input.trimLeft();
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  text = text.trim();
  if (text.isEmpty) throw const FormatException('书籍列表为空');
  if (text.length > maxBookListChars) {
    throw const FormatException('书籍列表超过 16 MB，请分批导入');
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('书籍列表不是有效的 JSON');
  }

  final List<Object?> items;
  if (decoded is List) {
    items = decoded;
  } else if (decoded is Map) {
    items = _booksFromObject(decoded);
  } else {
    throw const FormatException('书籍列表必须是 JSON 数组或包含 books 的对象');
  }

  final entries = <BookListEntry>[];
  final seen = <String>{};
  var ignored = 0;
  for (final item in items) {
    if (item is! Map) {
      ignored++;
      continue;
    }
    final title = _bounded(
      _text(item, const ['name', 'title', 'bookName', 'bookTitle']),
      500,
    );
    if (title.isEmpty) {
      ignored++;
      continue;
    }
    final author = _bounded(
      _text(item, const ['author', 'bookAuthor', 'authorName']),
      500,
    );
    final key = '${_normalize(title)}\u0000${_normalize(author)}';
    if (!seen.add(key)) {
      ignored++;
      continue;
    }
    if (entries.length >= maxBookListEntries) {
      throw const FormatException('书籍列表超过 5000 本，请分批导入');
    }
    entries.add(
      BookListEntry(
        title: title,
        author: author,
        summary: _bounded(
          _text(item, const [
            'intro',
            'summary',
            'description',
            'desc',
            'bookIntro',
          ]),
          20000,
        ),
        bookUrl: _boundedOrEmpty(
          _text(item, const ['bookUrl', 'book_url', 'url', 'bookUri']),
          4096,
        ),
        origin: _boundedOrEmpty(
          _text(item, const [
            'origin',
            'originUrl',
            'sourceUrl',
            'bookSourceUrl',
          ]),
          4096,
        ),
        originName: _bounded(
          _text(item, const ['originName', 'sourceName', 'bookSourceName']),
          500,
        ),
        coverUrl: _boundedOrEmpty(
          _text(item, const ['coverUrl', 'cover', 'imageUrl']),
          4096,
        ),
        customCoverUrl: BookSourceRef.webCover(item['customCoverUrl']),
      ),
    );
  }
  if (entries.isEmpty) throw const FormatException('没有可导入的书籍');
  return BookListDocument(
    entries: List.unmodifiable(entries),
    ignored: ignored,
    hasSourceCoordinates: entries.any((entry) => entry.bookUrl.isNotEmpty),
  );
}

List<Object?> _booksFromObject(Map<dynamic, dynamic> value) {
  for (final key in const [
    'books',
    'bookList',
    'booklist',
    'data',
    'items',
    'list',
    'result',
  ]) {
    final candidate = value[key];
    if (candidate is List) return candidate;
  }
  final title = _text(value, const ['name', 'title', 'bookName', 'bookTitle']);
  final author = _text(value, const ['author', 'bookAuthor', 'authorName']);
  final bookUrl = _text(value, const ['bookUrl', 'book_url', 'url', 'bookUri']);
  if (title.isNotEmpty && (author.isNotEmpty || bookUrl.isNotEmpty)) {
    return [value];
  }
  throw const FormatException('JSON 中没有书籍数组');
}

String _text(Map<dynamic, dynamic> value, List<String> keys) {
  for (final key in keys) {
    final item = value[key];
    final text = switch (item) {
      String() => item.trim(),
      null => '',
      _ => '$item'.trim(),
    };
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _normalize(String value) =>
    value.replaceAll(RegExp(r'[\s\u3000]+'), '').toLowerCase();

String _bounded(String value, int limit) =>
    value.length <= limit ? value : value.substring(0, limit);

String _boundedOrEmpty(String value, int limit) =>
    value.length <= limit ? value : '';
