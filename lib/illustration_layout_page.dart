import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'catalog.dart';
import 'feature_pages.dart';
import 'illustration_placement.dart';
import 'library_state.dart';
import 'reader_content.dart';
import 'reader_illustrations.dart';

class IllustrationLayoutPage extends StatefulWidget {
  const IllustrationLayoutPage({
    super.key,
    required this.novel,
    required this.chapter,
    required this.state,
    required this.repository,
    this.paragraph,
    this.source,
  });
  final Novel novel;
  final int chapter;
  final LibraryState state;
  final NovelRepository repository;
  final int? paragraph;
  final ReaderContent? source;
  @override
  State<IllustrationLayoutPage> createState() => _IllustrationLayoutPageState();
}

class _IllustrationLayoutPageState extends State<IllustrationLayoutPage> {
  late int? _paragraph = widget.paragraph;
  late Future<List<String>> _images = _load();
  String? _selected, _error;
  bool _saving = false;
  Future<List<String>> _load() async {
    if (_paragraph == null) return const [];
    final volume = NovelVolume.of(widget.novel.chapters).firstWhere(
      (volume) => widget.chapter >= volume.start && widget.chapter < volume.end,
    );
    final images = <String>{};
    for (final chapter in widget.novel.chapters.sublist(
      volume.start,
      volume.end,
    )) {
      if (!RegExp(
        r'插[图畫画絵]|彩页|イラスト|illustration',
        caseSensitive: false,
      ).hasMatch(chapter.title)) {
        continue;
      }
      final content = await ReaderContent.parse(
        await widget.repository.chapterContent(widget.novel.id, chapter),
      );
      images.addAll(content.illustrations);
    }
    return images.toList(growable: false);
  }

  Future<void> _save() async {
    if (_saving ||
        _selected == null ||
        _paragraph == null ||
        widget.source == null) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.state.putIllustration(
        widget.novel.id,
        IllustrationPlacement.at(
          chapterId: widget.novel.chapters[widget.chapter].id,
          chapterTitle: widget.novel.chapters[widget.chapter].title,
          url: _selected!,
          paragraphs: widget.source!.paragraphs,
          paragraph: _paragraph!,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : '插图位置未能保存，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(IllustrationPlacement placement) async {
    if (!await confirmNovelAction(
      context,
      title: '删除插图位置？',
      message: '仅移除正文中的排版位置，卷末原图和正文保留。',
      confirmLabel: '删除插图位置',
      reduceMotion: widget.state.reduceMotion,
    )) {
      return;
    }
    try {
      await widget.state.removeIllustration(widget.novel.id, placement.id);
    } catch (_) {
      if (mounted) setState(() => _error = '插图位置未能移除，请重试');
    }
  }

  Future<void> _openPlacementMenu(
    BuildContext anchor,
    IllustrationPlacement placement,
  ) async {
    final remove = await showGlassMenu<bool>(
      context: anchor,
      reduceMotion: widget.state.reduceMotion,
      builder: (menu) => GlassMenuItem(
        label: '移除插图位置',
        icon: CupertinoIcons.trash,
        onPressed: () => Navigator.pop(menu, true),
      ),
    );
    if (remove == true) await _remove(placement);
  }

  Future<void> _chooseParagraph() async {
    final source = widget.source;
    if (source == null) return;
    final ids = [
      for (var i = 0; i < source.paragraphs.length; i++)
        if (readerIllustrationUrl(source.paragraphs[i]) == null &&
            source.paragraphs[i] != '[插图]')
          i,
    ];
    final selected = await showJellySheet<int>(
      context: context,
      reduceMotion: widget.state.reduceMotion,
      heightFactor: .78,
      builder: (sheet) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        itemCount: ids.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (_, index) {
          if (index == 0) {
            return const ArchiveSection(
              title: '选择段落',
              code: 'ILLUSTRATIONS / ANCHOR',
            );
          }
          final id = ids[index - 1];
          return ContentPanel(
            onTap: () => Navigator.pop(sheet, id),
            child: AppText(
              source.paragraphs[id],
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          );
        },
      ),
    );
    if (mounted && selected != null) {
      setState(() {
        _paragraph = selected;
        _selected = null;
        _images = _load();
      });
    }
  }

  Future<void> _openPageActions(BuildContext anchor) async {
    if (widget.source == null || _saving) return;
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: widget.state.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassMenuItem(
            key: const ValueKey('illustration-placement-action'),
            label: _paragraph == null ? '手动修正插图位置' : '更换段落',
            icon: CupertinoIcons.photo,
            onPressed: () => Navigator.pop(menu, 'paragraph'),
          ),
        ],
      ),
    );
    if (!mounted || action != 'paragraph') return;
    await _chooseParagraph();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '插图排版',
    code: 'ILLUSTRATIONS / PLACEMENT',
    actions: [
      if (widget.source != null)
        GlassMenuAnchor(
          child: Builder(
            builder: (anchor) => GlassIconButton(
              key: const ValueKey('illustration-placement-actions'),
              icon: CupertinoIcons.ellipsis,
              label: '插图排版操作',
              onPressed: _saving ? null : () => _openPageActions(anchor),
            ),
          ),
        ),
    ],
    child: AnimatedBuilder(
      animation: widget.state.illustrationChanges,
      builder: (context, _) {
        final placements = widget.state.illustrationsFor(widget.novel.id);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: FutureBuilder<List<String>>(
              future: _images,
              builder: (context, snapshot) => ListView(
                padding: featurePadding(context),
                children: [
                  if (_paragraph != null) ...[
                    const ArchiveSection(
                      title: '放在这个段落之后',
                      code: 'ILLUSTRATIONS / ANCHOR',
                    ),
                    const SizedBox(height: 12),
                    ContentPanel(
                      child: AppText(
                        widget.source!.paragraphs[_paragraph!],
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.8),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const ArchiveSection(
                      title: '选择本卷插图',
                      code: 'ILLUSTRATIONS / IMAGES',
                    ),
                    const SizedBox(height: 12),
                    if (snapshot.connectionState != ConnectionState.done)
                      const SizedBox(
                        height: 220,
                        child: LoadingSkeleton(layout: SkeletonLayout.library),
                      )
                    else if (snapshot.hasError) ...[
                      SizedBox(
                        height: 190,
                        child: ContentNotice(
                          icon: CupertinoIcons.exclamationmark_triangle,
                          title: '插图暂未读取成功',
                          message: '正文和已保存的位置不受影响。',
                          onRetry: () => setState(() => _images = _load()),
                          actionLabel: '重试读取',
                        ),
                      ),
                    ] else if (snapshot.data!.isEmpty)
                      const SizedBox(
                        height: 190,
                        child: ContentNotice(
                          icon: CupertinoIcons.photo,
                          title: '没有独立插图章节',
                          message: '已有的文内插图会保留原位置。',
                        ),
                      )
                    else ...[
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 180,
                              childAspectRatio: .72,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) {
                          final url = snapshot.data![index];
                          return Semantics(
                            selected: _selected == url,
                            label: '本卷插图 ${index + 1}',
                            child: JellyTapSurface(
                              key: ValueKey('illustration-choice-$index'),
                              haptic: HapticCue.selection,
                              onTap: _saving
                                  ? null
                                  : () => setState(() => _selected = url),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: _selected == url
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onSurface
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: IgnorePointer(
                                    child: ReaderIllustration(
                                      url: url,
                                      sizedFrame: true,
                                      onOpen: () {},
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      GlassTextButton(
                        key: const ValueKey('illustration-confirm-placement'),
                        onPressed: _selected == null || _saving ? null : _save,
                        child: AppText(_saving ? '正在保存…' : '嵌入此段之后'),
                      ),
                    ],
                    const SizedBox(height: 28),
                  ],
                  AppText(
                    '已保存 ${placements.length} 处',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (placements.isEmpty && _paragraph == null)
                    const AppText(
                      '原文有插图地址时沿用原位置；本机有同版本 EPUB 时，自动用插图前后正文匹配位置。没有可靠位置的独立图集可在这里手动修正。',
                      style: TextStyle(height: 1.8),
                    ),
                  for (final placement in placements)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: ContentPanel(
                        child: Row(
                          children: [
                            const ArchiveIcon(CupertinoIcons.photo, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppText(
                                    placement.chapterTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  AppText(
                                    placement.tail,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                  if (widget.source != null &&
                                      placement.chapterId ==
                                          widget
                                              .novel
                                              .chapters[widget.chapter]
                                              .id &&
                                      placement.resolve(
                                            widget.source!.paragraphs,
                                          ) ==
                                          null)
                                    const AppText(
                                      '原文已变化，需要重新定位',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                            GlassMenuAnchor(
                              child: Builder(
                                builder: (anchor) => CompactRowMenuButton(
                                  label: '插图位置 ${placement.id} 更多操作',
                                  onPressed: () =>
                                      _openPlacementMenu(anchor, placement),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  FeatureError(_error),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
