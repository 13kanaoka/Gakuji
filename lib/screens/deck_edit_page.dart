import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../models/term.dart';
import '../services/gakuji_user_data_store.dart';
import '../widgets/gakuji_faded_scroll.dart';
import '../widgets/gakuji_search_bar.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_term_row.dart';
import '../widgets/gakuji_top_bar.dart';
import 'reading_card_edit_page.dart';

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
  static const Color accentBlue = Color(0xFF4D7EF7);
  static const Color dividerGray = Color(0xFFE1E1E1);
  static const Color rowDividerGray = Color(0xFFC8C8C8);
  static const Color softTextGray = Color(0xFF8A8A8A);

  static const double _revealedOffset = 88;
  static const double _firstSwipeThreshold = 42;
  static const double _secondSwipeThreshold = 54;
  static const double _closeSwipeThreshold = 36;

  static const Duration _snapDuration = Duration(milliseconds: 220);
  static const Duration _deleteSlideDuration = Duration(milliseconds: 240);
  static const Duration _headerCollapseDuration = Duration(milliseconds: 400);

  bool showMenu = false;
  bool showStarredOnly = false;
  bool deckInfoCollapsed = false;

  String searchQuery = '';

  String? revealedTermId;
  String? draggingTermId;
  double dragDistance = 0;

  final Set<String> deletingTermIds = {};

  bool selectionMode = false;
  final Set<String> selectedTerms = {};

  final TextEditingController searchController = TextEditingController();
  final ScrollController cardsScrollController = ScrollController();

  bool get supportsReadingCardEdit {
    return widget.deck.type == DeckType.reading;
  }

  @override
  void initState() {
    super.initState();

    cardsScrollController.addListener(handleCardListScroll);
  }

  @override
  void dispose() {
    searchController.dispose();
    cardsScrollController.dispose();

    super.dispose();
  }

  void scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
  }

  void handleCardListScroll() {
    if (!cardsScrollController.hasClients) return;

    final shouldCollapse = cardsScrollController.offset > 14;

    if (deckInfoCollapsed == shouldCollapse) return;

    setState(() {
      deckInfoCollapsed = shouldCollapse;
    });
  }

  void closeMenu() {
    if (!showMenu) return;

    setState(() {
      showMenu = false;
    });
  }

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

  void setTermFilter({
    required bool starredOnly,
  }) {
    setState(() {
      showStarredOnly = starredOnly;
      showMenu = false;
      revealedTermId = null;
      draggingTermId = null;
      dragDistance = 0;
      selectionMode = false;
      selectedTerms.clear();
    });
  }

  void toggleStarred(Term term) {
    if (deletingTermIds.contains(term.id)) return;

    setState(() {
      showMenu = false;
      revealedTermId = null;
      draggingTermId = null;
      dragDistance = 0;
      term.marked = !term.marked;
    });

    scheduleUserDataSave();
  }

  void showReadingOnlyMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
          backgroundColor: Colors.black.withOpacity(0.86),
          content: const Text(
            'Reading card editing is only for reading decks right now',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      );
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

    scheduleUserDataSave();
  }

  void toggleSelect(Term term) {
    if (deletingTermIds.contains(term.id)) return;

    setState(() {
      showMenu = false;
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
    if (selectedTerms.isEmpty) return;

    setState(() {
      widget.deck.terms.removeWhere(
        (term) => selectedTerms.contains(term.id),
      );

      selectedTerms.clear();
      selectionMode = false;
      revealedTermId = null;
      draggingTermId = null;
      dragDistance = 0;
      showMenu = false;
    });

    scheduleUserDataSave();
  }

  Future<void> openCardSettings(Term term) async {
    if (deletingTermIds.contains(term.id)) return;

    if (selectionMode) {
      toggleSelect(term);
      return;
    }

    FocusScope.of(context).unfocus();
    closeMenu();
    closeRevealedTerm();

    if (!supportsReadingCardEdit) {
      showReadingOnlyMessage();
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReadingCardEditPage(
          deck: widget.deck,
          term: term,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {});
    scheduleUserDataSave();
  }

  void handleSwipeStart(Term term) {
    if (selectionMode || deletingTermIds.contains(term.id)) return;

    setState(() {
      showMenu = false;

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

  List<Term> visibleCardsFrom(List<Term> cards) {
    final normalizedSearch = searchQuery.trim().toLowerCase();

    return cards.where((term) {
      final matchesSearch = normalizedSearch.isEmpty ||
          term.kanji.toLowerCase().contains(normalizedSearch) ||
          term.reading.toLowerCase().contains(normalizedSearch) ||
          term.meaning.toLowerCase().contains(normalizedSearch) ||
          term.cardMeaning.toLowerCase().contains(normalizedSearch);

      final matchesStarred = !showStarredOnly || term.marked;

      return matchesSearch && matchesStarred;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;
    final cards = deck.terms;
    final visibleCards = visibleCardsFrom(cards);

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          FocusScope.of(context).unfocus();
          closeMenu();
          closeRevealedTerm();
          clearSelection();
        },
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  GakujiTopBar(
                    leftIcon: GakujiTopBar.backIcon,
                    leftIconSize: GakujiTopBar.backIconSize,
                    leftIconColor: GakujiColors.darkGray,
                    onLeftTap: () => Navigator.pop(context),
                    title: 'Card Settings',
                    titleStyle: GakujiText.medium.copyWith(
                      color: GakujiColors.darkGray,
                      fontWeight: FontWeight.w700,
                    ),
                    rightIcon: selectionMode
                        ? Icons.delete
                        : showStarredOnly
                            ? Icons.star
                            : Icons.star_border,
                    rightIconSize: selectionMode ? 28 : 31,
                    onRightTap: selectionMode
                        ? deleteSelected
                        : () {
                            setTermFilter(starredOnly: !showStarredOnly);
                          },
                    rightIconColor: selectionMode
                        ? Colors.red
                        : showStarredOnly
                            ? accentBlue
                            : rowDividerGray,
                    showOptionsButton: false,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _collapsingDeckHeader(cards.length),
                          AnimatedContainer(
                            duration: _headerCollapseDuration,
                            curve: Curves.easeOutCubic,
                            height: deckInfoCollapsed ? 8 : 18,
                          ),
                          _searchBar(),
                          const SizedBox(height: 12),
                          Expanded(
                            child: visibleCards.isEmpty
                                ? _emptyState()
                                : _termList(visibleCards),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _collapsingDeckHeader(int totalCards) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: deckInfoCollapsed ? 0 : 1,
        end: deckInfoCollapsed ? 0 : 1,
      ),
      duration: _headerCollapseDuration,
      curve: Curves.easeOutCubic,
      child: _deckHeader(totalCards),
      builder: (context, value, child) {
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: value,
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.92 + (0.08 * value),
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _deckHeader(int totalCards) {
    final countLabel = totalCards == 1 ? '1 card' : '$totalCards cards';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.deck.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.large.copyWith(
              color: GakujiColors.darkGray,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            countLabel,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              fontSize: 16,
              height: 1,
              color: softTextGray,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return GakujiSearchBar(
      controller: searchController,
      hintText: 'Search cards',
      showClearButton: searchQuery.isNotEmpty,
      onChanged: (value) {
        setState(() {
          searchQuery = value;
        });
      },
      onClear: () {
        setState(() {
          searchController.clear();
          searchQuery = '';
        });
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Text(
        showStarredOnly ? 'No starred cards yet' : 'No cards yet',
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _termList(List<Term> visibleCards) {
    return GakujiFadedScroll(
      child: ListView.separated(
        controller: cardsScrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: visibleCards.length,
        separatorBuilder: (context, index) {
          return const Divider(
            height: 1,
            thickness: 1,
            color: GakujiTermRow.dividerColor,
          );
        },
        itemBuilder: (context, index) {
          final term = visibleCards[index];
          final isSelected = selectedTerms.contains(term.id);

          return _termRow(term, isSelected);
        },
      ),
    );
  }

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
          openCardSettings(term);
        },
        onHorizontalDragStart: (_) => handleSwipeStart(term),
        onHorizontalDragUpdate: handleSwipeUpdate,
        onHorizontalDragEnd: (_) => handleSwipeEnd(term),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0),
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
                child: GakujiTermRow(
                  term: term,
                  titleText: term.kanjiBracketText.isNotEmpty
                      ? term.kanjiBracketText
                      : term.kanji,
                  readingText: term.reading,
                  isSelected: isSelected,
                  showChevron: false,
                  leading: selectionMode
                      ? Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: isSelected ? Colors.red : softTextGray,
                          size: 24,
                        )
                      : null,
                  trailing: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (selectionMode) {
                        toggleSelect(term);
                        return;
                      }

                      toggleStarred(term);
                    },
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: Icon(
                          term.marked ? Icons.star : Icons.star_border,
                          color: term.marked ? accentBlue : rowDividerGray,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _menuOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: closeMenu,
            child: Container(
              color: Colors.transparent,
            ),
          ),
          Positioned(
            top: 58,
            right: 22,
            child: _deckEditMenuCard(),
          ),
        ],
      ),
    );
  }

  Widget _deckEditMenuCard() {
    return Container(
      width: 234,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 0,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _menuItem(
            icon: showStarredOnly ? Icons.star_border : Icons.star,
            label: showStarredOnly ? 'All terms' : 'Starred terms',
            iconColor: showStarredOnly ? Colors.grey : accentBlue,
            onTap: () {
              setTermFilter(starredOnly: !showStarredOnly);
            },
          ),
        ],
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.black,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Center(
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}