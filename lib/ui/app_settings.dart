import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_controller.dart';

/// Everything the user can change, in one place.
///
/// Held above the navigator so a toggle takes effect immediately rather than on
/// the next launch, and persisted so the choice survives a restart.
class AppSettings {
  final ThemeMode themeMode;
  final bool autoUpdate;
  final bool showTrending;
  final bool confirmBeforeTransfer;
  final int concurrentArtworkFetches;
  final bool resumeTransfersOnLaunch;
  final String? downloadFolder;
  final bool notifyOnTransferComplete;

  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.autoUpdate = true,
    this.showTrending = true,
    this.confirmBeforeTransfer = false,
    this.concurrentArtworkFetches = 4,
    this.resumeTransfersOnLaunch = true,
    this.downloadFolder,
    this.notifyOnTransferComplete = true,
  });

  static const _prefix = 'settings.';
  static const _prefixTheme = 'settings.themeMode';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefixTheme) ?? const <String>[];
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == (stored.isNotEmpty ? stored.first : 'dark'),
        orElse: () => ThemeMode.dark,
      ),
      autoUpdate: prefs.getBool('${_prefix}autoUpdate') ?? true,
      showTrending: prefs.getBool('${_prefix}showTrending') ?? true,
      confirmBeforeTransfer: prefs.getBool('${_prefix}confirm') ?? false,
      concurrentArtworkFetches: prefs.getInt('${_prefix}artwork') ?? 4,
      resumeTransfersOnLaunch: prefs.getBool('${_prefix}resume') ?? true,
      downloadFolder: prefs.getString('${_prefix}folder'),
      notifyOnTransferComplete: prefs.getBool('${_prefix}notify') ?? true,
    );
  }

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? autoUpdate,
    bool? showTrending,
    bool? confirmBeforeTransfer,
    int? concurrentArtworkFetches,
    bool? resumeTransfersOnLaunch,
    String? downloadFolder,
    bool clearDownloadFolder = false,
    bool? notifyOnTransferComplete,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      showTrending: showTrending ?? this.showTrending,
      confirmBeforeTransfer:
          confirmBeforeTransfer ?? this.confirmBeforeTransfer,
      concurrentArtworkFetches:
          concurrentArtworkFetches ?? this.concurrentArtworkFetches,
      resumeTransfersOnLaunch:
          resumeTransfersOnLaunch ?? this.resumeTransfersOnLaunch,
      downloadFolder:
          clearDownloadFolder ? null : (downloadFolder ?? this.downloadFolder),
      notifyOnTransferComplete:
          notifyOnTransferComplete ?? this.notifyOnTransferComplete,
    );
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefixTheme, [themeMode.name]);
    await prefs.setBool('${_prefix}autoUpdate', autoUpdate);
    await prefs.setBool('${_prefix}showTrending', showTrending);
    await prefs.setBool('${_prefix}confirm', confirmBeforeTransfer);
    await prefs.setInt('${_prefix}artwork', concurrentArtworkFetches);
    await prefs.setBool('${_prefix}resume', resumeTransfersOnLaunch);
    await prefs.setBool('${_prefix}notify', notifyOnTransferComplete);
    final folder = downloadFolder;
    if (folder == null) {
      await prefs.remove('${_prefix}folder');
    } else {
      await prefs.setString('${_prefix}folder', folder);
    }
  }
}

/// Makes the current settings and an update callback available to the tree.
///
/// Preferred over passing settings through every constructor: the tree reaches
/// them through context, so a new screen picks them up without touching its
/// callers. The value rides along as a snapshot so dependents are only notified
/// when a setting actually differs; the [controller] is what writes route
/// through, and what services with no widget above them read.
class AppSettingsScope extends InheritedWidget {
  final SettingsController controller;
  final AppSettings settings;

  const AppSettingsScope({
    super.key,
    required this.controller,
    required this.settings,
    required super.child,
  });

  /// Stand-in for screens pumped outside the app, as tests do.
  static final _detached = SettingsController();

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSettingsScope>()?.settings ??
      const AppSettings();

  /// Applies a change, persists it, and rebuilds dependents.
  static Future<void> update(
    BuildContext context,
    AppSettings Function(AppSettings current) mutate,
  ) =>
      (context.dependOnInheritedWidgetOfExactType<AppSettingsScope>()
              ?.controller ??
          _detached)
          .update(mutate);

  @override
  bool updateShouldNotify(AppSettingsScope oldWidget) =>
      oldWidget.settings != settings;
}
