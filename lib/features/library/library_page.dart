import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../bootstrap.dart';
import '../../data/artwork_service.dart';
import '../../data/catalogue_query.dart';
import '../../ui/app_settings.dart';
import '../../ui/rpck_top_bar.dart';
import '../../ui/skeletons.dart';
import '../../ui/tile_metrics.dart';
import '../downloads/downloads_page.dart';
import '../repack/repack_page.dart';
import '../../storefront/local_repack.dart';
import '../settings/settings_page.dart';
import '../settings/setting_effects.dart';
import 'source_selector.dart';
import 'trending_section.dart';

/// Catalogue home.
///
/// Reads from the on-disk catalogue rather than re-walking every source on
/// each launch, which is what previously made the grid look permanently empty.
class LibraryPage extends StatefulWidget {
  final AppEnvironment environment;

  const LibraryPage({super.key, required this.environment});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  Timer? _debounce;
  String _query = '';
  String? _sourceFilter;
  int _activeTransfers = 0;

  CataloguePage? _page;
  bool _loading = true;
  bool _reindexing = false;
  String _reindexStatus = '';
  bool _needsIndex = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.environment.transfers.snapshots.listen((transfers) {
      if (!mounted) return;
      setState(() {
        _activeTransfers = transfers.where((t) => !t.isTerminal).length;
      });
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int offset = 0}) async {
    setState(() => _loading = true);
    final page = await widget.environment.catalogue.read(
      search: _query,
      sourceId: _sourceFilter,
      limit: 120,
      offset: offset,
      withCover: true,
    );
    if (!mounted) return;
    setState(() {
      _page = offset == 0
          ? page
          : CataloguePage(
              records: [...?_page?.records, ...page.records],
              offset: 0,
              totalEntries: page.totalEntries,
              matchedExactSearch: page.matchedExactSearch,
            );
      _loading = false;
      _needsIndex = page.totalEntries == 0;
    });
  }

  void _onScroll() {
    final page = _page;
    if (page == null || _loading) return;
    final nextPage = page.records.length;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 600) return;
    if (nextPage >= page.totalEntries) return;
    unawaited(_load(offset: nextPage));
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
      unawaited(_load());
    });
  }

  /// Re-walks every source and replaces the stored catalogue.
  Future<void> _reindex() async {
    if (_reindexing) return;
    setState(() {
      _reindexing = true;
      _reindexStatus = 'starting';
    });

    final result = await widget.environment.catalogue.reindex(
      catalog: widget.environment.sources,
      onProgress: (progress) async {
        if (!mounted) return;
        setState(() => _reindexStatus = progress.phase);
      },
    );

    if (!mounted) return;
    result.fold(
      (written) {
        setState(() {
          _reindexing = false;
          _reindexStatus = 'indexed $written repacks';
          _needsIndex = false;
        });
        unawaited(_load());
      },
      (failure) {
        setState(() {
          _reindexing = false;
          _reindexStatus = failure.message;
        });
      },
    );
  }

  Future<void> _clearIndex() async {
    await widget.environment.catalogue.clear();
    if (!mounted) return;
    setState(() {
      _needsIndex = true;
      _reindexStatus = 'catalogue cleared';
    });
    await _load();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsPage(environment: widget.environment),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: [
            RpckTopBar(
              leading: const RpckWordmark(),
              trailing: [
                if (widget.environment.sources.all.length > 1)
                  TopBarAction(
                    icon: Icons.tune_rounded,
                    tooltip: 'Filter source',
                    onPressed: _pickSource,
                    active: _sourceFilter != null,
                  ),
                TopBarAction(
                  icon: Icons.download_rounded,
                  tooltip: 'Downloads',
                  badge: _activeTransfers,
                  onPressed: _openDownloads,
                ),
                TopBarAction(
                  icon: Icons.settings_rounded,
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                ),
              ],
              search: _SearchField(
                controller: _search,
                onChanged: _onSearchChanged,
              ),
            ),
            _StatusStrip(
              total: _page?.totalEntries ?? 0,
              indexedAt: _needsIndex ? null : widget.environment.lastIndexedAt,
              reindexing: _reindexing,
              status: _reindexStatus,
              onReindex: _reindex,
              onClear: _clearIndex,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _page == null) return const SkeletonGrid();

    final records = _page?.records ?? const [];
    if (records.isEmpty) {
      return _EmptyCatalogue(
        indexed: _page?.totalEntries ?? 0,
        searching: _query.isNotEmpty,
        reindexing: _reindexing,
        onReindex: _reindex,
      );
    }

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        if (shouldShowTrending(
          AppSettingsScope.of(context),
          searching: _query.isNotEmpty,
        ))
          SliverToBoxAdapter(
            child: TrendingSection(
              client: widget.environment.storefront,
              localRepacks: _localRepacks,
              onOpenRepack: _openRepack,
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          sliver: SliverToBoxAdapter(
            child: SectionLabel(
              _query.isEmpty ? 'All repacks' : 'Results for "$_query"',
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: tileGridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final record = records[index];
                return _CatalogueTile(
                  title: record.title,
                  sourceId: record.sourceId,
                  url: record.url,
                  coverUrl: record.coverUrl,
                  artwork: widget.environment.artwork,
                  onTap: () => _openRepack(
                    LocalRepack(
                      title: record.title,
                      url: record.url,
                      sourceId: record.sourceId,
                    ),
                  ),
                );
              },
              childCount: records.length,
            ),
          ),
        ),
        if (_loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: RpckTheme.primary,
                  ),
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  /// Locally indexed repacks offered as match candidates for storefront cards.
  ///
  /// Bounded: the trending row is about a dozen cards, so reading the whole
  /// catalogue to match them would be wasteful.
  Future<List<LocalRepack>> _localRepacks() async {
    final page = await widget.environment.catalogue.read(limit: 4000);
    return [
      for (final record in page.records)
        LocalRepack(
          title: record.title,
          url: record.url,
          sourceId: record.sourceId,
        ),
    ];
  }

  void _openRepack(LocalRepack repack) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RepackPage(
          environment: widget.environment,
          sourceId: repack.sourceId,
          url: repack.url,
          title: repack.title,
        ),
      ),
    );
  }

  Future<void> _pickSource() async {
    final chosen = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: context.palette.surfaceHigh,
      builder: (context) => SourceSelector(sources: widget.environment.sources),
    );
    if (chosen == null || !mounted) return;
    setState(() => _sourceFilter = chosen == _sourceFilter ? null : chosen);
    await _load();
  }

  void _openDownloads() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DownloadsPage(environment: widget.environment),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search 7,000 repacks',
          hintStyle: const TextStyle(color: Color(0xFF6E6E6E), fontSize: 15),
          filled: true,
          fillColor: palette.surface,
          isDense: true,
          prefixIcon: Icon(Icons.search_rounded, color: palette.muted, size: 20),
          suffixIcon: IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: palette.muted),
            onPressed: () {
              controller.clear();
              onChanged('');
            },
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.hairline),
          ),
        ),
      ),
    );
  }
}

/// Shows the stored count, when it was built, and the reindex control.
class _StatusStrip extends StatelessWidget {
  final int total;
  final DateTime? indexedAt;
  final bool reindexing;
  final String status;
  final VoidCallback onReindex;
  final VoidCallback onClear;

  const _StatusStrip({
    required this.total,
    required this.indexedAt,
    required this.reindexing,
    required this.status,
    required this.onReindex,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              status.isNotEmpty
                  ? status
                  : total == 0
                      ? 'catalogue empty'
                      : '$total repacks · ${_relative(indexedAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.bebasNeue(
                fontSize: 15,
                color: reindexing ? RpckTheme.primary : palette.muted,
                letterSpacing: 1.2,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: reindexing ? null : onReindex,
            icon: reindexing
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: RpckTheme.primary,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 17),
            label: Text(reindexing ? 'Indexing' : 'Reindex'),
            style: TextButton.styleFrom(
              foregroundColor: RpckTheme.primary,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (total > 0)
            IconButton(
              tooltip: 'Clear catalogue',
              onPressed: reindexing ? null : onClear,
              icon: Icon(Icons.delete_outline_rounded,
                  size: 18, color: palette.muted),
            ),
        ],
      ),
    );
  }

  static String _relative(DateTime? when) {
    if (when == null) return 'never indexed';
    final delta = DateTime.now().difference(when);
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }
}

/// A catalogue tile that fills its artwork in once, on demand.
class _CatalogueTile extends StatefulWidget {
  final String title;
  final String sourceId;
  final String url;
  final String? coverUrl;
  final ArtworkService artwork;
  final VoidCallback onTap;

  const _CatalogueTile({
    required this.title,
    required this.sourceId,
    required this.url,
    required this.artwork,
    required this.onTap,
    this.coverUrl,
  });

  @override
  State<_CatalogueTile> createState() => _CatalogueTileState();
}

class _CatalogueTileState extends State<_CatalogueTile> {
  String? _cover;

  @override
  void initState() {
    super.initState();
    final cached = widget.coverUrl;
    if (cached != null && cached.isNotEmpty) {
      _cover = cached;
      return;
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    final cover = await widget.artwork.coverFor(
      CoverRequest(
        sourceId: widget.sourceId,
        url: widget.url,
        title: widget.title,
        cachedCoverUrl: widget.coverUrl,
      ),
    );
    if (!mounted || cover == null) return;
    setState(() => _cover = cover);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: widget.onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Artwork(coverUrl: _cover)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.bebasNeue(
                      fontSize: 17,
                      color: Colors.white,
                      letterSpacing: .6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.sourceId,
                    style: TextStyle(color: palette.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders cover art, or the skeleton until one exists.
class _Artwork extends StatelessWidget {
  final String? coverUrl;

  const _Artwork({this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final url = coverUrl;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: url == null
            ? const SkeletonBox(width: double.infinity, height: double.infinity, radius: 12)
            : CachedNetworkImage(
                imageUrl: url,
                width: double.infinity,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (_, __) => const SkeletonBox(
                  width: double.infinity,
                  height: double.infinity,
                  radius: 12,
                ),
                errorWidget: (_, __, ___) => Container(
                  color: palette.surfaceHigh,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported_outlined,
                      color: Color(0x33FFFFFF)),
                ),
              ),
      ),
    );
  }
}

class _EmptyCatalogue extends StatelessWidget {
  final int indexed;
  final bool searching;
  final bool reindexing;
  final VoidCallback onReindex;

  const _EmptyCatalogue({
    required this.indexed,
    required this.searching,
    required this.reindexing,
    required this.onReindex,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final title = searching
        ? 'No matches'
        : indexed == 0
            ? 'Catalogue is empty'
            : 'Nothing to show';
    final body = searching
        ? 'No repack title contains that search.'
        : indexed == 0
            ? 'Build the index once to get the full catalogue. It takes about '
                'a minute and a half over 148 pages.'
            : 'The stored catalogue has no rows.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 52, color: Color(0x33FFFFFF)),
            const SizedBox(height: 18),
            Text(
              title,
              style: GoogleFonts.bebasNeue(fontSize: 24, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, fontSize: 14, height: 1.5),
            ),
            if (!searching) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: reindexing ? null : onReindex,
                icon: reindexing
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: Text(reindexing ? 'Indexing…' : 'Build index'),
                style: FilledButton.styleFrom(
                  backgroundColor: RpckTheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}