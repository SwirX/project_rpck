import '../../storefront/storefront_game.dart';

/// Storefront data for one repack, resolved once.
///
/// Value equality is defined because widget tests compare a whole
/// `RepackDetailBody` subtree, and a match resolved twice must not read as a
/// different child.
class StorefrontDetail {
  final StorefrontGame game;
  final double matchScore;

  const StorefrontDetail({required this.game, required this.matchScore});

  @override
  bool operator ==(Object other) =>
      other is StorefrontDetail &&
      other.game.title == game.title &&
      other.matchScore == matchScore;

  @override
  int get hashCode => Object.hash(game.title, matchScore);
}