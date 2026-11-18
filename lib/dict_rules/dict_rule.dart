import 'dart:convert';

/// A Legado online dictionary rule.
///
/// `urlRule` supports `{{key}}` placeholders and the same request/rule
/// expressions as book sources. `showRule` extracts the text shown in the
/// reader dictionary sheet; an empty value shows the response body.
class DictRule {
  const DictRule({
    required this.name,
    required this.urlRule,
    this.showRule = '',
    this.enabled = true,
    this.sortNumber = 0,
  });

  final String name;
  final String urlRule;
  final String showRule;
  final bool enabled;
  final int sortNumber;

  String? get validationError {
    if (name.trim().isEmpty) return '字典名称不能为空';
    if (name.trim().length > 120) return '字典名称过长';
    if (urlRule.trim().isEmpty) return '查询地址不能为空';
    if (urlRule.length > 8192) return '查询地址过长';
    if (showRule.length > 65536) return '提取规则过长';
    final uri = Uri.tryParse(
      urlRule.replaceAll(RegExp(r'\{\{[^}]+\}\}'), 'placeholder'),
    );
    if (uri == null || !uri.hasScheme) {
      return '查询地址需要包含 http:// 或 https://';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return '查询地址仅支持 HTTP 或 HTTPS';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'urlRule': urlRule,
    'showRule': showRule,
    'enabled': enabled,
    'sortNumber': sortNumber,
  };

  factory DictRule.fromJson(Map<String, dynamic> json, {int index = 0}) {
    String text(String key) => json[key] is String ? (json[key] as String) : '';
    bool flag(String key, bool fallback) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        return switch (value.trim().toLowerCase()) {
          'true' || '1' => true,
          'false' || '0' => false,
          _ => fallback,
        };
      }
      return fallback;
    }

    int number(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? index;
    }

    return DictRule(
      name: text('name').trim(),
      urlRule: text('urlRule').trim(),
      showRule: text('showRule'),
      enabled: flag('enabled', true),
      sortNumber: number('sortNumber'),
    );
  }

  DictRule copyWith({
    String? name,
    String? urlRule,
    String? showRule,
    bool? enabled,
    int? sortNumber,
  }) => DictRule(
    name: name ?? this.name,
    urlRule: urlRule ?? this.urlRule,
    showRule: showRule ?? this.showRule,
    enabled: enabled ?? this.enabled,
    sortNumber: sortNumber ?? this.sortNumber,
  );
}

class DictRuleBatch {
  const DictRuleBatch(this.rules, {this.skipped = 0});

  final List<DictRule> rules;
  final int skipped;
}

/// Accepts one rule, an exported array, or a wrapper with `dictRules`.
DictRuleBatch decodeDictRules(String text) {
  if (text.trim().isEmpty) throw const FormatException('字典规则内容为空');
  if (text.length > 16 * 1024 * 1024) {
    throw const FormatException('字典规则文件超过 16 MB');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('字典规则不是有效的 JSON');
  }
  final values = <Object?>[];
  if (decoded is List) {
    values.addAll(decoded);
  } else if (decoded is Map) {
    final nested = decoded['dictRules'] ?? decoded['rules'];
    if (nested is List) {
      values.addAll(nested);
    } else if (decoded.containsKey('urlRule')) {
      values.add(decoded);
    } else {
      throw const FormatException('未找到字典规则数组');
    }
  } else {
    throw const FormatException('字典规则 JSON 必须是对象或数组');
  }

  final rules = <DictRule>[];
  var skipped = 0;
  final names = <String>{};
  for (final (index, value) in values.indexed) {
    if (value is! Map) {
      skipped++;
      continue;
    }
    try {
      final rule = DictRule.fromJson(
        Map<String, dynamic>.from(value),
        index: index,
      );
      if (rule.validationError != null || !names.add(rule.name)) {
        skipped++;
        continue;
      }
      rules.add(rule);
    } on Object {
      skipped++;
    }
  }
  if (rules.isEmpty) throw const FormatException('没有可导入的字典规则');
  return DictRuleBatch(List.unmodifiable(rules), skipped: skipped);
}

String encodeDictRules(Iterable<DictRule> rules) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert([for (final rule in rules) rule.toJson()]);
