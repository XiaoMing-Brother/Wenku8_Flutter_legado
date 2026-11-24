import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'reader_theme_presets.dart';

enum ReaderThemeFilter {
  day('日间主题'),
  night('夜间主题');

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
    this.initialNight = false,
    this.actionLabel = '应用主题',
    required this.previewBuilder,
  });

  final int? selectedId;
  final bool initialNight;
  final String actionLabel;
  final Widget Function(ReaderThemeSelection) previewBuilder;

  @override
  State<ReaderThemePicker> createState() => _ReaderThemePickerState();
}

class _ReaderThemePickerState extends State<ReaderThemePicker> {
  late ReaderThemeFilter _filter = widget.initialNight
      ? ReaderThemeFilter.night
      : ReaderThemeFilter.day;
  int? _previewIndex;

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
      final visible = themes
          .where((theme) {
            if (_filter == ReaderThemeFilter.day && theme.isNightTheme) {
              return false;
            }
            if (_filter == ReaderThemeFilter.night && !theme.isNightTheme) {
              return false;
            }
            return true;
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ArchiveSection(
              title: '内置主题',
              code: 'READER / LEGADO THEMES',
              centeredTitle: true,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final filter in ReaderThemeFilter.values)
                  Expanded(
                    child: Semantics(
                      selected: _filter == filter,
                      button: true,
                      child: JellyTapSurface(
                        onTap: () => setState(() => _filter = filter),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: AppText(filter.label),
                            ),
                            SizedBox(
                              width: 68,
                              height: 3,
                              child: ColoredBox(
                                color: _filter == filter
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visible.isEmpty
                  ? ContentNotice(
                      icon: CupertinoIcons.paintbrush,
                      title: '没有可用主题',
                      message: '当前分类暂时没有主题。',
                    )
                  : GridView.builder(
                      key: ValueKey(('reader-legado-theme-grid', _filter)),
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: visible.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: .75,
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
    final scheme = Theme.of(context).colorScheme;
    final paper = theme.background.a == 0
        ? scheme.surfaceContainer
        : theme.background;
    final foreground = theme.content;
    final control = theme.control ?? scheme.primary;
    final primary = scheme.primary;
    return JellyTapSurface(
      tapKey: ValueKey('reader-theme-${theme.id}'),
      onTap: onTap,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary : foreground.withValues(alpha: .12),
            width: selected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: paper),
              if (hasImage) _ThemePreview(theme: theme),
              if (!hasImage)
                Row(
                  children: [
                    for (final swatch in [
                      foreground,
                      control,
                      theme.secondary ?? foreground,
                      theme.directory ?? paper,
                      paper,
                    ])
                      Expanded(
                        child: ColoredBox(
                          color: swatch,
                          child: const SizedBox.expand(),
                        ),
                      ),
                  ],
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: .44,
                  widthFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          paper.withValues(alpha: .82),
                          paper.withValues(alpha: .97),
                        ],
                        stops: const [0, .45, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: control,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: AppText(
                            theme.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: foreground,
                            ),
                          ),
                        ),
                        if (selected)
                          AppText(
                            '使用中',
                            style: TextStyle(fontSize: 11, color: control),
                          ),
                      ],
                    ),
                    AppText(
                      theme.author.trim().isNotEmpty
                          ? theme.author
                          : '${theme.downloadCount} 次下载',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 16 / 11,
                        color:
                            theme.secondary ??
                            foreground.withValues(alpha: .78),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: primary,
                    child: Icon(Icons.check, size: 14, color: scheme.onPrimary),
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
