import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gakuji/data/seed/deck_seed.dart';
import 'package:gakuji/data/state/recent_deck_data.dart';
import 'package:gakuji/data/review/review_card_data.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/data/decks/deck_storage.dart';
import 'package:gakuji/data/dictionary/dictionary_service.dart';
import 'package:gakuji/data/dictionary/dictionary_note_service.dart';
import 'package:gakuji/data/sync/gakuji_user_data_store.dart';
import 'package:gakuji/core/widgets/gakuji_faded_scroll.dart';
import 'package:gakuji/features/decks/widgets/gakuji_deck_save_sheet.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/features/dictionary/dictionary_detail_page.dart';
import 'package:gakuji/features/dictionary/kanji_components_page.dart';

class KanjiDictionaryDetailPage extends StatefulWidget {
  final Term kanjiEntry;

  const KanjiDictionaryDetailPage({
    super.key,
    required this.kanjiEntry,
  });

  @override
  State<KanjiDictionaryDetailPage> createState() =>
      _KanjiDictionaryDetailPageState();
}

class _KanjiDictionaryDetailPageState
    extends State<KanjiDictionaryDetailPage> {
  static Color get sectionColor => GakujiColors.warmCard;
  static const Color accentBlue = GakujiColors.reading;
  static Color get dividerColor => GakujiColors.warmDivider;
  static Color get softTextGray => GakujiColors.mediumGray;
  static Color get darkText => GakujiColors.darkGray;
  static Color get inputFill => GakujiColors.warmCard;

  static const int maxNoteCharacters = DictionaryNoteService.maxCharacters;
  static const Duration topBarTitleFadeDuration =
      Duration(milliseconds: 180);
  static const String directSaveDeckPreferenceKey =
      'gakuji_direct_save_deck_id';

  late final TextEditingController noteController;
  late final FocusNode noteFocusNode;
  late final ScrollController pageScrollController;

  final GlobalKey kanjiTitleKey = GlobalKey();
  final GlobalKey scrollViewportKey = GlobalKey();

  Timer? savePopupTimer;

  bool noteLoaded = false;
  bool isEditingNote = false;
  bool compoundsLoaded = false;
  bool strokeDataLoaded = false;
  bool componentTreeLoaded = false;
  bool showTopBarTitle = false;
  bool showSavePopup = false;

  String noteText = '';
  String? directSaveDeckId;
  String savePopupText = '';
  IconData savePopupIcon = Icons.check_circle;

  List<Term> compoundTerms = const [];
  List<KanjiComponentNode> componentTree = const [];
  KanjiStrokeData? strokeData;
  int strokeLoadRequestId = 0;
  int componentLoadRequestId = 0;

  Term get entry => widget.kanjiEntry;

  String get sourceId => entry.sourceId ?? entry.id;


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

  bool get isSaved => deckContainsEntry(directSaveDeck);

  @override
  void initState() {
    super.initState();

    noteController = TextEditingController();
    noteFocusNode = FocusNode();
    pageScrollController = ScrollController();

    noteFocusNode.addListener(_handleNoteFocusChange);
    pageScrollController.addListener(_handlePageScroll);

    unawaited(_loadSavedNote());
    unawaited(_loadDirectSaveDeck());
    unawaited(_loadStrokeData());
    unawaited(_loadComponentTree());
    unawaited(_loadCompounds());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateTopBarTitleVisibility();
    });
  }

  @override
  void didUpdateWidget(covariant KanjiDictionaryDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldSourceId = oldWidget.kanjiEntry.sourceId ?? oldWidget.kanjiEntry.id;

    if (oldSourceId == sourceId) return;

    noteLoaded = false;
    isEditingNote = false;
    compoundsLoaded = false;
    strokeDataLoaded = false;
    componentTreeLoaded = false;
    showTopBarTitle = false;
    noteText = '';
    compoundTerms = const [];
    componentTree = const [];
    strokeData = null;
    noteController.clear();

    unawaited(_loadSavedNote());
    unawaited(_loadStrokeData());
    unawaited(_loadComponentTree());
    unawaited(_loadCompounds());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (pageScrollController.hasClients) {
        pageScrollController.jumpTo(0);
      }

      _updateTopBarTitleVisibility();
    });
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

    final titleContext = kanjiTitleKey.currentContext;
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

  Future<void> _loadSavedNote() async {
    final initialNote = await DictionaryNoteService.loadForTerm(entry);

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

  Future<void> _loadStrokeData() async {
    final requestId = ++strokeLoadRequestId;
    final character = _displayCharacter;

    if (character.isEmpty) {
      if (!mounted || requestId != strokeLoadRequestId) return;

      setState(() {
        strokeData = null;
        strokeDataLoaded = true;
      });

      return;
    }

    final loadedStrokeData =
        await DictionaryService.getKanjiStrokeData(character);

    if (!mounted || requestId != strokeLoadRequestId) return;

    setState(() {
      strokeData = loadedStrokeData;
      strokeDataLoaded = true;
    });
  }


  Future<void> _loadComponentTree() async {
    final requestId = ++componentLoadRequestId;
    final character = _displayCharacter;

    if (character.isEmpty) {
      if (!mounted || requestId != componentLoadRequestId) return;

      setState(() {
        componentTree = const [];
        componentTreeLoaded = true;
      });
      return;
    }

    final loadedTree =
        await DictionaryService.getKanjiComponentTree(character);

    if (!mounted || requestId != componentLoadRequestId) return;

    setState(() {
      componentTree = loadedTree;
      componentTreeLoaded = true;
    });
  }

  void _openComponentsPage() {
    if (componentTree.isEmpty) return;

    Navigator.of(context).push(
      GakujiPageRoute(
        builder: (_) => KanjiComponentsPage(
          rootEntry: entry,
          componentTree: componentTree,
        ),
      ),
    );
  }


  void _openStrokeDetailSheet() {
    final data = strokeData;

    if (data == null || data.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.56),
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.80,
          child: _KanjiStrokeDetailSheet(
            character: _displayCharacter,
            data: data,
          ),
        );
      },
    );
  }

  Future<void> _loadCompounds() async {
    final character = _displayCharacter;

    if (character.isEmpty) {
      if (!mounted) return;

      setState(() {
        compoundTerms = const [];
        compoundsLoaded = true;
      });

      return;
    }

    final results = await DictionaryService.search(character, limit: 100);
    final seenIds = <String>{};
    final compounds = <Term>[];

    for (final term in results) {
      if (term.id == entry.id || term.partOfSpeech == 'kanji') continue;
      if (!term.kanji.contains(character)) continue;
      if (term.kanji.runes.length <= 1) continue;
      if (!seenIds.add(term.id)) continue;

      compounds.add(term);

      if (compounds.length >= 24) break;
    }

    if (!mounted) return;

    setState(() {
      compoundTerms = compounds;
      compoundsLoaded = true;
    });
  }

  void _handleNoteFocusChange() {
    if (!noteFocusNode.hasFocus && isEditingNote) {
      unawaited(_saveNoteFromController(closeEditor: true));
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
    final savedNote = await DictionaryNoteService.saveForTerm(
      term: entry,
      note: noteController.text,
    );

    if (!mounted) return;

    setState(() {
      noteText = savedNote;
      noteController.text = savedNote;

      if (closeEditor) {
        isEditingNote = false;
      }
    });
  }

  Future<void> _clearNote() async {
    noteController.clear();

    final savedNote = await DictionaryNoteService.saveForTerm(
      term: entry,
      note: '',
    );

    if (!mounted) return;

    setState(() {
      noteText = savedNote;
      isEditingNote = false;
    });

    FocusScope.of(context).unfocus();
  }

  bool deckContainsEntry(Deck deck) {
    return deck.terms.any((term) => term.sourceId == sourceId);
  }

  Term copiedEntryForDeck(Deck deck) {
    return Term.deckCopyFrom(
      entry,
      id: '${deck.id}_${sourceId}_${DateTime.now().microsecondsSinceEpoch}',
      marked: false,
    ).copyWith(note: noteText);
  }

  Future<void> _syncReviewCardsIfEnabled(Deck deck) async {
    final reviewEnabled = await DeckStorage.loadReviewEnabled(deck.id);

    if (!reviewEnabled) return;

    await createReviewCardsForDeck(deck);
  }

  Future<void> toggleDirectSaveDeck() async {
    final deck = directSaveDeck;
    final wasSaved = deckContainsEntry(deck);

    setState(() {
      if (wasSaved) {
        deck.terms.removeWhere((term) => term.sourceId == sourceId);
      } else {
        deck.terms.add(copiedEntryForDeck(deck));
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

    GakujiUserDataStore.scheduleSave();
    await markDeckOpenedRecently(deck.id);
    await _syncReviewCardsIfEnabled(deck);
  }

  Future<void> _toggleEntryInDeck(Deck deck) async {
    final wasSaved = deckContainsEntry(deck);

    setState(() {
      if (wasSaved) {
        deck.terms.removeWhere((term) => term.sourceId == sourceId);
      } else {
        deck.terms.add(copiedEntryForDeck(deck));
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

    GakujiUserDataStore.scheduleSave();
    await markDeckOpenedRecently(deck.id);
    await _syncReviewCardsIfEnabled(deck);
  }

  Future<void> _setDirectSaveDeck(Deck deck) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(directSaveDeckPreferenceKey, deck.id);
    await markDeckOpenedRecently(deck.id);

    if (!mounted) return;

    setState(() {
      directSaveDeckId = deck.id;
    });

    _showSavePopup('Direct save deck: ${deck.name}');
  }

  Future<void> openDeckPicker() async {
    if (isEditingNote) {
      await _saveNoteFromController(closeEditor: true);
    }

    if (!mounted) return;

    await loadRecentlyOpenedDeckIds();

    if (!mounted) return;

    final result = await showGakujiDeckSaveSheet(
      context: context,
      decks: decks,
      directSaveDeckId: directSaveDeck.id,
      deckContainsTerm: deckContainsEntry,
    );

    if (!mounted || result == null) return;

    switch (result.action) {
      case GakujiDeckSheetAction.saveToDeck:
        await _toggleEntryInDeck(result.deck);
        break;
      case GakujiDeckSheetAction.setDirectSaveDeck:
        await _setDirectSaveDeck(result.deck);
        break;
    }
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

  Future<void> _handleBackTap() async {
    if (isEditingNote) {
      await _saveNoteFromController(closeEditor: true);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<bool> _handleSystemBack() async {
    await _handleBackTap();
    return false;
  }

  void openCompound(Term compound) {
    Navigator.push(
      context,
      GakujiPageRoute(
        builder: (_) => DictionaryDetailPage(word: compound),
      ),
    );
  }

  String get _displayCharacter {
    if (entry.kanji.isEmpty) return '';

    return String.fromCharCode(entry.kanji.runes.first);
  }

  @override
  Widget build(BuildContext context) {
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
                    leftIconColor: darkText,
                    onLeftTap: _handleBackTap,
                    titleWidget: AnimatedOpacity(
                      opacity: showTopBarTitle ? 1 : 0,
                      duration: topBarTitleFadeDuration,
                      curve: Curves.easeOut,
                      child: Text(
                        _displayCharacter,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.dictionaryTopBarTitle.copyWith(
                          color: darkText,
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
                            _kanjiHeader(),
                            _readingsSection(),
                            _noteSection(),
                            _infoSection(),
                            _compoundsSection(),
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

  Widget _kanjiHeader() {
    final meaning = entry.kanjiMeaning.trim().isNotEmpty
        ? entry.kanjiMeaning.trim()
        : entry.meaning.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openStrokeDetailSheet,
                child: SizedBox(
                  key: kanjiTitleKey,
                  width: 90,
                  child: Text(
                    _displayCharacter,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.dictionaryKanjiDisplay.copyWith(
                      fontSize: 65,
                      color: darkText,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openStrokeDetailSheet,
                  child: _strokeOrderPanel(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (meaning.isNotEmpty) _infoRow('Meaning', meaning),
        ],
      ),
    );
  }

  Widget _strokeOrderPanel() {
    if (!strokeDataLoaded) {
      return const SizedBox(
        height: 104,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: accentBlue,
            ),
          ),
        ),
      );
    }

    final data = strokeData;

    if (data == null || data.isEmpty) {
      return Container(
        height: 104,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: GakujiColors.warmCard,
          border: Border.all(
            color: dividerColor,
            width: 1,
          ),
        ),
        child: Text(
          'No stroke data',
          textScaler: TextScaler.noScaling,
          style: GakujiText.dictionaryDetailBody.copyWith(
            color: softTextGray,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 5;
        const spacing = 4.0;
        final boxWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: List.generate(data.strokes.length, (index) {
            final visibleStrokeCount = index + 1;

            return Container(
              width: boxWidth,
              height: boxWidth,
              decoration: BoxDecoration(
                color: GakujiColors.warmCard,
                border: Border.all(
                  color: dividerColor,
                  width: 1,
                ),
              ),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: CustomPaint(
                      painter: _StrokeGuidePainter(),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(3.5),
                      child: SvgPicture.string(
                        _strokeFrameSvg(
                          data: data,
                          visibleStrokeCount: visibleStrokeCount,
                        ),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 3,
                    left: 4,
                    child: Text(
                      '$visibleStrokeCount',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: softTextGray,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }

  String _strokeFrameSvg({
    required KanjiStrokeData data,
    required int visibleStrokeCount,
  }) {
    final safeCount = visibleStrokeCount.clamp(0, data.strokes.length).toInt();
    final buffer = StringBuffer()
      ..write(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="${_escapeSvgAttribute(data.viewBox)}">',
      )
      ..write(
        '<g fill="none" stroke-linecap="round" '
        'stroke-linejoin="round" stroke-width="3.4">',
      );

    for (var index = 0; index < safeCount; index++) {
      final stroke = data.strokes[index];
      final isNewestStroke = index == safeCount - 1;
      final strokeColor = isNewestStroke
          ? '#5B84B8'
          : (GakujiColors.isDarkMode ? '#F1EDE5' : '#414247');

      buffer
        ..write('<path stroke="$strokeColor" d="')
        ..write(_escapeSvgAttribute(stroke.pathData))
        ..write('"/>');
    }

    buffer.write('</g></svg>');

    return buffer.toString();
  }

  String _escapeSvgAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  Widget _readingsSection() {
    final hasReadings = entry.onyomi.isNotEmpty ||
        entry.kunyomi.isNotEmpty ||
        entry.nanori.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Readings'),
        if (!hasReadings)
           Padding(
            padding: EdgeInsets.fromLTRB(22, 15, 22, 17),
            child: Text(
              'No readings listed',
              textScaler: TextScaler.noScaling,
              style: GakujiText.dictionaryDetailBody.copyWith(
                color: softTextGray,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 15),
            child: Column(
              children: [
                if (entry.onyomi.isNotEmpty)
                  _readingRow('On', entry.onyomi.join('、')),
                if (entry.kunyomi.isNotEmpty)
                  _readingRow('Kun', entry.kunyomi.join('、')),
                if (entry.nanori.isNotEmpty)
                  _readingRow('Nanori', entry.nanori.join('、')),
              ],
            ),
          ),
      ],
    );
  }

  Widget _readingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.dictionaryDetailBody.copyWith(
                height: 1.22,
                color: softTextGray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textScaler: TextScaler.noScaling,
              style: GakujiText.dictionaryDetailBody.copyWith(
                height: 1.22,
                color: darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteSection() {
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
      style: GakujiText.dictionaryDetailBody.copyWith(
        height: 1.15,
        color: softTextGray,
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
          style: GakujiText.dictionaryDetailBody.copyWith(
            height: 1.2,
            color: hasNote ? darkText : softTextGray,
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
          style: GakujiText.dictionaryDetailBody.copyWith(
            height: 1.2,
            color: darkText,
          ),
          decoration: InputDecoration(
            hintText: 'Add a personal definition, example, or note',
            hintStyle:  TextStyle(color: softTextGray),
            filled: true,
            fillColor: inputFill,
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
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _clearNote,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Text(
                    'Clear',
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.dictionaryDetailBody.copyWith(
                      color: softTextGray,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            const Spacer(),
            InkWell(
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
                child: Text(
                  'Done',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.dictionaryDetailBody.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoSection() {
    final rows = <MapEntry<String, String>>[];

    void addInfo(String label, String? value) {
      final cleanedValue = value?.trim() ?? '';

      if (cleanedValue.isNotEmpty) {
        rows.add(MapEntry(label, cleanedValue));
      }
    }

    addInfo('Strokes', entry.strokeCount?.toString());
    addInfo('Grade', entry.grade?.toString());
    addInfo(
      'JLPT',
      entry.jlptLevel == null || entry.jlptLevel!.trim().isEmpty
          ? null
          : 'N${entry.jlptLevel}',
    );
    addInfo('Frequency', entry.frequency?.toString());
    addInfo('Radical', DictionaryService.formatRadical(entry.radical));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Info'),
        if (rows.isEmpty &&
            (!componentTreeLoaded || componentTree.isEmpty))
           Padding(
            padding: EdgeInsets.fromLTRB(22, 15, 22, 17),
            child: Text(
              'No additional information',
              textScaler: TextScaler.noScaling,
              style: GakujiText.dictionaryDetailBody.copyWith(
                color: softTextGray,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 9, 22, 12),
            child: Column(
              children: [
                ...rows.map(
                  (row) => _infoRow(row.key, row.value),
                ),
                if (componentTreeLoaded && componentTree.isNotEmpty)
                  _componentsInfoRow(),
              ],
            ),
          ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 98,
            child: Text(
              '$label:',
              textScaler: TextScaler.noScaling,
              style: GakujiText.dictionaryDetailBody.copyWith(
                height: 1.2,
                color: accentBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textScaler: TextScaler.noScaling,
              style: GakujiText.dictionaryDetailBody.copyWith(
                height: 1.2,
                color: darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _componentsInfoRow() {
    final componentLabel = componentTree
        .map((node) => node.element.trim())
        .where((value) => value.isNotEmpty)
        .join('  ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openComponentsPage,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 98,
              child: Text(
                'Components:',
                textScaler: TextScaler.noScaling,
                style: GakujiText.dictionaryDetailBody.copyWith(
                  height: 1.2,
                  color: accentBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                componentLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: GakujiText.dictionaryDetailBody.copyWith(
                  height: 1.2,
                  color: darkText,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 26,
              color: softTextGray,
            ),
          ],
        ),
      ),
    );
  }

  Widget _compoundsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Compounds'),
        if (!compoundsLoaded)
           Padding(
            padding: EdgeInsets.fromLTRB(22, 15, 22, 17),
            child: Text(
              'Loading words...',
              textScaler: TextScaler.noScaling,
              style: GakujiText.dictionaryDetailBody.copyWith(
                color: softTextGray,
              ),
            ),
          )
        else if (compoundTerms.isEmpty)
           Padding(
            padding: EdgeInsets.fromLTRB(22, 15, 22, 17),
            child: Text(
              'No words found',
              textScaler: TextScaler.noScaling,
              style: GakujiText.dictionaryDetailBody.copyWith(
                color: softTextGray,
              ),
            ),
          )
        else
          ...compoundTerms.asMap().entries.map((compoundEntry) {
            return _compoundRow(
              compound: compoundEntry.value,
              showDivider: compoundEntry.key != compoundTerms.length - 1,
            );
          }),
      ],
    );
  }

  Widget _compoundRow({
    required Term compound,
    required bool showDivider,
  }) {
    final preferredWriting = compound.preferredSpelling.trim().isNotEmpty
        ? compound.preferredSpelling.trim()
        : compound.kanji.trim().isNotEmpty
            ? compound.kanji.trim()
            : compound.reading.trim();
    final reading = compound.reading.trim();
    final showReading = reading.isNotEmpty &&
        reading != preferredWriting &&
        RegExp(r'[\u4E00-\u9FFF]').hasMatch(preferredWriting);

    return Material(
      color: GakujiColors.warmBackground,
      child: InkWell(
        onTap: () => openCompound(compound),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 11, 22, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: preferredWriting,
                                style: GakujiText.termRowTitle.copyWith(
                                  height: 1,
                                  color: darkText,
                                ),
                              ),
                              if (showReading) const TextSpan(text: '  '),
                              if (showReading)
                                TextSpan(
                                  text: '【$reading】',
                                  style: GakujiText.termRowReading.copyWith(
                                    height: 1,
                                    color: accentBlue,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: TextScaler.noScaling,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          compound.cardMeaning,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.termRowMeaning.copyWith(
                            color: softTextGray,
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
              if (showDivider)
                 Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: dividerColor,
                  ),
                )
              else
                const SizedBox(height: 12),
            ],
          ),
        ),
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
        style: GakujiText.dictionaryDetailBody.copyWith(
          fontWeight: FontWeight.w600,
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
            size: GakujiTopBar.iconSize,
            color: iconColor,
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

}


class _KanjiStrokeDetailSheet extends StatefulWidget {
  final String character;
  final KanjiStrokeData data;

  const _KanjiStrokeDetailSheet({
    required this.character,
    required this.data,
  });

  @override
  State<_KanjiStrokeDetailSheet> createState() =>
      _KanjiStrokeDetailSheetState();
}

class _KanjiStrokeDetailSheetState extends State<_KanjiStrokeDetailSheet>
    with SingleTickerProviderStateMixin {
  static const int _strokeDrawMilliseconds = 820;
  static const int _strokePauseMilliseconds = 120;
  static const String _animationSpeedPreferenceKey =
      'gakuji_kanji_stroke_animation_speed';

  late final AnimationController _controller;
  bool isPlaying = false;
  double animationSpeed = 1.0;

  int get _baseAnimationDurationMilliseconds {
    final totalStrokes = widget.data.strokeCount;
    final pauseCount = (totalStrokes - 1).clamp(0, totalStrokes).toInt();
    return (totalStrokes * _strokeDrawMilliseconds) +
        (pauseCount * _strokePauseMilliseconds);
  }

  Duration get _animationDuration {
    final durationMilliseconds =
        (_baseAnimationDurationMilliseconds / animationSpeed).round();
    return Duration(
      milliseconds: durationMilliseconds > 0 ? durationMilliseconds : 1,
    );
  }

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );

    unawaited(_loadAnimationSpeed());
  }

  Future<void> _loadAnimationSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSpeed = prefs.getDouble(_animationSpeedPreferenceKey);

    if (!mounted || savedSpeed == null || isPlaying) return;

    final clampedSpeed = savedSpeed.clamp(0.5, 2.0).toDouble();

    setState(() {
      animationSpeed = clampedSpeed;
      _controller.duration = _animationDuration;
      _controller.value = 0;
    });
  }

  void _setAnimationSpeed(double speed) {
    if (isPlaying) return;

    setState(() {
      animationSpeed = speed;
      _controller.duration = _animationDuration;
      _controller.value = 0;
    });
  }

  Future<void> _saveAnimationSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_animationSpeedPreferenceKey, speed);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _playAnimation() async {
    if (isPlaying) return;

    setState(() {
      isPlaying = true;
    });

    await _controller.forward(from: 0);

    if (!mounted) return;

    setState(() {
      isPlaying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom > 0
        ? mediaQuery.padding.bottom + 14.0
        : 24.0;

    return Material(
      color: GakujiColors.warmBackground,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 9, 20, bottomPadding),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 47,
                height: 5,
                decoration: BoxDecoration(
                  color: GakujiColors.mediumGray.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.maxWidth.clamp(220.0, 286.0).toDouble();

                return SizedBox(
                  width: size,
                  height: size,
                  child: _KanjiStrokeAnimationCanvas(
                    data: widget.data,
                    controller: _controller,
                    isPlaying: isPlaying,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.speed_rounded,
                        size: 21,
                        color: GakujiColors.mediumGray,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: GakujiColors.reading,
                            inactiveTrackColor: GakujiColors.mediumGray
                                .withValues(alpha: 0.28),
                            thumbColor: GakujiColors.reading,
                            overlayColor:
                                GakujiColors.reading.withValues(alpha: 0.10),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                              disabledThumbRadius: 7,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 15,
                            ),
                          ),
                          child: Slider(
                            value: animationSpeed,
                            min: 0.5,
                            max: 2.0,
                            divisions: 6,
                            onChanged: isPlaying ? null : _setAnimationSpeed,
                            onChangeEnd: isPlaying
                                ? null
                                : (speed) =>
                                    unawaited(_saveAnimationSpeed(speed)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 50,
                  height: 50,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _playAnimation,
                      splashColor:
                          GakujiColors.reading.withValues(alpha: 0.08),
                      highlightColor:
                          GakujiColors.reading.withValues(alpha: 0.04),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 32,
                        color: isPlaying
                            ? GakujiColors.reading
                            : GakujiColors.mediumGray,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _largeStrokeOrderDiagram(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _largeStrokeOrderDiagram() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 4;
        const spacing = 7.0;
        final boxWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: List.generate(widget.data.strokes.length, (index) {
            final visibleStrokeCount = index + 1;

            return Container(
              width: boxWidth,
              height: boxWidth,
              decoration: BoxDecoration(
                color: GakujiColors.warmCard,
                border: Border.all(
                  color: GakujiColors.warmDivider,
                  width: 1,
                ),
              ),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: CustomPaint(
                      painter: _StrokeGuidePainter(),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: SvgPicture.string(
                        _strokeFrameSvg(visibleStrokeCount),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    left: 5,
                    child: Text(
                      '$visibleStrokeCount',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: GakujiColors.mediumGray,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }

  String _strokeFrameSvg(int visibleStrokeCount) {
    final safeCount = visibleStrokeCount
        .clamp(0, widget.data.strokes.length)
        .toInt();
    final buffer = StringBuffer()
      ..write(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="${_escapeSvgAttribute(widget.data.viewBox)}">',
      )
      ..write(
        '<g fill="none" stroke-linecap="round" '
        'stroke-linejoin="round" stroke-width="3.4">',
      );

    for (var index = 0; index < safeCount; index++) {
      final stroke = widget.data.strokes[index];
      final isNewestStroke = index == safeCount - 1;
      final strokeColor = isNewestStroke
          ? '#5B84B8'
          : (GakujiColors.isDarkMode ? '#F1EDE5' : '#414247');

      buffer
        ..write('<path stroke="$strokeColor" d="')
        ..write(_escapeSvgAttribute(stroke.pathData))
        ..write('"/>');
    }

    buffer.write('</g></svg>');
    return buffer.toString();
  }

  String _escapeSvgAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}

class _KanjiStrokeAnimationCanvas extends StatelessWidget {
  static const double _strokeTimelineUnits = 1.15;

  final KanjiStrokeData data;
  final AnimationController controller;
  final bool isPlaying;

  const _KanjiStrokeAnimationCanvas({
    required this.data,
    required this.controller,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: _StrokeGuidePainter(),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  final totalStrokes = data.strokeCount;
                  final totalTimeline = totalStrokes <= 1
                      ? 1.0
                      : ((totalStrokes - 1) * _strokeTimelineUnits) + 1.0;
                  final localTimeline = isPlaying
                      ? controller.value * totalTimeline
                      : totalTimeline + 1.0;

                  return CustomPaint(
                    painter: _KanjiAnimatedStrokePainter(
                      data: data,
                      localTimeline: localTimeline,
                      strokeTimelineUnits: _strokeTimelineUnits,
                      isPlaying: isPlaying,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KanjiAnimatedStrokePainter extends CustomPainter {
  final KanjiStrokeData data;
  final double localTimeline;
  final double strokeTimelineUnits;
  final bool isPlaying;

  const _KanjiAnimatedStrokePainter({
    required this.data,
    required this.localTimeline,
    required this.strokeTimelineUnits,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final viewBox = _parseViewBox(data.viewBox);
    final scale = (size.width / viewBox.width) < (size.height / viewBox.height)
        ? size.width / viewBox.width
        : size.height / viewBox.height;
    final drawWidth = viewBox.width * scale;
    final drawHeight = viewBox.height * scale;
    final offsetX = (size.width - drawWidth) / 2;
    final offsetY = (size.height - drawHeight) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale, scale);
    canvas.translate(-viewBox.left, -viewBox.top);

    final guidePaint = Paint()
      ..color = GakujiColors.mediumGray.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final completedPaint = Paint()
      ..color = GakujiColors.darkGray
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final activePaint = Paint()
      ..color = GakujiColors.reading
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final activeDotPaint = Paint()
      ..color = GakujiColors.reading
      ..style = PaintingStyle.fill;

    final parsedPaths = data.strokes
        .map((stroke) => _KanjiSvgPathParser.parse(stroke.pathData))
        .toList(growable: false);

    if (isPlaying) {
      for (final path in parsedPaths) {
        canvas.drawPath(path, guidePaint);
      }
    }

    Offset? activeDot;

    for (var index = 0; index < parsedPaths.length; index++) {
      final path = parsedPaths[index];
      final strokeStart = index * strokeTimelineUnits;
      final fraction =
          (localTimeline - strokeStart).clamp(0.0, 1.0).toDouble();

      if (fraction <= 0) continue;

      if (fraction >= 1) {
        canvas.drawPath(path, completedPaint);
        continue;
      }

      final partial = _extractPartialPath(path, fraction);
      canvas.drawPath(partial.path, activePaint);
      activeDot = partial.endPoint;
    }

    if (activeDot != null) {
      canvas.drawCircle(activeDot, 3.1, activeDotPaint);
    }

    canvas.restore();
  }

  _KanjiPartialPath _extractPartialPath(Path path, double fraction) {
    final metrics = path.computeMetrics(forceClosed: false).toList();

    if (metrics.isEmpty) {
      return _KanjiPartialPath(path: Path(), endPoint: null);
    }

    final totalLength = metrics.fold<double>(
      0,
      (sum, metric) => sum + metric.length,
    );
    var remaining = totalLength * fraction;
    final partial = Path();
    Offset? endPoint;

    for (final metric in metrics) {
      if (remaining <= 0) break;

      final take = remaining.clamp(0.0, metric.length).toDouble();
      partial.addPath(metric.extractPath(0, take), Offset.zero);

      if (take > 0) {
        endPoint = metric.getTangentForOffset(take)?.position;
      }

      remaining -= take;
    }

    return _KanjiPartialPath(path: partial, endPoint: endPoint);
  }

  Rect _parseViewBox(String rawViewBox) {
    final values = rawViewBox
        .trim()
        .split(RegExp(r'[ ,]+'))
        .map(double.tryParse)
        .whereType<double>()
        .toList(growable: false);

    if (values.length != 4 || values[2] <= 0 || values[3] <= 0) {
      return const Rect.fromLTWH(0, 0, 109, 109);
    }

    return Rect.fromLTWH(values[0], values[1], values[2], values[3]);
  }

  @override
  bool shouldRepaint(covariant _KanjiAnimatedStrokePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.localTimeline != localTimeline ||
        oldDelegate.strokeTimelineUnits != strokeTimelineUnits ||
        oldDelegate.isPlaying != isPlaying;
  }
}

class _KanjiPartialPath {
  final Path path;
  final Offset? endPoint;

  const _KanjiPartialPath({
    required this.path,
    required this.endPoint,
  });
}

class _KanjiSvgPathParser {
  static final RegExp _tokenPattern = RegExp(
    r'[AaCcHhLlMmQqSsTtVvZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
  );

  static Path parse(String pathData) {
    final tokens = _tokenPattern
        .allMatches(pathData)
        .map((match) => match.group(0)!)
        .toList(growable: false);

    final path = Path();
    var index = 0;
    var command = '';
    var current = Offset.zero;
    var subPathStart = Offset.zero;
    Offset? lastCubicControl;
    Offset? lastQuadraticControl;
    String? previousCommand;

    bool isCommand(String token) {
      return token.length == 1 && RegExp(r'[A-Za-z]').hasMatch(token);
    }

    double nextNumber() {
      if (index >= tokens.length || isCommand(tokens[index])) return 0;
      return double.tryParse(tokens[index++]) ?? 0;
    }

    Offset point(double x, double y, bool relative) {
      return relative ? current + Offset(x, y) : Offset(x, y);
    }

    while (index < tokens.length) {
      if (isCommand(tokens[index])) {
        command = tokens[index++];
      } else if (command.isEmpty) {
        index++;
        continue;
      }

      final relative = command == command.toLowerCase();
      final upper = command.toUpperCase();

      switch (upper) {
        case 'M':
          if (index + 1 >= tokens.length) break;
          final next = point(nextNumber(), nextNumber(), relative);
          path.moveTo(next.dx, next.dy);
          current = next;
          subPathStart = next;
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          command = relative ? 'l' : 'L';
          break;
        case 'L':
          if (index + 1 >= tokens.length) break;
          final next = point(nextNumber(), nextNumber(), relative);
          path.lineTo(next.dx, next.dy);
          current = next;
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'H':
          final x = nextNumber();
          current = Offset(relative ? current.dx + x : x, current.dy);
          path.lineTo(current.dx, current.dy);
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'V':
          final y = nextNumber();
          current = Offset(current.dx, relative ? current.dy + y : y);
          path.lineTo(current.dx, current.dy);
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'C':
          final control1 = point(nextNumber(), nextNumber(), relative);
          final control2 = point(nextNumber(), nextNumber(), relative);
          final next = point(nextNumber(), nextNumber(), relative);
          path.cubicTo(
            control1.dx,
            control1.dy,
            control2.dx,
            control2.dy,
            next.dx,
            next.dy,
          );
          current = next;
          lastCubicControl = control2;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'S':
          final hasPreviousCubic = previousCommand != null &&
              const {'C', 'c', 'S', 's'}.contains(previousCommand);
          final reflectedControl = hasPreviousCubic && lastCubicControl != null
              ? (current * 2) - lastCubicControl
              : current;
          final control2 = point(nextNumber(), nextNumber(), relative);
          final next = point(nextNumber(), nextNumber(), relative);
          path.cubicTo(
            reflectedControl.dx,
            reflectedControl.dy,
            control2.dx,
            control2.dy,
            next.dx,
            next.dy,
          );
          current = next;
          lastCubicControl = control2;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'Q':
          final control = point(nextNumber(), nextNumber(), relative);
          final next = point(nextNumber(), nextNumber(), relative);
          path.quadraticBezierTo(control.dx, control.dy, next.dx, next.dy);
          current = next;
          lastQuadraticControl = control;
          lastCubicControl = null;
          previousCommand = command;
          break;
        case 'T':
          final hasPreviousQuadratic = previousCommand != null &&
              const {'Q', 'q', 'T', 't'}.contains(previousCommand);
          final control = hasPreviousQuadratic && lastQuadraticControl != null
              ? (current * 2) - lastQuadraticControl
              : current;
          final next = point(nextNumber(), nextNumber(), relative);
          path.quadraticBezierTo(control.dx, control.dy, next.dx, next.dy);
          current = next;
          lastQuadraticControl = control;
          lastCubicControl = null;
          previousCommand = command;
          break;
        case 'A':
          nextNumber();
          nextNumber();
          nextNumber();
          nextNumber();
          nextNumber();
          final next = point(nextNumber(), nextNumber(), relative);
          path.lineTo(next.dx, next.dy);
          current = next;
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'Z':
          path.close();
          current = subPathStart;
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          command = '';
          break;
        default:
          command = '';
          break;
      }
    }

    return path;
  }
}


class _StrokeGuidePainter extends CustomPainter {
  const _StrokeGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GakujiColors.warmDivider.withValues(alpha: 0.55)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final horizontal = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width, size.height / 2);

    final vertical = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width / 2, size.height);

    canvas.drawPath(horizontal, paint);
    canvas.drawPath(vertical, paint);
  }

  @override
  bool shouldRepaint(covariant _StrokeGuidePainter oldDelegate) => false;
}
