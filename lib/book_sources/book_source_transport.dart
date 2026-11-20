import 'package:flutter/services.dart';

import 'book_source.dart';

class BookSourceEngineUnavailable implements Exception {
  const BookSourceEngineUnavailable();

  @override
  String toString() => '当前构建未接入 Android 书源引擎';
}

class BookSourceSearchPage {
  const BookSourceSearchPage({required this.items, required this.hasMore});

  final List<Map<String, Object?>> items;
  final bool hasMore;
}

/// Stable boundary to the Android Legado engine. Rule fields are never
/// interpreted on the Flutter side.
class BookSourceTransport {
  const BookSourceTransport({
    this.channel = const MethodChannel('org.mewx.wenku8/book_sources'),
  });

  static const channelName = 'org.mewx.wenku8/book_sources';
  final MethodChannel channel;

  Future<bool> available() async {
    try {
      return await channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> upsertSource(BookSource source) =>
      _invoke<void>('upsertSource', {'source': source.toJson()});

  Future<void> removeSource(String sourceKey) =>
      _invoke<void>('removeSource', {'sourceKey': sourceKey});

  Future<void> cancelSearches() async {
    try {
      await channel.invokeMethod<void>('cancelSearches');
    } on MissingPluginException {
      // Older builds do not expose cancellation; the request timeout still
      // releases their native worker threads.
    } on PlatformException {
      // Cancellation is best-effort and must never block a new search.
    }
  }

  Future<BookSourceSearchPage> search({
    required String sourceKey,
    required String keyword,
    required int page,
  }) async {
    final value = await _invoke<Map<Object?, Object?>>('search', {
      'sourceKey': sourceKey,
      'keyword': keyword,
      'page': page,
    });
    final items = value?['items'];
    return BookSourceSearchPage(
      items: items is List
          ? [
              for (final item in items)
                if (item is Map) _stringMap(item),
            ]
          : const [],
      hasMore: value?['hasMore'] == true,
    );
  }

  Future<List<Map<String, Object?>>> exploreKinds(
    String sourceKey, {
    Map<String, String> values = const {},
  }) async {
    final value = await _invoke<List<Object?>>('exploreKinds', {
      'sourceKey': sourceKey,
      'values': values,
    });
    return [
      for (final item in value ?? const <Object?>[])
        if (item is Map) _stringMap(item),
    ];
  }

  Future<BookSourceSearchPage> explore({
    required String sourceKey,
    required String url,
    required int page,
    String keyword = '',
    Map<String, String> values = const {},
  }) async {
    final value = await _invoke<Map<Object?, Object?>>('explore', {
      'sourceKey': sourceKey,
      'url': url,
      'page': page,
      'keyword': keyword,
      'values': values,
    });
    final items = value?['items'];
    return BookSourceSearchPage(
      items: items is List
          ? [
              for (final item in items)
                if (item is Map) _stringMap(item),
            ]
          : const [],
      hasMore: value?['hasMore'] == true,
    );
  }

  Future<BookSourceExploreAction> exploreAction({
    required String sourceKey,
    required String action,
    Map<String, String> values = const {},
  }) async {
    final value = await _invoke<Map<Object?, Object?>>('exploreAction', {
      'sourceKey': sourceKey,
      'action': action,
      'values': values,
    });
    final rawValues = value?['values'];
    return BookSourceExploreAction(
      values: rawValues is Map ? _stringValues(rawValues) : const {},
      searchKeyword: '${value?['search'] ?? ''}'.trim(),
    );
  }

  Future<Map<String, Object?>?> detail({
    required String sourceKey,
    required String bookUrl,
  }) async {
    final value = await _invoke<Map<Object?, Object?>>('detail', {
      'sourceKey': sourceKey,
      'bookUrl': bookUrl,
    });
    return value == null ? null : _stringMap(value);
  }

  Future<List<Map<String, Object?>>> chapters({
    required String sourceKey,
    required String bookUrl,
    String? tocUrl,
  }) async {
    final value = await _invoke<List<Object?>>('chapters', {
      'sourceKey': sourceKey,
      'bookUrl': bookUrl,
      if (tocUrl != null && tocUrl.isNotEmpty) 'tocUrl': tocUrl,
    });
    return [
      for (final item in value ?? const <Object?>[])
        if (item is Map) _stringMap(item),
    ];
  }

  Future<String?> content({
    required String sourceKey,
    required String bookUrl,
    required String chapterUrl,
    String? nextChapterUrl,
    String? chapterTitle,
  }) => _invoke<String>('content', {
    'sourceKey': sourceKey,
    'bookUrl': bookUrl,
    'chapterUrl': chapterUrl,
    if (nextChapterUrl != null && nextChapterUrl.isNotEmpty)
      'nextChapterUrl': nextChapterUrl,
    if (chapterTitle != null && chapterTitle.isNotEmpty)
      'chapterTitle': chapterTitle,
  });

  /// 抓取本章段评。native 引擎实现 `review` 方法后返回解析好的段评列表；
  /// 未实现（旧构建 / 非 Android）时优雅返回空，不影响阅读。
  Future<List<Map<String, Object?>>> review({
    required String sourceKey,
    required String bookUrl,
    required String chapterUrl,
    Map<String, Object?> rule = const {},
  }) async {
    try {
      final value = await channel.invokeMethod<List<Object?>>('review', {
        'sourceKey': sourceKey,
        'bookUrl': bookUrl,
        'chapterUrl': chapterUrl,
        'rule': rule,
      });
      return [
        for (final item in value ?? const <Object?>[])
          if (item is Map) _stringMap(item),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<Uint8List> image({
    required String sourceKey,
    required String url,
  }) async {
    final value = await _invoke<Uint8List>('fetchImage', {
      'sourceKey': sourceKey,
      'url': url,
    });
    if (value == null || value.isEmpty) {
      throw const FormatException('书源图片为空');
    }
    return value;
  }

  Future<BookSourceLoginState> loginInfo(String sourceKey) async {
    final value = await _invoke<Map<Object?, Object?>>('loginInfo', {
      'sourceKey': sourceKey,
    });
    return _loginState(value);
  }

  Future<BookSourceLoginState> login(
    String sourceKey,
    Map<String, String> values,
  ) async {
    final value = await _invoke<Map<Object?, Object?>>('login', {
      'sourceKey': sourceKey,
      'values': values,
    });
    return _loginState(value);
  }

  Future<BookSourceLoginState> logout(String sourceKey) async {
    final value = await _invoke<Map<Object?, Object?>>('logout', {
      'sourceKey': sourceKey,
    });
    return _loginState(value);
  }

  Future<BookSourceLoginState?> webLogin(String sourceKey) async {
    final value = await _invoke<Map<Object?, Object?>>('webLogin', {
      'sourceKey': sourceKey,
    });
    if (value == null) return null;
    return _loginState(value);
  }

  Future<BookSourceLoginState> checkLogin(String sourceKey) async {
    final value = await _invoke<Map<Object?, Object?>>('checkLogin', {
      'sourceKey': sourceKey,
    });
    return _loginState(value);
  }

  Future<void> loginAction({
    required String sourceKey,
    required String action,
    Map<String, String> values = const {},
  }) => _invoke<void>('loginAction', {
    'sourceKey': sourceKey,
    'action': action,
    'values': values,
  });

  Future<T?> _invoke<T>(String method, Map<String, Object?> arguments) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const BookSourceEngineUnavailable();
    }
  }

  static Map<String, Object?> _stringMap(Map<Object?, Object?> value) => {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };

  static Map<String, String> _stringValues(Map<Object?, Object?> value) => {
    for (final entry in value.entries)
      if (entry.key is String && entry.value != null)
        entry.key as String: '${entry.value}',
  };

  static BookSourceLoginState _loginState(Map<Object?, Object?>? value) =>
      BookSourceLoginState.fromMap(value == null ? const {} : _stringMap(value));
}
