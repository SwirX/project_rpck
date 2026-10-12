import 'package:flutter/foundation.dart';

class RepackSource {
  String? url;
  String? name;
  String? type;

  RepackSource({
    this.url,
    this.name,
    this.type,
  });

  factory RepackSource.fromJson(Map<String, dynamic> json) {
    return RepackSource(
      url: json['url'],
      name: json['name'],
      type: json['type'],
    );
  }
}

class GameIndex {
  String? title;
  String? url;

  GameIndex({
    required this.title,
    required this.url,
  });

  factory GameIndex.fromJson(Map<String, dynamic> json) {
    return GameIndex(
      title: json['title'],
      url: json['url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
    };
  }
}

class RepackInfo {
  final String title;
  final String url;
  final String description;
  final List<String> screenshots;
  final Map<String, String> info;
  final List<Download> downloads;
  final List torrent;
  final List magnets;
  final RepackSource? source;

  RepackInfo({
    required this.title,
    required this.url,
    required this.description,
    required this.screenshots,
    required this.info,
    required this.downloads,
    required this.torrent,
    required this.magnets,
    this.source,
  });

  factory RepackInfo.fromJson(Map<String, dynamic> json) {
    final urlsList = json['downloads']['urls'] as List;
    final downloadsList = urlsList.map((e) => Download.fromJson(e)).toList();
    return RepackInfo(
      title: json['title'],
      url: json['url'],
      description: json['description'],
      screenshots: List<String>.from(json['screenshots']),
      info: Map<String, String>.from(json['info']),
      downloads: downloadsList,
      magnets: json['downloads']['magnet'],
      torrent: json['downloads']['torrents'],
      source:
          json['source'] != null ? RepackSource.fromJson(json['source']) : null,
    );
  }

  factory RepackInfo.empty() {
    return RepackInfo(
      title: '',
      url: '',
      description: '',
      screenshots: [],
      info: {},
      downloads: [],
      torrent: [],
      magnets: [],
    );
  }
}

class Download {
  final String url;
  final String name;
  final String provider;

  Download({
    required this.url,
    required this.name,
    required this.provider,
  });

  factory Download.fromJson(Map<String, dynamic> json) {
    if (kDebugMode) {
      print(json);
    }
    return Download(
      url: json['url'],
      name: json['name'],
      provider: json['provider'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'name': name,
      'provider': provider,
    };
  }
}
