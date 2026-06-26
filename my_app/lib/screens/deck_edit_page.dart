import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../data/dictionary_helpers.dart';

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

  String searchQuery = "";

  /// 🔥 SWIPE STATE
  String? revealedTermId;
  double dragDistance = 0;

  /// ✋ MULTI SELECT STATE
  bool selectionMode = false;
  final Set<String> selectedTerms = {};

  /// 🔍 SEARCH FOCUS
  final FocusNode searchFocusNode = FocusNode();

  // -----------------------------
  // HELPERS
  // -----------------------------

  void closeRevealedTerm() {
    setState(() {
      revealedTermId = null;
    });
  }

  void removeTermFromDeck(Term term) {
    setState(() {
      widget.deck.termIds.remove(term.id);
      revealedTermId = null;
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
      widget.deck.termIds.removeWhere(
        (id) => selectedTerms.contains(id),
      );

      selectedTerms.clear();
      selectionMode = false;
      revealedTermId = null;
    });
  }

  // -----------------------------
  // SWIPE SYSTEM (UNCHANGED)
  // -----------------------------

  void handleSwipeEnd(Term term) {
    if (selectionMode) return; // 🚨 prevents conflicts

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

  @override
  void dispose() {
    searchFocusNode.dispose();
    super.dispose();
  }

  // -----------------------------
  // BUILD
  // -----------------------------

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;

    final List<Term> cards = getTermsFromDeck(deck.termIds);

    final visibleCards = cards.where((t) {
      final matchesSearch =
          searchQuery.isEmpty ||
          t.kanji.contains(searchQuery) ||
          t.reading.contains(searchQuery) ||
          t.meaning.toLowerCase().contains(searchQuery.toLowerCase());

      final matchesMarked = !showMarkedOnly || t.marked;

      return matchesSearch && matchesMarked;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,

      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          searchFocusNode.unfocus();
          closeRevealedTerm();

          setState(() {
            selectionMode = false;
            selectedTerms.clear();
          });
        },

        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
            child: Column(
              children: [
                // -----------------------------
                // TOP BAR
                // -----------------------------
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFEDEDED),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new),
                      ),
                    ),

                    const Expanded(
                      child: Center(
                        child: Text(
                          'Deck Edit',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),

                    /// 🗑 DELETE SELECTED
                    if (selectionMode)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: deleteSelected,
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),

                const SizedBox(height: 26),

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

      onHorizontalDragUpdate: (d) {
        if (!selectionMode) dragDistance += d.delta.dx;
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
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
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

                      Icon(
                        term.marked
                            ? Icons.star
                            : Icons.star_border,
                        color: term.marked
                            ? Colors.blue
                            : Colors.grey,
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

  Widget _toggleButton(
      String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label),
      ),
    );
  }
}