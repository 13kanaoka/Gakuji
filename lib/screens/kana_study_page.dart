import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gakuji/widgets/gakuji_page_route.dart';

import 'package:gakuji/models/writing_point.dart';
import 'package:gakuji/services/writing_answer_checker.dart';
import 'package:gakuji/services/writing_recognition_service.dart';
import 'package:gakuji/widgets/gakuji_options_sheet.dart';
import 'package:gakuji/widgets/gakuji_styles.dart';
import 'package:gakuji/widgets/low_latency_writing_canvas.dart';
import 'package:gakuji/widgets/gakuji_top_bar.dart';

class KanaStudyItem {
  final String character;
  final String romaji;
  final bool isKatakana;

  const KanaStudyItem({
    required this.character,
    required this.romaji,
    required this.isKatakana,
  });
}

enum KanaStudyEncounterType {
  reading,
  reverseReading,
  writing,
}

enum _KanaStudyNavigationAction {
  exitAll,
  restartFullStudy,
}

class _KanaStudyNavigationResult {
  final _KanaStudyNavigationAction action;
  final bool writingEnabled;
  final bool showWritingGrid;

  const _KanaStudyNavigationResult({
    required this.action,
    required this.writingEnabled,
    required this.showWritingGrid,
  });
}

class KanaStudyEncounter {
  final KanaStudyItem item;
  final KanaStudyEncounterType type;

  const KanaStudyEncounter({
    required this.item,
    required this.type,
  });
}

class KanaStudyPage extends StatefulWidget {
  final List<KanaStudyItem> items;
  final List<KanaStudyItem> answerPool;
  final List<KanaStudyEncounter>? encounterPlan;
  final bool writingEnabled;
  final bool isIncorrectReview;

  const KanaStudyPage({
    super.key,
    required this.items,
    this.answerPool = const [],
    this.encounterPlan,
    this.writingEnabled = true,
    this.isIncorrectReview = false,
  });

  @override
  State<KanaStudyPage> createState() => _KanaStudyPageState();
}

class _KanaStudyPageState extends State<KanaStudyPage> {
  static const Color incorrectRed = Color(0xFFF6A3A3);
  static const Color incorrectRedOutline = Color(0xFFE06F6F);

  static const Color correctGreen = Color(0xFFC5E7A5);
  static const Color correctGreenOutline = Color(0xFF8DBB66);

  static const Duration _answerFeedbackDuration = Duration(milliseconds: 650);
  static const Duration _writingFeedbackDuration =
      Duration(milliseconds: 1200);
  static const Duration _writingPromptTransitionDuration =
      Duration(milliseconds: 320);

  final math.Random _random = math.Random();

  late List<KanaStudyEncounter> encounters;
  final List<KanaStudyEncounter> incorrectEncounters = <KanaStudyEncounter>[];

  int currentIndex = 0;
  int correctCount = 0;
  int incorrectCount = 0;

  List<List<WritingPoint>> writingStrokes = <List<WritingPoint>>[];
  List<String> currentChoices = <String>[];

  String? selectedAnswer;
  bool? selectedAnswerWasCorrect;
  bool isShowingAnswerFeedback = false;
  bool isShowingWritingFeedback = false;
  bool isCheckingWriting = false;
  bool showWritingGrid = true;
  late bool writingEnabled;
  int _answerFeedbackGeneration = 0;

  KanaStudyEncounter get currentEncounter => encounters[currentIndex];
  int get totalEncounters => encounters.length;
  bool get isComplete => currentIndex >= totalEncounters;
  double get deckProgress {
    if (totalEncounters <= 0) return 0;
    return (currentIndex / totalEncounters).clamp(0.0, 1.0).toDouble();
  }

  @override
  void initState() {
    super.initState();
    writingEnabled = widget.writingEnabled;
    encounters = _buildEncounters();
    _prepareCurrentEncounter();
  }

  List<KanaStudyEncounter> _baseEncounterPlan() {
    final suppliedPlan = widget.encounterPlan;

    if (suppliedPlan != null) {
      return List<KanaStudyEncounter>.from(suppliedPlan)..shuffle(_random);
    }

    final built = <KanaStudyEncounter>[];
    final shuffledItems = List<KanaStudyItem>.from(widget.items)..shuffle(_random);

    for (final item in shuffledItems) {
      built.addAll([
        KanaStudyEncounter(
          item: item,
          type: KanaStudyEncounterType.reading,
        ),
        KanaStudyEncounter(
          item: item,
          type: KanaStudyEncounterType.reverseReading,
        ),
        KanaStudyEncounter(
          item: item,
          type: KanaStudyEncounterType.writing,
        ),
      ]);
    }

    return built;
  }

  List<KanaStudyEncounter> _buildEncounters() {
    final built = _baseEncounterPlan()
        .where(
          (encounter) =>
              writingEnabled ||
              encounter.type != KanaStudyEncounterType.writing,
        )
        .toList();

    built.shuffle(_random);
    return built;
  }

  String _encounterKey(KanaStudyEncounter encounter) {
    return '${encounter.item.isKatakana}:'
        '${encounter.item.character}:'
        '${encounter.type.name}';
  }

  void _prepareCurrentEncounter() {
    _answerFeedbackGeneration += 1;
    selectedAnswer = null;
    selectedAnswerWasCorrect = null;
    isShowingAnswerFeedback = false;
    isShowingWritingFeedback = false;
    isCheckingWriting = false;
    writingStrokes = <List<WritingPoint>>[];

    if (isComplete) {
      currentChoices = <String>[];
      return;
    }

    if (currentEncounter.type == KanaStudyEncounterType.writing) {
      currentChoices = <String>[];
    } else {
      currentChoices = _choicesFor(currentEncounter);
    }
  }

  void _restartStudy() {
    setState(() {
      encounters = _buildEncounters();
      currentIndex = 0;
      correctCount = 0;
      incorrectCount = 0;
      incorrectEncounters.clear();
      _prepareCurrentEncounter();
    });
  }

  void _setWritingEnabled(bool enabled) {
    if (writingEnabled == enabled) return;

    final completed = encounters.take(currentIndex).toList();
    final pending = encounters.skip(currentIndex).toList();

    setState(() {
      writingEnabled = enabled;

      if (!enabled) {
        final filteredPending = pending
            .where(
              (encounter) =>
                  encounter.type != KanaStudyEncounterType.writing,
            )
            .toList();

        encounters = <KanaStudyEncounter>[
          ...completed,
          ...filteredPending,
        ];
      } else {
        final existingKeys = <String>{
          ...completed.map(_encounterKey),
          ...pending.map(_encounterKey),
        };

        final missingWriting = _baseEncounterPlan()
            .where(
              (encounter) =>
                  encounter.type == KanaStudyEncounterType.writing &&
                  !existingKeys.contains(_encounterKey(encounter)),
            )
            .toList();

        final nextPending = <KanaStudyEncounter>[
          ...pending,
          ...missingWriting,
        ]..shuffle(_random);

        encounters = <KanaStudyEncounter>[
          ...completed,
          ...nextPending,
        ];
      }

      currentIndex = completed.length;
      _prepareCurrentEncounter();
    });
  }

  Future<void> _startIncorrectReview() async {
    if (incorrectEncounters.isEmpty) {
      _showFloatingMessage('No incorrect answers to review.');
      return;
    }

    final reviewEncounters = List<KanaStudyEncounter>.from(incorrectEncounters);

    final result = await Navigator.of(context).push<_KanaStudyNavigationResult>(
      GakujiPageRoute<_KanaStudyNavigationResult>(
        enableSwipeBack: false,
        builder: (context) => KanaStudyPage(
          items: widget.items,
          answerPool: widget.answerPool,
          encounterPlan: reviewEncounters,
          writingEnabled: writingEnabled,
          isIncorrectReview: true,
        ),
      ),
    );

    if (!mounted || result == null) return;

    if (widget.isIncorrectReview) {
      Navigator.of(context).pop(result);
      return;
    }

    switch (result.action) {
      case _KanaStudyNavigationAction.exitAll:
        Navigator.of(context).pop();
        break;
      case _KanaStudyNavigationAction.restartFullStudy:
        setState(() {
          writingEnabled = result.writingEnabled;
          showWritingGrid = result.showWritingGrid;
        });
        _restartStudy();
        break;
    }
  }

  void _exitStudy() {
    if (widget.isIncorrectReview) {
      Navigator.of(context).pop(
        _KanaStudyNavigationResult(
          action: _KanaStudyNavigationAction.exitAll,
          writingEnabled: writingEnabled,
          showWritingGrid: showWritingGrid,
        ),
      );
      return;
    }

    Navigator.of(context).pop();
  }

  void _restartFullStudy() {
    if (widget.isIncorrectReview) {
      Navigator.of(context).pop(
        _KanaStudyNavigationResult(
          action: _KanaStudyNavigationAction.restartFullStudy,
          writingEnabled: writingEnabled,
          showWritingGrid: showWritingGrid,
        ),
      );
      return;
    }

    _restartStudy();
  }

  void _advance() {
    if (currentIndex >= totalEncounters - 1) {
      setState(() {
        currentIndex = totalEncounters;
        _prepareCurrentEncounter();
      });
      return;
    }

    setState(() {
      currentIndex += 1;
      _prepareCurrentEncounter();
    });
  }

  String _correctAnswerFor(KanaStudyEncounter encounter) {
    return encounter.type == KanaStudyEncounterType.reading
        ? encounter.item.romaji
        : encounter.item.character;
  }

  Future<void> _handleAnswerTap(String answer) async {
    if (isComplete || isShowingAnswerFeedback) return;

    final encounter = currentEncounter;
    final isCorrect = answer == _correctAnswerFor(encounter);
    final feedbackGeneration = ++_answerFeedbackGeneration;

    setState(() {
      selectedAnswer = answer;
      selectedAnswerWasCorrect = isCorrect;
      isShowingAnswerFeedback = true;

      if (isCorrect) {
        correctCount += 1;
      } else {
        incorrectCount += 1;
        incorrectEncounters.add(encounter);
      }
    });

    await Future<void>.delayed(_answerFeedbackDuration);

    if (!mounted || feedbackGeneration != _answerFeedbackGeneration) return;
    _advance();
  }

  void _addWritingPoint(Offset point, {required bool startsStroke}) {
    if (isCheckingWriting) return;

    final writingPoint = WritingPoint.fromOffset(
      x: point.dx,
      y: point.dy,
      time: DateTime.now().millisecondsSinceEpoch,
    );

    if (startsStroke || writingStrokes.isEmpty) {
      writingStrokes.add(<WritingPoint>[writingPoint]);
    } else {
      writingStrokes.last.add(writingPoint);
    }
  }

  void _clearWriting() {
    if (writingStrokes.isEmpty || isCheckingWriting) return;

    setState(() {
      writingStrokes = <List<WritingPoint>>[];
    });
  }

  Future<void> _submitWriting() async {
    if (isComplete || isCheckingWriting) return;

    if (!WritingRecognitionService.hasStrokesInSlot(writingStrokes)) {
      _showFloatingMessage('Write the kana first');
      return;
    }

    final encounter = currentEncounter;

    setState(() {
      isCheckingWriting = true;
    });

    final recognizedCharacter = await WritingRecognitionService.recognizeSlot(
      slotStrokes: writingStrokes,
      mockCharacter: encounter.item.character,
    );

    if (!mounted) return;

    final answerResult = WritingAnswerChecker.check(
      submittedAnswer: recognizedCharacter,
      correctAnswer: encounter.item.character,
    );

    final feedbackGeneration = ++_answerFeedbackGeneration;

    setState(() {
      isShowingWritingFeedback = true;

      if (answerResult.isCorrect) {
        correctCount += 1;
      } else {
        incorrectCount += 1;
        incorrectEncounters.add(encounter);
      }
    });

    await Future<void>.delayed(_writingFeedbackDuration);

    if (!mounted || feedbackGeneration != _answerFeedbackGeneration) return;
    _advance();
  }

  List<String> _choicesFor(KanaStudyEncounter encounter) {
    final target = encounter.item;
    final pool = widget.answerPool.isNotEmpty ? widget.answerPool : widget.items;

    final targetKanaLength = target.character.runes.length;
    final sameShapePool = pool.where(
      (candidate) =>
          candidate.isKatakana == target.isKatakana &&
          candidate.character.runes.length == targetKanaLength,
    );

    if (encounter.type == KanaStudyEncounterType.reading) {
      final choices = <String>{target.romaji};
      final distractors = sameShapePool
          .where((candidate) => candidate.romaji != target.romaji)
          .map((candidate) => candidate.romaji)
          .toSet()
          .toList()
        ..shuffle(_random);

      for (final distractor in distractors) {
        choices.add(distractor);
        if (choices.length == 4) break;
      }

      return choices.toList()..shuffle(_random);
    }

    final choices = <String>{target.character};
    final distractors = sameShapePool
        .where(
          (candidate) =>
              candidate.character != target.character &&
              candidate.romaji != target.romaji,
        )
        .map((candidate) => candidate.character)
        .toSet()
        .toList()
      ..shuffle(_random);

    for (final distractor in distractors) {
      choices.add(distractor);
      if (choices.length == 4) break;
    }

    return choices.toList()..shuffle(_random);
  }

  void _openStudyOptions() {
    final pageContext = context;

    showGakujiOptionsSheet(
      context: pageContext,
      title: 'Study Options',
      sectionsBuilder: (sheetContext) => [
        GakujiOptionsSheetSection(
          title: 'Writing',
          items: [
            GakujiOptionsSheetItem(
              icon: writingEnabled
                  ? Icons.edit_rounded
                  : Icons.block_rounded,
              label: writingEnabled ? 'Writing Enabled' : 'Writing Disabled',
              iconColor: writingEnabled
                  ? GakujiColors.reading
                  : GakujiColors.mediumGray,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _setWritingEnabled(!writingEnabled);
              },
            ),
            if (writingEnabled)
              GakujiOptionsSheetItem(
                icon: showWritingGrid
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                label: showWritingGrid ? 'Hide Grid' : 'Show Grid',
                iconColor: showWritingGrid
                    ? GakujiColors.darkGray
                    : GakujiColors.mediumGray,
                onTap: () {
                  setState(() {
                    showWritingGrid = !showWritingGrid;
                  });
                },
              ),
          ],
        ),
        GakujiOptionsSheetSection(
          title: 'Session',
          items: [
            GakujiOptionsSheetItem(
              icon: Icons.refresh_rounded,
              label: 'Restart Study',
              iconColor: GakujiColors.mediumGray,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _restartFullStudy();
              },
            ),
            GakujiOptionsSheetItem(
              icon: Icons.close_rounded,
              label: 'Exit Study',
              iconColor: GakujiColors.mediumGray,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _exitStudy();
              },
            ),
          ],
        ),
      ],
    );
  }

  void _showFloatingMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
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
    if (isComplete) {
      return _completeScreen();
    }

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            _studyTopBar(
              leftIcon: Icons.close_rounded,
              onLeftTap: _exitStudy,
              title: '${currentIndex + 1}/$totalEncounters',
              rightIcon: Icons.menu_rounded,
              onRightTap: _openStudyOptions,
            ),
            _progressBar(deckProgress),
            const SizedBox(height: 24),
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
            const SizedBox(height: 24),
            Expanded(
              child: _encounterView(),
            ),
          ],
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

  Widget _scriptLabel(KanaStudyItem item) {
    return Text(
      item.isKatakana ? 'Katakana' : 'Hiragana',
      textAlign: TextAlign.center,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: 13.5,
        height: 1,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: GakujiColors.mediumGray.withValues(alpha: 0.82),
      ),
    );
  }

  Widget _encounterView() {
    final encounter = currentEncounter;
    final isReading = encounter.type == KanaStudyEncounterType.reading;
    final isWriting = encounter.type == KanaStudyEncounterType.writing;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;

        Widget prompt({required double height}) {
          return SizedBox(
            height: height,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isReading
                        ? encounter.item.character
                        : encounter.item.romaji,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontFamily: isReading ? GakujiFonts.japanese : null,
                      fontSize: isReading
                          ? (encounter.item.character.runes.length > 1
                              ? 86
                              : 112)
                          : 66,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      letterSpacing: isReading ? -1.0 : -1.4,
                      color: GakujiColors.darkGray.withValues(alpha: 0.86),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _scriptLabel(encounter.item),
                ],
              ),
            ),
          );
        }

        final promptHeight = compact ? 210.0 : 260.0;

        if (isWriting) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              compact ? 0 : 4,
              24,
              MediaQuery.of(context).padding.bottom + 24,
            ),
            child: Column(
              children: [
                _writingPrompt(
                  encounter,
                  height: promptHeight,
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _writingAnswerArea(),
                  ),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            compact ? 0 : 4,
            24,
            MediaQuery.of(context).padding.bottom + 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight -
                  MediaQuery.of(context).padding.bottom -
                  (compact ? 10 : 18),
            ),
            child: Column(
              children: [
                prompt(height: promptHeight),
                _multipleChoiceArea(encounter),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _writingPrompt(
    KanaStudyEncounter encounter, {
    required double height,
  }) {
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: 0,
          end: isShowingWritingFeedback ? 1 : 0,
        ),
        duration: _writingPromptTransitionDuration,
        curve: Curves.easeOutCubic,
        builder: (context, progress, child) {
          final pronunciationScale = 1 - (0.58 * progress);
          final pronunciationOffset = 46 * progress;
          final pronunciationOpacity = 0.86 - (0.44 * progress);
          final kanaScale = 0.68 + (0.32 * progress);
          final kanaOffset = -14 * progress;

          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Transform.translate(
                offset: Offset(0, pronunciationOffset),
                child: Transform.scale(
                  scale: pronunciationScale,
                  child: Text(
                    encounter.item.romaji,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 66,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -1.4,
                      color: GakujiColors.darkGray.withValues(
                        alpha: pronunciationOpacity,
                      ),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Opacity(
                  opacity: progress,
                  child: Transform.translate(
                    offset: Offset(0, kanaOffset),
                    child: Transform.scale(
                      scale: kanaScale,
                      child: Text(
                        encounter.item.character,
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontFamily: GakujiFonts.japanese,
                          fontSize: encounter.item.character.runes.length > 1
                              ? 86
                              : 112,
                          height: 1,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -1.0,
                          color:
                              GakujiColors.darkGray.withValues(alpha: 0.90),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: (height / 2) + 48 + (30 * progress),
                left: 0,
                right: 0,
                child: _scriptLabel(encounter.item),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _multipleChoiceArea(KanaStudyEncounter encounter) {
    final choices = currentChoices;
    final showKanaAnswers =
        encounter.type == KanaStudyEncounterType.reverseReading;
    final correctAnswer = _correctAnswerFor(encounter);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.06,
        ),
        itemCount: choices.length,
        itemBuilder: (context, index) {
          final choice = choices[index];

          _KanaAnswerState answerState = _KanaAnswerState.idle;

          if (isShowingAnswerFeedback) {
            if (choice == correctAnswer) {
              answerState = _KanaAnswerState.correct;
            } else if (choice == selectedAnswer && selectedAnswerWasCorrect == false) {
              answerState = _KanaAnswerState.incorrect;
            }
          }

          return _KanaAnswerTile(
            text: choice,
            useJapaneseFont: showKanaAnswers,
            state: answerState,
            correctColor: correctGreen,
            correctOutlineColor: correctGreenOutline,
            incorrectColor: incorrectRed,
            incorrectOutlineColor: incorrectRedOutline,
            onTap: isShowingAnswerFeedback
                ? null
                : () => _handleAnswerTap(choice),
          );
        },
      ),
    );
  }

  Widget _writingAnswerArea() {
    const boxSize = 280.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _KanaStudyWritingBox(
          size: boxSize,
          strokes: writingStrokes,
          showGrid: showWritingGrid,
          onStrokeStart: (point) {
            _addWritingPoint(point, startsStroke: true);
          },
          onStrokeUpdate: (point) {
            _addWritingPoint(point, startsStroke: false);
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: boxSize,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _WritingActionButton(
                label: 'Clear',
                color: GakujiColors.whiteCard,
                textColor: GakujiColors.mediumGray,
                width: 78,
                onTap: isCheckingWriting || isShowingWritingFeedback
                    ? null
                    : _clearWriting,
              ),
              _WritingActionButton(
                label: isCheckingWriting ? 'Checking...' : 'Submit',
                color: GakujiColors.reading,
                textColor: Colors.white,
                width: isCheckingWriting ? 112 : 88,
                onTap: isCheckingWriting || isShowingWritingFeedback
                    ? null
                    : _submitWriting,
              ),
            ],
          ),
        ),
      ],
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
              onLeftTap: _exitStudy,
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
                          label: 'Restart Study',
                          color: GakujiColors.whiteCard,
                          textColor: GakujiColors.mediumGray,
                          outlined: true,
                          height: buttonHeight,
                          onTap: _restartFullStudy,
                        ),
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
}

enum _KanaAnswerState {
  idle,
  correct,
  incorrect,
}

class _KanaAnswerTile extends StatelessWidget {
  final String text;
  final bool useJapaneseFont;
  final _KanaAnswerState state;
  final Color correctColor;
  final Color correctOutlineColor;
  final Color incorrectColor;
  final Color incorrectOutlineColor;
  final VoidCallback? onTap;

  const _KanaAnswerTile({
    required this.text,
    required this.useJapaneseFont,
    required this.state,
    required this.correctColor,
    required this.correctOutlineColor,
    required this.incorrectColor,
    required this.incorrectOutlineColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = switch (state) {
      _KanaAnswerState.correct => correctColor,
      _KanaAnswerState.incorrect => incorrectColor,
      _KanaAnswerState.idle => GakujiColors.whiteCard,
    };

    final borderColor = switch (state) {
      _KanaAnswerState.correct => correctOutlineColor,
      _KanaAnswerState.incorrect => incorrectOutlineColor,
      _KanaAnswerState.idle => Colors.transparent,
    };

    final textColor = switch (state) {
      _KanaAnswerState.correct => correctOutlineColor,
      _KanaAnswerState.incorrect => incorrectOutlineColor,
      _KanaAnswerState.idle => GakujiColors.reading,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: state == _KanaAnswerState.idle ? 0 : 3,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: GakujiColors.reading.withValues(alpha: 0.08),
          highlightColor: GakujiColors.reading.withValues(alpha: 0.04),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 170),
                  style: TextStyle(
                    fontFamily: useJapaneseFont ? GakujiFonts.japanese : null,
                    fontSize: useJapaneseFont
                        ? (text.runes.length > 1 ? 42 : 56)
                        : 48,
                    height: 1,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -1.1,
                    color: textColor,
                  ),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WritingActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final double width;
  final VoidCallback? onTap;

  const _WritingActionButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 42,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: GakujiColors.reading.withValues(alpha: 0.08),
          highlightColor: GakujiColors.reading.withValues(alpha: 0.04),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
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
        ),
      ),
    );
  }
}

class _KanaStudyWritingBox extends StatelessWidget {
  final double size;
  final List<List<WritingPoint>> strokes;
  final bool showGrid;
  final ValueChanged<Offset> onStrokeStart;
  final ValueChanged<Offset> onStrokeUpdate;

  const _KanaStudyWritingBox({
    required this.size,
    required this.strokes,
    required this.showGrid,
    required this.onStrokeStart,
    required this.onStrokeUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
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
            strokes: strokes,
            showGrid: showGrid,
            onStrokeStart: onStrokeStart,
            onStrokeUpdate: onStrokeUpdate,
          ),
        ),
      ),
    );
  }
}

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
    this.animationProgress = 1,
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
  bool shouldRepaint(covariant _CompletionGaugePainter oldDelegate) {
    return oldDelegate.correctCount != correctCount ||
        oldDelegate.incorrectCount != incorrectCount ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.correctColor != correctColor ||
        oldDelegate.incorrectColor != incorrectColor ||
        oldDelegate.animationProgress != animationProgress;
  }
}
