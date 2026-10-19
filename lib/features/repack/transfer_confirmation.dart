import 'package:flutter/material.dart';

import '../../ui/rpck_top_bar.dart';

/// Shown when [confirmTransfer] is enabled, before anything is enqueued.
///
/// Kept separate from the repack page so the wording and the two outcomes can
/// be tested without standing up a source adapter and a live transfer.
Future<bool> confirmTransfer(
  BuildContext context, {
  required String title,
  required String description,
  required String folder,
}) async {
  final palette = context.palette;
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: palette.surfaceHigh,
      title: const Text('Start this download?'),
      content: Text(
        '$title\n\n$description\n\nSaved to $folder.',
        style: TextStyle(color: palette.muted, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Start'),
        ),
      ],
    ),
  );
  // Dismissed rather than answered, which is a refusal: starting a multi-gigabyte
  // download because the dialog was swiped away is not what anyone meant.
  return answer ?? false;
}

/// What the settings screen calls the default location when none is set.
const defaultDownloadFolderName = 'the Downloads folder';