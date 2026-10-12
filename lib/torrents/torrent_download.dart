// torrent_download.dart
import 'dart:async';
import 'package:dtorrent_task/dtorrent_task.dart';

enum DownloadStatus { downloading, paused, stopped, completed }

class TorrentDownloadState {
  final String name;
  final String path;
  final double progress;
  final int downloaded;
  final int totalSize;
  final double downloadSpeed;
  final double uploadSpeed;
  final int peers;
  final int activePeers;
  final int connectedPeers;
  final DownloadStatus status;

  TorrentDownloadState({
    required this.name,
    required this.path,
    required this.progress,
    required this.downloaded,
    required this.totalSize,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.peers,
    required this.activePeers,
    required this.connectedPeers,
    required this.status,
  });

  @override
  String toString() =>
      'TorrentDownloadState($name, ${(progress * 100).toStringAsFixed(1)}%)';
}

class TorrentDownload {
  final TorrentTask task;
  final String torrentPath;
  final String downloadPath;
  final StreamController<TorrentDownloadState> _updateController =
      StreamController.broadcast();
  DownloadStatus _status;

  TorrentDownload(this.task, this.downloadPath, this.torrentPath)
      : _status = task.progress >= 1.0
            ? DownloadStatus.completed
            : DownloadStatus.downloading {
    task.events.listen((event) {
      if (task.progress >= 1.0) {
        _status = DownloadStatus.completed;
      }
      _updateController.add(currentState);
    });
  }

  String get name => task.name;
  double get progress => task.progress;
  int get downloaded => task.downloaded ?? 0;
  int get totalSize => task.metaInfo.length;
  double get downloadSpeed => task.averageDownloadSpeed;
  double get uploadSpeed => task.uploadSpeed;
  int get peers => task.allPeersNumber;
  int get activePeers => task.activePeers?.length ?? 0;
  int get connectedPeers => task.connectedPeersNumber;
  DownloadStatus get status => _status;

  TorrentDownloadState get currentState => TorrentDownloadState(
        name: name,
        path: downloadPath,
        progress: progress,
        downloaded: downloaded,
        totalSize: totalSize,
        downloadSpeed: downloadSpeed,
        uploadSpeed: uploadSpeed,
        peers: peers,
        activePeers: activePeers,
        connectedPeers: connectedPeers,
        status: status,
      );

  Stream<TorrentDownloadState> get updates => _updateController.stream;

  void start() {
    task.start();
    _status = DownloadStatus.downloading;
    _updateController.add(currentState);
  }

  void pause() {
    task.pause();
    _status = DownloadStatus.paused;
    _updateController.add(currentState);
  }

  void resume() {
    task.resume();
    _status = DownloadStatus.downloading;
    _updateController.add(currentState);
  }

  void stop() {
    task.stop();
    _status = DownloadStatus.stopped;
    _updateController.add(currentState);
  }

  void dispose() {
    _updateController.close();
  }

  Map toJson() {
    return {'torrentPath': torrentPath, 'path': downloadPath};
  }
}
