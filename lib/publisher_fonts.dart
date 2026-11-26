import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'epub_font_obfuscation.dart';

/// 从 EPUB 中提取「出版方内嵌字体」并去混淆，供「使用出版方字体」开关使用。
///
/// 只处理 IDPF / Adobe 两种字体混淆（可安全还原），其余一律跳过；
/// 不对正文/图片做任何解密（DRM 仍由导入层拒绝）。
class PublisherFontData {
  const PublisherFontData({
    required this.name,
    required this.extension,
    required this.bytes,
  });

  /// 字体族显示名（不含扩展名）。
  final String name;

  /// `ttf` / `otf`。
  final String extension;

  /// 去混淆后的字体字节。
  final Uint8List bytes;
}

/// 每本本地书对应的伪「用户字体」id（需满足 `^font_[a-z0-9-]{1,64}$`）。
String publisherFontId(int bookId) => 'font_pub-b$bookId';

/// 判断某个选择是否为本项目的出版方字体 id。
bool isPublisherFontChoice(String value) =>
    RegExp(r'^font_pub-b[0-9]+$').hasMatch(value);

/// 入口：传入整本 EPUB 字节，返回第一个可用的出版方字体；没有则返回 null。
/// 顶层纯函数，可用于 `compute()` / isolate。
PublisherFontData? extractPublisherFontFromEpub(Uint8List epubBytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(epubBytes);
  } on Object {
    return null;
  }
  final byName = <String, ArchiveFile>{};
  for (final file in archive) {
    if (file.isFile) byName[file.name] = file;
  }
  if (byName.isEmpty) return null;

  Uint8List? readBytes(String path) {
    final file = byName[path];
    if (file == null) return null;
    try {
      final out = OutputMemoryStream();
      file.writeContent(out);
      return out.getBytes();
    } on Object {
      return null;
    }
  }

  String? readText(String path) {
    final bytes = readBytes(path);
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } on Object {
      return null;
    }
  }

  final container = readText('META-INF/container.xml');
  if (container == null) return null;
  final XmlDocument containerDoc;
  try {
    containerDoc = XmlDocument.parse(container);
  } on Object {
    return null;
  }
  String? opfPath;
  for (final element in containerDoc.descendants.whereType<XmlElement>()) {
    if (element.name.local != 'rootfile') continue;
    final path = element.getAttribute('full-path');
    if (path != null && path.trim().isNotEmpty) {
      opfPath = path.trim();
      break;
    }
  }
  if (opfPath == null) return null;

  final opfText = readText(opfPath);
  if (opfText == null) return null;
  final XmlDocument opfDoc;
  try {
    opfDoc = XmlDocument.parse(opfText);
  } on Object {
    return null;
  }

  final uniqueIdAttr = opfDoc.rootElement.getAttribute('unique-identifier');
  String? identifier;
  for (final element in opfDoc.descendants.whereType<XmlElement>()) {
    if (element.name.local != 'identifier') continue;
    final id = element.getAttribute('id');
    if (uniqueIdAttr == null || id == uniqueIdAttr) {
      final text = element.innerText.trim();
      if (text.isNotEmpty) {
        identifier = text;
        if (uniqueIdAttr != null) break;
      }
    }
  }

  final opfDir = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
      : '';
  final manifest = <String, String>{}; // id -> resolved path
  for (final element in opfDoc.descendants.whereType<XmlElement>()) {
    if (element.name.local != 'item') continue;
    final id = element.getAttribute('id');
    final href = element.getAttribute('href');
    if (id == null || href == null) continue;
    manifest[id] = _resolvePath(opfDir, href);
  }

  final encryption = readText('META-INF/encryption.xml');
  if (encryption == null) return null;
  final XmlDocument encDoc;
  try {
    encDoc = XmlDocument.parse(encryption);
  } on Object {
    return null;
  }

  for (final data in encDoc.descendants.whereType<XmlElement>()) {
    if (data.name.local != 'EncryptedData') continue;
    String? algorithm;
    String? reference;
    for (final element in data.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'EncryptionMethod' && algorithm == null) {
        algorithm = element.getAttribute('Algorithm');
      } else if (element.name.local == 'CipherReference' && reference == null) {
        reference = element.getAttribute('URI');
      }
    }
    if (algorithm == null || reference == null) continue;
    if (!isEpubFontObfuscationAlgorithm(algorithm)) continue;

    final path = _resolvePath('', reference);
    // 必须是 manifest 中登记的字体项，避免把任意加密资源当字体。
    final isFontItem = manifest.values.contains(path);
    if (!isFontItem) continue;
    final raw = readBytes(path);
    if (raw == null || raw.isEmpty) continue;

    Uint8List? clear;
    if (algorithm == epubFontAlgorithmIdpf) {
      if (identifier == null) continue;
      clear = deobfuscateEpubFont(
        raw,
        algorithm: algorithm,
        uniqueIdentifier: identifier,
      );
    } else if (algorithm == epubFontAlgorithmAdobe) {
      final key = identifier == null ? null : adobeFontKeyFromUuid(identifier);
      if (key == null) continue;
      clear = deobfuscateEpubFont(raw, algorithm: algorithm, adobeKey: key);
    }
    if (clear == null || clear.isEmpty) continue;

    final fileName = path.split('/').last;
    final dot = fileName.lastIndexOf('.');
    final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    if (extension != 'ttf' && extension != 'otf') continue;
    final name = (dot < 0 ? fileName : fileName.substring(0, dot)).trim();
    return PublisherFontData(
      name: name.isEmpty ? '出版方字体' : name,
      extension: extension,
      bytes: clear,
    );
  }
  return null;
}

String _resolvePath(String baseDir, String href) {
  final cleaned = href.replaceAll(RegExp(r'[\t\n\r]'), '').trim();
  final base = Uri(
    scheme: 'https',
    host: 'local',
    pathSegments: ['', if (baseDir.isNotEmpty) ...baseDir.split('/')],
  );
  final resolved = base.resolve(cleaned);
  if (resolved.scheme != 'https' || resolved.host != 'local') return href;
  final path = resolved.path.startsWith('/')
      ? resolved.path.substring(1)
      : resolved.path;
  return Uri.decodeComponent(path);
}
