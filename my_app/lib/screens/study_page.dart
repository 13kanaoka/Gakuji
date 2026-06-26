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

  const StudyPage({
    super.key,
    required this.terms,
    required this.deck,
  });

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> with TickerProviderStateMixin {
  late List<Term> terms;

  int currentIndex = 0;
  int correctCount = 0;
  int incorrectCount = 0;

  final List<bool> history = [];

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  Offset dragOffset = Offset.zero;
  bool isDragging = false;

  bool hasCompletedDeck = false;

  bool showMenu = false;
  bool isShuffled = false;

  @override
  void initState() {
    super.initState();

    terms = List.from(widget.terms);

    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
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

    _loadProgress();
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final saved = await DeckStorage.loadProgress(widget.deck.id);

    if (!mounted) return;

    setState(() {
      if (terms.isEmpty) {
        currentIndex = 0;
      } else {
        currentIndex = saved.clamp(0, terms.length - 1).toInt();
      }
    });
  }

  void _saveProgress() {
    DeckStorage.saveProgress(widget.deck.id, currentIndex);
  }

  bool get isComplete => currentIndex >= terms.length;

  void restart() {
    setState(() {
      currentIndex = 0;
      correctCount = 0;
      incorrectCount = 0;
      history.clear();
      dragOffset = Offset.zero;
      isDragging = false;
      showMenu = false;
      _flipController.value = 0;
      hasCompletedDeck = false;
    });

    _saveProgress();
  }

  void goBack() {
    if (history.isEmpty || currentIndex == 0) return;

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
      _flipController.value = 0;
      showMenu = false;
    });

    _saveProgress();
  }

  void answer(bool correct) {
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
      _flipController.value = 0;
    });

    _saveProgress();
  }

  void flip() {
    if (_flipController.isAnimating) return;

    if (_flipController.value < 0.5) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
  }

  void onDragUpdate(DragUpdateDetails details) {
    setState(() {
      dragOffset += details.delta;
      isDragging = true;
    });
  }

  void onDragEnd(DragEndDetails details) {
    const threshold = 120.0;

    if (dragOffset.dx > threshold) {
      answer(true);
    } else if (dragOffset.dx < -threshold) {
      answer(false);
    } else {
      setState(() {
        dragOffset = Offset.zero;
        isDragging = false;
      });
    }
  }

  Future<void> handleExit() async {
    if (hasCompletedDeck) {
      await DeckStorage.saveProgress(widget.deck.id, 0);
    }

    if (!mounted) return;

    Navigator.pop(context);
  }

  void toggleShuffle() {
    setState(() {
      isShuffled = !isShuffled;

      if (isShuffled) {
        terms.shuffle();
      } else {
        terms = List.from(widget.terms);
      }

      showMenu = false;
      currentIndex = currentIndex.clamp(0, terms.length - 1).toInt();
      dragOffset = Offset.zero;
      isDragging = false;
      _flipController.value = 0;
    });
  }

  Future<void> openDeckEdit() async {
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

    setState(() {
      terms = List.from(widget.terms);

      if (isShuffled) {
        terms.shuffle();
      }

      if (terms.isEmpty) {
        currentIndex = 0;
      } else {
        currentIndex = currentIndex.clamp(0, terms.length - 1).toInt();
      }

      dragOffset = Offset.zero;
      isDragging = false;
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
    final nextTerm =
        currentIndex < terms.length - 1 ? terms[currentIndex + 1] : null;

    final rotation = dragOffset.dx / 700;

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
                        if (nextTerm != null)
                          Transform.scale(
                            scale: 0.96,
                            child: Opacity(
                              opacity: 0.2,
                              child: _card(nextTerm),
                            ),
                          ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          transform: Matrix4.identity()
                            ..translate(dragOffset.dx, dragOffset.dy)
                            ..rotateZ(rotation),
                          child: GestureDetector(
                            onTap: flip,
                            onPanUpdate: onDragUpdate,
                            onPanEnd: onDragEnd,
                            child: AnimatedBuilder(
                              animation: _flipAnimation,
                              builder: (context, child) {
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
                                          transform: Matrix4.identity()
                                            ..rotateY(math.pi),
                                          child: _card(
                                            currentTerm,
                                            showMeaning: true,
                                          ),
                                        )
                                      : _card(currentTerm),
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

                  GestureDetector(
                    onTap: toggleShuffle,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isShuffled
                            ? Colors.grey.withOpacity(0.25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shuffle, color: Colors.grey),
                          SizedBox(width: 10),
                          Text(
                            'Shuffle',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
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
              width: 220,
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

  Widget _card(Term term, {bool showMeaning = false}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E5E5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: showMeaning
            ? Text(
                term.meaning,
                style: const TextStyle(fontSize: 52),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    term.reading,
                    style: const TextStyle(fontSize: 22),
                  ),
                  Text(
                    term.kanji,
                    style: const TextStyle(fontSize: 82),
                  ),
                ],
              ),
      ),
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