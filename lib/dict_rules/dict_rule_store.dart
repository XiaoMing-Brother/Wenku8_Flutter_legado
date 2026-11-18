import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'dict_rule.dart';
import 'dict_rule_transport.dart';

class DictRuleLookupGroup {
  const DictRuleLookupGroup(this.rule, {this.text = '', this.error});

  final DictRule rule;
  final String text;
  final String? error;
}

class DictRuleImportResult {
  const DictRuleImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
  });

  final int added;
  final int updated;
  final int skipped;
}

/// App-owned online dictionary rule library. Lookup is explicit, never a
/// background request; each enabled rule fails independently.
class DictRuleStore extends ChangeNotifier {
  DictRuleStore({Directory? directory, DictRuleTransport? transport})
    : _directory = directory,
      _transport = transport ?? const DictRuleTransport();

  static final shared = DictRuleStore();
  static const version = 1;
  static const maxRules = 256;

  static const _defaultRules = [
    DictRule(
      name: '汉典',
      urlRule: 'https://www.zdic.net/hans/{{key}}',
      showRule:
          '@js:var doc = org.jsoup.Jsoup.parse(result)\n'
          'doc.select("script,style,svg,button,.section-nav,.dict-section__footer").remove()\n'
          'var node = doc.selectFirst("#jbjs")\n'
          'if (node == null) node = doc.selectFirst("#xxjs")\n'
          'node == null ? "" : node.html()',
      sortNumber: 0,
    ),
    DictRule(
      name: '海词英文',
      urlRule: 'https://apii.dict.cn/mini.php?q={{key}}',
      showRule: 'tag.body@all',
      sortNumber: 1,
    ),
  ];

  Directory? _directory;
  final DictRuleTransport _transport;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  List<DictRule> _rules = const [];
  bool _disposed = false;
  bool _engineAvailable = false;
  int _revision = 0;

  List<DictRule> get rules => List.unmodifiable(_rules);
  bool get engineAvailable => _engineAvailable;
  int get revision => _revision;
  String get signature => '$_revision:${_engineAvailable ? 1 : 0}';

  Future<Directory> _root() async => _directory ??= Directory(
    '${(await getApplicationSupportDirectory()).path}/reader-dict-rules',
  );

  Future<File> _file() async => File('${(await _root()).path}/rules.json');

  Future<void> load() => _loading ??=
      () async {
        final file = await _file();
        if (await file.exists()) {
          if (await file.length() > 16 * 1024 * 1024) {
            throw const FormatException('字典规则记录过大');
          }
          final raw = jsonDecode(await file.readAsString());
          if (raw is! Map ||
              raw['version'] != version ||
              raw['rules'] is! List ||
              (raw['rules'] as List).length > maxRules) {
            throw const FormatException('字典规则记录有误');
          }
          final values = <DictRule>[];
          for (final (index, item) in (raw['rules'] as List).indexed) {
            if (item is! Map) continue;
            final rule = DictRule.fromJson(
              Map<String, dynamic>.from(item),
              index: index,
            );
            if (rule.validationError == null) values.add(rule);
          }
          _rules = _sorted(values);
        } else {
          _rules = _sorted(_defaultRules);
          await _saveNow(_rules);
        }
        _engineAvailable = await _transport.available();
      }().catchError((Object error, StackTrace stack) {
        _loading = null;
        Error.throwWithStackTrace(error, stack);
      });

  static List<DictRule> _sorted(Iterable<DictRule> values) {
    final rules = values.toList()
      ..sort((a, b) {
        final order = a.sortNumber.compareTo(b.sortNumber);
        return order != 0 ? order : a.name.compareTo(b.name);
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

  Future<void> _saveNow(List<DictRule> rules) async {
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

  Future<void> add(DictRule rule) async {
    await load();
    if (_rules.length >= maxRules) {
      throw const FormatException('最多保留 $maxRules 条字典规则');
    }
    final error = rule.validationError;
    if (error != null) throw FormatException(error);
    if (_rules.any((item) => item.name == rule.name.trim())) {
      throw const FormatException('已存在同名字典规则');
    }
    final value = rule.copyWith(
      name: rule.name.trim(),
      sortNumber: _rules.isEmpty ? 0 : _rules.last.sortNumber + 10,
    );
    _rules = _sorted([..._rules, value]);
    await _save();
    _changed();
  }

  Future<void> update(DictRule rule, {String? previousName}) async {
    await load();
    final error = rule.validationError;
    if (error != null) throw FormatException(error);
    final oldName = previousName ?? rule.name;
    final index = _rules.indexWhere((item) => item.name == oldName);
    if (index < 0) throw const FormatException('字典规则已不存在');
    if (rule.name != oldName &&
        _rules.any((item) => item.name == rule.name.trim())) {
      throw const FormatException('已存在同名字典规则');
    }
    final next = List<DictRule>.of(_rules);
    next[index] = rule.copyWith(
      name: rule.name.trim(),
      sortNumber: next[index].sortNumber,
    );
    _rules = _sorted(next);
    await _save();
    _changed();
  }

  Future<void> remove(String name) async {
    await load();
    final next = _rules.where((rule) => rule.name != name).toList();
    if (next.length == _rules.length) return;
    _rules = _sorted(next);
    await _save();
    _changed();
  }

  Future<void> setEnabled(String name, bool enabled) async {
    await load();
    final index = _rules.indexWhere((rule) => rule.name == name);
    if (index < 0 || _rules[index].enabled == enabled) return;
    final next = List<DictRule>.of(_rules);
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
    final next = List<DictRule>.of(_rules);
    final item = next.removeAt(from);
    next.insert(to > from ? to - 1 : to, item);
    _rules = List.unmodifiable([
      for (final (index, rule) in next.indexed)
        rule.copyWith(sortNumber: index * 10),
    ]);
    await _save();
    _changed();
  }

  Future<DictRuleImportResult> importText(String text) async {
    await load();
    final batch = decodeDictRules(text);
    final byName = {for (final rule in _rules) rule.name: rule};
    var added = 0;
    var updated = 0;
    var sort = _rules.isEmpty ? 0 : _rules.last.sortNumber + 10;
    for (final rule in batch.rules) {
      if (byName.containsKey(rule.name)) {
        byName[rule.name] = rule.copyWith(
          sortNumber: byName[rule.name]!.sortNumber,
        );
        updated++;
      } else {
        byName[rule.name] = rule.copyWith(sortNumber: sort);
        sort += 10;
        added++;
      }
    }
    if (byName.length > maxRules) {
      throw const FormatException('字典规则数量超过上限');
    }
    _rules = _sorted(byName.values);
    await _save();
    _changed();
    return DictRuleImportResult(
      added: added,
      updated: updated,
      skipped: batch.skipped,
    );
  }

  String exportJson({Set<String>? names}) => encodeDictRules(
    _rules.where((rule) => names == null || names.contains(rule.name)),
  );

  Future<String> lookup(DictRule rule, String word) async {
    await load();
    if (!_engineAvailable) throw const DictRuleEngineUnavailable();
    return _transport.lookup(rule, word);
  }

  Future<List<DictRuleLookupGroup>> lookupAll(String word) async {
    await load();
    final query = word.trim();
    if (query.isEmpty) return const [];
    if (!_engineAvailable) throw const DictRuleEngineUnavailable();
    final enabled = _rules.where((rule) => rule.enabled).toList();
    return Future.wait([
      for (final rule in enabled)
        () async {
          try {
            final text = await _transport.lookup(rule, query);
            return DictRuleLookupGroup(rule, text: text);
          } catch (error) {
            return DictRuleLookupGroup(rule, error: _message(error));
          }
        }(),
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _message(Object error) => error is FormatException
    ? error.message.toString()
    : error is DictRuleEngineUnavailable
    ? error.toString()
    : '字典规则查询失败，请稍后重试';
