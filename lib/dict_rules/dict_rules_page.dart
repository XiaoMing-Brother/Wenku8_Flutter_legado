import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_interactions.dart';
import '../app_search_field.dart';
import '../app_ui.dart';
import '../book_documents.dart';
import '../feature_pages.dart';
import 'dict_rule.dart';
import 'dict_rule_store.dart';

class DictRulesPage extends StatefulWidget {
  const DictRulesPage({
    super.key,
    required this.store,
    this.reduceMotion = false,
  });

  final DictRuleStore store;
  final bool reduceMotion;

  @override
  State<DictRulesPage> createState() => _DictRulesPageState();
}

class _DictRulesPageState extends State<DictRulesPage> {
  final _query = TextEditingController();
  bool _loading = true;
  String? _error;

  DictRuleStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _store.load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DictRule> get _visibleRules {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return _store.rules;
    return [
      for (final rule in _store.rules)
        if (rule.name.toLowerCase().contains(query) ||
            rule.urlRule.toLowerCase().contains(query) ||
            rule.showRule.toLowerCase().contains(query))
          rule,
    ];
  }

  Future<void> _edit([DictRule? current]) async {
    final rule = await showJellySheet<DictRule>(
      context: context,
      reduceMotion: widget.reduceMotion,
      heightFactor: .88,
      maxWidth: 720,
      builder: (_) => _DictRuleEditor(rule: current),
    );
    if (!mounted || rule == null) return;
    try {
      if (current == null) {
        await _store.add(rule);
        _feedback('已添加字典规则');
      } else {
        await _store.update(rule, previousName: current.name);
        _feedback('已保存字典规则');
      }
    } catch (error) {
      _feedback(_message(error), error: true);
    }
  }

  Future<void> _delete(DictRule rule) async {
    final confirmed = await confirmNovelAction(
      context,
      title: '删除字典规则？',
      message: '「${rule.name}」将从本机规则库中移除，不影响已导入的离线词典。',
      confirmLabel: '删除字典规则',
      reduceMotion: widget.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    try {
      await _store.remove(rule.name);
      _feedback('已删除字典规则');
    } catch (error) {
      _feedback(_message(error), error: true);
    }
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      _feedback('剪贴板中没有字典规则 JSON', error: true);
      return;
    }
    await _importText(text);
  }

  Future<void> _importFromFile() async {
    final documents = BookDocuments();
    BookDocumentSelection? selected;
    try {
      selected = await documents.pickBookSource();
      if (selected == null || selected.path == null) return;
      final file = File(selected.path!);
      if (await file.length() > 16 * 1024 * 1024) {
        throw const FormatException('字典规则文件超过 16 MB');
      }
      await _importText(utf8.decode(await file.readAsBytes()));
    } catch (error) {
      if (mounted) _feedback(_message(error), error: true);
    } finally {
      if (selected != null) {
        try {
          await documents.releaseBooks([selected]);
        } on Object {
          // The rules are already stored; releasing the document is best effort.
        }
      }
    }
  }

  Future<void> _importText(String text) async {
    try {
      final result = await _store.importText(text);
      if (!mounted) return;
      final skipped = result.skipped > 0 ? ' · 跳过 ${result.skipped}' : '';
      _feedback('新增 ${result.added} · 更新 ${result.updated}$skipped');
    } catch (error) {
      if (mounted) _feedback(_message(error), error: true);
    }
  }

  Future<void> _export() async {
    if (_store.rules.isEmpty) {
      _feedback('还没有可导出的字典规则', error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: _store.exportJson()));
    if (mounted) _feedback('已复制 ${_store.rules.length} 条字典规则');
  }

  Future<void> _test([DictRule? rule]) async {
    await showJellySheet<void>(
      context: context,
      reduceMotion: widget.reduceMotion,
      heightFactor: .78,
      maxWidth: 720,
      builder: (_) => _DictRuleTester(store: _store, initialRule: rule),
    );
  }

  void _feedback(String message, {bool error = false}) {
    if (!mounted) return;
    showNovelFeedback(
      context,
      message,
      haptic: error ? HapticCue.error : null,
      reduceMotion: widget.reduceMotion,
    );
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '字典规则',
    code: 'READER / ONLINE DICTIONARIES',
    actions: [
      GlassMenuAnchor(
        child: Builder(
          builder: (anchor) => GlassIconButton(
            key: const ValueKey('dict-rule-actions'),
            icon: CupertinoIcons.ellipsis,
            label: '字典规则操作',
            onPressed: () => _openActions(anchor),
          ),
        ),
      ),
    ],
    child: AnimatedBuilder(
      animation: _store,
      builder: (context, _) => Padding(
        padding: featurePadding(context).copyWith(bottom: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSearchField(
              inputKey: const ValueKey('dict-rule-search'),
              controller: _query,
              hint: '搜索字典名称、查询地址或提取规则',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            _toolbar(context),
            if (_error != null) FeatureError(_error),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : _visibleRules.isEmpty
                  ? _empty(context)
                  : ReorderableListView.builder(
                      key: const ValueKey('dict-rule-list'),
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + 24,
                      ),
                      itemCount: _visibleRules.length,
                      onReorder: (from, to) => _reorder(from, to),
                      proxyDecorator: (child, _, _) => Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: child,
                      ),
                      itemBuilder: (context, index) =>
                          _ruleTile(context, _visibleRules[index], index),
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _toolbar(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final enabled = _store.rules.where((rule) => rule.enabled).length;
    final status = _store.engineAvailable
        ? '${_store.rules.length} 条规则 · $enabled 条启用 · 选中正文后可在线查询'
        : '${_store.rules.length} 条规则 · 当前构建仅支持离线词典';
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: status,
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reorder(int from, int to) async {
    final visible = _visibleRules;
    if (from < 0 || from >= visible.length) return;
    final moved = visible[from];
    final targetIndex = to > from ? to - 1 : to;
    final target = targetIndex >= visible.length ? null : visible[targetIndex];
    final source = _store.rules.indexWhere((rule) => rule.name == moved.name);
    final destination = target == null
        ? _store.rules.length
        : _store.rules.indexWhere((rule) => rule.name == target.name);
    if (source < 0 || destination < 0) return;
    try {
      await _store.reorder(source, destination);
    } catch (error) {
      _feedback(_message(error), error: true);
    }
  }

  Future<void> _openActions(BuildContext anchor) async {
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: widget.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassMenuItem(
            label: '新建规则',
            icon: CupertinoIcons.add,
            order: 0,
            onPressed: () => Navigator.pop(menu, 'add'),
          ),
          GlassMenuItem(
            label: '从剪贴板导入',
            icon: CupertinoIcons.doc_on_clipboard,
            order: 1,
            onPressed: () => Navigator.pop(menu, 'paste'),
          ),
          GlassMenuItem(
            label: '从文件导入',
            icon: CupertinoIcons.folder,
            order: 2,
            onPressed: () => Navigator.pop(menu, 'file'),
          ),
          GlassMenuItem(
            label: '导出全部规则',
            icon: CupertinoIcons.square_arrow_up,
            order: 3,
            onPressed: () => Navigator.pop(menu, 'export'),
          ),
          GlassMenuItem(
            label: '测试查询',
            icon: CupertinoIcons.play_rectangle,
            order: 4,
            onPressed: () => Navigator.pop(menu, 'test'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'add':
        await _edit();
      case 'paste':
        await _importFromClipboard();
      case 'file':
        await _importFromFile();
      case 'export':
        await _export();
      case 'test':
        await _test();
    }
  }

  Widget _ruleTile(BuildContext context, DictRule rule, int index) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final unsupported = rule.validationError != null;
    final details = [
      rule.urlRule,
      if (rule.showRule.isNotEmpty)
        rule.showRule.startsWith('@js:') ? '脚本提取' : '提取：${rule.showRule}',
    ].join(' · ');
    return Container(
      key: ValueKey(rule.name),
      margin: const EdgeInsets.only(bottom: 14),
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: ContentPanel(
          onTap: () => _edit(rule),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      rule.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
                    Tooltip(
                      message: details,
                      child: AppText(
                        details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: muted,
                        ),
                      ),
                    ),
                    if (unsupported)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          rule.validationError!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              AppControls.toggle(
                context,
                value: rule.enabled,
                liteGlass: true,
                onChanged: (value) async {
                  try {
                    await _store.setEnabled(rule.name, value);
                  } catch (error) {
                    _feedback(_message(error), error: true);
                  }
                },
              ),
              GlassMenuAnchor(
                child: Builder(
                  builder: (anchor) => CompactRowMenuButton(
                    label: '${rule.name} 更多操作',
                    onPressed: () => _openRuleMenu(anchor, rule),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRuleMenu(BuildContext anchor, DictRule rule) async {
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: widget.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassMenuItem(
            label: '测试查询',
            icon: CupertinoIcons.play_rectangle,
            order: 0,
            onPressed: () => Navigator.pop(menu, 'test'),
          ),
          GlassMenuItem(
            label: '编辑规则',
            icon: CupertinoIcons.pencil,
            order: 1,
            onPressed: () => Navigator.pop(menu, 'edit'),
          ),
          GlassMenuItem(
            label: '删除规则',
            icon: CupertinoIcons.trash,
            order: 2,
            onPressed: () => Navigator.pop(menu, 'delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'test':
        await _test(rule);
      case 'edit':
        await _edit(rule);
      case 'delete':
        await _delete(rule);
    }
  }

  Widget _empty(BuildContext context) => _store.rules.isEmpty
      ? ContentNotice(
          icon: CupertinoIcons.book,
          title: appText(context, '还没有字典规则'),
          message: appText(context, '字典规则像书源一样按地址和提取规则在线查词，结果会与离线词典一起显示。'),
          secondaryAction: GlassTextButton(
            compact: true,
            onPressed: _importFromClipboard,
            child: const AppText('从剪贴板导入'),
          ),
        )
      : ContentNotice(
          icon: CupertinoIcons.search,
          title: appText(context, '没有匹配的字典规则'),
          message: appText(context, '调整搜索词后再试。'),
          secondaryAction: GlassTextButton(
            compact: true,
            onPressed: () => setState(() => _query.clear()),
            child: const AppText('清除搜索'),
          ),
        );
}

class _DictRuleEditor extends StatefulWidget {
  const _DictRuleEditor({this.rule});

  final DictRule? rule;

  @override
  State<_DictRuleEditor> createState() => _DictRuleEditorState();
}

class _DictRuleEditorState extends State<_DictRuleEditor> {
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final _url = TextEditingController(text: widget.rule?.urlRule ?? '');
  late final _show = TextEditingController(text: widget.rule?.showRule ?? '');
  late bool _enabled = widget.rule?.enabled ?? true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _show.dispose();
    super.dispose();
  }

  void _save() {
    final rule = DictRule(
      name: _name.text.trim(),
      urlRule: _url.text.trim(),
      showRule: _show.text,
      enabled: _enabled,
      sortNumber: widget.rule?.sortNumber ?? 0,
    );
    final error = rule.validationError;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ArchiveSection(
                title: widget.rule == null ? '新建字典规则' : '编辑字典规则',
                code: 'READER / DICT RULE',
              ),
            ),
            GlassIconButton(
              icon: CupertinoIcons.xmark,
              label: '关闭',
              liveGlass: false,
              transparent: true,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            children: [
              _field('字典名称', _name, hint: '例如：汉典'),
              _field(
                '查询地址',
                _url,
                hint: '例如：https://www.zdic.net/hans/{{key}}',
                maxLines: 4,
              ),
              _field(
                '提取规则',
                _show,
                hint: '留空显示整个响应；支持 CSS、JSONPath、@regex 与 @js 规则',
                maxLines: 10,
              ),
              const AppText(
                '查询地址和提取规则与 Legado 书源规则一致。{{key}} 会替换为选中的词，'
                '高级 JavaScript 规则由 Android 原生引擎执行。',
                style: TextStyle(fontSize: 12, height: 1.65),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: AppText('启用此规则')),
                  AppControls.toggle(
                    context,
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GlassTextButton(
          key: const ValueKey('dict-rule-editor-save'),
          onPressed: _save,
          child: const AppText('保存规则'),
        ),
      ],
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );
}

class _DictRuleTester extends StatefulWidget {
  const _DictRuleTester({required this.store, this.initialRule});

  final DictRuleStore store;
  final DictRule? initialRule;

  @override
  State<_DictRuleTester> createState() => _DictRuleTesterState();
}

class _DictRuleTesterState extends State<_DictRuleTester> {
  final _word = TextEditingController(text: '阅读');
  DictRule? _rule;
  bool _busy = false;
  String? _error;
  String _result = '';

  @override
  void initState() {
    super.initState();
    _rule =
        widget.initialRule ??
        widget.store.rules.where((rule) => rule.enabled).firstOrNull;
  }

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final rule = _rule;
    if (rule == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = '';
    });
    try {
      final result = await widget.store.lookup(rule, _word.text.trim());
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ArchiveSection(title: '测试字典规则', code: 'READER / ONLINE PREVIEW'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _rule?.name,
          decoration: const InputDecoration(labelText: '字典规则'),
          items: [
            for (final rule in widget.store.rules)
              DropdownMenuItem(value: rule.name, child: Text(rule.name)),
          ],
          onChanged: (value) {
            setState(() {
              _rule = widget.store.rules
                  .where((rule) => rule.name == value)
                  .firstOrNull;
            });
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _word,
                decoration: const InputDecoration(labelText: '查询词'),
                onSubmitted: (_) => _run(),
              ),
            ),
            const SizedBox(width: 10),
            GlassTextButton(
              onPressed: _busy ? null : _run,
              child: AppText(_busy ? '查询中…' : '查询'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: _error != null
                    ? Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    : SelectableText(
                        _result.isEmpty ? '查询结果会显示在这里' : _result,
                        style: const TextStyle(fontSize: 14, height: 1.65),
                      ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

String _message(Object error) {
  if (error is FormatException && error.message.toString().isNotEmpty) {
    return error.message.toString();
  }
  if (error is FileSystemException) return '读取规则文件失败，请重试';
  return error.toString().trim().isEmpty ? '字典规则操作未完成，请重试' : '$error';
}
