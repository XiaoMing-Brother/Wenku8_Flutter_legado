/// 阅读页眉 / 页脚可配置「信息位」的值类型与格式化逻辑。
///
/// 语义对齐 legado_md3 的 `ReaderTipValueType` + `ReaderTipValueFormatter`：
/// 页眉、页脚各自可放左 / 中 / 右三个槽位，每槽选一种值类型；`custom` 支持模板占位。
///
/// 本文件只做纯数据与字符串格式化，不依赖 Flutter，方便单测与跨渲染层复用。
/// 真正的排版几何（基线、行高等）与 Widget 渲染放在后续的 reader_header_footer 渲染层。
library;

/// 页眉 / 页脚槽位可选的「信息值」类型。顺序即设置面板展示顺序。
enum ReaderTipValue {
  none('不显示'),
  chapterTitle('章节名'),
  bookName('书名'),
  chapterIndex('章序'),
  page('页码'),
  chapterProgress('本章进度'),
  totalProgress('全书进度'),
  pageAndProgress('页码 + 进度'),
  time('时间'),
  battery('电量'),
  timeBattery('时间 + 电量'),
  custom('自定义');

  const ReaderTipValue(this.label);
  final String label;
}

/// 格式化 [ReaderTipValue] 所需的上下文快照，全部由阅读器在构建状态行时填充。
///
/// 页码 / 章序均以 0 为起点，格式化时再加 1 展示，避免调用方各自处理偏移。
class ReaderTipContext {
  const ReaderTipContext({
    this.bookName = '',
    this.chapterTitle = '',
    this.chapterIndex = 0,
    this.chapterCount = 0,
    this.pageIndex = 0,
    this.pageCount = 0,
    this.readProgress = '',
    this.time = '',
    this.batteryPercent = 0,
    this.hasBattery = false,
  });

  /// 书名。
  final String bookName;

  /// 当前页所在章节名。
  final String chapterTitle;

  /// 当前章序（0 起）。
  final int chapterIndex;

  /// 全书章节总数。
  final int chapterCount;

  /// 当前页在章内的页码（0 起）。
  final int pageIndex;

  /// 本章总页数。
  final int pageCount;

  /// 全书阅读进度文案，如 `23.4%`；由调用方按需要本地化。
  final String readProgress;

  /// 当前时间文案，如 `09:30`。
  final String time;

  /// 电量百分比 0–100。
  final int batteryPercent;

  /// 是否真的有电量数据（未取到时不显示电量相关位）。
  final bool hasBattery;

  ReaderTipContext copyWith({
    String? bookName,
    String? chapterTitle,
    int? chapterIndex,
    int? chapterCount,
    int? pageIndex,
    int? pageCount,
    String? readProgress,
    String? time,
    int? batteryPercent,
    bool? hasBattery,
  }) => ReaderTipContext(
    bookName: bookName ?? this.bookName,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    chapterCount: chapterCount ?? this.chapterCount,
    pageIndex: pageIndex ?? this.pageIndex,
    pageCount: pageCount ?? this.pageCount,
    readProgress: readProgress ?? this.readProgress,
    time: time ?? this.time,
    batteryPercent: batteryPercent ?? this.batteryPercent,
    hasBattery: hasBattery ?? this.hasBattery,
  );
}

/// 章还没排出任何页时，页码文案用 `-` 兜底（对照 legado `pageSizeInt <= 0` 分支）。
String _pageCountText(ReaderTipContext c) => c.pageCount > 0 ? '${c.pageCount}' : '-';

/// 电量位：没有数据时返回空串，避免出现假的 `0%`。
String _batteryText(ReaderTipContext c) =>
    c.hasBattery ? '${c.batteryPercent}%' : '';

/// 按 [type] 生成一个槽位要显示的文本。
///
/// [template] 仅在 [ReaderTipValue.custom] 时使用，支持这些占位（大小写敏感）：
/// `{BookName}`、`{ChapterTitle}`、`{Time}`、`{BatteryPercent}`、`{ChapterIndex}`、
/// `{ChapterSize}`、`{PageIndex}`、`{PageSize}`、`{ReadProgress}`。未知占位原样保留。
String formatReaderTip(
  ReaderTipValue type,
  ReaderTipContext c, {
  String template = '',
}) {
  switch (type) {
    case ReaderTipValue.none:
      return '';
    case ReaderTipValue.chapterTitle:
      return c.chapterTitle;
    case ReaderTipValue.bookName:
      return c.bookName;
    case ReaderTipValue.chapterIndex:
      return c.chapterCount > 0
          ? '${c.chapterIndex + 1}/${c.chapterCount}'
          : '';
    case ReaderTipValue.page:
      return '${c.pageIndex + 1}/${_pageCountText(c)}';
    case ReaderTipValue.chapterProgress:
      return c.readProgress;
    case ReaderTipValue.totalProgress:
      return c.readProgress;
    case ReaderTipValue.pageAndProgress:
      return '${c.pageIndex + 1}/${_pageCountText(c)}  ${c.readProgress}'.trim();
    case ReaderTipValue.time:
      return c.time;
    case ReaderTipValue.battery:
      return _batteryText(c);
    case ReaderTipValue.timeBattery:
      final battery = _batteryText(c);
      return battery.isEmpty ? c.time : '${c.time} $battery';
    case ReaderTipValue.custom:
      return _resolveCustom(template, c);
  }
}

String _resolveCustom(String template, ReaderTipContext c) {
  if (template.isEmpty) return '';
  final battery = _batteryText(c);
  return template
      .replaceAll('{BookName}', c.bookName)
      .replaceAll('{ChapterTitle}', c.chapterTitle)
      .replaceAll('{Time}', c.time)
      .replaceAll('{BatteryPercent}', battery)
      .replaceAll('{ChapterIndex}', '${c.chapterIndex + 1}')
      .replaceAll('{ChapterSize}', '${c.chapterCount}')
      .replaceAll('{PageIndex}', '${c.pageIndex + 1}')
      .replaceAll('{PageSize}', _pageCountText(c))
      .replaceAll('{ReadProgress}', c.readProgress);
}

/// 一个槽位是「值类型 + 自定义模板」的组合，方便整体序列化进偏好。
class ReaderTip {
  const ReaderTip({this.value = ReaderTipValue.none, this.template = ''});
  final ReaderTipValue value;
  final String template;

  String format(ReaderTipContext c) =>
      formatReaderTip(value, c, template: template);

  Map<String, Object?> toJson() => {
    'value': value.name,
    if (template.isNotEmpty) 'template': template,
  };

  factory ReaderTip.fromJson(Map<String, dynamic> json) => ReaderTip(
    value: ReaderTipValue.values.firstWhere(
      (v) => v.name == (json['value'] ?? 'none'),
      orElse: () => ReaderTipValue.none,
    ),
    template: (json['template'] as String?) ?? '',
  );

  static const none = ReaderTip();
}
