// torrent_manager.dart
import 'dart:async';

import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'torrent_download.dart';

class TorrentManager {
  final List<TorrentDownload> activeDownloads = [];
  final List<TorrentDownload> downloadHistory = [];
  final StreamController<void> _updateController = StreamController.broadcast();

  Stream<void> get updates => _updateController.stream;

  Future<TorrentDownload> startDownload(
    String torrentPath,
    String downloadDir,
  ) async {
    final model = await Torrent.parse(torrentPath);
    final task = TorrentTask.newTask(model, downloadDir);
    final download = TorrentDownload(task, downloadDir, torrentPath);

    activeDownloads.add(download);
    _setupDownloadListeners(download);
    download.start();
    _updateController.add(null);
    return download;
  }

  void _setupDownloadListeners(TorrentDownload download) {
    download.updates.listen((state) {
      if (state.status == DownloadStatus.completed) {
        _moveToHistory(download);
      }
      _updateController.add(null);
    });
  }

  Future<void> saveState(SharedPreferences prefs) async {
    final paths = activeDownloads.map((d) => d.downloadPath).toList();
    await prefs.setStringList('activeDownloads', paths);

    for (final download in activeDownloads) {
      await prefs.setString(
          'dir_${download.downloadPath}', download.downloadPath);
    }
  }

  void _moveToHistory(TorrentDownload download) {
    activeDownloads.remove(download);
    downloadHistory.add(download);
    _updateController.add(null);
  }

  void pauseAll() {
    for (var download in activeDownloads) {
      download.pause();
    }
  }

  void resumeAll() {
    for (var download in activeDownloads) {
      download.resume();
    }
  }

  void stopAll() {
    for (var download in activeDownloads) {
      download.stop();
    }
  }

  void removeDownload(TorrentDownload download) {
    activeDownloads.remove(download);
    downloadHistory.remove(download);
    download.dispose();
  }
}
