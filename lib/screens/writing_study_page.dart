import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';
import '../models/term.dart';
import '../models/writing_point.dart';
import '../models/writing_prompt.dart';
import '../services/deck_storage.dart';
import '../services/prompt_converter.dart';
import '../services/writing_answer_checker.dart';
import '../services/writing_recognition_service.dart';
import '../widgets/gakuji_top_bar.dart';
import 'deck_edit_page.dart';

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
  final List<WritingHistoryEntry> history = [];
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
      WritingHistoryEntry(
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
      WritingHistoryEntry(
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

  static const Color deckBlue = Color(0xFF4D7EF7);
  static const Color cardGray = Color(0xFFEDEDED);
  static const Color dividerGray = Color(0xFFE1E1E1);
  static const Color textGray = Color(0xFF6F6F6F);

  static const Color incorrectRed = Color(0xFFFF8C8C);
  static const Color incorrectRedOutline = Color(0xFFFF6F6F);
  static const Color correctGreen = Color(0xFFC8F29D);
  static const Color correctGreenOutline = Color(0xFFA9E67E);

  late WritingSessionController controller;

  late AnimationController _swipeController;
  late Animation<Offset> _swipeAnimation;

  late AnimationController _cardContentController;
  late Animation<double> _cardContentOpacity;

  bool isCheckingAnswer = false;
  bool showMenu = false;
  bool isShuffled = false;
  bool isReviewingIncorrect = false;

  bool isAnswerRevealed = false;
  WritingAnswerResult? answerResult;

  Offset revealDragOffset = Offset.zero;
  bool isRevealDragging = false;
  bool isRevealSwipingAway = false;

  String get writingGridPreferenceKey {
    return 'writing_grid_visible_${widget.deck.id}';
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
  }

  Future<void> exitDeck() async {
    if (controller.isComplete && !isReviewingIncorrect) {
      await DeckStorage.saveProgress(widget.deck.id, 0);
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
      showMenu = false;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No incorrect answers to review.'),
        ),
      );
      return;
    }

    _swipeController.stop();
    _cardContentController.stop();
    _cardContentController.value = 1;

    final reviewTerms = List<Term>.from(controller.incorrectReviewTerms);

    setState(() {
      showMenu = false;
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
      showMenu = false;
    });

    _saveGridPreference();
  }

  void toggleShuffle() {
    if (isRevealSwipingAway) return;

    _swipeController.stop();
    _cardContentController.stop();

    final nextIsShuffled = !isShuffled;

    setState(() {
      isShuffled = nextIsShuffled;
      showMenu = false;

      controller.updateShuffle(
        shuffled: isShuffled,
        saveProgress: !isReviewingIncorrect,
      );

      resetRevealState();
    });
  }

  Future<void> openDeckEdit() async {
    if (isRevealSwipingAway) return;

    setState(() {
      showMenu = false;
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
      showMenu = false;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Write in the selected box first'),
        ),
      );

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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not recognize that character. Try again.'),
        ),
      );

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

  @override
  Widget build(BuildContext context) {
    if (controller.allTerms.isEmpty && controller.activeTerms.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(
            'No terms',
            style: TextStyle(
              fontSize: 18,
              color: textGray,
            ),
          ),
        ),
      );
    }

    if (controller.isComplete) {
      return _completeScreen();
    }

    final prompt = controller.current;

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: () {
          if (showMenu) {
            setState(() => showMenu = false);
          }
        },
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  GakujiTopBar(
                    leftIcon: Icons.close,
                    onLeftTap: exitDeck,
                    title:
                        '${controller.currentIndex + 1}/${controller.totalSessionCount}',
                    titleStyle: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                    rightIcon: Icons.more_horiz,
                    onRightTap: () {
                      setState(() => showMenu = !showMenu);
                    },
                  ),
                  const SizedBox(height: 22),
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
                  const SizedBox(height: 28),
                  Expanded(
                    child: _studyCardArea(prompt),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 22,
                      right: 22,
                      bottom: 22,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _circle(Icons.undo_rounded, goBack),
                        _circle(Icons.skip_next_rounded, skipCard),
                      ],
                    ),
                  ),
                ],
              ),
              if (showMenu) _menuOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _studyCardArea(WritingPrompt prompt) {
    final rotation =
        (revealDragOffset.dx / 700).clamp(-0.35, 0.35).toDouble();

    final feedbackText = swipeFeedbackText;
    final feedbackColor = swipeFeedbackColor;
    final feedbackOpacity = swipeFeedbackOpacity;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasNextPrompt) _blankCardBehind(),
        if (!isAnswerRevealed)
          AnimatedBuilder(
            animation: _cardContentController,
            builder: (context, child) {
              return _studyCard(
                prompt,
                contentOpacity: _cardContentOpacity.value,
              );
            },
          )
        else
          Transform(
            transform: Matrix4.identity()
              ..translateByDouble(revealDragOffset.dx, revealDragOffset.dy, 0, 1)
              ..rotateZ(rotation),
            alignment: Alignment.center,
            child: GestureDetector(
              onPanStart: onRevealDragStart,
              onPanUpdate: onRevealDragUpdate,
              onPanEnd: onRevealDragEnd,
              child: AnimatedBuilder(
                animation: _cardContentController,
                builder: (context, child) {
                  return _studyCard(
                    prompt,
                    swipeLabel: feedbackText,
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

  Widget _blankCardBehind() {
    return IgnorePointer(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          color: cardGray,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 0,
              offset: Offset(0, 8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studyCard(
    WritingPrompt prompt, {
    String? swipeLabel,
    Color? swipeColor,
    double swipeOpacity = 0,
    double contentOpacity = 1,
  }) {
    final hasSwipeFeedback =
        swipeLabel != null && swipeColor != null && swipeOpacity > 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: cardGray,
        borderRadius: BorderRadius.circular(24),
        border: hasSwipeFeedback
            ? Border.all(
                color: swipeColor,
                width: 5,
              )
            : null,
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 0,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Opacity(
            opacity: contentOpacity,
            child: isAnswerRevealed
                ? _answerRevealContent(prompt)
                : _writingContent(prompt),
          ),
          if (hasSwipeFeedback)
            Center(
              child: Opacity(
                opacity: swipeOpacity,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    swipeLabel,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: swipeColor,
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _writingContent(WritingPrompt prompt) {
    return Column(
      children: [
        Text(
          prompt.reading,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(fontSize: 20),
        ),
        const SizedBox(height: 20),
        _answerSlotRow(prompt),
        const SizedBox(height: 20),
        Text(
          prompt.meaning,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(fontSize: 18),
        ),
        const Spacer(),
        Row(
          children: [
            _miniDeckButton(
              label: 'Clear',
              color: Colors.white,
              textColor: Colors.black,
              onTap: () {
                setState(() {
                  controller.clearSlot();
                });
              },
            ),
            const Spacer(),
            _miniDeckButton(
              label: isCheckingAnswer
                  ? 'Checking...'
                  : isCheckingFinalSlot
                      ? 'Submit'
                      : 'Check',
              color: deckBlue,
              textColor: Colors.white,
              width: isCheckingAnswer ? 104 : 74,
              onTap: isCheckingAnswer ? null : checkAnswer,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: SizedBox(
            width: 242,
            height: 242,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        final box =
                            context.findRenderObject() as RenderBox;
                        final point = box.globalToLocal(
                          details.globalPosition,
                        );

                        setState(() {
                          controller.addStroke(
                            point,
                            isStart: true,
                          );
                        });
                      },
                      onPanUpdate: (details) {
                        final box =
                            context.findRenderObject() as RenderBox;
                        final point = box.globalToLocal(
                          details.globalPosition,
                        );

                        setState(() {
                          controller.addStroke(point);
                        });
                      },
                      child: CustomPaint(
                        painter: _Painter(
                          controller.slotStrokes.isNotEmpty
                              ? controller
                                  .slotStrokes[controller.activeSlotIndex]
                              : <List<WritingPoint>>[],
                          controller.showGrid,
                        ),
                        child: Container(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Please write your answer in the box above',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w500,
            color: textGray,
          ),
        ),
      ],
    );
  }

  Widget _answerRevealContent(WritingPrompt prompt) {
    final result = answerResult;

    return Column(
      children: [
        Text(
          prompt.reading,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(fontSize: 20),
        ),
        const SizedBox(height: 24),
        _answerSlotRow(prompt),
        const SizedBox(height: 24),
        Text(
          prompt.meaning,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 90),
        Container(
          width: double.infinity,
          height: 3,
          color: Colors.black,
        ),
        const SizedBox(height: 40),
        Text(
          result?.correctAnswer ?? prompt.answer,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            fontSize: 48,
            color: Color(0xFF6C78FF),
          ),
        ),
        const Spacer(),
        const Text(
          'Swipe left for incorrect · Swipe right for correct',
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _answerSlotRow(WritingPrompt prompt) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(prompt.slotCount, (index) {
        final active = index == controller.activeSlotIndex;
        final slotAnswer = controller.slotAnswers[index];
        final slotColor =
            active && !isAnswerRevealed ? deckBlue : Colors.black;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (isAnswerRevealed) return;

            setState(() {
              controller.selectSlot(index);
            });
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 58,
            height: 48,
            alignment: Alignment.center,
            color: Colors.transparent,
            child: slotAnswer == null || slotAnswer.isEmpty
                ? Container(
                    width: 50,
                    height: 3,
                    decoration: BoxDecoration(
                      color: slotColor,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  )
                : Text(
                    slotAnswer,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: slotColor,
                    ),
                  ),
          ),
        );
      }),
    );
  }

  Widget _miniDeckButton({
    required String label,
    required Color color,
    required Color textColor,
    required VoidCallback? onTap,
    double width = 74,
  }) {
    final disabled = onTap == null;

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: _Pushable(
        onTap: onTap,
        pressedOffset: 6,
        builder: (pressed) {
          return Container(
            width: width,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: pressed || disabled
                  ? const []
                  : const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 0,
                        offset: Offset(0, 6),
                      ),
                    ],
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    label,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _completeScreen() {
    final total = controller.correctCount + controller.incorrectCount;
    final percent =
        total == 0 ? 0 : ((controller.correctCount / total) * 100).round();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                GakujiTopBar(
                  leftIcon: Icons.close,
                  onLeftTap: exitDeck,
                  title: '',
                  rightIcon: Icons.more_horiz,
                  onRightTap: () {
                    setState(() => showMenu = !showMenu);
                  },
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact =
                          constraints.maxWidth < 390 ||
                              constraints.maxHeight < 720;

                      final donutSize = compact ? 142.0 : 164.0;
                      final statWidth = compact ? 112.0 : 132.0;
                      final statGap = compact ? 16.0 : 24.0;
                      final titleTopGap = compact ? 64.0 : 92.0;
                      final bottomReserve = compact ? 78.0 : 92.0;

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                        child: Column(
                          children: [
                            SizedBox(height: titleTopGap),
                            const Text(
                              'Complete!',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 48,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.2,
                                color: Colors.black,
                              ),
                            ),
                            const Spacer(flex: 3),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: donutSize,
                                  height: donutSize,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CustomPaint(
                                        size: Size(donutSize, donutSize),
                                        painter: _CompletionDonutPainter(
                                          correctCount:
                                              controller.correctCount,
                                          incorrectCount:
                                              controller.incorrectCount,
                                          correctColor: correctGreen,
                                          incorrectColor: incorrectRedOutline,
                                        ),
                                      ),
                                      Text(
                                        '$percent%',
                                        textScaler: TextScaler.noScaling,
                                        style: TextStyle(
                                          fontSize: compact ? 36 : 40,
                                          height: 1,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: statGap),
                                Column(
                                  children: [
                                    _completeStatPill(
                                      label: 'Correct',
                                      value: controller.correctCount,
                                      fillColor: correctGreen,
                                      textColor: const Color(0xFF5DCB38),
                                      width: statWidth,
                                    ),
                                    const SizedBox(height: 14),
                                    _completeStatPill(
                                      label: 'Incorrect',
                                      value: controller.incorrectCount,
                                      fillColor: incorrectRed,
                                      textColor: incorrectRedOutline,
                                      width: statWidth,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Spacer(flex: 4),
                            _completeActionButton(
                              label: 'Restart Deck',
                              color: deckBlue,
                              onTap: restartDeck,
                            ),
                            const SizedBox(height: 22),
                            _completeActionButton(
                              label: 'Review Incorrect Answers',
                              color: incorrectRedOutline,
                              onTap: startIncorrectReview,
                            ),
                            SizedBox(height: bottomReserve),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            Positioned(
              left: 22,
              bottom: 18,
              child: _circle(Icons.undo_rounded, goBack),
            ),
            if (showMenu) _menuOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _completeStatPill({
    required String label,
    required int value,
    required Color fillColor,
    required Color textColor,
    required double width,
  }) {
    return Container(
      width: width,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 19,
                height: 1,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$value',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 19,
              height: 1,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _completeActionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return _Pushable(
      onTap: onTap,
      pressedOffset: 8,
      builder: (pressed) {
        return Container(
          width: double.infinity,
          height: 64,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: pressed
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 0,
                      offset: Offset(0, 8),
                    ),
                  ],
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    fontSize: 26,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _menuOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => showMenu = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.16),
          child: Center(
            child: Container(
              width: 264,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 0,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _menuItem(
                    icon: Icons.edit,
                    label: 'Edit Deck',
                    onTap: openDeckEdit,
                  ),
                  const Divider(height: 1, color: dividerGray),
                  _menuItem(
                    icon: controller.showGrid
                        ? Icons.visibility
                        : Icons.visibility_off,
                    label: controller.showGrid ? 'Hide Grid' : 'Show Grid',
                    iconColor:
                        controller.showGrid ? Colors.black : Colors.grey,
                    onTap: toggleGridFromMenu,
                  ),
                  const Divider(height: 1, color: dividerGray),
                  _menuItem(
                    icon: Icons.shuffle,
                    label: isShuffled ? 'Unshuffle' : 'Shuffle',
                    iconColor: isShuffled ? Colors.black : Colors.grey,
                    onTap: toggleShuffle,
                  ),
                  const Divider(height: 1, color: dividerGray),
                  _menuItem(
                    icon: Icons.refresh,
                    label: 'Reset Deck',
                    iconColor: Colors.grey,
                    onTap: restartDeck,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.black,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ],
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
      pressedOffset: 5,
      builder: (pressed) {
        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: pressed
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 0,
                      offset: Offset(0, 5),
                    ),
                  ],
          ),
          child: Icon(
            icon,
            size: 25,
            color: Colors.black,
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

class WritingHistoryEntry {
  final Term term;
  final bool correct;

  const WritingHistoryEntry({
    required this.term,
    required this.correct,
  });
}

/* =========================
   PAINTER
   ========================= */

class _Painter extends CustomPainter {
  final List<List<WritingPoint>> strokes;
  final bool showGrid;

  _Painter(this.strokes, this.showGrid);

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Colors.black
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final grid = Paint()
      ..color = Colors.grey
      ..strokeWidth = 1;

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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _CompletionDonutPainter extends CustomPainter {
  final int correctCount;
  final int incorrectCount;
  final Color correctColor;
  final Color incorrectColor;

  const _CompletionDonutPainter({
    required this.correctCount,
    required this.incorrectCount,
    required this.correctColor,
    required this.incorrectColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = correctCount + incorrectCount;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = size.width * 0.19;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius - strokeWidth / 2,
    );

    final correctPaint = Paint()
      ..color = correctColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final incorrectPaint = Paint()
      ..color = incorrectColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    if (total == 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2,
        false,
        incorrectPaint,
      );
      return;
    }

    final correctSweep = (correctCount / total) * math.pi * 2;
    final incorrectSweep = math.pi * 2 - correctSweep;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      correctSweep,
      false,
      correctPaint,
    );

    canvas.drawArc(
      rect,
      -math.pi / 2 + correctSweep,
      incorrectSweep,
      false,
      incorrectPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CompletionDonutPainter oldDelegate) {
    return oldDelegate.correctCount != correctCount ||
        oldDelegate.incorrectCount != incorrectCount ||
        oldDelegate.correctColor != correctColor ||
        oldDelegate.incorrectColor != incorrectColor;
  }
}