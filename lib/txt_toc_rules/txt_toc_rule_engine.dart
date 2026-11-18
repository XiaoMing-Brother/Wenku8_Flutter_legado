import 'txt_toc_rule.dart';

enum TxtTocHeading { none, volume, chapter }

/// Compiles a Legado Java/Kotlin expression with the small differences that
/// matter for TXT imports. Inline `(?i)` and `(?m)` prefixes are translated to
/// Dart RegExp options; matching is always multi-line and case-insensitive to
/// preserve this app's existing custom-TXT behaviour.
RegExp compileTxtTocRegExp(String source) {
  var pattern = source;
  var caseSensitive = false;
  var multiLine = true;
  var dotAll = false;
  var unicode = false;
  while (true) {
    final flags = RegExp(r'^\(\?([imsux]+)\)').firstMatch(pattern);
    if (flags == null) break;
    final value = flags.group(1)!;
    if (value.contains('i')) caseSensitive = false;
    if (value.contains('m')) multiLine = true;
    if (value.contains('s')) dotAll = true;
    if (value.contains('u')) unicode = true;
    if (value.contains('x')) {
      throw const FormatException('当前引擎不支持 (?x) 扩展空白模式');
    }
    pattern = pattern.substring(flags.end).trimLeft();
  }
  return RegExp(
    pattern,
    caseSensitive: caseSensitive,
    multiLine: multiLine,
    dotAll: dotAll,
    unicode: unicode,
  );
}

class TxtTocCompiledRule {
  TxtTocCompiledRule._(this.chapter, this.volume);

  final RegExp chapter;
  final RegExp? volume;

  factory TxtTocCompiledRule.compile(TxtTocRule rule) => TxtTocCompiledRule._(
    compileTxtTocRegExp(rule.chapterRule),
    rule.volumeRule.trim().isEmpty
        ? null
        : compileTxtTocRegExp(rule.volumeRule),
  );

  /// The leading newline gives look-behind rules the same line boundary they
  /// would see while Legado scans a complete file.
  TxtTocHeading classify(String line) {
    final displayLength = line.trim().length;
    if (displayLength == 0 || displayLength > 90) return TxtTocHeading.none;
    final candidate = '\n$line';
    final volumePattern = volume;
    if (volumePattern != null) {
      final contentStart = 1 + line.length - line.trimLeft().length;
      if (volumePattern
          .allMatches(candidate)
          .any((match) => match.start <= contentStart)) {
        return TxtTocHeading.volume;
      }
    }
    return chapter.hasMatch(candidate)
        ? TxtTocHeading.chapter
        : TxtTocHeading.none;
  }
}

String? txtTocRulePatternError(TxtTocRule rule) {
  try {
    TxtTocCompiledRule.compile(rule);
  } on FormatException catch (error) {
    final message = error.message.toString().trim();
    return message.isEmpty ? '表达式不受当前正则引擎支持' : '表达式不受当前正则引擎支持：$message';
  }
  return null;
}

List<({int index, String text, TxtTocHeading heading})> testTxtTocRule(
  TxtTocRule rule,
  String sample,
) {
  final compiled = TxtTocCompiledRule.compile(rule);
  final lines = sample
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final result = <({int index, String text, TxtTocHeading heading})>[];
  for (final (index, line) in lines.indexed) {
    final heading = compiled.classify(line);
    if (heading != TxtTocHeading.none) {
      result.add((index: index + 1, text: line.trim(), heading: heading));
    }
  }
  return result;
}

/// Legado's heuristic: require at least two chapter-like matches and ignore
/// matches less than 1000 characters apart. This prevents a rule that matches
/// every line from beating a real chapter pattern. Ties prefer the lower
/// `serialNumber`.
TxtTocRule? selectTxtTocRule(
  Iterable<TxtTocRule> rules,
  String sample, {
  int minChapterMatches = 2,
  int minGap = 1000,
}) {
  final candidates = rules.where((rule) => rule.enabled).toList()
    ..sort((a, b) {
      final order = a.serialNumber.compareTo(b.serialNumber);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  var maxMatches = minChapterMatches;
  TxtTocRule? best;
  for (final rule in candidates.reversed) {
    final RegExp chapter;
    try {
      chapter = compileTxtTocRegExp(rule.chapterRule);
    } on FormatException {
      continue;
    }
    final matches = countTxtTocChapterMatches(
      chapter,
      '\n$sample',
      minGap: minGap,
    );
    if (matches >= maxMatches) {
      maxMatches = matches;
      best = rule;
    }
  }
  return best;
}

int countTxtTocChapterMatches(
  RegExp chapter,
  String sample, {
  int minGap = 1000,
}) {
  var start = 0;
  var count = 0;
  for (final match in chapter.allMatches(sample)) {
    if (match.start == match.end) continue;
    if (start == 0 || match.start - start > minGap) {
      count++;
      start = match.end;
    }
  }
  return count;
}
