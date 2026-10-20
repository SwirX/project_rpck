import 'dart:async';

import 'package:flutter/material.dart';

import '../../bootstrap.dart';
import '../../core/result.dart';
import '../../domain/models/repack.dart';
import '../../domain/models/source_option.dart';
import '../../storefront/local_repack.dart';
import '../../ui/app_settings.dart';
import '../../ui/rpck_top_bar.dart';
import 'repack_detail_body.dart';
import 'storefront_detail.dart';
import 'transfer_starter.dart';

export 'storefront_detail.dart';
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

  /// Runs the queued-start flow, then leaves the page.
  Future<void> _start(SourceOption option) async {
    final repack = _repack;
    if (repack == null) return;

    final message = await startTransfer(
      context: context,
      environment: widget.environment,
      repack: repack,
      option: option,
      settings: AppSettingsScope.of(context),
    );
    if (!mounted) return;
    _notify(message);
    if (message != 'Cancelled') Navigator.of(context).pop();
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