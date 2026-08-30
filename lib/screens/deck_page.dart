import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/gakuji_page_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/deck_data.dart';
import '../data/pinned_deck_data.dart';
import '../data/recent_deck_data.dart';
import '../data/review_card_data.dart';
import '../models/deck.dart';
import '../models/review_card.dart';
import '../models/term.dart';
import '../services/deck_storage.dart';
import '../services/gakuji_cloud_sync_service.dart';
import '../services/gakuji_local_preferences.dart';
import '../services/gakuji_session_storage.dart';
import '../services/gakuji_user_data_store.dart';
import '../services/gakuji_user_repository.dart';
import '../services/word_fusion_round_generator.dart';
import '../widgets/gakuji_deck_transition.dart';
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
  static const Duration topBarTitleFadeDuration =
      Duration(milliseconds: 180);
  static const Color deckActivityPrimaryForeground = Color(0xFFF7F3EA);

  static const String _showFuriganaPreferenceKey = 'study_show_furigana';
  static const String _termFirstPreferenceKey = 'study_term_first';
  static const String _writingGridPreferenceKey =
      'study_writing_grid_visible';

  late final ScrollController pageScrollController;

  final GlobalKey deckTitleKey = GlobalKey();
  final GlobalKey scrollViewportKey = GlobalKey();

  bool showTopBarTitle = false;
  bool isShuffled = false;
  bool showFurigana = true;
  bool termFirst = true;
  bool showWritingGrid = true;
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
    return GakujiColors.deckColorFor(widget.deck);
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

    // Seed the page from the Deck object that Library already has in memory so
    // the Hero can expand directly into real deck content. The persisted
    // values are still refreshed asynchronously by loadState() below.
    isShuffled = widget.deck.isShuffled;
    reviewEnabled = widget.deck.reviewEnabled;
    activeStudyMode = widget.deck.activeStudyMode;
    reviewEnabledAt = widget.deck.reviewEnabledAt;
    lastIndex = widget.deck.lastStudyIndex;

    pageScrollController = ScrollController();
    pageScrollController.addListener(_handlePageScroll);
    markDeckOpenedRecently(widget.deck.id);
    loadState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_prefetchResumeSessions());
      }
    });
  }

  Future<void> _prefetchResumeSessions() async {
    try {
      final states = await GakujiSessionStorage.loadMany(
        sessionTypes: const [
          'flashcards',
          'kanji_fusion',
          'word_fusion',
        ],
        deckId: widget.deck.id,
      );

      final roundTypes = <String>[];
      if (states['kanji_fusion'] != null) {
        roundTypes.add('kanji_fusion_rounds');
      }
      if (states['word_fusion'] != null) {
        roundTypes.add('word_fusion_rounds');
      }

      if (roundTypes.isNotEmpty) {
        await GakujiSessionStorage.loadMany(
          sessionTypes: roundTypes,
          deckId: widget.deck.id,
        );
      }
    } catch (_) {
      // Prefetch is only a latency optimization; normal page loading remains
      // the fallback if the database is temporarily unavailable.
    }
  }

  @override
  void dispose() {
    pageScrollController.removeListener(_handlePageScroll);
    pageScrollController.dispose();
    super.dispose();
  }

  void _handlePageScroll() {
    _updateTopBarTitleVisibility();
  }

  void _updateTopBarTitleVisibility() {
    if (!mounted) return;

    final titleContext = deckTitleKey.currentContext;
    final viewportContext = scrollViewportKey.currentContext;

    if (titleContext == null || viewportContext == null) return;

    final titleRenderObject = titleContext.findRenderObject();
    final viewportRenderObject = viewportContext.findRenderObject();

    if (titleRenderObject is! RenderBox ||
        viewportRenderObject is! RenderBox ||
        !titleRenderObject.attached ||
        !viewportRenderObject.attached ||
        !titleRenderObject.hasSize ||
        !viewportRenderObject.hasSize) {
      return;
    }

    final titleBottom =
        titleRenderObject.localToGlobal(Offset.zero).dy +
            titleRenderObject.size.height;
    final viewportTop = viewportRenderObject.localToGlobal(Offset.zero).dy;
    final shouldShowTitle = titleBottom <= viewportTop + 0.5;

    if (showTopBarTitle == shouldShowTitle) return;

    setState(() {
      showTopBarTitle = shouldShowTitle;
    });
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
    final savedShowFurigana =
        await GakujiLocalPreferences.loadBool(_showFuriganaPreferenceKey);
    final savedTermFirst =
        await GakujiLocalPreferences.loadBool(_termFirstPreferenceKey);
    final savedWritingGrid =
        await GakujiLocalPreferences.loadBool(_writingGridPreferenceKey);

    var savedReviewSessionStartedAt = await GakujiUserRepository.loadPreference(
      reviewSessionStartedPreferenceKey,
    );

    // One-time migration from the legacy SharedPreferences storage path.
    if (savedReviewSessionStartedAt == null) {
      final prefs = await SharedPreferences.getInstance();
      final legacyValue = prefs.getString(reviewSessionStartedPreferenceKey);

      if (legacyValue != null && legacyValue.isNotEmpty) {
        savedReviewSessionStartedAt = legacyValue;
        await GakujiUserRepository.savePreference(
          key: reviewSessionStartedPreferenceKey,
          value: legacyValue,
        );
        await prefs.remove(reviewSessionStartedPreferenceKey);
        GakujiCloudSyncService.schedulePush();
      }
    }

    if (!mounted) return;

    setState(() {
      lastIndex = savedIndex;
      isShuffled = savedShuffle;
      reviewEnabled = savedReviewEnabled;
      activeStudyMode = savedActiveStudyMode;
      reviewEnabledAt = savedReviewEnabledAt;
      reviewSessionStartedAt = _parseSavedDate(savedReviewSessionStartedAt);
      showFurigana = savedShowFurigana ?? true;
      termFirst = savedTermFirst ?? true;
      showWritingGrid = savedWritingGrid ?? true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateTopBarTitleVisibility();
    });

    await refreshReviewAvailability();
  }

  Future<void> _reloadStudyPreferences() async {
    final savedShuffle = await DeckStorage.loadShuffle(widget.deck.id);
    final savedShowFurigana =
        await GakujiLocalPreferences.loadBool(_showFuriganaPreferenceKey);
    final savedTermFirst =
        await GakujiLocalPreferences.loadBool(_termFirstPreferenceKey);
    final savedWritingGrid =
        await GakujiLocalPreferences.loadBool(_writingGridPreferenceKey);

    if (!mounted) return;

    setState(() {
      isShuffled = savedShuffle;
      if (savedShowFurigana != null) {
        showFurigana = savedShowFurigana;
      }
      if (savedTermFirst != null) {
        termFirst = savedTermFirst;
      }
      if (savedWritingGrid != null) {
        showWritingGrid = savedWritingGrid;
      }
    });
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
          GakujiPageRoute(
            enableSwipeBack: false,
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
          GakujiPageRoute(
            enableSwipeBack: false,
            builder: (context) => WritingStudyPage(
              terms: writingTerms,
              deck: widget.deck,
              initialIsShuffled: isShuffled,
              initialShowGrid: showWritingGrid,
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
          GakujiPageRoute(
            enableSwipeBack: false,
            builder: (context) => HybridStudyPage(
              deck: focusDeck,
              initialIsShuffled: isShuffled,
              initialShowFurigana: showFurigana,
              initialTermFirst: termFirst,
              initialShowGrid: showWritingGrid,
            ),
          ),
        );
        break;
    }

    await _reloadStudyPreferences();

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
    await GakujiUserRepository.savePreference(
      key: reviewSessionStartedPreferenceKey,
      value: startedAt.toIso8601String(),
    );
    GakujiCloudSyncService.schedulePush();
  }

  Future<void> clearReviewSessionStartedAt() async {
    await GakujiUserRepository.deletePreference(
      reviewSessionStartedPreferenceKey,
    );
    GakujiCloudSyncService.schedulePush();
  }

  Future<void> openTermList() async {
    await Navigator.push(
      context,
      GakujiPageRoute(
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
    await removeDeckFromRecentOrder(widget.deck.id);

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
        GakujiPageRoute(
          enableSwipeBack: false,
          builder: (context) => ReviewStudyPage(
            deck: widget.deck,
            reviewCards: dueCards,
            initialShowFurigana: showFurigana,
            initialShowWritingGrid: showWritingGrid,
          ),
        ),
      );

      await _reloadStudyPreferences();
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
          GakujiPageRoute(
            enableSwipeBack: false,
            builder: (context) => WritingStudyPage(
              terms: studyTerms,
              deck: widget.deck,
              initialIsShuffled: isShuffled,
              initialShowGrid: showWritingGrid,
            ),
          ),
        );
        break;

      case DeckType.hybrid:
        await Navigator.push(
          context,
          GakujiPageRoute(
            enableSwipeBack: false,
            builder: (context) => HybridStudyPage(
              deck: widget.deck,
              initialIsShuffled: isShuffled,
              initialShowFurigana: showFurigana,
              initialTermFirst: termFirst,
              initialShowGrid: showWritingGrid,
            ),
          ),
        );
        break;

      case DeckType.reading:
        await Navigator.push(
          context,
          GakujiPageRoute(
            enableSwipeBack: false,
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

    await _reloadStudyPreferences();

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
      GakujiPageRoute(
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
      GakujiPageRoute(
        builder: (_) => KanjiFusionGamePage(
          terms: gameTerms,
          deckId: widget.deck.id,
          deckName: widget.deck.name,
          accentColor: deckPrimaryColor,
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
      GakujiPageRoute(
        builder: (_) => WordFusionGamePage(
          terms: gameTerms,
          deckId: widget.deck.id,
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
      GakujiPageRoute(builder: (context) => DeckEditPage(deck: widget.deck)),
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
    final Widget body = Stack(
            children: [
              _deckHeaderPattern(),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _topBar(),
                    Expanded(
                      child: Container(
                        key: scrollViewportKey,
                        child: GakujiFadedScroll(
                          topFadeEnd: 0.09,
                          child: SingleChildScrollView(
                            controller: pageScrollController,
                            padding: const EdgeInsets.fromLTRB(
                              18,
                              0,
                              18,
                              GakujiSpacing.pageBottom,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _deckHeader(),
                                const SizedBox(height: 10),
                                _studySection(),
                                if (!isReviewMode) ...[
                                  const SizedBox(
                                    height: GakujiSpacing.sectionGap,
                                  ),
                                  _gamesSection(),
                                ],
                                if (isReviewMode && reviewEnabled) ...[
                                  const SizedBox(
                                    height: GakujiSpacing.sectionGap,
                                  ),
                                  _focusSection(),
                                ],
                                if (isReviewMode && reviewEnabled) ...[
                                  const SizedBox(
                                    height: GakujiSpacing.sectionGap,
                                  ),
                                  _reviewScheduleSection(),
                                ],
                                const SizedBox(
                                  height: GakujiSpacing.sectionGap,
                                ),
                                _deckInformationSection(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

    return Hero(
      tag: gakujiDeckHeroTag(widget.deck.id),
      createRectTween: gakujiDeckRectTween,
      flightShuttleBuilder: gakujiDeckFlightShuttleBuilder,
      child: Material(
        type: MaterialType.transparency,
        child: Scaffold(
          backgroundColor: GakujiColors.warmBackground,
          body: body,
        ),
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
                        color: deckPrimaryColor,
                        colorBlendMode: BlendMode.srcIn,
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
      leftIcon: Icons.close_rounded,
      leftIconSize: GakujiTopBar.iconSize,
      leftIconColor: GakujiColors.darkGray,
      onLeftTap: () => Navigator.pop(context),
      titleWidget: AnimatedOpacity(
        opacity: showTopBarTitle ? 1 : 0,
        duration: topBarTitleFadeDuration,
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.deck.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                color: GakujiColors.darkGray,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _deckTypeLabel(widget.deck.type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.mediumGray,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
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
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              color: pinned ? GakujiColors.darkGray : GakujiColors.softGray,
              colorBlendMode: BlendMode.srcIn,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.push_pin_rounded,
                  size: 24,
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
            top: 64,
            child: IgnorePointer(child: _deckWatermark()),
          ),
          Positioned(
            left: 0,
            top: 20,
            right: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  key: deckTitleKey,
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
                            style: GakujiText.pageTitle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    _headerMetaText(_deckTypeLabel(widget.deck.type)),
                  ],
                ),
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
      style: GakujiText.deckMeta.copyWith(
        color: GakujiColors.mediumGray,
      ),
    );
  }

  Widget _studySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Deck Activity',
          textScaler: TextScaler.noScaling,
          style: GakujiText.sectionTitle,
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
      ],
    );
  }

  Widget _gamesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Games',
          textScaler: TextScaler.noScaling,
          style: GakujiText.sectionTitle,
        ),
        const SizedBox(height: 16),
        _crosscheckButton(),
        const SizedBox(height: GakujiSpacing.buttonGap),
        _kanjiFusionButton(),
        const SizedBox(height: GakujiSpacing.buttonGap),
        _wordFusionButton(),
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
          style: GakujiText.sectionTitle,
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

    final contentColor = enabled ? deckPrimaryColor : GakujiColors.softGray;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.58,
      child: Container(
        height: 54,
        width: double.infinity,
        decoration: BoxDecoration(
          color: GakujiColors.warmCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled
                ? deckPrimaryColor.withValues(alpha: 0.55)
                : GakujiColors.softBorder,
            width: 1.5,
          ),
          boxShadow: [GakujiShadows.soft],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => openFocusStudy(type) : null,
            splashColor: enabled
                ? deckPrimaryColor.withValues(alpha: 0.08)
                : Colors.transparent,
            highlightColor: enabled
                ? deckPrimaryColor.withValues(alpha: 0.04)
                : Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(17, 0, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _focusLabel(type),
                      textScaler: TextScaler.noScaling,
                      style: GakujiText.actionLabel.copyWith(color: contentColor),
                    ),
                  ),
                  Text(
                    '$count',
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.deckMeta.copyWith(
                      color: contentColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 28,
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
      GakujiPageRoute(
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
          style: GakujiText.sectionTitle,
        ),
        const SizedBox(height: 18),
        Stack(
          children: [
            ReviewScheduleCard(
              deckId: widget.deck.id,
              reviewCards: deckReviewCards,
            ),
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
        boxShadow: [GakujiShadows.soft],
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
        : deckActivityPrimaryForeground;

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
            borderRadius: BorderRadius.circular(16),
            border: enableReviewButton
                ? Border.all(color: deckPrimaryColor, width: 1.5)
                : reviewUnavailable
                ? Border.all(color: GakujiColors.softBorder, width: 1.5)
                : null,
            boxShadow: [GakujiShadows.soft],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
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
                    ? Row(
                        children: [
                          Expanded(
                            child: Text(
                              studyButtonLabel,
                              textScaler: TextScaler.noScaling,
                              style: GakujiText.actionLabel.copyWith(
                                color: contentColor,
                              ),
                            ),
                          ),
                          if (!enableReviewButton)
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 38,
                              color: contentColor,
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
                              style: GakujiText.actionLabel.copyWith(
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: deckPrimaryColor.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
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
                    style: GakujiText.actionLabel.copyWith(color: deckPrimaryColor),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: deckPrimaryColor.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
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
                    style: GakujiText.actionLabel.copyWith(color: deckPrimaryColor),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: deckPrimaryColor.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
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
                    style: GakujiText.actionLabel.copyWith(color: deckPrimaryColor),
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
    return _deckActivityAssetIcon('assets/images/word_fusion.png');
  }

  Widget _kanjiFusionIcon() {
    return _deckActivityAssetIcon('assets/images/fusion.png');
  }

  Widget _flashcardsIcon() {
    return _deckActivityAssetIcon(
      'assets/images/flashcards.png',
      color: deckActivityPrimaryForeground,
    );
  }

  Widget _crosscheckIcon() {
    return _deckActivityAssetIcon('assets/images/crosscheck.png');
  }

  Widget _deckActivityAssetIcon(
    String assetPath, {
    Color? color,
  }) {
    return SizedBox(
      width: 38,
      height: 38,
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        color: color ?? deckPrimaryColor,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.shrink();
        },
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
          style: GakujiText.sectionTitle,
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
      height: 54,
      width: double.infinity,
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDestructive
              ? GakujiColors.pinRed.withValues(alpha: 0.45)
              : GakujiColors.warmDivider,
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
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
            padding: const EdgeInsets.symmetric(horizontal: 17),
            child: Row(
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: Icon(icon, size: 26, color: iconColor),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.actionLabel.copyWith(color: textColor),
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
