import 'library_state.dart';
import 'offline_repository.dart';
import 'local_library_preferences.dart';
import 'catalog.dart';
import 'pending_book.dart';

/// The shelf contains saved books and, when merged, imported originals.
/// Cached trial chapters provide offline availability, never membership.
Set<int> bookshelfIds(
  LibraryState state,
  OfflineNovelRepository? offline, {
  bool readableOnly = false,
  bool filterSource = true,
  bool filterCategory = true,
}) =>
    {
          for (final id in state.shelf)
            if (!readableOnly || offline?.availableOffline(id) == true) id,
          if (state.combinedShelf)
            ...?offline?.local?.books.map((book) => book.id),
        }
        .where(
          (id) =>
              state.localBookVisible(id) &&
              (!filterSource || bookshelfMatchesSource(id, state, offline)) &&
              (!filterCategory ||
                  bookshelfMatchesCategory(
                    id,
                    state,
                    book:
                        offline?.local?.book(id) ??
                        offline?.cache.book(id)?.novel,
                  )),
        )
        .toSet();

bool bookshelfMatchesCategory(
  int id,
  LibraryState state, {
  Novel? book,
  String? category,
}) {
  final selected = category ?? state.organization.shelfSelected;
  if (LocalLibraryPreferences.categoryAuthor(selected) case final author?) {
    return LocalLibraryPreferences.authorName(
          (book ?? state.cachedNovel(id))?.author ?? '',
        ) ==
        author;
  }
  return selected == LocalLibraryPreferences.all ||
      state.organization.groupOf(id) == selected;
}

bool bookshelfMatchesSource(
  int id,
  LibraryState state,
  OfflineNovelRepository? offline, {
  String? source,
}) {
  if (!state.combinedShelf) return true;
  final selected = source ?? state.shelfSourceFilter;
  if (isPendingBook(id)) return selected == 'all';
  final local = offline?.local?.book(id) != null;
  return switch (selected) {
    'local' => local,
    'cached' => !local && offline?.availableOffline(id) == true,
    'online' => !local && state.contains(id),
    _ => true,
  };
}

String bookshelfSource(int id, OfflineNovelRepository? offline) {
  if (isPendingBook(id)) return '待匹配';
  if (offline?.local?.book(id) != null) return '本地';
  return offline?.availableOffline(id) == true ? '缓存' : '在线';
}
