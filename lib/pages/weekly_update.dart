import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:pool/pool.dart';
import 'package:project_rpck/api/fitgirl/fitgirl.dart';
import 'package:project_rpck/pages/home.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/repack_base.dart';
import '../classes/caching.dart';

class WeeklyUpdatePage extends StatefulWidget {
  const WeeklyUpdatePage({super.key, this.message = 'Weekly Update'});

  final String message;

  @override
  State<WeeklyUpdatePage> createState() => _WeeklyUpdatePageState();
}

class _WeeklyUpdatePageState extends State<WeeklyUpdatePage> {
  bool _isUpdating = false;
  bool _updateComplete = false;
  double _progress = 0.0;
  final String _updateText = "UPDATE";
  final List<String> _dynamicChars = ["U", "P", "D", "A", "T", "E"];
  int _activeCharIndex = 0;
  String _statusMessage = "Weekly update";
  Timer? _animationTimer;

  @override
  void initState() {
    super.initState();
    _statusMessage = widget.message;
    _startCharAnimation();
  }

  void _startCharAnimation() {
    _animationTimer =
        Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!_isUpdating) {
        setState(() {
          _activeCharIndex = (_activeCharIndex + 1) % _dynamicChars.length;
        });
      }
    });
  }

  void _startUpdate() async {
    _animationTimer?.cancel();
    setState(() {
      _isUpdating = true;
      _progress = 0.0;
      _statusMessage = "Syncing latest repacks...";
    });

    final gamesIndex = await Fitgirl().indexDatabase(forced: true);
    final gameCount = gamesIndex.length;

    const batchSize = 100;
    int fetchedGames = 0;
    int errorCount = 0;
    final List<GameIndex> errorGames = [];
    final pool = Pool(batchSize); // Limit concurrency

    final futures = gamesIndex.map((game) async {
      return pool.withResource(() async {
        try {
          await Fitgirl().fetchGameInfo(game);
        } catch (e) {
          errorGames.add(game);
          errorCount++;
        }

        fetchedGames++;
        final errorString = errorCount > 0 ? ' Errors: $errorCount' : '';
        setState(() {
          _progress = fetchedGames / gameCount;
          _statusMessage =
              "Fetching ${game.title}... ($fetchedGames / $gameCount$errorString)";
        });
      });
    }).toList();

    await Future.wait(futures); // Wait for all to complete
    await pool.close(); // Close pool

    if (errorGames.isNotEmpty) {
      await Caching().cacheFile(
        'errors',
        jsonEncode(errorGames.map((e) => e.toJson()).toList()),
      );
    }

    setState(() {
      _isUpdating = false;
      _updateComplete = true;
      _statusMessage = "Update complete!";
    });

    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('lastUpdate', DateTime.now().toString());
      prefs.setInt('lastCheck', DateTime.now().millisecondsSinceEpoch);
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => HomePage()));
      }
    });
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background texture
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: Image.asset(
                'assets/textures/grid.png',
                repeat: ImageRepeat.repeat,
              ),
            ),
          ),

          Center(
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated header
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: _isUpdating
                        ? Lottie.asset(
                            'assets/animations/data_transfer.json',
                            width: 180,
                            height: 180,
                          )
                        : _UpdateTextHeader(
                            chars: _dynamicChars,
                            activeIndex: _activeCharIndex,
                          ),
                  ),

                  const SizedBox(height: 40),

                  // Status text
                  AnimatedOpacity(
                    opacity: _isUpdating ? 1.0 : 0.8,
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _isUpdating ? Colors.blueAccent : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Progress indicator
                  if (_isUpdating)
                    TweenAnimationBuilder(
                      tween: Tween(begin: 0.0, end: _progress),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeInOutCubic,
                      builder: (context, value, child) {
                        return CustomProgressIndicator(progress: value);
                      },
                    ),

                  const SizedBox(height: 40),

                  // Action button
                  if (!_isUpdating && !_updateComplete)
                    HoverButton(
                      onTap: _startUpdate,
                      text: _updateText,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateTextHeader extends StatelessWidget {
  final List<String> chars;
  final int activeIndex;

  const _UpdateTextHeader({
    required this.chars,
    required this.activeIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: chars.map((char) {
        final isActive = chars.indexOf(char) == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            char,
            style: TextStyle(
              fontSize: isActive ? 42 : 36,
              fontWeight: FontWeight.w900,
              color: isActive ? Colors.blueAccent : Colors.white,
              letterSpacing: isActive ? -2.0 : 0.0,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class CustomProgressIndicator extends StatelessWidget {
  final double progress;

  const CustomProgressIndicator({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      width: 200,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          AnimatedFractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            duration: const Duration(milliseconds: 300),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.blueAccent, Colors.purpleAccent],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HoverButton extends StatefulWidget {
  final VoidCallback onTap;
  final String text;

  const HoverButton({
    super.key,
    required this.onTap,
    required this.text,
  });

  @override
  State<HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<HoverButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          decoration: BoxDecoration(
            border: Border.all(
              color: _isHovered ? Colors.blueAccent : Colors.white30,
              width: _isHovered ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(50),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: widget.text.split('').map((char) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                child: Text(
                  char,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.blueAccent,
                    letterSpacing: 2,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
