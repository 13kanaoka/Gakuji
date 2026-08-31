import 'package:flutter/material.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';

import 'package:gakuji/data/seed/deck_seed.dart';
import 'package:gakuji/data/seed/folder_seed.dart';
import 'package:gakuji/data/state/pinned_deck_data.dart';
import 'package:gakuji/data/state/recent_deck_data.dart';
import 'package:gakuji/data/review/review_card_data.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/folder.dart';
import 'package:gakuji/domain/review_card.dart';
import 'package:gakuji/features/auth/services/account_username_service.dart';
import 'package:gakuji/data/sync/gakuji_user_data_store.dart';
import 'package:gakuji/data/review/review_settings.dart';
import 'package:gakuji/features/library/widgets/gakuji_deck_card.dart';
import 'package:gakuji/core/widgets/gakuji_deck_transition.dart';
import 'package:gakuji/core/widgets/gakuji_faded_scroll.dart';
import 'package:gakuji/features/library/widgets/gakuji_folder_card.dart';
import 'package:gakuji/core/widgets/gakuji_search_bar.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/features/library/widgets/gakuji_todo_deck_card.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/features/decks/create_deck_page.dart';
import 'package:gakuji/features/decks/deck_page.dart';
import 'package:gakuji/features/library/folder_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    this.onDeleteModeChanged,
  });

  final ValueChanged<bool>? onDeleteModeChanged;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const Color dividerGray = Color(0xFFE1E1E1);
  static const Color textGray = Color(0xFF6F6F6F);
  static const Color fieldGray = Color(0xFFEDEDED);
  static const Color deleteRed = Color(0xFFFF6F6F);

  static const Duration deleteAnimationDuration = Duration(milliseconds: 260);

  bool showDecks = true;
  bool showMenu = false;
  bool isDeletingItems = false;

  final Set<String> selectedDeckIds = <String>{};
  final Set<String> selectedFolderIds = <String>{};

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  final TextEditingController deckNameController = TextEditingController();
  final TextEditingController folderNameController = TextEditingController();

  String searchQuery = '';
  Map<String, int> remainingNewCardsTodayByDeck = <String, int>{};
  Map<String, int> remainingReviewCardsTodayByDeck = <String, int>{};

  int get selectedItemCount {
    return selectedDeckIds.length + selectedFolderIds.length;
  }

  bool get hasSelectedItems {
    return selectedItemCount > 0;
  }

  @override
  void initState() {
    super.initState();
    _loadRecentDeckOrder();
  }

  Future<void> _loadRecentDeckOrder() async {
    await loadRecentlyOpenedDeckIds();
    await loadReviewCards();
    await _loadReviewAvailability();

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadReviewAvailability() async {
    final settings = await ReviewSettingsStore.load();
    final nextRemainingNew = <String, int>{};
    final nextRemainingReview = <String, int>{};

    for (final deck in decks) {
      final newCardsStartedToday =
          await ReviewSettingsStore.newCardsStartedToday(deckId: deck.id);
      final reviewsCompletedToday =
          await ReviewSettingsStore.reviewsCompletedToday(deckId: deck.id);

      nextRemainingNew[deck.id] =
          (settings.newLimit - newCardsStartedToday).clamp(0, 9999).toInt();
      nextRemainingReview[deck.id] =
          (settings.reviewLimit - reviewsCompletedToday).clamp(0, 9999).toInt();
    }

    remainingNewCardsTodayByDeck = nextRemainingNew;
    remainingReviewCardsTodayByDeck = nextRemainingReview;
  }

  Future<void> _refreshLibraryData() async {
    if (isDeletingItems) return;

    FocusScope.of(context).unfocus();

    if (showMenu) {
      setState(() {
        showMenu = false;
      });
    }

    try {
      await GakujiUserDataStore.refreshFromCloud();
      await loadReviewCards();
      await _loadReviewAvailability();

      if (!mounted) return;

      setState(() {});
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1600),
            backgroundColor: Colors.black.withValues(alpha: 0.86),
            content: Text(
              'Couldn\'t refresh Library',
              textScaler: TextScaler.noScaling,
              style: GakujiText.snackBar,
            ),
          ),
        );
    }
  }

  Widget _libraryRefreshIndicator({required Widget child}) {
    return RefreshIndicator(
      onRefresh: _refreshLibraryData,
      color: GakujiColors.reading,
      backgroundColor: GakujiColors.warmCard,
      edgeOffset: 68,
      displacement: 30,
      child: child,
    );
  }

  Widget _refreshableEmptyContent(String message) {
    return _libraryRefreshIndicator(
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 70, 14, 190),
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.small.copyWith(
                    color: GakujiColors.mediumGray,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    searchFocusNode.dispose();
    searchController.dispose();
    deckNameController.dispose();
    folderNameController.dispose();

    super.dispose();
  }

  void scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
  }

  Future<void> openNewDeckPopup() async {
    setState(() {
      showMenu = false;
    });

    FocusScope.of(context).unfocus();
    deckNameController.clear();

    DeckType dialogSelectedType = DeckType.reading;
    String? deckNameError;

    final created = await showGeneralDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'Create New Deck',
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void createDeckFromDialog() {
              final name = deckNameController.text.trim();

              if (name.isEmpty) {
                setDialogState(() {
                  deckNameError = 'Deck name required';
                });

                return;
              }

              if (GakujiUsernameService.containsRestrictedLanguage(name)) {
                setDialogState(() {
                  deckNameError = 'Deck name contains a restricted term';
                });

                return;
              }

              decks.add(
                Deck(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  type: dialogSelectedType,
                  terms: [],
                ),
              );

              FocusScope.of(dialogContext).unfocus();
              Navigator.of(dialogContext, rootNavigator: true).pop(true);
            }

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
              ),
              child: _newDeckCard(
                selectedType: dialogSelectedType,
                deckNameError: deckNameError,
                onClose: () {
                  FocusScope.of(dialogContext).unfocus();
                  Navigator.of(dialogContext, rootNavigator: true).pop(false);
                },
                onNameChanged: (_) {
                  if (deckNameError == null) return;

                  setDialogState(() {
                    deckNameError = null;
                  });
                },
                onTypeChanged: (value) {
                  setDialogState(() {
                    dialogSelectedType = value;
                  });
                },
                onCreate: createDeckFromDialog,
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: FadeTransition(
            opacity: curvedAnimation,
            child: child,
          ),
        );
      },
    );

    if (!mounted) return;

    deckNameController.clear();

    if (created == true) {
      setState(() {
        showDecks = true;
      });

      scheduleUserDataSave();
    }
  }

  Future<void> openNewFolderPopup() async {
    setState(() {
      showMenu = false;
    });

    FocusScope.of(context).unfocus();
    folderNameController.clear();

    String? folderNameError;

    final created = await showGeneralDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'New Folder',
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void createFolderFromDialog() {
              final name = folderNameController.text.trim();

              if (name.isEmpty) {
                setDialogState(() {
                  folderNameError = 'Folder name required';
                });

                return;
              }

              folders.add(
                Folder(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  deckIds: [],
                ),
              );

              FocusScope.of(dialogContext).unfocus();
              Navigator.of(dialogContext, rootNavigator: true).pop(true);
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 36),
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
                ),
                child: _newFolderCard(
                  folderNameError: folderNameError,
                  onNameChanged: (_) {
                    if (folderNameError == null) return;

                    setDialogState(() {
                      folderNameError = null;
                    });
                  },
                  onCreate: createFolderFromDialog,
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1.1),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: FadeTransition(
            opacity: curvedAnimation,
            child: child,
          ),
        );
      },
    );

    if (!mounted) return;

    folderNameController.clear();

    if (created == true) {
      setState(() {
        showDecks = false;
      });

      scheduleUserDataSave();
    }
  }

  void closeMenu() {
    setState(() {
      showMenu = false;
    });
  }

  void exitSearchAndCloseMenu() {
    FocusScope.of(context).unfocus();

    if (!showMenu) return;

    setState(() {
      showMenu = false;
    });
  }

  void toggleLibraryView() {
    setState(() {
      showDecks = !showDecks;
    });
  }

  void startDeleteMode() {
    setState(() {
      showMenu = false;
      isDeletingItems = true;
      selectedDeckIds.clear();
      selectedFolderIds.clear();
    });

    widget.onDeleteModeChanged?.call(true);
  }

  void cancelDeleteMode() {
    setState(() {
      isDeletingItems = false;
      selectedDeckIds.clear();
      selectedFolderIds.clear();
    });

    widget.onDeleteModeChanged?.call(false);
  }

  void toggleDeckSelection(Deck deck) {
    if (!isDeletingItems) return;

    setState(() {
      if (selectedDeckIds.contains(deck.id)) {
        selectedDeckIds.remove(deck.id);
      } else {
        selectedDeckIds.add(deck.id);
      }
    });
  }

  void toggleFolderSelection(Folder folder) {
    if (!isDeletingItems) return;

    setState(() {
      if (selectedFolderIds.contains(folder.id)) {
        selectedFolderIds.remove(folder.id);
      } else {
        selectedFolderIds.add(folder.id);
      }
    });
  }

  void deleteSelectedItems() {
    if (!hasSelectedItems) return;

    final deckIdsToDelete = Set<String>.from(selectedDeckIds);
    final folderIdsToDelete = Set<String>.from(selectedFolderIds);

    if (deckIdsToDelete.isNotEmpty) {
      removeDecksFromRecentOrder(deckIdsToDelete);
    }

    setState(() {
      if (deckIdsToDelete.isNotEmpty) {
        decks.removeWhere((deck) {
          return deckIdsToDelete.contains(deck.id);
        });

        pinnedDeckIds.removeWhere((deckId) {
          return deckIdsToDelete.contains(deckId);
        });

        for (final folder in folders) {
          folder.deckIds.removeWhere((deckId) {
            return deckIdsToDelete.contains(deckId);
          });
        }
      }

      if (folderIdsToDelete.isNotEmpty) {
        folders.removeWhere((folder) {
          return folderIdsToDelete.contains(folder.id);
        });
      }

      selectedDeckIds.clear();
      selectedFolderIds.clear();
      isDeletingItems = false;
    });

    widget.onDeleteModeChanged?.call(false);
    scheduleUserDataSave();
  }

  List<Deck> _orderDecksForLibrary(List<Deck> sourceDecks) {
    final deckById = <String, Deck>{
      for (final deck in sourceDecks) deck.id: deck,
    };
    final originalIndex = <String, int>{
      for (var index = 0; index < sourceDecks.length; index++)
        sourceDecks[index].id: index,
    };
    final recentIndex = <String, int>{
      for (var index = 0; index < recentlyOpenedDeckIds.length; index++)
        recentlyOpenedDeckIds[index]: index,
    };

    final orderedDecks = <Deck>[];

    for (final pinnedDeckId in pinnedDeckIds) {
      final pinnedDeck = deckById.remove(pinnedDeckId);
      if (pinnedDeck != null) {
        orderedDecks.add(pinnedDeck);
      }
    }

    final unpinnedDecks = deckById.values.toList();
    unpinnedDecks.sort((first, second) {
      final firstRecentIndex = recentIndex[first.id];
      final secondRecentIndex = recentIndex[second.id];

      if (firstRecentIndex != null && secondRecentIndex != null) {
        return firstRecentIndex.compareTo(secondRecentIndex);
      }

      if (firstRecentIndex != null) return -1;
      if (secondRecentIndex != null) return 1;

      return originalIndex[first.id]!.compareTo(originalIndex[second.id]!);
    });

    return <Deck>[
      ...orderedDecks,
      ...unpinnedDecks,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final normalizedSearchQuery = searchQuery.trim().toLowerCase();

    final matchingDecks = decks.where((deck) {
      if (normalizedSearchQuery.isEmpty) return true;

      return deck.name.toLowerCase().contains(normalizedSearchQuery);
    }).toList();
    final visibleDecks = _orderDecksForLibrary(matchingDecks);

    final visibleFolders = folders.where((folder) {
      if (normalizedSearchQuery.isEmpty) return true;

      return folder.name.toLowerCase().contains(normalizedSearchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: exitSearchAndCloseMenu,
            child: Column(
              children: [
                _libraryHeader(),
                Expanded(
                  child: Stack(
                    children: [
                      showDecks
                          ? _deckContent(visibleDecks)
                          : _folderContent(visibleFolders),
                      Positioned(
                        top: 8,
                        left: 14,
                        right: 14,
                        child: GakujiSearchBar(
                          controller: searchController,
                          focusNode: searchFocusNode,
                          hintText: 'Search',
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
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _deleteModeControls(),
          if (showMenu) _menuOverlay(),
        ],
      ),
    );
  }

  Widget _libraryHeader() {
    final topInset = MediaQuery.of(context).padding.top;

    return Container(
      color: GakujiColors.warmBackground,
      padding: EdgeInsets.only(
        top: topInset + 4,
        bottom: 4,
      ),
      child: GakujiTopBar(
        title: 'Decks',
        titleStyle: GakujiText.pageTitle.copyWith(
          color: GakujiColors.darkGray,
        ),
        rightIcon: isDeletingItems ? null : Icons.add_rounded,
        rightIconColor: GakujiColors.darkGray,
        onRightTap: isDeletingItems ? null : _openCreateDeckPage,
      ),
    );
  }

  Future<void> _openCreateDeckPage() async {
    final created = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const GakujiSwipeBackScope(
            side: GakujiPageSide.right,
            child: CreateDeckPage(),
          );
        },
        transitionsBuilder: (
          context,
          animation,
          secondaryAnimation,
          child,
        ) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: child,
          );
        },
      ),
    );

    if (!mounted) return;

    if (created == true) {
      setState(() {
        showDecks = true;
      });

      scheduleUserDataSave();
    }
  }

  Widget _deckContent(List<Deck> visibleDecks) {
    if (visibleDecks.isEmpty) {
      return _refreshableEmptyContent(
        isDeletingItems
            ? 'No decks to delete'
            : searchQuery.trim().isEmpty
                ? 'No decks yet'
                : 'No decks found',
      );
    }

    return GakujiFadedScroll.withBottomNavigation(
      child: _libraryRefreshIndicator(
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 70, 14, 190),
          itemCount: visibleDecks.length,
          separatorBuilder: (context, index) {
            return const SizedBox(height: 18);
          },
          itemBuilder: (context, index) {
            final deck = visibleDecks[index];

            return _deckListItem(deck);
          },
        ),
      ),
    );
  }

  Widget _deckListItem(Deck deck) {
    final isSelected = selectedDeckIds.contains(deck.id);
    final dueCards = getDueReviewCardsForDeck(deck.id);
    final rawNewCount = dueCards
        .where((card) => card.state == ReviewCardState.newCard)
        .length;
    final remainingNewCardsToday =
        remainingNewCardsTodayByDeck[deck.id] ?? 0;
    final newCount = rawNewCount < remainingNewCardsToday
        ? rawNewCount
        : remainingNewCardsToday;
    final learningCount = dueCards
        .where(
          (card) =>
              card.state == ReviewCardState.learning ||
              card.state == ReviewCardState.relearning,
        )
        .length;
    final rawReviewCount = dueCards
        .where((card) => card.state == ReviewCardState.review)
        .length;
    final remainingReviewCardsToday =
        remainingReviewCardsTodayByDeck[deck.id] ?? 0;
    final reviewCount = rawReviewCount < remainingReviewCardsToday
        ? rawReviewCount
        : remainingReviewCardsToday;
    final hasReviewDue =
        newCount > 0 || learningCount > 0 || reviewCount > 0;

    Future<void> openDeck() async {
      if (isDeletingItems) {
        toggleDeckSelection(deck);
        return;
      }

      await Navigator.of(context).push(
        gakujiDeckRoute<void>(
          page: DeckPage(deck: deck),
        ),
      );

      await loadReviewCards();
      await _loadReviewAvailability();

      if (!mounted) return;

      setState(() {});
      scheduleUserDataSave();
    }

    if (hasReviewDue && !isDeletingItems) {
      return Hero(
        tag: gakujiDeckHeroTag(deck.id),
        createRectTween: gakujiDeckRectTween,
        flightShuttleBuilder: gakujiDeckFlightShuttleBuilder,
        child: Material(
          type: MaterialType.transparency,
          child: GakujiTodoDeckCard(
            deck: deck,
            newCount: newCount,
            learningCount: learningCount,
            reviewCount: reviewCount,
            isPinned: isDeckPinned(deck),
            compact: true,
            onTap: openDeck,
          ),
        ),
      );
    }

    return Hero(
      tag: gakujiDeckHeroTag(deck.id),
      createRectTween: gakujiDeckRectTween,
      flightShuttleBuilder: gakujiDeckFlightShuttleBuilder,
      child: Material(
        type: MaterialType.transparency,
        child: GakujiDeckCard(
          title: deck.name,
          subtitle: _deckTypeLabel(deck.type),
          watermark: _watermarkForDeckType(deck.type),
          watermarkAssetPath: _watermarkAssetForDeckType(deck.type),
          accentColor: GakujiColors.deckColorFor(deck),
          patternAssetPath: _patternAssetForDeckType(deck.type),
          shellColor: isSelected ? deleteRed : null,
          isPinned: isDeckPinned(deck),
          onTap: openDeck,
        ),
      ),
    );
  }

  Widget _folderContent(List<Folder> visibleFolders) {
    if (visibleFolders.isEmpty) {
      return _refreshableEmptyContent(
        isDeletingItems
            ? 'No folders to delete'
            : searchQuery.trim().isEmpty
                ? 'No folders yet'
                : 'No folders found',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 330 ? 2 : 3;

        return GakujiFadedScroll.withBottomNavigation(
          child: _libraryRefreshIndicator(
            child: GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 70, 14, 190),
              itemCount: visibleFolders.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 18,
                mainAxisSpacing: 30,
                childAspectRatio: 1.38,
              ),
              itemBuilder: (context, index) {
                final folder = visibleFolders[index];

                return _folderGridItem(folder);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _folderGridItem(Folder folder) {
    final isSelected = selectedFolderIds.contains(folder.id);

    return _Pushable(
      onTap: () async {
        if (isDeletingItems) {
          toggleFolderSelection(folder);
          return;
        }

        await Navigator.push(
          context,
          GakujiPageRoute(
            builder: (context) => FolderPage(folder: folder),
          ),
        );

        if (!mounted) return;

        setState(() {});
        scheduleUserDataSave();
      },
      pressedOffset: 4,
      child: AnimatedContainer(
        duration: deleteAnimationDuration,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: GakujiColors.warmCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? deleteRed : Colors.transparent,
            width: 3,
          ),
        ),
        child: IgnorePointer(
          child: GakujiFolderCard(
            title: folder.name,
            onTap: () {},
          ),
        ),
      ),
    );
  }

  Widget _menuOverlay() {
    final topInset = MediaQuery.of(context).padding.top;

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: closeMenu,
            child: Container(
              color: Colors.transparent,
            ),
          ),
          Positioned(
            top: topInset + 58,
            right: 28,
            child: Container(
              width: 214,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: GakujiColors.warmCard,
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
                    icon: Icons.add,
                    label: 'New Deck',
                    onTap: openNewDeckPopup,
                  ),
                  const Divider(height: 1, color: dividerGray),
                  _menuItem(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    iconColor: deleteRed,
                    textColor: deleteRed,
                    onTap: startDeleteMode,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deleteModeControls() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: IgnorePointer(
        ignoring: !isDeletingItems,
        child: AnimatedSlide(
          offset: isDeletingItems ? Offset.zero : const Offset(0, 1.45),
          duration: deleteAnimationDuration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: isDeletingItems ? 1 : 0,
            duration: deleteAnimationDuration,
            curve: Curves.easeOutCubic,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _bottomActionButton(
                  label: 'Cancel',
                  backgroundColor: GakujiColors.warmCard,
                  textColor: Colors.black,
                  borderColor: dividerGray,
                  onTap: cancelDeleteMode,
                ),
                AnimatedContainer(
                  duration: deleteAnimationDuration,
                  curve: Curves.easeOutCubic,
                  height: hasSelectedItems ? 14 : 0,
                ),
                ClipRect(
                  child: AnimatedAlign(
                    duration: deleteAnimationDuration,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    heightFactor: hasSelectedItems ? 1 : 0,
                    child: AnimatedSlide(
                      offset: hasSelectedItems
                          ? Offset.zero
                          : const Offset(0, 1.2),
                      duration: deleteAnimationDuration,
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: hasSelectedItems ? 1 : 0,
                        duration: deleteAnimationDuration,
                        curve: Curves.easeOutCubic,
                        child: _bottomActionButton(
                          label: selectedItemCount == 1
                              ? 'Delete Item'
                              : 'Delete Items',
                          backgroundColor: deleteRed,
                          textColor: Colors.white,
                          onTap: deleteSelectedItems,
                        ),
                      ),
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

  Widget _newDeckCard({
    required DeckType selectedType,
    required String? deckNameError,
    required VoidCallback onClose,
    required ValueChanged<String> onNameChanged,
    required ValueChanged<DeckType> onTypeChanged,
    required VoidCallback onCreate,
  }) {
    return Material(
      color: GakujiColors.warmBackground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 22, 32, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Icon(
                        Icons.close_rounded,
                        color: GakujiColors.darkGray,
                        size: 42,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 66),
              Center(
                child: _deckCreationIcon(),
              ),
              const SizedBox(height: 30),
              Text(
                'Create New Deck',
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: GakujiText.large.copyWith(
                  color: GakujiColors.darkGray,
                  fontSize: 34,
                  height: 1,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 82),
              _fieldLabel('Deck Name'),
              const SizedBox(height: 10),
              _nameField(
                controller: deckNameController,
                hintText: 'Enter deck name',
                hasError: deckNameError != null,
                onChanged: onNameChanged,
                onSubmit: onCreate,
              ),
              if (deckNameError != null) ...[
                const SizedBox(height: 8),
                _errorText(deckNameError),
              ],
              const SizedBox(height: 28),
              _fieldLabel('Deck Type'),
              const SizedBox(height: 10),
              _deckTypeDropdown(
                selectedType: selectedType,
                onChanged: onTypeChanged,
              ),
              const Spacer(),
              _createActionButton(
                label: 'Create Deck',
                onTap: onCreate,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deckCreationIcon() {
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 7,
            left: 18,
            child: Container(
              width: 28,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF2F5268),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 10,
            child: Container(
              width: 31,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF5B8DB0),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: const Color(0xFF456F8A),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _newFolderCard({
    required String? folderNameError,
    required ValueChanged<String> onNameChanged,
    required VoidCallback onCreate,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final cardWidth = (screenSize.width - 72).clamp(300.0, 360.0).toDouble();
    final cardHeight =
        (screenSize.height * 0.66).clamp(500.0, 620.0).toDouble();

    return Container(
      width: cardWidth,
      height: cardHeight,
      padding: const EdgeInsets.fromLTRB(24, 42, 24, 24),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: GakujiColors.deckBlue,
          width: 6,
        ),
      ),
      child: Column(
        children: [
          const Text(
            'New Folder',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 36,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 44),
          _fieldLabel('Folder Name'),
          const SizedBox(height: 8),
          _nameField(
            controller: folderNameController,
            hintText: 'Enter folder name',
            hasError: folderNameError != null,
            onChanged: onNameChanged,
            onSubmit: onCreate,
          ),
          if (folderNameError != null) ...[
            const SizedBox(height: 7),
            _errorText(folderNameError),
          ],
          const Spacer(),
          _createActionButton(
            label: 'Create Folder',
            onTap: onCreate,
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 17,
          height: 1,
          fontWeight: FontWeight.w700,
          color: GakujiColors.darkGray,
        ),
      ),
    );
  }

  Widget _errorText(String? text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text ?? '',
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: deleteRed,
        ),
      ),
    );
  }

  Widget _nameField({
    required TextEditingController controller,
    required String hintText,
    required bool hasError,
    required ValueChanged<String> onChanged,
    required VoidCallback onSubmit,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: fieldGray,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasError ? deleteRed : GakujiColors.warmDivider,
          width: hasError ? 2 : 1.5,
        ),
      ),
      child: Center(
        child: TextField(
          controller: controller,
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmit(),
          cursorColor: GakujiColors.darkGray,
          style: TextStyle(
            fontSize: 20,
            height: 1,
            fontWeight: FontWeight.w500,
            color: GakujiColors.darkGray,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            isCollapsed: true,
            hintText: hintText,
            hintStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: textGray,
            ),
          ),
        ),
      ),
    );
  }

  Widget _deckTypeDropdown({
    required DeckType selectedType,
    required ValueChanged<DeckType> onChanged,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: fieldGray,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.5,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DeckType>(
          value: selectedType,
          isExpanded: true,
          borderRadius: BorderRadius.circular(18),
          dropdownColor: GakujiColors.warmCard,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: GakujiColors.mediumGray,
            size: 30,
          ),
          style: TextStyle(
            fontSize: 20,
            height: 1,
            fontWeight: FontWeight.w500,
            color: GakujiColors.darkGray,
          ),
          items: DeckType.values.map((type) {
            return DropdownMenuItem(
              value: type,
              child: Text(
                _deckTypeLabel(type),
                textScaler: TextScaler.noScaling,
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;

            onChanged(value);
          },
        ),
      ),
    );
  }

  Widget _createActionButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: GakujiColors.deckBlue,
          borderRadius: BorderRadius.circular(GakujiRadius.pill),
          boxShadow: [GakujiShadows.soft],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(GakujiRadius.pill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.white.withValues(alpha: 0.10),
            highlightColor: Colors.white.withValues(alpha: 0.05),
            child: Center(
              child: Text(
                label,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomActionButton({
    required String label,
    required Color backgroundColor,
    required Color textColor,
    required VoidCallback onTap,
    Color? borderColor,
  }) {
    return Container(
      width: 230,
      height: 54,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: borderColor == null
            ? null
            : Border.all(
                color: borderColor,
                width: 1.5,
              ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 0,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 20,
                height: 1,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.black,
    Color textColor = Colors.black,
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
            Icon(
              icon,
              color: iconColor,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _deckTypeLabel(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'Writing';
      case DeckType.reading:
        return 'Reading';
      case DeckType.hybrid:
        return 'Hybrid';
    }
  }

  String _watermarkForDeckType(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return '書';
      case DeckType.reading:
        return '読';
      case DeckType.hybrid:
        return '学';
    }
  }

  String _watermarkAssetForDeckType(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'assets/images/deck_watermark_3.png';
      case DeckType.reading:
        return 'assets/images/deck_watermark_2.png';
      case DeckType.hybrid:
        return 'assets/images/deck_watermark_1.png';
    }
  }

  String _patternAssetForDeckType(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'assets/images/deck_pattern_writing.png';
      case DeckType.reading:
        return 'assets/images/deck_pattern_reading.png';
      case DeckType.hybrid:
        return 'assets/images/deck_pattern_hybrid.png';
    }
  }
}

class _Pushable extends StatefulWidget {
  const _Pushable({
    required this.child,
    required this.onTap,
    this.pressedOffset = 4,
  }) : duration = const Duration(milliseconds: 90);

  final Widget child;
  final VoidCallback? onTap;
  final double pressedOffset;
  final Duration duration;

  @override
  State<_Pushable> createState() => _PushableState();
}

class _PushableState extends State<_Pushable> {
  static const Duration minimumPressDuration = Duration(milliseconds: 85);
  static const Duration tapReleaseDelay = Duration(milliseconds: 35);

  bool pressed = false;
  bool isTapLocked = false;
  DateTime? pressedStartedAt;
  int releaseRunId = 0;

  void setPressed() {
    if (widget.onTap == null || isTapLocked) return;

    pressedStartedAt = DateTime.now();

    setState(() {
      pressed = true;
    });
  }

  Future<void> releaseAfterMinimumPress() async {
    final startedAt = pressedStartedAt;
    final currentRunId = ++releaseRunId;

    if (startedAt != null) {
      final elapsed = DateTime.now().difference(startedAt);
      final remaining = minimumPressDuration - elapsed;

      if (!remaining.isNegative) {
        await Future.delayed(remaining);
      }
    }

    if (!mounted || currentRunId != releaseRunId) return;

    setState(() {
      pressed = false;
    });
  }

  Future<void> handleTap() async {
    if (widget.onTap == null || isTapLocked) return;

    isTapLocked = true;

    await releaseAfterMinimumPress();
    await Future.delayed(tapReleaseDelay);

    if (!mounted) return;

    isTapLocked = false;
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setPressed(),
      onTapUp: (_) {},
      onTapCancel: releaseAfterMinimumPress,
      onTap: handleTap,
      child: AnimatedContainer(
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(
          0,
          pressed ? widget.pressedOffset : 0,
          0,
        ),
        child: widget.child,
      ),
    );
  }
}