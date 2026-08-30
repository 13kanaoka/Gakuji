import 'package:flutter/material.dart';

import 'package:gakuji/data/recent_deck_data.dart';
import 'package:gakuji/models/deck.dart';
import 'package:gakuji/services/account_username_service.dart';
import 'package:gakuji/services/gakuji_user_data_store.dart';
import 'package:gakuji/widgets/gakuji_styles.dart';

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
  late final PageController pageController;
  late final TextEditingController deckNameController;

  DeckType selectedDeckType = DeckType.reading;
  String? deckNameError;

  @override
  void initState() {
    super.initState();

    pageController = PageController();
    deckNameController = TextEditingController();
  }

  @override
  void dispose() {
    pageController.dispose();
    deckNameController.dispose();

    super.dispose();
  }

  void _showSaveDecks() {
    FocusScope.of(context).unfocus();

    pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOut,
    );
  }

  void _showDirectSaveDecks() {
    FocusScope.of(context).unfocus();

    pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOut,
    );
  }

  void _showCreateDeckPanel() {
    deckNameController.clear();

    setState(() {
      selectedDeckType = DeckType.reading;
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
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final bottomSafeInset = mediaQuery.viewPadding.bottom;
    final sheetHeight = (screenHeight * 0.52) + bottomSafeInset;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        height: sheetHeight,
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
                _saveToPanel(context),
                _directSavePanel(context),
                _createDeckPanel(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _saveToPanel(BuildContext context) {
    final orderedDecks = orderDecksByRecentInteraction(widget.decks);

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
        Expanded(
          child: _deckList(
            itemBuilder: (context, index) {
              final deck = orderedDecks[index];
              final isSaved = widget.deckContainsTerm(deck);
              final isDirectSaveDeck = deck.id == widget.directSaveDeckId;

              return _deckRow(
                deck: deck,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDirectSaveDeck)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          'Direct',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1,
                            color: GakujiColors.mediumGray,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (isSaved)
                      const Icon(
                        Icons.check_circle,
                        color: GakujiColors.reading,
                      ),
                  ],
                ),
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
        ),
      ],
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

  Widget _directSavePanel(BuildContext context) {
    final orderedDecks = orderDecksByRecentInteraction(widget.decks);

    return Column(
      children: [
        _sheetHandle(),
        _panelHeader(
          title: 'Select direct save deck',
          onBack: _showSaveDecks,
        ),
         Padding(
          padding: EdgeInsets.fromLTRB(22, 0, 22, 12),
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
        Expanded(
          child: _deckList(
            itemBuilder: (context, index) {
              final deck = orderedDecks[index];
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
        ),
      ],
    );
  }

  Widget _createDeckPanel(BuildContext context) {
    return Column(
      children: [
        _sheetHandle(),
        _panelHeader(
          title: 'Create new deck',
          onBack: _showSaveDecks,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
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
                  size: 19,
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
            });
          },
        ),
      ),
    );
  }

  Widget _createDeckButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: GakujiColors.reading,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _createDeckFromSheet(context),
          child: const Center(
            child: Text(
              'Create and Save',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 17,
                height: 1,
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
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


  Widget _deckList({
    required IndexedWidgetBuilder itemBuilder,
  }) {
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
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 28),
        itemCount: widget.decks.length,
        itemBuilder: itemBuilder,
      ),
    );
  }

  Widget _deckRow({
    required Deck deck,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      isThreeLine: true,
      minVerticalPadding: 8,
      contentPadding: const EdgeInsets.symmetric(horizontal: 22),
      title: Text(
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
