import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// EPUB 内嵌字体去混淆（参考 RM 2.3.5B3 的字体处理链）。
///
/// 说明：
///  - 本项目默认使用统一阅读字体，并不加载出版方内嵌字体；
///  - 本工具是「书级可选：使用出版方字体」能力的基础件，默认行为不改变；
///  - 仅对 EPUB 字体混淆做处理，绝不用于解密正文或图片（DRM 仍应在
///    `local_books.dart` 的 `META-INF/encryption.xml` 分支中被拒绝）。
///
/// 算法（XOR 对称，解密即再 XOR 一次）：
///  - IDPF  (`http://www.idpf.org/2008/embedding`)：
///      key = SHA-1(UTF-8(unique-identifier 去空白)) 的 20 字节；
///      data[i] ^= key[i % 20]，仅前 1040 字节。
///  - Adobe (`http://ns.adobe.com/pdf/enc#RC`)：
///      key = 16 字节 UUID；
///      data[i] ^= key[i % 16]，仅前 1024 字节。
const String epubFontAlgorithmIdpf = 'http://www.idpf.org/2008/embedding';
const String epubFontAlgorithmAdobe = 'http://ns.adobe.com/pdf/enc#RC';

const int _idpfObfuscatedLength = 1040;
const int _adobeObfuscatedLength = 1024;

/// 是否为 EPUB 字体混淆算法（可安全去混淆，而非正文/图片 DRM）。
bool isEpubFontObfuscationAlgorithm(String algorithm) =>
    algorithm == epubFontAlgorithmIdpf || algorithm == epubFontAlgorithmAdobe;

/// IDPF 混淆 key：对 unique-identifier（去掉所有空白）取 SHA-1（20 字节）。
Uint8List idpfFontKey(String uniqueIdentifier) => Uint8List.fromList(
  sha1.convert(utf8.encode(uniqueIdentifier.replaceAll(RegExp(r'\s+'), ''))).bytes,
);

/// Adobe 混淆 key：由 UUID 字符串（可带连字符/花括号）取 16 字节；不足 32 位十六进制返回 null。
Uint8List? adobeFontKeyFromUuid(String uuid) {
  final hex = uuid.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (hex.length < 32) return null;
  final key = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    key[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return key;
}

/// 通用入口：按 [algorithm] 分派；不认识的算法返回 null（交由调用方拒绝/忽略）。
Uint8List? deobfuscateEpubFont(
  Uint8List data, {
  required String algorithm,
  String? uniqueIdentifier,
  Uint8List? adobeKey,
}) {
  switch (algorithm) {
    case epubFontAlgorithmIdpf:
      if (uniqueIdentifier == null) return null;
      return xorFontPrefix(data, idpfFontKey(uniqueIdentifier), _idpfObfuscatedLength);
    case epubFontAlgorithmAdobe:
      if (adobeKey == null || adobeKey.length != 16) return null;
      return xorFontPrefix(data, adobeKey, _adobeObfuscatedLength);
    default:
      return null;
  }
}

/// 对前 [length] 字节按 [key] 循环 XOR，返回新数组（不修改入参）。
/// 混淆与去混淆是同一操作，故导出以便单测与显式混淆。
Uint8List xorFontPrefix(Uint8List data, Uint8List key, int length) {
  if (key.isEmpty) return Uint8List.fromList(data);
  final out = Uint8List.fromList(data);
  final end = length < out.length ? length : out.length;
  for (var i = 0; i < end; i++) {
    out[i] ^= key[i % key.length];
  }
  return out;
}
