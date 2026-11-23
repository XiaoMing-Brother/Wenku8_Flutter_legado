import 'dart:convert';

/// A Legado-compatible text replacement rule.
///
/// The original Legado fields are kept as their public names so exported JSON
/// can be imported back into Legado without a conversion step.
class ReplaceRule {
  static const unspecifiedOrder = -2147483648;

  const ReplaceRule({
    required this.id,
    required this.name,
    required this.pattern,
    required this.replacement,
    this.group = '',
    this.scope = '',
    this.excludeScope = '',
    this.scopeTitle = false,
    this.scopeContent = true,
    this.enabled = true,
    this.regex = true,
    this.order = 0,
  });

  final String id;
  final String name;
  final String group;
  final String pattern;
  final String replacement;
  final String scope;
  final String excludeScope;
  final bool scopeTitle;
  final bool scopeContent;
  final bool enabled;
  final bool regex;
  final int order;

  String get displayName => name.trim().isEmpty ? pattern : name.trim();

  String get displayGroup => group.trim().isEmpty ? '未分组' : group.trim();

  bool get hasUnsupportedScriptReplacement =>
      replacement.trimLeft().startsWith('@js:');

  bool get validPattern {
    if (pattern.trim().isEmpty) return false;
    if (!regex) return true;
    if (pattern.endsWith('|') && !pattern.endsWith(r'\|')) return false;
    try {
      RegExp(pattern, multiLine: true);
      return true;
    } on FormatException {
      return false;
    }
  }

  String? get validationError {
    if (name.trim().length > 200) return '规则名称过长';
    if (pattern.trim().isEmpty) return '替换内容不能为空';
    if (!validPattern) return '正则表达式无效';
    if (!scopeTitle && !scopeContent) return '请至少选择标题或正文';
    if (hasUnsupportedScriptReplacement) {
      return r'暂不支持 @js: 脚本替换，请改用普通文本或 $1 分组';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'group': group,
    'pattern': pattern,
    'replacement': replacement,
    'scope': scope,
    'excludeScope': excludeScope,
    'scopeTitle': scopeTitle,
    'scopeContent': scopeContent,
    'isEnabled': enabled,
    'isRegex': regex,
    'order': order,
  };

  factory ReplaceRule.fromJson(Map<String, dynamic> json, {int index = 0}) {
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

    int number(String key, int fallback) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? fallback;
    }

    final rawId = json['id'];
    final legacy = json.containsKey('regex') && !json.containsKey('pattern');
    final pattern = legacy ? text('regex') : text('pattern');
    final id = rawId == null || '$rawId'.trim().isEmpty
        ? 'replace-$index-${pattern.hashCode.toRadixString(36)}'
        : '$rawId';
    final replacement = text('replacement');
    final name = legacy ? text('replaceSummary') : text('name');
    final scope = legacy ? text('useTo') : text('scope');
    final enabled = legacy ? flag('enable', false) : flag('isEnabled', true);
    final regex = flag('isRegex', !legacy);
    final order = legacy
        ? number('serialNumber', 0)
        : number('order', unspecifiedOrder);
    final scopeTitle = flag('scopeTitle', false);
    final scopeContent = flag('scopeContent', true);

    return ReplaceRule(
      id: id,
      name: name,
      group: text('group'),
      pattern: pattern,
      replacement: replacement,
      scope: scope,
      excludeScope: text('excludeScope'),
      scopeTitle: scopeTitle,
      scopeContent: scopeContent,
      enabled: enabled,
      regex: regex,
      order: order,
    );
  }

  ReplaceRule copyWith({
    String? id,
    String? name,
    String? group,
    String? pattern,
    String? replacement,
    String? scope,
    String? excludeScope,
    bool? scopeTitle,
    bool? scopeContent,
    bool? enabled,
    bool? regex,
    int? order,
  }) => ReplaceRule(
    id: id ?? this.id,
    name: name ?? this.name,
    group: group ?? this.group,
    pattern: pattern ?? this.pattern,
    replacement: replacement ?? this.replacement,
    scope: scope ?? this.scope,
    excludeScope: excludeScope ?? this.excludeScope,
    scopeTitle: scopeTitle ?? this.scopeTitle,
    scopeContent: scopeContent ?? this.scopeContent,
    enabled: enabled ?? this.enabled,
    regex: regex ?? this.regex,
    order: order ?? this.order,
  );
}

class ReplaceRuleBatch {
  const ReplaceRuleBatch(this.rules, {this.skipped = 0});

  final List<ReplaceRule> rules;
  final int skipped;
}

/// Accepts one rule, an exported array, or a wrapper with `replaceRules`.
ReplaceRuleBatch decodeReplaceRules(String text) {
  if (text.trim().isEmpty) throw const FormatException('替换规则内容为空');
  if (text.length > 16 * 1024 * 1024) {
    throw const FormatException('替换规则文件超过 16 MB');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('替换规则不是有效的 JSON');
  }
  final values = <Object?>[];
  if (decoded is List) {
    values.addAll(decoded);
  } else if (decoded is Map) {
    final nested = decoded['replaceRules'] ?? decoded['rules'];
    if (nested is List) {
      values.addAll(nested);
    } else if (decoded.containsKey('pattern') || decoded.containsKey('regex')) {
      values.add(decoded);
    } else {
      throw const FormatException('未找到替换规则数组');
    }
  } else {
    throw const FormatException('替换规则 JSON 必须是对象或数组');
  }

  final rules = <ReplaceRule>[];
  var skipped = 0;
  for (final (index, value) in values.indexed) {
    if (value is! Map) {
      skipped++;
      continue;
    }
    try {
      final rule = ReplaceRule.fromJson(
        Map<String, dynamic>.from(value),
        index: index,
      );
      if (rule.pattern.trim().isEmpty || !rule.validPattern) {
        skipped++;
        continue;
      }
      rules.add(rule);
    } on Object {
      skipped++;
    }
  }
  if (rules.isEmpty) throw const FormatException('没有可导入的替换规则');
  return ReplaceRuleBatch(List.unmodifiable(rules), skipped: skipped);
}

String encodeReplaceRules(Iterable<ReplaceRule> rules) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert([for (final rule in rules) rule.toJson()]);
