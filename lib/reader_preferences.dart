import 'dart:convert';
import 'package:flutter/material.dart';
import 'archive_design.dart';
import 'personal_images.dart' show validBackgroundId;
import 'reader_theme_presets.dart';
import 'reader_tip.dart';

const minimumReaderFontSize = 10.0;
const maximumReaderFontSize = 27.0;

enum ReaderPaper {
  system('跟随外观'),
  milk('奶白', background: Color(0xFFF6F5EF)),
  parchment('羊皮纸', background: Color(0xFFEDE2CA)),
  sage('浅苔', background: Color(0xFFE4EBDD)),
  night('夜读', background: ArchiveDesign.darkBackground),

  /// Legado 内置阅读样式（`readConfig.json`）的配色。只应用底色与文字色，
  /// 不覆盖字号、字体、边距等排版；夜间值在应用深色外观时使用。
  legadoWechat(
    '微信读书',
    background: Color(0xFFC0EDC6),
    ink: Color(0xFF0B0B0B),
    nightBackground: Color(0xFF000000),
    nightInk: Color(0xFFADADAD),
  );

  const ReaderPaper(
    this.label, {
    this.background,
    this.ink,
    this.nightBackground,
    this.nightInk,
  });
  final String label;
  final Color? background, ink, nightBackground, nightInk;
}

enum ReaderThemeMode {
  follow('跟随应用'),
  day('日间'),
  night('夜间');

  const ReaderThemeMode(this.label);
  final String label;
}

class ReaderLook {
  const ReaderLook({
    this.paper = ReaderPaper.system,
    this.theme,
    this.backgroundImage,
    this.baseColor,
    this.textColor,
    this.accent,
    this.highlight,
  });

  final ReaderPaper paper;
  final ReaderThemeSelection? theme;
  final String? backgroundImage;
  final Color? baseColor, textColor, accent, highlight;
  String get choiceKey =>
      theme == null ? 'paper:${paper.name}' : 'theme:${theme!.id}';
  String get label => theme?.name ?? paper.label;
  bool sameChoice(ReaderLook other) =>
      theme?.id == other.theme?.id &&
      (theme != null || paper == other.paper) &&
      backgroundImage == other.backgroundImage &&
      theme?.imageUrl == other.theme?.imageUrl;

  Map<String, Object?> toJson() => {
    'paper': paper.name,
    if (baseColor != null) 'baseColor': baseColor!.toARGB32(),
    if (textColor != null) 'textColor': textColor!.toARGB32(),
    if (accent != null) 'accent': accent!.toARGB32(),
    if (highlight != null) 'highlight': highlight!.toARGB32(),
    if (theme != null) 'theme': theme!.toJson(),
    if (backgroundImage != null) 'backgroundImage': backgroundImage,
  };

  factory ReaderLook.fromJson(Map<String, dynamic> json) {
    final image = json['backgroundImage'];
    if (image != null && !validBackgroundId(image)) {
      throw const FormatException('阅读背景记录有误');
    }
    final rawTheme = json['theme'];
    return ReaderLook(
      paper:
          ReaderPaper.values
              .where((paper) => paper.name == json['paper'])
              .firstOrNull ??
          ReaderPaper.system,
      theme: rawTheme == null
          ? null
          : ReaderThemeSelection.fromJson(rawTheme as Map<String, dynamic>),
      backgroundImage: image as String?,
      baseColor: json['baseColor'] is int ? Color(json['baseColor']) : null,
      textColor: json['textColor'] is int ? Color(json['textColor']) : null,
      accent: json['accent'] is int ? Color(json['accent']) : null,
      highlight: json['highlight'] is int ? Color(json['highlight']) : null,
    );
  }
}

enum ReaderMode {
  scroll('上下滚动'),
  paged('横排翻页'),
  vertical('竖排翻页');

  const ReaderMode(this.label);
  final String label;
  bool get paginated => this != scroll;
}

enum ReaderVerticalLatinOrientation {
  rotated('随文旋转'),
  upright('逐字直立');

  const ReaderVerticalLatinOrientation(this.label);
  final String label;
}

/// Stored layout keys may also carry typography and content-filter suffixes.
/// Read the mode token rather than requiring it to be the last field.
bool readerLayoutIsPaginated(String layout) => layout
    .split('|')
    .any(
      (section) =>
          !section.startsWith('languages=') &&
          section
              .split(':')
              .any((part) => part == 'paged' || part == 'vertical'),
    );

enum ReaderTapLayout {
  standard('常规'),
  rightHand('右手'),
  leftHand('左手');

  const ReaderTapLayout(this.label);
  final String label;
}

enum ReaderPageEffect {
  staggered('段落接续'),
  none('无动画'),
  slide('平移'),
  cover('覆盖'),
  paper('纸页翻动'),
  fade('渐隐'),
  parallax('视差（实验）');

  const ReaderPageEffect(this.label);
  final String label;
  Duration get duration => switch (this) {
    staggered => const Duration(milliseconds: 620),
    none => Duration.zero,
    slide => const Duration(milliseconds: 300),
    cover => const Duration(milliseconds: 340),
    paper => const Duration(milliseconds: 440),
    fade => const Duration(milliseconds: 300),
    parallax => const Duration(milliseconds: 340),
  };
}

enum ReaderPageSpeed {
  // 越靠前越慢。已有 relaxed/normal/quick 的名称与倍率保持不变，保证旧记录可解析。
  slowest('极缓', 2),
  relaxed('舒缓', 1.35),
  normal('标准', 1),
  quick('利落', .7),
  fastest('极速', .5);

  const ReaderPageSpeed(this.label, this.durationScale);
  final String label;
  final double durationScale;

  Duration durationFor(ReaderPageEffect effect) => Duration(
    microseconds: (effect.duration.inMicroseconds * durationScale).round(),
  );
}

enum ReaderTextWeight {
  light('细体', FontWeight.w300),
  regular('常规', FontWeight.w400),
  medium('适中', FontWeight.w500),
  bold('加粗', FontWeight.w600);

  const ReaderTextWeight(this.label, this.weight);
  final String label;
  final FontWeight weight;
}

enum ReaderTitlePosition {
  start('左对齐'),
  center('居中'),
  hidden('隐藏标题');

  const ReaderTitlePosition(this.label);
  final String label;
}

/// 正文内图片的点按行为。默认沿用「点按查看大图」；选「禁用点按」后正文图片
/// 不再拦截点按，让点按落到翻页 / 控件切换的可点区域上。
enum ReaderImageTap {
  open('查看大图'),
  switchChrome('显示/隐藏控件'),
  none('禁用点按');

  const ReaderImageTap(this.label);
  final String label;
}

/// Reader-only settings: changing paper never changes the rest of the app.
class ReaderPreferences {
  const ReaderPreferences({
    this.paper = ReaderPaper.system,
    this.theme,
    this.nightLook,
    this.themeMode = ReaderThemeMode.follow,
    this.recentLooks = const [],
    this.dayShelf = const [],
    this.nightShelf = const [],
    this.margin = 26,
    this.marginLeft,
    this.marginRight,
    this.marginTop = 8,
    this.marginBottom = 8,
    this.paragraphGap = 12,
    this.paragraphGapOverride = false,
    this.catalogueReversed = false,
    this.indentCount = 0,
    this.justify = false,
    this.italic = false,
    this.tapPaging = false,
    this.tapBothSidesNext = false,
    this.volumePaging = false,
    this.brightness,
    this.autoScrollSpeed = 24,
    this.mode = ReaderMode.scroll,
    this.verticalLatinOrientation = ReaderVerticalLatinOrientation.rotated,
    this.tapLayout = ReaderTapLayout.standard,
    this.edgeBrightness = false,
    this.pageEffect = ReaderPageEffect.staggered,
    this.pageSpeed = ReaderPageSpeed.normal,
    this.hideSystemStatus = false,
    this.showStatusInfo = true,
    this.chapterEntrance = false,
    this.nightTextBrightness = .82,
    this.letterSpacing = .1,
    this.textWeight = ReaderTextWeight.regular,
    this.titleScale = 1.2,
    this.titleWeight = ReaderTextWeight.bold,
    this.titlePosition = ReaderTitlePosition.start,
    this.titleTopSpacing = 0,
    this.titleBottomSpacing = 28,
    this.imageTap = ReaderImageTap.open,
    this.statusSideInset = 0,
    this.statusFontSize = 12,
    this.statusTopOffset = 0,
    this.backgroundImage,
    this.backgroundOpacity = .18,
    this.backgroundFit = BoxFit.cover,
    this.headerTips = const [ReaderTip.none, ReaderTip.none, ReaderTip.none],
    this.footerTips = const [ReaderTip.none, ReaderTip.none, ReaderTip.none],
    this.headerPadding = EdgeInsets.zero,
    this.footerPadding = EdgeInsets.zero,
    this.dockActions = defaultDockActions,
  });
  final ReaderPaper paper;

  /// Legado 远程主题；存在时覆盖 [paper] 的底色和文字色。
  final ReaderThemeSelection? theme;
  final ReaderLook? nightLook;
  final ReaderThemeMode themeMode;
  final List<ReaderLook> recentLooks;
  final List<ReaderLook> dayShelf, nightShelf;

  List<ReaderLook> shelf(bool night) {
    final active = lookFor(night);
    final saved = night ? nightShelf : dayShelf;
    return <String, ReaderLook>{
      if (saved.isEmpty)
        for (final paper
            in (night
                ? [
                    ReaderPaper.system,
                    ReaderPaper.night,
                    ReaderPaper.legadoWechat,
                  ]
                : [
                    ReaderPaper.system,
                    ReaderPaper.milk,
                    ReaderPaper.parchment,
                    ReaderPaper.sage,
                    ReaderPaper.legadoWechat,
                  ]))
          'paper:${paper.name}': ReaderLook(paper: paper),
      for (final look in night ? nightShelf : dayShelf) look.choiceKey: look,
      active.choiceKey: active,
    }.values.toList();
  }

  ReaderPreferences saveCard(bool night, ReaderLook look) {
    final cards = <String, ReaderLook>{
      for (final card in shelf(night)) card.choiceKey: card,
      look.choiceKey: look,
    }.values.toList();
    final updated = night
        ? copyWith(nightShelf: cards)
        : copyWith(dayShelf: cards);
    return lookFor(night).choiceKey == look.choiceKey
        ? updated.setLook(night, look, remember: false)
        : updated;
  }

  ReaderPreferences removeCard(bool night, ReaderLook look) {
    final cards = shelf(night);
    if (cards.length <= 1 ||
        !cards.any((card) => card.choiceKey == look.choiceKey))
      return this;
    final remaining = cards
        .where((card) => card.choiceKey != look.choiceKey)
        .toList();
    final next = lookFor(night).choiceKey == look.choiceKey
        ? setLook(night, remaining.first, remember: false)
        : this;
    return night
        ? next.copyWith(nightShelf: remaining)
        : next.copyWith(dayShelf: remaining);
  }

  Iterable<ReaderLook> recentFor(bool night) =>
      recentLooks.where((look) => !look.sameChoice(lookFor(night))).take(4);

  bool usesNight(bool appDark) => switch (themeMode) {
    ReaderThemeMode.follow => appDark,
    ReaderThemeMode.day => false,
    ReaderThemeMode.night => true,
  };

  ReaderLook lookFor(bool night) {
    final active = night && nightLook != null
        ? nightLook!
        : ReaderLook(
            paper: paper,
            theme: theme,
            backgroundImage: backgroundImage,
          );
    final saved = (night ? nightShelf : dayShelf)
        .where((card) => card.choiceKey == active.choiceKey)
        .firstOrNull;
    return saved == null
        ? active
        : ReaderLook(
            paper: active.paper,
            theme: active.theme,
            backgroundImage: active.backgroundImage,
            baseColor: saved.baseColor,
            textColor: saved.textColor,
            accent: saved.accent,
            highlight: saved.highlight,
          );
  }

  ReaderPreferences setLook(
    bool night,
    ReaderLook look, {
    bool remember = true,
  }) {
    final previous = lookFor(night);
    final history = remember && !look.sameChoice(previous)
        ? <ReaderLook>[
            look,
            previous,
            ...recentLooks.where(
              (item) => !item.sameChoice(previous) && !item.sameChoice(look),
            ),
          ].take(5).toList(growable: false)
        : recentLooks;
    if (night) return copyWith(nightLook: look, recentLooks: history);
    return copyWith(
      paper: look.paper,
      theme: look.theme,
      backgroundImage: look.backgroundImage,
      clearBackground: look.backgroundImage == null,
      nightLook: lookFor(true),
      recentLooks: history,
    );
  }

  ReaderPreferences removeBackground(String image) {
    final used =
        backgroundImage == image ||
        nightLook?.backgroundImage == image ||
        recentLooks.any((look) => look.backgroundImage == image);
    if (!used) return this;
    final night = nightLook;
    return copyWith(
      clearBackground: backgroundImage == image,
      nightLook: night != null && night.backgroundImage == image
          ? ReaderLook(paper: night.paper, theme: night.theme)
          : night,
      recentLooks: recentLooks
          .where((look) => look.backgroundImage != image)
          .toList(),
    );
  }

  final double margin, paragraphGap, autoScrollSpeed;
  final bool paragraphGapOverride, catalogueReversed;
  // Null horizontal edges preserve old records and existing margin callers.
  final double? marginLeft, marginRight;
  final double marginTop, marginBottom;
  double get leftMargin => marginLeft ?? margin;
  double get rightMargin => marginRight ?? margin;
  double get bindingMargin => (leftMargin + rightMargin) / 2;

  /// 首行缩进字符数；0 表示不缩进。旧记录中的 `indent` 布尔值按 2 字迁移。
  final int indentCount;
  bool get indent => indentCount > 0;
  final bool justify, italic, tapPaging, tapBothSidesNext, volumePaging;
  final double? brightness;
  final ReaderMode mode;
  final ReaderVerticalLatinOrientation verticalLatinOrientation;
  final ReaderTapLayout tapLayout;
  final bool edgeBrightness;
  final ReaderPageEffect pageEffect;
  final ReaderPageSpeed pageSpeed;
  final bool hideSystemStatus;
  final bool showStatusInfo;
  bool get showReaderStatus => hideSystemStatus && showStatusInfo;
  final bool chapterEntrance;
  final double nightTextBrightness;
  final double letterSpacing;
  final ReaderTextWeight textWeight;

  /// 标题字号相对正文的倍数、字重、位置和上下留白。
  final double titleScale, titleTopSpacing, titleBottomSpacing;
  final ReaderTextWeight titleWeight;
  final ReaderTitlePosition titlePosition;
  final ReaderImageTap imageTap;
  final double statusSideInset;
  final double statusFontSize, statusTopOffset;
  final String? backgroundImage;
  final double backgroundOpacity;
  final BoxFit backgroundFit;

  /// 页眉三槽（左 / 中 / 右）显示的信息位，默认全不显示，沿用现有布局。
  final List<ReaderTip> headerTips;

  /// 页脚三槽（左 / 中 / 右）显示的信息位，默认全不显示，沿用现有布局。
  final List<ReaderTip> footerTips;

  /// 页眉 / 页脚信息条各自的上下左右内边距。
  final EdgeInsets headerPadding;
  final EdgeInsets footerPadding;

  /// 底部阅读栏显示的动作 id 列表（可自定义、可增删，见阅读器「更多」）。
  final List<String> dockActions;

  /// 底部栏默认动作：目录 / 书签 / 听书 / 换源 / 设置。
  static const List<String> defaultDockActions = [
    'catalogue',
    'bookmarks',
    'listening',
    'source',
    'settings',
  ];

  /// 固定的页眉槽位：左侧显示章节名（用户不再配置）。
  static const List<ReaderTip> fixedHeaderTips = [
    ReaderTip(value: ReaderTipValue.chapterTitle),
    ReaderTip.none,
    ReaderTip.none,
  ];

  /// 固定的页脚槽位：左页码 / 中书名 / 右时间+电量（用户不再配置）。
  static const List<ReaderTip> fixedFooterTips = [
    ReaderTip(value: ReaderTipValue.page),
    ReaderTip(value: ReaderTipValue.bookName),
    ReaderTip(value: ReaderTipValue.timeBattery),
  ];

  /// 是否配置了任意自定义页眉 / 页脚；未配置时渲染层保持原有状态行。
  bool get hasCustomHeaderFooter =>
      headerTips.any((t) => t.value != ReaderTipValue.none) ||
      footerTips.any((t) => t.value != ReaderTipValue.none);

  bool get showTitle => titlePosition != ReaderTitlePosition.hidden;
  TextAlign get titleTextAlign => titlePosition == ReaderTitlePosition.center
      ? TextAlign.center
      : TextAlign.start;
  TextStyle titleStyle(TextStyle base) => base.copyWith(
    fontSize: (base.fontSize ?? 19) * titleScale,
    height: 1.35,
    fontWeight: titleWeight.weight,
    color: base.color?.withValues(alpha: .9),
  );

  String get layoutKey {
    final geometry =
        leftMargin == 26 &&
            rightMargin == 26 &&
            marginTop == 8 &&
            marginBottom == 8 &&
            paragraphGap == 12 &&
            indentCount == 0 &&
            !justify &&
            mode == ReaderMode.scroll
        ? ''
        : '${leftMargin == rightMargin && marginTop == 8 && marginBottom == 8 ? '$leftMargin' : '$leftMargin,$marginTop,$rightMargin,$marginBottom'}:$paragraphGap:$indentCount:$justify';
    final modeKey = mode == ReaderMode.scroll ? '' : ':${mode.name}';
    final gapKey = paragraphGapOverride ? ':gap=custom' : '';
    final textKey =
        letterSpacing == .1 && textWeight == ReaderTextWeight.regular && !italic
        ? ''
        : ':text=$letterSpacing,${textWeight.name}${italic ? ',italic' : ''}';
    final titleKey =
        titleScale == 1.2 &&
            titleWeight == ReaderTextWeight.bold &&
            titlePosition == ReaderTitlePosition.start &&
            titleTopSpacing == 0 &&
            titleBottomSpacing == 28
        ? ''
        : ':title=$titleScale,${titleWeight.name},${titlePosition.name},$titleTopSpacing,$titleBottomSpacing';
    if (mode == ReaderMode.vertical &&
        verticalLatinOrientation == ReaderVerticalLatinOrientation.upright) {
      return '$geometry$gapKey$textKey$titleKey:latin=upright$modeKey';
    }
    // Existing preferences retain exactly the same persisted layout key.
    return '$geometry$gapKey$modeKey$textKey$titleKey';
  }

  Color background(bool appDark) {
    final dark = usesNight(appDark);
    final look = lookFor(dark);
    final paper = look.paper;
    if (look.baseColor != null) return look.baseColor!;
    if (look.theme case final selected?) {
      return dark ? selected.nightBackground : selected.background;
    }
    if (paper == ReaderPaper.system) {
      return dark ? ArchiveDesign.darkBackground : const Color(0xFFF7F7F2);
    }
    final backgroundColor = paper.background ?? const Color(0xFFF7F7F2);
    return dark ? paper.nightBackground ?? backgroundColor : backgroundColor;
  }

  Color controlForeground(bool appDark) {
    final dark = usesNight(appDark);
    final look = lookFor(dark);
    final paper = look.paper;
    if (look.textColor != null) return look.textColor!;
    if (look.theme case final selected?) {
      return dark ? selected.nightInk : selected.ink;
    }
    final themedInk = dark ? paper.nightInk ?? paper.ink : paper.ink;
    if (themedInk != null) return themedInk;
    return darkPaper(appDark) ? ArchiveDesign.darkInk : const Color(0xFF30352F);
  }

  bool darkPaper(bool dark) =>
      ThemeData.estimateBrightnessForColor(background(dark)) == Brightness.dark;

  Color foreground(bool dark) {
    final look = lookFor(usesNight(dark));
    if (look.textColor != null) return look.textColor!;
    return look.theme == null && look.paper.ink == null && darkPaper(dark)
        ? Color.lerp(
            background(dark),
            controlForeground(dark),
            nightTextBrightness,
          )!
        : controlForeground(dark);
  }

  Map<String, Object?> toJson() => {
    if (nightLook != null) 'nightLook': nightLook!.toJson(),
    if (dayShelf.isNotEmpty)
      'dayShelf': dayShelf.map((card) => card.toJson()).toList(),
    if (nightShelf.isNotEmpty)
      'nightShelf': nightShelf.map((card) => card.toJson()).toList(),
    if (themeMode != ReaderThemeMode.follow) 'themeMode': themeMode.name,
    if (recentLooks.isNotEmpty)
      'recentLooks': [for (final look in recentLooks) look.toJson()],
    'paper': paper.name,
    if (theme != null) 'theme': theme!.toJson(),
    'margin': margin,
    if (marginLeft != null) 'marginLeft': marginLeft,
    if (marginRight != null) 'marginRight': marginRight,
    'marginTop': marginTop,
    'marginBottom': marginBottom,
    'paragraphGap': paragraphGap,
    if (paragraphGapOverride || paragraphGap != 12)
      'paragraphGapOverride': paragraphGapOverride,
    if (catalogueReversed) 'catalogueReversed': true,
    'indent': indent,
    'indentCount': indentCount,
    'justify': justify,
    'italic': italic,
    'tapPaging': tapPaging,
    'tapBothSidesNext': tapBothSidesNext,
    'volumePaging': volumePaging,
    'brightness': brightness,
    'autoScrollSpeed': autoScrollSpeed,
    'mode': mode.name,
    'verticalLatinOrientation': verticalLatinOrientation.name,
    'tapLayout': tapLayout.name,
    'edgeBrightness': edgeBrightness,
    'pageEffect': pageEffect.name,
    'pageSpeed': pageSpeed.name,
    'hideSystemStatus': hideSystemStatus,
    'showStatusInfo': showStatusInfo,
    'chapterEntrance': chapterEntrance,
    'nightTextBrightness': nightTextBrightness,
    'letterSpacing': letterSpacing,
    'textWeight': textWeight.name,
    'titleScale': titleScale,
    'titleWeight': titleWeight.name,
    'titlePosition': titlePosition.name,
    'titleTopSpacing': titleTopSpacing,
    'titleBottomSpacing': titleBottomSpacing,
    'imageTap': imageTap.name,
    'statusSideInset': statusSideInset,
    'statusFontSize': statusFontSize,
    'statusTopOffset': statusTopOffset,
    if (backgroundImage != null) 'backgroundImage': backgroundImage,
    'backgroundOpacity': backgroundOpacity,
    'backgroundFit': backgroundFit.name,
    'headerTips': [for (final tip in headerTips) tip.toJson()],
    'footerTips': [for (final tip in footerTips) tip.toJson()],
    'headerPadding': [
      headerPadding.left,
      headerPadding.top,
      headerPadding.right,
      headerPadding.bottom,
    ],
    'footerPadding': [
      footerPadding.left,
      footerPadding.top,
      footerPadding.right,
      footerPadding.bottom,
    ],
    'dockActions': dockActions,
  };
  factory ReaderPreferences.fromJson(Map<String, dynamic> json) {
    double number(String key, double min, double max, double fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw const FormatException('阅读偏好数值超出范围');
      }
      return value.toDouble();
    }

    for (final key in [
      'indent',
      'justify',
      'italic',
      'tapPaging',
      'tapBothSidesNext',
      'volumePaging',
      'edgeBrightness',
      'hideSystemStatus',
      'showStatusInfo',
      'chapterEntrance',
      'paragraphGapOverride',
      'catalogueReversed',
    ]) {
      if (json[key] != null && json[key] is! bool) {
        throw const FormatException('阅读偏好格式有误');
      }
    }
    if (json['backgroundImage'] != null &&
        !validBackgroundId(json['backgroundImage'])) {
      throw const FormatException('阅读背景记录有误');
    }
    final rawTheme = json['theme'];
    if (rawTheme != null && rawTheme is! Map) {
      throw const FormatException('阅读主题记录有误');
    }
    final theme = rawTheme is Map
        ? ReaderThemeSelection.fromJson(Map<String, dynamic>.from(rawTheme))
        : null;
    return ReaderPreferences(
      paper: ReaderPaper.values.firstWhere(
        (p) => p.name == (json['paper'] ?? 'system'),
        // 旧版本曾保存预设 1–5，移除后回退到跟随外观，避免整条偏好解析失败。
        orElse: () => ReaderPaper.system,
      ),
      theme: theme,
      nightLook: json['nightLook'] == null
          ? null
          : ReaderLook.fromJson(json['nightLook'] as Map<String, dynamic>),
      dayShelf: [
        for (final item in json['dayShelf'] as List? ?? const [])
          ReaderLook.fromJson(item as Map<String, dynamic>),
      ],
      nightShelf: [
        for (final item in json['nightShelf'] as List? ?? const [])
          ReaderLook.fromJson(item as Map<String, dynamic>),
      ],
      recentLooks: [
        for (final look
            in (json['recentLooks'] as List? ?? const [])
                .whereType<Map<String, dynamic>>()
                .take(5))
          ReaderLook.fromJson(look),
      ],
      themeMode: ReaderThemeMode.values.byName(json['themeMode'] ?? 'follow'),
      margin: number('margin', 0, 200, 26),
      marginLeft: json['marginLeft'] == null
          ? null
          : number('marginLeft', 0, 200, 26),
      marginRight: json['marginRight'] == null
          ? null
          : number('marginRight', 0, 200, 26),
      marginTop: number('marginTop', 0, 200, 8),
      marginBottom: number('marginBottom', 0, 200, 8),
      paragraphGap: number('paragraphGap', 0, 32, 12),
      paragraphGapOverride:
          json['paragraphGapOverride'] as bool? ??
          number('paragraphGap', 0, 32, 12) != 12,
      catalogueReversed: json['catalogueReversed'] == true,
      indentCount: json['indentCount'] == null
          ? (json['indent'] == true ? 2 : 0)
          : number('indentCount', 0, 4, 0).toInt(),
      justify: json['justify'] == true,
      italic: json['italic'] == true,
      tapPaging: json['tapPaging'] == true,
      tapBothSidesNext: json['tapBothSidesNext'] == true,
      volumePaging: json['volumePaging'] == true,
      brightness: json['brightness'] == null
          ? null
          : number('brightness', 0, 1, 1),
      nightTextBrightness: number('nightTextBrightness', .35, 1, .82),
      letterSpacing: number('letterSpacing', -.5, 3, .1),
      textWeight: ReaderTextWeight.values.byName(
        json['textWeight'] ?? 'regular',
      ),
      titleScale: number('titleScale', .6, 2.5, 1.2),
      titleWeight: ReaderTextWeight.values.byName(
        json['titleWeight'] ?? 'bold',
      ),
      titlePosition: ReaderTitlePosition.values.byName(
        json['titlePosition'] ?? 'start',
      ),
      titleTopSpacing: number('titleTopSpacing', 0, 200, 0),
      titleBottomSpacing: number('titleBottomSpacing', 0, 200, 28),
      imageTap: ReaderImageTap.values.byName(json['imageTap'] ?? 'open'),
      statusSideInset: number('statusSideInset', 0, 96, 0),
      statusFontSize: number('statusFontSize', 9, 18, 12),
      statusTopOffset: number('statusTopOffset', -8, 24, 0),
      backgroundImage: json['backgroundImage'] as String?,
      backgroundOpacity: number('backgroundOpacity', .05, 1, .18),
      backgroundFit: (json['backgroundFit'] ?? 'cover') == 'contain'
          ? BoxFit.contain
          : BoxFit.cover,
      autoScrollSpeed: number('autoScrollSpeed', 8, 80, 24),
      mode: ReaderMode.values.byName(json['mode'] ?? 'scroll'),
      verticalLatinOrientation: ReaderVerticalLatinOrientation.values.byName(
        json['verticalLatinOrientation'] ?? 'rotated',
      ),
      tapLayout: ReaderTapLayout.values.byName(json['tapLayout'] ?? 'standard'),
      edgeBrightness: json['edgeBrightness'] == true,
      hideSystemStatus: json['hideSystemStatus'] == true,
      showStatusInfo: json['showStatusInfo'] != false,
      chapterEntrance: json['chapterEntrance'] == true,
      pageEffect: ReaderPageEffect.values.firstWhere(
        (effect) => effect.name == (json['pageEffect'] ?? 'staggered'),
        orElse: () => ReaderPageEffect.staggered,
      ),
      pageSpeed: ReaderPageSpeed.values.byName(json['pageSpeed'] ?? 'normal'),
      headerTips: _readerTipsFromJson(json['headerTips']),
      footerTips: _readerTipsFromJson(json['footerTips']),
      headerPadding: _edgeInsetsFromJson(json['headerPadding']),
      footerPadding: _edgeInsetsFromJson(json['footerPadding']),
      dockActions: _dockActionsFromJson(json['dockActions']),
    );
  }

  static EdgeInsets _edgeInsetsFromJson(Object? raw) {
    if (raw is List && raw.length >= 4) {
      double v(int i) => (raw[i] is num) ? (raw[i] as num).toDouble() : 0;
      return EdgeInsets.fromLTRB(v(0), v(1), v(2), v(3));
    }
    return EdgeInsets.zero;
  }

  static List<String> _dockActionsFromJson(Object? raw) {
    if (raw is List) {
      final ids = <String>[
        for (final item in raw)
          if (item is String) item,
      ];
      if (ids.isNotEmpty) return List<String>.unmodifiable(ids);
    }
    return defaultDockActions;
  }

  static List<ReaderTip> _readerTipsFromJson(Object? raw) {
    if (raw is! List) {
      return const [ReaderTip.none, ReaderTip.none, ReaderTip.none];
    }
    final tips = <ReaderTip>[
      for (final item in raw)
        item is Map<String, dynamic>
            ? ReaderTip.fromJson(item)
            : ReaderTip.none,
    ];
    while (tips.length < 3) {
      tips.add(ReaderTip.none);
    }
    return List<ReaderTip>.unmodifiable(tips.take(3));
  }

  static ReaderPreferences fromRecord(Object? record) {
    try {
      return ReaderPreferences.fromJson(jsonDecode(record as String));
    } catch (_) {
      return const ReaderPreferences();
    }
  }

  ReaderPreferences copyWith({
    ReaderLook? nightLook,
    List<ReaderLook>? recentLooks,
    List<ReaderLook>? dayShelf,
    List<ReaderLook>? nightShelf,
    ReaderThemeMode? themeMode,
    ReaderPaper? paper,
    ReaderThemeSelection? theme,
    bool clearTheme = false,
    bool clearThemeImage = false,
    double? margin,
    double? marginLeft,
    double? marginRight,
    double? marginTop,
    double? marginBottom,
    double? paragraphGap,
    bool? paragraphGapOverride,
    bool? catalogueReversed,
    int? indentCount,
    bool? indent,
    bool? justify,
    bool? italic,
    bool? tapPaging,
    bool? tapBothSidesNext,
    bool? volumePaging,
    double? brightness,
    bool systemBrightness = false,
    double? autoScrollSpeed,
    ReaderMode? mode,
    ReaderVerticalLatinOrientation? verticalLatinOrientation,
    ReaderTapLayout? tapLayout,
    bool? edgeBrightness,
    ReaderPageEffect? pageEffect,
    ReaderPageSpeed? pageSpeed,
    bool? hideSystemStatus,
    bool? showStatusInfo,
    bool? chapterEntrance,
    double? nightTextBrightness,
    double? letterSpacing,
    ReaderTextWeight? textWeight,
    double? titleScale,
    ReaderTextWeight? titleWeight,
    ReaderTitlePosition? titlePosition,
    double? titleTopSpacing,
    double? titleBottomSpacing,
    ReaderImageTap? imageTap,
    double? statusSideInset,
    double? statusFontSize,
    double? statusTopOffset,
    String? backgroundImage,
    bool clearBackground = false,
    double? backgroundOpacity,
    BoxFit? backgroundFit,
    List<ReaderTip>? headerTips,
    List<ReaderTip>? footerTips,
    List<String>? dockActions,
    EdgeInsets? headerPadding,
    EdgeInsets? footerPadding,
  }) => ReaderPreferences(
    nightLook: nightLook ?? this.nightLook,
    recentLooks: recentLooks ?? this.recentLooks,
    dayShelf: dayShelf ?? this.dayShelf,
    nightShelf: nightShelf ?? this.nightShelf,
    themeMode: themeMode ?? this.themeMode,
    paper: paper ?? this.paper,
    theme: clearTheme || (paper != null && theme == null)
        ? null
        : clearThemeImage
        ? (theme ?? this.theme)?.withoutImage
        : theme ?? this.theme,
    margin: margin ?? this.margin,
    marginLeft: marginLeft ?? (margin ?? this.marginLeft),
    marginRight: marginRight ?? (margin ?? this.marginRight),
    marginTop: marginTop ?? this.marginTop,
    marginBottom: marginBottom ?? this.marginBottom,
    paragraphGap: paragraphGap ?? this.paragraphGap,
    paragraphGapOverride: paragraphGapOverride ?? this.paragraphGapOverride,
    catalogueReversed: catalogueReversed ?? this.catalogueReversed,
    indentCount:
        indentCount ?? (indent == null ? this.indentCount : (indent ? 2 : 0)),
    justify: justify ?? this.justify,
    italic: italic ?? this.italic,
    tapPaging: tapPaging ?? this.tapPaging,
    tapBothSidesNext: tapBothSidesNext ?? this.tapBothSidesNext,
    volumePaging: volumePaging ?? this.volumePaging,
    brightness: systemBrightness ? null : brightness ?? this.brightness,
    autoScrollSpeed: autoScrollSpeed ?? this.autoScrollSpeed,
    mode: mode ?? this.mode,
    verticalLatinOrientation:
        verticalLatinOrientation ?? this.verticalLatinOrientation,
    tapLayout: tapLayout ?? this.tapLayout,
    edgeBrightness: edgeBrightness ?? this.edgeBrightness,
    pageEffect: pageEffect ?? this.pageEffect,
    pageSpeed: pageSpeed ?? this.pageSpeed,
    hideSystemStatus: hideSystemStatus ?? this.hideSystemStatus,
    showStatusInfo: showStatusInfo ?? this.showStatusInfo,
    chapterEntrance: chapterEntrance ?? this.chapterEntrance,
    nightTextBrightness: nightTextBrightness ?? this.nightTextBrightness,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    textWeight: textWeight ?? this.textWeight,
    titleScale: titleScale ?? this.titleScale,
    titleWeight: titleWeight ?? this.titleWeight,
    titlePosition: titlePosition ?? this.titlePosition,
    titleTopSpacing: titleTopSpacing ?? this.titleTopSpacing,
    titleBottomSpacing: titleBottomSpacing ?? this.titleBottomSpacing,
    imageTap: imageTap ?? this.imageTap,
    statusSideInset: statusSideInset ?? this.statusSideInset,
    statusFontSize: statusFontSize ?? this.statusFontSize,
    statusTopOffset: statusTopOffset ?? this.statusTopOffset,
    backgroundImage: clearBackground
        ? null
        : backgroundImage ?? this.backgroundImage,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    backgroundFit: backgroundFit ?? this.backgroundFit,
    headerTips: headerTips ?? this.headerTips,
    footerTips: footerTips ?? this.footerTips,
    dockActions: dockActions ?? this.dockActions,
    headerPadding: headerPadding ?? this.headerPadding,
    footerPadding: footerPadding ?? this.footerPadding,
  );

  /// A book can keep its typography while interaction and device settings
  /// continue to follow the shared reader. Explicit null margins stay null.
  ReaderPreferences withLayoutOf(ReaderPreferences layout) => ReaderPreferences(
    nightLook: layout.nightLook,
    recentLooks: layout.recentLooks,
    dayShelf: layout.dayShelf,
    nightShelf: layout.nightShelf,
    themeMode: layout.themeMode,
    paper: layout.paper,
    theme: layout.theme,
    margin: layout.margin,
    marginLeft: layout.marginLeft,
    marginRight: layout.marginRight,
    marginTop: layout.marginTop,
    marginBottom: layout.marginBottom,
    paragraphGap: layout.paragraphGap,
    paragraphGapOverride: layout.paragraphGapOverride,
    catalogueReversed: catalogueReversed,
    indentCount: layout.indentCount,
    justify: layout.justify,
    italic: layout.italic,
    mode: layout.mode,
    verticalLatinOrientation: layout.verticalLatinOrientation,
    nightTextBrightness: layout.nightTextBrightness,
    letterSpacing: layout.letterSpacing,
    textWeight: layout.textWeight,
    titleScale: layout.titleScale,
    titleWeight: layout.titleWeight,
    titlePosition: layout.titlePosition,
    titleTopSpacing: layout.titleTopSpacing,
    titleBottomSpacing: layout.titleBottomSpacing,
    backgroundImage: layout.backgroundImage,
    backgroundOpacity: layout.backgroundOpacity,
    backgroundFit: layout.backgroundFit,
    tapPaging: tapPaging,
    tapBothSidesNext: tapBothSidesNext,
    volumePaging: volumePaging,
    brightness: brightness,
    autoScrollSpeed: autoScrollSpeed,
    tapLayout: tapLayout,
    edgeBrightness: edgeBrightness,
    pageEffect: pageEffect,
    pageSpeed: pageSpeed,
    imageTap: imageTap,
    hideSystemStatus: hideSystemStatus,
    showStatusInfo: showStatusInfo,
    chapterEntrance: chapterEntrance,
    statusSideInset: statusSideInset,
    statusFontSize: statusFontSize,
    statusTopOffset: statusTopOffset,
    headerTips: headerTips,
    footerTips: footerTips,
    headerPadding: headerPadding,
    footerPadding: footerPadding,
    dockActions: dockActions,
  );
}
