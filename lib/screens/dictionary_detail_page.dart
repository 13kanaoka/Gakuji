import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/deck_data.dart';
import '../data/review_card_data.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../services/deck_storage.dart';
import '../services/dictionary_service.dart';
import '../widgets/gakuji_faded_scroll.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import 'kanji_dictionary_detail_page.dart';
import 'sentence_detail_page.dart';
import '../services/gakuji_user_data_store.dart';

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
  static Color get sectionColor => GakujiColors.warmCard;
  static const Color accentBlue = Color(0xFF4D7EF7);
  static Color get dividerColor => GakujiColors.warmDivider;
  static Color get softTextGray => GakujiColors.mediumGray;
  static Color get softBlueFill => GakujiColors.warmCard;
  static Color get darkText => GakujiColors.darkGray;

  static const double topActionPillWidth = 92;
  static const int maxNoteCharacters = 400;
  static const int maxExamplesPerSense = 3;
  static const Duration topBarTitleFadeDuration =
      Duration(milliseconds: 180);
  static const String directSaveDeckPreferenceKey =
      'gakuji_direct_save_deck_id';

  late final TextEditingController noteController;
  late final FocusNode noteFocusNode;
  late final ScrollController pageScrollController;

  final GlobalKey entryTitleKey = GlobalKey();
  final GlobalKey scrollViewportKey = GlobalKey();

  Timer? savePopupTimer;

  bool isEditingNote = false;
  bool noteLoaded = false;
  bool showSavePopup = false;
  bool kanjiEntriesLoaded = false;
  bool showTopBarTitle = false;

  List<Term> kanjiEntries = const [];
  final Set<int> expandedExampleSenseIndexes = <int>{};
  int kanjiLoadRequestId = 0;

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
    pageScrollController = ScrollController();

    noteFocusNode.addListener(_handleNoteFocusChange);
    pageScrollController.addListener(_handlePageScroll);

    _loadSavedNote();
    _loadDirectSaveDeck();
    unawaited(_loadKanjiEntries());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateTopBarTitleVisibility();
    });
  }

  @override
  void didUpdateWidget(covariant DictionaryDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldSourceId = oldWidget.word.sourceId ?? oldWidget.word.id;

    if (oldSourceId != sourceId) {
      isEditingNote = false;
      noteLoaded = false;
      noteText = '';
      noteController.text = '';
      kanjiEntries = const [];
      kanjiEntriesLoaded = false;
      showTopBarTitle = false;
      expandedExampleSenseIndexes.clear();

      _loadSavedNote();
      unawaited(_loadKanjiEntries());

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (pageScrollController.hasClients) {
          pageScrollController.jumpTo(0);
        }

        _updateTopBarTitleVisibility();
      });
    }
  }

  @override
  void dispose() {
    savePopupTimer?.cancel();
    noteFocusNode.removeListener(_handleNoteFocusChange);
    pageScrollController.removeListener(_handlePageScroll);
    noteFocusNode.dispose();
    noteController.dispose();
    pageScrollController.dispose();

    super.dispose();
  }

  void _handlePageScroll() {
    _updateTopBarTitleVisibility();
  }

  void _updateTopBarTitleVisibility() {
    if (!mounted) return;

    final titleContext = entryTitleKey.currentContext;
    final viewportContext = scrollViewportKey.currentContext;

    if (titleContext == null || viewportContext == null) return;

    final titleRenderObject = titleContext.findRenderObject();
    final viewportRenderObject = viewportContext.findRenderObject();

    if (titleRenderObject is! RenderBox ||
        viewportRenderObject is! RenderBox ||
        !titleRenderObject.attached ||
        !viewportRenderObject.attached ||
        !titleRenderObject.hasSize ||
        !viewportRenderObject.hasSize) {
      return;
    }

    final titleBottom =
        titleRenderObject.localToGlobal(Offset.zero).dy +
            titleRenderObject.size.height;
    final viewportTop =
        viewportRenderObject.localToGlobal(Offset.zero).dy;
    final shouldShowTitle = titleBottom <= viewportTop + 0.5;

    if (showTopBarTitle == shouldShowTitle) return;

    setState(() {
      showTopBarTitle = shouldShowTitle;
    });
  }

  Future<void> _loadKanjiEntries() async {
    final requestId = ++kanjiLoadRequestId;
    final kanjiText = _primaryKanjiText(widget.word);

    if (!_containsKanji(kanjiText)) {
      if (!mounted || requestId != kanjiLoadRequestId) return;

      setState(() {
        kanjiEntries = const [];
        kanjiEntriesLoaded = true;
      });

      return;
    }

    final entries = await DictionaryService.getKanjiEntriesForText(kanjiText);

    if (!mounted || requestId != kanjiLoadRequestId) return;

    setState(() {
      kanjiEntries = entries;
      kanjiEntriesLoaded = true;
    });
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

  Future<bool> _handleSystemBack() async {
    await _handleBackTap();
    return false;
  }

  bool deckContainsWord(Deck deck) {
    return deck.terms.any((term) => term.sourceId == sourceId);
  }

  List<Term> _deckCopiesForWord(Deck deck) {
    return deck.terms
        .where((term) => term.sourceId == sourceId)
        .toList(growable: false);
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

  void scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
  }

  Future<void> _syncReviewCardsIfEnabled(Deck deck) async {
    final reviewEnabled = await DeckStorage.loadReviewEnabled(deck.id);

    if (!reviewEnabled) return;

    await createReviewCardsForDeck(deck);
  }

  Future<HybridCardMode?> _chooseHybridCardMode(Deck deck) {
    return showModalBottomSheet<HybridCardMode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _HybridCardModeSheet(
          deckName: deck.name,
        );
      },
    );
  }

  void _removeWordFromDeck(Deck deck) {
    final copies = _deckCopiesForWord(deck);

    for (final copy in copies) {
      deck.removeHybridCardMode(copy);
    }

    deck.terms.removeWhere((term) => term.sourceId == sourceId);
  }

  Term _addWordToDeck(
    Deck deck, {
    HybridCardMode? hybridMode,
  }) {
    final copiedWord = copiedWordForDeck(deck);

    deck.terms.add(copiedWord);

    if (deck.type == DeckType.hybrid) {
      deck.setHybridCardMode(
        copiedWord,
        hybridMode ?? HybridCardMode.both,
      );
    }

    return copiedWord;
  }

  String _hybridCardModeLabel(HybridCardMode mode) {
    switch (mode) {
      case HybridCardMode.reading:
        return 'Reading';
      case HybridCardMode.writing:
        return 'Writing';
      case HybridCardMode.both:
        return 'Reading + Writing';
    }
  }

  Future<void> toggleDirectSaveDeck() async {
    if (isEditingNote) {
      await _saveNoteFromController(closeEditor: true);
    }

    if (!mounted) return;

    final deck = directSaveDeck;
    final wasSaved = deckContainsWord(deck);
    HybridCardMode? selectedHybridMode;

    if (!wasSaved && deck.type == DeckType.hybrid) {
      selectedHybridMode = await _chooseHybridCardMode(deck);

      if (!mounted || selectedHybridMode == null) return;
    }

    setState(() {
      if (wasSaved) {
        _removeWordFromDeck(deck);
      } else {
        _addWordToDeck(
          deck,
          hybridMode: selectedHybridMode,
        );
      }
    });

    if (wasSaved) {
      _showSavePopup(
        'Removed from ${deck.name}',
        icon: Icons.close_rounded,
      );
    } else if (selectedHybridMode != null) {
      _showSavePopup(
        'Saved to ${deck.name} as '
        '${_hybridCardModeLabel(selectedHybridMode)}',
      );
    } else {
      _showSavePopup('Saved to ${deck.name}');
    }

    scheduleUserDataSave();
    await _syncReviewCardsIfEnabled(deck);
  }

  Future<void> _toggleWordInDeck(Deck deck) async {
    final wasSaved = deckContainsWord(deck);
    HybridCardMode? selectedHybridMode;

    if (!wasSaved && deck.type == DeckType.hybrid) {
      selectedHybridMode = await _chooseHybridCardMode(deck);

      if (!mounted || selectedHybridMode == null) return;
    }

    setState(() {
      if (wasSaved) {
        _removeWordFromDeck(deck);
      } else {
        _addWordToDeck(
          deck,
          hybridMode: selectedHybridMode,
        );
      }
    });

    if (wasSaved) {
      _showSavePopup(
        'Removed from ${deck.name}',
        icon: Icons.close_rounded,
      );
    } else if (selectedHybridMode != null) {
      _showSavePopup(
        'Saved to ${deck.name} as '
        '${_hybridCardModeLabel(selectedHybridMode)}',
      );
    } else {
      _showSavePopup('Saved to ${deck.name}');
    }

    scheduleUserDataSave();
    await _syncReviewCardsIfEnabled(deck);
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
        await _toggleWordInDeck(result.deck);
        break;
      case _DeckSheetAction.setDirectSaveDeck:
        await _setDirectSaveDeck(result.deck);
        break;
    }
  }


  void openKanjiDetail(Term kanjiEntry) {
    if (!kanjiEntry.hasKanjiDetails) return;

    if (isEditingNote) {
      unawaited(_saveNoteFromController(closeEditor: true));
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KanjiDictionaryDetailPage(
          kanjiEntry: kanjiEntry,
        ),
      ),
    );
  }


  void _openSentenceDetail({
    required DictionaryExample example,
    required int labelIndex,
  }) {
    if (isEditingNote) {
      unawaited(_saveNoteFromController(closeEditor: true));
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SentenceDetailPage(
          example: example,
          senseLabel: _definitionLabel(labelIndex),
          onTokenTap: _openSentenceToken,
        ),
      ),
    );
  }

  Future<void> _openSentenceToken(
    BuildContext pageContext,
    DictionaryExampleToken token,
  ) async {
    final termId = token.termId;

    if (termId == null || termId.trim().isEmpty) return;

    try {
      final term = await DictionaryService.getTermByIdAsync(termId);

      if (!pageContext.mounted) return;

      await Navigator.of(pageContext).push(
        MaterialPageRoute(
          builder: (_) => DictionaryDetailPage(word: term),
        ),
      );
    } catch (_) {
      if (!pageContext.mounted) return;

      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(
          content: Text('Dictionary entry unavailable.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        _handleSystemBack();
      },
      child: Scaffold(
        backgroundColor: GakujiColors.warmBackground,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  GakujiTopBar(
                    leftIcon: GakujiTopBar.backIcon,
                    leftIconSize: GakujiTopBar.backIconSize,
                    leftIconColor: GakujiColors.darkGray,
                    onLeftTap: _handleBackTap,
                    titleWidget: AnimatedOpacity(
                      opacity: showTopBarTitle ? 1 : 0,
                      duration: topBarTitleFadeDuration,
                      curve: Curves.easeOut,
                      child: Text(
                        _topBarTitle(word),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w500,
                          color: GakujiColors.darkGray,
                        ),
                      ),
                    ),
                    rightWidget: _topActionPill(),
                  ),
                  Expanded(
                    child: Container(
                      key: scrollViewportKey,
                      child: GakujiFadedScroll(
                        child: ListView(
                          controller: pageScrollController,
                          padding: const EdgeInsets.only(bottom: 110),
                          children: [
                            _entryHeader(word),
                            _noteSection(word),
                            if (_shouldShowKanjiSection(word)) _kanjiSection(),
                            _examplesSection(word),
                          ],
                        ),
                      ),
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
                  color: GakujiColors.warmCard,
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
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.12,
                          color: darkText,
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
    final senses = _definitionSenses(word);

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
              style: TextStyle(
                fontSize: 16,
                height: 1.12,
                color: softTextGray,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 7),
          ],
          if (senses.isEmpty)
             Text(
              'No definitions yet',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 16,
                height: 1.2,
                color: softTextGray,
              ),
            )
          else
            ...senses.asMap().entries.map((entry) {
              final sense = entry.value;

              return _definitionRow(
                index: entry.key,
                definition: sense.displayDefinition,
                relatedTerms: sense.relatedTerms,
              );
            }),
        ],
      ),
    );
  }

  Widget _wordTitleLine(Term word) {
    return Container(
      key: entryTitleKey,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 8,
        runSpacing: 3,
        children: [
          Text(
            word.reading,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 27,
              height: 1,
              fontWeight: FontWeight.w700,
              color: darkText,
            ),
          ),
          if (word.hasKanjiBracketText)
            Text(
              '【${word.kanjiBracketText}】',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 23,
                height: 1,
                fontWeight: FontWeight.w700,
                color: darkText,
              ),
            ),
        ],
      ),
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
                style: TextStyle(
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
                style: TextStyle(
                  fontSize: 17.5,
                  height: 1.22,
                  color: darkText,
                  fontWeight: FontWeight.w400,
                ),
                children: [
                  TextSpan(text: definition),
                  if (relatedTerms.isNotEmpty)
                    TextSpan(
                      text: ' (see also: ${relatedTerms.join(', ')})',
                      style: TextStyle(color: softTextGray),
                    ),
                ],
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
    return Text(
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
            color: hasNote ? darkText : softTextGray,
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
          style: TextStyle(
            fontSize: 16,
            height: 1.2,
            color: darkText,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: 'Write a note',
            hintStyle:  TextStyle(
              color: softTextGray,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: softBlueFill,
            counterStyle:  TextStyle(
              fontSize: 12,
              height: 1,
              color: softTextGray,
            ),
            contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide:  BorderSide(
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

  Widget _kanjiSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Kanji'),
        if (!kanjiEntriesLoaded)
           Padding(
            padding: EdgeInsets.fromLTRB(22, 15, 22, 16),
            child: Text(
              'Loading kanji...',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 15.5,
                color: softTextGray,
              ),
            ),
          )
        else if (kanjiEntries.isEmpty)
           Padding(
            padding: EdgeInsets.fromLTRB(22, 15, 22, 16),
            child: Text(
              'No kanji details found',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 15.5,
                color: softTextGray,
              ),
            ),
          )
        else
          ...kanjiEntries.asMap().entries.map((entry) {
            return _kanjiEntryRow(
              kanjiEntry: entry.value,
              showDivider: entry.key != kanjiEntries.length - 1,
            );
          }),
      ],
    );
  }

  Widget _kanjiEntryRow({
    required Term kanjiEntry,
    required bool showDivider,
  }) {
    final meaning = kanjiEntry.kanjiMeaning.trim().isNotEmpty
        ? kanjiEntry.kanjiMeaning.trim()
        : kanjiEntry.meaning.trim();
    final canOpenKanjiDetails = kanjiEntry.hasKanjiDetails;

    return InkWell(
      onTap: canOpenKanjiDetails
          ? () => openKanjiDetail(kanjiEntry)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 11, 22, 0),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 49,
                  child: Text(
                    kanjiEntry.kanji,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 32,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      color: darkText,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (meaning.isNotEmpty)
                        Text(
                          meaning,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.14,
                            color: darkText,
                          ),
                        ),
                      if (kanjiEntry.kunyomi.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            kanjiEntry.kunyomi.join(', '),
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.14,
                              color: softTextGray,
                            ),
                          ),
                        ),
                      if (kanjiEntry.onyomi.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            kanjiEntry.onyomi.join(', '),
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.14,
                              color: softTextGray,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (canOpenKanjiDetails)
                   Icon(
                    Icons.chevron_right,
                    size: 27,
                    color: softTextGray,
                  ),
              ],
            ),
            if (showDivider)
               Padding(
                padding: EdgeInsets.only(top: 11),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: dividerColor,
                ),
              )
            else
              const SizedBox(height: 11),
          ],
        ),
      ),
    );
  }

  Widget _examplesSection(Term word) {
    final senses = _definitionSenses(word);
    final exampleSenseEntries = senses
        .asMap()
        .entries
        .where((entry) => entry.value.examples.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Examples'),
        if (exampleSenseEntries.isEmpty)
           Padding(
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
          ...exampleSenseEntries.asMap().entries.map((groupEntry) {
            final indexedSense = groupEntry.value;

            return _exampleSenseGroup(
              labelIndex: indexedSense.key,
              sense: indexedSense.value,
              showBottomDivider:
                  groupEntry.key != exampleSenseEntries.length - 1,
            );
          }),
      ],
    );
  }

  Widget _exampleSenseGroup({
    required int labelIndex,
    required DictionarySense sense,
    required bool showBottomDivider,
  }) {
    final isExpanded = expandedExampleSenseIndexes.contains(sense.index);
    final visibleExamples = isExpanded
        ? sense.examples
        : sense.examples.take(maxExamplesPerSense).toList();
    final hiddenCount = sense.examples.length - visibleExamples.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 13, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _senseBadge(labelIndex),
          const SizedBox(height: 4),
          ...visibleExamples.asMap().entries.map((entry) {
            return _exampleRow(
              example: entry.value,
              labelIndex: labelIndex,
              showDivider: entry.key != visibleExamples.length - 1,
            );
          }),
          if (sense.examples.length > maxExamplesPerSense)
            _exampleExpansionButton(
              senseIndex: sense.index,
              isExpanded: isExpanded,
              hiddenCount: hiddenCount,
            ),
          if (showBottomDivider)
             Padding(
              padding: EdgeInsets.only(top: 13),
              child: Divider(
                height: 1,
                thickness: 1,
                color: dividerColor,
              ),
            )
          else
            const SizedBox(height: 13),
        ],
      ),
    );
  }

  Widget _senseBadge(int labelIndex) {
    return Container(
      width: 19,
      height: 19,
      margin: const EdgeInsets.only(top: 1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: softTextGray,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          _definitionLabel(labelIndex),
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 10.5,
            height: 1,
            color: softTextGray,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _exampleExpansionButton({
    required int senseIndex,
    required bool isExpanded,
    required int hiddenCount,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() {
          if (isExpanded) {
            expandedExampleSenseIndexes.remove(senseIndex);
          } else {
            expandedExampleSenseIndexes.add(senseIndex);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 6, 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isExpanded ? 'Show fewer' : 'More examples ($hiddenCount)',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 15,
                height: 1,
                color: softTextGray,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              isExpanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              size: 20,
              color: softTextGray,
            ),
          ],
        ),
      ),
    );
  }

  Widget _exampleRow({
    required DictionaryExample example,
    required int labelIndex,
    required bool showDivider,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openSentenceDetail(
              example: example,
              labelIndex: labelIndex,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (example.reading.trim().isNotEmpty) ...[
                          Text(
                            example.reading,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.15,
                              color: darkText,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          example.japanese,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.24,
                            color: darkText,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          example.english,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.18,
                            color: darkText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                   Icon(
                    Icons.chevron_right,
                    size: 27,
                    color: softTextGray,
                  ),
                ],
              ),
            ),
          ),
          if (showDivider)
             Padding(
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
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      decoration: BoxDecoration(
        color: GakujiColors.sectionHeader,
        border: Border(
          top: BorderSide(
            color: darkText.withValues(alpha: 0.16),
            width: 1,
          ),
          bottom: BorderSide(
            color: darkText.withValues(alpha: 0.16),
            width: 1,
          ),
        ),
      ),
      child: Text(
        title,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1,
          color: darkText,
        ),
      ),
    );
  }

  Widget _topActionPill() {
    return Container(
      height: GakujiTopBar.buttonSize,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _topActionButton(
            icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
            iconColor: isSaved ? darkText : softTextGray,
            onTap: toggleDirectSaveDeck,
          ),
          const SizedBox(width: 2),
          _topActionButton(
            icon: Icons.menu_book_outlined,
            iconColor: darkText,
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
      width: GakujiTopBar.buttonSize,
      height: GakujiTopBar.buttonSize,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(
            icon,
            size: 30,
            color: iconColor,
          ),
        ),
      ),
    );
  }

  List<DictionarySense> _definitionSenses(Term word) {
    return word.senses
        .where((sense) => sense.glosses.isNotEmpty)
        .toList(growable: false);
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
    return _containsKanji(_primaryKanjiText(word));
  }

  bool _containsKanji(String text) {
    return RegExp(r'[\u4E00-\u9FFF]').hasMatch(text);
  }
}

class _HybridCardModeSheet extends StatelessWidget {
  final String deckName;

  const _HybridCardModeSheet({
    required this.deckName,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        decoration: BoxDecoration(
          color: GakujiColors.warmBackground,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                margin: const EdgeInsets.only(top: 9, bottom: 13),
                decoration: BoxDecoration(
                  color: GakujiColors.softGray,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
             Text(
              'Choose card type',
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 19,
                height: 1,
                color: GakujiColors.darkGray,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'How should this term be studied in $deckName?',
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 14,
                height: 1.2,
                color: GakujiColors.mediumGray,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),
            _modeOption(
              context: context,
              mode: HybridCardMode.reading,
              icon: Icons.menu_book_rounded,
              color: GakujiColors.reading,
              title: 'Reading',
              description: 'Recognize the term and recall its meaning.',
            ),
            const SizedBox(height: 11),
            _modeOption(
              context: context,
              mode: HybridCardMode.writing,
              icon: Icons.edit_rounded,
              color: GakujiColors.writing,
              title: 'Writing',
              description: 'Produce and write the term from its prompt.',
            ),
            const SizedBox(height: 11),
            _modeOption(
              context: context,
              mode: HybridCardMode.both,
              icon: Icons.compare_arrows_rounded,
              color: GakujiColors.hybrid,
              title: 'Both',
              description: 'Create separate Reading and Writing cards.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeOption({
    required BuildContext context,
    required HybridCardMode mode,
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Material(
      color: GakujiColors.warmCard,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pop(context, mode),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: GakujiColors.warmDivider,
              width: 1.4,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: color,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1,
                        color: GakujiColors.darkGray,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.2,
                        color: GakujiColors.mediumGray,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
               Icon(
                Icons.chevron_right_rounded,
                size: 27,
                color: GakujiColors.mediumGray,
              ),
            ],
          ),
        ),
      ),
    );
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
      _DeckSheetResult(
        action: _DeckSheetAction.saveToDeck,
        deck: newDeck,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final sheetHeight = screenHeight * 0.52;

    return SafeArea(
      top: false,
      bottom: false,
      child: AnimatedPadding(
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
    return Column(
      children: [
        _sheetHandle(),
        _sheetTitle('Save to...'),
        _createDeckNavButton(),
        _directSaveNavButton(),
         Divider(
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
                       Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Text(
                          'Direct',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1,
                            color: _DictionaryDetailPageState.softTextGray,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (isSaved)
                      const Icon(
                        Icons.check_circle,
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

  Widget _createDeckNavButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: Material(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _showCreateDeckPanel,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
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
                  color: _DictionaryDetailPageState.accentBlue,
                ),
                SizedBox(width: 13),
                Expanded(
                  child: Text(
                    'Create new deck',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1,
                      color: _DictionaryDetailPageState.darkText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 27,
                  color: _DictionaryDetailPageState.softTextGray,
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
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Material(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _showDirectSaveDecks,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
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
                  color: _DictionaryDetailPageState.accentBlue,
                ),
                SizedBox(width: 13),
                Expanded(
                  child: Text(
                    'Select direct save deck',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1,
                      color: _DictionaryDetailPageState.darkText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 27,
                  color: _DictionaryDetailPageState.softTextGray,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _directSavePanel(BuildContext context) {
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
              color: _DictionaryDetailPageState.softTextGray,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
         Divider(
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
                    :  Icon(
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
                  color: _DictionaryDetailPageState.darkText,
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
                color: _DictionaryDetailPageState.darkText,
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
        color: _DictionaryDetailPageState.darkText,
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
          cursorColor: _DictionaryDetailPageState.accentBlue,
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
            color: _DictionaryDetailPageState.darkText,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            isCollapsed: true,
            hintText: 'Enter deck name',
            hintStyle: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: _DictionaryDetailPageState.softTextGray,
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
            color: _DictionaryDetailPageState.softTextGray,
            size: 30,
          ),
          style: TextStyle(
            fontSize: 17,
            height: 1,
            fontWeight: FontWeight.w500,
            color: _DictionaryDetailPageState.darkText,
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
        color: _DictionaryDetailPageState.accentBlue,
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        title,
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 18,
          height: 1,
          fontWeight: FontWeight.w700,
          color: _DictionaryDetailPageState.darkText,
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
        style: TextStyle(
          fontSize: 16,
          height: 1.05,
          fontWeight: FontWeight.w600,
          color: _DictionaryDetailPageState.darkText,
        ),
      ),
      subtitle: Text(
        '${deck.terms.length} terms',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
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