import 'dart:convert';

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

  bool get supported => type == 0 || type == 3;

  String get exploreUrl => _string('exploreUrl');
  String get searchUrl => _string('searchUrl');
  bool get canExplore => exploreUrl.isNotEmpty && enabledExplore;
  String get loginUrl => _string('loginUrl');
  String get loginUi => _string('loginUi');
  String get loginCheckJs => _string('loginCheckJs');
  bool get needsLogin => loginUrl.isNotEmpty || loginUi.isNotEmpty;
  bool get hasLoginCheck => loginCheckJs.trim().isNotEmpty;

  bool get canSearch {
    return searchUrl.isNotEmpty;
  }

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

  String get label => viewName.isEmpty ? title : viewName;
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
  });

  final Map<String, String> values;
  final String searchKeyword;
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
  });

  final String name;
  final String title;
  final String type;
  final String action;
  final List<String> chars;
  final String defaultValue;

  bool get isPassword => type == 'password';
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
  bool get needsWebLogin => loginUrl.isNotEmpty && fields.isEmpty;
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
