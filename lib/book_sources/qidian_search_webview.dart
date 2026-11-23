import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 用无头 WebView 通过起点 argus 反爬，抓取起点**桌面页**数据（搜索/目录/正文）。
///
/// 背景：`m.qidian.com/search` 对裸 HTTP 与真机 WebView 都返回“页面无法访问”；
/// 但桌面页 `www.qidian.com/...` 在真实浏览器内核里能过 argus 正常渲染。
/// 因此本类统一加载桌面页并在页面内用 JS 抽取结构化结果。
///
/// 只服务于「起点官方」这一条链路；未被任何其他书源引用，失败一律返回 null，
/// 由调用方各自回退，不影响其他书源。
class QidianSearchWebView {
  QidianSearchWebView._();

  static final QidianSearchWebView instance = QidianSearchWebView._();

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Safari/537.36';

  /// 搜索页：`www.qidian.com/so/<kw>.html` 的 `.book-mid-info` 结果卡片。
  static const _searchJs = r'''
(function(){
  var els=[].slice.call(document.querySelectorAll('.book-mid-info'));
  var out=els.map(function(el){
    var a=el.querySelector('h4 a')||el.querySelector('a');
    var au=el.querySelector('p.author a')||el.querySelector('.author a');
    var intro=el.querySelector('p.intro')||el.querySelector('.intro');
    return {name:a?a.textContent.trim():'', href:a?a.href:'', author:au?au.textContent.trim():'', intro:intro?intro.textContent.trim():''};
  }).filter(function(x){return x.name && x.href;});
  return JSON.stringify({ok: out.length>0, data: out});
})()
''';

  /// 书页：`www.qidian.com/book/<id>/` 的完整目录（`li.chapter-item`）。
  static const _catalogJs = r'''
(function(){
  var els=[].slice.call(document.querySelectorAll('li.chapter-item a.chapter-name'));
  var out=els.map(function(a){return {t:a.textContent.trim(), h:a.href};})
             .filter(function(x){return x.t && x.h;});
  return JSON.stringify({ok: out.length>0, data: out});
})()
''';

  /// 阅读页：取 `.content`/`main` 的 innerHTML（保留段落）；付费页无内容则空串。
  static const _contentJs = r'''
(function(){
  var root=document.querySelector('.content')||document.querySelector('main');
  var html = root ? (root.innerHTML||'').replace(/<script[\s\S]*?<\/script>/gi,'').trim() : '';
  var bodyText = document.body ? document.body.innerText : '';
  var pay = /请先登录|登录后阅读|订阅|购买|VIP章节|本章为付费/.test(bodyText);
  var deny = (document.documentElement.outerHTML||'').indexOf('页面无法访问') >= 0;
  var ok = !deny && (html.length > 50 || pay);
  return JSON.stringify({ok: ok, data: html});
})()
''';

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  Completer<Object?>? _pending;
  String? _pendingJs;
  Future<void> _serial = Future<void>.value();

  bool get _supported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  Future<void> _ensure() async {
    if (_webView != null && _controller != null) return;
    final created = Completer<void>();
    final webView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: _userAgent,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        if (!created.isCompleted) created.complete();
      },
      onLoadStop: (controller, url) {
        unawaited(_tryExtract(controller));
      },
    );
    _webView = webView;
    await webView.run();
    await created.future.timeout(const Duration(seconds: 15));
  }

  Future<void> _tryExtract(InAppWebViewController controller) async {
    final pending = _pending;
    final js = _pendingJs;
    if (pending == null || pending.isCompleted || js == null) return;
    try {
      final result = await controller.evaluateJavascript(source: js);
      final text = _jsString(result);
      if (text == null || text.isEmpty) return;
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['ok'] == true) {
        pending.complete(decoded['data']);
      }
    } on Object {
      // 页面尚未就绪，等下一次 onLoadStop 或轮询。
    }
  }

  static String? _jsString(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.length >= 2 &&
          trimmed.startsWith('"') &&
          trimmed.endsWith('"')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is String) return decoded;
        } on Object {
          // 不是 JSON 编码的字符串，按原样返回。
        }
      }
      return value;
    }
    return '$value';
  }

  Future<T> _serialize<T>(Future<T> Function() task) {
    final result = _serial.then<T>((_) => task());
    _serial = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Object?> _run(String url, String js) async {
    if (!_supported) return null;
    try {
      await _ensure();
      final controller = _controller;
      if (controller == null) return null;
      final pending = Completer<Object?>();
      _pending = pending;
      _pendingJs = js;
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      final deadline = DateTime.now().add(const Duration(seconds: 22));
      while (!pending.isCompleted && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await _tryExtract(controller);
      }
      final result = pending.isCompleted ? await pending.future : null;
      _pending = null;
      _pendingJs = null;
      return result;
    } on Object {
      _pending = null;
      _pendingJs = null;
      return null;
    }
  }

  static List<Map<String, dynamic>>? _asMapList(Object? data) {
    if (data is! List) return null;
    final out = <Map<String, dynamic>>[];
    for (final value in data) {
      if (value is Map) {
        out.add(value.map((key, item) => MapEntry('$key', item)));
      }
    }
    return out.isEmpty ? null : out;
  }

  /// 起点搜索：返回 `[{name,href,author,intro}]`，失败返回 null。
  Future<List<Map<String, dynamic>>?> fetchSearchResults(String keyword) {
    return _serialize(() async {
      final data = await _run(
        'https://www.qidian.com/so/${Uri.encodeComponent(keyword)}.html',
        _searchJs,
      );
      return _asMapList(data);
    });
  }

  /// 起点目录：返回 `[{t,h}]`（章节标题 + 章节地址），失败返回 null。
  Future<List<Map<String, dynamic>>?> fetchChapterCatalog(String bookId) {
    return _serialize(() async {
      final data = await _run('https://www.qidian.com/book/$bookId/', _catalogJs);
      return _asMapList(data);
    });
  }

  /// 起点正文：返回 `<p>` 段落 HTML；VIP/付费/失败返回 null 或空串，由调用方判定锁定。
  Future<String?> fetchChapterContent(String chapterUrl) {
    return _serialize(() async {
      final data = await _run(chapterUrl, _contentJs);
      return data is String ? data : null;
    });
  }

  Future<void> dispose() async {
    final webView = _webView;
    _webView = null;
    _controller = null;
    _pending = null;
    _pendingJs = null;
    if (webView != null) {
      await webView.dispose();
    }
  }
}
