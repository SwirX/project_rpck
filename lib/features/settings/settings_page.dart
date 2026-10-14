import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bootstrap.dart';
import '../../ui/prjct_app_bar.dart';
import '../downloads/downloads_page.dart';

/// Settings with working controls.
///
/// The prototype shipped Dark Mode and Notifications switches whose `onChanged`
/// bodies were empty, and a Clear Cache action that deleted the OS cache
/// directory and then called `exit(0)`.
class SettingsPage extends StatefulWidget {
  final AppEnvironment environment;

  const SettingsPage({super.key, required this.environment});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _darkMode = true;
  bool _notifications = true;
  String _downloadLocation = 'resolving';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final location = widget.environment.cache.root.path;
    if (!mounted) return;
    setState(() {
      _darkMode = prefs.getBool('dark_mode') ?? true;
      _notifications = prefs.getBool('notifications') ?? true;
      _downloadLocation = location;
    });
  }

  Future<void> _setDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
    if (mounted) setState(() => _darkMode = value);
  }

  Future<void> _setNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications', value);
    if (mounted) setState(() => _notifications = value);
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cache'),
        content: const Text(
          'Cached pages will be fetched again on next use.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await widget.environment.cache.purgeEntries();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.fold(
              (removed) => 'Removed $removed cached entries.',
              (failure) => failure.message,
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            PrjctAppBar(
              title: 'SETTINGS',
              leading: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Back',
                icon: const Icon(Icons.chevron_left_rounded,
                    color: Colors.white, size: 30),
              ),
              height: 104,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                children: [
                  const _SectionLabel('APPEARANCE'),
                  _Tile(
                    title: 'Dark mode',
                    icon: Icons.dark_mode_outlined,
                    trailing: Switch(
                      value: _darkMode,
                      onChanged: _setDarkMode,
                    ),
                  ),
                  const _SectionLabel('TRANSFERS'),
                  _Tile(
                    title: 'Downloads',
                    icon: Icons.download_outlined,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            DownloadsPage(environment: widget.environment),
                      ),
                    ),
                  ),
                  _Tile(
                    title: 'Download folder',
                    icon: Icons.folder_outlined,
                    subtitle: _downloadLocation,
                  ),
                  const _SectionLabel('NOTIFICATIONS'),
                  _Tile(
                    title: 'Transfer notifications',
                    icon: Icons.notifications_outlined,
                    trailing: Switch(
                      value: _notifications,
                      onChanged: _setNotifications,
                    ),
                  ),
                  const _SectionLabel('STORAGE'),
                  _Tile(
                    title: 'Clear cache',
                    icon: Icons.delete_outline,
                    onTap: _clearCache,
                  ),
                  const _SectionLabel('ABOUT'),
                  const _Tile(
                    title: 'About',
                    icon: Icons.info_outline,
                    subtitle: 'Repack catalogue and transfer client',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        text,
        style: GoogleFonts.bebasNeue(
          fontSize: 17,
          color: Colors.white54,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Tile({
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
        trailing: trailing,
      ),
    );
  }
}