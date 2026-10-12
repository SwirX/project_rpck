import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:project_rpck/api/mediafire.dart';
import 'package:project_rpck/classes/checksum_utils.dart';

import 'first_setup.dart';
import 'home.dart';
import 'weekly_update.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.firstSetup = true, this.lastCheck = 0});

  final bool firstSetup;
  final int lastCheck;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _titleController;
  late Animation<double> _titleAnimation;
  bool _updateCheckComplete = false;
  double _checkProgress = 0.0;
  late String currentVersion;

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
    updateCheck();
  }

  void updateCheck() async {
    final newVersionInfo = await fetchLatestVersion();
    final currentVersionInfo = await getCurrentVersion();
    final updateAvailable = await isUpdateAvailable();
    print('version: ${currentVersionInfo.version}');
    print('build: ${currentVersionInfo.buildNumber}');
    if (currentVersionInfo.version ==
            newVersionInfo['versions']['windows'].last['version'] ||
        currentVersionInfo.buildNumber ==
            newVersionInfo['versions']['windows'].last['version']) {
      print('already on the latest version');
      final lastCheckDT = DateTime.fromMillisecondsSinceEpoch(widget.lastCheck);
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (context) => pageBuilder(widget.firstSetup, lastCheckDT)));
      return;
    }
    if (updateAvailable) {
      final lastVersion = newVersionInfo['versions']['windows'].last;
      final downloadUrl =
          newVersionInfo['versions']['windows'].last['download_url'];
      setState(() {
        _checkProgress = .3;
      });
      final filePath = await MediaFireDownloader.downloadFile(
          downloadUrl, '${lastVersion['checksum']}.exe');
      setState(() {
        _checkProgress = .9;
      });
      final expectedChecksum = lastVersion['checksum'];
      final integrityCheck =
          await ChecksumUtils.verifyChecksum(filePath, expectedChecksum);
      if (integrityCheck) {
        setState(() {
          _checkProgress = 1;
          _updateCheckComplete = true;
        });
        await Process.run(filePath, []);
      }
    } else {
      setState(() {
        _updateCheckComplete = true;
      });
    }
    final lastCheckDT = DateTime.fromMillisecondsSinceEpoch(widget.lastCheck);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (context) => pageBuilder(widget.firstSetup, lastCheckDT)));
  }

  Widget pageBuilder(bool firstSetup, DateTime lastCheck) {
    if (firstSetup) {
      return SetupPage();
    } else {
      if (DateTime.now().difference(lastCheck).inSeconds > 604800) {
        return WeeklyUpdatePage();
      }
      return HomePage();
    }
  }

  Future<Map> fetchLatestVersion() async {
    final uri = Uri.parse(
        'https://gist.githubusercontent.com/SwirX/7bdc181ac223ada52a22941376754ed7/raw/prjct_rpck.json');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      if (kDebugMode) {
        print('Getting the app manifest');
      }
      return {};
    }
    // print(response.body);
    final appMetadata = jsonDecode(response.body);
    return appMetadata;
  }

  Future<bool> isUpdateAvailable() async {
    final currentInfo = await getCurrentVersion();
    final latestVersionInfo = await fetchLatestVersion();
    final latestVersion =
        await latestVersionInfo['versions']['windows'].last['version'];

    setState(() {
      currentVersion = currentInfo.version;
    });

    if (currentVersion == latestVersion) {
      return false;
    }

    bool isVersionNewer =
        _compareSemanticVersions(currentInfo.version, latestVersion);

    return isVersionNewer;
  }

// Helper function to compare semantic versions (e.g., 1.2.3)
  bool _compareSemanticVersions(String current, String latest) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < latestParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  Future<PackageInfo> getCurrentVersion() async {
    return await PackageInfo.fromPlatform();
  }

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
          // Background dynamic gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.blueAccent.withOpacity(0.1),
                    Colors.transparent,
                  ],
                  radius: 0.6,
                  stops: const [0.1, 1.0],
                ),
              ),
            ),
          ),

          // Floating particles effect
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.3,
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
                // Animated logo/text
                ScaleTransition(
                  scale: _titleAnimation,
                  child: ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [Colors.blueAccent, Colors.purpleAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: Text(
                      'PRJCT RPCK',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2.0,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Version text with pulse animation
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _updateCheckComplete
                        ? Colors.greenAccent.withOpacity(0.1)
                        : Colors.blueAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _updateCheckComplete
                            ? Icons.check_circle
                            : Icons.autorenew,
                        color: _updateCheckComplete
                            ? Colors.greenAccent
                            : Colors.blueAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      FutureBuilder(
                        future: fetchLatestVersion(),
                        builder: (context, snapshot) {
                          final version = snapshot
                              .data?['versions']['windows'].last['version'];
                          return Text(
                            'v$version', // Replace with dynamic version
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          );
                        },
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 60),

                // Dynamic status container
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: _updateCheckComplete
                      ? _ReadyToLaunch()
                      : _UpdateProgress(progress: _checkProgress),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateProgress extends StatelessWidget {
  final double progress;

  const _UpdateProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 200,
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation(Colors.blueAccent),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'CHECKING FOR UPDATES...',
          style: TextStyle(
            color: Colors.blueAccent,
            fontSize: 14,
            letterSpacing: 2.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(progress * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
          ),
        ),
      ],
    );
  }
}

class _ReadyToLaunch extends StatelessWidget {
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
        Text(
          'READY TO LAUNCH',
          style: TextStyle(
            color: Colors.greenAccent,
            fontSize: 18,
            letterSpacing: 2.0,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
