import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';
import '../models/term.dart';
import '../models/writing_point.dart';
import '../models/writing_prompt.dart';
import '../services/deck_storage.dart';
import '../services/gakuji_user_data_store.dart';
import '../services/prompt_converter.dart';
import '../services/writing_answer_checker.dart';
import '../services/writing_recognition_service.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import '../widgets/writing_study_card.dart';
import 'deck_edit_page.dart';
import '../widgets/gakuji_options_sheet.dart';

class WritingStudyPage extends StatefulWidget {
  final List<Term> terms;
  final Deck deck;
  final bool initialIsShuffled;

  const WritingStudyPage({
    super.key,
    required this.terms,
    required this.deck,
    this.initialIsShuffled = false,
  });

  @override
  State<WritingStudyPage> createState() => _WritingStudyPageState();
}

/* =========================
   SESSION CONTROLLER
   ========================= */

class WritingSessionController {
  WritingSessionController({
    required List<Term> terms,
    required this.deckId,
  })  : allTerms = List<Term>.from(terms),
        activeTerms = List<Term>.from(terms) {
    _initSlots();
  }

  List<Term> allTerms;
  List<Term> activeTerms;

  final List<Term> answeredTerms = [];
  final List<_WritingHistoryEntry> history = [];
  final List<Term> incorrectReviewTerms = [];

  final String deckId;

  int correctCount = 0;
  int incorrectCount = 0;

  List<List<List<WritingPoint>>> slotStrokes = [];
  List<String?> slotAnswers = [];

  int activeSlotIndex = 0;

  final Set<String> starred = {};

  bool showGrid = true;
  bool hasChecked = false;

  int get currentIndex => answeredTerms.length;
  int get totalSessionCount => answeredTerms.length + activeTerms.length;

  bool get isComplete => activeTerms.isEmpty && allTerms.isNotEmpty;

  Term get currentTerm => activeTerms.first;
  WritingPrompt get current => PromptConverter.fromTerm(currentTerm);

  List<String> get currentAnswerCharacters {
    if (activeTerms.isEmpty || isComplete) return [];

    return current.answer.runes.map((rune) {
      return String.fromCharCode(rune);
    }).toList();
  }

  String get activeCorrectCharacter {
    final characters = currentAnswerCharacters;

    if (characters.isEmpty) return '';

    return characters[activeSlotIndex];
  }

  String get submittedAnswer {
    return slotAnswers.map((answer) => answer ?? '').join();
  }

  bool _isSameTerm(Term first, Term second) {
    return first.kanji == second.kanji &&
        first.reading == second.reading &&
        first.meaning == second.meaning;
  }

  int _termOrderIndex(Term term) {
    final index = allTerms.indexWhere(
      (savedTerm) => _isSameTerm(savedTerm, term),
    );

    return index == -1 ? 999999 : index;
  }

  void _sortActiveTermsToBaseOrder() {
    activeTerms.sort((a, b) {
      return _termOrderIndex(a).compareTo(_termOrderIndex(b));
    });
  }

  void _addIncorrectReviewTerm(Term term) {
    final alreadyAdded = incorrectReviewTerms.any(
      (savedTerm) => _isSameTerm(savedTerm, term),
    );

    if (!alreadyAdded) {
      incorrectReviewTerms.add(term);
    }
  }

  void _removeIncorrectReviewTerm(Term term) {
    final index = incorrectReviewTerms.indexWhere(
      (savedTerm) => _isSameTerm(savedTerm, term),
    );

    if (index != -1) {
      incorrectReviewTerms.removeAt(index);
    }
  }

  void _removeAnsweredTerm(Term term) {
    if (answeredTerms.isEmpty) return;

    final lastTerm = answeredTerms.last;

    if (_isSameTerm(lastTerm, term)) {
      answeredTerms.removeLast();
      return;
    }

    final index = answeredTerms.lastIndexWhere(
      (savedTerm) => _isSameTerm(savedTerm, term),
    );

    if (index != -1) {
      answeredTerms.removeAt(index);
    }
  }

  void _saveProgress(bool saveProgress) {
    if (!saveProgress) return;

    DeckStorage.saveProgress(deckId, answeredTerms.length);
    GakujiUserDataStore.scheduleSave();
  }

  void _initSlots() {
    if (activeTerms.isEmpty || isComplete) {
      slotStrokes = List.generate(
        1,
        (_) => <List<WritingPoint>>[],
      );

      slotAnswers = [];
      activeSlotIndex = 0;
      hasChecked = false;
      return;
    }

    final count = current.slotCount;

    slotStrokes = List.generate(
      count,
      (_) => <List<WritingPoint>>[],
    );

    slotAnswers = List<String?>.filled(count, null);

    activeSlotIndex = 0;
    hasChecked = false;
  }

  void restoreProgress(
    int index, {
    required bool shuffle,
  }) {
    if (allTerms.isEmpty) {
      answeredTerms.clear();
      activeTerms = [];
      correctCount = 0;
      incorrectCount = 0;
      history.clear();
      incorrectReviewTerms.clear();
      _initSlots();
      return;
    }

    final savedCount = index.clamp(0, allTerms.length).toInt();

    answeredTerms
      ..clear()
      ..addAll(allTerms.take(savedCount));

    activeTerms = List<Term>.from(allTerms.skip(savedCount));

    if (shuffle) {
      activeTerms.shuffle();
    }

    correctCount = 0;
    incorrectCount = 0;
    history.clear();
    incorrectReviewTerms.clear();

    _initSlots();
  }

  void replaceSessionTerms(
    List<Term> newTerms, {
    required bool shuffle,
    bool saveProgress = true,
    bool clearIncorrectReviewTerms = true,
  }) {
    allTerms = List<Term>.from(newTerms);
    activeTerms = List<Term>.from(allTerms);

    if (shuffle) {
      activeTerms.shuffle();
    }

    answeredTerms.clear();
    history.clear();

    correctCount = 0;
    incorrectCount = 0;

    if (clearIncorrectReviewTerms) {
      incorrectReviewTerms.clear();
    }

    _initSlots();

    _saveProgress(saveProgress);
  }

  void updateShuffle({
    required bool shuffled,
    required bool saveProgress,
  }) {
    if (activeTerms.isEmpty) return;

    if (shuffled) {
      activeTerms.shuffle();
    } else {
      _sortActiveTermsToBaseOrder();
    }

    _initSlots();

    _saveProgress(saveProgress);
  }

  void selectSlot(int index) {
    if (index < 0 || index >= slotStrokes.length) return;

    activeSlotIndex = index;
  }

  void addStroke(Offset point, {bool isStart = false}) {
    if (slotStrokes.isEmpty) _initSlots();

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

  void clearSlot() {
    if (slotStrokes.isEmpty) return;

    slotStrokes[activeSlotIndex].clear();

    if (activeSlotIndex < slotAnswers.length) {
      slotAnswers[activeSlotIndex] = null;
    }
  }

  void clearAllSlots() {
    _initSlots();
  }

  void setSlotAnswer(int index, String answer) {
    if (index < 0 || index >= slotAnswers.length) return;

    slotAnswers[index] = answer;
  }

  void moveToNextEmptySlot() {
    final nextIndex = slotAnswers.indexWhere(
      (answer) => answer == null || answer.isEmpty,
    );

    if (nextIndex != -1) {
      activeSlotIndex = nextIndex;
    }
  }

  void toggleGrid() {
    showGrid = !showGrid;
  }

  void toggleStar() {
    final id = current.id;
    starred.contains(id) ? starred.remove(id) : starred.add(id);
  }

  bool isStarred() => starred.contains(current.id);

  void answer(
    bool correct, {
    bool saveProgress = true,
  }) {
    if (activeTerms.isEmpty) return;

    final answeredTerm = activeTerms.first;

    history.add(
      _WritingHistoryEntry(
        term: answeredTerm,
        correct: correct,
      ),
    );

    answeredTerms.add(answeredTerm);
    activeTerms.removeAt(0);

    if (correct) {
      correctCount++;
    } else {
      incorrectCount++;
      _addIncorrectReviewTerm(answeredTerm);
    }

    _initSlots();

    _saveProgress(saveProgress);
  }

  void skip({
    bool saveProgress = true,
  }) {
    if (activeTerms.isEmpty) return;

    final skippedTerm = activeTerms.first;

    history.add(
      _WritingHistoryEntry(
        term: skippedTerm,
        correct: false,
      ),
    );

    answeredTerms.add(skippedTerm);
    activeTerms.removeAt(0);

    incorrectCount++;
    _addIncorrectReviewTerm(skippedTerm);

    _initSlots();

    _saveProgress(saveProgress);
  }

  void previousCard({
    bool saveProgress = true,
  }) {
    if (history.isEmpty) return;

    final last = history.removeLast();

    if (last.correct) {
      correctCount--;
    } else {
      incorrectCount--;
      _removeIncorrectReviewTerm(last.term);
    }

    _removeAnsweredTerm(last.term);
    activeTerms.insert(0, last.term);

    _initSlots();

    _saveProgress(saveProgress);
  }
}

/* =========================
   PAGE
   ========================= */

class _WritingStudyPageState extends State<WritingStudyPage>
    with TickerProviderStateMixin {
  static const Duration _cardReturnDuration = Duration(milliseconds: 320);
  static const Duration _cardExitDuration = Duration(milliseconds: 140);
  static const Duration _cardContentFadeDuration = Duration(milliseconds: 120);

  static const Color incorrectRed = Color(0xFFF6A3A3);
  static const Color incorrectRedOutline = Color(0xFFE06F6F);

  static const Color correctGreen = Color(0xFFC5E7A5);
  static const Color correctGreenOutline = Color(0xFF8DBB66);

  late WritingSessionController controller;

  late AnimationController _swipeController;
  late Animation<Offset> _swipeAnimation;

  late AnimationController _cardContentController;
  late Animation<double> _cardContentOpacity;

  bool isCheckingAnswer = false;
  bool isShuffled = false;
  bool isReviewingIncorrect = false;

  bool isAnswerRevealed = false;
  WritingAnswerResult? answerResult;

  Offset revealDragOffset = Offset.zero;
  bool isRevealDragging = false;
  bool isRevealSwipingAway = false;

  double get deckProgress {
    final total = controller.totalSessionCount;

    if (total <= 0) return 0;

    return (controller.currentIndex / total).clamp(0.0, 1.0).toDouble();
  }

  String get writingGridPreferenceKey {
    return 'writing_grid_visible_${widget.deck.id}';
  }

  void scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
  }

  @override
  void initState() {
    super.initState();

    isShuffled = widget.initialIsShuffled;

    controller = WritingSessionController(
      terms: widget.terms,
      deckId: widget.deck.id,
    );

    if (isShuffled) {
      controller.updateShuffle(
        shuffled: true,
        saveProgress: false,
      );
    }

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

    _loadProgress();
  }

  @override
  void dispose() {
    _swipeController.removeListener(_handleSwipeAnimationTick);
    _cardContentController.dispose();
    _swipeController.dispose();
    super.dispose();
  }

  void _handleSwipeAnimationTick() {
    if (!mounted) return;

    setState(() {
      revealDragOffset = _swipeAnimation.value;
    });
  }

  Future<void> _loadProgress() async {
    final saved = await DeckStorage.loadProgress(widget.deck.id);
    final prefs = await SharedPreferences.getInstance();
    final savedGridVisible = prefs.getBool(writingGridPreferenceKey);

    if (!mounted || isReviewingIncorrect) return;

    setState(() {
      controller.restoreProgress(
        saved,
        shuffle: isShuffled,
      );

      if (savedGridVisible != null) {
        controller.showGrid = savedGridVisible;
      }

      resetRevealState();
    });
  }

  Future<void> _saveGridPreference() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      writingGridPreferenceKey,
      controller.showGrid,
    );

    scheduleUserDataSave();
  }

  Future<void> exitDeck() async {
    if (controller.isComplete && !isReviewingIncorrect) {
      await DeckStorage.saveProgress(widget.deck.id, 0);
      scheduleUserDataSave();
    }

    if (!mounted) return;

    Navigator.pop(context);
  }

  String? get swipeFeedbackText {
    if (revealDragOffset.dx > 32) return 'Know';
    if (revealDragOffset.dx < -32) return 'Still learning';

    return null;
  }

  Color? get swipeFeedbackColor {
    if (revealDragOffset.dx > 32) return correctGreenOutline;
    if (revealDragOffset.dx < -32) return incorrectRedOutline;

    return null;
  }

  double get swipeFeedbackOpacity {
    final opacity =
        ((revealDragOffset.dx.abs() - 30) / 90).clamp(0.0, 1.0);

    return opacity.toDouble();
  }

  bool get hasNextPrompt {
    return controller.activeTerms.length > 1;
  }

  bool get isCheckingFinalSlot {
    if (controller.slotAnswers.isEmpty) return false;

    final emptyIndexes = <int>[];

    for (int i = 0; i < controller.slotAnswers.length; i++) {
      final answer = controller.slotAnswers[i];

      if (answer == null || answer.isEmpty) {
        emptyIndexes.add(i);
      }
    }

    return emptyIndexes.length == 1 &&
        emptyIndexes.first == controller.activeSlotIndex;
  }

  void resetRevealState({bool resetContentOpacity = true}) {
    isAnswerRevealed = false;
    answerResult = null;
    revealDragOffset = Offset.zero;
    isRevealDragging = false;
    isRevealSwipingAway = false;
    isCheckingAnswer = false;

    if (resetContentOpacity) {
      _cardContentController.value = 1;
    }
  }

  void restartDeck() {
    _swipeController.stop();
    _cardContentController.stop();

    setState(() {
      isReviewingIncorrect = false;
      controller.replaceSessionTerms(
        widget.terms,
        shuffle: isShuffled,
        saveProgress: true,
      );
      resetRevealState();
    });
  }

  void startIncorrectReview() {
    if (controller.incorrectReviewTerms.isEmpty) {
      _showFloatingMessage('No incorrect answers to review.');
      return;
    }

    _swipeController.stop();
    _cardContentController.stop();
    _cardContentController.value = 1;

    final reviewTerms = List<Term>.from(controller.incorrectReviewTerms);

    setState(() {
      isReviewingIncorrect = true;
      controller.replaceSessionTerms(
        reviewTerms,
        shuffle: isShuffled,
        saveProgress: false,
      );
      resetRevealState();
    });
  }

  void toggleGridFromMenu() {
    if (isRevealSwipingAway) return;

    setState(() {
      controller.toggleGrid();
    });

    _saveGridPreference();
  }

  void openStudyOptions() {
    showGakujiOptionsSheet(
      context: context,
      title: 'Study Options',
      sectionsBuilder: (context) => [
        GakujiOptionsSheetSection(
          title: 'Writing',
          items: [
            GakujiOptionsSheetItem(
              icon: controller.showGrid
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              label: controller.showGrid ? 'Hide Grid' : 'Show Grid',
              iconColor: controller.showGrid
                  ? GakujiColors.darkGray
                  : GakujiColors.mediumGray,
              onTap: toggleGridFromMenu,
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
              onTap: toggleShuffle,
            ),
            GakujiOptionsSheetItem(
              icon: Icons.refresh_rounded,
              label: 'Reset Deck',
              iconColor: GakujiColors.mediumGray,
              onTap: restartDeck,
            ),
          ],
        ),
      ],
    );
  }

  void toggleShuffle() {
    if (isRevealSwipingAway) return;

    _swipeController.stop();
    _cardContentController.stop();

    final nextIsShuffled = !isShuffled;

    setState(() {
      isShuffled = nextIsShuffled;

      controller.updateShuffle(
        shuffled: isShuffled,
        saveProgress: !isReviewingIncorrect,
      );

      resetRevealState();
    });

    DeckStorage.saveShuffle(widget.deck.id, isShuffled);
    scheduleUserDataSave();
  }

  Future<void> openDeckEdit() async {
    if (isRevealSwipingAway) return;

    setState(() {
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeckEditPage(deck: widget.deck),
      ),
    );

    if (!mounted) return;

    _swipeController.stop();
    _cardContentController.stop();

    setState(() {
      isReviewingIncorrect = false;
      controller.replaceSessionTerms(
        widget.terms,
        shuffle: isShuffled,
        saveProgress: true,
      );
      resetRevealState();
    });
  }

  void goBack() {
    if (isRevealSwipingAway) return;

    _swipeController.stop();
    _cardContentController.stop();

    setState(() {
      controller.previousCard(
        saveProgress: !isReviewingIncorrect,
      );
      resetRevealState();
    });
  }

  void skipCard() {
    if (isRevealSwipingAway) return;

    _swipeController.stop();
    _cardContentController.stop();

    setState(() {
      controller.skip(
        saveProgress: !isReviewingIncorrect,
      );
      resetRevealState();
    });
  }

  void submitRevealedAnswer(bool correct) {
    final shouldFadeInNextPrompt = controller.activeTerms.length > 1;

    if (shouldFadeInNextPrompt) {
      _cardContentController.value = 0;
    } else {
      _cardContentController.value = 1;
    }

    setState(() {
      controller.answer(
        correct,
        saveProgress: !isReviewingIncorrect,
      );
      resetRevealState(resetContentOpacity: false);
    });

    if (shouldFadeInNextPrompt) {
      _cardContentController.forward(from: 0);
    }
  }

  void onRevealDragStart(DragStartDetails details) {
    if (isRevealSwipingAway) return;

    setState(() {
      isRevealDragging = true;
    });
  }

  void onRevealDragUpdate(DragUpdateDetails details) {
    if (isRevealSwipingAway) return;

    setState(() {
      revealDragOffset = Offset(
        revealDragOffset.dx + details.delta.dx,
        revealDragOffset.dy + details.delta.dy,
      );

      isRevealDragging = true;
    });
  }

  void onRevealDragEnd(DragEndDetails details) {
    if (isRevealSwipingAway) return;

    const swipeThreshold = 120.0;

    if (revealDragOffset.dx > swipeThreshold) {
      animateRevealCardOffscreen(correct: true);
    } else if (revealDragOffset.dx < -swipeThreshold) {
      animateRevealCardOffscreen(correct: false);
    } else {
      animateRevealCardBack();
    }
  }

  Future<void> animateRevealCardBack() async {
    final startOffset = revealDragOffset;

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
      isRevealSwipingAway = true;
    });

    await _swipeController.forward();

    if (!mounted) return;

    setState(() {
      revealDragOffset = Offset.zero;
      isRevealDragging = false;
      isRevealSwipingAway = false;
    });
  }

  Future<void> animateRevealCardOffscreen({
    required bool correct,
  }) async {
    final screenWidth = MediaQuery.of(context).size.width;

    _swipeController.duration = _cardExitDuration;

    final endOffset = Offset(
      correct ? screenWidth * 1.5 : -screenWidth * 1.5,
      revealDragOffset.dy * 0.45,
    );

    _swipeAnimation = Tween<Offset>(
      begin: revealDragOffset,
      end: endOffset,
    ).animate(
      CurvedAnimation(
        parent: _swipeController,
        curve: Curves.easeOutQuad,
      ),
    );

    _swipeController.reset();

    setState(() {
      isRevealSwipingAway = true;
    });

    await _swipeController.forward();

    if (!mounted) return;

    submitRevealedAnswer(correct);
  }

  Future<void> checkAnswer() async {
    if (isCheckingAnswer || isAnswerRevealed) return;

    final activeSlotStrokes =
        controller.slotStrokes[controller.activeSlotIndex];

    final hasInput = WritingRecognitionService.hasStrokesInSlot(
      activeSlotStrokes,
    );

    if (!hasInput) {
      _showFloatingMessage('Write in the selected box first.');
      return;
    }

    setState(() {
      controller.hasChecked = true;
      isCheckingAnswer = true;
    });

    final recognizedCharacter =
        await WritingRecognitionService.recognizeSlot(
      slotStrokes: activeSlotStrokes,
      mockCharacter: controller.activeCorrectCharacter,
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
      controller.setSlotAnswer(
        controller.activeSlotIndex,
        recognizedCharacter,
      );

      final allSlotsFilled = WritingRecognitionService.areAllSlotsFilled(
        controller.slotAnswers,
      );

      if (allSlotsFilled) {
        final submittedAnswer =
            WritingRecognitionService.buildSubmittedAnswer(
          controller.slotAnswers,
        );

        answerResult = WritingAnswerChecker.check(
          submittedAnswer: submittedAnswer,
          correctAnswer: controller.current.answer,
        );

        isAnswerRevealed = true;
      } else {
        controller.moveToNextEmptySlot();
      }

      isCheckingAnswer = false;
    });
  }

  void _showFloatingMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1500),
          backgroundColor: Colors.black.withOpacity(0.86),
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
    if (controller.allTerms.isEmpty && controller.activeTerms.isEmpty) {
      return Scaffold(
        backgroundColor: GakujiColors.warmBackground,
        body: Center(
          child: Text(
            'No terms',
            textScaler: TextScaler.noScaling,
            style: GakujiText.small,
          ),
        ),
      );
    }

    if (controller.isComplete) {
      return _completeScreen();
    }

    final prompt = controller.current;
    final currentPosition = controller.currentIndex + 1;
    final totalPosition = controller.totalSessionCount;

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: GestureDetector(
        onTap: () {
        },
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _studyTopBar(
                    leftIcon: Icons.close_rounded,
                    onLeftTap: exitDeck,
                    title: '$currentPosition/$totalPosition',
                    rightIcon: Icons.menu_rounded,
                    onRightTap: openStudyOptions,
                  ),
                  _progressBar(deckProgress),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _pill(
                        controller.incorrectCount,
                        incorrectRed,
                        alignLeft: true,
                      ),
                      _pill(
                        controller.correctCount,
                        correctGreen,
                        alignLeft: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _studyCardArea(prompt),
                  ),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _circle(Icons.undo_rounded, goBack),
                        _circle(Icons.redo_rounded, skipCard),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
      leftIconSize: 34,
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
      rightIconSize: 36,
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

  Widget _studyCardArea(WritingPrompt prompt) {
    final rotation =
        (revealDragOffset.dx / 700).clamp(-0.35, 0.35).toDouble();

    final feedbackColor = swipeFeedbackColor;
    final feedbackOpacity = swipeFeedbackOpacity;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasNextPrompt) const WritingStudyBlankCard(),
        if (!isAnswerRevealed)
          AnimatedBuilder(
            animation: _cardContentController,
            builder: (context, child) {
              return _buildWritingStudyCard(
                prompt,
                contentOpacity: _cardContentOpacity.value,
              );
            },
          )
        else
          Transform(
            transform: Matrix4.identity()
              ..translate(revealDragOffset.dx, revealDragOffset.dy)
              ..rotateZ(rotation),
            alignment: Alignment.center,
            child: GestureDetector(
              onPanStart: onRevealDragStart,
              onPanUpdate: onRevealDragUpdate,
              onPanEnd: onRevealDragEnd,
              child: AnimatedBuilder(
                animation: _cardContentController,
                builder: (context, child) {
                  return _buildWritingStudyCard(
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

  Widget _buildWritingStudyCard(
    WritingPrompt prompt, {
    Color? swipeColor,
    double swipeOpacity = 0,
    double contentOpacity = 1,
  }) {
    final activeStrokes = controller.slotStrokes.isNotEmpty
        ? controller.slotStrokes[controller.activeSlotIndex]
        : <List<WritingPoint>>[];

    return WritingStudyCard(
      prompt: prompt,
      isAnswerRevealed: isAnswerRevealed,
      answerResult: answerResult,
      slotAnswers: controller.slotAnswers,
      activeSlotIndex: controller.activeSlotIndex,
      activeSlotStrokes: activeStrokes,
      showGrid: controller.showGrid,
      isCheckingAnswer: isCheckingAnswer,
      isCheckingFinalSlot: isCheckingFinalSlot,
      swipeColor: swipeColor,
      swipeOpacity: swipeOpacity,
      contentOpacity: contentOpacity,
      onSelectSlot: (index) {
        if (isAnswerRevealed) return;

        setState(() {
          controller.selectSlot(index);
        });
      },
      onClear: () {
        setState(() {
          controller.clearSlot();
        });
      },
      onCheck: isCheckingAnswer ? null : checkAnswer,
      onStrokeStart: (point) {
        setState(() {
          controller.addStroke(
            point,
            isStart: true,
          );
        });
      },
      onStrokeUpdate: (point) {
        setState(() {
          controller.addStroke(point);
        });
      },
    );
  }

  Widget _completeScreen() {
    final total = controller.correctCount + controller.incorrectCount;
    final percent =
        total == 0 ? 0 : ((controller.correctCount / total) * 100).round();

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _studyTopBar(
                  leftIcon: Icons.close_rounded,
                  onLeftTap: exitDeck,
                  title: '',
                  rightIcon: Icons.menu_rounded,
                  onRightTap: () {
                  },
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
                      final bottomGap = compact ? 52.0 : 64.0;

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
                                        painter: _CompletionGaugePainter(
                                          correctCount:
                                              controller.correctCount,
                                          incorrectCount:
                                              controller.incorrectCount,
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
                              onTap: startIncorrectReview,
                            ),
                            SizedBox(height: buttonGap),
                            _completeActionButton(
                              label: 'Restart Deck',
                              color: GakujiColors.whiteCard,
                              textColor: GakujiColors.mediumGray,
                              outlined: true,
                              height: buttonHeight,
                              onTap: restartDeck,
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
          count: controller.correctCount,
          color: correctGreenOutline,
        ),
        const SizedBox(width: 28),
        _completionStat(
          label: 'Incorrect',
          count: controller.incorrectCount,
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
          splashColor: Colors.white.withOpacity(0.10),
          highlightColor: Colors.white.withOpacity(0.05),
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
        onTap: goBack,
        borderRadius: BorderRadius.circular(20),
        splashColor: GakujiColors.deckBlue.withOpacity(0.08),
        highlightColor: GakujiColors.deckBlue.withOpacity(0.04),
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

    return Container(
      width: 78,
      height: 34,
      padding: EdgeInsets.only(
        left: alignLeft ? 24 : 0,
        right: alignLeft ? 0 : 24,
      ),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      decoration: BoxDecoration(
        color: color,
        borderRadius: alignLeft
            ? const BorderRadius.horizontal(
                right: Radius.circular(30),
              )
            : const BorderRadius.horizontal(
                left: Radius.circular(30),
              ),
        border: Border.all(
          color: isIncorrect ? incorrectRedOutline : correctGreenOutline,
          width: 3,
        ),
      ),
      child: Text(
        '$count',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 24,
          height: 1,
          fontWeight: FontWeight.w700,
          color: isIncorrect ? incorrectRedOutline : correctGreenOutline,
       ),
     ),
   );
 }

  Widget _circle(IconData icon, VoidCallback onTap) {
    return _Pushable(
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

class _Pushable extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget Function(bool pressed) builder;
  final double pressedOffset;

  const _Pushable({
    required this.onTap,
    required this.builder,
    this.pressedOffset = 6,
  });

  @override
  State<_Pushable> createState() => _PushableState();
}

class _PushableState extends State<_Pushable> {
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

class _WritingHistoryEntry {
  final Term term;
  final bool correct;

  const _WritingHistoryEntry({
    required this.term,
    required this.correct,
  });
}

/* =========================
   PAINTER
   ========================= */

class _CompletionGaugePainter extends CustomPainter {
  final int correctCount;
  final int incorrectCount;
  final Color baseColor;
  final Color correctColor;
  final Color incorrectColor;
  final double animationProgress;

  const _CompletionGaugePainter({
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

    // Bottom-centered opening matching the completion design.
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
  bool shouldRepaint(covariant _CompletionGaugePainter oldDelegate) {
    return oldDelegate.correctCount != correctCount ||
        oldDelegate.incorrectCount != incorrectCount ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.correctColor != correctColor ||
        oldDelegate.incorrectColor != incorrectColor ||
        oldDelegate.animationProgress != animationProgress;
  }
}