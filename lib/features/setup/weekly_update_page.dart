import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bootstrap.dart';
import '../library/library_page.dart';

/// Shown once a week to refresh the catalogue.
class WeeklyUpdatePage extends StatefulWidget {
  final AppEnvironment environment;

  const WeeklyUpdatePage({super.key, required this.environment});

  @override
  State<WeeklyUpdatePage> createState() => _WeeklyUpdatePageState();
}

class _WeeklyUpdatePageState extends State<WeeklyUpdatePage> {
  bool _running = false;
  int _indexed = 0;
  String _status = 'The index is refreshed weekly so new repacks appear.';

  Future<void> _start() async {
    final source = widget.environment.sources.all.firstOrNull;
    if (source == null) {
      setState(() => _status = 'No repack source is registered.');
      return;
    }

    setState(() {
      _running = true;
      _status = 'Refreshing the index...';
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
        await prefs.setInt('lastCheck', DateTime.now().millisecondsSinceEpoch);
        if (!mounted) return;
        setState(() {
          _running = false;
          _indexed = entries.length;
          _status = '${entries.length} repacks indexed.';
        });
      },
      (failure) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _status = 'Refresh failed: ${failure.message}';
        });
      },
    );
  }

  Future<void> _continue() async {
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
                Text(
                  'WEEKLY UPDATE',
                  style: GoogleFonts.bebasNeue(
                    fontSize: 34,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 15),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_running)
                      FilledButton(
                        onPressed: _start,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Update'),
                      ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _running ? null : _continue,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_indexed > 0 ? 'Library' : 'Skip'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}