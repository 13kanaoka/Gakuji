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
  static const double _revealedOffset = 88;
  static const double _firstSwipeThreshold = 42;
  static const double _secondSwipeThreshold = 54;
  static const double _closeSwipeThreshold = 36;

  static const Duration _snapDuration = Duration(milliseconds: 220);
  static const Duration _deleteSlideDuration = Duration(milliseconds: 240);

  bool showMarkedOnly = false;

  String searchQuery = '';

  /// Swipe state
  String? revealedTermId;
  String? draggingTermId;
  double dragDistance = 0;

  final Set<String> deletingTermIds = {};

  /// Multi-select state
  bool selectionMode = false;
  final Set<String> selectedTerms = {};

  /// Search
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  @override
  void dispose() {
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  // -----------------------------
  // HELPERS
  // -----------------------------

  void closeRevealedTerm() {
    if (revealedTermId == null && draggingTermId == null) return;

    setState(() {
      revealedTermId = null;
      draggingTermId = null;
      dragDistance = 0;
    });
  }

  void clearSelection() {
    if (!selectionMode && selectedTerms.isEmpty) return;

    setState(() {
      selectionMode = false;
      selectedTerms.clear();
    });
  }

  Future<void> removeTermFromDeck(Term term) async {
    if (deletingTermIds.contains(term.id)) return;

    setState(() {
      deletingTermIds.add(term.id);
      revealedTermId = null;
      draggingTermId = null;
      dragDistance = 0;
      selectedTerms.remove(term.id);

      if (selectedTerms.isEmpty) {
        selectionMode = false;
      }
    });

    await Future.delayed(_deleteSlideDuration);

    if (!mounted) return;

    setState(() {
      widget.deck.terms.removeWhere((deckTerm) => deckTerm.id == term.id);
      deletingTermIds.remove(term.id);
    });
  }

  void toggleSelect(Term term) {
    if (deletingTermIds.contains(term.id)) return;

    setState(() {
      revealedTermId = null;
      draggingTermId = null;
      dragDistance = 0;
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
      draggingTermId = null;
      dragDistance = 0;
    });
  }

  // -----------------------------
  // SWIPE SYSTEM
  // -----------------------------

  void handleSwipeStart(Term term) {
    if (selectionMode || deletingTermIds.contains(term.id)) return;

    setState(() {
      if (revealedTermId != null && revealedTermId != term.id) {
        revealedTermId = null;
      }

      draggingTermId = term.id;
      dragDistance = 0;
    });
  }

  void handleSwipeUpdate(DragUpdateDetails details) {
    if (selectionMode || draggingTermId == null) return;

    setState(() {
      dragDistance += details.delta.dx;
    });
  }

  void handleSwipeEnd(Term term) {
    if (selectionMode || draggingTermId != term.id) return;

    final wasRevealed = revealedTermId == term.id;

    if (wasRevealed && dragDistance < -_secondSwipeThreshold) {
      removeTermFromDeck(term);
      return;
    }

    if (!wasRevealed && dragDistance < -_firstSwipeThreshold) {
      setState(() {
        revealedTermId = term.id;
        draggingTermId = null;
        dragDistance = 0;
      });
      return;
    }

    if (wasRevealed && dragDistance > _closeSwipeThreshold) {
      setState(() {
        revealedTermId = null;
        draggingTermId = null;
        dragDistance = 0;
      });
      return;
    }

    setState(() {
      draggingTermId = null;
      dragDistance = 0;
    });
  }

  double rowOffsetFor(Term term) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (deletingTermIds.contains(term.id)) {
      return -screenWidth - 120;
    }

    if (selectionMode) return 0;

    final isRevealed = revealedTermId == term.id;
    final isDragging = draggingTermId == term.id;

    final baseOffset = isRevealed ? -_revealedOffset : 0.0;

    if (!isDragging) return baseOffset;

    final rawOffset = baseOffset + dragDistance;

    if (isRevealed) {
      return rawOffset.clamp(-220.0, 0.0).toDouble();
    }

    return rawOffset.clamp(-_revealedOffset, 24.0).toDouble();
  }

  Duration rowAnimationDurationFor(Term term) {
    if (draggingTermId == term.id) {
      return Duration.zero;
    }

    if (deletingTermIds.contains(term.id)) {
      return _deleteSlideDuration;
    }

    return _snapDuration;
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
                      _searchBar(),

                      const SizedBox(height: 18),

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
  // SEARCH BAR
  // -----------------------------

  Widget _searchBar() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: searchController,
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
          if (searchQuery.isNotEmpty)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                setState(() {
                  searchController.clear();
                  searchQuery = '';
                });
              },
            ),
        ],
      ),
    );
  }

  // -----------------------------
  // TERM ROW
  // -----------------------------

  Widget _termRow(Term term, bool isSelected) {
    final offset = rowOffsetFor(term);
    final duration = rowAnimationDurationFor(term);
    final isDeleting = deletingTermIds.contains(term.id);

    return AnimatedOpacity(
      key: ValueKey(term.id),
      opacity: isDeleting ? 0 : 1,
      duration: _deleteSlideDuration,
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        onLongPress: () => toggleSelect(term),
        onTap: () {
          if (deletingTermIds.contains(term.id)) return;

          if (selectionMode) {
            toggleSelect(term);
          } else {
            searchFocusNode.unfocus();
            closeRevealedTerm();
          }
        },
        onHorizontalDragStart: (_) => handleSwipeStart(term),
        onHorizontalDragUpdate: handleSwipeUpdate,
        onHorizontalDragEnd: (_) => handleSwipeEnd(term),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                if (!selectionMode)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => removeTermFromDeck(term),
                      child: Container(
                        color: Colors.redAccent,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(
                          Icons.delete,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(offset, 0, 0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDEDED),
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(
                              color: Colors.red,
                              width: 2,
                            )
                          : null,
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