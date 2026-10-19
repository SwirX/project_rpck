import 'package:flutter/material.dart';

import '../../domain/models/repack.dart';
import '../../domain/models/source_option.dart';
import '../../storefront/storefront_game.dart';
import '../../ui/rpck_top_bar.dart';
import 'downloads_section.dart';
import 'game_overview.dart';
import 'hero_block.dart';
import 'screenshot_gallery.dart';
import 'repack_page.dart' show StorefrontDetail;

export 'downloads_section.dart' show SourceOptionTile, describe;
export 'game_overview.dart' show GameOverviewSection, StorefrontFacts;
export 'screenshot_gallery.dart' show ScreenshotGallery;
export 'hero_block.dart' show DetailChip, HeroBlock;

/// Body of a repack page.
///
/// Order is deliberate and is the thing this class exists to express: the game
/// leads, then the game, then the repack. A repack listing describes one
/// packaging of a game, so it is the last thing on the page rather than the
/// first thing in it.
///
/// Split into the sections below because this was a 525-line file; each section
/// can now be pumped and tested on its own.
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
    final game = storefront?.game;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
      children: [
        HeroBlock(
          title: title,
          sourceId: sourceId,
          repack: repack,
          storefront: storefront,
          loading: loadingRepack,
        ),
        const SizedBox(height: 26),

        // Storefront game information leads, because it describes the game.
        if (storefront != null) ...[
          StorefrontFacts(detail: storefront!),
          const SizedBox(height: 26),
          ScreenshotGallery(shots: game?.screenshots ?? const <StorefrontShot>[]),
          const SizedBox(height: 26),
        ],
        GameOverviewSection(
          repack: repack,
          loading: loadingRepack,
          storefrontDescription: game?.detailedDescription,
        ),

        const SizedBox(height: 26),
        DownloadsSection(
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

/// Shown when the repack page cannot be read.
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