import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../bootstrap.dart';
import '../../core/platform/download_location.dart';
import '../../core/result.dart';
import '../../domain/models/repack.dart';
import '../../domain/models/source_option.dart';
import '../../download/transfer.dart';
import '../../ui/rpck_top_bar.dart';
import '../../ui/skeletons.dart';

/// One repack, with its download options.
///
/// The prototype launched a torrent from a button that merely saved the
/// `.torrent` file to disk, showed magnets and mirrors only as "Open" links to
/// the browser, and read `widget.repack.magnets` as a raw `List<dynamic>`.
class RepackPage extends StatefulWidget {
  final AppEnvironment environment;
  final String sourceId;
  final String url;
  final String title;

  const RepackPage({
    super.key,
    required this.environment,
    required this.sourceId,
    required this.url,
    required this.title,
  });

  @override
  State<RepackPage> createState() => _RepackPageState();
}

class _RepackPageState extends State<RepackPage> {
  Repack? _repack;
  Failure? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final adapter = widget.environment.sources[widget.sourceId];
    if (adapter == null) {
      setState(() {
        _loading = false;
        _failure = Failure(
          FailureKind.unknown,
          'source "${widget.sourceId}" is not registered',
        );
      });
      return;
    }

    final result = await adapter.fetchRepack(Uri.parse(widget.url));
    if (!mounted) return;
    setState(() {
      _loading = false;
      result.fold(
        (repack) {
          _repack = repack;
          _failure = null;
        },
        (failure) => _failure = failure,
      );
    });
  }

  Future<void> _start(SourceOption option) async {
    final repack = _repack;
    if (repack == null) return;

    final location = await DownloadLocation.resolve();
    final directory = location.fold((value) => value, (_) => null);
    if (directory == null) {
      _notify('No writable download directory.');
      return;
    }

    final target = directory.resolveFileName(
      DownloadLocation.sanitizeFileName(
        '${repack.title} ${_suffixFor(option)}',
      ),
    );
    final savePath = target.fold((value) => value, (_) => null);
    if (savePath == null) {
      _notify('That repack title cannot be used as a file name.');
      return;
    }

    final transfer = Transfer.forOption(
      id: '${repack.sourceUri.hashCode}-${option.hashCode}',
      title: repack.title,
      option: option,
      savePath: savePath,
    );

    widget.environment.transfers.enqueue(transfer);
    final result = await widget.environment.transfers.start(transfer);
    if (!mounted) return;
    result.fold(
      (_) => _notify('Queued ${option.label}.'),
      (failure) => _notify(failure.message),
    );

    if (mounted) Navigator.of(context).pop();
  }

  static String _suffixFor(SourceOption option) => switch (option) {
        MagnetOption() => '[magnet]',
        TorrentFileOption() => '[torrent]',
        DirectOption() => '[mirror]',
      };

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            RpckTopBar(
              leading: _BackButton(onPressed: () => Navigator.of(context).pop()),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const SkeletonDetail();
    if (_failure != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 16),
              Text(
                _failure!.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final repack = _repack;
    if (repack == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        if (repack.coverUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: repack.coverUrl,
              width: 320,
              height: 180,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox(
                height: 180,
                child: Center(
                  child: Icon(Icons.videogame_asset, size: 48, color: Colors.white24),
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        if (repack.description.isNotEmpty)
          Text(
            repack.description,
            style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
          ),
        if (repack.info.isNotEmpty) ...[
          const SizedBox(height: 28),
          const _SectionLabel('GAME INFO'),
          const SizedBox(height: 10),
          for (final entry in repack.info.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      entry.key.replaceAll('_', ' '),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (repack.repackFeatures.isNotEmpty) ...[
          const SizedBox(height: 28),
          const _SectionLabel('REPACK FEATURES'),
          const SizedBox(height: 10),
          for (final feature in repack.repackFeatures)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '· $feature',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
        ],
        if (repack.backwardCompatibility != null) ...[
          const SizedBox(height: 28),
          const _SectionLabel('BACKWARD COMPATIBILITY'),
          const SizedBox(height: 10),
          Text(
            repack.backwardCompatibility!,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
        const SizedBox(height: 32),
        const _SectionLabel('DOWNLOAD'),
        const SizedBox(height: 12),
        if (repack.sources.isEmpty)
          const Text(
            'This repack exposes no download option.',
            style: TextStyle(color: Colors.white38),
          )
        else
          for (final option in repack.preferredOrder)
            _SourceTile(option: option, onStart: () => _start(option)),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.bebasNeue(
        fontSize: 22,
        color: Colors.white,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final SourceOption option;
  final VoidCallback onStart;

  const _SourceTile({required this.option, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final (icon, accent) = switch (option) {
      TorrentFileOption() => (Icons.download_for_offline, Colors.greenAccent),
      MagnetOption() => (Icons.link, Colors.blueAccent),
      DirectOption() => (Icons.cloud_download_outlined, Colors.purpleAccent),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.label,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                Text(
                  _detail,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  String get _detail => switch (option) {
        TorrentFileOption(:final torrentUri) =>
          'Fastest · trackers embedded · ${torrentUri.host}',
        MagnetOption() => 'Resolves metadata over the DHT',
        DirectOption(:final url) => 'Plain mirror · ${url.host}',
      };
}