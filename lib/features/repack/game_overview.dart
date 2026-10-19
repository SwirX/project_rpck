import 'package:flutter/material.dart';

import '../../domain/models/repack.dart';
import '../../ui/rpck_top_bar.dart';
import '../../ui/skeletons.dart';
import 'info_grid.dart';
import 'repack_page.dart' show StorefrontDetail;

/// The game's own facts, taken from the storefront record.
///
/// Leads the page: it describes the game, whereas everything below it describes
/// one particular repack of that game.
class StorefrontFacts extends StatelessWidget {
  final StorefrontDetail detail;

  const StorefrontFacts({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final game = detail.game;
    final facts = <String, String>{
      if (game.developers.isNotEmpty) 'developer': game.developers.join(', '),
      if (game.publishers.isNotEmpty) 'publisher': game.publishers.join(', '),
      if (game.releaseDate != null) 'released': game.releaseDate!,
      if (game.genres.isNotEmpty) 'genres': game.genres.join(', '),
      if (game.categories.isNotEmpty) 'play': game.categories.join(', '),
      if (game.platforms.isNotEmpty) 'platforms': game.platforms.join(', '),
      if (game.price != null) 'price': game.price!,
      if (game.metacriticScore != null) 'metacritic': '${game.metacriticScore}',
      if (game.reviewCount > 0) 'reviews': '${game.reviewCount}',
      if (game.achievementCount > 0) 'achievements': '${game.achievementCount}',
      if ((game.requiredAge ?? 0) > 0) 'age rating': '${game.requiredAge}+',
    };
    if (facts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Game details'),
        InfoGrid(info: facts),
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

/// The long description, flattened from the storefront's markup.
///
/// The repack listing's own description is used only when the storefront has
/// none, so a game the store does not carry still reads as prose rather than as
/// an empty section.
class GameOverviewSection extends StatelessWidget {
  final Repack? repack;
  final bool loading;
  final String? storefrontDescription;

  const GameOverviewSection({
    super.key,
    required this.loading,
    this.repack,
    this.storefrontDescription,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final description = _resolve();

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

  String _resolve() {
    final fromStore = storefrontDescription?.trim() ?? '';
    if (fromStore.isNotEmpty) return fromStore;
    return repack?.description.trim() ?? '';
  }
}