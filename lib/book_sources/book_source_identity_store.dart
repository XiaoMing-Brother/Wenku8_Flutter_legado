import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../book_identity.dart';
import 'book_source.dart';
import 'book_source_reference.dart';

/// Keeps the source's string URL identity out of the app's integer book keys.
class BookSourceIdentityStore {
  BookSourceIdentityStore(this.directory);

  static const version = 1;
  static const maxBooks = 200000;
  final Directory directory;
  final Map<String, BookSourceRef> _byKey = {};
  final Map<int, BookSourceRef> _byId = {};
  final Map<String, int> _idByKey = {};
  int _nextId = bookSourceIdStart;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<void>? _pendingSave;

  static Future<BookSourceIdentityStore> forApp() async {
    final support = await getApplicationSupportDirectory();
    return BookSourceIdentityStore(
      Directory('${support.path}/wenku8-book-sources-v1'),
    );
  }

  BookSourceRef? byId(int id) => _byId[id];
  Iterable<MapEntry<int, BookSourceRef>> get entries => _byId.entries;

  BookSourceRef? bySource(String sourceKey, String bookUrl) =>
      _byKey[_key(sourceKey, bookUrl)];

  int? idFor(String sourceKey, String bookUrl) =>
      _idByKey[_key(sourceKey, bookUrl)];

  Future<void> remember(int id, BookSourceRef ref) async {
    if (id < bookSourceIdStart || id >= bookSourceIdEnd) return;
    final key = _key(ref.sourceKey, ref.bookUrl);
    if (identical(_byId[id], ref) && _idByKey[key] == id) return;
    final previous = _idByKey[key];
    if (previous != null && previous != id) _byId.remove(previous);
    _byId[id] = ref;
    _byKey[key] = ref;
    _idByKey[key] = id;
    if (_nextId <= id) _nextId = id + 1;
    await _save();
  }

  /// Reassigns an existing app book id to a new source coordinate.
  Future<void> replace(int id, BookSourceRef ref) async {
    if (id < bookSourceIdStart || id >= bookSourceIdEnd) return;
    final previous = _byId[id];
    if (previous != null) {
      final previousKey = _key(previous.sourceKey, previous.bookUrl);
      if (_idByKey[previousKey] == id) {
        _idByKey.remove(previousKey);
        _byKey.remove(previousKey);
      }
    }
    final key = _key(ref.sourceKey, ref.bookUrl);
    final previousId = _idByKey[key];
    if (previousId != null && previousId != id) _byId.remove(previousId);
    _byId[id] = ref;
    _byKey[key] = ref;
    _idByKey[key] = id;
    if (_nextId <= id) _nextId = id + 1;
    await _save();
  }

  Future<void> load() {
    if (_loading != null) return _loading!;
    final pending = _load();
    _loading = pending;
    return pending.catchError((Object error, StackTrace stack) {
      _loading = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _load() async {
    final file = _file;
    if (!await file.exists()) return;
    if (await file.length() > 16 * 1024 * 1024) {
      throw const FormatException('书源书籍索引超过 16 MB');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException {
      throw const FormatException('书源书籍索引不是有效的 JSON');
    }
    if (decoded is! Map || decoded['version'] != version) {
      throw const FormatException('书源书籍索引版本不受支持');
    }
    final nextId = decoded['nextId'];
    if (nextId is int &&
        nextId >= bookSourceIdStart &&
        nextId < bookSourceIdEnd) {
      _nextId = nextId;
    }
    final values = decoded['books'];
    if (values is! List) return;
    final ids = <int>{};
    var highestId = 0;
    for (final value in values) {
      if (value is! Map) continue;
      final id = value['id'];
      if (id is! int || id < bookSourceIdStart || id >= bookSourceIdEnd) {
        continue;
      }
      try {
        final ref = BookSourceRef.fromJson(value);
        if (!ids.add(id)) continue;
        _byId[id] = ref;
        final key = _key(ref.sourceKey, ref.bookUrl);
        _byKey[key] = ref;
        _idByKey[key] = id;
        if (id > highestId) highestId = id;
      } on FormatException {
        continue;
      }
    }
    // 旧索引或手工修改可能留下比 nextId 更大的条目，必须避免重复分配。
    if (highestId >= _nextId) {
      _nextId = highestId + 1;
    }
  }

  Future<BookSourceRef> refFor(
    BookSource source,
    String bookUrl, {
    String? tocUrl,
    String? title,
    String? author,
    String? coverUrl,
    String? customCoverUrl,
  }) async {
    await load();
    final key = _key(source.key, bookUrl);
    final current = _byKey[key];
    if (current != null) {
      final resolvedToc = tocUrl == null || tocUrl.isEmpty
          ? current.tocUrl
          : tocUrl;
      final next = current.copyWith(
        resourceType: source.resourceType,
        sourceName: source.name,
        tocUrl: resolvedToc,
        title: title?.trim().isNotEmpty == true ? title : null,
        author: author?.trim().isNotEmpty == true ? author : null,
        coverUrl: coverUrl?.trim().isNotEmpty == true ? coverUrl : null,
        customCoverUrl: customCoverUrl,
      );
      if (next.sourceName != current.sourceName ||
          next.tocUrl != current.tocUrl ||
          next.title != current.title ||
          next.author != current.author ||
          next.coverUrl != current.coverUrl || next.customCoverUrl != current.customCoverUrl || next.resourceType != current.resourceType) {
        _byKey[key] = next;
        final id = _idByKey[key];
        if (id != null) _byId[id] = next;
        unawaited(_saveQuietly());
      }
      return next;
    }
    if (_byId.length >= maxBooks) {
      throw const FormatException('书源书籍数量超过本机限制');
    }
    if (_nextId >= bookSourceIdEnd) {
      throw const FormatException('书源书籍标识已用尽');
    }
    final ref = BookSourceRef(
      resourceType: source.resourceType,
      sourceKey: source.key,
      sourceName: source.name,
      bookUrl: bookUrl,
      tocUrl: tocUrl,
      title: title ?? '',
      author: author ?? '',
      coverUrl: coverUrl ?? '',
      customCoverUrl: customCoverUrl ?? '',
    );
    final id = _nextId++;
    _byKey[key] = ref;
    _byId[id] = ref;
    _idByKey[key] = id;
    // Search can use the in-memory id immediately; the debounced writer
    // persists this batch without stalling result processing.
    unawaited(_saveQuietly());
    return ref;
  }

  Future<BookSourceRef> updateMeta(
    BookSourceRef ref, {
    String? tocUrl,
    String? title,
    String? author,
    String? coverUrl,
  }) async {
    final next = ref.copyWith(
      tocUrl: tocUrl == null || tocUrl.isEmpty ? null : tocUrl,
      title: title?.trim().isNotEmpty == true ? title : null,
      author: author?.trim().isNotEmpty == true ? author : null,
      coverUrl: coverUrl?.trim().isNotEmpty == true ? coverUrl : null,
    );
    if (next.tocUrl == ref.tocUrl &&
        next.title == ref.title &&
        next.author == ref.author &&
        next.coverUrl == ref.coverUrl) {
      return ref;
    }
    final key = _key(ref.sourceKey, ref.bookUrl);
    _byKey[key] = next;
    final id = _idByKey[key];
    if (id != null) _byId[id] = next;
    await _save();
    return next;
  }

  Future<void> _save() {
    final pending = _pendingSave;
    if (pending != null) return pending;
    final completer = Completer<void>();
    _pendingSave = completer.future;
    // A broad search discovers many books across sources. Coalesce those
    // mutations into one snapshot instead of rewriting the whole index for
    // every result on the UI isolate.
    Timer(const Duration(milliseconds: 300), () {
      _pendingSave = null;
      final String document;
      try {
        document = jsonEncode({
          'version': version,
          'nextId': _nextId,
          'books': [
            for (final entry in _byId.entries)
              {'id': entry.key, ...entry.value.toJson()},
          ],
        });
      } on Object catch (error, stack) {
        completer.completeError(error, stack);
        return;
      }
      final result = _writes.then((_) => _atomicWrite(document));
      _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      result.then<void>(
        (_) => completer.complete(),
        onError: (Object error, StackTrace stack) =>
            completer.completeError(error, stack),
      );
    });
    return completer.future;
  }

  Future<void> _saveQuietly() => _save().catchError((Object _) {});

  Future<void> _atomicWrite(String document) async {
    await directory.create(recursive: true);
    final temporary = File('${_file.path}.part');
    try {
      await temporary.writeAsString(document, flush: true);
      await temporary.rename(_file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  File get _file => File('${directory.path}/identities.json');

  static String _key(String sourceKey, String bookUrl) =>
      '$sourceKey\u0000$bookUrl';
}
