import 'package:flutter/material.dart';

import '../../bootstrap.dart';
import '../../core/platform/download_location.dart';
import '../../ui/app_settings.dart';
import '../../ui/rpck_top_bar.dart';
import '../onboarding/onboarding_guide.dart';
import 'settings_page.dart';
import 'settings_widgets.dart';

/// Looks and feel.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final tiles = <Widget>[
        SettingChoice<ThemeMode>(
          title: 'Theme',
          icon: Icons.palette_outlined,
          subtitle: 'Applies immediately, everywhere',
          value: settings.themeMode,
          options: const [
            (ThemeMode.system, 'Follow system'),
            (ThemeMode.light, 'Light'),
            (ThemeMode.dark, 'Dark'),
          ],
          mutate: (current, chosen) => current.copyWith(themeMode: chosen),
        ),
      ];
    return SettingGroup(
      title: 'Appearance',
      footer: 'Every surface reads its colours from the active palette, so a '
          'switch here changes the whole app rather than part of it.',
      children: tiles,
    );
  }
}

/// Where transfers go and how they behave.
class DownloadsSection extends StatelessWidget {
  const DownloadsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);

    return SettingGroup(
      title: 'Downloads',
      children: [
        SettingReadout(
          title: 'Download folder',
          icon: Icons.folder_outlined,
          value: settings.downloadFolder ?? 'System Downloads',
          actionLabel: 'Change',
          onTap: () => _chooseFolder(context, settings),
        ),
        SettingSwitch(
          title: 'Ask before starting',
          icon: Icons.help_outline_rounded,
          subtitle: 'Confirm each transfer instead of starting it immediately',
          value: settings.confirmBeforeTransfer,
          mutate: (current) =>
              current.copyWith(confirmBeforeTransfer: !current.confirmBeforeTransfer),
        ),
        SettingSwitch(
          title: 'Resume transfers on launch',
          icon: Icons.play_circle_outline_rounded,
          subtitle: 'Reattach to transfers that were running when the app closed',
          value: settings.resumeTransfersOnLaunch,
          mutate: (current) =>
              current.copyWith(resumeTransfersOnLaunch: !current.resumeTransfersOnLaunch),
        ),
        SettingSwitch(
          title: 'Notify when a transfer finishes',
          icon: Icons.notifications_outlined,
          value: settings.notifyOnTransferComplete,
          mutate: (current) =>
              current.copyWith(notifyOnTransferComplete: !current.notifyOnTransferComplete),
        ),
      ],
    );
  }

  Future<void> _chooseFolder(BuildContext context, AppSettings settings) async {
    // Resolved before the dialog so the field opens on a real path rather
    // than an empty box.
    final location = await DownloadLocation.resolve(
      override: settings.downloadFolder,
    );
    final fallback = location.fold(
      (value) => value.directory.path,
      (_) => '',
    );
    if (!context.mounted) return;

    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => _FolderDialog(fallback: fallback),
    );
    if (chosen == null || !context.mounted) return;

    await AppSettingsScope.update(
      context,
      (app) => chosen.isEmpty
          ? app.copyWith(clearDownloadFolder: true)
          : app.copyWith(downloadFolder: chosen),
    );
    if (!context.mounted) return;
    notify(
      context,
      chosen.isEmpty ? 'Using the system Downloads folder' : 'Folder updated',
    );
  }
}

class _FolderDialog extends StatefulWidget {
  final String fallback;

  const _FolderDialog({required this.fallback});

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.fallback);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Download folder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '/path/to/downloads'),
          ),
          const SizedBox(height: 10),
          Text(
            'Leave empty to use the system Downloads folder.',
            style: TextStyle(color: context.palette.muted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('Use default'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Catalogue behaviour.
class CatalogueSection extends StatelessWidget {
  const CatalogueSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);

    return SettingGroup(
      title: 'Catalogue',
      children: [
        SettingSwitch(
          title: 'Show trending',
          icon: Icons.local_fire_department_outlined,
          subtitle: 'Storefront picks above the catalogue, matched to your index',
          value: settings.showTrending,
          mutate: (current) => current.copyWith(showTrending: !current.showTrending),
        ),
        SettingChoice<int>(
          title: 'Artwork fetches at once',
          icon: Icons.image_outlined,
          subtitle: 'Lower is gentler on the source, higher fills the grid faster',
          value: settings.concurrentArtworkFetches,
          options: const [(2, '2'), (4, '4'), (6, '6'), (8, '8')],
          mutate: (current, chosen) =>
              current.copyWith(concurrentArtworkFetches: chosen),
        ),
      ],
    );
  }
}

/// Update behaviour.
class NetworkSection extends StatelessWidget {
  const NetworkSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);

    final tiles = <Widget>[
        SettingSwitch(
          title: 'Check for updates automatically',
          icon: Icons.system_update_alt_rounded,
          subtitle: 'Reads the Hyperion record and GitHub releases at launch',
          value: settings.autoUpdate,
          mutate: (current) => current.copyWith(autoUpdate: !current.autoUpdate),
        ),
    ];
    return SettingGroup(
      title: 'Updates',
      footer: 'An update is only ever offered when its checksum is published, '
          'and Windows builds can install it themselves.',
      children: tiles,
    );
  }
}

/// Storage and diagnostic actions.
class AdvancedSection extends StatelessWidget {
  final AppEnvironment environment;
  final String? cacheMessage;
  final void Function(String message) onCacheCleared;

  const AdvancedSection({
    super.key,
    required this.environment,
    this.cacheMessage,
    required this.onCacheCleared,
  });

  @override
  Widget build(BuildContext context) {
    return SettingGroup(
      title: 'Storage',
      children: [
        SettingTile(
          title: 'Clear cached pages',
          icon: Icons.delete_outline_rounded,
          subtitle: cacheMessage ?? 'Removes cached pages, not your catalogue',
          onTap: () => _clearCache(context),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        ),
        SettingTile(
          title: 'Clear the catalogue',
          icon: Icons.inventory_2_outlined,
          subtitle: 'Deletes every indexed repack so you can start over',
          onTap: () => _clearCatalogue(context),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        ),
      ],
    );
  }

  Future<void> _clearCache(BuildContext context) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Clear cached pages',
      message: 'Cached pages will be fetched again on next use. '
          'Your catalogue and downloads are untouched.',
      confirmLabel: 'Clear',
    );
    if (!confirmed || !context.mounted) return;

    final result = await environment.cache.purgeEntries();
    if (!context.mounted) return;
    final message = describeResult(result, 'Removed');
    onCacheCleared(message);
    notify(context, message);
  }

  Future<void> _clearCatalogue(BuildContext context) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Clear the catalogue',
      message: 'Every indexed repack is deleted. '
          'You will need to reindex before browsing again.',
      confirmLabel: 'Delete everything',
    );
    if (!confirmed || !context.mounted) return;

    await environment.catalogue.clear();
    if (!context.mounted) return;
    onCacheCleared('Catalogue cleared');
    notify(context, 'Catalogue cleared');
  }
}

/// Help and onboarding.
class HelpSection extends StatelessWidget {
  final AppEnvironment environment;

  const HelpSection({super.key, required this.environment});

  @override
  Widget build(BuildContext context) {
    return SettingGroup(
      title: 'Help',
      children: [
        SettingTile(
          title: 'How to use the app',
          icon: Icons.help_outline_rounded,
          subtitle: 'Browsing, transfers, reindexing and settings',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const OnboardingGuide()),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        ),
        SettingTile(
          title: 'Replay the welcome wizard',
          icon: Icons.replay_rounded,
          subtitle: 'Runs the first-time steps again, keeping your catalogue',
          onTap: () => _replay(context, environment),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        ),
      ],
    );
  }

  Future<void> _replay(BuildContext context, AppEnvironment environment) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Replay onboarding',
      message: 'The wizard runs from the first step again. '
          'Your catalogue is kept.',
      confirmLabel: 'Replay',
    );
    if (!confirmed || !context.mounted) return;
    await environment.resetOnboarding();
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }
}

/// Version information.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingGroup(
      title: 'About',
      children: [
        SettingReadout(
          title: 'PRJCT RPCK',
          icon: Icons.info_outline_rounded,
          value: 'Repack catalogue and transfer client',
        ),
      ],
    );
  }
}
