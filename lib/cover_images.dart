import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'app_interactions.dart';
import 'catalog.dart';
import 'book_sources/book_source_images.dart';
import 'legacy_cover.dart';
import 'local_book_media.dart';
import 'official_books.dart';
import 'reader_illustrations.dart';

Future<Uint8List> novelCoverBytes(Novel book) {
  final url = book.coverUrl;
  if (url == null || url.isEmpty) {
    return Future.error(const FormatException('书籍没有封面地址'));
  }
  if (url.startsWith('wenku-local:')) return LocalBookMedia.loadCover(url);
  final source = book.source;
  if (source != null) {
    if (OfficialBookService.isOfficialKey(source.sourceKey)) {
      return OfficialBookService.coverBytes(url);
    }
    return BookSourceImages.coverBytes(source.sourceKey, url);
  }
  return LegacyCover.bytes(book.id, url: url);
}

Uint8List? peekNovelCover(Novel book) {
  final url = book.coverUrl;
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('wenku-local:')) return LocalBookMedia.peek(url);
  final source = book.source;
  if (source != null) {
    if (OfficialBookService.isOfficialKey(source.sourceKey)) {
      return OfficialBookService.peekCover(url);
    }
    return BookSourceImages.peekCover(source.sourceKey, url);
  }
  return LegacyCover.peek(book.id);
}

ReaderIllustrationCache novelCoverImageCache(Novel book) =>
    ReaderIllustrationCache(request: (_) => novelCoverBytes(book));

Future<void> openNovelCoverImage(
  BuildContext context,
  Novel book, {
  required bool reduceMotion,
}) async {
  final url = book.coverUrl;
  if (url == null) return;
  await pushNovelPage<void>(
    context,
    ReaderIllustrationGallery(
      urls: [url],
      initialUrl: url,
      title: '小说封面',
      fileNamePrefix: book.title,
      cache: novelCoverImageCache(book),
    ),
    reduceMotion: reduceMotion,
  );
}
