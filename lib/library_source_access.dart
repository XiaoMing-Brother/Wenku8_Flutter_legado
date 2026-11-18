import 'book_sources/book_source_library.dart';
import 'book_sources/library_sources_repository.dart';
import 'catalog.dart';
import 'offline_repository.dart';

/// Exposes the enabled book sources hiding behind the app's repository stack.
BookSourceLibrary? bookSourceLibraryOf(NovelRepository repository) {
  if (repository is OfflineNovelRepository) return repository.bookSources;
  if (repository is LibrarySourcesRepository) return repository.bookSources;
  if (repository is BookSourceLibrary) return repository as BookSourceLibrary;
  return null;
}

/// Exposes only the library catalogue, excluding the book source search layer.
NovelRepository? libraryRepositoryOf(NovelRepository repository) {
  if (repository is OfflineNovelRepository) {
    final remote = repository.remote;
    if (remote is LibrarySourcesRepository) return remote.library;
    if (remote is BookSourceLibrary) return null;
    return remote;
  }
  if (repository is LibrarySourcesRepository) return repository.library;
  if (repository is BookSourceLibrary) return null;
  return repository;
}
