import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;

Future<Map<String, dynamic>> fetch1337(String url) async {
  final magnets = [];
  final torrents = [];
  //
  final response = await http.get(Uri.parse(url));
  final body = response.body;
  final document = html.parse(body);
  final magnetUrl = document.querySelector('#openPopup')?.attributes['href'];
  magnets.add(magnetUrl);
  final torrentsDownloadUrls = document
      .querySelectorAll('[aria-labelledby^=\'dropdownMenu\'] li a')
      .map((e) => e.attributes['href'])
      .toList();

  for (var torrent in torrentsDownloadUrls) {
    if (torrent!.contains('magnet:?')) {
      magnets.add(torrent);
    } else if (torrent.contains('itorrents.org')) {
      torrents.add(torrent);
    } else if (torrent.contains('torrage.info')) {
      final torrentUrl = await getTorrentFromTorrage(torrent);
      torrents.add(torrentUrl);
    } else {
      continue;
    }
  }

  if (kDebugMode) {
    print(torrentsDownloadUrls);
  }

  return {
    'files': torrents,
    'magnets': magnets,
  };
}

Future<String> getTorrentFromTorrage(String url) async {
  final response = await http.get(Uri.parse(url));
  final body = response.body;
  final document = html.parse(body);
  final magnetUrl = document.querySelector('a.btn')?.attributes['href'];
  return magnetUrl ?? '';
}

void main(List<String> args) async {
  fetch1337(
    'https://1337x.to/torrent/5689484/A-Whisper-in-the-Twilight-Chapter-One-FitGirl-Repack/',
  );
}
