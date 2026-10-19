import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../domain/models/repack.dart';
import '../../ui/rpck_top_bar.dart';
import '../../ui/skeletons.dart';
import 'repack_page.dart' show StorefrontDetail;

/// Title, cover and the chips under it.
///
/// The repack's own artwork wins over the storefront's when both exist: the
/// repack listing is the page the user actually arrived on.
class HeroBlock extends StatelessWidget {
  final String title;
  final String sourceId;
  final Repack? repack;
  final StorefrontDetail? storefront;
  final bool loading;

  const HeroBlock({
    super.key,
    required this.title,
    required this.sourceId,
    required this.loading,
    this.repack,
    this.storefront,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hero = repack?.coverUrl ?? storefront?.game.headerImage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: double.infinity,
            height: 200,
            child: hero == null || hero.isEmpty
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
                    imageUrl: hero,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        ColoredBox(color: palette.surfaceHigh),
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
              DetailChip(label: genre),
            if (storefront?.game.releaseDate != null)
              DetailChip(
                label: storefront!.game.releaseDate!,
                icon: Icons.event_rounded,
              ),
            DetailChip(label: sourceId, icon: Icons.public_rounded),
          ],
        ),
      ],
    );
  }
}

/// A small rounded label used under the title.
class DetailChip extends StatelessWidget {
  final String label;
  final IconData? icon;

  const DetailChip({super.key, required this.label, this.icon});

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