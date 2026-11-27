import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'catalog.dart';
import 'cover_images.dart';
import 'feature_pages.dart' show ArchiveFeaturePage, featurePadding;

/// 复刻起点中文网旧版阅读器的「扉页」版式。
///
/// 数据与在线书源一致，全部来自 [Novel] 的同一批元数据：
/// - 书名 / 作者 / 类型（genre / author / title）
/// - 上架时间（lastUpdate，缺失时退回导入/创建时间戳）
/// - 字数 / 完本（wordCount + isComplete）
/// - 卷首语（扉页寄语，缺省时退回简介首句）
/// - 页脚版权行是本地固定模板，不来自接口。
class BookTitlePage extends StatelessWidget {
  const BookTitlePage({
    super.key,
    required this.novel,
    this.reduceMotion = false,
    this.openChapter,
  });

  final Novel novel;
  final bool reduceMotion;

  /// 点按封面时的动作（一般是打开阅读/封面预览），可空。
  final VoidCallback? openChapter;

  // 扉页固定使用的暖色纸质调色板，刻意不跟随应用主题。
  static const _paper = Color(0xFFF4EAD3);
  static const _paperEdge = Color(0xFFE4D3B0);
  static const _ink = Color(0xFF2A2622);
  static const _inkSoft = Color(0xFF6B5D49);
  static const _rule = Color(0xFFB8A582);

  String get _genre {
    final tags = novel.tags;
    if (tags.isNotEmpty) return tags.first;
    final genre = novel.genre.trim();
    return genre.isEmpty ? '—' : genre;
  }

  String get _author =>
      novel.author.trim().isEmpty ? '佚名' : novel.author.trim();

  String get _title => novel.title.trim().isEmpty ? '无题' : novel.title.trim();

  String? get _publishStamp {
    final updated = novel.lastUpdate?.trim();
    if (updated == null || updated.isEmpty) return null;
    // 尽量把 2018-04-01 / 2018.4.1 统一成 2018.04.01 的起点风格。
    final match = RegExp(
      r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})',
    ).firstMatch(updated);
    if (match == null) return updated;
    final year = match.group(1)!;
    final month = match.group(2)!.padLeft(2, '0');
    final day = match.group(3)!.padLeft(2, '0');
    return '$year.$month.$day';
  }

  String get _wordLabel {
    final count = novel.wordCount;
    if (count == null || count <= 0) return '—';
    final wan = count / 10000;
    final text = wan >= 1
        ? wan.toStringAsFixed(0)
        : wan
              .toStringAsFixed(2)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
    return '$text万字';
  }

  /// 卷首语：优先使用扉页寄语，缺省时退回简介首句。
  String? get _epigraph {
    final summary = novel.summary.trim();
    if (summary.isEmpty) return null;
    final firstLine = summary.split(RegExp(r'[\r\n。！？!?]')).first.trim();
    if (firstLine.isEmpty) return null;
    return firstLine.length > 24 ? firstLine.substring(0, 24) : firstLine;
  }

  @override
  Widget build(BuildContext context) {
    return ArchiveFeaturePage(
      title: '扉页',
      code: 'LIBRARY / FRONTISPIECE',
      child: SingleChildScrollView(
        padding: featurePadding(context),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _sheet(context),
          ),
        ),
      ),
    );
  }

  Widget _sheet(BuildContext context) {
    return Container(
      key: const ValueKey('title-page-sheet'),
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _paperEdge, width: .8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cover(context),
          const SizedBox(height: 30),
          _heading(),
          const SizedBox(height: 40),
          _facts(context),
          const SizedBox(height: 34),
          if (_epigraph case final epigraph?) ...[
            _dashedRule(),
            const SizedBox(height: 26),
            _epigraphBlock(epigraph),
            const SizedBox(height: 26),
            _dashedRule(),
          ] else
            _dashedRule(),
          const SizedBox(height: 34),
          _footer(),
        ],
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final width = _genre == '—' ? 140.0 : 140.0;
    final cover = Container(
      decoration: BoxDecoration(
        border: Border.all(color: _paperEdge, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: NovelCover(
        novel,
        width: width,
        height: width * 1.42,
        isDetailCover: true,
      ),
    );
    return Center(
      child: Semantics(
        button: openChapter != null || novelCoverUrl(novel)?.isNotEmpty == true,
        label: openChapter != null ? '打开《$_title》' : '《$_title》封面',
        child: GestureDetector(
          key: const ValueKey('title-page-cover'),
          onTap: openChapter,
          child: cover,
        ),
      ),
    );
  }

  Widget _heading() => Column(
    children: [
      AppText(
        _title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 30,
          height: 1.3,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: _ink,
        ),
      ),
      const SizedBox(height: 12),
      AppText(
        _author,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 15,
          height: 1.4,
          letterSpacing: .6,
          color: _inkSoft,
        ),
      ),
    ],
  );

  Widget _facts(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _fact('类型', _genre)),
        Expanded(
          child: _fact(
            '上架',
            _publishStamp ?? '—',
            align: CrossAxisAlignment.center,
          ),
        ),
        Expanded(
          child: _fact(
            '字数 / $_completeWord',
            _wordLabel,
            align: CrossAxisAlignment.end,
          ),
        ),
      ],
    );
  }

  String get _completeWord => novel.isComplete ? '完本' : '连载';

  Widget _fact(
    String label,
    String value, {
    CrossAxisAlignment align = CrossAxisAlignment.start,
  }) {
    final textAlign = switch (align) {
      CrossAxisAlignment.end => TextAlign.right,
      CrossAxisAlignment.center => TextAlign.center,
      _ => TextAlign.left,
    };
    return Column(
      crossAxisAlignment: align,
      children: [
        AppText(
          value,
          textAlign: textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 22,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        AppText(
          label,
          textAlign: textAlign,
          style: const TextStyle(fontSize: 12, height: 1.3, color: _inkSoft),
        ),
      ],
    );
  }

  Widget _epigraphBlock(String epigraph) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppText(
        epigraph,
        style: const TextStyle(
          fontSize: 17,
          height: 1.7,
          letterSpacing: .4,
          color: _ink,
        ),
      ),
      const SizedBox(height: 18),
      AppText(
        '— $_author',
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 14, height: 1.4, color: _inkSoft),
      ),
    ],
  );

  /// 复刻扉页里的横向虚线分隔。
  Widget _dashedRule() => LayoutBuilder(
    builder: (context, constraints) {
      const dash = 5.0;
      const gap = 4.0;
      final count = (constraints.maxWidth / (dash + gap)).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < count; i++)
            const SizedBox(
              width: dash,
              height: 1,
              child: ColoredBox(color: _rule),
            ),
        ],
      );
    },
  );

  Widget _footer() => Column(
    children: [
      AppText(
        '— 本作品由起点中文网进行电子制作与发行 —',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, height: 1.6, color: _inkSoft),
      ),
      const SizedBox(height: 4),
      AppText(
        '版权所有·侵权必究',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, height: 1.6, color: _inkSoft),
      ),
    ],
  );
}
