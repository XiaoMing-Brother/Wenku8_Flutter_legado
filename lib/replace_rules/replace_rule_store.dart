import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../book_identity.dart';
import '../catalog.dart';
import 'replace_rule.dart';
import 'replace_rule_engine.dart';

class ReplaceRuleImportResult {
  const ReplaceRuleImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
  });

  final int added;
  final int updated;
  final int skipped;
  int get total => added + updated;
}

/// App-owned replacement library shared by the reader and settings.
///
/// The global switch only controls whether rules are applied by default.
/// Individual books can override it without rewriting their content cache.
class ReplaceRuleStore extends ChangeNotifier {
  ReplaceRuleStore({Directory? directory}) : _directory = directory;

  static final shared = ReplaceRuleStore();
  static const version = 1;
  static const maxRules = 5000;

  static String originFor(Novel book) =>
      book.source?.sourceKey ?? (isLocalBook(book.id) ? 'loc_book' : '');

  Directory? _directory;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  List<ReplaceRule> _rules = const [];
  bool _enabled = true;
  bool _disposed = false;
  int _revision = 0;

  List<ReplaceRule> get rules => List.unmodifiable(_rules);
  bool get enabled => _enabled;
  int get revision => _revision;
  String get signature => '$_revision:${_enabled ? 1 : 0}';
  List<String> get groups {
    final values =
        _rules
            .map((rule) => rule.group.trim())
            .where((group) => group.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return List.unmodifiable(values);
  }

  Future<Directory> _root() async => _directory ??= Directory(
    '${(await getApplicationSupportDirectory()).path}/reader-replace-rules',
  );

  Future<void> load() => _loading ??=
      () async {
        final file = await _file();
        if (!await file.exists()) return;
        if (await file.length() > 32 * 1024 * 1024) {
          throw const FormatException('替换规则记录过大');
        }
        final raw = jsonDecode(await file.readAsString());
        if (raw is! Map ||
            raw['version'] != version ||
            raw['rules'] is! List ||
            (raw['rules'] as List).length > maxRules) {
          throw const FormatException('替换规则记录有误');
        }
        final rules = <ReplaceRule>[];
        for (final (index, item) in (raw['rules'] as List).indexed) {
          if (item is! Map) continue;
          final rule = ReplaceRule.fromJson(
            Map<String, dynamic>.from(item),
            index: index,
          );
          if (rule.pattern.trim().isNotEmpty) rules.add(rule);
        }
        _rules = _sorted(rules);
        _enabled = raw['enabled'] != false;
      }().catchError((Object error, StackTrace stack) {
        _loading = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final operation = _writes.then((_) => action());
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  static List<ReplaceRule> _sorted(Iterable<ReplaceRule> values) {
    final rules = values.toList();
    mergeSort(
      rules,
      compare: (first, second) => first.order.compareTo(second.order),
    );
    return List.unmodifiable(rules);
  }

  Future<void> _save() => _exclusive(() async {
    final root = await _root();
    await root.create(recursive: true);
    final document = jsonEncode({
      'version': version,
      'enabled': _enabled,
      'rules': [for (final rule in _rules) rule.toJson()],
    });
    final file = File('${root.path}/rules.json');
    final part = File('${file.path}.part');
    try {
      await part.writeAsString(document, flush: true);
      await part.rename(file.path);
    } finally {
      if (await part.exists()) await part.delete();
    }
  });

  Future<File> _file() async => File('${(await _root()).path}/rules.json');

  void _changed() {
    _revision++;
    if (!_disposed) notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    await load();
    if (_enabled == enabled) return;
    _enabled = enabled;
    await _save();
    _changed();
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${Random.secure().nextInt(0x1000000).toRadixString(36)}';

  Future<ReplaceRule> add(ReplaceRule rule) async {
    await load();
    if (_rules.length >= maxRules) {
      throw const FormatException('最多保留 $maxRules 条替换规则');
    }
    final error = rule.validationError;
    if (error != null) throw FormatException(error);
    final value = rule.copyWith(
      id: rule.id.isEmpty ? _newId() : rule.id,
      order: _rules.isEmpty ? 0 : _rules.last.order + 10,
    );
    _rules = _sorted([..._rules, value]);
    await _save();
    _changed();
    return value;
  }

  Future<void> update(ReplaceRule rule) async {
    await load();
    final error = rule.validationError;
    if (error != null) throw FormatException(error);
    final index = _rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) throw const FormatException('替换规则已不存在');
    final next = List<ReplaceRule>.of(_rules);
    next[index] = rule;
    _rules = _sorted(next);
    await _save();
    _changed();
  }

  Future<void> remove(String id) async {
    await load();
    final next = _rules.where((rule) => rule.id != id).toList();
    if (next.length == _rules.length) return;
    _rules = _sorted(next);
    await _save();
    _changed();
  }

  Future<void> setRuleEnabled(String id, bool enabled) async {
    await load();
    final index = _rules.indexWhere((rule) => rule.id == id);
    if (index < 0 || _rules[index].enabled == enabled) return;
    final next = List<ReplaceRule>.of(_rules);
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
    final next = List<ReplaceRule>.of(_rules);
    final item = next.removeAt(from);
    next.insert(to > from ? to - 1 : to, item);
    _rules = List.unmodifiable([
      for (final (index, rule) in next.indexed)
        rule.copyWith(order: index * 10),
    ]);
    await _save();
    _changed();
  }

  Future<ReplaceRuleImportResult> importText(String text) async {
    await load();
    final batch = decodeReplaceRules(text);
    final byId = {for (final rule in _rules) rule.id: rule};
    var added = 0;
    var updated = 0;
    var nextOrder = _rules.isEmpty ? 0 : _rules.last.order + 10;
    for (final rule in batch.rules) {
      if (rule.order != ReplaceRule.unspecifiedOrder && rule.order >= nextOrder) {
        nextOrder = rule.order + 10;
      }
    }
    for (final rule in batch.rules) {
      final previous = byId[rule.id];
      if (previous != null) {
        updated++;
      } else {
        added++;
      }
      if (rule.order == ReplaceRule.unspecifiedOrder) {
        byId[rule.id] = rule.copyWith(order: previous?.order ?? nextOrder);
        if (previous == null) nextOrder += 10;
      } else {
        byId[rule.id] = rule;
      }
    }
    if (byId.length > maxRules) {
      throw const FormatException('替换规则数量超过上限');
    }
    _rules = _sorted(byId.values);
    await _save();
    _changed();
    return ReplaceRuleImportResult(
      added: added,
      updated: updated,
      skipped: batch.skipped,
    );
  }

  String exportJson({Set<String>? ids}) => encodeReplaceRules(
    _rules.where((rule) => ids == null || ids.contains(rule.id)),
  );

  List<ReplaceRule> rulesFor({
    required bool titles,
    required String bookTitle,
    required String origin,
  }) => [
    for (final rule in _rules)
      if (rule.enabled &&
          (titles ? rule.scopeTitle : rule.scopeContent) &&
          ReplaceRuleEngine.inScope(rule, bookTitle: bookTitle, origin: origin))
        rule,
  ];

  String applyContent(
    String text, {
    required String bookTitle,
    required String origin,
  }) => ReplaceRuleEngine.applyContent(
    text,
    _rules,
    bookTitle: bookTitle,
    origin: origin,
  );

  String applyTitle(
    String title, {
    required String bookTitle,
    required String origin,
  }) => ReplaceRuleEngine.applyTitle(
    title,
    _rules,
    bookTitle: bookTitle,
    origin: origin,
  );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
