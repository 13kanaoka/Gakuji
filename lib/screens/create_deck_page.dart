import 'package:flutter/material.dart';

import '../data/deck_data.dart';
import '../models/deck.dart';
import '../services/gakuji_user_data_store.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import 'import_terms_page.dart';

class CreateDeckPage extends StatefulWidget {
  const CreateDeckPage({super.key});

  @override
  State<CreateDeckPage> createState() => _CreateDeckPageState();
}

class _CreateDeckPageState extends State<CreateDeckPage> {
  final TextEditingController nameController = TextEditingController();

  DeckType selectedType = DeckType.reading;
  String? deckNameError;

  Color get selectedDeckTypeColor {
    switch (selectedType) {
      case DeckType.reading:
        return GakujiColors.reading;
      case DeckType.writing:
        return GakujiColors.writing;
      case DeckType.hybrid:
        return GakujiColors.hybrid;
    }
  }

  @override
  void dispose() {
    nameController.dispose();

    super.dispose();
  }

  void scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
  }

  Future<void> openTermsImportPage() async {
    final imported = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const ImportTermsPage(),
      ),
    );

    if (!mounted || imported != true) return;

    Navigator.pop(context, true);
  }

  void createDeck() {
    final name = nameController.text.trim();

    if (name.isEmpty) {
      setState(() {
        deckNameError = 'Deck name required';
      });

      return;
    }

    decks.add(
      Deck(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        type: selectedType,
        terms: [],
      ),
    );

    scheduleUserDataSave();

    Navigator.pop(context, true);
  }

  String deckTypeLabel(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'Writing';
      case DeckType.reading:
        return 'Reading';
      case DeckType.hybrid:
        return 'Hybrid';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    Center(
                      child: _deckCreationIcon(),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Create Deck',
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.large.copyWith(
                          color: GakujiColors.darkGray,
                          fontSize: 28,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 72),
                    _fieldLabel('Deck Name'),
                    const SizedBox(height: 10),
                    _nameField(),
                    if (deckNameError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        deckNameError!,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF6F6F),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    _fieldLabel('Deck Type'),
                    const SizedBox(height: 10),
                    _deckTypeDropdown(),
                    const Spacer(),
                    _createButton(),
                    const SizedBox(height: 12),
                    _importTermsButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return GakujiTopBar(
      leftIcon: Icons.close_rounded,
      leftIconSize: 34,
      leftIconColor: GakujiColors.darkGray,
      onLeftTap: () => Navigator.pop(context),
    );
  }

  Widget _deckCreationIcon() {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        children: [
          Positioned(
            left: 22,
            top: 8,
            child: Container(
              width: 42,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFB8B8B8),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 14,
            child: Container(
              width: 46,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF6B6B6B),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      textScaler: TextScaler.noScaling,
      style: GakujiText.small.copyWith(
        color: GakujiColors.darkGray,
      ),
    );
  }

  Widget _nameField() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: deckNameError == null
              ? GakujiColors.warmDivider
              : const Color(0xFFFF6F6F),
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: TextField(
        controller: nameController,
        textInputAction: TextInputAction.done,
        onChanged: (_) {
          if (deckNameError == null) return;

          setState(() {
            deckNameError = null;
          });
        },
        onSubmitted: (_) => createDeck(),
        style: GakujiText.small.copyWith(
          color: GakujiColors.darkGray,
        ),
        cursorColor: GakujiColors.darkGray,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Enter deck name',
          hintStyle: GakujiText.small.copyWith(
            color: GakujiColors.mediumGray,
          ),
        ),
      ),
    );
  }

  Widget _deckTypeDropdown() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DeckType>(
          value: selectedType,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          dropdownColor: GakujiColors.warmCard,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: GakujiColors.darkGray,
          ),
          style: GakujiText.small.copyWith(
            color: GakujiColors.darkGray,
          ),
          items: DeckType.values.map((type) {
            return DropdownMenuItem(
              value: type,
              child: Text(
                deckTypeLabel(type),
                textScaler: TextScaler.noScaling,
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              selectedType = value;
            });
          },
        ),
      ),
    );
  }

  Widget _importTermsButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openTermsImportPage,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GakujiRadius.pill),
              border: Border.all(
                color: GakujiColors.reading,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.upload_file_rounded,
                  color: GakujiColors.reading,
                  size: 23,
                ),
                const SizedBox(width: 10),
                Text(
                  'Import Terms From File',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.small.copyWith(
                    color: GakujiColors.reading,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _createButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          end: selectedDeckTypeColor,
        ),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        builder: (context, color, child) {
          return Material(
            color: color,
            borderRadius: BorderRadius.circular(GakujiRadius.pill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: createDeck,
              child: Center(
                child: Text(
                  'Create New Deck',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.small.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}