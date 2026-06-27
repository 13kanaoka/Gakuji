import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../models/term.dart';
import '../services/deck_storage.dart';
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

  late List<Term> terms;

  int currentIndex = 0;
  int correctCount = 0;
  int incorrectCount = 0;

  final List<bool> history = [];

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  late AnimationController _swipeController;
  late Animation<Offset> _swipeAnimation;

  late AnimationController _cardContentController;
  late Animation<double> _cardContentOpacity;

  Offset dragOffset = Offset.zero;
  bool isDragging = false;
  bool isSwipingAway = false;

  bool hasCompletedDeck = false;

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

    terms = List.from(widget.terms);

    if (isShuffled) {
      terms.shuffle();
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

    _loadProgress();
  }

  @override
  void dispose() {
    _swipeController.removeListener(_handleSwipeAnimationTick);
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

  Future<void> _loadProgress() async {
    final saved = await DeckStorage.loadProgress(widget.deck.id);

    if (!mounted) return;

    setState(() {
      if (terms.isEmpty) {
        currentIndex = 0;
      } else {
        currentIndex = saved.clamp(0, terms.length).toInt();
      }

      _cardContentController.value = 1;
    });
  }

  void _saveProgress() {
    DeckStorage.saveProgress(widget.deck.id, currentIndex);
  }

  bool get isComplete => currentIndex >= terms.length;

  String? get swipeFeedbackText {
    if (dragOffset.dx > 32) return 'Know';
    if (dragOffset.dx < -32) return 'Still learning';

    return null;
  }

  Color? get swipeFeedbackColor {
    if (dragOffset.dx > 32) return const Color(0xFF20BFA9);
    if (dragOffset.dx < -32) return const Color(0xFFFFA24A);

    return null;
  }

  double get swipeFeedbackOpacity {
    final opacity = ((dragOffset.dx.abs() - 30) / 90).clamp(0.0, 1.0);

    return opacity.toDouble();
  }

  void restart() {
    _swipeController.stop();
    _cardContentController.stop();
    _cardContentController.value = 1;

    setState(() {
      currentIndex = 0;
      correctCount = 0;
      incorrectCount = 0;
      history.clear();
      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      showMenu = false;
      _flipController.value = 0;
      hasCompletedDeck = false;
    });

    _saveProgress();
  }

  void goBack() {
    if (history.isEmpty || currentIndex == 0 || isSwipingAway) return;

    _swipeController.stop();
    _cardContentController.stop();
    _cardContentController.value = 1;

    setState(() {
      final last = history.removeLast();

      if (last) {
        correctCount--;
      } else {
        incorrectCount--;
      }

      currentIndex--;
      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      _flipController.value = 0;
      showMenu = false;
    });

    _saveProgress();
  }

  void answer(bool correct) {
    final shouldFadeInNextTerm = currentIndex + 1 < terms.length;

    if (shouldFadeInNextTerm) {
      _cardContentController.value = 0;
    } else {
      _cardContentController.value = 1;
    }

    setState(() {
      history.add(correct);

      if (correct) {
        correctCount++;
      } else {
        incorrectCount++;
      }

      currentIndex++;

      if (currentIndex >= terms.length) {
        hasCompletedDeck = true;
      }

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      _flipController.value = 0;
    });

    if (shouldFadeInNextTerm) {
      _cardContentController.forward(from: 0);
    }

    _saveProgress();
  }

  void flip() {
    if (_flipController.isAnimating || isDragging || isSwipingAway) return;

    if (_flipController.value < 0.5) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
  }

  void onDragStart(DragStartDetails details) {
    if (isSwipingAway) return;

    setState(() {
      showMenu = false;
      isDragging = true;
    });
  }

  void onDragUpdate(DragUpdateDetails details) {
    if (isSwipingAway) return;

    setState(() {
      dragOffset = Offset(
        dragOffset.dx + details.delta.dx,
        dragOffset.dy + details.delta.dy,
      );
      isDragging = true;
    });
  }

  void onDragEnd(DragEndDetails details) {
    if (isSwipingAway) return;

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
    if (hasCompletedDeck) {
      await DeckStorage.saveProgress(widget.deck.id, 0);
    }

    if (!mounted) return;

    Navigator.pop(context);
  }

  void toggleShuffle() {
    if (isSwipingAway) return;

    _cardContentController.stop();
    _cardContentController.value = 1;

    setState(() {
      isShuffled = !isShuffled;

      if (isShuffled) {
        terms.shuffle();
      } else {
        terms = List.from(widget.terms);
      }

      showMenu = false;

      if (terms.isEmpty) {
        currentIndex = 0;
      } else {
        currentIndex = currentIndex.clamp(0, terms.length).toInt();
      }

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      _flipController.value = 0;
    });
  }

  void toggleFurigana() {
    if (isSwipingAway) return;

    setState(() {
      showFurigana = !showFurigana;
      showMenu = false;
    });
  }

  void toggleCardOrientation() {
    if (isSwipingAway) return;

    setState(() {
      termFirst = !termFirst;
      showMenu = false;
      _flipController.value = 0;
    });
  }

  Future<void> openDeckEdit() async {
    if (isSwipingAway) return;

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

    _cardContentController.stop();
    _cardContentController.value = 1;

    setState(() {
      terms = List.from(widget.terms);

      if (isShuffled) {
        terms.shuffle();
      }

      if (terms.isEmpty) {
        currentIndex = 0;
      } else {
        currentIndex = currentIndex.clamp(0, terms.length).toInt();
      }

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      _flipController.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No terms')),
      );
    }

    if (isComplete) {
      return _completeScreen();
    }

    final currentTerm = terms[currentIndex];
    final hasNextCard = currentIndex < terms.length - 1;

    final rotation = (dragOffset.dx / 700).clamp(-0.35, 0.35).toDouble();

    final feedbackText = swipeFeedbackText;
    final feedbackColor = swipeFeedbackColor;
    final feedbackOpacity = swipeFeedbackOpacity;

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
                    title: '${currentIndex + 1}/${terms.length}',
                    titleStyle: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                    rightIcon: Icons.more_horiz,
                    onRightTap: () {
                      setState(() => showMenu = !showMenu);
                    },
                  ),

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _pill(incorrectCount, const Color(0xFFFF5A6A)),
                        _pill(correctCount, const Color(0xFFC7F3B5)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  Expanded(
                    child: Stack(
                      children: [
                        if (hasNextCard)
                          Transform.scale(
                            scale: 0.96,
                            child: Opacity(
                              opacity: 0.22,
                              child: _cardShell(),
                            ),
                          ),

                        Transform(
                          transform: Matrix4.identity()
                            ..translate(dragOffset.dx, dragOffset.dy)
                            ..rotateZ(rotation),
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
                                final angle = _flipAnimation.value;
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

                  Padding(
                    padding: const EdgeInsets.only(left: 20, bottom: 20),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: _circle(Icons.arrow_back_ios_new, goBack),
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
                  child: Stack(
                    children: [
                      const Center(
                        child: Text(
                          'Complete!',
                          style: TextStyle(fontSize: 42),
                        ),
                      ),

                      Positioned(
                        top: 230,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            _resultBox(
                              'Correct',
                              correctCount,
                              const Color(0xFFC7F3B5),
                            ),
                            const SizedBox(height: 12),
                            _resultBox(
                              'Incorrect',
                              incorrectCount,
                              const Color(0xFFFF5A6A),
                            ),
                          ],
                        ),
                      ),

                      Positioned(
                        bottom: 100,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: ElevatedButton(
                            onPressed: restart,
                            child: const Text('Restart'),
                          ),
                        ),
                      ),

                      Positioned(
                        bottom: 20,
                        left: 20,
                        child: _circle(Icons.arrow_back_ios_new, goBack),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (showMenu) _menuOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _menuOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => showMenu = false),
        child: Container(
          color: Colors.black.withOpacity(0.2),
          child: Center(
            child: Container(
              width: 240,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: openDeckEdit,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.edit),
                          SizedBox(width: 10),
                          Text('Edit Deck'),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  InkWell(
                    onTap: toggleFurigana,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Text(
                            'あ',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: showFurigana ? Colors.black : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            showFurigana
                                ? 'Hide Furigana'
                                : 'Show Furigana',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  InkWell(
                    onTap: toggleCardOrientation,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.swap_horiz,
                            color: termFirst ? Colors.black : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Card Orientation:'),
                                const SizedBox(height: 2),
                                Text(
                                  termFirst ? 'Term -> Def.' : 'Def. -> Term',
                                  style: const TextStyle(
                                    color: Colors.grey,
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
                  const Divider(),
                  InkWell(
                    onTap: toggleShuffle,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shuffle,
                            color: isShuffled ? Colors.black : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Text(isShuffled ? 'Unshuffle' : 'Shuffle'),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  InkWell(
                    onTap: restart,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.refresh, color: Colors.grey),
                          SizedBox(width: 10),
                          Text('Reset Deck'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardShell() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E5E5),
        borderRadius: BorderRadius.circular(12),
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
        color: const Color(0xFFE5E5E5),
        borderRadius: BorderRadius.circular(12),
        border: hasSwipeFeedback
            ? Border.all(
                color: swipeColor,
                width: 5,
              )
            : null,
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
                child: Text(
                  swipeLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: swipeColor,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
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
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          term.meaning,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 52),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showFurigana)
          Text(
            term.reading,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22),
          ),
        if (showFurigana) const SizedBox(height: 4),
        Text(
          term.kanji,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 82),
        ),
      ],
    );
  }

  Widget _resultBox(String label, int value, Color color) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('$value'),
        ],
      ),
    );
  }

  Widget _pill(int count, Color color) {
    return Container(
      width: 80,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _circle(IconData icon, VoidCallback onTap) {
    return CircleAvatar(
      backgroundColor: Colors.white,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon),
      ),
    );
  }
}