import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// One screenshot, in both sizes.
///
/// The gallery renders thumbnails and only fetches the full-size image when one
/// is actually opened, which matters because a full-size capture is a 1920x1080
/// JPEG and a page of twelve is a few megabytes of images nobody asked for.
class StorefrontShot {
  final String full;
  final String thumbnail;

  const StorefrontShot({required this.full, required this.thumbnail});

  /// Falls back to the full image when the listing carries only one size.
  factory StorefrontShot.fromJson(Map<Object?, Object?> json) {
    final full = '${json['path_full'] ?? ''}';
    final thumbnail = '${json['path_thumbnail'] ?? ''}';
    return StorefrontShot(
      full: full.isEmpty ? thumbnail : full,
      thumbnail: thumbnail.isEmpty ? full : thumbnail,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StorefrontShot && other.full == full && other.thumbnail == thumbnail;

  @override
  int get hashCode => Object.hash(full, thumbnail);
}

/// A storefront listing, used for discovery and for the game's own facts.
///
/// Every field past the title is optional because `appdetails` omits whatever it
/// has no value for: one measured app carried no `metacritic` and no
/// `recommendations` at all. A missing field must cost a row on the page, never
/// the page.
class StorefrontGame {
  final int? externalId;
  final String title;
  final String? shortDescription;

  /// The publisher's long description, flattened to plain text.
  final String? detailedDescription;

  final String? headerImage;
  final String? backgroundImage;
  final List<StorefrontShot> screenshots;
  final List<String> genres;
  final List<String> categories;
  final List<String> developers;
  final List<String> publishers;
  final List<String> platforms;
  final String? releaseDate;
  final int reviewCount;
  final int? metacriticScore;
  final String? price;
  final int achievementCount;
  final int? requiredAge;
  final String? website;
  final String? kind;

  const StorefrontGame({
    required this.title,
    this.externalId,
    this.shortDescription,
    this.detailedDescription,
    this.headerImage,
    this.backgroundImage,
    this.screenshots = const [],
    this.genres = const [],
    this.categories = const [],
    this.developers = const [],
    this.publishers = const [],
    this.platforms = const [],
    this.releaseDate,
    this.reviewCount = 0,
    this.metacriticScore,
    this.price,
    this.achievementCount = 0,
    this.requiredAge,
    this.website,
    this.kind,
  });

  /// True when the store has nothing worth showing beyond the title.
  bool get isThin =>
      shortDescription == null &&
      genres.isEmpty &&
      categories.isEmpty &&
      screenshots.isEmpty &&
      detailedDescription == null;

  factory StorefrontGame.fromJson(Map<String, dynamic> json) {
    return StorefrontGame(
      externalId: (json['steam_appid'] as num?)?.toInt(),
      title: (json['name'] as String?) ?? 'Unknown',
      shortDescription: _text(json['short_description']),
      detailedDescription: _plainText(json['detailed_description']),
      headerImage: _text(json['header_image']),
      backgroundImage: _text(json['background']),
      screenshots: _shots(json['screenshots']),
      genres: _labels(json['genres']),
      categories: _labels(json['categories']),
      developers: _labels(json['developers']),
      publishers: _labels(json['publishers']),
      platforms: _platforms(json['platforms']),
      releaseDate: (json['release_date'] as Map?)?['date'] as String?,
      reviewCount:
          ((json['recommendations'] as Map?)?['total'] as num?)?.toInt() ?? 0,
      metacriticScore:
          ((json['metacritic'] as Map?)?['score'] as num?)?.toInt(),
      price: _price(json['price_overview']),
      achievementCount:
          ((json['achievements'] as Map?)?['total'] as num?)?.toInt() ?? 0,
      requiredAge: (json['required_age'] as num?)?.toInt(),
      website: _text(json['website']),
      kind: _text(json['type']),
    );
  }

  static String? _text(Object? raw) {
    final value = raw is String ? raw.trim() : '';
    return value.isEmpty ? null : value;
  }

  /// Pulls `description` out of a list of `{id, description}` entries, or the
  /// plain strings a different field uses.
  static List<String> _labels(Object? raw) {
    if (raw is! List) return const [];
    final labels = <String>[];
    for (final entry in raw) {
      if (entry is String) {
        if (entry.trim().isNotEmpty) labels.add(entry.trim());
      } else if (entry is Map) {
        final label = entry['description'];
        if (label is String && label.trim().isNotEmpty) labels.add(label.trim());
      }
    }
    return List.unmodifiable(labels);
  }

  static List<StorefrontShot> _shots(Object? raw) {
    if (raw is! List) return const [];
    final shots = <StorefrontShot>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final shot = StorefrontShot.fromJson(entry);
      if (shot.full.isNotEmpty) shots.add(shot);
    }
    return List.unmodifiable(shots);
  }

  static List<String> _platforms(Object? raw) {
    if (raw is! Map) return const [];
    const names = {'windows': 'Windows', 'mac': 'macOS', 'linux': 'Linux'};
    return List.unmodifiable([
      for (final entry in names.entries)
        if (raw[entry.key] == true) entry.value,
    ]);
  }

  /// Prefers the formatted price and falls back to composing the minor units,
  /// which is the only field present on a heavily discounted title.
  static String? _price(Object? raw) {
    if (raw is! Map) return null;
    final formatted = _text(raw['final_formatted']);
    if (formatted != null) return formatted;
    final finalPrice = (raw['final'] as num?)?.toInt();
    if (finalPrice == null || finalPrice == 0) return null;
    final currency = '${raw['currency'] ?? ''}';
    return '$currency ${finalPrice ~/ 100}.${(finalPrice % 100).toString().padLeft(2, '0')}';
  }

  /// Flattens the description's markup, which is HTML with headings and lists.
  ///
  /// Rendered as a `Text` widget, so the tags would otherwise be visible, and
  /// block elements become line breaks. The package's own `.text` runs every
  /// node together, which turned "Game Features" and its first bullet into one
  /// run-on string.
  ///
  /// Falls back to the raw markup when it does not parse, because showing a
  /// stray tag beats showing nothing.
  static String? _plainText(Object? raw) {
    final markup = _text(raw);
    if (markup == null) return null;
    try {
      final fragment = html_parser.parseFragment(markup);
      final buffer = StringBuffer();
      _writeText(fragment, buffer);
      final text = buffer
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .join('\n');
      return text.isEmpty ? markup : text;
    } on Object {
      return markup;
    }
  }

  /// Emits [node]'s text, breaking a line around every block-level element.
  static void _writeText(dom.Node node, StringBuffer out) {
    const blocks = {
      'p', 'div', 'br', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'tr', 'ul', 'ol', 'table', 'section', 'blockquote', 'pre',
    };

    if (node is dom.Text) {
      final data = node.data.replaceAll(RegExp(r'\s+'), ' ');
      if (data.trim().isNotEmpty) out.write(data);
      return;
    }

    // The root is a DocumentFragment, which is a Node but not an Element, so
    // this recurses into it rather than bailing out.
    final isBlock =
        node is dom.Element && blocks.contains(node.localName?.toLowerCase());
    if (isBlock && out.isNotEmpty && !out.toString().endsWith('\n')) {
      out.write('\n');
    }
    for (final child in node.nodes) {
      _writeText(child, out);
    }
    if (isBlock) out.write('\n');
  }
}