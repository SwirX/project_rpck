import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'core/result.dart';
import 'features/startup/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final environment = await AppEnvironment.create();
  runApp(
    PrjctRpckApp(
      environment: environment.fold(
        (value) => value,
        // The app still starts without a cache: the catalogue is refetchable,
        // and refusing to launch would be a worse failure than a cold cache.
        (failure) => null,
      ),
      startupFailure: environment.failureOrNull,
    ),
  );
}

class PrjctRpckApp extends StatelessWidget {
  final AppEnvironment? environment;
  final Failure? startupFailure;

  const PrjctRpckApp({
    super.key,
    required this.environment,
    this.startupFailure,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PRJCT RPCK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // The brightness must be set on the scheme, not on ThemeData: the two
        // are asserted to match and fromSeed defaults to light.
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: environment == null
          ? _StartupFailure(failure: startupFailure)
          : SplashScreen(environment: environment!),
    );
  }
}

class _StartupFailure extends StatelessWidget {
  final Failure? failure;

  const _StartupFailure({this.failure});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text(
                'PRJCT RPCK could not start',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
              const SizedBox(height: 10),
              Text(
                failure?.message ?? 'an unknown startup error occurred',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}