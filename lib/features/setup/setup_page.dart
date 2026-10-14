import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bootstrap.dart';
import '../library/library_page.dart';

/// First-run catalogue build.
///
/// Replaces a flow that crawled up to 124 pages sequentially and then opened a
/// hundred simultaneous requests to detail pages. Index pages are walked one at
/// a time, and detail pages are fetched on demand when a repack is opened.
class SetupPage extends StatefulWidget {
  final AppEnvironment environment;

  const SetupPage({super.key, required this.environment});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  bool _running = false;
  bool _done = false;
  int _indexed = 0;
  String _status = 'Ready to build the repack index.';

  Future<void> _start() async {
    final source = widget.environment.sources.all.firstOrNull;
    if (source == null) {
      setState(() => _status = 'No repack source is registered.');
      return;
    }

    setState(() {
      _running = true;
      _indexed = 0;
      _status = 'Walking the index...';
    });

    final result = await source.fetchFullIndex(
      onProgress: (title, done, total) async {
        if (!mounted) return;
        setState(() => _status = 'Indexed $done entries.');
      },
    );
    if (!mounted) return;

    await result.fold(
      (entries) async {
          final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('first_setup', false);
        await prefs.setInt('lastCheck', DateTime.now().millisecondsSinceEpoch);
        if (!mounted) return;
        setState(() {
          _running = false;
          _done = true;
          _indexed = entries.length;
          _status = 'Indexed ${entries.length} repacks.';
        });
      },
      (failure) async {
        if (!mounted) return;
        setState(() {
          _running = false;
            _status = 'Failed: ${failure.message}';
        });
      },
    );
  }

  void _continue() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => LibraryPage(environment: widget.environment),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.asset(
                  _done
                      ? 'assets/animations/success.json'
                      : 'assets/animations/loading.json',
                  height: 140,
                  width: 140,
                  animate: _running,
                  repeat: _running,
                ),
                const SizedBox(height: 20),
                Text(
                  'INITIAL SETUP',
                  style: GoogleFonts.bebasNeue(
                    fontSize: 30,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'The app builds an index of repacks once. Individual repacks are '
                  'fetched only when you open one.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 15),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 280,
                  child: LinearProgressIndicator(
                    value: _running ? null : (_done ? 1 : 0),
                    backgroundColor: Colors.white.withValues(alpha: .1),
                    valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 28),
                if (!_running)
                  FilledButton(
                    onPressed: _done ? _continue : _start,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                    child: Text(
                      _done
                          ? 'Continue to library'
                          : 'Start indexing ($_indexed found)',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}