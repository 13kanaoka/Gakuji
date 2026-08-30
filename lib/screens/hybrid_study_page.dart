import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:gakuji/data/reading_card_edit_data.dart';
import 'package:gakuji/models/deck.dart';
import 'package:gakuji/models/term.dart';
import 'package:gakuji/models/writing_point.dart';
import 'package:gakuji/models/writing_prompt.dart';
import 'package:gakuji/services/deck_storage.dart';
import 'package:gakuji/services/gakuji_local_preferences.dart';
import 'package:gakuji/services/gakuji_user_data_store.dart';
import 'package:gakuji/services/prompt_converter.dart';
import 'package:gakuji/services/reading_card_edit_storage.dart';
import 'package:gakuji/services/term_favorite_service.dart';
import 'package:gakuji/services/writing_answer_checker.dart';
import 'package:gakuji/services/writing_recognition_service.dart';
import 'package:gakuji/widgets/gakuji_options_sheet.dart';
import 'package:gakuji/widgets/gakuji_styles.dart';
import 'package:gakuji/widgets/gakuji_top_bar.dart';
import 'package:gakuji/widgets/low_latency_writing_canvas.dart';
import 'package:gakuji/widgets/reading_card_back.dart';
import 'package:gakuji/widgets/writing_study_card.dart';

enum _HybridCardType {
  reading,
  writing,
}

class _HybridStudyItem {
  final Term term;
  final _HybridCardType type;

  const _HybridStudyItem({
    required this.term,
    required this.type,
  });

  String get key => '${term.id}:${type.name}';
}

class _HybridHistoryEntry {
  final _HybridStudyItem item;
  final bool correct;

  const _HybridHistoryEntry({
    required this.item,
    required this.correct,
  });
}

class HybridStudyPage extends StatefulWidget {
  final Deck deck;
  final bool initialIsShuffled;
  final bool initialShowFurigana;
  final bool initialTermFirst;
  final bool initialShowGrid;

  const HybridStudyPage({
    super.key,
    required this.deck,
    this.initialIsShuffled = false,
    this.initialShowFurigana = true,
    this.initialTermFirst = true,
    this.initialShowGrid = true,
  });

  @override
  State<HybridStudyPage> createState() => _HybridStudyPageState();
}

class _HybridStudyPageState extends State<HybridStudyPage>
    with TickerProviderStateMixin {
  static const String _showFuriganaPreferenceKey = 'study_show_furigana';
  static const String _showExampleFuriganaPreferenceKey =
      'study_show_example_furigana';
  static const String _termFirstPreferenceKey = 'study_term_first';
  static const String _writingGridPreferenceKey =
      'study_writing_grid_visible';
  static const String _blueCardTextPreferenceKey = 'blue_card_text_enabled';
  static String _starredOnlyPreferenceKey(String deckId) {
    return 'study_starred_only_$deckId';
  }

  static const Duration _cardReturnDuration = Duration(milliseconds: 320);
  static const Duration _cardExitDuration = Duration(milliseconds: 140);
  static const Duration _cardContentFadeDuration =
      Duration(milliseconds: 120);

  static const Color incorrectRed = Color(0xFFF6A3A3);
  static const Color incorrectRedOutline = Color(0xFFE06F6F);

  static const Color correctGreen = Color(0xFFC5E7A5);
  static const Color correctGreenOutline = Color(0xFF8DBB66);

  late List<_HybridStudyItem> allItems;
  late List<_HybridStudyItem> activeItems;

  final List<_HybridStudyItem> answeredItems = [];
  final List<_HybridHistoryEntry> history = [];
  final List<_HybridStudyItem> incorrectReviewItems = [];

  final Map<String, ReadingCardEditData> readingCardEdits = {};
  final Set<String> savedReadingCardEditTermIds = {};

  int correctCount = 0;
  int incorrectCount = 0;

  bool isShuffled = false;
  bool showFurigana = true;
  bool showExampleFurigana = true;
  bool termFirst = true;
  bool blueCardTextEnabled = false;
  bool showStarredOnly = false;
  bool isReviewingIncorrect = false;

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  late AnimationController _swipeController;
  late Animation<Offset> _swipeAnimation;

  late AnimationController _cardContentController;
  late Animation<double> _cardContentOpacity;

  Offset dragOffset = Offset.zero;
  bool isDragging = false;
  bool isSwipingAway = false;

  List<List<List<WritingPoint>>> slotStrokes = [];
  List<String?> slotAnswers = [];
  int activeSlotIndex = 0;
  bool showGrid = true;
  bool hasChecked = false;
  bool isCheckingAnswer = false;
  bool isWritingAnswerRevealed = false;
  WritingAnswerResult? writingAnswerResult;

  int get totalSessionCount => answeredItems.length + activeItems.length;

  bool get isComplete => activeItems.isEmpty && allItems.isNotEmpty;

  _HybridStudyItem get currentItem => activeItems.first;

  bool get currentIsReading =>
      currentItem.type == _HybridCardType.reading;

  bool get currentIsWriting =>
      currentItem.type == _HybridCardType.writing;

  WritingPrompt get currentWritingPrompt =>
      PromptConverter.fromTerm(currentItem.term);

  double get deckProgress {
    final total = totalSessionCount;

    if (total <= 0) return 0;

    return (answeredItems.length / total).clamp(0.0, 1.0).toDouble();
  }

  String? get swipeFeedbackText {
    if (dragOffset.dx > 32) return 'Know';
    if (dragOffset.dx < -32) return 'Still learning';

    return null;
  }

  Color? get swipeFeedbackColor {
    if (dragOffset.dx > 32) return correctGreenOutline;
    if (dragOffset.dx < -32) return incorrectRedOutline;

    return null;
  }

  double get swipeFeedbackOpacity {
    final opacity = ((dragOffset.dx.abs() - 30) / 90).clamp(0.0, 1.0);

    return opacity.toDouble();
  }

  bool get writingSwipeEnabled {
    return currentIsWriting && isWritingAnswerRevealed;
  }

  bool get isCheckingFinalSlot {
    if (!currentIsWriting || slotAnswers.isEmpty) return false;

    final emptyIndexes = <int>[];

    for (var index = 0; index < slotAnswers.length; index++) {
      final answer = slotAnswers[index];

      if (answer == null || answer.isEmpty) {
        emptyIndexes.add(index);
      }
    }

    return emptyIndexes.length == 1 &&
        emptyIndexes.first == activeSlotIndex;
  }

  List<String> get currentAnswerCharacters {
    if (!currentIsWriting) return const [];

    return currentWritingPrompt.answer.runes.map((rune) {
      return String.fromCharCode(rune);
    }).toList();
  }

  String get activeCorrectCharacter {
    final characters = currentAnswerCharacters;

    if (characters.isEmpty) return '';

    final safeIndex =
        activeSlotIndex.clamp(0, characters.length - 1).toInt();

    return characters[safeIndex];
  }

  @override
  void initState() {
    super.initState();

    isShuffled = widget.initialIsShuffled;
    showFurigana = widget.initialShowFurigana;
    termFirst = widget.initialTermFirst;
    showGrid = widget.initialShowGrid;

    allItems = _buildItems(widget.deck.terms);
    activeItems = List<_HybridStudyItem>.from(allItems);

    if (isShuffled) {
      _shuffleSeparatingVariants(activeItems);
    }

    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _flipAnimation = Tween<double>(
      begin: 0,
      end: math.pi,
    ).animate(
      CurvedAnimation(
        parent: _flipController,
        curve: Curves.easeInOut,
      ),
    );

    _swipeController = AnimationController(
      vsync: this,
      duration: _cardExitDuration,
    );

    _swipeAnimation = const AlwaysStoppedAnimation<Offset>(Offset.zero);
    _swipeController.addListener(_handleSwipeAnimationTick);

    _cardContentController = AnimationController(
      vsync: this,
      duration: _cardContentFadeDuration,
    );

    _cardContentOpacity = CurvedAnimation(
      parent: _cardContentController,
      curve: Curves.easeOut,
    );

    _cardContentController.value = 1;

    _resetCurrentCardState();

    _loadProgressAndPreferences();
    _loadReadingCardEdits();
  }

  @override
  void dispose() {
    _swipeController.removeListener(_handleSwipeAnimationTick);
    _cardContentController.dispose();
    _swipeController.dispose();
    _flipController.dispose();
    super.dispose();
  }

  List<Term> get filteredTerms {
    if (showStarredOnly) {
      return widget.deck.terms.where((term) => term.marked).toList();
    }

    return List<Term>.from(widget.deck.terms);
  }

  List<_HybridStudyItem> _buildItems(List<Term> terms) {
    final readingItems = <_HybridStudyItem>[];
    final writingItems = <_HybridStudyItem>[];

    for (final term in terms) {
      final mode = widget.deck.cardModeFor(term);

      if (mode == HybridCardMode.reading ||
          mode == HybridCardMode.both) {
        readingItems.add(
          _HybridStudyItem(
            term: term,
            type: _HybridCardType.reading,
          ),
        );
      }

      if (mode == HybridCardMode.writing ||
          mode == HybridCardMode.both) {
        writingItems.add(
          _HybridStudyItem(
            term: term,
            type: _HybridCardType.writing,
          ),
        );
      }
    }

    final mixedItems = <_HybridStudyItem>[];
    var preferReading = true;
    String? previousTermId;

    while (readingItems.isNotEmpty || writingItems.isNotEmpty) {
      final preferredItems =
          preferReading ? readingItems : writingItems;
      final alternateItems =
          preferReading ? writingItems : readingItems;

      var selectedIndex = preferredItems.indexWhere(
        (item) => item.term.id != previousTermId,
      );
      var selectedItems = preferredItems;

      if (selectedIndex == -1) {
        selectedIndex = alternateItems.indexWhere(
          (item) => item.term.id != previousTermId,
        );
        selectedItems = alternateItems;
      }

      if (selectedIndex == -1) {
        if (preferredItems.isNotEmpty) {
          selectedIndex = 0;
          selectedItems = preferredItems;
        } else {
          selectedIndex = 0;
          selectedItems = alternateItems;
        }
      }

      final selectedItem = selectedItems.removeAt(selectedIndex);

      mixedItems.add(selectedItem);
      previousTermId = selectedItem.term.id;

      preferReading = selectedItem.type == _HybridCardType.writing;
    }

    return mixedItems;
  }

  void _shuffleSeparatingVariants(List<_HybridStudyItem> items) {
    items.shuffle();

    for (var index = 1; index < items.length; index++) {
      if (items[index - 1].term.id != items[index].term.id) continue;

      var replacementIndex = -1;

      for (
        var candidateIndex = index + 1;
        candidateIndex < items.length;
        candidateIndex++
      ) {
        if (items[candidateIndex].term.id != items[index - 1].term.id) {
          replacementIndex = candidateIndex;
          break;
        }
      }

      if (replacementIndex == -1) continue;

      final current = items[index];
      items[index] = items[replacementIndex];
      items[replacementIndex] = current;
    }
  }

  int _baseOrderIndex(_HybridStudyItem item) {
    final index = allItems.indexWhere((candidate) {
      return candidate.key == item.key;
    });

    return index == -1 ? 999999 : index;
  }

  void _sortActiveItemsToBaseOrder() {
    activeItems.sort((first, second) {
      return _baseOrderIndex(first).compareTo(
        _baseOrderIndex(second),
      );
    });
  }

  Future<void> _loadProgressAndPreferences() async {
    final savedProgress = await DeckStorage.loadProgress(widget.deck.id);
    final savedShowFurigana =
        await GakujiLocalPreferences.loadBool(_showFuriganaPreferenceKey);
    final savedShowExampleFurigana = await GakujiLocalPreferences.loadBool(
      _showExampleFuriganaPreferenceKey,
    );
    final savedTermFirst =
        await GakujiLocalPreferences.loadBool(_termFirstPreferenceKey);
    final savedGridVisible =
        await GakujiLocalPreferences.loadBool(_writingGridPreferenceKey);
    final savedBlueCardText =
        await GakujiLocalPreferences.loadBool(_blueCardTextPreferenceKey);
    final savedShowStarredOnly = await GakujiLocalPreferences.loadBool(
      _starredOnlyPreferenceKey(widget.deck.id),
    );

    if (!mounted || isReviewingIncorrect) return;

    final nextShowStarredOnly = savedShowStarredOnly ?? showStarredOnly;
    final nextTerms = nextShowStarredOnly
        ? widget.deck.terms.where((term) => term.marked).toList()
        : List<Term>.from(widget.deck.terms);

    if (nextTerms.isEmpty) {
      await GakujiLocalPreferences.saveBool(
        _starredOnlyPreferenceKey(widget.deck.id),
        false,
      );
    }

    final nextAllItems = _buildItems(
      nextTerms.isEmpty ? List<Term>.from(widget.deck.terms) : nextTerms,
    );
    final savedCount = savedProgress.clamp(0, nextAllItems.length).toInt();

    setState(() {
      showStarredOnly = nextTerms.isNotEmpty && nextShowStarredOnly;
      allItems = nextAllItems;
      answeredItems
        ..clear()
        ..addAll(allItems.take(savedCount));

      activeItems = List<_HybridStudyItem>.from(
        allItems.skip(savedCount),
      );

      if (isShuffled) {
        _shuffleSeparatingVariants(activeItems);
      }

      if (savedShowFurigana != null) {
        showFurigana = savedShowFurigana;
      }
      if (savedShowExampleFurigana != null) {
        showExampleFurigana = savedShowExampleFurigana;
      }
      if (savedTermFirst != null) {
        termFirst = savedTermFirst;
      }
      if (savedGridVisible != null) {
        showGrid = savedGridVisible;
      }
      blueCardTextEnabled = savedBlueCardText ?? false;

      _resetCurrentCardState();
    });
  }

  Future<void> _loadReadingCardEdits() async {
    final loadedEdits = <String, ReadingCardEditData>{};
    final loadedSavedIds = <String>{};

    for (final term in widget.deck.terms) {
      final hasSavedEdit = await ReadingCardEditStorage.hasSavedEdit(
        deck: widget.deck,
        term: term,
      );

      final editData = await ReadingCardEditStorage.load(
        deck: widget.deck,
        term: term,
      );

      loadedEdits[term.id] = editData;

      if (hasSavedEdit) {
        loadedSavedIds.add(term.id);
      }
    }

    if (!mounted) return;

    setState(() {
      readingCardEdits
        ..clear()
        ..addAll(loadedEdits);

      savedReadingCardEditTermIds
        ..clear()
        ..addAll(loadedSavedIds);
    });
  }

  void _handleSwipeAnimationTick() {
    if (!mounted) return;

    setState(() {
      dragOffset = _swipeAnimation.value;
    });
  }

  void _scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
  }

  void _toggleFavorite(Term term) {
    setState(() {
      TermFavoriteService.toggle(term);
    });

    _scheduleUserDataSave();
  }

  void _saveProgress() {
    if (isReviewingIncorrect) return;

    DeckStorage.saveProgress(
      widget.deck.id,
      answeredItems.length,
    );

    _scheduleUserDataSave();
  }

  Future<void> _saveGridPreference() async {
    await GakujiLocalPreferences.saveBool(
      _writingGridPreferenceKey,
      showGrid,
    );
  }

  void _resetCurrentCardState({
    bool resetContentOpacity = true,
  }) {
    dragOffset = Offset.zero;
    isDragging = false;
    isSwipingAway = false;

    _flipController.value = 0;

    slotStrokes = [];
    slotAnswers = [];
    activeSlotIndex = 0;
    hasChecked = false;
    isCheckingAnswer = false;
    isWritingAnswerRevealed = false;
    writingAnswerResult = null;

    if (resetContentOpacity) {
      _cardContentController.value = 1;
    }

    if (activeItems.isNotEmpty && currentIsWriting) {
      _initializeWritingSlots();
    }
  }

  void _initializeWritingSlots() {
    if (activeItems.isEmpty || !currentIsWriting) {
      slotStrokes = [];
      slotAnswers = [];
      activeSlotIndex = 0;
      return;
    }

    final count = currentWritingPrompt.slotCount;

    slotStrokes = List.generate(
      count,
      (_) => <List<WritingPoint>>[],
    );

    slotAnswers = List<String?>.filled(count, null);
    activeSlotIndex = 0;
    hasChecked = false;
  }

  bool _sameItem(
    _HybridStudyItem first,
    _HybridStudyItem second,
  ) {
    return first.key == second.key;
  }

  void _addIncorrectReviewItem(_HybridStudyItem item) {
    final alreadyAdded = incorrectReviewItems.any(
      (candidate) => _sameItem(candidate, item),
    );

    if (!alreadyAdded) {
      incorrectReviewItems.add(item);
    }
  }

  void _removeIncorrectReviewItem(_HybridStudyItem item) {
    final index = incorrectReviewItems.indexWhere(
      (candidate) => _sameItem(candidate, item),
    );

    if (index != -1) {
      incorrectReviewItems.removeAt(index);
    }
  }

  void _removeAnsweredItem(_HybridStudyItem item) {
    if (answeredItems.isEmpty) return;

    final lastItem = answeredItems.last;

    if (_sameItem(lastItem, item)) {
      answeredItems.removeLast();
      return;
    }

    final index = answeredItems.lastIndexWhere(
      (candidate) => _sameItem(candidate, item),
    );

    if (index != -1) {
      answeredItems.removeAt(index);
    }
  }

  void _answerCurrent(bool correct) {
    if (activeItems.isEmpty) return;

    final shouldFadeInNext = activeItems.length > 1;
    final answeredItem = activeItems.first;

    if (shouldFadeInNext) {
      _cardContentController.value = 0;
    } else {
      _cardContentController.value = 1;
    }

    setState(() {
      history.add(
        _HybridHistoryEntry(
          item: answeredItem,
          correct: correct,
        ),
      );

      answeredItems.add(answeredItem);
      activeItems.removeAt(0);

      if (correct) {
        correctCount++;
      } else {
        incorrectCount++;
        _addIncorrectReviewItem(answeredItem);
      }

      _resetCurrentCardState(resetContentOpacity: false);
    });

    if (shouldFadeInNext) {
      _cardContentController.forward(from: 0);
    }

    _saveProgress();
  }

  void _skipCurrent() {
    if (activeItems.isEmpty || isSwipingAway) return;

    _answerCurrent(false);
  }

  void _goBack() {
    if (history.isEmpty || isSwipingAway) return;

    _swipeController.stop();
    _cardContentController.stop();

    final last = history.removeLast();

    setState(() {
      if (last.correct) {
        correctCount--;
      } else {
        incorrectCount--;
        _removeIncorrectReviewItem(last.item);
      }

      _removeAnsweredItem(last.item);
      activeItems.insert(0, last.item);
      _resetCurrentCardState();
    });

    _saveProgress();
  }

  void _restart() {
    _swipeController.stop();
    _cardContentController.stop();

    setState(() {
      isReviewingIncorrect = false;
      allItems = _buildItems(filteredTerms);
      activeItems = List<_HybridStudyItem>.from(allItems);

      if (isShuffled) {
        _shuffleSeparatingVariants(activeItems);
      }

      answeredItems.clear();
      history.clear();
      incorrectReviewItems.clear();

      correctCount = 0;
      incorrectCount = 0;

      _resetCurrentCardState();
    });

    DeckStorage.saveProgress(widget.deck.id, 0);
    GakujiLocalPreferences.saveBool(
      _starredOnlyPreferenceKey(widget.deck.id),
      showStarredOnly,
    );
    _scheduleUserDataSave();
  }

  void _startIncorrectReview() {
    if (incorrectReviewItems.isEmpty) {
      _showFloatingMessage('No incorrect answers to review.');
      return;
    }

    _swipeController.stop();
    _cardContentController.stop();

    final reviewItems = List<_HybridStudyItem>.from(
      incorrectReviewItems,
    );

    setState(() {
      isReviewingIncorrect = true;
      allItems = reviewItems;
      activeItems = List<_HybridStudyItem>.from(reviewItems);

      if (isShuffled) {
        _shuffleSeparatingVariants(activeItems);
      }

      answeredItems.clear();
      history.clear();
      incorrectReviewItems.clear();

      correctCount = 0;
      incorrectCount = 0;

      _resetCurrentCardState();
    });
  }

  Future<void> _handleExit() async {
    if (isComplete && !isReviewingIncorrect) {
      await DeckStorage.saveProgress(widget.deck.id, 0);
      _scheduleUserDataSave();
    }

    if (!mounted) return;

    Navigator.pop(context);
  }

  void _toggleStarredOnly() {
    if (isSwipingAway) return;

    final nextValue = !showStarredOnly;
    final nextTerms = nextValue
        ? widget.deck.terms.where((term) => term.marked).toList()
        : List<Term>.from(widget.deck.terms);

    if (nextTerms.isEmpty) {
      _showFloatingMessage('No starred terms to study');
      return;
    }

    setState(() {
      showStarredOnly = nextValue;
      isReviewingIncorrect = false;

      allItems = _buildItems(nextTerms);
      activeItems = List<_HybridStudyItem>.from(allItems);

      if (isShuffled) {
        _shuffleSeparatingVariants(activeItems);
      }

      answeredItems.clear();
      history.clear();
      incorrectReviewItems.clear();

      correctCount = 0;
      incorrectCount = 0;

      _resetCurrentCardState();
    });

    DeckStorage.saveProgress(widget.deck.id, 0);
    _scheduleUserDataSave();
  }

  void _toggleShuffle() {
    if (isSwipingAway) return;

    setState(() {
      isShuffled = !isShuffled;

      if (isShuffled) {
        _shuffleSeparatingVariants(activeItems);
      } else {
        _sortActiveItemsToBaseOrder();
      }

      _resetCurrentCardState();
    });

    DeckStorage.saveShuffle(widget.deck.id, isShuffled);
    _saveProgress();
  }

  void _toggleFurigana() {
    if (isSwipingAway) return;

    final nextShowFurigana = !showFurigana;

    setState(() {
      showFurigana = nextShowFurigana;
      _flipController.value = 0;
    });

    GakujiLocalPreferences.saveBool(
      _showFuriganaPreferenceKey,
      nextShowFurigana,
    );
  }

  void _toggleExampleFurigana() {
    if (isSwipingAway) return;

    final nextShowExampleFurigana = !showExampleFurigana;

    setState(() {
      showExampleFurigana = nextShowExampleFurigana;
      _flipController.value = 0;
    });

    GakujiLocalPreferences.saveBool(
      _showExampleFuriganaPreferenceKey,
      nextShowExampleFurigana,
    );
  }

  void _toggleCardOrientation() {
    if (isSwipingAway) return;

    final nextTermFirst = !termFirst;

    setState(() {
      termFirst = nextTermFirst;
      _flipController.value = 0;
    });

    GakujiLocalPreferences.saveBool(
      _termFirstPreferenceKey,
      nextTermFirst,
    );
  }

  void _toggleGrid() {
    if (isSwipingAway) return;

    setState(() {
      showGrid = !showGrid;
    });

    _saveGridPreference();
  }

  void _openStudyOptions() {
    showGakujiOptionsSheet(
      context: context,
      title: 'Study Options',
      sectionsBuilder: (context) => [
        GakujiOptionsSheetSection(
          title: 'Study Set',
          items: [
            GakujiOptionsSheetItem(
              icon: showStarredOnly
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              label: showStarredOnly ? 'Starred terms only' : 'All terms',
              iconColor: showStarredOnly
                  ? GakujiColors.darkGray
                  : GakujiColors.mediumGray,
              onTap: _toggleStarredOnly,
            ),
          ],
        ),
        GakujiOptionsSheetSection(
          title: 'Reading Cards',
          items: [
            GakujiOptionsSheetItem(
              textIcon: 'あ',
              label: showFurigana ? 'Hide Furigana' : 'Show Furigana',
              iconColor: showFurigana
                  ? GakujiColors.darkGray
                  : GakujiColors.mediumGray,
              onTap: _toggleFurigana,
            ),
            GakujiOptionsSheetItem(
              textIcon: '例',
              label: showExampleFurigana
                  ? 'Hide Example Sentence Furigana'
                  : 'Show Example Sentence Furigana',
              iconColor: showExampleFurigana
                  ? GakujiColors.darkGray
                  : GakujiColors.mediumGray,
              onTap: _toggleExampleFurigana,
            ),
            GakujiOptionsSheetItem(
              icon: Icons.swap_horiz_rounded,
              label: termFirst ? 'Term First' : 'Definition First',
              iconColor: termFirst
                  ? GakujiColors.mediumGray
                  : GakujiColors.darkGray,
              onTap: _toggleCardOrientation,
            ),
          ],
        ),
        GakujiOptionsSheetSection(
          title: 'Writing Cards',
          items: [
            GakujiOptionsSheetItem(
              icon: showGrid
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              label: showGrid ? 'Hide Grid' : 'Show Grid',
              iconColor: showGrid
                  ? GakujiColors.darkGray
                  : GakujiColors.mediumGray,
              onTap: _toggleGrid,
            ),
          ],
        ),
        GakujiOptionsSheetSection(
          title: 'Session',
          items: [
            GakujiOptionsSheetItem(
              icon: Icons.shuffle_rounded,
              label: isShuffled ? 'Unshuffle' : 'Shuffle',
              iconColor: isShuffled
                  ? GakujiColors.darkGray
                  : GakujiColors.mediumGray,
              onTap: _toggleShuffle,
            ),
            GakujiOptionsSheetItem(
              icon: Icons.refresh_rounded,
              label: 'Reset Deck',
              iconColor: GakujiColors.mediumGray,
              onTap: _restart,
            ),
          ],
        ),
      ],
    );
  }

  void _flipReadingCard() {
    if (!currentIsReading ||
        _flipController.isAnimating ||
        isDragging ||
        isSwipingAway) {
      return;
    }

    if (_flipController.value < 0.5) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
  }

  bool get _currentCardCanSwipe {
    if (currentIsReading) return true;

    return writingSwipeEnabled;
  }

  void _onDragStart(DragStartDetails details) {
    if (!_currentCardCanSwipe || isSwipingAway) return;

    setState(() {
      isDragging = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_currentCardCanSwipe || isSwipingAway) return;

    setState(() {
      dragOffset = Offset(
        dragOffset.dx + details.delta.dx,
        dragOffset.dy + details.delta.dy,
      );

      isDragging = true;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_currentCardCanSwipe || isSwipingAway) return;

    const threshold = 120.0;

    if (dragOffset.dx > threshold) {
      _animateCardOffscreen(correct: true);
    } else if (dragOffset.dx < -threshold) {
      _animateCardOffscreen(correct: false);
    } else {
      _animateCardBack();
    }
  }

  Future<void> _animateCardBack() async {
    final startOffset = dragOffset;

    _swipeController.duration = _cardReturnDuration;

    _swipeAnimation = Tween<Offset>(
      begin: startOffset,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _swipeController,
        curve: Curves.easeOutCubic,
      ),
    );

    _swipeController.reset();

    setState(() {
      isSwipingAway = true;
    });

    await _swipeController.forward();

    if (!mounted) return;

    setState(() {
      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
    });
  }

  Future<void> _animateCardOffscreen({
    required bool correct,
  }) async {
    if (activeItems.isEmpty) return;

    final screenWidth = MediaQuery.of(context).size.width;

    _swipeController.duration = _cardExitDuration;

    final endOffset = Offset(
      correct ? screenWidth * 1.5 : -screenWidth * 1.5,
      dragOffset.dy * 0.45,
    );

    _swipeAnimation = Tween<Offset>(
      begin: dragOffset,
      end: endOffset,
    ).animate(
      CurvedAnimation(
        parent: _swipeController,
        curve: Curves.easeOutQuad,
      ),
    );

    _swipeController.reset();

    setState(() {
      isSwipingAway = true;
    });

    await _swipeController.forward();

    if (!mounted) return;

    _answerCurrent(correct);
  }

  void _selectWritingSlot(int index) {
    if (!currentIsWriting ||
        isWritingAnswerRevealed ||
        index < 0 ||
        index >= slotStrokes.length) {
      return;
    }

    setState(() {
      activeSlotIndex = index;
    });
  }

  void _addStroke(
    Offset point, {
    bool isStart = false,
  }) {
    if (!currentIsWriting ||
        isWritingAnswerRevealed ||
        slotStrokes.isEmpty) {
      return;
    }

    final writingPoint = WritingPoint.fromOffset(
      x: point.dx,
      y: point.dy,
      time: DateTime.now().millisecondsSinceEpoch,
    );

    final slot = slotStrokes[activeSlotIndex];

    if (isStart || slot.isEmpty) {
      slot.add(<WritingPoint>[writingPoint]);
    } else {
      slot.last.add(writingPoint);
    }
  }

  void _clearWritingSlot() {
    if (!currentIsWriting || slotStrokes.isEmpty) return;

    setState(() {
      slotStrokes[activeSlotIndex].clear();

      if (activeSlotIndex < slotAnswers.length) {
        slotAnswers[activeSlotIndex] = null;
      }
    });
  }

  void _moveToNextEmptySlot() {
    final nextIndex = slotAnswers.indexWhere(
      (answer) => answer == null || answer.isEmpty,
    );

    if (nextIndex != -1) {
      activeSlotIndex = nextIndex;
    }
  }

  Future<void> _checkWritingAnswer() async {
    if (!currentIsWriting ||
        isCheckingAnswer ||
        isWritingAnswerRevealed ||
        slotStrokes.isEmpty) {
      return;
    }

    final activeStrokes = slotStrokes[activeSlotIndex];

    final hasInput = WritingRecognitionService.hasStrokesInSlot(
      activeStrokes,
    );

    if (!hasInput) {
      _showFloatingMessage('Write in the selected box first.');
      return;
    }

    setState(() {
      hasChecked = true;
      isCheckingAnswer = true;
    });

    final recognizedCharacter =
        await WritingRecognitionService.recognizeSlot(
      slotStrokes: activeStrokes,
      mockCharacter: activeCorrectCharacter,
    );

    if (!mounted) return;

    if (recognizedCharacter.isEmpty) {
      setState(() {
        isCheckingAnswer = false;
      });

      _showFloatingMessage('Could not recognize that character. Try again.');
      return;
    }

    setState(() {
      slotAnswers[activeSlotIndex] = recognizedCharacter;

      final allSlotsFilled = WritingRecognitionService.areAllSlotsFilled(
        slotAnswers,
      );

      if (allSlotsFilled) {
        final submittedAnswer =
            WritingRecognitionService.buildSubmittedAnswer(
          slotAnswers,
        );

        writingAnswerResult = WritingAnswerChecker.check(
          submittedAnswer: submittedAnswer,
          correctAnswer: currentWritingPrompt.answer,
        );

        isWritingAnswerRevealed = true;
      } else {
        _moveToNextEmptySlot();
      }

      isCheckingAnswer = false;
    });
  }

  bool _hasSavedReadingCardEdit(Term term) {
    return savedReadingCardEditTermIds.contains(term.id);
  }

  ReadingCardEditData? _readingCardEditFor(Term term) {
    return readingCardEdits[term.id];
  }

  List<String> _defaultReadingGlossesFor(Term term) {
    final sourceTerm = term;
    final glossBySenseIndex = <int, String>{};

    for (final sense in sourceTerm.senses) {
      final definition = sense.displayDefinition.trim();

      if (definition.isNotEmpty) {
        glossBySenseIndex[sense.index] = definition;
      }
    }

    final selectedSenseIndexes = term.selectedGlosses
        .map((selection) => selection.senseIndex)
        .toSet();
    final selectedGlosses = <String>[];

    for (final sense in sourceTerm.senses) {
      if (!selectedSenseIndexes.contains(sense.index)) continue;

      final definition = glossBySenseIndex[sense.index];

      if (definition != null && !selectedGlosses.contains(definition)) {
        selectedGlosses.add(definition);
      }

      if (selectedGlosses.length >= 3) break;
    }

    if (selectedGlosses.isNotEmpty) {
      return selectedGlosses;
    }

    final defaults = glossBySenseIndex.values.take(3).toList();

    if (defaults.isNotEmpty) {
      return defaults;
    }

    final fallback = sourceTerm.cardMeaning.trim();

    if (fallback.isEmpty) return const [];

    return [fallback];
  }

  List<String> _resolvedReadingGlossesFor(
    Term term,
    List<String> storedGlosses,
  ) {
    if (storedGlosses.isEmpty) {
      return _defaultReadingGlossesFor(term);
    }

    final sourceTerm = term;
    final resolved = <String>[];
    final usedSenseIndexes = <int>{};

    for (final storedGloss in storedGlosses) {
      final cleanedGloss = storedGloss.trim();

      if (cleanedGloss.isEmpty) continue;

      DictionarySense? matchedSense;

      for (final sense in sourceTerm.senses) {
        final matchesSense =
            sense.displayDefinition.trim() == cleanedGloss;
        final matchesLegacyGloss = sense.glosses.any(
          (gloss) => gloss.trim() == cleanedGloss,
        );

        if (matchesSense || matchesLegacyGloss) {
          matchedSense = sense;
          break;
        }
      }

      if (matchedSense == null ||
          !usedSenseIndexes.add(matchedSense.index)) {
        continue;
      }

      final definition = matchedSense.displayDefinition.trim();

      if (definition.isNotEmpty) {
        resolved.add(definition);
      }

      if (resolved.length >= 3) break;
    }

    if (resolved.isNotEmpty) {
      return resolved;
    }

    return _defaultReadingGlossesFor(term);
  }

  Set<int> _readingSenseIndexesForGlosses(
    Term term,
    List<String> glosses,
  ) {
    final sourceTerm = term;
    final indexes = <int>{};

    for (final displayedGloss in glosses) {
      final cleanedGloss = displayedGloss.trim();

      if (cleanedGloss.isEmpty) continue;

      for (final sense in sourceTerm.senses) {
        final matchesSense =
            sense.displayDefinition.trim() == cleanedGloss;
        final matchesLegacyGloss = sense.glosses.any(
          (gloss) => gloss.trim() == cleanedGloss,
        );

        if (matchesSense || matchesLegacyGloss) {
          indexes.add(sense.index);
          break;
        }
      }
    }

    return indexes;
  }

  List<DictionaryExample> _readingEligibleExamplesFor(
    Term term,
    List<String> glosses,
  ) {
    final sourceTerm = term;
    final senseIndexes = _readingSenseIndexesForGlosses(
      term,
      glosses,
    );
    final examples = <DictionaryExample>[];
    final seen = <String>{};

    for (final sense in sourceTerm.senses) {
      if (!senseIndexes.contains(sense.index)) continue;

      for (final example in sense.examples) {
        final key = '${example.japanese}\u0000${example.english}';

        if (!seen.add(key)) continue;

        examples.add(example);
      }
    }

    return examples;
  }

  List<String> _readingGlossesFor(Term term) {
    final editData = _readingCardEditFor(term);

    if (_hasSavedReadingCardEdit(term) && editData != null) {
      return _resolvedReadingGlossesFor(
        term,
        editData.selectedGlosses,
      );
    }

    return _defaultReadingGlossesFor(term);
  }

  String _readingNoteFor(Term term) {
    return (term.note ?? '').trim();
  }

  List<DictionaryExample> _readingExamplesFor(Term term) {
    final editData = _readingCardEditFor(term);
    final glosses = _readingGlossesFor(term);
    final eligibleExamples = _readingEligibleExamplesFor(
      term,
      glosses,
    );

    if (_hasSavedReadingCardEdit(term) && editData != null) {
      return ReadingCardEditData.examplesFromKeys(
        examples: eligibleExamples,
        selectedExampleKeys: editData.selectedExampleKeys,
      ).take(1).toList();
    }

    return eligibleExamples.take(1).toList();
  }

  String? _readingPhotoPathFor(Term term) {
    if (!_hasSavedReadingCardEdit(term)) return null;

    final editData = _readingCardEditFor(term);

    if (editData == null || !editData.photoEnabled) return null;

    final path = editData.photoPath?.trim();

    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return null;
    }

    return path;
  }

  void _showFloatingMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1500),
          backgroundColor: Colors.black.withValues(alpha: 0.86),
          content: Text(
            message,
            textScaler: TextScaler.noScaling,
            style: GakujiText.snackBar,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (allItems.isEmpty && activeItems.isEmpty) {
      return Scaffold(
        backgroundColor: GakujiColors.warmBackground,
        body: Center(
          child: Text(
            'No hybrid cards',
            textScaler: TextScaler.noScaling,
            style: GakujiText.small,
          ),
        ),
      );
    }

    if (isComplete) {
      return _completeScreen();
    }

    final currentPosition = answeredItems.length + 1;
    final totalPosition = totalSessionCount;

    final compactStudyLayout = MediaQuery.sizeOf(context).height < 820;

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            _studyTopBar(
              leftIcon: Icons.close_rounded,
              onLeftTap: _handleExit,
              title: '$currentPosition/$totalPosition',
              rightIcon: Icons.menu_rounded,
              onRightTap: _openStudyOptions,
            ),
            _progressBar(deckProgress),
            SizedBox(height: compactStudyLayout ? 16 : 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pill(
                  incorrectCount,
                  incorrectRed,
                  alignLeft: true,
                ),
                _pill(
                  correctCount,
                  correctGreen,
                  alignLeft: false,
                ),
              ],
            ),
            SizedBox(height: compactStudyLayout ? 12 : 24),
            Expanded(
              child: _cardArea(),
            ),
            SizedBox(height: compactStudyLayout ? 12 : 28),
            Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: compactStudyLayout ? 6 : 10,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _circle(Icons.undo_rounded, _goBack),
                  _circle(Icons.redo_rounded, _skipCurrent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardArea() {
    if (currentIsReading) {
      return _readingCardArea();
    }

    return _writingCardArea(currentWritingPrompt);
  }

  Widget _readingCardArea() {
    final rotation =
        (dragOffset.dx / 700).clamp(-0.35, 0.35).toDouble();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (activeItems.length > 1) _readingBlankCardBehind(),
        Transform(
          transform: Matrix4.identity()
            ..translateByDouble(dragOffset.dx, dragOffset.dy, 0, 1)
            ..rotateZ(rotation),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: _flipReadingCard,
            onPanStart: _onDragStart,
            onPanUpdate: _onDragUpdate,
            onPanEnd: _onDragEnd,
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _flipAnimation,
                _cardContentController,
              ]),
              builder: (context, child) {
                return _readingCardAnimated();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _writingCardArea(WritingPrompt prompt) {
    final rotation =
        (dragOffset.dx / 700).clamp(-0.35, 0.35).toDouble();

    final feedbackColor = swipeFeedbackColor;
    final feedbackOpacity = swipeFeedbackOpacity;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (activeItems.length > 1) _writingBlankCardBehind(),
        if (!isWritingAnswerRevealed)
          AnimatedBuilder(
            animation: _cardContentController,
            builder: (context, child) {
              return _writingCard(
                prompt,
                contentOpacity: _cardContentOpacity.value,
              );
            },
          )
        else
          Transform(
            transform: Matrix4.identity()
              ..translateByDouble(dragOffset.dx, dragOffset.dy, 0, 1)
              ..rotateZ(rotation),
            alignment: Alignment.center,
            child: GestureDetector(
              onPanStart: _onDragStart,
              onPanUpdate: _onDragUpdate,
              onPanEnd: _onDragEnd,
              child: AnimatedBuilder(
                animation: _cardContentController,
                builder: (context, child) {
                  return _writingCard(
                    prompt,
                    swipeColor: feedbackColor,
                    swipeOpacity: feedbackOpacity,
                    contentOpacity: _cardContentOpacity.value,
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _readingBlankCardBehind() {
    return IgnorePointer(
      child: ReadingCardFrame(
        minHeight: ReadingCardFrame.readingStudyMinHeight,
        margin: const EdgeInsets.fromLTRB(28, 0, 28, 0),
        boxShadow: [GakujiShadows.soft],
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _writingBlankCardBehind() {
    return IgnorePointer(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          color: GakujiColors.warmCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: GakujiColors.softBorder,
            width: 1.2,
          ),
          boxShadow: [GakujiShadows.soft],
        ),
      ),
    );
  }

  Widget _readingCardAnimated() {
    final angle = _flipAnimation.value;
    final showBack = angle > math.pi / 2;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateY(angle),
      child: showBack
          ? Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..rotateY(math.pi),
              child: _readingCard(
                showBack: true,
                contentOpacity: _cardContentOpacity.value,
              ),
            )
          : _readingCard(
              showBack: false,
              contentOpacity: _cardContentOpacity.value,
            ),
    );
  }

  Widget _readingCard({
    required bool showBack,
    required double contentOpacity,
  }) {
    final hasSwipeFeedback =
        swipeFeedbackColor != null && swipeFeedbackOpacity > 0;
    final showDefinition = termFirst ? showBack : !showBack;
    final term = currentItem.term;

    return ReadingCardFrame(
      minHeight: ReadingCardFrame.readingStudyMinHeight,
      margin: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      borderColor: hasSwipeFeedback
          ? swipeFeedbackColor!
          : GakujiColors.softBorder,
      borderWidth: hasSwipeFeedback ? 5 : 1.2,
      isStarred: term.marked,
      onStarTap: () => _toggleFavorite(term),
      child: Center(
        child: Opacity(
          opacity: contentOpacity,
          child: showDefinition
              ? _readingDefinitionContent(term)
              : _readingTermContent(term),
        ),
      ),
    );
  }

  Widget _readingDefinitionContent(Term term) {
    final readingText = term.reading.trim();
    final editData = _readingCardEditFor(term);

    return ReadingCardBackContent(
      glosses: _readingGlossesFor(term),
      note: _readingNoteFor(term),
      examples: _readingExamplesFor(term),
      photoPath: _readingPhotoPathFor(term),
      photoScale: editData?.photoScale ?? 1.0,
      photoOffsetX: editData?.photoOffsetX ?? 0.0,
      photoOffsetY: editData?.photoOffsetY ?? 0.0,
      readingText: readingText,
      showReadingOnBack: !showFurigana && readingText.isNotEmpty,
      showExampleFurigana: showExampleFurigana,
      textColor: blueCardTextEnabled ? GakujiColors.reading : null,
    );
  }

  Widget _readingTermContent(Term term) {
    final kanjiText =
        term.kanji.trim().isNotEmpty ? term.kanji.trim() : term.reading.trim();
    final readingText = term.reading.trim();
    final showReadingAbove = showFurigana && readingText.isNotEmpty;

    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  kanjiText,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: _termFontSizeFor(kanjiText),
                    height: 1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.8,
                    color: blueCardTextEnabled
                        ? GakujiColors.reading
                        : GakujiColors.darkGray,
                  ),
                ),
              ),
            ),
            if (showReadingAbove)
              Align(
                alignment: Alignment.center,
                child: Transform.translate(
                  offset: const Offset(0, -52),
                  child: Text(
                    readingText,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 20,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: blueCardTextEnabled
                          ? GakujiColors.reading
                          : GakujiColors.mediumGray,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _termFontSizeFor(String text) {
    if (text.length >= 7) return 40;
    if (text.length >= 5) return 46;
    if (text.length >= 3) return 52;

    return 56;
  }

  Widget _writingCard(
    WritingPrompt prompt, {
    Color? swipeColor,
    double swipeOpacity = 0,
    double contentOpacity = 1,
  }) {
    final hasSwipeFeedback = swipeColor != null && swipeOpacity > 0;

    return ReadingCardFrame(
      margin: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      borderColor: hasSwipeFeedback ? swipeColor : GakujiColors.softBorder,
      borderWidth: hasSwipeFeedback ? 5 : 1.2,
      isStarred: currentItem.term.marked,
      onStarTap: () => _toggleFavorite(currentItem.term),
      child: Opacity(
        opacity: contentOpacity,
        child: isWritingAnswerRevealed
            ? _writingAnswerRevealContent(prompt)
            : _writingInputContent(prompt),
      ),
    );
  }

  double _writingReadingFontSize(
    String value, {
    required int slotCount,
  }) {
    final length = value.runes.length;

    if (slotCount >= 10 || length >= 18) return 15;
    if (slotCount >= 8 || length >= 12) return 16;
    if (slotCount > 6) return 17;

    return 18;
  }

  double _writingMeaningFontSize(String value) {
    final length = value.runes.length;

    if (length >= 64) return 12;
    if (length >= 46) return 13;
    if (length >= 30) return 14;

    return 15;
  }

  double _writingAnswerFontSize(String value) {
    final length = value.runes.length;

    if (length >= 10) return 30;
    if (length >= 8) return 34;
    if (length > 6) return 38;

    return 48;
  }

  double _writingPadSizeFor(BoxConstraints constraints) {
    final maxWidth =
        constraints.maxWidth.isFinite ? constraints.maxWidth : 316.0;
    final maxHeight =
        constraints.maxHeight.isFinite ? constraints.maxHeight : 554.0;
    const fixedContentHeight = 218.0;
    final widthLimitedSize = math.min(280.0, maxWidth - 24);
    final heightLimitedSize = maxHeight - fixedContentHeight;

    return math
        .min(widthLimitedSize, heightLimitedSize)
        .clamp(190.0, 280.0)
        .toDouble();
  }

  Widget _writingReadingText(
    String reading, {
    required int slotCount,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 50),
      child: SizedBox(
        height: 40,
        child: Center(
          child: Text(
            reading,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.small.copyWith(
              fontSize: _writingReadingFontSize(
                reading,
                slotCount: slotCount,
              ),
              height: 1.08,
              color: blueCardTextEnabled
                  ? GakujiColors.reading
                  : GakujiColors.darkGray,
            ),
          ),
        ),
      ),
    );
  }

  Widget _writingMeaningText(String meaning) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SizedBox(
        height: 36,
        child: Center(
          child: Text(
            meaning,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              fontSize: _writingMeaningFontSize(meaning),
              height: 1.08,
              color: blueCardTextEnabled
                  ? GakujiColors.reading
                  : GakujiColors.darkGray,
            ),
          ),
        ),
      ),
    );
  }

  Widget _writingInputContent(WritingPrompt prompt) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padSize = _writingPadSizeFor(constraints);

        return Column(
          children: [
            const SizedBox(height: 10),
            _writingReadingText(
              prompt.reading,
              slotCount: prompt.slotCount,
            ),
            const SizedBox(height: 16),
            _answerSlotRow(prompt),
            const SizedBox(height: 12),
            _writingMeaningText(prompt.meaning),
            const Spacer(),
            _writingPad(padSize),
            const SizedBox(height: 10),
            WritingStudyActionRow(
              width: padSize,
              isCheckingAnswer: isCheckingAnswer,
              isCheckingFinalSlot: isCheckingFinalSlot,
              onClear: _clearWritingSlot,
              onCheck: _checkWritingAnswer,
            ),
          ],
        );
      },
    );
  }

  Widget _writingAnswerRevealContent(WritingPrompt prompt) {
    final answerText = writingAnswerResult?.correctAnswer ?? prompt.answer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final padSize = _writingPadSizeFor(constraints);

        return Column(
          children: [
            const SizedBox(height: 10),
            _writingReadingText(
              prompt.reading,
              slotCount: prompt.slotCount,
            ),
            const SizedBox(height: 16),
            _answerSlotRow(prompt),
            const SizedBox(height: 12),
            _writingMeaningText(prompt.meaning),
            const Spacer(),
            SizedBox(
              height: padSize + 44,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    height: 2,
                    decoration: BoxDecoration(
                      color: GakujiColors.darkGray,
                      borderRadius: BorderRadius.circular(GakujiRadius.pill),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            answerText,
                            maxLines: 1,
                            softWrap: false,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: _writingAnswerFontSize(answerText),
                              height: 1,
                              color: blueCardTextEnabled
                                  ? GakujiColors.reading
                                  : GakujiColors.deckBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 34,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Text(
                        'Swipe left for incorrect · Swipe right for correct',
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.xSmall.copyWith(
                          fontSize: 14,
                          color: blueCardTextEnabled
                              ? GakujiColors.reading
                              : GakujiColors.softGray,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _writingPad(double padSize) {
    return Center(
      child: SizedBox(
        width: padSize,
        height: padSize,
        child: Container(
          decoration: BoxDecoration(
            color: GakujiColors.whiteCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: GakujiColors.warmDivider,
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _writingPadCanvas(),
          ),
        ),
      ),
    );
  }

  Widget _writingPadCanvas() {
    return GakujiLowLatencyWritingCanvas(
      strokes: slotStrokes.isNotEmpty
          ? slotStrokes[activeSlotIndex]
          : <List<WritingPoint>>[],
      showGrid: showGrid,
      onStrokeStart: (point) {
        _addStroke(
          point,
          isStart: true,
        );
      },
      onStrokeUpdate: _addStroke,
    );
  }

  Widget _answerSlotRow(WritingPrompt prompt) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _slotMetricsFor(
          slotCount: prompt.slotCount,
          maxWidth: constraints.maxWidth,
        );

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(prompt.slotCount, (index) {
            final active = index == activeSlotIndex;
            final slotAnswer = index < slotAnswers.length
                ? slotAnswers[index]
                : null;
            final slotColor = isWritingAnswerRevealed
                ? GakujiColors.darkGray
                : active
                    ? GakujiColors.darkGray
                    : GakujiColors.softGray;

            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _selectWritingSlot(index),
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: metrics.margin),
                width: metrics.width,
                height: metrics.height,
                alignment: Alignment.center,
                color: Colors.transparent,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: metrics.characterHeight,
                      child: Center(
                        child: slotAnswer == null || slotAnswer.isEmpty
                            ? const SizedBox.shrink()
                            : Text(
                                slotAnswer,
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontSize: metrics.characterFontSize,
                                  height: 1,
                                  fontWeight: FontWeight.w600,
                                  color: blueCardTextEnabled
                                      ? GakujiColors.reading
                                      : slotColor,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(height: metrics.gap),
                    Container(
                      width: metrics.lineWidth,
                      height: metrics.lineHeight,
                      decoration: BoxDecoration(
                        color: slotColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }

  _HybridAnswerSlotMetrics _slotMetricsFor({
    required int slotCount,
    required double maxWidth,
  }) {
    if (slotCount <= 6) {
      return const _HybridAnswerSlotMetrics(
        margin: 3,
        width: 42,
        height: 52,
        characterHeight: 36,
        characterFontSize: 30,
        gap: 5,
        lineWidth: 34,
        lineHeight: 3,
      );
    }

    final availableWidth =
        maxWidth.isFinite ? math.min(maxWidth, 320.0) : 320.0;
    const margin = 2.0;
    final slotWidth = ((availableWidth - (slotCount * margin * 2)) /
            slotCount)
        .clamp(24.0, 36.0)
        .toDouble();
    final scale = (slotWidth / 42).clamp(0.0, 1.0).toDouble();

    return _HybridAnswerSlotMetrics(
      margin: margin,
      width: slotWidth,
      height: (52 * scale).clamp(42.0, 48.0).toDouble(),
      characterHeight: (36 * scale).clamp(28.0, 32.0).toDouble(),
      characterFontSize: (30 * scale).clamp(22.0, 26.0).toDouble(),
      gap: 4,
      lineWidth: (34 * scale).clamp(20.0, 30.0).toDouble(),
      lineHeight: 2.7,
    );
  }

  Widget _studyTopBar({
    required IconData leftIcon,
    required VoidCallback onLeftTap,
    required String title,
    required IconData rightIcon,
    required VoidCallback onRightTap,
  }) {
    return GakujiTopBar(
      leftIcon: leftIcon,
      leftIconSize: GakujiTopBar.iconSize,
      leftIconColor: GakujiColors.darkGray,
      onLeftTap: onLeftTap,
      title: title,
      titleStyle: TextStyle(
        fontSize: 20,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: GakujiColors.darkGray,
      ),
      rightIcon: rightIcon,
      rightIconSize: GakujiTopBar.iconSize,
      rightIconColor: GakujiColors.darkGray,
      onRightTap: onRightTap,
    );
  }

  Widget _progressBar(double progress) {
    return SizedBox(
      height: 4,
      width: double.infinity,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: 4,
            color: GakujiColors.softBorder,
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0,
              end: progress,
            ),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return FractionallySizedBox(
                widthFactor: value,
                alignment: Alignment.centerLeft,
                child: child,
              );
            },
            child: Container(
              height: 4,
              color: GakujiColors.darkGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fadingProgressBar(double progress) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: 1,
        end: 0,
      ),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeOutCubic,
      builder: (context, opacity, child) {
        return ClipRect(
          child: Align(
            heightFactor: opacity,
            child: Opacity(
              opacity: opacity,
              child: child,
            ),
          ),
        );
      },
      child: _progressBar(progress),
    );
  }

  Widget _completeScreen() {
    final total = correctCount + incorrectCount;
    final percent = total == 0 ? 0 : ((correctCount / total) * 100).round();

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            _studyTopBar(
              leftIcon: Icons.close_rounded,
              onLeftTap: _handleExit,
              title: '',
              rightIcon: Icons.menu_rounded,
              onRightTap: _openStudyOptions,
            ),
            _fadingProgressBar(1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 390 ||
                      constraints.maxHeight < 720;

                  final titleTopGap = compact ? 48.0 : 68.0;
                  final gaugeSize = compact ? 246.0 : 286.0;
                  final gaugeTopGap = compact ? 42.0 : 52.0;
                  final legendGap = compact ? 18.0 : 22.0;
                  final buttonHeight = compact ? 56.0 : 62.0;
                  final buttonGap = compact ? 18.0 : 22.0;
                  final bottomGap = compact ? 40.0 : 64.0;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                    child: Column(
                      children: [
                        SizedBox(height: titleTopGap),
                         Text(
                          'Complete!',
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.xLarge,
                        ),
                        SizedBox(height: gaugeTopGap),
                        SizedBox(
                          width: gaugeSize,
                          height: gaugeSize,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0,
                              end: 1,
                            ),
                            duration: const Duration(milliseconds: 1050),
                            curve: Curves.easeOutCubic,
                            builder: (context, animationProgress, child) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  CustomPaint(
                                    size: Size(gaugeSize, gaugeSize),
                                    painter: _HybridCompletionGaugePainter(
                                      correctCount: correctCount,
                                      incorrectCount: incorrectCount,
                                      baseColor: GakujiColors.darkGray,
                                      correctColor: correctGreenOutline,
                                      incorrectColor: incorrectRedOutline,
                                      animationProgress: animationProgress,
                                    ),
                                  ),
                                  Text(
                                    '$percent%',
                                    textScaler: TextScaler.noScaling,
                                    style: TextStyle(
                                      fontSize: compact ? 50 : 58,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                      color: GakujiColors.darkGray,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        SizedBox(height: legendGap),
                        _completionLegend(),
                        const Spacer(),
                        _completeActionButton(
                          label: 'Review Incorrect Answers',
                          color: GakujiColors.deckBlue,
                          height: buttonHeight,
                          onTap: _startIncorrectReview,
                        ),
                        SizedBox(height: buttonGap),
                        _completeActionButton(
                          label: 'Restart Deck',
                          color: GakujiColors.whiteCard,
                          textColor: GakujiColors.mediumGray,
                          outlined: true,
                          height: buttonHeight,
                          onTap: _restart,
                        ),
                        const SizedBox(height: 10),
                        _returnLastCardButton(),
                        SizedBox(height: bottomGap),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _completionLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _completionStat(
          label: 'Correct',
          count: correctCount,
          color: correctGreenOutline,
        ),
        const SizedBox(width: 28),
        _completionStat(
          label: 'Incorrect',
          count: incorrectCount,
          color: incorrectRedOutline,
        ),
      ],
    );
  }

  Widget _completionStat({
    required String label,
    required int count,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textScaler: TextScaler.noScaling,
          style: GakujiText.xSmall.copyWith(
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 34,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(GakujiRadius.pill),
          ),
          child: Text(
            '$count',
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              fontSize: 14,
              height: 1,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _completeActionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
    Color textColor = Colors.white,
    bool outlined = false,
    double height = 62,
  }) {
    return Container(
      width: double.infinity,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        border: outlined
            ? Border.all(
                color: GakujiColors.softBorder,
                width: 1.5,
              )
            : null,
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white.withValues(alpha: 0.10),
          highlightColor: Colors.white.withValues(alpha: 0.05),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.small.copyWith(
                    color: textColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _returnLastCardButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _goBack,
        borderRadius: BorderRadius.circular(20),
        splashColor: GakujiColors.deckBlue.withValues(alpha: 0.08),
        highlightColor: GakujiColors.deckBlue.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
               Icon(
                Icons.arrow_back_rounded,
                size: 22,
                color: GakujiColors.mediumGray,
              ),
              const SizedBox(width: 6),
              Text(
                'Return to Last Card',
                textScaler: TextScaler.noScaling,
                style: GakujiText.xSmall.copyWith(
                  color: GakujiColors.mediumGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(
    int count,
    Color color, {
    required bool alignLeft,
  }) {
    final isIncorrect = color == incorrectRed;
    final fillColor = isIncorrect
        ? const Color(0xFFF28F8F)
        : const Color(0xFFB8DF91);
    final outlineColor = isIncorrect
        ? const Color(0xFFD85F5F)
        : const Color(0xFF78AA50);
    final countText = '$count';
    final fontSize = countText.length >= 5
        ? 16.0
        : countText.length >= 4
            ? 17.0
            : countText.length >= 3
                ? 18.0
                : 20.0;

    return Container(
      width: 70,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: alignLeft
            ? const BorderRadius.horizontal(
                right: Radius.circular(30),
              )
            : const BorderRadius.horizontal(
                left: Radius.circular(30),
              ),
        border: Border.all(
          color: outlineColor,
          width: 2.5,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          countText,
          textScaler: TextScaler.noScaling,
          style: GakujiText.studyCounter.copyWith(
            fontSize: fontSize,
            color: outlineColor,
          ),
        ),
      ),
    );
  }

  Widget _circle(
    IconData icon,
    VoidCallback onTap,
  ) {
    return _HybridPushable(
      onTap: onTap,
      pressedOffset: 3,
      builder: (pressed) {
        return SizedBox(
          width: 46,
          height: 46,
          child: Center(
            child: Icon(
              icon,
              size: 32,
              color: GakujiColors.darkGray,
            ),
          ),
        );
      },
    );
  }
}

class _HybridPushable extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget Function(bool pressed) builder;
  final double pressedOffset;

  const _HybridPushable({
    required this.onTap,
    required this.builder,
    this.pressedOffset = 6,
  });

  @override
  State<_HybridPushable> createState() => _HybridPushableState();
}

class _HybridPushableState extends State<_HybridPushable> {
  static const Duration minimumPressDuration = Duration(milliseconds: 85);

  bool pressed = false;
  DateTime? pressedStartedAt;
  int releaseRunId = 0;

  void setPressed(bool value) {
    if (!mounted || pressed == value || widget.onTap == null) return;

    setState(() {
      pressed = value;
    });

    if (value) {
      pressedStartedAt = DateTime.now();
    }
  }

  void releaseAfterMinimumPress() {
    if (widget.onTap == null) return;

    final runId = ++releaseRunId;
    final startedAt = pressedStartedAt;
    final elapsed = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);

    final remaining = elapsed >= minimumPressDuration
        ? Duration.zero
        : minimumPressDuration - elapsed;

    Future.delayed(remaining, () {
      if (!mounted || runId != releaseRunId) return;

      setPressed(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: disabled ? null : (_) => setPressed(true),
      onTapUp: disabled ? null : (_) => releaseAfterMinimumPress(),
      onTapCancel: disabled ? null : releaseAfterMinimumPress,
      onTap: disabled ? null : widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 55),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          0,
          pressed ? widget.pressedOffset : 0,
          0,
        ),
        child: widget.builder(pressed),
      ),
    );
  }
}

class _HybridAnswerSlotMetrics {
  final double margin;
  final double width;
  final double height;
  final double characterHeight;
  final double characterFontSize;
  final double gap;
  final double lineWidth;
  final double lineHeight;

  const _HybridAnswerSlotMetrics({
    required this.margin,
    required this.width,
    required this.height,
    required this.characterHeight,
    required this.characterFontSize,
    required this.gap,
    required this.lineWidth,
    required this.lineHeight,
  });
}

class _HybridCompletionGaugePainter extends CustomPainter {
  final int correctCount;
  final int incorrectCount;
  final Color baseColor;
  final Color correctColor;
  final Color incorrectColor;
  final double animationProgress;

  const _HybridCompletionGaugePainter({
    required this.correctCount,
    required this.incorrectCount,
    required this.baseColor,
    required this.correctColor,
    required this.incorrectColor,
    required this.animationProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = correctCount + incorrectCount;

    final strokeWidth = size.width * 0.032;
    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);

    final rect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

    final basePaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final correctPaint = Paint()
      ..color = correctColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final incorrectPaint = Paint()
      ..color = incorrectColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const gapSweep = math.pi * 0.34;
    const startAngle = math.pi / 2 + gapSweep / 2;
    const totalSweep = math.pi * 2 - gapSweep;

    canvas.drawArc(
      rect,
      startAngle,
      totalSweep,
      false,
      basePaint,
    );

    if (total == 0) return;

    final progress = animationProgress.clamp(0.0, 1.0);

    final correctSweep = (correctCount / total) * totalSweep;
    final visibleSweep = totalSweep * progress;

    final animatedCorrect = math.min(
      visibleSweep,
      correctSweep,
    );

    final animatedIncorrect = math.max(
      0.0,
      visibleSweep - correctSweep,
    );

    if (animatedCorrect > 0) {
      canvas.drawArc(
        rect,
        startAngle,
        animatedCorrect,
        false,
        correctPaint,
      );
    }

    if (animatedIncorrect > 0) {
      canvas.drawArc(
        rect,
        startAngle + correctSweep,
        animatedIncorrect,
        false,
        incorrectPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _HybridCompletionGaugePainter oldDelegate,
  ) {
    return oldDelegate.correctCount != correctCount ||
        oldDelegate.incorrectCount != incorrectCount ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.correctColor != correctColor ||
        oldDelegate.incorrectColor != incorrectColor ||
        oldDelegate.animationProgress != animationProgress;
  }
}
