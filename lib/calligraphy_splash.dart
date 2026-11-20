import 'dart:async';

import 'package:flutter/material.dart';

import 'calligraphy_splash_policy.dart';
import 'library_state.dart';

/// 阅微式书法开屏的配色。纸色/墨色/印色/印文色随明暗主题切换，
/// 对应 legado-with-MD3 的 `calligraphy_splash_paper/_ink/_seal/_seal_carving`。
class CalligraphySplashPalette {
  const CalligraphySplashPalette({
    required this.paper,
    required this.ink,
    required this.seal,
    required this.carving,
  });

  final Color paper;
  final Color ink;
  final Color seal;
  final Color carving;

  static const light = CalligraphySplashPalette(
    paper: Color(0xFFF7F8FA),
    ink: Color(0xFF2A241D),
    seal: Color(0xFFC90A16),
    carving: Color(0xFFF7F8FA),
  );
  static const dark = CalligraphySplashPalette(
    paper: Color(0xFF1E1A15),
    ink: Color(0xFFE8E2D8),
    seal: Color(0xFFD22A32),
    carving: Color(0xFF1E1A15),
  );

  static CalligraphySplashPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// 纯色纸底 + 竖排书法文字 + 朱红落款印。
///
/// [text] 为空时使用默认诗句；换行分列，首列在最右。
class CalligraphySplashScreen extends StatelessWidget {
  const CalligraphySplashScreen({super.key, this.text = ''});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = CalligraphySplashPalette.of(context);
    final columns = calligraphySplashColumns(text);
    final totalChars = columns.fold<int>(0, (sum, column) => sum + column.length);
    final fontSize = switch (totalChars) {
      > 32 => 22.0,
      > 20 => 26.0,
      > 10 => 32.0,
      _ => 38.0,
    };
    // 用 Material 提供默认文字样式：开屏浮层不在 Scaffold 之内，
    // 若缺少 DefaultTextStyle，Text 会落到带黄色下划线的 fallback 样式。
    return Material(
      color: palette.paper,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: fontSize * 0.62,
                children: [
                  // 中文竖排：首列在最右，而 Row 从左往右布局，故倒序排列。
                  for (final column in columns.reversed)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final glyph in column)
                          Text(
                            glyph,
                            softWrap: false,
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: fontSize,
                              height: 1.04,
                              fontFamily: 'SplashCalligraphy',
                              fontWeight: FontWeight.normal,
                              letterSpacing: 0,
                              decoration: TextDecoration.none,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              // 小印落在末字（右列「酒」）右侧，竖向落款印。
              Positioned(
                right: -(fontSize * 0.72),
                bottom: fontSize * 0.14,
                child: _SealMark(palette: palette, size: fontSize),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 参考 legado-with-MD3 的 res/drawable/calligraphy_seal.xml：
// 不规则朱印主体 + 两档印泥漏痕（纸色半透明），下垫白色「朙」篆书。
const String _sealBodyPath =
    'M4.2,6.6 C5.0,3.3 7.1,1.8 10.6,1.5 L14.5,0.9 L18.2,1.4 C21.3,1.5 23.0,2.8 23.1,5.1 '
    'L22.6,7.3 C23.6,8.8 23.5,10.0 23.6,11.2 L24.5,13.0 L24.0,16.5 L24.9,20.2 L24.2,23.1 '
    'L25.0,27.3 L24.3,30.1 L24.6,32.6 L23.2,35.3 C22.0,38.3 19.7,39.8 16.6,40.0 L12.4,40.4 '
    'L8.5,39.8 C5.5,39.1 3.9,37.2 3.3,34.2 L2.7,30.8 L3.0,26.9 L2.5,23.0 L3.2,19.9 L2.8,16.5 '
    'L3.4,13.5 L3.2,10.0 Z';
const String _sealMottleStrong =
    'M4.9,8.4 l0.7,-0.4 0.4,0.6 -0.3,1.8 -0.6,0.3 z M19.7,4.6 l1.1,0.5 -0.2,0.8 -1.2,-0.2 z '
    'M21.6,24.0 l0.6,0.8 -0.4,2.0 -0.7,-0.3 z M5.0,29.0 l0.7,0.3 -0.2,2.0 -0.7,-0.6 z '
    'M9.1,35.9 l1.7,-0.3 0.4,0.5 -1.2,0.6 z M15.8,36.1 l1.3,-0.2 0.4,0.4 -0.7,0.5 z';
const String _sealMottleLight =
    'M6.5,6.9 l0.55,-0.2 0.23,0.38 -0.45,0.31 z M17.9,3.3 l0.42,0.12 0.12,0.42 -0.46,0.1 z '
    'M22.2,12.0 l0.42,0.3 -0.1,0.68 -0.45,0.12 z M4.4,18.4 l0.48,-0.16 0.2,0.56 -0.35,0.35 z '
    'M21.8,29.1 l0.46,0.14 -0.06,0.56 -0.55,-0.08 z M7.3,33.4 l0.4,-0.26 0.26,0.34 -0.22,0.38 z '
    'M13.0,37.6 l0.56,-0.10 0.17,0.33 -0.52,0.26 z M19.2,34.8 l0.5,-0.38 0.23,0.34 -0.31,0.47 z';

class _SealMark extends StatelessWidget {
  const _SealMark({required this.palette, required this.size});

  final CalligraphySplashPalette palette;

  /// 以文字字号为基准缩放印章尺寸（原矢量 14×21dp，比例 2:3）。
  final double size;

  @override
  Widget build(BuildContext context) {
    final width = size * 0.5;
    final height = size * 0.75;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _SealPainter(
              sealColor: palette.seal,
              paperColor: palette.paper,
            ),
          ),
          Center(
            child: Text(
              '朙',
              softWrap: false,
              style: TextStyle(
                fontFamily: 'SplashSeal',
                fontSize: height * 0.5,
                height: 1,
                color: palette.carving,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  _SealPainter({required this.sealColor, required this.paperColor});

  final Color sealColor;
  final Color paperColor;

  static final Path _body = _parseSealPath(_sealBodyPath);
  static final Path _mottleStrong = _parseSealPath(_sealMottleStrong);
  static final Path _mottleLight = _parseSealPath(_sealMottleLight);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28.0, size.height / 42.0);
    canvas.drawPath(_body, Paint()..color = sealColor);
    canvas.drawPath(
      _mottleStrong,
      Paint()..color = paperColor.withValues(alpha: 0.30),
    );
    canvas.drawPath(
      _mottleLight,
      Paint()..color = paperColor.withValues(alpha: 0.72),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SealPainter oldDelegate) =>
      oldDelegate.sealColor != sealColor ||
      oldDelegate.paperColor != paperColor;
}

/// 解析 calligraphy_seal.xml 用到的 SVG 路径子集（M/C/L/H/V、相对 l/h/v、z）。
Path _parseSealPath(String data) {
  final path = Path();
  final tokens = RegExp(
    r'[MCLZmclzHhVv]|-?\d*\.?\d+',
  ).allMatches(data).map((match) => match.group(0)!).toList();
  var i = 0;
  var cmd = '';
  var cx = 0.0, cy = 0.0, startX = 0.0, startY = 0.0;
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    final token = tokens[i];
    if (token.length == 1 && 'MCLZmclzHhVv'.contains(token)) {
      cmd = token;
      i++;
      if (cmd == 'Z' || cmd == 'z') {
        path.close();
        cx = startX;
        cy = startY;
      }
      continue;
    }
    if (cmd == 'M') {
      cx = next();
      cy = next();
      path.moveTo(cx, cy);
      startX = cx;
      startY = cy;
      cmd = 'L';
    } else if (cmd == 'm') {
      cx += next();
      cy += next();
      path.moveTo(cx, cy);
      startX = cx;
      startY = cy;
      cmd = 'l';
    } else if (cmd == 'C') {
      final x1 = next(), y1 = next(), x2 = next(), y2 = next();
      final x = next(), y = next();
      path.cubicTo(x1, y1, x2, y2, x, y);
      cx = x;
      cy = y;
    } else if (cmd == 'c') {
      final x1 = cx + next(), y1 = cy + next();
      final x2 = cx + next(), y2 = cy + next();
      final x = cx + next(), y = cy + next();
      path.cubicTo(x1, y1, x2, y2, x, y);
      cx = x;
      cy = y;
    } else if (cmd == 'L') {
      cx = next();
      cy = next();
      path.lineTo(cx, cy);
    } else if (cmd == 'l') {
      cx += next();
      cy += next();
      path.lineTo(cx, cy);
    } else if (cmd == 'H') {
      cx = next();
      path.lineTo(cx, cy);
    } else if (cmd == 'h') {
      cx += next();
      path.lineTo(cx, cy);
    } else if (cmd == 'V') {
      cy = next();
      path.lineTo(cx, cy);
    } else if (cmd == 'v') {
      cy += next();
      path.lineTo(cx, cy);
    } else {
      i++;
    }
  }
  return path;
}

/// 冷启动时覆盖在主界面之上的书法开屏；停留后可点击跳过，淡出后回调 [onFinished]。
class CalligraphySplashOverlay extends StatefulWidget {
  const CalligraphySplashOverlay({
    super.key,
    this.text = '',
    required this.onFinished,
    this.reduceMotion = false,
    this.hold = const Duration(milliseconds: 1500),
  });

  final String text;
  final VoidCallback onFinished;
  final bool reduceMotion;
  final Duration hold;

  @override
  State<CalligraphySplashOverlay> createState() =>
      _CalligraphySplashOverlayState();
}

class _CalligraphySplashOverlayState extends State<CalligraphySplashOverlay> {
  bool _visible = true;
  bool _dismissed = false;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _holdTimer = Timer(widget.hold, _dismiss);
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _holdTimer?.cancel();
    if (!mounted) {
      widget.onFinished();
      return;
    }
    setState(() => _visible = false);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !_visible,
    child: AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: widget.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      onEnd: () {
        if (!_visible) widget.onFinished();
      },
      child: Semantics(
        label: '启动书法欢迎屏，点击跳过',
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _dismiss,
          child: CalligraphySplashScreen(text: widget.text),
        ),
      ),
    ),
  );
}

/// 在冷启动的根路由上包一层书法开屏；只在本次挂载（即冷启动）判断并展示一次。
///
/// 是否展示由 [shouldShowCalligraphySplash] 决定；开启「每日仅显示一次」时，
/// 展示后立即记录当天，避免同一天重复出现。
class CalligraphySplashGate extends StatefulWidget {
  const CalligraphySplashGate({
    super.key,
    required this.state,
    required this.child,
  });

  final LibraryState state;
  final Widget child;

  @override
  State<CalligraphySplashGate> createState() => _CalligraphySplashGateState();
}

class _CalligraphySplashGateState extends State<CalligraphySplashGate> {
  late bool _show;

  @override
  void initState() {
    super.initState();
    final state = widget.state;
    _show = shouldShowCalligraphySplash(
      enabled: state.calligraphySplashEnabled,
      oncePerDay: state.calligraphySplashOncePerDay,
      lastShownDay: state.calligraphySplashLastShownDay,
    );
    if (_show && state.calligraphySplashOncePerDay) {
      unawaited(state.markCalligraphySplashShown());
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (_show)
        CalligraphySplashOverlay(
          text: widget.state.calligraphySplashText,
          reduceMotion: widget.state.effectiveReduceMotion,
          onFinished: () {
            if (mounted) setState(() => _show = false);
          },
        ),
    ],
  );
}
