import 'dart:async';

import 'package:flutter/material.dart';

import '../../download/transfer.dart';
import '../../download/transfer_registry.dart';
import '../../ui/app_settings.dart';
import '../settings/setting_effects.dart';

/// Watches the transfer registry and tells the user when something finishes.
///
/// Sits above the navigator so the notice appears wherever the user is, rather
/// than only on the downloads screen they may have navigated away from.
///
/// The notice is in-app. No notification plugin is a dependency, and adding one
/// for a desktop-first app to say "finished" is not a trade worth making on its
/// own; the downloads screen stays the detailed view.
class TransferNotifier extends StatefulWidget {
  final TransferRegistry transfers;
  final Widget child;

  const TransferNotifier({
    super.key,
    required this.transfers,
    required this.child,
  });

  @override
  State<TransferNotifier> createState() => _TransferNotifierState();
}

class _TransferNotifierState extends State<TransferNotifier> {
  StreamSubscription<Transfer>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.transfers.completions.listen(_announce);
  }

  void _announce(Transfer transfer) {
    if (!mounted) return;
    if (!shouldAnnounceCompletion(AppSettingsScope.of(context))) return;

    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(transferCompleteMessage(transfer.title)),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Wording shared by the notifier and any other surface that reports one.
String transferCompleteMessage(String title) =>
    title.isEmpty ? 'A transfer finished' : '$title finished downloading';