import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'txt_toc_rule.dart';
import 'txt_toc_rule_engine.dart';

class TxtTocRuleImportResult {
  const TxtTocRuleImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
  });

  final int added;
  final int updated;
  final int skipped;
}

/// App-owned TXT directory rule library shared by settings and import flows.
class TxtTocRuleStore extends ChangeNotifier {
  TxtTocRuleStore({Directory? directory}) : _directory = directory;

  static final shared = TxtTocRuleStore();
  static const version = 1;
  static const maxRules = 1000;

  Directory? _directory;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  List<TxtTocRule> _rules = const [];
  bool _disposed = false;
  int _revision = 0;

  List<TxtTocRule> get rules => List.unmodifiable(_rules);
  int get revision => _revision;
  int get enabledCount => _rules.where((rule) => rule.enabled).length;

  Future<Directory> _root() async => _directory ??= Directory(
    '${(await getApplicationSupportDirectory()).path}/reader-txt-toc-rules',
  );

  Future<File> _file() async => File('${(await _root()).path}/rules.json');

  Future<void> load() => _loading ??=
      () async {
        final file = await _file();
        if (await file.exists()) {
          if (await file.length() > 16 * 1024 * 1024) {
            throw const FormatException('TXT 目录规则记录过大');
          }
          final raw = jsonDecode(await file.readAsString());
          if (raw is! Map ||
              raw['version'] != version ||
              raw['rules'] is! List ||
              (raw['rules'] as List).length > maxRules) {
            throw const FormatException('TXT 目录规则记录有误');
          }
          final values = <TxtTocRule>[];
          for (final (index, item) in (raw['rules'] as List).indexed) {
            if (item is! Map) continue;
            final rule = TxtTocRule.fromJson(
              Map<String, dynamic>.from(item),
              index: index,
            );
            if (rule.validationError == null) values.add(rule);
          }
          _rules = _sorted(values);
        } else {
          _rules = _sorted(decodeTxtTocRules(txtTocRuleDefaultsJson).rules);
          await _saveNow(_rules);
        }
      }().catchError((Object error, StackTrace stack) {
        _loading = null;
        Error.throwWithStackTrace(error, stack);
      });

  static List<TxtTocRule> _sorted(Iterable<TxtTocRule> values) {
    final rules = values.toList()
      ..sort((a, b) {
        final order = a.serialNumber.compareTo(b.serialNumber);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    return List.unmodifiable(rules);
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final operation = _writes.then((_) => action());
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _saveNow(List<TxtTocRule> rules) async {
    final root = await _root();
    await root.create(recursive: true);
    final file = File('${root.path}/rules.json');
    final part = File('${file.path}.part');
    final document = jsonEncode({
      'version': version,
      'rules': [for (final rule in rules) rule.toJson()],
    });
    try {
      await part.writeAsString(document, flush: true);
      await part.rename(file.path);
    } finally {
      if (await part.exists()) await part.delete();
    }
  }

  Future<void> _save() => _exclusive(() => _saveNow(_rules));

  void _changed() {
    _revision++;
    if (!_disposed) notifyListeners();
  }

  int _newId() {
    var next = 0;
    for (final rule in _rules) {
      if (rule.id > next) next = rule.id;
    }
    return next + 1;
  }

  String? _ruleError(TxtTocRule rule) =>
      rule.validationError ?? txtTocRulePatternError(rule);

  Future<TxtTocRule> add(TxtTocRule rule) async {
    await load();
    if (_rules.length >= maxRules) {
      throw const FormatException('最多保留 $maxRules 条 TXT 目录规则');
    }
    final error = _ruleError(rule);
    if (error != null) throw FormatException(error);
    final value = rule.copyWith(
      id: rule.id <= 0 ? _newId() : rule.id,
      name: rule.name.trim(),
      serialNumber: _rules.isEmpty ? 0 : _rules.last.serialNumber + 10,
    );
    if (_rules.any((item) => item.id == value.id)) {
      throw const FormatException('TXT 目录规则 ID 已存在');
    }
    _rules = _sorted([..._rules, value]);
    await _save();
    _changed();
    return value;
  }

  Future<void> update(TxtTocRule rule) async {
    await load();
    final error = _ruleError(rule);
    if (error != null) throw FormatException(error);
    final index = _rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) throw const FormatException('TXT 目录规则已不存在');
    final next = List<TxtTocRule>.of(_rules);
    next[index] = rule.copyWith(
      name: rule.name.trim(),
      serialNumber: next[index].serialNumber,
    );
    _rules = _sorted(next);
    await _save();
    _changed();
  }

  Future<void> remove(int id) async {
    await load();
    final next = _rules.where((rule) => rule.id != id).toList();
    if (next.length == _rules.length) return;
    _rules = _sorted(next);
    await _save();
    _changed();
  }

  Future<void> setEnabled(int id, bool enabled) async {
    await load();
    final index = _rules.indexWhere((rule) => rule.id == id);
    if (index < 0 || _rules[index].enabled == enabled) return;
    final next = List<TxtTocRule>.of(_rules);
    next[index] = next[index].copyWith(enabled: enabled);
    _rules = _sorted(next);
    await _save();
    _changed();
  }

  Future<void> reorder(int from, int to) async {
    await load();
    if (from < 0 || from >= _rules.length || to < 0 || to > _rules.length) {
      return;
    }
    final next = List<TxtTocRule>.of(_rules);
    final item = next.removeAt(from);
    next.insert(to > from ? to - 1 : to, item);
    _rules = List.unmodifiable([
      for (final (index, rule) in next.indexed)
        rule.copyWith(serialNumber: index * 10),
    ]);
    await _save();
    _changed();
  }

  Future<TxtTocRuleImportResult> importText(String text) async {
    await load();
    final batch = decodeTxtTocRules(text);
    final byId = {for (final rule in _rules) rule.id: rule};
    var added = 0;
    var updated = 0;
    var serial = _rules.isEmpty ? 0 : _rules.last.serialNumber + 10;
    for (final rule in batch.rules) {
      final id = rule.id;
      final existing = byId[id];
      if (existing != null) {
        byId[id] = rule.copyWith(
          id: id,
          name: rule.name.trim(),
          serialNumber: existing.serialNumber,
        );
        updated++;
      } else {
        byId[id] = rule.copyWith(
          id: id,
          name: rule.name.trim(),
          serialNumber: serial,
        );
        serial += 10;
        added++;
      }
    }
    if (byId.length > maxRules) {
      throw const FormatException('TXT 目录规则数量超过上限');
    }
    _rules = _sorted(byId.values);
    await _save();
    _changed();
    return TxtTocRuleImportResult(
      added: added,
      updated: updated,
      skipped: batch.skipped,
    );
  }

  Future<TxtTocRuleImportResult> importBuiltIn() =>
      importText(txtTocRuleDefaultsJson);

  String exportJson({Set<int>? ids}) => encodeTxtTocRules(
    _rules.where((rule) => ids == null || ids.contains(rule.id)),
  );

  TxtTocRule? findByExpressions(String chapterRule, String volumeRule) {
    for (final rule in _rules) {
      if (rule.chapterRule == chapterRule && rule.volumeRule == volumeRule) {
        return rule;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Built-in rules mirroring Legado's `defaultData/txtTocRule.json`.
const txtTocRuleDefaultsJson = r'''
[
  {
    "id": -1,
    "enable": true,
    "name": "目录(去空白)",
    "chapterRule": "(?<=[　\\s])(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和]))).{0,30}$",
    "volumeRule": "第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:卷|集(?![合和]))",
    "example": "第一章 假装第一章前面有空白但我不要",
    "serialNumber": 0
  },
  {
    "id": -2,
    "enable": true,
    "name": "目录",
    "chapterRule": "^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$",
    "volumeRule": "第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:卷|集(?![合和]))",
    "example": "第一章 标准的粤语就是这样",
    "serialNumber": 1
  },
  {
    "id": -3,
    "enable": false,
    "name": "目录(匹配简介)",
    "chapterRule": "(?<=[　\\s])(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|篇(?!张))).{0,30}$",
    "volumeRule": "第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:卷|集(?![合和]))",
    "example": "简介 老夫诸葛村夫",
    "serialNumber": 2
  },
  {
    "id": -4,
    "enable": false,
    "name": "目录(古典、轻小说备用)",
    "chapterRule": "^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|话|篇(?!张))).{0,30}$",
    "volumeRule": "第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:卷|集(?![合和]))",
    "example": "第一章 比上面只多了回和话",
    "serialNumber": 3
  },
  {
    "id": -5,
    "enable": false,
    "name": "数字(纯数字标题)",
    "chapterRule": "(?<=[　\\s])\\d+\\.?[ 　\\t]{0,4}$",
    "volumeRule": "",
    "example": "12",
    "serialNumber": 4
  },
  {
    "id": -6,
    "enable": false,
    "name": "大写数字(纯数字标题)",
    "chapterRule": "(?<=[　\\s])[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,12}[ 　\\t]{0,4}$",
    "volumeRule": "",
    "example": "一百七十",
    "serialNumber": 5
  },
  {
    "id": -7,
    "enable": false,
    "name": "数字混合(纯数字标题)",
    "chapterRule": "(?<=[　\\s])[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\\d]{1,12}[ 　\\t]{0,4}$",
    "volumeRule": "",
    "example": "12\n一百七十",
    "serialNumber": 6
  },
  {
    "id": -8,
    "enable": true,
    "name": "数字 可选分隔符 标题名称",
    "chapterRule": "^[ 　\\t]{0,4}\\d{1,5}[:：,.， 、_—\\-]?.{1,30}$",
    "volumeRule": "",
    "example": "1、这个就是标题\n02美好的明天",
    "serialNumber": 7
  },
  {
    "id": -9,
    "enable": true,
    "name": "大写数字 分隔符 标题名称",
    "chapterRule": "^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?)[ 、_—\\-].{1,30}$",
    "volumeRule": "",
    "example": "一、只有前面的数字有差别\n二十四章 我瞎编的标题",
    "serialNumber": 8
  },
  {
    "id": -10,
    "enable": false,
    "name": "数字混合 分隔符 标题名称",
    "chapterRule": "^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?[ 、_—\\-]|\\d{1,5}章?[:：,.， 、_—\\-]).{0,30}$",
    "volumeRule": "",
    "example": "1、人参公鸡\n二百二十章 boy next door",
    "serialNumber": 9
  },
  {
    "id": -11,
    "enable": true,
    "name": "正文 标题/序号",
    "chapterRule": "^[ 　\\t]{0,4}正文[ 　]{1,4}.{0,20}$",
    "volumeRule": "",
    "example": "正文 我奶常山赵子龙",
    "serialNumber": 10
  },
  {
    "id": -12,
    "enable": true,
    "name": "Chapter/Section/Part/Episode 序号 标题",
    "chapterRule": "^[ 　\\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO][.、]|[Ee]pisode|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\\s{0,4}\\d{1,4}.{0,30}$",
    "volumeRule": "",
    "example": "Chapter 1 MyGrandmaIsNB",
    "serialNumber": 11
  },
  {
    "id": -13,
    "enable": false,
    "name": "Chapter(去简介)",
    "chapterRule": "^[ 　\\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO]\\.|[Ee]pisode)\\s{0,4}\\d{1,4}.{0,30}$",
    "volumeRule": "",
    "example": "Chapter 1 MyGrandmaIsNB",
    "serialNumber": 12
  },
  {
    "id": -14,
    "enable": true,
    "name": "特殊符号 序号 标题",
    "chapterRule": "(?<=[\\s　])[【〔〖「『〈［\\[](?:第|[Cc]hapter)[\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}[章节].{0,20}$",
    "volumeRule": "",
    "example": "【第一章 后面的符号可以没有",
    "serialNumber": 13
  },
  {
    "id": -15,
    "enable": false,
    "name": "特殊符号 标题(成对)",
    "chapterRule": "(?<=[\\s　]{0,4})(?:[\\[〈「『〖〔《（【\\(].{1,30}[\\)】）》〕〗』」〉\\]]?|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$",
    "volumeRule": "",
    "example": "『加个直角引号更专业』\n(11)我奶常山赵子聋",
    "serialNumber": 14
  },
  {
    "id": -16,
    "enable": true,
    "name": "特殊符号 标题(单个)",
    "chapterRule": "(?<=[\\s　]{0,4})(?:[☆★✦✧].{1,30}|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$",
    "volumeRule": "",
    "example": "☆、晋江作者最喜欢的格式",
    "serialNumber": 15
  },
  {
    "id": -17,
    "enable": true,
    "name": "章/卷 序号 标题",
    "chapterRule": "^[ \\t　]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[卷章][\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ 　]{0,4}.{0,30}$",
    "volumeRule": "",
    "example": "卷五 开源盛世",
    "serialNumber": 16
  },
  {
    "id": -18,
    "enable": false,
    "name": "顶格标题",
    "chapterRule": "^\\S.{1,20}$",
    "volumeRule": "",
    "example": "20字以内顶格写的都是标题",
    "serialNumber": 17
  },
  {
    "id": -19,
    "enable": false,
    "name": "中文顶格标题",
    "chapterRule": "^[一-龟]{1,20}$",
    "volumeRule": "",
    "example": "20字以内顶格写的中文视为标题",
    "serialNumber": 18
  },
  {
    "id": -20,
    "enable": false,
    "name": "双标题(前向)",
    "chapterRule": "(?m)(?<=[ \\t　]{0,4})第[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$(?=[\\s　]{0,8}第[\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章)",
    "volumeRule": "",
    "example": "第一章 真正的标题\n第一章 这个不要",
    "serialNumber": 19
  },
  {
    "id": -21,
    "enable": false,
    "name": "双标题(后向)",
    "chapterRule": "(?m)(?<=[ \\t　]{0,4}第[\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$[\\s　]{0,8})第[\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$",
    "volumeRule": "",
    "example": "第一章 这个标题不要\n第一章真正的标题",
    "serialNumber": 20
  },
  {
    "id": -22,
    "enable": true,
    "name": "书名 括号 序号",
    "chapterRule": "^[一-龥]{1,20}[ 　\\t]{0,4}[(（][\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[)）][ 　\\t]{0,4}$",
    "volumeRule": "",
    "example": "标题后面数字有括号(12)",
    "serialNumber": 21
  },
  {
    "id": -23,
    "enable": true,
    "name": "书名 序号",
    "chapterRule": "^[一-龥]{1,20}[ 　\\t]{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[ 　\\t]{0,4}$",
    "volumeRule": "",
    "example": "标题后面数字没有括号124",
    "serialNumber": 22
  },
  {
    "id": -24,
    "enable": false,
    "name": "特定字符 标题 特定符号",
    "chapterRule": "(?<=\\={3,6}).{1,40}?(?=\\=)",
    "volumeRule": "",
    "example": "===起这种标题干什么===",
    "serialNumber": 23
  },
  {
    "id": -25,
    "enable": true,
    "name": "字数分割 分节阅读",
    "chapterRule": "(?<=[ 　\\t]{0,4})(?:.{0,15}分[页节章段]阅读[-_ ]|第\\s{0,4}[\\d零一二两三四五六七八九十百千万]{1,6}\\s{0,4}[页节]).{0,30}$",
    "volumeRule": "",
    "example": "分节|分页|分段阅读\n第一页",
    "serialNumber": 24
  },
  {
    "id": -26,
    "enable": false,
    "name": "通用规则",
    "chapterRule": "(?im)^.{0,6}(?:[引楔]子|正文(?!完|结)|[引序前]言|[序终]章|扉页|[上中下][部篇卷]|卷首语|后记|尾声|番外|={2,4}|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|页[、 　]|集(?![合和])|部(?![分是门落])|篇(?!张))).{0,40}$|^.{0,6}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟a-z]{1,8}[、. 　].{0,20}$",
    "volumeRule": "",
    "example": "激进规则,适配更多非常用格式",
    "serialNumber": 25
  }
]
''';
