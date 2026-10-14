import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../bootstrap.dart';
import '../../domain/models/repack.dart';
import '../../ui/prjct_app_bar.dart';
import '../downloads/downloads_page.dart';
import '../repack/repack_page.dart';
import 'source_selector.dart';

/// The repack catalogue.
///
/// Entries come from whichever sources are registered. The prototype named
/// `Fitgirl` directly and fired a full page fetch for every visible grid tile,
/// so scrolling meant unbounded network work.
class LibraryPage extends StatefulWidget {
  final AppEnvironment environment;

  const LibraryPage({super.key, required this.environment});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final TextEditingController _search;
  Timer? _debounce;

  List<GameIndexEntry> _entries = const [];
  bool _loading = true;
  String? _failure;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });

    final source = widget.environment.sources.all.firstOrNull;
    if (source == null) {
      setState(() {
        _loading = false;
        _failure = 'no repack source is registered';
      });
      return;
    }

    final result = await source.fetchFullIndex(onProgress: null);
    if (!mounted) return;
    setState(() {
      _loading = false;
      result.fold(
        (entries) {
          _entries = entries;
          _failure = null;
        },
        (failure) {
          _entries = const [];
          _failure = failure.message;
        },
      );
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // Filtering the full list is cheap, but re-running it per keystroke on a
    // five hundred entry list still costs more than it should.
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = value.trim().toLowerCase());
    });
  }

  List<GameIndexEntry> get _visible {
    if (_query.isEmpty) return _entries;
    return _entries
        .where((entry) => entry.title.toLowerCase().contains(_query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            PrjctAppBar(
              title: 'GAME LIBRARY',
              subtitle: '${_entries.length} repacks indexed',
              searchField: _SearchField(
                controller: _search,
                onChanged: _onSearchChanged,
              ),
              actions: [
                if (widget.environment.sources.all.length > 1)
                  PrjctAppBarAction(
                    icon: Icons.tune,
                    tooltip: 'Choose source',
                    onPressed: _showSourcePicker,
                  ),
                PrjctAppBarAction(
                  icon: Icons.download_outlined,
                  tooltip: 'Downloads',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          DownloadsPage(environment: widget.environment),
                    ),
                  ),
                ),
                PrjctAppBarAction(
                  icon: Icons.refresh,
                  tooltip: 'Re-index',
                  onPressed: _loading ? () {} : _load,
                ),
              ],
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      );
    }
    if (_failure != null) {
      return _Message(
        title: 'Could not build the index',
        body: _failure!,
        action: TextButton(
          onPressed: _load,
          child: const Text('Retry'),
        ),
      );
    }

    final visible = _visible;
    if (visible.isEmpty) {
      return _Message(
        title: 'Nothing matches',
        body: _query.isEmpty
            ? 'No repacks were indexed.'
            : 'No repack title contains "$_query".',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
            childAspectRatio: 0.72,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) =>
              _CoverCard(entry: visible[index], environment: widget.environment),
        );
      },
    );
  }

  static int _columnsFor(double width) {
    if (width < 560) return 2;
    if (width < 900) return 3;
    if (width < 1300) return 4;
    return 6;
  }

  Future<void> _showSourcePicker() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (context) => SourceSelector(sources: widget.environment.sources),
    );
    if (chosen != null) _load();
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search for a game',
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.grey.shade900,
        prefixIcon: const Icon(Icons.search, color: Colors.white54),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// A tile that shows the entry title and only loads artwork.
///
/// The cover is not known until the repack page has been parsed, so the tile
/// deliberately does not fetch it. That is the single change that removes the
/// prototype's fetch-per-visible-tile behaviour.
class _CoverCard extends StatelessWidget {
  final GameIndexEntry entry;
  final AppEnvironment environment;

  const _CoverCard({required this.entry, required this.environment});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(context),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blueAccent.withValues(alpha: .18),
                        Colors.purpleAccent.withValues(alpha: .08),
                      ],
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.videogame_asset, size: 40, color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                entry.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.bebasNeue(
                  fontSize: 19,
                  color: Colors.white,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(
        builder: (context) => RepackPage(
          environment: environment,
          sourceId: environment.sources.ids.first,
          entry: entry,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String title;
  final String body;
  final Widget? action;

  const _Message({required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: GoogleFonts.bebasNeue(fontSize: 24, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
