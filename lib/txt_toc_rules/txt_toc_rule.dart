import 'dart:convert';

/// A Legado-compatible TXT table-of-contents rule.
///
/// Field names are kept in their original form so exported JSON can be sent
/// back to Legado without conversion.
class TxtTocRule {
  const TxtTocRule({
    required this.id,
    required this.name,
    required this.chapterRule,
    this.volumeRule = '',
    this.example = '',
    this.serialNumber = 0,
    this.enabled = true,
  });

  final int id;
  final String name;
  final String chapterRule;
  final String volumeRule;
  final String example;
  final int serialNumber;
  final bool enabled;

  String get displayName => name.trim().isEmpty ? chapterRule : name.trim();

  bool get hasVolume => volumeRule.trim().isNotEmpty;

  String? get validationError {
    if (name.trim().isEmpty) return '请填写规则名称';
    if (name.trim().length > 200) return '规则名称过长';
    if (chapterRule.trim().isEmpty) return '请填写章节表达式';
    if (chapterRule.length > 1024 || volumeRule.length > 1024) {
      return '章节和分卷表达式每条最多 1024 个字符';
    }
    return null;
  }

  TxtTocRule copyWith({
    int? id,
    String? name,
    String? chapterRule,
    String? volumeRule,
    String? example,
    int? serialNumber,
    bool? enabled,
  }) => TxtTocRule(
    id: id ?? this.id,
    name: name ?? this.name,
    chapterRule: chapterRule ?? this.chapterRule,
    volumeRule: volumeRule ?? this.volumeRule,
    example: example ?? this.example,
    serialNumber: serialNumber ?? this.serialNumber,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'chapterRule': chapterRule,
    'volumeRule': volumeRule,
    'example': example,
    'serialNumber': serialNumber,
    'enable': enabled,
  };

  factory TxtTocRule.fromJson(Map<String, dynamic> json, {int index = 0}) {
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

    final chapter = text('chapterRule').isEmpty
        ? text('rule')
        : text('chapterRule');
    final id = number('id', 0);
    return TxtTocRule(
      id: id == 0 ? -1000000 - index : id,
      name: text('name'),
      chapterRule: chapter,
      volumeRule: text('volumeRule'),
      example: text('example'),
      serialNumber: number(
        'serialNumber',
        number('sortNumber', number('order', index)),
      ),
      enabled: json.containsKey('enable')
          ? flag('enable', true)
          : flag('enabled', true),
    );
  }
}

class TxtTocRuleBatch {
  const TxtTocRuleBatch(this.rules, {this.skipped = 0});

  final List<TxtTocRule> rules;
  final int skipped;
}

/// Accepts one rule, a Legado array, or a wrapper containing `txtTocRules` or
/// `rules`. Unusable entries are skipped individually.
TxtTocRuleBatch decodeTxtTocRules(String text) {
  if (text.trim().isEmpty) throw const FormatException('TXT 目录规则内容为空');
  if (text.length > 16 * 1024 * 1024) {
    throw const FormatException('TXT 目录规则文件超过 16 MB');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('TXT 目录规则不是有效的 JSON');
  }

  final values = <Object?>[];
  if (decoded is List) {
    values.addAll(decoded);
  } else if (decoded is Map) {
    final nested =
        decoded['txtTocRules'] ?? decoded['rules'] ?? decoded['data'];
    if (nested is List) {
      values.addAll(nested);
    } else if (decoded.containsKey('chapterRule') ||
        decoded.containsKey('rule')) {
      values.add(decoded);
    } else {
      throw const FormatException('未找到 TXT 目录规则数组');
    }
  } else {
    throw const FormatException('TXT 目录规则 JSON 必须是对象或数组');
  }

  final rules = <TxtTocRule>[];
  var skipped = 0;
  for (final (index, value) in values.indexed) {
    if (value is! Map) {
      skipped++;
      continue;
    }
    try {
      final rule = TxtTocRule.fromJson(
        Map<String, dynamic>.from(value),
        index: index,
      );
      if (rule.validationError != null) {
        skipped++;
        continue;
      }
      rules.add(rule);
    } on Object {
      skipped++;
    }
  }
  if (rules.isEmpty) throw const FormatException('没有可导入的 TXT 目录规则');
  return TxtTocRuleBatch(List.unmodifiable(rules), skipped: skipped);
}

String encodeTxtTocRules(Iterable<TxtTocRule> rules) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert([for (final rule in rules) rule.toJson()]);
