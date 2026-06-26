import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../services/deck_storage.dart';
import 'deck_page.dart';
import 'create_deck_page.dart';
import '../data/deck_data.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool showDecks = true;

  final List<String> folders = const [
    'JLPT',
    'School',
    'Work',
    'Favorites',
    'Archive',
    'Custom',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
          child: Column(
            children: [
              /// TOP BAR
              Row(
                children: [
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Library',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFEDEDED),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CreateDeckPage(),
                          ),
                        );

                        setState(() {});
                      },
                      icon: const Icon(Icons.add, color: Colors.black),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              /// SEARCH BAR (UI ONLY FOR NOW)
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEDED),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search, size: 22),
                    SizedBox(width: 10),
                    Text('Search'),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              /// TOGGLE
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFAFAFAF),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _toggleButton('Decks', showDecks, () {
                      setState(() => showDecks = true);
                    }),
                    _toggleButton('Folders', !showDecks, () {
                      setState(() => showDecks = false);
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              /// CONTENT
              Expanded(
                child: showDecks
                    ? ListView.builder(
                        itemCount: decks.length,
                        itemBuilder: (context, index) {
                          final deck = decks[index];

                          return GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DeckPage(deck: deck),
                                ),
                              );

                              setState(() {});
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC6C6C6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${deck.name}\nTerms: ${deck.termIds.length}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : GridView.builder(
                        itemCount: folders.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 28,
                          childAspectRatio: 1.25,
                        ),
                        itemBuilder: (context, index) {
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC6C6C6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              folders[index],
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleButton(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFD8D8D8) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}