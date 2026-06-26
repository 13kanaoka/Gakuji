import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../models/term.dart';
import '../widgets/gakuji_top_bar.dart';

class DeckEditPage extends StatefulWidget {
  final Deck deck;

  const DeckEditPage({
    super.key,
    required this.deck,
  });

  @override
  State<DeckEditPage> createState() => _DeckEditPageState();
}

class _DeckEditPageState extends State<DeckEditPage> {
  bool showMarkedOnly = false;

  String searchQuery = '';

  /// Swipe state
  String? revealedTermId;
  double dragDistance = 0;

  /// Multi-select state
  bool selectionMode = false;
  final Set<String> selectedTerms = {};

  /// Search focus
  final FocusNode searchFocusNode = FocusNode();

  @override
  void dispose() {
    searchFocusNode.dispose();
    super.dispose();
  }

  // -----------------------------
  // HELPERS
  // -----------------------------

  void closeRevealedTerm() {
    setState(() {
      revealedTermId = null;
    });
  }

  void clearSelection() {
    setState(() {
      selectionMode = false;
      selectedTerms.clear();
    });
  }

  void removeTermFromDeck(Term term) {
    setState(() {
      widget.deck.terms.removeWhere((deckTerm) => deckTerm.id == term.id);
      revealedTermId = null;
      selectedTerms.remove(term.id);

      if (selectedTerms.isEmpty) {
        selectionMode = false;
      }
    });
  }

  void toggleSelect(Term term) {
    setState(() {
      selectionMode = true;

      if (selectedTerms.contains(term.id)) {
        selectedTerms.remove(term.id);

        if (selectedTerms.isEmpty) {
          selectionMode = false;
        }
      } else {
        selectedTerms.add(term.id);
      }
    });
  }

  void deleteSelected() {
    setState(() {
      widget.deck.terms.removeWhere(
        (term) => selectedTerms.contains(term.id),
      );

      selectedTerms.clear();
      selectionMode = false;
      revealedTermId = null;
    });
  }

  // -----------------------------
  // SWIPE SYSTEM
  // -----------------------------

  void handleSwipeEnd(Term term) {
    if (selectionMode) return;

    const swipeThreshold = 40.0;
    final isRevealed = revealedTermId == term.id;

    if (dragDistance < -swipeThreshold) {
      if (isRevealed) {
        removeTermFromDeck(term);
      } else {
        setState(() {
          revealedTermId = term.id;
        });
      }
    } else if (dragDistance > swipeThreshold) {
      if (isRevealed) {
        setState(() {
          revealedTermId = null;
        });
      }
    }

    dragDistance = 0;
  }

  // -----------------------------
  // BUILD
  // -----------------------------

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;

    final List<Term> cards = deck.terms;

    final visibleCards = cards.where((term) {
      final normalizedSearch = searchQuery.toLowerCase();

      final matchesSearch = searchQuery.isEmpty ||
          term.kanji.contains(searchQuery) ||
          term.reading.contains(searchQuery) ||
          term.meaning.toLowerCase().contains(normalizedSearch);

      final matchesMarked = !showMarkedOnly || term.marked;

      return matchesSearch && matchesMarked;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          searchFocusNode.unfocus();
          closeRevealedTerm();
          clearSelection();
        },
        child: SafeArea(
          child: Column(
            children: [
              GakujiTopBar(
                leftIcon: Icons.arrow_back_ios_new,
                onLeftTap: () => Navigator.pop(context),
                title: 'Deck Edit',
                titleStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: Colors.black,
                ),
                rightIcon: selectionMode ? Icons.delete : null,
                onRightTap: selectionMode ? deleteSelected : null,
                rightIconColor: Colors.red,
              ),

              const SizedBox(height: 26),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                  child: Column(
                    children: [
                      // -----------------------------
                      // SEARCH
                      // -----------------------------
                      Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDEDED),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          focusNode: searchFocusNode,
                          onChanged: (value) {
                            setState(() {
                              searchQuery = value;
                            });
                          },
                          decoration: const InputDecoration(
                            hintText: 'Search',
                            border: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.only(top: 10),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // -----------------------------
                      // TOGGLE
                      // -----------------------------
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFAFAFAF),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _toggleButton('All', !showMarkedOnly, () {
                                setState(() => showMarkedOnly = false);
                              }),
                              _toggleButton('Marked', showMarkedOnly, () {
                                setState(() => showMarkedOnly = true);
                              }),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // -----------------------------
                      // LIST
                      // -----------------------------
                      Expanded(
                        child: visibleCards.isEmpty
                            ? const Center(child: Text('No cards yet'))
                            : ListView.builder(
                                itemCount: visibleCards.length,
                                itemBuilder: (context, index) {
                                  final term = visibleCards[index];
                                  final isSelected =
                                      selectedTerms.contains(term.id);

                                  return _termRow(term, isSelected);
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

  // -----------------------------
  // TERM ROW
  // -----------------------------

  Widget _termRow(Term term, bool isSelected) {
    final isRevealed = revealedTermId == term.id;

    return GestureDetector(
      onLongPress: () => toggleSelect(term),
      onTap: () {
        if (selectionMode) {
          toggleSelect(term);
        } else {
          searchFocusNode.unfocus();
          closeRevealedTerm();
        }
      },
      onHorizontalDragStart: (_) {
        if (!selectionMode) dragDistance = 0;
      },
      onHorizontalDragUpdate: (details) {
        if (!selectionMode) dragDistance += details.delta.dx;
      },
      onHorizontalDragEnd: (_) {
        if (!selectionMode) handleSwipeEnd(term);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
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
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.blue.withOpacity(0.2)
                        : const Color(0xFFEDEDED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              term.kanji,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            Text(term.reading),
                            Text(term.meaning),
                          ],
                        ),
                      ),
                      Icon(
                        term.marked ? Icons.star : Icons.star_border,
                        color: term.marked ? Colors.blue : Colors.grey,
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

  // -----------------------------
  // TOGGLE BUTTON
  // -----------------------------

  Widget _toggleButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label),
      ),
    );
  }
}