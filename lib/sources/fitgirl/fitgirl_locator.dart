/// Every CSS selector the FitGirl source depends on.
///
/// Isolated deliberately. A site redesign should break one file that a test can
/// point at, not four call sites. Each selector here has a matching fixture
/// under `test/fixtures/fitgirl/`.
abstract final class FitgirlLocator {
  static const indexListing = 'https://fitgirl-repacks.site/all-my-repacks-a-z/';

  /// Wrapper around the ajax-loaded index list.
  static const indexListRoot = '#lcp_instance_0';

  /// The listing itself, used when the wrapper id is renumbered.
  static const indexListClass = 'ul.lcp_catlist';

  /// Pagination links. Each carries a numeric `title`, and the highest title is
  /// the final page.
  static const paginator = 'ul.lcp_paginator';

  static const paginatorLink = 'a[title]';

  /// The paginator renders the final page number after an ellipsis.
  static const paginatorText = "[class*='paginator']";

  /// Body region holding the structured metadata block.
  static const entryContent = '.entry-content';

  /// Heading carrying the repack's own name.
  ///
  /// The page has eight `h1` elements, the first of which is the site brand, so
  /// selecting any `h1` returned "FitGirl Repacks" as the game title.
  static const entryTitle = '.entry-title';

  /// Spoilers group the repack notes and the download mirrors.
  static const spoilerContent = '.su-spoiler-content';

  static const spoilerIconPlus = '.su-spoiler-icon-plus';

  /// Heading inside a spoiler, which is the only way to tell the spoilers apart.
  static const spoilerTitle = '.su-spoiler-title';

  /// The spoiler holding the publisher's own description of the game.
  static const gameDescriptionTitle = 'game description';

  /// Headings that mark a spoiler as a download listing rather than prose.
  static const listingTitleFragments = ['direct links', 'download', 'mirror'];

  /// Gallery anchors wrap each screenshot.
  static const screenshotAnchor = 'p a';

  /// Anchor id carrying the primary magnet on a 1337x page.
  static const downloadPopupAnchor = '#openPopup';

  /// Per-tracker dropdown on a 1337x page.
  static const trackerDropdownItems =
      "[aria-labelledby^='dropdownMenu'] li a";

  /// Markers used to classify a link inside the download section.
  static const magnetMarker = 'magnet:?';
  static const torrentMirrorMarker = '1337x';
  static const ignoredHoster = 'jdownloader2';

  /// Mirrors that serve a `.torrent` when followed.
  static const torrentMirrorHosts = ['itorrents.org', 'torrage.info'];
}