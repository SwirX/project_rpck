import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '/api/fitgirl/fitgirl.dart';
import '/api/repack_base.dart';
import 'game_details.dart';
import 'settings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Fitgirl fitgirl = Fitgirl();
  List<GameIndex> _allGames = [];
  List<GameIndex> _filteredGames = [];
  final Map<String, Future<RepackInfo>> _gameDetails = {};
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadGames();
    _searchController.addListener(_filterGames);
  }

  Future<void> _loadGames() async {
    List<GameIndex> games = await fitgirl.indexDatabase();
    setState(() {
      _allGames = games;
      _filteredGames = games;
    });
  }

  void _filterGames() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredGames = _allGames
          .where((game) => game.title!.toLowerCase().contains(query))
          .toList();
    });
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search for a game...',
                hintStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.grey.shade900,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(Icons.search, color: Colors.white70),
              ),
            ),
          ),
          Expanded(
            child: _filteredGames.isEmpty
                ? const Center(
                    child: Text(
                      'No games found',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: _filteredGames.length,
                      itemBuilder: (context, index) {
                        final game = _filteredGames[index];
                        _gameDetails[game.title!] ??=
                            fitgirl.fetchGameInfo(game);

                        return FutureBuilder<RepackInfo>(
                          future: _gameDetails[game.title],
                          builder: (context, snapshot) {
                            Widget content;
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              content = const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white));
                            } else if (snapshot.hasError || !snapshot.hasData) {
                              content = const Icon(Icons.broken_image,
                                  color: Colors.white38, size: 50);
                            } else {
                              final gameInfo = snapshot.data!;
                              content = GestureDetector(
                                onTap: () async {
                                  final info =
                                      await fitgirl.fetchGameInfo(game);
                                  Navigator.push(
                                    // ignore: use_build_context_synchronously
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          RepackDetailsPage(repack: info),
                                    ),
                                  );
                                },
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
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
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.center,
                                          colors: [
                                            Colors.black.withOpacity(0.8),
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
                                  padding: const EdgeInsets.all(12),
                                  child: content),
                            );
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
