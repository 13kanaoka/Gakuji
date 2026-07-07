import 'dart:async';

import 'package:flutter/material.dart';

import '../data/recent_searches.dart';
import '../models/term.dart';
import '../models/writing_point.dart';
import '../services/dictionary_service.dart';
import '../services/writing_recognition_service.dart';
import '../theme/app_text_styles.dart';
import 'dictionary_detail_page.dart';

enum DictionaryInputMode { keyboard, writing }

class DictionaryPage extends StatefulWidget {
  final ValueChanged<bool>? onHandwritingInputActive;

  const DictionaryPage({super.key, this.onHandwritingInputActive});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  static const Color accentBlue = Color(0xFF4D7EF7);
  static const Color dividerGray = Color(0xFFC8C8C8);
  static const Color panelGray = Color(0xFFF0F2F5);
  static const Color panelBorderGray = Color(0xFFD6D8DC);

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  Timer? searchDebounce;
  Timer? handwritingRecognitionDebounce;

  String searchText = '';
  String handwritingResult = '';

  DictionaryInputMode inputMode = DictionaryInputMode.keyboard;

  final List<List<WritingPoint>> handwritingStrokes = [];
  final List<String> handwritingCandidates = [];
  List<Term> searchResults = [];

  bool isRecognizingHandwriting = false;
  bool isDictionaryLoading = true;
  bool isSearchingDictionary = false;
  bool isInputActive = false;
  bool searchHasFocus = false;

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

    super.dispose();
  }

  Future<void> loadDictionary() async {
    await DictionaryService.loadDictionary();

    if (!mounted) return;

    setState(() {
      isDictionaryLoading = false;
    });
  }

  double _writingPanelHeight(BuildContext context) {
    final rawHeight = MediaQuery.of(context).size.height * 0.36;

    return rawHeight.clamp(270.0, 340.0).toDouble();
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

  void _setInputActive(bool active, {bool rebuild = true}) {
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

  void updateSearchText(String value, {bool clearHandwritingResult = true}) {
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

    searchDebounce = Timer(const Duration(milliseconds: 280), () {
      searchDictionary(query: query, requestNumber: requestNumber);
    });
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
    setState(() {
      recentSearches.removeWhere((recentWord) => recentWord.id == word.id);

      recentSearches.insert(0, word);
    });
  }

  Future<void> openDictionaryDetail(Term word) async {
    FocusScope.of(context).unfocus();

    setState(() {
      inputMode = DictionaryInputMode.keyboard;
      searchHasFocus = false;
    });

    _setInputActive(false);
    addToRecentSearches(word);

    final result = await Navigator.push<DictionaryDetailBackResult>(
      context,
      MaterialPageRoute(builder: (context) => DictionaryDetailPage(word: word)),
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
    setState(() {
      inputMode = mode;
    });

    if (mode == DictionaryInputMode.keyboard) {
      _setInputActive(true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        searchFocusNode.requestFocus();
      });
    }

    if (mode == DictionaryInputMode.writing) {
      FocusScope.of(context).unfocus();
      _setInputActive(true);
    }
  }

  void clearKeyboardSearch() {
    clearSearchState();
  }

  void addHandwritingPoint(Offset point, {bool isStart = false}) {
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
    searchDebounce?.cancel();
    searchRequestNumber++;

    setState(() {
      handwritingStrokes.removeLast();
      handwritingCandidates.clear();
      handwritingResult = '';
      isRecognizingHandwriting = false;

      if (handwritingStrokes.isEmpty) {
        searchController.clear();
        searchText = '';
        searchResults = [];
        isSearchingDictionary = false;
      }
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

    final recognizedCharacter = await WritingRecognitionService.recognizeSlot(
      slotStrokes: handwritingStrokes,
      mockCharacter: '',
    );

    if (!mounted) return;
    if (requestNumber != handwritingRecognitionRequestNumber) return;

    if (recognizedCharacter.isEmpty) {
      setState(() {
        isRecognizingHandwriting = false;
        handwritingCandidates.clear();
        handwritingResult = '';
      });

      return;
    }

    setState(() {
      isRecognizingHandwriting = false;
      handwritingResult = recognizedCharacter;
      handwritingCandidates
        ..clear()
        ..add(recognizedCharacter);

      searchText = recognizedCharacter;

      searchController.value = TextEditingValue(
        text: recognizedCharacter,
        selection: TextSelection.collapsed(offset: recognizedCharacter.length),
      );
    });

    scheduleDictionarySearch(recognizedCharacter);
    _setInputActive(true);
  }

  void selectHandwritingCandidate(String candidate) {
    handwritingRecognitionDebounce?.cancel();
    handwritingRecognitionRequestNumber++;

    setState(() {
      handwritingResult = candidate;
      searchText = candidate;

      searchController.value = TextEditingValue(
        text: candidate,
        selection: TextSelection.collapsed(offset: candidate.length),
      );
    });

    scheduleDictionarySearch(candidate);
    _setInputActive(true);
  }

  @override
  Widget build(BuildContext context) {
    final query = searchText.trim();
    final wordsToShow = query.isEmpty ? recentSearches : searchResults;
    final writingPanelHeight = _writingPanelHeight(context);
    final headerHeight = MediaQuery.of(context).padding.top + 58;
    final bottomResultsPadding = inputMode == DictionaryInputMode.writing
        ? writingPanelHeight + 92
        : shouldShowInputAccessoryBar
        ? 90.0
        : 190.0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: headerHeight,
            child: const ColoredBox(color: accentBlue),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (isInputActive) {
                exitDictionaryInputMode();
              }
            },
            onPanDown: (_) {
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                        child: _dictionaryContent(
                          query: query,
                          wordsToShow: wordsToShow,
                          bottomResultsPadding: bottomResultsPadding,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 18,
                        right: 18,
                        child: _keyboardSearchBar(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _writingInputPanel(panelHeight: writingPanelHeight),
          _keyboardAccessoryBar(writingPanelHeight: writingPanelHeight),
        ],
      ),
    );
  }

  Widget _dictionaryHeader() {
    final topInset = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      height: topInset + 58,
      color: accentBlue,
      padding: EdgeInsets.fromLTRB(28, topInset + 18, 28, 18),
      child: const Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'Dictionary',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: AppText.pageTitle,
          ),
        ],
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
        padding: const EdgeInsets.only(top: 82),
        child: Center(
          child: Text(
            isDictionaryLoading ? 'Loading dictionary...' : 'Search for a word',
            textScaler: TextScaler.noScaling,
            style: AppText.emptyState,
          ),
        ),
      );
    }

    if (query.isNotEmpty && isSearchingDictionary && searchResults.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 82),
        child: Center(
          child: Text(
            'Searching...',
            textScaler: TextScaler.noScaling,
            style: AppText.emptyState,
          ),
        ),
      );
    }

    if (query.isNotEmpty && !isSearchingDictionary && searchResults.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 82),
        child: Center(
          child: Text(
            'No results found',
            textScaler: TextScaler.noScaling,
            style: AppText.emptyState,
          ),
        ),
      );
    }

    if (query.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 82),
          const Text(
            'Recent Searches',
            textScaler: TextScaler.noScaling,
            style: AppText.listHeading,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _dictionaryResultList(
              wordsToShow: wordsToShow,
              topPadding: 0,
              bottomResultsPadding: bottomResultsPadding,
            ),
          ),
        ],
      );
    }

    return _dictionaryResultList(
      wordsToShow: wordsToShow,
      topPadding: 82,
      bottomResultsPadding: bottomResultsPadding,
    );
  }

  Widget _dictionaryResultList({
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
      child: ListView.separated(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(top: topPadding, bottom: bottomResultsPadding),
        itemCount: wordsToShow.length,
        separatorBuilder: (context, index) {
          return const Divider(height: 1, thickness: 1, color: dividerGray);
        },
        itemBuilder: (context, index) {
          final word = wordsToShow[index];

          return _DictionaryTermTile(
            word: word,
            onTap: () => openDictionaryDetail(word),
          );
        },
      ),
    );
  }

  Widget _keyboardSearchBar() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        searchFocusNode.requestFocus();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 18,
                spreadRadius: 0,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 22, color: Colors.black),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: searchController,
                  focusNode: searchFocusNode,
                  onTap: () {
                    if (inputMode != DictionaryInputMode.keyboard) {
                      switchInputMode(DictionaryInputMode.keyboard);
                    } else {
                      _setInputActive(true);
                    }
                  },
                  onChanged: updateSearchText,
                  cursorColor: accentBlue,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    hintStyle: AppText.inputHint,
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                  style: AppText.input,
                ),
              ),
              if (searchText.isNotEmpty)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.black45,
                    ),
                    onPressed: clearKeyboardSearch,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyboardAccessoryBar({required double writingPanelHeight}) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final double bottomOffset = inputMode == DictionaryInputMode.writing
        ? writingPanelHeight + 8.0
        : keyboardHeight > 0
        ? keyboardHeight + 8.0
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
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
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
                    _accessoryModeButton(
                      label: 'Keyboard',
                      icon: Icons.keyboard_alt_outlined,
                      mode: DictionaryInputMode.keyboard,
                    ),
                    const SizedBox(width: 5),
                    _accessoryModeButton(
                      label: 'Writing',
                      icon: Icons.draw_outlined,
                      mode: DictionaryInputMode.writing,
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

  Widget _accessoryModeButton({
    required String label,
    required IconData icon,
    required DictionaryInputMode mode,
  }) {
    final isSelected = inputMode == mode;

    return Material(
      color: isSelected ? accentBlue : const Color(0xFFF4F4F4),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () => switchInputMode(mode),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 21,
                color: isSelected ? Colors.white : accentBlue,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                textScaler: TextScaler.noScaling,
                style: AppText.buttonLabel.copyWith(
                  color: isSelected ? Colors.white : accentBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _writingInputPanel({required double panelHeight}) {
    final visible = inputMode == DictionaryInputMode.writing;

    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: visible ? 0 : -panelHeight - 24,
      height: panelHeight,
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _setInputActive(true);
        },
        onPanDown: (_) {
          _setInputActive(true);
        },
        child: Container(
          decoration: const BoxDecoration(
            color: panelGray,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 18,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Column(
              children: [
                _handwritingCandidateRow(),
                const Divider(height: 1, thickness: 1, color: panelBorderGray),
                _handwritingActionRow(),
                const Divider(height: 1, thickness: 1, color: panelBorderGray),
                Expanded(child: _handwritingCanvas()),
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
            style: AppText.body.copyWith(
              color: Colors.black45,
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
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: handwritingCandidates.length,
        separatorBuilder: (context, index) {
          return const VerticalDivider(
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
              width: 76,
              alignment: Alignment.center,
              child: Text(
                candidate,
                textScaler: TextScaler.noScaling,
                style: AppText.kanjiCandidate,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _handwritingActionRow() {
    return SizedBox(
      height: 43,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _handwritingTextButton(
              label: 'Clear',
              enabled: hasHandwritingInput && !isRecognizingHandwriting,
              onTap: clearHandwritingBox,
            ),
            const SizedBox(width: 12),
            _handwritingTextButton(
              label: 'Undo',
              enabled:
                  handwritingStrokes.isNotEmpty && !isRecognizingHandwriting,
              onTap: undoLastHandwritingStroke,
            ),
            const Spacer(),
            if (isRecognizingHandwriting)
              Text(
                'Checking...',
                textScaler: TextScaler.noScaling,
                style: AppText.cardCaption.copyWith(
                  color: Colors.black38,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (handwritingResult.isNotEmpty)
              Text(
                'Searching: $handwritingResult',
                textScaler: TextScaler.noScaling,
                style: AppText.cardCaption.copyWith(
                  color: Colors.black38,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _handwritingTextButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Text(
          label,
          textScaler: TextScaler.noScaling,
          style: AppText.buttonLabel.copyWith(
            color: enabled ? accentBlue : Colors.black26,
          ),
        ),
      ),
    );
  }

  Widget _handwritingCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            _setInputActive(true);
          },
          onPanDown: (_) {
            _setInputActive(true);
          },
          onPanStart: (details) {
            _setInputActive(true);
            handwritingRecognitionDebounce?.cancel();

            final box = context.findRenderObject() as RenderBox;
            final point = box.globalToLocal(details.globalPosition);

            setState(() {
              handwritingCandidates.clear();
              handwritingResult = '';

              addHandwritingPoint(point, isStart: true);
            });
          },
          onPanUpdate: (details) {
            final box = context.findRenderObject() as RenderBox;
            final point = box.globalToLocal(details.globalPosition);

            setState(() {
              addHandwritingPoint(point);
            });
          },
          onPanEnd: (_) {
            scheduleHandwritingCandidateRecognition();
          },
          onPanCancel: () {
            scheduleHandwritingCandidateRecognition();
          },
          child: CustomPaint(
            painter: _HandwritingSearchPainter(
              strokes: handwritingStrokes,
              showGrid: false,
            ),
            child: Center(
              child: handwritingStrokes.isEmpty
                  ? Text(
                      'Write here',
                      textScaler: TextScaler.noScaling,
                      style: AppText.body.copyWith(
                        color: Colors.black38,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _DictionaryTermTile extends StatelessWidget {
  final Term word;
  final VoidCallback onTap;

  const _DictionaryTermTile({required this.word, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final titleText = word.kanjiBracketText.isNotEmpty
        ? word.kanjiBracketText
        : word.reading;
    final subtitleText = word.kanjiBracketText.isNotEmpty ? word.reading : '';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 10,
                runSpacing: 0,
                children: [
                  Text(
                    titleText,
                    textScaler: TextScaler.noScaling,
                    style: AppText.cardTitle,
                  ),
                  if (subtitleText.isNotEmpty)
                    Text(
                      '【$subtitleText】',
                      textScaler: TextScaler.noScaling,
                      style: AppText.cardReading,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                word.cardMeaning,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: AppText.cardCaption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HandwritingSearchPainter extends CustomPainter {
  final List<List<WritingPoint>> strokes;
  final bool showGrid;

  const _HandwritingSearchPainter({
    required this.strokes,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = const Color(0xFFD8D8D8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final grid = Paint()
      ..color = const Color(0xFFE3E3E3)
      ..strokeWidth = 1;

    final pen = Paint()
      ..color = Colors.black87
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), border);

    if (showGrid) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        grid,
      );

      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        grid,
      );
    }

    for (final stroke in strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(
          Offset(stroke[i].x, stroke[i].y),
          Offset(stroke[i + 1].x, stroke[i + 1].y),
          pen,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HandwritingSearchPainter oldDelegate) {
    return true;
  }
}
