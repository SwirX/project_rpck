import 'package:flutter/material.dart';

import '../../bootstrap.dart';
import '../../core/result.dart';
import '../../ui/rpck_top_bar.dart';
import 'settings_sections.dart';

/// Every setting the app exposes, grouped by what it affects.
///
/// Each control writes through [AppSettingsScope] so a change takes effect on
/// the current frame rather than on the next launch, and is persisted at the
/// same time.
class SettingsPage extends StatefulWidget {
  final AppEnvironment environment;

  const SettingsPage({super.key, required this.environment});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _cacheMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            RpckTopBar(
              leading: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
                children: [
                  const AppearanceSection(),
                  const DownloadsSection(),
                  const CatalogueSection(),
                  const NetworkSection(),
                  AdvancedSection(
                    environment: widget.environment,
                    cacheMessage: _cacheMessage,
                    onCacheCleared: (message) =>
                        setState(() => _cacheMessage = message),
                  ),
                  HelpSection(environment: widget.environment),
                  const AboutSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation dialog shared by the destructive actions.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final palette = context.palette;
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: palette.surfaceHigh,
      title: Text(title, style: TextStyle(color: palette.onSurface)),
      content: Text(message, style: TextStyle(color: palette.muted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel, style: const TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// Shows a short confirmation after an action completes.
void notify(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Surfaces a failure or its message, whichever the result carries.
String describeResult(Result<int> result, String onSuccess) => result.fold(
      (count) => '$onSuccess $count',
      (failure) => failure.message,
    );