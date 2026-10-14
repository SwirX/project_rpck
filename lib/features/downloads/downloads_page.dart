import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../bootstrap.dart';
import '../../download/transfer.dart';
import '../../ui/prjct_app_bar.dart';

/// Live transfer list.
///
/// The prototype rendered three hardcoded games with literal progress values
/// and declared its own `DownloadStatus` enum, which did not match the enum the
/// torrent layer used.
class DownloadsPage extends StatelessWidget {
  final AppEnvironment environment;

  const DownloadsPage({super.key, required this.environment});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            PrjctAppBar(
              title: 'DOWNLOADS',
              subtitle: 'Torrents, magnets and mirrors',
              leading: _BackButton(onPressed: () => Navigator.of(context).pop()),
              actions: [
                PrjctAppBarAction(
                  icon: Icons.delete_sweep_outlined,
                  tooltip: 'Clear finished',
                  onPressed: () {
                    for (final transfer in environment.transfers.completed
                        .toList(growable: false)) {
                      environment.transfers.remove(transfer.id);
                    }
                  },
                ),
              ],
            ),
            Expanded(
              child: StreamBuilder<List<Transfer>>(
                stream: environment.transfers.snapshots,
                initialData: environment.transfers.all,
                builder: (context, snapshot) {
                  final transfers = snapshot.data ?? const <Transfer>[];
                  if (transfers.isEmpty) {
                    return const _EmptyState();
                  }
                  final active =
                      transfers.where((t) => !t.isTerminal).toList(growable: false);
                  final finished =
                      transfers.where((t) => t.isTerminal).toList(growable: false);

                  return ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      if (active.isNotEmpty) ...[
                        _SectionHeader('IN PROGRESS', active.length),
                        for (final transfer in active)
                          _TransferCard(transfer: transfer),
                      ],
                      if (finished.isNotEmpty) ...[
                        _SectionHeader('FINISHED', finished.length),
                        for (final transfer in finished)
                          _TransferCard(transfer: transfer),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Back',
      icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 30),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.download_outlined, size: 56, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            'No transfers yet',
            style: GoogleFonts.bebasNeue(
              fontSize: 24,
              color: Colors.white70,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick a download from a repack to start one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader(this.title, this.count);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.blueAccent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.blueAccent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  final Transfer transfer;

  const _TransferCard({required this.transfer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: transfer.status == TransferStatus.failed
              ? Colors.redAccent.withValues(alpha: .4)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusGlyph(status: transfer.status),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      transfer.source.label,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _ThroughputLabel(transfer: transfer),
            ],
          ),
          const SizedBox(height: 16),
          _ProgressRow(transfer: transfer),
          if (transfer.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              transfer.errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusGlyph extends StatelessWidget {
  final TransferStatus status;

  const _StatusGlyph({required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      TransferStatus.completed => (Icons.check_circle, Colors.greenAccent),
      TransferStatus.failed => (Icons.error_outline, Colors.redAccent),
      TransferStatus.paused => (Icons.pause_circle, Colors.amberAccent),
      TransferStatus.resolving => (Icons.hourglass_top, Colors.blueAccent),
      _ => (Icons.downloading, Colors.blueAccent),
    };
    return Icon(icon, color: color, size: 30);
  }
}

class _ThroughputLabel extends StatelessWidget {
  final Transfer transfer;

  const _ThroughputLabel({required this.transfer});

  @override
  Widget build(BuildContext context) {
    if (transfer.status != TransferStatus.downloading ||
        transfer.bytesPerSecond <= 0) {
      return const SizedBox.shrink();
    }
    return Text(
      '${formatBytes(transfer.bytesPerSecond.round())}/s',
      style: const TextStyle(
        color: Colors.blueAccent,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final Transfer transfer;

  const _ProgressRow({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final fraction = transfer.fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(
            children: [
              Container(height: 4, color: Colors.white.withValues(alpha: .1)),
              AnimatedFractionallySizedBox(
                alignment: Alignment.centerLeft,
                duration: const Duration(milliseconds: 300),
                widthFactor: fraction ?? (transfer.isTerminal ? 1 : 0),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: transfer.status == TransferStatus.failed
                          ? [Colors.redAccent, Colors.red]
                          : [Colors.blueAccent, Colors.purpleAccent],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              _statusText(transfer),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const Spacer(),
            Text(
              fraction == null
                  ? formatBytes(transfer.downloadedBytes)
                  : '${(fraction * 100).round()}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _statusText(Transfer transfer) => switch (transfer.status) {
        TransferStatus.queued => 'Queued',
        TransferStatus.resolving => 'Resolving metadata',
        TransferStatus.downloading => transfer.totalBytes > 0
            ? '${formatBytes(transfer.downloadedBytes)} of '
                '${formatBytes(transfer.totalBytes)}'
            : formatBytes(transfer.downloadedBytes),
        TransferStatus.paused => 'Paused',
        TransferStatus.verifying => 'Verifying',
        TransferStatus.completed =>
          '${formatBytes(transfer.downloadedBytes)} downloaded',
        TransferStatus.failed => 'Failed',
      };
}

/// Formats a byte count for display.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final precision = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unit]}';
}