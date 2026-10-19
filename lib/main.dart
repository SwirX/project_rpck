import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'core/result.dart';
import 'features/startup/splash_screen.dart';
import 'ui/app_settings.dart';
import 'ui/rpck_top_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final environment = await AppEnvironment.create();
  runApp(
    PrjctRpckApp(
      environment: environment.fold((value) => value, (_) => null),
      startupFailure: environment.failureOrNull,
    ),
  );
}

class PrjctRpckApp extends StatefulWidget {
  final AppEnvironment? environment;
  final Failure? startupFailure;

  const PrjctRpckApp({
    super.key,
    required this.environment,
    this.startupFailure,
  });

  @override
  State<PrjctRpckApp> createState() => _PrjctRpckAppState();
}

class _PrjctRpckAppState extends State<PrjctRpckApp> {
  AppSettings _settings = const AppSettings();

  @override
  void initState() {
    super.initState();
    AppSettings.load().then((loaded) {
      if (mounted) setState(() => _settings = loaded);
    });
  }

  void updateSettings(AppSettings next) => setState(() => _settings = next);

  @override
  Widget build(BuildContext context) {
    final environment = widget.environment;

    return MaterialApp(
      title: 'PRJCT RPCK',
      debugShowCheckedModeBanner: false,
      theme: buildRpckTheme(Brightness.light, RpckPalette.light),
      darkTheme: buildRpckTheme(Brightness.dark, RpckPalette.dark),
      themeMode: _settings.themeMode,
      home: AppSettingsScope(
        settings: _settings,
        onChanged: updateSettings,
        child: environment == null
            ? _StartupFailure(failure: widget.startupFailure)
            : SplashScreen(environment: environment),
      ),
    );
  }
}

/// Builds both brightness variants from one definition.
///
/// Anything the app draws comes from [RpckPalette] through
/// `ThemeExtension`, so a switch repaints every surface rather than leaving the
/// hard-coded dark widgets behind.
ThemeData buildRpckTheme(Brightness brightness, RpckPalette palette) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: RpckTheme.primary,
      brightness: brightness,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    dividerColor: palette.hairline,
    extensions: <ThemeExtension<dynamic>>[palette],
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: palette.onSurface,
      elevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surfaceHigh,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(backgroundColor: palette.surfaceHigh),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceHigh,
      contentTextStyle: TextStyle(color: palette.onSurface),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: RpckTheme.primary,
      selectionColor: RpckTheme.primary.withValues(alpha: .3),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: RpckTheme.primary,
      linearTrackColor: palette.surfaceHigh,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : palette.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? RpckTheme.primary
            : palette.surfaceHigh,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: RpckTheme.primary,
        foregroundColor: Colors.white,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.onSurface,
        side: BorderSide(color: palette.hairline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: RpckTheme.primary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      hintStyle: TextStyle(color: palette.muted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: RpckTheme.primary, width: 1.4),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.hairline),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: RpckTheme.primary,
      inactiveTrackColor: palette.surfaceHigh,
      thumbColor: RpckTheme.primary,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.hairline),
      ),
      textStyle: TextStyle(color: palette.onSurface, fontSize: 12),
    ),
  );
}

class _StartupFailure extends StatelessWidget {
  final Failure? failure;

  const _StartupFailure({this.failure});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                'PRJCT RPCK could not start',
                style: TextStyle(color: palette.onSurface, fontSize: 20),
              ),
              const SizedBox(height: 10),
              Text(
                failure?.message ?? 'an unknown startup error occurred',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}