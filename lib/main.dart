import 'package:flutter/material.dart';
import 'package:project_rpck/pages/update_check.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  final prefs = await SharedPreferences.getInstance();
  final firstSetup = prefs.getBool('first_setup') ?? true;
  final lastDbCheck = prefs.getInt('lastCheck') ?? 0;
  runApp(MyApp(
    firstSetup: firstSetup,
    lastCheck: lastDbCheck,
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.firstSetup = true, this.lastCheck = 0});

  final bool firstSetup;
  final int lastCheck;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'PRJCT RPCK',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: SplashScreen(
          firstSetup: firstSetup,
          lastCheck: lastCheck,
        ));
  }
}
