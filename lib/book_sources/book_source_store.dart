import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'book_source.dart';
import 'book_source_search_scope.dart';

class BookSourceImportResult {
  const BookSourceImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
  });

  final int added;
  final int updated;
  final int skipped;
  int get total => added + updated;
}

/// App-owned Legado source library. The original JSON object is retained so an
/// export can be imported back into Legado without losing unknown fields.
class BookSourceStore extends ChangeNotifier {
  BookSourceStore(this.directory);

  static const version = 1;
  static const maxSources = 10000;
  static const maxConfigBytes = 128 * 1024 * 1024;
  final Directory directory;
  final Map<String, BookSource> _sources = {};
  BookSourceSearchScope _searchScope = const BookSourceSearchScope.all();
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<void> _scopeWrites = Future.value();
  bool _loaded = false;

  static Future<BookSourceStore> forApp() async {
    final support = await getApplicationSupportDirectory();
    return BookSourceStore(Directory('${support.path}/wenku8-book-sources-v1'));
  }

  List<BookSource> get sources => List.unmodifiable(_sources.values);
  List<BookSource> get enabled =>
      List.unmodifiable(_sources.values.where((source) => source.enabled));
  BookSourceSearchScope get searchScope => _searchScope;
  int get length => _sources.length;
  BookSource? source(String key) => _sources[key];
  bool get loaded => _loaded;

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
    if (!await file.exists()) {
      await _loadScope();
      _loaded = true;
      return;
    }
    if (await file.length() > maxConfigBytes) {
      throw const FormatException('书源配置超过 128 MB');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException {
      throw const FormatException('书源配置不是有效的 JSON');
    }
    if (decoded is! Map || decoded['version'] != version) {
      throw const FormatException('书源配置版本不受支持');
    }
    final values = decoded['sources'];
    if (values is! List) {
      throw const FormatException('书源配置缺少来源列表');
    }
    _sources
      ..clear()
      ..addEntries([
        for (final value in values)
          if (BookSource.tryParse(value) case final source?)
            MapEntry(source.key, source),
      ]);
    await _loadScope();
    _loaded = true;
    notifyListeners();
  }

  Future<BookSourceImportResult> importText(String text) async {
    final batch = decodeBookSources(text);
    await load();
    final additions = batch.sources
        .where((source) => !_sources.containsKey(source.key))
        .length;
    if (_sources.length + additions > maxSources) {
      throw FormatException('书源数量不能超过 $maxSources 个');
    }
    var added = 0;
    var updated = 0;
    for (final source in batch.sources) {
      if (_sources.containsKey(source.key)) {
        updated++;
        // Updating a source keeps its existing position, matching Legado's
        // customOrder retention instead of moving it to the end.
        _sources[source.key] = source;
      } else {
        added++;
        _sources[source.key] = source;
      }
    }
    await _save();
    notifyListeners();
    return BookSourceImportResult(
      added: added,
      updated: updated,
      skipped: batch.skipped,
    );
  }

  Future<void> updateSource(BookSource source) async {
    await load();
    final current = _sources[source.key];
    if (current == null) {
      throw const FormatException('书源已不存在，请刷新后重试');
    }
    if (mapEquals(current.raw, source.raw)) return;
    _sources[source.key] = source;
    await _save();
    notifyListeners();
  }

  Future<void> setEnabled(String key, bool enabled) async {
    await setEnabledMany([key], enabled);
  }

  Future<void> setEnabledMany(Iterable<String> keys, bool enabled) async {
    var changed = false;
    for (final key in keys.toSet()) {
      final current = _sources[key];
      if (current == null || current.enabled == enabled) continue;
      _sources[key] = current.withEnabled(enabled);
      changed = true;
    }
    if (!changed) return;
    await _save();
    notifyListeners();
  }

  Future<void> updateGroups(
    Iterable<String> keys, {
    String? addGroup,
    String? removeGroup,
  }) async {
    final add = addGroup?.trim() ?? '';
    final remove = removeGroup?.trim() ?? '';
    if (add.isEmpty && remove.isEmpty) return;
    var changed = false;
    for (final key in keys.toSet()) {
      final current = _sources[key];
      if (current == null) continue;
      final groups = current.groups.toSet();
      final applied = add.isNotEmpty ? groups.add(add) : groups.remove(remove);
      if (!applied) continue;
      _sources[key] = current.withGroups(groups);
      changed = true;
    }
    if (!changed) return;
    await _save();
    notifyListeners();
  }

  Future<void> setSearchScope(BookSourceSearchScope scope) async {
    if (_searchScope == scope) return;
    final previous = _searchScope;
    _searchScope = scope;
    try {
      await _saveScope();
    } on Object {
      _searchScope = previous;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> remove(String key) async {
    await removeMany([key]);
  }

  Future<void> removeMany(Iterable<String> keys) async {
    var changed = false;
    for (final key in keys.toSet()) {
      if (_sources.remove(key) != null) changed = true;
    }
    if (!changed) return;
    await _save();
    notifyListeners();
  }

  String exportJson({Set<String>? keys}) {
    final values = [
      for (final source in _sources.values)
        if (keys == null || keys.contains(source.key)) source.toJson(),
    ];
    return const JsonEncoder.withIndent('  ').convert(values);
  }

  Future<void> _loadScope() async {
    final file = _scopeFile;
    if (!await file.exists()) return;
    try {
      if (await file.length() > 256 * 1024) return;
      final decoded = jsonDecode(await file.readAsString());
      _searchScope = BookSourceSearchScope.fromJson(decoded);
    } on Object {
      // A broken preference must not make the whole source library unusable.
      _searchScope = const BookSourceSearchScope.all();
    }
  }

  Future<void> _saveScope() {
    final document = jsonEncode(_searchScope.toJson());
    final result = _scopeWrites.then((_) => _atomicWrite(_scopeFile, document));
    _scopeWrites = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _save() {
    final document = jsonEncode({
      'version': version,
      'sources': [for (final source in _sources.values) source.toJson()],
    });
    final result = _writes.then((_) => _atomicWrite(_file, document));
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _atomicWrite(File file, String document) async {
    await directory.create(recursive: true);
    final temporary = File('${file.path}.part');
    try {
      await temporary.writeAsString(document, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  File get _file => File('${directory.path}/sources.json');
  File get _scopeFile => File('${directory.path}/search_scope.json');

  @override
  void dispose() {
    _sources.clear();
    super.dispose();
  }
}
