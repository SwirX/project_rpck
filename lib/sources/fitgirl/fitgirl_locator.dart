/// Every CSS selector the FitGirl source depends on.
///
/// Isolated deliberately. A site redesign should break one file that a test can
/// point at, not four call sites. Each selector here has a matching fixture
/// under `test/fixtures/fitgirl/`.
abstract final class FitgirlLocator {
  static const indexListing = 'https://fitgirl-repacks.site/all-my-repacks-a-z/';

  /// Wrapper around the ajax-loaded index list.
  static const indexListRoot = '#lcp_instance_0';

  /// The paginator renders the final page number after an ellipsis.
  static const paginator = "[class*='paginator']";

  /// Body region holding the structured metadata block.
  static const entryContent = '.entry-content';

  /// Spoilers group the repack notes and the download mirrors.
  static const spoilerContent = '.su-spoiler-content';

  static const spoilerIconPlus = '.su-spoiler-icon-plus';

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