import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_interactions.dart';
import 'app_ui.dart';
import 'book_text_encoding.dart';
import 'feature_pages.dart';
import 'glass_choices.dart';
import 'library_state.dart';
import 'local_import_options.dart';
import 'local_text_rules.dart';
import 'txt_toc_rules/txt_toc_rule.dart';
import 'txt_toc_rules/txt_toc_rule_engine.dart';
import 'txt_toc_rules/txt_toc_rule_store.dart';
import 'txt_toc_rules/txt_toc_rules_page.dart';

class LocalImportSettingsPage extends StatefulWidget {
  const LocalImportSettingsPage({super.key, required this.library});
  final LibraryState library;
  @override
  State<LocalImportSettingsPage> createState() =>
      _LocalImportSettingsPageState();
}

class _LocalImportSettingsPageState extends State<LocalImportSettingsPage> {
  late final organization = widget.library.organization;
  late final initial = organization.importOptions;
  final tocStore = TxtTocRuleStore.shared;
  late final chapter = TextEditingController(text: initial.chapterRule);
  late final volume = TextEditingController(text: initial.volumeRule);
  final sample = TextEditingController(
    text: '序言\n这是前言。\n第一卷 春日\n第一章 海岸\n这是正文。\n【归途】\n完整的结尾。\nChapter 3 Night',
  );
  late String tocMode = initial.customToc
      ? 'custom'
      : initial.autoTocRule
      ? 'library'
      : 'auto';
  late bool autoTitles = initial.autoTitles;
  bool busy = false, dirty = false, previewCurrent = false;
  String? error;
  List<({String title, bool volume})>? preview;
  TxtTocRule? selectedRule;
  TxtTocRule? autoPreviewRule;

  bool get custom => tocMode == 'custom';

  @override
  void initState() {
    super.initState();
    _identifySelectedRule();
  }

  Future<void> _identifySelectedRule() async {
    try {
      await tocStore.load();
      if (!mounted) return;
      setState(() {
        selectedRule = tocStore.findByExpressions(chapter.text, volume.text);
      });
    } on Object {
      // Rule-library loading is optional; the expression fields still work.
    }
  }

  LocalImportOptions get draft => LocalImportOptions(
    customToc: custom,
    autoTocRule: tocMode == 'library',
    chapterRule: chapter.text,
    volumeRule: volume.text,
    autoTitles: autoTitles,
  );
  void changed(VoidCallback change) => setState(() {
    change();
    dirty = true;
    previewCurrent = false;
    error = null;
  });
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is FormatException
              ? failure.message
              : '设置处理未完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() => perform(() async {
    await organization.setImportOptions(draft);
    if (mounted) Navigator.pop(context, true);
  });
  Future<void> inspect() => perform(() async {
    var options = draft;
    TxtTocRule? autoRule;
    if (tocMode == 'library') {
      await tocStore.load();
      autoRule = selectTxtTocRule(tocStore.rules, sample.text);
      if (autoRule == null) {
        if (mounted) {
          setState(() {
            preview = const [];
            previewCurrent = true;
            autoPreviewRule = null;
            error = '没有找到匹配的已启用规则；导入时会退回内置自动识别';
          });
        }
        return;
      }
      options = draft.withTocRule(autoRule.chapterRule, autoRule.volumeRule);
    }
    final result = await previewLocalDirectory(options, sample.text);
    if (mounted) {
      setState(() {
        preview = result;
        previewCurrent = true;
        autoPreviewRule = autoRule;
      });
    }
  });
  Future<void> pickTocRule() async {
    final rule = await pushNovelPage<TxtTocRule>(
      context,
      TxtTocRulesPage(
        store: tocStore,
        reduceMotion: widget.library.reduceMotion,
        pickMode: true,
      ),
      reduceMotion: widget.library.reduceMotion,
      slot: ('settings', 'txt-toc-rule-picker'),
    );
    if (!mounted || rule == null) return;
    changed(() {
      tocMode = 'custom';
      chapter.text = rule.chapterRule;
      volume.text = rule.volumeRule;
      selectedRule = rule;
    });
  }

  Future<void> manageTocRules() async {
    await pushNovelPage<void>(
      context,
      TxtTocRulesPage(
        store: tocStore,
        reduceMotion: widget.library.reduceMotion,
      ),
      reduceMotion: widget.library.reduceMotion,
      slot: ('settings', 'txt-toc-rules'),
    );
    if (mounted) await _identifySelectedRule();
  }

  void expressionChanged() {
    changed(() {
      selectedRule = tocStore.findByExpressions(chapter.text, volume.text);
    });
  }

  void preset(String kind) => changed(() {
    tocMode = 'custom';
    selectedRule = null;
    chapter.text = switch (kind) {
      'brackets' => r'^【.+】$',
      'english' => r'^chapter\s+\d+',
      _ => defaultLocalChapterRule,
    };
    volume.text = kind == 'english' ? r'^volume\s+\d+' : defaultLocalVolumeRule;
  });
  Widget ruleField(
    String label,
    TextEditingController controller,
    String key, {
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: TextField(
      key: ValueKey(key),
      onTap: () => AppHaptics.play(context, HapticCue.selection),
      onTapAlwaysCalled: true,
      controller: controller,
      enabled: !busy,
      minLines: 1,
      maxLines: 3,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 14, height: 1.5),
      inputFormatters: [LengthLimitingTextInputFormatter(1024)],
      decoration: InputDecoration(labelText: label, hintText: hint),
      onChanged: (_) => expressionChanged(),
    ),
  );
  @override
  void dispose() {
    chapter.dispose();
    volume.dispose();
    sample.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([organization, widget.library.settingsChanges]),
    builder: (context, _) => ArchiveFeaturePage(
      title: '导入与目录',
      code: 'IMPORT / CONTENTS',
      actions: [
        GlassMenuAnchor(
          child: Builder(
            builder: (anchor) => GlassIconButton(
              icon: CupertinoIcons.checkmark,
              label: busy ? '正在检查设置' : '保存导入设置',
              onPressed: busy || !dirty
                  ? null
                  : () async {
                      final action = await showGlassMenu<String>(
                        context: anchor,
                        reduceMotion: MediaQuery.disableAnimationsOf(context),
                        builder: (menu) => GlassMenuItem(
                          label: '保存设置',
                          icon: CupertinoIcons.checkmark,
                          onPressed: () => Navigator.pop(menu, 'save'),
                        ),
                      );
                      if (mounted && action == 'save') await save();
                    },
            ),
          ),
        ),
      ],
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: featurePadding(context),
            children: [
              GlassChoiceGroup<bool>(
                name: 'local-book-storage',
                label: '本地书籍保存方式',
                value: organization.linkLocalBooks,
                options: const {true: '关联原文件', false: '复制到应用'},
                enabled: !busy,
                onChanged: (value) =>
                    perform(() => organization.setLinkLocalBooks(value)),
              ),
              const AppText(
                '关联模式不重复保存原书，请保留原文件；移动或撤销授权后可重新定位。文档转换、解压和排版会生成必要的阅读缓存。已有副本不自动转换，网盘下载仍保存到本机。',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 18),
              const ArchiveSection(
                title: '从文件管理器打开',
                code: 'IMPORT / SYSTEM OPEN',
              ),
              const SizedBox(height: 8),
              const AppText(
                '在文件管理器点开书籍，选择「文库阅读」。如系统显示「始终」，选中后即可作为这类文件的默认阅读器；不同文件格式需分别选择。',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 18),
              GlassChoiceGroup<String>(
                name: 'local-txt-encoding',
                label: 'TXT 编码',
                value: organization.encoding,
                options: localTextEncodingOptions,
                enabled: !busy,
                onChanged: (value) =>
                    perform(() => organization.setEncoding(value)),
              ),
              const SizedBox(height: 18),
              GlassChoiceGroup<String>(
                name: 'import-toc-mode',
                label: 'TXT 目录识别',
                value: tocMode,
                options: const {
                  'auto': '自动识别',
                  'library': '规则库自动匹配',
                  'custom': '自定义规则',
                },
                enabled: !busy,
                onChanged: (value) => changed(() {
                  tocMode = value;
                  selectedRule = value == 'custom'
                      ? tocStore.findByExpressions(chapter.text, volume.text)
                      : null;
                  if (value != 'library') autoPreviewRule = null;
                }),
              ),
              if (error case final message?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: AppText(
                    message,
                    key: const ValueKey('import-options-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      height: 1.6,
                    ),
                  ),
                ),
              AnimatedOptionSection(
                expanded: tocMode == 'library',
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppText(
                        '导入前用原书开头文本，从已启用规则中选择一条。命中数相同则排序靠前的规则优先；没有合适规则时退回内置自动识别。',
                        style: TextStyle(fontSize: 12, height: 1.6),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GlassTextButton(
                          key: const ValueKey('import-toc-manage-auto'),
                          compact: true,
                          onPressed: busy ? null : manageTocRules,
                          child: const AppText(
                            '管理启用规则',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedOptionSection(
                expanded: custom,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: AppText(
                              selectedRule == null
                                  ? '可从规则库选择，或直接编辑下面两条表达式'
                                  : '当前规则 · ${selectedRule!.displayName}',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.6,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GlassTextButton(
                            key: const ValueKey('import-toc-pick-rule'),
                            compact: true,
                            onPressed: busy ? null : pickTocRule,
                            child: const AppText(
                              '选择规则',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GlassTextButton(
                            key: const ValueKey('import-toc-manage-rules'),
                            compact: true,
                            onPressed: busy ? null : manageTocRules,
                            child: const AppText(
                              '管理',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ruleField('章节表达式', chapter, 'import-chapter-rule'),
                    ruleField(
                      '分卷表达式',
                      volume,
                      'import-volume-rule',
                      hint: '留空则不识别分卷',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in const {
                          'chinese': '常见中文',
                          'english': 'Chapter',
                          'brackets': '【标题】',
                        }.entries)
                          GlassTextButton(
                            compact: true,
                            onPressed: busy ? null : () => preset(entry.key),
                            child: AppText(
                              entry.value,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                    const AppText(
                      '逐行匹配，正则使用原始行并保留行首空白；标题显示时去除首尾空白，分卷规则优先。',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ],
                ),
              ),
              GlassChoiceGroup<bool>(
                name: 'import-auto-titles',
                label: '原书未提供标题时',
                value: autoTitles,
                options: const {true: '补齐章名', false: '标为正文片段'},
                enabled: !busy,
                onChanged: (value) => changed(() => autoTitles = value),
              ),
              const SizedBox(height: 14),
              const AppText(
                '目录设置只用于之后导入的书籍，已有目录、阅读位置与书签不会重写。TXT 编码点选后立即保存。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 24),
              const ArchiveSection(title: '预览目录', code: 'TXT / PREVIEW'),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('import-toc-sample'),
                onTap: () => AppHaptics.play(context, HapticCue.selection),
                onTapAlwaysCalled: true,
                controller: sample,
                enabled: !busy,
                minLines: 4,
                maxLines: 8,
                style: const TextStyle(fontSize: 14, height: 1.6),
                inputFormatters: [LengthLimitingTextInputFormatter(20000)],
                decoration: const InputDecoration(labelText: '粘贴几段原文，查看识别结果'),
                onChanged: (_) => setState(() => previewCurrent = false),
              ),
              const SizedBox(height: 12),
              GlassPillButton(
                key: const ValueKey('preview-import-toc'),
                icon: CupertinoIcons.list_bullet,
                label: busy ? '正在检查规则' : '预览目录',
                onPressed: busy ? null : inspect,
              ),
              AnimatedOptionSection(
                expanded: preview != null,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppText(
                        previewCurrent
                            ? '识别到 ${preview?.length ?? 0} 个卷名与章名'
                                  '${autoPreviewRule == null ? '' : ' · 使用规则：${autoPreviewRule!.displayName}'}'
                            : '上次预览 · 修改后请重新预览',
                        style: const TextStyle(fontSize: 12, height: 1.6),
                      ),
                      for (final item
                          in preview?.take(60) ??
                              const <({String title, bool volume})>[])
                        Padding(
                          padding: const EdgeInsets.only(top: 10, left: 0),
                          child: AppText(
                            '${item.volume ? '卷' : '章'} · ${item.title}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: item.volume
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              height: 1.6,
                            ),
                          ),
                        ),
                      if (preview?.isEmpty == true)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: AppText(
                            '没有匹配的标题，请检查表达式或换一段原文。',
                            style: TextStyle(fontSize: 13, height: 1.6),
                          ),
                        ),
                      if ((preview?.length ?? 0) > 60)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: AppText(
                            '预览只展示前 60 条，完整导入不受此预览数量限制。',
                            style: TextStyle(fontSize: 12, height: 1.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
