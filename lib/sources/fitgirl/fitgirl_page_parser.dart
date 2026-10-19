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

  String _pageTitle(Document document) {
    final heading = document.querySelector('h1');
    final text = heading?.text.trim();
    return text == null || text.isEmpty ? pageUri.pathSegments.last : text;
  }

  String _description(Element content) {
    final spoilers = content.querySelectorAll(FitgirlLocator.spoilerIconPlus);
    for (final spoiler in spoilers) {
      final body = spoiler.querySelector(FitgirlLocator.spoilerContent);
      final text = body?.text.trim() ?? '';
      if (text.length > 40) return text;
    }
    return '';
  }

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
