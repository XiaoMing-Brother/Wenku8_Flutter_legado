import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_ui.dart';
import 'replace_rule.dart';
import 'replace_rule_engine.dart';
import 'replace_rule_store.dart';
import 'builtin_replace_rules.dart';

/// 「生效的替换」内联版：以可嵌入的 Column 呈现（用于阅读器「净化」分类内直接展示）。
class EffectiveReplacesInline extends StatefulWidget {
  const EffectiveReplacesInline({
    super.key,
    required this.bookTitle,
    required this.origin,
    this.active = true,
    this.store,
  });

  final String bookTitle;
  final String origin;
  final bool active;
  final ReplaceRuleStore? store;

  @override
  State<EffectiveReplacesInline> createState() =>
      _EffectiveReplacesInlineState();
}

class _EffectiveReplacesInlineState extends State<EffectiveReplacesInline> {
  ReplaceRuleStore get _store => widget.store ?? ReplaceRuleStore.shared;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _load();
  }

  Future<void> _load() async {
    try {
      await _store.load();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  List<ReplaceRule> get _effective {
    final result = <ReplaceRule>[];
    final seen = <String>{};
    for (final rule in _store.rules) {
      if (!rule.scopeTitle && !rule.scopeContent) continue;
      if (!ReplaceRuleEngine.inScope(
        rule,
        bookTitle: widget.bookTitle,
        origin: widget.origin,
      )) {
        continue;
      }
      if (seen.add(rule.id)) result.add(rule);
    }
    return result;
  }

  Future<void> _toggle(ReplaceRule rule, bool value) async {
    try {
      await _store.setRuleEnabled(rule.id, value);
    } catch (_) {}
  }

  Future<void> _importBuiltin() async {
    try {
      await _store.importText(encodeReplaceRules(builtinReplaceRules()));
    } catch (_) {}
  }

  Future<void> _setGroup(List<ReplaceRule> rules, bool value) async {
    for (final rule in rules) {
      if (rule.enabled == value) continue;
      try {
        await _store.setRuleEnabled(rule.id, value);
      } catch (_) {}
    }
  }

  Widget _groupToggles(
    BuildContext context,
    List<ReplaceRule> rules,
    Color muted,
  ) {
    final groups = <String, List<ReplaceRule>>{};
    for (final rule in rules) {
      groups.putIfAbsent(rule.displayGroup, () => <ReplaceRule>[]).add(rule);
    }
    if (groups.length <= 1) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: AppText(
                    '${entry.key} · '
                    '${entry.value.where((r) => r.enabled).length}/${entry.value.length}',
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ),
                AppControls.toggle(
                  context,
                  value: entry.value.every((r) => r.enabled),
                  onChanged: (value) => _setGroup(entry.value, value),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _ruleRow(BuildContext context, ReplaceRule rule, Color muted) {
    final detail = StringBuffer()
      ..write(rule.regex ? '正则' : '文本')
      ..write(' · ')
      ..write(rule.displayGroup);
    if (rule.pattern.isNotEmpty) {
      detail.write('\n${rule.pattern} → ${rule.replacement}');
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  rule.enabled ? rule.displayName : '${rule.displayName}（已停用）',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                AppText(
                  detail.toString(),
                  style: TextStyle(fontSize: 12, height: 1.5, color: muted),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppControls.toggle(
            context,
            value: rule.enabled,
            onChanged: (value) => _toggle(rule, value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rules = _effective;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ArchiveSection(title: '生效的替换', code: 'REPLACE / ACTIVE'),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CupertinoActivityIndicator()),
          )
        else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: GlassTextButton(
              key: const ValueKey('effective-replaces-builtin-inline'),
              compact: true,
              onPressed: _importBuiltin,
              child: const AppText('导入内置净化规则'),
            ),
          ),
          const SizedBox(height: 8),
          if (rules.isNotEmpty) _groupToggles(context, rules, muted),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AppText(
                '当前书籍没有作用域匹配的替换规则。',
                style: TextStyle(fontSize: 13, color: muted),
              ),
            )
          else
            for (final rule in rules) _ruleRow(context, rule, muted),
        ],
      ],
    );
  }
}
