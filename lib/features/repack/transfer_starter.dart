import 'package:flutter/material.dart';

import '../../bootstrap.dart';
import '../../core/platform/download_location.dart';
import '../../domain/models/repack.dart';
import '../../domain/models/source_option.dart';
import '../../download/transfer.dart';
import '../../ui/app_settings.dart';
import '../settings/setting_effects.dart';
import 'downloads_section.dart';
import 'transfer_confirmation.dart';

/// Queues [option] for [repack] and reports what happened.
///
/// Pulled out of the page widget so the decision order is readable in one
/// place: confirm, resolve a writable directory, turn the repack title into a
/// filename, enqueue, start.
///
/// Every step reports rather than throws, because a download that cannot start
/// has to say so on screen instead of leaving the user pressing a button that
/// does nothing.
Future<String> startTransfer({
  required BuildContext context,
  required AppEnvironment environment,
  required Repack repack,
  required SourceOption option,
  required AppSettings settings,
}) async {
  // Asked before anything is enqueued, so cancelling leaves no queued record
  // and no journal entry behind.
  if (shouldConfirmBeforeTransfer(settings) &&
      !await confirmTransfer(
        context,
        title: repack.title,
        description: describe(option),
        folder: settings.downloadFolder ?? defaultDownloadFolderName,
      )) {
    return 'Cancelled';
  }
  if (!context.mounted) return 'Cancelled';

  final directory = (await DownloadLocation.resolve(
    override: settings.downloadFolder,
  ))
      .valueOrNull;
  if (directory == null) return 'No writable download directory.';

  final suffix = switch (option) {
    MagnetOption() => 'magnet',
    TorrentFileOption() => 'torrent',
    TorrentIndexOption() => 'index',
    DirectOption(:final parts) =>
      parts.length > 1 ? 'mirror-${parts.length}parts' : 'mirror',
  };

  final savePath = directory
      .resolveFileName(
        DownloadLocation.sanitizeFileName('${repack.title} [$suffix]'),
      )
      .valueOrNull;
  if (savePath == null) return 'That repack title cannot be used as a file name.';

  final transfer = Transfer.forOption(
    // Derived from the source so a re-tap on the same option is the same
    // transfer rather than a second copy of it.
    id: '${repack.sourceUri.hashCode}-${option.hashCode}',
    title: repack.title,
    option: option,
    savePath: savePath,
  );

  environment.transfers.enqueue(transfer);
  final result = await environment.transfers.start(transfer);
  return result.fold(
    (_) => 'Queued ${option.label}.',
    (failure) => failure.message,
  );
}