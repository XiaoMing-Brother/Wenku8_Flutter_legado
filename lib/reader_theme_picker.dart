import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_search_field.dart';
import 'app_ui.dart';
import 'glass_choices.dart';
import 'reader_theme_presets.dart';

enum ReaderThemeFilter {
  all('全部'),
  day('日间'),
  night('夜间');

  const ReaderThemeFilter(this.label);
  final String label;
}

/// 从 Legado 内置的 LightInk 主题清单中选择一套阅读主题。
///
/// 清单本身随应用打包；卡片缩略图按需加载，只有确认选择后才会缓存原图。
class ReaderThemePicker extends StatefulWidget {
  const ReaderThemePicker({
    super.key,
    this.selectedId,
    this.actionLabel = '应用主题',
    required this.previewBuilder,
  });

  final int? selectedId;
  final String actionLabel;
  final Widget Function(ReaderThemeSelection) previewBuilder;

  @override
  State<ReaderThemePicker> createState() => _ReaderThemePickerState();
}

class _ReaderThemePickerState extends State<ReaderThemePicker> {
  final _search = TextEditingController();
  ReaderThemeFilter _filter = ReaderThemeFilter.all;
  String _query = '';
  int? _previewIndex;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: LegadoReaderThemes.load(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: ContentNotice(
            icon: CupertinoIcons.paintbrush,
            title: '主题清单无法读取',
            message: '请重新打开阅读设置后再试。',
            onRetry: () => setState(() {}),
          ),
        );
      }
      final themes = snapshot.data;
      if (themes == null) {
        return const Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final query = _query.trim().toLowerCase();
      final visible = themes
          .where((theme) {
            if (_filter == ReaderThemeFilter.day && theme.isNightTheme) {
              return false;
            }
            if (_filter == ReaderThemeFilter.night && !theme.isNightTheme) {
              return false;
            }
            if (query.isEmpty) return true;
            return theme.name.toLowerCase().contains(query) ||
                theme.author.toLowerCase().contains(query);
          })
          .toList(growable: false);
      final index = _previewIndex;
      if (index != null) {
        final theme = visible[index];
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            ArchiveSection(title: theme.name, code: 'READER / THEME PREVIEW'),
            widget.previewBuilder(theme.selection),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GlassTextButton(
                  onPressed: index > 0
                      ? () => setState(() => _previewIndex = index - 1)
                      : null,
                  child: const AppText('上一套'),
                ),
                GlassTextButton(
                  onPressed: index + 1 < visible.length
                      ? () => setState(() => _previewIndex = index + 1)
                      : null,
                  child: const AppText('下一套'),
                ),
                GlassTextButton(
                  onPressed: () => setState(() => _previewIndex = null),
                  child: const AppText('返回主题库'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GlassTextButton(
              selected: true,
              onPressed: () => Navigator.of(context).pop(theme.selection),
              child: AppText(widget.actionLabel),
            ),
            GlassTextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const AppText('取消'),
            ),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ArchiveSection(
              title: 'Legado 内置主题',
              code: 'READER / LEGADO THEMES',
            ),
            AppSearchField(
              inputKey: const ValueKey('reader-theme-search'),
              controller: _search,
              hint: '搜索主题名称或作者',
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            GlassChoiceGroup<ReaderThemeFilter>(
              name: 'reader-theme-filter',
              label: '主题类型',
              value: _filter,
              options: {
                for (final filter in ReaderThemeFilter.values)
                  filter: filter.label,
              },
              onChanged: (value) => setState(() => _filter = value),
              labelSize: 13,
              optionSize: 12,
              columns: 3,
            ),
            const SizedBox(height: 8),
            AppText(
              '${visible.length} 套 · 点选主题试读正文',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visible.isEmpty
                  ? ContentNotice(
                      icon: CupertinoIcons.paintbrush,
                      title: '没有匹配主题',
                      message: '换个名称，或清除筛选后再试。',
                      actionLabel: '清除筛选',
                      onRetry: () => setState(() {
                        _search.clear();
                        _query = '';
                        _filter = ReaderThemeFilter.all;
                      }),
                    )
                  : GridView.builder(
                      key: const ValueKey('reader-legado-theme-grid'),
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: visible.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: .78,
                          ),
                      itemBuilder: (context, index) {
                        final theme = visible[index];
                        return _ThemeCard(
                          theme: theme,
                          selected: theme.id == widget.selectedId,
                          onTap: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() => _previewIndex = index);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final LegadoReaderTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = theme.thumbnailUrl != null;
    final selection = theme.selection;
    final foreground = hasImage ? Colors.white : selection.ink;
    return JellyTapSurface(
      tapKey: ValueKey('reader-theme-${theme.id}'),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selection.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage) _ThemePreview(theme: theme),
              if (hasImage)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                      stops: [.35, 1],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: selected
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: AppText(
                                  '✓ 使用中',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox(height: 17),
                    ),
                    const Spacer(),
                    AppText(
                      theme.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    if (theme.author.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      AppText(
                        theme.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          height: 1.2,
                          color: foreground.withValues(alpha: .78),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.theme});

  final LegadoReaderTheme theme;

  @override
  Widget build(BuildContext context) {
    final urls = theme.imageCandidates;
    if (urls.isEmpty) return const SizedBox.expand();
    Widget image(int index) {
      if (index >= urls.length) return const SizedBox.expand();
      return Image.network(
        urls[index],
        fit: BoxFit.cover,
        cacheWidth: 300,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => image(index + 1),
      );
    }

    return image(0);
  }
}
