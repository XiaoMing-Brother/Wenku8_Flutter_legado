/// 章节标题的「章号 / 章名」拆分与纯化（对标 RM 阅读页标题：小章号 + 大章名）。
///
/// 纯 Dart，无 Flutter 依赖，便于单测与各渲染层复用。
///
/// 目标：把各种来源的章节标题拆成 `label`（如“第1章”“第1话”“Chapter 3”）
/// 与 `name`（如“穿越者”），并剥掉盗版站常见的前缀/书名/作者/校对版等元信息，
/// 让正文标题只显示作者真正想表达的章名。
library;

class ReaderChapterTitleParts {
  const ReaderChapterTitleParts({required this.label, required this.name});

  /// 章节号，如“第1章”“第1话”“Chapter 3”；无法识别时为空串。
  final String label;

  /// 章名（不含章号与站点元信息）；为空表示这条标题没有可用的章名。
  final String name;

  bool get hasLabel => label.isNotEmpty;
  bool get hasName => name.isNotEmpty;

  @override
  String toString() => 'ReaderChapterTitleParts(label: $label, name: $name)';
}

final _labelPatterns = <RegExp>[
  RegExp(r'^第\s*[〇零一二三四五六七八九十百千万萬两兩0-9０-９]+\s*[章节節回卷部篇话話幕社集]'),
  RegExp(r'^(?:chapter|volume|part|book)\s+[0-9ivxlcdm]+', caseSensitive: false),
];

// 书名号 / 各种括号（含校对版全本之类的括号备注）。
final _bracketMeta = RegExp(r'《[^》]*》|（[^）]*）|\([^)]*\)|【[^】]*】|「[^」]*」');
final _authorTail = RegExp(r'作者\s*[:：].*$');
final _leadingJunk = RegExp(r'^[\s·・:：\-—–、,，。.;；|/]+');
final _spaces = RegExp(r'[\s\u00a0\u3000\ufeff]+');

/// 拆分章节标题。不会抛异常，任何输入都返回结构（可能 label/name 皆为空）。
ReaderChapterTitleParts splitReaderChapterTitle(String raw) {
  final text = raw.replaceAll(_spaces, ' ').trim();
  if (text.isEmpty) {
    return const ReaderChapterTitleParts(label: '', name: '');
  }
  var label = '';
  var rest = text;
  for (final pattern in _labelPatterns) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      label = match.group(0)!.trim();
      rest = text.substring(match.end);
      break;
    }
  }
  rest = rest.replaceFirst(_leadingJunk, '');
  // 剥掉书名/括号备注/作者尾巴，再清理残留分隔符。
  var name = rest
      .replaceAll(_bracketMeta, '')
      .replaceAll(_authorTail, '')
      .replaceFirst(_leadingJunk, '')
      .replaceAll(_spaces, ' ')
      .trim();
  return ReaderChapterTitleParts(label: label, name: name);
}

/// 阅读页“大标题”应显示的文本：优先用章名；没有章名时回退到 [fallback]。
String readerChapterDisplayName(String raw, String fallback) {
  final parts = splitReaderChapterTitle(raw);
  return parts.hasName ? parts.name : fallback;
}

/// 阅读页“小章号”应显示的文本：优先用真实章号；没有时回退到 [fallback]。
String readerChapterLabel(String raw, String fallback) {
  final parts = splitReaderChapterTitle(raw);
  return parts.hasLabel ? parts.label : fallback;
}

/// 页眉左侧固定信息：「第几章 章节名」。
/// 例：`第1章 穿越者`；无章名时只留章号，无章号时回退原文。
String readerChapterHeadingText(String raw) {
  final parts = splitReaderChapterTitle(raw);
  if (parts.hasLabel && parts.hasName) return '${parts.label} ${parts.name}';
  if (parts.hasName) return parts.name;
  if (parts.hasLabel) return parts.label;
  return raw.trim();
}

/// 是否为「前言/序章/番外」等无编号章节，避免再补一个假的“第 N 章”。
bool readerIsSectionTitle(String raw) => RegExp(
  r'^(前言|序章|序言|楔子|引子|后记|後記|尾声|尾聲|番外|完本感言|感言)',
).hasMatch(raw.trim());

/// 页脚中间固定信息：「书名」。去掉盗版站附带的《》、（校对版全本）、作者等。
String readerBookDisplayName(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return text;
  final titled = RegExp(r'《([^》]*)》').firstMatch(text)?.group(1)?.trim();
  if (titled != null && titled.isNotEmpty) return titled;
  final cleaned = text
      .replaceAll(RegExp(r'（[^）]*）|\([^)]*\)|【[^】]*】'), '')
      .replaceAll(RegExp(r'作者\s*[:：].*$'), '')
      .replaceAll(RegExp(r'校对版全本|精校版?全本|全本$'), '')
      .trim();
  return cleaned.isEmpty ? text : cleaned;
}
