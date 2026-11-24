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
    this.imageUrl,
  });

  final int id;
  final String name;
  final Color background, nightBackground, ink, nightInk;
  final Color? control;
  final String? imageUrl;

  ReaderThemeSelection get inverted => ReaderThemeSelection(
    id: id,
    name: name,
    background: nightBackground,
    nightBackground: background,
    ink: nightInk,
    control: control,
    nightInk: ink,
    imageUrl: imageUrl,
  );

  ReaderThemeSelection get withoutImage => ReaderThemeSelection(
    id: id,
    name: name,
    background: background,
    nightBackground: nightBackground,
    ink: ink,
    nightInk: nightInk,
    control: control,
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
    if (imageUrl != null) 'imageUrl': imageUrl,
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
      imageUrl: json['imageUrl'] is String ? json['imageUrl'] as String : null,
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
      imageUrl == other.imageUrl;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    background,
    nightBackground,
    ink,
    nightInk,
    control,
    imageUrl,
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
