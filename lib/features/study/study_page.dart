import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';

import 'package:gakuji/data/decks/reading_card_edit_data.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/data/decks/deck_storage.dart';
import 'package:gakuji/data/sync/gakuji_local_preferences.dart';
import 'package:gakuji/data/sync/gakuji_user_data_store.dart';
import 'package:gakuji/data/decks/reading_card_edit_storage.dart';
import 'package:gakuji/data/decks/term_favorite_service.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/features/decks/deck_edit_page.dart';
import 'package:gakuji/core/widgets/gakuji_options_sheet.dart';
import 'package:gakuji/features/study/widgets/reading_card_back.dart';
import 'package:gakuji/data/sync/gakuji_session_storage.dart';

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
  static const String _showFuriganaPreferenceKey = 'study_show_furigana';
  static const String _showExampleFuriganaPreferenceKey =
      'study_show_example_furigana';
  static const String _termFirstPreferenceKey = 'study_term_first';
  static const String _blueCardTextPreferenceKey = 'blue_card_text_enabled';
  static const String _sessionType = 'flashcards';
  static String _starredOnlyPreferenceKey(String deckId) {
    return 'study_starred_only_$deckId';
  }

  static const Duration _cardReturnDuration = Duration(milliseconds: 320);
  static const Duration _cardExitDuration = Duration(milliseconds: 140);
  static const Duration _cardContentFadeDuration = Duration(milliseconds: 120);
  static const Duration _previousCardReturnDuration =
      Duration(milliseconds: 180);

  static const Color incorrectRed = Color(0xFFF6A3A3);
  static const Color incorrectRedOutline = Color(0xFFE06F6F);

  static const Color correctGreen = Color(0xFFC5E7A5);
  static const Color correctGreenOutline = Color(0xFF8DBB66);

  late List<Term> allTerms;
  late List<Term> activeTerms;

  final List<Term> answeredTerms = [];
  final List<_StudyHistoryEntry> history = [];
  final List<Term> incorrectReviewTerms = [];

  final Map<String, ReadingCardEditData> readingCardEdits = {};
  final Set<String> savedReadingCardEditTermIds = {};

  int correctCount = 0;
  int incorrectCount = 0;

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  late AnimationController _swipeController;
  late Animation<Offset> _swipeAnimation;

  late AnimationController _cardContentController;
  late Animation<double> _cardContentOpacity;

  late AnimationController _previousCardReturnController;
  late Animation<double> _previousCardReturnAnimation;

  Offset dragOffset = Offset.zero;
  bool isDragging = false;
  bool isSwipingAway = false;

  bool isReturningPreviousCard = false;
  double previousCardReturnDirection = 1;
  Term? outgoingCardTerm;
  int _previousCardReturnRunId = 0;

  bool hasCompletedDeck = false;
  bool isReviewingIncorrect = false;

  bool showMenu = false;
  bool isShuffled = false;
  bool showFurigana = true;
  bool showExampleFurigana = true;
  bool termFirst = true;
  bool blueCardTextEnabled = false;
  bool showStarredOnly = false;
  bool isSessionReady = false;

  int get totalSessionCount => answeredTerms.length + activeTerms.length;

  bool get isComplete => activeTerms.isEmpty && allTerms.isNotEmpty;

  double get deckProgress {
    final total = totalSessionCount;

    if (total <= 0) return 0;

    return (answeredTerms.length / total).clamp(0.0, 1.0).toDouble();
  }

  List<Term> get filteredStudyTerms {
    if (showStarredOnly) {
      return widget.terms.where((term) => term.marked).toList();
    }

    return List<Term>.from(widget.terms);
  }

  String? get swipeFeedbackText {
    if (dragOffset.dx > 32) return 'Know';
    if (dragOffset.dx < -32) return 'Still learning';

    return null;
  }

  Color? get swipeFeedbackColor {
    if (dragOffset.dx > 32) return correctGreenOutline;
    if (dragOffset.dx < -32) return incorrectRedOutline;

    return null;
  }

  double get swipeFeedbackOpacity {
    final opacity = ((dragOffset.dx.abs() - 30) / 90).clamp(0.0, 1.0);

    return opacity.toDouble();
  }

  @override
  void initState() {
    super.initState();

    blueCardTextEnabled = GakujiLocalPreferences.peekBool(
          _blueCardTextPreferenceKey,
        ) ??
        false;

    isShuffled = widget.initialIsShuffled;
    showFurigana = widget.initialShowFurigana;
    termFirst = widget.initialTermFirst;

    allTerms = List<Term>.from(filteredStudyTerms);
    activeTerms = List<Term>.from(allTerms);

    if (isShuffled) {
      activeTerms.shuffle();
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

    _previousCardReturnController = AnimationController(
      vsync: this,
      duration: _previousCardReturnDuration,
    );

    _previousCardReturnAnimation = CurvedAnimation(
      parent: _previousCardReturnController,
      curve: Curves.easeOutCubic,
    );

    _previousCardReturnController.addListener(
      _handlePreviousCardReturnAnimationTick,
    );

    _restoreCachedSessionSnapshot();
    _loadProgress();
    _loadReadingCardEdits();
  }

  @override
  void dispose() {
    _previousCardReturnController.removeListener(
      _handlePreviousCardReturnAnimationTick,
    );
    _swipeController.removeListener(_handleSwipeAnimationTick);
    _previousCardReturnController.dispose();
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

  void _handlePreviousCardReturnAnimationTick() {
    if (!mounted) return;

    setState(() {});
  }

  Future<void> _loadProgress() async {
    final savedSessionFuture = GakujiSessionStorage.load(
      sessionType: _sessionType,
      deckId: widget.deck.id,
    );
    final savedProgressFuture = DeckStorage.loadProgress(widget.deck.id);
    final savedShowFuriganaFuture =
        GakujiLocalPreferences.loadBool(_showFuriganaPreferenceKey);
    final savedShowExampleFuriganaFuture = GakujiLocalPreferences.loadBool(
      _showExampleFuriganaPreferenceKey,
    );
    final savedTermFirstFuture =
        GakujiLocalPreferences.loadBool(_termFirstPreferenceKey);
    final savedBlueCardTextFuture =
        GakujiLocalPreferences.loadBool(_blueCardTextPreferenceKey);
    final savedShowStarredOnlyFuture = GakujiLocalPreferences.loadBool(
      _starredOnlyPreferenceKey(widget.deck.id),
    );

    // Resume the actual card order/history as soon as the session record is
    // available. Display preferences continue loading in parallel and are
    // applied immediately afterward instead of blocking the resume itself.
    final savedSession = await savedSessionFuture;

    if (!mounted || (isReviewingIncorrect && !isSessionReady)) return;

    if (savedSession != null &&
        _restoreSessionSnapshot(
          savedSession,
          savedShowFurigana: null,
          savedShowExampleFurigana: null,
          savedTermFirst: null,
          savedBlueCardText: null,
        )) {
      final savedShowFurigana = await savedShowFuriganaFuture;
      final savedShowExampleFurigana = await savedShowExampleFuriganaFuture;
      final savedTermFirst = await savedTermFirstFuture;
      final savedBlueCardText = await savedBlueCardTextFuture;

      if (!mounted) return;

      setState(() {
        if (savedShowFurigana != null) {
          showFurigana = savedShowFurigana;
        }
        if (savedShowExampleFurigana != null) {
          showExampleFurigana = savedShowExampleFurigana;
        }
        if (savedTermFirst != null) {
          termFirst = savedTermFirst;
        }
        blueCardTextEnabled = savedBlueCardText ?? false;
      });
      return;
    }

    if (savedSession != null) {
      unawaited(_clearSessionSnapshot());
    }

    final saved = await savedProgressFuture;
    final savedShowFurigana = await savedShowFuriganaFuture;
    final savedShowExampleFurigana = await savedShowExampleFuriganaFuture;
    final savedTermFirst = await savedTermFirstFuture;
    final savedBlueCardText = await savedBlueCardTextFuture;
    final savedShowStarredOnly = await savedShowStarredOnlyFuture;

    if (!mounted || (isReviewingIncorrect && !isSessionReady)) return;

    final nextShowStarredOnly = savedShowStarredOnly ?? showStarredOnly;
    final nextAllTerms = nextShowStarredOnly
        ? widget.terms.where((term) => term.marked).toList()
        : List<Term>.from(widget.terms);

    if (nextAllTerms.isEmpty) {
      await GakujiLocalPreferences.saveBool(
        _starredOnlyPreferenceKey(widget.deck.id),
        false,
      );
    }

    final effectiveAllTerms =
        nextAllTerms.isEmpty ? List<Term>.from(widget.terms) : nextAllTerms;
    final savedCount = saved.clamp(0, effectiveAllTerms.length).toInt();

    setState(() {
      showStarredOnly = nextAllTerms.isNotEmpty && nextShowStarredOnly;
      allTerms = List<Term>.from(effectiveAllTerms);
      answeredTerms
        ..clear()
        ..addAll(allTerms.take(savedCount));
      history.clear();
      incorrectReviewTerms.clear();
      correctCount = 0;
      incorrectCount = 0;

      activeTerms = List<Term>.from(allTerms.skip(savedCount));

      if (isShuffled) {
        activeTerms.shuffle();
      }

      if (savedShowFurigana != null) {
        showFurigana = savedShowFurigana;
      }
      if (savedShowExampleFurigana != null) {
        showExampleFurigana = savedShowExampleFurigana;
      }
      if (savedTermFirst != null) {
        termFirst = savedTermFirst;
      }
      blueCardTextEnabled = savedBlueCardText ?? false;
      hasCompletedDeck = activeTerms.isEmpty && allTerms.isNotEmpty;
      _cardContentController.value = 1;
      isSessionReady = true;
    });

    unawaited(_saveSessionSnapshot());
  }

  void _restoreCachedSessionSnapshot() {
    if (!GakujiSessionStorage.hasCached(
      sessionType: _sessionType,
      deckId: widget.deck.id,
    )) {
      return;
    }

    final cached = GakujiSessionStorage.peek(
      sessionType: _sessionType,
      deckId: widget.deck.id,
    );
    if (cached == null) return;

    _restoreSessionSnapshot(
      cached,
      savedShowFurigana: null,
      savedShowExampleFurigana: null,
      savedTermFirst: null,
      savedBlueCardText: null,
    );
  }

  List<String> get _deckSessionTermIds {
    return widget.terms.map((term) => term.id).toList(growable: false);
  }

  String get _deckSessionSignature {
    var hash = 0x811C9DC5;
    for (final term in widget.terms) {
      for (final codeUnit in term.id.codeUnits) {
        hash ^= codeUnit;
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
      hash ^= 0xFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return '${widget.terms.length}:${hash.toRadixString(16)}';
  }

  bool _restoreSessionSnapshot(
    Map<String, dynamic> snapshot, {
    required bool? savedShowFurigana,
    required bool? savedShowExampleFurigana,
    required bool? savedTermFirst,
    required bool? savedBlueCardText,
  }) {
    final version = _asInt(snapshot['version']);
    if (version == 2) {
      return _restoreCompactSessionSnapshot(
        snapshot,
        savedShowFurigana: savedShowFurigana,
        savedShowExampleFurigana: savedShowExampleFurigana,
        savedTermFirst: savedTermFirst,
        savedBlueCardText: savedBlueCardText,
      );
    }
    if (version == 1) {
      final restored = _restoreLegacySessionSnapshot(
        snapshot,
        savedShowFurigana: savedShowFurigana,
        savedShowExampleFurigana: savedShowExampleFurigana,
        savedTermFirst: savedTermFirst,
        savedBlueCardText: savedBlueCardText,
      );
      if (restored) {
        unawaited(_saveSessionSnapshot());
      }
      return restored;
    }
    return false;
  }

  bool _restoreCompactSessionSnapshot(
    Map<String, dynamic> snapshot, {
    required bool? savedShowFurigana,
    required bool? savedShowExampleFurigana,
    required bool? savedTermFirst,
    required bool? savedBlueCardText,
  }) {
    if (snapshot['deckSignature']?.toString() != _deckSessionSignature) {
      return false;
    }

    final termsById = <String, Term>{
      for (final term in widget.terms) term.id: term,
    };
    final savedAllTermIds = _stringList(snapshot['allTermIds']);
    final savedSessionOrderIds = _stringList(snapshot['sessionOrderTermIds']);
    final savedIncorrectTermIds = _stringList(snapshot['incorrectTermIds']);
    final answeredCount = _asInt(snapshot['answeredCount']);
    final historyStartIndex = _asInt(snapshot['historyStartIndex']) ?? 0;
    final rawHistoryCorrect = snapshot['historyCorrect'];

    if (savedAllTermIds.isEmpty ||
        savedSessionOrderIds.isEmpty ||
        answeredCount == null ||
        answeredCount < 0 ||
        answeredCount > savedSessionOrderIds.length ||
        rawHistoryCorrect is! List) {
      return false;
    }

    final historyCorrect = <bool>[];
    for (final value in rawHistoryCorrect) {
      if (value is! bool) return false;
      historyCorrect.add(value);
    }

    if (historyStartIndex < 0 ||
        historyStartIndex > answeredCount ||
        historyStartIndex + historyCorrect.length > answeredCount) {
      return false;
    }

    final restoredAllTerms = _termsForIds(savedAllTermIds, termsById);
    final restoredSessionOrder = _termsForIds(savedSessionOrderIds, termsById);
    final restoredIncorrectTerms =
        _termsForIds(savedIncorrectTermIds, termsById);

    if (restoredAllTerms.length != savedAllTermIds.length ||
        restoredSessionOrder.length != savedSessionOrderIds.length ||
        restoredIncorrectTerms.length != savedIncorrectTermIds.length) {
      return false;
    }

    final restoredAnsweredTerms =
        restoredSessionOrder.take(answeredCount).toList(growable: false);
    final restoredActiveTerms =
        restoredSessionOrder.skip(answeredCount).toList();
    final restoredHistory = <_StudyHistoryEntry>[];

    for (var index = 0; index < historyCorrect.length; index++) {
      restoredHistory.add(
        _StudyHistoryEntry(
          term: restoredAnsweredTerms[historyStartIndex + index],
          correct: historyCorrect[index],
        ),
      );
    }

    return _applyRestoredSession(
      restoredAllTerms: restoredAllTerms,
      restoredAnsweredTerms: restoredAnsweredTerms,
      restoredActiveTerms: restoredActiveTerms,
      restoredHistory: restoredHistory,
      restoredIncorrectTerms: restoredIncorrectTerms,
      restoredCorrectCount: historyCorrect.where((value) => value).length,
      restoredIncorrectCount: historyCorrect.where((value) => !value).length,
      isShuffledValue: snapshot['isShuffled'] == true,
      showStarredOnlyValue: snapshot['showStarredOnly'] == true,
      isReviewingIncorrectValue: snapshot['isReviewingIncorrect'] == true,
      savedShowFurigana: savedShowFurigana,
      savedShowExampleFurigana: savedShowExampleFurigana,
      savedTermFirst: savedTermFirst,
      savedBlueCardText: savedBlueCardText,
    );
  }

  bool _restoreLegacySessionSnapshot(
    Map<String, dynamic> snapshot, {
    required bool? savedShowFurigana,
    required bool? savedShowExampleFurigana,
    required bool? savedTermFirst,
    required bool? savedBlueCardText,
  }) {
    final savedDeckTermIds = _stringList(snapshot['deckTermIds']);
    if (!_sameStringLists(savedDeckTermIds, _deckSessionTermIds)) return false;

    final termsById = <String, Term>{
      for (final term in widget.terms) term.id: term,
    };

    final savedAllTermIds = _stringList(snapshot['allTermIds']);
    final savedAnsweredTermIds = _stringList(snapshot['answeredTermIds']);
    final savedActiveTermIds = _stringList(snapshot['activeTermIds']);
    final savedIncorrectTermIds = _stringList(snapshot['incorrectTermIds']);
    final rawHistory = snapshot['history'];

    if (savedAllTermIds.isEmpty || rawHistory is! List) return false;

    final restoredAllTerms = _termsForIds(savedAllTermIds, termsById);
    final restoredAnsweredTerms =
        _termsForIds(savedAnsweredTermIds, termsById);
    final restoredActiveTerms = _termsForIds(savedActiveTermIds, termsById);
    final restoredIncorrectTerms =
        _termsForIds(savedIncorrectTermIds, termsById);

    if (restoredAllTerms.length != savedAllTermIds.length ||
        restoredAnsweredTerms.length != savedAnsweredTermIds.length ||
        restoredActiveTerms.length != savedActiveTermIds.length ||
        restoredIncorrectTerms.length != savedIncorrectTermIds.length) {
      return false;
    }

    final restoredHistory = <_StudyHistoryEntry>[];
    for (final rawEntry in rawHistory) {
      if (rawEntry is! Map) return false;
      final termId = rawEntry['termId']?.toString();
      final term = termId == null ? null : termsById[termId];
      final correct = rawEntry['correct'];
      if (term == null || correct is! bool) return false;
      restoredHistory.add(
        _StudyHistoryEntry(term: term, correct: correct),
      );
    }

    return _applyRestoredSession(
      restoredAllTerms: restoredAllTerms,
      restoredAnsweredTerms: restoredAnsweredTerms,
      restoredActiveTerms: restoredActiveTerms,
      restoredHistory: restoredHistory,
      restoredIncorrectTerms: restoredIncorrectTerms,
      restoredCorrectCount: _asInt(snapshot['correctCount']) ?? 0,
      restoredIncorrectCount: _asInt(snapshot['incorrectCount']) ?? 0,
      isShuffledValue: snapshot['isShuffled'] == true,
      showStarredOnlyValue: snapshot['showStarredOnly'] == true,
      isReviewingIncorrectValue: snapshot['isReviewingIncorrect'] == true,
      savedShowFurigana: savedShowFurigana,
      savedShowExampleFurigana: savedShowExampleFurigana,
      savedTermFirst: savedTermFirst,
      savedBlueCardText: savedBlueCardText,
    );
  }

  bool _applyRestoredSession({
    required List<Term> restoredAllTerms,
    required List<Term> restoredAnsweredTerms,
    required List<Term> restoredActiveTerms,
    required List<_StudyHistoryEntry> restoredHistory,
    required List<Term> restoredIncorrectTerms,
    required int restoredCorrectCount,
    required int restoredIncorrectCount,
    required bool isShuffledValue,
    required bool showStarredOnlyValue,
    required bool isReviewingIncorrectValue,
    required bool? savedShowFurigana,
    required bool? savedShowExampleFurigana,
    required bool? savedTermFirst,
    required bool? savedBlueCardText,
  }) {
    setState(() {
      allTerms = restoredAllTerms;
      activeTerms = restoredActiveTerms;
      answeredTerms
        ..clear()
        ..addAll(restoredAnsweredTerms);
      history
        ..clear()
        ..addAll(restoredHistory);
      incorrectReviewTerms
        ..clear()
        ..addAll(restoredIncorrectTerms);
      correctCount = restoredCorrectCount;
      incorrectCount = restoredIncorrectCount;
      isShuffled = isShuffledValue;
      showStarredOnly = showStarredOnlyValue;
      isReviewingIncorrect = isReviewingIncorrectValue;
      hasCompletedDeck = activeTerms.isEmpty && allTerms.isNotEmpty;

      if (savedShowFurigana != null) {
        showFurigana = savedShowFurigana;
      }
      if (savedShowExampleFurigana != null) {
        showExampleFurigana = savedShowExampleFurigana;
      }
      if (savedTermFirst != null) {
        termFirst = savedTermFirst;
      }
      if (savedBlueCardText != null) {
        blueCardTextEnabled = savedBlueCardText;
      }

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      showMenu = false;
      _flipController.value = 0;
      _cardContentController.value = 1;
      isSessionReady = true;
    });

    return true;
  }

  Future<void> _saveSessionSnapshot() {
    if (!isSessionReady || allTerms.isEmpty) return Future<void>.value();

    final sessionOrderTermIds = <String>[
      ...answeredTerms.map((term) => term.id),
      ...activeTerms.map((term) => term.id),
    ];
    final historyStartIndex = answeredTerms.length - history.length;

    return GakujiSessionStorage.save(
      sessionType: _sessionType,
      deckId: widget.deck.id,
      snapshot: <String, dynamic>{
        'version': 2,
        'deckSignature': _deckSessionSignature,
        'allTermIds': allTerms.map((term) => term.id).toList(growable: false),
        'sessionOrderTermIds': sessionOrderTermIds,
        'answeredCount': answeredTerms.length,
        'historyStartIndex': historyStartIndex < 0 ? 0 : historyStartIndex,
        'historyCorrect':
            history.map((entry) => entry.correct).toList(growable: false),
        'incorrectTermIds': incorrectReviewTerms
            .map((term) => term.id)
            .toList(growable: false),
        'isShuffled': isShuffled,
        'showStarredOnly': showStarredOnly,
        'isReviewingIncorrect': isReviewingIncorrect,
      },
    );
  }

  Future<void> _clearSessionSnapshot() {
    return GakujiSessionStorage.clear(
      sessionType: _sessionType,
      deckId: widget.deck.id,
    );
  }

  static List<Term> _termsForIds(
    List<String> ids,
    Map<String, Term> termsById,
  ) {
    return ids.map((id) => termsById[id]).whereType<Term>().toList();
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return <String>[];
    return value.map((item) => item.toString()).toList(growable: false);
  }

  static bool _sameStringLists(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  Future<void> _loadReadingCardEdits() async {
    final snapshot = await ReadingCardEditStorage.loadDeck(
      deck: widget.deck,
      terms: widget.deck.terms,
    );
    if (!mounted) return;

    setState(() {
      readingCardEdits
        ..clear()
        ..addAll(snapshot.editsByTermId);

      savedReadingCardEditTermIds
        ..clear()
        ..addAll(snapshot.savedTermIds);
    });
  }

  void scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
  }

  void _toggleFavorite(Term term) {
    setState(() {
      TermFavoriteService.toggle(term);
    });

    scheduleUserDataSave();
  }

  void _saveProgress() {
    if (!isReviewingIncorrect) {
      DeckStorage.saveProgress(widget.deck.id, answeredTerms.length);
      scheduleUserDataSave();
    }

    unawaited(_saveSessionSnapshot());
  }

  bool _isSameTerm(Term first, Term second) {
    return first.kanji == second.kanji &&
        first.reading == second.reading &&
        first.meaning == second.meaning;
  }

  int _termOrderIndex(Term term) {
    final index = allTerms.indexWhere(
      (savedTerm) => _isSameTerm(savedTerm, term),
    );

    return index == -1 ? 999999 : index;
  }

  void _sortActiveTermsToBaseOrder() {
    activeTerms.sort((a, b) {
      return _termOrderIndex(a).compareTo(_termOrderIndex(b));
    });
  }

  void _addIncorrectReviewTerm(Term term) {
    final alreadyAdded = incorrectReviewTerms.any(
      (savedTerm) => _isSameTerm(savedTerm, term),
    );

    if (!alreadyAdded) {
      incorrectReviewTerms.add(term);
    }
  }

  void _removeIncorrectReviewTerm(Term term) {
    final index = incorrectReviewTerms.indexWhere(
      (savedTerm) => _isSameTerm(savedTerm, term),
    );

    if (index != -1) {
      incorrectReviewTerms.removeAt(index);
    }
  }

  void _removeAnsweredTerm(Term term) {
    if (answeredTerms.isEmpty) return;

    final lastTerm = answeredTerms.last;

    if (_isSameTerm(lastTerm, term)) {
      answeredTerms.removeLast();
      return;
    }

    final index = answeredTerms.lastIndexWhere(
      (savedTerm) => _isSameTerm(savedTerm, term),
    );

    if (index != -1) {
      answeredTerms.removeAt(index);
    }
  }

  bool _hasSavedCardEdit(Term term) {
    return savedReadingCardEditTermIds.contains(term.id);
  }

  ReadingCardEditData? _cardEditFor(Term term) {
    return readingCardEdits[term.id];
  }

  String _studyWritingFor(Term term) {
    final override = _cardEditFor(term)?.preferredWritingOverride?.trim() ?? '';
    if (override.isNotEmpty) return override;

    final preferred = term.preferredSpelling.trim();
    if (preferred.isNotEmpty) return preferred;

    if (term.kanji.trim().isNotEmpty) return term.kanji.trim();
    return term.reading.trim();
  }

  List<String> _defaultStudyGlossesFor(Term term) {
    final sourceTerm = term;
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

    if (selectedGlosses.isNotEmpty) {
      return selectedGlosses;
    }

    final defaults = glossBySenseIndex.values.take(3).toList();

    if (defaults.isNotEmpty) {
      return defaults;
    }

    final fallback = sourceTerm.cardMeaning.trim();

    if (fallback.isEmpty) return const [];

    return [fallback];
  }

  List<String> _resolvedStudyGlossesFor(
    Term term,
    List<String> storedGlosses,
  ) {
    if (storedGlosses.isEmpty) {
      return _defaultStudyGlossesFor(term);
    }

    final sourceTerm = term;
    final resolved = <String>[];
    final usedSenseIndexes = <int>{};

    for (final storedGloss in storedGlosses) {
      final cleanedGloss = storedGloss.trim();

      if (cleanedGloss.isEmpty) continue;

      DictionarySense? matchedSense;

      for (final sense in sourceTerm.senses) {
        final matchesSense =
            sense.displayDefinition.trim() == cleanedGloss;
        final matchesLegacyGloss = sense.glosses.any(
          (gloss) => gloss.trim() == cleanedGloss,
        );

        if (matchesSense || matchesLegacyGloss) {
          matchedSense = sense;
          break;
        }
      }

      if (matchedSense == null ||
          !usedSenseIndexes.add(matchedSense.index)) {
        continue;
      }

      final definition = matchedSense.displayDefinition.trim();

      if (definition.isNotEmpty) {
        resolved.add(definition);
      }

      if (resolved.length >= 3) break;
    }

    if (resolved.isNotEmpty) {
      return resolved;
    }

    return _defaultStudyGlossesFor(term);
  }

  Set<int> _studySenseIndexesForGlosses(
    Term term,
    List<String> glosses,
  ) {
    final sourceTerm = term;
    final indexes = <int>{};

    for (final displayedGloss in glosses) {
      final cleanedGloss = displayedGloss.trim();

      if (cleanedGloss.isEmpty) continue;

      for (final sense in sourceTerm.senses) {
        final matchesSense =
            sense.displayDefinition.trim() == cleanedGloss;
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

  List<DictionaryExample> _studyEligibleExamplesFor(
    Term term,
    List<String> glosses,
  ) {
    final sourceTerm = term;
    final senseIndexes = _studySenseIndexesForGlosses(
      term,
      glosses,
    );
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

  List<String> _studyGlossesFor(Term term) {
    final editData = _cardEditFor(term);

    if (_hasSavedCardEdit(term) && editData != null) {
      return _resolvedStudyGlossesFor(
        term,
        editData.selectedGlosses,
      );
    }

    return _defaultStudyGlossesFor(term);
  }

  String _studyNoteFor(Term term) {
    return (term.note ?? '').trim();
  }

  List<DictionaryExample> _studyExamplesFor(Term term) {
    final editData = _cardEditFor(term);
    final glosses = _studyGlossesFor(term);
    final eligibleExamples = _studyEligibleExamplesFor(
      term,
      glosses,
    );

    if (_hasSavedCardEdit(term) && editData != null) {
      return ReadingCardEditData.examplesFromKeys(
        examples: eligibleExamples,
        selectedExampleKeys: editData.selectedExampleKeys,
      ).take(1).toList();
    }

    return eligibleExamples.take(1).toList();
  }

  bool _studyPhotoEnabledFor(Term term) {
    if (!_hasSavedCardEdit(term)) return false;

    return _cardEditFor(term)?.photoEnabled ?? false;
  }

  String? _studyPhotoPathFor(Term term) {
    if (!_studyPhotoEnabledFor(term)) return null;

    final path = _cardEditFor(term)?.photoPath?.trim();

    if (path == null || path.isEmpty) return null;

    return path;
  }

  bool _studyPhotoExistsFor(Term term) {
    final path = _studyPhotoPathFor(term);

    if (path == null) return false;

    return File(path).existsSync();
  }

  void restart() {
    _previousCardReturnRunId++;
    _swipeController.stop();
    _previousCardReturnController.stop();
    _previousCardReturnController.reset();
    _cardContentController.stop();
    _cardContentController.value = 1;

    setState(() {
      allTerms = List<Term>.from(filteredStudyTerms);
      activeTerms = List<Term>.from(allTerms);

      if (isShuffled) {
        activeTerms.shuffle();
      }

      answeredTerms.clear();
      history.clear();
      incorrectReviewTerms.clear();

      correctCount = 0;
      incorrectCount = 0;

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      showMenu = false;
      _flipController.value = 0;
      hasCompletedDeck = false;
      isReviewingIncorrect = false;
    });

    _saveProgress();
  }

  void startIncorrectReview() {
    if (incorrectReviewTerms.isEmpty) {
      _showFloatingMessage('No incorrect answers to review.');
      return;
    }

    _previousCardReturnRunId++;
    _swipeController.stop();
    _previousCardReturnController.stop();
    _previousCardReturnController.reset();
    _cardContentController.stop();
    _cardContentController.value = 1;

    final reviewTerms = List<Term>.from(incorrectReviewTerms);

    setState(() {
      allTerms = reviewTerms;
      activeTerms = List.from(reviewTerms);

      if (isShuffled) {
        activeTerms.shuffle();
      }

      answeredTerms.clear();
      history.clear();
      incorrectReviewTerms.clear();

      correctCount = 0;
      incorrectCount = 0;

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      showMenu = false;
      _flipController.value = 0;
      hasCompletedDeck = false;
      isReviewingIncorrect = true;
    });

    _saveProgress();
  }

  void goBack() {
    if (history.isEmpty || isSwipingAway) {
      return;
    }

    animatePreviousCardBack();
  }

  Future<void> animatePreviousCardBack() async {
    if (history.isEmpty || isSwipingAway) return;

    final runId = ++_previousCardReturnRunId;

    _swipeController.stop();
    _previousCardReturnController.stop();
    _previousCardReturnController.reset();
    _cardContentController.stop();
    _cardContentController.value = 1;

    final oldCurrentTerm = activeTerms.isNotEmpty ? activeTerms.first : null;
    final last = history.removeLast();

    setState(() {
      if (last.correct) {
        correctCount--;
      } else {
        incorrectCount--;
        _removeIncorrectReviewTerm(last.term);
      }

      _removeAnsweredTerm(last.term);
      activeTerms.insert(0, last.term);

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = true;
      previousCardReturnDirection = last.correct ? 1 : -1;
      outgoingCardTerm = oldCurrentTerm;
      _flipController.value = 0;
      showMenu = false;
      hasCompletedDeck = false;
    });

    _saveProgress();

    await _previousCardReturnController.forward(from: 0);

    if (!mounted || runId != _previousCardReturnRunId) return;

    setState(() {
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
    });
  }

  void answer(bool correct) {
    if (activeTerms.isEmpty) return;

    final shouldFadeInNextTerm = activeTerms.length > 1;
    final answeredTerm = activeTerms.first;

    if (shouldFadeInNextTerm) {
      _cardContentController.value = 0;
    } else {
      _cardContentController.value = 1;
    }

    _previousCardReturnRunId++;

    setState(() {
      history.add(
        _StudyHistoryEntry(
          term: answeredTerm,
          correct: correct,
        ),
      );

      answeredTerms.add(answeredTerm);
      activeTerms.removeAt(0);

      if (correct) {
        correctCount++;
      } else {
        incorrectCount++;
        _addIncorrectReviewTerm(answeredTerm);
      }

      if (activeTerms.isEmpty) {
        hasCompletedDeck = true;
      }

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      _flipController.value = 0;
    });

    if (shouldFadeInNextTerm) {
      _cardContentController.forward(from: 0);
    }

    _saveProgress();
  }

  void flip() {
    if (_flipController.isAnimating ||
        isDragging ||
        isSwipingAway ||
        isReturningPreviousCard) {
      return;
    }

    if (_flipController.value < 0.5) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
  }

  void onDragStart(DragStartDetails details) {
    if (isSwipingAway || isReturningPreviousCard) return;

    setState(() {
      showMenu = false;
      isDragging = true;
    });
  }

  void onDragUpdate(DragUpdateDetails details) {
    if (isSwipingAway || isReturningPreviousCard) return;

    setState(() {
      dragOffset = Offset(
        dragOffset.dx + details.delta.dx,
        dragOffset.dy + details.delta.dy,
      );
      isDragging = true;
    });
  }

  void onDragEnd(DragEndDetails details) {
    if (isSwipingAway || isReturningPreviousCard) return;

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
    if (activeTerms.isEmpty) return;

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
      await _clearSessionSnapshot();
      await DeckStorage.saveProgress(widget.deck.id, 0);
      scheduleUserDataSave();
    } else {
      await _saveSessionSnapshot();
    }

    if (!mounted) return;

    Navigator.pop(context);
  }

  void toggleStarredTermFilter() {
    if (isSwipingAway || isReturningPreviousCard) return;

    final nextShowStarredOnly = !showStarredOnly;
    final nextTerms = nextShowStarredOnly
        ? widget.terms.where((term) => term.marked).toList()
        : List<Term>.from(widget.terms);

    if (nextTerms.isEmpty) {
      setState(() {
        showMenu = false;
      });

      _showFloatingMessage('No starred terms to study');
      return;
    }

    _previousCardReturnRunId++;
    _swipeController.stop();
    _previousCardReturnController.stop();
    _previousCardReturnController.reset();
    _cardContentController.stop();
    _cardContentController.value = 1;

    setState(() {
      showStarredOnly = nextShowStarredOnly;

      allTerms = List<Term>.from(nextTerms);
      activeTerms = List<Term>.from(allTerms);

      if (isShuffled) {
        activeTerms.shuffle();
      }

      answeredTerms.clear();
      history.clear();
      incorrectReviewTerms.clear();

      correctCount = 0;
      incorrectCount = 0;

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      showMenu = false;
      _flipController.value = 0;
      hasCompletedDeck = false;
      isReviewingIncorrect = false;
    });

    DeckStorage.saveProgress(widget.deck.id, 0);
    GakujiLocalPreferences.saveBool(
      _starredOnlyPreferenceKey(widget.deck.id),
      showStarredOnly,
    );
    scheduleUserDataSave();
    unawaited(_saveSessionSnapshot());
  }

  void toggleShuffle() {
    if (isSwipingAway || isReturningPreviousCard) return;

    _previousCardReturnRunId++;
    _cardContentController.stop();
    _previousCardReturnController.stop();
    _previousCardReturnController.reset();
    _cardContentController.value = 1;

    setState(() {
      isShuffled = !isShuffled;

      if (isShuffled) {
        activeTerms.shuffle();
      } else {
        _sortActiveTermsToBaseOrder();
      }

      showMenu = false;
      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      _flipController.value = 0;
      hasCompletedDeck = activeTerms.isEmpty && allTerms.isNotEmpty;
    });

    DeckStorage.saveShuffle(widget.deck.id, isShuffled);
    _saveProgress();
  }

  void toggleFurigana() {
    if (isSwipingAway || isReturningPreviousCard) return;

    final nextShowFurigana = !showFurigana;

    setState(() {
      showFurigana = nextShowFurigana;
      showMenu = false;
    });

    GakujiLocalPreferences.saveBool(
      _showFuriganaPreferenceKey,
      nextShowFurigana,
    );
  }

  void toggleExampleFurigana() {
    if (isSwipingAway || isReturningPreviousCard) return;

    final nextShowExampleFurigana = !showExampleFurigana;

    setState(() {
      showExampleFurigana = nextShowExampleFurigana;
      showMenu = false;
    });

    GakujiLocalPreferences.saveBool(
      _showExampleFuriganaPreferenceKey,
      nextShowExampleFurigana,
    );
  }

  void toggleCardOrientation() {
    if (isSwipingAway || isReturningPreviousCard) return;

    final nextTermFirst = !termFirst;

    setState(() {
      termFirst = nextTermFirst;
      showMenu = false;
      _flipController.value = 0;
    });

    GakujiLocalPreferences.saveBool(
      _termFirstPreferenceKey,
      nextTermFirst,
    );
  }

  Future<void> openDeckEdit() async {
    if (isSwipingAway || isReturningPreviousCard) return;

    setState(() {
      showMenu = false;
    });

    await Navigator.push(
      context,
      GakujiPageRoute(
        builder: (context) => DeckEditPage(deck: widget.deck),
      ),
    );

    if (!mounted) return;

    _previousCardReturnRunId++;
    _cardContentController.stop();
    _previousCardReturnController.stop();
    _previousCardReturnController.reset();
    _cardContentController.value = 1;

    setState(() {
      allTerms = List<Term>.from(filteredStudyTerms);
      activeTerms = List<Term>.from(allTerms);

      if (isShuffled) {
        activeTerms.shuffle();
      }

      answeredTerms.clear();
      history.clear();
      incorrectReviewTerms.clear();

      correctCount = 0;
      incorrectCount = 0;

      dragOffset = Offset.zero;
      isDragging = false;
      isSwipingAway = false;
      isReturningPreviousCard = false;
      outgoingCardTerm = null;
      _flipController.value = 0;
      hasCompletedDeck = false;
      isReviewingIncorrect = false;
    });

    _saveProgress();
    await _loadReadingCardEdits();
  }

  void openStudyOptions() {
    showGakujiOptionsSheet(
      context: context,
      title: 'Study Options',
      sectionsBuilder: (context) => [
        GakujiOptionsSheetSection(
          title: 'Study Set',
          items: [
            GakujiOptionsSheetItem(
              icon: showStarredOnly
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              label: showStarredOnly ? 'Starred terms only' : 'All terms',
              iconColor: showStarredOnly
                  ? GakujiColors.starred
                  : GakujiColors.mediumGray,
              onTap: toggleStarredTermFilter,
            ),
          ],
        ),
        GakujiOptionsSheetSection(
          title: 'Display',
          items: [
            GakujiOptionsSheetItem(
              textIcon: 'あ',
              label: showFurigana ? 'Hide Furigana' : 'Show Furigana',
              iconColor: showFurigana
                  ? GakujiColors.darkGray
                  : GakujiColors.mediumGray,
              onTap: toggleFurigana,
            ),
            GakujiOptionsSheetItem(
              textIcon: '例',
              label: showExampleFurigana
                  ? 'Hide Example Sentence Furigana'
                  : 'Show Example Sentence Furigana',
              iconColor: showExampleFurigana
                  ? GakujiColors.darkGray
                  : GakujiColors.mediumGray,
              onTap: toggleExampleFurigana,
            ),
            GakujiOptionsSheetItem(
              icon: Icons.swap_horiz_rounded,
              label: termFirst ? 'Term First' : 'Definition First',
              iconColor: termFirst
                  ? GakujiColors.mediumGray
                  : GakujiColors.darkGray,
              onTap: toggleCardOrientation,
            ),
          ],
        ),
        GakujiOptionsSheetSection(
          title: 'Session',
          items: [
            GakujiOptionsSheetItem(
              icon: Icons.shuffle_rounded,
              label: isShuffled ? 'Shuffled' : 'Unshuffled',
              iconColor: isShuffled
                  ? GakujiColors.darkGray
                  : GakujiColors.mediumGray,
              onTap: () {
                Navigator.of(context).pop();
                toggleShuffle();
              },
            ),
            GakujiOptionsSheetItem(
              icon: Icons.refresh_rounded,
              label: 'Reset Deck',
              iconColor: GakujiColors.mediumGray,
              onTap: () {
                Navigator.of(context).pop();
                restart();
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

  @override
  Widget build(BuildContext context) {
    if (allTerms.isEmpty && activeTerms.isEmpty) {
      return Scaffold(
        backgroundColor: GakujiColors.warmBackground,
        body: Center(
          child: Text(
            'No terms',
            textScaler: TextScaler.noScaling,
            style: GakujiText.small,
          ),
        ),
      );
    }

    if (isComplete) {
      return _completeScreen();
    }

    final currentTerm = activeTerms.first;
    final hasCardBehind = activeTerms.length > 1;

    final rotation = (dragOffset.dx / 700).clamp(-0.35, 0.35).toDouble();

    final feedbackText = swipeFeedbackText;
    final feedbackColor = swipeFeedbackColor;
    final feedbackOpacity = swipeFeedbackOpacity;

    final screenWidth = MediaQuery.of(context).size.width;
    final previousReturnProgress = _previousCardReturnAnimation.value;

    final returningOffsetX = isReturningPreviousCard
        ? previousCardReturnDirection *
            screenWidth *
            (1 - previousReturnProgress)
        : 0.0;

    final outgoingOffsetX =
        -previousCardReturnDirection * 72 * previousReturnProgress;

    final outgoingOpacity = (1 - previousReturnProgress).clamp(0.0, 1.0);

    final currentPosition = answeredTerms.length + 1;
    final totalPosition = totalSessionCount;

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
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
                  _studyTopBar(
                    leftIcon: Icons.close_rounded,
                    onLeftTap: handleExit,
                    title: '$currentPosition/$totalPosition',
                    rightIcon: Icons.menu_rounded,
                    onRightTap: openStudyOptions,
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
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasCardBehind) _blankCardBehind(),
                        if (isReturningPreviousCard && outgoingCardTerm != null)
                          Opacity(
                            opacity: outgoingOpacity,
                            child: Transform(
                              transform: Matrix4.identity()
                                ..translateByDouble(outgoingOffsetX, 0.0, 0.0, 1.0),
                              alignment: Alignment.center,
                              child: _card(
                                outgoingCardTerm!,
                                showBack: false,
                                contentOpacity: 1,
                              ),
                            ),
                          ),
                        Transform(
                          transform: Matrix4.identity()
                            ..translateByDouble(
                              isReturningPreviousCard
                                  ? returningOffsetX
                                  : dragOffset.dx,
                              isReturningPreviousCard ? 0.0 : dragOffset.dy,
                              0.0,
                              1.0,
                            )
                            ..rotateZ(
                              isReturningPreviousCard ? 0.0 : rotation,
                            ),
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
                                final angle = isReturningPreviousCard
                                    ? 0.0
                                    : _flipAnimation.value;
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
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _circle(Icons.undo_rounded, goBack),
                        const SizedBox(
                          width: 46,
                          height: 46,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
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

  Widget _completeScreen() {
    final total = correctCount + incorrectCount;
    final percent = total == 0 ? 0 : ((correctCount / total) * 100).round();

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _studyTopBar(
                  leftIcon: Icons.close_rounded,
                  onLeftTap: handleExit,
                  title: '',
                  rightIcon: Icons.menu_rounded,
                  onRightTap: openStudyOptions,
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
                            if (incorrectReviewTerms.isNotEmpty) ...[
                              _completeActionButton(
                                label: 'Review Incorrect Answers',
                                color: GakujiColors.deckBlue,
                                height: buttonHeight,
                                onTap: startIncorrectReview,
                              ),
                              SizedBox(height: buttonGap),
                            ],
                            _completeActionButton(
                              label: 'Restart Deck',
                              color: incorrectReviewTerms.isEmpty
                                  ? GakujiColors.deckBlue
                                  : GakujiColors.whiteCard,
                              textColor: incorrectReviewTerms.isEmpty
                                  ? Colors.white
                                  : GakujiColors.mediumGray,
                              outlined: incorrectReviewTerms.isNotEmpty,
                              height: buttonHeight,
                              onTap: restart,
                            ),
                            const SizedBox(height: 10),
                            _returnLastCardButton(),
                            SizedBox(height: bottomGap),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
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
                  style: GakujiText.actionLabel.copyWith(
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

  Widget _returnLastCardButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: goBack,
        borderRadius: BorderRadius.circular(20),
        splashColor: GakujiColors.deckBlue.withValues(alpha: 0.08),
        highlightColor: GakujiColors.deckBlue.withValues(alpha: 0.04),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back_rounded,
                size: 22,
                color: GakujiColors.mediumGray,
              ),
              SizedBox(width: 6),
              Text(
                'Return to Last Card',
                textScaler: TextScaler.noScaling,
                style: GakujiText.body.copyWith(
                  color: GakujiColors.mediumGray,
                )
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blankCardBehind() {
    return IgnorePointer(
      child: ReadingCardFrame(
        margin: const EdgeInsets.fromLTRB(28, 0, 28, 0),
        boxShadow: [GakujiShadows.soft],
        child: const SizedBox.expand(),
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

    return ReadingCardFrame(
      margin: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      borderColor:
          hasSwipeFeedback ? swipeColor : GakujiColors.softBorder,
      borderWidth: hasSwipeFeedback ? 5 : 1.2,
      isStarred: term.marked,
      onStarTap: () => _toggleFavorite(term),
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
        ],
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
    final readingText = term.reading.trim();
    final editData = _cardEditFor(term);
    final photoPath = _studyPhotoExistsFor(term)
        ? _studyPhotoPathFor(term)
        : null;

    return ReadingCardBackContent(
      glosses: _studyGlossesFor(term),
      note: _studyNoteFor(term),
      examples: _studyExamplesFor(term),
      photoPath: photoPath,
      photoScale: editData?.photoScale ?? 1.0,
      photoOffsetX: editData?.photoOffsetX ?? 0.0,
      photoOffsetY: editData?.photoOffsetY ?? 0.0,
      readingText: readingText,
      showReadingOnBack: !showFurigana && readingText.isNotEmpty,
      showExampleFurigana: showExampleFurigana,
      textColor: blueCardTextEnabled ? GakujiColors.reading : null,
    );
  }

  Widget _termCardContent(Term term) {
    final kanjiText = _studyWritingFor(term);
    final readingText = term.reading.trim();
    final showReadingAbove = showFurigana &&
        readingText.isNotEmpty &&
        readingText != kanjiText &&
        RegExp(r'[\u4E00-\u9FFF]').hasMatch(kanjiText);

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
                    color: blueCardTextEnabled
                        ? GakujiColors.reading
                        : GakujiColors.darkGray,
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
                      color: blueCardTextEnabled
                          ? GakujiColors.reading
                          : GakujiColors.mediumGray,
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

  Widget _circle(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: GakujiColors.deckBlue.withValues(alpha: 0.08),
        highlightColor: GakujiColors.deckBlue.withValues(alpha: 0.04),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            icon,
            size: 31,
            color: GakujiColors.darkGray,
          ),
        ),
      ),
    );
  }
}

class _StudyHistoryEntry {
  final Term term;
  final bool correct;

  const _StudyHistoryEntry({
    required this.term,
    required this.correct,
  });
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

    // Bottom-centered opening matching the completion design.
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
