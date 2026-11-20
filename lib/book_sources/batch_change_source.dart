/// 批量换源的调度器：与具体书源/书籍类型解耦（泛型 B=书籍，C=候选），
/// 通过注入 `search`（查候选）与 `apply`（执行切换）两个函数完成批量流程，
/// 便于单测，也让 UI 层只需提供两个闭包。
///
/// 典型用法（UI 层）：
/// ```dart
/// final runner = BatchChangeSourceRunner<Novel, Novel>(
///   search: (book) async =>
///       (await library.searchSourceCandidates(book, checkAuthor: true)).items,
///   apply: (book, candidate) async {
///     await repository.switchSource(book, candidate);
///   },
/// );
/// ```
library;

enum BatchChangeSourceStatus { pending, matched, notFound, done, failed }

class BatchChangeSourceItem<B, C> {
  const BatchChangeSourceItem({
    required this.book,
    this.candidates = const [],
    this.selectedIndex = 0,
    this.status = BatchChangeSourceStatus.pending,
    this.error,
  });

  final B book;
  final List<C> candidates;
  final int selectedIndex;
  final BatchChangeSourceStatus status;
  final String? error;

  C? get selected =>
      selectedIndex >= 0 && selectedIndex < candidates.length
      ? candidates[selectedIndex]
      : null;

  bool get canApply =>
      status == BatchChangeSourceStatus.matched && selected != null;

  BatchChangeSourceItem<B, C> copyWith({
    List<C>? candidates,
    int? selectedIndex,
    BatchChangeSourceStatus? status,
    String? error,
  }) => BatchChangeSourceItem<B, C>(
    book: book,
    candidates: candidates ?? this.candidates,
    selectedIndex: selectedIndex ?? this.selectedIndex,
    status: status ?? this.status,
    error: error ?? this.error,
  );
}

class BatchChangeSourceResult {
  const BatchChangeSourceResult({
    required this.changed,
    required this.failed,
    required this.skipped,
  });
  final int changed, failed, skipped;
  int get total => changed + failed + skipped;
}

class BatchChangeSourceRunner<B, C> {
  BatchChangeSourceRunner({required this.search, required this.apply});

  /// 返回某书籍的候选列表（已按匹配度排序，首个为推荐）。
  final Future<List<C>> Function(B book) search;

  /// 执行单本切换；失败时抛异常。
  final Future<void> Function(B book, C candidate) apply;

  /// 解析单本：查候选并给出 matched / notFound / failed。
  Future<BatchChangeSourceItem<B, C>> resolve(B book) async {
    try {
      final items = await search(book);
      if (items.isEmpty) {
        return BatchChangeSourceItem<B, C>(
          book: book,
          status: BatchChangeSourceStatus.notFound,
        );
      }
      return BatchChangeSourceItem<B, C>(
        book: book,
        candidates: List<C>.unmodifiable(items),
        status: BatchChangeSourceStatus.matched,
      );
    } catch (error) {
      return BatchChangeSourceItem<B, C>(
        book: book,
        status: BatchChangeSourceStatus.failed,
        error: '$error',
      );
    }
  }

  /// 逐个执行已匹配项，返回 changed / failed / skipped 统计。
  /// [onChanged] 在每本处理后回调（index 为 items 内的序号，item 为最新状态）。
  Future<BatchChangeSourceResult> run(
    List<BatchChangeSourceItem<B, C>> items, {
    void Function(int index, BatchChangeSourceItem<B, C> item)? onChanged,
  }) async {
    var changed = 0, failed = 0, skipped = 0;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (!item.canApply) {
        skipped++;
        continue;
      }
      try {
        await apply(item.book, item.selected as C);
        changed++;
        final done = item.copyWith(status: BatchChangeSourceStatus.done);
        items[i] = done;
        onChanged?.call(i, done);
      } catch (error) {
        failed++;
        final next = item.copyWith(
          status: BatchChangeSourceStatus.failed,
          error: '$error',
        );
        items[i] = next;
        onChanged?.call(i, next);
      }
    }
    return BatchChangeSourceResult(
      changed: changed,
      failed: failed,
      skipped: skipped,
    );
  }
}
