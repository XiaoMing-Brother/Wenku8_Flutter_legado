import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

Color readerCardOutline(Color paper, {Color? accent}) {
  if (accent != null) return accent;
  final tone = HSLColor.fromColor(paper);
  return tone
      .withLightness(
        tone.lightness > .5 ? tone.lightness * .62 : tone.lightness + .32,
      )
      .toColor();
}

/// Legado 内置阅读主题（清墨 LightInk 主题商店快照）的选择结果。
///
/// 主题数据来自 Legado 的 `assets/defaultData/readThemes.json`。这里保存
/// 已经解析好的日/夜颜色和图片地址，避免阅读偏好恢复时再次异步读取资源。
class ReaderThemeSelection {
  const ReaderThemeSelection({
    required this.id,
    required this.name,
    required this.background,
    required this.nightBackground,
    required this.ink,
    required this.nightInk,
    this.control,
    this.accent,
    this.nightAccent,
    this.chrome,
    this.nightChrome,
    this.imageUrl,
    this.textureAsset,
    this.nightTextureAsset,
  });

  final int id;
  final String name;
  final Color background, nightBackground, ink, nightInk;
  final Color? control;
  final Color? accent, nightAccent, chrome, nightChrome;
  final String? imageUrl;
  final String? textureAsset, nightTextureAsset;

  Color? accentFor(bool night) => night ? nightAccent : accent;
  Color? chromeFor(bool night) => night ? nightChrome ?? chrome : chrome;
  String? textureFor(bool night) =>
      night ? nightTextureAsset ?? textureAsset : textureAsset;
  bool get hasTexture => textureAsset != null || nightTextureAsset != null;

  ReaderThemeSelection get inverted => ReaderThemeSelection(
    id: id,
    name: name,
    background: nightBackground,
    nightBackground: background,
    ink: nightInk,
    control: control,
    nightInk: ink,
    accent: nightAccent,
    nightAccent: accent,
    chrome: nightChrome,
    nightChrome: chrome,
    imageUrl: imageUrl,
    textureAsset: nightTextureAsset,
    nightTextureAsset: textureAsset,
  );

  ReaderThemeSelection get withoutImage => ReaderThemeSelection(
    id: id,
    name: name,
    background: background,
    nightBackground: nightBackground,
    ink: ink,
    nightInk: nightInk,
    control: control,
    accent: accent,
    nightAccent: nightAccent,
    chrome: chrome,
    nightChrome: nightChrome,
  );

  List<String> get imageCandidates {
    final raw = imageUrl?.trim();
    if (raw == null || raw.isEmpty) return const [];
    const secureHost = 'https://minio.zhendong.ltd/';
    if (raw.startsWith(secureHost)) {
      return [
        raw,
        'http://minio.zhendong.ltd/${raw.substring(secureHost.length)}',
      ];
    }
    return [raw];
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'background': _argb(background),
    'nightBackground': _argb(nightBackground),
    'ink': _argb(ink),
    'nightInk': _argb(nightInk),
    if (control != null) 'control': _argb(control!),
    if (accent != null) 'accent': _argb(accent!),
    if (nightAccent != null) 'nightAccent': _argb(nightAccent!),
    if (chrome != null) 'chrome': _argb(chrome!),
    if (nightChrome != null) 'nightChrome': _argb(nightChrome!),
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (textureAsset != null) 'textureAsset': textureAsset,
    if (nightTextureAsset != null) 'nightTextureAsset': nightTextureAsset,
  };

  factory ReaderThemeSelection.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final background = json['background'];
    final nightBackground = json['nightBackground'];
    final ink = json['ink'];
    final nightInk = json['nightInk'];
    if (id is! num ||
        name is! String ||
        background is! num ||
        nightBackground is! num ||
        ink is! num ||
        nightInk is! num) {
      throw const FormatException('阅读主题记录有误');
    }
    return ReaderThemeSelection(
      id: id.toInt(),
      name: name,
      background: Color(background.toInt()),
      nightBackground: Color(nightBackground.toInt()),
      ink: Color(ink.toInt()),
      nightInk: Color(nightInk.toInt()),
      control: json['control'] is int ? Color(json['control'] as int) : null,
      accent: json['accent'] is int ? Color(json['accent'] as int) : null,
      nightAccent: json['nightAccent'] is int
          ? Color(json['nightAccent'] as int)
          : null,
      chrome: json['chrome'] is int ? Color(json['chrome'] as int) : null,
      nightChrome: json['nightChrome'] is int
          ? Color(json['nightChrome'] as int)
          : null,
      imageUrl: json['imageUrl'] is String ? json['imageUrl'] as String : null,
      textureAsset: json['textureAsset'] is String
          ? json['textureAsset'] as String
          : null,
      nightTextureAsset: json['nightTextureAsset'] is String
          ? json['nightTextureAsset'] as String
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderThemeSelection &&
      id == other.id &&
      name == other.name &&
      background == other.background &&
      nightBackground == other.nightBackground &&
      ink == other.ink &&
      nightInk == other.nightInk &&
      control == other.control &&
      accent == other.accent &&
      nightAccent == other.nightAccent &&
      chrome == other.chrome &&
      nightChrome == other.nightChrome &&
      imageUrl == other.imageUrl &&
      textureAsset == other.textureAsset &&
      nightTextureAsset == other.nightTextureAsset;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    background,
    nightBackground,
    ink,
    nightInk,
    control,
    accent,
    nightAccent,
    chrome,
    nightChrome,
    imageUrl,
    textureAsset,
    nightTextureAsset,
  );
}

/// Legado `readThemes.json` 中的一条主题。
class LegadoReaderTheme {
  const LegadoReaderTheme({
    required this.id,
    required this.name,
    required this.author,
    required this.downloadCount,
    this.control,
    this.secondary,
    this.directory,
    required this.background,
    required this.content,
    required this.imageUrl,
  });

  final int id;
  final String name, author;
  final int downloadCount;
  final Color? control, secondary, directory;
  final Color background, content;
  final String? imageUrl;

  bool get isNightTheme {
    if (ThemeData.estimateBrightnessForColor(background) != Brightness.dark) {
      return false;
    }
    return content.computeLuminance() > background.computeLuminance();
  }

  List<String> get imageCandidates {
    final raw = imageUrl?.trim();
    if (raw == null || raw.isEmpty) return const [];
    const host = 'http://minio.zhendong.ltd/';
    if (raw.startsWith(host)) {
      return ['https://minio.zhendong.ltd/${raw.substring(host.length)}', raw];
    }
    return [raw];
  }

  String? get thumbnailUrl => imageCandidates.firstOrNull;

  ReaderThemeSelection get selection {
    final nightBackground = _nightBackground(background);
    return ReaderThemeSelection(
      id: id,
      name: name,
      background: _opaque(background),
      nightBackground: nightBackground,
      ink: _readableInk(background, content),
      nightInk: _readableInk(nightBackground, content),
      control: control,
      imageUrl: thumbnailUrl,
    );
  }
}

class LegadoReaderThemes {
  LegadoReaderThemes._();

  static Future<List<LegadoReaderTheme>>? _pending;

  static Future<List<LegadoReaderTheme>> load() async {
    if (_pending case final pending?) return pending;
    final future = _parse(rootBundle.loadString('assets/reader_themes.json'));
    _pending = future;
    try {
      return await future;
    } catch (_) {
      if (identical(_pending, future)) _pending = null;
      rethrow;
    }
  }

  static Future<List<LegadoReaderTheme>> _parse(Future<String> source) async {
    final decoded = jsonDecode(await source);
    if (decoded is! List) {
      throw const FormatException('Legado 主题清单格式有误');
    }
    final themes = <LegadoReaderTheme>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'];
      final name = json['name'];
      if (id is! num || name is! String) continue;
      themes.add(
        LegadoReaderTheme(
          id: id.toInt(),
          name: name,
          author: json['author'] is String ? json['author'] as String : '',
          downloadCount: json['downloadCount'] is num
              ? (json['downloadCount'] as num).toInt()
              : 0,
          background: _parseColor(json['background'], const Color(0xFFF1F3F4)),
          control: _parseColor(json['control'], const Color(0xFF42704A)),
          secondary: _parseColor(json['secondary'], const Color(0xFF777777)),
          directory: _parseColor(json['foreground'], const Color(0xFFF1F3F4)),
          content: _parseColor(json['content'], const Color(0xFF2D2D33)),
          imageUrl:
              json['mipmap'] is String &&
                  (json['mipmap'] as String).trim().isNotEmpty
              ? (json['mipmap'] as String).trim()
              : null,
        ),
      );
    }
    return List<LegadoReaderTheme>.unmodifiable(themes);
  }
}

/// 随应用打包的纸纹主题：每套同时提供日间与夜间纸纹、正文色、强调色和
/// 页眉页脚色，切换外观时不需要联网下载背景图。
class ReaderPaperTheme {
  const ReaderPaperTheme({
    required this.id,
    required this.name,
    required this.dayTexture,
    required this.nightTexture,
    required this.dayPaper,
    required this.nightPaper,
    required this.dayInk,
    required this.nightInk,
    required this.dayAccent,
    required this.nightAccent,
    required this.dayChrome,
    required this.nightChrome,
  });

  final int id;
  final String name;
  final String dayTexture, nightTexture;
  final Color dayPaper, nightPaper, dayInk, nightInk;
  final Color dayAccent, nightAccent, dayChrome, nightChrome;

  String textureFor(bool night) => night ? nightTexture : dayTexture;
  Color paperFor(bool night) => night ? nightPaper : dayPaper;
  Color inkFor(bool night) => night ? nightInk : dayInk;
  Color accentFor(bool night) => night ? nightAccent : dayAccent;

  ReaderThemeSelection get selection => ReaderThemeSelection(
    id: id,
    name: name,
    background: dayPaper,
    nightBackground: nightPaper,
    ink: dayInk,
    nightInk: nightInk,
    control: dayAccent,
    accent: dayAccent,
    nightAccent: nightAccent,
    chrome: dayChrome,
    nightChrome: nightChrome,
    textureAsset: dayTexture,
    nightTextureAsset: nightTexture,
  );
}

/// 内置“纸间”主题。8 套主题共用 5 张日间、3 张夜间纸纹，并用不同的
/// 正文／强调／页眉页脚色区分。
const readerPaperThemes = <ReaderPaperTheme>[
  ReaderPaperTheme(
    id: -101,
    name: '米纸',
    dayTexture: 'assets/reader_paper/day_mist.jpg',
    nightTexture: 'assets/reader_paper/night_ink.jpg',
    dayPaper: Color(0xFFEFEEEC),
    nightPaper: Color(0xFF161616),
    dayInk: Color(0xFF35302A),
    nightInk: Color(0xFFE7E1D8),
    dayAccent: Color(0xFF8A5A3F),
    nightAccent: Color(0xFFC99573),
    dayChrome: Color(0xFF7A6F63),
    nightChrome: Color(0xFFB3A79A),
  ),
  ReaderPaperTheme(
    id: -102,
    name: '素纸',
    dayTexture: 'assets/reader_paper/day_cool.jpg',
    nightTexture: 'assets/reader_paper/night_charcoal.jpg',
    dayPaper: Color(0xFFF3F3F3),
    nightPaper: Color(0xFF181818),
    dayInk: Color(0xFF2F3234),
    nightInk: Color(0xFFE4E4E4),
    dayAccent: Color(0xFF4E6578),
    nightAccent: Color(0xFF93AFC4),
    dayChrome: Color(0xFF666D72),
    nightChrome: Color(0xFFA6A6A6),
  ),
  ReaderPaperTheme(
    id: -103,
    name: '雪纸',
    dayTexture: 'assets/reader_paper/day_snow.jpg',
    nightTexture: 'assets/reader_paper/night_charcoal.jpg',
    dayPaper: Color(0xFFF3F2F0),
    nightPaper: Color(0xFF181818),
    dayInk: Color(0xFF2C2B29),
    nightInk: Color(0xFFEAE6E2),
    dayAccent: Color(0xFF7D4E4E),
    nightAccent: Color(0xFFC09090),
    dayChrome: Color(0xFF6F6460),
    nightChrome: Color(0xFFB0A9A3),
  ),
  ReaderPaperTheme(
    id: -104,
    name: '净白',
    dayTexture: 'assets/reader_paper/day_clean.jpg',
    nightTexture: 'assets/reader_paper/night_navy.jpg',
    dayPaper: Color(0xFFF5F5F5),
    nightPaper: Color(0xFF121B2E),
    dayInk: Color(0xFF2E3033),
    nightInk: Color(0xFFE2E6ED),
    dayAccent: Color(0xFF6B5A40),
    nightAccent: Color(0xFFA8BEDB),
    dayChrome: Color(0xFF675F56),
    nightChrome: Color(0xFFA9B4C6),
  ),
  ReaderPaperTheme(
    id: -105,
    name: '雾蓝',
    dayTexture: 'assets/reader_paper/day_bluegrey.jpg',
    nightTexture: 'assets/reader_paper/night_navy.jpg',
    dayPaper: Color(0xFFDFE2E7),
    nightPaper: Color(0xFF121B2E),
    dayInk: Color(0xFF262B33),
    nightInk: Color(0xFFDDE4EE),
    dayAccent: Color(0xFF435A73),
    nightAccent: Color(0xFF8FAED1),
    dayChrome: Color(0xFF58626E),
    nightChrome: Color(0xFF9FACC0),
  ),
  ReaderPaperTheme(
    id: -106,
    name: '青禾',
    dayTexture: 'assets/reader_paper/day_mist.jpg',
    nightTexture: 'assets/reader_paper/night_charcoal.jpg',
    dayPaper: Color(0xFFEFEEEC),
    nightPaper: Color(0xFF181818),
    dayInk: Color(0xFF2E332C),
    nightInk: Color(0xFFE1E5DC),
    dayAccent: Color(0xFF4F6343),
    nightAccent: Color(0xFF97AB86),
    dayChrome: Color(0xFF616A59),
    nightChrome: Color(0xFFA1A79A),
  ),
  ReaderPaperTheme(
    id: -107,
    name: '胭纸',
    dayTexture: 'assets/reader_paper/day_cool.jpg',
    nightTexture: 'assets/reader_paper/night_ink.jpg',
    dayPaper: Color(0xFFF3F3F3),
    nightPaper: Color(0xFF161616),
    dayInk: Color(0xFF342A2C),
    nightInk: Color(0xFFE9DEE0),
    dayAccent: Color(0xFF8A5562),
    nightAccent: Color(0xFFC58F99),
    dayChrome: Color(0xFF716467),
    nightChrome: Color(0xFFB2A4A7),
  ),
  ReaderPaperTheme(
    id: -108,
    name: '茶烟',
    dayTexture: 'assets/reader_paper/day_snow.jpg',
    nightTexture: 'assets/reader_paper/night_navy.jpg',
    dayPaper: Color(0xFFF3F2F0),
    nightPaper: Color(0xFF121B2E),
    dayInk: Color(0xFF332E26),
    nightInk: Color(0xFFE5E1DA),
    dayAccent: Color(0xFF7A603D),
    nightAccent: Color(0xFFBFA47C),
    dayChrome: Color(0xFF6E6455),
    nightChrome: Color(0xFFAEA495),
  ),
];

Future<ReaderThemeSelection?> readerThemeSelectionById(int id) async {
  final paper = readerPaperThemes.where((theme) => theme.id == id).firstOrNull;
  if (paper != null) return paper.selection;
  final catalog = await LegadoReaderThemes.load();
  return catalog.where((theme) => theme.id == id).firstOrNull?.selection;
}

Color _parseColor(Object? raw, Color fallback) {
  if (raw is! String) return fallback;
  var hex = raw.trim().replaceFirst('#', '');
  if (hex.length == 3) {
    hex = hex.split('').map((char) => '$char$char').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  final value = hex.length == 8 ? int.tryParse(hex, radix: 16) : null;
  return value == null ? fallback : Color(value);
}

Color _opaque(Color color) => Color(color.toARGB32() | 0xFF000000);

int _argb(Color color) => color.toARGB32();

Color _nightBackground(Color dayBackground) {
  final day = _opaque(dayBackground);
  if (day.computeLuminance() < .05) return day;
  final hsl = HSLColor.fromColor(day);
  return hsl
      .withSaturation(math.min(hsl.saturation, .24))
      .withLightness(.09)
      .toColor();
}

Color _readableInk(Color background, Color preferred) {
  final bg = _opaque(background);
  final ink = _opaque(preferred);
  final contrast =
      (math.max(bg.computeLuminance(), ink.computeLuminance()) + .05) /
      (math.min(bg.computeLuminance(), ink.computeLuminance()) + .05);
  if (contrast >= 4.5) return ink;
  return bg.computeLuminance() < .18
      ? const Color(0xFFE8E8E8)
      : const Color(0xFF202020);
}
