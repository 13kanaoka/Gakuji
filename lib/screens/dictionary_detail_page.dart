import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/deck_data.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../widgets/gakuji_top_bar.dart';
import 'kanji_dictionary_detail_page.dart';

class DictionaryDetailBackResult {
  final bool returnToResults;

  const DictionaryDetailBackResult({
    this.returnToResults = true,
  });
}

class DictionaryDetailPage extends StatefulWidget {
  final Term word;

  const DictionaryDetailPage({
    super.key,
    required this.word,
  });

  @override
  State<DictionaryDetailPage> createState() => _DictionaryDetailPageState();
}

class _DictionaryDetailPageState extends State<DictionaryDetailPage> {
  static const Color sectionColor = Color(0xFFEAF0FF);
  static const Color accentBlue = Color(0xFF4D7EF7);
  static const Color dividerColor = Color(0xFFE3E3E3);
  static const Color softTextGray = Color(0xFF8A8A8A);
  static const Color softBlueFill = Color(0xFFF5F7FF);

  static const double topActionPillWidth = 92;
  static const int maxNoteCharacters = 400;
  static const String directSaveDeckPreferenceKey =
      'gakuji_direct_save_deck_id';

  late final TextEditingController noteController;
  late final FocusNode noteFocusNode;

  Timer? savePopupTimer;

  bool showMoreMeanings = false;
  bool isEditingNote = false;
  bool noteLoaded = false;
  bool showSavePopup = false;

  String noteText = '';
  String? directSaveDeckId;
  String savePopupText = '';
  IconData savePopupIcon = Icons.check_circle;

  Deck get fallbackDirectSaveDeck {
    for (final deck in decks) {
      if (deck.name == 'Gakuji test deck') {
        return deck;
      }
    }

    return decks.first;
  }

  Deck get directSaveDeck {
    final selectedDeckId = directSaveDeckId;

    if (selectedDeckId != null) {
      for (final deck in decks) {
        if (deck.id == selectedDeckId) {
          return deck;
        }
      }
    }

    return fallbackDirectSaveDeck;
  }

  String get sourceId => widget.word.sourceId ?? widget.word.id;

  String get notePreferenceKey => 'gakuji_dictionary_note_$sourceId';

  @override
  void initState() {
    super.initState();

    noteController = TextEditingController();
    noteFocusNode = FocusNode();
    noteFocusNode.addListener(_handleNoteFocusChange);

    _loadSavedNote();
    _loadDirectSaveDeck();
  }

  @override
  void didUpdateWidget(covariant DictionaryDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldSourceId = oldWidget.word.sourceId ?? oldWidget.word.id;

    if (oldSourceId != sourceId) {
      showMoreMeanings = false;
      isEditingNote = false;
      noteLoaded = false;
      noteText = '';
      noteController.text = '';

      _loadSavedNote();
    }
  }

  @override
  void dispose() {
    savePopupTimer?.cancel();
    noteFocusNode.removeListener(_handleNoteFocusChange);
    noteFocusNode.dispose();
    noteController.dispose();

    super.dispose();
  }

  Future<void> _loadSavedNote() async {
    final prefs = await SharedPreferences.getInstance();
    final savedNote = prefs.getString(notePreferenceKey);
    final initialNote = savedNote ?? widget.word.note ?? '';

    if (!mounted) return;

    setState(() {
      noteText = initialNote;
      noteController.text = initialNote;
      noteLoaded = true;
    });
  }

  Future<void> _loadDirectSaveDeck() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDeckId = prefs.getString(directSaveDeckPreferenceKey);

    if (!mounted) return;

    setState(() {
      directSaveDeckId = savedDeckId;
    });
  }

  Future<void> _setDirectSaveDeck(Deck deck) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(directSaveDeckPreferenceKey, deck.id);

    if (!mounted) return;

    setState(() {
      directSaveDeckId = deck.id;
    });

    _showSavePopup('Direct save deck: ${deck.name}');
  }

  void _showSavePopup(
    String message, {
    IconData icon = Icons.check_circle,
  }) {
    savePopupTimer?.cancel();

    setState(() {
      savePopupText = message;
      savePopupIcon = icon;
      showSavePopup = true;
    });

    savePopupTimer = Timer(const Duration(milliseconds: 1700), () {
      if (!mounted) return;

      setState(() {
        showSavePopup = false;
      });
    });
  }

  void _handleNoteFocusChange() {
    if (!noteFocusNode.hasFocus && isEditingNote) {
      _saveNoteFromController(closeEditor: true);
    }
  }

  void _startEditingNote() {
    if (!noteLoaded) return;

    setState(() {
      isEditingNote = true;
      noteController.text = noteText;
      noteController.selection = TextSelection.collapsed(
        offset: noteController.text.length,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      noteFocusNode.requestFocus();
    });
  }

  Future<void> _saveNoteFromController({
    required bool closeEditor,
  }) async {
    final cleanedNote = _cleanNoteText(noteController.text);

    await _saveNote(
      cleanedNote,
      closeEditor: closeEditor,
    );
  }

  Future<void> _clearNote() async {
    noteController.clear();

    await _saveNote(
      '',
      closeEditor: true,
    );

    if (!mounted) return;

    FocusScope.of(context).unfocus();
  }

  Future<void> _saveNote(
    String value, {
    required bool closeEditor,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(notePreferenceKey, value);

    if (!mounted) return;

    setState(() {
      noteText = value;

      if (closeEditor) {
        isEditingNote = false;
      }
    });
  }

  String _cleanNoteText(String value) {
    if (value.length <= maxNoteCharacters) {
      return value.trimRight();
    }

    return value.substring(0, maxNoteCharacters).trimRight();
  }

  Future<void> _handleBackTap() async {
    if (isEditingNote) {
      await _saveNoteFromController(closeEditor: true);
    }

    if (!mounted) return;

    Navigator.of(context).pop(
      const DictionaryDetailBackResult(returnToResults: true),
    );
  }

  bool deckContainsWord(Deck deck) {
    return deck.terms.any((term) => term.sourceId == sourceId);
  }

  Term copiedWordForDeck(Deck deck) {
    return Term.deckCopyFrom(
      widget.word,
      id: '${deck.id}_${sourceId}_${DateTime.now().microsecondsSinceEpoch}',
      marked: false,
    );
  }

  bool get isSaved {
    return deckContainsWord(directSaveDeck);
  }

  void toggleDirectSaveDeck() {
    if (isEditingNote) {
      _saveNoteFromController(closeEditor: true);
    }

    final deck = directSaveDeck;
    final wasSaved = deckContainsWord(deck);

    setState(() {
      if (wasSaved) {
        deck.terms.removeWhere((term) => term.sourceId == sourceId);
      } else {
        deck.terms.add(copiedWordForDeck(deck));
      }
    });

    if (wasSaved) {
      _showSavePopup(
        'Removed from ${deck.name}',
        icon: Icons.close_rounded,
      );
    } else {
      _showSavePopup('Saved to ${deck.name}');
    }
  }

  void _toggleWordInDeck(Deck deck) {
    final wasSaved = deckContainsWord(deck);

    setState(() {
      if (wasSaved) {
        deck.terms.removeWhere((term) => term.sourceId == sourceId);
      } else {
        deck.terms.add(copiedWordForDeck(deck));
      }
    });

    if (wasSaved) {
      _showSavePopup(
        'Removed from ${deck.name}',
        icon: Icons.close_rounded,
      );
    } else {
      _showSavePopup('Saved to ${deck.name}');
    }
  }

  Future<void> openDeckPicker() async {
    if (isEditingNote) {
      await _saveNoteFromController(closeEditor: true);
    }

    if (!mounted) return;

    final result = await showModalBottomSheet<_DeckSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _DeckSaveSheet(
          decks: decks,
          directSaveDeckId: directSaveDeck.id,
          deckContainsWord: deckContainsWord,
        );
      },
    );

    if (!mounted || result == null) return;

    switch (result.action) {
      case _DeckSheetAction.saveToDeck:
        _toggleWordInDeck(result.deck);
        break;
      case _DeckSheetAction.setDirectSaveDeck:
        await _setDirectSaveDeck(result.deck);
        break;
    }
  }

  void openKanjiDetail(Term word) {
    if (!word.hasKanjiDetails) return;

    if (isEditingNote) {
      _saveNoteFromController(closeEditor: true);
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KanjiDictionaryDetailPage(
          kanjiEntry: word,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _handleBackTap();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  GakujiTopBar(
                    leftIcon: Icons.arrow_back_ios_new,
                    onLeftTap: _handleBackTap,
                    title: _topBarTitle(word),
                    rightWidget: _topActionPill(),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 110),
                      children: [
                        _entryHeader(word),
                        _noteSection(word),
                        if (_shouldShowKanjiSection(word)) _kanjiSection(word),
                        _examplesSection(word),
                      ],
                    ),
                  ),
                ],
              ),
              _savePopupOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _savePopupOverlay() {
    final isRemoval = savePopupIcon == Icons.close_rounded;

    return Positioned(
      top: 58,
      left: 22,
      right: 22,
      child: IgnorePointer(
        ignoring: true,
        child: AnimatedSlide(
          offset: showSavePopup ? Offset.zero : const Offset(0, -0.16),
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: showSavePopup ? 1 : 0,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 310),
                padding: const EdgeInsets.fromLTRB(13, 9, 14, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: sectionColor,
                    width: 1.4,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 0,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      savePopupIcon,
                      size: 20,
                      color: isRemoval ? softTextGray : accentBlue,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        savePopupText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.12,
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _entryHeader(Term word) {
    final definitions = word.displayDefinitions;
    final extraDefinitions = _extraRawDefinitions(word);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _wordTitleLine(word)),
              if (word.isCommon)
                SizedBox(
                  width: topActionPillWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Center(child: _commonBadge()),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (word.partOfSpeech.trim().isNotEmpty) ...[
            Text(
              word.partOfSpeech,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                fontSize: 16,
                height: 1.12,
                color: softTextGray,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 7),
          ],
          if (definitions.isEmpty)
            const Text(
              'No definitions yet',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 16,
                height: 1.2,
                color: softTextGray,
              ),
            )
          else
            ...definitions.asMap().entries.map((entry) {
              return _definitionRow(
                index: entry.key,
                definition: entry.value,
                relatedTerms: entry.key == definitions.length - 1
                    ? word.relatedTerms
                    : const [],
              );
            }),
          if (extraDefinitions.isNotEmpty) _moreMeaningsBlock(extraDefinitions),
        ],
      ),
    );
  }

  Widget _wordTitleLine(Term word) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      runSpacing: 3,
      children: [
        Text(
          word.reading,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            fontSize: 27,
            height: 1,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        if (word.hasKanjiBracketText)
          Text(
            '【${word.kanjiBracketText}】',
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              fontSize: 23,
              height: 1,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
      ],
    );
  }

  Widget _definitionRow({
    required int index,
    required String definition,
    required List<String> relatedTerms,
  }) {
    final label = _definitionLabel(index);

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 17,
            height: 17,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: softTextGray,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                label,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1,
                  color: softTextGray,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              textScaler: TextScaler.noScaling,
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 17.5,
                  height: 1.22,
                  color: Colors.black,
                  fontWeight: FontWeight.w400,
                ),
                children: [
                  TextSpan(text: definition),
                  if (relatedTerms.isNotEmpty)
                    TextSpan(
                      text: ' (see also: ${relatedTerms.join(', ')})',
                      style: const TextStyle(color: softTextGray),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moreMeaningsBlock(List<String> extraDefinitions) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                showMoreMeanings = !showMoreMeanings;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    showMoreMeanings
                        ? 'Hide meanings'
                        : 'More meanings (${extraDefinitions.length})',
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      fontSize: 15.5,
                      height: 1,
                      color: accentBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    showMoreMeanings
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 21,
                    color: accentBlue,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _extraMeaningsPanel(extraDefinitions),
            crossFadeState: showMoreMeanings
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }

  Widget _extraMeaningsPanel(List<String> extraDefinitions) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: softBlueFill,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: sectionColor,
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: extraDefinitions.asMap().entries.map((entry) {
          final isLast = entry.key == extraDefinitions.length - 1;

          return _extraMeaningRow(
            definition: entry.value,
            isLast: isLast,
          );
        }).toList(),
      ),
    );
  }

  Widget _extraMeaningRow({
    required String definition,
    required bool isLast,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: SizedBox(
              width: 4.5,
              height: 4.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: softTextGray,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              definition,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.22,
                color: Colors.black,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _commonBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accentBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Common',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.1,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _noteSection(Term word) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Note'),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
          child: noteLoaded ? _noteBody() : _loadingNoteBody(),
        ),
      ],
    );
  }

  Widget _loadingNoteBody() {
    return const Text(
      'Loading note...',
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: 16,
        height: 1.15,
        color: softTextGray,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  Widget _noteBody() {
    if (isEditingNote) {
      return _noteEditor();
    }

    final hasNote = noteText.trim().isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _startEditingNote,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          hasNote ? noteText : 'Write a note',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 16,
            height: 1.2,
            color: hasNote ? Colors.black : accentBlue,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _noteEditor() {
    final hasTypedNote = noteController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: noteController,
          focusNode: noteFocusNode,
          maxLength: maxNoteCharacters,
          minLines: 3,
          maxLines: 7,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          cursorColor: accentBlue,
          style: const TextStyle(
            fontSize: 16,
            height: 1.2,
            color: Colors.black,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: 'Write a note',
            hintStyle: const TextStyle(
              color: softTextGray,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: softBlueFill,
            counterStyle: const TextStyle(
              fontSize: 12,
              height: 1,
              color: softTextGray,
            ),
            contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                color: sectionColor,
                width: 1.4,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                color: accentBlue,
                width: 1.6,
              ),
            ),
          ),
          onChanged: (value) {
            setState(() {
              noteText = value;
            });
          },
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            if (hasTypedNote)
              _noteTextButton(
                label: 'Clear',
                color: softTextGray,
                onTap: _clearNote,
              ),
            const Spacer(),
            _noteDoneButton(),
          ],
        ),
      ],
    );
  }

  Widget _noteTextButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          label,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 15,
            height: 1,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _noteDoneButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () async {
        await _saveNoteFromController(closeEditor: true);

        if (!mounted) return;

        FocusScope.of(context).unfocus();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
        decoration: BoxDecoration(
          color: accentBlue,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'Done',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 14.5,
            height: 1,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _kanjiSection(Term word) {
    final canOpenKanjiDetails = word.hasKanjiDetails;
    final firstCharacter = _firstKanjiCharacter(_primaryKanjiText(word));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Kanji'),
        InkWell(
          onTap: canOpenKanjiDetails ? () => openKanjiDetail(word) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 11),
            child: Row(
              children: [
                SizedBox(
                  width: 49,
                  child: Text(
                    firstCharacter,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      fontSize: 32,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (word.kanjiMeaning.trim().isNotEmpty)
                        Text(
                          word.kanjiMeaning,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.14,
                            color: Colors.black,
                          ),
                        ),
                      if (word.kunyomi.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            word.kunyomi.join(', '),
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.14,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      if (word.onyomi.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            word.onyomi.join(', '),
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.14,
                              color: Colors.black,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (canOpenKanjiDetails)
                  const Icon(
                    Icons.chevron_right,
                    size: 27,
                    color: softTextGray,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _examplesSection(Term word) {
    final examples = word.examples;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Examples'),
        if (examples.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 15, 22, 17),
            child: Text(
              'No examples yet',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 15.5,
                color: softTextGray,
              ),
            ),
          )
        else
          ...examples.asMap().entries.map((entry) {
            final isLast = entry.key == examples.length - 1;
            return _exampleRow(
              example: entry.value,
              showDivider: !isLast,
            );
          }),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 13, 22, 0),
          child: Text(
            'More Examples',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 16,
              height: 1,
              color: accentBlue.withValues(alpha: 0.72),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _exampleRow({
    required DictionaryExample example,
    required bool showDivider,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      example.reading,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.15,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      example.japanese,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.24,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      example.english,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.18,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 27,
                color: softTextGray,
              ),
            ],
          ),
          if (showDivider)
            const Padding(
              padding: EdgeInsets.only(top: 13),
              child: Divider(
                height: 1,
                thickness: 1,
                color: dividerColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      width: double.infinity,
      color: sectionColor,
      padding: const EdgeInsets.fromLTRB(22, 5, 22, 5),
      child: Text(
        title,
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _topActionPill() {
    return Container(
      height: GakujiTopBar.buttonSize,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _topActionButton(
            icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
            iconColor: isSaved ? Colors.black : softTextGray,
            onTap: toggleDirectSaveDeck,
          ),
          const SizedBox(width: 2),
          _topActionButton(
            icon: Icons.menu_book_outlined,
            iconColor: Colors.black,
            onTap: openDeckPicker,
          ),
        ],
      ),
    );
  }

  Widget _topActionButton({
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: GakujiTopBar.buttonSize - 4,
      height: GakujiTopBar.buttonSize,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(
            icon,
            size: 26,
            color: iconColor,
          ),
        ),
      ),
    );
  }

  List<String> _extraRawDefinitions(Term word) {
    final displayDefinitions = word.displayDefinitions;

    return word.rawDefinitions.where((rawDefinition) {
      return !_definitionIsCovered(
        rawDefinition: rawDefinition,
        displayDefinitions: displayDefinitions,
      );
    }).toList();
  }

  bool _definitionIsCovered({
    required String rawDefinition,
    required List<String> displayDefinitions,
  }) {
    final raw = _normalizedDefinition(rawDefinition);

    if (raw.isEmpty) return true;

    return displayDefinitions.any((displayDefinition) {
      final display = _normalizedDefinition(displayDefinition);

      if (display == raw) return true;

      final pieces = display
          .split(';')
          .map(_normalizedDefinition)
          .where((piece) => piece.isNotEmpty)
          .toList();

      return pieces.contains(raw);
    });
  }

  String _normalizedDefinition(String definition) {
    return definition.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  String _definitionLabel(int index) {
    if (index >= 0 && index < 26) {
      return String.fromCharCode(65 + index);
    }

    return '•';
  }

  String _topBarTitle(Term word) {
    final primaryKanji = _primaryKanjiText(word);

    if (primaryKanji.isNotEmpty) return primaryKanji;

    return word.reading;
  }

  String _primaryKanjiText(Term word) {
    if (word.kanjiSpellings.isNotEmpty) {
      return word.kanjiSpellings.first;
    }

    return '';
  }

  bool _shouldShowKanjiSection(Term word) {
    return _firstKanjiCharacter(_primaryKanjiText(word)).isNotEmpty &&
        word.hasKanjiDetails;
  }

  String _firstKanjiCharacter(String text) {
    for (final codePoint in text.runes) {
      final character = String.fromCharCode(codePoint);

      if (_containsKanji(character)) {
        return character;
      }
    }

    return '';
  }

  bool _containsKanji(String text) {
    return RegExp(r'[\u4E00-\u9FFF]').hasMatch(text);
  }
}

enum _DeckSheetAction {
  saveToDeck,
  setDirectSaveDeck,
}

class _DeckSheetResult {
  final _DeckSheetAction action;
  final Deck deck;

  const _DeckSheetResult({
    required this.action,
    required this.deck,
  });
}

class _DeckSaveSheet extends StatefulWidget {
  final List<Deck> decks;
  final String directSaveDeckId;
  final bool Function(Deck deck) deckContainsWord;

  const _DeckSaveSheet({
    required this.decks,
    required this.directSaveDeckId,
    required this.deckContainsWord,
  });

  @override
  State<_DeckSaveSheet> createState() => _DeckSaveSheetState();
}

class _DeckSaveSheetState extends State<_DeckSaveSheet> {
  late final PageController pageController;

  @override
  void initState() {
    super.initState();

    pageController = PageController();
  }

  @override
  void dispose() {
    pageController.dispose();

    super.dispose();
  }

  void _showDirectSaveDecks() {
    pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOut,
    );
  }

  void _showSaveDecks() {
    pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = screenHeight * 0.52;

    return SafeArea(
      top: false,
      child: Container(
        height: sheetHeight,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(22),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
          child: PageView(
            controller: pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _saveToPanel(context),
              _directSavePanel(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _saveToPanel(BuildContext context) {
    return Column(
      children: [
        _sheetHandle(),
        _sheetTitle('Save to...'),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _showDirectSaveDecks,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: const Text(
                'Select direct save deck',
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1,
                  color: _DictionaryDetailPageState.accentBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const Divider(
          height: 1,
          color: _DictionaryDetailPageState.dividerColor,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: widget.decks.length,
            itemBuilder: (context, index) {
              final deck = widget.decks[index];
              final isSaved = widget.deckContainsWord(deck);
              final isDirectSaveDeck = deck.id == widget.directSaveDeckId;

              return _deckRow(
                deck: deck,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDirectSaveDeck)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Text(
                          'Direct',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1,
                            color: _DictionaryDetailPageState.accentBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (isSaved)
                      const Icon(
                        Icons.check,
                        color: _DictionaryDetailPageState.accentBlue,
                      ),
                  ],
                ),
                onTap: () {
                  Navigator.pop(
                    context,
                    _DeckSheetResult(
                      action: _DeckSheetAction.saveToDeck,
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

  Widget _directSavePanel(BuildContext context) {
    return Column(
      children: [
        _sheetHandle(),
        Padding(
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
                    onTap: _showSaveDecks,
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      size: 19,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const Expanded(
                child: Text(
                  'Select direct save deck',
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 18,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 0, 22, 12),
          child: Text(
            'The bookmark button saves terms to this deck.',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.15,
              color: _DictionaryDetailPageState.softTextGray,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const Divider(
          height: 1,
          color: _DictionaryDetailPageState.dividerColor,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: widget.decks.length,
            itemBuilder: (context, index) {
              final deck = widget.decks[index];
              final isSelected = deck.id == widget.directSaveDeckId;

              return _deckRow(
                deck: deck,
                trailing: isSelected
                    ? const Icon(
                        Icons.check_circle,
                        color: _DictionaryDetailPageState.accentBlue,
                      )
                    : const Icon(
                        Icons.circle_outlined,
                        color: _DictionaryDetailPageState.softTextGray,
                      ),
                onTap: () {
                  Navigator.pop(
                    context,
                    _DeckSheetResult(
                      action: _DeckSheetAction.setDirectSaveDeck,
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

  Widget _sheetHandle() {
    return Center(
      child: Container(
        width: 42,
        height: 5,
        margin: const EdgeInsets.only(top: 9, bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFD8D8D8),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _sheetTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        title,
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontSize: 18,
          height: 1,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _deckRow({
    required Deck deck,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      minVerticalPadding: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 22),
      title: Text(
        deck.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontSize: 16,
          height: 1.05,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      subtitle: Text(
        '${deck.terms.length} terms',
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontSize: 13,
          height: 1.2,
          color: _DictionaryDetailPageState.softTextGray,
          fontWeight: FontWeight.w400,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}