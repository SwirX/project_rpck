import 'dart:async';

import 'package:flutter/material.dart';

import '../../bootstrap.dart';
import '../../core/platform/download_location.dart';
import '../library/library_page.dart';
import 'onboarding_guide.dart';
import 'onboarding_shell.dart';

/// First-run wizard.
///
/// Covers everything the user has to decide or do once: where downloads go,
/// whether to build the catalogue now or later, and what the app does. Ends by
/// offering the usage guide, which is skippable and reachable later from
/// settings.
class OnboardingFlow extends StatefulWidget {
  final AppEnvironment environment;
  final OnboardingProgress progress;

  const OnboardingFlow({
    super.key,
    required this.environment,
    required this.progress,
  });

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  OnboardingStep _step = OnboardingStep.welcome;
  String? _folder;
  bool _folderResolved = false;
  bool _indexing = false;
  bool _indexed = false;
  int _indexedCount = 0;
  String _indexStatus = '';
  String? _indexError;

  @override
  void initState() {
    super.initState();
    _folder = widget.progress.folder;
    unawaited(_resolveFolder());
  }

  Future<void> _resolveFolder() async {
    final location = await DownloadLocationProbe.resolve();
    if (!mounted) return;
    setState(() {
      _folder ??= location;
      _folderResolved = true;
    });
  }

  Future<void> _startIndex() async {
    setState(() {
      _indexing = true;
      _indexError = null;
      _indexStatus = 'starting';
    });

    final result = await widget.environment.catalogue.reindex(
      catalog: widget.environment.sources,
      onProgress: (progress) async {
        if (!mounted) return;
        setState(() {
          _indexStatus = progress.phase;
          if (progress.phase == 'index complete') {
            _indexedCount = progress.indexed;
          }
        });
      },
    );

    if (!mounted) return;
    result.fold(
      (written) => setState(() {
        _indexing = false;
        _indexed = true;
        _indexedCount = written;
        _step = OnboardingStep.ready;
      }),
      (failure) => setState(() {
        _indexing = false;
        _indexError = failure.message;
      }),
    );
  }

  Future<void> _finish() async {
    await widget.progress.complete(folder: _folder);
    if (!mounted) return;
    if (!widget.progress.seenGuide) {
      final read = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (context) => const OnboardingGuide(isFirstRun: true)),
      );
      if (read == true) await widget.progress.markGuideSeen();
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => LibraryPage(environment: widget.environment)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      OnboardingStep.welcome => _welcome(),
      OnboardingStep.downloadFolder => _downloadFolder(),
      OnboardingStep.buildIndex => _buildIndex(),
      OnboardingStep.ready => _ready(),
    };
  }

  Widget _welcome() {
    const body = SingleChildScrollView(
      child: Column(
        children: [
          OnboardingCard(
            icon: Icons.travel_explore_rounded,
            title: 'Index once, browse offline',
            body: 'The catalogue is stored locally after the first pass, so '
                'searching and browsing stay instant.',
          ),
          OnboardingCard(
            icon: Icons.download_for_offline_rounded,
            title: 'Torrent, magnet or mirror',
            body: 'Pick the source that suits a game. Torrent files carry '
                'embedded trackers and find the most peers.',
          ),
          OnboardingCard(
            icon: Icons.shield_outlined,
            title: 'Verified downloads',
            body: 'An update is only offered when its SHA-256 checksum is '
                'published and matches.',
          ),
        ],
      ),
    );

    return OnboardingScaffold(
      stepIndex: 0,
      stepCount: 3,
      title: 'Every repack,\none place.',
      subtitle: 'PRJCT RPCK indexes repack sites, keeps the metadata on your '
          'own disk, and hands downloads to a built-in BitTorrent client. No '
          'browser hand-off, no separate download tool.',
      actions: [
        _SkipButton(onPressed: _finish),
        const Spacer(),
        _NextButton(label: 'Get started', onPressed: _next),
      ],
      child: body,
    );
  }

  Widget _downloadFolder() {
    final body = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded, color: Color(0xFF3D8BFF), size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _folder ?? 'Unavailable',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const OnboardingCard(
            icon: Icons.warning_amber_rounded,
            title: 'Repacks need room',
            body: 'A single modern title can be tens of gigabytes once '
                'installed. Make sure the drive has space before you start.',
          ),
        ],
      ),
    );

    return OnboardingScaffold(
      stepIndex: 1,
      stepCount: 3,
      title: 'Where should downloads land?',
      subtitle: _folderResolved
          ? 'Change it any time in settings. Leaving it on the system '
              'Downloads folder keeps installers next to everything else.'
          : 'Resolving your system Downloads folder…',
      actions: [
        _BackButton(onPressed: _previous),
        const Spacer(),
        _NextButton(label: 'Continue', onPressed: _folderResolved ? _next : null),
      ],
      child: body,
    );
  }

  Widget _buildIndex() {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_indexing || _indexed) ...[
          _IndexProgressBar(indexed: _indexed),
          const SizedBox(height: 20),
          Text(
            _indexStatus,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 13.5),
          ),
        ] else ...[
          const OnboardingCard(
            icon: Icons.storage_rounded,
            title: 'Why a first pass at all?',
            body: 'The sites only expose listings page by page. Doing it once '
                'keeps every later launch instant.',
          ),
          if (_indexError != null) ...[
            const SizedBox(height: 8),
            Text(
              _indexError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
            ),
          ],
        ],
        const Spacer(),
      ],
    );

    return OnboardingScaffold(
      stepIndex: 2,
      stepCount: 3,
      title: 'Build the catalogue',
      subtitle: _indexing
          ? 'This walks 148 index pages and takes roughly ninety seconds. '
              'It only happens once.'
          : 'About seven thousand repacks, indexed once and stored on disk.',
      actions: [
        _BackButton(onPressed: _indexing ? null : _previous),
        const Spacer(),
        if (_indexing)
          const _BusyButton(label: 'Indexing')
        else
          _NextButton(label: 'Start indexing', onPressed: _startIndex),
      ],
      child: body,
    );
  }

  Widget _ready() {
    const body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingCard(
          icon: Icons.search_rounded,
          title: 'Search from the top bar',
          body: 'Partial words work. Typing "cyber" narrows the catalogue as '
              'you go.',
        ),
        OnboardingCard(
          icon: Icons.local_fire_department_rounded,
          title: 'Check trending first',
          body: 'Cards on the home screen show when a trending game already '
              'has a repack listed. Tap one to open it.',
        ),
        OnboardingCard(
          icon: Icons.download_rounded,
          title: 'Transfers live in their own screen',
          body: 'The download button in the top right shows live progress, '
              'speed and peer counts.',
        ),
      ],
    );

    return OnboardingScaffold(
      stepCount: 1,
      title: 'You are set up.',
      subtitle: '$_indexedCount repacks are indexed and searchable. Artwork '
          'fills in as you browse, then stays cached.',
      actions: [
        _SkipButton(onPressed: _finish),
        const Spacer(),
        _NextButton(label: 'Open the library', onPressed: _finish),
      ],
      child: body,
    );
  }

  void _next() => setState(() {
        _step = OnboardingStep.values[
            (_step.index + 1).clamp(0, OnboardingStep.values.length - 1)];
      });

  void _previous() => setState(() {
        _step = OnboardingStep.values[
            (_step.index - 1).clamp(0, OnboardingStep.values.length - 1)];
      });
}

class _IndexProgressBar extends StatelessWidget {
  final bool indexed;

  const _IndexProgressBar({required this.indexed});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 4),
        AnimatedFractionallySizedBox(
          duration: const Duration(milliseconds: 300),
          widthFactor: indexed ? 1 : 0.08,
          alignment: Alignment.centerLeft,
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3D8BFF), Color(0xFFB14DFF)],
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    );
  }
}

class _NextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _NextButton({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF3D8BFF),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _BackButton({this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: const Color(0xFF9A9A9A)),
      child: const Text('Back'),
    );
  }
}

class _SkipButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SkipButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: const Color(0xFF6E6E6E)),
      child: const Text('Skip'),
    );
  }
}

class _BusyButton extends StatelessWidget {
  final String label;

  const _BusyButton({required this.label});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: null,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF3D8BFF),
        foregroundColor: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}

/// Resolves the download directory without dragging platform code into a widget.
abstract final class DownloadLocationProbe {
  static Future<String?> resolve() async {
    final result = await DownloadLocation.resolve();
    return result.fold((location) => location.directory.path, (_) => null);
  }
}