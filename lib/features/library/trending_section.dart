import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../storefront/local_repack.dart';
import '../../storefront/storefront_client.dart';
import '../../storefront/title_matcher.dart';
import '../../ui/rpck_top_bar.dart';
import '../../ui/skeletons.dart';

/// Trending storefront games, matched to the local catalogue where possible.
///
/// Sits above the catalogue on the library home. The match lets a storefront
/// card link straight into the repack listings for the same game.
class TrendingSection extends StatefulWidget {
  final StorefrontClient client;

  /// Repacks already indexed locally, offered as match candidates.
  final Future<List<LocalRepack>> Function() localRepacks;

  /// Opens the matched repack. The card is inert unless this is supplied, so a
  /// match alone never implies navigation.
  final void Function(LocalRepack repack)? onOpenRepack;

  const TrendingSection({
    super.key,
    required this.client,
    required this.localRepacks,
    this.onOpenRepack,
  });

  @override
  State<TrendingSection> createState() => _TrendingSectionState();
}

class _TrendingSectionState extends State<TrendingSection> {
  List<StorefrontGame> _games = const [];
  Map<String, LocalRepack> _matches = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final trending = await widget.client.trending(
      categories: const ['top_sellers', 'new_releases'],
      perCategory: 8,
    );
    if (!mounted) return;

    final games = trending.valueOrNull;
    if (games == null) {
      setState(() {
        _loading = false;
        _error = trending.failureOrNull?.message ?? 'trending unavailable';
      });
      return;
    }

    var locals = const <LocalRepack>[];
    try {
      locals = await widget.localRepacks();
    } catch (_) {
      // Matching is an enhancement; the cards still render without it.
    }
    if (!mounted) return;

    final matches = <String, LocalRepack>{};
    if (locals.isNotEmpty) {
      for (final game in games) {
        final match = bestLocalMatch(game.title, locals);
        if (match != null) matches[game.title] = match.repack;
      }
    }

    setState(() {
      _games = games;
      _matches = matches;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 210,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SkeletonBox(width: double.infinity, height: double.infinity,
              radius: 16),
        ),
      );
    }
    if (_error != null || _games.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Trending now'),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _games.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final game = _games[index];
              final LocalRepack? repack = _matches[game.title];
              return _TrendingCard(
                game: game,
                repack: repack,
                onTap: repack == null || widget.onOpenRepack == null
                    ? null
                    : () => widget.onOpenRepack!(repack),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrendingCard extends StatelessWidget {
  final StorefrontGame game;
  final LocalRepack? repack;
  final VoidCallback? onTap;

  const _TrendingCard({
    required this.game,
    required this.repack,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 268,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: RpckTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: RpckTheme.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 106,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13),
                  ),
                  child: game.headerImage == null
                      ? const ColoredBox(
                          color: RpckTheme.surfaceHigh,
                          child: Icon(Icons.sports_esports_rounded,
                              color: Color(0x33FFFFFF)),
                        )
                      : CachedNetworkImage(
                          imageUrl: game.headerImage!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              const ColoredBox(color: RpckTheme.surfaceHigh),
                          errorWidget: (_, __, ___) => const ColoredBox(
                            color: RpckTheme.surfaceHigh,
                            child: Icon(Icons.image_not_supported_outlined,
                                color: Color(0x33FFFFFF)),
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (repack != null) ...[
                          const Icon(Icons.download_rounded,
                              size: 13, color: RpckTheme.primary),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Repack available',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: RpckTheme.primary,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ] else
                          const Text(
                            'Not in the catalogue',
                            style: TextStyle(color: RpckTheme.muted, fontSize: 11.5),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}