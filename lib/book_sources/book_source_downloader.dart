import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A user-facing failure while downloading a book source document.
class BookSourceImportException implements Exception {
  const BookSourceImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads Legado book source JSON from the links published by source sites.
///
/// Only the document is fetched here. Validation and de-duplication stay in the
/// source store so remote and pasted imports share the same rules.
class BookSourceDownloader {
  BookSourceDownloader({
    HttpClient Function()? clientFactory,
    this.timeout = const Duration(seconds: 30),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  static const maxBytes = 128 * 1024 * 1024;
  final HttpClient Function() _clientFactory;
  final Duration timeout;

  Future<String> fetch(String input) async {
    final uri = _parse(input);
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri).timeout(timeout)
        ..followRedirects = true
        ..maxRedirects = 5;
      request.headers
        ..set(
          HttpHeaders.acceptHeader,
          'application/json, text/plain;q=0.9, */*;q=0.1',
        )
        ..set(HttpHeaders.userAgentHeader, 'Wenku/1.0');
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw BookSourceImportException(
          response.statusCode == 404
              ? '下载书源失败：链接不存在（HTTP 404）'
              : '下载书源失败（HTTP ${response.statusCode}）',
        );
      }
      if (response.headers.contentType?.mimeType == 'text/html') {
        await response.drain<void>();
        throw const BookSourceImportException('这个链接返回的是网页，不是书源 JSON');
      }
      if (response.contentLength > maxBytes) {
        await response.drain<void>();
        throw const BookSourceImportException('书源文件超过 128 MB');
      }
      final builder = BytesBuilder(copy: false);
      await for (final part in response.timeout(timeout)) {
        if (builder.length + part.length > maxBytes) {
          throw const BookSourceImportException('书源文件超过 128 MB');
        }
        builder.add(part);
      }
      final text = _decode(builder.takeBytes());
      if (text.trimLeft().startsWith('<')) {
        throw const BookSourceImportException('这个链接返回的是网页，不是书源 JSON');
      }
      return text;
    } on BookSourceImportException {
      rethrow;
    } on TimeoutException {
      throw const BookSourceImportException('下载书源超时，请检查网络后重试');
    } on IOException {
      throw const BookSourceImportException('无法下载书源，请检查网络和链接');
    } finally {
      client.close(force: true);
    }
  }

  static String _decode(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      return text.startsWith('\uFEFF') ? text.substring(1) : text;
    } on FormatException {
      throw const BookSourceImportException('书源文件不是 UTF-8 编码的 JSON');
    }
  }

  static Uri _parse(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      throw const BookSourceImportException('请填写书源 JSON 链接');
    }
    if (value.length > 4096) {
      throw const BookSourceImportException('书源链接过长');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const BookSourceImportException('请填写 http 或 https 开头的书源 JSON 链接');
    }
    return uri;
  }
}
