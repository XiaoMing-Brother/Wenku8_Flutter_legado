import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersonalCovers extends ChangeNotifier {
  PersonalCovers({Directory? directory}) : _directory = directory;
  static final shared = PersonalCovers();
  static const defaultCover = 'default';
  static const original = 'original';
  static const _prefix = 'personalCover.v1.';
  static const _albumPrefix = 'coverAlbum.v1.';
  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  final Directory? _directory;
  SharedPreferences? _prefs;
  final _memory = <String, Uint8List>{};
  int _bytes = 0;

  Future<void> load() async => _prefs = await SharedPreferences.getInstance();
  String? choice(int id) => _prefs?.getString('$_prefix$id');
  List<String> get albums =>
      (_prefs?.getKeys() ?? <String>{})
          .where((key) => key.startsWith(_albumPrefix))
          .map((key) => key.substring(_albumPrefix.length))
          .toList()
        ..sort();
  List<String> album(String name) =>
      (_prefs?.getStringList('$_albumPrefix$name') ?? const <String>[])
          .where(_hash.hasMatch)
          .toList();

  Future<File> file(String key) async {
    if (!_hash.hasMatch(key)) throw const FormatException('封面记录无效');
    final root =
        _directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/personal-covers-v1',
        );
    return File('${root.path}/$key.png');
  }

  Future<String> save(Uint8List png, {String? albumName}) async {
    final key = sha256.convert(png).toString();
    final target = await file(key);
    if (!await target.exists()) {
      await target.parent.create(recursive: true);
      final part = File(
        '${target.path}.${DateTime.now().microsecondsSinceEpoch}.part',
      );
      try {
        await part.writeAsBytes(png, flush: true);
        await part.rename(target.path);
      } finally {
        if (await part.exists()) await part.delete();
      }
    }
    if (albumName != null) {
      final preferences = _prefs ??= await SharedPreferences.getInstance();
      if (!await preferences.setStringList(
        '$_albumPrefix$albumName',
        {key, ...album(albumName)}.toList(),
      )) {
        throw const FormatException('封面图集保存失败');
      }
    }
    _remember(key, png);
    return key;
  }

  Future<void> select(int id, String? key) async {
    if (key != null &&
        key != defaultCover &&
        key != original &&
        !await (await file(key)).exists()) {
      throw const FormatException('自选封面文件不存在');
    }
    final preferences = _prefs ??= await SharedPreferences.getInstance();
    final previous = choice(id);
    final saved = key == null
        ? await preferences.remove('$_prefix$id')
        : await preferences.setString('$_prefix$id', key);
    if (!saved) throw const FormatException('封面选择保存失败');
    notifyListeners();
    if (previous != null && previous != key) await releaseUnused(previous);
  }

  Future<void> removeAlbum(String name) async {
    final preferences = _prefs ??= await SharedPreferences.getInstance();
    final images = album(name);
    if (!await preferences.remove('$_albumPrefix$name')) {
      throw const FormatException('图集删除失败');
    }
    for (final image in images) {
      await releaseUnused(image);
    }
  }

  Future<void> releaseUnused(String previous) async {
    final preferences = _prefs ??= await SharedPreferences.getInstance();
    if (_hash.hasMatch(previous) &&
        !preferences.getKeys().any(
          (pref) =>
              pref.startsWith(_prefix) &&
              preferences.getString(pref) == previous,
        ) &&
        !albums.any((name) => album(name).contains(previous))) {
      try {
        await (await file(previous)).delete();
      } on FileSystemException catch (error) {
        debugPrint('旧封面未清理：$error');
      }
    }
  }

  Uint8List? peek(String key) => _memory[key];
  Future<Uint8List> read(String key) async =>
      _memory[key] ?? _remember(key, await (await file(key)).readAsBytes());
  Uint8List _remember(String key, Uint8List bytes) {
    _bytes -= _memory.remove(key)?.length ?? 0;
    _memory[key] = bytes;
    _bytes += bytes.length;
    while (_bytes > 16 * 1024 * 1024 && _memory.isNotEmpty) {
      _bytes -= _memory.remove(_memory.keys.first)!.length;
    }
    return bytes;
  }
}
