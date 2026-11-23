import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'app_interactions.dart';
import 'catalog.dart';
import 'cover_disk_cache.dart';
import 'book_sources/book_source_images.dart';
import 'legacy_cover.dart';
import 'local_book_media.dart';
import 'official_books.dart';
import 'personal_covers.dart';
export 'personal_covers.dart';
import 'reader_illustrations.dart';

String? novelCoverUrl(Novel book) =>
    switch (PersonalCovers.shared.choice(book.id)) {
      null => book.coverUrl,
      PersonalCovers.defaultCover => null,
      PersonalCovers.original =>
        book.source?.customCoverUrl.isNotEmpty == true
            ? book.source!.coverUrl
            : book.coverUrl,
      final key => 'wenku-cover:$key',
    };

Future<Uint8List> novelCoverBytes(
  Novel book, {
  bool original = false,
  bool cachedOnly = false,
  bool preferBookCache = false,
}) async {
  final url = original ? book.coverUrl : novelCoverUrl(book);
  if (url == null || url.isEmpty) {
    throw const FormatException('书籍没有封面地址');
  }
  if (url.startsWith('wenku-cover:')) {
    return PersonalCovers.shared.read(url.substring(12));
  }
  if (url.startsWith('wenku-local:')) return LocalBookMedia.loadCover(url);
  final memory = _peek(book, url);
  if (memory != null) return memory;
  final source = book.source;
  if (source == null) {
    if (cachedOnly) throw const FormatException('这张封面尚未缓存');
    return LegacyCover.bytes(book.id, url: url);
  }
  final official = OfficialBookService.isOfficialKey(source.sourceKey);
  final cacheSource = official ? 'official' : source.sourceKey;
  final bookKey = source.customCoverUrl.isEmpty || url == source.coverUrl
      ? '${source.sourceKey}\u0000${source.bookUrl}'
      : null;
  final allowAlias = !original && bookKey != null;
  Future<Uint8List?> cached() => CoverDiskCache.shared.cached(
    cacheSource,
    url,
    bookKey: bookKey,
    allowAlias: allowAlias,
  );
  if (cachedOnly || (preferBookCache && allowAlias)) {
    final hit = await cached();
    if (hit != null) return hit;
    if (cachedOnly) throw const FormatException('这张封面尚未缓存，请联网后重试');
  }
  try {
    return official
        ? await OfficialBookService.coverBytes(url, bookKey: bookKey)
        : await BookSourceImages.coverBytes(
            source.sourceKey,
            url,
            bookKey: bookKey,
          );
  } catch (error) {
    if (allowAlias && !preferBookCache && error is! StateError) {
      final hit = await cached();
      if (hit != null) return hit;
    }
    rethrow;
  }
}

Uint8List? peekNovelCover(Novel book) {
  final url = novelCoverUrl(book);
  if (url == null || url.isEmpty) return null;
  return _peek(book, url);
}

Uint8List? _peek(Novel book, String url) {
  if (url.startsWith('wenku-cover:')) {
    return PersonalCovers.shared.peek(url.substring(12));
  }
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
  final url = novelCoverUrl(book);
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
