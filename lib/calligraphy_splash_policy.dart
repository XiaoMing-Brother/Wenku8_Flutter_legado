import 'package:characters/characters.dart';

/// 书法开屏（启动书法欢迎屏）的纯策略与文本布局逻辑。
///
/// 与 UI 解耦，便于单元测试。对应 legado-with-MD3 的
/// `feature/splash/CalligraphySplashPolicy`：可开关、可每日仅显示一次、可自定义竖排文字。

/// 未设置开屏文字时使用的默认诗句，换行即分列。
const String defaultCalligraphySplashText = '欲买桂花同载酒\n终不似少年游';

/// 竖排上限：最多 4 列，每列最多 12 字，超出截断，避免长文本溢出屏幕。
const int calligraphySplashMaxColumns = 4;
const int calligraphySplashMaxCharsPerColumn = 12;

/// `yyyymmdd` 形式的日期编号，用于「每日仅显示一次」的比较与持久化。
int calligraphySplashDayNumber(DateTime date) =>
    date.year * 10000 + date.month * 100 + date.day;

/// 是否应在本次冷启动展示书法开屏。
///
/// - 关闭时永不展示；
/// - 未开启「每日仅显示一次」时每次都展示；
/// - 开启后仅当「上次展示日」不是今天时展示。
bool shouldShowCalligraphySplash({
  required bool enabled,
  required bool oncePerDay,
  required int lastShownDay,
  DateTime? today,
}) {
  if (!enabled) return false;
  if (!oncePerDay) return true;
  return lastShownDay != calligraphySplashDayNumber(today ?? DateTime.now());
}

/// 把开屏文字切成竖排列（首列在最右，由 UI 负责倒序渲染）。
///
/// 空串回退到 [defaultCalligraphySplashText]；按 `\n` 分列，去掉空行，
/// 最多 [calligraphySplashMaxColumns] 列、每列 [calligraphySplashMaxCharsPerColumn] 字。
List<List<String>> calligraphySplashColumns(String text) {
  final source = text.trim().isEmpty ? defaultCalligraphySplashText : text;
  final columns = source
      .replaceAll('\r', '')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(calligraphySplashMaxColumns)
      .map(
        (line) => line.characters
            .take(calligraphySplashMaxCharsPerColumn)
            .toList(growable: false),
      )
      .toList(growable: false);
  if (columns.isNotEmpty) return columns;
  // 文字为空白或仅含换行时回退到默认诗句。
  return defaultCalligraphySplashText
      .split('\n')
      .map((line) => line.characters.toList(growable: false))
      .toList(growable: false);
}
