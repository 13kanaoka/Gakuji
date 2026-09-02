import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';

import 'package:gakuji/data/state/recent_searches.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/domain/writing_point.dart';
import 'package:gakuji/data/dictionary/dictionary_service.dart';
import 'package:gakuji/data/sync/gakuji_cloud_sync_service.dart';
import 'package:gakuji/data/sync/gakuji_user_repository.dart';
import 'package:gakuji/data/sync/gakuji_term_payload_repair.dart';
import 'package:gakuji/core/services/writing_recognition_service.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_term_row.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/core/widgets/low_latency_writing_canvas.dart';
import 'package:gakuji/features/camera/camera_dictionary_page.dart';
import 'package:gakuji/features/dictionary/dictionary_detail_page.dart';
import 'package:gakuji/features/dictionary/kanji_dictionary_detail_page.dart';
import 'package:gakuji/features/settings/settings_page.dart';
import 'package:gakuji/core/widgets/gakuji_search_bar.dart';

enum DictionaryInputMode {
  keyboard,
  writing,
}

class DictionaryPage extends StatefulWidget {
  final ValueChanged<bool>? onHandwritingInputActive;

  const DictionaryPage({
    super.key,
    this.onHandwritingInputActive,
  });

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  static const Color accentBlue = Color(0xFF4D7EF7);
  static Color get panelGray => GakujiColors.warmCard;
  static Color get panelBorderGray => GakujiColors.warmDivider;

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  final ScrollController recentSearchScrollController = ScrollController();
  final GlobalKey _inputStackKey = GlobalKey();
  final GlobalKey _inputAccessoryBarKey = GlobalKey();

  Timer? searchDebounce;
  Timer? handwritingRecognitionDebounce;

  String searchText = '';
  String handwritingResult = '';

  DictionaryInputMode inputMode = DictionaryInputMode.keyboard;

  final List<List<WritingPoint>> handwritingStrokes = [];
  final List<String> handwritingCandidates = [];
  List<Term> searchResults = [];
  final Map<String, int> recentSearchTimestamps = {};

  bool isRecognizingHandwriting = false;
  bool isDictionaryLoading = true;
  bool isSearchingDictionary = false;
  bool isInputActive = false;
  bool searchHasFocus = false;
  bool recentSearchHasScrolled = false;

  double _lastKeyboardHeight = 0;
  double _lastAccessoryBottomOffset = 0;

  int searchRequestNumber = 0;
  int handwritingRecognitionRequestNumber = 0;

  bool get hasHandwritingInput {
    return handwritingStrokes.any((stroke) => stroke.isNotEmpty);
  }

  bool get shouldShowInputAccessoryBar {
    return isInputActive || inputMode == DictionaryInputMode.writing;
  }

  @override
  void initState() {
    super.initState();

    searchFocusNode.addListener(_handleSearchFocusChange);

    _loadRecentSearchTimestamps();
    loadDictionary();
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    handwritingRecognitionDebounce?.cancel();
    _setInputActive(false, rebuild: false);
    searchFocusNode.removeListener(_handleSearchFocusChange);
    searchFocusNode.dispose();
    searchController.dispose();
    recentSearchScrollController.dispose();

    super.dispose();
  }

  Future<void> loadDictionary() async {
    await DictionaryService.loadDictionary();

    // Recent-search rows are persisted Term snapshots. Refresh their
    // dictionary-owned preferred writing whenever this page opens so an
    // already-running app does not keep showing an old kanji-first snapshot
    // after the bundled dictionary changes.
    final repairedRecentSearchCount =
        await GakujiTermPayloadRepair.repairRecentSearches(recentSearches);

    if (repairedRecentSearchCount > 0) {
      await GakujiUserRepository.saveRecentSearches(
        recentSearches,
        updatedAtByTermId: recentSearchTimestamps,
      );
      GakujiCloudSyncService.schedulePush();
    }

    if (!mounted) return;

    setState(() {
      isDictionaryLoading = false;
    });
  }

  Future<void> _loadRecentSearchTimestamps() async {
    final loadedTimestamps =
        await GakujiUserRepository.loadRecentSearchTimestamps();

    if (!mounted) return;

    setState(() {
      recentSearchTimestamps
        ..clear()
        ..addAll(loadedTimestamps);
    });
  }

  double _writingPanelHeight(
    BuildContext context, {
    required double keyboardHeight,
  }) {
    // Once the real accessory-bar position has been captured, derive the
    // writing panel from that screen position instead of assuming the system
    // keyboard and the Flutter panel share the same height coordinate system.
    if (_lastAccessoryBottomOffset > 8.0) {
      return _lastAccessoryBottomOffset - 8.0;
    }

    if (_lastKeyboardHeight > 0) {
      return _lastKeyboardHeight;
    }

    if (keyboardHeight > 0) {
      return keyboardHeight;
    }

    // This is only a pre-keyboard fallback. In normal use the writing button is
    // reached from the open keyboard, so the real position is captured first.
    final rawHeight = MediaQuery.sizeOf(context).height * 0.42;
    return rawHeight.clamp(300.0, 410.0).toDouble();
  }

  void _captureInputAccessoryAnchor() {
    final stackRenderObject =
        _inputStackKey.currentContext?.findRenderObject();
    final accessoryRenderObject =
        _inputAccessoryBarKey.currentContext?.findRenderObject();

    if (stackRenderObject is! RenderBox ||
        accessoryRenderObject is! RenderBox ||
        !stackRenderObject.hasSize ||
        !accessoryRenderObject.hasSize) {
      return;
    }

    final stackBottom = stackRenderObject
        .localToGlobal(Offset(0, stackRenderObject.size.height))
        .dy;
    final accessoryBottom = accessoryRenderObject
        .localToGlobal(Offset(0, accessoryRenderObject.size.height))
        .dy;
    final bottomOffset = stackBottom - accessoryBottom;

    if (bottomOffset.isFinite && bottomOffset > 0) {
      _lastAccessoryBottomOffset = bottomOffset;
    }
  }

  void _handleSearchFocusChange() {
    final hasFocus = searchFocusNode.hasFocus;

    setState(() {
      searchHasFocus = hasFocus;

      if (hasFocus) {
        inputMode = DictionaryInputMode.keyboard;
      }
    });

    _syncInputActiveState(
      hasSearchFocus: hasFocus,
      mode: hasFocus ? DictionaryInputMode.keyboard : inputMode,
    );
  }

  void _syncInputActiveState({
    bool? hasSearchFocus,
    DictionaryInputMode? mode,
  }) {
    final activeSearchFocus = hasSearchFocus ?? searchHasFocus;
    final activeMode = mode ?? inputMode;

    _setInputActive(
      activeSearchFocus || activeMode == DictionaryInputMode.writing,
    );
  }

  void _setInputActive(
    bool active, {
    bool rebuild = true,
  }) {
    if (isInputActive == active) return;

    isInputActive = active;
    widget.onHandwritingInputActive?.call(active);

    if (rebuild && mounted) {
      setState(() {});
    }
  }

  void exitDictionaryInputMode() {
    FocusScope.of(context).unfocus();

    setState(() {
      inputMode = DictionaryInputMode.keyboard;
      searchHasFocus = false;
    });

    _setInputActive(false);
  }

  void updateSearchText(
    String value, {
    bool clearHandwritingResult = true,
  }) {
    setState(() {
      searchText = value;

      if (clearHandwritingResult) {
        handwritingResult = '';
      }
    });

    scheduleDictionarySearch(value);
  }

  void scheduleDictionarySearch(String rawQuery) {
    searchDebounce?.cancel();

    final query = rawQuery.trim();

    searchRequestNumber++;

    if (query.isEmpty) {
      setState(() {
        searchResults = [];
        isSearchingDictionary = false;
      });

      return;
    }

    setState(() {
      searchResults = [];
      isSearchingDictionary = true;
    });

    final requestNumber = searchRequestNumber;

    searchDebounce = Timer(
      const Duration(milliseconds: 280),
      () {
        searchDictionary(
          query: query,
          requestNumber: requestNumber,
        );
      },
    );
  }

  Future<void> searchDictionary({
    required String query,
    required int requestNumber,
  }) async {
    final results = await DictionaryService.search(query);

    if (!mounted) return;
    if (requestNumber != searchRequestNumber) return;
    if (query != searchText.trim()) return;

    setState(() {
      searchResults = results;
      isSearchingDictionary = false;
    });
  }

  void clearSearchState() {
    searchDebounce?.cancel();
    searchRequestNumber++;

    setState(() {
      searchController.clear();
      searchText = '';
      handwritingResult = '';
      searchResults = [];
      isSearchingDictionary = false;
    });
  }

  void addToRecentSearches(Term word) {
    final searchedAt = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      recentSearches.removeWhere(
        (recentWord) => recentWord.id == word.id,
      );

      recentSearchTimestamps[word.id] = searchedAt;
      recentSearches.insert(0, word);

      if (recentSearches.length > 30) {
        final removedSearches = recentSearches.sublist(30);
        recentSearches.removeRange(30, recentSearches.length);

        for (final removedSearch in removedSearches) {
          recentSearchTimestamps.remove(removedSearch.id);
        }
      }
    });

    unawaited(
      GakujiUserRepository.saveRecentSearches(
        recentSearches,
        updatedAtByTermId: recentSearchTimestamps,
      ),
    );
    GakujiCloudSyncService.schedulePush();
  }

  Future<void> openDictionaryDetail(Term word) async {
    FocusScope.of(context).unfocus();

    setState(() {
      inputMode = DictionaryInputMode.keyboard;
      searchHasFocus = false;
    });

    _setInputActive(false);
    addToRecentSearches(word);

    if (word.isKanjiDictionaryEntry) {
      await Navigator.push<void>(
        context,
        GakujiPageRoute(
          builder: (context) => KanjiDictionaryDetailPage(
            kanjiEntry: word,
          ),
        ),
      );

      if (!mounted) return;

      setState(() {
        inputMode = DictionaryInputMode.keyboard;
        searchHasFocus = false;
      });

      _setInputActive(false);
      return;
    }

    final result = await Navigator.push<DictionaryDetailBackResult>(
      context,
      GakujiPageRoute(
        builder: (context) => DictionaryDetailPage(word: word),
      ),
    );

    if (!mounted) return;

    if (result?.returnToResults ?? true) {
      setState(() {
        inputMode = DictionaryInputMode.keyboard;
        searchHasFocus = false;
      });

      _setInputActive(false);
    }
  }

  void switchInputMode(DictionaryInputMode mode) {
    if (mode == inputMode) return;

  if (mode == DictionaryInputMode.writing) {
      final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
      if (keyboardHeight > 0) {
        _lastKeyboardHeight = keyboardHeight;
        // Anchoring is only meaningful while the OS keyboard is on screen.
        // Otherwise the accessory row is at its fallback offset near the bottom
        // edge and would collapse the writing panel to a sliver.
        _captureInputAccessoryAnchor();
      }
      FocusScope.of(context).unfocus();
    }

    setState(() {
      inputMode = mode;
    });

    _setInputActive(true);

    if (mode == DictionaryInputMode.keyboard) {
      // The search field already exists in the tree, so there is no reason to
      // wait an extra frame before asking iOS to bring the keyboard back.
      searchFocusNode.requestFocus();
    }
  }

  void clearKeyboardSearch() {
    clearSearchState();
  }

  void addHandwritingPoint(
    Offset point, {
    bool isStart = false,
  }) {
    final writingPoint = WritingPoint.fromOffset(
      x: point.dx,
      y: point.dy,
      time: DateTime.now().millisecondsSinceEpoch,
    );

    if (isStart || handwritingStrokes.isEmpty) {
      handwritingStrokes.add(<WritingPoint>[writingPoint]);
    } else {
      handwritingStrokes.last.add(writingPoint);
    }
  }

  void clearHandwritingBox() {
    handwritingRecognitionDebounce?.cancel();
    handwritingRecognitionRequestNumber++;
    searchDebounce?.cancel();
    searchRequestNumber++;

    setState(() {
      handwritingStrokes.clear();
      handwritingCandidates.clear();
      handwritingResult = '';
      searchController.clear();
      searchText = '';
      searchResults = [];
      isSearchingDictionary = false;
      isRecognizingHandwriting = false;
    });
  }

  void undoLastHandwritingStroke() {
    if (handwritingStrokes.isEmpty) return;

    handwritingRecognitionDebounce?.cancel();
    handwritingRecognitionRequestNumber++;

    setState(() {
      handwritingStrokes.removeLast();
      handwritingCandidates.clear();
      handwritingResult = '';
      isRecognizingHandwriting = false;
    });

    if (hasHandwritingInput) {
      scheduleHandwritingCandidateRecognition();
    }
  }

  void scheduleHandwritingCandidateRecognition() {
    handwritingRecognitionDebounce?.cancel();
    handwritingRecognitionRequestNumber++;

    if (!hasHandwritingInput) {
      setState(() {
        handwritingCandidates.clear();
        handwritingResult = '';
        isRecognizingHandwriting = false;
      });

      return;
    }

    final requestNumber = handwritingRecognitionRequestNumber;

    handwritingRecognitionDebounce = Timer(
      const Duration(milliseconds: 360),
      () {
        recognizeHandwritingCandidates(requestNumber: requestNumber);
      },
    );
  }

  Future<void> recognizeHandwritingCandidates({
    required int requestNumber,
  }) async {
    if (!hasHandwritingInput) return;

    setState(() {
      isRecognizingHandwriting = true;
    });

    final recognitionCandidates =
        await WritingRecognitionService.recognizeCandidates(
      slotStrokes: handwritingStrokes,
      mockCharacter: '',
      maxCandidates: 16,
      kanjiOnly: true,
    );

    if (!mounted) return;
    if (requestNumber != handwritingRecognitionRequestNumber) return;

    if (recognitionCandidates.isEmpty) {
      setState(() {
        isRecognizingHandwriting = false;
        handwritingCandidates.clear();
        handwritingResult = '';
      });

      return;
    }

    final relatedCandidates = await DictionaryService.getRelatedKanjiCandidates(
      recognitionCandidates,
      limit: 24,
    );

    if (!mounted) return;
    if (requestNumber != handwritingRecognitionRequestNumber) return;

    final combinedCandidates = <String>[];
    final seenCandidates = <String>{};

    for (final candidate in <String>[
      ...recognitionCandidates,
      ...relatedCandidates,
    ]) {
      if (!seenCandidates.add(candidate)) continue;
      combinedCandidates.add(candidate);

      if (combinedCandidates.length >= 32) break;
    }

    setState(() {
      isRecognizingHandwriting = false;
      handwritingResult = combinedCandidates.first;
      handwritingCandidates
        ..clear()
        ..addAll(combinedCandidates);
    });
    _setInputActive(true);
  }

  void selectHandwritingCandidate(String candidate) {
    handwritingRecognitionDebounce?.cancel();
    handwritingRecognitionRequestNumber++;

    final currentValue = searchController.value;
    final currentText = currentValue.text;
    final selection = currentValue.selection;
    final hasSelection = selection.isValid;
    final start = hasSelection ? selection.start : currentText.length;
    final end = hasSelection ? selection.end : currentText.length;
    final nextSearchText = currentText.replaceRange(start, end, candidate);
    final nextOffset = start + candidate.length;

    setState(() {
      handwritingStrokes.clear();
      handwritingCandidates.clear();
      handwritingResult = '';
      isRecognizingHandwriting = false;
      searchText = nextSearchText;

      searchController.value = TextEditingValue(
        text: nextSearchText,
        selection: TextSelection.collapsed(
          offset: nextOffset,
        ),
      );
    });

    scheduleDictionarySearch(nextSearchText);
    _setInputActive(true);
  }

  @override
  Widget build(BuildContext context) {
    final query = searchText.trim();
    final wordsToShow = query.isEmpty ? recentSearches : searchResults;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final writingPanelHeight = _writingPanelHeight(
      context,
      keyboardHeight: keyboardHeight,
    );
    final bottomResultsPadding = inputMode == DictionaryInputMode.writing
        ? writingPanelHeight + 92
        : shouldShowInputAccessoryBar
            ? 90.0
            : 190.0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: GakujiColors.warmBackground,
      body: Stack(
        key: _inputStackKey,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (isInputActive) {
                exitDictionaryInputMode();
              }
            },
            child: Column(
              children: [
                _dictionaryHeader(),
                Expanded(
                  child: Stack(
                    children: [
                      _dictionaryContent(
                        query: query,
                        wordsToShow: wordsToShow,
                        bottomResultsPadding: bottomResultsPadding,
                      ),
                      Positioned(
                        top: 8,
                        left: 14,
                        right: 14,
                        child: _keyboardSearchBar(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _writingInputPanel(panelHeight: writingPanelHeight),
          _keyboardAccessoryBar(
            writingPanelHeight: writingPanelHeight,
            keyboardHeight: keyboardHeight,
          ),
        ],
      ),
    );
  }

  Widget _dictionaryHeader() {
    final topInset = MediaQuery.of(context).padding.top;

    return Container(
      color: GakujiColors.warmBackground,
      padding: EdgeInsets.only(
        top: topInset + 4,
        bottom: 4,
      ),
      child: GakujiTopBar(
        leftIcon: Icons.settings,
        leftIconColor: GakujiColors.darkGray,
        onLeftTap: _openSettingsPage,
        title: 'Dictionary',
        titleStyle: GakujiText.pageTitle.copyWith(
          color: GakujiColors.darkGray,
        ),
        rightIcon: Icons.camera_alt_rounded,
        rightIconColor: GakujiColors.darkGray,
        onRightTap: _openCameraPage,
      ),
    );
  }

  Future<void> _openCameraPage() async {
    FocusScope.of(context).unfocus();

    if (mounted) {
      setState(() {
        inputMode = DictionaryInputMode.keyboard;
        searchHasFocus = false;
      });
    }

    _setInputActive(false);

    await Navigator.of(context).push(
      GakujiPageRoute(
        builder: (context) => const CameraDictionaryPage(),
      ),
    );

    if (!mounted) return;

    setState(() {
      inputMode = DictionaryInputMode.keyboard;
      searchHasFocus = false;
    });

    _setInputActive(false);
  }

  void _openSettingsPage() {
    FocusScope.of(context).unfocus();
    _setInputActive(false);

    Navigator.of(context).push(
      GakujiPageRoute(
        side: GakujiPageSide.left,
        builder: (context) => const SettingsPage(),
      ),
    );
  }

  Widget _dictionaryContent({
    required String query,
    required List<Term> wordsToShow,
    required double bottomResultsPadding,
  }) {
    if (query.isEmpty && recentSearches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 74),
        child: Center(
          child: Text(
            isDictionaryLoading ? 'Loading dictionary...' : 'Search for a word',
            textScaler: TextScaler.noScaling,
            style: GakujiText.body.copyWith(color: Colors.grey),
          ),
        ),
      );
    }

    if (query.isNotEmpty && isSearchingDictionary && searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 74),
        child: Center(
          child: Text(
            'Searching...',
            textScaler: TextScaler.noScaling,
            style: GakujiText.body.copyWith(color: Colors.grey),
          ),
        ),
      );
    }

    if (query.isNotEmpty && !isSearchingDictionary && searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 74),
        child: Center(
          child: Text(
            'No results found',
            textScaler: TextScaler.noScaling,
            style: GakujiText.body.copyWith(color: Colors.grey),
          ),
        ),
      );
    }

    if (query.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 66),
        child: _recentSearchList(
          wordsToShow: wordsToShow,
          topPadding: 0,
          bottomResultsPadding: bottomResultsPadding,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 70, 14, 0),
      child: _dictionaryResultList(
        query: query,
        wordsToShow: wordsToShow,
        topPadding: 14,
        bottomResultsPadding: bottomResultsPadding,
      ),
    );
  }

  Widget _recentSearchList({
    required List<Term> wordsToShow,
    required double topPadding,
    required double bottomResultsPadding,
  }) {
    final groupedSearches = <String, List<Term>>{};

    for (final word in wordsToShow) {
      final timestamp = recentSearchTimestamps[word.id];
      final dateLabel = _recentSearchDateLabel(timestamp);
      groupedSearches.putIfAbsent(dateLabel, () => <Term>[]).add(word);
    }

    final children = <Widget>[];

    for (final entry in groupedSearches.entries) {
      children.add(_recentSearchDateHeader(entry.key));
      children.add(const SizedBox(height: 8));

      for (var index = 0; index < entry.value.length; index++) {
        final word = entry.value[index];
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _dictionaryTermRow(word),
          ),
        );

        if (index < entry.value.length - 1) {
          children.add(
            Divider(
              height: 1,
              thickness: 1,
              indent: 14,
              endIndent: 14,
              color: GakujiColors.softBorder,
            ),
          );
        }
      }
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification && isInputActive) {
          exitDictionaryInputMode();
        }

        final hasScrolled = notification.metrics.pixels > 0.5;
        if (hasScrolled != recentSearchHasScrolled) {
          setState(() {
            recentSearchHasScrolled = hasScrolled;
          });
        }

        return false;
      },
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              recentSearchHasScrolled
                  ? const Color(0x00000000)
                  : Colors.black,
              Colors.black,
              Colors.black,
              const Color(0x00000000),
            ],
            stops: const [
              0.0,
              0.035,
              0.94,
              1.0,
            ],
          ).createShader(bounds);
        },
        child: ListView(
          controller: recentSearchScrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(
            top: topPadding,
            bottom: bottomResultsPadding,
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _recentSearchDateHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      decoration: BoxDecoration(
        color: GakujiColors.sectionHeader,
        border: Border(
          top: BorderSide(
            color: GakujiColors.darkGray.withValues(alpha: 0.16),
            width: 1,
          ),
          bottom: BorderSide(
            color: GakujiColors.darkGray.withValues(alpha: 0.16),
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
          color: GakujiColors.darkGray,
        ),
      ),
    );
  }

  String _recentSearchDateLabel(int? timestamp) {
    final now = DateTime.now();
    final date = timestamp == null
        ? now
        : DateTime.fromMillisecondsSinceEpoch(timestamp);
    final today = DateTime(now.year, now.month, now.day);
    final searchDate = DateTime(date.year, date.month, date.day);
    final daysOld = today.difference(searchDate).inDays;

    if (daysOld == 0) return 'Today';
    if (daysOld == 1) return 'Yesterday';
    if (daysOld == 2) return '2 Days Ago';

    const monthNames = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${monthNames[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _dictionaryTermRow(
    Term word, {
    String searchQuery = '',
  }) {
    final queryWriting = _exactSearchWritingFor(word, searchQuery);
    final titleText = queryWriting ?? _preferredListWriting(word);
    final secondaryText = _dictionaryRowSecondaryText(
      word,
      titleText: titleText,
    );

    return GakujiTermRow(
      term: word,
      titleText: titleText,
      readingText: secondaryText,
      allowSecondaryForKanaTitle: true,
      onTap: () => openDictionaryDetail(word),
    );
  }

  String _preferredListWriting(Term word) {
    final preferred = word.preferredSpelling.trim();
    if (preferred.isNotEmpty) return preferred;

    if (word.kanji.trim().isNotEmpty) return word.kanji.trim();
    return word.reading.trim();
  }

  String? _exactSearchWritingFor(Term word, String rawQuery) {
    final query = _normalizedDictionaryLookup(rawQuery);
    if (query.isEmpty) return null;

    for (final form in word.allWrittenForms) {
      if (_normalizedDictionaryLookup(form) == query) {
        return form.trim();
      }
    }

    return null;
  }

  String _dictionaryRowSecondaryText(
    Term word, {
    required String titleText,
  }) {
    final title = titleText.trim();
    if (title.isEmpty) return '';

    if (_isDictionaryWrittenForm(word, title)) {
      final reading = word.reading.trim();
      return reading == title ? '' : reading;
    }

    return _writtenFormsForPrimaryReading(
      word,
      excluding: title,
    ).join('・');
  }

  bool _isDictionaryWrittenForm(Term word, String value) {
    final metadata = word.spellingMetadataFor(value);
    if (metadata != null) return metadata.isKanji;

    if (word.kanji.trim() == value) return true;
    if (word.alternativeKanji.any((form) => form.trim() == value)) return true;

    return RegExp(r'[\u4E00-\u9FFF]').hasMatch(value);
  }

  List<String> _writtenFormsForPrimaryReading(
    Term word, {
    String excluding = '',
  }) {
    final compatible = word.cardWritingForms.toSet();
    final forms = <String>[];
    final seen = <String>{};

    void add(String value) {
      final cleaned = value.trim();
      if (cleaned.isEmpty || cleaned == excluding || !seen.add(cleaned)) return;
      forms.add(cleaned);
    }

    for (final spelling in word.spellings) {
      if (!spelling.isKanji || !compatible.contains(spelling.text)) continue;
      add(spelling.text);
    }

    if (compatible.contains(word.kanji)) add(word.kanji);
    for (final form in word.alternativeKanji) {
      if (compatible.contains(form)) add(form);
    }

    return forms;
  }

  String _normalizedDictionaryLookup(String value) {
    return value.replaceAll(RegExp(r'\s+'), '').trim();
  }

  Widget _dictionaryResultList({
    required String query,
    required List<Term> wordsToShow,
    required double topPadding,
    required double bottomResultsPadding,
  }) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (isInputActive) {
          exitDictionaryInputMode();
        }

        return false;
      },
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x00000000),
              Colors.black,
              Colors.black,
              Color(0x00000000),
            ],
            stops: [
              0.0,
              0.035,
              0.94,
              1.0,
            ],
          ).createShader(bounds);
        },
        child: ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(
            top: topPadding,
            bottom: bottomResultsPadding,
          ),
          itemCount: wordsToShow.length,
          separatorBuilder: (context, index) {
            return Divider(
              height: 1,
              thickness: 1,
              color: GakujiColors.softBorder,
            );
          },
          itemBuilder: (context, index) {
            return _dictionaryTermRow(
              wordsToShow[index],
              searchQuery: query,
            );
          },
        ),
      ),
    );
  }
  Widget _keyboardSearchBar() {
    return GakujiSearchBar(
      controller: searchController,
      focusNode: searchFocusNode,
      hintText: 'Search',
      showClearButton: searchText.isNotEmpty,
      onTap: () {
        if (inputMode != DictionaryInputMode.keyboard) {
          switchInputMode(DictionaryInputMode.keyboard);
        } else {
          _setInputActive(true);
        }
      },
      onChanged: updateSearchText,
      onClear: clearKeyboardSearch,
    );
  }

  Widget _keyboardAccessoryBar({
    required double writingPanelHeight,
    required double keyboardHeight,
  }) {
    // The native keyboard can report a height that does not map one-to-one to
    // the bottom coordinate used by this Flutter Stack. In writing mode, use
    // the actual accessory-row position captured before the keyboard closed.
    final double bottomOffset = inputMode == DictionaryInputMode.writing
        ? _lastAccessoryBottomOffset > 0
            ? _lastAccessoryBottomOffset
            : writingPanelHeight + 8.0
        : keyboardHeight > 0
            ? keyboardHeight + 8.0
            : _lastAccessoryBottomOffset > 0
                ? _lastAccessoryBottomOffset
                : _lastKeyboardHeight > 0
                    ? _lastKeyboardHeight + 8.0
                    : 18.0;

    return Positioned(
      left: 18,
      right: 18,
      bottom: bottomOffset,
      child: IgnorePointer(
        ignoring: !shouldShowInputAccessoryBar,
        child: AnimatedSlide(
          offset: shouldShowInputAccessoryBar
              ? Offset.zero
              : const Offset(0, 0.24),
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: shouldShowInputAccessoryBar ? 1 : 0,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            child: Row(
              key: _inputAccessoryBarKey,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (inputMode == DictionaryInputMode.writing)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _writingAccessoryActionButton(
                        label: 'Clear',
                        icon: Icons.refresh_rounded,
                        enabled: hasHandwritingInput &&
                            !isRecognizingHandwriting,
                        onTap: clearHandwritingBox,
                      ),
                      const SizedBox(width: 7),
                      _writingAccessoryActionButton(
                        label: 'Undo',
                        icon: Icons.undo_rounded,
                        enabled: handwritingStrokes.isNotEmpty &&
                            !isRecognizingHandwriting,
                        onTap: undoLastHandwritingStroke,
                      ),
                    ],
                  )
                else
                  const SizedBox.shrink(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _accessoryModeButton(
                      label: 'Keyboard',
                      icon: Icons.keyboard_alt_outlined,
                      mode: DictionaryInputMode.keyboard,
                    ),
                    const SizedBox(width: 7),
                    _accessoryModeButton(
                      label: 'Writing',
                      icon: Icons.draw_outlined,
                      mode: DictionaryInputMode.writing,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accessoryModeButton({
    required String label,
    required IconData icon,
    required DictionaryInputMode mode,
  }) {
    final isSelected = inputMode == mode;

    return Semantics(
      label: label,
      button: true,
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(12.5),
          onTap: () => switchInputMode(mode),
          child: Container(
            width: 45,
            height: 42.5,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? accentBlue : GakujiColors.whiteCard,
              borderRadius: BorderRadius.circular(12.5),
              border: Border.all(
                color: isSelected
                    ? GakujiColors.reading
                    : GakujiColors.softBorder,
                width: 1,
              ),
              boxShadow: [GakujiShadows.soft],
            ),
            child: Icon(
              icon,
              size: 22.5,
              color: isSelected ? Colors.white : accentBlue,
            ),
          ),
        ),
      ),
    );
  }

  Widget _writingAccessoryActionButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(12.5),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 45,
            height: 42.5,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GakujiColors.whiteCard,
              borderRadius: BorderRadius.circular(12.5),
              border: Border.all(
                color: GakujiColors.softBorder,
                width: 1,
              ),
              boxShadow: [GakujiShadows.soft],
            ),
            child: Icon(
              icon,
              size: 22.5,
              color: enabled ? accentBlue : GakujiColors.softGray,
            ),
          ),
        ),
      ),
    );
  }

  Widget _writingInputPanel({
    required double panelHeight,
  }) {
    final visible = inputMode == DictionaryInputMode.writing;

    return Positioned(
      left: 0,
      right: 0,
      bottom: visible ? 0 : -panelHeight - 24,
      height: panelHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _setInputActive(true);
        },
        onPanDown: (_) {
          _setInputActive(true);
        },
        child: Container(
          decoration: BoxDecoration(
            color: panelGray,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 18,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
            child: Column(
              children: [
                _handwritingCandidateRow(),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: panelBorderGray,
                ),
                Expanded(
                  child: _handwritingCanvas(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _handwritingCandidateRow() {
    if (handwritingCandidates.isEmpty) {
      return SizedBox(
        height: 48,
        child: Center(
          child: Text(
            hasHandwritingInput
                ? isRecognizingHandwriting
                    ? 'Checking...'
                    : 'Keep writing'
                : 'Write a character',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 14,
              height: 1,
              color: GakujiColors.mediumGray,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: handwritingCandidates.length,
        separatorBuilder: (context, index) {
          return VerticalDivider(
            width: 1,
            thickness: 1,
            color: panelBorderGray,
          );
        },
        itemBuilder: (context, index) {
          final candidate = handwritingCandidates[index];

          return InkWell(
            onTap: () => selectHandwritingCandidate(candidate),
            child: Container(
              width: 46,
              alignment: Alignment.center,
              child: Text(
                candidate,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 22,
                  height: 1,
                  color: GakujiColors.darkGray,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _handwritingCanvas() {
    return GakujiLowLatencyWritingCanvas(
      strokes: handwritingStrokes,
      showGrid: false,
      penColor: GakujiColors.darkGray,
      gridColor: GakujiColors.warmDivider,
      borderColor: GakujiColors.warmDivider,
      strokeWidth: 5,
      onStrokeStart: (point) {
        _setInputActive(true);
        handwritingRecognitionDebounce?.cancel();

        setState(() {
          handwritingCandidates.clear();
          handwritingResult = '';
          addHandwritingPoint(
            point,
            isStart: true,
          );
        });
      },
      onStrokeUpdate: addHandwritingPoint,
      onStrokeEnd: scheduleHandwritingCandidateRecognition,
      child: Center(
        child: handwritingStrokes.isEmpty
            ? Text(
                'Write here',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 14,
                  color: GakujiColors.mediumGray,
                  fontWeight: FontWeight.w500,
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}
