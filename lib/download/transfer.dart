import '../domain/models/source_option.dart';

enum TransferStatus {
  queued,
  resolving,
  downloading,
  paused,
  verifying,
  completed,
  failed;

  /// True when nothing further will happen on its own.
  bool get isTerminal => this == completed || this == failed;
}

/// Immutable snapshot of one transfer, emitted to the UI.
class Transfer {
  final String id;
  final String title;
  final TransferStatus status;

  /// Bytes written to disk.
  final int downloadedBytes;

  /// Total payload size, or 0 while still unknown (mid-magnet resolution).
  final int totalBytes;

  final double bytesPerSecond;
  final int connectedPeers;
  final int availablePeers;
  final String? errorMessage;
  final String savePath;

  /// What this transfer was started from. Kept so an engine can recover the
  /// method it was dispatched with after the transfer has been persisted.
  final SourceOption source;

  const Transfer({
    required this.id,
    required this.title,
    required this.source,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
    required this.connectedPeers,
    required this.availablePeers,
    required this.savePath,
    this.errorMessage,
  });

  /// 0.0 to 1.0, or null when the total size is not yet known.
  double? get fraction => totalBytes <= 0 ? null : downloadedBytes / totalBytes;

  bool get isTerminal => status.isTerminal;

  bool get isActive =>
      status == TransferStatus.downloading || status == TransferStatus.resolving;

  Transfer copyWith({
    TransferStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    double? bytesPerSecond,
    int? connectedPeers,
    int? availablePeers,
    String? errorMessage,
  }) {
    return Transfer(
      id: id,
      title: title,
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      connectedPeers: connectedPeers ?? this.connectedPeers,
      availablePeers: availablePeers ?? this.availablePeers,
      savePath: savePath,
      source: source,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  /// Which acquisition method this transfer was started from.
  static Transfer forOption({
    required String id,
    required String title,
    required SourceOption option,
    required String savePath,
  }) {
    return Transfer(
      id: id,
      title: title,
      status: TransferStatus.queued,
      downloadedBytes: 0,
      totalBytes: 0,
      bytesPerSecond: 0,
      connectedPeers: 0,
      availablePeers: 0,
      savePath: savePath,
      source: option,
    );
  }
}