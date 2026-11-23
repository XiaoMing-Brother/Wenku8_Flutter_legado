import 'dart:convert';

import 'package:flutter/material.dart';

import 'book_sources/book_source_reference.dart';
import 'book_identity.dart';
import 'catalog.dart';

const pendingBooksPreferenceKey = 'pending_books_v1';
const maxPendingBooksBytes = 2 * 1024 * 1024;

bool isPendingBook(int id) => id >= pendingBookIdStart && id < pendingBookIdEnd;

/// A book list entry that is on the shelf but still needs a source.
class PendingBook {
  const PendingBook({
    required this.id,
    required this.title,
    this.author = '',
    this.coverUrl = '',
    this.customCoverUrl = '',
    this.origin = '',
    this.originName = '',
    this.bookUrl = '',
    required this.addedAt,
  });

  final int id;
  final String title;
  final String author;
  final String coverUrl;
  final String customCoverUrl;
  final String origin;
  final String originName;
  final String bookUrl;
  final int addedAt;

  factory PendingBook.fromNovel(Novel novel, {required int addedAt}) {
    final source = novel.source;
    return PendingBook(
      id: novel.id,
      title: novel.title,
      author: novel.author,
      coverUrl: source?.coverUrl ?? novel.coverUrl ?? '',
      customCoverUrl: source?.customCoverUrl ?? '',
      origin: source?.sourceKey ?? '',
      originName: source?.sourceName ?? '',
      bookUrl: source?.bookUrl ?? '',
      addedAt: addedAt,
    );
  }

  Novel toNovel() {
    final hasCoordinates =
        origin.trim().isNotEmpty && bookUrl.trim().isNotEmpty;
    return Novel(
      id: id,
      title: title,
      author: author,
      genre: '待匹配',
      summary: '',
      colors: const [Color(0xFF202020), Color(0xFF333333)],
      coverUrl: customCoverUrl.isNotEmpty ? customCoverUrl : (coverUrl.isEmpty ? null : coverUrl),
      source: hasCoordinates
          ? BookSourceRef(
              sourceKey: origin,
              sourceName: originName,
              bookUrl: bookUrl,
              title: title,
              author: author,
              coverUrl: coverUrl,
              customCoverUrl: customCoverUrl,
            )
          : null,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (author.isNotEmpty) 'author': author,
    if (coverUrl.isNotEmpty) 'cover': coverUrl,
    if (customCoverUrl.isNotEmpty) 'customCoverUrl': customCoverUrl,
    if (origin.isNotEmpty) 'origin': origin,
    if (originName.isNotEmpty) 'originName': originName,
    if (bookUrl.isNotEmpty) 'bookUrl': bookUrl,
    'addedAt': addedAt,
  };

  static PendingBook? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = _text(value['title'], 500);
    final addedAt = value['addedAt'];
    if (id is! int || !isPendingBook(id) || title.isEmpty) return null;
    if (addedAt is! int || addedAt < 0 || addedAt > 1000000000000000) {
      return null;
    }
    return PendingBook(
      id: id,
      title: title,
      author: _text(value['author'], 500),
      coverUrl: _text(value['cover'], 4096),
      customCoverUrl: BookSourceRef.webCover(value['customCoverUrl']),
      origin: _text(value['origin'], 4096),
      originName: _text(value['originName'], 512),
      bookUrl: _text(value['bookUrl'], 4096),
      addedAt: addedAt,
    );
  }
}

int pendingBookIdFor(String title, String author) {
  var hash = 0x811c9dc5;
  final key = '${sourceSearchTitleKey(title)}\u0000${sourceAuthorName(author)}';
  for (final unit in _keyPart(key).codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return pendingBookIdStart | (hash & 0x0FFFFFFF);
}

int nextPendingBookId(int id) {
  final next = id + 1;
  return next >= pendingBookIdEnd ? pendingBookIdStart : next;
}

List<PendingBook> decodePendingBooks(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    throw const FormatException('待匹配书籍记录格式有误');
  }
  final seen = <int>{};
  final result = <PendingBook>[];
  for (final item in decoded.take(10000)) {
    final book = PendingBook.fromJson(item);
    if (book != null && seen.add(book.id)) result.add(book);
  }
  return result;
}

String encodePendingBooks(Iterable<PendingBook> books) {
  final text = jsonEncode([for (final book in books) book.toJson()]);
  if (utf8.encode(text).length > maxPendingBooksBytes) {
    throw const FormatException('书单待匹配记录超过 2 MB，请分批导入');
  }
  return text;
}

String _keyPart(String value) =>
    value.replaceAll(RegExp(r'[\s\u3000]+'), '').toLowerCase();

String _text(Object? value, int max) {
  if (value is! String) return '';
  final text = value.trim();
  return text.length <= max ? text : text.substring(0, max);
}
