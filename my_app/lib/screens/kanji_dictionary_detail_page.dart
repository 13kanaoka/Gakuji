import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/deck_data.dart';
import '../data/review_card_data.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../services/deck_storage.dart';
import '../services/dictionary_service.dart';
import '../services/gakuji_user_data_store.dart';
import '../widgets/gakuji_faded_scroll.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import 'dictionary_detail_page.dart';

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
  static const Color sectionHighlightColor = Color(0xFFFAF7F2);
  static const Color accentBlue = Color(0xFF4D7EF7);
  static Color get dividerColor => GakujiColors.warmDivider;
  static Color get softTextGray => GakujiColors.mediumGray;
  static Color get darkText => GakujiColors.darkGray;
  static Color get inputFill => GakujiColors.warmCard;

  static const int maxNoteCharacters = 400;
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
  bool showTopBarTitle = false;
  bool showSavePopup = false;

  String noteText = '';
  String? directSaveDeckId;
  String savePopupText = '';
  IconData savePopupIcon = Icons.check_circle;

  List<Term> compoundTerms = const [];
  KanjiStrokeData? strokeData;
  int strokeLoadRequestId = 0;

  Term get entry => widget.kanjiEntry;

  String get sourceId => entry.sourceId ?? entry.id;

  String get notePreferenceKey => 'gakuji_dictionary_note_$sourceId';

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
    showTopBarTitle = false;
    noteText = '';
    compoundTerms = const [];
    strokeData = null;
    noteController.clear();

    unawaited(_loadSavedNote());
    unawaited(_loadStrokeData());
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
    final prefs = await SharedPreferences.getInstance();
    final savedNote = prefs.getString(notePreferenceKey);
    final initialNote = savedNote ?? entry.note ?? '';

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
    final cleanedNote = _cleanNoteText(noteController.text);
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(notePreferenceKey, cleanedNote);

    if (!mounted) return;

    setState(() {
      noteText = cleanedNote;

      if (closeEditor) {
        isEditingNote = false;
      }
    });
  }

  Future<void> _clearNote() async {
    noteController.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(notePreferenceKey, '');

    if (!mounted) return;

    setState(() {
      noteText = '';
      isEditingNote = false;
    });

    FocusScope.of(context).unfocus();
  }

  String _cleanNoteText(String value) {
    if (value.length <= maxNoteCharacters) {
      return value.trimRight();
    }

    return value.substring(0, maxNoteCharacters).trimRight();
  }

  bool deckContainsEntry(Deck deck) {
    return deck.terms.any((term) => term.sourceId == sourceId);
  }

  Term copiedEntryForDeck(Deck deck) {
    return Term.deckCopyFrom(
      entry,
      id: '${deck.id}_${sourceId}_${DateTime.now().microsecondsSinceEpoch}',
      marked: false,
    );
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
    await _syncReviewCardsIfEnabled(deck);
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

  Future<void> openDeckPicker() async {
    if (isEditingNote) {
      await _saveNoteFromController(closeEditor: true);
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.62,
                ),
                decoration: BoxDecoration(
                  color: GakujiColors.warmBackground,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _sheetHandle(),
                     Padding(
                      padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
                      child: Text(
                        'Save to...',
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: 18,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: darkText,
                        ),
                      ),
                    ),
                     Divider(
                      height: 1,
                      color: dividerColor,
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: decks.length,
                        itemBuilder: (context, index) {
                          final deck = decks[index];
                          final saved = deckContainsEntry(deck);
                          final isDirect = deck.id == directSaveDeck.id;

                          return ListTile(
                            minVerticalPadding: 11,
                            contentPadding:
                                const EdgeInsets.fromLTRB(22, 0, 12, 0),
                            title: Text(
                              deck.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.05,
                                fontWeight: FontWeight.w600,
                                color: darkText,
                              ),
                            ),
                            subtitle: Text(
                              '${deck.terms.length} terms',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.2,
                                color: softTextGray,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Set as direct save deck',
                                  onPressed: () async {
                                    await _setDirectSaveDeck(deck);
                                    setSheetState(() {});
                                  },
                                  icon: Icon(
                                    isDirect
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    color: isDirect
                                        ? accentBlue
                                        : softTextGray,
                                  ),
                                ),
                                Icon(
                                  saved
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color: saved ? accentBlue : softTextGray,
                                ),
                              ],
                            ),
                            onTap: () async {
                              await _toggleEntryInDeck(deck);
                              setSheetState(() {});
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
      MaterialPageRoute(
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
    return WillPopScope(
      onWillPop: _handleSystemBack,
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
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w500,
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
              SizedBox(
                key: kanjiTitleKey,
                width: 112,
                child: Text(
                  _displayCharacter,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 86,
                    height: 1,
                    fontWeight: FontWeight.w400,
                    color: darkText,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _strokeOrderPanel(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (meaning.isNotEmpty)
            Text(
              meaning,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 19,
                height: 1.24,
                fontWeight: FontWeight.w600,
                color: darkText,
              ),
            ),
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
          style: TextStyle(
            fontSize: 13,
            color: softTextGray,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 4;
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
      final strokeColor = isNewestStroke ? '#4D7EF7' : '#414247';

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
              style: TextStyle(
                fontSize: 15.5,
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
              style: TextStyle(
                fontSize: 15.5,
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
              style: TextStyle(
                fontSize: 17,
                height: 1.22,
                color: darkText,
                fontWeight: FontWeight.w400,
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
      style: TextStyle(
        fontSize: 16,
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
          style: TextStyle(
            fontSize: 16,
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
          style: TextStyle(
            fontSize: 16,
            height: 1.2,
            color: darkText,
          ),
          decoration: InputDecoration(
            hintText: 'Write a note',
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
                    style: TextStyle(
                      fontSize: 15,
                      height: 1,
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
    addInfo('Radical', entry.radical);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Info'),
        if (rows.isEmpty)
           Padding(
            padding: EdgeInsets.fromLTRB(22, 15, 22, 17),
            child: Text(
              'No additional information',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 15.5,
                color: softTextGray,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 9, 22, 12),
            child: Column(
              children: rows
                  .map(
                    (row) => _infoRow(row.key, row.value),
                  )
                  .toList(),
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
            width: 92,
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.2,
                color: softTextGray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 16.5,
                height: 1.2,
                color: darkText,
              ),
            ),
          ),
        ],
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
              style: TextStyle(
                fontSize: 15.5,
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
              style: TextStyle(
                fontSize: 15.5,
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
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 3,
                          children: [
                            Text(
                              compound.kanji,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 20,
                                height: 1,
                                color: darkText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (compound.reading.trim().isNotEmpty &&
                                compound.reading != compound.kanji)
                              Text(
                                compound.reading,
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1,
                                  color: softTextGray,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          compound.cardMeaning,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 15,
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
        color: sectionHighlightColor,
        border: Border(
          top: BorderSide(
            color: darkText.withOpacity(0.16),
            width: 1,
          ),
          bottom: BorderSide(
            color: darkText.withOpacity(0.16),
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
}


class _StrokeGuidePainter extends CustomPainter {
  const _StrokeGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GakujiColors.warmDivider.withOpacity(0.55)
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
