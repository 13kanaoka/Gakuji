import 'package:flutter/material.dart';

import '../data/deck_data.dart';
import '../data/folder_data.dart';
import '../data/pinned_deck_data.dart';
import '../models/deck.dart';
import '../models/folder.dart';
import '../widgets/gakuji_deck_card.dart';
import '../widgets/gakuji_folder_card.dart';
import '../widgets/gakuji_search_bar.dart';
import 'deck_page.dart';
import 'folder_page.dart';

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
  static const Color deckBlue = Color(0xFF4D7EF7);
  static const Color dividerGray = Color(0xFFE1E1E1);
  static const Color outlineGray = Color(0xFFD8D8D8);
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
  final TextEditingController deckNameController = TextEditingController();
  final TextEditingController folderNameController = TextEditingController();

  String searchQuery = '';

  int get selectedItemCount {
    return selectedDeckIds.length + selectedFolderIds.length;
  }

  bool get hasSelectedItems {
    return selectedItemCount > 0;
  }

  @override
  void dispose() {
    searchController.dispose();
    deckNameController.dispose();
    folderNameController.dispose();
    super.dispose();
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
      barrierLabel: 'New Deck',
      barrierColor: Colors.black.withOpacity(0.72),
      transitionDuration: const Duration(milliseconds: 280),
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
                child: _newDeckCard(
                  selectedType: dialogSelectedType,
                  deckNameError: deckNameError,
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

    deckNameController.clear();

    if (created == true) {
      setState(() {
        showDecks = true;
      });
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
      barrierColor: Colors.black.withOpacity(0.72),
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
    }
  }

  void closeMenu() {
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
  }

  @override
  Widget build(BuildContext context) {
    final normalizedSearchQuery = searchQuery.trim().toLowerCase();

    final visibleDecks = decks.where((deck) {
      if (normalizedSearchQuery.isEmpty) return true;

      return deck.name.toLowerCase().contains(normalizedSearchQuery);
    }).toList();

    final visibleFolders = folders.where((folder) {
      if (normalizedSearchQuery.isEmpty) return true;

      return folder.name.toLowerCase().contains(normalizedSearchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
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
                _libraryHeader(),
                Expanded(
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                        child: showDecks
                            ? _deckContent(visibleDecks)
                            : _folderContent(visibleFolders),
                      ),
                      Positioned(
                        top: 18,
                        left: 18,
                        right: 18,
                        child: GakujiSearchBar(
                          controller: searchController,
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
      height: topInset + 96,
      color: deckBlue,
      padding: EdgeInsets.fromLTRB(28, topInset + 18, 28, 18),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _viewSwitchButton(),
          ),
          const Text(
            'Library',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 18,
              height: 1,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _headerMenuButton(),
          ),
        ],
      ),
    );
  }

  Widget _viewSwitchButton() {
    return _Pushable(
      onTap: toggleLibraryView,
      pressedOffset: 4,
      child: Container(
        width: 76,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: outlineGray,
            width: 2.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D000000),
              blurRadius: 0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          showDecks ? 'Decks' : 'Folders',
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            fontSize: 15,
            height: 1,
            fontWeight: FontWeight.w700,
            color: Color(0xFF666666),
          ),
        ),
      ),
    );
  }

  Widget _headerMenuButton() {
    return Opacity(
      opacity: isDeletingItems ? 0 : 1,
      child: _Pushable(
        onTap: isDeletingItems
            ? null
            : () {
                setState(() {
                  showMenu = !showMenu;
                });
              },
        pressedOffset: 4,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: outlineGray,
              width: 2.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D000000),
                blurRadius: 0,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.more_horiz,
            color: Color(0xFF666666),
            size: 23,
          ),
        ),
      ),
    );
  }

  Widget _deckContent(List<Deck> visibleDecks) {
    if (visibleDecks.isEmpty) {
      return Center(
        child: Text(
          isDeletingItems
              ? 'No decks to delete'
              : searchQuery.trim().isEmpty
                  ? 'No decks yet'
                  : 'No decks found',
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
        ),
      );
    }

    return _fadedScrollContent(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 82, 0, 190),
        itemCount: visibleDecks.length,
        separatorBuilder: (context, index) {
          return const SizedBox(height: 18);
        },
        itemBuilder: (context, index) {
          final deck = visibleDecks[index];

          return _deckListItem(deck);
        },
      ),
    );
  }

  Widget _deckListItem(Deck deck) {
    final isSelected = selectedDeckIds.contains(deck.id);

    return GakujiDeckCard(
      title: deck.name,
      subtitle: _deckTypeLabel(deck.type),
      watermark: _watermarkForDeckType(deck.type),
      watermarkAssetPath: _watermarkAssetForDeckType(deck.type),
      shellColor: isSelected ? deleteRed : null,
      isPinned: isDeckPinned(deck),
      onTap: () async {
        if (isDeletingItems) {
          toggleDeckSelection(deck);
          return;
        }

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DeckPage(deck: deck),
          ),
        );

        if (!mounted) return;

        setState(() {});
      },
    );
  }

  Widget _folderContent(List<Folder> visibleFolders) {
    if (visibleFolders.isEmpty) {
      return Center(
        child: Text(
          isDeletingItems
              ? 'No folders to delete'
              : searchQuery.trim().isEmpty
                  ? 'No folders yet'
                  : 'No folders found',
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 330 ? 2 : 3;

        return _fadedScrollContent(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(0, 82, 0, 190),
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
          MaterialPageRoute(
            builder: (context) => FolderPage(folder: folder),
          ),
        );

        if (!mounted) return;

        setState(() {});
      },
      pressedOffset: 4,
      child: AnimatedContainer(
        duration: deleteAnimationDuration,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
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

  Widget _fadedScrollContent({
    required Widget child,
  }) {
    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [
            0.0,
            0.055,
            0.76,
            1.0,
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
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
                    icon: Icons.add,
                    label: 'New Deck',
                    onTap: openNewDeckPopup,
                  ),
                  const Divider(height: 1, color: dividerGray),
                  _menuItem(
                    icon: Icons.create_new_folder_rounded,
                    label: 'New Folder',
                    iconColor: Colors.grey,
                    onTap: openNewFolderPopup,
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
                  backgroundColor: Colors.white,
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
    required ValueChanged<String> onNameChanged,
    required ValueChanged<DeckType> onTypeChanged,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: deckBlue,
          width: 6,
        ),
      ),
      child: Column(
        children: [
          const Text(
            'New Deck',
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
          _fieldLabel('Deck Name'),
          const SizedBox(height: 8),
          _nameField(
            controller: deckNameController,
            hintText: 'Enter deck name',
            hasError: deckNameError != null,
            onChanged: onNameChanged,
            onSubmit: onCreate,
          ),
          if (deckNameError != null) ...[
            const SizedBox(height: 7),
            _errorText(deckNameError),
          ],
          const SizedBox(height: 22),
          _fieldLabel('Deck Type'),
          const SizedBox(height: 8),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: deckBlue,
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
        style: const TextStyle(
          fontSize: 15,
          height: 1,
          fontWeight: FontWeight.w600,
          color: Colors.black,
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
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: fieldGray,
        borderRadius: BorderRadius.circular(14),
        border: hasError
            ? Border.all(
                color: deleteRed,
                width: 2,
              )
            : null,
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.done,
        onChanged: onChanged,
        onSubmitted: (_) => onSubmit(),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: const TextStyle(
            color: textGray,
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
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: fieldGray,
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DeckType>(
          value: selectedType,
          isExpanded: true,
          borderRadius: BorderRadius.circular(14),
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          style: const TextStyle(
            fontSize: 16,
            color: Colors.black,
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
    return Container(
      width: 230,
      height: 54,
      decoration: BoxDecoration(
        color: deckBlue,
        borderRadius: BorderRadius.circular(14),
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
              style: const TextStyle(
                fontSize: 20,
                height: 1,
                fontWeight: FontWeight.w700,
                color: Colors.white,
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
}

class _Pushable extends StatefulWidget {
  const _Pushable({
    required this.child,
    required this.onTap,
    this.pressedOffset = 4,
    this.duration = const Duration(milliseconds: 90),
  });

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