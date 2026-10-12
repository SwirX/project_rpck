import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_rpck/api/fitgirl/fitgirl.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:carousel_slider/carousel_slider.dart';

import '../api/repack_base.dart';

class RepackDetailsPage extends StatefulWidget {
  final RepackInfo repack;

  const RepackDetailsPage({super.key, required this.repack});

  @override
  State<RepackDetailsPage> createState() => _RepackDetailsPageState();
}

class _RepackDetailsPageState extends State<RepackDetailsPage> {
  bool downloading = false;
  bool downloadingError = false;
  bool downloadingSuccess = false;

  void showScreenshotsPopup(BuildContext context, List<String> screenshots,
      String currentScreenshot) {
    showDialog(
      context: context,
      barrierDismissible: true, // Close when clicking outside
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.pop(context), // Dismiss when tapping outside
          child: Material(
            color: Colors.black.withOpacity(0.7), // Dim background
            child: Center(
              child: GestureDetector(
                onTap: () {}, // Prevent closing when tapping inside
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Container(
                      width: MediaQuery.of(context).size.width * 0.8,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CarouselSlider(
                            options: CarouselOptions(
                              autoPlay: true,
                              enlargeCenterPage: true,
                              enableInfiniteScroll: true,
                              initialPage:
                                  screenshots.indexOf(currentScreenshot),
                            ),
                            items: screenshots.map((url) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.broken_image,
                                          size: 100, color: Colors.white38),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isMobile = constraints.maxWidth < 800;
          List<String> screenshots = widget.repack.screenshots;
          String gameCover = screenshots.first;
          List<String> otherScreenshots = screenshots.sublist(1);

          return Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.1,
                  child: CachedNetworkImage(
                    imageUrl: gameCover,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 20 : 80, vertical: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Hero(
                          tag: widget.repack.url,
                          child: CachedNetworkImage(
                            imageUrl: gameCover,
                            width: isMobile ? 200 : 400,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.repack.title.toUpperCase(),
                      style: GoogleFonts.bebasNeue(
                        fontSize: isMobile ? 50 : 100,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.repack.description,
                      style: GoogleFonts.roboto(
                        fontSize: 18,
                        // ignore: deprecated_member_use
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 30),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 20,
                        children: otherScreenshots
                            .map((img) => GestureDetector(
                                  onTap: () => showScreenshotsPopup(
                                      context, otherScreenshots, img),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                        imageUrl: img,
                                        width: isMobile ? 150 : 250,
                                        height: isMobile ? 90 : 140,
                                        fit: BoxFit.cover),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      "Game Info",
                      style: GoogleFonts.bebasNeue(
                        fontSize: isMobile ? 30 : 50,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children: widget.repack.info.entries.map((entry) {
                        String name = entry.key;
                        String value = entry.value;
                        if (name.isEmpty || value.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        if (name.length > 15) {
                          name = name.replaceAll("_", " ");
                        }
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: SizedBox(
                                width: name.length > 15
                                    ? MediaQuery.of(context).size.width * 0.75
                                    : null,
                                child: Text(
                                  name.length > 15 ? name : '$name:',
                                  style: GoogleFonts.roboto(
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            name.length < 15
                                ? Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      value,
                                      style: GoogleFonts.roboto(
                                        fontSize: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink()
                          ],
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 30),

                    Center(
                      child: Text(
                        "Downloads",
                        style: GoogleFonts.bebasNeue(
                          fontSize: isMobile ? 40 : 60,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Magnet Links

                    Text(
                      "Magnet Links",
                      style: GoogleFonts.bebasNeue(
                        fontSize: isMobile ? 30 : 50,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children:
                          widget.repack.magnets.asMap().entries.map((entry) {
                        int index = entry.key + 1;
                        String download = entry.value ?? '';
                        return ListTile(
                          title: Text(
                            'Magnet $index',
                            style: GoogleFonts.roboto(
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              launchUrlString(download);
                            },
                            child: const Text(
                              "Open",
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 30),

                    // Torrents

                    Text(
                      "Torrents",
                      style: GoogleFonts.bebasNeue(
                        fontSize: isMobile ? 30 : 50,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children: widget.repack.torrent.map(
                        (download) {
                          final name = Uri.tryParse(download)?.host;
                          if (name == null || download.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            child: ListTile(
                              title: Text(
                                name,
                                style: GoogleFonts.roboto(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () async {
                                  if (!downloadingSuccess) {
                                    setState(() {
                                      downloading = true;
                                    });
                                    await downloadFile(
                                      download,
                                      '${widget.repack.title}.torrent',
                                    );
                                    await Future.delayed(
                                      const Duration(seconds: 2),
                                    );
                                    setState(() {
                                      downloading = false;
                                      downloadingSuccess = true;
                                    });
                                  } else {
                                    final downloadDir =
                                        await getDownloadsDirectory();
                                    launchUrlString(downloadDir?.path ?? '');
                                  }
                                },
                                child: downloading
                                    ? LottieBuilder.asset(
                                        'assets/animations/download.json',
                                        height: 30,
                                        width: 30,
                                      )
                                    : downloadingSuccess
                                        ? const Icon(
                                            Icons.folder,
                                            color: Colors.white,
                                            size: 30,
                                          )
                                        : const Text(
                                            "Download",
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                              ),
                            ),
                          );
                        },
                      ).toList(),
                    ),
                    const SizedBox(height: 30),

                    // Download Links

                    Text(
                      "Download Links",
                      style: GoogleFonts.bebasNeue(
                        fontSize: isMobile ? 30 : 50,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children: widget.repack.downloads.map((download) {
                        if (download.name.isEmpty ||
                            download.url.contains("torrent") ||
                            download.url.contains("magnet") ||
                            download.name.contains("torrent")) {
                          return const SizedBox.shrink();
                        }
                        return ListTile(
                          title: Text(
                            download.name,
                            style: GoogleFonts.roboto(
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              if (kDebugMode) {
                                print(download.url);
                              }
                              launchUrlString(download.url);
                            },
                            child: const Text(
                              "Open In Browser",
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              Positioned(
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: Colors.white,
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}
