import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:html/parser.dart' as html_parser;

class MediaFireDownloader {
  /// Extracts the direct download link from a MediaFire page
  static Future<String?> _getDirectDownloadLink(String mediaFireUrl) async {
    try {
      final response = await http.get(Uri.parse(mediaFireUrl));
      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);

        // Find the direct download link in the HTML
        final downloadButton = document.querySelector('a#downloadButton');
        if (downloadButton != null) {
          return downloadButton.attributes['href'];
        }
      }
    } catch (e) {
      debugPrint('Error fetching MediaFire link: $e');
    }
    return null;
  }

  /// Downloads a file from MediaFire
  static Future<String> downloadFile(String mediaFireUrl, String fileName) async {
    try {
      // Step 1: Get the direct download link
      final directLink = await _getDirectDownloadLink(mediaFireUrl);
      if (directLink == null) {
        throw Exception('Failed to extract direct download link');
      }

      // Step 2: Download the file
      final response = await http.get(Uri.parse(directLink));
      if (response.statusCode == 200) {
        // Step 3: Save the file to device storage
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);

        await file.writeAsBytes(response.bodyBytes);
        debugPrint('File saved to: $filePath');
        return file.absolute.path;
      } else {
        throw Exception('Failed to download file: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error downloading file: $e');
      rethrow;
    }
  }
}
