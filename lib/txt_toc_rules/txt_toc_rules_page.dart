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
import 'txt_toc_rule.dart';
import 'txt_toc_rule_engine.dart';
import 'txt_toc_rule_store.dart';

class TxtTocRulesPage extends StatefulWidget {
  const TxtTocRulesPage({
    super.key,
    required this.store,
    this.reduceMotion = false,
    this.pickMode = false,
  });

  final TxtTocRuleStore store;
  final bool reduceMotion;
  final bool pickMode;

  @override
  State<TxtTocRulesPage> createState() => _TxtTocRulesPageState();
}

class _TxtTocRulesPageState extends State<TxtTocRulesPage> {
  final _query = TextEditingController();
  bool _loading = true;
  String? _error;

  TxtTocRuleStore get _store => widget.store;

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

  List<TxtTocRule> get _visibleRules {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return _store.rules;
    return [
      for (final rule in _store.rules)
        if (rule.name.toLowerCase().contains(query) ||
            rule.chapterRule.toLowerCase().contains(query) ||
            rule.volumeRule.toLowerCase().contains(query) ||
            rule.example.toLowerCase().contains(query))
          rule,
    ];
  }

  void _select(TxtTocRule rule) {
    final error = rule.validationError ?? txtTocRulePatternError(rule);
    if (error != null) {
      _feedback('这条规则暂不可用：$error', error: true);
      return;
    }
    Navigator.pop(context, rule);
  }

  Future<void> _edit([TxtTocRule? current]) async {
    final rule = await showJellySheet<TxtTocRule>(
      context: context,
      reduceMotion: widget.reduceMotion,
      heightFactor: .92,
      maxWidth: 720,
      builder: (_) => _TxtTocRuleEditor(rule: current),
    );
    if (!mounted || rule == null) return;
    try {
      if (current == null) {
        await _store.add(rule);
        _feedback('已添加 TXT 目录规则');
      } else {
        await _store.update(rule);
        _feedback('已保存 TXT 目录规则');
      }
    } catch (error) {
      _feedback(_message(error), error: true);
    }
  }

  Future<void> _delete(TxtTocRule rule) async {
    final confirmed = await confirmNovelAction(
      context,
      title: '删除 TXT 目录规则？',
      message: '「${rule.displayName}」将从本机规则库中移除，已导入书籍的目录不会被重写。',
      confirmLabel: '删除 TXT 目录规则',
      reduceMotion: widget.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    try {
      await _store.remove(rule.id);
      _feedback('已删除 TXT 目录规则');
    } catch (error) {
      _feedback(_message(error), error: true);
    }
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      _feedback('剪贴板中没有 TXT 目录规则 JSON', error: true);
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
        throw const FormatException('TXT 目录规则文件超过 16 MB');
      }
      await _importText(utf8.decode(await file.readAsBytes()));
    } catch (error) {
      if (mounted) _feedback(_message(error), error: true);
    } finally {
      if (selected != null) {
        try {
          await documents.releaseBooks([selected]);
        } on Object {
          // Rules are already stored; releasing the picked document is best effort.
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

  Future<void> _importBuiltIn() async {
    final confirmed = await confirmNovelAction(
      context,
      title: '导入 Legado 内置规则？',
      message: '同 ID 规则会被内置版本覆盖，自建规则保持不变。',
      confirmLabel: '导入内置规则',
      reduceMotion: widget.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    try {
      final result = await _store.importBuiltIn();
      if (mounted) {
        final skipped = result.skipped > 0 ? ' · 跳过 ${result.skipped}' : '';
        _feedback('新增 ${result.added} · 更新 ${result.updated}$skipped');
      }
    } catch (error) {
      if (mounted) _feedback(_message(error), error: true);
    }
  }

  Future<void> _export() async {
    if (_store.rules.isEmpty) {
      _feedback('还没有可导出的 TXT 目录规则', error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: _store.exportJson()));
    if (mounted) _feedback('已复制 ${_store.rules.length} 条 TXT 目录规则');
  }

  Future<void> _test([TxtTocRule? rule]) async {
    await showJellySheet<void>(
      context: context,
      reduceMotion: widget.reduceMotion,
      heightFactor: .92,
      maxWidth: 720,
      builder: (_) => _TxtTocRuleTester(store: _store, initialRule: rule),
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
    title: widget.pickMode ? '选择目录规则' : 'TXT 目录规则',
    code: 'READER / TXT CONTENTS',
    actions: widget.pickMode
        ? const []
        : [
            GlassMenuAnchor(
              child: Builder(
                builder: (anchor) => GlassIconButton(
                  key: const ValueKey('txt-toc-rule-actions'),
                  icon: CupertinoIcons.ellipsis,
                  label: 'TXT 目录规则操作',
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
              inputKey: const ValueKey('txt-toc-rule-search'),
              controller: _query,
              hint: '搜索规则名称、表达式或示例',
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
                  : widget.pickMode
                  ? ListView.builder(
                      key: const ValueKey('txt-toc-rule-pick-list'),
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + 24,
                      ),
                      itemCount: _visibleRules.length,
                      itemBuilder: (context, index) =>
                          _ruleTile(context, _visibleRules[index], index),
                    )
                  : ReorderableListView.builder(
                      key: const ValueKey('txt-toc-rule-list'),
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
    final status = widget.pickMode
        ? '${_store.rules.length} 条规则 · 点按一条应用到本次导入设置'
        : '${_store.rules.length} 条规则 · ${_store.enabledCount} 条启用';
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
            label: '导入 Legado 内置规则',
            icon: CupertinoIcons.tray_arrow_down,
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
        await _importBuiltIn();
      case 'export':
        await _export();
      case 'test':
        await _test();
    }
  }

  Widget _ruleTile(BuildContext context, TxtTocRule rule, int index) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final patternError = txtTocRulePatternError(rule);
    final error = rule.validationError ?? patternError;
    final example = rule.example.trim();
    final details = [
      if (example.isNotEmpty) example.replaceAll('\n', ' · '),
      '章节 · ${rule.chapterRule}',
      if (rule.hasVolume) '分卷 · ${rule.volumeRule}',
    ].join(' · ');
    final panel = ContentPanel(
      onTap: widget.pickMode ? () => _select(rule) : () => _edit(rule),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  rule.displayName,
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
                    style: TextStyle(fontSize: 12, height: 1.4, color: muted),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      error,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
          if (widget.pickMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ArchiveIcon(
                error == null
                    ? CupertinoIcons.chevron_right
                    : CupertinoIcons.exclamationmark_circle,
                size: 16,
              ),
            )
          else ...[
            AppControls.toggle(
              context,
              value: rule.enabled,
              liteGlass: true,
              onChanged: (value) async {
                try {
                  await _store.setEnabled(rule.id, value);
                } catch (failure) {
                  _feedback(_message(failure), error: true);
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
        ],
      ),
    );
    return Container(
      key: ValueKey('txt-toc-rule-${rule.id}'),
      margin: const EdgeInsets.only(bottom: 14),
      child: widget.pickMode
          ? panel
          : ReorderableDelayedDragStartListener(index: index, child: panel),
    );
  }

  Future<void> _openRuleMenu(BuildContext anchor, TxtTocRule rule) async {
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: widget.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassMenuItem(
            label: '测试规则',
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
          icon: CupertinoIcons.list_bullet,
          title: appText(context, '还没有 TXT 目录规则'),
          message: appText(context, '目录规则用逐行正则识别章节与分卷，可在“导入与目录”中选择后用于之后的 TXT。'),
          secondaryAction: widget.pickMode
              ? null
              : GlassTextButton(
                  compact: true,
                  onPressed: _importBuiltIn,
                  child: const AppText('导入 Legado 内置规则'),
                ),
        )
      : ContentNotice(
          icon: CupertinoIcons.search,
          title: appText(context, '没有匹配的规则'),
          message: appText(context, '调整搜索词后再试。'),
          secondaryAction: GlassTextButton(
            compact: true,
            onPressed: () => setState(() => _query.clear()),
            child: const AppText('清除搜索'),
          ),
        );
}

class _TxtTocRuleEditor extends StatefulWidget {
  const _TxtTocRuleEditor({this.rule});

  final TxtTocRule? rule;

  @override
  State<_TxtTocRuleEditor> createState() => _TxtTocRuleEditorState();
}

class _TxtTocRuleEditorState extends State<_TxtTocRuleEditor> {
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final _chapter = TextEditingController(
    text: widget.rule?.chapterRule ?? '',
  );
  late final _volume = TextEditingController(
    text: widget.rule?.volumeRule ?? '',
  );
  late final _example = TextEditingController(text: widget.rule?.example ?? '');
  late bool _enabled = widget.rule?.enabled ?? true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _chapter.dispose();
    _volume.dispose();
    _example.dispose();
    super.dispose();
  }

  void _save() {
    final rule = TxtTocRule(
      id: widget.rule?.id ?? 0,
      name: _name.text.trim(),
      chapterRule: _chapter.text.trim(),
      volumeRule: _volume.text.trim(),
      example: _example.text.trim(),
      serialNumber: widget.rule?.serialNumber ?? 0,
      enabled: _enabled,
    );
    final error = rule.validationError ?? txtTocRulePatternError(rule);
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
                title: widget.rule == null ? '新建 TXT 目录规则' : '编辑 TXT 目录规则',
                code: 'READER / TXT TOC RULE',
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
              _field('规则名称', _name, hint: '例如：标准章节'),
              _field(
                '章节表达式',
                _chapter,
                hint: r'例如：^第[零一二三四五六七八九十0-9]+章',
                maxLines: 3,
                maxLength: 1024,
              ),
              _field(
                '分卷表达式',
                _volume,
                hint: '可留空；同时匹配时优先识别为卷名',
                maxLines: 3,
                maxLength: 1024,
              ),
              _field('示例文本', _example, hint: '每行一个示例，方便测试和查找', maxLines: 5),
              const AppText(
                '逐行匹配，单行最多识别 90 个字符。Legado 的 (?i)、(?m) 前缀会自动转换；'
                '依赖跨行上下文的正则无法在逐行导入中完整复现。',
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
          key: const ValueKey('txt-toc-rule-editor-save'),
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
    int? maxLength,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: maxLength == null
          ? null
          : [LengthLimitingTextInputFormatter(maxLength)],
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );
}

class _TxtTocRuleTester extends StatefulWidget {
  const _TxtTocRuleTester({required this.store, this.initialRule});

  final TxtTocRuleStore store;
  final TxtTocRule? initialRule;

  @override
  State<_TxtTocRuleTester> createState() => _TxtTocRuleTesterState();
}

class _TxtTocRuleTesterState extends State<_TxtTocRuleTester> {
  final _sample = TextEditingController(
    text:
        '序言\n这是前言。\n'
        '第一卷 春日\n'
        '第一章 海岸\n这是正文。\n'
        '【归途】\n完整的结尾。\n'
        'Chapter 3 Night',
  );
  TxtTocRule? _rule;
  TxtTocRule? _autoRule;
  List<({int index, String text, TxtTocHeading heading})> _matches = const [];
  String? _error;
  bool _tested = false;

  @override
  void initState() {
    super.initState();
    _rule =
        widget.initialRule ??
        widget.store.rules.where((rule) => rule.enabled).firstOrNull ??
        widget.store.rules.firstOrNull;
  }

  @override
  void dispose() {
    _sample.dispose();
    super.dispose();
  }

  void _run() {
    final rule = _rule;
    if (rule == null) return;
    try {
      final matches = testTxtTocRule(rule, _sample.text);
      final auto = selectTxtTocRule(widget.store.rules, _sample.text);
      setState(() {
        _matches = matches;
        _autoRule = auto;
        _error = null;
        _tested = true;
      });
    } catch (error) {
      setState(() {
        _matches = const [];
        _error = _message(error);
        _tested = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ArchiveSection(title: '测试 TXT 目录规则', code: 'TXT / TOC PREVIEW'),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _rule?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '目录规则'),
          items: [
            for (final rule in widget.store.rules)
              DropdownMenuItem(
                value: rule.id,
                child: Text(
                  '${rule.enabled ? '' : '已停用 · '}${rule.displayName}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            setState(() {
              _rule = widget.store.rules
                  .where((rule) => rule.id == value)
                  .firstOrNull;
              _tested = false;
            });
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _sample,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '示例原文'),
          onChanged: (_) => setState(() => _tested = false),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: GlassTextButton(
            key: const ValueKey('txt-toc-rule-test-run'),
            onPressed: _rule == null ? null : _run,
            child: const AppText('测试规则'),
          ),
        ),
        if (_tested) ...[
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else
            AppText(
              '识别到 ${_matches.length} 个卷名或章名'
              ' · 自动匹配建议：'
              '${_autoRule?.displayName ?? '无（至少 2 章且相邻间隔需超过 1000 字符）'}',
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: SingleChildScrollView(
            child: _matches.isEmpty
                ? AppText(
                    _tested ? '没有匹配的标题，请检查表达式或换一段原文。' : '测试结果会显示在这里。',
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final match in _matches)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppText(
                            '${match.heading == TxtTocHeading.volume ? '卷' : '章'}'
                            ' · 第 ${match.index} 行 · ${match.text}',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              fontWeight: match.heading == TxtTocHeading.volume
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                    ],
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
  return error.toString().trim().isEmpty ? 'TXT 目录规则操作未完成，请重试' : '$error';
}
