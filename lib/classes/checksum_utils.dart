import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class ChecksumUtils {
  /// Computes the SHA-256 checksum of a file
  static Future<String> computeChecksum(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist: $filePath');
    }

    // Read the file in chunks to handle large files
    final stream = file.openRead();
    final hash = await sha256.bind(stream).first;

    // Convert the hash bytes to a hex string
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Verifies the file's checksum against an expected value
  static Future<bool> verifyChecksum(String filePath, String expectedChecksum) async {
    try {
      final computedChecksum = await computeChecksum(filePath);
      return computedChecksum == expectedChecksum.toLowerCase();
    } catch (e) {
      debugPrint('Error verifying checksum: $e');
      return false;
    }
  }
}