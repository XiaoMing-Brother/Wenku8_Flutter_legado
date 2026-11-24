import 'dart:convert';

import 'review_rule.dart';

/// An imported Legado book source.
///
/// [raw] is authoritative. Known getters are views over it so unknown fields
/// survive import/export and future Legado additions do not get discarded.
class BookSource {
  BookSource(Map<String, dynamic> raw)
    : raw = Map<String, dynamic>.unmodifiable(raw);

  final Map<String, dynamic> raw;

  String get key => _string('bookSourceUrl');
  String get name {
    final value = _string('bookSourceName');
    return value.isEmpty ? key : value;
  }

  String get group => _string('bookSourceGroup');

  List<String> get groups {
    final value = group;
    if (value.isEmpty) return const [];
    return List.unmodifiable(
      value
          .split(RegExp(r'[,;，；]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet(),
    );
  }

  int get type {
    final value = raw['bookSourceType'];
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  int get lastUpdateTime => _int('lastUpdateTime') ?? 0;
  int get customOrder => _int('customOrder') ?? 0;

  bool get enabled => _bool('enabled', fallback: true);
  bool get enabledExplore => _bool('enabledExplore', fallback: true);

  Map? _ruleGroup(String field) {
    var content = raw[field];
    if (content is String) {
      try {
        content = jsonDecode(content);
      } on FormatException {
        return null;
      }
    }
    return content is Map ? content : null;
  }

  int get resourceType =>
      type == 3 &&
          '${_ruleGroup('ruleBookInfo')?['downloadUrls'] ?? ''}'
              .trim()
              .isNotEmpty
      ? 3
      : (type == 1 || type == 4 ? type : 0);

  bool get supported {
    if (type == 0 || type == 3) return true;
    final content = _ruleGroup('ruleContent');
    if (type == 1 || type == 4) {
      return '${content?['content'] ?? ''}'.trim().isNotEmpty;
    }
    return type == 2 &&
        content != null &&
        '${content['content'] ?? ''}'.trim().isNotEmpty &&
        '${content['imageDecode'] ?? ''}'.trim().isEmpty;
  }

  String get exploreUrl => _string('exploreUrl');
  String get searchUrl => _string('searchUrl');
  String checkKeyword(String fallback) {
    final value = _ruleGroup('ruleSearch')?['checkKeyWord'];
    if (value is! String ||
        value.trim().isEmpty ||
        ['http', '::', '++', '--'].any(value.contains)) {
      return fallback.trim();
    }
    return value.trim();
  }

  bool get canExplore => exploreUrl.isNotEmpty && enabledExplore;

  /// 旧版发现源的兼容标记：为 true 时榜单点击只跨书源搜索，不直接进详情。
  bool get discoveryOnly => _bool('wenkuDiscoveryOnly', fallback: false);
  String get loginUrl => _string('loginUrl');
  String get loginUi => _string('loginUi');
  String get loginCheckJs => _string('loginCheckJs');
  bool get needsLogin {
    if (loginUrl.isNotEmpty) return true;
    final value = loginUi.trim();
    return value.isNotEmpty &&
        value != '[]' &&
        value != '{}' &&
        value.toLowerCase() != 'null';
  }

  bool get hasLoginCheck => loginCheckJs.trim().isNotEmpty;

  bool get canSearch {
    return searchUrl.isNotEmpty;
  }

  /// 段评规则（Legado `ruleReview`；兼容 `reviewRule` 键，值可为对象或 JSON 字符串）。
  ReviewRule get reviewRule =>
      ReviewRule.fromMap(raw['ruleReview'] ?? raw['reviewRule']);

  /// 该源是否配置了段评地址。
  bool get hasReviewRule => reviewRule.isConfigured;

  String get typeLabel => switch (type) {
    0 => '文字',
    1 => '音频',
    2 => '图片',
    3 => '文件',
    4 => '视频',
    _ => '未知',
  };

  String _string(String key) {
    final value = raw[key];
    return value is String ? value.trim() : '';
  }

  bool _bool(String key, {required bool fallback}) {
    final value = raw[key];
    if (value == null) return fallback;
    if (value is bool) return value;
    return '$value'.toLowerCase() == 'true' || '$value' == '1';
  }

  int? _int(String key) {
    final value = raw[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  BookSource withEnabled(bool value) {
    final copy = Map<String, dynamic>.from(raw);
    copy['enabled'] = value;
    return BookSource(copy);
  }

  BookSource withEdits({
    String? name,
    Iterable<String>? groups,
    String? searchUrl,
    String? exploreUrl,
    bool? enabled,
    bool? enabledExplore,
  }) {
    final copy = Map<String, dynamic>.from(raw);
    if (name != null) {
      final value = name.trim();
      if (value.isEmpty) {
        copy.remove('bookSourceName');
      } else {
        copy['bookSourceName'] = value;
      }
    }
    if (groups != null) {
      final values = {
        for (final value in groups)
          if (value.trim().isNotEmpty) value.trim(),
      };
      if (values.isEmpty) {
        copy.remove('bookSourceGroup');
      } else {
        copy['bookSourceGroup'] = values.join(',');
      }
    }
    if (searchUrl != null) {
      final value = searchUrl.trim();
      if (value.isEmpty) {
        copy.remove('searchUrl');
      } else {
        copy['searchUrl'] = value;
      }
    }
    if (exploreUrl != null) {
      final value = exploreUrl.trim();
      if (value.isEmpty) {
        copy.remove('exploreUrl');
      } else {
        copy['exploreUrl'] = value;
      }
    }
    if (enabled != null) copy['enabled'] = enabled;
    if (enabledExplore != null) copy['enabledExplore'] = enabledExplore;
    return BookSource(copy);
  }

  BookSource withGroups(Iterable<String> values) {
    return withEdits(groups: values);
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(raw);

  static const editableRules = [
    'ruleSearch',
    'ruleExplore',
    'ruleBookInfo',
    'ruleToc',
    'ruleContent',
  ];

  String get ruleDocument => const JsonEncoder.withIndent('  ').convert({
    for (final field in editableRules)
      if (raw.containsKey(field)) field: raw[field],
  });

  BookSource withRuleDocument(String text) {
    final document = jsonDecode(text);
    if (document is! Map<String, dynamic>) {
      throw const FormatException('规则必须是 JSON 对象');
    }
    final copy = toJson();
    for (final entry in document.entries) {
      if (!editableRules.contains(entry.key)) {
        throw FormatException('不是可编辑的规则组：${entry.key}');
      }
      final value = entry.value;
      if (value == null) {
        copy.remove(entry.key);
      } else {
        if (value != raw[entry.key] &&
            value is! Map &&
            !(value is String && jsonDecode(value) is Map)) {
          throw FormatException('${entry.key} 必须是对象、对象的 JSON 字符串或 null');
        }
        copy[entry.key] = value;
      }
    }
    return BookSource(copy);
  }

  static BookSource? tryParse(Object? value) {
    if (value is! Map) return null;
    try {
      final json = <String, dynamic>{
        for (final entry in value.entries) '${entry.key}': entry.value,
      };
      final source = BookSource(json);
      if (source.key.isEmpty ||
          source.key.length > 4096 ||
          source.name.length > 500) {
        return null;
      }
      return source;
    } on Object {
      return null;
    }
  }
}

class BookSourceExploreKind {
  const BookSourceExploreKind({
    required this.title,
    this.url = '',
    this.type = '',
    this.action = '',
    this.viewName = '',
    this.chars = const [],
    this.defaultValue = '',
    this.basisPercent = -1,
    this.flexGrow = 0,
    this.wrapBefore = false,
  });

  final String title;
  final String url;
  final String type;
  final String action;
  final String viewName;
  final List<String> chars;
  final String defaultValue;
  final double basisPercent;
  final double flexGrow;
  final bool wrapBefore;

  String get label {
    final value = viewName.trim();
    if (value.isEmpty) return title;
    if (value.length >= 3 &&
        value.length <= 19 &&
        value.startsWith("'") &&
        value.endsWith("'")) {
      return value.substring(1, value.length - 1);
    }
    // viewName 可以是 JS 表达式；Flutter 侧不执行脚本，退回标题比展示源码更可读。
    if (value.contains('infoMap') || RegExp(r'[(){}\[\]=+;]').hasMatch(value)) {
      return title;
    }
    return value;
  }

  bool get isError =>
      title.toLowerCase().startsWith('error:') ||
      url.toLowerCase().contains('exception');
  bool get opensBooks =>
      (type.isEmpty || type == 'url') && url.isNotEmpty && action.isEmpty;
  bool get isText => type == 'text';
  bool get isSelect => type == 'select';
  bool get isToggle => type == 'toggle';
  bool get isButton => type == 'button';
  bool get isHeading => isButton && action.isEmpty && basisPercent >= 1;

  factory BookSourceExploreKind.fromMap(Map<String, Object?> value) =>
      BookSourceExploreKind(
        title: '${value['title'] ?? ''}'.trim(),
        url: '${value['url'] ?? ''}'.trim(),
        type: '${value['type'] ?? ''}'.trim(),
        action: '${value['action'] ?? ''}'.trim(),
        viewName: '${value['viewName'] ?? ''}'.trim(),
        chars: switch (value['chars']) {
          final List items => [
            for (final item in items)
              if (item != null) '$item',
          ],
          _ => const [],
        },
        defaultValue: '${value['default'] ?? ''}'.trim(),
        basisPercent: _number(value['basisPercent'], -1),
        flexGrow: _number(value['flexGrow'], 0),
        wrapBefore: value['wrapBefore'] == true,
      );

  static double _number(Object? value, double fallback) => switch (value) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text.trim()) ?? fallback,
    _ => fallback,
  };
}

class BookSourceExploreAction {
  const BookSourceExploreAction({
    required this.values,
    required this.searchKeyword,
    this.searchRequested = false,
    this.refreshRequested = false,
    this.loginRequested = false,
    this.openUrl = '',
    this.message = '',
  });

  final Map<String, String> values;
  final String searchKeyword;
  final bool searchRequested;
  final bool refreshRequested;
  final bool loginRequested;
  final String openUrl;
  final String message;
}

class BookSourceLoginAction {
  const BookSourceLoginAction({this.openUrl = '', this.message = ''});

  final String openUrl;
  final String message;
}

class BookSourceBatch {
  const BookSourceBatch(this.sources, {this.skipped = 0});
  final List<BookSource> sources;
  final int skipped;
}

/// One row of a Legado `loginUi` form.
class BookSourceLoginField {
  const BookSourceLoginField({
    required this.name,
    required this.title,
    this.type = 'text',
    this.action = '',
    this.chars = const [],
    this.defaultValue = '',
    this.basisPercent = -1,
    this.flexGrow = 0,
    this.wrapBefore = false,
  });

  final String name;
  final String title;
  final String type;
  final String action;
  final List<String> chars;
  final String defaultValue;
  final double basisPercent;
  final double flexGrow;
  final bool wrapBefore;

  bool get isPassword => type == 'password';
  bool get isText => type.isEmpty || type == 'text';
  bool get isSelect => type == 'select';
  bool get isToggle => type == 'toggle';
  bool get isButton => type == 'button';

  factory BookSourceLoginField.fromMap(Map<String, Object?> value) =>
      BookSourceLoginField(
        name: '${value['name'] ?? ''}'.trim(),
        title: '${value['title'] ?? ''}'.trim(),
        type: '${value['type'] ?? 'text'}'.trim(),
        action: '${value['action'] ?? ''}'.trim(),
        chars: switch (value['chars']) {
          final List items => [
            for (final item in items)
              if (item != null) '$item',
          ],
          _ => const [],
        },
        defaultValue: '${value['default'] ?? ''}'.trim(),
        basisPercent: switch (value['basisPercent']) {
          final num number => number.toDouble(),
          final String text => double.tryParse(text.trim()) ?? -1,
          _ => -1,
        },
        flexGrow: switch (value['flexGrow']) {
          final num number => number.toDouble(),
          final String text => double.tryParse(text.trim()) ?? 0,
          _ => 0,
        },
        wrapBefore: value['wrapBefore'] == true,
      );
}

/// Login form and credential state reported by the native engine.
class BookSourceLoginState {
  const BookSourceLoginState({
    this.fields = const [],
    this.values = const {},
    this.loginUrl = '',
    this.loginCheckJs = '',
    this.hasLoginHeader = false,
    this.hasCookie = false,
    this.checked = false,
    this.checkedUrl = '',
  });

  final List<BookSourceLoginField> fields;
  final Map<String, String> values;
  final String loginUrl;
  final String loginCheckJs;
  final bool hasLoginHeader;
  final bool hasCookie;
  final bool checked;
  final String checkedUrl;

  bool get loggedIn => hasLoginHeader || hasCookie;
  bool get hasWebLoginUrl {
    final url = loginUrl.trim().toLowerCase();
    return url.startsWith('http://') || url.startsWith('https://');
  }

  bool get needsWebLogin {
    if (fields.isNotEmpty) return false;
    final url = loginUrl.trim().toLowerCase();
    return hasWebLoginUrl || url.startsWith('@js:') || url.startsWith('<js>');
  }

  bool get hasLoginCheck => loginCheckJs.trim().isNotEmpty;

  factory BookSourceLoginState.fromMap(Map<String, Object?> value) {
    final rows = value['loginUi'];
    final rawValues = value['values'];
    return BookSourceLoginState(
      fields: rows is List
          ? [
              for (final row in rows)
                if (row is Map && '${row['name'] ?? ''}'.trim().isNotEmpty)
                  BookSourceLoginField.fromMap({
                    for (final entry in row.entries)
                      '${entry.key}': entry.value,
                  }),
            ]
          : const [],
      values: rawValues is Map
          ? {
              for (final entry in rawValues.entries)
                if (entry.key is String && entry.value != null)
                  entry.key as String: '${entry.value}',
            }
          : const {},
      loginUrl: '${value['loginUrl'] ?? ''}'.trim(),
      loginCheckJs: '${value['loginCheckJs'] ?? ''}'.trim(),
      hasLoginHeader: value['hasLoginHeader'] == true,
      hasCookie: value['hasCookie'] == true,
      checked: value['checked'] == true,
      checkedUrl: '${value['checkedUrl'] ?? ''}'.trim(),
    );
  }
}

/// Accepts a single source object, an exported array, or a wrapper containing
/// `sources`/`bookSources`. Duplicate `bookSourceUrl` values keep the last one.
BookSourceBatch decodeBookSources(String text) {
  if (text.trim().isEmpty) {
    throw const FormatException('书源内容为空');
  }
  if (text.length > 128 * 1024 * 1024) {
    throw const FormatException('书源文件超过 128 MB');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('书源不是有效的 JSON');
  }

  final values = <Object?>[];
  if (decoded is List) {
    values.addAll(decoded);
  } else if (decoded is Map) {
    final nested = decoded['sources'] ?? decoded['bookSources'];
    if (nested is List) {
      values.addAll(nested);
    } else if (decoded.containsKey('bookSourceUrl')) {
      values.add(decoded);
    } else {
      throw const FormatException('未找到书源数组');
    }
  } else {
    throw const FormatException('书源 JSON 必须是对象或数组');
  }

  final byKey = <String, BookSource>{};
  var skipped = 0;
  for (final value in values) {
    final source = BookSource.tryParse(value);
    if (source == null) {
      skipped++;
      continue;
    }
    byKey.remove(source.key);
    byKey[source.key] = source;
  }
  if (byKey.isEmpty) {
    throw const FormatException('没有可导入的书源');
  }
  return BookSourceBatch(
    List<BookSource>.unmodifiable(byKey.values),
    skipped: skipped,
  );
}
