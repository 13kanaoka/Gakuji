import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:gakuji/data/state/recent_deck_data.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/features/auth/services/account_username_service.dart';
import 'package:gakuji/data/sync/gakuji_user_data_store.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/data/sync/gakuji_user_repository.dart';

Future<GakujiDeckSheetResult?> showGakujiDeckSaveSheet({
  required BuildContext context,
  required List<Deck> decks,
  required String directSaveDeckId,
  required bool Function(Deck deck) deckContainsTerm,
}) {
  return showModalBottomSheet<GakujiDeckSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _GakujiDeckSaveSheet(
        decks: decks,
        directSaveDeckId: directSaveDeckId,
        deckContainsTerm: deckContainsTerm,
      );
    },
  );
}

enum GakujiDeckSheetAction {
  saveToDeck,
  setDirectSaveDeck,
}

class GakujiDeckSheetResult {
  final GakujiDeckSheetAction action;
  final Deck deck;

  const GakujiDeckSheetResult({
    required this.action,
    required this.deck,
  });
}

class _GakujiDeckSaveSheet extends StatefulWidget {
  final List<Deck> decks;
  final String directSaveDeckId;
  final bool Function(Deck deck) deckContainsTerm;

  const _GakujiDeckSaveSheet({
    required this.decks,
    required this.directSaveDeckId,
    required this.deckContainsTerm,
  });

  @override
  State<_GakujiDeckSaveSheet> createState() => _GakujiDeckSaveSheetState();
}

class _GakujiDeckSaveSheetState extends State<_GakujiDeckSaveSheet> {
  static const String recentDeckColorsPreferenceKey = 'recent_deck_colors';
  static const int maxRecentDeckColors = 6;

  late final PageController pageController;
  late final TextEditingController deckNameController;

  int currentPanel = 0;
  DeckType selectedDeckType = DeckType.reading;
  Color selectedDeckColor = GakujiColors.reading;
  bool hasManuallySelectedDeckColor = false;
  String? deckNameError;
  List<Color> recentDeckColors = [];

  @override
  void initState() {
    super.initState();

    pageController = PageController();
    deckNameController = TextEditingController();
    _loadRecentDeckColors();
  }

  Color _defaultDeckColorForType(DeckType type) {
    return GakujiColors.defaultDeckColorForType(type);
  }

  Color _readableTextColor(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF3F3F3F);
  }

  Future<void> _loadRecentDeckColors() async {
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

  Future<void> _saveRecentDeckColor(Color color) async {
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
  }

  @override
  void dispose() {
    pageController.dispose();
    deckNameController.dispose();

    super.dispose();
  }

  void _showSaveDecks() {
    FocusScope.of(context).unfocus();

    setState(() {
      currentPanel = 0;
    });

    pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOut,
    );
  }

  void _showDirectSaveDecks() {
    FocusScope.of(context).unfocus();

    setState(() {
      currentPanel = 1;
    });

    pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOut,
    );
  }

  void _showCreateDeckPanel() {
    FocusScope.of(context).unfocus();
    deckNameController.clear();

    setState(() {
      currentPanel = 2;
      selectedDeckType = DeckType.reading;
      selectedDeckColor = _defaultDeckColorForType(DeckType.reading);
      hasManuallySelectedDeckColor = false;
      deckNameError = null;
    });

    pageController.animateToPage(
      2,
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOut,
    );
  }

  void _createDeckFromSheet(BuildContext context) {
    final deckName = deckNameController.text.trim();

    if (deckName.isEmpty) {
      setState(() {
        deckNameError = 'Deck name required';
      });

      return;
    }

    if (GakujiUsernameService.containsRestrictedLanguage(deckName)) {
      setState(() {
        deckNameError = 'Deck name contains a restricted term';
      });

      return;
    }

    final newDeck = Deck(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: deckName,
      type: selectedDeckType,
      colorValue: selectedDeckColor.toARGB32(),
      terms: [],
    );

    widget.decks.add(newDeck);
    GakujiUserDataStore.scheduleSave();

    FocusScope.of(context).unfocus();

    Navigator.pop(
      context,
      GakujiDeckSheetResult(
        action: GakujiDeckSheetAction.saveToDeck,
        deck: newDeck,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: DraggableScrollableSheet(
        minChildSize: 0.46,
        initialChildSize: 0.56,
        maxChildSize: 0.96,
        snap: true,
        snapSizes: const [0.56, 0.96],
        expand: false,
        builder: (context, sheetScrollController) {
          return Container(
            decoration: BoxDecoration(
              color: GakujiColors.warmBackground,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              top: false,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: PageView(
                  controller: pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _saveToPanel(
                      context,
                      scrollController:
                          currentPanel == 0 ? sheetScrollController : null,
                    ),
                    _directSavePanel(
                      context,
                      scrollController:
                          currentPanel == 1 ? sheetScrollController : null,
                    ),
                    _createDeckPanel(
                      context,
                      scrollController:
                          currentPanel == 2 ? sheetScrollController : null,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _saveToPanel(
    BuildContext context, {
    ScrollController? scrollController,
  }) {
    final orderedDecks = orderDecksByRecentInteraction(widget.decks);

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black,
            Colors.black,
            Color(0x00000000),
          ],
          stops: [
            0.0,
            0.94,
            1.0,
          ],
        ).createShader(bounds);
      },
      child: ListView.separated(
        controller: scrollController,
        primary: false,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 28),
        itemCount: orderedDecks.length + 1,
        separatorBuilder: (context, index) {
          if (index == 0) return const SizedBox.shrink();

          return Divider(
            height: 1,
            thickness: 1,
            color: GakujiColors.warmDivider,
          );
        },
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              children: [
                _sheetHandle(),
                _sheetTitle('Save to...'),
                _createDeckNavButton(),
                _directSaveNavButton(),
                Divider(
                  height: 1,
                  color: GakujiColors.warmDivider,
                ),
              ],
            );
          }

          final deck = orderedDecks[index - 1];
          final isSaved = widget.deckContainsTerm(deck);
          final isDirectSaveDeck = deck.id == widget.directSaveDeckId;

          return _deckRow(
            deck: deck,
            isDirectSaveDeck: isDirectSaveDeck,
            trailing: isSaved
                ? const Icon(
                    Icons.check_circle,
                    color: GakujiColors.reading,
                  )
                : const SizedBox.shrink(),
            onTap: () {
              Navigator.pop(
                context,
                GakujiDeckSheetResult(
                  action: GakujiDeckSheetAction.saveToDeck,
                  deck: deck,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _createDeckNavButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Material(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _showCreateDeckPanel,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: GakujiColors.warmDivider,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 27,
                  color: GakujiColors.reading,
                ),
                SizedBox(width: 13),
                Expanded(
                  child: Text(
                    'Create new deck',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1,
                      color: GakujiColors.darkGray,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 27,
                  color: GakujiColors.mediumGray,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _directSaveNavButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Material(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _showDirectSaveDecks,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: GakujiColors.warmDivider,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bookmark_border,
                  size: 24,
                  color: GakujiColors.reading,
                ),
                SizedBox(width: 13),
                Expanded(
                  child: Text(
                    'Select direct save deck',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1,
                      color: GakujiColors.darkGray,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 27,
                  color: GakujiColors.mediumGray,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _directSavePanel(
    BuildContext context, {
    ScrollController? scrollController,
  }) {
    final orderedDecks = orderDecksByRecentInteraction(widget.decks);

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black,
            Colors.black,
            Color(0x00000000),
          ],
          stops: [
            0.0,
            0.94,
            1.0,
          ],
        ).createShader(bounds);
      },
      child: ListView.separated(
        controller: scrollController,
        primary: false,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 28),
        itemCount: orderedDecks.length + 1,
        separatorBuilder: (context, index) {
          if (index == 0) return const SizedBox.shrink();

          return Divider(
            height: 1,
            thickness: 1,
            color: GakujiColors.warmDivider,
          );
        },
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              children: [
                _sheetHandle(),
                _panelHeader(
                  title: 'Select direct save deck',
                  onBack: _showSaveDecks,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                  child: Text(
                    'Bookmark saves go directly to this deck.',
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.15,
                      color: GakujiColors.mediumGray,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: GakujiColors.warmDivider,
                ),
              ],
            );
          }

          final deck = orderedDecks[index - 1];
          final isSelected = deck.id == widget.directSaveDeckId;

          return _deckRow(
            deck: deck,
            trailing: isSelected
                ? const Icon(
                    Icons.check_circle,
                    color: GakujiColors.reading,
                  )
                : Icon(
                    Icons.circle_outlined,
                    color: GakujiColors.mediumGray,
                  ),
            onTap: () {
              Navigator.pop(
                context,
                GakujiDeckSheetResult(
                  action: GakujiDeckSheetAction.setDirectSaveDeck,
                  deck: deck,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _createDeckPanel(
    BuildContext context, {
    ScrollController? scrollController,
  }) {
    return ListView(
      controller: scrollController,
      primary: false,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _sheetHandle(),
        _panelHeader(
          title: 'Create new deck',
          onBack: _showSaveDecks,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel('Deck Name'),
              const SizedBox(height: 10),
              _deckNameField(context),
              if (deckNameError != null) ...[
                const SizedBox(height: 8),
                _errorText(deckNameError),
              ],
              const SizedBox(height: 24),
              _fieldLabel('Deck Type'),
              const SizedBox(height: 10),
              _deckTypeDropdown(),
              const SizedBox(height: 24),
              _fieldLabel('Deck Color'),
              const SizedBox(height: 10),
              _deckColorPicker(),
              const SizedBox(height: 28),
              _createDeckButton(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _panelHeader({
    required String title,
    required VoidCallback onBack,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 38,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack,
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 17,
                  color: GakujiColors.darkGray,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 18,
                height: 1,
                fontWeight: FontWeight.w700,
                color: GakujiColors.darkGray,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: 15.5,
        height: 1,
        color: GakujiColors.darkGray,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _deckNameField(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: deckNameError == null
              ? GakujiColors.warmDivider
              : const Color(0xFFFF6F6F),
          width: deckNameError == null ? 1.4 : 2,
        ),
      ),
      child: Center(
        child: TextField(
          controller: deckNameController,
          textInputAction: TextInputAction.done,
          cursorColor: GakujiColors.reading,
          onChanged: (_) {
            if (deckNameError == null) return;

            setState(() {
              deckNameError = null;
            });
          },
          onSubmitted: (_) => _createDeckFromSheet(context),
          style: TextStyle(
            fontSize: 17,
            height: 1,
            color: GakujiColors.darkGray,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            isCollapsed: true,
            hintText: 'Enter deck name',
            hintStyle: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: GakujiColors.mediumGray,
            ),
          ),
        ),
      ),
    );
  }

  Widget _deckTypeDropdown() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.4,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DeckType>(
          value: selectedDeckType,
          isExpanded: true,
          borderRadius: BorderRadius.circular(17),
          dropdownColor: GakujiColors.warmCard,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: GakujiColors.mediumGray,
            size: 30,
          ),
          style: TextStyle(
            fontSize: 17,
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

            setState(() {
              selectedDeckType = value;
              if (!hasManuallySelectedDeckColor) {
                selectedDeckColor = _defaultDeckColorForType(value);
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> _openDeckColorPicker() async {
    FocusScope.of(context).unfocus();

    final pickedColor = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var workingColor = HSVColor.fromColor(selectedDeckColor);
        var sheetDismissDragOffset = 0.0;
        var isSheetDismissDragging = false;
        final bottomSafePadding =
            MediaQuery.viewPaddingOf(sheetContext).bottom;
        final colorPickerMaxHeight =
            MediaQuery.sizeOf(sheetContext).height * 0.88;

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
                    maxHeight: colorPickerMaxHeight,
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
                                        borderRadius: BorderRadius.circular(999),
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
                                        style: GakujiText.sectionTitle.copyWith(
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
                                style: GakujiText.deckMeta.copyWith(
                                  color: GakujiColors.darkGray,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: previewColor,
                                    inactiveTrackColor:
                                        GakujiColors.warmDivider,
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
                                style: GakujiText.deckMeta.copyWith(
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
                                  final isSelected = color.toARGB32() ==
                                      previewColor.toARGB32();

                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      setSheetState(() {
                                        workingColor =
                                            HSVColor.fromColor(color);
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
                                              color:
                                                  _readableTextColor(color),
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
                                    onPressed: () =>
                                        Navigator.pop(sheetContext),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: GakujiColors.softBorder,
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Text(
                                      'Cancel',
                                      textScaler: TextScaler.noScaling,
                                      style: GakujiText.deckMeta.copyWith(
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
                                      Navigator.pop(
                                        sheetContext,
                                        previewColor,
                                      );
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: previewColor,
                                      foregroundColor:
                                          _readableTextColor(previewColor),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Text(
                                      'Use Color',
                                      textScaler: TextScaler.noScaling,
                                      style: GakujiText.deckMeta.copyWith(
                                        color:
                                            _readableTextColor(previewColor),
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
      selectedDeckColor = pickedColor;
      hasManuallySelectedDeckColor = true;
    });

    await _saveRecentDeckColor(pickedColor);
  }

  Widget _deckColorPicker() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.4,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openDeckColorPicker,
          splashColor: selectedDeckColor.withValues(alpha: 0.08),
          highlightColor: selectedDeckColor.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose Color',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      color: GakujiColors.darkGray,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selectedDeckColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: GakujiColors.softBorder,
                      width: 1.5,
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

  Widget _createDeckButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: selectedDeckColor),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        builder: (context, color, child) {
          final buttonColor = color ?? selectedDeckColor;

          return Material(
            color: buttonColor,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _createDeckFromSheet(context),
              child: Center(
                child: Text(
                  'Create and Save',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1,
                    color: _readableTextColor(buttonColor),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _errorText(String? text) {
    return Text(
      text ?? '',
      textScaler: TextScaler.noScaling,
      style: const TextStyle(
        fontSize: 12,
        height: 1,
        color: Color(0xFFFF6F6F),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _sheetHandle() {
    return Center(
      child: Container(
        width: 42,
        height: 5,
        margin: const EdgeInsets.only(top: 9, bottom: 10),
        decoration: BoxDecoration(
          color: GakujiColors.softGray,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _sheetTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: Text(
        title,
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 18,
          height: 1,
          fontWeight: FontWeight.w700,
          color: GakujiColors.darkGray,
        ),
      ),
    );
  }


  Widget _deckRow({
    required Deck deck,
    required Widget trailing,
    required VoidCallback onTap,
    bool isDirectSaveDeck = false,
  }) {
    return ListTile(
      isThreeLine: true,
      minVerticalPadding: 8,
      contentPadding: const EdgeInsets.symmetric(horizontal: 22),
      titleAlignment: ListTileTitleAlignment.center,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDirectSaveDeck) ...[
            const Icon(
              Icons.bookmark_rounded,
              size: 17,
              color: GakujiColors.reading,
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              deck.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 16,
                height: 1.05,
                fontWeight: FontWeight.w600,
                color: GakujiColors.darkGray,
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_deckTypeLabel(deck.type)} deck',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.15,
                color: GakujiColors.mediumGray,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${deck.terms.length} terms',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.15,
                color: GakujiColors.mediumGray,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      trailing: trailing,
      onTap: onTap,
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
