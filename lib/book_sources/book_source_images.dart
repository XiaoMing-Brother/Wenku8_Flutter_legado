import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'book_source_transport.dart';
import '../cover_disk_cache.dart';

/// Book-source images need the source's headers and cookies, which live in the
/// Android engine. Reader markers therefore carry both the source key and the
/// original image URL instead of relying on host or referer heuristics.
abstract final class BookSourceImages {
  static const markerScheme = 'legado-image';
  static const _transport = BookSourceTransport();
  static final _cache = _ImageCache();
  static final _readerRevisions = <String, int>{};
  static int _nextRevision = 0;

  static bool isMarker(String value) =>
      value.startsWith('$markerScheme:') && parseMarker(value) != null;

  static String markerUrl({required String sourceKey, required String url}) {
    return '$markerScheme:'
        '${_encode(sourceKey)}.${_encode(url)}';
  }

  static ({String sourceKey, String url})? parseMarker(String value) {
    if (!value.startsWith('$markerScheme:')) return null;
    final payload = value.substring(markerScheme.length + 1);
    final separator = payload.indexOf('.');
    if (separator <= 0 || separator == payload.length - 1) return null;
    try {
      final sourceKey = _decode(payload.substring(0, separator));
      final url = _decode(payload.substring(separator + 1));
      if (sourceKey.trim().isEmpty ||
          !(url.startsWith('http://') || url.startsWith('https://'))) {
        return null;
      }
      return (sourceKey: sourceKey, url: url);
    } on FormatException {
      return null;
    }
  }

  static Uint8List? peekMarker(String value) {
    final parsed = parseMarker(value);
    return parsed == null ? null : _cache.peek(_key(parsed));
  }

  static Future<Uint8List> loadMarker(String value) {
    final parsed = parseMarker(value);
    if (parsed == null) {
      return Future.error(const FormatException('书源图片地址无效'));
    }
    return _cache.load(_key(parsed), () => _fetch(parsed));
  }

  static Uint8List? peekCover(String sourceKey, String url) =>
      _cache.peek(_coverKey(sourceKey, url));

  static Future<Uint8List> coverBytes(
    String sourceKey,
    String url, {
    String? bookKey,
  }) => _cache.load(
    _coverKey(sourceKey, url),
    () => CoverDiskCache.shared.load(
      sourceKey,
      url,
      () => _fetchCover((
        sourceKey: sourceKey,
        url: url,
        bookUrl: _bookKeyUrl(bookKey),
      )),
      bookKey: bookKey,
    ),
  );

  static Future<Uint8List> _fetch(({String sourceKey, String url}) image) =>
      _transport.image(sourceKey: image.sourceKey, url: image.url);

  /// 封面需要执行 coverDecodeJs，并把书籍地址传给脚本的 book.bookUrl。
  static Future<Uint8List> _fetchCover(
    ({String sourceKey, String url, String? bookUrl}) image,
  ) => _transport.image(
    sourceKey: image.sourceKey,
    url: image.url,
    cover: true,
    bookUrl: image.bookUrl,
  );

  static String? _bookKeyUrl(String? bookKey) {
    if (bookKey == null || !bookKey.contains('\u0000')) return null;
    final value = bookKey.substring(bookKey.indexOf('\u0000') + 1).trim();
    return value.isEmpty ? null : value;
  }

  static int markerRevision(String marker) {
    final image = parseMarker(marker);
    if (image == null) return 0;
    return _readerRevisions.putIfAbsent(image.sourceKey, () => ++_nextRevision);
  }

  static Future<void> invalidateSource(String sourceKey) {
    _readerRevisions.remove(sourceKey);
    _cache.invalidate(sourceKey);
    return CoverDiskCache.shared.invalidate(sourceKey);
  }

  static _ImageKey _coverKey(String sourceKey, String url) =>
      (sourceKey: sourceKey, url: url, cover: true);

  static _ImageKey _key(({String sourceKey, String url}) image) =>
      (sourceKey: image.sourceKey, url: image.url, cover: false);

  static String _encode(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  static String _decode(String value) =>
      utf8.decode(base64Url.decode(base64Url.normalize(value)));
}

typedef _ImageKey = ({String sourceKey, String url, bool cover});

class _ImageCache {
  static const maxBytes = 16 * 1024 * 1024;
  static const maxEntries = 256;
  static const retryDelay = Duration(seconds: 30);

  final _entries = <_ImageKey, Uint8List>{};
  final _pending = <_ImageKey, Future<Uint8List>>{};
  final _failures = <_ImageKey, (DateTime, Future<Uint8List>)>{};
  int _bytes = 0;

  void invalidate(String sourceKey) {
    _entries.removeWhere((key, bytes) {
      if (key.sourceKey != sourceKey) return false;
      _bytes -= bytes.length;
      return true;
    });
    _pending.removeWhere((key, _) => key.sourceKey == sourceKey);
    _failures.removeWhere((key, _) => key.sourceKey == sourceKey);
  }

  Uint8List? peek(_ImageKey key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  Future<Uint8List> load(_ImageKey key, Future<Uint8List> Function() request) {
    final cached = peek(key);
    if (cached != null) return Future.value(cached);
    final failure = _failures[key];
    if (failure != null && DateTime.now().isBefore(failure.$1)) {
      return failure.$2;
    }
    _failures.remove(key);
    final pending = _pending[key];
    if (pending != null) return pending;
    final completer = Completer<Uint8List>();
    final future = completer.future;
    _pending[key] = future;
    unawaited(() async {
      try {
        final image = await request();
        if (!identical(_pending[key], future)) throw StateError('书源图片会话已变更');
        if (image.isEmpty || image.length > 8 * 1024 * 1024) {
          throw const FormatException('书源图片大小无效');
        }
        final bytes = Uint8List.fromList(image).asUnmodifiableView();
        _store(key, bytes);
        completer.complete(bytes);
      } catch (error, stack) {
        if (identical(_pending[key], future)) {
          _failures[key] = (DateTime.now().add(retryDelay), future);
          while (_failures.length > maxEntries) {
            _failures.remove(_failures.keys.first);
          }
        }
        completer.completeError(error, stack);
      } finally {
        if (identical(_pending[key], future)) _pending.remove(key);
      }
    }());
    return future;
  }

  void _store(_ImageKey key, Uint8List bytes) {
    final previous = _entries.remove(key);
    if (previous != null) _bytes -= previous.length;
    if (bytes.length > maxBytes) return;
    _entries[key] = bytes;
    _bytes += bytes.length;
    while (_bytes > maxBytes || _entries.length > maxEntries) {
      _bytes -= _entries.remove(_entries.keys.first)!.length;
    }
  }
}
