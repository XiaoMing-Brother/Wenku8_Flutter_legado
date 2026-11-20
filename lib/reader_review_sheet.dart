import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'reader_paragraph_review.dart';

/// 本章段评面板。
///
/// 读取 [ChapterReviewCache]：有数据显示头像占位 / 内容 / 时间；无数据先显示空态。
/// 若传入 [loader]，会对空缓存异步抓取一次并刷新（抓取走 native 引擎，缺失/失败时
/// 保持空态、不影响阅读）。
class ReaderReviewSheet extends StatefulWidget {
  const ReaderReviewSheet({
    super.key,
    required this.bookId,
    required this.chapterId,
    this.chapterTitle,
    this.sourceSupportsReview = true,
    this.loader,
    this.focusPara,
  });

  final int bookId;
  final int chapterId;
  final String? chapterTitle;

  /// 当前书源是否配置了段评规则（`ruleReview`）。用于区分「未配置」与「暂未抓取」。
  final bool sourceSupportsReview;

  /// 空缓存时的异步抓取回调；返回抓到的数据（内部一般已写入缓存）。
  final Future<ChapterReviewData?> Function()? loader;

  /// 若指定，则只显示该段落号（paraIndex）的段评（点段落气泡时传入）。
  final int? focusPara;

  @override
  State<ReaderReviewSheet> createState() => _ReaderReviewSheetState();
}

class _ReaderReviewSheetState extends State<ReaderReviewSheet> {
  ChapterReviewData? _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _data = ChapterReviewCache.shared.lookup(widget.bookId, widget.chapterId);
    if (_data == null || _data!.items.isEmpty) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final loader = widget.loader;
    if (loader == null || _loading) return;
    setState(() => _loading = true);
    try {
      final value = await loader();
      if (!mounted) return;
      setState(() {
        _data = value ?? _data;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final allItems = _data?.items ?? const <ParagraphReview>[];
    final items = widget.focusPara == null
        ? allItems
        : [
            for (final item in allItems)
              if (item.paraIndex == widget.focusPara) item,
          ];
    final sorted = [...items]..sort((a, b) {
      final ai = a.paraIndex, bi = b.paraIndex;
      if (ai == null && bi == null) return 0;
      if (ai == null) return 1;
      if (bi == null) return -1;
      return ai.compareTo(bi);
    });
    final coveredParagraphs = items
        .map((item) => item.paraIndex)
        .whereType<int>()
        .toSet()
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        const ArchiveSection(title: '本章段评', code: 'REVIEW / CHAPTER'),
        if (widget.chapterTitle != null && widget.chapterTitle!.isNotEmpty) ...[
          const SizedBox(height: 6),
          AppText(
            widget.chapterTitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ],
        if (items.isNotEmpty) ...[
          const SizedBox(height: 2),
          AppText(
            '共 ${items.length} 条 · 覆盖 $coveredParagraphs 段',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
        if (widget.sourceSupportsReview && widget.loader != null)
          Align(
            alignment: Alignment.centerRight,
            child: GlassTextButton(
              key: const ValueKey('reader-review-refresh'),
              compact: true,
              onPressed: _loading ? null : _refresh,
              child: const AppText('刷新'),
            ),
          ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: AppText(
              widget.sourceSupportsReview
                  ? '本章暂无段评，可能尚未抓取；稍后重试或确认网络后可再查看。'
                  : '当前书源未配置段评规则，无法显示段评。',
              style: TextStyle(fontSize: 13, height: 1.6, color: muted),
            ),
          )
        else
          for (final item in sorted) _row(context, item, muted),
      ],
    );
  }

  Widget _row(BuildContext context, ParagraphReview item, Color muted) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: item.content));
        if (context.mounted) showNovelFeedback(context, '已复制段评');
      },
      child: Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          item.avatarUrl.isEmpty
              ? ArchiveIcon(
                  CupertinoIcons.person_crop_circle,
                  size: 26,
                  color: muted,
                )
              : ClipOval(
                  child: Image.network(
                    item.avatarUrl,
                    width: 26,
                    height: 26,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => ArchiveIcon(
                      CupertinoIcons.person_crop_circle,
                      size: 26,
                      color: muted,
                    ),
                  ),
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.paraIndex != null) ...[
                  AppText(
                    '第 ${item.paraIndex! + 1} 段',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  const SizedBox(height: 2),
                ],
                AppText(
                  item.content,
                  style: const TextStyle(fontSize: 13, height: 1.6),
                ),
                if (item.postTime.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  AppText(
                    item.postTime,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}
