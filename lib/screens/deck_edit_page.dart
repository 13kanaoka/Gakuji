import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../widgets/gakuji_page_route.dart';

import '../data/deck_data.dart';
import '../data/review_card_data.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../services/deck_storage.dart';
import '../services/gakuji_cloud_sync_service.dart';
import '../services/gakuji_user_data_store.dart';
import '../services/gakuji_user_repository.dart';
import '../services/term_favorite_service.dart';
import '../widgets/gakuji_search_bar.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_term_row.dart';
import '../widgets/gakuji_top_bar.dart';
import 'reading_card_edit_page.dart';

enum _HybridCardEditView {
  reading,
  writing,
}

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
  static const Color softTextGray = Color(0xFF8A8A8A);

  static const String recentDeckColorsPreferenceKey = 'recent_deck_colors';
  static const int maxRecentDeckColors = 6;

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
  _HybridCardEditView hybridCardEditView = _HybridCardEditView.reading;

  String searchQuery = '';

  String? revealedTermId;
  String? draggingTermId;
  double dragDistance = 0;

  final Set<String> deletingTermIds = {};

  bool selectionMode = false;
  final Set<String> selectedTerms = {};

  final TextEditingController searchController = TextEditingController();
  final ScrollController cardsScrollController = ScrollController();

  List<Color> recentDeckColors = [];

  Color get deckColor {
    final storedColor = widget.deck.colorValue;

    if (storedColor != null) {
      return Color(storedColor);
    }

    switch (widget.deck.type) {
      case DeckType.reading:
        return GakujiColors.reading;
      case DeckType.writing:
        return GakujiColors.writing;
      case DeckType.hybrid:
        return GakujiColors.hybrid;
    }
  }

  Color readableTextColor(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF3F3F3F);
  }

  bool get supportsReadingCardEdit {
    return widget.deck.type == DeckType.reading;
  }

  bool get isHybridDeck {
    return widget.deck.type == DeckType.hybrid;
  }

  bool get viewingHybridReadingCards {
    return hybridCardEditView == _HybridCardEditView.reading;
  }

  Color get activeHybridCardEditColor {
    return deckColor;
  }

  @override
  void initState() {
    super.initState();

    cardsScrollController.addListener(handleCardListScroll);
    loadRecentDeckColors();
  }

  @override
  void dispose() {
    searchController.dispose();
    cardsScrollController.dispose();

    super.dispose();
  }

  Future<void> loadRecentDeckColors() async {
    final stored = await GakujiUserRepository.loadPreference(
      recentDeckColorsPreferenceKey,
    );

    if (!mounted || stored == null || stored.trim().isEmpty) return;

    final loadedColors = stored
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .map((value) => Color(value))
        .take(maxRecentDeckColors)
        .toList();

    if (loadedColors.isEmpty) return;

    setState(() {
      recentDeckColors = loadedColors;
    });
  }

  Future<void> saveRecentDeckColor(Color color) async {
    final colorValue = color.toARGB32();

    final updatedColors = <Color>[
      color,
      ...recentDeckColors.where(
        (recentColor) => recentColor.toARGB32() != colorValue,
      ),
    ].take(maxRecentDeckColors).toList();

    if (mounted) {
      setState(() {
        recentDeckColors = updatedColors;
      });
    }

    await GakujiUserRepository.savePreference(
      key: recentDeckColorsPreferenceKey,
      value: updatedColors
          .map((recentColor) => recentColor.toARGB32().toString())
          .join(','),
    );
    GakujiCloudSyncService.schedulePush();
  }

  Future<void> openDeckColorPicker() async {
    final pickedColor = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var workingColor = HSVColor.fromColor(deckColor);
        var sheetDismissDragOffset = 0.0;
        var isSheetDismissDragging = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final previewColor = workingColor.toColor();

            void startSheetDismissDrag(DragStartDetails details) {
              setSheetState(() {
                isSheetDismissDragging = true;
              });
            }

            void updateSheetDismissDrag(DragUpdateDetails details) {
              setSheetState(() {
                isSheetDismissDragging = true;
                sheetDismissDragOffset += details.delta.dy;
                if (sheetDismissDragOffset < 0) {
                  sheetDismissDragOffset = 0;
                }
              });
            }

            void endSheetDismissDrag(DragEndDetails details) {
              final velocity = details.primaryVelocity ?? 0;
              final shouldDismiss =
                  sheetDismissDragOffset > 96 || velocity > 850;

              if (shouldDismiss) {
                Navigator.of(sheetContext).pop();
                return;
              }

              setSheetState(() {
                isSheetDismissDragging = false;
                sheetDismissDragOffset = 0;
              });
            }

            void cancelSheetDismissDrag() {
              setSheetState(() {
                isSheetDismissDragging = false;
                sheetDismissDragOffset = 0;
              });
            }

            final bottomSafePadding =
                MediaQuery.viewPaddingOf(sheetContext).bottom;

            return AnimatedContainer(
                duration: isSheetDismissDragging
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(
                  0,
                  sheetDismissDragOffset,
                  0,
                ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
                ),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    18,
                    24,
                    24 + bottomSafePadding,
                  ),
                  decoration: BoxDecoration(
                    color: GakujiColors.warmCard,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                    border: Border.all(
                      color: GakujiColors.warmDivider,
                      width: 1.2,
                    ),
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onVerticalDragStart: startSheetDismissDrag,
                          onVerticalDragUpdate: updateSheetDismissDrag,
                          onVerticalDragEnd: endSheetDismissDrag,
                          onVerticalDragCancel: cancelSheetDismissDrag,
                          child: Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                height: 23,
                                child: Center(
                                  child: Container(
                                    width: 44,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: GakujiColors.softBorder,
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Choose Deck Color',
                                      textScaler: TextScaler.noScaling,
                                      style: GakujiText.medium.copyWith(
                                        color: GakujiColors.darkGray,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: previewColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: GakujiColors.softBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        _DeckColorWheel(
                          hsvColor: workingColor,
                          onChanged: (value) {
                            setSheetState(() {
                              workingColor = value;
                            });
                          },
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Text(
                              'Brightness',
                              textScaler: TextScaler.noScaling,
                              style: GakujiText.xSmall.copyWith(
                                color: GakujiColors.darkGray,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: previewColor,
                                  inactiveTrackColor: GakujiColors.warmDivider,
                                  thumbColor: previewColor,
                                  overlayColor:
                                      previewColor.withValues(alpha: 0.10),
                                  trackHeight: 4,
                                ),
                                child: Slider(
                                  value: workingColor.value,
                                  min: 0,
                                  max: 1,
                                  onChanged: (value) {
                                    setSheetState(() {
                                      workingColor =
                                          workingColor.withValue(value);
                                    });
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (recentDeckColors.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Recent Colors',
                              textScaler: TextScaler.noScaling,
                              style: GakujiText.xSmall.copyWith(
                                color: GakujiColors.darkGray,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: recentDeckColors.map((color) {
                                final isSelected =
                                    color.toARGB32() == previewColor.toARGB32();

                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    setSheetState(() {
                                      workingColor = HSVColor.fromColor(color);
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 160),
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? GakujiColors.darkGray
                                            : GakujiColors.softBorder,
                                        width: isSelected ? 2.5 : 1.5,
                                      ),
                                    ),
                                    child: isSelected
                                        ? Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                            color: readableTextColor(color),
                                          )
                                        : null,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(sheetContext),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: GakujiColors.softBorder,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    'Cancel',
                                    textScaler: TextScaler.noScaling,
                                    style: GakujiText.xSmall.copyWith(
                                      color: GakujiColors.darkGray,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: FilledButton(
                                  onPressed: () {
                                    Navigator.pop(sheetContext, previewColor);
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: previewColor,
                                    foregroundColor:
                                        readableTextColor(previewColor),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    'Use Color',
                                    textScaler: TextScaler.noScaling,
                                    style: GakujiText.xSmall.copyWith(
                                      color: readableTextColor(previewColor),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || pickedColor == null) return;

    setState(() {
      widget.deck.colorValue = pickedColor.toARGB32();
    });

    GakujiUserDataStore.scheduleSave();
    await saveRecentDeckColor(pickedColor);
  }

  Widget _topBarDeckActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: openDeckColorPicker,
          child: SizedBox(
            width: GakujiTopBar.buttonSize,
            height: GakujiTopBar.buttonSize,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: deckColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: GakujiColors.softBorder,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setTermFilter(starredOnly: !showStarredOnly);
          },
          child: SizedBox(
            width: GakujiTopBar.buttonSize,
            height: GakujiTopBar.buttonSize,
            child: Center(
              child: Icon(
                showStarredOnly
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                size: GakujiTopBar.iconSize,
                color: GakujiColors.reading,
              ),
            ),
          ),
        ),
      ],
    );
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

  void setHybridCardEditView(_HybridCardEditView view) {
    if (!isHybridDeck || hybridCardEditView == view) return;
    if (deletingTermIds.isNotEmpty) return;

    setState(() {
      hybridCardEditView = view;
      showMenu = false;
      revealedTermId = null;
      draggingTermId = null;
      dragDistance = 0;
      deckInfoCollapsed = false;
      selectionMode = false;
      selectedTerms.clear();
    });

    if (cardsScrollController.hasClients) {
      cardsScrollController.jumpTo(0);
    }
  }

  void toggleStarred(Term term) {
    if (deletingTermIds.contains(term.id)) return;

    setState(() {
      showMenu = false;
      revealedTermId = null;
      draggingTermId = null;
      dragDistance = 0;
      TermFavoriteService.toggle(term);
    });

    GakujiUserDataStore.scheduleSave();
  }

  void showReadingOnlyMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
          backgroundColor: Colors.black.withValues(alpha: 0.86),
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

  void syncEditedDeckToDeckList() {
    final deckIndex = decks.indexWhere((deck) => deck.id == widget.deck.id);

    if (deckIndex == -1 || identical(decks[deckIndex], widget.deck)) return;

    final currentDeck = decks[deckIndex];
    decks[deckIndex] = currentDeck.copyWith(
      colorValue: widget.deck.colorValue,
      terms: widget.deck.terms,
      hybridCardModes: widget.deck.hybridCardModes,
    );
  }

  Future<void> syncDeckAfterCardChanges() async {
    syncEditedDeckToDeckList();
    GakujiUserDataStore.scheduleSave();

    final reviewEnabled = await DeckStorage.loadReviewEnabled(widget.deck.id);

    if (!reviewEnabled) return;

    await createReviewCardsForDeck(widget.deck);
  }

  void removeWholeTermFromDeck(Term term) {
    widget.deck.removeHybridCardMode(term);
    widget.deck.terms.removeWhere((deckTerm) => deckTerm.id == term.id);
  }

  void removeCardFromCurrentView(
    Term term,
    _HybridCardEditView cardView,
  ) {
    if (!isHybridDeck) {
      removeWholeTermFromDeck(term);
      return;
    }

    final mode = widget.deck.cardModeFor(term);

    switch (cardView) {
      case _HybridCardEditView.reading:
        switch (mode) {
          case HybridCardMode.both:
            widget.deck.setHybridCardMode(term, HybridCardMode.writing);
            break;
          case HybridCardMode.reading:
            removeWholeTermFromDeck(term);
            break;
          case HybridCardMode.writing:
            break;
        }
        break;
      case _HybridCardEditView.writing:
        switch (mode) {
          case HybridCardMode.both:
            widget.deck.setHybridCardMode(term, HybridCardMode.reading);
            break;
          case HybridCardMode.writing:
            removeWholeTermFromDeck(term);
            break;
          case HybridCardMode.reading:
            break;
        }
        break;
    }
  }

  Future<void> removeTermFromDeck(Term term) async {
    if (deletingTermIds.contains(term.id)) return;

    final cardView = hybridCardEditView;

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
      removeCardFromCurrentView(term, cardView);
      deletingTermIds.remove(term.id);
    });

    await syncDeckAfterCardChanges();
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
    final selectedTermIds = Set<String>.from(selectedTerms);
    final cardView = hybridCardEditView;

    setState(() {
      for (final term in widget.deck.terms.toList()) {
        if (selectedTermIds.contains(term.id)) {
          removeCardFromCurrentView(term, cardView);
        }
      }

      selectedTerms.clear();
      selectionMode = false;
      revealedTermId = null;
      draggingTermId = null;
      dragDistance = 0;
      showMenu = false;
    });

    unawaited(syncDeckAfterCardChanges());
  }

  void openCardSettings(Term term) {
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

    Navigator.push(
      context,
      GakujiPageRoute(
        builder: (context) => ReadingCardEditPage(
          deck: widget.deck,
          term: term,
        ),
      ),
    );
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
      final matchesHybridCardView = !isHybridDeck ||
          (viewingHybridReadingCards
              ? widget.deck.readingEnabledFor(term)
              : widget.deck.writingEnabledFor(term));
      final matchesSearch = normalizedSearch.isEmpty ||
          term.kanji.toLowerCase().contains(normalizedSearch) ||
          term.reading.toLowerCase().contains(normalizedSearch) ||
          term.meaning.toLowerCase().contains(normalizedSearch) ||
          term.cardMeaning.toLowerCase().contains(normalizedSearch);

      final matchesStarred = !showStarredOnly || term.marked;

      return matchesHybridCardView && matchesSearch && matchesStarred;
    }).toList();
  }

  int cardCountForCurrentView(List<Term> cards) {
    if (!isHybridDeck) return cards.length;

    return cards.where((term) {
      return viewingHybridReadingCards
          ? widget.deck.readingEnabledFor(term)
          : widget.deck.writingEnabledFor(term);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;
    final cards = deck.terms;
    final visibleCards = visibleCardsFrom(cards);
    final totalCards = cardCountForCurrentView(cards);

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
                    title: 'Edit Deck',
                    titleStyle: GakujiText.pageTitle.copyWith(
                      color: GakujiColors.darkGray,
                    ),
                    rightIcon: selectionMode ? Icons.delete : null,
                    rightIconSize: GakujiTopBar.iconSize,
                    onRightTap: selectionMode ? deleteSelected : null,
                    rightIconColor: Colors.red,
                    rightWidget:
                        selectionMode ? null : _topBarDeckActions(),
                    showOptionsButton: false,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _collapsingDeckHeader(totalCards),
                          AnimatedContainer(
                            duration: _headerCollapseDuration,
                            curve: Curves.easeOutCubic,
                            height: deckInfoCollapsed ? 8 : 18,
                          ),
                          _searchBar(),
                          if (isHybridDeck) ...[
                            const SizedBox(height: 12),
                            _HybridCardEditSwitcher(
                              selectedView: hybridCardEditView,
                              activeColor: activeHybridCardEditColor,
                              onReadingTap: () => setHybridCardEditView(
                                _HybridCardEditView.reading,
                              ),
                              onWritingTap: () => setHybridCardEditView(
                                _HybridCardEditView.writing,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ] else ...[
                            const SizedBox(height: 20),
                          ],
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
            style: GakujiText.pageTitle.copyWith(
              color: GakujiColors.darkGray,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            countLabel,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.deckMeta.copyWith(
              color: GakujiColors.mediumGray,
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
    final emptyCardType = viewingHybridReadingCards ? 'reading' : 'writing';
    final emptyMessage = isHybridDeck
        ? (showStarredOnly
            ? 'No starred $emptyCardType cards yet'
            : 'No $emptyCardType cards yet')
        : (showStarredOnly ? 'No starred cards yet' : 'No cards yet');

    return Center(
      child: Text(
        emptyMessage,
        textScaler: TextScaler.noScaling,
        style: GakujiText.body.copyWith(color: Colors.grey),
      ),
    );
  }

  Widget _termList(List<Term> visibleCards) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00000000),
            Colors.black,
            Colors.black,
            Color(0x00000000),
          ],
          stops: [
            0.0,
            0.035,
            0.94,
            1.0,
          ],
        ).createShader(bounds);
      },
      child: ListView.separated(
        controller: cardsScrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(
          top: 14,
          bottom: 140,
        ),
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
    final titleText = term.kanjiBracketText.isNotEmpty
        ? term.kanjiBracketText
        : term.kanji;

    return AnimatedOpacity(
      key: ValueKey(term.id),
      opacity: isDeleting ? 0 : 1,
      duration: _deleteSlideDuration,
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        onLongPress: () => toggleSelect(term),
        onTap: () => openCardSettings(term),
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
                  titleText: titleText,
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
                          term.marked
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: GakujiColors.reading,
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

}

class _HybridCardEditSwitcher extends StatelessWidget {
  final _HybridCardEditView selectedView;
  final Color activeColor;
  final VoidCallback onReadingTap;
  final VoidCallback onWritingTap;

  const _HybridCardEditSwitcher({
    required this.selectedView,
    required this.activeColor,
    required this.onReadingTap,
    required this.onWritingTap,
  });

  bool get readingSelected {
    return selectedView == _HybridCardEditView.reading;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final indicatorWidth = constraints.maxWidth / 2;

        return SizedBox(
          height: 42,
          child: Stack(
            children: [
              Positioned.fill(
                bottom: 6,
                child: Row(
                  children: [
                    Expanded(
                      child: _HybridCardEditTab(
                        label: 'Reading',
                        isSelected: readingSelected,
                        activeColor: activeColor,
                        onTap: onReadingTap,
                      ),
                    ),
                    Expanded(
                      child: _HybridCardEditTab(
                        label: 'Writing',
                        isSelected: !readingSelected,
                        activeColor: activeColor,
                        onTap: onWritingTap,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 2,
                  color: GakujiColors.softBorder,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: readingSelected
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: indicatorWidth,
                    height: 4,
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HybridCardEditTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _HybridCardEditTab({
    required this.label,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          style: GakujiText.medium.copyWith(
            fontSize: 16,
            height: 1,
            fontWeight: FontWeight.w700,
            color: isSelected ? activeColor : GakujiColors.darkGray,
          ),
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
          ),
        ),
      ),
    );
  }
}

class _DeckColorWheel extends StatelessWidget {
  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onChanged;

  const _DeckColorWheel({
    required this.hsvColor,
    required this.onChanged,
  });

  void _updateColor(Offset localPosition, double size) {
    final center = Offset(size / 2, size / 2);
    final offset = localPosition - center;
    final radius = size / 2;

    final saturation =
        (offset.distance / radius).clamp(0.0, 1.0).toDouble();
    final angle = math.atan2(offset.dy, offset.dx);
    final hue = ((angle * 180 / math.pi) + 360) % 360;

    onChanged(
      HSVColor.fromAHSV(
        1,
        hue,
        saturation,
        hsvColor.value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 204.0).toDouble();

        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) {
              _updateColor(details.localPosition, size);
            },
            onPanUpdate: (details) {
              _updateColor(details.localPosition, size);
            },
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _DeckColorWheelPainter(hsvColor),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeckColorWheelPainter extends CustomPainter {
  final HSVColor hsvColor;

  const _DeckColorWheelPainter(this.hsvColor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final wheelRect = Rect.fromCircle(center: center, radius: radius);

    final huePaint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ).createShader(wheelRect);

    canvas.drawCircle(center, radius, huePaint);

    final saturationPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(wheelRect);

    canvas.drawCircle(center, radius, saturationPaint);

    if (hsvColor.value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.black.withValues(alpha: 1 - hsvColor.value),
      );
    }

    final angle = hsvColor.hue * math.pi / 180;
    final indicatorRadius = radius * hsvColor.saturation;
    final indicatorCenter = Offset(
      center.dx + math.cos(angle) * indicatorRadius,
      center.dy + math.sin(angle) * indicatorRadius,
    );

    canvas.drawCircle(
      indicatorCenter,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );

    canvas.drawCircle(
      indicatorCenter,
      10.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x66000000),
    );
  }

  @override
  bool shouldRepaint(covariant _DeckColorWheelPainter oldDelegate) {
    return oldDelegate.hsvColor != hsvColor;
  }
}
