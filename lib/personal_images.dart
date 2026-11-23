import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

/// Decode once at import time. Reading and shelf animations only use the
/// bounded, application-owned still image, never the picker URI or original.
Future<Uint8List> preparePersonalImage(
  String path, {
  bool cover = false,
}) async {
  final file = File(path);
  final bytes = await file.length();
  if (bytes == 0 || bytes > 20 * 1024 * 1024) {
    throw const FormatException('请选择 20 MiB 以内的图片');
  }
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  return _prepareImageBuffer(buffer, cover: cover);
}

Future<Uint8List> preparePersonalImageBytes(
  Uint8List bytes, {
  bool cover = false,
}) async {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('请选择 20 MiB 以内的图片');
  }
  return _prepareImageBuffer(
    await ui.ImmutableBuffer.fromUint8List(bytes),
    cover: cover,
  );
}

Future<Uint8List> prepareCoverFromUrl(String input) async {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !{'https', 'http'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('请输入完整的 HTTP 或 HTTPS 图片地址');
  }
  const timeout = Duration(seconds: 20);
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'image/*');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw const FormatException('图片地址不可访问');
    }
    const limit = 20 * 1024 * 1024;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      if (response.contentLength > limit ||
          bytes.length + chunk.length > limit) {
        throw const FormatException('请选择 20 MiB 以内的图片');
      }
      bytes.add(chunk);
    }
    return await preparePersonalImageBytes(bytes.takeBytes(), cover: true);
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List> _prepareImageBuffer(
  ui.ImmutableBuffer buffer, {
  required bool cover,
}) async {
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width, height = descriptor.height;
    if (width <= 0 || height <= 0 || width * height > 80000000) {
      throw const FormatException('图片尺寸过大，请先缩小图片');
    }
    final limit = cover ? 1440 : 2048;
    final scale = (limit / (width > height ? width : height)).clamp(0.0, 1.0);
    codec = await descriptor.instantiateCodec(
      targetWidth: (width * scale).round().clamp(1, limit),
      targetHeight: (height * scale).round().clamp(1, limit),
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes > 16 * 1024 * 1024) {
      throw const FormatException('图片处理未完成，请选择较小的图片');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('无法读取这张图片，请选择 PNG、JPEG 或 WebP 图片');
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

bool validBackgroundId(Object? id) =>
    id is String && RegExp(r'^paper_[0-9]+\.png$').hasMatch(id);

class ReaderBackgroundStore {
  ReaderBackgroundStore({Directory? directory, Directory? themeDirectory})
    : _directory = directory,
      _themeDirectory = themeDirectory;
  Directory? _directory;
  Directory? _themeDirectory;
  final _resolvedFiles = <String, File>{};
  final _resolvedThemeFiles = <int, File>{};
  final _themeDownloads = <int, Future<File?>>{};
  File? resolvedFile(String? id) => _resolvedFiles[id];
  File? resolvedThemeFile(int? id) => _resolvedThemeFiles[id];
  Future<Directory> get directory async => _directory ??= Directory(
    '${(await getApplicationSupportDirectory()).path}/reader-backgrounds',
  );
  Future<Directory> get themeDirectory async => _themeDirectory ??= Directory(
    '${(await getApplicationSupportDirectory()).path}/reader-theme-backgrounds',
  );
  Future<File?> file(String? id) async {
    if (!validBackgroundId(id)) return null;
    final value = File('${(await directory).path}/$id');
    if (await value.exists()) return _resolvedFiles[id!] = value;
    _resolvedFiles.remove(id);
    return null;
  }

  Future<File?> themeFile(int? id) async {
    if (id == null) return null;
    final value = File('${(await themeDirectory).path}/theme_$id.png');
    if (await value.exists()) return _resolvedThemeFiles[id] = value;
    _resolvedThemeFiles.remove(id);
    return null;
  }

  Future<File?> cacheThemeImage(int? id, List<String> urls) {
    if (id == null || urls.isEmpty) return Future<File?>.value();
    final pending = _themeDownloads[id];
    if (pending != null) return pending;
    final operation = _cacheThemeImage(id, urls);
    _themeDownloads[id] = operation;
    return operation.whenComplete(() => _themeDownloads.remove(id));
  }

  Future<File?> _cacheThemeImage(int id, List<String> urls) async {
    final cached = await themeFile(id);
    if (cached != null) return cached;
    final root = await themeDirectory;
    await root.create(recursive: true);
    for (final raw in urls) {
      final uri = Uri.tryParse(raw);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        continue;
      }
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final request =
            await client.getUrl(uri).timeout(const Duration(seconds: 20))
              ..followRedirects = true
              ..maxRedirects = 5;
        request.headers
          ..set(HttpHeaders.acceptHeader, 'image/*')
          ..set(HttpHeaders.userAgentHeader, 'Wenku/1.0');
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>();
          continue;
        }
        const limit = 20 * 1024 * 1024;
        if (response.contentLength > limit) {
          await response.drain<void>();
          continue;
        }
        final builder = BytesBuilder(copy: false);
        await for (final part in response) {
          if (builder.length + part.length > limit) {
            throw const FormatException('主题背景图超过 20 MiB');
          }
          builder.add(part);
        }
        final prepared = await preparePersonalImageBytes(builder.takeBytes());
        final part = File('${root.path}/theme_$id.png.part');
        try {
          await part.writeAsBytes(prepared, flush: true);
          final file = await part.rename('${root.path}/theme_$id.png');
          _resolvedThemeFiles[id] = file;
          await _pruneThemeImages(root, keep: id);
          return file;
        } finally {
          if (await part.exists()) await part.delete();
        }
      } catch (_) {
        // 试下一个候选地址；主题底色仍然可用。
      } finally {
        client.close(force: true);
      }
    }
    return null;
  }

  Future<void> _pruneThemeImages(Directory root, {required int keep}) async {
    final files = <File>[];
    await for (final entry in root.list()) {
      if (entry is File && entry.path.endsWith('.png')) files.add(entry);
    }
    if (files.length <= 12) return;
    final stats = <(File, DateTime)>[];
    for (final file in files) {
      if (file.uri.pathSegments.last == 'theme_$keep.png') continue;
      final stat = await file.stat();
      stats.add((file, stat.modified));
    }
    stats.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (file, _) in stats.take(files.length - 12)) {
      try {
        await file.delete();
      } catch (_) {
        // 清理失败不影响当前主题。
      }
    }
  }

  Future<List<String>> list() async {
    final root = await directory;
    if (!await root.exists()) return [];
    final ids = <String>[];
    await for (final entry in root.list()) {
      final id = entry.uri.pathSegments.last;
      if (entry is File && validBackgroundId(id)) ids.add(id);
    }
    return ids..sort((a, b) => b.compareTo(a));
  }

  Future<String> import(String path) async {
    if ((await list()).length >= 12) {
      throw const FormatException('最多保留 12 张背景，请先删除不用的图片');
    }
    final bytes = await preparePersonalImage(path);
    final root = await directory;
    await root.create(recursive: true);
    final id = 'paper_${DateTime.now().microsecondsSinceEpoch}.png';
    final part = File('${root.path}/$id.part');
    try {
      await part.writeAsBytes(bytes, flush: true);
      _resolvedFiles[id] = await part.rename('${root.path}/$id');
    } finally {
      if (await part.exists()) await part.delete();
    }
    return id;
  }

  Future<void> remove(String id) async {
    final owned = await file(id);
    if (owned != null) await owned.delete();
    _resolvedFiles.remove(id);
  }
}
