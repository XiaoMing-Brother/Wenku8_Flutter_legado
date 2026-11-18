import 'book_source.dart';

/// Search scope mirroring Legado's group/source selector.
///
/// An empty scope means every enabled source. A non-empty source set takes
/// precedence over groups so a stale persisted scope can never be ambiguous.
class BookSourceSearchScope {
  const BookSourceSearchScope({
    this.groupNames = const {},
    this.sourceKeys = const {},
  });

  const BookSourceSearchScope.all()
    : groupNames = const {},
      sourceKeys = const {};

  factory BookSourceSearchScope.groups(Iterable<String> groups) =>
      bookSourceScopeOfGroups(groups);

  factory BookSourceSearchScope.sources(Iterable<String> keys) =>
      bookSourceScopeOfSources(keys);

  final Set<String> groupNames;
  final Set<String> sourceKeys;

  bool get isAll => groupNames.isEmpty && sourceKeys.isEmpty;
  bool get isSource => sourceKeys.isNotEmpty;

  bool matches(BookSource source) {
    if (isAll) return true;
    if (isSource) return sourceKeys.contains(source.key);
    return source.groups.any(groupNames.contains);
  }

  String describe(Iterable<BookSource> sources) {
    if (isAll) return '全部书源';
    if (isSource) {
      final names = <String>[
        for (final source in sources)
          if (sourceKeys.contains(source.key)) source.name,
      ];
      if (names.isEmpty) return '${sourceKeys.length} 个书源';
      if (names.length <= 3) return names.join('、');
      return '${names.take(3).join('、')} 等 ${names.length} 个书源';
    }
    final names = groupNames.where((group) => group.isNotEmpty).toList()
      ..sort();
    if (names.isEmpty) return '全部书源';
    return names.join('、');
  }

  String get signature => [
    (groupNames.where((value) => value.isNotEmpty).toList()..sort()).join(
      '\u0001',
    ),
    (sourceKeys.where((value) => value.isNotEmpty).toList()..sort()).join(
      '\u0001',
    ),
  ].join('\u0002');

  factory BookSourceSearchScope.fromJson(Object? value) {
    if (value is! Map) return const BookSourceSearchScope.all();
    final groups = _clean(value['groups']);
    final sources = _clean(value['sources'] ?? value['sourceKeys']);
    if (sources.isNotEmpty) return BookSourceSearchScope.sources(sources);
    if (groups.isNotEmpty) return BookSourceSearchScope.groups(groups);
    return const BookSourceSearchScope.all();
  }

  Map<String, Object?> toJson() => {
    if (groupNames.isNotEmpty) 'groups': groupNames.toList(growable: false),
    if (sourceKeys.isNotEmpty) 'sources': sourceKeys.toList(growable: false),
  };

  static Set<String> _clean(Object? value) {
    if (value is! List) return const {};
    return {
      for (final item in value)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BookSourceSearchScope &&
        _sameSet(groupNames, other.groupNames) &&
        _sameSet(sourceKeys, other.sourceKeys);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(groupNames),
    Object.hashAllUnordered(sourceKeys),
  );

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}

BookSourceSearchScope bookSourceScopeOfGroups(Iterable<String> groups) {
  final values = {
    for (final group in groups)
      if (group.trim().isNotEmpty) group.trim(),
  };
  return values.isEmpty
      ? const BookSourceSearchScope.all()
      : BookSourceSearchScope(groupNames: Set.unmodifiable(values));
}

BookSourceSearchScope bookSourceScopeOfSources(Iterable<String> keys) {
  final values = {
    for (final key in keys)
      if (key.trim().isNotEmpty) key.trim(),
  };
  return values.isEmpty
      ? const BookSourceSearchScope.all()
      : BookSourceSearchScope(sourceKeys: Set.unmodifiable(values));
}
