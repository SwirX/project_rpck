import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/result.dart';
import '../../domain/models/repack.dart';
import '../../domain/models/source_option.dart';
import 'fitgirl_locator.dart';

/// Turns a FitGirl page into a normalised [Repack].
class FitgirlPageParser {
  final Uri pageUri;

  const FitgirlPageParser(this.pageUri);

  Result<Repack> parse(String body) {
    final document = guardSync(() => html_parser.parse(body));
    final parsed = document.fold(
      (value) => value,
      (failure) => null,
    );
    if (parsed == null) {
      return FailureResult(
        const Failure(FailureKind.parse, 'page is not valid HTML'),
      );
    }

    final content = parsed.querySelector(FitgirlLocator.entryContent);
    if (content == null) {
      return FailureResult(
        Failure(FailureKind.layout,
            'entry content block is gone; the page template changed',
            cause: pageUri),
      );
    }

    final lines = content.text.split('\n');
    return guardSync(() {
      final info = _parseInfoBlock(lines);
      return Repack(
        title: _pageTitle(parsed),
        sourceUri: pageUri,
        sourceId: 'fitgirl',
        description: _description(content),
        screenshots: _screenshots(content),
        info: info,
        repackFeatures: _sectionBetween(lines, 'Repack Features', 'Game Description'),
        backwardCompatibility: _backwardCompatibility(lines),
        contentId: _contentId(info),
        sources: _sources(content),
      );
    });
  }

  /// Reads the `key: value` metadata block that precedes the mirrors.
  ///
  /// The block has no container element upstream, so it is recovered from the
  /// line ordering that has always accompanied it.
  Map<String, String> _parseInfoBlock(List<String> lines) {
    final stop = lines.indexWhere((line) => line.contains('Download Mirrors'));
    final end = stop < 0 ? lines.length : stop;
    final info = <String, String>{};
    for (final line in lines.getRange(0, end < 2 ? 0 : end)) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line
          .substring(0, separator)
          .trim()
          .toLowerCase()
          .replaceAll(' ', '_');
      final value = line.substring(separator + 1).trim();
      if (key.isEmpty || value.isEmpty) continue;
      info[key] = value.split(',').map((part) => part.trim()).join(', ');
    }
    return info;
  }

  /// Reads the repack's own name.
  ///
  /// Scoped to `.entry-title` because the page carries several unrelated `h1`
  /// elements and the first of them is the site brand. Falls back to the url
  /// slug so a template change degrades to something readable.
  String _pageTitle(Document document) {
    final heading = document.querySelector(FitgirlLocator.entryTitle)?.text.trim();
    if (heading != null && heading.isNotEmpty) return heading;
    return pageUri.pathSegments.last;
  }

  /// Longest body accepted as prose. Below this it is a mirror row or a caption.
  static const _minimumProseLength = 140;

  /// Picks the spoiler holding prose rather than a download listing.
  ///
  /// A live page carries three `su-spoiler-icon-plus` blocks: two headed "Click
  /// to show direct links" whose text is nothing but mirror file names, then
  /// the real description. Taking the first block past a length threshold
  /// therefore rendered "setup.part1.rar setup.part2.rar setup.part3.rar" as the
  /// game description, which is what the details page was showing.
  ///
  /// Falls back to the first non-listing spoiler when a page leaves the heading
  /// off, rather than dropping the description entirely.
  String _description(Element content) {
    String? prose;
    for (final spoiler
        in content.querySelectorAll(FitgirlLocator.spoilerIconPlus)) {
      final body =
          spoiler.querySelector(FitgirlLocator.spoilerContent)?.text.trim();
      if (body == null || body.length <= _minimumProseLength) continue;

      final title = spoiler
              .querySelector(FitgirlLocator.spoilerTitle)
              ?.text
              .trim()
              .toLowerCase() ??
          '';

      if (title.contains(FitgirlLocator.gameDescriptionTitle)) return body;
      if (prose == null && !_isListing(title)) prose = body;
    }
    return prose ?? '';
  }

  static bool _isListing(String title) => FitgirlLocator.listingTitleFragments
      .any((fragment) => title.contains(fragment));

  List<String> _screenshots(Element content) => content
      .querySelectorAll(FitgirlLocator.screenshotAnchor)
      .map((anchor) => anchor.querySelector('img')?.attributes['src'])
      .whereType<String>()
      .where((src) => src.isNotEmpty)
      .toList(growable: false);

  List<String> _sectionBetween(
    List<String> lines,
    String startMarker,
    String endMarker,
  ) {
    final start = lines.indexWhere((line) => line.contains(startMarker));
    final end = lines.indexWhere((line) => line.contains(endMarker));
    if (start < 0 || end <= start) return const [];
    return lines
        .getRange(start + 1, end)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  String? _backwardCompatibility(List<String> lines) {
    final index = lines.indexWhere(
      (line) => line.contains('Backward Compatibility'),
    );
    if (index < 0) return null;
    return lines
        .getRange(index + 1, lines.length)
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  }

  String? _contentId(Map<String, String> info) =>
      info['original_size'] == null && info['repack_size'] == null
          ? null
          : '${info['original_size'] ?? ''}|${info['repack_size'] ?? ''}';

  /// Classifies every anchor in the download section into a [SourceOption].
  ///
  /// Plain mirrors are grouped by host, because a split mirror exposes one
  /// anchor per part and those parts only reassemble in the listed order.
  List<SourceOption> _sources(Element content) {
    final magnets = <MagnetOption>[];
    final torrents = <TorrentFileOption>[];
    final indexes = <TorrentIndexOption>[];
    final mirrorOrder = <String>[];
    final mirrors = <String, List<DirectPart>>{};

    for (final anchor in content.querySelectorAll('li a')) {
      final href = anchor.attributes['href'];
      if (href == null || href.isEmpty) continue;

      if (href.startsWith(FitgirlLocator.magnetMarker)) {
        magnets.add(MagnetOption(href));
        continue;
      }
      if (href.contains(FitgirlLocator.torrentMirrorMarker)) {
        // The listing is a web page, not a .torrent file, so it is expanded at
        // download time into a real torrent file or magnet.
        final uri = Uri.tryParse(href);
        if (uri != null) {
          indexes.add(TorrentIndexOption(listingUri: uri, indexName: '1337x'));
        }
        continue;
      }
      if (href.contains(FitgirlLocator.ignoredHoster)) continue;

      final uri = Uri.tryParse(href);
      if (uri == null || uri.host.isEmpty) continue;
      if (uri.scheme != 'http' && uri.scheme != 'https') continue;

      if (FitgirlLocator.torrentMirrorHosts.contains(uri.host)) {
        torrents.add(TorrentFileOption(uri));
        continue;
      }

      mirrorOrder.add(uri.host);
      mirrors
          .putIfAbsent(uri.host, () => <DirectPart>[])
          .add(DirectPart(uri, (mirrors[uri.host]?.length ?? 0) + 1));
    }

    return <SourceOption>[
      ...torrents,
      ...indexes,
      ...magnets,
      for (final host in mirrorOrder.toSet())
        DirectOption(host: host, parts: mirrors[host]!),
    ];
  }
}
