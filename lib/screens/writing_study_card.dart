import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/writing_point.dart';
import '../models/writing_prompt.dart';
import '../services/writing_answer_checker.dart';
import 'gakuji_styles.dart';
import 'low_latency_writing_canvas.dart';
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
  final Color? cardTextColor;
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
    this.cardTextColor,
    this.isStarred,
    this.onStarTap,
  });

  bool get _hasSwipeFeedback {
    return swipeColor != null && swipeOpacity > 0;
  }

  Color _cardText(Color fallback) {
    return cardTextColor ?? fallback;
  }

  double _meaningFontSize(String value) {
    final length = value.runes.length;

    if (length >= 52) return 12;
    if (length >= 38) return 13;
    if (length >= 26) return 14;
    return 15;
  }

  double _readingFontSize(String value) {
    final length = value.runes.length;

    if (length >= 40) return 15;
    if (length >= 32) return 16;
    if (length >= 24) return 17;

    return 18;
  }

  double _answerFontSize(String value) {
    final length = value.runes.length;

    if (length >= 10) return 30;
    if (length >= 8) return 34;
    if (length > 6) return 38;

    return 48;
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
        _readingHeader(),
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
            color: _cardText(GakujiColors.darkGray),
          ),
        ),
        const Spacer(),
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
                child: GakujiLowLatencyWritingCanvas(
                  strokes: activeSlotStrokes,
                  showGrid: showGrid,
                  onStrokeStart: onStrokeStart,
                  onStrokeUpdate: onStrokeUpdate,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        WritingStudyActionRow(
          width: 280,
          isCheckingAnswer: isCheckingAnswer,
          isCheckingFinalSlot: isCheckingFinalSlot,
          onClear: onClear,
          onCheck: onCheck,
        ),
      ],
    );
  }

  Widget _answerRevealContent() {
    final answerText = answerResult?.correctAnswer ?? prompt.answer;

    return Column(
      children: [
        const SizedBox(height: 12),
        _readingHeader(),
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
            color: _cardText(GakujiColors.darkGray),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              answerText,
              maxLines: 1,
              softWrap: false,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: _answerFontSize(answerText),
                height: 1,
                color: _cardText(GakujiColors.deckBlue),
                fontWeight: FontWeight.w700,
              ),
            ),
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
              color: _cardText(GakujiColors.softGray),
            ),
          ),
      ],
    );
  }


  Widget _readingHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Text(
        prompt.reading,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        softWrap: true,
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: GakujiText.small.copyWith(
          fontSize: _readingFontSize(prompt.reading),
          height: 1.08,
          color: _cardText(GakujiColors.darkGray),
        ),
      ),
    );
  }

  Widget _answerSlotRow() {
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
                                  color: _cardText(slotColor),
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

  _WritingAnswerSlotMetrics _slotMetricsFor({
    required int slotCount,
    required double maxWidth,
  }) {
    if (slotCount <= 6) {
      return const _WritingAnswerSlotMetrics(
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

    return _WritingAnswerSlotMetrics(
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
}

class WritingStudyActionRow extends StatelessWidget {
  final double width;
  final bool isCheckingAnswer;
  final bool isCheckingFinalSlot;
  final VoidCallback onClear;
  final VoidCallback? onCheck;

  const WritingStudyActionRow({
    super.key,
    required this.width,
    required this.isCheckingAnswer,
    required this.isCheckingFinalSlot,
    required this.onClear,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    final checkLabel = isCheckingAnswer
        ? 'Checking...'
        : isCheckingFinalSlot
            ? 'Submit'
            : 'Check';
    final buttonWidth = (width - 7) / 2;

    return Center(
      child: SizedBox(
        width: width,
        height: 34,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _WritingStudyActionButton(
              label: 'Clear',
              width: buttonWidth,
              onTap: onClear,
            ),
            _WritingStudyActionButton(
              label: checkLabel,
              width: buttonWidth,
              filled: true,
              onTap: isCheckingAnswer ? null : onCheck,
            ),
          ],
        ),
      ),
    );
  }
}

class _WritingAnswerSlotMetrics {
  final double margin;
  final double width;
  final double height;
  final double characterHeight;
  final double characterFontSize;
  final double gap;
  final double lineWidth;
  final double lineHeight;

  const _WritingAnswerSlotMetrics({
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

class _WritingStudyActionButton extends StatelessWidget {
  final String label;
  final double width;
  final bool filled;
  final VoidCallback? onTap;

  const _WritingStudyActionButton({
    required this.label,
    required this.width,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final backgroundColor =
        filled ? GakujiColors.mediumGray : GakujiColors.whiteCard;
    final borderColor =
        filled ? GakujiColors.mediumGray : GakujiColors.warmDivider;
    final foregroundColor =
        filled ? GakujiColors.lightDivider : GakujiColors.mediumGray;

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: _WritingCardPushable(
        onTap: onTap,
        pressedOffset: 2,
        builder: (pressed) {
          return Container(
            width: width,
            height: 28,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(9),
              border: filled
                  ? null
                  : Border.all(
                      color: borderColor,
                      width: 1.1,
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
                      fontSize: 13.5,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: foregroundColor,
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
