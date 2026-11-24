import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'app_interactions.dart';
import 'book_documents.dart';
import 'feature_pages.dart' show confirmNovelAction;
import 'personal_images.dart';
import 'reader_background.dart';
import 'reader_preferences.dart';
import 'reader_theme_presets.dart';

class ReaderThemeShelf extends StatefulWidget {
  const ReaderThemeShelf({
    super.key,
    required this.preferences,
    required this.appDark,
    required this.store,
    required this.onChanged,
    required this.onAdd,
    required this.reduceMotion,
  });
  final ReaderPreferences preferences;
  final bool appDark, reduceMotion;
  final ReaderBackgroundStore store;
  final ValueChanged<ReaderPreferences> onChanged;
  final ValueChanged<bool> onAdd;
  @override
  State<ReaderThemeShelf> createState() => _ReaderThemeShelfState();
}

class _ReaderThemeShelfState extends State<ReaderThemeShelf> {
  bool? browsingNight;
  bool get activeNight => widget.preferences.usesNight(widget.appDark);
  bool get night => browsingNight ?? activeNight;

  Widget sample(ReaderLook look, bool group, {Widget? overlay}) {
    final preview = ReaderPreferences(
      paper: look.paper,
      theme: look.theme,
      backgroundImage: look.backgroundImage,
      nightLook: look,
      dayShelf: [look],
      nightShelf: [look],
      backgroundOpacity: widget.preferences.backgroundOpacity,
      nightTextBrightness: widget.preferences.nightTextBrightness,
    );
    final ink = preview.foreground(group);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ReaderBackground(
        store: widget.store,
        preferences: preview,
        paper: preview.background(group),
        night: group,
        preview: true,
        reduceMotion: true,
        child:
            overlay ??
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(color: ink, fontSize: 13),
                    children: [
                      TextSpan(text: '雨停了，'),
                      TextSpan(
                        text: '长街',
                        style: TextStyle(
                          backgroundColor:
                              look.highlight ?? ink.withValues(alpha: .14),
                        ),
                      ),
                      const TextSpan(text: '尽头亮起一盏灯。'),
                      TextSpan(
                        text: '  01',
                        style: TextStyle(
                          color: look.accent ?? ink,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
      ),
    );
  }

  Future<void> edit(ReaderLook initial, bool group) async {
    var draft = initial;
    var fieldsVersion = 0;
    final form = GlobalKey<FormState>();
    final result = await showJellySheet<ReaderLook>(
      context: context,
      reduceMotion: widget.reduceMotion,
      heightFactor: .85,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, refresh) {
          final colors = [
            draft.baseColor,
            draft.textColor,
            draft.accent,
            draft.highlight,
          ];
          const labels = ['背景色', '正文字色', '强调色', '高亮底色'];
          ReaderLook update({String? image, bool replaceImage = false}) =>
              ReaderLook(
                paper: draft.paper,
                theme: replaceImage ? draft.theme?.withoutImage : draft.theme,
                backgroundImage: replaceImage ? image : draft.backgroundImage,
                baseColor: colors[0],
                textColor: colors[1],
                accent: colors[2],
                highlight: colors[3],
              );
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              ArchiveSection(
                title: '编辑 · ${initial.label}',
                code: 'READER / THEME EDITOR',
              ),
              SizedBox(height: 95, child: sample(draft, group)),
              Form(
                key: form,
                child: Column(
                  children: [
                    for (var index = 0; index < labels.length; index++)
                      TextFormField(
                        key: ValueKey((fieldsVersion, index)),
                        initialValue: colors[index]
                            ?.toARGB32()
                            .toRadixString(16)
                            .substring(2)
                            .toUpperCase(),
                        decoration: InputDecoration(
                          labelText: labels[index],
                          hintText: '留空跟随主题，或输入 #RRGGBB',
                        ),
                        validator: (value) =>
                            value!.trim().isEmpty ||
                                RegExp(
                                  r'^#?[0-9a-fA-F]{6}$',
                                ).hasMatch(value.trim())
                            ? null
                            : '请输入六位十六进制颜色',
                        onChanged: (raw) {
                          final hex = raw.trim().replaceFirst('#', '');
                          if (hex.isNotEmpty &&
                              !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
                            return;
                          }
                          refresh(() {
                            colors[index] = hex.isEmpty
                                ? null
                                : Color(0xff000000 | int.parse(hex, radix: 16));
                            draft = update();
                          });
                        },
                      ),
                  ],
                ),
              ),
              GlassTextButton(
                onPressed: () async {
                  final documents = BookDocuments();
                  try {
                    final picked = await documents.pickImage();
                    if (picked == null) return;
                    try {
                      final id = await widget.store.import(picked.path!);
                      if (sheet.mounted) {
                        refresh(
                          () => draft = update(image: id, replaceImage: true),
                        );
                      }
                    } finally {
                      await documents.releaseBooks([picked]);
                    }
                  } catch (_) {
                    if (sheet.mounted) showNovelFeedback(sheet, '未能导入图片');
                  }
                },
                child: const AppText('选择背景图片'),
              ),
              if (draft.backgroundImage != null ||
                  draft.theme?.imageUrl != null)
                GlassTextButton(
                  onPressed: () =>
                      refresh(() => draft = update(replaceImage: true)),
                  child: const AppText('使用纯色背景'),
                ),
              GlassTextButton(
                onPressed: () async {
                  var original = initial.theme;
                  if (original != null) {
                    try {
                      final catalog = await LegadoReaderThemes.load();
                      original =
                          catalog
                              .where((item) => item.id == initial.theme!.id)
                              .firstOrNull
                              ?.selection ??
                          original;
                    } catch (_) {
                      if (sheet.mounted) showNovelFeedback(sheet, '无法读取原主题');
                      return;
                    }
                  }
                  if (sheet.mounted) {
                    refresh(() {
                      draft = ReaderLook(paper: initial.paper, theme: original);
                      fieldsVersion++;
                    });
                  }
                },
                child: const AppText('恢复原配色'),
              ),
              GlassTextButton(
                selected: true,
                onPressed: () {
                  if (form.currentState!.validate()) {
                    Navigator.pop(sheet, draft);
                  }
                },
                child: const AppText('保存主题'),
              ),
              GlassTextButton(
                onPressed: () => Navigator.pop(sheet),
                child: const AppText('取消'),
              ),
            ],
          );
        },
      ),
    );
    if (mounted && result != null) {
      widget.onChanged(widget.preferences.saveCard(group, result));
    }
  }

  Future<void> remove(ReaderLook look, bool group) async {
    final cards = widget.preferences.shelf(group);
    if (cards.length <= 1) {
      showNovelFeedback(context, '每组至少保留一个主题，请先添加其他主题。');
      return;
    }
    final fallback =
        widget.preferences.lookFor(group).choiceKey == look.choiceKey
        ? '本组将改用「${cards.firstWhere((card) => card.choiceKey != look.choiceKey).label}」。'
        : '';
    final confirmed = await confirmNovelAction(
      context,
      title: '删除主题？',
      message:
          '「${look.label}」将从本机${group ? '夜间' : '日间'}主题列表移除。${fallback}另一组主题、背景图片和阅读进度均保留。',
      confirmLabel: '删除主题',
      reduceMotion: widget.reduceMotion,
    );
    if (mounted && confirmed)
      widget.onChanged(widget.preferences.removeCard(group, look));
  }

  @override
  Widget build(BuildContext context) {
    final group = night;
    final cards = widget.preferences.shelf(group);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final entry in [false, true])
              Expanded(
                child: Semantics(
                  selected: group == entry,
                  button: true,
                  child: JellyTapSurface(
                    onTap: () => setState(() => browsingNight = entry),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: AppText(
                            entry ? '夜间主题' : '日间主题',
                            style: TextStyle(
                              color: group == entry
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Container(
                          width: 54,
                          height: 3,
                          decoration: BoxDecoration(
                            color: group == entry
                                ? scheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: .75,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) {
            final look = cards[index];
            final paper = look.baseColor ?? ReaderPreferences(paper: look.paper, theme: look.theme).background(group);
            final outline = readerCardOutline(paper, accent: look.accent);
            final selected =
                activeNight == group &&
                widget.preferences.lookFor(group).choiceKey == look.choiceKey;
            return DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: outline,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Semantics(
                    button: true,
                    selected: selected,
                    label: '应用${look.label}',
                    child: JellyTapSurface(
                      onTap: () {
                        var next = widget.preferences.setLook(group, look);
                        if (group != activeNight) {
                          next = next.copyWith(
                            themeMode: group
                                ? ReaderThemeMode.night
                                : ReaderThemeMode.day,
                          );
                        }
                        widget.onChanged(next);
                      },
                      child: sample(
                        look,
                        group,
                        overlay: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(7, 22, 5, 7),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  scheme.surface.withValues(alpha: 0),
                                  scheme.surface.withValues(alpha: .92),
                                ],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(
                                  look.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                AppText(
                                  selected
                                      ? '使用中'
                                      : look.theme == null
                                      ? '默认主题'
                                      : '已添加',
                                  style: TextStyle(
                                    color: selected
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: IgnorePointer(
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: scheme.primary,
                          child: Icon(
                            Icons.check,
                            size: 15,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GlassMenuAnchor(
                      child: Builder(
                        builder: (anchor) => GlassIconButton(
                          icon: CupertinoIcons.ellipsis,
                          liveGlass: false,
                          transparent: true,
                          label: '${look.label}操作',
                          onPressed: () async {
                            final picked = await showGlassMenu<String>(
                              context: anchor,
                              reduceMotion: widget.reduceMotion,
                              builder: (menu) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GlassMenuItem(
                                    label: '编辑',
                                    icon: CupertinoIcons.pencil,
                                    onPressed: () =>
                                        Navigator.pop(menu, 'edit'),
                                  ),
                                  GlassMenuItem(
                                    label: '删除',
                                    order: 1,
                                    icon: CupertinoIcons.trash,
                                    onPressed: () =>
                                        Navigator.pop(menu, 'delete'),
                                  ),
                                ],
                              ),
                            );
                            if (!mounted) return;
                            if (picked == 'edit') {
                              await edit(look, group);
                            } else if (picked == 'delete') {
                              await remove(look, group);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        GlassTextButton(
          compact: true,
          key: const ValueKey('reader-legado-themes'),
          onPressed: () => widget.onAdd(group),
          child: const AppText('＋ 从主题库添加'),
        ),
      ],
    );
  }
}
