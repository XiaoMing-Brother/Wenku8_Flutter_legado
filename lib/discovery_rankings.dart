import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
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
  List<Novel> _items = const [];
  Object? _error;
  int _page = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _loaded = false;
  int _generation = 0;

  List<OfficialRanking> get _rankings =>
      officialRankings.where((item) => item.site == _site).toList();

  OfficialRanking get _ranking {
    for (final item in _rankings) {
      if (item.id == _rankingId) {
        return switch (item.site) {
          OfficialSite.qidian => item.copyWith(categoryId: _qidianCategoryId),
          OfficialSite.fanqie => item.copyWith(categoryId: _fanqieCategoryId),
          OfficialSite.qimao || OfficialSite.shuqi => item,
        };
      }
    }
    final first = _rankings.first;
    return switch (first.site) {
      OfficialSite.qidian => first.copyWith(categoryId: _qidianCategoryId),
      OfficialSite.fanqie => first.copyWith(categoryId: _fanqieCategoryId),
      OfficialSite.qimao || OfficialSite.shuqi => first,
    };
  }

  List<OfficialCategory> get _categories => switch (_site) {
    OfficialSite.qidian => qidianCategories,
    OfficialSite.fanqie => _ranking.gender == '1'
        ? fanqieMaleCategories
        : fanqieFemaleCategories,
    OfficialSite.qimao || OfficialSite.shuqi => const [],
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

  Future<void> _load({required bool reset}) async {
    final generation = ++_generation;
    final ranking = _ranking;
    final page = reset ? 1 : _page + 1;
    if (reset &&
        _scrollController.hasClients &&
        _scrollController.offset > 0) {
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
      final result = await OfficialBookService.ranking(ranking, page);
      if (!mounted || generation != _generation) return;
      final next = result.books
          .map(_novelFromOfficial)
          .whereType<Novel>()
          .toList(growable: false);
      final items = reset
          ? next
          : [
              ..._items,
              for (final item in next)
                if (!_items.any((known) => known.id == item.id)) item,
            ];
      setState(() {
        _items = List.unmodifiable(items);
        _page = page;
        _hasMore = result.hasMore;
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

  Novel? _novelFromOfficial(OfficialBook book) {
    if (book.title.trim().isEmpty) return null;
    return Novel(
      id: OfficialBookService.idFor(book),
      title: book.title,
      author: book.author,
      genre: book.kind,
      summary: book.summary,
      colors: const [Color(0xFF31405A), Color(0xFF1B2333)],
      coverUrl: book.coverUrl.isEmpty ? null : book.coverUrl,
      wordCount: _wordCountFromLabel(book.wordCount),
      source: OfficialBookService.refFor(book),
    );
  }

  int? _wordCountFromLabel(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final tenK = RegExp(r'([\d.]+)\s*万字').firstMatch(text);
    if (tenK != null) {
      final amount = double.tryParse(tenK.group(1)!);
      return amount == null ? null : (amount * 10000).round();
    }
    final chars = RegExp(r'([\d.]+)\s*字').firstMatch(text);
    if (chars != null) {
      return double.tryParse(chars.group(1)!)?.round();
    }
    return int.tryParse(text);
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
      }
      _items = const [];
      _error = null;
      _page = 0;
      _hasMore = false;
      _loaded = false;
    });
    await _load(reset: true);
  }

  Future<void> _selectRanking(OfficialRanking ranking) async {
    if (ranking.id == _rankingId && (_loaded || _loading)) return;
    setState(() {
      _rankingId = ranking.id;
      if (ranking.site == OfficialSite.qidian) {
        _qidianCategoryId = '';
      } else if (ranking.site == OfficialSite.fanqie) {
        _fanqieCategoryId = ranking.gender == '1' ? '1141' : '1139';
      }
    });
    await _load(reset: true);
  }

  Future<void> _selectCategory(OfficialCategory category) async {
    final current = _site == OfficialSite.qidian
        ? _qidianCategoryId
        : _fanqieCategoryId;
    if (category.id == current && (_loaded || _loading)) return;
    setState(() {
      if (_site == OfficialSite.qidian) {
        _qidianCategoryId = category.id;
      } else {
        _fanqieCategoryId = category.id;
      }
    });
    await _load(reset: true);
  }

  Future<void> _refresh() => _load(reset: true);

  Future<void> _openBook(Novel book) async {
    if (_site.supportsDirectReading) {
      openDetail(
        context,
        book,
        widget.state,
        widget.repository,
        coverHeroTag: CoverHeroTag(this, book.id),
      );
      return;
    }
    await openInSourceSearch(context, book, widget.state, widget.repository);
  }

  Future<void> _openActions(BuildContext anchor) async {
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: widget.state.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassMenuItem(
            label: '搜索书籍',
            icon: CupertinoIcons.search,
            order: 0,
            onPressed: () => Navigator.pop(menu, 'search'),
          ),
          GlassMenuItem(
            label: '刷新当前榜单',
            icon: CupertinoIcons.arrow_2_circlepath,
            order: 1,
            onPressed: () => Navigator.pop(menu, 'refresh'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'search':
        widget.onSearch();
      case 'refresh':
        await _refresh();
    }
  }

  Widget buildHeader(BuildContext context) => Row(
    children: [
      const Expanded(
        child: ArchiveMasthead(title: '发现', code: 'DISCOVERY / BOOKS'),
      ),
      GlassMenuAnchor(
        child: Builder(
          builder: (anchor) => GlassIconButton(
            key: const ValueKey('discovery-actions'),
            icon: CupertinoIcons.ellipsis,
            label: '发现操作',
            onPressed: () => _openActions(anchor),
          ),
        ),
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
    final bottomInset = DockLayout.scrollPaddingOf(context);
    return RefreshIndicator.noSpinner(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: PageStorageKey('official-discovery-${_site.name}'),
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
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: BookCollectionSkeleton(rows: 5, label: '正在读取榜单'),
              ),
            )
          else if (_error != null && _items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ContentNotice(
                icon: CupertinoIcons.wifi_exclamationmark,
                title: '榜单加载失败',
                message: _errorText(_error!),
                onRetry: _refresh,
              ),
            )
          else if (_loaded && _items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ContentNotice(
                icon: CupertinoIcons.book,
                title: '榜单暂无书籍',
                message: '换一个榜单，或下拉刷新后重试。',
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
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final book = _items[index];
                    final hero = CoverHeroTag(this, book.id);
                    return _bookGridCard(book, hero);
                  },
                  childCount: _items.length,
                ),
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
    key: ValueKey(('official-grid-book', _ranking.id, book.id)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final site in OfficialSite.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GlassTextButton(
                    key: ValueKey('official-site-${site.name}'),
                    compact: true,
                    selected: site == _site,
                    onPressed: () => _selectSite(site),
                    child: AppText(site.label),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final item in rankings)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GlassTextButton(
                    key: ValueKey('official-rank-${item.id}'),
                    compact: true,
                    selected: item.id == ranking.id,
                    onPressed: () => _selectRanking(item),
                    child: AppText(item.title),
                  ),
                ),
            ],
          ),
        ),
        if (_categories.isNotEmpty) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
                  child: AppText(
                    '分类',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
    );
  }

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
