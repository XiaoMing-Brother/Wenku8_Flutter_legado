import 'replace_rule.dart';

/// Applies ordered replacement rules to chapter titles and body text.
///
/// Supported replacement tokens are `$0`/`$&` (whole match), `$1`…`$99`
/// (capture groups) and `$$` (a literal dollar sign). Legado's `@js:`
/// replacement scripts are intentionally not executed on the Flutter side.
class ReplaceRuleEngine {
  const ReplaceRuleEngine._();

  static bool inScope(
    ReplaceRule rule, {
    required String bookTitle,
    required String origin,
  }) {
    final scope = rule.scope.trim().toLowerCase();
    final exclude = rule.excludeScope.trim().toLowerCase();
    final title = bookTitle.trim().toLowerCase();
    final source = origin.trim().toLowerCase();
    if (exclude.isNotEmpty &&
        (exclude.contains(title) ||
            source.isNotEmpty && exclude.contains(source))) {
      return false;
    }
    if (scope.isEmpty) return true;
    return scope.contains(title) || source.isNotEmpty && scope.contains(source);
  }

  static String applyContent(
    String text,
    Iterable<ReplaceRule> rules, {
    required String bookTitle,
    required String origin,
  }) {
    var value = text;
    for (final rule in rules) {
      if (!rule.enabled ||
          !rule.scopeContent ||
          !inScope(rule, bookTitle: bookTitle, origin: origin)) {
        continue;
      }
      value = _apply(value, rule);
      if (value.isEmpty) break;
    }
    return value;
  }

  static String applyTitle(
    String title,
    Iterable<ReplaceRule> rules, {
    required String bookTitle,
    required String origin,
  }) {
    var value = title;
    for (final rule in rules) {
      if (!rule.enabled ||
          !rule.scopeTitle ||
          !inScope(rule, bookTitle: bookTitle, origin: origin)) {
        continue;
      }
      final next = _apply(value, rule);
      if (next.trim().isNotEmpty) value = next;
    }
    return value;
  }

  static String _apply(String text, ReplaceRule rule) {
    if (rule.pattern.isEmpty || rule.hasUnsupportedScriptReplacement) {
      return text;
    }
    if (!rule.regex) {
      return text.replaceAll(rule.pattern, rule.replacement);
    }
    final RegExp expression;
    try {
      expression = RegExp(rule.pattern, multiLine: true);
    } on FormatException {
      return text;
    }
    try {
      return text.replaceAllMapped(
        expression,
        (match) => _expandReplacement(rule.replacement, match),
      );
    } on Object {
      return text;
    }
  }

  static String _expandReplacement(String template, Match match) {
    final result = StringBuffer();
    var index = 0;
    while (index < template.length) {
      final char = template[index];
      if (char != r'$') {
        result.write(char);
        index++;
        continue;
      }
      if (index + 1 >= template.length) {
        result.write(r'$');
        break;
      }
      final next = template[index + 1];
      if (next == r'$') {
        result.write(r'$');
        index += 2;
        continue;
      }
      if (next == '&') {
        result.write(match.group(0) ?? '');
        index += 2;
        continue;
      }
      final braced = next == '{';
      final start = braced ? index + 2 : index + 1;
      var end = start;
      while (end < template.length &&
          template.codeUnitAt(end) >= 0x30 &&
          template.codeUnitAt(end) <= 0x39) {
        end++;
      }
      if (end == start ||
          (braced && (end >= template.length || template[end] != '}'))) {
        result.write(r'$');
        index++;
        continue;
      }
      final groupIndex = int.tryParse(template.substring(start, end));
      if (groupIndex == null || groupIndex >= match.groupCount + 1) {
        result.write(template.substring(index, braced ? end + 1 : end));
      } else {
        result.write(match.group(groupIndex) ?? '');
      }
      index = braced ? end + 1 : end;
    }
    return result.toString();
  }
}
