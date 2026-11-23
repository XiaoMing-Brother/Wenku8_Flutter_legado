import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class CoverDiskCache {
  CoverDiskCache(
    this.directory, {
    this.limit = 96 * 1024 * 1024,
    this.validate,
  });

  static final shared = CoverDiskCache(
    () async => Directory(
      '${(await getTemporaryDirectory()).path}/book-cover-cache-v1',
    ),
    validate: _validImage,
  );
  final Future<bool> Function(Uint8List)? validate;
  static Future<bool> _validImage(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      descriptor.dispose();
      return true;
    } on Object {
      return false;
    } finally {
      buffer.dispose();
    }
  }

  final Future<Directory> Function() directory;
  final int limit;
  Future<void> _queue = Future.value();
  final _pending = <String, Future<Uint8List>>{};
  final _epochs = <String, int>{};
  final _sizes = <String, int>{};
  final _hot = <String, WeakReference<Uint8List>>{};
  int _size = 0;
  bool _indexed = false;

  String _hash(String text) => sha256.convert(utf8.encode(text)).toString();

  String _name(String prefix, String url, String? bookKey) =>
      '$prefix-${_hash(url)}${bookKey == null ? '' : '-${_hash(bookKey).substring(0, 32)}'}.img';

  Future<Uint8List?> cached(
    String source,
    String url, {
    String? bookKey,
    bool allowAlias = false,
  }) => _disk<Uint8List?>((root) async {
    final prefix = _hash(source);
    final name = _name(prefix, url, bookKey);
    if (_sizes.containsKey(name)) return _read(root, name);
    final exact = '$prefix-${_hash(url)}';
    final suffix = allowAlias && bookKey != null
        ? '-${_hash(bookKey).substring(0, 32)}.img'
        : null;
    String? alias;
    for (final key in _sizes.keys) {
      if (key.startsWith(exact)) return _read(root, key);
      if (suffix != null &&
          key.startsWith('$prefix-') &&
          key.endsWith(suffix)) {
        alias = key;
      }
    }
    return alias == null ? null : _read(root, alias);
  });

  Future<Uint8List?> _read(Directory root, String name) async {
    final size = _sizes.remove(name);
    if (size == null) return null;
    final hot = _hot[name]?.target;
    if (hot != null) {
      _sizes[name] = size;
      return hot;
    }
    _size -= size;
    final file = File('${root.path}/$name');
    if (size <= 0 || size > limit || size != await file.length()) {
      await file.delete();
      return null;
    }
    final bytes = await file.readAsBytes();
    _hot[name] = WeakReference(bytes);
    _sizes[name] = size;
    _size += size;
    return bytes;
  }

  Future<T?> _disk<T>(Future<T> Function(Directory) action) {
    final result = _queue.then((_) async {
      try {
        final root = await directory();
        await root.create(recursive: true);
        if (!_indexed) {
          final files = <(String, FileStat)>[];
          await for (final file in root.list(followLinks: false)) {
            if (file is File && file.path.endsWith('.img')) {
              files.add((file.uri.pathSegments.last, await file.stat()));
            } else if (file is File && file.path.endsWith('.img.part')) {
              await file.delete();
            }
          }
          files.sort(
            (left, right) => left.$2.modified.compareTo(right.$2.modified),
          );
          for (final (name, stat) in files) {
            _sizes[name] = stat.size;
            _size += stat.size;
          }
          _indexed = true;
        }
        return await action(root);
      } on Object {
        return null;
      }
    });
    _queue = result.then<void>((_) {});
    return result;
  }

  Future<Uint8List> load(
    String source,
    String url,
    Future<Uint8List> Function() fetch, {
    String? bookKey,
  }) {
    final prefix = _hash(source);
    final name = _name(prefix, url, bookKey);
    final epoch = _epochs[prefix] ?? 0;
    final key = '$name:$epoch';
    return _pending.putIfAbsent(key, () async {
      try {
        final hit = await cached(source, url, bookKey: bookKey);
        if (hit != null) return hit;
        final bytes = await fetch();
        if (bytes.isNotEmpty &&
            bytes.length <= limit &&
            (validate == null || await validate!(bytes))) {
          await _disk((root) async {
            if ((_epochs[prefix] ?? 0) != epoch) return;
            final file = File('${root.path}/$name');
            final part = File('${file.path}.part');
            await part.writeAsBytes(bytes, flush: true);
            await part.rename(file.path);
            _sizes[name] = bytes.length;
            _hot[name] = WeakReference(bytes);
            _size += bytes.length;
            while (_size > limit || _sizes.length > 1024) {
              final oldest = _sizes.keys.first;
              await _remove(root, oldest);
            }
          });
        }
        return bytes;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<void> _remove(Directory root, String name) async {
    final file = File('${root.path}/$name');
    if (await file.exists()) await file.delete();
    _hot.remove(name);
    _size -= _sizes.remove(name) ?? 0;
  }

  Future<void> invalidate(String source) async {
    final prefix = _hash(source);
    _epochs[prefix] = (_epochs[prefix] ?? 0) + 1;
    await _disk((root) async {
      for (final name
          in _sizes.keys.where((key) => key.startsWith('$prefix-')).toList()) {
        await _remove(root, name);
      }
    });
  }
}
