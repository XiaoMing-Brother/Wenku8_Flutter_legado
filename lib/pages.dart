import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import 'app_ui.dart';
import 'app_palette.dart';
import 'app_window_insets.dart';
import 'app_search_field.dart';
import 'setting_menu.dart';
import 'cover_images.dart';
import 'change_cover_sheet.dart';
import 'font_settings_page.dart';
import 'palette_settings_page.dart';
import 'my_page.dart';
import 'official_books.dart';
import 'illustration_layout_page.dart';
import 'illustration_placement.dart';
import 'automatic_illustrations.dart';
import 'local_book_series.dart';
import 'local_book_batch_page.dart';
import 'app_interactions.dart';
import 'author_works_page.dart';
import 'archive_carousel.dart';
import 'backup_page.dart';
import 'haptic_settings_page.dart';
import 'book_collection_layout.dart';
import 'book_collection_mode.dart';
import 'book_shelf_preferences.dart';
import 'book_shelf_content_preferences.dart';
import 'book_shelf_content_projection.dart';
import 'book_collection_view_options.dart';
import 'book_collection_region_toolbar.dart';
import 'book_collection_grid.dart';
import 'book_grid_density.dart';
import 'book_categories.dart';
import 'book_list_import_page.dart';
import 'bookshelf_scope.dart';
import 'book_source_badge.dart';
import 'book_search.dart';
import 'book_sources/book_source.dart';
import 'book_sources/book_source_library.dart';
import 'book_sources/book_source_search_scope.dart';
import 'book_sources/book_source_scope_sheet.dart';
import 'book_sources/fanqie_review_service.dart';
import 'book_sources/inline_review.dart';
import 'book_sources/library_sources_repository.dart';
import 'book_sources/paragraph_review_service.dart';
import 'book_sources/qimao_review_service.dart';
import 'reader_paragraph_review.dart';
import 'blocked_tags_controls.dart';
import 'catalog.dart';
import 'glass_dock.dart';
import 'home_navigation.dart';
import 'library_state.dart';
import 'library_source_access.dart';
import 'pending_book.dart';
import 'reading_activity.dart';
import 'reading_moment_cover.dart';
import 'reading_moments.dart';
import 'reading_moments_ui.dart';
import 'reading_moments_settings_page.dart';
import 'reading_widget_settings_page.dart';
import 'reading_visual_theme.dart';
import 'library_toolbar.dart';
import 'library_workspace.dart';
import 'library_reflow.dart';
import 'library_search_repository.dart';
import 'listening/controller.dart';
import 'listening/models.dart' show hasSpeechText, ListeningPhase;
import 'listening/widgets.dart';
import 'listening/custom_tts_page.dart';
import 'listening/reader_target.dart';
import 'local_platform.dart';
import 'local_books.dart';
import 'local_library_page.dart';
import 'local_library_preferences.dart';
import 'local_book_editor.dart';
import 'local_book_importer.dart';
import 'local_text_reference.dart';
import 'local_text_recovery.dart';
import 'native_effects.dart' show NativeGlassGroup;
import 'lan_handoff_widgets.dart';
import 'network_status.dart';
import 'novel_feed_controller.dart';
import 'offline_cache.dart' show formatCacheBytes;
import 'offline_repository.dart';
import 'offline_widgets.dart';
import 'low_performance_page.dart';
import 'frame_rate_settings.dart';
import 'reader_catalogue.dart';
import 'reader_chrome.dart';
import 'reader_tap_surface.dart';
import 'reader_touch_surface.dart';
import 'reader_article_boundary.dart';
import 'reader_appearance.dart';
import 'reader_handoff_navigation.dart';
import 'reader_background.dart';
import 'reader_content.dart';
import 'reader_chapter_heading.dart';
import 'reader_rich_content.dart';
import 'reader_scroll_stream.dart';
import 'discovery_rankings.dart';
import 'dock_layout.dart';
import 'reader_follow_scroll.dart';
import 'reader_listening_follow.dart';
import 'reader_illustrations.dart';
import 'reader_volume_illustrations.dart';
import 'local_image_layout.dart';
import 'reader_find.dart';
import 'reader_book_find.dart';
import 'reader_annotations.dart';
import 'reader_annotation_editor.dart';
import 'reader_embedded_vertical.dart';
import 'lan_reading_sync.dart';
import 'lan_reading_page.dart';
import 'reader_pagination.dart';
import 'reader_paged_view.dart';
import 'reader_vertical_text.dart';
import 'reader_reflow.dart';
import 'reader_turn_motion.dart';
import 'reader_header_footer.dart';
import 'reader_tip.dart';
import 'reader_review_sheet.dart';
import 'reader_more_sheet.dart';
import 'reader_selection.dart';
import 'reader_underline.dart';
import 'reader_dictionary.dart';
import 'replace_rules/replace_rule_store.dart';
import 'replace_rules/replace_rules_page.dart';
import 'dict_rules/dict_rule_store.dart';
import 'dict_rules/dict_rules_page.dart';
import 'txt_toc_rules/txt_toc_rule_store.dart';
import 'txt_toc_rules/txt_toc_rules_page.dart';
import 'reader_landing_highlight.dart';
import 'reader_tools.dart';
import 'reader_status.dart';
import 'reader_scroll_location.dart';
import 'reader_source_progress.dart';
import 'reader_preferences.dart';
import 'reader_text.dart';
import 'reading_history.dart';
import 'recent_searches.dart';
import 'ui_notifiers.dart';
import 'route_identity.dart';
import 'feature_pages.dart';
import 'legacy_import_page.dart';
import 'legacy_transport.dart';

export 'app_ui.dart' show sectionHeader;

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.state,
    required this.repository,
    this.network,
  });
  final LibraryState state;
  final NovelRepository repository;
  final NetworkStatus? network;

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  void openShelf() {
    if (_searchOpen) _closeSearch();
    _selectTab(_navigation.destination(1));
  }

  late final _navigation = HomeNavigation(widget.state, widget.network);
  late List<int> _visibleTabs;
  final _visitedTabs = <int>{};
  static final _scrollPlatforms = TargetPlatform.values.toSet();
  late final _tabScrolls = [
    for (var i = 0; i < _dockItems.length; i++)
      ScrollController(debugLabel: 'home-tab-$i'),
  ];
  final _searchScroll = ScrollController(debugLabel: 'home-search');
  static const _dockItems = [
    GlassDockItem(CupertinoIcons.house, '发现'),
    GlassDockItem(CupertinoIcons.book, '书架', symbol: ArchiveSymbol.shelf),
    GlassDockItem(CupertinoIcons.folder, '本地'),
    GlassDockItem(CupertinoIcons.person_crop_circle, '我的'),
  ];
  late final _searchFeed = NovelFeedController(
    widget.repository,
    search: true,
    mergeSourceResults: true,
  )..searchField = BookSearchField.all;
  late final BookSourceLibrary? _sources = _bookSourceLibrary;
  BookSourceLibrary? get _bookSourceLibrary {
    final repository = widget.repository;
    if (repository is OfflineNovelRepository) return repository.bookSources;
    if (repository is LibrarySourcesRepository) return repository.bookSources;
    if (repository is BookSourceLibrary) {
      return repository as BookSourceLibrary;
    }
    return null;
  }

  String? get _searchScopeLabel {
    final library = _bookSourceLibrary;
    return library == null || library.searchScope.isAll
        ? null
        : library.searchScopeLabel;
  }

  VoidCallback? get _openSearchScopeAction {
    final library = _bookSourceLibrary;
    return library == null ? null : () => _openSearchScope(library);
  }

  LocalBookStore? get _localBooks => widget.repository is OfflineNovelRepository
      ? (widget.repository as OfflineNovelRepository).local
      : null;
  late final _localSearch = NovelFeedController(
    LibrarySearchRepository(
      source: widget.repository,
      state: widget.state,
      local: _localBooks,
      localOnly: true,
    ),
    search: true,
  )..searchField = BookSearchField.title;
  int _searchScope = 0;
  NovelFeedController get _activeSearch => switch (_searchScope) {
    1 => _searchFeed,
    2 => _localSearch,
    _ => _searchFeed,
  };
  final _localLibrary = LocalLibraryController();
  final _discoverHeaderKey = GlobalKey<DiscoveryRankingsPageState>();
  List<Widget> _pageWidgets = const [];
  List<WidgetBuilder> _headers = const [];
  int _tab = 0;
  double _tabDirection = 1;
  int? _outgoingTab;
  bool _searchOpen = false;
  bool _searchMounted = false;
  bool _searchCovered = false;
  bool _searchFocusPending = false;
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode(
    debugLabel: 'inline-search',
    canRequestFocus: false,
  );
  bool _searchStarted = false;
  bool? _routeCurrent;
  String _lastRecordedSearch = '';
  late final AnimationController _searchExpansion =
      AnimationController(
        vsync: this,
        duration: NovelMotion.enter,
        reverseDuration: NovelMotion.exit,
      )..addStatusListener((status) {
        if (!mounted) return;
        if (status == AnimationStatus.dismissed && !_searchOpen) {
          setState(() => _searchMounted = false);
        } else if (status == AnimationStatus.completed && _searchOpen) {
          setState(() => _searchCovered = true);
          _focusOpenedSearch();
        }
      });
  late final AnimationController _pageTransition =
      AnimationController(vsync: this, duration: NovelMotion.enter, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _outgoingTab = null);
          }
        });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visibleTabs = _navigation.tabs;
    _tab = _navigation.destination(widget.state.startPage.index);
    _visitedTabs.add(_tab);
    _navigation.addListener(_navigationChanged);
    _searchText.addListener(_searchEdited);
    _searchFeed.addListener(_searchSucceeded);
    _sources?.changes.addListener(_bookSourcesChanged);
    widget.state.blockedTagsChanges.addListener(_blockedTagsChanged);
    _blockedTagsChanged();
    if (widget.repository case final OfflineNovelRepository offline) {
      unawaited(offline.loadCache().catchError((Object _) {}));
    }
    final discover = DiscoveryRankingsPage(
      key: _discoverHeaderKey,
      headerKey: _discoverHeaderKey,
      state: widget.state,
      repository: widget.repository,
      showHeader: false,
      compactMainPageControls: true,
      onSearch: _openSearch,
    );
    final shelf = ShelfPage(
      books: const [],
      state: widget.state,
      repository: widget.repository,
      showHeader: false,
      compactMainPageControls: true,
      onSearch: _openSearch,
      navigation: _navigation,
    );
    final settings = MyPage(
      state: widget.state,
      repository: widget.repository,
      showHeader: false,
    );
    final local = widget.repository is OfflineNovelRepository
        ? (widget.repository as OfflineNovelRepository).local
        : null;
    final localPage = local == null
        ? null
        : LocalLibraryPage(
            books: local,
            state: widget.state,
            controller: _localLibrary,
            showHeader: false,
            compactMainPageControls: true,
            onSearch: _openSearch,
            onOpen: (page, book) => openDetail(
              page,
              book,
              widget.state,
              widget.repository,
              entry: ReadingEntry.local,
            ),
            onOpenWithCover: (page, book, tag) => openDetail(
              page,
              book,
              widget.state,
              widget.repository,
              coverHeroTag: tag,
              entry: ReadingEntry.local,
            ),
          );
    _headers = [
      discover.buildHeader,
      shelf.buildHeader,
      localPage?.buildHeader ??
          (_) => const ArchiveMasthead(title: '本地', code: 'LOCAL / LIBRARY'),
      settings.buildHeader,
    ];
    _pageWidgets =
        [
              discover,
              shelf,
              localPage ?? const Center(child: AppText('当前演示数据源未启用本地书库')),
              settings,
            ].indexed
            .map(
              (entry) => PrimaryScrollController(
                controller: _tabScrolls[entry.$1],
                automaticallyInheritForPlatforms: _scrollPlatforms,
                child: RepaintBoundary(child: Atmosphere(child: entry.$2)),
              ),
            )
            .toList(growable: false);
  }

  void _blockedTagsChanged() {
    _searchFeed.setBlockedTags(widget.state.blockedTags);
  }

  void _bookSourcesChanged() {
    if (mounted) setState(() {});
  }

  void _navigationChanged() {
    if (!mounted) return;
    final tabs = _navigation.tabs;
    final next = _navigation.destination(_tab);
    if (_searchOpen && !tabs.contains(_searchScope)) _closeSearch();
    setState(() {
      _visibleTabs = tabs;
    });
    if (next != _tab) _selectTab(next);
    if (_searchOpen && _searchScope == 1 && _routeCurrent != false) {
      _searchFeed.refresh();
    }
  }

  void _routeChanged(ModalRoute<dynamic>? route) {
    final current = route?.isCurrent;
    // An obscured route also pauses search work: results cannot be seen, and
    // native requests would keep competing with the page now in front.
    if (current == false) {
      if (_searchOpen || _searchMounted) _cancelSearchRequests();
    }
    _routeCurrent = current;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _cancelSearchRequests();
    }
  }

  void _cancelSearchRequests() {
    _searchFocusPending = false;
    _searchFeed.cancelScheduledSearch();
    _localSearch.cancelScheduledSearch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.blockedTagsChanges.removeListener(_blockedTagsChanged);
    _navigation.removeListener(_navigationChanged);
    _sources?.changes.removeListener(_bookSourcesChanged);
    _navigation.dispose();
    _pageTransition.dispose();
    _searchExpansion.dispose();
    _searchText.dispose();
    _searchFocus.dispose();
    _searchFeed.dispose();
    _localSearch.dispose();
    _localLibrary.dispose();
    for (final scroll in _tabScrolls) {
      scroll.dispose();
    }
    _searchScroll.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context);

  void _openSearch() {
    _searchFocus.canRequestFocus = true;
    _searchScope = _tab;
    final feed = _activeSearch;
    _searchText.value = TextEditingValue(
      text: feed.query,
      selection: TextSelection.collapsed(offset: feed.query.length),
    );
    _searchFocusPending = true;
    if (_searchScope != 0) {
      feed.refresh();
    } else if (!_searchStarted ||
        (_searchFeed.page == 0 && !_searchFeed.loading)) {
      _searchStarted = true;
      _searchFeed.loadInitial();
    }
    setState(() {
      _searchOpen = true;
      _searchMounted = true;
    });
    if (_reduceMotion) {
      _searchExpansion.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusOpenedSearch();
      });
    } else {
      _searchExpansion.forward();
    }
  }

  void _focusOpenedSearch() {
    if (!_searchFocusPending ||
        !_searchOpen ||
        _searchFocus.context == null ||
        _routeCurrent == false) {
      return;
    }
    _searchFocusPending = false;
    _searchFocus.requestFocus();
  }

  void _dismissSearchKeyboard() {
    _searchFocusPending = false;
    _searchFocus.unfocus();
  }

  void _closeSearch() {
    _dismissSearchKeyboard();
    _searchFocus.canRequestFocus = false;
    _cancelSearchRequests();
    setState(() {
      _searchOpen = false;
      _searchCovered = false;
    });
    if (_reduceMotion) {
      _searchExpansion.value = 0;
    } else {
      _searchExpansion.reverse();
    }
  }

  void _searchEdited() {
    if (!_searchOpen) return;
    if (!_searchText.value.composing.isCollapsed) {
      _activeSearch.cancelScheduledSearch();
      return;
    }
    _activeSearch.scheduleSearch(_searchText.text);
  }

  void _searchSucceeded() {
    if (_searchScope == 2 ||
        _searchFeed.loading ||
        _searchFeed.error != null ||
        _searchFeed.page < 1) {
      return;
    }
    final query = _searchFeed.query.trim();
    if (query == _lastRecordedSearch) return;
    _lastRecordedSearch = query;
    unawaited(
      widget.state.recordSearch(query).catchError((Object _) {
        if (_lastRecordedSearch == query) _lastRecordedSearch = '';
        if (mounted) showNovelFeedback(context, '最近搜索保存失败');
      }),
    );
  }

  void _recallSearch(String query) {
    _searchText.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _searchFeed.searchFor(query);
    _dismissSearchKeyboard();
  }

  void _scrollTabToTop(int index) {
    for (final position in _tabScrolls[index].positions.toList()) {
      if (position.pixels <= position.minScrollExtent) continue;
      if (_reduceMotion) {
        position.jumpTo(position.minScrollExtent);
      } else {
        unawaited(
          position.animateTo(
            position.minScrollExtent,
            duration: NovelMotion.enter,
            curve: NovelMotion.ease,
          ),
        );
      }
    }
  }

  void _selectTab(int index) {
    if (index == _tab || !_visibleTabs.contains(index)) return;
    if (index == 2) _localLibrary.refresh?.call();
    FocusManager.instance.primaryFocus?.unfocus();
    final reduceMotion =
        widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context);
    setState(() {
      if (index != _tab) {
        _tabDirection = index > _tab ? 1 : -1;
        _outgoingTab = reduceMotion ? null : _tab;
        if (reduceMotion) {
          _pageTransition.value = 1;
        } else {
          _pageTransition.forward(from: 0);
        }
      }
      _tab = index;
      _visitedTabs.add(index);
    });
  }

  Widget _tabPlane(int index) {
    if (!_visitedTabs.contains(index)) {
      return SizedBox.shrink(key: ValueKey('home-tab-unvisited-$index'));
    }
    final active = index == _tab;
    final outgoing = index == _outgoingTab;
    final animation = (active || outgoing) && !_reduceMotion
        ? _pageTransition
        : const AlwaysStoppedAnimation<double>(1);
    return RetainedPane(
      key: ValueKey('home-tab-$index'),
      active: !_searchCovered && (active || outgoing),
      child: ExcludeFocus(
        excluding: !active || _searchMounted,
        child: TickerMode(
          enabled: active && !_searchCovered,
          child: HeroMode(
            enabled: active && !_searchMounted,
            child: IgnorePointer(
              ignoring: !active || _searchMounted,
              child: ExcludeSemantics(
                excluding: !active || _searchMounted,
                child: ArchivePlaneTransition(
                  key: ValueKey('home-archive-plane-$index'),
                  animation: animation,
                  kind: outgoing
                      ? ArchivePlaneKind.outgoing
                      : ArchivePlaneKind.incoming,
                  direction: _tabDirection,
                  child: ArchiveMotionScope(
                    animation: animation,
                    enabled: active && !_reduceMotion,
                    child: _pageWidgets[index],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _HomeRouteBinding(
    onChanged: _routeChanged,
    child: PrimaryScrollController(
      // The scaffold's iOS status-bar scroll action follows the visible page.
      // Search has its own position and must not also move the retained tab.
      controller: _searchMounted ? _searchScroll : _tabScrolls[_tab],
      automaticallyInheritForPlatforms: _scrollPlatforms,
      child: _buildWorkspace(context),
    ),
  );

  Widget _buildWorkspace(BuildContext context) => LibraryWorkspace(
    reduceMotion: widget.state.reduceMotion,
    child: PopScope<void>(
      canPop: !_searchMounted,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _searchMounted) _closeSearch();
      },
      child: Scaffold(
        body: Atmosphere(
          // Each tab/search paints its own archive diagram; the shell only
          // supplies the fallback canvas during a transition.
          archiveBackdrop: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          for (var i = 0; i < _pageWidgets.length; i++)
                            if (i != _tab && i != _outgoingTab) _tabPlane(i),
                          if (_outgoingTab case final outgoing?)
                            _tabPlane(outgoing),
                          _tabPlane(_tab),
                        ],
                      ),
                    ),
                    if (_searchMounted)
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !_searchOpen,
                          child: ArchivePlaneTransition(
                            key: const ValueKey('search-archive-plane'),
                            animation: _searchExpansion,
                            child: Atmosphere(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: _searchTabsHeight(context),
                                ),
                                child: InlineSearchResults(
                                  feed: _activeSearch,
                                  state: widget.state,
                                  repository: widget.repository,
                                  onOpenBook: _dismissSearchKeyboard,
                                  allowBlockedTags: _searchScope != 2,
                                  showSources:
                                      _searchScope == 1 &&
                                      widget.state.combinedShelf,
                                  allowShelfQuickAdd: _searchScope == 1,
                                  onRecall: _searchScope != 2
                                      ? _recallSearch
                                      : null,
                                  sourceScopeLabel: _searchScope != 2
                                      ? _searchScopeLabel
                                      : null,
                                  onOpenSourceScope: _searchScope != 2
                                      ? _openSearchScopeAction
                                      : null,
                                  emptyQueryTitle: switch (_searchScope) {
                                    1 => '搜索并加入书架',
                                    2 => '本地书籍',
                                    _ => '你可能会喜欢',
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      key: const ValueKey('home-pinned-header'),
                      top: 0,
                      left: 0,
                      right: 0,
                      child: FrostedHeader(
                        extraHeight: _searchMounted
                            ? _searchTabsHeight(context)
                            : 0,
                        child: _searchMounted
                            ? Column(
                                children: [
                                  SizedBox(
                                    height: FrostedHeader.toolbarHeight,
                                    child: _expandedSearchHeader(context),
                                  ),
                                  SizedBox(
                                    height: _searchTabsHeight(context),
                                    child: _searchTabs(context),
                                  ),
                                ],
                              )
                            : ArchiveMotionScope(
                                animation: _pageTransition,
                                enabled: !_reduceMotion,
                                child: Row(
                                  children: [
                                    Expanded(child: _headers[_tab](context)),
                                    if (ListeningScope.maybeOf(context)
                                        case final listening?)
                                      SelectedValueBuilder<
                                        ListeningSnapshot,
                                        Novel?
                                      >(
                                        listenable: listening.snapshot,
                                        select: (session) => session.active
                                            ? session.novel
                                            : null,
                                        builder: (context, novel, _) =>
                                            novel == null
                                            ? const SizedBox.shrink()
                                            : Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 4,
                                                ),
                                                child: GlassIconButton(
                                                  key: const ValueKey(
                                                    'home-listening-entry',
                                                  ),
                                                  icon:
                                                      CupertinoIcons.headphones,
                                                  label:
                                                      '正在听书 · ${novel.title}',
                                                  onPressed: () {
                                                    // This button does not rebuild at clip boundaries;
                                                    // opening the panel still uses the live cursor.
                                                    final session = listening
                                                        .snapshot
                                                        .value;
                                                    if (session.novel == null ||
                                                        !session.active) {
                                                      return;
                                                    }
                                                    showListeningPanel(
                                                      context,
                                                      controller: listening,
                                                      novel: session.novel!,
                                                      chapter: session.chapter,
                                                      paragraph:
                                                          session
                                                              .current
                                                              ?.paragraph ??
                                                          0,
                                                      reduceMotion: widget
                                                          .state
                                                          .reduceMotion,
                                                      onOpenReader: (target) =>
                                                          pushNovelPage<void>(
                                                            context,
                                                            ReaderPage(
                                                              novel:
                                                                  target.novel,
                                                              state:
                                                                  widget.state,
                                                              repository: widget
                                                                  .repository,
                                                              initialChapter:
                                                                  target
                                                                      .position
                                                                      .chapter,
                                                              initialPosition:
                                                                  target
                                                                      .position,
                                                            ),
                                                            reduceMotion: widget
                                                                .state
                                                                .reduceMotion,
                                                          ),
                                                    );
                                                  },
                                                ),
                                              ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DockUnderlay(),
              ),
              AnimatedBuilder(
                animation: _searchExpansion,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      22 + MediaQuery.paddingOf(context).left,
                      0,
                      22 + MediaQuery.paddingOf(context).right,
                      DockLayout.bottomPaddingOf(context),
                    ),
                    child: LibraryReflowPart(
                      child: GlassDock(
                        key: const ValueKey('liquid-dock'),
                        selectedIndex: _visibleTabs.indexOf(_tab),
                        reduceMotion: widget.state.reduceMotion,
                        onSelected: (slot) => _selectTab(_visibleTabs[slot]),
                        onReselected: (slot) =>
                            _scrollTabToTop(_visibleTabs[slot]),
                        items: [
                          for (final page in _visibleTabs) _dockItems[page],
                        ],
                      ),
                    ),
                  ),
                ),
                builder: (context, child) => IgnorePointer(
                  ignoring: _searchMounted,
                  child: ExcludeSemantics(
                    excluding: _searchMounted,
                    child: Opacity(
                      opacity: 1 - _searchExpansion.value,
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _expandedSearchHeader(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: _searchExpansion,
      child: _searchField(context),
      builder: (context, child) {
        final t = _searchExpansion.value;
        final expansion = NovelMotion.ease.transform(t);
        final wobble = _reduceMotion ? 0.0 : NovelMotion.jelly(t);
        final width = 46 + (constraints.maxWidth - 46) * expansion;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            ExcludeSemantics(
              child: Opacity(
                opacity: 1 - expansion,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ArchiveMasthead(
                    title: switch (_searchScope) {
                      1 => '书架',
                      2 => '本地',
                      _ => '发现',
                    },
                    code: switch (_searchScope) {
                      1 => 'LIBRARY / BOOKSHELF',
                      2 => 'LOCAL / LIBRARY',
                      _ => 'DISCOVERY / BOOKS',
                    },
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Transform(
                key: const ValueKey('search-jelly-transform'),
                alignment: Alignment.centerRight,
                transform: Matrix4.diagonal3Values(
                  1 + .026 * wobble,
                  1 - .042 * wobble,
                  1,
                ),
                child: IgnorePointer(
                  ignoring: !_searchOpen || t < .4,
                  child: LiquidGlass(
                    key: const ValueKey('expanded-search-bar'),
                    radius: 24 - expansion,
                    elevated: false,
                    activation: wobble.abs() * .35,
                    touchPosition: .94,
                    child: SizedBox(
                      width: width,
                      height: 46,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24 - expansion),
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: constraints.maxWidth,
                          maxWidth: constraints.maxWidth,
                          minHeight: 46,
                          maxHeight: 46,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _searchField(BuildContext context) => Row(
    children: [
      const SizedBox(
        width: 44,
        child: ArchiveIcon(CupertinoIcons.search, size: 19),
      ),
      Expanded(
        child: AppSearchField(
          inputKey: const ValueKey('expanded-search-input'),
          embedded: true,
          showLeading: false,
          hint: _searchScope == 1
              ? '搜索书名、作者或标签，加入书架'
              : _activeSearch.searchField.hint,
          controller: _searchText,
          focusNode: _searchFocus,
          onSubmitted: (query) {
            _activeSearch.searchFor(query);
            _dismissSearchKeyboard();
          },
        ),
      ),
      if (_searchScope != 2)
        if (_bookSourceLibrary case final library?)
          SizedBox(
            width: 44,
            height: 46,
            child: ArchiveIconButton(
              key: const ValueKey('search-source-scope'),
              tooltip: '搜索范围：${library.searchScopeLabel}',
              onPressed: () => _openSearchScope(library),
              icon: ArchiveIcon(
                CupertinoIcons.line_horizontal_3_decrease,
                size: 18,
                color: library.searchScope.isAll
                    ? null
                    : Theme.of(context).extension<AppTonalColors>()?.action,
              ),
            ),
          ),
      SizedBox(
        width: 46,
        height: 46,
        child: ArchiveIconButton(
          key: const ValueKey('inline-search-close'),
          tooltip: '收起搜索',
          onPressed: _closeSearch,
          icon: const ArchiveIcon(CupertinoIcons.xmark, size: 17),
        ),
      ),
    ],
  );

  double _searchTabsHeight(BuildContext context) =>
      math.max(48, MediaQuery.textScalerOf(context).scale(14) * 1.4 + 12) + 16;

  Widget _searchTabs(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: AppControls.segments<BookSearchField>(
      context,
      key: const ValueKey('home-search-tabs'),
      groupValue: _activeSearch.searchField,
      children: {
        BookSearchField.all: Text(appText(context, '全部')),
        BookSearchField.title: Text(appText(context, '书名')),
        BookSearchField.author: Text(appText(context, '作者')),
        BookSearchField.tags: Text(appText(context, '标签')),
        BookSearchField.id: Text(appText(context, 'ID')),
      },
      onValueChanged: (field) {
        if (field != null) _selectSearchField(field);
      },
    ),
  );

  Future<void> _selectSearchField(BookSearchField field) async {
    if (_activeSearch.searchField == field) return;
    _dismissSearchKeyboard();
    final pending = _activeSearch.selectSearchField(field);
    setState(() {});
    await pending;
  }

  Future<void> _openSearchScope(BookSourceLibrary library) async {
    _dismissSearchKeyboard();
    final previous = library.searchScope;
    final applied = await showBookSourceScopeSheet(
      context: context,
      library: library,
      reduceMotion: _reduceMotion,
    );
    if (!mounted || applied == null || applied == previous) return;
    if (_searchFeed.query.trim().isNotEmpty) {
      await _searchFeed.refresh();
    }
    if (!mounted) return;
    setState(() {});
    showNovelFeedback(
      context,
      '搜索范围：${library.searchScopeLabel}',
      haptic: HapticCue.selection,
    );
  }
}

class _ReviewBubble extends StatelessWidget {
  const _ReviewBubble({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  static double widthFor(int count) =>
      math.max(24, 15 + count.toString().length * 4.8);

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: count == -1 ? '查看本段段评' : '查看本段 ${count < 0 ? 0 : count} 条段评',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppHaptics.play(context, HapticCue.action);
          onTap();
        },
        child: SizedBox(
          width: widthFor(count),
          height: 22,
          child: CustomPaint(
            painter: _ReviewBubblePainter(
              color: foreground.withValues(alpha: .72),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 2, right: 2),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AppText(
                    count == -1 ? '评' : '${count < 0 ? 0 : count}',
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewBubblePainter extends CustomPainter {
  const _ReviewBubblePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(.6, .6, size.width - 1.2, size.height - 4.2),
      Radius.circular((size.height - 4.2) / 2),
    );
    canvas.drawRRect(body, paint);
    canvas.drawPath(
      Path()
        ..moveTo(6.5, body.bottom - .2)
        ..lineTo(5.5, size.height - .7)
        ..lineTo(11, body.bottom - .2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ReviewBubblePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Route focus only changes search lifecycle bookkeeping. Keep that inherited
/// dependency out of the home shell's retained workspace and layout builders.
class _HomeRouteBinding extends StatefulWidget {
  const _HomeRouteBinding({required this.onChanged, required this.child});
  final ValueChanged<ModalRoute<dynamic>?> onChanged;
  final Widget child;

  @override
  State<_HomeRouteBinding> createState() => _HomeRouteBindingState();
}

class _HomeRouteBindingState extends State<_HomeRouteBinding> {
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    widget.onChanged(_route);
  }

  @override
  Widget build(BuildContext context) =>
      RouteIdentity(route: _route, child: widget.child);
}

/// Discovery mirrors Legado's source-first model: pick a book source, then
/// search inside it or open one of its explore categories.
/// Refresh keeps the resolved view mounted. Only a thin progress line appears
/// below the header; existing books never return to loading placeholders.
class FeedRefresh extends StatelessWidget {
  const FeedRefresh({super.key, required this.feed, required this.child});
  final NovelFeedController feed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: RefreshIndicator.noSpinner(
          onStatusChange: (status) {
            if (status == RefreshIndicatorStatus.armed) {
              AppHaptics.play(context, HapticCue.selection);
            }
          },
          onRefresh: () async {
            await feed.refresh();
            if (context.mounted) {
              AppHaptics.play(
                context,
                feed.refreshFailed ? HapticCue.error : HapticCue.success,
              );
            }
          },
          child: child,
        ),
      ),
      if (feed.refreshing)
        Positioned(
          top:
              MediaQuery.paddingOf(context).top +
              FrostedHeader.toolbarHeight +
              6,
          left: 24,
          right: 24,
          height: 8,
          child: IgnorePointer(
            child: const RefreshProgress(
              key: ValueKey('feed-refresh-progress'),
              label: '正在刷新书籍',
            ),
          ),
        ),
    ],
  );
}

/// Keeps pagination placeholders in the same layout as the visible books.
class FeedFooter extends StatelessWidget {
  const FeedFooter({
    super.key,
    required this.feed,
    this.horizontalPadding = 24,
    this.grid = false,
    this.gridDensity = const BookGridDensity.auto(),
  });
  final NovelFeedController feed;
  final double horizontalPadding;
  final bool grid;
  final BookGridDensity gridDensity;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 20, horizontal: horizontalPadding),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (feed.loading && !feed.refreshing) ...[
          if (feed.tagProgressLabel case final progress?) ...[
            AppText(
              progress,
              key: const ValueKey('tag-search-progress'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
          ],
          BookCollectionSkeleton(
            rows: 2,
            label: '正在加载更多书籍',
            grid: grid,
            gridDensity: gridDensity,
          ),
        ] else if (feed.error != null) ...[
          AppText(
            feed.refreshFailed
                ? '刷新失败，已保留原列表'
                : feed.hasLoaded
                ? '加载下一页失败'
                : '搜索尚未完成，已保留找到的书籍',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          GlassTextButton(onPressed: feed.retry, child: const AppText('重试')),
        ] else if (feed.hasMore)
          GlassTextButton(
            onPressed: feed.loadMore,
            child: const AppText('加载更多'),
          )
        else if (feed.items.isNotEmpty)
          AppText(
            feed.searchNotice == null ? '已经到底了' : '已显示当前可用结果',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
      ],
    ),
  );
}

Future<Novel?> matchPendingBook(
  BuildContext context,
  Novel pending,
  LibraryState state,
  NovelRepository repository, {
  bool openAfterMatch = true,
  Object? coverHeroTag,
  bool fromCache = false,
  bool showOpening = false,
  bool promptAddToShelfOnExit = true,
  ReadingEntry entry = ReadingEntry.shelf,
}) async {
  if (!isPendingBook(pending.id)) return pending;
  final selected = await showJellySheet<Novel>(
    context: context,
    reduceMotion: state.reduceMotion,
    heightFactor: .85,
    maxWidth: 720,
    builder: (_) => _PendingBookMatchSheet(
      pending: pending,
      repository: repository,
      library: bookSourceLibraryOf(repository),
    ),
  );
  if (!context.mounted || selected == null) return null;
  final record = state.pendingBook(pending.id);
  if (record == null) {
    showNovelFeedback(context, '待匹配记录已不存在', haptic: HapticCue.error);
    return null;
  }
  try {
    await state.replacePendingShelfBook(record, selected);
  } on Object {
    if (context.mounted) {
      showNovelFeedback(context, '匹配结果保存失败，请重试', haptic: HapticCue.error);
    }
    return null;
  }
  if (!context.mounted) return selected;
  showNovelFeedback(
    context,
    '已匹配《${selected.title}》',
    haptic: HapticCue.selection,
  );
  if (openAfterMatch) {
    openDetail(
      context,
      selected,
      state,
      repository,
      coverHeroTag: coverHeroTag,
      fromCache: fromCache,
      entry: entry,
      showOpening: showOpening,
      promptAddToShelfOnExit: promptAddToShelfOnExit,
    );
  }
  return selected;
}

/// 发现页里只能浏览的平台（七猫、书旗等）点书时，不直连官网正文，
/// 而是在用户已导入的书源里按书名/作者搜索匹配，选中后再打开详情阅读。
Future<void> openInSourceSearch(
  BuildContext context,
  Novel book,
  LibraryState state,
  NovelRepository repository,
) async {
  final query = Novel(
    id: book.id,
    title: book.title,
    author: book.author,
    genre: book.genre,
    summary: book.summary,
    colors: book.colors,
    coverUrl: book.coverUrl,
    wordCount: book.wordCount,
  );
  final selected = await showJellySheet<Novel>(
    context: context,
    reduceMotion: state.reduceMotion,
    heightFactor: .85,
    maxWidth: 720,
    builder: (_) => _PendingBookMatchSheet(
      pending: query,
      repository: repository,
      library: bookSourceLibraryOf(repository),
    ),
  );
  if (!context.mounted || selected == null) return;
  openDetail(
    context,
    selected,
    state,
    repository,
    entry: ReadingEntry.discovery,
    showOpening: true,
    promptAddToShelfOnExit: true,
  );
}

void openDetail(
  BuildContext context,
  Novel novel,
  LibraryState state,
  NovelRepository repository, {
  Object? coverHeroTag,
  bool fromCache = false,
  bool forceDetails = false,
  bool showOpening = false,
  bool promptAddToShelfOnExit = true,
  ReadingEntry entry = ReadingEntry.discovery,
}) {
  if (isPendingBook(novel.id)) {
    unawaited(
      matchPendingBook(
        context,
        novel,
        state,
        repository,
        coverHeroTag: coverHeroTag,
        fromCache: fromCache,
        entry: entry,
        showOpening: showOpening,
        promptAddToShelfOnExit: promptAddToShelfOnExit,
      ),
    );
    return;
  }
  if (state.directReadingOn(entry) && !forceDetails) {
    unawaited(
      pushNovelPage<void>(
        context,
        ReaderLoaderPage(
          novel: novel,
          state: state,
          repository: repository,
          fromCache: fromCache,
          showOpening: showOpening,
          promptAddToShelfOnExit: promptAddToShelfOnExit,
        ),
        reduceMotion: state.reduceMotion,
        slot: ('reader-entry', novel.id),
      ),
    );
    return;
  }
  if (LibraryWorkspace.open(
    context,
    novel.id,
    (_) => fromCache
        ? DetailPage(
            novel: novel,
            state: state,
            repository: repository,
            fromCache: true,
            showOpening: showOpening,
            promptAddToShelfOnExit: promptAddToShelfOnExit,
          )
        : DetailLoaderPage(
            novel: novel,
            state: state,
            repository: repository,
            showOpening: showOpening,
            promptAddToShelfOnExit: promptAddToShelfOnExit,
          ),
  )) {
    return;
  }
  unawaited(
    pushNovelPage<void>(
      context,
      fromCache
          ? DetailPage(
              novel: novel,
              state: state,
              repository: repository,
              fromCache: true,
              coverHeroTag: coverHeroTag,
              showOpening: showOpening,
              promptAddToShelfOnExit: promptAddToShelfOnExit,
            )
          : DetailLoaderPage(
              novel: novel,
              state: state,
              repository: repository,
              coverHeroTag: coverHeroTag,
              showOpening: showOpening,
              promptAddToShelfOnExit: promptAddToShelfOnExit,
            ),
      reduceMotion: state.reduceMotion,
      paperFlight: coverHeroTag != null,
      slot: 'detail',
      explorationKey: ('book', novel.id),
    ),
  );
}

/// 发现页开始阅读前的书籍扉页：先呈现作品信息，轻触后进入正文。
class _BookOpeningPage extends StatelessWidget {
  const _BookOpeningPage({
    required this.novel,
    required this.onOpen,
    this.loading = false,
  });

  final Novel novel;
  final VoidCallback onOpen;
  final bool loading;

  int? get _wordCount => switch (novel.wordCount) {
    final value? when value > 0 => value,
    _ => null,
  };

  String get _genre {
    final value = novel.genre.trim();
    return value.isEmpty ? '未分类' : value;
  }

  String? get _updatedDate {
    final value = novel.lastUpdate?.trim() ?? '';
    if (value.isEmpty) return null;
    final match = RegExp(
      r'(\d{4})[-./年](\d{1,2})[-./月](\d{1,2})',
    ).firstMatch(value);
    if (match == null) return value;
    return '${match.group(1)}.'
        '${match.group(2)!.padLeft(2, '0')}.'
        '${match.group(3)!.padLeft(2, '0')}';
  }

  String get _wordValue {
    final value = _wordCount;
    if (value == null) return '—';
    if (value < 10000) return '$value';
    return (value / 10000)
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String get _wordLabel {
    final value = _wordCount;
    if (value == null) return '字数';
    final unit = value >= 10000 ? '万字' : '字';
    if (loading) return unit;
    return '$unit / ${novel.isComplete ? '完本' : '连载'}';
  }

  String get _sourceName {
    final source = novel.source?.sourceName.trim() ?? '';
    return source.isEmpty ? '在线书库' : source;
  }

  String get _credit {
    final author = novel.author.trim();
    return author.isEmpty ? '— 本作品来自 $_sourceName —' : '— 本作品由 $author 创作 —';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final coverWidth = math.min(158.0, math.max(104.0, width * .36));
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Atmosphere(
        archiveBackdrop: false,
        child: SafeArea(
          child: Semantics(
            button: true,
            label: '开始阅读《${novel.title}》',
            hint: '轻触进入正文',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: scheme.surface,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha:
                                              theme.brightness ==
                                                  Brightness.dark
                                              ? .24
                                              : .10,
                                        ),
                                        blurRadius: 24,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: NovelCover(
                                    novel,
                                    width: coverWidth,
                                    height: coverWidth * 1.4,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                AppText(
                                  novel.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 27,
                                    height: 1.28,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -.4,
                                  ),
                                ),
                                const SizedBox(height: 34),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _BookOpeningFact(
                                        value: _genre,
                                        label: '类型',
                                      ),
                                    ),
                                    Expanded(
                                      child: _BookOpeningFact(
                                        value: _updatedDate ?? '—',
                                        label: '更新',
                                      ),
                                    ),
                                    Expanded(
                                      child: _BookOpeningFact(
                                        value: _wordValue,
                                        label: _wordLabel,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    AppText(
                      '轻触开始阅读',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 22),
                    AppText(
                      _credit,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 5),
                    AppText(
                      '来源：$_sourceName',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookOpeningFact extends StatelessWidget {
  const _BookOpeningFact({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 7),
          AppText(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One destination owns directory loading and reading, so Back never exposes
/// a transient loading route or a details page that the user chose to skip.
class ReaderLoaderPage extends StatefulWidget {
  const ReaderLoaderPage({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
    this.fromCache = false,
    this.showOpening = false,
    this.promptAddToShelfOnExit = true,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  final bool fromCache;
  final bool showOpening;
  final bool promptAddToShelfOnExit;
  @override
  State<ReaderLoaderPage> createState() => _ReaderLoaderPageState();
}

class _ReaderLoaderPageState extends State<ReaderLoaderPage> {
  late bool _opening = widget.showOpening;

  ReaderPreferences get _readerPreferences =>
      widget.state.readerPreferencesFor(widget.novel.id);
  late Future<Novel> _book = _load();
  Future<Novel> _load() async {
    Novel? book;
    if (widget.repository case final OfflineNovelRepository offline) {
      if (widget.fromCache || offline.offline) {
        if (!isLocalBook(widget.novel.id)) await offline.loadCache();
        book = await offline.cachedBook(widget.novel.id);
      }
    }
    book ??= (await widget.repository.detail(
      widget.novel,
    )).withChapters(await widget.repository.chapters(widget.novel.id));
    if (book.tags.isEmpty && widget.novel.tags.isNotEmpty) {
      book = book.withGenre(widget.novel.genre);
    }
    if (book.chapters.isEmpty) throw const FormatException('本书暂无可阅读的章节');
    await widget.state.rememberNovel(book);
    return book;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Novel>(
    future: _book,
    builder: (context, snapshot) {
      if (_opening) {
        return _BookOpeningPage(
          novel: snapshot.data ?? widget.novel,
          loading: snapshot.connectionState != ConnectionState.done,
          onOpen: _openReader,
        );
      }
      if (snapshot.data case final book?) {
        var chapter = widget.state.chapterForNovel(book);
        if (widget.repository case final OfflineNovelRepository offline) {
          if (offline.offline &&
              !isLocalBook(book.id) &&
              offline.cache
                      .book(book.id)
                      ?.chapterBytes
                      .containsKey(book.chapters[chapter].id) !=
                  true) {
            final cached = book.chapters.indexWhere(
              (c) =>
                  offline.cache.book(book.id)?.chapterBytes.containsKey(c.id) ==
                  true,
            );
            if (cached >= 0) chapter = cached;
          }
        }
        return ReaderPage(
          novel: book,
          state: widget.state,
          repository: widget.repository,
          initialChapter: chapter,
          directEntry: true,
          showOpening: false,
          promptAddToShelfOnExit: widget.promptAddToShelfOnExit,
        );
      }
      final preferences = _readerPreferences;
      final chromeVisible = widget.state.readerChromeVisible;
      return ReaderAppearance(
        state: widget.state,
        bookId: widget.novel.id,
        appTheme: Theme.of(context),
        child: Scaffold(
          body: Atmosphere(
            archiveBackdrop: false,
            child: GlassHeaderLayout(
              showHeader: chromeVisible || snapshot.hasError,
              header: ArchiveHeaderBar(
                leading: GlassIconButton(
                  icon: CupertinoIcons.back,
                  label: '返回',
                  onPressed: () => Navigator.pop(context),
                ),
                title: ArchiveRouteTitle(
                  title: widget.novel.title,
                  code: 'READER / BOOK DETAIL',
                ),
              ),
              body: snapshot.hasError
                  ? ContentNotice(
                      icon: CupertinoIcons.exclamationmark_triangle,
                      title: '暂时无法打开本书',
                      message: snapshot.error is FormatException
                          ? (snapshot.error as FormatException).message
                          : '请检查网络或本机缓存后重试',
                      onRetry: () => setState(() => _book = _load()),
                    )
                  : SafeArea(
                      top:
                          !(preferences.hideSystemStatus &&
                              preferences.mode == ReaderMode.scroll),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          preferences.leftMargin,
                          preferences.marginTop +
                              (chromeVisible
                                  ? FrostedHeader.toolbarHeight + 16
                                  : 16),
                          preferences.rightMargin,
                          preferences.marginBottom + 24,
                        ),
                        child: ReaderSkeleton(
                          vertical:
                              _readerPreferences.mode == ReaderMode.vertical,
                          expand: _readerPreferences.mode.paginated,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
    },
  );

  void _openReader() {
    if (!_opening) return;
    AppHaptics.play(context, HapticCue.action);
    setState(() => _opening = false);
  }
}

void openReadingHistory(
  BuildContext context,
  LibraryState state,
  NovelRepository repository,
) => unawaited(
  pushNovelPage<void>(
    context,
    ReadingHistoryPage(
      state: state,
      repository: repository,
      onOpen: (pageContext, id, book) => openDetail(
        pageContext,
        book ??
            Novel(
              id: id,
              title: '书籍 $id',
              author: '',
              genre: '',
              summary: '',
              colors: const [Color(0xFF202020), Color(0xFF333333)],
            ),
        state,
        repository,
      ),
    ),
    reduceMotion: state.reduceMotion,
  ),
);

class NovelRow extends StatelessWidget {
  const NovelRow({
    super.key,
    required this.novel,
    required this.onTap,
    this.trailing,
    this.coverHeroTag,
    this.sourceLabel,
    this.sourceText,
    this.supportingText,
    this.code,
  });
  final Novel novel;
  final VoidCallback onTap;
  final Widget? trailing;
  final Object? coverHeroTag;
  final String? sourceLabel;
  final String? sourceText;
  final String? supportingText;
  final String? code;

  @override
  Widget build(BuildContext context) => JellyTapSurface(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Semantics(
                label: novel.title,
                image: true,
                child: NovelCover(
                  novel,
                  width: 56,
                  height: 76,
                  heroTag: coverHeroTag,
                ),
              ),
              if (sourceLabel != null)
                Positioned(
                  top: 3,
                  right: 3,
                  child: BookSourceBadge(sourceLabel!),
                ),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ArchiveCode(code ?? ArchiveDesign.fileCode(novel.id)),
                const SizedBox(height: 4),
                AppText(
                  novel.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 7),
                AppText(
                  novel.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (sourceText case final text?
                    when text.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  AppText(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (supportingText case final text?
                    when text.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  AppText(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          trailing ?? const ArchiveIcon(CupertinoIcons.chevron_right, size: 15),
        ],
      ),
    ),
  );
}

class ShelfPage extends StatefulWidget {
  const ShelfPage({
    super.key,
    required this.books,
    required this.state,
    required this.repository,
    this.showHeader = true,
    this.compactMainPageControls = false,
    this.onSearch,
    this.navigation,
  });
  final List<Novel> books;
  final LibraryState state;
  final NovelRepository repository;
  final bool showHeader;
  final bool compactMainPageControls;
  final VoidCallback? onSearch;
  final HomeNavigation? navigation;

  Widget buildHeader(BuildContext context, {VoidCallback? search}) =>
      AnimatedBuilder(
        animation: state.navigationChanges,
        builder: (context, _) => Row(
          children: [
            Expanded(
              child: const ArchiveMasthead(
                title: '书架',
                code: 'LIBRARY / BOOKSHELF',
              ),
            ),
            GlassIconButton(
              key: const ValueKey('shelf-search-entry'),
              icon: CupertinoIcons.search,
              label: '搜索图书',
              onPressed: onSearch ?? search,
            ),
            if (state.combinedShelf && repository is OfflineNovelRepository)
              if ((repository as OfflineNovelRepository).local
                  case final local?)
                LocalBookImportButton(
                  books: local,
                  library: state,
                  onImportBookList: () => pushNovelPage<void>(
                    context,
                    BookListImportPage(state: state, repository: repository),
                    reduceMotion: state.reduceMotion,
                  ),
                  onManage: () => pushNovelPage<void>(
                    context,
                    LocalLibraryPage(
                      books: local,
                      state: state,
                      onOpen: (page, book) => openDetail(
                        page,
                        book,
                        state,
                        repository,
                        entry: ReadingEntry.local,
                      ),
                      onOpenWithCover: (page, book, tag) => openDetail(
                        page,
                        book,
                        state,
                        repository,
                        coverHeroTag: tag,
                        entry: ReadingEntry.local,
                      ),
                    ),
                    reduceMotion: state.reduceMotion,
                  ),
                ),
          ],
        ),
      );

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

enum _ShelfSort { recentRead, recentAdded, title }

class _ShelfPageState extends State<ShelfPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _modeTransition;
  final _gridViewport = ValueNotifier<BookGridViewport?>(null);
  late bool _lastCacheOnly;
  final _cacheAvailability = ValueNotifier(0);
  Set<int> _availableIds = const {};
  bool _cacheLoaded = false, _cacheFailed = false;
  OfflineNovelRepository? get _offline =>
      widget.repository is OfflineNovelRepository
      ? widget.repository as OfflineNovelRepository
      : null;
  bool get _cacheOnly =>
      widget.navigation?.readableShelfOnly ??
      (state.localReaderMode ||
          (state.adaptWhenOffline && _offline?.offline == true));
  bool _lastCombined = false;
  final Map<int, Future<Novel?>> _requests = {};
  late Map<int, Novel> _bookIndex;
  ({Set<int> all, List<int> saved, List<int> featured})? _projection;
  Map<String, String>? _shelfCategoryCache;
  String? _projectionQuery;
  String? _previewKey;
  Future<List<Novel>>? _previewRequest;
  final _query = TextEditingController();
  bool _standaloneSearch = false;
  _ShelfSort get _sort =>
      _ShelfSort.values.firstWhere((sort) => sort.name == state.shelfSort);
  LibraryState get state => widget.state;
  late final _changes = Listenable.merge([
    state,
    state.historyChanges,
    state.shelfViewChanges,
    if (widget.navigation != null) widget.navigation!,
    _cacheAvailability,
    state.organization,
    if (_offline?.local != null) _offline!.local!,
  ]);

  @override
  void initState() {
    super.initState();
    _bookIndex = {for (final book in widget.books) book.id: book};
    _changes.addListener(_invalidateProjection);
    _modeTransition = AnimationController(
      vsync: this,
      duration: NovelMotion.enter,
      value: 1,
    );
    _lastCacheOnly = _cacheOnly;
    _lastCombined = state.combinedShelf;
    _offline?.addListener(_offlineCacheChanged);
    widget.navigation?.addListener(_modeChanged);
    state.navigationChanges.addListener(_modeChanged);
    if (state.combinedShelf && _offline != null) {
      unawaited(_offline!.loadCache().catchError((Object _) {}));
    }
  }

  @override
  void didUpdateWidget(ShelfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bookIndex = {for (final book in widget.books) book.id: book};
    _invalidateProjection();
  }

  void _invalidateProjection() {
    _projection = null;
    _shelfCategoryCache = null;
  }

  void _modeChanged() {
    if (_lastCacheOnly == _cacheOnly && _lastCombined == state.combinedShelf) {
      return;
    }
    _lastCacheOnly = _cacheOnly;
    _lastCombined = state.combinedShelf;
    if (state.combinedShelf && _offline?.cache.loaded == false) {
      unawaited(_offline!.loadCache().catchError((Object _) {}));
    }
    if (state.effectiveReduceMotion ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _modeTransition.value = 1;
    } else {
      _modeTransition.forward(from: 0);
    }
  }

  Widget _modeMotion(int index, Widget child) => AnimatedBuilder(
    animation: _modeTransition,
    child: child,
    builder: (context, child) {
      final delay = (index * .07).clamp(0.0, .24);
      final progress = Curves.easeOutCubic.transform(
        ((_modeTransition.value - delay) / (1 - delay)).clamp(0.0, 1.0),
      );
      return Transform.translate(
        offset: Offset(-8, 10) * (1 - progress),
        child: child,
      );
    },
  );

  void _offlineCacheChanged() {
    if (!_cacheOnly && !state.combinedShelf) return;
    final source = _offline!;
    final ids = {
      for (final book in source.cache.books)
        if (book.cachedCount > 0) book.novel.id,
    };
    final loaded = source.cache.loaded;
    final failed = source.cacheError != null;
    if (setEquals(ids, _availableIds) &&
        loaded == _cacheLoaded &&
        failed == _cacheFailed) {
      return;
    }
    _availableIds = ids;
    _cacheLoaded = loaded;
    _cacheFailed = failed;
    _cacheAvailability.value++;
  }

  @override
  void dispose() {
    _changes.removeListener(_invalidateProjection);
    widget.navigation?.removeListener(_modeChanged);
    state.navigationChanges.removeListener(_modeChanged);
    _modeTransition.dispose();
    _offline?.removeListener(_offlineCacheChanged);
    _cacheAvailability.dispose();
    _gridViewport.dispose();
    _query.dispose();
    super.dispose();
  }

  bool _matches(int id, String term) {
    if (_cacheOnly && _offline?.availableOffline(id) != true) return false;
    final book = _known(id);
    if (!bookshelfMatchesCategory(id, state, book: book)) return false;
    if (term.isNotEmpty &&
        !'$id ${book?.title ?? ''} ${book?.author ?? ''}'
            .toLowerCase()
            .contains(term)) {
      return false;
    }
    final read = state.hasRead(id);
    final finished = book != null && state.finishedReading(book);
    return switch (state.shelfFilter) {
      'unread' => !read,
      'reading' => read && !finished,
      'finished' => finished,
      _ => true,
    };
  }

  Novel? _known(int id) {
    final local = _offline?.local?.book(id);
    if (local != null) return local;
    if (_cacheOnly || state.combinedShelf) {
      final cached = _offline?.cache.book(id)?.novel;
      if (cached != null) return cached;
    }
    final cached = state.cachedNovel(id);
    if (cached != null) return cached;
    return _bookIndex[id];
  }

  Future<Novel?> _resolve(int id) async {
    final book = await widget.repository.find(id);
    if (book != null) await state.rememberNovel(book);
    return book;
  }

  Future<List<Novel>> _resolvePreview(List<int> ids) async {
    final resolved = <int, Novel>{};
    var cursor = 0;
    Future<void> next() async {
      while (cursor < ids.length) {
        final id = ids[cursor++];
        try {
          final book =
              _known(id) ?? await _requests.putIfAbsent(id, () => _resolve(id));
          if (book != null) resolved[id] = book;
        } catch (_) {
          // Failed books keep the existing retry/remove actions in the list.
        }
      }
    }

    await Future.wait(List.generate(ids.length.clamp(0, 4), (_) => next()));
    return [
      for (final id in ids)
        if (resolved[id] != null) resolved[id]!,
    ];
  }

  Widget _preview(List<int> ids) {
    Widget carousel(List<Novel> books) => ArchiveFileCarousel(
      key: ValueKey((
        'bookshelf-preview',
        books.map((book) => book.id).join(','),
        state.shelfContent.followCollection
            ? (
                state.shelfSort,
                state.shelfFilter,
                state.organization.shelfSelected,
                _query.text,
              )
            : state.shelfContent.record,
      )),
      books: books,
      library: state,
      entry: ReadingEntry.shelf,
      reduceMotion: state.reduceMotion,
      animateEntrance: true,
      repeatFill: state.shelfPreferences.repeatFill,
      sourceLabel: (book) => isPendingBook(book.id)
          ? '待匹配'
          : state.combinedShelf
          ? bookshelfSource(book.id, _offline)
          : null,
      onOpen: (book, tag) => openDetail(
        context,
        book,
        state,
        widget.repository,
        coverHeroTag: tag,
        entry: ReadingEntry.shelf,
      ),
    );
    final known = [for (final id in ids) ?_known(id)];
    final ready = known.length == ids.length;
    final key = ids.join(',');
    if (!ready && _previewKey != key) {
      _previewKey = key;
      _previewRequest = _resolvePreview(ids);
    }
    return FutureBuilder<List<Novel>>(
      // Keep the same parent for resolved and asynchronously resolved books.
      // Reparenting the carousel on a later rebuild loses its Hero identity.
      key: const ValueKey('shelf-preview-state'),
      future: ready ? null : _previewRequest,
      initialData: ready ? known : null,
      builder: (context, snapshot) {
        if (!ready && snapshot.connectionState != ConnectionState.done) {
          return const ArchiveShelfSkeleton();
        }
        final books = ready ? known : snapshot.data ?? const <Novel>[];
        if (books.isNotEmpty) return carousel(books);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              const AppText('立体书架暂未载入，下方列表仍可整理书籍。'),
              const SizedBox(height: 12),
              GlassTextButton(
                onPressed: () => setState(() {
                  for (final id in ids) {
                    if (_known(id) == null) _requests.remove(id);
                  }
                  _previewKey = null;
                }),
                child: const AppText('重新载入'),
              ),
            ],
          ),
        );
      },
    );
  }

  ({Set<int> all, List<int> saved, List<int> featured}) _projectBooks() {
    final query = _query.text.trim().toLowerCase();
    if (_projection != null && _projectionQuery == query) return _projection!;
    final all = bookshelfIds(
      state,
      _offline,
      readableOnly: _cacheOnly,
      filterCategory: false,
    );
    final saved = all.where((id) => _matches(id, query)).toList();
    final sort = _sort;
    // Resolve sort keys once. In a large shelf, comparators otherwise repeat
    // source lookups O(n log n) times and previously scanned widget.books too.
    final added = <int, int>{};
    int addedAt(int id) => added[id] ??= _addedAt(id);
    final read = sort == _ShelfSort.recentRead
        ? {for (final id in saved) id: state.lastReadAt(id)}
        : const <int, int>{};
    final titles = sort == _ShelfSort.title
        ? {for (final id in saved) id: _known(id)?.title ?? '$id'}
        : const <int, String>{};
    saved.sort((a, b) {
      final result = switch (sort) {
        _ShelfSort.recentRead => read[b]!.compareTo(read[a]!),
        _ShelfSort.recentAdded => addedAt(b).compareTo(addedAt(a)),
        _ShelfSort.title => titles[a]!.compareTo(titles[b]!),
      };
      if (result != 0) return result;
      final order = addedAt(b).compareTo(addedAt(a));
      return order != 0 ? order : a.compareTo(b);
    });
    final content = state.shelfContent;
    final contentCategory = content.followCollection
        ? '_all'
        : _shelfContentCategory;
    final featured = content.followCollection
        ? saved
        : bookshelfIds(
                state,
                _offline,
                readableOnly: _cacheOnly,
                filterSource: false,
                filterCategory: false,
              )
              .where(
                (id) =>
                    bookshelfMatchesSource(
                      id,
                      state,
                      _offline,
                      source: content.source,
                    ) &&
                    bookshelfMatchesCategory(
                      id,
                      state,
                      book: _known(id),
                      category: contentCategory,
                    ) &&
                    shelfContentMatchesReading(
                      id,
                      _known(id),
                      state,
                      content.readingFilter,
                    ),
              )
              .toList();
    if (!content.followCollection) {
      sortShelfContentIds(
        featured,
        content.sort,
        readAt: state.lastReadAt,
        addedAt: _addedAt,
        title: (id) => _known(id)?.title ?? '$id',
      );
    }
    _projectionQuery = query;
    return _projection = (all: all, saved: saved, featured: featured);
  }

  Map<String, String> get _shelfContentCategories =>
      _shelfCategoryCache ??= _buildShelfContentCategories();

  Map<String, String> _buildShelfContentCategories() {
    final organization = state.organization;
    final authors =
        bookshelfIds(
              state,
              _offline,
              readableOnly: _cacheOnly,
              filterSource: false,
              filterCategory: false,
            )
            .map(_known)
            .whereType<Novel>()
            .map((book) => LocalLibraryPreferences.authorName(book.author))
            .toSet()
            .toList()
          ..sort();
    return {
      LocalLibraryPreferences.all: '全部书籍',
      LocalLibraryPreferences.unfiled: '未分类',
      ...organization.groups,
      for (final author in authors)
        LocalLibraryPreferences.authorCategory(author): '作者 · $author',
      if (shelfContentDynamicCategoryLabel(state.shelfContent.category)
          case final label?)
        if (!authors.any(
          (author) =>
              LocalLibraryPreferences.authorCategory(author) ==
              state.shelfContent.category,
        ))
          state.shelfContent.category: '$label（暂无匹配）',
    };
  }

  String get _shelfContentCategory =>
      _shelfContentCategories.containsKey(state.shelfContent.category)
      ? state.shelfContent.category
      : LocalLibraryPreferences.all;

  int _addedAt(int id) => isLocalBook(id)
      ? _offline?.local?.importedAt(id) ?? 0
      : state.addedAt(id);

  @override
  Widget build(BuildContext context) => ActiveListenableBuilder(
    listenable: _changes,
    builder: (context) {
      final (:all, :saved, :featured) = _projectBooks();
      final cacheLoading =
          (_cacheOnly || state.combinedShelf) &&
          _offline?.cache.loaded == false &&
          _offline?.cacheError == null;
      final featuredCount = state.shelfViewMode.hasShelf
          ? state.shelfPreferences.featuredCount(featured.length)
          : 0;
      final showPreview = featuredCount > 0;
      final grid = state.shelfViewMode.isGrid;
      final hasShelf = state.shelfViewMode.hasShelf;
      final showCollection = state.shelfViewMode.showsCollection;
      final collectionItems = showCollection
          ? (saved.isEmpty ? 1 : saved.length)
          : 0;
      final leadingCount = hasShelf ? 2 + (showCollection ? 1 : 0) : 1;
      return GlassHeaderLayout(
        showHeader: widget.showHeader,
        header: widget.onSearch != null || state.combinedShelf
            ? widget.buildHeader(
                context,
                search: () =>
                    setState(() => _standaloneSearch = !_standaloneSearch),
              )
            : Row(
                children: [
                  const Expanded(
                    child: ArchiveMasthead(
                      title: '书架',
                      code: 'LIBRARY / BOOKSHELF',
                    ),
                  ),
                  GlassIconButton(
                    icon: CupertinoIcons.search,
                    label: '搜索书架',
                    onPressed: () =>
                        setState(() => _standaloneSearch = !_standaloneSearch),
                  ),
                ],
              ),
        body: CompactMainPageControls(
          enabled: widget.compactMainPageControls,
          child: cacheLoading
              ? LibrarySkeleton(
                  featured: hasShelf,
                  collection: showCollection,
                  grid: grid,
                  gridDensity: state.shelfGridDensity,
                )
              : _cacheOnly &&
                    _offline?.cache.loaded == false &&
                    _offline?.cacheError != null
              ? ContentNotice(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  title: '离线书库暂未载入',
                  message: '缓存目录读取失败，请重试',
                  onRetry: () =>
                      _offline!.loadCache().catchError((Object _) {}),
                )
              : BookCollectionView.builder(
                  key: const PageStorageKey('shelf'),
                  shareRowGlass: !grid,
                  grid: grid,
                  gridDensity: state.shelfGridDensity,
                  onGridViewport: (v) => _gridViewport.value = v,
                  leadingCount: leadingCount,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    MediaQuery.paddingOf(context).top +
                        FrostedHeader.toolbarHeight +
                        20,
                    24,
                    DockLayout.scrollPaddingOf(context),
                  ),
                  itemCount: leadingCount + collectionItems,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: hasShelf
                            ? BookCollectionRegionToolbar(
                                title: '立体书架',
                                category: state.shelfContent.followCollection
                                    ? state.organization.nameOf(
                                        state.organization.shelfSelected,
                                      )
                                    : _shelfContentCategories[_shelfContentCategory] ??
                                          '全部书籍',
                                count: featured.length,
                                categoryKey: const ValueKey(
                                  'shelf-upper-category',
                                ),
                                filterKey: const ValueKey('shelf-upper-filter'),
                                viewKey: const ValueKey('shelf-upper-view'),
                                onCategory: _upperShelfCategories,
                                onFilter: _upperShelfFilters,
                                onView: () => _viewOptions(
                                  target: showCollection
                                      ? BookCollectionViewTarget.shelf
                                      : BookCollectionViewTarget.all,
                                ),
                              )
                            : _lowerShelfToolbar(saved.length),
                      );
                    }
                    if (hasShelf && index == 1) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: showPreview
                            ? _preview(featured.take(featuredCount).toList())
                            : AppText(
                                featured.isEmpty
                                    ? state.shelf.isEmpty
                                          ? '书架还空着，点右上角搜索图书加入'
                                          : '立体书架暂无符合条件的书籍'
                                    : '当前范围共 ${featured.length} 本，达到 ${state.shelfPreferences.minimumBooks} 本时显示立体书架。',
                                style: const TextStyle(fontSize: 13),
                              ),
                      );
                    }
                    if (showCollection &&
                        hasShelf &&
                        index == leadingCount - 1) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: _lowerShelfToolbar(saved.length),
                      );
                    }
                    if (showCollection &&
                        saved.isEmpty &&
                        index == leadingCount) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 90),
                        child: Column(
                          children: [
                            ArchiveIcon.symbol(
                              ArchiveSymbol.shelf,
                              key: const ValueKey('empty-shelf-icon'),
                              ambient: true,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              size: 34,
                            ),
                            const SizedBox(height: 18),
                            AppText(
                              all.isNotEmpty ||
                                      state.combinedShelf &&
                                          state.shelfSourceFilter != 'all'
                                  ? '没有符合条件的书'
                                  : _cacheOnly
                                  ? '没有可离线阅读的书'
                                  : state.shelf.isEmpty
                                  ? '书架还空着'
                                  : '没有符合条件的书',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            AppText(
                              _cacheOnly
                                  ? state.combinedShelf
                                        ? '已缓存的收藏和本地导入书籍会显示在这里'
                                        : '已缓存正文的收藏会显示在这里，本地导入请到「本地」阅读'
                                  : state.combinedShelf && all.isEmpty
                                  ? '收藏喜欢的书，或点击右上角更多按钮导入书籍'
                                  : state.shelf.isEmpty
                                  ? '在发现页收藏喜欢的书'
                                  : '试试其他关键词或切回全部',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final rowIndex = index - leadingCount;
                    final id = saved[rowIndex];
                    final book = _known(id);
                    return FutureBuilder<Novel?>(
                      key: ValueKey('shelf-resolve-$id'),
                      initialData: book,
                      future: book == null
                          ? _requests.putIfAbsent(id, () => _resolve(id))
                          : _requests[id],
                      builder: (context, snapshot) {
                        final resolved = book ?? snapshot.data;
                        final pending =
                            snapshot.connectionState != ConnectionState.done;
                        return _modeMotion(
                          rowIndex,
                          LoadedContentSequence(
                            generation: resolved?.id,
                            child: resolved != null
                                ? LoadedContentItem(
                                    index: rowIndex,
                                    placeholder: grid
                                        ? const BookGridSkeleton()
                                        : const BookRowSkeleton(),
                                    child: grid
                                        ? _gridRow(context, resolved)
                                        : _row(context, resolved),
                                  )
                                : _unresolvedRow(
                                    id,
                                    pending: pending,
                                    grid: grid,
                                  ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      );
    },
  );

  Widget _lowerShelfToolbar(int count) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      BookCollectionRegionToolbar(
        title: state.shelfViewMode.isGrid ? '图书宫格' : '图书列表',
        category: state.organization.nameOf(state.organization.shelfSelected),
        count: count,
        categoryKey: const ValueKey('shelf-category'),
        filterKey: const ValueKey('shelf-filter'),
        viewKey: const ValueKey('shelf-view'),
        activeFilters:
            (state.shelfFilter == 'all' ? 0 : 1) +
            (state.combinedShelf && state.shelfSourceFilter != 'all' ? 1 : 0),
        onCategory: _lowerShelfCategories,
        onFilter: _libraryOptions,
        onView: () => _viewOptions(target: BookCollectionViewTarget.collection),
      ),
      if (_standaloneSearch) ...[
        const SizedBox(height: 12),
        AppSearchField(
          inputKey: const ValueKey('shelf-search'),
          controller: _query,
          hint: '在下方书目中查找书名、作者或 ID',
          onChanged: (_) => setState(() {}),
        ),
      ],
    ],
  );

  Future<void> _lowerShelfCategories() {
    final ids = bookshelfIds(
      state,
      _offline,
      filterSource: false,
      filterCategory: false,
    );
    final known = [for (final id in ids) ?_known(id)];
    return showBookCategories(
      context,
      state.organization,
      shelf: true,
      books: known,
      unknownAuthorCount: ids.length - known.length,
      reduceMotion: state.reduceMotion,
    );
  }

  Future<void> _upperShelfCategories() async {
    final chosen = await chooseBookCollectionRegionCategory(
      context,
      options: _shelfContentCategories,
      selected: state.shelfContent.followCollection
          ? state.organization.shelfSelected
          : _shelfContentCategory,
      reduceMotion: state.reduceMotion,
    );
    if (chosen != null && mounted) {
      await _saveShelfContent(
        state.shelfContent.copyWith(followCollection: false, category: chosen),
      );
    }
  }

  Future<void> _upperShelfFilters() => showJellySheet<void>(
    context: context,
    reduceMotion: state.reduceMotion,
    heightFactor: .78,
    builder: (_) => AnimatedBuilder(
      animation: Listenable.merge([state.shelfViewChanges, state.organization]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: BookShelfContentOptions(
          value: state.shelfContent,
          onChanged: _saveShelfContent,
          categoryOptions: _shelfContentCategories,
          sourceOptions: state.combinedShelf
              ? const {
                  'all': '全部来源',
                  'local': '本地导入',
                  'cached': '已缓存',
                  'online': '在线收藏',
                }
              : const {},
          hint: '只调整立体书架，下方列表保留自己的分类、筛选和排序。',
          reduceMotion: state.reduceMotion,
        ),
      ),
    ),
  );

  Widget _unresolvedRow(int id, {required bool pending, required bool grid}) {
    if (pending) {
      return grid
          ? BookGridSkeleton(label: '正在载入书籍 $id')
          : BookRowSkeleton(label: '正在载入书籍 $id');
    }
    void retry() {
      setState(() {
        _requests[id] = _resolve(id);
      });
    }

    final action = GlassMenuAnchor(
      child: Builder(
        builder: (buttonContext) => grid
            ? GlassIconButton.custom(
                label: '书籍 $id 书架操作',
                onPressed: () => _bookMenu(buttonContext, id),
                liveGlass: false,
                transparent: true,
                child: const ArchiveIcon(CupertinoIcons.ellipsis, size: 18),
              )
            : GlassIconButton(
                icon: CupertinoIcons.ellipsis,
                label: '书籍 $id 书架操作',
                onPressed: () => _bookMenu(buttonContext, id),
              ),
      ),
    );
    if (grid) {
      return BookGridFailure(id: id, onRetry: retry, trailing: action);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          const ArchiveIcon(CupertinoIcons.book, size: 26),
          const SizedBox(width: 15),
          Expanded(child: AppText('书籍 $id 暂未载入')),
          GlassTextButton(onPressed: retry, child: const AppText('重试')),
          action,
        ],
      ),
    );
  }

  String _progressLabel(Novel book) => isPendingBook(book.id)
      ? '待匹配'
      : !state.hasRead(book.id)
      ? '未读'
      : state.finishedReading(book)
      ? '已读完'
      : (book.chapters.isNotEmpty || book.chapterCount > 0)
      ? '${state.chapterForNovel(book) + 1}/${book.chapters.isNotEmpty ? book.chapters.length : book.chapterCount}'
      : '第 ${state.chapterFor(book.id) + 1} 章';

  Widget _gridRow(BuildContext context, Novel book) => BookGridTile(
    key: ValueKey('shelf-grid-book-${book.id}'),
    book: book,
    sourceLabel: isPendingBook(book.id)
        ? '待匹配'
        : state.combinedShelf
        ? bookshelfSource(book.id, _offline)
        : null,
    coverHeroTag: CoverHeroTag(this, book.id),
    progress: _progressLabel(book),
    onTap: () => openDetail(
      context,
      book,
      state,
      widget.repository,
      coverHeroTag: CoverHeroTag(this, book.id),
      fromCache: _cacheOnly,
      entry: ReadingEntry.shelf,
    ),
    trailing: GlassMenuAnchor(
      child: Builder(
        builder: (buttonContext) => GlassIconButton.custom(
          label: '${book.title}书架操作',
          onPressed: () => _bookMenu(buttonContext, book.id, book: book),
          liveGlass: false,
          transparent: true,
          child: const ArchiveIcon(CupertinoIcons.ellipsis, size: 18),
        ),
      ),
    ),
  );

  Widget _row(BuildContext context, Novel book) => NovelRow(
    key: ValueKey('shelf-book-${book.id}'),
    novel: book,
    sourceLabel: isPendingBook(book.id)
        ? '待匹配'
        : state.combinedShelf
        ? bookshelfSource(book.id, _offline)
        : null,
    supportingText: isPendingBook(book.id) ? '点开自动搜索书源' : null,
    code: isPendingBook(book.id) ? 'PENDING' : null,
    coverHeroTag: CoverHeroTag(this, book.id),
    onTap: () => openDetail(
      context,
      book,
      state,
      widget.repository,
      coverHeroTag: CoverHeroTag(this, book.id),
      fromCache: _cacheOnly,
      entry: ReadingEntry.shelf,
    ),
    trailing: SizedBox(
      width: 74,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassMenuAnchor(
            child: Builder(
              builder: (buttonContext) => GlassIconButton(
                icon: CupertinoIcons.ellipsis,
                label: '${book.title}书架操作',
                onPressed: () => _bookMenu(buttonContext, book.id, book: book),
              ),
            ),
          ),
          AppText(
            _progressLabel(book),
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _libraryOptions() => showJellySheet<void>(
    context: context,
    reduceMotion: state.reduceMotion,
    heightFactor: .78,
    builder: (_) => AnimatedBuilder(
      animation: Listenable.merge([state.shelfViewChanges, _gridViewport]),
      builder: (context, _) {
        void save({
          String? layout,
          String? filter,
          String? source,
          String? sort,
          BookGridDensity? gridDensity,
        }) {
          unawaited(
            state
                .setShelfView(
                  layout: layout,
                  filter: filter,
                  source: source,
                  sort: sort,
                  gridDensity: gridDensity,
                )
                .catchError((Object _) {
                  if (mounted) showNovelFeedback(this.context, '书架偏好保存失败，请重试');
                }),
          );
        }

        return LibraryViewOptions(
          showView: false,
          shelf: state.shelfLayout == 'shelf',
          layout: state.shelfLayout,
          onLayout: (v) => save(layout: v),
          gridDensity: state.shelfGridDensity,
          gridViewport: _gridViewport.value,
          onGridDensity: (v) => save(gridDensity: v),
          reading: state.shelfFilter,
          sort: state.shelfSort,
          source: state.combinedShelf ? state.shelfSourceFilter : null,
          onView: (v) => save(layout: v ? 'shelf' : 'list'),
          onReading: (v) => save(filter: v),
          onSource: (v) => save(source: v),
          onSort: (v) => save(sort: v),
          footer:
              state.combinedShelf && _offline?.local?.books.isNotEmpty == true
              ? GlassTextButton(
                  key: const ValueKey('shelf-manage-local'),
                  onPressed: () => openLocalBookBatch(
                    context,
                    books: _offline!.local!,
                    library: state,
                  ),
                  child: const AppText('批量整理本地书'),
                )
              : null,
        );
      },
    ),
  );

  Future<void> _viewOptions({
    BookCollectionViewTarget target = BookCollectionViewTarget.all,
  }) async {
    var all = false;
    await showJellySheet<void>(
      context: context,
      reduceMotion: state.reduceMotion,
      heightFactor: .82,
      builder: (sheet) => AnimatedBuilder(
        animation: Listenable.merge([state.shelfViewChanges, _gridViewport]),
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: BookCollectionViewOptions(
            target: target,
            allowShelfOnly: true,
            onShowLayoutOptions: () {
              all = true;
              Navigator.pop(sheet);
            },
            mode: state.shelfViewMode,
            gridDensity: state.shelfGridDensity,
            gridViewport: _gridViewport.value,
            shelfPreferences: state.shelfPreferences,
            shelfContent: state.shelfContent,
            shelfCategoryOptions: _shelfContentCategories,
            shelfSourceOptions: state.combinedShelf
                ? const {
                    'all': '全部来源',
                    'local': '本地导入',
                    'cached': '已缓存',
                    'online': '在线收藏',
                  }
                : const {},
            shelfContentHint: state.shelfViewMode.showsCollection
                ? '仅调整上方立体书架；下方继续使用页面上的分类、筛选和排序。'
                : '只调整立体书架本身；切换到列表或宫格后可浏览全部书籍。',
            reduceMotion: state.reduceMotion,
            onShelfPreferencesChanged: (preferences) =>
                _saveShelfView(shelfPreferences: preferences),
            onModeChanged: (mode) => _saveShelfView(mode: mode),
            onGridDensityChanged: (density) => _saveShelfView(density: density),
          ),
        ),
      ),
    );
    if (all && mounted) await _viewOptions();
  }

  Future<void> _saveShelfContent(BookShelfContentPreferences value) async {
    try {
      await state.setShelfContent(value);
    } catch (_) {
      if (mounted) showNovelFeedback(context, '立体书架偏好保存失败，请重试');
    }
  }

  Future<void> _saveShelfView({
    BookCollectionMode? mode,
    BookGridDensity? density,
    BookShelfPreferences? shelfPreferences,
  }) async {
    try {
      await state.setShelfView(
        mode: mode,
        gridDensity: density,
        shelfPreferences: shelfPreferences,
      );
    } catch (_) {
      if (mounted) showNovelFeedback(context, '视图偏好保存失败，请重试');
    }
  }

  Future<void> _bookMenu(BuildContext context, int id, {Novel? book}) async {
    if (isLocalBook(id) && book != null && _offline?.local != null) {
      await pushNovelPage<LocalBookEditResult>(
        context,
        LocalBookEditor(book: book, books: _offline!.local!, library: state),
        reduceMotion: state.reduceMotion,
      );
      return;
    }
    final action = await showGlassMenu<String>(
      context: context,
      reduceMotion: state.reduceMotion,
      builder: (menuContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPendingBook(id))
            GlassMenuItem(
              label: '搜索书源',
              onPressed: () => Navigator.pop(menuContext, 'match'),
            ),
          GlassMenuItem(
            label: '移至分类',
            onPressed: () => Navigator.pop(menuContext, 'category'),
          ),
          GlassMenuItem(
            order: 1,
            label: !state.contains(id) ? '加入收藏书架' : '移出书架',
            onPressed: () => Navigator.pop(
              menuContext,
              state.contains(id) ? 'remove' : 'add',
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'match') {
      final target = book ?? state.cachedNovel(id);
      if (target != null) {
        await matchPendingBook(
          this.context,
          target,
          state,
          widget.repository,
          openAfterMatch: false,
        );
      }
      return;
    }
    if (action == 'add') {
      try {
        await state.setShelfMembership(id, true, novel: book);
      } catch (_) {
        if (context.mounted) showNovelFeedback(context, '书架操作保存失败，请重试');
      }
      return;
    }
    if (action == 'category') {
      final group = await chooseBookCategory(
        this.context,
        state.organization,
        bookId: id,
        reduceMotion: state.reduceMotion,
      );
      if (group != null) {
        try {
          await state.organization.assign(id, group);
        } catch (_) {
          if (mounted) showNovelFeedback(this.context, '分类保存失败，请重试');
        }
      }
      return;
    }
    if (action != 'remove' || !state.contains(id)) return;
    final addedAt = state.addedAt(id);
    try {
      await state.setShelfMembership(id, false);
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '书架操作保存失败，请重试');
      return;
    }
    final revision = state.shelfRevision(id);
    if (!mounted) return;
    showNovelFeedback(
      this.context,
      _offline?.availableOffline(id) == true ? '已移出书架，缓存和阅读进度保留' : '已移出书架',
      actionLabel: '撤销',
      action: () async {
        if (!state.contains(id) && state.shelfRevision(id) == revision) {
          await state.setShelfMembership(
            id,
            true,
            novel: book,
            restoredAddedAt: addedAt,
          );
        }
      },
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.state,
    this.repository,
    this.showHeader = true,
  });
  final LibraryState state;
  final NovelRepository? repository;
  final bool showHeader;

  Widget buildHeader(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: const ArchiveMasthead(title: '设置', code: 'SYSTEM / PREFERENCES'),
  );

  @override
  Widget build(BuildContext context) => ActiveListenableBuilder(
    listenable: state.settingsChanges,
    builder: (context) => GlassHeaderLayout(
      showHeader: showHeader,
      header: buildHeader(context),
      body: ListView(
        key: const PageStorageKey('settings'),
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
          24,
          MediaQuery.paddingOf(context).bottom + 120,
        ),
        children: [
          _sectionEntry(
            context,
            id: 'usage',
            title: '使用方式',
            subtitle: '启动与续读、书架及离线适配',
            code: 'SYSTEM / USAGE',
            icon: CupertinoIcons.square_grid_2x2,
            options: _usageOptions,
          ),
          const SizedBox(height: 14),
          _sectionEntry(
            context,
            id: 'reading',
            title: '阅读与外观',
            subtitle: '外观模式、主题配色、字体与听书',
            code: 'SYSTEM / READING',
            icon: CupertinoIcons.textformat,
            options: _readingOptions,
          ),
          const SizedBox(height: 14),
          FeatureEntry(
            key: const ValueKey('settings-replace-rules'),
            title: '替换净化',
            subtitle: '按书名或书源批量替换章节标题与正文',
            icon: CupertinoIcons.wand_stars,
            onTap: () => pushNovelPage<void>(
              context,
              ReplaceRulesPage(
                store: ReplaceRuleStore.shared,
                reduceMotion: state.reduceMotion,
              ),
              reduceMotion: state.reduceMotion,
              slot: ('settings', 'replace-rules'),
            ),
          ),
          const SizedBox(height: 14),
          FeatureEntry(
            key: const ValueKey('settings-dict-rules'),
            title: '字典规则',
            subtitle: '管理在线查词规则，并与离线词典合并显示',
            icon: CupertinoIcons.globe,
            onTap: () => pushNovelPage<void>(
              context,
              DictRulesPage(
                store: DictRuleStore.shared,
                reduceMotion: state.reduceMotion,
              ),
              reduceMotion: state.reduceMotion,
              slot: ('settings', 'dict-rules'),
            ),
          ),
          const SizedBox(height: 14),
          FeatureEntry(
            key: const ValueKey('settings-txt-toc-rules'),
            title: 'TXT 目录规则',
            subtitle: '管理分章、分卷正则并选择用于本地 TXT 导入',
            icon: CupertinoIcons.list_bullet,
            onTap: () => pushNovelPage<void>(
              context,
              TxtTocRulesPage(
                store: TxtTocRuleStore.shared,
                reduceMotion: state.reduceMotion,
              ),
              reduceMotion: state.reduceMotion,
              slot: ('settings', 'txt-toc-rules'),
            ),
          ),
          const SizedBox(height: 14),
          _sectionEntry(
            context,
            id: 'effects',
            title: '性能与动效',
            subtitle: '振动反馈、帧率偏好与动态效果',
            code: 'SYSTEM / EFFECTS',
            icon: CupertinoIcons.speedometer,
            options: _effectsOptions,
          ),
          const SizedBox(height: 14),
          if (LanSyncScope.maybeOf(context) case final sync?) ...[
            FeatureEntry(
              key: const ValueKey('settings-lan-sync'),
              title: '局域网续读',
              subtitle: '连接自己的设备，接着上次的位置阅读',
              icon: CupertinoIcons.wifi,
              onTap: () => pushNovelPage<void>(
                context,
                LanReadingPage(sync: sync, reduceMotion: state.reduceMotion),
                reduceMotion: state.reduceMotion,
                slot: ('settings', 'lan-reading'),
              ),
            ),
            const SizedBox(height: 14),
          ],
          FeatureEntry(
            key: const ValueKey('settings-reading-widgets'),
            title: '小组件',
            subtitle: '配置桌面上的阅读主题与隐私',
            icon: CupertinoIcons.square_grid_2x2,
            onTap: () => pushNovelPage<void>(
              context,
              ReadingWidgetSettingsPage(state: state),
              reduceMotion: state.reduceMotion,
              slot: ('settings', 'reading-widgets'),
            ),
          ),
          const SizedBox(height: 14),
          _sectionEntry(
            context,
            id: 'data',
            title: '数据与存储',
            subtitle: '阅读历史、缓存管理与备份恢复',
            code: 'SYSTEM / STORAGE',
            icon: CupertinoIcons.folder,
            options: _dataOptions,
          ),
        ],
      ),
    ),
  );

  Widget _sectionEntry(
    BuildContext context, {
    required String id,
    required String title,
    required String subtitle,
    required String code,
    required IconData icon,
    required List<Widget> Function(BuildContext) options,
  }) => FeatureEntry(
    key: ValueKey('settings-$id-entry'),
    title: title,
    subtitle: subtitle,
    icon: icon,
    onTap: () => pushNovelPage<void>(
      context,
      ArchiveFeaturePage(
        key: ValueKey('settings-$id-page'),
        title: title,
        code: code,
        child: ActiveListenableBuilder(
          listenable: state.settingsChanges,
          builder: (context) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                key: PageStorageKey('settings-$id'),
                padding: featurePadding(context).add(
                  EdgeInsets.only(
                    left: MediaQuery.paddingOf(context).left,
                    right: MediaQuery.paddingOf(context).right,
                  ),
                ),
                children: options(context),
              ),
            ),
          ),
        ),
      ),
      reduceMotion: state.reduceMotion,
      slot: ('settings', id),
    ),
  );

  List<Widget> _usageOptions(BuildContext context) => [
    ContentPanel(
      child: Column(
        children: [
          _toggleSetting(
            context,
            keyName: 'settings-force-portrait',
            icon: CupertinoIcons.lock_rotation,
            title: '强制竖屏',
            description: '仅本 App 固定竖屏，关闭后跟随系统',
            value: state.forcePortrait,
            onChanged: state.setForcePortrait,
          ),
          const Divider(height: 22),
          _toggleSetting(
            context,
            keyName: 'settings-direct-reading',
            icon: CupertinoIcons.book_fill,
            title: '点书直接阅读',
            description: '选择适用页面（可多选），从上次位置继续',
            value: state.directReading,
            onChanged: state.setDirectReading,
          ),
          if (state.directReading)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 36),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final page in ReadingEntry.values)
                    GlassTextButton(
                      key: ValueKey('settings-direct-reading-${page.name}'),
                      selected: state.directReadingOn(page),
                      onPressed: () => _savePreference(
                        context,
                        () => state.setDirectReadingPages({
                          ...state.directReadingPages.where((p) => p != page),
                          if (!state.directReadingOn(page)) page,
                        }),
                      ),
                      child: AppText(page.label),
                    ),
                ],
              ),
            ),
          const Divider(height: 22),
          GlassSettingMenu<AppStartPage>(
            key: const ValueKey('settings-start-page'),
            icon: CupertinoIcons.house,
            label: '启动页面',
            value: state.startPage,
            options: {for (final page in AppStartPage.values) page: page.label},
            reduceMotion: state.reduceMotion,
            onChanged: (page) =>
                _savePreference(context, () => state.setStartPage(page)),
          ),
          const Divider(height: 22),
          _toggleSetting(
            context,
            keyName: 'settings-calligraphy-splash',
            icon: CupertinoIcons.paintbrush,
            title: '启动书法欢迎屏',
            description: '冷启动进入主界面时显示纸纹书法开屏',
            value: state.calligraphySplashEnabled,
            onChanged: state.setCalligraphySplashEnabled,
          ),
          const Divider(height: 22),
          _toggleSetting(
            context,
            keyName: 'settings-calligraphy-splash-once',
            icon: CupertinoIcons.sun_max,
            title: '每日仅显示一次',
            description: '当天已显示过后，再次冷启动不再显示，次日恢复',
            value: state.calligraphySplashOncePerDay,
            enabled: state.calligraphySplashEnabled,
            onChanged: state.setCalligraphySplashOncePerDay,
          ),
          const Divider(height: 22),
          _calligraphySplashTextRow(context),
          const Divider(height: 22),
          _toggleSetting(
            context,
            keyName: 'settings-open-recent-on-launch',
            icon: CupertinoIcons.clock,
            title: '启动时继续阅读',
            description: '打开应用后进入最近读过的书',
            value: state.openRecentOnLaunch,
            onChanged: state.setOpenRecentOnLaunch,
          ),
          const Divider(height: 22),
          _toggleSetting(
            context,
            keyName: 'settings-combined-shelf',
            icon: CupertinoIcons.square_stack,
            title: '合并书架',
            description: '收藏与本地书统一显示在书架，试读缓存不加入',
            value: state.combinedShelf,
            onChanged: (value) => state.setNavigationMode(combinedShelf: value),
          ),
          const Divider(height: 22),
          _toggleSetting(
            context,
            keyName: 'settings-adapt-offline',
            icon: CupertinoIcons.wifi_slash,
            title: '离线适配',
            description: state.combinedShelf
                ? '断网后隐藏发现，书架保留已缓存的收藏和本地书籍'
                : '断网后隐藏发现，书架只显示已缓存的收藏',
            value: state.adaptWhenOffline,
            onChanged: (value) =>
                state.setNavigationMode(adaptWhenOffline: value),
          ),
          const Divider(height: 22),
          _toggleSetting(
            context,
            keyName: 'settings-local-reader-mode',
            icon: CupertinoIcons.book,
            title: '阅读器模式',
            description: state.combinedShelf ? '只显示离线可读的合并书架和我的' : '只显示本地和我的',
            value: state.localReaderMode,
            onChanged: (value) =>
                state.setNavigationMode(localReaderMode: value),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _readingOptions(BuildContext context) => [
    FeatureEntry(
      key: const ValueKey('settings-reading-moments'),
      title: '阅读纪念',
      subtitle: '纪念风格、阅读里程碑与书页终点',
      icon: CupertinoIcons.sparkles,
      onTap: () => pushNovelPage<void>(
        context,
        ReadingMomentsSettingsPage(state: state),
        reduceMotion: state.reduceMotion,
        slot: ('settings', 'reading-moments'),
      ),
    ),
    const SizedBox(height: 14),
    ContentPanel(
      child: Column(
        children: [
          _appearanceSetting(context),
          const Divider(height: 22),
          JellyTapSurface(
            key: const ValueKey('settings-palette'),
            onTap: () => pushNovelPage<void>(
              context,
              PaletteSettingsPage(state: state),
              reduceMotion: state.effectiveReduceMotion,
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  ArchiveIcon(CupertinoIcons.paintbrush, size: 21),
                  SizedBox(width: 12),
                  Expanded(
                    child: AppText(
                      '主题配色',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ArchiveIcon(CupertinoIcons.chevron_forward, size: 14),
                ],
              ),
            ),
          ),
          const Divider(height: 22),
          LanguageSettingMenu(
            key: const ValueKey('settings-language'),
            state: state,
          ),
          const Divider(height: 22),
          JellyTapSurface(
            key: const ValueKey('settings-fonts'),
            onTap: () => pushNovelPage<void>(
              context,
              FontSettingsPage(state: state),
              reduceMotion: state.reduceMotion,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const ArchiveIcon(CupertinoIcons.textformat, size: 21),
                  const SizedBox(width: 12),
                  Expanded(
                    child: const AppText(
                      '字体',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const ArchiveIcon(CupertinoIcons.chevron_forward, size: 14),
                ],
              ),
            ),
          ),
          const Divider(height: 22),
          JellyTapSurface(
            key: const ValueKey('settings-dictionaries'),
            onTap: () => showDictionaryManagementSheet(
              context: context,
              reduceMotion: state.reduceMotion,
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  ArchiveIcon(CupertinoIcons.book, size: 21),
                  SizedBox(width: 12),
                  Expanded(
                    child: AppText(
                      '离线词典',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ArchiveIcon(CupertinoIcons.chevron_forward, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    if (LocalPlatform.listening) ...[
      if (ListeningScope.maybeOf(context) case final listening?)
        if (listening.customSpeech case final settings?) ...[
          const SizedBox(height: 14),
          FeatureEntry(
            title: '自定义语音接口',
            subtitle: 'Microsoft SSML 兼容服务',
            icon: CupertinoIcons.waveform,
            onTap: () => pushNovelPage<void>(
              context,
              CustomSpeechPage(settings: settings, controller: listening),
              reduceMotion: state.reduceMotion,
            ),
          ),
        ],
    ],
  ];

  List<Widget> _effectsOptions(BuildContext context) => [
    sectionHeader(context, '显示流畅度', ''),
    const SizedBox(height: 14),
    const FrameRateOptions(),
    const SizedBox(height: 14),
    ContentPanel(
      key: const ValueKey('settings-performance'),
      onTap: () => pushNovelPage<void>(
        context,
        LowPerformancePage(state: state),
        reduceMotion: state.reduceMotion,
      ),
      child: const Row(
        children: [
          ArchiveIcon(CupertinoIcons.speedometer, size: 21),
          SizedBox(width: 12),
          Expanded(
            child: AppText(
              '低性能设备模式',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ArchiveIcon(CupertinoIcons.chevron_right, size: 14),
        ],
      ),
    ),
    const SizedBox(height: 24),
    sectionHeader(context, '视觉效果', '玻璃外观 · 实时预览'),
    const SizedBox(height: 14),
    ContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _glassSettingLabel(context, '模糊度', '${state.glassBlur.round()}'),
          AppControls.slider(
            context,
            key: const ValueKey('glass-blur-slider'),
            value: state.glassBlur,
            min: 0,
            max: 24,
            divisions: 24,
            onChanged: (value) => state.setGlassBlur(value, persist: false),
            onChangeEnd: state.setGlassBlur,
          ),
          const Divider(height: 22),
          _glassSettingLabel(
            context,
            '不透明度',
            '${(state.glassOpacity * 100).round()}%',
          ),
          AppControls.slider(
            context,
            key: const ValueKey('glass-opacity-slider'),
            value: state.glassOpacity,
            min: 0,
            max: 1,
            divisions: 100,
            onChanged: (value) => state.setGlassOpacity(value, persist: false),
            onChangeEnd: state.setGlassOpacity,
          ),
          GlassTextButton(
            onPressed: () async {
              await state.setGlassBlur(8);
              await state.setGlassOpacity(.87);
            },
            child: const AppText('恢复默认'),
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    sectionHeader(context, '交互动效', ''),
    const SizedBox(height: 14),
    ContentPanel(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                ArchiveIcon(
                  CupertinoIcons.circle_grid_3x3,
                  color: Theme.of(context).colorScheme.primary,
                  size: 21,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: AppText(
                    '减少动态效果',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                AppControls.toggle(
                  context,
                  value: state.reduceMotion,
                  onChanged: (value) => _savePreference(
                    context,
                    () => state.setReduceMotion(value),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    sectionHeader(context, '触感反馈', ''),
    const SizedBox(height: 14),
    ContentPanel(
      key: const ValueKey('settings-haptics'),
      onTap: () => pushNovelPage<void>(
        context,
        HapticSettingsPage(state: state),
        reduceMotion: state.reduceMotion,
      ),
      child: Row(
        children: [
          const ArchiveIcon(CupertinoIcons.waveform, size: 21),
          const SizedBox(width: 12),
          const Expanded(
            child: AppText(
              '振动反馈',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          AppText(state.haptics.enabled ? '已开启' : '已关闭'),
          const SizedBox(width: 10),
          const ArchiveIcon(CupertinoIcons.chevron_right, size: 14),
        ],
      ),
    ),
  ];

  List<Widget> _dataOptions(BuildContext context) => [
    if (repository case final NovelRepository source) ...[
      sectionHeader(context, '阅读记录', ''),
      const SizedBox(height: 14),
      ContentPanel(
        onTap: () => openReadingHistory(context, state, source),
        child: const Row(
          children: [
            ArchiveIcon(CupertinoIcons.clock, size: 21),
            SizedBox(width: 12),
            Expanded(
              child: AppText(
                '阅读历史',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ArchiveIcon(CupertinoIcons.chevron_right, size: 14),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ],
    if (repository case final OfflineNovelRepository offline) ...[
      sectionHeader(context, '离线阅读', ''),
      const SizedBox(height: 14),
      ContentPanel(
        onTap: () => pushNovelPage<void>(
          context,
          OfflineCachePage(
            repository: offline,
            reduceMotion: state.reduceMotion,
            onOpen: (pageContext, novel) =>
                openDetail(pageContext, novel, state, offline, fromCache: true),
          ),
          reduceMotion: state.reduceMotion,
        ),
        child: const Row(
          children: [
            ArchiveIcon(CupertinoIcons.cloud_download, size: 21),
            SizedBox(width: 12),
            Expanded(
              child: AppText(
                '缓存管理',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ArchiveIcon(CupertinoIcons.chevron_right, size: 14),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ],
    sectionHeader(context, '备份与清理', ''),
    const SizedBox(height: 14),
    ContentPanel(
      key: const ValueKey('settings-backup'),
      onTap: () => pushNovelPage<void>(
        context,
        LibraryBackupPage(state: state),
        reduceMotion: state.reduceMotion,
      ),
      child: const Row(
        children: [
          ArchiveIcon(CupertinoIcons.folder, size: 21),
          SizedBox(width: 12),
          Expanded(
            child: AppText(
              '备份与恢复',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ArchiveIcon(CupertinoIcons.chevron_right, size: 14),
        ],
      ),
    ),
    if (LocalPlatform.android) ...[
      const SizedBox(height: 14),
      FeatureEntry(
        key: const ValueKey('settings-legacy-import'),
        title: '导入旧版文库记录',
        icon: CupertinoIcons.folder_badge_plus,
        subtitle: '预览后合并，保留较新的阅读进度',
        onTap: () => pushNovelPage<void>(
          context,
          LegacyImportPage(state: state),
          reduceMotion: state.reduceMotion,
        ),
      ),
      const SizedBox(height: 14),
      FeatureEntry(
        title: '清理插图缓存',
        icon: CupertinoIcons.photo,
        subtitle: '不影响书架、正文缓存和阅读记录',
        onTap: () async {
          if (!await confirmNovelAction(
            context,
            title: '删除插图缓存？',
            message: '已下载的插图会从本机缓存移除，下次查看时重新下载，正文和阅读记录仍保留。',
            confirmLabel: '删除插图缓存',
            reduceMotion: state.reduceMotion,
          )) {
            return;
          }
          try {
            await LegacyTransport.clearIllustrations();
            ReaderIllustrationCache.shared.clearMemory();
            if (context.mounted) showNovelFeedback(context, '插图缓存已清理');
          } catch (_) {
            if (context.mounted) showNovelFeedback(context, '缓存清理失败，请重试');
          }
        },
      ),
    ],
  ];

  Widget _appearanceSetting(BuildContext context) =>
      GlassSettingMenu<ThemeMode>(
        key: const ValueKey('settings-appearance'),
        icon: CupertinoIcons.moon_stars,
        label: '外观模式',
        value: state.theme,
        options: const {
          ThemeMode.system: '跟随系统',
          ThemeMode.light: '浅色',
          ThemeMode.dark: '深色',
        },
        reduceMotion: state.reduceMotion,
        onChanged: (value) =>
            _savePreference(context, () => state.setTheme(value)),
      );

  Widget _glassSettingLabel(BuildContext context, String title, String value) =>
      Row(
        children: [
          Expanded(
            child: AppText(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          AppText(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );

  Widget _toggleSetting(
    BuildContext context, {
    required String keyName,
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    bool enabled = true,
    required Future<void> Function(bool) onChanged,
  }) => Opacity(
    opacity: enabled ? 1 : .5,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ArchiveIcon(icon, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: AppText(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            AppControls.toggle(
              context,
              key: ValueKey(keyName),
              value: value,
              onChanged: enabled
                  ? (value) => _savePreference(context, () => onChanged(value))
                  : null,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 33, top: 4),
          child: AppText(
            description,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _savePreference(
    BuildContext context,
    Future<void> Function() save,
  ) async {
    try {
      await save();
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '设置保存失败，请重试');
    }
  }

  Widget _calligraphySplashTextRow(BuildContext context) {
    final text = state.calligraphySplashText;
    final preview = text.isEmpty
        ? '默认：欲买桂花同载酒 / 终不似少年游'
        : text.replaceAll('\n', ' / ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const ArchiveIcon(CupertinoIcons.text_quote, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: AppText(
                '开屏文字',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            GlassTextButton(
              key: const ValueKey('settings-calligraphy-splash-text'),
              compact: true,
              onPressed: state.calligraphySplashEnabled
                  ? () => _editCalligraphySplashText(context)
                  : null,
              child: const AppText('编辑'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 33, top: 4),
          child: AppText(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editCalligraphySplashText(BuildContext context) async {
    final controller = TextEditingController(text: state.calligraphySplashText);
    try {
      final value = await showJellySheet<String>(
        context: context,
        reduceMotion: state.effectiveReduceMotion,
        builder: (sheet) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const ArchiveSection(title: '开屏文字', code: 'SYSTEM / LAUNCH TEXT'),
            const SizedBox(height: 10),
            AppText(
              '竖排显示在启动页，换行可分列；留空使用默认诗句「欲买桂花同载酒 / 终不似少年游」。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '欲买桂花同载酒\n终不似少年游',
              ),
            ),
            const SizedBox(height: 16),
            GlassTextButton(
              key: const ValueKey('calligraphy-splash-text-save'),
              onPressed: () => Navigator.pop(sheet, controller.text),
              child: const AppText(
                '保存',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 6),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet),
              child: const AppText('取消'),
            ),
          ],
        ),
      );
      if (value == null || !context.mounted) return;
      await _savePreference(
        context,
        () => state.setCalligraphySplashText(value),
      );
    } finally {
      controller.dispose();
    }
  }
}

class InlineSearchResults extends StatelessWidget {
  const InlineSearchResults({
    super.key,
    required this.state,
    required this.repository,
    required this.feed,
    required this.onOpenBook,
    this.onRecall,
    this.emptyQueryTitle = '你可能会喜欢',
    this.showSources = false,
    this.fromCache = false,
    this.allowBlockedTags = false,
    this.allowShelfQuickAdd = false,
    this.sourceScopeLabel,
    this.onOpenSourceScope,
  });
  final LibraryState state;
  final NovelRepository repository;
  final NovelFeedController feed;
  final VoidCallback onOpenBook;
  final ValueChanged<String>? onRecall;
  final String emptyQueryTitle;
  final bool showSources, fromCache, allowBlockedTags, allowShelfQuickAdd;
  final String? sourceScopeLabel;
  final VoidCallback? onOpenSourceScope;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: feed,
    builder: (context, _) => feed.searchGroups.isNotEmpty
        ? _buildGroupedResults(context)
        : LoadedContentSequence(
            generation: feed.resultReplacesRetained
                ? null
                : feed.resultRevision,
            firstIndex: feed.resultStartIndex == 0
                ? 0
                : feed.resultStartIndex + 1,
            child: _buildResults(context),
          ),
  );

  Widget _buildGroupedResults(BuildContext context) => FeedRefresh(
    feed: feed,
    child: CustomScrollView(
      key: PageStorageKey(('grouped-search-results', feed.query)),
      clipBehavior: LibraryReflowScope.clipOf(context),
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: BookCollectionLayout.cacheExtentFor(
        MediaQuery.sizeOf(context).width - 48,
        base: 250,
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.paddingOf(context).top +
                FrostedHeader.toolbarHeight +
                20,
            24,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              if (allowBlockedTags)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        BlockedTagsButton(
                          key: const ValueKey('search-blocked-tags-manage'),
                          state: state,
                          feed: feed,
                          compact: true,
                        ),
                        if (feed.blockedItemCount > 0) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppText(
                              '当前已隐藏 ${feed.blockedItemCount} 条结果',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              for (final group in feed.searchGroups)
                LoadedContentSequence(
                  key: ValueKey('search-group-${group.searchField.name}'),
                  generation: group.resultReplacesRetained
                      ? null
                      : group.resultRevision,
                  firstIndex: group.resultStartIndex + 1,
                  child: SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: group.searchField == BookSearchField.title
                                ? 0
                                : 20,
                            bottom: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: AppText(
                                  group.searchField.label,
                                  key: ValueKey(
                                    'search-group-heading-${group.searchField.name}',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (group.hasLoaded || group.items.isNotEmpty)
                                AppText(
                                  group.hasBlockedTags
                                      ? '已显示 ${group.items.length}'
                                      : group.totalItems == null ||
                                            group.error != null ||
                                            group.searchNotice != null
                                      ? '已找到 ${group.items.length}'
                                      : '${group.totalItems} 个结果',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      BookCollectionSliver(
                        itemCount: group.items.length,
                        itemBuilder: (context, index) {
                          final book = group.items[index];
                          final hero = CoverHeroTag(group, book.id);
                          return LoadedContentItem(
                            index: index + 1,
                            placeholder: const BookRowSkeleton(),
                            child: NovelRow(
                              key: ValueKey((
                                'search-group-book',
                                group.searchField,
                                book.id,
                              )),
                              novel: book,
                              sourceText: _searchSourceText(book),
                              sourceLabel: showSources
                                  ? bookshelfSource(
                                      book.id,
                                      repository is OfflineNovelRepository
                                          ? repository as OfflineNovelRepository
                                          : null,
                                    )
                                  : null,
                              trailing: _rowTrailing(context, book),
                              coverHeroTag: hero,
                              onTap: () {
                                onOpenBook();
                                openDetail(
                                  context,
                                  book,
                                  state,
                                  repository,
                                  coverHeroTag: hero,
                                  fromCache: fromCache,
                                );
                              },
                            ),
                          );
                        },
                      ),
                      SliverToBoxAdapter(
                        child: _SearchGroupFooter(
                          feed: group,
                          reduceMotion: state.reduceMotion,
                          onManageBlockedTags: allowBlockedTags
                              ? () => showBlockedTagsSettings(
                                  context,
                                  state: state,
                                  feed: feed,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _rowTrailing(BuildContext context, Novel book) {
    if (!allowShelfQuickAdd || isLocalBook(book.id)) {
      return const ArchiveIcon(CupertinoIcons.chevron_right, size: 15);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SearchShelfAction(state: state, book: book),
        const SizedBox(width: 4),
        const ArchiveIcon(CupertinoIcons.chevron_right, size: 15),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    final books = feed.items;
    final searchProgress = feed.searchProgressLabel;
    if (books.isEmpty &&
        feed.query.isEmpty &&
        onRecall != null &&
        state.recentSearches.isNotEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
          24,
          24,
        ),
        children: [
          RecentSearches(state: state, onRecall: onRecall!),
          if (feed.loading && !feed.hasLoaded)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: BookCollectionSkeleton(rows: 2),
            )
          else if (feed.error != null)
            Column(
              children: [
                const AppText('推荐载入失败，仍可搜索书名或作者'),
                GlassTextButton(
                  onPressed: feed.retry,
                  child: const AppText('重试'),
                ),
              ],
            )
          else
            const AppText('搜索书名或作者，开始寻找故事。'),
        ],
      );
    }
    if (books.isEmpty && feed.loading && !feed.hasLoaded) {
      return SearchSkeleton(
        status: feed.searchProgressLabel ?? feed.tagProgressLabel,
      );
    }
    if (books.isEmpty && feed.error != null) {
      return ContentNotice(
        icon: CupertinoIcons.wifi_exclamationmark,
        title: feed.query.isEmpty ? '推荐载入失败' : '搜索失败，请稍后重试',
        message: feed.failureMessage,
        onRetry: feed.retry,
      );
    }
    if (books.isEmpty) {
      if (feed.blockedItemCount > 0) {
        return ContentNotice(
          icon: CupertinoIcons.eye_slash,
          title: '当前结果已被标签屏蔽',
          message: '可管理屏蔽标签，或继续加载后续结果。',
          secondaryAction: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (allowBlockedTags)
                BlockedTagsButton(
                  key: const ValueKey('search-blocked-tags-manage'),
                  state: state,
                  feed: feed,
                  label: '管理屏蔽标签',
                ),
              if (feed.loading)
                const AppText('正在加载…')
              else if (feed.hasMore)
                GlassTextButton(
                  key: const ValueKey('search-blocked-tags-more'),
                  onPressed: feed.loadMore,
                  child: const AppText('继续加载'),
                ),
            ],
          ),
        );
      }
      final scopeHint = sourceScopeLabel == null
          ? ''
          : '\n当前范围：$sourceScopeLabel';
      if (feed.query.isEmpty) {
        final failureScope = feed.failureScopeLabel;
        return ContentNotice(
          icon: failureScope == null
              ? CupertinoIcons.search
              : CupertinoIcons.wifi_exclamationmark,
          title: failureScope == null ? '暂无推荐内容' : '推荐载入失败',
          message: failureScope == null
              ? '试试搜索书名、作者或标签。'
              : '$failureScope暂时无法载入，仍可搜索书名、作者或标签。',
          onRetry: failureScope == null ? null : feed.refresh,
        );
      }
      return ContentNotice(
        icon: CupertinoIcons.search,
        title: feed.searchNotice == null ? '没有找到相关故事' : '部分书源搜索失败',
        message: (feed.searchNotice ?? '试试更短的书名或作者名') + scopeHint,
        onRetry: feed.searchNotice == null ? null : feed.refresh,
        secondaryAction: sourceScopeLabel == null || onOpenSourceScope == null
            ? null
            : GlassTextButton(
                compact: true,
                onPressed: onOpenSourceScope,
                child: const AppText('调整搜索范围'),
              ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            !feed.loading &&
            feed.hasMore &&
            feed.error == null &&
            notification.metrics.extentAfter < 400) {
          WidgetsBinding.instance.addPostFrameCallback((_) => feed.loadMore());
        }
        return false;
      },
      child: FeedRefresh(
        feed: feed,
        child: BookCollectionView.builder(
          key: PageStorageKey(
            'inline-search-results-${feed.searchField.name}-${feed.query}',
          ),
          leadingCount: 1,
          trailingCount: 1,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            22,
            MediaQuery.paddingOf(context).top +
                FrostedHeader.toolbarHeight +
                20,
            22,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          itemCount: books.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return LoadedContentItem(
                index: 0,
                placeholder: const LoadingSkeleton(
                  layout: SkeletonLayout.actions,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (feed.query.isEmpty && onRecall != null)
                        RecentSearches(state: state, onRecall: onRecall!),
                      Row(
                        children: [
                          Expanded(
                            child: AppText(
                              feed.query.isEmpty
                                  ? emptyQueryTitle
                                  : feed.hasBlockedTags
                                  ? '已显示 ${books.length} 个结果'
                                  : '找到 ${feed.totalItems ?? books.length} 个结果',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          if (allowBlockedTags)
                            BlockedTagsButton(
                              key: const ValueKey('search-blocked-tags-manage'),
                              state: state,
                              feed: feed,
                              compact: true,
                            ),
                        ],
                      ),
                      if (feed.loading && searchProgress != null) ...[
                        const SizedBox(height: 8),
                        AppText(
                          searchProgress,
                          key: const ValueKey('source-search-progress'),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (feed.searchNotice case final notice?) ...[
                        const SizedBox(height: 8),
                        AppText(
                          notice,
                          key: const ValueKey('search-partial-notice'),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.6,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GlassTextButton(
                            onPressed: feed.loading ? null : feed.refresh,
                            child: const AppText('重试搜索'),
                          ),
                        ),
                      ],
                      if (sourceScopeLabel case final label?) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: AppText(
                                '搜索范围：$label',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (onOpenSourceScope != null)
                              GlassTextButton(
                                compact: true,
                                onPressed: onOpenSourceScope,
                                child: const AppText('调整'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }
            if (index == books.length + 1) {
              return FeedFooter(feed: feed, horizontalPadding: 0);
            }
            final book = books[index - 1];
            return LoadedContentItem(
              key: ValueKey(book.id),
              index: index,
              placeholder: const BookRowSkeleton(),
              child: NovelRow(
                novel: book,
                sourceText: _searchSourceText(book),
                sourceLabel: showSources
                    ? bookshelfSource(
                        book.id,
                        repository is OfflineNovelRepository
                            ? repository as OfflineNovelRepository
                            : null,
                      )
                    : null,
                trailing: _rowTrailing(context, book),
                coverHeroTag: CoverHeroTag(context, book.id),
                onTap: () {
                  onOpenBook();
                  openDetail(
                    context,
                    book,
                    state,
                    repository,
                    coverHeroTag: CoverHeroTag(context, book.id),
                    fromCache: fromCache,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

String _searchSourceText(Novel book) {
  final name = book.source?.sourceName.trim() ?? '';
  if (name.isNotEmpty) return name;
  return isLocalBook(book.id) ? '本地' : '轻小说文库';
}

class _SearchShelfAction extends StatefulWidget {
  const _SearchShelfAction({required this.state, required this.book});

  final LibraryState state;
  final Novel book;

  @override
  State<_SearchShelfAction> createState() => _SearchShelfActionState();
}

class _SearchShelfActionState extends State<_SearchShelfAction> {
  bool _busy = false;

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.state.setShelfMembership(
        widget.book.id,
        true,
        novel: widget.book,
      );
      if (mounted) {
        showNovelFeedback(context, '已加入书架', haptic: HapticCue.selection);
      }
    } catch (_) {
      if (mounted) showNovelFeedback(context, '加入书架失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final added = widget.state.contains(widget.book.id);
      return GlassIconButton(
        key: ValueKey('search-add-${widget.book.id}'),
        icon: added ? CupertinoIcons.checkmark : CupertinoIcons.bookmark,
        color: added ? Theme.of(context).colorScheme.primary : null,
        label: added ? '已在书架' : '加入书架',
        liveGlass: false,
        transparent: true,
        onPressed: added || _busy ? null : _add,
      );
    },
  );
}

class _SearchGroupFooter extends StatelessWidget {
  const _SearchGroupFooter({
    required this.feed,
    required this.reduceMotion,
    this.onManageBlockedTags,
  });
  final NovelFeedController feed;
  final bool reduceMotion;
  final VoidCallback? onManageBlockedTags;

  @override
  Widget build(BuildContext context) {
    final progress = feed.searchProgressLabel ?? feed.tagProgressLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (feed.loading && !feed.refreshing) ...[
            if (progress != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppText(
                  progress,
                  key: const ValueKey('tag-search-progress'),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            BookCollectionSkeleton(
              rows: 1,
              label: '正在搜索${feed.searchField.label}',
            ),
          ] else if (feed.error != null) ...[
            AppText(
              feed.refreshFailed
                  ? '刷新失败，已保留原结果'
                  : feed.hasLoaded
                  ? '加载下一页失败'
                  : '${feed.searchField.label}搜索未完成',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            AppText(
              feed.failureMessage,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            GlassTextButton(onPressed: feed.retry, child: const AppText('重试')),
          ] else if (feed.searchNotice case final notice?) ...[
            AppText(
              notice,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            GlassTextButton(
              onPressed: feed.refresh,
              child: const AppText('重试'),
            ),
          ] else if (feed.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    feed.blockedItemCount > 0
                        ? '当前页结果已被标签屏蔽'
                        : '没有匹配的${feed.searchField.label}',
                    key: ValueKey(
                      'search-group-empty-${feed.searchField.name}',
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (feed.blockedItemCount > 0) ...[
                    if (onManageBlockedTags != null)
                      GlassTextButton(
                        onPressed: onManageBlockedTags,
                        child: const AppText('管理屏蔽标签'),
                      ),
                    if (feed.hasMore)
                      GlassTextButton(
                        onPressed: feed.loadMore,
                        child: AppText('更多${feed.searchField.label}结果'),
                      ),
                  ],
                ],
              ),
            )
          else if (feed.hasMore)
            GlassTextButton(
              onPressed: feed.loadMore,
              child: AppText('更多${feed.searchField.label}结果'),
            ),
        ],
      ),
    );
  }
}

class DetailLoaderPage extends StatefulWidget {
  const DetailLoaderPage({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
    this.coverHeroTag,
    this.showOpening = false,
    this.promptAddToShelfOnExit = true,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  final Object? coverHeroTag;
  final bool showOpening;
  final bool promptAddToShelfOnExit;

  @override
  State<DetailLoaderPage> createState() => _DetailLoaderPageState();
}

class _DetailLoaderPageState extends State<DetailLoaderPage> {
  late Future<Novel> _loaded = _load();
  Novel? _cached;

  @override
  void initState() {
    super.initState();
    if (widget.repository case final OfflineNovelRepository offline) {
      final saved = offline.cache.book(widget.novel.id)?.novel;
      if (saved != null && saved.chapters.isNotEmpty) _cached = saved;
    }
    unawaited(_seedFromCache());
  }

  Future<void> _seedFromCache() async {
    if (widget.repository case final OfflineNovelRepository offline) {
      try {
        final cached = await offline.cachedBook(widget.novel.id);
        if (mounted && cached != null && cached.chapters.isNotEmpty) {
          setState(() => _cached = cached);
        }
      } catch (_) {
        // Online loading remains available when a local snapshot is damaged.
      }
    }
  }

  Future<Novel> _load() async {
    final detail = await widget.repository.detail(widget.novel);
    final chapters = await widget.repository.chapters(widget.novel.id);
    final loaded = detail.withChapters(chapters);
    await widget.state.rememberNovel(loaded);
    return loaded;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Novel>(
    future: _loaded,
    // Keep the destination cover's element and layout alive from the first
    // route frame through loading, errors and completion of its Hero flight.
    builder: (context, snapshot) => DetailPage(
      novel: snapshot.data ?? _cached ?? widget.novel,
      transitionNovel: widget.novel,
      coverHeroTag: widget.coverHeroTag,
      state: widget.state,
      repository: widget.repository,
      isLoading:
          !snapshot.hasData &&
          _cached == null &&
          snapshot.connectionState != ConnectionState.done,
      loadError: _cached == null ? snapshot.error : null,
      showOpening: widget.showOpening,
      promptAddToShelfOnExit: widget.promptAddToShelfOnExit,
      fromCache:
          (_cached != null && !snapshot.hasData) ||
          (widget.repository is OfflineNovelRepository &&
              (widget.repository as OfflineNovelRepository).isDirectoryOffline(
                widget.novel.id,
              )),
      onRetry: () => setState(() {
        _loaded = _load();
      }),
    ),
  );
}

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
    this.coverHeroTag,
    this.transitionNovel,
    this.isLoading = false,
    this.loadError,
    this.onRetry,
    this.fromCache = false,
    this.showOpening = false,
    this.promptAddToShelfOnExit = true,
    this.onRead,
    this.onReadTarget,
    this.onSourceSwitched,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  final Object? coverHeroTag;
  final Novel? transitionNovel;
  final bool isLoading;
  final Object? loadError;
  final VoidCallback? onRetry;
  final bool fromCache;
  final bool showOpening;
  final bool promptAddToShelfOnExit;
  final ValueChanged<int>? onRead;
  final ValueChanged<BookReadingTarget>? onReadTarget;
  final ValueChanged<Novel>? onSourceSwitched;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> with TickerProviderStateMixin {
  final _directoryReflow = LibraryReflowController();
  late final AnimationController _catalogueOrder = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: NovelMotion.reveal,
  );
  late final AnimationController _contentIntro = AnimationController(
    vsync: this,
    duration: NovelMotion.reveal,
  );
  Animation<double>? _routeAnimation;
  bool _introStarted = false;
  bool _contentStarted = false;
  bool _cacheSkeletonShown = false;
  bool _readerOpening = false;
  bool _shelfChanging = false;
  bool _cacheOpen = false;
  bool _refreshing = false;
  bool _catalogueOrderSaving = false;
  bool _summaryExpanded = false;
  bool _catalogueExpanded = false;
  late bool _catalogueReversed = state
      .readerPreferencesFor(novel.id)
      .catalogueReversed;
  int? _resumeChapter;
  int? _resumeDirectory;
  final Set<String> _expandedVolumes = {};
  final Set<String> _directoryVolumeKeys = {};
  int? _directoryBook;
  Novel? _switchedNovel;
  bool _sourceSwitching = false;
  bool _sourcePickerOpen = false;

  List<({NovelVolume? volume, int? chapter})> _directory() {
    // Provisional cached chapters can predate volume metadata. Wait for the
    // displayed directory before choosing its initially expanded volume.
    if (isLoading || loadError != null) return const [];
    final volumes = NovelVolume.of(novel.directoryChapters);
    if (_directoryBook != novel.id) {
      _expandedVolumes.clear();
      _directoryVolumeKeys.clear();
    }
    final current = novel.directoryIndexFor(
      _resumeChapter ?? 0,
      paragraph: state.positionFor(novel.id)?.paragraphIndex ?? 0,
      offset: state.positionFor(novel.id)?.textOffset ?? 0,
    );
    for (final volume in volumes) {
      if (current >= volume.start &&
          current < volume.end &&
          !_directoryVolumeKeys.contains(volume.key)) {
        _expandedVolumes.add(volume.key);
      }
    }
    _directoryVolumeKeys
      ..clear()
      ..addAll(volumes.map((volume) => volume.key));
    _expandedVolumes.retainAll(_directoryVolumeKeys);
    if (volumes.isNotEmpty) _directoryBook = novel.id;
    return [
      for (final volume in _catalogueReversed ? volumes.reversed : volumes) ...[
        if (volume.title.isNotEmpty) (volume: volume, chapter: null),
        if (volume.title.isEmpty || _expandedVolumes.contains(volume.key))
          for (final i in Iterable.generate(
            volume.length,
            (i) => _catalogueReversed ? volume.end - i - 1 : volume.start + i,
          ))
            (volume: null, chapter: i),
      ],
    ];
  }

  Novel get novel {
    final switched = _switchedNovel;
    if (switched != null && switched.id == widget.novel.id) return switched;
    return isLocalBook(widget.novel.id) && repository is OfflineNovelRepository
        ? (repository as OfflineNovelRepository).local?.book(widget.novel.id) ??
              widget.novel
        : widget.novel;
  }

  LibraryState get state => widget.state;
  NovelRepository get repository => widget.repository;
  BookSourceLibrary? get _bookSources {
    final source = repository;
    if (source is OfflineNovelRepository) return source.bookSources;
    if (source is LibrarySourcesRepository) return source.bookSources;
    if (source is BookSourceLibrary) return source as BookSourceLibrary;
    return null;
  }

  Object? get coverHeroTag => widget.coverHeroTag;
  Novel? get transitionNovel => widget.transitionNovel;
  bool get _titleUpdated =>
      transitionNovel != null && transitionNovel!.title != novel.title;
  bool get _authorUpdated =>
      transitionNovel != null && transitionNovel!.author != novel.author;
  bool get isLoading => widget.isLoading;
  Object? get loadError => widget.loadError;
  VoidCallback? get onRetry => widget.onRetry;
  bool get _reduceMotion =>
      state.reduceMotion || MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    state.readerSettingsChanges.addListener(_catalogueSettingsChanged);
    _catalogueOrder.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          _directoryReflow.active &&
          mounted) {
        setState(_directoryReflow.finish);
      }
    });
  }

  void _changeDirectory(VoidCallback change) {
    if (!_reduceMotion) _directoryReflow.begin(_catalogueOrder);
    setState(change);
    if (!_reduceMotion) _catalogueOrder.forward(from: 0);
  }

  Widget _directoryMotion(Widget child) => LibraryReflowScope(
    controller: _directoryReflow,
    enabled: !_reduceMotion,
    generation: _directoryReflow.generation,
    active: _directoryReflow.active,
    child: LibraryReflowClip(controller: _directoryReflow, child: child),
  );

  void _catalogueSettingsChanged() {
    final reversed = state.readerPreferencesFor(novel.id).catalogueReversed;
    if (mounted && reversed != _catalogueReversed) {
      _changeDirectory(() => _catalogueReversed = reversed);
    }
  }

  Future<void> _toggleCatalogueOrder() async {
    if (_catalogueOrderSaving) return;
    setState(() => _catalogueOrderSaving = true);
    try {
      // Order is shared interaction behaviour, not this book's typography.
      await state.setReaderPreferences(
        state.readerPreferences.copyWith(
          catalogueReversed: !_catalogueReversed,
        ),
      );
    } catch (_) {
      if (mounted) showNovelFeedback(context, '目录顺序保存失败，请重试');
    } finally {
      if (mounted) setState(() => _catalogueOrderSaving = false);
    }
  }

  Widget _directoryHeading(BuildContext context) => Row(
    children: [
      Expanded(
        child: ArchiveSection(
          title: '目录',
          code: '02 / CONTENTS',
          subtitle: _directoryCountLabel,
        ),
      ),
      GlassTextButton(
        key: const ValueKey('detail-catalogue-order'),
        compact: true,
        selected: _catalogueReversed,
        onPressed:
            isLoading ||
                loadError != null ||
                novel.directory.length < 2 ||
                _catalogueOrderSaving
            ? null
            : _toggleCatalogueOrder,
        child: AppText(_catalogueReversed ? '倒序' : '正序'),
      ),
    ],
  );

  void _viewCover() {
    AppHaptics.play(context, HapticCue.action);
    openNovelCoverImage(context, novel, reduceMotion: state.reduceMotion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeStatusListener(_routeChanged);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeChanged);
    }
    if (_reduceMotion) {
      _intro.stop();
      _contentIntro.stop();
      _intro.value = 1;
      _contentIntro.value = 1;
      _introStarted = true;
      _contentStarted = !isLoading;
    } else if (animation == null ||
        animation.status == AnimationStatus.completed) {
      // A newly installed route's proxy can briefly report completed before
      // Navigator attaches the push animation at the end of its first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startIntro();
      });
    }
  }

  void _routeChanged(AnimationStatus status) {
    if (mounted && status == AnimationStatus.completed) _startIntro();
  }

  void _startIntro() {
    if (_routeAnimation != null &&
        _routeAnimation!.status != AnimationStatus.completed) {
      return;
    }
    if (!_introStarted) {
      _introStarted = true;
      if (isLoading) setState(() => _cacheSkeletonShown = true);
      _intro.forward();
    }
    if (!isLoading && !_contentStarted) {
      _contentStarted = true;
      _contentIntro.forward();
    }
  }

  @override
  void didUpdateWidget(DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousSource = oldWidget.novel.source;
    final nextSource = widget.novel.source;
    if (oldWidget.novel.id != widget.novel.id ||
        previousSource?.sourceKey != nextSource?.sourceKey ||
        previousSource?.bookUrl != nextSource?.bookUrl) {
      _summaryExpanded = false;
      _switchedNovel = null;
      _catalogueExpanded = false;
    }
    if (oldWidget.state != widget.state) {
      oldWidget.state.readerSettingsChanges.removeListener(
        _catalogueSettingsChanged,
      );
      state.readerSettingsChanges.addListener(_catalogueSettingsChanged);
    }
    _catalogueReversed = state.readerPreferencesFor(novel.id).catalogueReversed;
    if (isLoading && !oldWidget.isLoading) {
      _contentStarted = false;
      _contentIntro.value = 0;
    } else if (!isLoading && oldWidget.isLoading) {
      if (_reduceMotion) {
        _contentIntro.value = 1;
        _contentStarted = true;
      } else if (_introStarted) {
        _startIntro();
      }
    }
  }

  @override
  void dispose() {
    state.readerSettingsChanges.removeListener(_catalogueSettingsChanged);
    _routeAnimation?.removeStatusListener(_routeChanged);
    _intro.dispose();
    _contentIntro.dispose();
    _directoryReflow.dispose();
    _catalogueOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _resumeChapter = _recordedChapter;
    _resumeDirectory = _resumeChapter == null
        ? null
        : novel.directoryIndexFor(
            _resumeChapter!,
            paragraph: state.positionFor(novel.id)?.paragraphIndex ?? 0,
            offset: state.positionFor(novel.id)?.textOffset ?? 0,
          );
    final directory = _directory();
    final safe = MediaQuery.viewPaddingOf(context);
    final edge = MediaQuery.sizeOf(context).width >= 700 ? 40.0 : 24.0;
    return PopScope(
      canPop: !_sourceSwitching,
      child: Scaffold(
        body: Atmosphere(
          child: GlassHeaderLayout(
            header: _header(context),
            body: AbsorbPointer(
              absorbing: _sourceSwitching,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _directoryMotion(
                      CustomScrollView(
                        key: PageStorageKey('detail-scroll-${novel.id}'),
                        clipBehavior: _directoryReflow.active
                            ? Clip.none
                            : Clip.hardEdge,
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              edge + safe.left,
                              safe.top + FrostedHeader.toolbarHeight + 24,
                              edge + safe.right,
                              0,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: RepaintBoundary(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _identity(context),
                                    if (isLoading) ...[
                                      const SizedBox(height: 28),
                                      const DetailSkeleton(),
                                    ] else if (loadError != null) ...[
                                      const SizedBox(height: 28),
                                      _detailFailure(context),
                                    ] else ...[
                                      if (novel.tags.isNotEmpty) ...[
                                        const SizedBox(height: 20),
                                        _tags(context),
                                      ],
                                      if (_resumeChapter != null) ...[
                                        const SizedBox(height: 24),
                                        _resumeInformation(context),
                                      ],
                                      RevealFromTop(
                                        key: const ValueKey(
                                          'detail-summary-reveal',
                                        ),
                                        animation: _contentIntro,
                                        start: .27,
                                        end: .76,
                                        placeholder: const LoadingSkeleton(
                                          layout: SkeletonLayout.detail,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 28,
                                          ),
                                          child: _synopsis(context),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 24),
                                        child: _bookFacts(context),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 24),
                                        child: RevealFromTop(
                                          key: const ValueKey(
                                            'detail-catalogue-toggle-reveal',
                                          ),
                                          animation: _contentIntro,
                                          start: .34,
                                          placeholder: const LoadingSkeleton(
                                            layout: SkeletonLayout.actions,
                                          ),
                                          child: _catalogueToggle(context),
                                        ),
                                      ),
                                      if (_catalogueExpanded)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 24,
                                          ),
                                          child: RevealFromTop(
                                            key: const ValueKey(
                                              'detail-directory-reveal',
                                            ),
                                            animation: _contentIntro,
                                            start: .43,
                                            placeholder: const LoadingSkeleton(
                                              layout: SkeletonLayout.actions,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _directoryHeading(context),
                                                if (novel.chapters.isEmpty) ...[
                                                  const SizedBox(height: 14),
                                                  const AppText('暂无章节'),
                                                ],
                                                const SizedBox(height: 8),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_catalogueExpanded &&
                              !isLoading &&
                              loadError == null)
                            SliverPadding(
                              padding: EdgeInsets.symmetric(horizontal: edge)
                                  .copyWith(
                                    left: edge + safe.left,
                                    right: edge + safe.right,
                                  ),
                              sliver: SliverList.builder(
                                itemCount: directory.length,
                                itemBuilder: (context, index) => RevealFromTop(
                                  key: ValueKey('detail-chapter-$index'),
                                  animation: _contentIntro,
                                  start: .48 + index.clamp(0, 8) * .025,
                                  placeholder: const LoadingSkeleton(
                                    layout: SkeletonLayout.inline,
                                  ),
                                  end: .78 + index.clamp(0, 8) * .025,
                                  child: LibraryReflowPart(
                                    id: directory[index].volume != null
                                        ? (
                                            'volume',
                                            directory[index].volume!.key,
                                          )
                                        : (
                                            'chapter',
                                            directory[index].chapter!,
                                          ),
                                    child: directory[index].volume != null
                                        ? _volumeRow(
                                            context,
                                            directory[index].volume!,
                                          )
                                        : _chapterRow(
                                            context,
                                            directory[index].chapter!,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: _footerGeometry(context).extent + 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: DockUnderlay(
                      contentHeight: _footerGeometry(context).height,
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        DockLayout.actionSideInset + safe.left,
                        0,
                        DockLayout.actionSideInset + safe.right,
                        DockLayout.bottomPaddingOf(context, viewPadding: true),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: DockLayout.actionMaxWidth,
                        ),
                        child: RevealFromTop(
                          key: const ValueKey('detail-footer-reveal'),
                          animation: _intro,
                          start: .52,
                          child: ArchiveMotionScope(
                            animation: _contentIntro,
                            enabled: !_reduceMotion && loadError == null,
                            child: AnimatedBuilder(
                              animation: state,
                              builder: (context, _) => _footerActions(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _identity(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final wide = constraints.maxWidth >= 650;
      final coverWidth = wide ? 150.0 : 118.0;
      final cover = Semantics(
        button: true,
        label: novelCoverUrl(novel)?.isNotEmpty == true ? '查看小说封面，长按更换' : '更换封面',
        child: GestureDetector(
          key: const ValueKey('detail-view-cover'),
          onTap: novelCoverUrl(novel)?.isNotEmpty == true ? _viewCover : _changeCover,
          onLongPress: _changeCover,
          child: NovelCover(
            transitionNovel ?? novel,
            width: coverWidth,
            height: coverWidth * 1.4,
            heroTag: coverHeroTag,
            isDetailCover: true,
          ),
        ),
      );
      final metadata = _identityText(context, wide: wide);
      if (scale >= 1.45 && !wide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [cover, const SizedBox(height: 22), metadata],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cover,
          SizedBox(width: wide ? 28 : 20),
          Expanded(child: metadata),
        ],
      );
    },
  );

  Widget _identityText(BuildContext context, {required bool wide}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RevealFromTop(
        key: const ValueKey('detail-title-reveal'),
        axis: ArchiveRevealAxis.horizontal,
        animation: _titleUpdated ? _contentIntro : _intro,
        end: .46,
        placeholder: _titleUpdated
            ? const LoadingSkeleton(layout: SkeletonLayout.inline)
            : null,
        child: AppText(
          novel.title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: wide ? 28 : 24,
            height: 1.25,
            letterSpacing: -.5,
          ),
        ),
      ),
      const SizedBox(height: 8),
      RevealFromTop(
        key: const ValueKey('detail-author-reveal'),
        axis: ArchiveRevealAxis.horizontal,
        animation: _authorUpdated ? _contentIntro : _intro,
        start: .09,
        end: .56,
        placeholder: _authorUpdated && !isLoading
            ? const LoadingSkeleton(layout: SkeletonLayout.inline)
            : null,
        child: isLoading && novel.author.trim().isEmpty
            ? const InlineSkeleton(
                key: ValueKey('detail-author-skeleton'),
                height: 20,
                label: '正在加载作者信息',
              )
            : novel.author.trim().isEmpty
            ? const SizedBox.shrink()
            : Semantics(
                button: true,
                label: '查看${novel.author}的作品',
                child: JellyTapSurface(
                  key: const ValueKey('detail-author-works'),
                  onTap: () => pushNovelPage<void>(
                    context,
                    AuthorWorksPage(
                      author: novel.author,
                      repository: repository,
                      state: state,
                      localOnly: isLocalBook(novel.id),
                    ),
                    reduceMotion: _reduceMotion,
                    explorationKey: (
                      'author',
                      novel.author.trim(),
                      isLocalBook(novel.id),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: AppText(
                            novel.author,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const ArchiveIcon(
                          CupertinoIcons.chevron_right,
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
      const SizedBox(height: 6),
      RevealFromTop(
        key: const ValueKey('detail-source-reveal'),
        axis: ArchiveRevealAxis.horizontal,
        animation: isLoading ? _intro : _contentIntro,
        start: .14,
        end: .6,
        child: _sourceLine(context),
      ),
      const SizedBox(height: 10),
      RevealFromTop(
        key: const ValueKey('detail-meta-reveal'),
        axis: ArchiveRevealAxis.horizontal,
        animation: isLoading ? _intro : _contentIntro,
        start: .18,
        end: .64,
        placeholder: !isLoading
            ? const LoadingSkeleton(layout: SkeletonLayout.actions)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLoading)
              const InlineSkeleton(
                key: ValueKey('detail-meta-skeleton'),
                label: '正在加载章节信息',
              )
            else
              _cacheReactive(
                () => AppText(
                  loadError != null
                      ? '目录暂未载入'
                      : '${novel.isComplete ? '已完结' : '连载中'} · $_chapterCountLabel',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            ArchiveCode(ArchiveDesign.fileCode(novel.id), inverse: true),
          ],
        ),
      ),
      if (repository case final OfflineNovelRepository offline) ...[
        const SizedBox(height: 8),
        if (isLoading && _cacheSkeletonShown)
          const InlineSkeleton(
            key: ValueKey('detail-cache-skeleton'),
            label: '正在加载缓存信息',
          )
        else if (isLoading)
          const SizedBox(height: 18)
        else if (loadError == null && !isLocalBook(novel.id))
          RevealFromTop(
            key: const ValueKey('detail-cache-reveal'),
            axis: ArchiveRevealAxis.horizontal,
            animation: _cacheSkeletonShown ? _contentIntro : _intro,
            start: .24,
            end: .72,
            placeholder: _cacheSkeletonShown
                ? const LoadingSkeleton(layout: SkeletonLayout.inline)
                : null,
            child: OfflineBookStatus(
              repository: offline,
              novel: novel,
              localDirectory: widget.fromCache,
              reduceMotion: state.reduceMotion,
            ),
          ),
      ],
    ],
  );

  String? get _updateStamp {
    final updated = novel.lastUpdate?.trim();
    if (updated != null && updated.isNotEmpty) return updated;
    if (repository case final OfflineNovelRepository offline) {
      if (isLocalBook(novel.id)) {
        final at = offline.local?.importedAt(novel.id) ?? 0;
        if (at > 0) {
          final date = DateTime.fromMillisecondsSinceEpoch(at);
          return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        }
      }
    }
    return null;
  }

  String get _sourceName {
    final name = novel.source?.sourceName.trim() ?? '';
    if (name.isNotEmpty) return name;
    final offline = repository is OfflineNovelRepository
        ? repository as OfflineNovelRepository
        : null;
    return switch (bookshelfSource(novel.id, offline)) {
      '本地' => '本地导入',
      '缓存' => '已缓存',
      _ => '在线',
    };
  }

  String? get _latestChapter {
    final directory = novel.directory;
    if (directory.isEmpty) return null;
    final title = directory.last.title.trim();
    return title.isEmpty ? null : title;
  }

  Widget _sourceLine(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: '当前书源：$_sourceName',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText(
            '书源',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              letterSpacing: .3,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: .7),
                  width: .7,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: AppText(
                  _sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookFacts(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final update = _updateStamp;
    final latest = _latestChapter;
    final facts = <(String, String)>[
      ('状态', novel.isComplete ? '已完结' : '连载中'),
      ('目录', _directoryCountLabel),
      if (novel.wordCount != null && novel.wordCount! > 0)
        ('字数', _formatWordCount(novel.wordCount!)),
      if (update != null) ('更新时间', update),
    ];
    return ArchiveRegistration(
      child: Container(
        key: const ValueKey('detail-book-facts'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: .65),
            width: .7,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(0.0, (constraints.maxWidth - 14) / 2);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  children: [
                    for (final (label, value) in facts)
                      SizedBox(
                        width: width,
                        child: _fact(context, label, value),
                      ),
                  ],
                ),
                if (latest != null) ...[
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    thickness: .7,
                    color: colors.outlineVariant.withValues(alpha: .55),
                  ),
                  const SizedBox(height: 12),
                  _fact(context, '最新章节', latest, maxLines: 2),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatWordCount(int value) {
    if (value >= 10000) {
      final text = (value / 10000)
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
      return '$text万字';
    }
    return '$value字';
  }

  Widget _fact(
    BuildContext context,
    String label,
    String value, {
    int maxLines = 1,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppText(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          letterSpacing: .3,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 3),
      AppText(
        value,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _catalogueToggle(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ready = !isLoading && loadError == null && novel.chapters.isNotEmpty;
    final subtitle = isLoading
        ? '正在加载目录'
        : loadError != null
        ? '目录暂未载入'
        : novel.chapters.isEmpty
        ? '暂无可读章节'
        : _directoryCountLabel;
    return ArchiveRegistration(
      child: Semantics(
        button: true,
        enabled: ready,
        label: _catalogueExpanded ? '收起目录' : '查看目录',
        child: JellyTapSurface(
          key: const ValueKey('detail-catalogue-toggle'),
          onTap: ready
              ? () => _changeDirectory(
                  () => _catalogueExpanded = !_catalogueExpanded,
                )
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: .65),
                width: .7,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                ArchiveIcon(
                  CupertinoIcons.list_bullet,
                  size: 19,
                  color: colors.onSurface.withValues(alpha: ready ? 1 : .45),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        _catalogueExpanded ? '收起目录' : '查看目录',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface.withValues(
                            alpha: ready ? 1 : .45,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      AppText(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _catalogueExpanded ? .5 : 0,
                  duration: _reduceMotion ? Duration.zero : NovelMotion.enter,
                  curve: NovelMotion.ease,
                  child: ArchiveIcon(
                    CupertinoIcons.chevron_down,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tags(BuildContext context) => Wrap(
    key: const ValueKey('detail-book-tags'),
    spacing: 7,
    runSpacing: 7,
    children: [
      for (final tag in novel.tags)
        JellyTapSurface(
          key: ValueKey('detail-tag-$tag'),
          onTap: () => pushNovelPage<void>(
            context,
            TagWorksPage(tag: tag, repository: repository, state: state),
            reduceMotion: state.reduceMotion,
            explorationKey: ('tag', tag),
          ),
          child: Semantics(
            button: true,
            label: '查看标签 $tag 的书籍',
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: .7),
                  width: .7,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: AppText(
                  tag,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _resumeInformation(BuildContext context) {
    final index = _resumeChapter!;
    final saved = state.positionFor(novel.id);
    final title = novel.readingTitleFor(
      index,
      paragraph: saved?.paragraphIndex ?? 0,
      offset: saved?.textOffset ?? 0,
    );
    final volume = novel.chapters[index].volumeTitle;
    final ink = Theme.of(context).colorScheme.onSurface;
    return ArchiveRegistration(
      child: Container(
        key: const ValueKey('detail-resume-information'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: .65),
            width: .7,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              '读到 ${volume.isEmpty ? '' : '$volume · '}$title',
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (saved != null) ...[
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: saved.fraction.clamp(0.0, 1.0),
                      minHeight: 3,
                      color: ink,
                      backgroundColor: ink.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppText(
                    '本章 ${(saved.fraction * 100).floor()}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _synopsisText {
    final direct = novel.summary.trim();
    if (direct.isNotEmpty) return direct;
    final original = transitionNovel;
    if (original != null &&
        original.id == novel.id &&
        original.source?.sourceKey == novel.source?.sourceKey &&
        original.source?.bookUrl == novel.source?.bookUrl) {
      final fallback = original.summary.trim();
      if (fallback.isNotEmpty) return fallback;
    }
    return '暂无简介';
  }

  Widget _synopsis(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const style = TextStyle(fontSize: 15, height: 1.8);
      final text = appText(context, _synopsisText);
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        maxLines: 3,
        ellipsis: '…',
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final expandable = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ArchiveSection(title: '简介', code: '01 / SYNOPSIS'),
          const SizedBox(height: 14),
          AnimatedSize(
            duration: _reduceMotion ? Duration.zero : NovelMotion.enter,
            reverseDuration: _reduceMotion ? Duration.zero : NovelMotion.exit,
            alignment: Alignment.topLeft,
            curve: NovelMotion.ease,
            child: AppText(
              _synopsisText,
              key: const ValueKey('detail-synopsis-text'),
              maxLines: _summaryExpanded ? null : 3,
              overflow: _summaryExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (expandable)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: JellyTapSurface(
                key: const ValueKey('detail-synopsis-toggle'),
                onTap: () =>
                    setState(() => _summaryExpanded = !_summaryExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppText(
                        _summaryExpanded ? '收起' : '展开全部',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 7),
                      AnimatedRotation(
                        turns: _summaryExpanded ? .5 : 0,
                        duration: _reduceMotion
                            ? Duration.zero
                            : NovelMotion.enter,
                        curve: NovelMotion.ease,
                        child: const ArchiveIcon(
                          CupertinoIcons.chevron_down,
                          size: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _detailFailure(BuildContext context) => Column(
    children: [
      const Center(child: AppText('书籍详情加载失败')),
      if (loadError case final FormatException error)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AppText(error.message, textAlign: TextAlign.center),
        ),
      Center(
        child: GlassTextButton(onPressed: onRetry, child: const AppText('重试')),
      ),
    ],
  );

  int? get _recordedChapter {
    if (novel.chapters.isEmpty || !state.hasRead(novel.id)) return null;
    final saved = state.positionFor(novel.id);
    if (saved != null) return state.chapterForPosition(novel, saved);
    final chapter = state.chapterFor(novel.id);
    return chapter >= 0 && chapter < novel.chapters.length ? chapter : null;
  }

  String get _primaryLabel => isLoading
      ? '正在加载目录'
      : loadError != null
      ? '重试加载目录'
      : novel.chapters.isEmpty
      ? '暂无可读章节'
      : _resumeChapter != null
      ? '继续阅读'
      : '开始阅读';

  String get _secondaryLabel => isLocalBook(novel.id)
      ? '配置书籍'
      : state.contains(novel.id)
      ? '移出书架'
      : '加入书架';

  ({bool stacked, double height, double extent}) _footerGeometry(
    BuildContext context,
  ) => glassActionDockGeometry(
    context,
    primary: _primaryLabel,
    secondary: _secondaryLabel,
  );

  Widget _footerActions(BuildContext context) {
    final action = isLoading
        ? null
        : loadError != null
        ? onRetry
        : novel.chapters.isEmpty
        ? null
        : () => _openReader(context, _resumeChapter ?? 0);
    final theme = Theme.of(context);
    final primary = _footerAction(
      context,
      key: const ValueKey('detail-read-button'),
      icon: CupertinoIcons.play_fill,
      label: _primaryLabel,
      semanticLabel: _readLabel,
      loading: isLoading,
      onTap: action,
    );
    final secondary = _footerAction(
      context,
      key: ValueKey(
        isLocalBook(novel.id) ? 'local-book-config' : 'detail-shelf-button',
      ),
      icon: isLocalBook(novel.id)
          ? CupertinoIcons.gear_alt
          : state.contains(novel.id)
          ? CupertinoIcons.bookmark_fill
          : CupertinoIcons.bookmark,
      label: _secondaryLabel,
      onTap: isLocalBook(novel.id)
          ? repository is OfflineNovelRepository &&
                    (repository as OfflineNovelRepository).local != null
                ? _configureLocalBook
                : null
          : _shelfChanging
          ? null
          : _toggleShelf,
    );
    final geometry = _footerGeometry(context);
    return Theme(
      key: const ValueKey('detail-action-dock'),
      data: theme,
      child: ControlMaterialScope.chrome(
        child: SizedBox(
          height: geometry.height,
          child: geometry.stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    primary,
                    const SizedBox(height: DockLayout.actionGap),
                    secondary,
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 5, child: secondary),
                    const SizedBox(width: DockLayout.actionGap),
                    Expanded(flex: 7, child: primary),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _footerAction(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    String? semanticLabel,
    bool loading = false,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      enabled: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: GlassPillButton(
        key: key,
        icon: icon,
        label: label,
        onPressed: onTap,
        loading: loading,
        height: DockLayout.heightOf(context),
        iconSize: DockLayout.iconSize,
        fontSize: DockLayout.labelFontSize,
      ),
    );
  }

  Future<void> _toggleShelf() async {
    if (_shelfChanging) return;
    setState(() => _shelfChanging = true);
    try {
      await state.toggleShelf(novel.id, novel: novel);
    } catch (_) {
      if (mounted) showNovelFeedback(context, '书架操作保存失败，请重试');
    } finally {
      if (mounted) setState(() => _shelfChanging = false);
    }
  }

  Future<void> _configureLocalBook() async {
    final local = repository is OfflineNovelRepository
        ? (repository as OfflineNovelRepository).local
        : null;
    if (local == null) return;
    final result = await pushNovelPage<LocalBookEditResult>(
      context,
      LocalBookEditor(book: novel, books: local, library: state),
      reduceMotion: _reduceMotion,
    );
    if (!mounted) return;
    if (result == LocalBookEditResult.hidden ||
        result == LocalBookEditResult.deleted ||
        result == LocalBookEditResult.regrouped) {
      if (!LibraryWorkspace.close(context)) Navigator.pop(context);
    } else if (result == LocalBookEditResult.saved) {
      setState(() {});
    }
  }

  String get _readLabel {
    if (isLoading) return '正在加载目录';
    if (loadError != null) return '重试加载目录';
    if (novel.chapters.isEmpty) return '暂无可读章节';
    final action = _resumeChapter != null ? '继续阅读' : '开始阅读';
    final chapter = _resumeChapter ?? 0;
    final saved = state.positionFor(novel.id);
    final title = novel.readingTitleFor(
      chapter,
      paragraph: saved?.paragraphIndex ?? 0,
      offset: saved?.textOffset ?? 0,
    );
    final volume = novel.chapters[chapter].volumeTitle;
    return '$action · ${volume.isEmpty ? '' : '$volume · '}$title';
  }

  String get _chapterCountLabel {
    final unit = novel.navigation?.entries.isNotEmpty == true ? '项' : '章';
    return '${novel.directory.length} $unit';
  }

  String get _directoryCountLabel {
    final volumes = NovelVolume.of(
      novel.directoryChapters,
    ).where((volume) => volume.title.isNotEmpty).length;
    return '${volumes > 0 ? '$volumes 卷 · ' : ''}$_chapterCountLabel';
  }

  Widget _cacheReactive(Widget Function() builder) {
    if (repository case final OfflineNovelRepository offline) {
      if (!isLocalBook(novel.id)) {
        return AnimatedBuilder(
          animation: offline.bookChanges(novel.id),
          builder: (context, _) => builder(),
        );
      }
    }
    return builder();
  }

  bool _isCached(int chapterId) =>
      repository is OfflineNovelRepository &&
      !isLocalBook(novel.id) &&
      (repository as OfflineNovelRepository).cache
              .book(novel.id)
              ?.chapterBytes
              .containsKey(chapterId) ==
          true;

  String? _cacheLabel(Set<int> chapters) {
    if (repository is! OfflineNovelRepository ||
        isLocalBook(novel.id) ||
        chapters.isEmpty) {
      return null;
    }
    final count = chapters.where(_isCached).length;
    return count == chapters.length
        ? '已缓存'
        : count > 0
        ? '已缓存 $count / ${chapters.length}'
        : '未缓存';
  }

  Widget _volumeRow(BuildContext context, NovelVolume volume) {
    final expanded = _expandedVolumes.contains(volume.key);
    final ids = novel.directory
        .skip(volume.start)
        .take(volume.length)
        .map((entry) => entry.target.chapterId)
        .toSet();
    return _cacheReactive(() {
      final cached = _cacheLabel(ids);
      return Semantics(
        expanded: expanded,
        child: JellyTapSurface(
          key: ValueKey('detail-volume-${volume.key}'),
          onTap: () => _changeDirectory(() {
            if (!_expandedVolumes.add(volume.key)) {
              _expandedVolumes.remove(volume.key);
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: .7,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        volume.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 5),
                      AppText(
                        '${volume.length} ${novel.navigation?.entries.isNotEmpty == true ? '项' : '章'}${cached == null ? '' : ' · $cached'}',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (cached == '已缓存') ...[
                  const SizedBox(width: 12),
                  ArchiveIcon(
                    CupertinoIcons.check_mark,
                    key: ValueKey('detail-volume-cached-${volume.key}'),
                    size: 17,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
                const SizedBox(width: 14),
                AnimatedRotation(
                  turns: expanded ? .25 : 0,
                  duration: _reduceMotion ? Duration.zero : NovelMotion.enter,
                  curve: NovelMotion.ease,
                  child: ArchiveIcon(
                    CupertinoIcons.chevron_right,
                    size: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _chapterRow(BuildContext context, int index) {
    final entry = novel.directory[index];
    final chapter = entry.chapter >= 0 && entry.chapter < novel.chapters.length
        ? novel.chapters[entry.chapter]
        : null;
    final current = _resumeDirectory == index;
    return _cacheReactive(
      () => JellyTapSurface(
        key: ValueKey('detail-directory-entry-$index'),
        onTap: () => _openReader(
          context,
          entry.chapter,
          target: novel.navigation?.entries.isNotEmpty == true
              ? entry.target
              : null,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: .7,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 36,
                child: AppText(
                  (index + 1).toString().padLeft(2, '0'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      entry.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    if (current) ...[
                      const SizedBox(height: 4),
                      AppText(
                        '上次阅读',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (chapter?.isLocked == true) ...[
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: .8),
                      width: .7,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    child: AppText(
                      'VIP',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
              if (_isCached(entry.target.chapterId)) ...[
                const SizedBox(width: 10),
                ArchiveIcon(
                  CupertinoIcons.check_mark,
                  key: ValueKey('detail-chapter-cached-$index'),
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
              const SizedBox(width: 12),
              const ArchiveIcon(CupertinoIcons.chevron_right, size: 13),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => ArchiveHeaderBar(
    leading: GlassIconButton(
      icon: CupertinoIcons.back,
      label: '返回',
      onPressed: _sourceSwitching
          ? null
          : () {
              if (!LibraryWorkspace.close(context)) Navigator.pop(context);
            },
    ),
    title: const AppText(
      '图书详情',
      style: TextStyle(fontSize: 18, height: 1.2, fontWeight: FontWeight.w700),
    ),
    actions: [
      if (_sourceSwitching || _refreshing)
        GlassIconButton.custom(
          key: const ValueKey('detail-busy'),
          label: _sourceSwitching ? '正在换源' : '正在刷新详情',
          onPressed: null,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CupertinoActivityIndicator(radius: 9),
          ),
        )
      else
        GlassMenuAnchor(
          child: Builder(
            builder: (anchor) => GlassIconButton(
              key: const ValueKey('detail-actions'),
              icon: CupertinoIcons.ellipsis,
              label: '更多',
              onPressed: () => _openDetailActions(anchor),
            ),
          ),
        ),
    ],
  );

  Future<void> _openDetailActions(BuildContext anchor) async {
    final offline = repository is OfflineNovelRepository
        ? repository as OfflineNovelRepository
        : null;
    final saved = offline?.cache.book(novel.id);
    final bookUrl = novel.source?.bookUrl.trim() ?? '';
    final onlineActions = !isLocalBook(novel.id) && !isLoading && loadError == null;
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: _reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onlineActions)
            GlassMenuItem(
              key: const ValueKey('detail-refresh'),
              label: '刷新详情',
              icon: CupertinoIcons.refresh,
              onPressed: () => Navigator.pop(menu, 'refresh'),
            ),
          if (onlineActions && novel.chapters.isNotEmpty)
            GlassMenuItem(
              key: const ValueKey('detail-cache'),
              order: 1,
              label: '缓存图书',
              icon: CupertinoIcons.cloud_download,
              onPressed: () => Navigator.pop(menu, 'cache'),
            ),
          if (onlineActions && offline != null)
            GlassMenuItem(
              key: const ValueKey('detail-clear-cache'),
              order: 2,
              label: saved == null || saved.bytes <= 0
                  ? '清除缓存'
                  : '清除缓存 · ${formatCacheBytes(saved.bytes)}',
              icon: CupertinoIcons.trash,
              onPressed: () => Navigator.pop(menu, 'clear'),
            ),
          if (onlineActions && novel.source != null)
            GlassMenuItem(
              key: const ValueKey('detail-switch-source'),
              order: 3,
              label: '换源',
              icon: CupertinoIcons.arrow_swap,
              onPressed: () => Navigator.pop(menu, 'source'),
            ),
          if (onlineActions && bookUrl.isNotEmpty)
            GlassMenuItem(
              order: 4,
              label: '复制书籍链接',
              icon: CupertinoIcons.doc_on_doc,
              onPressed: () => Navigator.pop(menu, 'copy'),
            ),
          GlassMenuItem(
            key: const ValueKey('detail-change-cover'),
            order: 5,
            label: '更换封面',
            icon: CupertinoIcons.photo,
            onPressed: () => Navigator.pop(menu, 'cover'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'refresh':
        await _refreshDetail();
      case 'cache':
        await _openCache();
      case 'clear':
        await _clearCache();
      case 'source':
        await _openSourceSwitch();
      case 'copy':
        await _copyBookLink(bookUrl);
      case 'cover':
        await _changeCover();
    }
  }

  Future<void> _changeCover() async {
    final book = novel;
    final offline = repository is OfflineNovelRepository
        ? repository as OfflineNovelRepository
        : null;
    final store = PersonalCovers.shared;
    final choice = await showJellySheet<String>(
      context: context,
      reduceMotion: _reduceMotion,
      heightFactor: .82,
      maxWidth: 720,
      builder: (_) => ChangeCoverSheet(
        book: book,
        library: _bookSources,
        offline: offline?.offline ?? false,
        reduceMotion: _reduceMotion,
      ),
    );
    if (!mounted || choice == null) return;
    try {
      final local = isLocalBook(book.id) ? offline?.local : null;
      if (local != null && choice != PersonalCovers.defaultCover) {
        final updated = choice == PersonalCovers.original
            ? await local.restoreCover(book.id)
            : await local.setCover(book.id, (await store.file(choice)).path);
        await store.select(book.id, null);
        await state.setShelfMembership(book.id, state.contains(book.id), novel: updated);
        await store.releaseUnused(choice);
      } else {
        final restore = choice == PersonalCovers.original &&
            book.source?.customCoverUrl.isNotEmpty != true;
        await store.select(book.id, restore ? null : choice);
      }
      if (mounted) {
        setState(() {});
        showNovelFeedback(context, '封面已更新');
      }
    } on Object {
      if (mounted) showNovelFeedback(context, '封面保存失败，请重试');
    }
  }

  Future<void> _refreshDetail() async {
    if (_refreshing || _sourceSwitching || isLoading || loadError != null) {
      return;
    }
    final offline = repository is OfflineNovelRepository
        ? repository as OfflineNovelRepository
        : null;
    if (offline?.offline == true) {
      showNovelFeedback(context, '当前无网络连接，无法刷新书籍详情', haptic: HapticCue.error);
      return;
    }
    setState(() => _refreshing = true);
    try {
      final detail = await repository.detail(novel);
      final chapters = await repository.chapters(novel.id);
      final loaded = detail.withChapters(chapters);
      if (!mounted) return;
      setState(() {
        _switchedNovel = loaded;
        _directoryBook = null;
      });
      try {
        await state.rememberNovel(loaded);
      } on Object {
        // 刷新到的内容仍可阅读，元数据写入失败留待下次加载重试。
      }
      if (mounted) {
        showNovelFeedback(context, '书籍详情已刷新', haptic: HapticCue.success);
      }
    } on Object {
      if (mounted) {
        showNovelFeedback(context, '刷新失败，请稍后重试', haptic: HapticCue.error);
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _clearCache() async {
    if (repository is! OfflineNovelRepository) return;
    final offline = repository as OfflineNovelRepository;
    final saved = offline.cache.book(novel.id);
    final caching = offline.jobFor(novel.id)?.active == true;
    if (saved == null && !caching) {
      showNovelFeedback(context, '「${novel.title}」暂无离线缓存');
      return;
    }
    final size = saved == null || saved.bytes <= 0
        ? ''
        : '（${formatCacheBytes(saved.bytes)}）';
    final confirmed = await confirmNovelAction(
      context,
      title: '删除离线缓存？',
      message:
          '「${novel.title}」的离线正文、插图与目录缓存$size会从本机移除，书架、阅读进度和书签保留，也不需要重新导入书籍。正在进行的缓存会同时停止。',
      confirmLabel: '删除离线缓存',
      reduceMotion: _reduceMotion,
    );
    if (!confirmed || !mounted) return;
    try {
      await offline.removeCachedBook(novel.id);
      if (mounted) {
        showNovelFeedback(
          context,
          '已清除「${novel.title}」的离线缓存',
          haptic: HapticCue.success,
        );
      }
    } on Object {
      if (mounted) {
        showNovelFeedback(context, '缓存操作失败，请重试', haptic: HapticCue.error);
      }
    }
  }

  Future<void> _copyBookLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      showNovelFeedback(context, '书籍链接已复制', haptic: HapticCue.success);
    }
  }

  Future<void> _openCache() async {
    if (_cacheOpen || repository is! OfflineNovelRepository) return;
    _cacheOpen = true;
    try {
      await showJellySheet<void>(
        context: context,
        reduceMotion: _reduceMotion,
        maxWidth: 720,
        builder: (_) => OfflineVolumeCacheSheet(
          repository: repository as OfflineNovelRepository,
          novel: novel,
        ),
      );
    } finally {
      _cacheOpen = false;
    }
  }

  Future<void> _openSourceSwitch() async {
    if (_sourceSwitching || _sourcePickerOpen) return;
    final current = novel;
    final sources = _bookSources;
    if (sources == null) {
      showNovelFeedback(context, '当前版本未启用书源，无法换源', haptic: HapticCue.error);
      return;
    }
    if (repository is OfflineNovelRepository &&
        (repository as OfflineNovelRepository).offline) {
      showNovelFeedback(context, '当前无网络连接，无法换源', haptic: HapticCue.error);
      return;
    }
    Novel? candidate;
    _sourcePickerOpen = true;
    try {
      await sources.prepare();
      if (!mounted) return;
      if (!sources.engineAvailable) {
        showNovelFeedback(context, '书源引擎暂不可用，请稍后重试', haptic: HapticCue.error);
        return;
      }
      candidate = await showJellySheet<Novel>(
        context: context,
        reduceMotion: _reduceMotion,
        heightFactor: .82,
        maxWidth: 720,
        builder: (_) => SourceSwitchSheet(
          novel: current,
          repository: repository,
          library: sources,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        showNovelFeedback(
          context,
          error is FormatException ? error.message : '书源列表暂时无法打开，请稍后重试',
          haptic: HapticCue.error,
        );
      }
      return;
    } finally {
      _sourcePickerOpen = false;
    }
    if (!mounted || candidate == null) return;
    final chosen = candidate;
    setState(() => _sourceSwitching = true);
    try {
      final switched = repository is OfflineNovelRepository
          ? await (repository as OfflineNovelRepository).switchSource(
              current,
              chosen,
            )
          : await sources.switchSource(current, chosen);
      if (mounted) await _applySourceSwitch(current, switched);
    } on Object catch (error) {
      if (mounted) {
        showNovelFeedback(
          context,
          error is FormatException ? error.message : '换源失败，请稍后重试',
          haptic: HapticCue.error,
        );
      }
    } finally {
      if (mounted) setState(() => _sourceSwitching = false);
    }
  }

  Future<void> _applySourceSwitch(Novel previous, Novel switched) async {
    await state.applySourceSwitch(previous, switched);
    if (!mounted) return;
    setState(() {
      _switchedNovel = switched;
      _expandedVolumes.clear();
      _directoryVolumeKeys.clear();
      _directoryBook = null;
      _summaryExpanded = false;
      _catalogueExpanded = false;
      _resumeChapter = null;
      _resumeDirectory = null;
    });
    widget.onSourceSwitched?.call(switched);
    if (mounted) {
      showNovelFeedback(
        context,
        '已切换到「${switched.source?.sourceName ?? '新书源'}」',
        haptic: HapticCue.success,
      );
    }
  }

  Future<void> _openReader(
    BuildContext context,
    int chapter, {
    BookReadingTarget? target,
  }) async {
    if (target != null && widget.onReadTarget != null) {
      widget.onReadTarget!(target);
      return;
    }
    if (widget.onRead case final read?) {
      read(chapter);
      return;
    }
    if (_readerOpening || !mounted || !context.mounted) return;
    _readerOpening = true;
    try {
      await pushNovelPage<void>(
        context,
        ReaderPage(
          novel: novel,
          state: state,
          repository: repository,
          initialChapter: chapter,
          showOpening: widget.showOpening,
          promptAddToShelfOnExit: widget.promptAddToShelfOnExit,
          initialPosition: target == null
              ? null
              : _bookTargetPosition(novel, target),
          onSourceSwitched: (book) {
            if (!mounted) return;
            setState(() {
              _switchedNovel = book;
              _expandedVolumes.clear();
              _directoryVolumeKeys.clear();
              _directoryBook = null;
              _summaryExpanded = false;
              _catalogueExpanded = false;
              _resumeChapter = null;
              _resumeDirectory = null;
            });
            widget.onSourceSwitched?.call(book);
          },
        ),
        reduceMotion: state.reduceMotion,
      );
    } finally {
      _readerOpening = false;
      // Reader exit persists its final anchor without broadcasting scroll
      // changes. Refresh the label and directory marker once, without replay.
      if (mounted) setState(() {});
    }
  }
}

ReadingPosition _bookTargetPosition(Novel novel, BookReadingTarget target) {
  // A chapter-start link includes its heading. Aligning its first body
  // paragraph instead would scroll that heading behind the fixed location bar.
  // Inner links retain source anchors; saved resume positions bypass this path.
  final chapterStart = target.paragraph == 0 && target.offset == 0;
  return ReadingPosition(
    chapter: novel.chapters.indexWhere((c) => c.id == target.chapterId),
    chapterId: target.chapterId,
    offset: 0,
    fraction: 0,
    fontSize: 19,
    width: 0,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
    paragraphIndex: chapterStart ? null : target.paragraph,
    textOffset: chapterStart ? null : target.offset,
  );
}

class SourceSwitchSheet extends StatefulWidget {
  const SourceSwitchSheet({
    super.key,
    required this.novel,
    required this.repository,
    this.library,
  });
  final Novel novel;
  final NovelRepository repository;
  final BookSourceLibrary? library;

  @override
  State<SourceSwitchSheet> createState() => _SourceSwitchSheetState();
}

class _SourceSwitchSheetState extends State<SourceSwitchSheet> {
  var _items = const <Novel>[];
  bool _loading = true;
  bool _stopped = false;
  late bool _checkAuthor = widget.library?.changeSourceCheckAuthor ?? false;
  Object? _error;
  int _completed = 0;
  int _total = 0;
  int _failed = 0;
  int _generation = 0;
  final _filter = TextEditingController();
  String _filterQuery = '';
  final _coverQueue = <Novel>[];
  final _coverRequested = <int>{};
  int _coverLoads = 0;
  static const _coverConcurrency = 3;
  late BookSourceSearchScope _scope =
      widget.library?.changeSourceScope ?? const BookSourceSearchScope.all();

  String get _searchTerm {
    final sourceTitle = widget.novel.source?.title.trim() ?? '';
    return sourceSearchKeyword(
      sourceTitle.isEmpty ? widget.novel.title : sourceTitle,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_search(reset: false));
  }

  @override
  void dispose() {
    _generation++;
    final library = widget.library;
    if (library != null) {
      unawaited(library.cancelSourceCandidateSearch());
    }
    _filter.dispose();
    _coverQueue.clear();
    _coverRequested.clear();
    super.dispose();
  }

  void _stopSearch() {
    _generation++;
    final library = widget.library;
    if (library != null) {
      unawaited(library.cancelSourceCandidateSearch());
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _stopped = true;
      _error = null;
    });
  }

  Future<void> _chooseScope() async {
    final library = widget.library;
    if (library == null) return;
    final applied = await showBookSourceScopeSheet(
      context: context,
      library: library,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      initialScope: _scope,
      persist: false,
    );
    if (!mounted || applied == null) return;
    setState(() => _scope = applied);
    try {
      await library.setChangeSourceScope(applied);
    } on Object {
      // 偏好写入失败时本次仍按所选范围搜索。
    }
    await _search();
  }

  Future<void> _search({bool reset = true}) async {
    final generation = ++_generation;
    if (reset) {
      _coverQueue.clear();
      _coverRequested.clear();
      setState(() {
        _items = const [];
        _loading = true;
        _stopped = false;
        _error = null;
        _completed = 0;
        _total = 0;
        _failed = 0;
      });
    } else {
      _loading = true;
      _stopped = false;
      _error = null;
      _failed = 0;
    }
    try {
      final library = widget.library;
      if (library != null) {
        final result = await library.searchSourceCandidates(
          widget.novel,
          checkAuthor: _checkAuthor,
          scope: _scope,
          current: () => mounted && generation == _generation,
          onProgress: (progress) {
            if (!mounted || generation != _generation) return;
            setState(() {
              _items = List<Novel>.unmodifiable(progress.items);
              _completed = progress.completedSources;
              _total = progress.totalSources;
            });
          },
        );
        if (!mounted || generation != _generation) return;
        setState(() {
          _items = result.items;
          _completed = result.totalSources;
          _total = result.totalSources;
          _failed = result.failedSources;
          _loading = false;
        });
        return;
      }
      final repository = widget.repository;
      if (repository is ProgressiveNovelSearch) {
        final page = await (repository as ProgressiveNovelSearch)
            .searchFilteredPageProgressively(
              _searchTerm,
              field: BookSearchField.title,
              refresh: true,
              current: () => mounted && generation == _generation,
              onProgress: (progress) {
                if (!mounted || generation != _generation) return;
                setState(() {
                  _items = _candidates(progress.items);
                  _completed = progress.completedSources;
                  _total = progress.totalSources;
                });
              },
            );
        if (!mounted || generation != _generation) return;
        setState(() {
          _items = _candidates(page.items);
          _loading = false;
          if (_total > 0) _completed = _total;
        });
      } else {
        final page = await repository.searchFilteredPage(
          _searchTerm,
          field: BookSearchField.title,
          refresh: true,
        );
        if (!mounted || generation != _generation) return;
        setState(() {
          _items = _candidates(page.items);
          _loading = false;
        });
      }
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  List<Novel> _candidates(Iterable<Novel> books) {
    final current = widget.novel.source;
    final author = widget.novel.author.trim();
    final title = sourceSearchTitleKey(_searchTerm);
    final seen = <String>{};
    final result = <Novel>[];
    for (final book in books) {
      final ref = book.source;
      if (ref == null) continue;
      if (_checkAuthor &&
          author.isNotEmpty &&
          !sameSourceAuthor(book.author, author)) {
        continue;
      }
      if (title.isNotEmpty && sourceSearchTitleKey(book.title) != title) {
        continue;
      }
      if (current != null &&
          ref.sourceKey == current.sourceKey &&
          ref.bookUrl == current.bookUrl) {
        continue;
      }
      final key = '${ref.sourceKey}\u0000${ref.bookUrl}';
      if (!seen.add(key)) continue;
      result.add(book);
    }
    final library = widget.library;
    if (library != null) {
      sortSourceCandidates(result, library.sources);
    } else {
      result.sort(
        (a, b) =>
            (a.source?.sourceName ?? '').compareTo(b.source?.sourceName ?? ''),
      );
    }
    return result;
  }

  void _requestCover(Novel book) {
    if (book.coverUrl?.trim().isNotEmpty ?? false) return;
    if (!_coverRequested.add(book.id)) return;
    _coverQueue.add(book);
    _drainCovers();
  }

  void _drainCovers() {
    while (_coverLoads < _coverConcurrency && _coverQueue.isNotEmpty) {
      final book = _coverQueue.removeAt(0);
      _coverLoads++;
      unawaited(_loadCover(book));
    }
  }

  Future<void> _loadCover(Novel book) async {
    final generation = _generation;
    try {
      final detail = await widget.repository.detail(book);
      if (!mounted || generation != _generation) return;
      final cover = detail.coverUrl?.trim() ?? '';
      if (cover.isEmpty) return;
      setState(() {
        _items = [
          for (final item in _items)
            if (item.id == book.id) item.withCoverUrl(cover) else item,
        ];
      });
    } on Object {
      // 详情暂时读不到时保留文字封面，不影响候选切换。
    } finally {
      _coverLoads = math.max(0, _coverLoads - 1);
      if (mounted && generation == _generation) _drainCovers();
    }
  }

  List<Novel> get _visibleItems {
    final query = _filterQuery.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return [
      for (final book in _items)
        if (book.title.toLowerCase().contains(query) ||
            book.author.toLowerCase().contains(query) ||
            (book.source?.sourceName.toLowerCase().contains(query) ?? false))
          book,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final currentName = widget.novel.source?.sourceName ?? '当前书源';
    final library = widget.library;
    final visible = _visibleItems;
    final scopeLabel = library == null ? '' : _scope.describe(library.sources);
    final status = _loading
        ? _total > 0
              ? '正在搜索书源 · $_completed / $_total'
              : '正在搜索书源'
        : _items.isEmpty
        ? _stopped
              ? '搜索已停止 · 当前：$currentName'
              : '当前：$currentName · 只显示同名书籍'
        : visible.isEmpty
        ? '没有匹配筛选条件的候选 · 当前：$currentName'
        : '${_stopped ? '搜索已停止 · ' : ''}找到 ${visible.length} 个候选'
              '${visible.length == _items.length ? '' : ' / 共 ${_items.length} 个'}'
              ' · 当前：$currentName';
    return SizedBox(
      height: math.min(650, MediaQuery.sizeOf(context).height * .76),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 14, 4),
            child: Row(
              children: [
                const Expanded(
                  child: AppText(
                    '换源',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (library != null)
                  GlassIconButton(
                    icon: CupertinoIcons.line_horizontal_3_decrease,
                    label: '设置换源搜索范围',
                    onPressed: _chooseScope,
                  ),
                GlassIconButton(
                  icon: _loading
                      ? CupertinoIcons.pause
                      : CupertinoIcons.refresh,
                  label: _loading ? '停止换源搜索' : '重新搜索换源候选',
                  onPressed: _loading ? _stopSearch : _search,
                ),
                GlassIconButton(
                  icon: CupertinoIcons.xmark,
                  label: '关闭换源列表',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: AppText(
              scopeLabel.isEmpty ? status : '$status · 范围：$scopeLabel',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: AppSearchField(
              inputKey: const ValueKey('source-candidate-filter'),
              controller: _filter,
              hint: '筛选书名、作者或书源',
              onChanged: (value) => setState(() => _filterQuery = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText(
                        '校验作者',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AppText(
                        widget.novel.author.trim().isEmpty
                            ? '当前书籍没有作者信息'
                            : '只保留作者与「${widget.novel.author}」一致的候选',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
                AppControls.toggle(
                  context,
                  value: _checkAuthor,
                  onChanged: (value) async {
                    if (_checkAuthor == value) return;
                    setState(() => _checkAuthor = value);
                    final library = widget.library;
                    if (library != null) {
                      try {
                        await library.setChangeSourceCheckAuthor(value);
                      } on Object {
                        // 偏好写入失败时仍按本次选择过滤。
                      }
                    }
                    await _search();
                  },
                ),
              ],
            ),
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final visible = _visibleItems;
    if (_items.isEmpty && _loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(),
            const SizedBox(height: 12),
            AppText(
              _total > 0 ? '正在搜索同名书籍 · $_completed / $_total' : '正在搜索同名书籍',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty && _error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppText('换源搜索失败'),
            const SizedBox(height: 6),
            GlassTextButton(onPressed: _search, child: const AppText('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      final muted = Theme.of(context).colorScheme.onSurfaceVariant;
      final noSources = _total == 0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText(noSources ? '没有可用书源' : '没有找到同名书籍'),
              if (_failed > 0) ...[
                const SizedBox(height: 8),
                AppText(
                  '$_failed 个书源搜索失败，可稍后重试',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
              if (!noSources &&
                  _checkAuthor &&
                  widget.novel.author.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                GlassTextButton(
                  onPressed: () async {
                    setState(() => _checkAuthor = false);
                    await _search();
                  },
                  child: const AppText('关闭作者校验后重试'),
                ),
              ],
              if (!_scope.isAll) ...[
                const SizedBox(height: 8),
                GlassTextButton(
                  onPressed: () async {
                    const all = BookSourceSearchScope.all();
                    setState(() => _scope = all);
                    final library = widget.library;
                    if (library != null) {
                      try {
                        await library.setChangeSourceScope(all);
                      } on Object {
                        // 偏好写入失败时本次仍按全部书源搜索。
                      }
                    }
                    await _search();
                  },
                  child: const AppText('改用全部书源搜索'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppText('没有匹配筛选条件的候选'),
              const SizedBox(height: 8),
              GlassTextButton(
                onPressed: () {
                  _filter.clear();
                  setState(() => _filterQuery = '');
                },
                child: const AppText('清空筛选'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final book = visible[index];
        final author = book.author.trim();
        final sourceName = book.source?.sourceName ?? '';
        final sameAuthor =
            _checkAuthor &&
            author.isNotEmpty &&
            author == widget.novel.author.trim();
        final parts = <String>[
          if (author.isNotEmpty) author,
          if (sourceName.isNotEmpty) sourceName,
          if (sameAuthor) '作者一致',
        ];
        _requestCover(book);
        return NovelRow(
          key: ValueKey(
            'source-candidate-${book.source?.sourceKey}-${book.source?.bookUrl}',
          ),
          novel: book,
          supportingText: parts.isEmpty ? null : parts.join(' · '),
          trailing: AppText(
            book.chapterCount > 0 ? '${book.chapterCount} 章' : '',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          onTap: () => Navigator.pop(context, book),
        );
      },
    );
  }
}

class _PendingBookMatchSheet extends StatefulWidget {
  const _PendingBookMatchSheet({
    required this.pending,
    required this.repository,
    required this.library,
  });

  final Novel pending;
  final NovelRepository repository;
  final BookSourceLibrary? library;

  @override
  State<_PendingBookMatchSheet> createState() => _PendingBookMatchSheetState();
}

class _PendingBookMatchSheetState extends State<_PendingBookMatchSheet> {
  var _items = const <Novel>[];
  bool _loading = true;
  bool _autoSelected = false;
  late bool _checkAuthor = widget.pending.author.trim().isNotEmpty;
  Object? _error;
  int _completed = 0;
  int _total = 0;
  int _generation = 0;

  String get _term => sourceSearchKeyword(widget.pending.title);

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _generation++;
    unawaited(widget.library?.cancelSourceCandidateSearch());
    unawaited(
      (libraryRepositoryOf(widget.repository) ?? widget.repository)
          .cancelSearch(),
    );
    super.dispose();
  }

  Future<Novel?> _direct(BookSourceLibrary library) async {
    final source = widget.pending.source;
    if (source == null || source.bookUrl.trim().isEmpty) return null;
    try {
      return await library.importBookReference(
        sourceKey: source.sourceKey,
        sourceName: source.sourceName,
        bookUrl: source.bookUrl,
        title: widget.pending.title,
        author: widget.pending.author,
        coverUrl: source.coverUrl,
        customCoverUrl: source.customCoverUrl,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _search() async {
    final generation = ++_generation;
    setState(() {
      _items = const [];
      _loading = true;
      _autoSelected = false;
      _error = null;
      _completed = 0;
      _total = 0;
    });
    if (_term.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    Object? sourceError;
    final library = widget.library;
    if (library != null) {
      try {
        await library.prepare();
        if (!mounted || generation != _generation) return;
        if (library.engineAvailable) {
          final direct = await _direct(library);
          if (!mounted || generation != _generation) return;
          if (direct != null) {
            _select(direct);
            return;
          }
          final result = await library.searchSourceCandidates(
            widget.pending,
            checkAuthor: _checkAuthor,
            current: () => mounted && generation == _generation,
            onProgress: (progress) {
              if (!mounted || generation != _generation) return;
              setState(() {
                _items = _candidates(progress.items);
                _completed = progress.completedSources;
                _total = progress.totalSources;
              });
            },
          );
          if (!mounted || generation != _generation) return;
          final items = _candidates(result.items);
          if (items.isNotEmpty) {
            setState(() {
              _items = items;
              _loading = false;
              _completed = result.totalSources;
              _total = result.totalSources;
            });
            _autoSelect(items);
            return;
          }
        }
      } on Object catch (error) {
        sourceError = error;
      }
    }
    try {
      final repository =
          libraryRepositoryOf(widget.repository) ?? widget.repository;
      final page = await repository.searchFilteredPage(
        _term,
        field: BookSearchField.title,
        refresh: true,
      );
      if (!mounted || generation != _generation) return;
      final items = _candidates(page.items);
      setState(() {
        _items = items;
        _loading = false;
        _error = items.isEmpty ? sourceError : null;
      });
      _autoSelect(items);
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = sourceError ?? error;
      });
    }
  }

  List<Novel> _candidates(Iterable<Novel> books) {
    final titleKey = sourceSearchTitleKey(widget.pending.title);
    final author = widget.pending.author.trim();
    final seen = <int>{};
    final result = <Novel>[];
    for (final book in books) {
      if (!seen.add(book.id)) continue;
      if (titleKey.isNotEmpty && sourceSearchTitleKey(book.title) != titleKey) {
        continue;
      }
      if (_checkAuthor &&
          author.isNotEmpty &&
          !sameSourceAuthor(book.author, author)) {
        continue;
      }
      result.add(book);
    }
    final library = widget.library;
    if (library != null) {
      sortSourceCandidates(result, library.sources);
    } else {
      result.sort(
        (a, b) =>
            (a.source?.sourceName ?? '').compareTo(b.source?.sourceName ?? ''),
      );
    }
    return result;
  }

  void _autoSelect(List<Novel> items) {
    if (_autoSelected || items.length != 1) return;
    _autoSelected = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _select(items.single);
    });
  }

  void _select(Novel book) {
    if (!mounted) return;
    Navigator.of(context).pop(book);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final status = _loading
        ? _total > 0
              ? '正在搜索书源 · $_completed / $_total'
              : '正在搜索书源和文库'
        : _items.isEmpty
        ? '没有找到匹配书籍'
        : '找到 ${_items.length} 个候选';
    return SizedBox(
      height: math.min(650, MediaQuery.sizeOf(context).height * .8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 14, 4),
            child: Row(
              children: [
                const Expanded(
                  child: AppText(
                    '匹配书源',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                GlassIconButton(
                  icon: _loading
                      ? CupertinoIcons.pause
                      : CupertinoIcons.refresh,
                  label: _loading ? '停止匹配搜索' : '重新搜索',
                  onPressed: _loading
                      ? () {
                          _generation++;
                          unawaited(
                            widget.library?.cancelSourceCandidateSearch(),
                          );
                          unawaited(
                            (libraryRepositoryOf(widget.repository) ??
                                    widget.repository)
                                .cancelSearch(),
                          );
                          setState(() => _loading = false);
                        }
                      : _search,
                ),
                GlassIconButton(
                  icon: CupertinoIcons.xmark,
                  label: '关闭匹配',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: AppText(
              '《${widget.pending.title}》'
              '${widget.pending.author.isEmpty ? '' : ' / ${widget.pending.author}'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText(
                        '校验作者',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AppText(
                        widget.pending.author.trim().isEmpty
                            ? '当前书籍没有作者信息'
                            : '只保留作者与「${widget.pending.author}」一致的候选',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
                AppControls.toggle(
                  context,
                  value: _checkAuthor,
                  onChanged: (value) async {
                    if (_checkAuthor == value) return;
                    setState(() => _checkAuthor = value);
                    await _search();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Semantics(
              liveRegion: true,
              child: AppText(
                status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_items.isEmpty && _loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(),
            const SizedBox(height: 12),
            AppText(
              _total > 0 ? '正在搜索同名书籍 · $_completed / $_total' : '正在搜索同名书籍',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      final muted = Theme.of(context).colorScheme.onSurfaceVariant;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText(_error == null ? '没有找到匹配书籍' : '搜索失败，请稍后重试'),
              if (_checkAuthor && widget.pending.author.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                GlassTextButton(
                  onPressed: () async {
                    setState(() => _checkAuthor = false);
                    await _search();
                  },
                  child: const AppText('关闭作者校验后重试'),
                ),
              ],
              const SizedBox(height: 8),
              GlassTextButton(onPressed: _search, child: const AppText('重新搜索')),
              if (_error != null) ...[
                const SizedBox(height: 8),
                AppText(
                  '可以关闭作者校验或稍后重试',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final book = _items[index];
        return NovelRow(
          key: ValueKey('pending-match-${book.id}'),
          novel: book,
          supportingText: book.source?.sourceName ?? '文库',
          trailing: AppText(
            book.chapterCount > 0 ? '${book.chapterCount} 章' : '',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          onTap: () => _select(book),
        );
      },
    );
  }
}

typedef _PreparedReaderChapter = ({
  ReaderContent content,
  ReaderContent unfiltered,
});

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
    required this.initialChapter,
    this.directEntry = false,
    this.showOpening = false,
    this.promptAddToShelfOnExit = true,
    this.initialBookmark,
    this.initialPosition,
    this.dictionaryLauncher,
    this.verifiedReadingElapsed,
    this.onSourceSwitched,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  final int initialChapter;
  final bool directEntry;
  final bool showOpening;
  final bool promptAddToShelfOnExit;
  final ReaderBookmark? initialBookmark;
  final ReadingPosition? initialPosition;
  final Future<bool> Function(String selectedText)? dictionaryLauncher;
  final ValueChanged<Novel>? onSourceSwitched;

  /// Deterministic monotonic clock for causal reader integration fixtures.
  @visibleForTesting
  final Duration Function()? verifiedReadingElapsed;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late bool _opening = widget.showOpening;

  ReaderPreferences get _readerPreferences =>
      widget.state.readerPreferencesFor(widget.novel.id);
  double get _fontSize => widget.state.readerFontSizeFor(widget.novel.id);
  late VoidCallback _releaseReadingPosition;
  ReaderHandoffNavigation? _handoffNavigation;
  VoidCallback? _releaseHandoffTarget;
  double get _lineHeight => widget.state.readerLineHeightFor(widget.novel.id);
  String get _readerFontId => widget.state.readerFontIdFor(widget.novel.id);
  String? get _readerFontFamily =>
      widget.state.readerFontFamilyFor(widget.novel.id);
  late final _bookFontReady = _prepareBookFont();
  ReplaceRuleStore get _replaceRules => ReplaceRuleStore.shared;
  bool get _replaceRulesActive => widget.state.replaceRulesEnabledFor(
    widget.novel.id,
    fallback: _replaceRules.enabled,
  );
  String get _replaceRuleSignature =>
      _replaceRulesActive ? _replaceRules.signature : 'off';
  Novel? _titleProjectionBase;
  Novel? _titleProjectionCache;
  String? _titleProjectionSignature;
  late String _replaceSignature;

  Novel get _displayBook {
    final base = _sourceBook;
    if (!_replaceRulesActive) return base;
    final signature = _replaceRuleSignature;
    if (identical(_titleProjectionBase, base) &&
        _titleProjectionSignature == signature) {
      return _titleProjectionCache ?? base;
    }
    _titleProjectionBase = base;
    _titleProjectionSignature = signature;
    final origin = ReplaceRuleStore.originFor(base);
    final rules = _replaceRules.rulesFor(
      titles: true,
      bookTitle: base.title,
      origin: origin,
    );
    if (rules.isEmpty) {
      _titleProjectionCache = base;
      return base;
    }
    String title(String value) =>
        _replaceRules.applyTitle(value, bookTitle: base.title, origin: origin);
    final navigation = base.navigation;
    final projected = Novel(
      id: base.id,
      title: base.title,
      author: base.author,
      genre: base.genre,
      summary: base.summary,
      colors: base.colors,
      chapters: [
        for (final chapter in base.chapters)
          NovelChapter(
            title(chapter.title),
            chapter.content,
            id: chapter.id,
            volumeId: chapter.volumeId,
            volumeTitle: title(chapter.volumeTitle),
            isLocked: chapter.isLocked,
            sourceUrl: chapter.sourceUrl,
            sourceNextUrl: chapter.sourceNextUrl,
          ),
      ],
      isComplete: base.isComplete,
      coverUrl: base.coverUrl,
      lastUpdate: base.lastUpdate,
      chapterCount: base.chapterCount,
      navigation: navigation == null
          ? null
          : BookNavigation([
              for (final entry in navigation.entries)
                BookNavigationEntry(
                  title(entry.title),
                  entry.target,
                  depth: entry.depth,
                ),
            ], targets: navigation.targets),
      source: base.source,
    );
    _titleProjectionCache = projected;
    return projected;
  }

  String _displayChapterTitle(String value) {
    if (!_replaceRulesActive) return value;
    return _replaceRules.applyTitle(
      value,
      bookTitle: _sourceBook.title,
      origin: ReplaceRuleStore.originFor(_sourceBook),
    );
  }

  Future<void> _prepareBookFont() async {
    try {
      await widget.state.fonts.ensureLoaded(_readerFontId);
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showNovelFeedback(context, '本书字体未能加载，请在阅读字体中重新选择');
        }
      });
    }
  }

  VoidCallback? _releaseFeedbackHeader, _dismissChromeHint;
  // Content, navigation and saved coordinates consume one adopted directory.
  // Local EPUB recovery may insert chapters before an existing stable ID.
  late Novel _readerBook = widget.novel;
  Novel? _detailSwitchedBook;
  late int _chapter = _sourceBook.chapters.isEmpty
      ? 0
      : widget.initialChapter.clamp(0, _sourceBook.chapters.length - 1);
  late Future<({ReaderContent? content, Object? error})> _content;
  ReaderContent? _currentContent;
  ReaderContent? _unfilteredContent;
  bool _illustrationsRefreshing = false;
  final _findMatch = ValueNotifier<ReaderMatch?>(null);
  final _bookmarkLanding = ValueNotifier<int?>(null);
  Timer? _bookmarkLandingTimer;
  bool _bookmarkLandingPending = false;
  Timer? _highlightTimer;
  // Stable chapter IDs/paragraph anchors own restoration; do not also walk
  // PageStorage and persist the viewport on every interrupted fling.
  final _scroll = ScrollController(keepScrollOffset: false);
  late final _followScroll = ReaderFollowScroll(_scroll);
  final _scrollStream = ReaderScrollStreamController<_PreparedReaderChapter>();
  final _emptyParagraphRegistry = ReaderParagraphRegistry();
  ReaderParagraphRegistry get _paragraphRegistry =>
      _scrollStream.registryFor(_chapter) ?? _emptyParagraphRegistry;
  final _paragraphWidgets =
      <(int, int, ReaderContent, ReaderParagraphRegistry, int), Widget>{};
  Object? _paragraphWidgetSpec;
  final _paged = ReaderPagedController();
  final _verticalGlyphs = ReaderGlyphCache();
  final _selection = ReaderSelectionController();
  final _contentTapSurface = ReaderTapSurfaceController();
  late ReaderMode _readerMode;
  late bool _chapterEntrance;
  bool get _paginated => _readerMode.paginated;
  ReadingPosition? _restorePending;
  bool _restoreQueued = false;
  bool _activityRestoring = false;
  bool get _restoring => _activityRestoring;
  set _restoring(bool value) {
    if (_activityRestoring == value) return;
    _activityRestoring = value;
    _syncReadingActivity();
  }

  bool _activityReady = false;
  bool get _ready => _activityReady;
  set _ready(bool value) {
    if (_activityReady == value) return;
    _activityReady = value;
    _syncReadingActivity();
  }

  int _paragraphCount = 0;
  bool _saveQueued = false;
  Timer? _idleSave;
  final _activityOverlays = <String>{};
  bool get _catalogueOpen => _activityOverlays.contains('catalogue');
  set _catalogueOpen(bool value) => _activityOverlay('catalogue', value);
  bool get _toolsOpen => _activityOverlays.contains('tools');
  set _toolsOpen(bool value) => _activityOverlay('tools', value);
  bool get _findOpen => _activityOverlays.contains('find');
  set _findOpen(bool value) => _activityOverlay('find', value);
  bool get _noteOpen => _activityOverlays.contains('note');
  set _noteOpen(bool value) => _activityOverlay('note', value);
  bool get _detailsOpen => _activityOverlays.contains('details');
  set _detailsOpen(bool value) => _activityOverlay('details', value);
  bool _sourceChanged = false;
  late ReadingActivitySession _readingActivity;
  late VerifiedReadingSession _verifiedReading;
  (int, int)? _pageAdvanceOrigin;
  double? _scrollAdvanceOrigin;
  bool _showingMoment = false;
  bool _exitInProgress = false;
  bool _completionPending = false;
  bool _activityAttached = false;
  bool _activityRouteCurrent = false;
  bool _activityForeground = true;
  bool _activityStartQueued = false;

  void _activityOverlay(String overlay, bool open) {
    if (_activityOverlays.contains(overlay) == open) return;
    if (open) {
      _activityOverlays.add(overlay);
    } else {
      _activityOverlays.remove(overlay);
    }
    _syncReadingActivity();
  }

  bool get _activityEligible =>
      _activityAttached &&
      _activityForeground &&
      _activityRouteCurrent &&
      _ready &&
      _currentContent?.paragraphs.isNotEmpty == true &&
      !_restoring &&
      !_sourceChanged &&
      _activityOverlays.isEmpty;

  bool get _verifiedEligible => _activityEligible && !_selection.value;

  void _syncReadingActivity() {
    if (!_activityAttached) return;
    if (!_verifiedEligible) {
      _verifiedReading.setActive(false);
      _pageAdvanceOrigin = null;
      _scrollAdvanceOrigin = null;
    }
    if (!_activityEligible) {
      _readingActivity.setActive(false);
    } else if ((!_readingActivity.active ||
            (_verifiedEligible && !_verifiedReading.active)) &&
        !_activityStartQueued) {
      // Begin only after the ready text has actually reached a painted frame.
      _activityStartQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _activityStartQueued = false;
        if (mounted && _activityAttached) {
          _readingActivity.setActive(_activityEligible);
          _verifiedReading.setActive(_verifiedEligible);
        }
      });
    }
  }

  void _armPageAdvance() {
    if (_verifiedEligible && _paged.ready) {
      _pageAdvanceOrigin = (_chapter, _paged.page);
    }
  }

  void _pagedReadingChanged() {
    final origin = _pageAdvanceOrigin;
    if (origin != null &&
        _verifiedEligible &&
        (_chapter != origin.$1 || _paged.page != origin.$2)) {
      _pageAdvanceOrigin = null;
      _verifiedReading.advance();
    }
    _saveWhenIdle();
  }

  Future<void> _completeReadingAtEnd() async {
    if (_completionPending ||
        !_verifiedEligible ||
        _chapter != _sourceBook.chapters.length - 1 ||
        !_verifiedReading.advance()) {
      return;
    }
    _completionPending = true;
    final book = _sourceBook;
    final completedAt = DateTime.now();
    try {
      await _verifiedReading.settled;
      final moments = widget.state.readingMoments;
      final alreadyCompleted = moments.moments.any(
        (event) => event.id == 'completion:${book.id}',
      );
      final coverPath = alreadyCompleted
          ? null
          : await captureReadingMomentCover(
              book: book,
              completedAt: completedAt,
            );
      try {
        await moments.completeBook(
          bookId: book.id,
          title: book.title,
          author: book.author,
          finished: isLocalBook(book.id) || book.isComplete,
          at: completedAt,
          coverPath: coverPath,
        );
      } catch (_) {
        await discardReadingMomentCover(
          bookId: book.id,
          completedAt: completedAt,
          coverPath: coverPath,
        );
        rethrow;
      }
      await _presentReadingMoment();
    } catch (_) {
      if (mounted) showNovelFeedback(context, '阅读纪念暂未保存，请稍后重试');
    } finally {
      _completionPending = false;
    }
  }

  Future<void> _presentReadingMoment() async {
    if (_showingMoment ||
        !mounted ||
        !_activityForeground ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _showingMoment = true;
    _activityOverlay('reading-moment', true);
    try {
      await _verifiedReading.settled;
      final moment = await widget.state.readingMoments.takePending(
        canPresent: () =>
            mounted &&
            _activityForeground &&
            ModalRoute.of(context)?.isCurrent != false,
      );
      if (moment == null ||
          !mounted ||
          !_activityForeground ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      await showReadingMoment(
        context,
        moment: moment,
        reduceMotion: widget.state.reduceMotion,
        confetti: widget.state.readingMoments.preferences.confetti,
        theme: ReadingVisualTheme.fromId(
          widget.state.readingMoments.preferences.themeId,
        ),
      );
    } catch (_) {
      if (mounted) showNovelFeedback(context, '阅读纪念暂未保存，请稍后重试');
    } finally {
      _showingMoment = false;
      if (mounted) _activityOverlay('reading-moment', false);
    }
  }

  Future<Novel>? _navigationPreparation;
  bool get _authoredDirectory =>
      _sourceBook.navigation?.entries.isNotEmpty == true;
  int? _lastDirectoryOrdinal;
  int get _directoryOrdinal {
    final position = _currentPosition(bookmark: true);
    return _sourceBook.directoryIndexFor(
      _chapter,
      paragraph: position?.paragraphIndex ?? 0,
      offset: position?.textOffset ?? 0,
    );
  }

  Novel get _sourceBook => _readerBook;

  int? _readerChapterFor(Novel source, int chapter) {
    if (source.id != _sourceBook.id ||
        chapter < 0 ||
        chapter >= source.chapters.length) {
      return null;
    }
    final id = source.chapters[chapter].id;
    // Legacy/demo directories without IDs retain their original index contract.
    if (id <= 0) return chapter < _sourceBook.chapters.length ? chapter : null;
    final index = _sourceBook.chapters.indexWhere((entry) => entry.id == id);
    return index < 0 ? null : index;
  }

  ReadingPosition? _readerPosition(ReadingPosition? position) {
    if (position == null) return null;
    final index = widget.state.chapterForPosition(_sourceBook, position);
    if (index == null) return null;
    return ReadingPosition(
      chapter: index,
      chapterId: _sourceBook.chapters[index].id,
      offset: position.offset,
      fraction: position.fraction,
      fontSize: position.fontSize,
      width: position.width,
      updatedAt: position.updatedAt,
      lineHeight: position.lineHeight,
      paragraphIndex: position.paragraphIndex,
      paragraphFraction: position.paragraphFraction,
      textOffset: position.textOffset,
      textScale: position.textScale,
      typeface: position.typeface,
      layout: position.layout,
      contentRevision: position.contentRevision,
    );
  }

  Future<Novel> _prepareReaderDirectory() =>
      _navigationPreparation ??= () async {
        if (isLocalBook(widget.novel.id) &&
            widget.repository is OfflineNovelRepository) {
          try {
            return await (widget.repository as OfflineNovelRepository).local
                    ?.ensureNavigation(widget.novel.id) ??
                _sourceBook;
          } catch (error) {
            // Keep existing local content usable if navigation repair fails.
          }
        }
        return _sourceBook;
      }();
  DateTime? _exitRequestedAt;
  bool _allowExit = false;
  final _preparedContent = <int, ReaderContent>{};
  final _automaticContent = <int, (ReaderContent, ReaderContent)>{};
  final _contentLoads = <int, Future<ReaderContent>>{};
  final _preparedDisplay =
      <int, ({Object spec, _PreparedReaderChapter chapter})>{};
  final _displayLoads =
      <int, ({Object spec, Future<_PreparedReaderChapter> request})>{};
  int _illustrationGeneration = 0;
  Object get _displaySpec => (
    _readerRegion ?? 'CN',
    (widget.state.hiddenReaderLanguagesFor(widget.novel.id).toList()..sort())
        .join(','),
    widget.state.onlyReaderLanguageFor(widget.novel.id),
    _illustrationGeneration,
    _replaceRuleSignature,
  );
  _PreparedReaderChapter? _cachedDisplay(int index) {
    final value = _preparedDisplay[index];
    return value?.spec == _displaySpec ? value?.chapter : null;
  }

  int _chapterSwitchTicket = 0;
  int _chapterTurnDirection = 0;
  int? _pendingChapter;
  bool _boundaryQueued = false;
  ListeningController? _listening;
  (int, int, int, int)? _listeningTarget;
  String? _listeningError;
  int _followTicket = 0;
  bool _followLocallyPaused = false;
  bool _followAutomatic = false;
  final _followPrompt = ValueNotifier(false);
  bool _enablingFollow = false;
  int _restoreTicket = 0;
  double _layoutWidth = 0;
  String _layoutTypeface = 'system';
  bool _typographyPreviewing = false;
  double _layoutTextScale = 1;
  double _readingInset = 0;
  int _contentGeneration = 0;
  final Set<int> _reviewsRequested = <int>{};
  int _reviewRevision = 0;
  late final AnimationController _chapterReveal;
  bool _chapterRevealPending = false;
  int _chapterRevealFirst = 0;
  late final AnimationController _chrome;
  final _readerDockKey = GlobalKey();
  bool _chromeTarget = false;
  bool _chromeHintQueued = false;
  String? _readerRegion;
  late final Ticker _autoScroll;
  Timer? _autoPageTimer;
  Duration? _autoLast;
  bool _autoRunning = false;
  bool _autoPaused = false;
  ReaderPaper? _dayPaper;
  int _nightIconActivation = 0;
  int? _chromeProgressFrame;
  double? _chromeProgressPending;
  bool _chromeProgressActive = false;
  final _chromeSourceProgress =
      ValueNotifier<
        ({int chapter, int generation, ReaderContent content, double fraction})?
      >(null);
  double _chapterOverscroll = 0;
  String _layoutKey = '';
  late ReaderPaper _paper;
  late bool _hideSystemStatus;
  late bool _showStatusInfo;
  Widget _readerSurface(Widget child) => ReaderAppearance(
    state: widget.state,
    bookId: widget.novel.id,
    appTheme: Theme.of(context),
    child: child,
  );

  void _paperChanged() {
    final replaceSignature = _replaceRuleSignature;
    if (replaceSignature != _replaceSignature) {
      _replaceSignature = replaceSignature;
      _rebuildForReplaceRules();
    }
    if (!_readerPreferences.chapterEntrance) {
      _chapterRevealPending = false;
      if (!_chapterReveal.isCompleted) _chapterReveal.value = 1;
    }
    final paper = _readerPreferences.paper;
    // Typography previews rebuild the article, not the glass controls. Only a
    // different paper palette needs to update the chrome's contrast.
    final mode = _readerPreferences.mode;
    final hideSystemStatus = _readerPreferences.hideSystemStatus;
    final showStatusInfo = _readerPreferences.showStatusInfo;
    final chapterEntrance = _readerPreferences.chapterEntrance;
    if (mode != _readerMode ||
        hideSystemStatus != _hideSystemStatus ||
        showStatusInfo != _showStatusInfo ||
        chapterEntrance != _chapterEntrance) {
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
      _selection.clear();
      _stopAutoScroll();
    }
    if (paper != _paper ||
        mode != _readerMode ||
        hideSystemStatus != _hideSystemStatus ||
        showStatusInfo != _showStatusInfo ||
        chapterEntrance != _chapterEntrance) {
      setState(() {
        _paper = paper;
        _readerMode = mode;
        _hideSystemStatus = hideSystemStatus;
        _showStatusInfo = showStatusInfo;
        _chapterEntrance = chapterEntrance;
      });
    }
  }

  Future<void> _loadReplaceRules() async {
    try {
      await _replaceRules.load();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final signature = _replaceRuleSignature;
    if (signature == _replaceSignature) return;
    _replaceSignature = signature;
    _rebuildForReplaceRules();
  }

  void _replaceRulesChanged() {
    if (!mounted) return;
    final signature = _replaceRuleSignature;
    if (signature == _replaceSignature) return;
    _replaceSignature = signature;
    _rebuildForReplaceRules();
  }

  void _rebuildForReplaceRules() {
    _preparedContent.clear();
    _automaticContent.clear();
    _contentLoads.clear();
    _preparedDisplay.clear();
    _displayLoads.clear();
    _titleProjectionBase = null;
    _titleProjectionCache = null;
    _titleProjectionSignature = null;
    if (!mounted || _readerRegion == null) return;
    final position = _currentPosition();
    if (position != null) _prepareRestore(position);
    setState(() {
      _content = _loadContent();
    });
    _prefetchAdjacent();
  }

  void _autoTick(Duration elapsed) {
    final previous = _autoLast;
    _autoLast = elapsed;
    if (previous == null ||
        !_ready ||
        _restoring ||
        !_listeningScrollSceneActive) {
      return;
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - .5) {
      if (_chapter + 1 < _sourceBook.chapters.length) {
        if (_readerPreferences.chapterEntrance) {
          _go(_chapter + 1, prepared: _cachedDisplay(_chapter + 1));
        } else {
          _scrollStream.prepareAdjacent();
        }
      } else {
        _stopAutoScroll(showControls: true);
      }
      return;
    }
    final dt = ((elapsed - previous).inMicroseconds / 1000000).clamp(0.0, .05);
    _scroll.jumpTo(
      (position.pixels + dt * _readerPreferences.autoScrollSpeed).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _scheduleAutoPage() {
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
    if (!_autoRunning ||
        !_paginated ||
        !_ready ||
        _restoring ||
        !_paged.ready) {
      return;
    }
    // A stationary page needs no vsync callbacks. Wake once at the requested
    // interval; only the existing page-turn animation drives display frames.
    _autoPageTimer = Timer(
      Duration(
        microseconds: (600000000 / _readerPreferences.autoScrollSpeed).round(),
      ),
      () {
        _autoPageTimer = null;
        if (!_autoRunning || !mounted) return;
        if (!_listeningScrollSceneActive) {
          _stopAutoScroll();
          return;
        }
        if (!_ready || _restoring || !_paged.ready) return;
        if (_paged.pageBy(1)) {
          _scheduleAutoPage();
        } else if (_chapter + 1 < _sourceBook.chapters.length) {
          // The new chapter schedules its own interval after layout/restoration.
          _go(_chapter + 1);
        } else {
          _stopAutoScroll(showControls: true);
        }
      },
    );
  }

  void _startAutoScroll() {
    if (!_ready) return;
    _suspendListeningFollow();
    unawaited(_listening?.pause().catchError((Object _) {}));
    _autoRunning = true;
    if (_autoPaused) setState(() => _autoPaused = false);
    _autoLast = null;
    _showChrome(false);
    if (_paginated) {
      _scheduleAutoPage();
    } else if (!_autoScroll.isActive) {
      _autoScroll.start();
    }
  }

  void _stopAutoScroll({bool showControls = false}) {
    if (!_autoRunning) return;
    _autoRunning = false;
    _autoLast = null;
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
    _autoScroll.stop();
    if (mounted && _autoPaused != showControls) {
      setState(() => _autoPaused = showControls);
    }
    _saveWhenIdle();
    if (showControls && mounted) _showChrome(true);
  }

  int _contentTapDirection(TapUpDetails details) {
    final prefs = _readerPreferences;
    if (!prefs.tapPaging) return 0;
    final x = details.localPosition.dx / MediaQuery.sizeOf(context).width;
    final y = details.localPosition.dy / MediaQuery.sizeOf(context).height;
    final direction = prefs.tapBothSidesNext
        ? (x < .28 || x > .72 ? 1 : 0)
        : switch (prefs.tapLayout) {
            ReaderTapLayout.standard =>
              x < .28
                  ? -1
                  : x > .72
                  ? 1
                  : 0,
            ReaderTapLayout.rightHand => x > .4 ? (y < .3 ? -1 : 1) : 0,
            ReaderTapLayout.leftHand => x < .6 ? (y < .3 ? -1 : 1) : 0,
          };
    return !prefs.tapBothSidesNext &&
            prefs.mode == ReaderMode.vertical &&
            prefs.tapLayout == ReaderTapLayout.standard
        ? -direction
        : direction;
  }

  VoidCallback? _previewContentTap(TapUpDetails details) {
    final listening = _listening?.snapshot.value;
    if (!_ready ||
        _toolsOpen ||
        _catalogueOpen ||
        _findOpen ||
        _selection.value ||
        _autoRunning ||
        listening?.active != true ||
        listening?.novel?.id != widget.novel.id ||
        _contentTapDirection(details) != 0) {
      return null;
    }
    final original = _chromeTarget;
    // A listening double tap holds the normal single-tap arena. Give only the
    // reversible centre chrome immediate feedback; commit/haptics remain with
    // the original winner. No source position or page is changed here.
    _animateChrome(!original);
    return () {
      if (mounted && _chromeTarget == original) _animateChrome(original);
    };
  }

  void _contentTap(TapUpDetails details) {
    _cancelExitRequest();
    if (_selection.value) {
      AppHaptics.play(context, HapticCue.selection);
      _selection.clear();
      return;
    }
    if (_autoRunning) {
      AppHaptics.play(context, HapticCue.action);
      _stopAutoScroll(showControls: true);
      return;
    }
    final direction = _contentTapDirection(details);
    if (direction != 0) {
      _pageBy(direction);
      return;
    }
    _toggleChrome();
  }

  @override
  void initState() {
    super.initState();
    _paper = _readerPreferences.paper;
    _readingActivity = ReadingActivitySession(
      store: widget.state.readingActivity,
      bookId: widget.novel.id,
    );
    _verifiedReading = VerifiedReadingSession(
      store: widget.state.readingMoments,
      bookId: widget.novel.id,
      elapsed: widget.verifiedReadingElapsed,
    );
    _selection.addListener(_syncReadingActivity);
    _activityAttached = true;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _activityForeground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _releaseReadingPosition = widget.state.holdReadingPosition(widget.novel.id);
    _hideSystemStatus = _readerPreferences.hideSystemStatus;
    _showStatusInfo = _readerPreferences.showStatusInfo;
    _readerMode = _readerPreferences.mode;
    _chapterEntrance = _readerPreferences.chapterEntrance;
    _chromeTarget = widget.state.readerChromeVisible;
    LocalPlatform.setChromeVisible(_chromeTarget);
    widget.state.readerSettingsChanges.addListener(_paperChanged);
    widget.state.illustrationChanges.addListener(_illustrationLayoutChanged);
    _replaceRules.addListener(_replaceRulesChanged);
    _replaceSignature = _replaceRuleSignature;
    unawaited(_loadReplaceRules());
    _autoScroll = createTicker(_autoTick);
    _chapterReveal = AnimationController(
      vsync: this,
      duration: NovelMotion.enter,
      value: 1,
    );
    _chrome = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: NovelMotion.exit,
      value: _chromeTarget ? 1 : 0,
    );
    WidgetsBinding.instance.addObserver(this);
    final saved =
        widget.initialBookmark?.position ??
        widget.initialPosition ??
        widget.state.positionFor(widget.novel.id);
    _bookmarkLandingPending = widget.initialBookmark != null;
    if (widget.initialBookmark != null || widget.initialPosition != null) {
      final target = saved == null
          ? null
          : widget.state.chapterForPosition(_sourceBook, saved);
      if (target != null) _chapter = target;
    }
    if (saved != null &&
        _sourceBook.chapters.isNotEmpty &&
        (saved.chapterId > 0
            ? saved.chapterId == _sourceBook.chapters[_chapter].id
            : saved.chapter == _chapter)) {
      _restorePending = _readerPosition(saved);
      _restoreAlignStart = _alignIosResumeStart(saved);
    }
  }

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _readingActivity.dispose();
      _verifiedReading.dispose();
      _readingActivity = ReadingActivitySession(
        store: widget.state.readingActivity,
        bookId: widget.novel.id,
      );
      _verifiedReading = VerifiedReadingSession(
        store: widget.state.readingMoments,
        bookId: widget.novel.id,
        elapsed: widget.verifiedReadingElapsed,
      );
      _syncReadingActivity();
      _releaseReadingPosition();
      _releaseReadingPosition = widget.state.holdReadingPosition(
        widget.novel.id,
      );
      oldWidget.state.readerSettingsChanges.removeListener(_paperChanged);
      oldWidget.state.illustrationChanges.removeListener(
        _illustrationLayoutChanged,
      );
      widget.state.readerSettingsChanges.addListener(_paperChanged);
      widget.state.illustrationChanges.addListener(_illustrationLayoutChanged);
      _paper = _readerPreferences.paper;
      _hideSystemStatus = _readerPreferences.hideSystemStatus;
      _showStatusInfo = _readerPreferences.showStatusInfo;
    }
  }

  @override
  void deactivate() {
    _readingActivity.setActive(false);
    _verifiedReading.setActive(false);
    _activityAttached = false;
    _pageAdvanceOrigin = null;
    _scrollAdvanceOrigin = null;
    // The Scrollable child detaches its controller before this State's dispose.
    // Capture while it is still attached, also when idle-save is pending.
    _idleSave?.cancel();
    _followTicket++;
    _followScroll.cancel();
    _savePosition(notify: false, finalSave: true);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _activityAttached = true;
    _syncReadingActivity();
  }

  @override
  void dispose() {
    widget.state.illustrationChanges.removeListener(_illustrationLayoutChanged);
    _selection.removeListener(_syncReadingActivity);
    _readingActivity.dispose();
    _verifiedReading.dispose();
    _cancelChromeProgress();
    _chromeSourceProgress.dispose();
    _releaseHandoffTarget?.call();
    _releaseReadingPosition();
    _dismissChromeHint?.call();
    _releaseFeedbackHeader?.call();
    widget.state.readerSettingsChanges.removeListener(_paperChanged);
    _replaceRules.removeListener(_replaceRulesChanged);
    _idleSave?.cancel();
    _savePosition(notify: false, finalSave: true);
    _highlightTimer?.cancel();
    _findMatch.dispose();
    _bookmarkLandingTimer?.cancel();
    _bookmarkLanding.dispose();
    _selection.dispose();
    _verticalGlyphs.dispose();
    _listening?.snapshot.removeListener(_listeningChanged);
    _listening?.progress.removeListener(_listeningProgressChanged);
    _followPrompt.dispose();
    _followTicket++;
    _followScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _chapterReveal.dispose();
    _chrome.dispose();
    _autoScroll.dispose();
    _autoPageTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _activityRouteCurrent = ModalRoute.isCurrentOf(context) != false;
    _syncReadingActivity();
    _releaseFeedbackHeader ??= bindNovelFeedbackHeader(context, _chrome);
    final handoff = ReaderHandoffScope.maybeOf(context);
    if (handoff != _handoffNavigation) {
      _releaseHandoffTarget?.call();
      _handoffNavigation = handoff;
      _releaseHandoffTarget = handoff?.register(context, widget.novel.id, (
        position,
      ) {
        if (!mounted) return;
        _stopAutoScroll();
        _cancelExitRequest();
        _go(position.chapter, position: position);
      });
    }
    _scheduleChromeHint();
    final region = chineseLocale(
      Localizations.maybeLocaleOf(context),
    ).countryCode;
    if (_readerRegion == null) {
      // Resolve inherited locale before creating the first display/cache spec.
      _readerRegion = region;
      _content = _loadContent();
    } else if (_readerRegion != region) {
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
      _readerRegion = region;
      _content = _loadContent();
    }
    _readerRegion = region;
    final listening = ListeningScope.maybeOf(context);
    if (listening != _listening) {
      _listening?.snapshot.removeListener(_listeningChanged);
      _listening?.progress.removeListener(_listeningProgressChanged);
      _listening = listening;
      listening?.snapshot.addListener(_listeningChanged);
      listening?.progress.addListener(_listeningProgressChanged);
      _listeningTarget = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listeningChanged();
      });
    } else if (listening != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listeningChanged();
      });
    }
    if (!_ready || _restoring || _layoutWidth <= 0) return;
    final media = MediaQuery.of(context);
    final scale = media.textScaler.scale(_fontSize) / _fontSize;
    if ((media.size.width - _layoutWidth).abs() >= 1 ||
        (scale - _layoutTextScale).abs() >= .01 ||
        _layoutTypeface != _readerFontId) {
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
    }
  }

  Future<void> _listen() async {
    if (_listening != null) {
      await _settings(scope: ReaderToolsScope.listening, fromDock: false);
    }
  }

  Future<void> _openListeningReader(ListeningReaderTarget target) async {
    if (!mounted) return;
    if (target.novel.id == widget.novel.id) {
      final chapter = widget.state.chapterForPosition(
        _sourceBook,
        target.position,
      );
      if (chapter == null) {
        showNovelFeedback(context, '正在听的章节暂未就绪，请稍后重试');
        return;
      }
      _stopAutoScroll();
      _go(chapter, position: target.position, listeningFollow: true);
    } else {
      await pushNovelPage<void>(
        context,
        ReaderPage(
          novel: target.novel,
          state: widget.state,
          repository: widget.repository,
          initialChapter: target.position.chapter,
          initialPosition: target.position,
        ),
        reduceMotion: widget.state.reduceMotion,
      );
    }
  }

  void _suspendListeningFollow({bool userDrag = false}) {
    final listening = _listening;
    _followTicket++;
    _followScroll.cancel(userDrag: userDrag);
    if (listening != null &&
        listening.snapshot.value.active &&
        listening.snapshot.value.novel?.id == widget.novel.id &&
        listening.snapshot.value.follow) {
      _followLocallyPaused = true;
      _followPrompt.value = listening.snapshot.value.current != null;
      unawaited(listening.setFollow(false).catchError((Object _) {}));
    }
  }

  void _listeningProgressChanged() {
    final listeningState = _listening?.snapshot.value;
    final clip = listeningState?.current;
    if (listeningState != null &&
        clip != null &&
        listeningState.novel?.id == widget.novel.id) {
      _verifiedReading.playbackProgress(
        segment: (listeningState.chapter, clip.paragraph, clip.start),
        position: _listening!.progress.value.position,
        speed: listeningState.speed,
        playing:
            listeningState.playing && !_listening!.seeking && _verifiedEligible,
      );
    }
    if (!_paginated || !_listeningScrollSceneActive) return;
    final state = _listening?.snapshot.value;
    final current = state?.current;
    if (state == null ||
        !state.active ||
        !state.follow ||
        _followLocallyPaused ||
        state.novel?.id != widget.novel.id ||
        current == null ||
        _listening!.seeking ||
        state.phase == ListeningPhase.preparing) {
      return;
    }
    final anchor = ReaderTextAnchor(
      current.paragraph,
      readerListeningOffset(current, _listening!.progress.value),
    );
    // Most audio ticks stay on the current spread. They must not rebuild the
    // page or restart its existing turn animation.
    final chapter = _readerChapterFor(state.novel!, state.chapter);
    if (chapter == null) return;
    if (_chapter == chapter && _paged.isRevealed(anchor)) return;
    _listeningChanged();
  }

  void _listeningChanged() {
    final state = _listening?.snapshot.value;
    if (state?.playing != true) {
      _verifiedReading.playbackProgress(
        segment: 0,
        position: Duration.zero,
        playing: false,
      );
    }
    final current = state?.current;
    if (state?.error == null) _listeningError = null;
    if (mounted &&
        state?.novel?.id == widget.novel.id &&
        state?.error != null &&
        state!.error != _listeningError) {
      final error = _listeningError = state.error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ModalRoute.of(context)?.isCurrent != false &&
            _listening?.snapshot.value.error == error) {
          showNovelFeedback(
            context,
            error!,
            actionLabel: '听书',
            action: _listen,
          );
        }
      });
    }
    if (state == null || !state.active || !state.follow) {
      _followLocallyPaused = false;
    }
    _followPrompt.value =
        state != null &&
        state.active &&
        state.novel?.id == widget.novel.id &&
        current != null &&
        (!state.follow || _followLocallyPaused);
    if (state == null ||
        !state.active ||
        state.novel?.id != widget.novel.id ||
        !_listeningScrollSceneActive) {
      _listeningTarget = null;
      _followTicket++;
      _followScroll.cancel();
      return;
    }
    if (!state.follow || _followLocallyPaused || current == null) {
      _listeningTarget = null;
      if (_followAutomatic) {
        _followTicket++;
        _followScroll.cancel();
        _followAutomatic = false;
      }
      return;
    }
    final chapter = _readerChapterFor(state.novel!, state.chapter);
    if (chapter == null) {
      _listeningTarget = null;
      _followTicket++;
      _followScroll.cancel();
      return;
    }
    final start =
        _paginated &&
            (state.phase != ListeningPhase.preparing || _listening!.seeking)
        ? readerListeningOffset(current, _listening!.progress.value)
        : current.start;
    final target = (widget.novel.id, chapter, current.paragraph, start);
    if (_listeningTarget == target) return;
    _listeningTarget = target;
    if (chapter != _chapter) _go(chapter, listeningFollow: true);
    _revealListeningFragment(
      chapter,
      current.paragraph,
      start,
      current.end,
      automatic: true,
    );
  }

  bool get _listeningScrollSceneActive =>
      mounted &&
      !_toolsOpen &&
      !_catalogueOpen &&
      !_findOpen &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      ModalRoute.of(context)?.isCurrent != false;

  Future<void> _enableListeningFollow() async {
    _contentTapSurface.commitPreview();
    final listening = _listening;
    final state = listening?.snapshot.value;
    if (_enablingFollow ||
        listening == null ||
        state?.active != true ||
        state?.novel?.id != widget.novel.id ||
        state?.current == null) {
      return;
    }
    _enablingFollow = true;
    _stopAutoScroll();
    _selection.clear();
    try {
      await listening.setFollow(true);
      if (!mounted) return;
      _followLocallyPaused = false;
      _listeningTarget = null;
      _listeningChanged();
    } catch (_) {
      if (mounted) showNovelFeedback(context, '跟随设置保存失败，请重试');
    } finally {
      _enablingFollow = false;
    }
  }

  void _revealListeningFragment(
    int chapter,
    int paragraph,
    int start,
    int end, {
    required bool automatic,
  }) {
    final ticket = ++_followTicket;
    _followAutomatic = automatic;
    _followScroll.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool allowed() =>
          _listeningScrollSceneActive &&
          ticket == _followTicket &&
          _chapter == chapter &&
          _listening?.snapshot.value.active == true &&
          _listening?.snapshot.value.novel?.id == widget.novel.id &&
          (!automatic ||
              (_listening?.snapshot.value.follow == true &&
                  !_followLocallyPaused));
      if (!allowed()) return;
      try {
        if (_paginated) {
          if (allowed() && _paged.ready) {
            final anchor = ReaderTextAnchor(paragraph, start);
            if (!_paged.isRevealed(anchor)) _paged.reveal(anchor);
          }
          return;
        }
        await _followScroll.reveal(
          allowed: allowed,
          reduceMotion:
              widget.state.reduceMotion ||
              MediaQuery.disableAnimationsOf(context),
          target: () =>
              !_ready ||
                  _restoring ||
                  _restorePending != null ||
                  !_scroll.hasClients
              ? null
              : _paragraphRegistry.speechTarget(
                  paragraph,
                  start,
                  end,
                  _readingInset,
                  viewportBottom:
                      _scroll.position.viewportDimension -
                      MediaQuery.paddingOf(context).bottom -
                      116,
                  trailingSpace: 12,
                ),
        );
      } finally {
        if (ticket == _followTicket) _followAutomatic = false;
      }
    });
    // Adding a post-frame callback alone does not request a frame. In a static
    // chapter or after resuming, explicitly wake the one requested landing.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _doubleTapListeningParagraph(
    int paragraph, {
    int? sourceChapter,
  }) async {
    final listening = _listening;
    if (listening == null) return;
    final state = listening.snapshot.value;
    final chapter = sourceChapter ?? _chapter;
    final listeningChapter = state.novel == null
        ? null
        : _readerChapterFor(state.novel!, state.chapter);
    final other =
        state.active &&
        state.novel?.id == widget.novel.id &&
        (listeningChapter != chapter || state.current?.paragraph != paragraph);
    final action = listening.paragraphDoubleTap(
      novelId: widget.novel.id,
      chapter: chapter,
      paragraph: paragraph,
      source: _sourceBook,
    );
    // An explicit double-tap is a one-off soft landing even after a manual
    // scroll suspended following. It never flips the user's follow preference.
    if (other &&
        (!state.follow || _followLocallyPaused) &&
        _currentContent != null &&
        chapter == _chapter) {
      final text = _currentContent!.paragraphs[paragraph];
      _revealListeningFragment(
        _chapter,
        paragraph,
        0,
        text.length.clamp(0, 240),
        automatic: false,
      );
    }
    await action;
  }

  void _go(
    int index, {
    ReadingPosition? position,
    bool highlightBookmark = false,
    ReaderMatch? findMatch,
    bool listeningFollow = false,
    _PreparedReaderChapter? prepared,
    int turnDirection = 0,
  }) {
    if (index < 0 || index >= _sourceBook.chapters.length) {
      return;
    }
    if (index != _chapter &&
        prepared == null &&
        (!_readerPreferences.chapterEntrance || turnDirection != 0) &&
        _currentContent != null) {
      if (_pendingChapter == index) return;
      unawaited(
        _stageChapter(
          index,
          position: position,
          highlightBookmark: highlightBookmark,
          findMatch: findMatch,
          listeningFollow: listeningFollow,
          turnDirection: turnDirection,
        ),
      );
      return;
    }
    _chapterSwitchTicket++;
    _pendingChapter = null;
    _selection.clear();
    if (!listeningFollow) _suspendListeningFollow();
    _clearBookmarkLanding();
    _bookmarkLandingPending = highlightBookmark;
    if (highlightBookmark) {
      _highlightTimer?.cancel();
      _findMatch.value = null;
    }
    if (index == _chapter) {
      if (position == null) return;
      _prepareRestore(position);
      setState(() {});
      return;
    }
    if (_chromeProgressActive) {
      _chromeProgressActive = false;
      _typographyPreviewing = false;
      _cancelChromeProgress();
    }
    _idleSave?.cancel();
    _savePosition(notify: false);
    _cancelExitRequest();
    _highlightTimer?.cancel();
    _findMatch.value = null;
    _currentContent = null;
    _unfilteredContent = null;
    _illustrationsRefreshing = false;
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
    _autoScroll.stop();
    _autoLast = null;
    _ready = false;
    _restorePending = position;
    _restoreAlignStart = _alignIosResumeStart(position);
    _restoreQueued = false;
    _restoring = false;
    _restoreTicket++;
    setState(() {
      _chapterTurnDirection = turnDirection;
      _chapter = index;
      _content = _loadContent(prepared: prepared, findMatch: findMatch);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _stageChapter(
    int index, {
    ReadingPosition? position,
    bool highlightBookmark = false,
    ReaderMatch? findMatch,
    bool listeningFollow = false,
    int turnDirection = 0,
  }) async {
    final ticket = ++_chapterSwitchTicket, generation = _contentGeneration;
    _pendingChapter = index;
    final hint = Timer(const Duration(milliseconds: 500), () {
      if (mounted && ticket == _chapterSwitchTicket) {
        showNovelFeedback(context, '正在准备章节，当前正文仍可阅读');
      }
    });
    try {
      final prepared = await _prepareDisplayContent(index);
      if (!mounted ||
          ticket != _chapterSwitchTicket ||
          generation != _contentGeneration) {
        return;
      }
      _go(
        index,
        prepared: prepared,
        position: position,
        highlightBookmark: highlightBookmark,
        findMatch: findMatch,
        listeningFollow: listeningFollow,
        turnDirection: turnDirection,
      );
    } catch (error) {
      if (!mounted || ticket != _chapterSwitchTicket) return;
      _showChrome(true);
      showNovelFeedback(context, '章节未能载入，当前正文已保留，请重试');
    } finally {
      hint.cancel();
      if (ticket == _chapterSwitchTicket) _pendingChapter = null;
    }
  }

  Future<_PreparedReaderChapter> _prepareDisplayContent(
    int index, {
    bool refresh = false,
  }) {
    final spec = _displaySpec;
    if (!refresh) {
      if (_cachedDisplay(index) case final cached?) return Future.value(cached);
      if (_displayLoads[index] case (
        spec: final key,
        request: final request,
      ) when key == spec) {
        return request;
      }
    }
    final region = _readerRegion ?? 'CN';
    final hidden = widget.state.hiddenReaderLanguagesFor(widget.novel.id);
    final only = widget.state.onlyReaderLanguageFor(widget.novel.id);
    late final Future<_PreparedReaderChapter> request;
    request = () async {
      try {
        final source = await _prepareContent(index, refresh: refresh);
        await _bookFontReady;
        final placed = placeIllustrations(
          await _automaticIllustrations(source, index),
          widget.state.illustrationsFor(
            widget.novel.id,
            chapterId: _sourceBook.chapters[index].id,
          ),
        );
        final localized = await placed.localizedAsync(Locale('zh', region));
        final result = (
          unfiltered: localized,
          content: localized.withHiddenLanguages(hidden, onlyLanguage: only),
        );
        if (mounted &&
            spec == _displaySpec &&
            (index - _chapter).abs() <= 1 &&
            identical(_displayLoads[index]?.request, request)) {
          _preparedDisplay[index] = (spec: spec, chapter: result);
        }
        return result;
      } finally {
        if (identical(_displayLoads[index]?.request, request)) {
          _displayLoads.remove(index);
        }
      }
    }();
    _displayLoads[index] = (spec: spec, request: request);
    return request;
  }

  Future<void> _catalogue() async {
    _cancelExitRequest();
    _selection.clear();
    if (_catalogueOpen ||
        _toolsOpen ||
        _findOpen ||
        _sourceBook.chapters.isEmpty) {
      return;
    }
    _stopAutoScroll();
    _catalogueOpen = true;
    _followTicket++;
    _followScroll.cancel();
    try {
      final action = await showJellySheet<Object>(
        context: context,
        anchor: _readerDockAnchor,
        sourceContext: _chrome.value == 0
            ? null
            : _readerDockKey.currentContext,
        reduceMotion: widget.state.reduceMotion,
        surfaceWrapper: _readerSurface,
        builder: (context) => ReaderCatalogue(
          novel: _displayBook,
          reduceMotion: widget.state.reduceMotion,
          currentChapter: _chapter,
          position: _currentPosition(),
          initialReversed: widget.state.readerPreferences.catalogueReversed,
          onOrderChanged: (reversed) => widget.state.setReaderPreferences(
            widget.state.readerPreferences.copyWith(
              catalogueReversed: reversed,
            ),
          ),
          cache: widget.repository is OfflineNovelRepository
              ? (widget.repository as OfflineNovelRepository).cache
              : null,
        ),
      );
      if (!mounted) return;
      if (action is int && action != _chapter) {
        _go(action);
      } else if (action is BookReadingTarget) {
        _openBookTarget(action);
      }
    } finally {
      _catalogueOpen = false;
      _listeningTarget = null;
      _savePosition(notify: false);
      if (mounted) _listeningChanged();
    }
  }

  Future<({ReaderContent? content, Object? error})> _loadContent({
    bool refresh = false,
    _PreparedReaderChapter? prepared,
    ReaderMatch? findMatch,
  }) async {
    var index = _chapter;
    final source = _sourceBook;
    final sourceId = index >= 0 && index < source.chapters.length
        ? source.chapters[index].id
        : null;
    final generation = ++_contentGeneration;
    _illustrationsRefreshing = false;
    _chapterRevealPending = false;
    _chapterReveal.value = 1;
    // Picker results can arrive between frames. Carry expected request failure
    // as data, rather than an exceptional future awaiting the next UI listener.
    try {
      final directory = await _prepareReaderDirectory();
      if (!mounted || generation != _contentGeneration) {
        return (content: null, error: null);
      }
      if (!identical(directory, _sourceBook)) {
        final mapped = sourceId == null
            ? 0
            : directory.chapters.indexWhere(
                (chapter) => chapter.id == sourceId,
              );
        if (mapped < 0) throw const FormatException('当前章节已不在目录中');
        _readerBook = directory;
        index = _chapter = mapped;
        _restorePending = _readerPosition(_restorePending);
        // These caches are indexed by the adopted directory, never by an
        // obsolete position in the pre-recovery chapter table.
        _preparedContent.clear();
        _automaticContent.clear();
        _contentLoads.clear();
        _preparedDisplay.clear();
        _displayLoads.clear();
        prepared = null;
        // The scaffold captures its chapter title outside FutureBuilder.
        // Publish the new table and index together before any new body paints.
        setState(() {});
      }
      final display =
          prepared ?? await _prepareDisplayContent(index, refresh: refresh);
      final content = display.content, localized = display.unfiltered;
      if (mounted && index == _chapter && generation == _contentGeneration) {
        _currentContent = content;
        _unfilteredContent = localized;
        if (findMatch != null) _showFindMatch(findMatch);
        if (_restorePending case final saved?) {
          _restorePending = _resolveContentPosition(saved);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _contentGeneration) {
            _listeningTarget = null;
            _listeningChanged();
            if (!_paginated && _scroll.hasClients) {
              final fraction = _scrollSourceFraction(_scroll.offset);
              if (fraction != null) _reportChromeSourceProgress(fraction);
            }
            _deferContentWarmup(generation, content);
            unawaited(_autoFetchReviews(index));
          }
        });
        final reduce =
            !_readerPreferences.chapterEntrance ||
            widget.state.reduceMotion ||
            MediaQuery.disableAnimationsOf(context);
        if (reduce) {
          _chapterReveal.value = 1;
        } else {
          _chapterRevealPending = true;
          _chapterReveal.value = 0;
        }
      }
      return (content: content, error: null);
    } catch (error, stack) {
      debugPrint('[reader] content load failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted && generation == _contentGeneration) _showChrome(true);
      return (content: null, error: error);
    }
  }

  Future<ReaderContent> _prepareContent(int index, {bool refresh = false}) {
    if (!refresh) {
      if (_preparedContent[index] case final content?) {
        return Future.value(content);
      }
      if (_contentLoads[index] case final request?) return request;
    }
    late final Future<ReaderContent> request;
    request = () async {
      try {
        final body = await _requestContent(index, refresh: refresh);
        final content = await ReaderContent.parse(_filterReaderText(body));
        if (mounted &&
            (index - _chapter).abs() <= 1 &&
            identical(_contentLoads[index], request)) {
          _preparedContent[index] = content;
        }
        return content;
      } finally {
        if (identical(_contentLoads[index], request)) {
          _contentLoads.remove(index);
        }
      }
    }();
    _contentLoads[index] = request;
    return request;
  }

  String _filterReaderText(String body) {
    if (!_replaceRulesActive) return body;
    return _replaceRules.applyContent(
      body,
      bookTitle: _sourceBook.title,
      origin: ReplaceRuleStore.originFor(_sourceBook),
    );
  }

  void _prefetchAdjacent() {
    _automaticContent.removeWhere((index, _) => (index - _chapter).abs() > 1);
    _preparedContent.removeWhere((index, _) => (index - _chapter).abs() > 1);
    _preparedDisplay.removeWhere((index, _) => (index - _chapter).abs() > 1);
    // The continuous view owns its next/previous slots and inline retry state.
    if (!_paginated && !_readerPreferences.chapterEntrance) {
      _scrollStream.prepareAdjacent();
      return;
    }
    for (final index in [_chapter + 1, _chapter - 1]) {
      if (index < 0 || index >= _sourceBook.chapters.length) continue;
      if (widget.repository case final OfflineNovelRepository offline) {
        if (offline.offline &&
            !isLocalBook(widget.novel.id) &&
            offline.cache
                    .book(widget.novel.id)
                    ?.chapterBytes
                    .containsKey(_sourceBook.chapters[index].id) !=
                true) {
          continue;
        }
      }
      unawaited(
        _prepareDisplayContent(index).then<void>((_) {
          if (mounted &&
              _paginated &&
              (index - _chapter).abs() == 1 &&
              _cachedDisplay(index) != null) {
            setState(() {});
          }
        }, onError: (Object _) {}),
      );
    }
  }

  void _deferContentWarmup(int generation, ReaderContent content) {
    // Borrow frames already driven by the route/reveal. A blocked idle task
    // would continuously reschedule event-loop callbacks during animation;
    // this check never starts a ticker or requests another frame of its own.
    void afterFrame(Duration _) {
      if (!mounted || generation != _contentGeneration) return;
      final route = ModalRoute.of(context);
      final entering =
          route?.animation?.status == AnimationStatus.forward ||
          route?.animation?.status == AnimationStatus.reverse;
      final preparing =
          !_ready ||
          _restoring ||
          (_paginated
              ? !_paged.ready
              : _chapterRevealPending || _chapterReveal.isAnimating);
      if (entering || preparing) {
        WidgetsBinding.instance.addPostFrameCallback(afterFrame);
        return;
      }
      _prefetchAdjacent();
      if (content.paragraphs.any((p) => p.trim() == '[插图]') &&
          widget.repository is OfflineNovelRepository) {
        unawaited(_refreshIllustrations(automatic: true));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(afterFrame);
  }

  Future<ReaderContent> _automaticIllustrations(
    ReaderContent source,
    int chapter,
  ) async {
    if (isLocalBook(widget.novel.id)) return source;
    if (_automaticContent[chapter] case (
      final original,
      final effective,
    ) when identical(original, source)) {
      return effective;
    }
    final local = widget.repository is OfflineNovelRepository
        ? (widget.repository as OfflineNovelRepository).local
        : null;
    if (local == null || local.originals.isEmpty) return source;
    final title = seriesTitleKey(widget.novel.title),
        section = _sourceBook.chapters[chapter];
    final volume = inferLocalSeries(
      '${widget.novel.title} ${section.volumeTitle}',
    )?.number;
    final candidates = <(Novel, NovelChapter)>[];
    for (final book in local.originals) {
      final hint = local.seriesHint(book.id);
      if ((hint?.key ?? seriesTitleKey(book.title)) != title ||
          (volume != null && hint?.number != null && hint!.number != volume)) {
        continue;
      }
      if (book.author != '本地书籍' &&
          seriesTitleKey(book.author) != seriesTitleKey(widget.novel.author)) {
        continue;
      }
      for (final entry in book.chapters) {
        if (seriesTitleKey(entry.title) == seriesTitleKey(section.title)) {
          candidates.add((book, entry));
        }
      }
    }
    ReaderContent result = source;
    var matched = 0;
    // Ambiguous short chapter labels must not trigger a library-wide parse.
    if (candidates.length <= 4) {
      for (final (book, entry) in candidates) {
        try {
          final reference = await ReaderContent.parse(
            await local.chapterContent(book.id, entry),
          );
          final placed = autoIllustrationsFromReference(source, reference);
          if (!identical(placed, source)) {
            result = placed;
            matched++;
          }
        } catch (_) {
          /* A missing reference never blocks the original prose. */
        }
      }
    }
    if (matched != 1) result = source;
    _automaticContent[chapter] = (source, result);
    return result;
  }

  void _continueChapter(int direction) {
    if (!_ready ||
        _restoring ||
        _boundaryQueued ||
        _toolsOpen ||
        _catalogueOpen ||
        _findOpen) {
      return;
    }
    final target = _chapter + direction;
    if (target < 0 || target >= _sourceBook.chapters.length) {
      if (direction > 0) unawaited(_completeReadingAtEnd());
      AppHaptics.play(context, HapticCue.boundary);
      return;
    }
    _verifiedReading.advance();
    AppHaptics.play(context, HapticCue.pageTurn);
    final generation = _contentGeneration;
    _boundaryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _boundaryQueued = false;
      if (!mounted || generation != _contentGeneration) return;
      _go(
        target,
        turnDirection: _paginated ? direction : 0,
        position: _boundaryPosition(target, direction),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  ReadingPosition? _boundaryPosition(int target, int direction) => direction < 0
      ? ReadingPosition(
          chapter: target,
          chapterId: _sourceBook.chapters[target].id,
          offset: 0,
          fraction: 1,
          fontSize: _fontSize,
          width: 0,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        )
      : null;

  void _adoptPagedChapter(int direction) {
    final target = _chapter + direction;
    if (!mounted || target < 0 || target >= _sourceBook.chapters.length) {
      return;
    }
    if (_pageAdvanceOrigin != null) {
      _pageAdvanceOrigin = null;
      _verifiedReading.advance();
    }
    _go(
      target,
      prepared: _cachedDisplay(target),
      position: _boundaryPosition(target, direction),
    );
  }

  double get _scrollChapterOrigin => _scrollStream.originOf(_chapter);
  double get _scrollChapterExtent =>
      _scrollStream.extentOf(_chapter) ??
      (_scroll.hasClients
          ? _scroll.position.maxScrollExtent +
                _scroll.position.viewportDimension
          : 0);
  double get _scrollSeekMaximum => math.max(
    0.0,
    _scrollChapterExtent -
        (_scroll.hasClients ? _scroll.position.viewportDimension : 0),
  );
  double get _scrollChapterMaximum =>
      !_readerPreferences.chapterEntrance &&
          _chapter + 1 < _sourceBook.chapters.length
      ? _scrollChapterExtent
      : _scrollSeekMaximum;

  void _adoptScrollChapter(int index, _PreparedReaderChapter prepared) {
    if (!mounted || _chapter == index || _restoring) return;
    _idleSave?.cancel();
    _chapterSwitchTicket++;
    _pendingChapter = null;
    _paragraphWidgets.removeWhere((key, _) => (key.$1 - index).abs() > 1);
    _clearBookmarkLanding();
    _highlightTimer?.cancel();
    _findMatch.value = null;
    // Natural scrolling changes the source owner, not the viewport, activity,
    // content generation or entrance animation. The same finger/fling carries
    // straight through the next chapter.
    setState(() {
      _chapter = index;
      _currentContent = prepared.content;
      _unfilteredContent = prepared.unfiltered;
      _content = Future.value((content: prepared.content, error: null));
      _paragraphCount = prepared.content.paragraphs.length;
    });
    unawaited(_autoFetchReviews(index));
    _prefetchAdjacent();
    _saveWhenIdle();
  }

  void _showChrome(bool visible) {
    if (visible) {
      _dismissChromeHint?.call();
      _dismissChromeHint = null;
    }
    final changed = _chromeTarget != visible;
    if (changed) {
      unawaited(
        widget.state.setReaderChromeVisible(visible).catchError((Object _) {
          if (mounted) showNovelFeedback(context, '控件显示偏好未保存，请重试');
        }),
      );
    }
    _chromeTarget = visible;
    LocalPlatform.setChromeVisible(visible);
    widget.state.notifyReaderBehaviorChanged();
    if (mounted) setState(() {});
    _animateChrome(visible);
  }

  void _animateChrome(bool visible) {
    if (widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      _chrome.value = visible ? 1 : 0;
    } else if (visible) {
      _chrome.forward();
    } else {
      _chrome.reverse();
    }
  }

  void _scheduleChromeHint() {
    if (!_ready ||
        _chromeTarget ||
        _chromeHintQueued ||
        widget.state.readerChromeHintSeen) {
      return;
    }
    _chromeHintQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      final animation = route?.animation;
      void show() {
        if (!mounted || !_ready || _chromeTarget || route?.isCurrent == false) {
          return;
        }
        _dismissChromeHint = showNovelFeedback(context, '点击屏幕显示控件');
        unawaited(
          widget.state.markReaderChromeHintSeen().catchError((Object _) {}),
        );
      }

      if (animation == null || animation.status == AnimationStatus.completed) {
        show();
      } else {
        void after(AnimationStatus status) {
          if (status == AnimationStatus.completed ||
              status == AnimationStatus.dismissed) {
            animation.removeStatusListener(after);
            if (status == AnimationStatus.completed) show();
          }
        }

        animation.addStatusListener(after);
      }
    });
  }

  void _revealChapter() {
    if (!_chapterRevealPending || !_ready || !_scroll.hasClients) return;
    _chapterRevealPending = false;
    // Reveal the restored viewport, not offscreen paragraphs at chapter start.
    // The anchor render objects remain outside the visual transform so saving,
    // typography changes and lazy restoration keep the same coordinates.
    final first =
        _paragraphRegistry.capture(_scroll.offset + _readingInset)?.index ?? 0;
    if (_chapterRevealFirst != first) {
      setState(() => _chapterRevealFirst = first);
    }
    if (!_readerPreferences.chapterEntrance ||
        widget.state.reduceMotion ||
        MediaQuery.disableAnimationsOf(context)) {
      _chapterReveal.value = 1;
    } else {
      _chapterReveal.forward(from: 0);
    }
  }

  void _toggleChrome() {
    if (_ready && !_toolsOpen && !_catalogueOpen && !_findOpen) {
      AppHaptics.play(context, HapticCue.action);
      _showChrome(!_chromeTarget);
    }
  }

  void _pageBy(int direction) {
    if (_pendingChapter != null && _pendingChapter != _chapter + direction) {
      _chapterSwitchTicket++;
      _pendingChapter = null;
    }
    _cancelExitRequest();
    if (!_ready || _toolsOpen || _catalogueOpen || _findOpen || _noteOpen) {
      return;
    }
    if (_selection.value) {
      AppHaptics.play(context, HapticCue.selection);
      _selection.clear();
      return;
    }
    _stopAutoScroll();
    _suspendListeningFollow();
    if (_paginated) {
      if (!_paged.ready) return;
      _armPageAdvance();
      if (_paged.pageBy(direction)) {
        AppHaptics.play(context, HapticCue.pageTurn);
        return;
      }
      _continueChapter(direction);
      return;
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (_readerPreferences.chapterEntrance &&
        (direction > 0
            ? position.pixels >= position.maxScrollExtent - .5
            : position.pixels <= position.minScrollExtent + .5)) {
      _continueChapter(direction);
      return;
    }
    _scrollStream.prepareAdjacent();
    final target =
        (position.pixels +
                direction *
                    (position.viewportDimension - _readingInset - 100).clamp(
                      80.0,
                      double.infinity,
                    ))
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) {
      _verifiedReading.advance();
    } else if (direction > 0 && _chapter == _sourceBook.chapters.length - 1) {
      unawaited(_completeReadingAtEnd());
    }
    AppHaptics.play(
      context,
      target != position.pixels ? HapticCue.pageTurn : HapticCue.boundary,
    );
    if (widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: NovelMotion.contact,
        curve: NovelMotion.ease,
      );
    }
  }

  Future<String> _requestContent(int index, {bool refresh = false}) async {
    if (_sourceBook.chapters.isEmpty) throw const FormatException('目录为空');
    if (widget.repository case final OfflineNovelRepository offline) {
      await offline.rememberDirectory(_sourceBook);
      if (refresh) {
        return offline.refreshChapterContent(
          widget.novel.id,
          _sourceBook.chapters[index],
        );
      }
    }
    return widget.repository.chapterContent(
      widget.novel.id,
      _sourceBook.chapters[index],
    );
  }

  Future<void> _refreshIllustrations({bool automatic = false}) async {
    if (_illustrationsRefreshing) return;
    final chapter = _chapter;
    final generation = _contentGeneration;
    setState(() => _illustrationsRefreshing = true);
    try {
      final body = automatic
          ? await (widget.repository as OfflineNovelRepository)
                .repairChapterIllustrations(
                  widget.novel.id,
                  _sourceBook.chapters[chapter],
                )
          : await _requestContent(chapter, refresh: true);
      if (body == null) return;
      final source = await ReaderContent.parse(_filterReaderText(body));
      if (!mounted || chapter != _chapter || generation != _contentGeneration) {
        return;
      }
      _preparedContent[chapter] = source;
      final placed = placeIllustrations(
        await _automaticIllustrations(source, chapter),
        widget.state.illustrationsFor(
          widget.novel.id,
          chapterId: _sourceBook.chapters[chapter].id,
        ),
      );
      final localized = await placed.localizedAsync(
        Locale('zh', _readerRegion ?? 'CN'),
      );
      final content = localized.withHiddenLanguages(
        widget.state.hiddenReaderLanguagesFor(widget.novel.id),
        onlyLanguage: widget.state.onlyReaderLanguageFor(widget.novel.id),
      );
      if (!mounted || chapter != _chapter || generation != _contentGeneration) {
        return;
      }
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
      setState(() {
        _currentContent = content;
        _unfilteredContent = localized;
        _preparedDisplay[chapter] = (
          spec: _displaySpec,
          chapter: (content: content, unfiltered: localized),
        );
        _content = Future.value((content: content, error: null));
      });
    } catch (_) {
      if (!automatic && mounted && chapter == _chapter) {
        showNovelFeedback(context, '插图暂未更新成功，正文已保留，可稍后重试');
      }
    } finally {
      if (mounted && generation == _contentGeneration) {
        setState(() => _illustrationsRefreshing = false);
      }
    }
  }

  Widget _paragraphContent(
    List<String> paragraphs,
    int index,
    TextStyle style, {
    bool fullPage = false,
    bool sizedImage = false,
    ReaderContent? content,
    int? sourceChapter,
    Widget? trailing,
  }) {
    final source = content ?? _currentContent;
    final chapter = sourceChapter ?? _chapter;
    void onNote(String id) =>
        _openEpubNote(id, content: source, sourceChapter: chapter);
    if (source?.formats[index]?.rule == true) {
      return const SizedBox(
        height: 24,
        child: Center(child: Divider(indent: 24, endIndent: 24)),
      );
    }
    final url = readerIllustrationUrl(paragraphs[index]);
    if (url != null) {
      final image = ReaderIllustration(
        url: url,
        fitPage: fullPage,
        alignment: switch (source?.formats[index]?.alignment) {
          'right' || 'end' => Alignment.topRight,
          'left' || 'start' => Alignment.topLeft,
          _ => Alignment.topCenter,
        },
        localLayout: LocalImageLayout.fromParagraph(paragraphs[index]),
        fontSize: MediaQuery.textScalerOf(context).scale(style.fontSize ?? 19),
        sizedFrame: sizedImage,
        onOpen: switch (_readerPreferences.imageTap) {
          ReaderImageTap.none => null,
          ReaderImageTap.switchChrome => () {
            AppHaptics.play(context, HapticCue.action);
            _toggleChrome();
          },
          ReaderImageTap.open => () => pushNovelPage<void>(
            context,
            _readerSurface(
              ReaderIllustrationGallery(
                urls: source!.illustrations,
                initialUrl: url,
              ),
            ),
            slot: ReaderIllustrationGallery,
            reduceMotion: widget.state.reduceMotion,
          ),
        },
      );
      final placement = source?.placementIds[index];
      return placement == null
          ? image
          : GestureDetector(
              onLongPress: () {
                AppHaptics.play(context, HapticCue.longPress);
                _removePlacedIllustration(placement);
              },
              child: image,
            );
    }
    if (paragraphs[index].trim() == '[插图]') {
      return ReaderIllustrationFrame(
        fitPage: fullPage,
        child: _illustrationsRefreshing
            ? const LoadingSkeleton(
                layout: SkeletonLayout.cover,
                label: '正在补全插图',
              )
            : ContentPanel(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ArchiveIcon(CupertinoIcons.photo),
                      const SizedBox(height: 10),
                      const AppText('暂未取得本章插图地址'),
                      GlassTextButton(
                        onPressed: () => _refreshIllustrationsFor(chapter),
                        child: const AppText('重试本章插图'),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }
    final format = source?.formats[index];
    if (format?.writing == 'vertical') {
      return ReaderEmbeddedVertical(
        text: paragraphs[index],
        paragraph: index,
        chapter: chapter,
        format: format!,
        style: style,
        preferences: _readerPreferences,
        selection: _selection,
        onNote: onNote,
        annotationChanges: widget.state.underlineChanges,
        annotations: () =>
            _annotationTextMarks(chapter, index, 0, paragraphs[index].length),
      );
    }
    return ReaderSelectionFragment(
      controller: _selection,
      chapter: chapter,
      text: paragraphs[index],
      selectableOffset:
          _readerPreferences.indent && format?.allowsIndent != false
          ? readerIndentLength
          : 0,
      anchorForOffset: (offset) =>
          (paragraph: index, offset: offset.clamp(0, paragraphs[index].length)),
      child: ReaderHighlightText(
        text: paragraphs[index],
        index: index,
        chapter: chapter,
        match: _findMatch,
        underlineChanges: widget.state.underlineChanges,
        annotations: () =>
            _annotationTextMarks(chapter, index, 0, paragraphs[index].length),
        style: style,
        format: format,
        onNote: onNote,
        indent: _readerPreferences.indent && format?.allowsIndent != false
            ? _readerPreferences.indentCount
            : 0,
        trailing: trailing,
        textAlign: _readerPreferences.justify
            ? TextAlign.justify
            : TextAlign.start,
      ),
    );
  }

  Future<void> _refreshIllustrationsFor(int chapter) async {
    if (chapter != _chapter) {
      _go(chapter, prepared: _scrollStream.dataFor(chapter));
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted && chapter == _chapter) await _refreshIllustrations();
  }

  Future<void> _openEpubNote(
    String id, {
    ReaderContent? content,
    int? sourceChapter,
  }) async {
    if (id.startsWith('epub-link:')) {
      final key = id.substring('epub-link:'.length);
      final local = widget.repository is OfflineNovelRepository
          ? (widget.repository as OfflineNovelRepository).local
          : null;
      final target =
          local?.navigationTarget(
            widget.novel.id,
            _sourceBook.chapters[sourceChapter ?? _chapter].id,
            key,
          ) ??
          _sourceBook.navigation?.targets[key];
      if (target != null) {
        AppHaptics.play(context, HapticCue.action);
        _openBookTarget(target);
      } else {
        showNovelFeedback(context, '原书链接的目标暂时无法定位', haptic: HapticCue.error);
      }
      return;
    }
    final note = (content ?? _currentContent)?.notes[id];
    if (note == null ||
        _noteOpen ||
        _toolsOpen ||
        _catalogueOpen ||
        _findOpen) {
      return;
    }
    AppHaptics.play(context, HapticCue.action);
    _noteOpen = true;
    _selection.clear();
    _stopAutoScroll();
    _followTicket++;
    _followScroll.cancel();
    try {
      await showReaderNote(
        context,
        note,
        reduceMotion: widget.state.reduceMotion,
        surfaceWrapper: _readerSurface,
      );
    } finally {
      _noteOpen = false;
      _listeningTarget = null;
    }
  }

  void _openBookTarget(BookReadingTarget target) {
    final index = _sourceBook.chapters.indexWhere(
      (c) => c.id == target.chapterId,
    );
    if (index < 0) return;
    _stopAutoScroll();
    _go(index, position: _bookTargetPosition(_sourceBook, target));
  }

  @override
  void didChangeMetrics() {
    if (!mounted || !_ready || _restoring) return;
    final view = View.of(context);
    final width = view.physicalSize.width / view.devicePixelRatio;
    if ((width - _layoutWidth).abs() < 1) return;
    final position = _currentPosition();
    if (position != null) _prepareRestore(position);
  }

  @override
  void didChangeTextScaleFactor() {
    if (!mounted) return;
    final position = _currentPosition();
    if (position != null) _prepareRestore(position);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _activityForeground = state == AppLifecycleState.resumed;
    _syncReadingActivity();
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopAutoScroll();
      _idleSave?.cancel();
      _savePosition(notify: false);
    }
    _followTicket++;
    _followScroll.cancel();
    _listeningTarget = null;
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listeningChanged();
      });
    }
  }

  void _saveWhenIdle() {
    _idleSave?.cancel();
    if (_restoring) return;
    final generation = _contentGeneration;
    _idleSave = Timer(const Duration(milliseconds: 160), () {
      _idleSave = null;
      if (mounted &&
          generation == _contentGeneration &&
          (_paginated
              ? _paged.ready
              : _scroll.hasClients &&
                    !_scroll.position.isScrollingNotifier.value)) {
        _savePosition(notify: false);
        if (_authoredDirectory && _lastDirectoryOrdinal != _directoryOrdinal) {
          setState(() {});
        }
      }
    });
  }

  void _savePosition({bool notify = true, bool finalSave = false}) {
    // Explicit save/restore/exit supersedes any delayed copy of that position.
    _idleSave?.cancel();
    _idleSave = null;
    if (_detailsOpen ||
        _sourceChanged ||
        !_ready ||
        _restoring ||
        (_paginated ? !_paged.ready : !_scroll.hasClients) ||
        (_typographyPreviewing && !finalSave)) {
      return;
    }
    // Lazy slivers can emit a scroll-end while correcting their estimated
    // extent during layout. Persist after that frame, not from inside layout.
    final duringLayout =
        WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;
    if (duringLayout && !finalSave) {
      if (!_saveQueued) {
        _saveQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _saveQueued = false;
          if (mounted) _savePosition(notify: notify);
        });
      }
      return;
    }
    final position = _currentPosition(includeParagraph: !duringLayout);
    unawaited(
      widget.state
          .savePosition(
            novel: _sourceBook,
            chapter: _chapter,
            offset:
                position?.offset ??
                (_paginated ? _paged.fraction : _scroll.offset),
            maximum: _paginated ? 1 : _scrollSeekMaximum,
            width: _layoutWidth,
            notify: notify,
            paragraphIndex: position?.paragraphIndex,
            paragraphFraction: position?.paragraphFraction ?? 0,
            textOffset: position?.textOffset,
            textScale: _textScale,
            typeface: position?.typeface ?? _layoutTypeface,
            contentRevision: _currentContent?.revision ?? '',
          )
          .catchError((Object _) {}),
    );
  }

  double get _textScale => _layoutTextScale;

  ReadingPosition? _currentPosition({
    bool includeParagraph = true,
    bool bookmark = false,
  }) {
    if (!_ready ||
        _restoring ||
        (_paginated ? !_paged.ready : !_scroll.hasClients) ||
        _sourceBook.chapters.isEmpty) {
      return null;
    }
    if (_paginated) {
      final visible = _paged.anchor;
      final owner = _currentContent?.inlineOwners[visible?.paragraph];
      final anchor = owner == null
          ? visible
          : ReaderTextAnchor(owner, _currentContent!.paragraphs[owner].length);
      return ReadingPosition(
        chapter: _chapter,
        chapterId: _sourceBook.chapters[_chapter].id,
        offset: _paged.fraction,
        fraction: _paged.fraction,
        fontSize: _fontSize,
        lineHeight: _lineHeight,
        width: _layoutWidth,
        textScale: _textScale,
        typeface: _layoutTypeface,
        layout: _layoutKey,
        contentRevision: _currentContent?.revision ?? '',
        paragraphIndex: anchor?.paragraph,
        textOffset: anchor?.offset,
        paragraphFraction: anchor == null
            ? 0
            : anchor.offset /
                  _currentContent!.paragraphs[anchor.paragraph].length.clamp(
                    1,
                    100000000,
                  ),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    final maximum = _scrollSeekMaximum;
    final offsetMaximum = _scrollChapterMaximum;
    final offset = (_scroll.offset - _scrollChapterOrigin).clamp(
      0.0,
      offsetMaximum.clamp(0.0, double.infinity),
    );
    var paragraph =
        includeParagraph &&
            (bookmark || offset > .5 && offset < offsetMaximum - .5)
        ? _paragraphRegistry.capture(
            _scroll.offset + _readingInset,
            clampToLast: bookmark,
          )
        : null;
    if (!includeParagraph) {
      // A route can be disposed inside layout, where reading RenderBox sizes
      // is invalid. Retain an already measured anchor only for the exact same
      // chapter, offset and geometry; otherwise keep the raw-offset fallback.
      final previous = widget.state.positionFor(widget.novel.id);
      if (previous != null &&
          previous.paragraphIndex != null &&
          previous.chapter == _chapter &&
          previous.chapterId == _sourceBook.chapters[_chapter].id &&
          (previous.offset - offset).abs() < .5 &&
          previous.fontSize == _fontSize &&
          previous.lineHeight == _lineHeight &&
          previous.typeface == _layoutTypeface &&
          previous.layout == _layoutKey &&
          (previous.width - _layoutWidth).abs() < .5 &&
          (previous.textScale - _textScale).abs() < .01) {
        paragraph = (
          index: previous.paragraphIndex!,
          fraction: previous.paragraphFraction,
        );
      }
    }
    return ReadingPosition(
      chapter: _chapter,
      chapterId: _sourceBook.chapters[_chapter].id,
      offset: offset,
      fraction: maximum > 0 ? (offset / maximum).clamp(0, 1) : 0,
      fontSize: _fontSize,
      lineHeight: _lineHeight,
      width: _layoutWidth,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      paragraphIndex: paragraph?.index,
      paragraphFraction: paragraph?.fraction ?? 0,
      textOffset: paragraph == null
          ? null
          : includeParagraph
          ? _paragraphRegistry.captureTextOffset(
              paragraph.index,
              _scroll.offset + _readingInset,
            )
          : widget.state.positionFor(widget.novel.id)?.textOffset,
      textScale: _textScale,
      typeface: _layoutTypeface,
      layout: _layoutKey,
      contentRevision: _currentContent?.revision ?? '',
    );
  }

  bool _restoreAlignStart = false;
  bool _alignIosResumeStart(ReadingPosition? position) =>
      LocalPlatform.ios && position?.paragraphIndex != null;

  ReadingPosition _resolveContentPosition(ReadingPosition position) {
    final content = _currentContent;
    final coordinates = content?.coordinateMap;
    if (content == null) return position;
    var resolved = position;
    if (coordinates != null && coordinates.accepts(position.contentRevision)) {
      final target = coordinates.resolve(
        paragraphs: content.paragraphs,
        paragraph: position.paragraphIndex,
        offset: position.textOffset,
        paragraphFraction: position.paragraphFraction,
        fraction: position.fraction,
        revision: position.contentRevision,
      );
      resolved = ReadingPosition.fromJson({
        ...position.toJson(),
        'paragraphIndex': target.paragraph,
        'paragraphFraction': target.fraction,
        'textOffset': target.offset,
        'contentRevision': content.revision,
        'width': 0,
        'layout': '',
        'offset': 0,
      });
    }
    final order = content.readingOrder;
    if (content.languageFilter.isNotEmpty &&
        order != null &&
        order.isNotEmpty &&
        !order.contains(resolved.paragraphIndex)) {
      final anchor = resolved.paragraphIndex;
      final nearest = anchor == null
          ? order[(resolved.fraction * (order.length - 1)).round()]
          : order.where((index) => index >= anchor).firstOrNull ?? order.last;
      return ReadingPosition.fromJson({
        ...resolved.toJson(),
        'paragraphIndex': nearest,
        'paragraphFraction': 0,
        'textOffset': 0,
        'width': 0,
        'layout': '',
        'offset': 0,
      });
    }
    return resolved;
  }

  void _prepareRestore(ReadingPosition position, {bool alignStart = false}) {
    // Rotation/safe-area changes must resume at the saved source sentence,
    // rather than the beginning of a newly packed iOS page.
    _restoreAlignStart = alignStart || _alignIosResumeStart(position);
    _restorePending = _resolveContentPosition(position);
    _restoreQueued = false;
    _restoring = true;
    _restoreTicket++;
  }

  void _clearBookmarkLanding() {
    _bookmarkLandingTimer?.cancel();
    _bookmarkLandingPending = false;
    _bookmarkLanding.value = null;
  }

  void _pagedReady() {
    if (!mounted || !_paginated || !_paged.ready) return;
    final saved = _restorePending;
    _restoreAlignStart = false;
    _restorePending = null;
    _restoring = false;
    _restoreQueued = false;
    _landBookmark(saved);
    _listeningTarget = null;
    _listeningChanged();
    _saveWhenIdle();
    _scheduleAutoPage();
  }

  double _scrollReadingInset(ReaderPreferences preferences) =>
      ((preferences.hideSystemStatus
                  ? 12.0
                  : FrostedHeader.toolbarHeight + 12) -
              preferences.marginTop)
          .clamp(0.0, double.infinity);

  double _systemStatusExtent(BuildContext context) => !_hideSystemStatus
      ? 0
      : _showStatusInfo
      ? ReaderStatusFooter.heightFor(
              context,
              fontSize: _readerPreferences.statusFontSize,
            ) +
            math.max(0, _readerPreferences.statusTopOffset)
      : math.max(
          MediaQuery.viewPaddingOf(context).top,
          AppWindowInsets.viewPaddingOf(context).top,
        );

  double _chromeStatusInset(BuildContext context) => _hideSystemStatus
      ? (_systemStatusExtent(context) - MediaQuery.viewPaddingOf(context).top)
            .clamp(0.0, double.infinity)
      : 0;

  double _readerHeaderTop(BuildContext context) {
    final safe = MediaQuery.viewPaddingOf(context).top;
    return math.max(
      LocalPlatform.ios ? safe : 0,
      safe + _chromeStatusInset(context) - 6,
    );
  }

  Widget _pagedLeaf(
    ReaderLeaf page,
    TextStyle style, {
    ReaderContent? source,
    int? sourceChapter,
    int Function(int paragraph)? reviewCountFor,
    ValueChanged<int>? onReviewTap,
  }) {
    // This leaf may remain on screen as the outgoing chapter. Its deferred
    // builders must keep its source, not consult the next chapter's state.
    final content = source ?? _currentContent!,
        chapterIndex = sourceChapter ?? _chapter;
    if (page.fragments.length == 1 &&
        page.fragments.first.image &&
        readerIllustrationUrl(
              page.fragments.first.text,
            )?.startsWith('wenku-local:') !=
            true) {
      return ReaderTurnPart(
        bounds: page.fragments.first.rect,
        child: _paragraphContent(
          content.paragraphs,
          page.fragments.first.paragraph,
          style,
          fullPage: true,
          content: content,
          sourceChapter: chapterIndex,
        ),
      );
    }
    if (page.vertical) {
      final key = GlobalKey(debugLabel: 'reader-vertical-page');
      Offset? doubleTap;
      Widget verticalPage(
        BuildContext context,
        ({bool active, int? paragraph}) listening,
        Widget? child,
      ) => AnimatedBuilder(
        animation: Listenable.merge([
          _findMatch,
          _bookmarkLanding,
          widget.state.underlineChanges,
        ]),
        builder: (context, _) {
          final selected = _findMatch.value;
          final match =
              selected != null &&
                  (selected.chapter == null || selected.chapter == chapterIndex)
              ? selected
              : null;
          final body = ReaderSelectionFragment(
            controller: _selection,
            chapter: chapterIndex,
            text: page.text,
            paragraphEnds: [
              for (var i = 0; i < page.glyphs.length; i++)
                if (i + 1 == page.glyphs.length ||
                    page.glyphs[i].paragraph != page.glyphs[i + 1].paragraph)
                  page.glyphs[i].end,
            ],
            anchorForOffset: (offset) {
              for (final glyph in page.glyphs) {
                if (glyph.end > offset) {
                  return (
                    paragraph: glyph.paragraph,
                    offset:
                        glyph.sourceStart +
                        (offset - glyph.start).clamp(
                          0,
                          glyph.sourceEnd - glyph.sourceStart,
                        ),
                  );
                }
              }
              return null;
            },
            anchorForEndOffset: (offset) {
              for (final glyph in page.glyphs.reversed) {
                if (glyph.start < offset) {
                  return (
                    paragraph: glyph.paragraph,
                    offset:
                        glyph.sourceStart +
                        (offset - glyph.start).clamp(
                          0,
                          glyph.sourceEnd - glyph.sourceStart,
                        ),
                  );
                }
              }
              return null;
            },
            child: ReaderVerticalText(
              key: key,
              page: page,
              glyphCache: _verticalGlyphs,
              style: style.copyWith(
                fontSize: MediaQuery.textScalerOf(
                  context,
                ).scale(style.fontSize ?? 19),
              ),
              highlightParagraph: _bookmarkLanding.value,
              listeningParagraph: listening.paragraph,
              annotations: widget.state.annotationsFor(
                widget.novel.id,
                chapterId: _sourceBook.chapters[chapterIndex].id,
              ),
              match: match == null
                  ? null
                  : (
                      paragraph: match.paragraph,
                      start: match.start,
                      end: match.end,
                    ),
            ),
          );
          return !listening.active
              ? body
              : GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTapDown: (details) =>
                      doubleTap = details.localPosition,
                  onDoubleTap: () {
                    if (_selection.value || doubleTap == null) return;
                    final render = key.currentContext?.findRenderObject();
                    final glyph = render is RenderReaderVerticalText
                        ? render.glyphAt(doubleTap!)
                        : null;
                    if (glyph != null) {
                      AppHaptics.play(context, HapticCue.action);
                      unawaited(
                        _doubleTapListeningParagraph(
                          glyph.paragraph,
                        ).catchError((Object _) {}),
                      );
                    }
                  },
                  child: body,
                );
        },
      );
      final controller = _listening;
      final body = controller == null
          ? verticalPage(context, (active: false, paragraph: null), null)
          : SelectedValueBuilder<
              ListeningSnapshot,
              ({bool active, int? paragraph})
            >(
              pauseWhenCovered: true,
              listenable: controller.snapshot,
              select: (state) {
                final active =
                    state.active && state.novel?.id == widget.novel.id;
                return (
                  active: active,
                  paragraph: active && state.chapter == chapterIndex
                      ? state.current?.paragraph
                      : null,
                );
              },
              builder: verticalPage,
            );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: body),
          for (final (index, fragment) in page.fragments.indexed)
            if (fragment.image)
              Positioned.fromRect(
                rect: fragment.rect,
                child: ReaderFragmentMotion(
                  fragment: fragment,
                  index: index,
                  count: page.fragments.length,
                  child: _paragraphContent(
                    content.paragraphs,
                    fragment.paragraph,
                    style,
                    sizedImage: true,
                    content: content,
                    sourceChapter: chapterIndex,
                  ),
                ),
              ),
          for (final glyph in page.glyphs)
            if (glyph.note != null)
              Positioned.fromRect(
                rect: glyph.rect.inflate(2),
                child: Semantics(
                  button: true,
                  label: '查看注释',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openEpubNote(
                      glyph.note!,
                      content: content,
                      sourceChapter: chapterIndex,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          for (final fragment in page.fragments)
            if (fragment.rule)
              Positioned.fromRect(
                rect: fragment.rect,
                child: Center(
                  child: Container(
                    width: 1,
                    color: style.color?.withValues(alpha: .4),
                  ),
                ),
              ),
        ],
      );
    }
    return Builder(
      builder: (context) {
        final previous = ReaderReflowScope.maybeOf(context)?.previous.fragments;
        final paragraphs = {
          for (final fragment in page.fragments) fragment.paragraph,
        };
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (index, fragment) in page.fragments.indexed)
              Positioned.fromRect(
                rect: fragment.rect,
                child: ReaderFragmentMotion(
                  fragment: fragment,
                  index: index,
                  count: page.fragments.length,
                  previousBuilder: (old) => _horizontalFragment(
                    old,
                    style,
                    content: content,
                    chapter: chapterIndex,
                  ),
                  child: _horizontalFragment(
                    fragment,
                    style,
                    content: content,
                    chapter: chapterIndex,
                  ),
                ),
              ),
            if (previous != null)
              for (final (index, fragment) in previous.indexed)
                if (!paragraphs.contains(fragment.paragraph))
                  Positioned.fromRect(
                    rect: fragment.rect,
                    child: ReaderLeavingFragment(
                      fragment: fragment,
                      index: index,
                      count: previous.length,
                      child: _horizontalFragment(
                        fragment,
                        style,
                        content: content,
                        chapter: chapterIndex,
                      ),
                    ),
                  ),
            if (reviewCountFor != null && onReviewTap != null)
              ..._pagedReviewBubbles(
                context,
                page,
                content,
                chapterIndex,
                reviewCountFor,
                onReviewTap,
              ),
          ],
        );
      },
    );
  }

  Iterable<Widget> _pagedReviewBubbles(
    BuildContext context,
    ReaderLeaf page,
    ReaderContent content,
    int chapter,
    int Function(int paragraph) countFor,
    ValueChanged<int> onTap,
  ) sync* {
    final seen = <int>{};
    for (final fragment in page.fragments) {
      if (fragment.rule || fragment.image) continue;
      final paragraph = fragment.paragraph;
      if (paragraph < 0 || paragraph >= content.paragraphs.length) continue;
      if (fragment.end < content.paragraphs[paragraph].length) continue;
      if (!seen.add(paragraph)) continue;
      final count = countFor(paragraph);
      if (count == 0) continue;
      final line = fragment.lines.last;
      final width = _ReviewBubble.widthFor(count);
      final top = (fragment.rect.top + line.top + (line.height - 22) / 2).clamp(
        0.0,
        fragment.rect.bottom - 22,
      );
      final alignment =
          content.formats[paragraph]?.textAlign(
            _readerPreferences.justify ? TextAlign.justify : TextAlign.start,
          ) ??
          TextAlign.start;
      final lineWidth = line.width > 0 ? line.width : fragment.rect.width;
      final lineLeft = switch (alignment) {
        TextAlign.center => math.max(
          0.0,
          (fragment.rect.width - lineWidth) / 2,
        ),
        TextAlign.end ||
        TextAlign.right => math.max(0.0, fragment.rect.width - lineWidth),
        _ => 0.0,
      };
      yield Positioned(
        left: fragment.rect.left + lineLeft + lineWidth + 5,
        top: top.toDouble(),
        child: SizedBox(
          width: width,
          child: _reviewBubble(
            count,
            () => onTap(paragraph),
            key: ValueKey('reader-paged-bubble-$chapter-$paragraph'),
          ),
        ),
      );
    }
  }

  Widget _horizontalFragment(
    ReaderPageFragment fragment,
    TextStyle style, {
    required ReaderContent content,
    required int chapter,
  }) => ValueListenableBuilder<int?>(
    valueListenable: _bookmarkLanding,
    child: Builder(
      builder: (context) {
        if (fragment.rule) {
          return const Center(child: Divider(indent: 24, endIndent: 24));
        }
        if (fragment.image) {
          return _paragraphContent(
            content.paragraphs,
            fragment.paragraph,
            style,
            sizedImage: true,
            content: content,
            sourceChapter: chapter,
          );
        }
        final text = ReaderSelectionFragment(
          controller: _selection,
          chapter: chapter,
          text: fragment.text,
          selectableOffset: fragment.indent ? readerIndentLength : 0,
          anchorForOffset: (offset) => (
            paragraph: fragment.paragraph,
            offset: fragment.start + offset.clamp(0, fragment.text.length),
          ),
          child: ReaderHighlightText(
            text: fragment.text,
            index: fragment.paragraph,
            chapter: chapter,
            sourceStart: fragment.start,
            continuesParagraph:
                fragment.end < content.paragraphs[fragment.paragraph].length,
            match: _findMatch,
            underlineChanges: widget.state.underlineChanges,
            annotations: () => _annotationTextMarks(
              chapter,
              fragment.paragraph,
              fragment.start,
              fragment.text.length,
            ),
            style: style,
            format: content.formats[fragment.paragraph]?.slice(
              fragment.start,
              fragment.end,
            ),
            onNote: (id) =>
                _openEpubNote(id, content: content, sourceChapter: chapter),
            indent: fragment.indent ? _readerPreferences.indentCount : 0,
            textAlign: _readerPreferences.justify
                ? TextAlign.justify
                : TextAlign.start,
          ),
        );
        return _listening == null
            ? text
            : ListeningParagraphHighlight(
                controller: _listening!,
                novelId: widget.novel.id,
                chapter: chapter,
                chapterId: _sourceBook.chapters[chapter].id,
                paragraph: fragment.paragraph,
                onDoubleTap: () => _doubleTapListeningParagraph(
                  fragment.paragraph,
                  sourceChapter: chapter,
                ),
                child: text,
              );
      },
    ),
    builder: (context, selected, child) => selected == fragment.paragraph
        ? ReaderLandingHighlight(
            reduceMotion: widget.state.reduceMotion,
            child: child!,
          )
        : child!,
  );

  void _landBookmark(ReadingPosition? saved, {int? paragraphIndex}) {
    if (!_bookmarkLandingPending ||
        (_paginated ? !_paged.ready : !_scroll.hasClients)) {
      return;
    }
    _bookmarkLandingPending = false;
    final savedIndex = paragraphIndex ?? saved?.paragraphIndex;
    final index =
        savedIndex != null && savedIndex >= 0 && savedIndex < _paragraphCount
        ? savedIndex
        : (_paginated
                  ? _paged.anchor?.paragraph
                  : _paragraphRegistry
                        .capture(_scroll.offset + _readingInset)
                        ?.index) ??
              0;
    if (index >= _paragraphCount) return;
    _bookmarkLanding.value = index;
    _bookmarkLandingTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) _bookmarkLanding.value = null;
    });
  }

  void _applyTypography({
    double? fontSize,
    double? lineHeight,
    bool persist = true,
  }) {
    final font = fontSize ?? _fontSize;
    final spacing = lineHeight ?? _lineHeight;
    if (font == _fontSize && spacing == _lineHeight) {
      if (persist) {
        unawaited(
          widget.state
              .setTypography(
                fontSize: fontSize,
                lineHeight: lineHeight,
                bookId: widget.novel.id,
              )
              .catchError((Object _) {
                if (mounted) showNovelFeedback(context, '排版设置保存失败，请重试');
              }),
        );
      }
      return;
    }
    final position = _currentPosition();
    if (position != null) _prepareRestore(position);
    unawaited(
      widget.state
          .setTypography(
            fontSize: fontSize,
            lineHeight: lineHeight,
            persist: persist,
            bookId: widget.novel.id,
          )
          .catchError((Object _) {
            if (mounted) showNovelFeedback(context, '排版设置保存失败，请重试');
          }),
    );
  }

  void _applyReaderPreferences(ReaderPreferences value, bool persist) {
    final changesLayout = value.layoutKey != _readerPreferences.layoutKey;
    if (changesLayout) {
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
    }
    unawaited(
      widget.state
          .setReaderPreferences(
            value,
            persist: persist,
            bookId: widget.novel.id,
          )
          .catchError((Object _) {
            if (mounted) {
              _restoring = false;
              showNovelFeedback(context, '阅读偏好保存失败，请重试');
            }
          }),
    );
  }

  Future<void> _applyStyleScope(bool enabled) async {
    final position = _currentPosition();
    final before = (
      _readerPreferences.layoutKey,
      _fontSize,
      _lineHeight,
      _readerFontId,
    );
    await widget.state.setIndependentReaderStyle(widget.novel.id, enabled);
    final after = (
      _readerPreferences.layoutKey,
      _fontSize,
      _lineHeight,
      _readerFontId,
    );
    if (mounted && position != null && before != after) {
      _prepareRestore(position, alignStart: true);
    }
  }

  Future<void> _applyHiddenLanguages(
    Set<String> hidden, {
    String? onlyLanguage,
  }) async {
    final source = _unfilteredContent;
    if (source == null) return;
    final position = _currentPosition();
    await widget.state.setHiddenReaderLanguages(
      widget.novel.id,
      hidden,
      onlyLanguage: onlyLanguage,
    );
    if (!mounted || !identical(source, _unfilteredContent)) return;
    _selection.clear();
    _stopAutoScroll();
    final content = source.withHiddenLanguages(
      hidden,
      onlyLanguage: onlyLanguage,
    );
    setState(() {
      _currentContent = content;
      _preparedDisplay[_chapter] = (
        spec: _displaySpec,
        chapter: (content: content, unfiltered: source),
      );
      if (position != null) _prepareRestore(position, alignStart: true);
      _content = Future.value((content: content, error: null));
    });
    _prefetchAdjacent();
  }

  Future<void> _applyReaderTypeface(String choice) async {
    final position = _currentPosition();
    final old = _readerFontId;
    await widget.state.setReaderTypeface(choice, bookId: widget.novel.id);
    if (mounted && position != null && old != _readerFontId) {
      _prepareRestore(position);
    }
  }

  Future<ReaderBookmark?> _addBookmark() async {
    final position = _currentPosition(bookmark: true);
    if (position == null) return null;
    _savePosition(notify: false);
    final index = position.paragraphIndex;
    final text = index == null ? '' : _currentContent?.paragraphs[index] ?? '';
    return widget.state.addBookmark(
      novel: _sourceBook,
      position: position,
      quote:
          readerIllustrationUrl(text) == null &&
              text != '[插图]' &&
              text.length <= 12000
          ? text
          : '',
    );
  }

  ReadingPosition? _quotePosition(ReaderQuoteSelection selected) {
    final position = _currentPosition(bookmark: true), anchor = selected.anchor;
    if (position == null || anchor == null) return null;
    final chapter = selected.chapter ?? _chapter;
    if (chapter < 0 || chapter >= _sourceBook.chapters.length) return null;
    final content = chapter == _chapter
        ? _currentContent
        : _scrollStream.dataFor(chapter)?.content;
    return ReadingPosition.fromJson({
      ...position.toJson(),
      'chapter': chapter,
      'chapterId': _sourceBook.chapters[chapter].id,
      'contentRevision': content?.revision ?? '',
      if (chapter != _chapter) ...{'offset': 0, 'width': 0, 'layout': ''},
      'paragraphIndex': anchor.paragraph,
      'textOffset': anchor.offset,
      'paragraphFraction': 0,
    });
  }

  Future<void> _saveQuote(ReaderQuoteSelection selected) =>
      _editQuoteAnnotation(selected, ReaderMarkStyle.highlight);

  Future<ReaderAnnotationContext?> _annotationRangeContext(
    List<ReaderUnderlineRange> ranges,
    ReadingPosition anchor,
  ) async {
    if (!mounted) return null;
    final book = _sourceBook;
    final required = <int>{};
    for (final range in ranges) {
      final index = book.chapters.indexWhere(
        (entry) => entry.id == range.chapterId,
      );
      if (index < 0) return null;
      required.add(index);
    }
    if (required.isEmpty) {
      final index = widget.state.chapterForPosition(book, anchor);
      if (index == null) return null;
      required.add(index);
    }
    final nearby = <int>{
      ...required,
      for (final index in required) ...[index - 1, index + 1],
    };
    final sources = <ReaderAnnotationChapterSource>[];
    for (final index in nearby.toList()..sort()) {
      if (index < 0 || index >= book.chapters.length) continue;
      final content =
          (index == _chapter ? _currentContent : null) ??
          _scrollStream.dataFor(index)?.content ??
          _cachedDisplay(index)?.content ??
          _preparedContent[index];
      if (content == null) {
        if (required.contains(index)) return null;
        continue;
      }
      sources.add(
        ReaderAnnotationChapterSource(
          chapterId: book.chapters[index].id,
          title: book.chapters[index].title,
          content: content,
        ),
      );
    }
    return ReaderAnnotationContext(
      novelId: book.id,
      novel: book,
      chapters: sources,
    );
  }

  List<ReaderTextMark> _annotationTextMarks(
    int chapter,
    int paragraph,
    int sourceStart,
    int length,
  ) {
    if (chapter < 0 || chapter >= _sourceBook.chapters.length) return const [];
    final result = <ReaderTextMark>[];
    for (final annotation in widget.state.annotationsFor(
      widget.novel.id,
      chapterId: _sourceBook.chapters[chapter].id,
    )) {
      final range = annotation.range;
      if (paragraph < range.startParagraph || paragraph > range.endParagraph) {
        continue;
      }
      final start = paragraph == range.startParagraph ? range.startOffset : 0;
      final end = paragraph == range.endParagraph
          ? range.endOffset
          : sourceStart + length;
      final lower = (start - sourceStart).clamp(0, length);
      final upper = (end - sourceStart).clamp(0, length);
      if (upper > lower) {
        result.add(
          ReaderTextMark(lower, upper, annotation.style, annotation.color),
        );
      }
    }
    return result;
  }

  Future<void> _editQuoteAnnotation(
    ReaderQuoteSelection selected,
    ReaderMarkStyle initialStyle,
  ) async {
    final position = _quotePosition(selected);
    if (position == null || selected.ranges.isEmpty) {
      showNovelFeedback(context, '暂时无法定位完整选区，请重新选择');
      return;
    }
    final ranges = <ReaderUnderlineRange>[];
    for (final range in selected.ranges) {
      final chapter = range.chapter ?? _chapter;
      if (chapter < 0 || chapter >= _sourceBook.chapters.length) return;
      final content = chapter == _chapter
          ? _currentContent
          : _scrollStream.dataFor(chapter)?.content ??
                _cachedDisplay(chapter)?.content ??
                _preparedContent[chapter];
      if (content == null) {
        showNovelFeedback(context, '暂时无法定位完整选区，请重新选择');
        return;
      }
      ranges.add(
        ReaderUnderlineRange(
          chapterId: _sourceBook.chapters[chapter].id,
          startParagraph: range.start.paragraph,
          startOffset: range.start.offset,
          endParagraph: range.end.paragraph,
          endOffset: range.end.offset,
          contentRevision: content.revision,
        ),
      );
    }
    _selection.clear();
    _cancelExitRequest();
    _stopAutoScroll();
    _suspendListeningFollow();
    try {
      await showReaderAnnotationEditor(
        context,
        state: widget.state,
        novelId: widget.novel.id,
        novel: _sourceBook,
        position: position,
        ranges: ranges,
        quote: selected.text,
        initialStyle: initialStyle,
        rangeContextResolver: _annotationRangeContext,
        surfaceWrapper: _readerSurface,
      );
    } catch (error) {
      if (mounted) {
        showNovelFeedback(
          context,
          error is FormatException ? error.message : '标记与批注暂时无法打开，请重试',
        );
      }
    }
  }

  Future<void> _lookupQuote(ReaderQuoteSelection selected) async {
    final text = selected.text.trim();
    if (text.isEmpty) return;
    _selection.clear();
    _cancelExitRequest();
    _stopAutoScroll();
    _suspendListeningFollow();
    try {
      final launcher = widget.dictionaryLauncher;
      if (launcher != null) {
        if (!await launcher(text) && mounted) {
          showNovelFeedback(context, '词典暂时无法打开，请重试');
        }
      } else {
        await showReaderDictionarySheet(
          context: context,
          word: text,
          reduceMotion: widget.state.reduceMotion,
          surfaceWrapper: _readerSurface,
        );
      }
    } catch (_) {
      if (mounted) showNovelFeedback(context, '词典暂时无法打开，请重试');
    }
  }

  Future<void> _volumeIllustrations() async {
    _cancelExitRequest();
    _selection.clear();
    _stopAutoScroll();
    _suspendListeningFollow();
    await pushNovelPage<void>(
      context,
      _readerSurface(
        ReaderVolumeIllustrationsPage(
          novel: _sourceBook,
          chapter: _chapter,
          repository: widget.repository,
          known: {..._preparedContent, _chapter: ?_currentContent},
          reduceMotion: widget.state.reduceMotion,
        ),
      ),
      slot: ReaderVolumeIllustrationsPage,
      reduceMotion: widget.state.reduceMotion,
    );
  }

  void _illustrationLayoutChanged() {
    _illustrationGeneration++;
    final source = _preparedContent[_chapter];
    if (!mounted || source == null) return;
    final position = _currentPosition(bookmark: true);
    if (position != null) _prepareRestore(position);
    final localized = placeIllustrations(
      _automaticContent[_chapter]?.$2 ?? source,
      widget.state.illustrationsFor(
        widget.novel.id,
        chapterId: _sourceBook.chapters[_chapter].id,
      ),
    ).localized(Locale('zh', _readerRegion ?? 'CN'));
    final content = localized.withHiddenLanguages(
      widget.state.hiddenReaderLanguagesFor(widget.novel.id),
      onlyLanguage: widget.state.onlyReaderLanguageFor(widget.novel.id),
    );
    setState(() {
      _currentContent = content;
      _unfilteredContent = localized;
      _preparedDisplay[_chapter] = (
        spec: _displaySpec,
        chapter: (content: content, unfiltered: localized),
      );
      _content = Future.value((content: content, error: null));
    });
    _prefetchAdjacent();
  }

  Future<void> _openIllustrationLayout([ReaderQuoteSelection? selected]) async {
    final source = _preparedContent[_chapter];
    final anchor = selected?.anchor;
    if (selected != null &&
        (source == null ||
            anchor == null ||
            anchor.paragraph >= source.paragraphs.length)) {
      return;
    }
    _selection.clear();
    _stopAutoScroll();
    _suspendListeningFollow();
    final inserted = await pushNovelPage<bool>(
      context,
      _readerSurface(
        IllustrationLayoutPage(
          novel: _sourceBook,
          chapter: _chapter,
          state: widget.state,
          repository: widget.repository,
          source: source,
          paragraph: anchor?.paragraph,
        ),
      ),
      slot: IllustrationLayoutPage,
      reduceMotion: widget.state.reduceMotion,
    );
    if (mounted && inserted == true) {
      showNovelFeedback(context, '已嵌入段落之后，长按插图可移除');
    }
  }

  Future<void> _removePlacedIllustration(String id) async {
    if (!await confirmNovelAction(
      context,
      title: '删除插图位置？',
      message: '仅从正文移除这处排版位置，卷末原图和正文保留。',
      confirmLabel: '删除插图位置',
      reduceMotion: widget.state.reduceMotion,
    )) {
      return;
    }
    try {
      await widget.state.removeIllustration(widget.novel.id, id);
    } catch (_) {
      if (mounted) showNovelFeedback(context, '插图位置移除失败，请重试');
    }
  }

  Future<void> _seekProgress(double fraction) async {
    if (!_ready || (_paginated ? !_paged.ready : !_scroll.hasClients)) return;
    _clearBookmarkLanding();
    if (_paginated) {
      _paged.seek(fraction);
      return;
    }
    final value = fraction.clamp(0.0, 1.0);
    final generation = _contentGeneration;
    final ticket = ++_restoreTicket;
    _restoring = true;
    // A lazy sliver refines its estimate after a large jump. Follow that new
    // extent for a bounded number of frames, including an exact chapter end.
    for (var step = 0; step < 4; step++) {
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket ||
          !_scroll.hasClients) {
        return;
      }
      final maximum = _scrollSeekMaximum;
      _scroll.jumpTo(_scrollChapterOrigin + value * maximum);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket ||
          !_scroll.hasClients) {
        return;
      }
      if ((_scrollSeekMaximum - maximum).abs() < .5) break;
    }
    _restoring = false;
    _savePosition(notify: false);
  }

  void _restoreAfterLayout() {
    if (_paginated) return;
    if (_restoreQueued) return;
    _restoreQueued = true;
    final generation = _contentGeneration;
    final ticket = ++_restoreTicket;
    _restoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket ||
          !_scroll.hasClients ||
          !_ready) {
        return;
      }
      final saved = _restorePending;
      _restorePending = null;
      int? landingParagraph;
      if (saved != null) {
        final centreBookmark = _bookmarkLandingPending;
        final viewportBottom = centreBookmark
            ? (_scroll.position.viewportDimension -
                      MediaQuery.paddingOf(context).bottom -
                      96)
                  .clamp(_readingInset + 1, double.infinity)
            : null;
        final sameLayout =
            (saved.fontSize - _fontSize).abs() < .01 &&
            (saved.lineHeight - _lineHeight).abs() < .01 &&
            (saved.width - _layoutWidth).abs() < 1 &&
            (saved.textScale - _textScale).abs() < .01 &&
            saved.typeface == _readerFontId;
        final identicalLayout = sameLayout && saved.layout == _layoutKey;
        var anchor =
            saved.paragraphIndex != null &&
                saved.paragraphIndex! >= 0 &&
                saved.paragraphIndex! < _paragraphCount
            ? (index: saved.paragraphIndex!, fraction: saved.paragraphFraction)
            : null;
        for (var step = 0; step < 10; step++) {
          if (!mounted ||
              generation != _contentGeneration ||
              ticket != _restoreTicket ||
              !_scroll.hasClients) {
            return;
          }
          final origin = _scrollChapterOrigin;
          final maximum = _scrollSeekMaximum;
          final paragraph = anchor == null
              ? null
              : _paragraphRegistry.target(
                  anchor,
                  _readingInset,
                  viewportBottom: viewportBottom,
                  trailingSpace: centreBookmark ? 12 : 0,
                );
          final textOffset = saved.textOffset;
          final fromPaged = readerLayoutIsPaginated(saved.layout);
          final precise =
              fromPaged &&
                  !centreBookmark &&
                  anchor != null &&
                  textOffset != null
              ? _paragraphRegistry.matchOffset(
                  anchor.index,
                  textOffset,
                  textOffset + 1,
                  _readingInset,
                )
              : null;
          final target = identicalLayout && step == 0 && !centreBookmark
              ? origin + saved.offset
              : precise ??
                    paragraph?.offset ??
                    (identicalLayout && saved.fraction < .999
                        ? origin + saved.offset
                        : origin + saved.fraction * maximum);
          if (step == 0 &&
              identicalLayout &&
              !centreBookmark &&
              anchor != null &&
              paragraph?.exact != true) {
            final row =
                _currentContent?.readingOrder?.indexOf(anchor.index) ??
                anchor.index;
            if (row >= 0) {
              _scrollStream.restoreParagraph(
                _chapter,
                row,
                anchor.fraction,
                _readingInset,
              );
            }
          }
          _scroll.jumpTo(
            target.clamp(
              _scroll.position.minScrollExtent,
              centreBookmark && paragraph?.exact == true
                  ? maximum.clamp(0.0, double.infinity)
                  : double.infinity,
            ),
          );
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted ||
              generation != _contentGeneration ||
              ticket != _restoreTicket ||
              !_scroll.hasClients) {
            return;
          }
          // Older bookmarks stored only pixels. Resolve that position once,
          // then use the same paragraph-centred refinement as newer bookmarks.
          if (centreBookmark && anchor == null) {
            anchor = _paragraphRegistry.capture(
              _scroll.offset + _readingInset,
              clampToLast: true,
            );
          }
          final refined = anchor == null
              ? null
              : _paragraphRegistry.target(
                  anchor,
                  _readingInset,
                  viewportBottom: viewportBottom,
                  trailingSpace: centreBookmark ? 12 : 0,
                );
          final preciseRefined =
              fromPaged &&
                  !centreBookmark &&
                  anchor != null &&
                  textOffset != null
              ? _paragraphRegistry.matchOffset(
                  anchor.index,
                  textOffset,
                  textOffset + 1,
                  _readingInset,
                )
              : null;
          if (refined?.exact == true &&
              (_scroll.offset -
                          (preciseRefined ?? refined!.offset).clamp(
                            _scroll.position.minScrollExtent,
                            centreBookmark
                                ? _scroll.position.maxScrollExtent.clamp(
                                    0.0,
                                    double.infinity,
                                  )
                                : double.infinity,
                          ))
                      .abs() <
                  .5) {
            break;
          }
          if (anchor == null && (_scrollSeekMaximum - maximum).abs() < .5) {
            break;
          }
        }
        landingParagraph = anchor?.index;
      }
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket) {
        return;
      }
      _restoring = false;
      if (_autoRunning && !_paginated && !_autoScroll.isActive) {
        _autoLast = null;
        _autoScroll.start();
      }
      _revealChapter();
      _landBookmark(saved, paragraphIndex: landingParagraph);
      _savePosition();
    });
  }

  Future<void> _requestExit() async {
    if (_allowExit) return;
    if (_toolsOpen || _catalogueOpen || _findOpen) {
      _cancelExitRequest();
      return;
    }
    if (_selection.value) {
      _selection.clear();
      _cancelExitRequest();
      return;
    }
    final now = DateTime.now();
    if (_exitRequestedAt == null ||
        now.difference(_exitRequestedAt!) > const Duration(seconds: 2)) {
      _exitRequestedAt = now;
      showNovelFeedback(context, '再滑动一次退出阅读', headerVisibility: _chrome);
      return;
    }
    dismissNovelFeedback(context);
    await _exitReader();
  }

  Future<void> _exitReader() async {
    if (_showingMoment || _allowExit || _exitInProgress) return;
    _exitInProgress = true;
    try {
      if (!await _confirmAddToShelfOnExit() || !mounted) return;
      await _presentReadingMoment();
      if (!mounted) return;
      setState(() => _allowExit = true);
      LocalPlatform.restoreReaderBars();
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } finally {
      _exitInProgress = false;
    }
  }

  Future<bool> _confirmAddToShelfOnExit() async {
    final book = _sourceBook;
    if (!widget.promptAddToShelfOnExit ||
        isLocalBook(book.id) ||
        widget.state.contains(book.id)) {
      return true;
    }
    final add = await confirmNovelAction(
      context,
      title: '加入书架？',
      message: '是否把《${book.title}》加入书架？',
      confirmLabel: '加入书架',
      reduceMotion: widget.state.reduceMotion,
    );
    if (!add || !mounted) return true;
    try {
      await widget.state.setShelfMembership(book.id, true, novel: book);
      return true;
    } catch (_) {
      if (mounted) {
        showNovelFeedback(context, '加入书架失败，请重试', haptic: HapticCue.error);
      }
      return false;
    }
  }

  void _cancelExitRequest() {
    if (_exitRequestedAt == null) return;
    _exitRequestedAt = null;
    dismissNovelFeedback(context);
  }

  void _adoptSourceBook(Novel book) {
    if (!mounted || book.id != widget.novel.id || book.chapters.isEmpty) {
      return;
    }
    final previous = _sourceBook;
    final oldIndex = previous.chapters.isEmpty
        ? 0
        : _chapter.clamp(0, previous.chapters.length - 1);
    final oldChapter = previous.chapters.isEmpty
        ? null
        : previous.chapters[oldIndex];
    final index = oldChapter == null
        ? 0
        : sourceChapterIndex(
            book.chapters,
            oldChapter,
            oldIndex,
            previousCount: previous.chapters.length,
          );
    final position = _currentPosition(bookmark: true);
    final nextPosition = position == null
        ? null
        : ReadingPosition.fromJson({
            ...position.toJson(),
            'chapter': index,
            'chapterId': book.chapters[index].id,
            'contentRevision': '',
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
    _readerBook = book;
    _navigationPreparation = null;
    _chapter = index;
    _chapterSwitchTicket++;
    _chapterTurnDirection = 0;
    _pendingChapter = null;
    _selection.clear();
    _stopAutoScroll();
    _suspendListeningFollow();
    _clearBookmarkLanding();
    _preparedContent.clear();
    _automaticContent.clear();
    _contentLoads.clear();
    _preparedDisplay.clear();
    _displayLoads.clear();
    _currentContent = null;
    _unfilteredContent = null;
    _illustrationsRefreshing = false;
    _ready = false;
    _restorePending = nextPosition;
    _restoreAlignStart = false;
    _restoreQueued = false;
    _restoring = false;
    _restoreTicket++;
    setState(() {
      _content = _loadContent();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _bookDetails() async {
    if (_detailsOpen || _toolsOpen || _catalogueOpen || _findOpen) {
      return;
    }
    _cancelExitRequest();
    _stopAutoScroll();
    _savePosition(notify: false, finalSave: true);
    _detailsOpen = true;
    Object? chapter;
    _detailSwitchedBook = null;
    try {
      chapter = await pushNovelPage<Object>(
        context,
        DetailPage(
          novel: _sourceBook,
          state: widget.state,
          repository: widget.repository,
          fromCache:
              widget.repository is OfflineNovelRepository &&
              (widget.repository as OfflineNovelRepository).offline,
          onRead: (index) => Navigator.of(context).pop(index),
          onReadTarget: (target) => Navigator.of(context).pop(target),
          onSourceSwitched: (book) => _detailSwitchedBook = book,
        ),
        reduceMotion: widget.state.reduceMotion,
        slot: ('reader-details', widget.novel.id),
      );
    } finally {
      _detailsOpen = false;
    }
    if (!mounted) return;
    final switched = _detailSwitchedBook;
    _detailSwitchedBook = null;
    if (switched != null) _adoptSourceBook(switched);
    if (isLocalBook(widget.novel.id) &&
        widget.repository is OfflineNovelRepository) {
      final current = (widget.repository as OfflineNovelRepository).local?.book(
        widget.novel.id,
      );
      if (current == null ||
          current.chapters.length != _sourceBook.chapters.length ||
          current.chapters.indexed.any((entry) {
            final original = _sourceBook.chapters[entry.$1];
            return entry.$2.id != original.id ||
                entry.$2.title != original.title ||
                entry.$2.volumeId != original.volumeId ||
                entry.$2.volumeTitle != original.volumeTitle;
          })) {
        // An editor can delete/regroup/reorder the underlying originals. Its
        // remapped records must not be overwritten by this obsolete directory.
        _sourceChanged = true;
        Navigator.pop(context);
        return;
      }
      setState(() => _readerBook = current);
    }
    if (mounted && chapter is BookReadingTarget) {
      _openBookTarget(chapter);
    } else if (mounted && chapter is int && chapter != _chapter) {
      _go(chapter);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_opening) {
      return _BookOpeningPage(novel: _sourceBook, onOpen: _openReader);
    }
    _lastDirectoryOrdinal = _directoryOrdinal;
    var chapter = _sourceBook.chapters.isEmpty
        ? const NovelChapter('目录为空', '')
        : _sourceBook.chapters[_chapter];
    if (_authoredDirectory) {
      chapter = NovelChapter(
        _sourceBook.readingTitleFor(_chapter),
        chapter.content,
        id: chapter.id,
        volumeId: chapter.volumeId,
        volumeTitle: chapter.volumeTitle,
      );
    }
    _layoutWidth = MediaQuery.sizeOf(context).width;
    _layoutTypeface = _readerFontId;
    final appTheme = Theme.of(context);
    final appDark = appTheme.brightness == Brightness.dark;
    return PopScope<void>(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: ReaderAppearance(
        state: widget.state,
        bookId: widget.novel.id,
        appTheme: appTheme,
        child: Builder(
          builder: (context) => _readerScaffold(context, chapter, appDark),
        ),
      ),
    );
  }

  void _openReader() {
    if (!_opening) return;
    AppHaptics.play(context, HapticCue.action);
    setState(() => _opening = false);
  }

  bool _canHandoff(BuildContext context) {
    final sync = LanSyncScope.maybeOf(context);
    return isLocalBook(widget.novel.id)
        ? sync?.books != null
        : widget.novel.id > 0 && sync?.repository != null;
  }

  double _readerHeaderExtent(BuildContext context) =>
      math.max(46, MediaQuery.textScalerOf(context).scale(16) * 1.25);

  /// 页眉区高度：正文顶部需让出的空间（内边距 + 一行）。
  double _headerZoneExtent(BuildContext context, ReaderPreferences prefs) {
    final line =
        MediaQuery.textScalerOf(context).scale(prefs.statusFontSize) * 1.4;
    return prefs.headerPadding.top + line + prefs.headerPadding.bottom;
  }

  Widget _readerHeader(BuildContext context) => Listener(
    onPointerDown: (_) => _contentTapSurface.commitPreview(),
    child: ReaderChromeLayer(
      key: const ValueKey('reader-chrome-header'),
      animation: _chrome,
      interactionThreshold: 0,
      slide: const Offset(0, -1),
      child: ControlMaterialScope.chrome(
        child: ActiveListenableBuilder(
          listenable: Listenable.merge([
            widget.state.settingsChanges,
            widget.state.historyChanges,
          ]),
          builder: (context) {
            final safe = MediaQuery.viewPaddingOf(context);
            final canOpenDetails =
                widget.directEntry && widget.state.directReading;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16 + safe.left,
                _readerHeaderTop(context),
                16 + safe.right,
                16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 46,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: GlassIconButton(
                            key: const ValueKey('reader-back-entry'),
                            icon: CupertinoIcons.back,
                            label: widget.directEntry ? '返回' : '返回详情',
                            onPressed: () {
                              dismissNovelFeedback(context);
                              unawaited(_exitReader());
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Semantics(
                            button: canOpenDetails,
                            child: JellyTapSurface(
                              key: const ValueKey('reader-title-details'),
                              onTap: canOpenDetails ? _bookDetails : null,
                              haptic: canOpenDetails ? HapticCue.action : null,
                              child: AppText(
                                _sourceBook.title,
                                key: const ValueKey('reader-header-book-title'),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 46,
                        child: GlassIconButton(
                          key: const ValueKey('reader-more-entry'),
                          icon: CupertinoIcons.ellipsis,
                          label: '更多',
                          onPressed: _openReaderMore,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  Future<void> _readerSwitchSource() async {
    final repository = widget.repository;
    final library = repository is OfflineNovelRepository
        ? repository.bookSources
        : null;
    if (library == null) {
      showNovelFeedback(context, '当前版本未启用书源，无法换源', haptic: HapticCue.error);
      return;
    }
    final current = _sourceBook;
    Novel? candidate;
    try {
      await library.prepare();
      if (!mounted) return;
      candidate = await showJellySheet<Novel>(
        context: context,
        reduceMotion: widget.state.reduceMotion,
        heightFactor: .82,
        maxWidth: 720,
        builder: (_) => SourceSwitchSheet(
          novel: current,
          repository: repository,
          library: library,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        showNovelFeedback(
          context,
          error is FormatException ? error.message : '书源列表暂时无法打开',
          haptic: HapticCue.error,
        );
      }
      return;
    }
    if (!mounted || candidate == null) return;
    final chosen = candidate;
    _savePosition(notify: false);
    try {
      final Novel switched;
      if (repository is OfflineNovelRepository) {
        switched = await repository.switchSource(current, chosen);
      } else {
        switched = await library.switchSource(current, chosen);
      }
      _sourceChanged = true;
      await widget.state.applySourceSwitch(
        current,
        switched,
        includeActiveReader: true,
      );
      widget.onSourceSwitched?.call(switched);
      if (!mounted) return;
      showNovelFeedback(
        context,
        '已切换到「${switched.source?.sourceName ?? '新书源'}」',
        haptic: HapticCue.success,
      );
      await _exitReader();
    } on Object catch (error) {
      if (mounted) {
        showNovelFeedback(
          context,
          error is FormatException ? error.message : '换源失败，请稍后重试',
          haptic: HapticCue.error,
        );
      }
    }
  }

  static const List<ReaderMoreEntry> _readerDockCatalog = [
    ReaderMoreEntry(
      id: 'catalogue',
      label: '目录',
      icon: CupertinoIcons.list_bullet,
    ),
    ReaderMoreEntry(
      id: 'bookmarks',
      label: '书签',
      icon: CupertinoIcons.bookmark,
    ),
    ReaderMoreEntry(
      id: 'listening',
      label: '听书',
      icon: CupertinoIcons.headphones,
    ),
    ReaderMoreEntry(id: 'source', label: '换源', icon: CupertinoIcons.arrow_swap),
    ReaderMoreEntry(
      id: 'refresh',
      label: '刷新',
      icon: CupertinoIcons.arrow_clockwise,
    ),
    ReaderMoreEntry(id: 'find', label: '查找', icon: CupertinoIcons.search),
    ReaderMoreEntry(id: 'night', label: '深浅色', icon: CupertinoIcons.moon),
    ReaderMoreEntry(id: 'settings', label: '设置', icon: CupertinoIcons.gear),
  ];

  List<String> get _dockActionIds {
    final known = _readerDockCatalog.map((entry) => entry.id).toSet();
    final picked = [
      for (final id in _readerPreferences.dockActions)
        if (known.contains(id)) id,
    ];
    if (picked.isEmpty) return ReaderPreferences.defaultDockActions;
    return picked.take(6).toList();
  }

  Widget _buildDockAction(BuildContext context, String id) {
    switch (id) {
      case 'catalogue':
        return _readerAction(
          key: const ValueKey('reader-catalogue-entry'),
          icon: CupertinoIcons.list_bullet,
          label: '目录',
          onPressed: _sourceBook.chapters.isEmpty ? null : _catalogue,
        );
      case 'bookmarks':
        return _readerAction(
          key: const ValueKey('reader-bookmarks-entry'),
          icon: CupertinoIcons.bookmark,
          label: '书签',
          onPressed: () =>
              _settings(bookmarks: true, scope: ReaderToolsScope.bookmarks),
        );
      case 'listening':
        return _readerAction(
          key: const ValueKey('reader-dock-listening'),
          icon: CupertinoIcons.headphones,
          label: '听书',
          onPressed: _listening == null ? null : _listen,
        );
      case 'source':
        return _readerAction(
          key: const ValueKey('reader-dock-source'),
          icon: CupertinoIcons.arrow_swap,
          label: '换源',
          onPressed: _readerSwitchSource,
        );
      case 'refresh':
        return _readerAction(
          key: const ValueKey('reader-dock-refresh'),
          icon: CupertinoIcons.arrow_clockwise,
          label: '刷新',
          onPressed: _ready ? _refreshChapterBody : null,
        );
      case 'reviews':
        return _readerAction(
          key: const ValueKey('reader-dock-reviews'),
          icon: CupertinoIcons.chat_bubble,
          label: '段评',
          onPressed: _ready ? () => _openReviews() : null,
        );
      case 'find':
        return _readerAction(
          key: const ValueKey('reader-dock-find'),
          icon: CupertinoIcons.search,
          label: '查找',
          onPressed: _ready ? _findInChapter : null,
        );
      case 'night':
        final dark = _readerPreferences.darkPaper(
          Theme.of(context).brightness == Brightness.dark,
        );
        return _readerAction(
          key: const ValueKey('reader-dock-night'),
          icon: dark ? CupertinoIcons.sun_max : CupertinoIcons.moon,
          label: dark ? '日间' : '夜读',
          activation: _nightIconActivation,
          onPressed: _toggleNightReading,
        );
      case 'settings':
      default:
        return _readerAction(
          key: const ValueKey('reader-dock-settings'),
          icon: CupertinoIcons.gear,
          label: '设置',
          onPressed: () => _settings(),
        );
    }
  }

  void _runDockAction(String id) {
    switch (id) {
      case 'catalogue':
        if (_sourceBook.chapters.isNotEmpty) _catalogue();
      case 'bookmarks':
        _settings(bookmarks: true, scope: ReaderToolsScope.bookmarks);
      case 'listening':
        if (_listening != null) _listen();
      case 'source':
        _readerSwitchSource();
      case 'refresh':
        if (_ready) _refreshChapterBody();
      case 'reviews':
        if (_ready) _openReviews();
      case 'find':
        if (_ready) _findInChapter();
      case 'night':
        _toggleNightReading();
      case 'settings':
        _settings();
    }
  }

  Future<void> _openReaderMore() async {
    final result = await showJellySheet<String>(
      context: context,
      reduceMotion: widget.state.reduceMotion,
      heightFactor: .82,
      maxWidth: 720,
      builder: (_) => ReaderMoreSheet(
        entries: _readerDockCatalog,
        dockActions: _readerPreferences.dockActions,
        onChanged: (list) => _applyReaderPreferences(
          _readerPreferences.copyWith(dockActions: list),
          true,
        ),
      ),
    );
    if (!mounted || result == null) return;
    _runDockAction(result);
  }

  Future<void> _refreshChapterBody() async {
    if (_sourceBook.chapters.isEmpty || !_ready) return;
    showNovelFeedback(context, '正在刷新本章…');
    final future = _loadContent(refresh: true);
    setState(() => _content = future);
    await future;
  }

  void _previewChromeProgress(double value) {
    _pageAdvanceOrigin = null;
    _scrollAdvanceOrigin = null;
    _verifiedReading.resetPending();
    _chromeProgressPending = value;
    final generation = _contentGeneration;
    _chromeProgressFrame ??= SchedulerBinding.instance.scheduleFrameCallback((
      _,
    ) {
      _chromeProgressFrame = null;
      if (!mounted ||
          generation != _contentGeneration ||
          _chromeProgressPending == null) {
        return;
      }
      final target = _chromeProgressPending!.clamp(0.0, 1.0);
      _chromeProgressPending = null;
      if (_paginated) {
        _paged.seek(target);
      } else if (_scroll.hasClients) {
        unawaited(_seekChromeSourceProgress(target, persist: false));
      }
    });
  }

  void _cancelChromeProgress() {
    if (_chromeProgressFrame case final frame?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    }
    _chromeProgressFrame = null;
    _chromeProgressPending = null;
  }

  void _commitChromeProgress(double value) {
    _cancelChromeProgress();
    if (mounted) {
      if (_paginated) {
        unawaited(_seekProgress(value));
      } else {
        unawaited(_seekChromeSourceProgress(value, persist: true));
      }
    }
  }

  double? _scrollSourceFraction(double offset) {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) {
      return null;
    }
    if (offset <= .5) return 0;
    if (_scroll.position.extentAfter <= .5) return 1;
    final content = _currentContent;
    final anchor = _paragraphRegistry.capture(offset, clampToLast: true);
    if (content == null || anchor == null) return null;
    final row = content.readingOrder?.indexOf(anchor.index) ?? anchor.index;
    return ReaderSourceProgress.of(
      content,
    ).fraction((row: row, fraction: anchor.fraction));
  }

  void _reportChromeSourceProgress(double fraction) {
    final content = _currentContent;
    if (!mounted || content == null) return;
    _chromeSourceProgress.value = (
      chapter: _chapter,
      generation: _contentGeneration,
      content: content,
      fraction: fraction,
    );
  }

  Future<void> _seekChromeSourceProgress(
    double fraction, {
    required bool persist,
  }) async {
    final content = _currentContent;
    if (!_ready || !_scroll.hasClients || content == null) return;
    final value = fraction.clamp(0.0, 1.0);
    final source = ReaderSourceProgress.of(content).anchor(value);
    if (source == null) return;
    final paragraph = content.readingOrder?[source.row] ?? source.row;
    final anchor = (index: paragraph, fraction: source.fraction);
    final generation = _contentGeneration, chapter = _chapter;
    final ticket = ++_restoreTicket;
    _restoring = true;
    _idleSave?.cancel();
    _clearBookmarkLanding();
    for (var step = 0; step < 10; step++) {
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket ||
          chapter != _chapter ||
          !_scroll.hasClients) {
        return;
      }
      final origin = _scrollChapterOrigin, maximum = _scrollSeekMaximum;
      final lastRow =
          (content.readingOrder?.length ?? content.paragraphs.length) - 1;
      final lastParagraph = content.readingOrder?[lastRow] ?? lastRow;
      final tail = _paragraphRegistry.target((
        index: lastParagraph,
        fraction: 1.0,
      ), 0);
      final finalChapter = chapter == _sourceBook.chapters.length - 1;
      final safeEnd = finalChapter
          ? _scroll.position.maxScrollExtent
          : tail?.exact == true
          ? math.max(origin, tail!.offset - _scroll.position.viewportDimension)
          : null;
      final measured = _paragraphRegistry.target(anchor, 0);
      if (value > 0 && step == 0 && measured?.exact != true) {
        _scrollStream.restoreParagraph(
          chapter,
          source.row,
          source.fraction,
          value == 1 ? _scroll.position.viewportDimension : 0,
        );
      }
      final target = value == 0
          ? origin
          : value == 1
          ? safeEnd ?? origin + maximum
          : measured?.offset ?? origin + value * maximum;
      _scroll.jumpTo(target.clamp(origin, safeEnd ?? double.infinity));
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket ||
          chapter != _chapter ||
          !_scroll.hasClients) {
        return;
      }
      final refined = _paragraphRegistry.target(anchor, 0);
      final nextTail = _paragraphRegistry.target((
        index: lastParagraph,
        fraction: 1.0,
      ), 0);
      final nextEnd = finalChapter
          ? _scroll.position.maxScrollExtent
          : nextTail?.exact == true
          ? math.max(
              _scrollChapterOrigin,
              nextTail!.offset - _scroll.position.viewportDimension,
            )
          : null;
      if (value == 0) {
        break;
      }
      if (value == 1) {
        if (nextEnd != null && (_scroll.offset - nextEnd).abs() < .5) break;
      } else if (refined?.exact == true &&
          (_scroll.offset -
                      refined!.offset.clamp(
                        _scrollChapterOrigin,
                        nextEnd ?? double.infinity,
                      ))
                  .abs() <
              .5) {
        break;
      }
    }
    _restoring = false;
    final actual = _scrollSourceFraction(_scroll.offset);
    if (actual != null) _reportChromeSourceProgress(actual);
    if (persist) _savePosition(notify: false);
  }

  void _toggleNightReading() {
    setState(() => _nightIconActivation++);
    final preferences = _readerPreferences;
    if (preferences.theme case final theme?) {
      _applyReaderPreferences(
        preferences.copyWith(theme: theme.inverted),
        true,
      );
      return;
    }
    final dark = preferences.darkPaper(
      Theme.of(context).brightness == Brightness.dark,
    );
    if (!dark) _dayPaper = preferences.paper;
    _applyReaderPreferences(
      preferences.copyWith(
        paper: dark ? _dayPaper ?? ReaderPaper.milk : ReaderPaper.night,
      ),
      true,
    );
  }

  Rect? get _readerDockAnchor {
    if (_chrome.value == 0) return null;
    final box = _readerDockKey.currentContext?.findRenderObject();
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (box is! RenderBox ||
        overlay is! RenderBox ||
        !box.hasSize ||
        !box.attached) {
      return null;
    }
    return MatrixUtils.transformRect(
      box.getTransformTo(overlay),
      Offset.zero & box.size,
    );
  }

  Widget _readerAction({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    int activation = 0,
  }) => Expanded(
    child: Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: JellyTapSurface(
        key: key,
        onTap: onPressed,
        child: SizedBox(
          height: DockLayout.heightOf(context),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ArchiveIconContact(
                  pressed: false,
                  activation: activation,
                  child: ArchiveIcon(
                    icon,
                    size: DockLayout.iconSize,
                    color: onPressed == null
                        ? Theme.of(context).disabledColor
                        : null,
                  ),
                ),
                const SizedBox(height: DockLayout.labelGap),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AppText(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: DockLayout.labelFontSize,
                        color: onPressed == null
                            ? Theme.of(context).disabledColor
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _readerBottomControls(BuildContext context) => ActiveListenableBuilder(
    listenable: Listenable.merge([
      widget.state.settingsChanges,
      widget.state.historyChanges,
    ]),
    builder: (context) {
      final generation = _contentGeneration;
      final dockIds = _dockActionIds;
      final dockAnimation = _chrome.drive(
        CurveTween(curve: const Interval(0, .90)),
      );
      final progressAnimation = _chrome.drive(
        CurveTween(curve: const Interval(.10, 1)),
      );
      return ValueListenableBuilder<bool>(
        valueListenable: _followPrompt,
        builder: (context, follow, controls) => ReaderFollowDock(
          visible: _listening != null && follow,
          chrome: _chrome,
          hiddenExtent: math.max(
            0,
            MediaQuery.viewPaddingOf(context).bottom +
                _readerPreferences.marginBottom +
                ReaderScrollLocation.extentOf(context) -
                readerDockBottomPadding(context) -
                (LocalPlatform.ios ? 0 : readerDockPaintPadding.bottom),
          ),
          reduceMotion: widget.state.reduceMotion,
          onEnable: _enableListeningFollow,
          controls: controls!,
        ),
        child: Listener(
          onPointerDown: (_) => _contentTapSurface.commitPreview(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_autoPaused)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassTextButton(
                      key: const ValueKey('reader-auto-resume'),
                      onPressed: _startAutoScroll,
                      child: AppText(_paginated ? '继续自动翻页' : '继续自动滚动'),
                    ),
                  ),
                ReaderChromeLayer(
                  animation: progressAnimation,
                  interactionThreshold: 0,
                  maintainSize: true,
                  slide: const Offset(0, 1.28),
                  curve: NovelMotion.settle,
                  scaleFrom: .90,
                  clip: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: DockLayout.widthFor(5) - 32,
                    ),
                    child: ReaderChromeValueBuilder(
                      visibility: progressAnimation,
                      valueListenable: _chromeSourceProgress,
                      builder: (context, source) {
                        final sourceFraction =
                            !_paginated &&
                                source?.chapter == _chapter &&
                                source?.generation == _contentGeneration &&
                                identical(source?.content, _currentContent)
                            ? source?.fraction
                            : null;
                        return ReaderChapterProgress(
                          key: ValueKey((
                            'reader-chrome-progress',
                            _sourceBook.chapters.isEmpty
                                ? 0
                                : _sourceBook.chapters[_chapter].id,
                          )),
                          compact: true,
                          chapterLabel: _sourceBook.chapters.isEmpty
                              ? '目录为空'
                              : '第${_authoredDirectory ? _directoryOrdinal + 1 : _chapter + 1}章',
                          position: _paginated || sourceFraction != null
                              ? _currentPosition()
                              : null,
                          progressFraction: sourceFraction,
                          onFind: _findInChapter,
                          onSeek: _commitChromeProgress,
                          onPrevious: _chapter > 0
                              ? () => _go(_chapter - 1)
                              : null,
                          onNext: _chapter + 1 < _sourceBook.chapters.length
                              ? () => _go(_chapter + 1)
                              : null,
                          onPreview: (value) {
                            if (generation == _contentGeneration) {
                              _previewChromeProgress(value);
                            }
                          },
                          onCommitted: (value) {
                            if (generation == _contentGeneration) {
                              _commitChromeProgress(value);
                            }
                          },
                          onPreviewChanged: (active) {
                            if (generation != _contentGeneration) return;
                            _chromeProgressActive = active;
                            _typographyPreviewing = active;
                            if (active) {
                              _selection.clear();
                              _stopAutoScroll();
                              _suspendListeningFollow();
                              _clearBookmarkLanding();
                            }
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ReaderChromeLayer(
                  animation: dockAnimation,
                  interactionThreshold: 0,
                  maintainSize: true,
                  slide: const Offset(0, 1),
                  curve: NovelMotion.settle,
                  scaleFrom: .96,
                  clip: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: DockLayout.widthFor(
                        dockIds.length.clamp(1, 6).toInt(),
                      ),
                    ),
                    child: GlassMenuAnchor(
                      child: KeyedSubtree(
                        key: _readerDockKey,
                        child: LiquidGlass(
                          key: const ValueKey('reader-liquid-dock'),
                          radius: DockLayout.heightOf(context) / 2,
                          thickness: 16,
                          padding: const EdgeInsets.symmetric(
                            horizontal: DockLayout.horizontalInset,
                          ),
                          child: Row(
                            children: [
                              for (final id in dockIds)
                                _buildDockAction(context, id),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  // 仅 debug 且 --dart-define=REVIEW_DEMO=true 时用示例段评，便于真机验收；正式包不受影响。
  static const _reviewDemo = bool.fromEnvironment('REVIEW_DEMO');
  static ChapterReviewData _demoReviews(int chapterId) => ChapterReviewData(
    chapterId: chapterId,
    reviewUrl: 'demo://review',
    items: const [
      ParagraphReview(
        content: '这一段写得太好了，鸡皮疙瘩起来了。',
        postTime: '2026-11-20 12:00',
        paraIndex: 0,
      ),
      ParagraphReview(content: '同感，作者这段功力很深。', postTime: '12:05', paraIndex: 1),
      ParagraphReview(
        content: '前面的伏笔在这里收回来了。',
        postTime: '12:09',
        paraIndex: 2,
      ),
    ],
  );

  int _paragraphReviewCount(int chapter, int index, ReaderContent content) {
    final inline = content.reviews[index];
    if (inline != null) return inline.count == 0 ? -2 : inline.count ?? -1;
    if (chapter < 0 || chapter >= _sourceBook.chapters.length) return 0;
    final chapterId = _sourceBook.chapters[chapter].id;
    if (_reviewDemo && chapter == _chapter) {
      final cached = ChapterReviewCache.shared.lookup(
        widget.novel.id,
        chapterId,
      );
      if (cached == null || cached.items.isEmpty) {
        ChapterReviewCache.shared.put(widget.novel.id, _demoReviews(chapterId));
      }
    }
    final data = ChapterReviewCache.shared.lookup(widget.novel.id, chapterId);
    return data?.countFor(index) ?? 0;
  }

  Widget _reviewBubble(int count, VoidCallback onTap, {Key? key}) =>
      _ReviewBubble(key: key, count: count, onTap: onTap);

  Future<void> _autoFetchReviews(int chapterIndex) async {
    if (!mounted || chapterIndex != _chapter) return;
    if (chapterIndex < 0 || chapterIndex >= _sourceBook.chapters.length) return;
    final chapter = _sourceBook.chapters[chapterIndex];
    final cached = ChapterReviewCache.shared.lookup(
      widget.novel.id,
      chapter.id,
    );
    final sourceKey = widget.novel.source?.sourceKey;
    if (cached != null) return;
    if (sourceKey == OfficialBookService.sourceKey(OfficialSite.fanqie)) {
      final paragraphs = _currentContent?.paragraphs ?? const <String>[];
      final bookUrl = widget.novel.source?.bookUrl ?? '';
      final chapterUrl = chapter.sourceUrl ?? '';
      if (paragraphs.isEmpty || bookUrl.isEmpty || chapterUrl.isEmpty) return;
      if (!_reviewsRequested.add(chapter.id)) return;
      final data = await FanqieReviewService().fetch(
        bookId: widget.novel.id,
        chapterId: chapter.id,
        bookUrl: bookUrl,
        chapterUrl: chapterUrl,
        paragraphs: paragraphs,
        loadComments: false,
      );
      if (data != null && mounted && chapterIndex == _chapter) {
        setState(() => _reviewRevision++);
      }
      return;
    }
    if (sourceKey == OfficialBookService.sourceKey(OfficialSite.qimao)) {
      final paragraphs = _currentContent?.paragraphs ?? const <String>[];
      final bookUrl = widget.novel.source?.bookUrl ?? '';
      final chapterUrl = chapter.sourceUrl ?? '';
      if (paragraphs.isEmpty || bookUrl.isEmpty || chapterUrl.isEmpty) return;
      if (!_reviewsRequested.add(chapter.id)) return;
      final data = await QimaoReviewService().fetch(
        bookId: widget.novel.id,
        chapterId: chapter.id,
        bookUrl: bookUrl,
        chapterUrl: chapterUrl,
        paragraphs: paragraphs,
        loadComments: false,
      );
      if (data != null && mounted && chapterIndex == _chapter) {
        setState(() => _reviewRevision++);
      }
      return;
    }
    final repository = widget.repository;
    if (repository is! OfflineNovelRepository || sourceKey == null) return;
    final library = repository.bookSources;
    BookSource? match;
    for (final source in library?.sources ?? const <BookSource>[]) {
      if (source.key == sourceKey) {
        match = source;
        break;
      }
    }
    // 段评依赖书源：只有书源配置了段评规则（ruleReview）才抓取。
    if (match == null || !match.hasReviewRule) return;
    final bookUrl = widget.novel.source?.bookUrl ?? '';
    final chapterUrl = chapter.sourceUrl ?? '';
    if (bookUrl.isEmpty || chapterUrl.isEmpty) return;
    if (!_reviewsRequested.add(chapter.id)) return;
    final data = await ParagraphReviewService().fetch(
      bookId: widget.novel.id,
      chapterId: chapter.id,
      sourceKey: sourceKey,
      bookUrl: bookUrl,
      chapterUrl: chapterUrl,
      rule: match.reviewRule.toMap(),
    );
    if (data != null && mounted && chapterIndex == _chapter) {
      setState(() => _reviewRevision++);
    }
  }

  Future<void> _openReviews({int? paraIndex, InlineReview? inline, int? sourceChapter}) async {
    if (_sourceBook.chapters.isEmpty) return;
    final index = (sourceChapter ?? _chapter).clamp(0, _sourceBook.chapters.length - 1);
    final chapter = _sourceBook.chapters[index];
    if (_reviewDemo &&
        (ChapterReviewCache.shared
                .lookup(widget.novel.id, chapter.id)
                ?.items
                .isEmpty ??
            true)) {
      ChapterReviewCache.shared.put(widget.novel.id, _demoReviews(chapter.id));
    }
    var supports = true;
    BookSource? match;
    final repository = widget.repository;
    final sourceKey = widget.novel.source?.sourceKey;
    final officialQimao =
        sourceKey == OfficialBookService.sourceKey(OfficialSite.qimao);
    final officialFanqie =
        sourceKey == OfficialBookService.sourceKey(OfficialSite.fanqie);
    if (repository is OfflineNovelRepository && sourceKey != null) {
      final library = repository.bookSources;
      for (final source in library?.sources ?? const <BookSource>[]) {
        if (source.key == sourceKey) {
          match = source;
          break;
        }
      }
      supports =
          officialQimao || officialFanqie || (match?.hasReviewRule ?? false);
    }
    if (inline != null && inline.webPlatform != null) {
      final jsLib = match?.raw['jsLib'];
      final url = jsLib is String ? inline.webUrl(jsLib) : null;
      if (url == null) {
        showNovelFeedback(context, '当前书源的段评地址无法识别');
        return;
      }
      await showJellySheet<void>(
        context: context,
        reduceMotion: widget.state.reduceMotion,
        heightFactor: .7,
        maxWidth: 680,
        guardDragDismiss: true,
        builder: (_) => ReaderWebReviewSheet(url: url),
      );
      return;
    }
    final bookUrl = widget.novel.source?.bookUrl ?? '';
    final chapterUrl = chapter.sourceUrl ?? '';
    Future<ChapterReviewData?> Function()? loader;
    var providerLabel = '官方';
    if (inline != null) {
      supports = true;
      providerLabel = '番茄';
      loader = () => FanqieReviewService().fetchInline(inline, chapter.id);
    } else if (officialQimao) {
      providerLabel = '七猫';
      final paragraphs = _currentContent?.paragraphs ?? const <String>[];
      if (paragraphs.isNotEmpty &&
          bookUrl.isNotEmpty &&
          chapterUrl.isNotEmpty) {
        loader = () => QimaoReviewService().fetch(
          bookId: widget.novel.id,
          chapterId: chapter.id,
          bookUrl: bookUrl,
          chapterUrl: chapterUrl,
          paragraphs: paragraphs,
          focusPara: paraIndex,
        );
      }
    } else if (officialFanqie) {
      providerLabel = '番茄';
      final paragraphs = _currentContent?.paragraphs ?? const <String>[];
      if (paragraphs.isNotEmpty &&
          bookUrl.isNotEmpty &&
          chapterUrl.isNotEmpty) {
        loader = () => FanqieReviewService().fetch(
          bookId: widget.novel.id,
          chapterId: chapter.id,
          bookUrl: bookUrl,
          chapterUrl: chapterUrl,
          paragraphs: paragraphs,
          focusPara: paraIndex,
        );
      }
    } else if (supports &&
        sourceKey != null &&
        bookUrl.isNotEmpty &&
        chapterUrl.isNotEmpty) {
      final ruleMap = match?.reviewRule.toMap() ?? const <String, Object?>{};
      loader = () => ParagraphReviewService().fetch(
        bookId: widget.novel.id,
        chapterId: chapter.id,
        sourceKey: sourceKey,
        bookUrl: bookUrl,
        chapterUrl: chapterUrl,
        rule: ruleMap,
      );
    }
    await showJellySheet<void>(
      context: context,
      reduceMotion: widget.state.reduceMotion,
      heightFactor: .7,
      maxWidth: 680,
      builder: (_) => ReaderReviewSheet(
        bookId: widget.novel.id,
        chapterId: chapter.id,
        chapterTitle: _displayChapterTitle(chapter.title),
        sourceSupportsReview: supports,
        loader: loader,
        focusPara: inline?.paragraph ?? paraIndex,
        useChapterCache: inline == null,
        providerLabel: providerLabel,
      ),
    );
    if (mounted) setState(() => _reviewRevision++);
  }

  Widget _readerScrollInformation(
    NovelChapter chapter, {
    bool footer = false,
  }) => ActiveListenableBuilder(
    listenable: widget.state.readerSettingsChanges,
    builder: (context) {
      if (_paginated) return const SizedBox.shrink();
      final preferences = _readerPreferences;
      final safe = MediaQuery.viewPaddingOf(context);
      final dark = Theme.of(context).brightness == Brightness.dark;
      final statusInsets = !footer && preferences.hideSystemStatus
          ? ReaderStatusFooter.horizontalInsetsFor(
              context,
              extra: preferences.statusSideInset,
              fontSize: preferences.statusFontSize,
            )
          : EdgeInsets.zero;
      final headerLine =
          MediaQuery.textScalerOf(context).scale(preferences.statusFontSize) *
          1.4;
      final tipBase = ReaderTipContext(
        bookName: widget.novel.title,
        chapterTitle: readerInformationTitle(
          _displayChapterTitle(chapter.title),
          _sourceBook.directoryIndexFor(_chapter) + 1,
        ),
      );
      final tipInfoStyle = TextStyle(
        fontSize: preferences.statusFontSize,
        height: 1.3,
        color: preferences.controlForeground(dark),
      );
      return Positioned(
        top: footer
            ? null
            : (preferences.hideSystemStatus
                  ? preferences.statusTopOffset
                  : safe.top + preferences.statusTopOffset),
        bottom: footer
            ? MediaQuery.viewPaddingOf(context).bottom +
                  preferences.footerPadding.bottom
            : null,
        left: footer
            ? safe.left + preferences.footerPadding.left
            : safe.left + preferences.headerPadding.left,
        right: footer
            ? safe.right + preferences.footerPadding.right
            : safe.right + preferences.headerPadding.right,
        height: footer
            ? ReaderScrollLocation.extentOf(context)
            : headerLine +
                  preferences.headerPadding.top +
                  preferences.headerPadding.bottom,
        child: ReaderLocationLayer(
          chrome: _chrome,
          interactive: !footer,
          child: RepaintBoundary(
            child: !footer
                ? Padding(
                    padding: EdgeInsets.only(
                      left: math.max(
                        preferences.leftMargin,
                        statusInsets.left - safe.left,
                      ),
                      right: math.max(
                        preferences.rightMargin,
                        statusInsets.right - safe.right,
                      ),
                    ),
                    child: ReaderTipStrip(
                      key: const ValueKey('reader-scroll-header-tip'),
                      tips: ReaderPreferences.fixedHeaderTips,
                      baseContext: tipBase,
                      style: tipInfoStyle,
                    ),
                  )
                : ReaderTipStrip(
                    key: const ValueKey('reader-scroll-footer-tip'),
                    tips: ReaderPreferences.fixedFooterTips,
                    baseContext: tipBase,
                    style: tipInfoStyle,
                  ),
          ),
        ),
      );
    },
  );

  Widget _readerScaffold(
    BuildContext context,
    NovelChapter chapter,
    bool appDark,
  ) => Scaffold(
    // The catalogue owns the keyboard inset; keep the obscured article and
    // its saved scroll geometry fixed while searching in the drawer.
    resizeToAvoidBottomInset: false,
    body: Atmosphere(
      shareGlass: true,
      archiveBackdrop: false,
      child: Stack(
        children: [
          ReaderScreenBinding(
            state: widget.state,
            onPage: _pageBy,
            readerOverlayOpen: () =>
                _toolsOpen || _catalogueOpen || _findOpen || _noteOpen,
          ),
          Positioned.fill(
            child: NativeGlassGroup(
              enabled: false,
              inherit: false,
              child: ReaderArticleBoundary(
                key: const ValueKey('reader-article-boundary'),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                          _pageBy(1),
                      const SingleActivator(LogicalKeyboardKey.space): () =>
                          _pageBy(1),
                      const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                          _pageBy(-1),
                      const SingleActivator(LogicalKeyboardKey.home): () =>
                          _seekProgress(0),
                      const SingleActivator(LogicalKeyboardKey.end): () =>
                          _seekProgress(1),
                      const SingleActivator(
                        LogicalKeyboardKey.keyF,
                        control: true,
                      ): _findInChapter,
                      const SingleActivator(
                        LogicalKeyboardKey.keyF,
                        meta: true,
                      ): _findInChapter,
                    },
                    child: Focus(
                      autofocus: true,
                      child: Semantics(
                        customSemanticsActions: {
                          const CustomSemanticsAction(label: '切换阅读控件'):
                              _toggleChrome,
                        },
                        child: ReaderSelection(
                          controller: _selection,
                          vertical: _readerMode == ReaderMode.vertical,
                          onBookmark: _saveQuote,
                          onDictionary: _lookupQuote,
                          onIllustrations: _volumeIllustrations,
                          onSelect: () {
                            _stopAutoScroll();
                            _suspendListeningFollow();
                          },
                          child: ReaderTouchSurface(
                            canRecord: () =>
                                _activityEligible && !_selection.value,
                            child: ReaderTapSurface(
                              key: const ValueKey('reader-content-tap'),
                              controller: _contentTapSurface,
                              onTapUp: _contentTap,
                              onPreview: _previewContentTap,
                              child: _article(context, chapter, appDark),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: ReaderChromeLayer(
              key: const ValueKey('reader-chrome-edge-blur'),
              animation: _chrome,
              child: ReaderEdgeBlur(
                animation: _chrome,
                topInset:
                    _readerHeaderTop(context) -
                    MediaQuery.viewPaddingOf(context).top,
                headerExtent: _readerHeaderExtent(context),
                compact: _hideSystemStatus,
                blurBottom: true,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _chrome,
            builder: (context, _) {
              final v = _chrome.value.clamp(0.0, 1.0);
              if (v <= 0.01) return const SizedBox.shrink();
              final paper = _readerPreferences.background(appDark);
              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: v,
                    child: Container(
                      height:
                          DockLayout.heightOf(context) +
                          MediaQuery.paddingOf(context).bottom +
                          96,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            paper.withValues(alpha: 0),
                            paper.withValues(alpha: .55),
                            paper.withValues(alpha: .94),
                            paper,
                          ],
                          stops: const [0, .45, .8, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (LocalPlatform.readerAppearance)
            Positioned(
              left: 0,
              width: 20,
              top: MediaQuery.paddingOf(context).top + 80,
              bottom: MediaQuery.paddingOf(context).bottom + 116,
              child: ReaderBrightnessGesture(
                state: widget.state,
                onChanged: _applyReaderPreferences,
                onExitSwipe: LocalPlatform.ios ? _requestExit : null,
              ),
            ),
          _readerScrollInformation(chapter),
          _readerScrollInformation(chapter, footer: true),
          Positioned(top: 0, left: 0, right: 0, child: _readerHeader(context)),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.paddingOf(context).left,
                0,
                MediaQuery.paddingOf(context).right,
                readerDockBottomPadding(context) -
                    (LocalPlatform.ios ? readerDockPaintPadding.bottom : 0),
              ),
              child: Padding(
                key: const ValueKey('reader-chrome-dock'),
                padding: readerDockPaintPadding,
                child: _readerBottomControls(context),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _scrollHeading(
    int index,
    ReaderPreferences prefs,
    bool dark, {
    double fontSize = 19,
    bool continuation = false,
    bool showTitle = true,
  }) => Padding(
    padding: EdgeInsets.fromLTRB(
      prefs.leftMargin,
      (continuation ? 24 : 0) + (prefs.showTitle ? prefs.titleTopSpacing : 0),
      prefs.rightMargin,
      prefs.showTitle ? prefs.titleBottomSpacing : 0,
    ),
    child: Column(
      crossAxisAlignment: prefs.titlePosition == ReaderTitlePosition.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppText(
              _authoredDirectory
                  ? '目录 ${_sourceBook.directoryIndexFor(index) + 1} / ${_sourceBook.directory.length}'
                  : '第 ${index + 1} 章',
              style: TextStyle(
                color: prefs.foreground(dark).withValues(alpha: .65),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ArchiveCode(
                  _authoredDirectory
                      ? 'EPUB / TEXT'
                      : 'CH.${(index + 1).toString().padLeft(3, '0')} / TEXT',
                  color: prefs.foreground(dark).withValues(alpha: .65),
                ),
              ),
            ),
          ],
        ),
        if (showTitle && prefs.showTitle) ...[
          const SizedBox(height: 12),
          AppText(
            _displayBook.readingTitleFor(index),
            key: ValueKey(
              index == _chapter
                  ? 'reader-chapter-title'
                  : 'reader-chapter-title-$index',
            ),
            textAlign: prefs.titleTextAlign,
            style: prefs.titleStyle(
              TextStyle(color: prefs.foreground(dark), fontSize: fontSize),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _scrollFailure(Object? error, VoidCallback retry) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppText(
        error is FormatException
            ? error.message
            : '章节加载失败（${error.runtimeType}: $error）',
      ),
      if (error case final LocalTextReferenceFailure failure)
        if (widget.repository case final OfflineNovelRepository repo
            when repo.local != null)
          LocalTextRecovery(
            books: repo.local!,
            bookId: failure.bookId,
            onChanged: retry,
          ),
      GlassTextButton(onPressed: retry, child: const AppText('重试')),
    ],
  );

  Widget _scrollParagraph(
    BuildContext context,
    int chapter,
    ReaderContent content,
    int row,
    TextStyle style,
  ) {
    final prefs = _readerPreferences, paragraphs = content.paragraphs;
    final index = content.readingOrder?[row] ?? row;
    final registry = _scrollStream.registryFor(chapter)!;
    final reviewCount = _paragraphReviewCount(chapter, index, content);
    final cacheKey = (chapter, index, content, registry, reviewCount);
    if (_paragraphWidgets.remove(cacheKey) case final cached?) {
      _paragraphWidgets[cacheKey] = cached;
      return cached;
    }
    final review = reviewCount != 0 && chapter == _chapter
        ? _reviewBubble(
            reviewCount,
            () => _openReviews(paraIndex: index, inline: content.reviews[index], sourceChapter: chapter),
            key: ValueKey('reader-paragraph-bubble-$index'),
          )
        : null;
    final body = _paragraphContent(
      paragraphs,
      index,
      style,
      content: content,
      sourceChapter: chapter,
      trailing: review,
    );
    Widget prose = Padding(
      padding: EdgeInsets.only(
        top: (content.formats[index] ?? const ReaderRichParagraph()).gapBefore(
          row == 0
              ? null
              : (content.formats[content.readingOrder?[row - 1] ?? row - 1] ??
                    const ReaderRichParagraph()),
          font: MediaQuery.textScalerOf(context).scale(style.fontSize ?? 19),
          lineHeight: style.height ?? 1.72,
          width:
              MediaQuery.sizeOf(context).width -
              prefs.leftMargin -
              prefs.rightMargin,
          defaultGap: prefs.paragraphGap,
          overrideGap: prefs.paragraphGapOverride,
        ),
        bottom: row + 1 == (content.readingOrder?.length ?? paragraphs.length)
            ? prefs.paragraphGap
            : 0,
      ),
      child: ValueListenableBuilder<int?>(
        valueListenable: _bookmarkLanding,
        child: _listening == null
            ? body
            : ListeningParagraphHighlight(
                controller: _listening!,
                novelId: widget.novel.id,
                chapter: chapter,
                chapterId: _sourceBook.chapters[chapter].id,
                paragraph: index,
                onDoubleTap: () =>
                    _doubleTapListeningParagraph(index, sourceChapter: chapter),
                interactive:
                    readerIllustrationUrl(paragraphs[index]) == null &&
                    paragraphs[index].trim() != '[插图]' &&
                    hasSpeechText(paragraphs[index]),
                child: body,
              ),
        builder: (context, selected, child) =>
            selected == index && chapter == _chapter
            ? ReaderLandingHighlight(
                reduceMotion: widget.state.reduceMotion,
                child: child!,
              )
            : child!,
      ),
    );
    if (chapter == _scrollStream.originChapter) {
      prose = LoadedContentItem(
        key: ValueKey('reader-paragraph-reveal-$index'),
        index: row - _chapterRevealFirst,
        animation: _chapterReveal,
        placeholder: const LoadingSkeleton(layout: SkeletonLayout.reader),
        child: prose,
      );
    }
    final child = Padding(
      padding: EdgeInsets.only(
        left: prefs.leftMargin,
        right: prefs.rightMargin,
      ),
      child: content.inlineOwners.containsKey(index)
          ? body
          : ReaderParagraph(
              key: ValueKey('paragraph-anchor-$chapter-$index'),
              registry: registry,
              index: index,
              textOffset: prefs.indent ? readerIndentLength : 0,
              child: prose,
            ),
    );
    if (_paragraphWidgets.length >= 96) {
      _paragraphWidgets.remove(_paragraphWidgets.keys.first);
    }
    return _paragraphWidgets[cacheKey] = child;
  }

  Widget _scrollArticle(
    ReaderPreferences prefs,
    bool dark,
    TextStyle style,
    ReaderContent? content,
    Object? error,
  ) {
    final safe = MediaQuery.viewPaddingOf(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        if (notification is ScrollStartNotification) {
          _idleSave?.cancel();
          if (notification.dragDetails != null) {
            _scrollAdvanceOrigin = notification.metrics.pixels;
            _chapterOverscroll = 0;
            _cancelExitRequest();
            _stopAutoScroll();
            _suspendListeningFollow(userDrag: true);
            _clearBookmarkLanding();
            _restoreTicket++;
            _restorePending = null;
            _restoring = false;
            _revealChapter();
          }
        } else if (notification is OverscrollNotification &&
            notification.dragDetails != null) {
          final delta = notification.overscroll;
          if (_chapterOverscroll.sign != delta.sign) _chapterOverscroll = 0;
          _chapterOverscroll += delta;
        } else if (notification is ScrollEndNotification) {
          final origin = _scrollAdvanceOrigin;
          _scrollAdvanceOrigin = null;
          if (origin != null &&
              _activityEligible &&
              (notification.metrics.pixels - origin).abs() >=
                  math.max(
                    80.0,
                    notification.metrics.viewportDimension * .35,
                  )) {
            _verifiedReading.advance();
          }
          final direction = _chapterOverscroll.abs() >= 36
              ? _chapterOverscroll.sign.toInt()
              : 0;
          _chapterOverscroll = 0;
          if (prefs.chapterEntrance && direction != 0) {
            _continueChapter(direction);
          } else if (direction > 0 &&
              notification.metrics.extentAfter < 1 &&
              _chapter == _sourceBook.chapters.length - 1) {
            unawaited(_completeReadingAtEnd());
          } else {
            _saveWhenIdle();
          }
        }
        return false;
      },
      child: Padding(
        padding: EdgeInsets.only(
          top:
              (prefs.hideSystemStatus
                  ? prefs.statusTopOffset
                  : safe.top + prefs.statusTopOffset) +
              _headerZoneExtent(context, prefs) +
              prefs.marginTop,
          left: safe.left,
          right: safe.right,
          // Hidden information and visible controls share this fixed viewport.
          bottom:
              MediaQuery.viewPaddingOf(context).bottom +
              prefs.footerPadding.bottom +
              ReaderScrollLocation.extentOf(context) +
              prefs.marginBottom,
        ),
        child: ClipRect(
          key: const ValueKey('reader-scroll-safe-viewport'),
          child: content == null
              ? CustomScrollView(
                  key: const ValueKey('reader-scroll'),
                  controller: _scroll,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _scrollHeading(
                        _chapter,
                        prefs,
                        dark,
                        fontSize: _fontSize,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: error == null
                          ? Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: prefs.leftMargin,
                              ),
                              child: const ReaderSkeleton(),
                            )
                          : _scrollFailure(
                              error,
                              () => setState(() {
                                _content = _loadContent();
                              }),
                            ),
                    ),
                  ],
                )
              : ReaderScrollStream<_PreparedReaderChapter>(
                  controller: _scrollStream,
                  scroll: _scroll,
                  deferPreparation: true,
                  continuous: !prefs.chapterEntrance,
                  identity: _contentGeneration,
                  geometry: (
                    prefs.layoutKey,
                    _displaySpec,
                    _fontSize,
                    _lineHeight,
                    _readerFontId,
                    _layoutWidth,
                    _layoutTextScale,
                    prefs.hideSystemStatus,
                    prefs.showStatusInfo,
                  ),
                  chapter: _chapter,
                  data: (
                    content: content,
                    unfiltered: _unfilteredContent ?? content,
                  ),
                  chapterCount: _sourceBook.chapters.length,
                  readingInset: _readingInset,
                  canAdopt: () =>
                      !_restoring &&
                      !_chromeProgressActive &&
                      !_selection.value &&
                      !_toolsOpen &&
                      !_catalogueOpen &&
                      !_findOpen &&
                      !_noteOpen &&
                      _listeningScrollSceneActive,
                  rowCount: (data) =>
                      data.content.readingOrder?.length ??
                      data.content.paragraphs.length,
                  load: _prepareDisplayContent,
                  onChapterChanged: _adoptScrollChapter,
                  pendingBuilder: (context, chapter, error, retry) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 12,
                    ),
                    child: error != null
                        ? _scrollFailure(error, retry)
                        : const SizedBox(
                            height: 72,
                            child: LoadingSkeleton(
                              layout: SkeletonLayout.inline,
                              label: '正在接续章节',
                            ),
                          ),
                  ),
                  itemBuilder: (context, chapter, data, row) {
                    if (row < 0) {
                      return _scrollHeading(
                        chapter,
                        prefs,
                        dark,
                        fontSize: _fontSize,
                        continuation: chapter != _scrollStream.originChapter,
                        showTitle:
                            !isLocalBook(widget.novel.id) ||
                            !readerHasLeadingChapterTitle(
                              data.content,
                              appText(
                                context,
                                _displayBook.readingTitleFor(chapter),
                              ),
                            ),
                      );
                    }
                    final count =
                        data.content.readingOrder?.length ??
                        data.content.paragraphs.length;
                    if (row < count) {
                      return _scrollParagraph(
                        context,
                        chapter,
                        data.content,
                        row,
                        style,
                      );
                    }
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        0,
                        12,
                        0,
                        chapter + 1 == _sourceBook.chapters.length
                            ? 48 +
                                  prefs.marginBottom +
                                  (LocalPlatform.ios ? safe.bottom : 0)
                            : 12,
                      ),
                      child: chapter + 1 < _sourceBook.chapters.length
                          ? Center(
                              child: prefs.chapterEntrance
                                  ? GlassTextButton(
                                      onPressed: () => _continueChapter(1),
                                      child: const AppText('下一章'),
                                    )
                                  : const SizedBox(width: 30, child: Divider()),
                            )
                          : const Center(
                              child: AppText(
                                '已读至当前目录末章',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _article(
    BuildContext context,
    NovelChapter chapter,
    bool dark,
  ) => AnimatedBuilder(
    animation: widget.state.readerSettingsChanges,
    builder: (context, child) =>
        FutureBuilder<({ReaderContent? content, Object? error})>(
          future: _content,
          builder: (context, snapshot) {
            final prefs = _readerPreferences;
            final chapterIndex = _chapter;
            String pageTitle(int index, ReaderTextAnchor anchor) =>
                _displayBook.readingTitleFor(
                  index,
                  paragraph: anchor.paragraph,
                  offset: anchor.offset,
                );
            _layoutKey =
                _currentContent?.layoutKey(prefs.layoutKey) ?? prefs.layoutKey;
            _layoutTextScale =
                MediaQuery.textScalerOf(context).scale(_fontSize) / _fontSize;
            // Scroll offsets are relative to the inset, clipped viewport, not the
            // status bar. Keep that band clear even after all glass is hidden.
            _readingInset = _scrollReadingInset(prefs);
            final content = _currentContent;
            final ready = content != null;
            final failed =
                snapshot.connectionState == ConnectionState.done &&
                (snapshot.hasError || snapshot.data?.error != null);
            _ready = ready;
            if (ready) {
              _restoreAfterLayout();
              _scheduleChromeHint();
            }
            final paragraphs = ready ? content.paragraphs : const <String>[];
            _paragraphCount = paragraphs.length;
            // Pagination must measure the exact resolved style that Text paints,
            // including the theme's leading distribution and fallback metrics.
            // Android emoji/CJK fallback otherwise makes the final line taller
            // than the fragment measured with a standalone partial TextStyle.
            final paragraphStyle = DefaultTextStyle.of(context).style
                .merge(
                  TextStyle(
                    fontFamily: _readerFontFamily ?? 'Roboto',
                    fontSize: _fontSize,
                    height: _lineHeight,
                    letterSpacing: prefs.letterSpacing,
                    fontWeight: prefs.textWeight.weight,
                    fontStyle: prefs.italic
                        ? FontStyle.italic
                        : FontStyle.normal,
                    color: prefs.foreground(dark),
                  ),
                )
                .copyWith(inherit: false);
            final rowSpec = (
              _contentGeneration,
              paragraphStyle,
              prefs.indentCount,
              prefs.justify,
              prefs.paragraphGap,
              prefs.paragraphGapOverride,
              _fontSize,
              _listening,
              _chapterRevealFirst,
              _illustrationsRefreshing,
              widget.state.reduceMotion,
              _reviewRevision,
            );
            if (_paragraphWidgetSpec != rowSpec) {
              _paragraphWidgetSpec = rowSpec;
              _paragraphWidgets.clear();
            }
            final safe = MediaQuery.viewPaddingOf(context);
            // Fixed information rows keep their home-indicator clearance in
            // both chrome states; showing controls never changes this geometry.
            final headerBase = prefs.hideSystemStatus
                ? prefs.statusTopOffset
                : safe.top + prefs.statusTopOffset;
            final pagedPadding = EdgeInsets.fromLTRB(
              prefs.leftMargin + safe.left,
              headerBase + _headerZoneExtent(context, prefs) + prefs.marginTop,
              prefs.rightMargin + safe.right,
              MediaQuery.viewPaddingOf(context).bottom +
                  prefs.footerPadding.bottom +
                  ReaderScrollLocation.extentOf(context) +
                  prefs.marginBottom,
            );
            ReaderPagedChapter? adjacent(int direction) {
              final index = _chapter + direction;
              if (index < 0 || index >= _sourceBook.chapters.length) {
                return null;
              }
              final display = _cachedDisplay(index);
              if (display == null) return null;
              return ReaderPagedChapter(
                key: (widget.novel.id, index),
                content: display.content,
                title: readerInformationTitle(
                  _displayBook.readingTitleFor(index),
                  index + 1,
                ),
                titleForAnchor: (anchor) =>
                    readerInformationTitle(pageTitle(index, anchor), index + 1),
                pageBuilder: (page) => _pagedLeaf(
                  page,
                  paragraphStyle,
                  source: display.content,
                  sourceChapter: index,
                ),
                pageBuilderKey: (
                  display.content,
                  paragraphStyle,
                  prefs.indentCount,
                  prefs.justify,
                  prefs.paragraphGap,
                  prefs.paragraphGapOverride,
                  _listening,
                ),
              );
            }

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: novelSystemUiStyle(
                ThemeData.estimateBrightnessForColor(prefs.background(dark)),
              ),
              child: ReaderBackground(
                store: widget.state.backgrounds,
                preferences: prefs,
                paper: prefs.background(dark),
                reduceMotion: widget.state.reduceMotion,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DefaultTextStyle.merge(
                      style: TextStyle(color: prefs.foreground(dark)),
                      child: _paginated && !ready && !failed
                          ? ReaderPageSkeleton(
                              title: _displayChapterTitle(chapter.title),
                              padding: pagedPadding,
                              style: paragraphStyle,
                              vertical: prefs.mode == ReaderMode.vertical,
                              preferences: prefs,
                              margin: prefs.bindingMargin,
                            )
                          : _paginated && ready
                          ? ReaderPagedView(
                              key: const ValueKey('reader-pages'),
                              chapterKey: (widget.novel.id, _chapter),
                              chapterTurnDirection: _chapterTurnDirection,
                              previousChapter: adjacent(-1),
                              nextChapter: adjacent(1),
                              onChapterTurned: _adoptPagedChapter,
                              content: content,
                              controller: _paged,
                              preferences: prefs,
                              style: paragraphStyle,
                              title: _displayChapterTitle(chapter.title),
                              bookTitle: _sourceBook.title,
                              chrome: _chrome,
                              titleForAnchor: (anchor) =>
                                  readerInformationTitle(
                                    pageTitle(chapterIndex, anchor),
                                    chapterIndex + 1,
                                  ),
                              position: _restorePending,
                              preservePositionStart: _restoreAlignStart,
                              padding: pagedPadding,
                              reduceMotion: widget.state.reduceMotion,
                              onReady: _pagedReady,
                              onChanged: _pagedReadingChanged,
                              onUserScroll: () {
                                _armPageAdvance();
                                _chapterSwitchTicket++;
                                _pendingChapter = null;
                                _cancelExitRequest();
                                _stopAutoScroll();
                                _suspendListeningFollow(userDrag: true);
                                _clearBookmarkLanding();
                              },
                              onBoundary: _pageBy,
                              pageBuilder: (page) => _pagedLeaf(
                                page,
                                paragraphStyle,
                                source: content,
                                sourceChapter: chapterIndex,
                                reviewCountFor: (paragraph) =>
                                    _paragraphReviewCount(
                                      chapterIndex,
                                      paragraph,
                                      content,
                                    ),
                                onReviewTap: (paragraph) =>
                                    _openReviews(paraIndex: paragraph, inline: content.reviews[paragraph], sourceChapter: chapterIndex),
                              ),
                              pageBuilderKey: rowSpec,
                              backgroundBuilder: (child) => ReaderBackground(
                                store: widget.state.backgrounds,
                                preferences: prefs,
                                paper: prefs.background(dark),
                                reduceMotion: widget.state.reduceMotion,
                                child: child,
                              ),
                            )
                          : _scrollArticle(
                              prefs,
                              dark,
                              paragraphStyle,
                              content,
                              snapshot.data?.error ?? snapshot.error,
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
  );

  Future<void> _settings({
    bool bookmarks = false,
    String? initialTab,
    ReaderToolsScope scope = ReaderToolsScope.all,
    bool fromDock = true,
  }) async {
    _cancelExitRequest();
    if (_toolsOpen || _catalogueOpen || _findOpen) return;
    _selection.clear();
    _stopAutoScroll();
    _toolsOpen = true;
    _followTicket++;
    _followScroll.cancel();
    final preview = ValueNotifier(false);

    try {
      final position = _currentPosition();
      final action = await showJellySheet<ReaderToolAction>(
        context: context,
        anchor: fromDock ? _readerDockAnchor : null,
        sourceContext: !fromDock || _chrome.value == 0
            ? null
            : _readerDockKey.currentContext,
        reduceMotion: widget.state.reduceMotion,
        previewing: preview,
        maxWidth: 720,
        maxHeight: math.min(760, MediaQuery.sizeOf(context).height * .86),
        surfaceWrapper: _readerSurface,
        builder: (context) => ReaderTools(
          novel: _sourceBook,
          state: widget.state,
          position: position,
          onAddBookmark: _addBookmark,
          rangeContextResolver: _annotationRangeContext,
          onFontSize: (value) => _applyTypography(fontSize: value),
          onLineHeight: (value) => _applyTypography(lineHeight: value),
          onFontPreview: (value) =>
              _applyTypography(fontSize: value, persist: false),
          onLineHeightPreview: (value) =>
              _applyTypography(lineHeight: value, persist: false),
          onPreviewChanged: (value) {
            _typographyPreviewing = value;
            preview.value = value;
          },
          onReset: () {
            _applyTypography(fontSize: 19, lineHeight: 1.72);
            _applyReaderPreferences(
              _readerPreferences.copyWith(
                margin: 26,
                marginTop: 8,
                marginBottom: 8,
                paragraphGap: 12,
                paragraphGapOverride: false,
                letterSpacing: .1,
                textWeight: ReaderTextWeight.regular,
                indentCount: 0,
                justify: false,
                italic: false,
                titleScale: 1.2,
                titleWeight: ReaderTextWeight.bold,
                titlePosition: ReaderTitlePosition.start,
                titleTopSpacing: 0,
                titleBottomSpacing: 28,
              ),
              true,
            );
          },
          initialBookmarks: bookmarks,
          initialTab: initialTab,
          scope: scope,
          canHandoff: _canHandoff(context),
          listeningBuilder: _listening == null
              ? null
              : (sheetContext) => ListeningPanel(
                  controller: _listening!,
                  novel: _sourceBook,
                  chapter: _chapter,
                  paragraph: position?.paragraphIndex ?? 0,
                  embedded: true,
                  languages: _unfilteredContent?.languages ?? const {},
                  onOpenReader: (target) async {
                    final route = ModalRoute.of(sheetContext);
                    Navigator.pop(sheetContext);
                    if (route != null) await route.completed;
                    if (mounted) await _openListeningReader(target);
                  },
                ),
          onPreferencesChanged: _applyReaderPreferences,
          onStyleScopeChanged: _applyStyleScope,
          onReaderTypefaceChanged: _applyReaderTypeface,
          languages: _unfilteredContent?.languages ?? const {},
          onHiddenLanguagesChanged: _applyHiddenLanguages,
          onIllustrations: isLocalBook(widget.novel.id)
              ? null
              : () => Navigator.pop(context, const ReaderOpenIllustrations()),
        ),
      );
      if (!mounted) return;
      await _handleReaderAction(action);
    } finally {
      _toolsOpen = false;
      _typographyPreviewing = false;
      preview.dispose();
      _listeningTarget = null;
      if (mounted) _listeningChanged();
      _savePosition(notify: false);
    }
  }

  Future<void> _handleReaderAction(ReaderToolAction? action) async {
    switch (action) {
      case ReaderEnterFocus():
        _showChrome(false);
      case ReaderSeekProgress(:final fraction):
        await _seekProgress(fraction);
      case ReaderSeekBookProgress(:final chapter, :final fraction):
        if (chapter == _chapter) {
          await _seekProgress(fraction);
        } else {
          _go(
            chapter,
            position: ReadingPosition(
              chapter: chapter,
              chapterId: _sourceBook.chapters[chapter].id,
              offset: 0,
              fraction: fraction,
              contentRevision: 'current',
              fontSize: _fontSize,
              width: 0,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        }
      case ReaderOpenBookmark(:final bookmark):
        final chapter = widget.state.chapterForPosition(
          _sourceBook,
          bookmark.position,
        );
        if (chapter != null) {
          _go(chapter, position: bookmark.position, highlightBookmark: true);
        }
      case ReaderOpenFind():
        // The settings surface has fully collapsed before opening the next.
        _toolsOpen = false;
        await _findInChapter();
      case ReaderOpenListening():
        _toolsOpen = false;
        await _settings(scope: ReaderToolsScope.listening, fromDock: false);
      case ReaderStartAutoScroll():
        _toolsOpen = false;
        _startAutoScroll();
      case ReaderOpenIllustrations():
        _toolsOpen = false;
        await _openIllustrationLayout();
      case ReaderOpenHandoff():
        _toolsOpen = false;
        await _openHandoff();
      case null:
        break;
    }
  }

  Future<void> _openHandoff() async {
    if (_toolsOpen || _catalogueOpen || _findOpen || _detailsOpen) return;
    final sync = LanSyncScope.maybeOf(context);
    final position = _currentPosition();
    if (!_canHandoff(context) || sync == null || position == null) return;
    _cancelExitRequest();
    _selection.clear();
    _stopAutoScroll();
    _followTicket++;
    _followScroll.cancel();
    _toolsOpen = true;
    try {
      await showJellySheet<void>(
        context: context,
        reduceMotion: widget.state.reduceMotion,
        surfaceWrapper: _readerSurface,
        builder: (_) => LanSendBookSheet(
          sync: sync,
          book: _sourceBook,
          position: position,
          reduceMotion: widget.state.reduceMotion,
        ),
      );
    } finally {
      _toolsOpen = false;
      _savePosition(notify: false);
    }
  }

  void _showFindMatch(ReaderMatch match) {
    _highlightTimer?.cancel();
    _findMatch.value = ReaderMatch(
      match.paragraph,
      match.start,
      match.end,
      chapter: _chapter,
    );
    _highlightTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) _findMatch.value = null;
    });
  }

  Future<void> _findInChapter({bool wholeBook = false}) async {
    _cancelExitRequest();
    final content = _currentContent;
    if (!_ready ||
        content == null ||
        _findOpen ||
        _toolsOpen ||
        _catalogueOpen) {
      return;
    }
    _stopAutoScroll();
    _clearBookmarkLanding();
    _suspendListeningFollow();
    _chapterSwitchTicket++;
    _pendingChapter = null;
    _findOpen = true;
    final generation = _contentGeneration;
    try {
      final result = await showJellySheet<Object>(
        context: context,
        anchor: _readerDockAnchor,
        sourceContext: _chrome.value == 0
            ? null
            : _readerDockKey.currentContext,
        reduceMotion: widget.state.reduceMotion,
        surfaceWrapper: _readerSurface,
        builder: (sheet) => ReaderSearchPanel(
          content: content,
          novel: _sourceBook,
          repository: widget.repository,
          locale: Locale('zh', _readerRegion ?? 'CN'),
          wholeBook: wholeBook,
        ),
      );
      if (!mounted || result == null || generation != _contentGeneration) {
        return;
      }
      if (result is! ReaderMatch) return;
      final match = result;
      if (match.chapter != null && match.chapter != _chapter) {
        final chapter = match.chapter!;
        _go(
          chapter,
          findMatch: match,
          position: ReadingPosition(
            chapter: chapter,
            chapterId: _sourceBook.chapters[chapter].id,
            offset: 0,
            fraction: 0,
            fontSize: _fontSize,
            width: 0,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            paragraphIndex: match.paragraph,
            textOffset: match.start,
          ),
        );
        _showChrome(true);
        return;
      }
      _showFindMatch(match);
      // A manual drag can interrupt lazy positioning before it completes.
      // Expiration belongs to selection, not to successful restoration.
      if (_paginated) {
        _paged.reveal(ReaderTextAnchor(match.paragraph, match.start));
        _saveWhenIdle();
        _showChrome(true);
        return;
      }
      final ticket = ++_restoreTicket;
      _restoring = true;
      for (var step = 0; step < 20; step++) {
        if (!mounted ||
            generation != _contentGeneration ||
            ticket != _restoreTicket ||
            !_scroll.hasClients) {
          return;
        }
        final precise = _paragraphRegistry.matchOffset(
          match.paragraph,
          match.start,
          match.end,
          _readingInset + 8,
        );
        final estimate = _paragraphRegistry.target((
          index: match.paragraph,
          fraction: 0,
        ), _readingInset + 8);
        final target = precise ?? estimate?.offset;
        if (target == null) break;
        _scroll.jumpTo(
          target.clamp(_scroll.position.minScrollExtent, double.infinity),
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            generation != _contentGeneration ||
            ticket != _restoreTicket ||
            !_scroll.hasClients) {
          return;
        }
        final refined = _paragraphRegistry.matchOffset(
          match.paragraph,
          match.start,
          match.end,
          _readingInset + 8,
        );
        if (refined != null &&
            (_scroll.offset -
                        refined.clamp(
                          _scroll.position.minScrollExtent,
                          _scroll.position.maxScrollExtent,
                        ))
                    .abs() <
                1) {
          break;
        }
      }
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket) {
        return;
      }
      _restoring = false;
      _savePosition(notify: false);
      _showChrome(true);
    } finally {
      _findOpen = false;
    }
  }
}
