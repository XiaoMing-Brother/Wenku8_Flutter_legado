import 'replace_rule.dart';

/// Applies ordered replacement rules to chapter titles and body text.
///
/// Supported replacement tokens are `$0`/`$&` (whole match), `$1`…`$99`
/// (capture groups) and `$$` (a literal dollar sign).
///
/// Legado 净化规则包里大量 `@js:` 替换是“按匹配文本做映射/简单变换”。Flutter 端
/// 没有 JS 运行时，这里内置了这类规则的 Dart 等价实现（见 `_buildJsReplacer`）：
/// 常见写法 `zk = {…}; zk[result]`、`switch(result){case "x":"y"}`、全角转半角、
/// 去换行等都能直接执行；无法识别的脚本仍按原逻辑跳过。
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
    if (rule.pattern.isEmpty) return text;
    final String result;
    if (rule.hasUnsupportedScriptReplacement) {
      final replacer = _jsReplacer(rule);
      if (replacer == null) return text; // 无法识别的 @js 脚本：跳过（不影响正文）
      final RegExp expression;
      try {
        expression = RegExp(rule.pattern, multiLine: true);
      } on FormatException {
        return text;
      }
      try {
        result = text.replaceAllMapped(
          expression,
          (match) => replacer(match.group(0) ?? '') ?? (match.group(0) ?? ''),
        );
      } on Object {
        return text;
      }
    } else if (!rule.regex) {
      result = text.replaceAll(rule.pattern, rule.replacement);
    } else {
      final RegExp expression;
      try {
        expression = RegExp(rule.pattern, multiLine: true);
      } on FormatException {
        return text;
      }
      try {
        result = text.replaceAllMapped(
          expression,
          (match) => _expandReplacement(rule.replacement, match),
        );
      } on Object {
        return text;
      }
    }
    // Dart 的 RegExp 与 Legado(Java) 语义差异很大（\b/\w 为 ASCII、multiline 下
    // $ 逐行匹配、变量长度后行断言等）。一些为 Java 正则编写的净化规则在 Dart 下
    // 会过度匹配：有的把整章正文当噪音删掉（如 #14 净化标点 3271→273 字），有的
    // 反而把正文疯狂放大（如 #02 全角字符 3271→12463 字）。正常净化只删广告/标点，
    // 篇幅应基本不变。这里加安全阀：单条规则若删除超过一半、或放大约 1.3 倍以上，
    // 判定为误匹配，保留原文，继续用后面的规则。
    if (text.length >= 200 &&
        (result.length * 2 < text.length ||
            result.length * 10 > text.length * 13)) {
      return text;
    }
    return result;
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

  // ───────────────────────── 内置 @js 替换的 Dart 等价实现 ─────────────────────────

  static final Map<String, String? Function(String)> _jsReplacerCache = {};
  static final Set<String> _jsReplacerMiss = {};

  static String? Function(String)? _jsReplacer(ReplaceRule rule) {
    if (_jsReplacerCache.containsKey(rule.id)) return _jsReplacerCache[rule.id];
    if (_jsReplacerMiss.contains(rule.id)) return null;
    final fn = _buildJsReplacer(rule);
    if (fn == null) {
      _jsReplacerMiss.add(rule.id);
    } else {
      _jsReplacerCache[rule.id] = fn;
    }
    return fn;
  }

  static String? Function(String)? _buildJsReplacer(ReplaceRule rule) {
    final js = rule.replacement;
    final literal = _parseJsMap(js);
    if (literal != null) return (match) => literal[match] ?? match;
    switch (rule.id) {
      case '1743211343045': // 🌈修正其它符号
        return _fixOtherSymbols;
      case '1619421126360': // 🌈补充换行(下)
        return _supplementNewline;
      case '1727417347231': // 🌈去除引号内汉字之间的换行
        return (m) => m.replaceFirst(RegExp(r'\n\s*'), '');
      case '2': // #02 全角字符#JS
        return (m) => _fw02[m] ?? _fullToHalf(m);
      case '1730564004405': // 🌈引号和换行错误
        return _quoteNewline;
      case '1723710206051': // 🌈修正英语符号
        return _englishSymbols;
      case '1716805642220': // 🌈认定为词语的处理
        return (m) => m.replaceFirst(RegExp(r'\r?\n\s{0,8}|~'), '');
      case '1669956418082': // 🌈全角字符转半角
        return _fullToHalf;
    }
    return null;
  }

  /// 解析 `zk = { … }` 形式或 `switch (result) { case "x":"y"; … }` 形式的映射表。
  static Map<String, String>? _parseJsMap(String js) {
    final map = <String, String>{};
    final block = RegExp(r'zk\s*=\s*\{([\s\S]*?)\}').firstMatch(js);
    if (block != null) {
      final entry = RegExp(
        r'''(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"|([^\s:'"{}]+))\s*:\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
      );
      for (final e in entry.allMatches(block.group(1)!)) {
        final k = _jsUnescape(e.group(1) ?? e.group(2) ?? e.group(3) ?? '');
        final v = _jsUnescape(e.group(4) ?? e.group(5) ?? '');
        if (k.isNotEmpty) map[k] = v;
      }
    } else {
      final cases = RegExp(
        r'''case\s*(['"])((?:(?!\1).)*)\1\s*:\s*(['"])((?:(?!\3).)*)\3''',
      );
      for (final e in cases.allMatches(js)) {
        final k = _jsUnescape(e.group(2) ?? '');
        final v = _jsUnescape(e.group(4) ?? '');
        if (k.isNotEmpty) map[k] = v;
      }
    }
    return map.isEmpty ? null : map;
  }

  static String _jsUnescape(String s) {
    final b = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == r'\' && i + 1 < s.length) {
        final n = s[i + 1];
        switch (n) {
          case 'n':
            b.write('\n');
          case 'r':
            b.write('\r');
          case 't':
            b.write('\t');
          case r'\':
            b.write(r'\');
          case "'":
            b.write("'");
          case '"':
            b.write('"');
          case r'$':
            b.write(r'$');
          default:
            b.write(n);
        }
        i += 2;
      } else {
        b.write(c);
        i++;
      }
    }
    return b.toString();
  }

  static String _fullToHalf(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0xFF01 && r <= 0xFF5E) {
        b.writeCharCode(r - 0xFEE0);
      } else if (r == 0xFFE5) {
        b.write('¥');
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  static String? _fixOtherSymbols(String m) {
    var t = m.replaceFirst(RegExp(r'；$'), '：');
    t = t.replaceFirst(RegExp(r'^.\n.$', multiLine: true), '');
    return t;
  }

  static String? _supplementNewline(String m) {
    if (m.startsWith('：')) return '$m\n';
    var t = m.replaceFirstMapped(
      RegExp(r'([”」].{1,6}[说道问]。)(?![\n他她它“「])(?=[^\n]{9})'),
      (x) => '${x.group(1)}\n',
    );
    t = t.replaceFirst(RegExp(r'[”」][“「]'), '”\n“');
    return t;
  }

  static String? _quoteNewline(String m) {
    if (RegExp(r'^[“"”]').hasMatch(m)) {
      var i = 0;
      return m.replaceAllMapped(RegExp(r'[“"”]'), (x) {
        i++;
        return i == 1 ? '“' : (i == 2 ? '”' : x.group(0)!);
      });
    }
    if (RegExp(r"^['‘’]").hasMatch(m)) {
      var i = 0;
      return m.replaceAllMapped(RegExp(r"['‘’]"), (x) {
        i++;
        return i == 1 ? '‘' : (i == 2 ? '’' : x.group(0)!);
      });
    }
    if (RegExp(r'^\r?\n').hasMatch(m)) return '';
    if (RegExp(r'^[一-ꀀ\d，]').hasMatch(m)) {
      if (RegExp(r'简介|作者|第.{1,6}章|，[男女]，|不[过是]，$').hasMatch(m)) {
        return m;
      }
      return m.replaceFirst(RegExp(r'\n\s*'), '');
    }
    return null;
  }

  static String? _englishSymbols(String m) {
    var t = m.replaceAll(' ', '');
    final re = RegExp(
      r'[:?!。？！…~]|\.{3,7}|\.{1,2}…\.{1,2}|[“"][?!]["”]|[,?!;.:~]',
    );
    t = t.replaceAllMapped(re, (x) => _zkEnglish[x.group(0)!] ?? x.group(0)!);
    return t;
  }

  static const Map<String, String> _zkEnglish = {
    ',': '，', '?': '？', '!': '！', ';': '；', '.': '。', ':': '：', '~': '～',
    ':"': '：“', '?"': '？”', '!"': '！”', '。"': '。”', '？"': '？”', '！"': '！”',
    '…"': '…”', '..."': '…”', '...."': '…”', '....."': '……”', '......"': '……”',
    '...': '…', '....': '…', '.....': '……', '......': '……', '.......': '……',
    '.….': '……', '.…..': '……', '..….': '……', '..…..': '……', '~"': '~”',
    '"?"': '“？”', '“?"': '“？”', '"?”': '“？”', '“?”': '“？”',
    '"!"': '“！”', '“!"': '“！”', '"!”': '“！”', '“!”': '“！”',
  };

  static const Map<String, String> _fw02 = {
    '０': '0', '１': '1', '２': '2', '３': '3', '４': '4', '５': '5', '６': '6',
    '７': '7', '８': '8', '９': '9',
    'Ａ': 'A', 'Ｂ': 'B', 'Ｃ': 'C', 'Ｄ': 'D', 'Ｅ': 'E', 'Ｆ': 'F', 'Ｇ': 'G',
    'Ｈ': 'H', 'Ｉ': 'I', 'Ｊ': 'J', 'Ｋ': 'K', 'Ｌ': 'L', 'Ｍ': 'M', 'Ｎ': 'N',
    'Ｏ': 'O', 'Ｐ': 'P', 'Ｑ': 'Q', 'Ｒ': 'R', 'Ｓ': 'S', 'Ｔ': 'T', 'Ｕ': 'U',
    'Ｖ': 'V', 'Ｗ': 'W', 'Ｘ': 'X', 'Ｙ': 'Y', 'Ｚ': 'Z',
    'ａ': 'a', 'ｂ': 'b', 'ｃ': 'c', 'ｄ': 'd', 'ｅ': 'e', 'ｆ': 'f', 'ｇ': 'g',
    'ｈ': 'h', 'ｉ': 'i', 'ｊ': 'j', 'ｋ': 'k', 'ｌ': 'l', 'ｍ': 'm', 'ｎ': 'n',
    'ｏ': 'o', 'ｐ': 'p', 'ｑ': 'q', 'ｒ': 'r', 'ｓ': 's', 'ｔ': 't', 'ｕ': 'u',
    'ｖ': 'v', 'ｗ': 'w', 'ｘ': 'x', 'ｙ': 'y', 'ｚ': 'z',
    '＜': '<', '／': '/', '＞': '>', '［': '[', '］': ']', '｛': '{', '｝': '}',
    '＋': '+', '＝': '=', '＼': r'\', '＠': '@', '＃': '#', '％': '%', '＆': '&',
    '＄': r'$', '＾': '^', '￥': '¥', '～': '~',
    '(': '（', ')': '）', '､': '、', '｡': '。', '｢': '“', '｣': '”',
    '「': '“', '」': '”', '『': '‘', '』': '’', '．': 'ꔷ', '.': 'ꔷ',
    '∶': '：', '︰': '：',
  };
}
