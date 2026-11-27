import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'local_platform.dart';
import 'reader_status.dart';
import 'reader_tip.dart';

/// 页眉 / 页脚的三槽信息条（左 / 中 / 右）。
///
/// 每槽一个 [ReaderTip]，空槽（[ReaderTipValue.none]）不显示文字。三槽始终等分，
/// 保证左右两槽在有无中间内容时位置稳定；文本单行、超出省略。
///
/// 这是渲染原语：由阅读页在 `hasCustomHeaderFooter` 为真时插入，
/// 为假时保持原有状态行，不改变现有观感。
class ReaderInfoStrip extends StatelessWidget {
  const ReaderInfoStrip({
    super.key,
    required this.tips,
    required this.tipContext,
    required this.style,
    this.slotKeys,
    this.equalSlots = false,
  }) : assert(tips.length == 3);

  /// 左 / 中 / 右三个槽位，长度固定为 3。
  final List<ReaderTip> tips;

  /// 格式化所需的数据快照（书名、章节、页码、进度、时间、电量等）。
  final ReaderTipContext tipContext;

  /// 文字样式；颜色由调用方按纸张配色传入。
  final TextStyle style;

  /// 可选：每槽用于测试/无障碍定位的 Key。
  final List<Key?>? slotKeys;

  /// 三槽等分：中间槽永远落在页面正中（页脚书名居中）；默认按文字宽度加权。
  final bool equalSlots;

  /// 三个槽位是否全部为空。
  static bool isEmpty(List<ReaderTip> tips) =>
      tips.every((t) => t.value == ReaderTipValue.none);

  static const _aligns = [TextAlign.start, TextAlign.center, TextAlign.end];

  @override
  Widget build(BuildContext context) {
    if (equalSlots) {
      // 等分槽位保持中槽居中，并由文字决定信息条高度。
      return Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(child: _slot(i, tips[i], _aligns[i])),
        ],
      );
    }
    // 按各槽实际文字宽度分配比例：长内容更宽、空槽几乎不占，避免「章节名被截断」。
    final weights = <int>[];
    for (var i = 0; i < 3; i++) {
      final text = tips[i].format(tipContext);
      if (text.isEmpty) {
        weights.add(1);
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      weights.add(w.isFinite ? w.round().clamp(4, 4000) : 4);
    }
    return Row(
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(flex: weights[i], child: _slot(i, tips[i], _aligns[i])),
      ],
    );
  }

  Widget _slot(int index, ReaderTip tip, TextAlign align) {
    if (tip.value == ReaderTipValue.battery) {
      if (!tipContext.hasBattery) return const SizedBox.shrink();
      return KeyedSubtree(
        key: slotKeys?[index],
        child: Align(
          alignment: _aligns[index] == TextAlign.start
              ? Alignment.centerLeft
              : _aligns[index] == TextAlign.center
              ? Alignment.center
              : Alignment.centerRight,
          child: _ReaderBatteryMeter(
            percent: tipContext.batteryPercent,
            style: style,
          ),
        ),
      );
    }
    final text = tip.format(tipContext);
    if (text.isEmpty) {
      // 空槽仍占位，保持左右槽位置不因中间增删而跳动。
      return const SizedBox.shrink();
    }
    return AppText(
      text,
      key: slotKeys?[index],
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: style,
    );
  }
}

/// 页脚电量：百分比数字内嵌在电池轮廓中。
class _ReaderBatteryMeter extends StatelessWidget {
  const _ReaderBatteryMeter({required this.percent, required this.style});

  final int percent;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final value = percent.clamp(0, 100);
    final ink = style.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final numberSize = MediaQuery.textScalerOf(
      context,
    ).scale((style.fontSize ?? 12) * .72).clamp(8.0, 13.0);
    final height = (numberSize + 6).clamp(15.0, 21.0);
    final width = height * 1.9;
    return Semantics(
      label: '电量 $value%',
      excludeSemantics: true,
      child: SizedBox(
        key: const ValueKey('reader-tip-battery'),
        width: width,
        height: height,
        child: CustomPaint(
          painter: _ReaderBatteryPainter(ink),
          child: Padding(
            padding: EdgeInsets.only(right: height * .16),
            child: Center(
              child: Text(
                '$value',
                maxLines: 1,
                style: TextStyle(
                  color: ink,
                  fontFamily: style.fontFamily,
                  fontFamilyFallback: style.fontFamilyFallback,
                  fontSize: numberSize,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderBatteryPainter extends CustomPainter {
  const _ReaderBatteryPainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final capWidth = math.max(1.8, size.height * .13);
    final bodyWidth = size.width - capWidth;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(.7, 1, bodyWidth - 1.4, size.height - 2),
      Radius.circular(size.height * .3),
    );
    final cap = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        bodyWidth - 1,
        size.height * .31,
        capWidth + 1,
        size.height * .38,
      ),
      Radius.circular(capWidth * .38),
    );
    canvas.drawRRect(cap, Paint()..color = ink.withValues(alpha: .34));

    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..color = ink.withValues(alpha: .5),
    );
  }

  @override
  bool shouldRepaint(_ReaderBatteryPainter oldDelegate) =>
      oldDelegate.ink != ink;
}

/// 带时钟的页眉 / 页脚信息条：在基础上下文（书名 / 章节 / 页码 / 进度）上补齐
/// 时间与电量，复用 [ReaderStatusFooter] 的原生状态事件流并随其更新重建。
class ReaderTipStrip extends StatefulWidget {
  const ReaderTipStrip({
    super.key,
    required this.tips,
    required this.baseContext,
    required this.style,
    this.slotKeys,
    this.equalSlots = false,
  });

  final List<ReaderTip> tips;
  final ReaderTipContext baseContext;
  final TextStyle style;
  final List<Key?>? slotKeys;
  final bool equalSlots;

  @override
  State<ReaderTipStrip> createState() => _ReaderTipStripState();
}

class _ReaderTipStripState extends State<ReaderTipStrip>
    with WidgetsBindingObserver {
  /// 跨实例保留最近一次有效电量：翻页时信息条会换 State，避免电量闪没。
  static int? _lastBattery;
  StreamSubscription<dynamic>? _subscription;
  DateTime _time = DateTime.now();
  int? _battery;

  @override
  void initState() {
    super.initState();
    _battery = _lastBattery;
    final cached = ReaderStatusFooter.lastStatus;
    if (cached != null) _read(cached);
    WidgetsBinding.instance.addObserver(this);
    _listen();
  }

  void _listen() {
    if (!LocalPlatform.readerAppearance || _subscription != null) return;
    _subscription = ReaderStatusFooter.updates.listen((value) {
      if (!mounted || value is! Map) return;
      setState(() => _read(value));
    }, onError: (Object _) {});
  }

  void _read(Map value) {
    final status = ReaderStatusFooter.decodeStatus(value);
    _time = status.time;
    // 分/秒级状态事件可能只带时间不带电量；不要用缺失值覆盖上一次电量，
    // 否则页脚右侧会在「14:51 96%」和「14:51」之间闪。
    final battery = status.battery;
    if (battery != null) {
      _lastBattery = battery.clamp(0, 100);
      _battery = _lastBattery;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _listen();
    } else {
      _subscription?.cancel();
      _subscription = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    final tipContext = widget.baseContext.copyWith(
      time: time,
      batteryPercent: _battery ?? 0,
      hasBattery: _battery != null,
    );
    return ReaderInfoStrip(
      tips: widget.tips,
      tipContext: tipContext,
      style: widget.style,
      slotKeys: widget.slotKeys,
      equalSlots: widget.equalSlots,
    );
  }
}
