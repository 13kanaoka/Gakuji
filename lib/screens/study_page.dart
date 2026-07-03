import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/reading_card_edit_data.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../services/deck_storage.dart';
import '../services/reading_card_edit_storage.dart';
import '../widgets/gakuji_top_bar.dart';
import 'deck_edit_page.dart';

class StudyPage extends StatefulWidget {
  final List<Term> terms;
  final Deck deck;
  final bool initialIsShuffled;
  final bool initialShowFurigana;
  final bool initialTermFirst;

  const StudyPage({
    super.key,
    required this.terms,
    required this.deck,
    this.initialIsShuffled = false,
    this.initialShowFurigana = true,
    this.initialTermFirst = true,
  });

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> with TickerProviderStateMixin {
  static const Duration _cardReturnDuration = Duration(milliseconds: 320);
  static const Duration _cardExitDuration = Duration(milliseconds: 140);
  static const Duration _cardContentFadeDuration = Duration(milliseconds: 120);
  static const Duration _previousCardReturnDuration =
      Duration(milliseconds: 180);

  static const Color deckBlue = Color(0xFF4D7EF7);
  static const Color cardGray = Color(0xFFEDEDED);
  static const Color dividerGray = Color(0xFFE1E1E1);
  static const Color textGray = Color(0xFF6F6F6F);

  static const Color incorrectRed = Color(0xFFFF8C8C);
  static const Color incorrectRedOutline = Color(0xFFFF6F6F);
  static const Color correctGreen = Color(0xFFC8F29D);
  static const Color correctGreenOutline = Color(0xFFA9E67E);

  late List<Term> allTerms;
  late List<Term> activeTerms;

  final List<Term> answeredTerms = [];
  final List<_StudyHistoryEntry> history = [];
  final List<Term> incorrectReviewTerms = [];

  final Map<String, ReadingCardEditData> readingCardEdits = {};
  final Set<String> savedReadingCardEditTermIds = {};

  int correctCount = 0;
  int incorrectCount = 0;

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  late AnimationController _swipeController;
  late Animation<Offset> _swipeAnimation;

  late AnimationController _cardContentController;
  late Animation<double> _cardContentOpacity;

  late AnimationController _previousCardReturnController;
  late Animation<double> _previousCardReturnAnimation;

  Offset dragOffset = Offset.zero;
  bool isDragging = false;
  bool isSwipingAway = false;

  bool isReturningPreviousCard = false;
  double previousCardReturnDirection = 1;
  Term? outgoingCardTerm;
  int _previousCardReturnRunId = 0;

  bool hasCompletedDeck = false;
  bool isReviewingIncorrect = false;

  bool showMenu = false;
  bool isShuffled = false;
  bool showFurigana = true;
  bool termFirst = true;

  @override
  void initState() {
    super.initState();

    isShuffled = widget.initialIsShuffled;
    showFurigana = widget.initialShowFurigana;
    termFirst = widget.initialTermFirst;

    allTerms = List.from(widget.terms);
    activeTerms = List.from(allTerms);

    if (isShuffled) {
      activeTerms.shuffle();
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

    _previousCardReturnController = AnimationController(
      vsync: this,
      duration: _previousCardReturnDuration,
    );

    _previousCardReturnAnimation = CurvedAnimation(
      parent: _previousCardReturnController,
      curve: Curves.easeOutCubic,
    );

    _previousCardReturnController.addListener(
      _handlePreviousCardReturnAnimationTick,
    );

    _loadProgress();
    _loadReadingCardEdits();
  }

  @override
  void dispose() {
    _previousCardReturnController.removeListener(
      _handlePreviousCardReturnAnimationTick,
    );
    _swipeController.removeListener(_handleSwipeAnimationTick);
    _previousCardReturnController.dispose();
    _cardContentController.dispose();
    _swipeController.dispose();
    _flipController.dispose();
    super.dispose();
  }

  void _handleSwipeAnimationTick() {
    if (!mounted) return;

    setState(() {
      dragOffset = _swipeAnimation.value;
    });
  }

  void _handlePreviousCardReturnAnimationTick() {
    if (!mounted) return;

    setState(() {});
  }

  Future<void> _loadProgress() async {
    final saved = await DeckStorage.loadProgress(widget.deck.id);

    if (!mounted || isReviewingIncorrect) return;

    final savedCount = saved.clamp(0, allTerms.length).toInt();

    setState(() {
      answeredTerms
        ..clear()
        ..addAll(allTerms.take(savedCount));

      activeTerms = List<Term>.from(allTerms.skip(savedCount));

      if (isShuffled) {
        activeTerms.shuffle();
      }

      hasCompletedDeck = activeTerms.isEmpty && allTerms.isNotEmpty;
      _cardContentController.value = 1;
    });
  }

  Future<void> _loadReadingCardEdits() async {
    final loadedEdits = <String, ReadingCardEditData>{};
    final loadedSavedIds = <String>{};

    final termsToLoad = List<Term>.from(widget.deck.terms);

    for (final term in termsToLoad) {
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

  void _saveProgress() {
    if (isReviewingIncorrect) return;

    DeckStorage.saveProgress(widget.deck.id, answeredTerms.length);
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

  int get totalSessionCount => answeredTerms.length + activeTerms.length;

  bool get isComplete => activeTerms.isEmpty && allTerms.isNotEmpty;

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

  bool _hasSavedCardEdit(Term term) {
    return savedReadingCardEditTermIds.contains(term.id);
  }

  ReadingCardEditData? _cardEditFor(Term term) {
    return readingCardEdits[term.id];
  }

  List<String> _studyGlossesFor(Term term) {
    final editData = _cardEditFor(term);

    if (_hasSavedCardEdit(term)) {
      return editData?.selectedGlosses ?? const [];
    }

    final meaning = term.meaning.trim();

    if (meaning.isNotEmpty) {
      return [meaning];
    }

    final cardMeaning = term.cardMeaning.trim();

    if (cardMeaning.isNotEmpty) {
      return [cardMeaning];
    }

    return const [];
  }

  String _studyNoteFor(Term term) {
    if (!_hasSavedCardEdit(term)) return '';

    return _cardEditFor(term)?.note.trim() ?? '';
  }

  List<DictionaryExample> _studyExamplesFor(Term term) {
    final editData = _cardEditFor(term);

    if (!_hasSavedCardEdit(term) || editData == null) {
      return const [];
    }

    return ReadingCardEditData.examplesFromKeys(
      examples: term.examples,
      selectedExampleKeys: editData.selectedExampleKeys,
    );
  }

  bool _studyPhotoEnabledFor(Term term) {
    if (!_hasSavedCardEdit(term)) return false;

    return _cardEditFor(term)?.photoEnabled ?? false;
  }

  String? _studyPhotoPathFor(Term term) {
    if (!_studyPhotoEnabledFor(term)) return null;

    final path = _cardEditFor(term)?.photoPath?.trim();

    if (path == null || path.isEmpty) return null;

    return path;
  }

  bool _studyPhotoExistsFor(Term term) {
    final path = _studyPhotoPathFor(term);

    if (path == null) return false;

    return File(path).existsSync();
  }

  void restart() {
    _previousCardReturnRunId++;
    _swipeController.stop();
    _previousCardReturnController.stop();
    _previousCardReturnController.reset();
    _cardContentController.stop();
    _cardContentController.value = 1;

    setState(() {
      allTerms = List.from(widget.terms);
      activeTerms = List.from(allTerms);

      if (isShuffled) {
        activeTerms.shuffle();
      }

      answeredTerms.clear();
      history.clear();
      incorrectReviewTerms.clear();

      correctCount = 0;
      incorrectCount = 0;

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      showMenu = false;
      _flipController.value = 0;
      hasCompletedDeck = false;
      isReviewingIncorrect = false;
    });

    _saveProgress();
  }

  void startIncorrectReview() {
    if (incorrectReviewTerms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No incorrect answers to review.'),
        ),
      );
      return;
    }

    _previousCardReturnRunId++;
    _swipeController.stop();
    _previousCardReturnController.stop();
    _previousCardReturnController.reset();
    _cardContentController.stop();
    _cardContentController.value = 1;

    final reviewTerms = List<Term>.from(incorrectReviewTerms);

    setState(() {
      allTerms = reviewTerms;
      activeTerms = List.from(reviewTerms);

      if (isShuffled) {
        activeTerms.shuffle();
      }

      answeredTerms.clear();
      history.clear();
      incorrectReviewTerms.clear();

      correctCount = 0;
      incorrectCount = 0;

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      showMenu = false;
      _flipController.value = 0;
      hasCompletedDeck = false;
      isReviewingIncorrect = true;
    });
  }

  void goBack() {
    if (history.isEmpty || isSwipingAway) {
      return;
    }

    animatePreviousCardBack();
  }

  Future<void> animatePreviousCardBack() async {
    if (history.isEmpty || isSwipingAway) return;

    final runId = ++_previousCardReturnRunId;

    _swipeController.stop();
    _previousCardReturnController.stop();
    _previousCardReturnController.reset();
    _cardContentController.stop();
    _cardContentController.value = 1;

    final oldCurrentTerm = activeTerms.isNotEmpty ? activeTerms.first : null;
    final last = history.removeLast();

    setState(() {
      if (last.correct) {
        correctCount--;
      } else {
        incorrectCount--;
        _removeIncorrectReviewTerm(last.term);
      }

      _removeAnsweredTerm(last.term);
      activeTerms.insert(0, last.term);

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = true;
      previousCardReturnDirection = last.correct ? 1 : -1;
      outgoingCardTerm = oldCurrentTerm;
      _flipController.value = 0;
      showMenu = false;
      hasCompletedDeck = false;
    });

    _saveProgress();

    await _previousCardReturnController.forward(from: 0);

    if (!mounted || runId != _previousCardReturnRunId) return;

    setState(() {
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
    });
  }

  void answer(bool correct) {
    if (activeTerms.isEmpty) return;

    final shouldFadeInNextTerm = activeTerms.length > 1;
    final answeredTerm = activeTerms.first;

    if (shouldFadeInNextTerm) {
      _cardContentController.value = 0;
    } else {
      _cardContentController.value = 1;
    }

    _previousCardReturnRunId++;

    setState(() {
      history.add(
        _StudyHistoryEntry(
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

      if (activeTerms.isEmpty) {
        hasCompletedDeck = true;
      }

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      _flipController.value = 0;
    });

    if (shouldFadeInNextTerm) {
      _cardContentController.forward(from: 0);
    }

    _saveProgress();
  }

  void flip() {
    if (_flipController.isAnimating ||
        isDragging ||
        isSwipingAway ||
        isReturningPreviousCard) {
      return;
    }

    if (_flipController.value < 0.5) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
  }

  void onDragStart(DragStartDetails details) {
    if (isSwipingAway || isReturningPreviousCard) return;

    setState(() {
      showMenu = false;
      isDragging = true;
    });
  }

  void onDragUpdate(DragUpdateDetails details) {
    if (isSwipingAway || isReturningPreviousCard) return;

    setState(() {
      dragOffset = Offset(
        dragOffset.dx + details.delta.dx,
        dragOffset.dy + details.delta.dy,
      );
      isDragging = true;
    });
  }

  void onDragEnd(DragEndDetails details) {
    if (isSwipingAway || isReturningPreviousCard) return;

    const threshold = 120.0;

    if (dragOffset.dx > threshold) {
      animateCardOffscreen(correct: true);
    } else if (dragOffset.dx < -threshold) {
      animateCardOffscreen(correct: false);
    } else {
      animateCardBack();
    }
  }

  Future<void> animateCardBack() async {
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

  Future<void> animateCardOffscreen({
    required bool correct,
  }) async {
    if (activeTerms.isEmpty) return;

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

    answer(correct);
  }

  Future<void> handleExit() async {
    if (hasCompletedDeck && !isReviewingIncorrect) {
      await DeckStorage.saveProgress(widget.deck.id, 0);
    }

    if (!mounted) return;

    Navigator.pop(context);
  }

  void toggleShuffle() {
    if (isSwipingAway || isReturningPreviousCard) return;

    _previousCardReturnRunId++;
    _cardContentController.stop();
    _previousCardReturnController.stop();
    _previousCardReturnController.reset();
    _cardContentController.value = 1;

    setState(() {
      isShuffled = !isShuffled;

      if (isShuffled) {
        activeTerms.shuffle();
      } else {
        _sortActiveTermsToBaseOrder();
      }

      showMenu = false;
      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      _flipController.value = 0;
      hasCompletedDeck = activeTerms.isEmpty && allTerms.isNotEmpty;
    });

    _saveProgress();
  }

  void toggleFurigana() {
    if (isSwipingAway || isReturningPreviousCard) return;

    setState(() {
      showFurigana = !showFurigana;
      showMenu = false;
    });
  }

  void toggleCardOrientation() {
    if (isSwipingAway || isReturningPreviousCard) return;

    setState(() {
      termFirst = !termFirst;
      showMenu = false;
      _flipController.value = 0;
    });
  }

  Future<void> openDeckEdit() async {
    if (isSwipingAway || isReturningPreviousCard) return;

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

    _previousCardReturnRunId++;
    _cardContentController.stop();
    _previousCardReturnController.stop();
    _previousCardReturnController.reset();
    _cardContentController.value = 1;

    setState(() {
      allTerms = List.from(widget.terms);
      activeTerms = List.from(allTerms);

      if (isShuffled) {
        activeTerms.shuffle();
      }

      answeredTerms.clear();
      history.clear();
      incorrectReviewTerms.clear();

      correctCount = 0;
      incorrectCount = 0;

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      _flipController.value = 0;
      hasCompletedDeck = false;
      isReviewingIncorrect = false;
    });

    _saveProgress();
    await _loadReadingCardEdits();
  }

  @override
  Widget build(BuildContext context) {
    if (allTerms.isEmpty && activeTerms.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(
            'No terms',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 18,
              color: textGray,
            ),
          ),
        ),
      );
    }

    if (isComplete) {
      return _completeScreen();
    }

    final currentTerm = activeTerms.first;
    final hasCardBehind = activeTerms.length > 1;

    final rotation = (dragOffset.dx / 700).clamp(-0.35, 0.35).toDouble();

    final feedbackText = swipeFeedbackText;
    final feedbackColor = swipeFeedbackColor;
    final feedbackOpacity = swipeFeedbackOpacity;

    final screenWidth = MediaQuery.of(context).size.width;
    final previousReturnProgress = _previousCardReturnAnimation.value;

    final returningOffsetX = isReturningPreviousCard
        ? previousCardReturnDirection *
            screenWidth *
            (1 - previousReturnProgress)
        : 0.0;

    final outgoingOffsetX =
        -previousCardReturnDirection * 72 * previousReturnProgress;

    final outgoingOpacity = (1 - previousReturnProgress).clamp(0.0, 1.0);

    final currentPosition = answeredTerms.length + 1;
    final totalPosition = totalSessionCount;

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
                    onLeftTap: handleExit,
                    title: '$currentPosition/$totalPosition',
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
                  const SizedBox(height: 28),
                  Expanded(
                    child: Stack(
                      children: [
                        if (hasCardBehind) _blankCardBehind(),
                        if (isReturningPreviousCard && outgoingCardTerm != null)
                          Opacity(
                            opacity: outgoingOpacity,
                            child: Transform(
                              transform: Matrix4.identity()
                                ..translateByDouble(outgoingOffsetX, 0, 0, 1),
                              alignment: Alignment.center,
                              child: _card(
                                outgoingCardTerm!,
                                showBack: false,
                                contentOpacity: 1,
                              ),
                            ),
                          ),
                        Transform(
                          transform: Matrix4.identity()
                            ..translateByDouble(
                              isReturningPreviousCard
                                  ? returningOffsetX
                                  : dragOffset.dx,
                              isReturningPreviousCard ? 0.0 : dragOffset.dy,
                              0,
                              1,
                            )
                            ..rotateZ(
                              isReturningPreviousCard ? 0.0 : rotation,
                            ),
                          alignment: Alignment.center,
                          child: GestureDetector(
                            onTap: flip,
                            onPanStart: onDragStart,
                            onPanUpdate: onDragUpdate,
                            onPanEnd: onDragEnd,
                            child: AnimatedBuilder(
                              animation: Listenable.merge([
                                _flipAnimation,
                                _cardContentController,
                              ]),
                              builder: (context, child) {
                                final angle = isReturningPreviousCard
                                    ? 0.0
                                    : _flipAnimation.value;
                                final showBack = angle > math.pi / 2;
                                final contentOpacity =
                                    _cardContentOpacity.value;

                                return Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, 0.001)
                                    ..rotateY(angle),
                                  child: showBack
                                      ? Transform(
                                          alignment: Alignment.center,
                                          transform: Matrix4.identity()
                                            ..rotateY(math.pi),
                                          child: _card(
                                            currentTerm,
                                            showBack: true,
                                            swipeLabel: feedbackText,
                                            swipeColor: feedbackColor,
                                            swipeOpacity: feedbackOpacity,
                                            contentOpacity: contentOpacity,
                                          ),
                                        )
                                      : _card(
                                          currentTerm,
                                          showBack: false,
                                          swipeLabel: feedbackText,
                                          swipeColor: feedbackColor,
                                          swipeOpacity: feedbackOpacity,
                                          contentOpacity: contentOpacity,
                                        ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.only(left: 22, bottom: 22),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: _circle(Icons.undo_rounded, goBack),
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

  Widget _completeScreen() {
    final total = correctCount + incorrectCount;
    final percent = total == 0 ? 0 : ((correctCount / total) * 100).round();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                GakujiTopBar(
                  leftIcon: Icons.close,
                  onLeftTap: handleExit,
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
                          constraints.maxWidth < 390 || constraints.maxHeight < 720;

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
                                          correctCount: correctCount,
                                          incorrectCount: incorrectCount,
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
                                      value: correctCount,
                                      fillColor: correctGreen,
                                      textColor: const Color(0xFF5DCB38),
                                      width: statWidth,
                                    ),
                                    const SizedBox(height: 14),
                                    _completeStatPill(
                                      label: 'Incorrect',
                                      value: incorrectCount,
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
                              onTap: restart,
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
    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 0,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
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
        ),
      ),
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
                  InkWell(
                    onTap: toggleFurigana,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'あ',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 22,
                              height: 1,
                              fontWeight: FontWeight.bold,
                              color: showFurigana ? Colors.black : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            showFurigana ? 'Hide Furigana' : 'Show Furigana',
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
                  ),
                  const Divider(height: 1, color: dividerGray),
                  InkWell(
                    onTap: toggleCardOrientation,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.swap_horiz,
                            color: termFirst ? Colors.black : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Card Orientation:',
                                  textScaler: TextScaler.noScaling,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  termFirst ? 'Term -> Def.' : 'Def. -> Term',
                                  textScaler: TextScaler.noScaling,
                                  style: const TextStyle(
                                    color: textGray,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: dividerGray),
                  InkWell(
                    onTap: toggleShuffle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shuffle,
                            color: isShuffled ? Colors.black : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isShuffled ? 'Unshuffle' : 'Shuffle',
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
                  ),
                  const Divider(height: 1, color: dividerGray),
                  _menuItem(
                    icon: Icons.refresh,
                    label: 'Reset Deck',
                    iconColor: Colors.grey,
                    onTap: restart,
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

  Widget _card(
    Term term, {
    required bool showBack,
    String? swipeLabel,
    Color? swipeColor,
    double swipeOpacity = 0,
    double contentOpacity = 1,
  }) {
    final hasSwipeFeedback =
        swipeLabel != null && swipeColor != null && swipeOpacity > 0;

    final showDefinition = termFirst ? showBack : !showBack;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 28),
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
          Center(
            child: Opacity(
              opacity: contentOpacity,
              child: _cardContent(
                term,
                showDefinition: showDefinition,
              ),
            ),
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

  Widget _cardContent(
    Term term, {
    required bool showDefinition,
  }) {
    if (showDefinition) {
      return _definitionCardContent(term);
    }

    return _termCardContent(term);
  }

  Widget _definitionCardContent(Term term) {
    final glosses = _studyGlossesFor(term);
    final note = _studyNoteFor(term);
    final examples = _studyExamplesFor(term);
    final photoPath = _studyPhotoPathFor(term);
    final hasPhoto = _studyPhotoExistsFor(term) && photoPath != null;

    final hasNote = note.isNotEmpty;
    final hasExamples = examples.isNotEmpty;
    final hasExtras = hasNote || hasExamples || hasPhoto;

    final glossText = _glossTextForStudy(glosses);

    final glossFontSize = glosses.length <= 1 && !hasExtras
        ? 34.0
        : hasPhoto
            ? 18.0
            : glosses.length <= 3
                ? 23.0
                : 20.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 24, 25, 24),
      child: Center(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                glossText,
                maxLines: hasPhoto ? 4 : hasExtras ? 6 : 8,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: glossFontSize,
                  height: 1.14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.35,
                  color: Colors.black,
                ),
              ),
              if (hasNote) ...[
                SizedBox(height: hasPhoto ? 12 : 18),
                _studyCardDivider(),
                SizedBox(height: hasPhoto ? 10 : 14),
                Text(
                  note,
                  maxLines: hasPhoto ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: hasPhoto ? 14.5 : 16,
                    height: 1.16,
                    fontWeight: FontWeight.w600,
                    color: textGray,
                  ),
                ),
              ],
              if (hasExamples) ...[
                SizedBox(height: hasPhoto ? 12 : 18),
                _studyCardDivider(),
                SizedBox(height: hasPhoto ? 10 : 14),
                _studyExamplesBlock(
                  examples,
                  compact: hasPhoto,
                ),
              ],
              if (hasPhoto) ...[
                const SizedBox(height: 14),
                _studyPhotoBlock(photoPath),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _studyPhotoBlock(String photoPath) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.file(
        File(photoPath),
        width: 188,
        height: 132,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 188,
            height: 132,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Photo unavailable',
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 13,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: textGray,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _termCardContent(Term term) {
    final kanjiText =
        term.kanji.trim().isNotEmpty ? term.kanji.trim() : term.reading.trim();
    final readingText = term.reading.trim();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showFurigana && readingText.isNotEmpty)
              Text(
                readingText,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: textGray,
                ),
              ),
            if (showFurigana && readingText.isNotEmpty)
              const SizedBox(height: 8),
            FittedBox(
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
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _glossTextForStudy(List<String> glosses) {
    if (glosses.isEmpty) {
      return 'No glosses selected';
    }

    if (glosses.length == 1) {
      return glosses.first;
    }

    return glosses
        .asMap()
        .entries
        .map((entry) {
          final label = String.fromCharCode(65 + entry.key);
          return '$label. ${entry.value}';
        })
        .join('\n');
  }

  double _termFontSizeFor(String text) {
    if (text.length >= 7) return 40;
    if (text.length >= 5) return 46;
    if (text.length >= 3) return 52;

    return 56;
  }

  Widget _studyCardDivider() {
    return Container(
      width: 54,
      height: 3,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  Widget _studyExamplesBlock(
    List<DictionaryExample> examples, {
    bool compact = false,
  }) {
    final visibleExamples = examples.take(compact ? 1 : 2).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: visibleExamples.map((example) {
        final english = example.english.trim();

        return Padding(
          padding: EdgeInsets.only(bottom: compact ? 6 : 9),
          child: Column(
            children: [
              Text(
                example.japanese,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: compact ? 13.5 : 15.5,
                  height: 1.16,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              if (english.isNotEmpty && !compact) ...[
                const SizedBox(height: 3),
                Text(
                  english,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: textGray,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
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
    return Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 0,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(
            icon,
            size: 25,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

class _StudyHistoryEntry {
  final Term term;
  final bool correct;

  const _StudyHistoryEntry({
    required this.term,
    required this.correct,
  });
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