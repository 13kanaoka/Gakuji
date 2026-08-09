import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/deck_data.dart';
import '../data/pinned_deck_data.dart';
import '../data/review_card_data.dart';
import '../models/deck.dart';
import '../models/review_card.dart';
import '../models/term.dart';
import '../services/deck_storage.dart';
import '../services/gakuji_user_data_store.dart';
import '../services/word_fusion_round_generator.dart';
import '../widgets/gakuji_faded_scroll.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import '../widgets/review_schedule_card.dart';
import 'deck_edit_page.dart';
import 'deck_term_list_page.dart';
import 'review_study_page.dart';
import 'review_calendar_page.dart';
import 'study_page.dart';
import 'writing_study_page.dart';
import 'hybrid_study_page.dart';
import 'kanji_fusion_game_page.dart';
import 'word_fusion_game_page.dart';
import 'imposter_detective_page.dart';

class DeckPage extends StatefulWidget {
  final Deck deck;

  const DeckPage({super.key, required this.deck});

  @override
  State<DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<DeckPage> {
  bool isShuffled = false;
  bool showFurigana = true;
  bool termFirst = true;
  bool dataLoaded = false;

  bool reviewEnabled = false;
  bool reviewAvailable = false;
  StudyMode activeStudyMode = StudyMode.study;
  DateTime? reviewEnabledAt;
  DateTime? reviewSessionStartedAt;

  int lastIndex = 0;

  bool get isReadingDeck => widget.deck.type == DeckType.reading;
  bool get isWritingDeck => widget.deck.type == DeckType.writing;
  bool get isHybridDeck => widget.deck.type == DeckType.hybrid;

  bool get deckIsPinned => isDeckPinned(widget.deck);
  bool get isReviewMode => activeStudyMode == StudyMode.review;

  Color get deckPrimaryColor {
    switch (widget.deck.type) {
      case DeckType.reading:
        return GakujiColors.reading;
      case DeckType.writing:
        return GakujiColors.writing;
      case DeckType.hybrid:
        return GakujiColors.hybrid;
    }
  }

  double get headerPatternSize {
    if (isReadingDeck) return 520;
    if (isWritingDeck) return 520;
    return 620;
  }

  double get headerPatternTopOffset {
    if (isReadingDeck) return -300;
    if (isWritingDeck) return -304;
    return -388;
  }

  double get headerPatternLeftOffset {
    if (isReadingDeck) return -42;
    if (isWritingDeck) return -46;
    return -84;
  }

  double get headerPatternRotation {
    if (isReadingDeck) return 0;
    if (isWritingDeck) return 0;
    return 0;
  }

  double get headerPatternOpacity {
    if (isReadingDeck) return 0.18;
    if (isWritingDeck) return 0.17;
    return 0.16;
  }

  bool get reviewSessionStartedToday {
    if (reviewSessionStartedAt == null) {
      return false;
    }

    return _isSameDate(reviewSessionStartedAt!, DateTime.now());
  }

  List<ReviewCard> get deckReviewCards {
    return getReviewCardsForDeck(widget.deck.id);
  }

  Future<List<ReviewCard>> _reviewCardsForCurrentSession({DateTime? now}) {
    return getLimitedReviewCardsForDeck(
      widget.deck.id,
      now: now,
      includeShortIntervalCards: reviewSessionStartedToday,
    );
  }

  String get reviewSessionStartedPreferenceKey {
    return 'review_session_started_${widget.deck.id}';
  }

  String get termsCountLabel {
    final count = widget.deck.terms.length;
    return count == 1 ? '1 Term' : '$count Terms';
  }

  String get studyButtonLabel {
    if (isReviewMode) {
      if (!reviewEnabled) return 'Enable Review';

      return reviewSessionStartedToday ? 'Resume Review' : 'Review';
    }

    return 'Flashcards';
  }

  void scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
  }

  Future<void> refreshDeckAfterChanges() async {
    if (reviewEnabled) {
      await createReviewCardsForDeck(widget.deck);
    }

    final availableCards = reviewEnabled
        ? await _reviewCardsForCurrentSession()
        : const <ReviewCard>[];

    if (!mounted) return;

    setState(() {
      reviewAvailable = availableCards.isNotEmpty;
    });

    scheduleUserDataSave();
  }

  Future<void> refreshReviewAvailability() async {
    if (!reviewEnabled) {
      if (!mounted) return;

      setState(() {
        reviewAvailable = false;
      });
      return;
    }

    final availableCards = await _reviewCardsForCurrentSession();

    if (!mounted) return;

    setState(() {
      reviewAvailable = availableCards.isNotEmpty;
    });
  }

  @override
  void initState() {
    super.initState();
    loadState();
  }

  Future<void> loadState() async {
    await loadReviewCards();

    final savedIndex = await DeckStorage.loadProgress(widget.deck.id);
    final savedShuffle = await DeckStorage.loadShuffle(widget.deck.id);
    final savedReviewEnabled = await DeckStorage.loadReviewEnabled(
      widget.deck.id,
    );
    final savedActiveStudyMode = await DeckStorage.loadActiveStudyMode(
      widget.deck.id,
    );
    final savedReviewEnabledAt = await DeckStorage.loadReviewEnabledAt(
      widget.deck.id,
    );

    final prefs = await SharedPreferences.getInstance();
    final savedReviewSessionStartedAt = prefs.getString(
      reviewSessionStartedPreferenceKey,
    );

    if (!mounted) return;

    setState(() {
      lastIndex = savedIndex;
      isShuffled = savedShuffle;
      reviewEnabled = savedReviewEnabled;
      activeStudyMode = savedActiveStudyMode;
      reviewEnabledAt = savedReviewEnabledAt;
      reviewSessionStartedAt = _parseSavedDate(savedReviewSessionStartedAt);
      dataLoaded = true;
    });

    await refreshReviewAvailability();
  }

  List<ReviewCard> _focusCardsFor(_FocusStudyType type) {
    return deckReviewCards.where((card) {
      switch (type) {
        case _FocusStudyType.newCards:
          return card.state == ReviewCardState.newCard;
        case _FocusStudyType.learning:
          return card.state == ReviewCardState.learning ||
              card.state == ReviewCardState.relearning;
        case _FocusStudyType.review:
          return card.state == ReviewCardState.review;
      }
    }).toList();
  }

  int _focusCount(_FocusStudyType type) {
    return _focusCardsFor(type).length;
  }

  Future<void> openFocusStudy(_FocusStudyType type) async {
    await createReviewCardsForDeck(widget.deck);

    if (!mounted) return;

    final focusCards = _focusCardsFor(type);
    final focusTermIds = focusCards.map((card) => card.termId).toSet();
    final focusTerms = widget.deck.terms.where((term) {
      final termId = term.sourceId ?? term.id;
      return focusTermIds.contains(termId);
    }).toList();

    if (focusTerms.isEmpty) {
      _showFloatingMessage('No ${_focusLabel(type)} cards to study');
      return;
    }

    switch (widget.deck.type) {
      case DeckType.reading:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StudyPage(
              terms: focusTerms,
              deck: widget.deck,
              initialIsShuffled: isShuffled,
              initialShowFurigana: showFurigana,
              initialTermFirst: termFirst,
            ),
          ),
        );
        break;

      case DeckType.writing:
        final writingTerms = isShuffled
            ? (List<Term>.from(focusTerms)..shuffle())
            : focusTerms;

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WritingStudyPage(
              terms: writingTerms,
              deck: widget.deck,
              initialIsShuffled: isShuffled,
            ),
          ),
        );
        break;

      case DeckType.hybrid:
        final cardTypesByTermId = <String, Set<ReviewCardType>>{};

        for (final card in focusCards) {
          cardTypesByTermId
              .putIfAbsent(card.termId, () => <ReviewCardType>{})
              .add(card.cardType);
        }

        final focusHybridModes = <String, HybridCardMode>{};

        for (final term in focusTerms) {
          final termId = term.sourceId ?? term.id;
          final cardTypes =
              cardTypesByTermId[termId] ?? const <ReviewCardType>{};

          final hasReading = cardTypes.contains(ReviewCardType.reading);
          final hasWriting = cardTypes.contains(ReviewCardType.writing);

          if (hasReading && hasWriting) {
            focusHybridModes[term.id] = HybridCardMode.both;
          } else if (hasWriting) {
            focusHybridModes[term.id] = HybridCardMode.writing;
          } else {
            focusHybridModes[term.id] = HybridCardMode.reading;
          }
        }

        final focusDeck = widget.deck.copyWith(
          terms: focusTerms,
          hybridCardModes: focusHybridModes,
        );

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HybridStudyPage(
              deck: focusDeck,
              initialIsShuffled: isShuffled,
              initialShowFurigana: showFurigana,
              initialTermFirst: termFirst,
            ),
          ),
        );
        break;
    }

    if (!mounted) return;

    setState(() {});
    scheduleUserDataSave();
  }

  String _focusLabel(_FocusStudyType type) {
    switch (type) {
      case _FocusStudyType.newCards:
        return 'New';
      case _FocusStudyType.learning:
        return 'Learning';
      case _FocusStudyType.review:
        return 'Review';
    }
  }

  Future<void> saveReviewSessionStartedAt(DateTime startedAt) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      reviewSessionStartedPreferenceKey,
      startedAt.toIso8601String(),
    );
  }

  Future<void> clearReviewSessionStartedAt() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(reviewSessionStartedPreferenceKey);
  }

  Future<void> openTermList() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeckTermListPage(deck: widget.deck),
      ),
    );

    await refreshDeckAfterChanges();
  }

  Future<void> confirmDeleteDeck() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: GakujiColors.warmCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            'Delete Deck?',
            textScaler: TextScaler.noScaling,
            style: GakujiText.large.copyWith(color: GakujiColors.darkGray),
          ),
          content: Text(
            'This will permanently delete this deck.',
            textScaler: TextScaler.noScaling,
            style: GakujiText.small.copyWith(color: GakujiColors.mediumGray),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(
                'Cancel',
                textScaler: TextScaler.noScaling,
                style: GakujiText.small.copyWith(
                  color: GakujiColors.mediumGray,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(
                'Delete',
                textScaler: TextScaler.noScaling,
                style: GakujiText.small.copyWith(color: GakujiColors.pinRed),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    decks.removeWhere((deck) => deck.id == widget.deck.id);
    pinnedDeckIds.remove(widget.deck.id);

    scheduleUserDataSave();

    if (!mounted) return;

    Navigator.pop(context);
  }

  void togglePinnedDeck() {
    if (deckIsPinned) {
      setState(() {
        pinnedDeckIds.remove(widget.deck.id);
      });

      scheduleUserDataSave();
      return;
    }

    if (!canPinMoreDecks()) {
      _showPinLimitMessage();
      return;
    }

    setState(() {
      pinnedDeckIds.add(widget.deck.id);
    });

    scheduleUserDataSave();
  }

  void _showPinLimitMessage() {
    _showFloatingMessage('You can pin up to 3 decks');
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

  Future<void> toggleStudyMode(StudyMode mode) async {
    setState(() {
      activeStudyMode = mode;
    });

    await DeckStorage.saveActiveStudyMode(widget.deck.id, mode);

    if (mode == StudyMode.review && reviewEnabled) {
      await refreshReviewAvailability();
    }

    scheduleUserDataSave();
  }

  Future<void> enableReviewForDeck() async {
    if (reviewEnabled) return;

    await createReviewCardsForDeck(widget.deck);

    final enabledAt = DateTime.now();

    await DeckStorage.saveReviewEnabled(widget.deck.id, true);
    await DeckStorage.saveReviewEnabledAt(widget.deck.id, enabledAt);

    if (!mounted) return;

    setState(() {
      reviewEnabled = true;
      reviewEnabledAt = enabledAt;
    });

    await refreshReviewAvailability();
    scheduleUserDataSave();
  }

  Future<void> openStudy() async {
    if (isReviewMode) {
      if (!reviewEnabled) {
        await enableReviewForDeck();
        return;
      }

      await createReviewCardsForDeck(widget.deck);

      final dueCards = await _reviewCardsForCurrentSession();

      if (dueCards.isEmpty) {
        await clearReviewSessionStartedAt();

        if (!mounted) return;

        setState(() {
          reviewSessionStartedAt = null;
          reviewAvailable = false;
        });

        _showFloatingMessage('No cards due for Review');
        return;
      }

      final startedAt = reviewSessionStartedToday
          ? reviewSessionStartedAt!
          : DateTime.now();

      await saveReviewSessionStartedAt(startedAt);

      if (!mounted) return;

      setState(() {
        reviewSessionStartedAt = startedAt;
      });

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ReviewStudyPage(deck: widget.deck, reviewCards: dueCards),
        ),
      );

      await loadReviewCards();

      final remainingReviewCards = await _reviewCardsForCurrentSession();

      if (remainingReviewCards.isEmpty) {
        await clearReviewSessionStartedAt();
      }

      if (!mounted) return;

      setState(() {
        reviewAvailable = remainingReviewCards.isNotEmpty;

        if (remainingReviewCards.isEmpty) {
          reviewSessionStartedAt = null;
        }
      });

      scheduleUserDataSave();
      return;
    }

    final baseStudyTerms = List<Term>.from(widget.deck.terms);

    if (baseStudyTerms.isEmpty) {
      _showFloatingMessage('No terms to study');
      return;
    }

    switch (widget.deck.type) {
      case DeckType.writing:
        final studyTerms = isShuffled
            ? (List<Term>.from(baseStudyTerms)..shuffle())
            : baseStudyTerms;

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WritingStudyPage(
              terms: studyTerms,
              deck: widget.deck,
              initialIsShuffled: isShuffled,
            ),
          ),
        );
        break;

      case DeckType.hybrid:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HybridStudyPage(
              deck: widget.deck,
              initialIsShuffled: isShuffled,
              initialShowFurigana: showFurigana,
              initialTermFirst: termFirst,
            ),
          ),
        );
        break;

      case DeckType.reading:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StudyPage(
              terms: baseStudyTerms,
              deck: widget.deck,
              initialIsShuffled: isShuffled,
              initialShowFurigana: showFurigana,
              initialTermFirst: termFirst,
            ),
          ),
        );
        break;
    }

    final updatedIndex = await DeckStorage.loadProgress(widget.deck.id);

    if (!mounted) return;

    setState(() {
      lastIndex = updatedIndex;
    });

    scheduleUserDataSave();
  }

  Future<void> openCrosscheckGame() async {
    final gameTerms = List<Term>.from(widget.deck.terms);

    if (gameTerms.isEmpty) {
      _showFloatingMessage('No entries available for Crosscheck');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ImposterDetectivePage(deck: widget.deck, terms: gameTerms),
      ),
    );

    if (!mounted) return;

    setState(() {});
    scheduleUserDataSave();
  }

  Future<void> openKanjiFusionGame() async {
    final gameTerms = List<Term>.from(widget.deck.terms);

    if (gameTerms.isEmpty) {
      _showFloatingMessage('No terms available for Fusion');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KanjiFusionGamePage(
          terms: gameTerms,
          deckName: widget.deck.name,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {});
    scheduleUserDataSave();
  }

  Future<void> openWordFusionGame() async {
    final gameTerms = List<Term>.from(widget.deck.terms);

    final eligibleCount = WordFusionRoundGenerator.eligibleTermCount(gameTerms);

    if (eligibleCount == 0) {
      _showFloatingMessage('Word Fusion needs a word written with 2–6 kanji');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WordFusionGamePage(
          terms: gameTerms,
          deckName: widget.deck.name,
          accentColor: deckPrimaryColor,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {});
    scheduleUserDataSave();
  }

  Future<void> openDeckEdit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DeckEditPage(deck: widget.deck)),
    );

    await refreshDeckAfterChanges();
  }

  DateTime? _parseSavedDate(String? savedDate) {
    if (savedDate == null || savedDate.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(savedDate);
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isSameDate(DateTime first, DateTime second) {
    final firstDate = _dateOnly(first);
    final secondDate = _dateOnly(second);

    return firstDate.year == secondDate.year &&
        firstDate.month == secondDate.month &&
        firstDate.day == secondDate.day;
  }

  @override
  Widget build(BuildContext context) {
    if (!dataLoaded) {
      return Scaffold(
        backgroundColor: GakujiColors.warmBackground,
        body: Center(child: CircularProgressIndicator(color: deckPrimaryColor)),
      );
    }

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: Stack(
        children: [
          _deckHeaderPattern(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: GakujiFadedScroll(
                    topFadeEnd: 0.09,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        GakujiSpacing.pageHorizontal,
                        0,
                        GakujiSpacing.pageHorizontal,
                        GakujiSpacing.pageBottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _deckHeader(),
                          const SizedBox(height: 10),
                          _studySection(),
                          if (isReviewMode && reviewEnabled) ...[
                            const SizedBox(height: GakujiSpacing.sectionGap),
                            _focusSection(),
                          ],
                          if (isReviewMode && reviewEnabled) ...[
                            const SizedBox(height: GakujiSpacing.sectionGap),
                            _reviewScheduleSection(),
                          ],
                          const SizedBox(height: GakujiSpacing.sectionGap),
                          _deckInformationSection(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deckHeaderPattern() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 150,
      child: IgnorePointer(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.black, Colors.transparent],
              stops: [0.0, 0.62, 1.0],
            ).createShader(bounds);
          },
          child: Opacity(
            opacity: headerPatternOpacity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: headerPatternTopOffset,
                  left: headerPatternLeftOffset,
                  child: Transform.rotate(
                    angle: headerPatternRotation,
                    child: SizedBox(
                      width: headerPatternSize,
                      height: headerPatternSize,
                      child: Image.asset(
                        _deckPatternAssetPath(widget.deck.type),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return GakujiTopBar(
      leftIcon: GakujiTopBar.backIcon,
      leftIconSize: GakujiTopBar.backIconSize,
      leftIconColor: GakujiColors.darkGray,
      onLeftTap: () => Navigator.pop(context),
      rightWidget: _topPinButton(),
    );
  }

  Widget _topPinButton() {
    final pinned = deckIsPinned;

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: togglePinnedDeck,
        splashColor: GakujiColors.darkGray.withValues(alpha: 0.08),
        highlightColor: GakujiColors.darkGray.withValues(alpha: 0.04),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Image.asset(
              'assets/images/pin_icon.png',
              width: 30,
              height: 30,
              fit: BoxFit.contain,
              color: pinned ? GakujiColors.darkGray : GakujiColors.softGray,
              colorBlendMode: BlendMode.srcIn,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.push_pin_rounded,
                  size: 30,
                  color: pinned
                      ? GakujiColors.darkGray
                      : GakujiColors.mediumGray,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _deckHeader() {
    return SizedBox(
      height: 225,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 4,
            top: 58,
            child: IgnorePointer(child: _deckWatermark()),
          ),
          Positioned(
            left: 0,
            top: 20,
            right: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.deck.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.xLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                _headerMetaText(_deckTypeLabel(widget.deck.type)),
                const SizedBox(height: 4),
                _headerMetaText('Created by:'),
                const SizedBox(height: 4),
                _headerMetaText(termsCountLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deckWatermark() {
    final assetPath = _deckWatermarkAssetPath(widget.deck.type);

    if (assetPath == null || assetPath.isEmpty) {
      return Opacity(
        opacity: 0.30,
        child: Text(
          _deckWatermarkText(widget.deck.type),
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 130,
            height: 1,
            fontWeight: FontWeight.w800,
            color: deckPrimaryColor,
          ),
        ),
      );
    }

    return Opacity(
      opacity: 0.30,
      child: Image.asset(
        assetPath,
        width: 165,
        height: 165,
        fit: BoxFit.contain,
        color: deckPrimaryColor,
        colorBlendMode: BlendMode.srcIn,
        errorBuilder: (context, error, stackTrace) {
          return Text(
            _deckWatermarkText(widget.deck.type),
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 130,
              height: 1,
              fontWeight: FontWeight.w800,
              color: deckPrimaryColor,
            ),
          );
        },
      ),
    );
  }

  Widget _headerMetaText(String text) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
      style: GakujiText.small,
    );
  }

  Widget _studySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Deck Activity',
          textScaler: TextScaler.noScaling,
          style: GakujiText.large,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _studyModePill(
              label: 'Study',
              selected: activeStudyMode == StudyMode.study,
              onTap: () => toggleStudyMode(StudyMode.study),
            ),
            const SizedBox(width: GakujiSpacing.pillGap),
            _studyModePill(
              label: 'Review',
              selected: activeStudyMode == StudyMode.review,
              onTap: () => toggleStudyMode(StudyMode.review),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _flashcardsButton(),
        if (!isReviewMode) ...[
          const SizedBox(height: GakujiSpacing.buttonGap),
          _crosscheckButton(),
          const SizedBox(height: GakujiSpacing.buttonGap),
          _kanjiFusionButton(),
          const SizedBox(height: GakujiSpacing.buttonGap),
          _wordFusionButton(),
        ],
      ],
    );
  }

  Widget _focusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Focus',
          textScaler: TextScaler.noScaling,
          style: GakujiText.large,
        ),
        const SizedBox(height: 16),
        _focusButton(_FocusStudyType.newCards),
        const SizedBox(height: GakujiSpacing.buttonGap),
        _focusButton(_FocusStudyType.learning),
        const SizedBox(height: GakujiSpacing.buttonGap),
        _focusButton(_FocusStudyType.review),
      ],
    );
  }

  Widget _focusButton(_FocusStudyType type) {
    final count = _focusCount(type);
    final enabled = count > 0;

    final backgroundColor = enabled ? deckPrimaryColor : GakujiColors.warmCard;

    final contentColor = enabled
        ? GakujiColors.warmCard
        : GakujiColors.softGray;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.58,
      child: Container(
        height: 54,
        width: double.infinity,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(GakujiRadius.small),
          border: enabled
              ? null
              : Border.all(color: GakujiColors.softBorder, width: 1.7),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(GakujiRadius.small),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => openFocusStudy(type) : null,
            splashColor: enabled
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.transparent,
            highlightColor: enabled
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(17, 0, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _focusLabel(type),
                      textScaler: TextScaler.noScaling,
                      style: GakujiText.medium.copyWith(color: contentColor),
                    ),
                  ),
                  Text(
                    '$count',
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.small.copyWith(
                      color: contentColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 38,
                    color: contentColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openReviewCalendar() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReviewCalendarPage(
          deck: widget.deck,
          initialMonth: DateTime.now(),
          initialSelectedDate: DateTime.now(),
        ),
      ),
    );
  }

  Widget _reviewScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review Calendar',
          textScaler: TextScaler.noScaling,
          style: GakujiText.large,
        ),
        const SizedBox(height: 18),
        Stack(
          children: [
            ReviewScheduleCard(reviewCards: deckReviewCards),
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: openReviewCalendar,
                  splashColor: deckPrimaryColor.withValues(alpha: 0.08),
                  highlightColor: deckPrimaryColor.withValues(alpha: 0.04),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 30,
                      color: GakujiColors.mediumGray,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _studyModePill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: selected
            ? deckPrimaryColor.withValues(alpha: 0.78)
            : GakujiColors.warmBackground,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        border: Border.all(color: deckPrimaryColor, width: 2.3),
        boxShadow: selected ? [GakujiShadows.soft] : const [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: deckPrimaryColor.withValues(alpha: 0.08),
          highlightColor: deckPrimaryColor.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 19),
            child: Center(
              child: Text(
                label,
                textScaler: TextScaler.noScaling,
                style: GakujiText.pill.copyWith(
                  color: selected ? Colors.white : deckPrimaryColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _flashcardsButton() {
    final enableReviewButton = isReviewMode && !reviewEnabled;
    final reviewUnavailable = isReviewMode && reviewEnabled && !reviewAvailable;

    final backgroundColor = enableReviewButton || reviewUnavailable
        ? GakujiColors.warmCard
        : deckPrimaryColor;

    final contentColor = enableReviewButton
        ? deckPrimaryColor
        : reviewUnavailable
        ? GakujiColors.softGray
        : GakujiColors.warmCard;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: reviewUnavailable ? 0.58 : 1,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: Container(
          key: ValueKey(
            '${activeStudyMode.name}-$reviewEnabled-$reviewAvailable-$studyButtonLabel',
          ),
          height: 54,
          width: double.infinity,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(GakujiRadius.small),
            border: enableReviewButton
                ? Border.all(color: deckPrimaryColor, width: 2)
                : reviewUnavailable
                ? Border.all(color: GakujiColors.softBorder, width: 1.7)
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(GakujiRadius.small),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: reviewUnavailable
                  ? null
                  : () {
                      if (enableReviewButton) {
                        enableReviewForDeck();
                        return;
                      }

                      openStudy();
                    },
              splashColor: deckPrimaryColor.withValues(alpha: 0.08),
              highlightColor: deckPrimaryColor.withValues(alpha: 0.04),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(17, 0, 17, 0),
                child: isReviewMode
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Center(
                            child: Text(
                              studyButtonLabel,
                              textScaler: TextScaler.noScaling,
                              style: GakujiText.medium.copyWith(
                                color: contentColor,
                              ),
                            ),
                          ),
                          if (!enableReviewButton)
                            Positioned(
                              right: 0,
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 38,
                                color: contentColor,
                              ),
                            ),
                        ],
                      )
                    : Row(
                        children: [
                          _flashcardsIcon(),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              studyButtonLabel,
                              textScaler: TextScaler.noScaling,
                              style: GakujiText.medium.copyWith(
                                color: contentColor,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 38,
                            color: contentColor,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _crosscheckButton() {
    return Container(
      height: 54,
      width: double.infinity,
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        border: Border.all(
          color: deckPrimaryColor.withValues(alpha: 0.55),
          width: 1.7,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openCrosscheckGame,
          splashColor: deckPrimaryColor.withValues(alpha: 0.08),
          highlightColor: deckPrimaryColor.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(17, 0, 17, 0),
            child: Row(
              children: [
                _crosscheckIcon(),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Crosscheck',
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.medium.copyWith(color: deckPrimaryColor),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 38,
                  color: deckPrimaryColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kanjiFusionButton() {
    return Container(
      height: 54,
      width: double.infinity,
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        border: Border.all(
          color: deckPrimaryColor.withValues(alpha: 0.55),
          width: 1.7,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openKanjiFusionGame,
          splashColor: deckPrimaryColor.withValues(alpha: 0.08),
          highlightColor: deckPrimaryColor.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(17, 0, 17, 0),
            child: Row(
              children: [
                _kanjiFusionIcon(),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Fusion',
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.medium.copyWith(color: deckPrimaryColor),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 38,
                  color: deckPrimaryColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wordFusionButton() {
    return Container(
      height: 54,
      width: double.infinity,
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        border: Border.all(
          color: deckPrimaryColor.withValues(alpha: 0.55),
          width: 1.7,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openWordFusionGame,
          splashColor: deckPrimaryColor.withValues(alpha: 0.08),
          highlightColor: deckPrimaryColor.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(17, 0, 17, 0),
            child: Row(
              children: [
                _wordFusionIcon(),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Word Fusion',
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.medium.copyWith(color: deckPrimaryColor),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 38,
                  color: deckPrimaryColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wordFusionIcon() {
    Widget miniTile(String text) {
      return Container(
        width: 22,
        height: 25,
        decoration: BoxDecoration(
          color: GakujiColors.warmCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: deckPrimaryColor, width: 1.5),
        ),
        child: Center(
          child: Text(
            text,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: GakujiFonts.japanese,
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w700,
              color: deckPrimaryColor,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(left: 0, top: 7, child: miniTile('学')),
          Positioned(right: 0, bottom: 6, child: miniTile('校')),
        ],
      ),
    );
  }

  Widget _kanjiFusionIcon() {
    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: deckPrimaryColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
          ),
          Icon(Icons.auto_awesome_rounded, size: 25, color: deckPrimaryColor),
        ],
      ),
    );
  }

  Widget _flashcardsIcon() {
    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: 4,
            child: Container(
              width: 20,
              height: 29,
              decoration: BoxDecoration(
                color: const Color(0xFFE6E1D8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: 2,
            top: 7,
            child: Container(
              width: 22,
              height: 29,
              decoration: BoxDecoration(
                color: const Color(0xFFF7F2E8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _crosscheckIcon() {
    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: deckPrimaryColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
          ),
          Icon(Icons.fact_check_rounded, size: 28, color: deckPrimaryColor),
        ],
      ),
    );
  }

  Widget _deckInformationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Deck Information',
          textScaler: TextScaler.noScaling,
          style: GakujiText.large,
        ),
        const SizedBox(height: 18),
        _deckInfoButton(
          icon: Icons.edit_rounded,
          label: 'Edit Deck',
          onTap: openDeckEdit,
        ),
        const SizedBox(height: GakujiSpacing.buttonGap),
        _deckInfoButton(
          icon: Icons.description_outlined,
          label: 'View Term List',
          onTap: openTermList,
        ),
        const SizedBox(height: GakujiSpacing.buttonGap),
        _deckInfoButton(
          icon: Icons.delete_outline_rounded,
          label: 'Delete Deck',
          onTap: confirmDeleteDeck,
          isDestructive: true,
        ),
      ],
    );
  }

  Widget _deckInfoButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final iconColor = isDestructive
        ? GakujiColors.pinRed
        : GakujiColors.mediumGray;

    final textColor = isDestructive
        ? GakujiColors.pinRed
        : GakujiColors.darkGray;

    return Container(
      height: 50,
      width: double.infinity,
      decoration: BoxDecoration(
        color: GakujiColors.whiteCard,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        border: Border.all(
          color: isDestructive
              ? GakujiColors.pinRed.withValues(alpha: 0.45)
              : GakujiColors.softBorder,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: isDestructive
              ? GakujiColors.pinRed.withValues(alpha: 0.08)
              : deckPrimaryColor.withValues(alpha: 0.08),
          highlightColor: isDestructive
              ? GakujiColors.pinRed.withValues(alpha: 0.04)
              : deckPrimaryColor.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(icon, size: 26, color: iconColor),
                const SizedBox(width: 12),
                Text(
                  label,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.medium.copyWith(color: textColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _deckTypeLabel(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'Writing';
      case DeckType.reading:
        return 'Reading';
      case DeckType.hybrid:
        return 'Hybrid';
    }
  }

  String _deckPatternAssetPath(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'assets/images/deck_pattern_writing.png';
      case DeckType.reading:
        return 'assets/images/deck_pattern_reading.png';
      case DeckType.hybrid:
        return 'assets/images/deck_pattern_hybrid.png';
    }
  }

  String? _deckWatermarkAssetPath(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'assets/images/deck_page_watermark_writing.png';
      case DeckType.reading:
        return 'assets/images/deck_page_watermark_reading.png';
      case DeckType.hybrid:
        return 'assets/images/deck_page_watermark_hybrid.png';
    }
  }

  String _deckWatermarkText(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return '書';
      case DeckType.reading:
        return '読';
      case DeckType.hybrid:
        return '合';
    }
  }
}

enum _FocusStudyType { newCards, learning, review }
