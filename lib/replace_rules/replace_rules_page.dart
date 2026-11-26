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
import 'replace_rule.dart';
import 'replace_rule_store.dart';
import 'builtin_replace_rules.dart';

class ReplaceRulesPage extends StatefulWidget {
  const ReplaceRulesPage({
    super.key,
    required this.store,
    this.reduceMotion = false,
  });

  final ReplaceRuleStore store;
  final bool reduceMotion;

  @override
  State<ReplaceRulesPage> createState() => _ReplaceRulesPageState();
}

class _ReplaceRulesPageState extends State<ReplaceRulesPage> {
  final _query = TextEditingController();
  bool _loading = true;
  String? _error;

  ReplaceRuleStore get _store => widget.store;

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

  List<ReplaceRule> get _visibleRules {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return _store.rules;
    return [
      for (final rule in _store.rules)
        if (rule.name.toLowerCase().contains(query) ||
            rule.group.toLowerCase().contains(query) ||
            rule.pattern.toLowerCase().contains(query) ||
            rule.replacement.toLowerCase().contains(query) ||
            rule.scope.toLowerCase().contains(query))
          rule,
    ];
  }

  Future<void> _edit([ReplaceRule? current]) async {
    final rule = await showJellySheet<ReplaceRule>(
      context: context,
      reduceMotion: widget.reduceMotion,
      heightFactor: .92,
      maxWidth: 720,
      builder: (_) => _ReplaceRuleEditor(
        rule: current,
        order:
            current?.order ??
            (_store.rules.isEmpty ? 0 : _store.rules.last.order + 10),
      ),
    );
    if (!mounted || rule == null) return;
    try {
      if (current == null) {
        await _store.add(rule);
        _feedback('已添加替换规则');
      } else {
        await _store.update(rule);
        _feedback('已保存替换规则');
      }
    } catch (error) {
      _feedback(_message(error), error: true);
    }
  }

  Future<void> _delete(ReplaceRule rule) async {
    final confirmed = await confirmNovelAction(
      context,
      title: '删除替换规则？',
      message: '「${rule.displayName}」将从本机替换库中移除，已缓存的正文不受影响。',
      confirmLabel: '删除替换规则',
      reduceMotion: widget.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    try {
      await _store.remove(rule.id);
      _feedback('已删除替换规则');
    } catch (error) {
      _feedback(_message(error), error: true);
    }
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      _feedback('剪贴板中没有替换规则 JSON', error: true);
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
        throw const FormatException('替换规则文件超过 16 MB');
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

  Future<void> _importBuiltin() async {
    await _importText(encodeReplaceRules(builtinReplaceRules()));
  }

  Future<void> _export() async {
    if (_store.rules.isEmpty) {
      _feedback('还没有可导出的替换规则', error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: _store.exportJson()));
    if (mounted) _feedback('已复制 ${_store.rules.length} 条替换规则');
  }

  Future<void> _test() async {
    await showJellySheet<void>(
      context: context,
      reduceMotion: widget.reduceMotion,
      heightFactor: .84,
      maxWidth: 720,
      builder: (_) => _ReplaceRuleTester(store: _store),
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
    title: '替换净化',
    code: 'READER / TEXT FILTERS',
    actions: [
      GlassMenuAnchor(
        child: Builder(
          builder: (anchor) => GlassIconButton(
            key: const ValueKey('replace-rule-actions'),
            icon: CupertinoIcons.ellipsis,
            label: '替换规则操作',
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
              inputKey: const ValueKey('replace-rule-search'),
              controller: _query,
              hint: '搜索名称、分组、规则或范围',
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
                      key: const ValueKey('replace-rule-list'),
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + 32,
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
    final status =
        '${_store.rules.length} 条规则 · $enabled 条启用 · '
        '${_store.enabled ? '默认启用' : '默认关闭'}';
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
          AppControls.toggle(
            context,
            value: _store.enabled,
            onChanged: (value) async {
              try {
                await _store.setEnabled(value);
              } catch (error) {
                _feedback(_message(error), error: true);
              }
            },
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
    final source = _store.rules.indexWhere((rule) => rule.id == moved.id);
    final destination = target == null
        ? _store.rules.length
        : _store.rules.indexWhere((rule) => rule.id == target.id);
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
            label: '导入内置净化规则',
            icon: CupertinoIcons.star,
            order: 3,
            onPressed: () => Navigator.pop(menu, 'builtin'),
          ),
          GlassMenuItem(
            label: '导出全部规则',
            icon: CupertinoIcons.square_arrow_up,
            order: 4,
            onPressed: () => Navigator.pop(menu, 'export'),
          ),
          GlassMenuItem(
            label: '测试规则',
            icon: CupertinoIcons.play_rectangle,
            order: 5,
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
      case 'builtin':
        await _importBuiltin();
      case 'export':
        await _export();
      case 'test':
        await _test();
    }
  }

  Widget _ruleTile(BuildContext context, ReplaceRule rule, int index) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final invalid = rule.validationError != null;
    final details =
        '${rule.displayGroup} · ${rule.pattern} → '
        '${rule.replacement.isEmpty ? '（删除）' : rule.replacement}';
    return Container(
      key: ValueKey(rule.id),
      margin: const EdgeInsets.only(bottom: 14),
      child: ContentPanel(
        onTap: () => _edit(rule),
        child: Row(
          children: [
            ArchiveReorderHandle(
              index: index,
              label: '拖动调整${rule.displayName}的顺序',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: AppText(
                          rule.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (rule.regex) ...[
                        const SizedBox(width: 8),
                        _badge(context, '正则'),
                      ],
                      if (rule.scopeTitle) ...[
                        const SizedBox(width: 6),
                        _badge(context, '标题'),
                      ],
                      if (rule.scopeContent) ...[
                        const SizedBox(width: 6),
                        _badge(context, '正文'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Tooltip(
                    message: details,
                    child: AppText(
                      details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.4, color: muted),
                    ),
                  ),
                  if (invalid)
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
                  await _store.setRuleEnabled(rule.id, value);
                } catch (error) {
                  _feedback(_message(error), error: true);
                }
              },
            ),
            GlassMenuAnchor(
              child: Builder(
                builder: (anchor) => CompactRowMenuButton(
                  label: '${rule.displayName} 更多操作',
                  onPressed: () => _openRuleMenu(anchor, rule),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRuleMenu(BuildContext anchor, ReplaceRule rule) async {
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: widget.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassMenuItem(
            label: '编辑规则',
            icon: CupertinoIcons.pencil,
            order: 0,
            onPressed: () => Navigator.pop(menu, 'edit'),
          ),
          GlassMenuItem(
            label: '删除规则',
            icon: CupertinoIcons.trash,
            order: 1,
            onPressed: () => Navigator.pop(menu, 'delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        await _edit(rule);
      case 'delete':
        await _delete(rule);
    }
  }

  Widget _badge(BuildContext context, String text) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: .7),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      child: Text(text, style: const TextStyle(fontSize: 9)),
    ),
  );

  Widget _empty(BuildContext context) => _store.rules.isEmpty
      ? ContentNotice(
          icon: CupertinoIcons.sparkles,
          title: appText(context, '还没有替换规则'),
          message: appText(
            context,
            '可导入 Legado 替换规则 JSON，或新建一条规则，在阅读时净化广告、重复标题等文字。',
          ),
          secondaryAction: GlassTextButton(
            compact: true,
            onPressed: _importFromClipboard,
            child: const AppText('从剪贴板导入'),
          ),
        )
      : ContentNotice(
          icon: CupertinoIcons.search,
          title: appText(context, '没有匹配的替换规则'),
          message: appText(context, '调整搜索词后再试。'),
          secondaryAction: GlassTextButton(
            compact: true,
            onPressed: () => setState(() => _query.clear()),
            child: const AppText('清除搜索'),
          ),
        );
}

Future<void> showReaderReplaceEditor(
  BuildContext context, {
  required String bookTitle,
  String selectedText = '',
  required bool reduceMotion,
  required bool active,
}) async {
  final rule = await showJellySheet<ReplaceRule>(
    context: context,
    reduceMotion: reduceMotion,
    heightFactor: .92,
    maxWidth: 720,
    builder: (_) => _ReplaceRuleEditor(
      order: 0,
      initialScope: bookTitle,
      initialText: selectedText,
    ),
  );
  if (rule == null || !context.mounted) return;
  try {
    await ReplaceRuleStore.shared.add(rule);
    if (context.mounted) {
      showNovelFeedback(context, active ? '已添加替换规则' : '已保存规则，本书尚未开启替换净化');
    }
  } catch (error) {
    if (context.mounted) {
      showNovelFeedback(context, _message(error), haptic: HapticCue.error);
    }
  }
}

class _ReplaceRuleEditor extends StatefulWidget {
  const _ReplaceRuleEditor({
    this.rule,
    required this.order,
    this.initialScope,
    this.initialText = '',
  });

  final ReplaceRule? rule;
  final int order;
  final String? initialScope;
  final String initialText;

  @override
  State<_ReplaceRuleEditor> createState() => _ReplaceRuleEditorState();
}

class _ReplaceRuleEditorState extends State<_ReplaceRuleEditor> {
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final _group = TextEditingController(text: widget.rule?.group ?? '');
  late final _pattern = TextEditingController(
    text: widget.rule?.pattern ?? widget.initialText,
  );
  late final _replacement = TextEditingController(
    text: widget.rule?.replacement ?? '',
  );
  late final _scope = TextEditingController(
    text: widget.rule?.scope ?? widget.initialScope ?? '',
  );
  late final _exclude = TextEditingController(
    text: widget.rule?.excludeScope ?? '',
  );
  late bool _regex = widget.rule?.regex ?? (widget.initialScope == null);
  late bool _scopeTitle = widget.rule?.scopeTitle ?? false;
  late bool _scopeContent = widget.rule?.scopeContent ?? true;
  late bool _enabled = widget.rule?.enabled ?? true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _group.dispose();
    _pattern.dispose();
    _replacement.dispose();
    _scope.dispose();
    _exclude.dispose();
    super.dispose();
  }

  void _save() {
    final rule = ReplaceRule(
      id: widget.rule?.id ?? '',
      name: _name.text.trim(),
      group: _group.text.trim(),
      pattern: _pattern.text,
      replacement: _replacement.text,
      scope: _scope.text.trim(),
      excludeScope: _exclude.text.trim(),
      scopeTitle: _scopeTitle,
      scopeContent: _scopeContent,
      enabled: _enabled,
      regex: _regex,
      order: widget.order,
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
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ArchiveSection(
                title: widget.rule == null ? '新建替换规则' : '编辑替换规则',
                code: 'READER / REPLACE RULE',
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
              _field('规则名称', _name, hint: '例如：去除广告尾巴'),
              _field('分组', _group, hint: '可选，同一分组的规则便于整理'),
              const SizedBox(height: 10),
              _field(
                '替换内容',
                _pattern,
                hint: _regex ? r'正则表达式，例如：\s*请收藏本站.*' : '要查找的原文',
                maxLines: 3,
              ),
              _field(
                '替换为',
                _replacement,
                hint: r'留空表示删除；正则可用 $1 引用分组',
                maxLines: 3,
              ),
              _field('作用范围', _scope, hint: '填写完整书名或书源地址；本地书填 loc_book，留空为全部'),
              _field('排除范围', _exclude, hint: '命中这些书时不应用此规则'),
              const SizedBox(height: 6),
              _switch('使用正则表达式', _regex, (value) {
                setState(() => _regex = value);
              }),
              _switch('作用于章节标题', _scopeTitle, (value) {
                setState(() => _scopeTitle = value);
              }),
              _switch('作用于正文', _scopeContent, (value) {
                setState(() => _scopeContent = value);
              }),
              _switch('启用此规则', _enabled, (value) {
                setState(() => _enabled = value);
              }),
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
          key: const ValueKey('replace-rule-editor-save'),
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

  Widget _switch(String label, bool value, ValueChanged<bool> changed) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: AppText(label)),
            AppControls.toggle(context, value: value, onChanged: changed),
          ],
        ),
      );
}

class _ReplaceRuleTester extends StatefulWidget {
  const _ReplaceRuleTester({required this.store});

  final ReplaceRuleStore store;

  @override
  State<_ReplaceRuleTester> createState() => _ReplaceRuleTesterState();
}

class _ReplaceRuleTesterState extends State<_ReplaceRuleTester> {
  final _book = TextEditingController(text: '测试书籍');
  final _text = TextEditingController(
    text: '第1章 测试\n这是正文第一句。\n请收藏本站：example.com\n这是正文最后一句。',
  );
  String _result = '';

  @override
  void dispose() {
    _book.dispose();
    _text.dispose();
    super.dispose();
  }

  void _run() {
    setState(() {
      _result = widget.store.applyContent(
        _text.text,
        bookTitle: _book.text.trim(),
        origin: '',
      );
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ArchiveSection(title: '测试替换规则', code: 'READER / PREVIEW'),
        const SizedBox(height: 12),
        const AppText(
          '使用当前已启用且匹配这本书的正文规则。标题规则请在目录中查看效果。',
          style: TextStyle(fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _book,
          decoration: const InputDecoration(labelText: '书名'),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: TextField(
            controller: _text,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              labelText: '正文示例',
              alignLabelWithHint: true,
            ),
          ),
        ),
        const SizedBox(height: 10),
        GlassTextButton(onPressed: _run, child: const AppText('执行测试')),
        const SizedBox(height: 10),
        Expanded(
          child: ContentPanel(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: SelectableText(
                _result.isEmpty ? '结果会显示在这里' : _result,
                style: const TextStyle(fontSize: 14, height: 1.65),
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
  return '替换规则操作未完成，请重试';
}
