import 'package:flutter/material.dart';

import '../data/deck_data.dart';
import '../models/deck.dart';
import '../models/folder.dart';
import '../theme/app_text_styles.dart';
import '../widgets/gakuji_deck_card.dart';
import '../widgets/gakuji_search_bar.dart';
import '../widgets/gakuji_top_bar.dart';
import 'deck_page.dart';

class FolderPage extends StatefulWidget {
  final Folder folder;

  const FolderPage({super.key, required this.folder});

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  static const Color dividerGray = Color(0xFFE1E1E1);
  static const Color deleteRed = Color(0xFFFF6F6F);

  static const Duration deleteAnimationDuration = Duration(milliseconds: 260);

  final TextEditingController searchController = TextEditingController();

  String searchQuery = '';

  bool showMenu = false;
  bool isRemovingDecks = false;

  final Set<String> selectedDeckIds = <String>{};

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

  void closeMenu() {
    setState(() {
      showMenu = false;
    });
  }

  void startRemoveMode() {
    setState(() {
      showMenu = false;
      isRemovingDecks = true;
      selectedDeckIds.clear();
    });
  }

  void cancelRemoveMode() {
    setState(() {
      isRemovingDecks = false;
      selectedDeckIds.clear();
    });
  }

  void toggleDeckSelection(Deck deck) {
    if (!isRemovingDecks) return;

    setState(() {
      if (selectedDeckIds.contains(deck.id)) {
        selectedDeckIds.remove(deck.id);
      } else {
        selectedDeckIds.add(deck.id);
      }
    });
  }

  void removeSelectedDecksFromFolder() {
    if (selectedDeckIds.isEmpty) return;

    final idsToRemove = Set<String>.from(selectedDeckIds);

    setState(() {
      widget.folder.deckIds.removeWhere((deckId) {
        return idsToRemove.contains(deckId);
      });

      selectedDeckIds.clear();
      isRemovingDecks = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final normalizedSearchQuery = searchQuery.trim().toLowerCase();

    final visibleDecks = folderDecks.where((deck) {
      if (normalizedSearchQuery.isEmpty) return true;

      return deck.name.toLowerCase().contains(normalizedSearchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              onTap: () {
                if (showMenu) {
                  setState(() {
                    showMenu = false;
                  });
                }
              },
              child: Column(
                children: [
                  GakujiTopBar(
                    leftIcon: Icons.arrow_back_ios_new,
                    onLeftTap: () {
                      if (isRemovingDecks) {
                        cancelRemoveMode();
                        return;
                      }

                      Navigator.pop(context);
                    },
                    title: widget.folder.name,
                    titleStyle: AppText.topBarTitleSmall,
                    rightIcon: isRemovingDecks ? null : Icons.more_horiz,
                    onRightTap: isRemovingDecks
                        ? null
                        : () {
                            setState(() {
                              showMenu = !showMenu;
                            });
                          },
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                      child: Column(
                        children: [
                          GakujiSearchBar(
                            controller: searchController,
                            hintText: 'Search decks',
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
                          const SizedBox(height: 24),
                          Expanded(
                            child: visibleDecks.isEmpty
                                ? Center(
                                    child: Text(
                                      searchQuery.trim().isEmpty
                                          ? 'No decks in this folder yet'
                                          : 'No decks found',
                                      textScaler: TextScaler.noScaling,
                                      style: AppText.emptyState,
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      12,
                                      0,
                                      190,
                                    ),
                                    itemCount: visibleDecks.length,
                                    separatorBuilder: (context, index) {
                                      return const SizedBox(height: 18);
                                    },
                                    itemBuilder: (context, index) {
                                      final deck = visibleDecks[index];
                                      final isSelected = selectedDeckIds
                                          .contains(deck.id);

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
            _removeModeControls(),
            if (showMenu) _menuOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _deckCard(Deck deck, bool isSelected) {
    return AnimatedContainer(
      duration: deleteAnimationDuration,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: isSelected ? deleteRed : Colors.transparent,
          width: 3,
        ),
      ),
      child: GakujiDeckCard(
        title: deck.name,
        subtitle: _deckTypeLabel(deck.type),
        watermark: _watermarkForDeckType(deck.type),
        watermarkAssetPath: _watermarkAssetForDeckType(deck.type),
        onTap: () async {
          if (isRemovingDecks) {
            toggleDeckSelection(deck);
            return;
          }

          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => DeckPage(deck: deck)),
          );

          if (!mounted) return;

          setState(() {});
        },
      ),
    );
  }

  Widget _menuOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: closeMenu,
            child: Container(color: Colors.transparent),
          ),
          Positioned(
            top: 48,
            right: 18,
            child: Container(
              width: 214,
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
              child: _menuItem(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                iconColor: deleteRed,
                textColor: deleteRed,
                onTap: startRemoveMode,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _removeModeControls() {
    final hasSelection = selectedDeckIds.isNotEmpty;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: IgnorePointer(
        ignoring: !isRemovingDecks,
        child: AnimatedSlide(
          offset: isRemovingDecks ? Offset.zero : const Offset(0, 1.45),
          duration: deleteAnimationDuration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: isRemovingDecks ? 1 : 0,
            duration: deleteAnimationDuration,
            curve: Curves.easeOutCubic,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _bottomActionButton(
                  label: 'Cancel',
                  backgroundColor: Colors.white,
                  textColor: Colors.black,
                  borderColor: dividerGray,
                  onTap: cancelRemoveMode,
                ),
                AnimatedContainer(
                  duration: deleteAnimationDuration,
                  curve: Curves.easeOutCubic,
                  height: hasSelection ? 14 : 0,
                ),
                ClipRect(
                  child: AnimatedAlign(
                    duration: deleteAnimationDuration,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    heightFactor: hasSelection ? 1 : 0,
                    child: AnimatedSlide(
                      offset: hasSelection ? Offset.zero : const Offset(0, 1.2),
                      duration: deleteAnimationDuration,
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: hasSelection ? 1 : 0,
                        duration: deleteAnimationDuration,
                        curve: Curves.easeOutCubic,
                        child: _bottomActionButton(
                          label: selectedDeckIds.length == 1
                              ? 'Remove Deck'
                              : 'Remove Decks',
                          backgroundColor: deleteRed,
                          textColor: Colors.white,
                          onTap: removeSelectedDecksFromFolder,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 12),
            Text(
              label,
              textScaler: TextScaler.noScaling,
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
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
            : Border.all(color: borderColor, width: 1.5),
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
              style: AppText.primaryButton.copyWith(color: textColor),
            ),
          ),
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
}
