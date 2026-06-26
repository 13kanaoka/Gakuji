import 'package:flutter/material.dart';

import '../data/deck_data.dart';
import '../data/folder_data.dart';
import '../widgets/gakuji_top_bar.dart';
import 'create_deck_page.dart';
import 'deck_page.dart';
import 'folder_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool showDecks = true;

  final TextEditingController searchController = TextEditingController();

  String searchQuery = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> openCreateDeckPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateDeckPage(),
      ),
    );

    if (!mounted) return;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final normalizedSearchQuery = searchQuery.trim().toLowerCase();

    final visibleDecks = decks.where((deck) {
      if (normalizedSearchQuery.isEmpty) return true;

      return deck.name.toLowerCase().contains(normalizedSearchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            GakujiTopBar(
              title: 'Library',
              titleStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: Colors.black,
              ),
              rightIcon: Icons.add,
              onRightTap: openCreateDeckPage,
            ),

            const SizedBox(height: 26),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 100),
                child: Column(
                  children: [
                    /// SEARCH BAR
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDEDED),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: searchController,
                        onChanged: (value) {
                          setState(() {
                            searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          icon: const Icon(Icons.search, size: 22),
                          hintText: showDecks ? 'Search decks' : 'Search',
                          border: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: const EdgeInsets.only(top: 8),
                          suffixIcon: searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      searchController.clear();
                                      searchQuery = '';
                                    });
                                  },
                                ),
                        ),
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
                          ? visibleDecks.isEmpty
                              ? const Center(
                                  child: Text('No decks found'),
                                )
                              : ListView.builder(
                                  itemCount: visibleDecks.length,
                                  itemBuilder: (context, index) {
                                    final deck = visibleDecks[index];

                                    return GestureDetector(
                                      onTap: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                DeckPage(deck: deck),
                                          ),
                                        );

                                        if (!mounted) return;

                                        setState(() {});
                                      },
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFC6C6C6),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${deck.name}\nTerms: ${deck.terms.length}',
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
                                final folder = folders[index];

                                return GestureDetector(
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            FolderPage(folder: folder),
                                      ),
                                    );

                                    if (!mounted) return;

                                    setState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFC6C6C6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          folder.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Decks: ${folder.deckIds.length}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
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
          ],
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