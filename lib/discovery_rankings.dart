import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_search_field.dart';
import 'app_ui.dart';
import 'book_sources/fanqie_library_categories.dart';
import 'catalog.dart';
import 'dock_layout.dart';
import 'feature_pages.dart';
import 'library_state.dart';
import 'official_books.dart';
import 'pages.dart' show openDetail, openInSourceSearch;

/// 发现页直接请求起点/番茄官网榜单接口，不经过书源规则，也不要求导入书源。
class DiscoveryRankingsPage extends StatefulWidget {
  const DiscoveryRankingsPage({
    super.key,
    required this.state,
    required this.repository,
    required this.onSearch,
    this.showHeader = true,
    this.compactMainPageControls = false,
    this.headerKey,
  });

  final LibraryState state;
  final NovelRepository repository;
  final VoidCallback onSearch;
  final bool showHeader;
  final bool compactMainPageControls;
  final GlobalKey<DiscoveryRankingsPageState>? headerKey;

  Widget buildHeader(BuildContext context) =>
      headerKey?.currentState?.buildHeader(context) ??
      const ArchiveMasthead(title: '发现', code: 'DISCOVERY / BOOKS');

  @override
  State<DiscoveryRankingsPage> createState() => DiscoveryRankingsPageState();
}

class DiscoveryRankingsPageState extends State<DiscoveryRankingsPage> {
  final _scrollController = ScrollController();
  OfficialSite _site = OfficialSite.qidian;
  String _rankingId = officialRankings.first.id;
  String _qidianCategoryId = '';
  String _fanqieCategoryId = '1141';
  String _qimaoCategoryId = '';
  bool _fanqieLibrary = false;
  String _fanqieLibraryGender = '-1';
  String _fanqieLibraryCategoryId = '';
  List<Novel> _items = const [];
  Object? _error;
  int _page = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _loaded = false;
  int _generation = 0;
  final _firstPages = <String, ({DateTime saved, OfficialRankingPage result})>{};
  // 番茄官方榜单目录（动态，来自 core）；为空时回落写死的 officialRankings。
  List<OfficialRanking> _fanqieBoards = const [];
  List<OfficialCategory> _fanqieCoreCategories = const [];
  bool _fanqieCoreLoading = false;

  List<OfficialRanking> get _rankings {
    if (_site == OfficialSite.fanqie &&
        !_fanqieLibrary &&
        _fanqieBoards.isNotEmpty) {
      return _fanqieBoards;
    }
    return officialRankings.where((item) => item.site == _site).toList();
  }

  OfficialRanking get _ranking {
    for (final item in _rankings) {
      if (item.id == _rankingId) {
        return _rankingWithCategory(item);
      }
    }
    return _rankingWithCategory(_rankings.first);
  }

  String get _contentKey {
    if (_site == OfficialSite.fanqie && _fanqieLibrary) {
      return 'fanqie-library-$_fanqieLibraryGender-'
          '$_fanqieLibraryCategoryId';
    }
    return '${_ranking.id}-${_ranking.categoryId ?? ''}';
  }

  String get _fanqieLibraryCategoryName {
    for (final category in fanqieLibraryCategories) {
      if (category.id == _fanqieLibraryCategoryId) return category.name;
    }
    return '';
  }

  Set<String> _fanqieChannelCategoryIds(String gender) {
    for (final channel in fanqieLibraryChannels) {
      if (channel.gender == gender) return channel.categoryIds;
    }
    return const {};
  }

  OfficialRanking _rankingWithCategory(OfficialRanking item) {
    return switch (item.site) {
      OfficialSite.qidian => item.copyWith(categoryId: _qidianCategoryId),
      OfficialSite.fanqie => item.copyWith(categoryId: _fanqieCategoryId),
      OfficialSite.qimao => item.copyWith(
        categoryId: _qimaoCategoryId,
        clearCategoryId: item.kind == 'new' || _qimaoCategoryId.isEmpty,
      ),
      OfficialSite.shuqi => item,
    };
  }

  List<OfficialCategory> get _categories => switch (_site) {
    OfficialSite.qidian => qidianCategories,
    OfficialSite.fanqie =>
      (_ranking.kind == 'core' && _fanqieCoreCategories.isNotEmpty)
          ? _fanqieCoreCategories
          : (_ranking.gender == '1'
                ? fanqieMaleCategories
                : fanqieFemaleCategories),
    OfficialSite.qimao =>
      _ranking.kind == 'new'
          ? const []
          : _ranking.gender == 'girl'
          ? qimaoFemaleCategories
          : qimaoMaleCategories,
    OfficialSite.shuqi => const [],
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading || _error != null) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions || position.extentAfter > 480) return;
    unawaited(_load(reset: false));
  }

  Future<void> _load({required bool reset, bool refresh = false}) async {
    final generation = ++_generation;
    final ranking = _ranking;
    final library = _site == OfficialSite.fanqie && _fanqieLibrary;
    final page = reset ? 1 : _page + 1;
    final key = _contentKey;
    final cached = reset && !refresh ? _firstPages[key] : null;
    if (reset && _scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.jumpTo(0);
    }
    setState(() {
      _loading = true;
      if (reset) {
        _items = const [];
        _error = null;
        _page = 0;
        _hasMore = false;
        _loaded = false;
      }
    });
    try {
      final fromCache = cached != null && DateTime.now().difference(cached.saved) < const Duration(minutes: 5);
      final result = fromCache ? cached.result : library
          ? await OfficialBookService.fanqieLibrary(
              gender: _fanqieLibraryGender,
              categoryId: _fanqieLibraryCategoryId.isEmpty
                  ? '-1'
                  : _fanqieLibraryCategoryId,
              categoryName: _fanqieLibraryCategoryName,
              page: page,
            )
          : await OfficialBookService.ranking(ranking, page);
      if (!mounted || generation != _generation) return;
      if (reset && !fromCache) {
        _firstPages.remove(key);
        if (result.books.isNotEmpty) _firstPages[key] = (saved: DateTime.now(), result: result);
        if (_firstPages.length > 24) _firstPages.remove(_firstPages.keys.first);
      }
      final ids = {if (!reset) for (final book in _items) book.id};
      final next = [for (final book in result.books)
        if (book.title.trim().isNotEmpty && ids.add(OfficialBookService.idFor(book))) book.toNovel()];
      final items = [if (!reset) ..._items, ...next];
      setState(() {
        _items = List.unmodifiable(items);
        _page = page;
        _hasMore = next.isNotEmpty && result.hasMore;
        _loaded = true;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatGridWordCount(int? value) {
    if (value == null || value <= 0) return '';
    if (value >= 10000) {
      final text = (value / 10000)
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
      return '$text万字';
    }
    return '$value字';
  }

  String _bookMeta(Novel book) {
    final parts = <String>[
      if (book.genre.trim().isNotEmpty) book.genre.trim(),
      if (_formatGridWordCount(book.wordCount).isNotEmpty)
        _formatGridWordCount(book.wordCount),
    ];
    return parts.join(' · ');
  }

  Future<void> _selectSite(OfficialSite site) async {
    if (site == _site) return;
    final first = officialRankings.firstWhere((item) => item.site == site);
    setState(() {
      _site = site;
      _rankingId = first.id;
      if (site == OfficialSite.qidian) {
        _qidianCategoryId = '';
      } else if (site == OfficialSite.fanqie) {
        _fanqieCategoryId = first.gender == '1' ? '1141' : '1139';
        _fanqieLibrary = false;
        _fanqieLibraryGender = '-1';
        _fanqieLibraryCategoryId = '';
      } else if (site == OfficialSite.qimao) {
        _qimaoCategoryId = '';
      }
      _items = const [];
      _error = null;
      _page = 0;
      _hasMore = false;
      _loaded = false;
    });
    if (site == OfficialSite.fanqie) {
      await _ensureFanqieCore();
    }
    await _load(reset: true);
  }

  Future<void> _selectRanking(OfficialRanking ranking) async {
    if (ranking.id == _rankingId && (_loaded || _loading)) return;
    final genderChanged =
        ranking.site == OfficialSite.qimao && ranking.gender != _ranking.gender;
    setState(() {
      _rankingId = ranking.id;
      if (ranking.site == OfficialSite.qidian) {
        _qidianCategoryId = '';
      } else if (ranking.site == OfficialSite.fanqie) {
        if (ranking.kind != 'core') {
          _fanqieCategoryId = ranking.gender == '1' ? '1141' : '1139';
        }
      } else if (genderChanged) {
        _qimaoCategoryId = '';
      }
    });
    await _load(reset: true);
  }

  Future<void> _selectCategory(OfficialCategory category) async {
    final current = switch (_site) {
      OfficialSite.qidian => _qidianCategoryId,
      OfficialSite.fanqie => _fanqieCategoryId,
      OfficialSite.qimao => _qimaoCategoryId,
      OfficialSite.shuqi => '',
    };
    if (category.id == current && (_loaded || _loading)) return;
    setState(() {
      if (_site == OfficialSite.qidian) {
        _qidianCategoryId = category.id;
      } else if (_site == OfficialSite.fanqie) {
        _fanqieCategoryId = category.id;
      } else if (_site == OfficialSite.qimao) {
        _qimaoCategoryId = category.id;
      }
    });
    await _load(reset: true);
  }

  Future<void> _selectFanqieMode({required bool library}) async {
    if (library == _fanqieLibrary) return;
    setState(() {
      _fanqieLibrary = library;
      _items = const [];
      _error = null;
      _page = 0;
      _hasMore = false;
      _loaded = false;
    });
    if (!library) await _ensureFanqieCore();
    await _load(reset: true);
  }

  Future<void> _selectFanqieLibraryChannel(String gender) async {
    if (gender == _fanqieLibraryGender) return;
    final allowed = _fanqieChannelCategoryIds(gender);
    setState(() {
      _fanqieLibraryGender = gender;
      if (_fanqieLibraryCategoryId.isNotEmpty &&
          !allowed.contains(_fanqieLibraryCategoryId)) {
        _fanqieLibraryCategoryId = '';
      }
    });
    await _load(reset: true);
  }

  Future<void> _chooseFanqieLibraryCategory() async {
    final allowed = _fanqieChannelCategoryIds(_fanqieLibraryGender);
    final categories = [
      for (final category in fanqieLibraryCategories)
        if (allowed.isEmpty || allowed.contains(category.id)) category,
    ];
    final selected = await showJellySheet<String>(
      context: context,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      heightFactor: .8,
      maxWidth: 560,
      builder: (_) => _FanqieCategoryPicker(
        categories: categories,
        selectedId: _fanqieLibraryCategoryId,
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == _fanqieLibraryCategoryId) return;
    setState(() => _fanqieLibraryCategoryId = selected);
    await _load(reset: true);
  }

  Future<void> _refresh() => _load(reset: true, refresh: true);

  /// 拉取番茄官方榜单目录（动态）。核心不可用时静默保持写死兜底。
  Future<void> _ensureFanqieCore() async {
    if (_fanqieBoards.isNotEmpty) return;
    if (_fanqieCoreLoading) return;
    _fanqieCoreLoading = true;
    try {
      final set = await OfficialBookService.fanqieRankCatalog();
      if (!mounted) return;
      if (set != null && set.boards.isNotEmpty) {
        setState(() {
          _fanqieBoards = set.boards;
          _fanqieCoreCategories = set.categories;
          if (!set.boards.any((r) => r.id == _rankingId)) {
            _rankingId = set.boards.first.id;
            _fanqieCategoryId = '';
          }
        });
      }
    } on Object {
      // 核心不可用 → 保持写死的 officialRankings 兜底。
    } finally {
      _fanqieCoreLoading = false;
    }
  }

  Future<void> _openBook(Novel book) async {
    if (_site.supportsDirectReading) {
      openDetail(
        context,
        book,
        widget.state,
        widget.repository,
        coverHeroTag: CoverHeroTag(this, book.id),
        promptAddToShelfOnExit: true,
      );
      return;
    }
    await openInSourceSearch(context, book, widget.state, widget.repository);
  }

  Widget buildHeader(BuildContext context) => Row(
    children: [
      const Expanded(
        child: ArchiveMasthead(title: '发现', code: 'DISCOVERY / BOOKS'),
      ),
      GlassIconButton(
        key: const ValueKey('discovery-search'),
        icon: CupertinoIcons.search,
        label: '搜索书籍',
        onPressed: widget.onSearch,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => GlassHeaderLayout(
    showHeader: widget.showHeader,
    header: buildHeader(context),
    body: CompactMainPageControls(
      enabled: widget.compactMainPageControls,
      child: _buildBody(context),
    ),
  );

  Widget _buildBody(BuildContext context) {
    final rankings = _rankings;
    final ranking = _ranking;
    final library = _site == OfficialSite.fanqie && _fanqieLibrary;
    final bottomInset = DockLayout.scrollPaddingOf(context);
    return RefreshIndicator.noSpinner(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: PageStorageKey('official-discovery-$_contentKey'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: featurePadding(context).copyWith(bottom: 0),
            sliver: SliverToBoxAdapter(
              child: _headerSection(context, rankings, ranking),
            ),
          ),
          if (_loading && _items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: BookCollectionSkeleton(
                  rows: 5,
                  label: library ? '正在读取书库' : '正在读取榜单',
                ),
              ),
            )
          else if (_error != null && _items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ContentNotice(
                icon: CupertinoIcons.wifi_exclamationmark,
                title: library ? '书库加载失败' : '榜单加载失败',
                message: _errorText(_error!),
                onRetry: _refresh,
              ),
            )
          else if (_loaded && _items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ContentNotice(
                icon: CupertinoIcons.book,
                title: library ? '书库暂无书籍' : '榜单暂无书籍',
                message: library ? '换一个分类，或下拉刷新后重试。' : '换一个榜单，或下拉刷新后重试。',
                onRetry: _refresh,
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 10,
                  childAspectRatio: .48,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final book = _items[index];
                  final hero = CoverHeroTag(this, book.id);
                  return _bookGridCard(book, hero);
                }, childCount: _items.length),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 14, 24, bottomInset),
                child: _footer(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bookGridCard(Novel book, Object hero) => JellyTapSurface(
    key: ValueKey(('official-grid-book', _contentKey, book.id)),
    onTap: () => _openBook(book),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NovelCover(
              book,
              width: width,
              height: width * 1.4,
              heroTag: hero,
              fadeIn: true,
            ),
            const SizedBox(height: 7),
            AppText(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            AppText(
              book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_bookMeta(book).isNotEmpty) ...[
              const SizedBox(height: 2),
              AppText(
                _bookMeta(book),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.3,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    ),
  );

  Widget _headerSection(
    BuildContext context,
    List<OfficialRanking> rankings,
    OfficialRanking ranking,
  ) {
    final library = _site == OfficialSite.fanqie && _fanqieLibrary;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chipRow([
          for (final site in OfficialSite.values)
            GlassTextButton(
              key: ValueKey('official-site-${site.name}'),
              compact: true,
              selected: site == _site,
              onPressed: () => _selectSite(site),
              child: AppText(site.label),
            ),
        ]),
        if (_site == OfficialSite.fanqie) ...[
          const SizedBox(height: 8),
          _chipRow([
            GlassTextButton(
              key: const ValueKey('fanqie-mode-ranking'),
              compact: true,
              selected: !_fanqieLibrary,
              onPressed: () => _selectFanqieMode(library: false),
              child: const AppText('排行榜'),
            ),
            GlassTextButton(
              key: const ValueKey('fanqie-mode-library'),
              compact: true,
              selected: _fanqieLibrary,
              onPressed: () => _selectFanqieMode(library: true),
              child: const AppText('分类书库'),
            ),
          ]),
        ],
        if (library) ...[
          const SizedBox(height: 8),
          _chipRow([
            for (final channel in fanqieLibraryChannels)
              GlassTextButton(
                key: ValueKey('fanqie-library-channel-${channel.gender}'),
                compact: true,
                selected: channel.gender == _fanqieLibraryGender,
                onPressed: () => _selectFanqieLibraryChannel(channel.gender),
                child: AppText(channel.name),
              ),
          ]),
          const SizedBox(height: 8),
          Row(
            children: [
              AppText('分类', style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(width: 10),
              GlassTextButton(
                key: const ValueKey('fanqie-library-category'),
                compact: true,
                onPressed: _chooseFanqieLibraryCategory,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppText(
                      _fanqieLibraryCategoryId.isEmpty
                          ? '全部书籍'
                          : _fanqieLibraryCategoryName,
                    ),
                    const SizedBox(width: 4),
                    const ArchiveIcon(CupertinoIcons.chevron_down, size: 12),
                  ],
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 8),
          _chipRow([
            for (final item in rankings)
              GlassTextButton(
                key: ValueKey('official-rank-${item.id}'),
                compact: true,
                selected: item.id == ranking.id,
                onPressed: () => _selectRanking(item),
                child: AppText(item.title),
              ),
          ]),
          if (_categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      right: 8,
                      top: 10,
                      bottom: 10,
                    ),
                    child: AppText(
                      '分类',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                  for (final category in _categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GlassTextButton(
                        key: ValueKey('official-category-${category.id}'),
                        compact: true,
                        selected: category.id == (ranking.categoryId ?? ''),
                        onPressed: () => _selectCategory(category),
                        child: AppText(category.name),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _chipRow(List<Widget> children) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final child in children)
          Padding(padding: const EdgeInsets.only(right: 8), child: child),
      ],
    ),
  );

  Widget _footer(BuildContext context) {
    if (_loading && _items.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: BookCollectionSkeleton(rows: 2, label: '正在加载更多书籍'),
        ),
      );
    }
    if (_error != null && _items.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText(
            '加载下一页失败，已保留当前榜单',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          GlassTextButton(
            onPressed: () => _load(reset: false),
            child: const AppText('重试'),
          ),
        ],
      );
    }
    if (_hasMore) {
      return Center(
        child: GlassTextButton(
          onPressed: _loading ? null : () => _load(reset: false),
          child: AppText(_loading ? '正在加载…' : '加载更多'),
        ),
      );
    }
    return Center(
      child: AppText(
        '已显示全部 ${_items.length} 本',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _errorText(Object error) => '$error';
}

class _FanqieCategoryPicker extends StatefulWidget {
  const _FanqieCategoryPicker({
    required this.categories,
    required this.selectedId,
  });

  final List<FanqieLibraryCategory> categories;
  final String selectedId;

  @override
  State<_FanqieCategoryPicker> createState() => _FanqieCategoryPickerState();
}

class _FanqieCategoryPickerState extends State<_FanqieCategoryPicker> {
  final _query = TextEditingController();
  String _group = fanqieLibraryGroups.first;

  @override
  void initState() {
    super.initState();
    for (final category in widget.categories) {
      if (category.id == widget.selectedId) {
        _group = category.group;
        break;
      }
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _query.text.trim();
    final searching = keyword.isNotEmpty;
    final categories = [
      for (final category in widget.categories)
        if (searching
            ? category.name.contains(keyword)
            : category.group == _group)
          category,
    ];
    final showAll = !searching && _group == fanqieLibraryGroups.first;
    return SizedBox(
      height: math.min(600, MediaQuery.sizeOf(context).height * .76),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: ArchiveSection(title: '选择分类', code: 'LIBRARY / CATEGORIES'),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AppSearchField(
              controller: _query,
              hint: '搜索分类，如悬疑、种田',
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 92,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 2, 6, 24),
                    children: [
                      for (final group in fanqieLibraryGroups)
                        _groupButton(context, group),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: Theme.of(context).dividerColor.withValues(alpha: .55),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: categories.isEmpty && !showAll
                      ? const ContentNotice(
                          icon: CupertinoIcons.search,
                          title: '没有匹配的分类',
                          message: '换个关键词再试试。',
                        )
                      : GridView.builder(
                          key: ValueKey(
                            'fanqie-category-grid-${searching ? keyword : _group}',
                          ),
                          padding: const EdgeInsets.fromLTRB(0, 2, 20, 24),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                mainAxisExtent: 44,
                              ),
                          itemCount: categories.length + (showAll ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (showAll && index == 0) {
                              return _tagChip(context, '', '全部书籍');
                            }
                            final category =
                                categories[index - (showAll ? 1 : 0)];
                            return _tagChip(
                              context,
                              category.id,
                              category.name,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupButton(BuildContext context, String group) {
    final selected = group == _group;
    final action = Theme.of(context).extension<AppTonalColors>()?.action;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: true,
        selected: selected,
        child: JellyTapSurface(
          onTap: () => setState(() {
            _query.clear();
            _group = group;
          }),
          haptic: HapticCue.selection,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : NovelMotion.enter,
            curve: NovelMotion.settle,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
            decoration: BoxDecoration(
              color: selected && action != null
                  ? action.withValues(alpha: .09)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: AppText(
              _groupLabel(group),
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.3,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? action : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tagChip(BuildContext context, String id, String name) {
    final selected = id == widget.selectedId;
    final action = Theme.of(context).extension<AppTonalColors>()?.action;
    return ContentPanel(
      key: ValueKey('fanqie-library-category-option-$id'),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      radius: 9,
      backgroundColor: selected && action != null
          ? action.withValues(alpha: .10)
          : Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
      borderColor: selected && action != null
          ? action.withValues(alpha: .42)
          : Theme.of(context).dividerColor.withValues(alpha: .45),
      onTap: () => Navigator.pop(context, id),
      child: Center(
        child: AppText(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            height: 1.2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? action : null,
          ),
        ),
      ),
    );
  }

  String _groupLabel(String group) => group == '主分类' ? '热门标签' : group;
}
