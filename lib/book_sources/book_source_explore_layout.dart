import 'book_source.dart';

/// One entry in a Legado explore `style` row.
class BookSourceExploreCell {
  const BookSourceExploreCell(this.kind, this.span);

  final BookSourceExploreKind kind;
  final int span;
}

/// Mirrors Legado's `calculateExploreKindRows(kinds, 6)` flex calculation.
List<List<BookSourceExploreCell>> buildBookSourceExploreRows(
  Iterable<BookSourceExploreKind> kinds, {
  int maxSpan = 6,
}) {
  final rows = <List<BookSourceExploreCell>>[];
  var current = <BookSourceExploreCell>[];
  var currentSpan = 0;

  void fillRowTail() {
    if (current.isEmpty) return;
    final remain = maxSpan - currentSpan;
    if (remain <= 0) return;
    final spans = current.map((cell) => cell.span).toSet();
    if (spans.length == 1 && current.length > 1) {
      final each = remain ~/ current.length;
      var extra = remain % current.length;
      current = [
        for (final cell in current)
          BookSourceExploreCell(
            cell.kind,
            cell.span + each + (extra-- > 0 ? 1 : 0),
          ),
      ];
    } else {
      final last = current.removeLast();
      current.add(BookSourceExploreCell(last.kind, last.span + remain));
    }
    currentSpan += remain;
  }

  void flush() {
    fillRowTail();
    rows.add(current);
    current = <BookSourceExploreCell>[];
    currentSpan = 0;
  }

  for (final kind in kinds) {
    final span = switch (kind) {
      _ when kind.wrapBefore || kind.basisPercent >= 1 => maxSpan,
      _ when kind.basisPercent > 0 =>
        (maxSpan * kind.basisPercent).round().clamp(1, maxSpan).toInt(),
      _ when kind.flexGrow > 0 => 3,
      _ => 2,
    };
    if ((kind.wrapBefore && current.isNotEmpty) ||
        currentSpan + span > maxSpan) {
      flush();
    }
    current.add(BookSourceExploreCell(kind, span));
    currentSpan += span;
    if (currentSpan >= maxSpan) flush();
  }
  if (current.isNotEmpty) flush();
  return rows;
}
