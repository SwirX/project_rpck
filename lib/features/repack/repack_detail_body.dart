import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../domain/models/repack.dart';
import '../../domain/models/source_option.dart';
import '../../ui/rpck_top_bar.dart';
import '../../ui/skeletons.dart';
import 'repack_page.dart' show StorefrontDetail;

/// Body of a repack page, split out so it can be rendered and tested without a
/// live source adapter.
class RepackDetailBody extends StatelessWidget {
  final String title;
  final String sourceId;
  final Repack? repack;
  final StorefrontDetail? storefront;
  final bool loadingRepack;
  final void Function(SourceOption option) onStartDownload;

  const RepackDetailBody({
    super.key,
    required this.title,
    required this.sourceId,
    required this.loadingRepack,
    required this.onStartDownload,
    this.repack,
    this.storefront,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
      children: [
        _HeroBlock(
          title: title,
          sourceId: sourceId,
          repack: repack,
          storefront: storefront,
          loading: loadingRepack,
        ),
        const SizedBox(height: 26),

        // Storefront game information leads, because it describes the game.
        if (storefront != null) ...[
          _StorefrontFacts(detail: storefront!),
          const SizedBox(height: 26),
        ],
        _GameOverviewSection(repack: repack, loading: loadingRepack),

        const SizedBox(height: 26),
        _DownloadsSection(
          repack: repack,
          loading: loadingRepack,
          onStart: onStartDownload,
        ),

        const SizedBox(height: 28),
        Text(
          'Source: $sourceId',
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  final String title;
  final String sourceId;
  final Repack? repack;
  final StorefrontDetail? storefront;
  final bool loading;

  const _HeroBlock({
    required this.title,
    required this.sourceId,
    required this.loading,
    this.repack,
    this.storefront,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final artwork = storefront?.game.screenshots.firstOrNull ??
        storefront?.game.headerImage ??
        repack?.coverUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: double.infinity,
            height: 200,
            child: artwork == null || artwork.isEmpty
                ? ColoredBox(
                    color: palette.surfaceHigh,
                    child: loading
                        ? const SkeletonBox(
                            width: double.infinity,
                            height: double.infinity,
                            radius: 0,
                          )
                        : Icon(
                            Icons.videogame_asset_rounded,
                            size: 46,
                            color: palette.muted,
                          ),
                  )
                : CachedNetworkImage(
                    imageUrl: artwork,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => ColoredBox(color: palette.surfaceHigh),
                    errorWidget: (_, __, ___) => ColoredBox(
                      color: palette.surfaceHigh,
                      child: Icon(Icons.image_not_supported_outlined,
                          color: palette.muted),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: TextStyle(
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final genre in storefront?.game.genres ?? const <String>[])
              _Chip(label: genre),
            if (storefront?.game.releaseDate != null)
              _Chip(label: storefront!.game.releaseDate!, icon: Icons.event_rounded),
            _Chip(label: sourceId, icon: Icons.public_rounded),
          ],
        ),
      ],
    );
  }
}

/// Facts sourced from the storefront record rather than the repack listing.
class _StorefrontFacts extends StatelessWidget {
  final StorefrontDetail detail;

  const _StorefrontFacts({required this.detail});

  @override
  Widget build(BuildContext context) {
    final game = detail.game;
    final facts = <String, String>{
      if (game.releaseDate != null) 'released': game.releaseDate!,
      if (game.genres.isNotEmpty) 'genres': game.genres.join(', '),
      if (game.reviewCount > 0) 'reviews': '${game.reviewCount}',
    };
    if (facts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Game details'),
        _InfoGrid(info: facts),
        if (game.shortDescription != null) ...[
          const SizedBox(height: 14),
          Text(
            game.shortDescription!,
            style: TextStyle(
              color: context.palette.onSurface,
              fontSize: 14.5,
              height: 1.55,
            ),
          ),
        ],
      ],
    );
  }
}

/// Description taken from the repack listing, shown once the storefront facts
/// above it have covered the shared information.
class _GameOverviewSection extends StatelessWidget {
  final Repack? repack;
  final bool loading;

  const _GameOverviewSection({required this.loading, this.repack});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final description = repack?.description ?? '';

    if (loading && description.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: double.infinity, height: 14, radius: 6),
          SizedBox(height: 10),
          SkeletonBox(width: 260, height: 14, radius: 6),
          SizedBox(height: 10),
          SkeletonBox(width: 200, height: 14, radius: 6),
        ],
      );
    }

    if (description.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('About this game'),
        Text(
          description,
          style: TextStyle(
            color: palette.onSurface,
            fontSize: 14.5,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

/// Everything specific to the repack: its sizing, its feature list and where to
/// get it. Sits below the game information on purpose.
class _DownloadsSection extends StatelessWidget {
  final Repack? repack;
  final bool loading;
  final void Function(SourceOption option) onStart;

  const _DownloadsSection({
    required this.loading,
    required this.onStart,
    this.repack,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final info = repack?.info ?? const <String, String>{};
    final features = repack?.repackFeatures ?? const <String>[];
    final options = repack?.preferredOrder ?? const <SourceOption>[];

    if (loading && options.isEmpty && info.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 140, height: 18, radius: 6),
          SizedBox(height: 14),
          SkeletonBox(width: double.infinity, height: 64, radius: 12),
          SizedBox(height: 10),
          SkeletonBox(width: double.infinity, height: 64, radius: 12),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Repack information'),
        if (info.isNotEmpty) _InfoGrid(info: info),
        if (features.isNotEmpty) ...[
          const SizedBox(height: 18),
          _FeatureList(features: features),
        ],
        const SizedBox(height: 26),
        const SectionLabel('Download'),
        if (options.isEmpty)
          Text(
            'This repack exposes no download option.',
            style: TextStyle(color: palette.muted, fontSize: 13.5),
          )
        else
          for (final option in options) ...[
            SourceOptionTile(option: option, onStart: () => onStart(option)),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final Map<String, String> info;

  const _InfoGrid({required this.info});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (final entry in info.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 132,
                    child: Text(
                      entry.key.replaceAll('_', ' '),
                      style: TextStyle(color: palette.muted, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        color: palette.onSurface,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  final List<String> features;

  const _FeatureList({required this.features});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final feature in features)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_rounded, size: 15, color: RpckTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    feature,
                    style: TextStyle(
                      color: palette.onSurface,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One download row. A split mirror is a single row with a single button that
/// transfers every part in order, rather than a button per part.
class SourceOptionTile extends StatelessWidget {
  final SourceOption option;
  final VoidCallback onStart;

  const SourceOptionTile({super.key, required this.option, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (icon, accent) = switch (option) {
      TorrentFileOption() => (Icons.download_for_offline_rounded, const Color(0xFF34C759)),
      TorrentIndexOption() => (Icons.travel_explore_rounded, const Color(0xFF34C759)),
      MagnetOption() => (Icons.link_rounded, RpckTheme.primary),
      DirectOption() => (Icons.cloud_download_outlined, RpckTheme.secondary),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.label,
                  style: TextStyle(
                    color: palette.onSurface,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  describe(option),
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

String describe(SourceOption option) => switch (option) {
      TorrentFileOption(:final torrentUri) =>
        'Torrent file with trackers embedded, from ${torrentUri.host}',
      TorrentIndexOption(:final indexName, :final listingUri) =>
        'Torrent via the $indexName index at ${listingUri.host}',
      MagnetOption() => 'Resolves its metadata over the DHT, slower but no mirror needed',
      DirectOption(:final host, :final parts) => parts.length > 1
          ? '${parts.length} parts, downloaded one after another from $host'
          : 'Plain mirror from $host',
    };

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _Chip({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: palette.muted),
            const SizedBox(width: 5),
          ],
          Text(label, style: TextStyle(color: palette.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class RepackErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const RepackErrorState({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 40),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.onSurface),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
