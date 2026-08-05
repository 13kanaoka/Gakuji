import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/reading_card_edit_data.dart';
import '../data/review_card_data.dart';
import '../models/deck.dart';
import '../models/review_card.dart';
import '../models/term.dart';
import '../models/writing_point.dart';
import '../models/writing_prompt.dart';
import '../services/dictionary_service.dart';
import '../services/gakuji_user_data_store.dart';
import '../services/reading_card_edit_storage.dart';
import '../services/review_scheduler.dart';
import '../services/review_settings.dart';
import '../services/prompt_converter.dart';
import '../services/writing_answer_checker.dart';
import '../services/writing_recognition_service.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import '../widgets/reading_card_back.dart';
import '../widgets/writing_study_card.dart';

class ReviewStudyPage extends StatefulWidget {
  final Deck deck;
  final List<ReviewCard> reviewCards;

  const ReviewStudyPage({
    super.key,
    required this.deck,
    required this.reviewCards,
  });

  @override
  State<ReviewStudyPage> createState() => _ReviewStudyPageState();
}

class _ReviewStudyPageState extends State<ReviewStudyPage> {
  static const Duration _inSessionReviewThreshold = Duration(minutes: 10);

  static const Color newBlue = Color(0xFFB8C7F2);
  static const Color newBlueText = Color(0xFF6F82BF);

  static const Color learningOrange = Color(0xFFF3BE8B);
  static const Color learningOrangeText = Color(0xFFC77A3E);

  static const Color reviewGreen = Color(0xFFC5E7A5);
  static const Color reviewGreenText = Color(0xFF8DBB66);

  late List<_ReviewQueueEntry> reviewQueue;
  late final int initialSessionCount;

  final Map<String, ReadingCardEditData> readingCardEdits = {};
  final Map<String, Term> readingSourceTerms = {};
  final Set<String> savedReadingCardEditTermIds = {};

  List<List<List<WritingPoint>>> writingSlotStrokes = [];
  List<String?> writingSlotAnswers = [];
  int activeWritingSlotIndex = 0;

  bool showWritingGrid = true;
  bool isCheckingWritingAnswer = false;
  WritingAnswerResult? writingAnswerResult;

  bool answerShown = false;
  bool isRating = false;
  bool showFurigana = true;

  int againCount = 0;
  int hardCount = 0;
  int goodCount = 0;
  int easyCount = 0;
  int graduatedCount = 0;

  _ReviewQueueEntry? get currentEntry {
    if (reviewQueue.isEmpty) return null;

    return reviewQueue.first;
  }

  ReviewCard? get currentReviewCard {
    return currentEntry?.card;
  }

  Term? get currentTerm {
    final reviewCard = currentReviewCard;

    if (reviewCard == null) return null;

    try {
      return widget.deck.terms.firstWhere((term) {
        final reviewTermId = term.sourceId ?? term.id;
        return reviewTermId == reviewCard.termId;
      });
    } catch (_) {
      return null;
    }
  }

  bool get isCurrentCardWriting {
    return currentReviewCard?.cardType == ReviewCardType.writing;
  }

  WritingPrompt? get currentWritingPrompt {
    final term = currentTerm;

    if (term == null || !isCurrentCardWriting) return null;

    return PromptConverter.fromTerm(term);
  }

  String get writingGridPreferenceKey {
    return 'writing_grid_visible_${widget.deck.id}';
  }

  bool get isCheckingFinalWritingSlot {
    if (writingSlotAnswers.isEmpty) return false;

    final emptyIndexes = <int>[];

    for (int index = 0; index < writingSlotAnswers.length; index++) {
      final answer = writingSlotAnswers[index];

      if (answer == null || answer.isEmpty) {
        emptyIndexes.add(index);
      }
    }

    return emptyIndexes.length == 1 &&
        emptyIndexes.first == activeWritingSlotIndex;
  }

  int get newCount {
    return reviewQueue
        .where((entry) => entry.originalState == ReviewCardState.newCard)
        .length;
  }

  int get learningCount {
    return reviewQueue
        .where((entry) {
          return entry.originalState == ReviewCardState.learning ||
              entry.originalState == ReviewCardState.relearning;
        })
        .length;
  }

  int get reviewCount {
    return reviewQueue
        .where((entry) => entry.originalState == ReviewCardState.review)
        .length;
  }

  int get reviewedCount {
    return againCount + hardCount + goodCount + easyCount;
  }

  bool get isComplete {
    return reviewQueue.isEmpty;
  }

  double get deckProgress {
    if (initialSessionCount <= 0) return 0;

    return (graduatedCount / initialSessionCount)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  @override
  void initState() {
    super.initState();

    initialSessionCount = widget.reviewCards.length;

    reviewQueue = widget.reviewCards
        .map(
          (card) => _ReviewQueueEntry(
            card: card,
            originalState: card.state,
          ),
        )
        .toList();

    _resetWritingState();
    _loadWritingGridPreference();

    if (widget.reviewCards.any(
      (card) => card.cardType == ReviewCardType.reading,
    )) {
      _loadReadingCardEdits();
    }
  }

  Future<void> _loadReadingCardEdits() async {
    final loadedEdits = <String, ReadingCardEditData>{};
    final loadedSourceTerms = <String, Term>{};
    final loadedSavedIds = <String>{};

    for (final term in widget.deck.terms) {
      var sourceTerm = term;
      final dictionaryTermId = term.sourceId ?? term.id;

      try {
        sourceTerm = await DictionaryService.getTermByIdAsync(
          dictionaryTermId,
        );
      } catch (_) {
        // Keep the deck copy if the dictionary source cannot be loaded.
      }

      final hasSavedEdit = await ReadingCardEditStorage.hasSavedEdit(
        deck: widget.deck,
        term: term,
      );

      final editData = await ReadingCardEditStorage.load(
        deck: widget.deck,
        term: term,
      );

      loadedSourceTerms[term.id] = sourceTerm;
      loadedEdits[term.id] = editData;

      if (hasSavedEdit) {
        loadedSavedIds.add(term.id);
      }
    }

    if (!mounted) return;

    setState(() {
      readingSourceTerms
        ..clear()
        ..addAll(loadedSourceTerms);
      readingCardEdits
        ..clear()
        ..addAll(loadedEdits);
      savedReadingCardEditTermIds
        ..clear()
        ..addAll(loadedSavedIds);
    });
  }

  bool _hasSavedCardEdit(Term term) {
    return savedReadingCardEditTermIds.contains(term.id);
  }

  ReadingCardEditData? _cardEditFor(Term term) {
    return readingCardEdits[term.id];
  }

  Term _reviewSourceTermFor(Term term) {
    return readingSourceTerms[term.id] ?? term;
  }

  bool _reviewSourceIsReady(Term term) {
    return term.sourceId == null || readingSourceTerms.containsKey(term.id);
  }

  String _limitReviewNote(String value) {
    if (value.runes.length <= 35) return value;
    return String.fromCharCodes(value.runes.take(35));
  }

  List<String> _defaultReviewGlossesFor(Term term) {
    if (!_reviewSourceIsReady(term)) return const [];

    final sourceTerm = _reviewSourceTermFor(term);
    final glossBySenseIndex = <int, String>{};

    for (final sense in sourceTerm.senses) {
      final definition = sense.displayDefinition.trim();
      if (definition.isNotEmpty) {
        glossBySenseIndex[sense.index] = definition;
      }
    }

    final selectedSenseIndexes = term.selectedGlosses
        .map((selection) => selection.senseIndex)
        .toSet();
    final selectedGlosses = <String>[];

    for (final sense in sourceTerm.senses) {
      if (!selectedSenseIndexes.contains(sense.index)) continue;
      final definition = glossBySenseIndex[sense.index];
      if (definition != null && !selectedGlosses.contains(definition)) {
        selectedGlosses.add(definition);
      }
      if (selectedGlosses.length >= 3) break;
    }

    if (selectedGlosses.isNotEmpty) return selectedGlosses;

    final defaults = glossBySenseIndex.values.take(3).toList();
    if (defaults.isNotEmpty) return defaults;

    final fallback = sourceTerm.cardMeaning.trim();
    return fallback.isEmpty ? const [] : [fallback];
  }

  List<String> _resolvedReviewGlossesFor(
    Term term,
    List<String> storedGlosses,
  ) {
    if (storedGlosses.isEmpty) return _defaultReviewGlossesFor(term);

    final sourceTerm = _reviewSourceTermFor(term);
    final resolved = <String>[];
    final usedSenseIndexes = <int>{};

    for (final storedGloss in storedGlosses) {
      final cleanedGloss = storedGloss.trim();
      if (cleanedGloss.isEmpty) continue;

      DictionarySense? matchedSense;
      for (final sense in sourceTerm.senses) {
        final matchesSense = sense.displayDefinition.trim() == cleanedGloss;
        final matchesLegacyGloss = sense.glosses.any(
          (gloss) => gloss.trim() == cleanedGloss,
        );
        if (matchesSense || matchesLegacyGloss) {
          matchedSense = sense;
          break;
        }
      }

      if (matchedSense == null || !usedSenseIndexes.add(matchedSense.index)) {
        continue;
      }

      final definition = matchedSense.displayDefinition.trim();
      if (definition.isNotEmpty) resolved.add(definition);
      if (resolved.length >= 3) break;
    }

    return resolved.isNotEmpty ? resolved : _defaultReviewGlossesFor(term);
  }

  Set<int> _reviewSenseIndexesForGlosses(
    Term term,
    List<String> glosses,
  ) {
    final sourceTerm = _reviewSourceTermFor(term);
    final indexes = <int>{};

    for (final displayedGloss in glosses) {
      final cleanedGloss = displayedGloss.trim();
      if (cleanedGloss.isEmpty) continue;

      for (final sense in sourceTerm.senses) {
        final matchesSense = sense.displayDefinition.trim() == cleanedGloss;
        final matchesLegacyGloss = sense.glosses.any(
          (gloss) => gloss.trim() == cleanedGloss,
        );
        if (matchesSense || matchesLegacyGloss) {
          indexes.add(sense.index);
          break;
        }
      }
    }

    return indexes;
  }

  List<DictionaryExample> _reviewEligibleExamplesFor(
    Term term,
    List<String> glosses,
  ) {
    final sourceTerm = _reviewSourceTermFor(term);
    final senseIndexes = _reviewSenseIndexesForGlosses(term, glosses);
    final examples = <DictionaryExample>[];
    final seen = <String>{};

    for (final sense in sourceTerm.senses) {
      if (!senseIndexes.contains(sense.index)) continue;
      for (final example in sense.examples) {
        final key = '${example.japanese}\u0000${example.english}';
        if (!seen.add(key)) continue;
        examples.add(example);
      }
    }

    return examples;
  }

  List<String> _reviewGlossesFor(Term term) {
    final editData = _cardEditFor(term);
    if (_hasSavedCardEdit(term) && editData != null) {
      return _resolvedReviewGlossesFor(term, editData.selectedGlosses);
    }
    return _defaultReviewGlossesFor(term);
  }

  String _reviewNoteFor(Term term) {
    final note = _hasSavedCardEdit(term)
        ? _cardEditFor(term)?.note ?? ''
        : term.note ?? '';
    return _limitReviewNote(note.trim());
  }

  List<DictionaryExample> _reviewExamplesFor(Term term) {
    final editData = _cardEditFor(term);
    final glosses = _reviewGlossesFor(term);
    final eligibleExamples = _reviewEligibleExamplesFor(term, glosses);

    if (_hasSavedCardEdit(term) && editData != null) {
      return ReadingCardEditData.examplesFromKeys(
        examples: eligibleExamples,
        selectedExampleKeys: editData.selectedExampleKeys,
      ).take(1).toList();
    }

    return eligibleExamples.take(1).toList();
  }

  String? _reviewPhotoPathFor(Term term) {
    if (!_hasSavedCardEdit(term)) return null;
    if (!(_cardEditFor(term)?.photoEnabled ?? false)) return null;
    final path = _cardEditFor(term)?.photoPath?.trim();
    if (path == null || path.isEmpty || !File(path).existsSync()) return null;
    return path;
  }


  Future<void> _loadWritingGridPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedGridVisible = prefs.getBool(writingGridPreferenceKey);

    if (!mounted || savedGridVisible == null) return;

    setState(() {
      showWritingGrid = savedGridVisible;
    });
  }

  Future<void> _saveWritingGridPreference() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      writingGridPreferenceKey,
      showWritingGrid,
    );

    scheduleUserDataSave();
  }

  void _resetWritingState() {
    final prompt = currentWritingPrompt;
    final slotCount = prompt?.slotCount ?? 1;

    writingSlotStrokes = List.generate(
      slotCount,
      (_) => <List<WritingPoint>>[],
    );

    writingSlotAnswers = List<String?>.filled(
      slotCount,
      null,
    );

    activeWritingSlotIndex = 0;
    isCheckingWritingAnswer = false;
    writingAnswerResult = null;
  }

  void toggleWritingGrid() {
    setState(() {
      showWritingGrid = !showWritingGrid;
    });

    _saveWritingGridPreference();
  }

  void selectWritingSlot(int index) {
    if (answerShown) return;
    if (index < 0 || index >= writingSlotStrokes.length) return;

    setState(() {
      activeWritingSlotIndex = index;
    });
  }

  void addWritingStroke(
    Offset point, {
    bool isStart = false,
  }) {
    if (answerShown || writingSlotStrokes.isEmpty) return;

    final writingPoint = WritingPoint.fromOffset(
      x: point.dx,
      y: point.dy,
      time: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() {
      final slot = writingSlotStrokes[activeWritingSlotIndex];

      if (isStart || slot.isEmpty) {
        slot.add(<WritingPoint>[writingPoint]);
      } else {
        slot.last.add(writingPoint);
      }
    });
  }

  void clearActiveWritingSlot() {
    if (answerShown || writingSlotStrokes.isEmpty) return;

    setState(() {
      writingSlotStrokes[activeWritingSlotIndex].clear();

      if (activeWritingSlotIndex < writingSlotAnswers.length) {
        writingSlotAnswers[activeWritingSlotIndex] = null;
      }
    });
  }

  void _moveToNextEmptyWritingSlot() {
    final nextIndex = writingSlotAnswers.indexWhere(
      (answer) => answer == null || answer.isEmpty,
    );

    if (nextIndex != -1) {
      activeWritingSlotIndex = nextIndex;
    }
  }

  Future<void> checkWritingAnswer() async {
    final prompt = currentWritingPrompt;

    if (prompt == null ||
        isCheckingWritingAnswer ||
        answerShown ||
        writingSlotStrokes.isEmpty) {
      return;
    }

    final activeSlotStrokes =
        writingSlotStrokes[activeWritingSlotIndex];

    final hasInput = WritingRecognitionService.hasStrokesInSlot(
      activeSlotStrokes,
    );

    if (!hasInput) {
      _showFloatingMessage('Write in the selected box first.');
      return;
    }

    setState(() {
      isCheckingWritingAnswer = true;
    });

    final correctCharacters = prompt.answer.runes.map((rune) {
      return String.fromCharCode(rune);
    }).toList();

    final mockCharacter = activeWritingSlotIndex < correctCharacters.length
        ? correctCharacters[activeWritingSlotIndex]
        : '';

    final recognizedCharacter =
        await WritingRecognitionService.recognizeSlot(
      slotStrokes: activeSlotStrokes,
      mockCharacter: mockCharacter,
    );

    if (!mounted) return;

    if (recognizedCharacter.isEmpty) {
      setState(() {
        isCheckingWritingAnswer = false;
      });

      _showFloatingMessage('Could not recognize that character. Try again.');
      return;
    }

    setState(() {
      writingSlotAnswers[activeWritingSlotIndex] = recognizedCharacter;

      final allSlotsFilled = WritingRecognitionService.areAllSlotsFilled(
        writingSlotAnswers,
      );

      if (allSlotsFilled) {
        final submittedAnswer =
            WritingRecognitionService.buildSubmittedAnswer(
          writingSlotAnswers,
        );

        writingAnswerResult = WritingAnswerChecker.check(
          submittedAnswer: submittedAnswer,
          correctAnswer: prompt.answer,
        );

        answerShown = true;
      } else {
        _moveToNextEmptyWritingSlot();
      }

      isCheckingWritingAnswer = false;
    });
  }

  void scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
  }

  void handleExit() {
    scheduleUserDataSave();

    Navigator.pop(context);
  }

  void showAnswer() {
    if (isRating || isCheckingWritingAnswer) return;

    setState(() {
      answerShown = true;

      if (isCurrentCardWriting) {
        writingAnswerResult = null;
      }
    });
  }

  Future<void> rateCard(ReviewRating rating) async {
    final entry = currentEntry;

    if (entry == null || isRating) return;

    setState(() {
      isRating = true;
    });

    try {
      final reviewedAt = DateTime.now().toUtc();
      final result = ReviewScheduler.reviewCard(
        card: entry.card,
        rating: rating,
        now: reviewedAt,
      );
      final scheduledInterval = result.card.dueDate
          .toUtc()
          .difference(reviewedAt);
      final keepInCurrentSession =
          scheduledInterval < _inSessionReviewThreshold;

      await applyReviewResult(result);

      if (entry.originalState == ReviewCardState.newCard) {
        await ReviewSettingsStore.recordStartedNewCard(
          now: reviewedAt,
        );
      }

      if (entry.originalState == ReviewCardState.review) {
        await ReviewSettingsStore.recordCompletedReview(
          now: reviewedAt,
        );
      }

      scheduleUserDataSave();

      if (!mounted) return;

      setState(() {
        switch (rating) {
          case ReviewRating.again:
            againCount++;
            break;
          case ReviewRating.hard:
            hardCount++;
            break;
          case ReviewRating.good:
            goodCount++;
            break;
          case ReviewRating.easy:
            easyCount++;
            break;
        }

        reviewQueue.removeAt(0);

        if (keepInCurrentSession) {
          reviewQueue.add(
            _ReviewQueueEntry(
              card: result.card,
              originalState: result.card.state,
            ),
          );
        } else {
          graduatedCount++;
        }

        answerShown = false;
        isRating = false;
        _resetWritingState();
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isRating = false;
      });

      _showFloatingMessage('Could not save this review. Please try again.');
    }
  }

  void _showFloatingMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1500),
          backgroundColor: Colors.black.withValues(alpha: 0.86),
          content: Text(
            message,
            textScaler: TextScaler.noScaling,
            style: GakujiText.snackBar,
          ),
        ),
      );
  }

  void toggleFurigana() {
    setState(() {
      showFurigana = !showFurigana;
    });

    scheduleUserDataSave();
  }

  @override
  Widget build(BuildContext context) {
    if (isComplete) {
      return _completeScreen();
    }

    final term = currentTerm;

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            _reviewTopBar(
              leftIcon: Icons.close_rounded,
              onLeftTap: handleExit,
              rightWidget: _currentReviewControlButton(),
            ),
            _progressBar(deckProgress),
            const SizedBox(height: 18),
            _reviewCounters(),
            const SizedBox(height: 26),
            Expanded(
              child: _reviewContent(term),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: SizedBox(
                height: 54,
                child: answerShown
                    ? Align(
                        alignment: Alignment.bottomCenter,
                        child: Transform.translate(
                          offset: const Offset(0, 2),
                          child: _ratingButtons(),
                        ),
                      )
                    : _showAnswerButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewTopBar({
    required IconData leftIcon,
    required VoidCallback onLeftTap,
    required Widget rightWidget,
  }) {
    return GakujiTopBar(
      leftIcon: leftIcon,
      leftIconSize: 34,
      leftIconColor: GakujiColors.darkGray,
      onLeftTap: onLeftTap,
      title: 'Review',
      titleStyle: TextStyle(
        fontSize: 20,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: GakujiColors.darkGray,
      ),
      rightWidget: rightWidget,
    );
  }

  Widget _currentReviewControlButton() {
    if (isCurrentCardWriting) {
      return _writingGridButton();
    }

    return _furiganaButton();
  }

  Widget _completionControlButton() {
    switch (widget.deck.type) {
      case DeckType.writing:
        return _writingGridButton();
      case DeckType.reading:
        return _furiganaButton();
      case DeckType.hybrid:
        return const SizedBox(
          width: 44,
          height: 44,
        );
    }
  }

  Widget _writingGridButton() {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: toggleWritingGrid,
        splashColor: GakujiColors.deckBlue.withValues(alpha: 0.08),
        highlightColor: GakujiColors.deckBlue.withValues(alpha: 0.04),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            showWritingGrid
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            size: 27,
            color: showWritingGrid
                ? GakujiColors.darkGray
                : GakujiColors.mediumGray,
          ),
        ),
      ),
    );
  }

  Widget _furiganaButton() {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: toggleFurigana,
        splashColor: GakujiColors.deckBlue.withValues(alpha: 0.08),
        highlightColor: GakujiColors.deckBlue.withValues(alpha: 0.04),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Text(
              'あ',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 24,
                height: 1,
                fontWeight: FontWeight.w800,
                color: showFurigana
                    ? GakujiColors.darkGray
                    : GakujiColors.mediumGray,
              ),
            ),
          ),
        ),
      ),
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

  Widget _reviewCounters() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _reviewCounterPill(
          count: newCount,
          label: 'New',
          color: newBlue,
          textColor: newBlueText,
          alignLeft: true,
        ),
        _reviewCounterPill(
          count: learningCount,
          label: 'Learning',
          color: learningOrange,
          textColor: learningOrangeText,
          centered: true,
        ),
        _reviewCounterPill(
          count: reviewCount,
          label: 'Review',
          color: reviewGreen,
          textColor: reviewGreenText,
          alignLeft: false,
        ),
      ],
    );
  }

  Widget _reviewCounterPill({
    required int count,
    required String label,
    required Color color,
    required Color textColor,
    bool alignLeft = true,
    bool centered = false,
  }) {
    final borderRadius = centered
        ? BorderRadius.circular(GakujiRadius.pill)
        : alignLeft
            ? const BorderRadius.horizontal(
                right: Radius.circular(30),
              )
            : const BorderRadius.horizontal(
                left: Radius.circular(30),
              );

    final alignment = centered
        ? Alignment.center
        : alignLeft
            ? Alignment.centerLeft
            : Alignment.centerRight;

    final padding = centered
        ? EdgeInsets.zero
        : EdgeInsets.only(
            left: alignLeft ? 24 : 0,
            right: alignLeft ? 0 : 24,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 78,
          height: 34,
          padding: padding,
          alignment: alignment,
          decoration: BoxDecoration(
            color: color,
            borderRadius: borderRadius,
            border: Border.all(
              color: textColor,
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
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textScaler: TextScaler.noScaling,
          style: GakujiText.xSmall.copyWith(
            color: GakujiColors.mediumGray,
          ),
        ),
      ],
    );
  }


  Widget _reviewContent(Term? term) {
    if (isCurrentCardWriting) {
      return _writingReviewCard(term);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: _reviewCard(term),
    );
  }

  Widget _writingReviewCard(Term? term) {
    if (term == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: _missingTermCard(),
      );
    }

    final prompt = currentWritingPrompt;

    if (prompt == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: _missingTermCard(),
      );
    }

    final activeStrokes = writingSlotStrokes.isNotEmpty
        ? writingSlotStrokes[activeWritingSlotIndex]
        : <List<WritingPoint>>[];

    return WritingStudyCard(
      prompt: prompt,
      isAnswerRevealed: answerShown,
      answerResult: writingAnswerResult,
      slotAnswers: writingSlotAnswers,
      activeSlotIndex: activeWritingSlotIndex,
      activeSlotStrokes: activeStrokes,
      showGrid: showWritingGrid,
      isCheckingAnswer: isCheckingWritingAnswer,
      isCheckingFinalSlot: isCheckingFinalWritingSlot,
      showSwipeInstructions: false,
      onSelectSlot: selectWritingSlot,
      onClear: clearActiveWritingSlot,
      onCheck: isCheckingWritingAnswer ? null : checkWritingAnswer,
      onStrokeStart: (point) {
        addWritingStroke(
          point,
          isStart: true,
        );
      },
      onStrokeUpdate: addWritingStroke,
    );
  }

  Widget _reviewCard(Term? term) {
    if (term == null) {
      return _missingTermCard();
    }

    final showDefinition = answerShown;

    return ReadingCardFrame(
      child: Stack(
        children: [
          Center(
            child: _cardContent(
              term,
              showDefinition: showDefinition,
            ),
          ),
        ],
      ),
    );
  }

  Widget _missingTermCard() {
    return ReadingCardFrame(
      child: Center(
        child: Text(
          'This term could not be found.',
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: GakujiText.medium,
        ),
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
    final kanjiText =
        term.kanji.trim().isNotEmpty ? term.kanji.trim() : term.reading.trim();
    final readingText = term.reading.trim();
    final showReading = showFurigana &&
        readingText.isNotEmpty &&
        readingText != kanjiText;

    return SizedBox.expand(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showReading) ...[
                  Text(
                    readingText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: GakujiColors.mediumGray,
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    kanjiText,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: GakujiColors.darkGray,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ReadingCardBackContent(
              glosses: _reviewGlossesFor(term),
              note: _reviewNoteFor(term),
              examples: _reviewExamplesFor(term),
              photoPath: _reviewPhotoPathFor(term),
              readingText: readingText,
              showReadingOnBack:
                  !showFurigana && readingText.isNotEmpty,
            ),
          ),
        ],
      ),
    );
  }

  Widget _termCardContent(Term term) {
    final kanjiText =
        term.kanji.trim().isNotEmpty ? term.kanji.trim() : term.reading.trim();
    final readingText = term.reading.trim();
    final showReadingAbove = showFurigana && readingText.isNotEmpty;

    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: FittedBox(
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
                    color: GakujiColors.darkGray,
                  ),
                ),
              ),
            ),
            if (showReadingAbove)
              Align(
                alignment: Alignment.center,
                child: Transform.translate(
                  offset: const Offset(0, -52),
                  child: Text(
                    readingText,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 20,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: GakujiColors.mediumGray,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _termFontSizeFor(String text) {
    if (text.length >= 7) return 40;
    if (text.length >= 5) return 46;
    if (text.length >= 3) return 52;

    return 56;
  }

  Widget _showAnswerButton() {
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: Material(
        color: GakujiColors.deckBlue,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: showAnswer,
          splashColor: Colors.white.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          child: Center(
            child: Text(
              'Show Answer',
              textScaler: TextScaler.noScaling,
              style: GakujiText.medium.copyWith(
                color: GakujiColors.warmCard,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ratingButtons() {
    final card = currentReviewCard;
    final intervals = card == null
        ? const <ReviewRating, Duration>{}
        : ReviewScheduler.previewIntervals(card: card);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _ratingButton(
                label: 'Again',
                intervalLabel: ReviewScheduler.formatInterval(
                  intervals[ReviewRating.again],
                ),
                onTap: () => rateCard(ReviewRating.again),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ratingButton(
                label: 'Hard',
                intervalLabel: ReviewScheduler.formatInterval(
                  intervals[ReviewRating.hard],
                ),
                onTap: () => rateCard(ReviewRating.hard),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ratingButton(
                label: 'Good',
                intervalLabel: ReviewScheduler.formatInterval(
                  intervals[ReviewRating.good],
                ),
                onTap: () => rateCard(ReviewRating.good),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ratingButton(
                label: 'Easy',
                intervalLabel: ReviewScheduler.formatInterval(
                  intervals[ReviewRating.easy],
                ),
                onTap: () => rateCard(ReviewRating.easy),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _ratingButton({
    required String label,
    required String intervalLabel,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          intervalLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textScaler: TextScaler.noScaling,
          style: GakujiText.xSmall.copyWith(
            fontSize: 11,
            height: 1,
            color: GakujiColors.mediumGray.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 38,
          child: Material(
            color: GakujiColors.mediumGray,
            borderRadius: BorderRadius.circular(6),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isRating ? null : onTap,
              splashColor: Colors.white.withValues(alpha: 0.10),
              highlightColor: Colors.white.withValues(alpha: 0.05),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _completeScreen() {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _reviewTopBar(
                  leftIcon: Icons.close_rounded,
                  onLeftTap: handleExit,
                  rightWidget: _completionControlButton(),
                ),
                _progressBar(1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                    child: Column(
                      children: [
                        const SizedBox(height: 72),
                         Text(
                          'Review Complete!',
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.xLarge,
                        ),
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 28,
                          ),
                          decoration: BoxDecoration(
                            color: GakujiColors.whiteCard,
                            borderRadius: BorderRadius.circular(
                              GakujiRadius.large,
                            ),
                            border: Border.all(
                              color: GakujiColors.softBorder,
                              width: 1.5,
                            ),
                            boxShadow: [GakujiShadows.card],
                          ),
                          child: Column(
                            children: [
                              Text(
                                '$reviewedCount cards reviewed',
                                textScaler: TextScaler.noScaling,
                                style: GakujiText.medium,
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 14,
                                runSpacing: 10,
                                children: [
                                  _completeStat(
                                    label: 'Again',
                                    count: againCount,
                                  ),
                                  _completeStat(
                                    label: 'Hard',
                                    count: hardCount,
                                  ),
                                  _completeStat(
                                    label: 'Good',
                                    count: goodCount,
                                  ),
                                  _completeStat(
                                    label: 'Easy',
                                    count: easyCount,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        _doneButton(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _completeStat({
    required String label,
    required int count,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        border: Border.all(
          color: GakujiColors.softBorder,
          width: 1.2,
        ),
      ),
      child: Text(
        '$label: $count',
        textScaler: TextScaler.noScaling,
        style: GakujiText.xSmall,
      ),
    );
  }

  Widget _doneButton() {
    return Container(
      width: double.infinity,
      height: 62,
      margin: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: GakujiColors.deckBlue,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: handleExit,
          splashColor: Colors.white.withValues(alpha: 0.10),
          highlightColor: Colors.white.withValues(alpha: 0.05),
          child: Center(
            child: Text(
              'Done',
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

}

class _ReviewQueueEntry {
  final ReviewCard card;
  final ReviewCardState originalState;

  const _ReviewQueueEntry({
    required this.card,
    required this.originalState,
  });
}