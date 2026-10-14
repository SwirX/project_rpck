import 'package:flutter/material.dart';

import '../../sources/source_registry.dart';

/// Picks which registered repack source the library browses.
///
/// Rendered only when more than one source is registered, which is the state
/// that proves the source registry is doing its job.
class SourceSelector extends StatelessWidget {
  final SourceRegistry sources;

  const SourceSelector({super.key, required this.sources});

  @override
  Widget build(BuildContext context) {
    final available = sources.all;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Text(
              'REPACK SOURCES',
              style: TextStyle(
                color: Colors.blueAccent,
                fontSize: 13,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final source in available)
            ListTile(
              leading: const Icon(Icons.public, color: Colors.white70),
              title: Text(
                source.displayName,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                [
                  if (source.supportsTorrentFile) 'torrent',
                  if (source.supportsMagnet) 'magnet',
                  if (source.supportsDirectDownload) 'mirror',
                ].join(' · '),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              onTap: () => Navigator.of(context).pop(source.id),
            ),
          if (available.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No repack source is registered.',
                style: TextStyle(color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }
}