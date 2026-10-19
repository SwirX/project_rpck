import 'dart:async';

import 'package:flutter/material.dart';

import '../../bootstrap.dart';
import '../../core/platform/download_location.dart';
import '../../core/result.dart';
import '../../domain/models/repack.dart';
import '../../domain/models/source_option.dart';
import '../../download/transfer.dart';
import '../../storefront/local_repack.dart';
import '../../storefront/storefront_client.dart';
import '../../ui/app_settings.dart';
import '../../ui/rpck_top_bar.dart';
import 'repack_detail_body.dart';
import '../settings/setting_effects.dart';
import 'transfer_confirmation.dart';
import '../../ui/skeletons.dart';

/// One repack, with its download options.
///
/// Presentation is deliberately ordered: the storefront record comes first,
/// because it describes the game, and everything specific to the repack sits
/// below it under its own heading.
class RepackPage extends StatefulWidget {
  final AppEnvironment environment;
  final String sourceId;
  final String url;
  final String title;
  final LocalRepack? storefrontHint;

  const RepackPage({
    super.key,
    required this.environment,
    required this.sourceId,
    required this.url,
    required this.title,
    this.storefrontHint,
  });

  @override
  State<RepackPage> createState() => _RepackPageState();
}

class _RepackPageState extends State<RepackPage> {
  Repack? _repack;
  StorefrontDetail? _storefront;
  Failure? _failure;
  bool _loadingRepack = true;
  bool _loadingStorefront = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRepack());
    unawaited(_loadStorefront());
  }

  Future<void> _loadRepack() async {
    final adapter = widget.environment.sources[widget.sourceId];
    if (adapter == null) {
      setState(() {
        _loadingRepack = false;
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
      _loadingRepack = false;
      result.fold(
        (repack) {
          _repack = repack;
          _failure = null;
        },
        (failure) => _failure = failure,
      );
    });
  }

  /// Looks the repack up in the storefront so the page can lead with real
  /// game data: screenshots, description, genres and release date.
  Future<void> _loadStorefront() async {
    final match = await widget.environment.storefrontResolver.resolve(
      LocalRepack(
        title: widget.title,
        url: widget.url,
        sourceId: widget.sourceId,
      ),
    );
    if (!mounted) return;
    setState(() {
      _loadingStorefront = false;
      _storefront = match == null
          ? null
          : StorefrontDetail(game: match.game, matchScore: match.score);
    });
  }

  Future<void> _start(SourceOption option) async {
    final repack = _repack;
    if (repack == null) return;

    final settings = AppSettingsScope.of(context);

    // Asked before anything is enqueued, so cancelling leaves no queued record
    // and no journal entry behind.
    if (!await _confirmTransfer(repack, option, settings)) return;
    if (!mounted) return;

    final location = await DownloadLocation.resolve(
      override: settings.downloadFolder,
    );
    final directory = location.fold((value) => value, (_) => null);
    if (directory == null) {
      _notify('No writable download directory.');
      return;
    }

    final suffix = switch (option) {
      MagnetOption() => 'magnet',
      TorrentFileOption() => 'torrent',
      TorrentIndexOption() => 'index',
      DirectOption(:final parts) => parts.length > 1 ? 'mirror-${parts.length}parts' : 'mirror',
    };
    final target = directory.resolveFileName(
      DownloadLocation.sanitizeFileName('${repack.title} [$suffix]'),
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

  /// Returns true when the transfer may proceed.
  ///
  /// Always true when the confirmation setting is off, which is the default:
  /// asking on every single download is friction most people do not want.
  Future<bool> _confirmTransfer(
    Repack repack,
    SourceOption option,
    AppSettings settings,
  ) async {
    if (!shouldConfirmBeforeTransfer(settings)) return true;
    return confirmTransfer(
      context,
      title: repack.title,
      description: describe(option),
      folder: settings.downloadFolder ?? defaultDownloadFolderName,
    );
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            RpckTopBar(
              leading: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                        color: context.palette.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingRepack && _loadingStorefront) return const SkeletonDetail();

    if (_failure != null && _repack == null) {
      return RepackErrorState(
        message: _failure!.message,
        onRetry: () {
          setState(() {
            _failure = null;
            _loadingRepack = true;
          });
          unawaited(_loadRepack());
        },
      );
    }

    return RepackDetailBody(
      title: widget.title,
      sourceId: widget.sourceId,
      repack: _repack,
      storefront: _storefront,
      loadingRepack: _loadingRepack,
      onStartDownload: _start,
    );
  }
}

/// Storefront data for one repack, resolved once.
class StorefrontDetail {
  final StorefrontGame game;
  final double matchScore;

  const StorefrontDetail({required this.game, required this.matchScore});

  @override
  bool operator ==(Object other) =>
      other is StorefrontDetail &&
      other.game.title == game.title &&
      other.matchScore == matchScore;

  @override
  int get hashCode => Object.hash(game.title, matchScore);
}