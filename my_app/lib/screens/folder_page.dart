import 'package:flutter/material.dart';

import '../data/deck_data.dart';
import '../models/deck.dart';
import '../models/folder.dart';
import '../widgets/gakuji_top_bar.dart';
import 'deck_page.dart';

class FolderPage extends StatefulWidget {
  final Folder folder;

  const FolderPage({
    super.key,
    required this.folder,
  });

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  final TextEditingController searchController = TextEditingController();

  String searchQuery = '';

  /// Swipe state
  String? revealedDeckId;
  double dragDistance = 0;

  /// Multi-select state
  bool selectionMode = false;
  final Set<String> selectedDeckIds = {};

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Deck> get folderDecks {
    return decks.where((deck) {
      return widget.folder.deckIds.contains(deck.id);
    }).toList();
  }

  void closeRevealedDeck() {
    setState(() {
      revealedDeckId = null;
    });
  }

  void clearSelection() {
    setState(() {
      selectionMode = false;
      selectedDeckIds.clear();
    });
  }

  void removeDeckFromFolder(Deck deck) {
    setState(() {
      widget.folder.deckIds.removeWhere((deckId) => deckId == deck.id);
      revealedDeckId = null;
      selectedDeckIds.remove(deck.id);

      if (selectedDeckIds.isEmpty) {
        selectionMode = false;
      }
    });
  }

  void toggleSelect(Deck deck) {
    setState(() {
      selectionMode = true;

      if (selectedDeckIds.contains(deck.id)) {
        selectedDeckIds.remove(deck.id);

        if (selectedDeckIds.isEmpty) {
          selectionMode = false;
        }
      } else {
        selectedDeckIds.add(deck.id);
      }
    });
  }

  void deleteSelected() {
    setState(() {
      widget.folder.deckIds.removeWhere(
        (deckId) => selectedDeckIds.contains(deckId),
      );

      selectedDeckIds.clear();
      selectionMode = false;
      revealedDeckId = null;
    });
  }

  void handleSwipeEnd(Deck deck) {
    if (selectionMode) return;

    const swipeThreshold = 40.0;
    final isRevealed = revealedDeckId == deck.id;

    if (dragDistance < -swipeThreshold) {
      if (isRevealed) {
        removeDeckFromFolder(deck);
      } else {
        setState(() {
          revealedDeckId = deck.id;
        });
      }
    } else if (dragDistance > swipeThreshold) {
      if (isRevealed) {
        setState(() {
          revealedDeckId = null;
        });
      }
    }

    dragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    final visibleDecks = folderDecks.where((deck) {
      return searchQuery.isEmpty ||
          deck.name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          closeRevealedDeck();
          clearSelection();
        },
        child: SafeArea(
          child: Column(
            children: [
              GakujiTopBar(
                leftIcon: Icons.arrow_back_ios_new,
                onLeftTap: () => Navigator.pop(context),
                title: widget.folder.name,
                titleStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: Colors.black,
                ),
                rightIcon: selectionMode ? Icons.delete : null,
                onRightTap: selectionMode ? deleteSelected : null,
                rightIconColor: Colors.red,
              ),

              const SizedBox(height: 28),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
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
                            icon: const Icon(
                              Icons.search,
                              size: 22,
                              color: Colors.black,
                            ),
                            hintText: 'Search decks',
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

                      const SizedBox(height: 64),

                      /// DECK LIST
                      Expanded(
                        child: visibleDecks.isEmpty
                            ? const Center(
                                child: Text('No decks in this folder yet'),
                              )
                            : ListView.builder(
                                itemCount: visibleDecks.length,
                                itemBuilder: (context, index) {
                                  final deck = visibleDecks[index];
                                  final isSelected =
                                      selectedDeckIds.contains(deck.id);

                                  return _deckCard(deck, isSelected);
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
      ),
    );
  }

  Widget _deckCard(Deck deck, bool isSelected) {
    final isRevealed = revealedDeckId == deck.id;

    return GestureDetector(
      onLongPress: () => toggleSelect(deck),
      onTap: () async {
        if (selectionMode) {
          toggleSelect(deck);
        } else {
          closeRevealedDeck();

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DeckPage(deck: deck),
            ),
          );

          if (!mounted) return;

          setState(() {});
        }
      },
      onHorizontalDragStart: (_) {
        if (!selectionMode) dragDistance = 0;
      },
      onHorizontalDragUpdate: (details) {
        if (!selectionMode) dragDistance += details.delta.dx;
      },
      onHorizontalDragEnd: (_) {
        if (!selectionMode) handleSwipeEnd(deck);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              /// DELETE BACKGROUND
              Positioned.fill(
                child: Container(
                  color: Colors.redAccent,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
              ),

              /// FRONT CARD
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                transform: Matrix4.translationValues(
                  isRevealed ? -82 : 0,
                  0,
                  0,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.blue.withOpacity(0.2)
                      : const Color(0xFFC6C6C6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    /// LEFT SIDE
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deck.name,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          Text(
                            'Items: ${deck.terms.length}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    /// RIGHT SIDE
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'New: ',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '#',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Review: ',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '#',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}