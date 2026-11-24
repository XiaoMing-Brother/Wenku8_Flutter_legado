import 'book_source.dart';

/// One entry in a Legado explore `style` row.
class BookSourceExploreCell {
  const BookSourceExploreCell(this.kind, this.span);

  final BookSourceExploreKind kind;
  final int span;
}

/// One entry in a Legado login `style` row.
class BookSourceLoginCell {
  const BookSourceLoginCell(this.field, this.span);

  final BookSourceLoginField field;
  final int span;
}

/// Mirrors Legado's `calculateExploreKindRows(kinds, 6)` flex calculation.
List<List<BookSourceExploreCell>> buildBookSourceExploreRows(
  Iterable<BookSourceExploreKind> kinds, {
  int maxSpan = 6,
}) => _buildRows(
  kinds,
  maxSpan: maxSpan,
  spanOf: (kind) => switch (kind) {
    _ when kind.wrapBefore || kind.basisPercent >= 1 => maxSpan,
    _ when kind.basisPercent > 0 =>
      (maxSpan * kind.basisPercent).round().clamp(1, maxSpan).toInt(),
    _ when kind.flexGrow > 0 => 3,
    _ => 2,
  },
  wrapBefore: (kind) => kind.wrapBefore,
  withSpan: BookSourceExploreCell.new,
);

/// Mirrors Legado's login sheet flex calculation over `loginUi` rows.
List<List<BookSourceLoginCell>> buildBookSourceLoginRows(
  Iterable<BookSourceLoginField> fields, {
  int maxSpan = 6,
}) => _buildRows(
  fields,
  maxSpan: maxSpan,
  spanOf: (field) => switch (field) {
    _ when field.isText || field.wrapBefore || field.basisPercent >= 1 =>
      maxSpan,
    _ when field.basisPercent > 0 =>
      (maxSpan * field.basisPercent).round().clamp(1, maxSpan).toInt(),
    _ when field.flexGrow > 0 => 3,
    _ => 2,
  },
  wrapBefore: (field) => field.isText || field.wrapBefore,
  withSpan: BookSourceLoginCell.new,
);

List<List<Cell>> _buildRows<Item, Cell>(
  Iterable<Item> items, {
  required int maxSpan,
  required int Function(Item item) spanOf,
  required bool Function(Item item) wrapBefore,
  required Cell Function(Item item, int span) withSpan,
}) {
  final rows = <List<({Item item, int span})>>[];
  var current = <({Item item, int span})>[];
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
          (item: cell.item, span: cell.span + each + (extra-- > 0 ? 1 : 0)),
      ];
    } else {
      final last = current.removeLast();
      current.add((item: last.item, span: last.span + remain));
    }
    currentSpan += remain;
  }

  void flush() {
    fillRowTail();
    rows.add(current);
    current = <({Item item, int span})>[];
    currentSpan = 0;
  }

  for (final item in items) {
    final span = spanOf(item);
    if ((wrapBefore(item) && current.isNotEmpty) ||
        currentSpan + span > maxSpan) {
      flush();
    }
    current.add((item: item, span: span));
    currentSpan += span;
    if (currentSpan >= maxSpan) flush();
  }
  if (current.isNotEmpty) flush();
  return [
    for (final row in rows)
      [for (final cell in row) withSpan(cell.item, cell.span)],
  ];
}
