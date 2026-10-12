import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/api/fitgirl/fitgirl.dart';
import '/api/repack_base.dart';
import 'settings.dart';
import 'game_details.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Fitgirl fitgirl = Fitgirl();
  late Future<List<GameIndex>> _gamesFuture;
  final Map<String, Future<RepackInfo>> _gameDetails = {};

  @override
  void initState() {
    super.initState();
    _gamesFuture = fitgirl.indexDatabase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'GAME LIBRARY',
          style: GoogleFonts.bebasNeue(
            fontSize: 28,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.black,
        centerTitle: true,
        actions: [
          // IconButton(
          //   onPressed: () => Navigator.push(
          //     context,
          //     MaterialPageRoute(
          //       builder: (context) => const SearchPage(),
          //     ),
          //   ),
          //   icon: Icon(Icons.search_rounded, color: Colors.white),
          // ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SettingsPage(),
              ),
            ),
            icon: Icon(Icons.settings, color: Colors.white),
          ),
        ],
      ),
      body: FutureBuilder<List<GameIndex>>(
        future: _gamesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.white));
          } else if (snapshot.hasError) {
            return const Center(
                child: Text(
              'ERROR FETCHING DATABASE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ));
          } else if (snapshot.hasData) {
            final games = snapshot.data!;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 0.7,
                ),
                itemCount: games.length,
                itemBuilder: (context, index) {
                  final game = games[index];
                  _gameDetails[game.title!] ??= fitgirl.fetchGameInfo(game);

                  return FutureBuilder<RepackInfo>(
                    future: _gameDetails[game.title],
                    builder: (context, detailsSnapshot) {
                      Widget content;
                      if (detailsSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        content = const Center(
                            child:
                                CircularProgressIndicator(color: Colors.white));
                      } else if (detailsSnapshot.hasError ||
                          !detailsSnapshot.hasData) {
                        content = const Icon(Icons.broken_image,
                            color: Colors.white38, size: 50);
                      } else {
                        final gameInfo = detailsSnapshot.data!;
                        content = GestureDetector(
                          onTap: () async {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    RepackDetailsPage(repack: gameInfo),
                              ),
                            );
                          },
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Hero(
                                  tag: gameInfo.url,
                                  child: CachedNetworkImage(
                                    imageUrl: gameInfo.screenshots.first,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) =>
                                        const Center(
                                      child: Icon(
                                        Icons.broken_image,
                                        color: Colors.white38,
                                        size: 50,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.center,
                                    colors: [
                                      Colors.black,
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 10,
                                left: 10,
                                right: 10,
                                child: Text(
                                  gameInfo.title.toUpperCase(),
                                  style: GoogleFonts.bebasNeue(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return Card(
                        color: Colors.grey.shade900,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                            padding: const EdgeInsets.all(12), child: content),
                      );
                    },
                  );
                },
              ),
            );
          }
          return const Center(
              child: Text(
            'NO DATA AVAILABLE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ));
        },
      ),
    );
  }
}
