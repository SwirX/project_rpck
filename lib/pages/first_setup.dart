import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:pool/pool.dart';

import '../api/fitgirl/fitgirl.dart';
import '../classes/caching.dart';
import '../api/repack_base.dart';
import 'home.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  bool isFetching = false;
  bool successAnim = false;
  double progress = 0.0;
  int errorCount = 0;
  String statusMessage = "Ready to fetch game database.";
  Fitgirl fitgirl = Fitgirl();

  void startSetup() async {
    final startTime = DateTime.now();
    setState(() {
      isFetching = true;
      progress = 0.0;
      statusMessage = "Fetching game database...";
    });

    final prefs = await SharedPreferences.getInstance();
    final gamesIndex = await fitgirl.indexDatabase(forced: true);
    final gameCount = gamesIndex.length;

    const batchSize = 100;
    int fetchedGames = 0;
    int errorCount = 0;
    final List<GameIndex> errorGames = [];
    final pool = Pool(batchSize); // Limit concurrency

    final futures = gamesIndex.map((game) async {
      return pool.withResource(() async {
        try {
          await fitgirl.fetchGameInfo(game, forced: true);
        } catch (e) {
          errorGames.add(game);
          errorCount++;
        }

        fetchedGames++;
        final errorString = errorCount > 0 ? ' Errors: $errorCount' : '';
        setState(() {
          progress = fetchedGames / gameCount;
          statusMessage =
              "Fetching game info... $fetchedGames / $gameCount$errorString";
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
      isFetching = false;
      progress = 1.0;
      statusMessage = "Setup complete! You're ready to go.";
      successAnim = true;
    });

    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        successAnim = false;
        prefs.setBool('first_setup', false);
        prefs.setInt('lastCheck', DateTime.now().millisecondsSinceEpoch);
      });
    });
    if (kDebugMode) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      final milliseconds = duration.inMilliseconds % 1000;
      final formattedDuration =
          '$minutes:${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(3, '0')}';
      print(
          'Setup completed in $formattedDuration. Fetched $fetchedGames games.');
    }
  }

  continueToHome() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) {
      return const HomePage();
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Lottie.asset(
                progress != 1
                    ? "assets/animations/loading.json"
                    : "assets/animations/success.json",
                height: 150,
                width: 150,
                animate: progress != 1 ? isFetching : successAnim,
                repeat: progress != 1 ? true : false,
              ),
              const SizedBox(height: 20),
              Text(
                "Initial Setup",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "The app will fetch and build a database of games. This will only take time during the first setup. Future updates will be streamlined.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 20),
              if (isFetching)
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade800,
                      valueColor: AlwaysStoppedAnimation(Colors.blueAccent),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      statusMessage,
                      style:
                          TextStyle(color: Colors.grey.shade300, fontSize: 14),
                    ),
                  ],
                )
              else
                ElevatedButton(
                  onPressed: progress != 1 ? startSetup : continueToHome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 24),
                  ),
                  child: Text(
                      progress != 1 ? "Start Setup" : 'Continue To HomeScreen',
                      style: TextStyle(fontSize: 16)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
