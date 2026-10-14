import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bootstrap.dart';
import '../../core/result.dart';
import '../../update/hyperion_manifest.dart';
import '../../update/release_installer.dart';
import '../../update/update_checker.dart';
import '../library/library_page.dart';
import '../setup/setup_page.dart';
import '../setup/weekly_update_page.dart';

/// Startup gate: resolves an update, then routes into the app.
class SplashScreen extends StatefulWidget {
  final AppEnvironment environment;

  const SplashScreen({super.key, required this.environment});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static final _manifestUri =
      Uri.parse('https://hyperion.alibks.dev/api/v1/apps/prjct_rpck');

  late final AnimationController _titleController;
  late final Animation<double> _titleAnimation;

  bool _updateCheckComplete = false;
  double _checkProgress = 0.0;
  String? _latestVersion;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _titleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _titleAnimation = CurvedAnimation(
      parent: _titleController,
      curve: Curves.easeInOutCubic,
    );
    _titleController.forward();
    unawaited(_resolveUpdate());
  }

  Future<void> _resolveUpdate() async {
    final manifest = await _fetchManifest();
    final currentVersion = await _tryGetCurrentVersion();

    final latest = manifest.fold(
      (app) => app.latestReleaseFor(UpdateChecker.platformKey()),
      (_) => null,
    );
    if (mounted) setState(() => _latestVersion = latest?.version);

    if (manifest case FailureResult(:final failure)) {
      debugPrint('Release manifest unavailable: $failure');
      await _enterApp();
      return;
    }

    final verdict = currentVersion == null
        ? const UpToDate()
        : UpdateChecker.evaluate(
            manifest: manifest.valueOrNull!,
            currentVersion: currentVersion.version,
          );

    if (verdict is! UpdateAvailable) {
      await _enterApp();
      return;
    }
    if (!UpdateChecker.canSelfReplace()) {
      // Linux and Android have no self-replacement path, so the release is
      // left for the user to install rather than downloaded and orphaned.
      debugPrint(
        'Update ${verdict.release.version} is published for '
        '${UpdateChecker.platformKey()}; install it manually.',
      );
      await _enterApp();
      return;
    }

    await _applyUpdate(verdict);
  }

  Future<Result<HyperionApp>> _fetchManifest() async {
    try {
      final response = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: true,
        headers: {'User-Agent': _userAgent},
      )).getUri<String>(_manifestUri);

      final status = response.statusCode ?? 0;
      if (status != 200) {
        return FailureResult(Failure(FailureKind.http, 'HTTP $status'));
      }
      return HyperionApp.parse(response.data ?? '');
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.network, 'manifest request failed', cause: error),
      );
    }
  }

  Future<void> _applyUpdate(UpdateAvailable update) async {
    if (mounted) setState(() => _downloading = true);
    final installer = ReleaseInstaller(userAgent: _userAgent);

    try {
      final downloaded = await installer.download(
        update.artifact,
        fileName: 'prjct_rpck-${update.release.version}.exe',
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _checkProgress = .3 + .5 * (received / total));
        },
      );

      final file = downloaded.valueOrNull;
      if (file == null || !mounted) {
        await _enterApp();
        return;
      }
      setState(() => _checkProgress = .9);

      if (!await ReleaseInstaller.verify(file, update.artifact.checksumSha256!)) {
        debugPrint('Checksum mismatch for ${update.release.version}');
        await _enterApp();
        return;
      }

      setState(() {
        _checkProgress = 1;
        _updateCheckComplete = true;
        _downloading = false;
      });
      await Process.run(file.path, []);
    } finally {
      installer.close();
    }
  }

  /// Reads the running version, tolerating platforms that cannot answer.
  ///
  /// The plugin can throw, and it can also leave a platform-channel reply
  /// pending forever, which no try/catch can intercept. Either outcome means the
  /// build cannot self-identify, which is not a reason to hold the user here.
  Future<PackageInfo?> _tryGetCurrentVersion() async {
    try {
      return await PackageInfo.fromPlatform().timeout(
            const Duration(seconds: 3),
          );
    } catch (error) {
      debugPrint('Unable to read package info: $error');
      return null;
    }
  }

  Future<void> _enterApp() async {
    final prefs = await SharedPreferences.getInstance();
    final firstSetup = prefs.getBool('first_setup') ?? true;
    final lastCheck =
        DateTime.fromMillisecondsSinceEpoch(prefs.getInt('lastCheck') ?? 0);
    if (!mounted) return;

    final Widget next;
    if (firstSetup) {
      next = SetupPage(environment: widget.environment);
    } else if (DateTime.now().difference(lastCheck) > const Duration(days: 7)) {
      next = WeeklyUpdatePage(environment: widget.environment);
    } else {
      next = LibraryPage(environment: widget.environment);
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => next),
    );
  }

  String get _userAgent =>
      'PRJCT-RPCK/${UpdateChecker.platformKey()} '
      '(Flutter; +https://hyperion.alibks.dev)';

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.blueAccent.withValues(alpha: .1),
                    Colors.transparent,
                  ],
                  radius: .6,
                  stops: const [.1, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: .3,
                child: Lottie.asset(
                  'assets/animations/particles.json',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _titleAnimation,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.blueAccent, Colors.purpleAccent],
                    ).createShader(bounds),
                    child: const Text(
                      'PRJCT RPCK',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                _VersionBadge(
                  latestVersion: _latestVersion,
                  complete: _updateCheckComplete,
                ),
                const SizedBox(height: 60),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: _updateCheckComplete
                      ? const _ReadyToLaunch()
                      : _UpdateProgress(
                          progress: _checkProgress,
                          downloading: _downloading,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  final String? latestVersion;
  final bool complete;

  const _VersionBadge({required this.latestVersion, required this.complete});

  @override
  Widget build(BuildContext context) {
    final resolved = latestVersion ?? 'checking';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: (complete ? Colors.greenAccent : Colors.blueAccent)
            .withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            complete ? Icons.check_circle : Icons.autorenew,
            color: complete ? Colors.greenAccent : Colors.blueAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'v$resolved',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateProgress extends StatelessWidget {
  final double progress;
  final bool downloading;

  const _UpdateProgress({required this.progress, required this.downloading});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 200,
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withValues(alpha: .1),
            valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          downloading ? 'DOWNLOADING UPDATE' : 'CHECKING FOR UPDATES',
          style: const TextStyle(
            color: Colors.blueAccent,
            fontSize: 14,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(progress * 100).round()}%',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }
}

class _ReadyToLaunch extends StatelessWidget {
  const _ReadyToLaunch();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Lottie.asset(
          'assets/animations/success.json',
          width: 100,
          height: 100,
        ),
        const SizedBox(height: 20),
        const Text(
          'READY TO LAUNCH',
          style: TextStyle(
            color: Colors.greenAccent,
            fontSize: 18,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}