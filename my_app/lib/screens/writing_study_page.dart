import 'dart:ui';
import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../models/term.dart';
import '../models/writing_prompt.dart';
import '../services/deck_storage.dart';
import '../services/prompt_converter.dart';

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
   SESSION CONTROLLER (UNCHANGED LOGIC, STABLE)
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

  List<List<List<Offset>>> slotStrokes = [];
  int activeSlotIndex = 0;

  final Set<String> starred = {};

  bool showGrid = true;
  bool hasChecked = false;

  int get currentIndex => _currentIndex;
  WritingPrompt get current => prompts[_currentIndex];

  bool get isComplete => _currentIndex >= prompts.length;

  void _initSlots() {
    final count = prompts.isNotEmpty ? current.slotCount : 1;

    slotStrokes = List.generate(
      count,
      (_) => <List<Offset>>[],
    );

    activeSlotIndex = 0;
  }

  void setIndex(int index) {
    _currentIndex = index.clamp(0, prompts.length - 1);
    _initSlots();
  }

  void selectSlot(int index) {
    activeSlotIndex = index;
  }

  void addStroke(Offset point, {bool isStart = false}) {
    if (slotStrokes.isEmpty) _initSlots();

    final slot = slotStrokes[activeSlotIndex];

    if (isStart || slot.isEmpty) {
      slot.add(<Offset>[point]);
    } else {
      slot.last.add(point);
    }
  }

  void clearSlot() {
    if (slotStrokes.isEmpty) return;
    slotStrokes[activeSlotIndex].clear();
  }

  void clearAllSlots() {
    _initSlots();
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
    });
  }

  void refresh() => setState(() {});
  void exitDeck() => Navigator.pop(context);

  void checkAnswer() {
    setState(() {
      controller.hasChecked = true;
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        final prompt = controller.current;

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Correct answer',
                  style: TextStyle(fontSize: 18)),
              const SizedBox(height: 14),
              Text(prompt.reading,
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 10),
              Text(prompt.answer,
                  style: const TextStyle(fontSize: 54)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => controller.answer(false));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5A6A),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Wrong'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => controller.answer(true));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC7F3B5),
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Correct'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.terms.isEmpty) {
      return const Scaffold(body: Center(child: Text('No terms')));
    }

    if (controller.isComplete) {
      return const Scaffold(body: Center(child: Text('Complete!')));
    }

    final prompt = controller.current;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: exitDeck,
                  ),
                  Text(
                    '${controller.currentIndex + 1}/${controller.prompts.length}',
                    style: const TextStyle(fontSize: 28),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz),
                    onPressed: () {},
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _counterPill(controller.incorrectCount,
                      const Color(0xFFFF5A6A)),
                  _counterPill(controller.correctCount,
                      const Color(0xFFC7F3B5)),
                ],
              ),

              const SizedBox(height: 18),

              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEDED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(prompt.reading,
                          style: const TextStyle(fontSize: 20)),

                      const SizedBox(height: 28),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(prompt.slotCount, (i) {
                          final active =
                              i == controller.activeSlotIndex;

                          return GestureDetector(
                            onTap: () {
                              setState(() =>
                                  controller.selectSlot(i));
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: active
                                      ? Colors.blue
                                      : Colors.grey,
                                  width: 2,
                                ),
                              ),
                              child: const Text('_'),
                            ),
                          );
                        }),
                      ),

                      const SizedBox(height: 28),

                      Text(prompt.meaning,
                          style: const TextStyle(fontSize: 18)),

                      const Spacer(),

                      Row(
                        children: [
                          IconButton(
                            icon: Icon(controller.showGrid
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () {
                              setState(() =>
                                  controller.toggleGrid());
                            },
                          ),
                          ElevatedButton(
                            onPressed: () {
                              setState(() =>
                                  controller.clearSlot());
                            },
                            child: const Text('Clear'),
                          ),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: checkAnswer,
                            child: const Text('Check'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      /// ✅ FIXED CANVAS (THIS IS THE KEY FIX)
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,

                                onPanStart: (d) {
                                  final box = context.findRenderObject()
                                      as RenderBox;
                                  final p = box.globalToLocal(d.globalPosition);

                                  setState(() {
                                    controller.addStroke(p, isStart: true);
                                  });
                                },

                                onPanUpdate: (d) {
                                  final box = context.findRenderObject()
                                      as RenderBox;
                                  final p = box.globalToLocal(d.globalPosition);

                                  setState(() {
                                    controller.addStroke(p);
                                  });
                                },

                                child: CustomPaint(
                                  painter: _Painter(
                                    controller.slotStrokes.isNotEmpty
                                        ? controller.slotStrokes[
                                            controller.activeSlotIndex]
                                        : <List<Offset>>[],
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
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      setState(() => controller.previousCard());
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: () {
                      setState(() => controller.skip());
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
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
}

/* =========================
   PAINTER
   ========================= */

class _Painter extends CustomPainter {
  final List<List<Offset>> strokes;
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
        canvas.drawLine(stroke[i], stroke[i + 1], pen);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}