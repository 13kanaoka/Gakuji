import 'package:flutter/material.dart';

import '../models/writing_point.dart';
import '../models/writing_prompt.dart';
import '../services/writing_answer_checker.dart';
import 'gakuji_styles.dart';
import 'reading_card_back.dart';

class WritingStudyBlankCard extends StatelessWidget {
  const WritingStudyBlankCard({super.key});

  @override
  Widget build(BuildContext context) {
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
}

class WritingStudyCard extends StatelessWidget {
  final WritingPrompt prompt;
  final bool isAnswerRevealed;
  final WritingAnswerResult? answerResult;
  final List<String?> slotAnswers;
  final int activeSlotIndex;
  final List<List<WritingPoint>> activeSlotStrokes;
  final bool showGrid;
  final bool isCheckingAnswer;
  final bool isCheckingFinalSlot;
  final Color? swipeColor;
  final double swipeOpacity;
  final double contentOpacity;
  final bool showSwipeInstructions;
  final bool? isStarred;
  final VoidCallback? onStarTap;
  final ValueChanged<int> onSelectSlot;
  final VoidCallback onClear;
  final VoidCallback? onCheck;
  final ValueChanged<Offset> onStrokeStart;
  final ValueChanged<Offset> onStrokeUpdate;

  const WritingStudyCard({
    super.key,
    required this.prompt,
    required this.isAnswerRevealed,
    required this.answerResult,
    required this.slotAnswers,
    required this.activeSlotIndex,
    required this.activeSlotStrokes,
    required this.showGrid,
    required this.isCheckingAnswer,
    required this.isCheckingFinalSlot,
    required this.onSelectSlot,
    required this.onClear,
    required this.onCheck,
    required this.onStrokeStart,
    required this.onStrokeUpdate,
    this.swipeColor,
    this.swipeOpacity = 0,
    this.contentOpacity = 1,
    this.showSwipeInstructions = true,
    this.isStarred,
    this.onStarTap,
  });

  bool get _hasSwipeFeedback {
    return swipeColor != null && swipeOpacity > 0;
  }

  double _meaningFontSize(String value) {
    final length = value.runes.length;

    if (length >= 52) return 12;
    if (length >= 38) return 13;
    if (length >= 26) return 14;
    return 15;
  }

  @override
  Widget build(BuildContext context) {
    return ReadingCardFrame(
      margin: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      borderColor:
          _hasSwipeFeedback ? swipeColor! : GakujiColors.softBorder,
      borderWidth: _hasSwipeFeedback ? 5 : 1.2,
      isStarred: isStarred,
      onStarTap: onStarTap,
      child: Opacity(
        opacity: contentOpacity,
        child: isAnswerRevealed
            ? _answerRevealContent()
            : _writingInputContent(),
      ),
    );
  }

  Widget _writingInputContent() {
    return Column(
      children: [
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 22,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              prompt.reading,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                fontSize: 18,
                height: 1,
                color: GakujiColors.darkGray,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _answerSlotRow(),
        const SizedBox(height: 18),
        Text(
          prompt.meaning,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: GakujiText.xSmall.copyWith(
            fontSize: _meaningFontSize(prompt.meaning),
            height: 1.08,
            color: GakujiColors.darkGray,
          ),
        ),
        const Spacer(),
        Center(
          child: SizedBox(
            width: 280,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _WritingCardButton(
                  label: 'Clear',
                  color: GakujiColors.whiteCard,
                  textColor: const Color(0xFFB8B0A8),
                  width: 70,
                  onTap: onClear,
                ),
                _WritingCardButton(
                  label: isCheckingAnswer
                      ? 'Checking...'
                      : isCheckingFinalSlot
                          ? 'Submit'
                          : 'Check',
                  color: GakujiColors.mediumGray,
                  textColor: GakujiColors.lightDivider,
                  width: isCheckingAnswer ? 96 : 78,
                  onTap: isCheckingAnswer ? null : onCheck,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: SizedBox(
            width: 280,
            height: 280,
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        final box = context.findRenderObject() as RenderBox;
                        final point = box.globalToLocal(
                          details.globalPosition,
                        );

                        onStrokeStart(point);
                      },
                      onPanUpdate: (details) {
                        final box = context.findRenderObject() as RenderBox;
                        final point = box.globalToLocal(
                          details.globalPosition,
                        );

                        onStrokeUpdate(point);
                      },
                      child: CustomPaint(
                        painter: _WritingStudyPainter(
                          activeSlotStrokes,
                          showGrid,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _answerRevealContent() {
    return Column(
      children: [
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 22,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              prompt.reading,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                fontSize: 18,
                height: 1,
                color: GakujiColors.darkGray,
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _answerSlotRow(),
        const SizedBox(height: 22),
        Text(
          prompt.meaning,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: GakujiText.xSmall.copyWith(
            fontSize: _meaningFontSize(prompt.meaning),
            height: 1.08,
            color: GakujiColors.darkGray,
          ),
        ),
        const SizedBox(height: 72),
        Container(
          width: double.infinity,
          height: 2,
          decoration: BoxDecoration(
            color: GakujiColors.darkGray,
            borderRadius: BorderRadius.circular(GakujiRadius.pill),
          ),
        ),
        const SizedBox(height: 38),
        Text(
          answerResult?.correctAnswer ?? prompt.answer,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            fontSize: 48,
            height: 1,
            color: GakujiColors.deckBlue,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (showSwipeInstructions)
          Text(
            'Swipe left for incorrect · Swipe right for correct',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              fontSize: 14,
              color: GakujiColors.softGray,
            ),
          ),
      ],
    );
  }

  Widget _answerSlotRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(prompt.slotCount, (index) {
        final active = index == activeSlotIndex;
        final slotAnswer = index < slotAnswers.length
            ? slotAnswers[index]
            : null;
        final slotColor = isAnswerRevealed
            ? GakujiColors.darkGray
            : active
                ? GakujiColors.darkGray
                : GakujiColors.softGray;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: isAnswerRevealed
              ? null
              : () => onSelectSlot(index),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 42,
            height: 52,
            alignment: Alignment.center,
            color: Colors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 36,
                  child: Center(
                    child: slotAnswer == null || slotAnswer.isEmpty
                        ? const SizedBox.shrink()
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
                ),
                const SizedBox(height: 5),
                Container(
                  width: 34,
                  height: 3,
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
  }
}

class _WritingCardButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback? onTap;
  final double width;

  const _WritingCardButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: _WritingCardPushable(
        onTap: onTap,
        pressedOffset: 3,
        builder: (pressed) {
          return Container(
            width: width,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: GakujiColors.warmDivider,
                width: 1.5,
              ),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    label,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 16,
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
}

class _WritingCardPushable extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget Function(bool pressed) builder;
  final double pressedOffset;

  const _WritingCardPushable({
    required this.onTap,
    required this.builder,
    required this.pressedOffset,
  });

  @override
  State<_WritingCardPushable> createState() =>
      _WritingCardPushableState();
}

class _WritingCardPushableState extends State<_WritingCardPushable> {
  static const Duration minimumPressDuration = Duration(milliseconds: 85);

  bool pressed = false;
  DateTime? pressedStartedAt;
  int releaseRunId = 0;

  void _setPressed(bool value) {
    if (!mounted || pressed == value || widget.onTap == null) return;

    setState(() {
      pressed = value;
    });

    if (value) {
      pressedStartedAt = DateTime.now();
    }
  }

  void _releaseAfterMinimumPress() {
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

      _setPressed(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: disabled ? null : (_) => _setPressed(true),
      onTapUp: disabled ? null : (_) => _releaseAfterMinimumPress(),
      onTapCancel: disabled ? null : _releaseAfterMinimumPress,
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

class _WritingStudyPainter extends CustomPainter {
  final List<List<WritingPoint>> strokes;
  final bool showGrid;

  _WritingStudyPainter(
    this.strokes,
    this.showGrid,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = GakujiColors.darkGray
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final grid = Paint()
      ..color = GakujiColors.warmDivider
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
      for (var index = 0; index < stroke.length - 1; index++) {
        canvas.drawLine(
          Offset(stroke[index].x, stroke[index].y),
          Offset(stroke[index + 1].x, stroke[index + 1].y),
          pen,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WritingStudyPainter oldDelegate) => true;
}
