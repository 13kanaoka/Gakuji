import 'dart:ui';
import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../models/term.dart';
import '../models/writing_point.dart';
import '../models/writing_prompt.dart';
import '../services/deck_storage.dart';
import '../services/prompt_converter.dart';
import '../services/writing_answer_checker.dart';
import '../services/writing_recognition_service.dart';
import '../widgets/gakuji_top_bar.dart';

class WritingStudyPage extends StatefulWidget {
  final List<Term> terms;
  final Deck deck;

  const WritingStudyPage({
    super.key,
    required this.terms,
    required this.deck,
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
  }) : prompts = terms.map(PromptConverter.fromTerm).toList() {
    _initSlots();
  }

  final List<WritingPrompt> prompts;
  final String deckId;

  int _currentIndex = 0;

  int correctCount = 0;
  int incorrectCount = 0;

  final List<bool?> history = [];

  List<List<List<WritingPoint>>> slotStrokes = [];
  List<String?> slotAnswers = [];

  int activeSlotIndex = 0;

  final Set<String> starred = {};

  bool showGrid = true;
  bool hasChecked = false;

  int get currentIndex => _currentIndex;
  WritingPrompt get current => prompts[_currentIndex];

  bool get isComplete => _currentIndex >= prompts.length;

  List<String> get currentAnswerCharacters {
    if (prompts.isEmpty || isComplete) return [];

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

  void _initSlots() {
    if (prompts.isEmpty || isComplete) {
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

  void setIndex(int index) {
    if (prompts.isEmpty) {
      _currentIndex = 0;
      _initSlots();
      return;
    }

    _currentIndex = index.clamp(0, prompts.length);
    _initSlots();
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

  void answer(bool correct) {
    history.add(correct);

    if (correct) {
      correctCount++;
    } else {
      incorrectCount++;
    }

    _currentIndex++;
    _initSlots();

    DeckStorage.saveProgress(deckId, _currentIndex);
  }

  void skip() {
    history.add(false);
    incorrectCount++;

    _currentIndex++;
    _initSlots();

    DeckStorage.saveProgress(deckId, _currentIndex);
  }

  void previousCard() {
    if (_currentIndex == 0 || history.isEmpty) return;

    final last = history.removeLast();

    last == true ? correctCount-- : incorrectCount--;

    _currentIndex--;
    _initSlots();

    DeckStorage.saveProgress(deckId, _currentIndex);
  }

  void restartDeck() {
    _currentIndex = 0;
    correctCount = 0;
    incorrectCount = 0;
    history.clear();

    _initSlots();

    DeckStorage.saveProgress(deckId, _currentIndex);
  }
}

/* =========================
   PAGE
   ========================= */

class _WritingStudyPageState extends State<WritingStudyPage> {
  late WritingSessionController controller;

  bool isCheckingAnswer = false;
  bool showMenu = false;

  bool isAnswerRevealed = false;
  WritingAnswerResult? answerResult;
  double revealDragDistance = 0;

  @override
  void initState() {
    super.initState();

    controller = WritingSessionController(
      terms: widget.terms,
      deckId: widget.deck.id,
    );

    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final saved = await DeckStorage.loadProgress(widget.deck.id);

    if (!mounted) return;

    setState(() {
      controller.setIndex(saved);
      resetRevealState();
    });
  }

  void refresh() => setState(() {});

  Future<void> exitDeck() async {
    if (controller.isComplete) {
      await DeckStorage.saveProgress(widget.deck.id, 0);
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  void resetRevealState() {
    isAnswerRevealed = false;
    answerResult = null;
    revealDragDistance = 0;
    isCheckingAnswer = false;
  }

  void restartDeck() {
    setState(() {
      showMenu = false;
      controller.restartDeck();
      resetRevealState();
    });
  }

  void goBack() {
    setState(() {
      controller.previousCard();
      resetRevealState();
    });
  }

  void skipCard() {
    setState(() {
      controller.skip();
      resetRevealState();
    });
  }

  void submitRevealedAnswer(bool correct) {
    setState(() {
      controller.answer(correct);
      resetRevealState();
    });
  }

  void handleRevealSwipeEnd() {
    const swipeThreshold = 80.0;

    if (revealDragDistance > swipeThreshold) {
      submitRevealedAnswer(true);
    } else if (revealDragDistance < -swipeThreshold) {
      submitRevealedAnswer(false);
    }

    revealDragDistance = 0;
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
    if (widget.terms.isEmpty) {
      return const Scaffold(body: Center(child: Text('No terms')));
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
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
                child: Column(
                  children: [
                    GakujiTopBar(
                      leftIcon: Icons.close,
                      onLeftTap: exitDeck,
                      title:
                          '${controller.currentIndex + 1}/${controller.prompts.length}',
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

                    const SizedBox(height: 16),

                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                _counterPill(
                                  controller.incorrectCount,
                                  const Color(0xFFFF5A6A),
                                ),
                                _counterPill(
                                  controller.correctCount,
                                  const Color(0xFFC7F3B5),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            Expanded(
                              child: isAnswerRevealed
                                  ? GestureDetector(
                                      onHorizontalDragStart: (_) {
                                        revealDragDistance = 0;
                                      },
                                      onHorizontalDragUpdate: (details) {
                                        revealDragDistance +=
                                            details.delta.dx;
                                      },
                                      onHorizontalDragEnd: (_) {
                                        handleRevealSwipeEnd();
                                      },
                                      child: _studyCard(prompt),
                                    )
                                  : _studyCard(prompt),
                            ),

                            const SizedBox(height: 16),

                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back),
                                  onPressed: goBack,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next),
                                  onPressed: skipCard,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (showMenu) _menuOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _studyCard(WritingPrompt prompt) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(12),
      ),
      child: isAnswerRevealed
          ? _answerRevealContent(prompt)
          : _writingContent(prompt),
    );
  }

  Widget _writingContent(WritingPrompt prompt) {
    return Column(
      children: [
        Text(
          prompt.reading,
          style: const TextStyle(fontSize: 20),
        ),

        const SizedBox(height: 28),

        _answerSlotRow(prompt),

        const SizedBox(height: 28),

        Text(
          prompt.meaning,
          style: const TextStyle(fontSize: 18),
        ),

        const Spacer(),

        Row(
          children: [
            IconButton(
              icon: Icon(
                controller.showGrid
                    ? Icons.visibility
                    : Icons.visibility_off,
              ),
              onPressed: () {
                setState(() {
                  controller.toggleGrid();
                });
              },
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  controller.clearSlot();
                });
              },
              child: const Text('Clear'),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: isCheckingAnswer ? null : checkAnswer,
              child: Text(
                isCheckingAnswer ? 'Checking...' : 'Check',
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        /// KANJI WRITING CANVAS
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    final box =
                        context.findRenderObject() as RenderBox;
                    final p = box.globalToLocal(
                      d.globalPosition,
                    );

                    setState(() {
                      controller.addStroke(
                        p,
                        isStart: true,
                      );
                    });
                  },
                  onPanUpdate: (d) {
                    final box =
                        context.findRenderObject() as RenderBox;
                    final p = box.globalToLocal(
                      d.globalPosition,
                    );

                    setState(() {
                      controller.addStroke(p);
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
      ],
    );
  }

  Widget _answerRevealContent(WritingPrompt prompt) {
    final result = answerResult;

    return Column(
      children: [
        Text(
          prompt.reading,
          style: const TextStyle(fontSize: 20),
        ),

        const SizedBox(height: 24),

        _answerSlotRow(prompt),

        const SizedBox(height: 24),

        Text(
          prompt.meaning,
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
          style: const TextStyle(
            fontSize: 48,
            color: Color(0xFF6C78FF),
          ),
        ),

        const Spacer(),

        const Text(
          'Swipe left for incorrect · Swipe right for correct',
          textAlign: TextAlign.center,
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
      children: List.generate(prompt.slotCount, (i) {
        final active = i == controller.activeSlotIndex;
        final slotAnswer = controller.slotAnswers[i];

        return GestureDetector(
          onTap: () {
            if (isAnswerRevealed) return;

            setState(() {
              controller.selectSlot(i);
            });
          },
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: 6,
            ),
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: active && !isAnswerRevealed
                    ? Colors.blue
                    : Colors.grey,
                width: 2,
              ),
            ),
            child: Text(
              slotAnswer ?? '_',
              style: const TextStyle(fontSize: 28),
            ),
          ),
        );
      }),
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
                  onLeftTap: exitDeck,
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
                              controller.correctCount,
                              const Color(0xFFC7F3B5),
                            ),
                            const SizedBox(height: 12),
                            _resultBox(
                              'Incorrect',
                              controller.incorrectCount,
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
                            onPressed: restartDeck,
                            child: const Text('Restart'),
                          ),
                        ),
                      ),

                      Positioned(
                        bottom: 0,
                        left: 22,
                        child: _circle(
                          Icons.arrow_back_ios_new,
                          goBack,
                        ),
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
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.edit),
                        SizedBox(width: 10),
                        Text('Edit Deck'),
                      ],
                    ),
                  ),
                  const Divider(),
                  InkWell(
                    onTap: restartDeck,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.refresh,
                            color: Colors.grey,
                          ),
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

  Widget _counterPill(int value, Color color) {
    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text('$value', textAlign: TextAlign.center),
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

    final border = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      border,
    );

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