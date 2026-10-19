import 'package:flutter/material.dart';

import '../../domain/models/repack.dart';
import '../../domain/models/source_option.dart';
import '../../ui/rpck_top_bar.dart';
import '../../ui/skeletons.dart';
import 'info_grid.dart';

/// Everything specific to the repack: its sizing, its feature list and where to
/// get it. Sits below the game information on purpose.
class DownloadsSection extends StatelessWidget {
  final Repack? repack;
  final bool loading;
  final void Function(SourceOption option) onStart;

  const DownloadsSection({
    super.key,
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
        if (info.isNotEmpty) InfoGrid(info: info),
        if (features.isNotEmpty) ...[
          const SizedBox(height: 18),
          FeatureList(features: features),
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
