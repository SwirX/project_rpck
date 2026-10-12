import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';

import '../../classes/caching.dart';
import '../repack_base.dart';
import 'fetch_1337.dart';

class Fitgirl {
  String name = 'Fitgirl';
  String url = 'https://fitgirl-repacks.site/';
  String type = 'Repacks';

  Fitgirl();

  final caching = Caching();

  /// Decodes a cache file that may legitimately be absent.
  ///
  /// `Caching.getCachedFile` returns an empty string for a missing key, and the
  /// `errors` key is only ever written when a run produced failures. Calling
  /// `jsonDecode('')` throws `FormatException`, so every cache read must pass
  /// through here.
  static List<Map<String, dynamic>> _decodeCache(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<List<GameIndex>> indexDatabase({bool forced = false}) async {
    final games = <GameIndex>[];
    final errors = <GameIndex>[];

    if (!forced) {
      final cachedIndex = await caching.getCachedFile('index');
      final errorIndex = await caching.getCachedFile('errors');
      for (final game in _decodeCache(cachedIndex)) {
        games.add(GameIndex.fromJson(game));
      }
      for (final game in _decodeCache(errorIndex)) {
        errors.add(GameIndex.fromJson(game));
      }
      //remove from games the errors
      for (final error in errors) {
        games.removeWhere((game) => game.title == error.title);
      }
      return games;
    }

    // get available pages
    final tempUrl = 'https://fitgirl-repacks.site/all-my-repacks-a-z/';
    final lastPageSelector = '[class*=\'paginator\']';
    final tempResponse = await http.get(Uri.parse(tempUrl));
    final body = tempResponse.body;
    final document = html.parse(body);
    final paginator = document.querySelector(lastPageSelector);
    int lastPage = 100;
    final text =
        paginator?.text.trim().split('...').last.split('N').first ?? '100';
    lastPage = int.parse(text);

    for (int i = 0; i < lastPage; i++) {
      final url =
          'https://fitgirl-repacks.site/all-my-repacks-a-z/?lcp_page0=$i';
      final response = await http.get(Uri.parse(url));
      final body = response.body;
      final document = html.parse(body);
      final ulElement = document.querySelector('#lcp_instance_0');
      final links = ulElement?.querySelectorAll('a');

      for (var link in links!) {
        final href = link.attributes['href'];
        final title = link.text;
        if (kDebugMode) {
          print(title);
        }
        final firstPass = title.replaceAll(RegExp(r'\\u[\d\w]{4}'), '');
        final secondPass =
            firstPass.replaceAll(RegExp(r'[^A-Za-z0-9\' '- ]"'), '');
        final thirdPass = secondPass.replaceAll(RegExp(r'\s+'), ' ');
        games.add(GameIndex(title: thirdPass, url: href));
      }
    }
    caching.cacheFile(
        'index', jsonEncode(games.map((e) => e.toJson()).toList()));
    return games;
  }

  Future<RepackInfo> fetchGameInfo(GameIndex game,
      {bool forced = false}) async {
    final url = game.url!;
    final title = game.title!;
    if (kDebugMode) {
      print('Getting info for $title');
    }

    if (!forced) {
      final cachedData =
          await caching.getCachedFile(base64Encode(utf8.encode(url)));
      if (cachedData.isNotEmpty) {
        return RepackInfo.fromJson(jsonDecode(cachedData));
      }
    }

    final response = await http.get(Uri.parse(url));
    final body = response.body;
    final document = html.parse(body);
    final List<String> gameRepackInfoContentText =
        document.querySelector('.entry-content')!.text.split('\n');
    int downloadsTitleListIndex = 8;
    try {
      downloadsTitleListIndex = gameRepackInfoContentText.indexOf(
        gameRepackInfoContentText.firstWhere(
          (element) => element.contains('Download Mirrors'),
          orElse: () => '',
        ),
      );
    } catch (e) {
      downloadsTitleListIndex = 8;
    }
    final infoLines =
        gameRepackInfoContentText.getRange(2, downloadsTitleListIndex);
    final List<String> infoKeys = infoLines
        .map((line) =>
            line.split(':').first.trim().replaceAll(' ', '_').toLowerCase())
        .toList();
    final List<List<String>> tempinfoValues = infoLines
        .map((line) => line.split(':').last.trim().split(','))
        .toList();
    final infoValues = [];
    for (var value in tempinfoValues) {
      if (value.length == 1) {
        infoValues.add(value.first);
      } else {
        infoValues.add(value.join(', '));
      }
    }
    final Map<String, dynamic> infoMap = {};
    for (int i = 0; i < infoKeys.length; i++) {
      infoMap[infoKeys[i]] = infoValues[i];
    }

    final downloadsList = {
      'urls': [],
      'magnet': [],
      'torrents': [],
    };

    final directDownloadElements =
        document.querySelectorAll('li .su-spoiler-content');
    for (var downloadElement in directDownloadElements) {
      final directDownloadAnchors = downloadElement.querySelectorAll('a');
      for (var downloadLink in directDownloadAnchors) {
        final href = downloadLink.attributes['href'];
        final providerName = downloadLink.text.replaceAll('Filehoster: ', '');
        downloadsList.putIfAbsent(providerName, () => [href]);
      }
    }

    final torrentDownloadElements =
        document.querySelectorAll('.entry-content li a');
    for (var torrentDownloadElement in torrentDownloadElements) {
      final href = torrentDownloadElement.attributes['href'];
      if (href!.contains('magnet:?')) {
        downloadsList['magnet']!.add(href);
      } else if (href.contains('1337x')) {
        final sources = await fetch1337(href);
        if (kDebugMode) {
          print(sources);
        }
        final foundMagnets = sources['magnets'];
        final torrentFiles = sources['files'];
        if (foundMagnets.isNotEmpty) {
          downloadsList['magnet']!.addAll(foundMagnets);
        }
        if (torrentFiles.isNotEmpty) {
          downloadsList['torrents']!.addAll(torrentFiles);
        }
      } else if (href.contains('jdownloader2')) {
        continue;
      } else {
        final downloadText = torrentDownloadElement.text;
        if (kDebugMode) {
          print(downloadText);
        }
        final dlMap = {
          'url': href,
          'name': downloadText,
          'provider': Uri.parse(href).host,
        };
        if (kDebugMode) {
          print(dlMap);
        }
        downloadsList['urls']!.add(
          dlMap,
        );
      }
    }
    if (kDebugMode) {
      print('gotten downloads');
    }

    final screenshotElements =
        document.querySelectorAll('.entry-content p a img');
    final screenshots = screenshotElements.map((element) {
      final src = element.attributes['src'];
      return src;
    }).toList();

    final repackInfoContentTitle = gameRepackInfoContentText.indexOf(
      gameRepackInfoContentText.firstWhere(
        (e) => e.contains('Repack Features'),
      ),
    );

    final gameDescriptionTitle = gameRepackInfoContentText.indexOf(
      gameRepackInfoContentText.firstWhere(
        (e) => e.contains('Game Description'),
      ),
    );

    final repackFeaturesList = gameRepackInfoContentText.getRange(
      repackInfoContentTitle + 1,
      gameDescriptionTitle,
    );

    final gameDescription = document
        .querySelector('h3~ .su-spoiler-icon-plus .su-spoiler-content')!
        .text;

    String? backwardCompatibility;
    try {
      final backwardsCompatibilityTitle = gameRepackInfoContentText
          .indexOf(gameRepackInfoContentText.firstWhere(
        (e) => e.contains('Backward Compatibility'),
      ));
      backwardCompatibility = gameRepackInfoContentText
          .getRange(
              backwardsCompatibilityTitle + 1, gameRepackInfoContentText.length)
          .firstWhere((e) => e.isNotEmpty);
    } catch (e) {
      backwardCompatibility = 'No Info';
    }

    final repackInfo = {
      'title': title,
      'url': url,
      'info': infoMap,
      'description': gameDescription,
      'backwardCompatibility': backwardCompatibility,
      'screenshots': screenshots,
      'repackInfo': repackFeaturesList.join('\n'),
      'downloads': downloadsList,
      'source': {
        'url': url,
        'name': 'FitGirl',
        'type': 'repack',
      },
    };

    caching.cacheFile(base64Encode(utf8.encode(url)), jsonEncode(repackInfo));

    // print(json.encode(repackInfo));

    return RepackInfo.fromJson(repackInfo);
  }
}

Future<void> downloadFile(String url, String filename) async {
  try {
    // Get the download directory depending on the platform
    Directory? downloadsDirectory;

    if (Platform.isAndroid) {
      downloadsDirectory = Directory(
          '/storage/emulated/0/Download'); // Default Android Download folder
    } else if (Platform.isWindows) {
      downloadsDirectory = await getDownloadsDirectory();
    } else {
      throw UnsupportedError("This platform is not supported.");
    }

    if (downloadsDirectory == null) {
      throw Exception("Could not determine downloads directory.");
    }

    String savePath = '${downloadsDirectory.path}/$filename';

    Dio dio = Dio();
    await dio.download(url, savePath);

    if (kDebugMode) {
      print("File downloaded to: $savePath");
    }
  } catch (e) {
    if (kDebugMode) {
      print("Error downloading file: $e");
    }
  }
}

void main(List<String> args) async {
  // final games = fitGirl.indexDatabase();
}
