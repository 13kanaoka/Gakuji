import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/features/games/models/imposter_round.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/data/sync/gakuji_local_preferences.dart';
import 'package:gakuji/data/sync/gakuji_session_storage.dart';
import 'package:gakuji/features/games/services/imposter_round_generator.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_options_sheet.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';

enum CrosscheckMode { normal, rush, endless }

enum _RushField { reading, definition }

class ImposterDetectivePage extends StatefulWidget {
  final Deck deck;
  final List<Term> terms;

  const ImposterDetectivePage({
    super.key,
    required this.deck,
    required this.terms,
  });

  @override
  State<ImposterDetectivePage> createState() => _ImposterDetectivePageState();
}

class _ImposterDetectivePageState extends State<ImposterDetectivePage> {
  static const Duration _rushStartingRoundDuration = Duration(seconds: 5);
  static const Duration _rushMinimumRoundDuration = Duration(milliseconds: 1500);
  static const Duration _rushSpeedUpPerCorrect = Duration(milliseconds: 150);
  static const Duration _rushTickInterval = Duration(milliseconds: 50);
  static const int _sessionSnapshotVersion = 1;

  // Crosscheck verdict palette: soft, but stronger than the old washed-out fills.
  static const Color _incorrectRed = Color(0xFFF29A9A);
  static const Color _incorrectRedOutline = Color(0xFFD75F5F);
  static const Color _correctGreen = Color(0xFFBDE68F);
  static const Color _correctGreenOutline = Color(0xFF78A94F);

  late final List<Term> gameTerms;

  final ImposterRoundGenerator _generator = ImposterRoundGenerator();
  final math.Random _random = math.Random();
  final Map<CrosscheckMode, String> _sessionTermSignatureCache =
      <CrosscheckMode, String>{};

  ImposterRound? currentRound;
  ImposterRound? correctionRound;
  bool? correctionUserApproved;

  bool gameStarted = false;
  bool gameOver = false;
  bool showingCorrection = false;

  CrosscheckMode? selectedMode;

  int currentIndex = 0;
  int roundsPlayed = 0;
  int correctCount = 0;
  int mistakeCount = 0;
  int streak = 0;
  int bestStreak = 0;

  Timer? _rushTimer;
  DateTime? _rushDeadline;
  int _rushRoundDurationMilliseconds =
      _rushStartingRoundDuration.inMilliseconds;
  int _rushRemainingMilliseconds =
      _rushStartingRoundDuration.inMilliseconds;
  bool _rushCheckReading = true;
  bool _rushCheckDefinition = true;
  bool _checkPartOfSpeech = false;

  final Map<CrosscheckMode, int> highScores = {
    CrosscheckMode.normal: 0,
    CrosscheckMode.rush: 0,
    CrosscheckMode.endless: 0,
  };

  int get mistakeLimit {
    return selectedMode == CrosscheckMode.rush ? 1 : 3;
  }

  bool get isEndlessMode => selectedMode == CrosscheckMode.endless;

  bool get isRushMode => selectedMode == CrosscheckMode.rush;

  bool get isLoopingMode => isEndlessMode || isRushMode;

  String get _rushFieldLabel {
    if (_rushCheckReading && _rushCheckDefinition) {
      return 'Reading + Definition';
    }
    if (_rushCheckReading) return 'Reading';
    return 'Definition';
  }

  bool get _rushTimerShouldRun {
    return isRushMode &&
        gameStarted &&
        !gameOver &&
        !showingCorrection &&
        currentRound != null;
  }

  double get _rushProgress {
    if (_rushRoundDurationMilliseconds <= 0) return 0;

    return (_rushRemainingMilliseconds / _rushRoundDurationMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  int _rushDurationMillisecondsForScore(int score) {
    final start = _rushStartingRoundDuration.inMilliseconds;
    final minimum = _rushMinimumRoundDuration.inMilliseconds;
    final reduction = _rushSpeedUpPerCorrect.inMilliseconds * score;
    return (start - reduction).clamp(minimum, start).toInt();
  }

  void _resetRushRoundTimerForCurrentScore() {
    _rushRoundDurationMilliseconds =
        _rushDurationMillisecondsForScore(correctCount);
    _rushRemainingMilliseconds = _rushRoundDurationMilliseconds;
  }


  Color get deckPrimaryColor {
    return GakujiColors.deckColorFor(widget.deck);
  }

  bool get clearedDeck {
    return selectedMode == CrosscheckMode.normal &&
        gameTerms.isNotEmpty &&
        currentIndex >= gameTerms.length;
  }

  @override
  void initState() {
    super.initState();
    gameTerms = List<Term>.from(widget.terms)..shuffle();
    unawaited(_loadHighScores());
    unawaited(_loadRushSettings());
    unawaited(_loadPartOfSpeechSetting());
  }

  @override
  void dispose() {
    if (_shouldPersistSelectedSession) {
      unawaited(_saveSessionSnapshot());
    }
    _cancelRushTimer();
    super.dispose();
  }

  Future<void> _loadHighScores() async {
    final loadedScores = <CrosscheckMode, int>{};
    for (final mode in CrosscheckMode.values) {
      loadedScores[mode] =
          await GakujiLocalPreferences.loadInt(_highScoreKey(mode)) ?? 0;
    }

    if (!mounted) return;

    setState(() {
      highScores.addAll(loadedScores);
    });
  }

  Future<void> _loadRushSettings() async {
    final savedReading = await GakujiLocalPreferences.loadBool(
      'crosscheck_rush_check_reading_v1',
    );
    final savedDefinition = await GakujiLocalPreferences.loadBool(
      'crosscheck_rush_check_definition_v1',
    );

    if (!mounted) return;

    setState(() {
      _rushCheckReading = savedReading ?? true;
      _rushCheckDefinition = savedDefinition ?? true;

      if (!_rushCheckReading && !_rushCheckDefinition) {
        _rushCheckReading = true;
        _rushCheckDefinition = true;
      }
    });
  }

  Future<void> _persistRushSettings() async {
    await Future.wait([
      GakujiLocalPreferences.saveBool(
        'crosscheck_rush_check_reading_v1',
        _rushCheckReading,
      ),
      GakujiLocalPreferences.saveBool(
        'crosscheck_rush_check_definition_v1',
        _rushCheckDefinition,
      ),
    ]);
  }

  Future<void> _loadPartOfSpeechSetting() async {
    final savedPartOfSpeech = await GakujiLocalPreferences.loadBool(
      'crosscheck_check_part_of_speech_v1',
    );

    if (!mounted) return;

    setState(() {
      _checkPartOfSpeech = savedPartOfSpeech ?? false;
    });
  }

  Future<void> _persistPartOfSpeechSetting() async {
    await GakujiLocalPreferences.saveBool(
      'crosscheck_check_part_of_speech_v1',
      _checkPartOfSpeech,
    );
  }

  String _highScoreKey(CrosscheckMode mode) {
    return 'crosscheck_high_score_v1_${widget.deck.id}_${mode.name}';
  }

  Future<void> _persistHighScore(CrosscheckMode mode, int score) async {
    await GakujiLocalPreferences.saveInt(_highScoreKey(mode), score);
  }

  void _recordHighScoreIfNeeded() {
    final mode = selectedMode;
    if (mode == null) return;

    final previousBest = highScores[mode] ?? 0;
    if (correctCount <= previousBest) return;

    setState(() {
      highScores[mode] = correctCount;
    });

    unawaited(_persistHighScore(mode, correctCount));
  }

  List<Term> _termsForMode(CrosscheckMode mode) {
    if (mode == CrosscheckMode.rush) {
      return List<Term>.from(widget.terms);
    }

    return widget.terms
        .where(_hasPreferredKanjiWriting)
        .toList(growable: false);
  }

  bool _hasPreferredKanjiWriting(Term term) {
    final preferred = term.preferredSpelling.trim();
    if (preferred.isEmpty) return false;

    return RegExp(
      r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々〆ヵヶ]',
    ).hasMatch(preferred);
  }

  bool _supportsSessionSave(CrosscheckMode? mode) {
    return mode == CrosscheckMode.normal || mode == CrosscheckMode.endless;
  }

  bool get _shouldPersistSelectedSession {
    return _supportsSessionSave(selectedMode) &&
        gameStarted &&
        !gameOver &&
        currentRound != null &&
        gameTerms.isNotEmpty;
  }

  String? _sessionTypeForMode(CrosscheckMode mode) {
    switch (mode) {
      case CrosscheckMode.normal:
        return 'crosscheck_normal';
      case CrosscheckMode.endless:
        return 'crosscheck_endless';
      case CrosscheckMode.rush:
        return null;
    }
  }

  String _sessionTermSignature(CrosscheckMode mode) {
    return _sessionTermSignatureCache.putIfAbsent(mode, () {
      final modeTerms = _termsForMode(mode);
      var hash = 0x811C9DC5;

      for (final term in modeTerms) {
        for (final value in <String>[
          term.id,
          term.preferredSpelling,
          term.kanji,
          term.reading,
          term.meaning,
          term.cardMeaning,
          term.partOfSpeech,
        ]) {
          for (final codeUnit in value.codeUnits) {
            hash ^= codeUnit;
            hash = (hash * 0x01000193) & 0xFFFFFFFF;
          }
          hash ^= 0xFE;
          hash = (hash * 0x01000193) & 0xFFFFFFFF;
        }
        hash ^= 0xFF;
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }

      return '${modeTerms.length}:${hash.toRadixString(16)}';
    });
  }

  bool _restoreCachedSession(CrosscheckMode mode) {
    final sessionType = _sessionTypeForMode(mode);
    if (sessionType == null ||
        !GakujiSessionStorage.hasCached(
          sessionType: sessionType,
          deckId: widget.deck.id,
        )) {
      return false;
    }

    final snapshot = GakujiSessionStorage.peek(
      sessionType: sessionType,
      deckId: widget.deck.id,
    );
    if (snapshot == null) return false;

    return _restoreSessionSnapshot(mode, snapshot);
  }

  Future<Map<String, dynamic>?> _loadSessionSnapshot(
    CrosscheckMode mode,
  ) {
    final sessionType = _sessionTypeForMode(mode);
    if (sessionType == null) return Future<Map<String, dynamic>?>.value();

    return GakujiSessionStorage.load(
      sessionType: sessionType,
      deckId: widget.deck.id,
    );
  }

  bool _restoreSessionSnapshot(
    CrosscheckMode mode,
    Map<String, dynamic> snapshot,
  ) {
    if (_asInt(snapshot['version']) != _sessionSnapshotVersion ||
        snapshot['mode']?.toString() != mode.name ||
        snapshot['termSignature']?.toString() != _sessionTermSignature(mode)) {
      return false;
    }

    final modeTerms = _termsForMode(mode);
    if (modeTerms.isEmpty) return false;

    final termsById = <String, Term>{
      for (final term in modeTerms) term.id: term,
    };
    final savedGameTermIds = _stringList(snapshot['gameTermIds']);
    if (savedGameTermIds.length != modeTerms.length ||
        savedGameTermIds.toSet().length != savedGameTermIds.length) {
      return false;
    }

    final restoredGameTerms = savedGameTermIds
        .map((id) => termsById[id])
        .whereType<Term>()
        .toList(growable: false);
    if (restoredGameTerms.length != savedGameTermIds.length) return false;

    final restoredIndex = _asInt(snapshot['currentIndex']);
    if (restoredIndex == null ||
        restoredIndex < 0 ||
        restoredIndex >= restoredGameTerms.length) {
      return false;
    }

    final restoredCurrentRound = _roundFromSnapshot(
      snapshot['currentRound'],
      termsById,
    );
    if (restoredCurrentRound == null ||
        restoredCurrentRound.visitor.id != restoredGameTerms[restoredIndex].id) {
      return false;
    }

    final restoredShowingCorrection = snapshot['showingCorrection'] == true;
    final restoredCorrectionRound = restoredShowingCorrection
        ? _roundFromSnapshot(snapshot['correctionRound'], termsById)
        : null;
    final restoredCorrectionUserApproved =
        snapshot['correctionUserApproved'] is bool
            ? snapshot['correctionUserApproved'] as bool
            : null;

    if (restoredShowingCorrection &&
        (restoredCorrectionRound == null ||
            restoredCorrectionUserApproved == null ||
            restoredCorrectionRound.visitor.id != restoredCurrentRound.visitor.id)) {
      return false;
    }

    final restoredMistakeCount = _asInt(snapshot['mistakeCount']) ?? 0;
    if (restoredMistakeCount < 0 ||
        restoredMistakeCount > 3 ||
        (restoredMistakeCount == 3 && !restoredShowingCorrection)) {
      return false;
    }

    _cancelRushTimer();

    setState(() {
      gameTerms
        ..clear()
        ..addAll(restoredGameTerms);
      selectedMode = mode;
      gameStarted = true;
      gameOver = false;
      showingCorrection = restoredShowingCorrection;
      currentIndex = restoredIndex;
      roundsPlayed =
          math.max(0, _asInt(snapshot['roundsPlayed']) ?? 0).toInt();
      correctCount =
          math.max(0, _asInt(snapshot['correctCount']) ?? 0).toInt();
      mistakeCount = restoredMistakeCount;
      streak = math.max(0, _asInt(snapshot['streak']) ?? 0).toInt();
      bestStreak = math
          .max(
            streak,
            math.max(0, _asInt(snapshot['bestStreak']) ?? 0),
          )
          .toInt();
      currentRound = restoredCurrentRound;
      correctionRound = restoredCorrectionRound;
      correctionUserApproved = restoredShowingCorrection
          ? restoredCorrectionUserApproved
          : null;
      _rushRoundDurationMilliseconds =
          _rushStartingRoundDuration.inMilliseconds;
      _rushRemainingMilliseconds = _rushRoundDurationMilliseconds;
    });

    return true;
  }

  Map<String, dynamic> _roundToSnapshot(ImposterRound round) {
    return <String, dynamic>{
      'visitorId': round.visitor.id,
      'reading': round.file.reading,
      'definition': round.file.definition,
      'partOfSpeech': round.file.partOfSpeech,
      'isValid': round.isValid,
    };
  }

  ImposterRound? _roundFromSnapshot(
    dynamic raw,
    Map<String, Term> termsById,
  ) {
    if (raw is! Map) return null;

    final visitorId = raw['visitorId']?.toString() ?? '';
    final visitor = termsById[visitorId];
    if (visitor == null) return null;

    final isValid = raw['isValid'];
    if (isValid is! bool) return null;

    return ImposterRound(
      visitor: visitor,
      file: IdentityFile(
        reading: raw['reading']?.toString() ?? '—',
        definition: raw['definition']?.toString() ?? '—',
        partOfSpeech: raw['partOfSpeech']?.toString() ?? '—',
      ),
      isValid: isValid,
    );
  }

  Future<void> _saveSessionSnapshot() {
    final mode = selectedMode;
    if (!_shouldPersistSelectedSession || mode == null) {
      return Future<void>.value();
    }

    final sessionType = _sessionTypeForMode(mode);
    final round = currentRound;
    if (sessionType == null || round == null) return Future<void>.value();

    return GakujiSessionStorage.save(
      sessionType: sessionType,
      deckId: widget.deck.id,
      snapshot: <String, dynamic>{
        'version': _sessionSnapshotVersion,
        'mode': mode.name,
        'termSignature': _sessionTermSignature(mode),
        'gameTermIds': gameTerms.map((term) => term.id).toList(growable: false),
        'currentIndex': currentIndex,
        'roundsPlayed': roundsPlayed,
        'correctCount': correctCount,
        'mistakeCount': mistakeCount,
        'streak': streak,
        'bestStreak': bestStreak,
        'showingCorrection': showingCorrection,
        'currentRound': _roundToSnapshot(round),
        if (showingCorrection && correctionRound != null)
          'correctionRound': _roundToSnapshot(correctionRound!),
        if (showingCorrection && correctionUserApproved != null)
          'correctionUserApproved': correctionUserApproved,
      },
    );
  }

  Future<void> _clearSessionSnapshot(CrosscheckMode mode) {
    final sessionType = _sessionTypeForMode(mode);
    if (sessionType == null) return Future<void>.value();

    return GakujiSessionStorage.clear(
      sessionType: sessionType,
      deckId: widget.deck.id,
    );
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

  Future<void> startGame(CrosscheckMode mode) async {
    final modeTerms = _termsForMode(mode);
    if (modeTerms.isEmpty) return;

    _cancelRushTimer();

    if (_supportsSessionSave(mode)) {
      if (_restoreCachedSession(mode)) return;

      final savedSnapshot = await _loadSessionSnapshot(mode);
      if (!mounted) return;

      if (savedSnapshot != null &&
          _restoreSessionSnapshot(mode, savedSnapshot)) {
        return;
      }

      if (savedSnapshot != null) {
        await _clearSessionSnapshot(mode);
        if (!mounted) return;
      }
    }

    _startFreshGame(mode, modeTerms: modeTerms);
  }

  void _startFreshGame(
    CrosscheckMode mode, {
    List<Term>? modeTerms,
  }) {
    final freshTerms = modeTerms ?? _termsForMode(mode);
    if (freshTerms.isEmpty) return;

    _cancelRushTimer();
    gameTerms
      ..clear()
      ..addAll(freshTerms)
      ..shuffle();

    setState(() {
      selectedMode = mode;
      gameStarted = true;
      gameOver = false;
      showingCorrection = false;
      correctionRound = null;
      correctionUserApproved = null;
      currentIndex = 0;
      roundsPlayed = 0;
      correctCount = 0;
      mistakeCount = 0;
      streak = 0;
      bestStreak = 0;
      _rushRoundDurationMilliseconds =
          _rushStartingRoundDuration.inMilliseconds;
      _rushRemainingMilliseconds = _rushRoundDurationMilliseconds;
      currentRound = _generateRoundForCurrentIndex();
    });

    if (mode == CrosscheckMode.rush) {
      _startRushTimer(reset: true);
    } else {
      unawaited(_saveSessionSnapshot());
    }
  }

  void _startRushTimer({required bool reset}) {
    _cancelRushTimer();

    if (!_rushTimerShouldRun) return;

    if (reset) {
      _resetRushRoundTimerForCurrentScore();
    }

    if (_rushRemainingMilliseconds <= 0) {
      _handleRushTimeout();
      return;
    }

    _rushDeadline = DateTime.now().add(
      Duration(milliseconds: _rushRemainingMilliseconds),
    );

    _rushTimer = Timer.periodic(_rushTickInterval, (_) {
      if (!mounted || !_rushTimerShouldRun) {
        _cancelRushTimer();
        return;
      }

      final deadline = _rushDeadline;
      if (deadline == null) return;

      final remaining = deadline.difference(DateTime.now()).inMilliseconds;

      if (remaining <= 0) {
        _cancelRushTimer();
        _handleRushTimeout();
        return;
      }

      setState(() {
        _rushRemainingMilliseconds = remaining;
      });
    });
  }

  void _pauseRushTimer() {
    if (!isRushMode || _rushTimer == null) return;

    final deadline = _rushDeadline;
    var remaining = _rushRemainingMilliseconds;

    if (deadline != null) {
      remaining = deadline.difference(DateTime.now()).inMilliseconds;
    }

    _cancelRushTimer();

    if (!mounted) return;

    setState(() {
      _rushRemainingMilliseconds = remaining
          .clamp(0, _rushRoundDurationMilliseconds)
          .toInt();
    });
  }

  void _cancelRushTimer() {
    _rushTimer?.cancel();
    _rushTimer = null;
    _rushDeadline = null;
  }

  void _handleRushTimeout() {
    if (!mounted || !_rushTimerShouldRun) return;

    setState(() {
      _rushRemainingMilliseconds = 0;
      mistakeCount++;
      streak = 0;
      roundsPlayed++;
      gameOver = true;
      currentRound = null;
    });
  }

  ImposterRound? _generateRoundForCurrentIndex() {
    if (currentIndex >= gameTerms.length) return null;

    final visitor = gameTerms[currentIndex];

    if (isRushMode) {
      return _generateRushRound(visitor);
    }

    return _generator.generate(
      visitor: visitor,
      deckTerms: gameTerms,
    );
  }

  ImposterRound _generateRushRound(Term visitor) {
    final correctFile = _correctIdentityFile(visitor);
    final mismatchOptions = <_RushMismatchOption>[];

    if (_rushCheckReading) {
      final alternative = _alternativeRushReading(visitor);
      if (alternative != null) {
        mismatchOptions.add(
          _RushMismatchOption(
            field: _RushField.reading,
            value: alternative,
          ),
        );
      }
    }

    if (_rushCheckDefinition) {
      final alternative = _alternativeRushDefinition(visitor);
      if (alternative != null) {
        mismatchOptions.add(
          _RushMismatchOption(
            field: _RushField.definition,
            value: alternative,
          ),
        );
      }
    }

    final shouldBeValid = mismatchOptions.isEmpty || _random.nextBool();

    if (shouldBeValid) {
      return ImposterRound(
        visitor: visitor,
        file: correctFile,
        isValid: true,
      );
    }

    final mismatch = mismatchOptions[_random.nextInt(mismatchOptions.length)];

    return ImposterRound(
      visitor: visitor,
      file: IdentityFile(
        reading: mismatch.field == _RushField.reading
            ? mismatch.value
            : correctFile.reading,
        definition: mismatch.field == _RushField.definition
            ? mismatch.value
            : correctFile.definition,
        partOfSpeech: correctFile.partOfSpeech,
      ),
      isValid: false,
    );
  }

  String? _alternativeRushReading(Term visitor) {
    final current = _normalized(_safeValue(visitor.reading));
    final candidates = gameTerms
        .where((term) => term.id != visitor.id)
        .map((term) => _safeValue(term.reading))
        .where((value) => value != '—' && _normalized(value) != current)
        .toSet()
        .toList();

    if (candidates.isEmpty) return null;
    return candidates[_random.nextInt(candidates.length)];
  }

  String? _alternativeRushDefinition(Term visitor) {
    final current = _normalized(_definitionText(visitor));
    final candidates = gameTerms
        .where((term) => term.id != visitor.id)
        .map(_definitionText)
        .where((value) => value != '—' && _normalized(value) != current)
        .toSet()
        .toList();

    if (candidates.isEmpty) return null;
    return candidates[_random.nextInt(candidates.length)];
  }

  void answer({
    required bool approved,
  }) {
    final round = currentRound;

    if (!gameStarted || gameOver || showingCorrection || round == null) {
      return;
    }

    if (isRushMode) {
      _cancelRushTimer();
    }

    final isCorrect = approved == round.isValid;

    if (isCorrect) {
      setState(() {
        correctCount++;
        streak++;

        if (streak > bestStreak) {
          bestStreak = streak;
        }

        _advanceToNextRound();
      });

      _recordHighScoreIfNeeded();

      final mode = selectedMode;
      if (_supportsSessionSave(mode) && mode != null) {
        if (gameOver) {
          unawaited(_clearSessionSnapshot(mode));
        } else {
          unawaited(_saveSessionSnapshot());
        }
      }

      if (_rushTimerShouldRun) {
        _startRushTimer(reset: true);
      }
      return;
    }

    setState(() {
      mistakeCount++;
      streak = 0;
      if (isRushMode) {
        _rushRemainingMilliseconds = 0;
      }
      showingCorrection = true;
      correctionRound = round;
      correctionUserApproved = approved;
    });

    if (_shouldPersistSelectedSession) {
      unawaited(_saveSessionSnapshot());
    }
  }

  void continueAfterCorrection() {
    if (!showingCorrection) return;

    setState(() {
      showingCorrection = false;
      correctionRound = null;
      correctionUserApproved = null;
      _advanceToNextRound();
    });

    final mode = selectedMode;
    if (_supportsSessionSave(mode) && mode != null) {
      if (gameOver) {
        unawaited(_clearSessionSnapshot(mode));
      } else {
        unawaited(_saveSessionSnapshot());
      }
    }
  }

  void _advanceToNextRound() {
    roundsPlayed++;
    currentIndex++;

    if (mistakeCount >= mistakeLimit) {
      gameOver = true;
      currentRound = null;
      return;
    }

    if (currentIndex >= gameTerms.length) {
      if (!isLoopingMode) {
        gameOver = true;
        currentRound = null;
        return;
      }

      gameTerms.shuffle();
      currentIndex = 0;
    }

    currentRound = _generateRoundForCurrentIndex();
  }

  Future<void> restartGame() async {
    final mode = selectedMode ?? CrosscheckMode.normal;
    _cancelRushTimer();

    if (_supportsSessionSave(mode)) {
      await _clearSessionSnapshot(mode);
      if (!mounted) return;
    }

    _startFreshGame(mode);
  }

  void _returnToModeSelection() {
    if (_shouldPersistSelectedSession) {
      unawaited(_saveSessionSnapshot());
    }

    _cancelRushTimer();

    setState(() {
      gameStarted = false;
      gameOver = false;
      showingCorrection = false;
      correctionRound = null;
      correctionUserApproved = null;
      currentRound = null;
      currentIndex = 0;
      roundsPlayed = 0;
      correctCount = 0;
      mistakeCount = 0;
      streak = 0;
      bestStreak = 0;
      _rushRoundDurationMilliseconds =
          _rushStartingRoundDuration.inMilliseconds;
      _rushRemainingMilliseconds = _rushRoundDurationMilliseconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!gameStarted) {
      return _startScreen(context);
    }

    if (gameOver || clearedDeck) {
      return _resultsScreen(context);
    }

    return _gameScreen(context);
  }

  Widget _startScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            _simpleTopBar(
              context: context,
              icon: Icons.close_rounded,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      GakujiSpacing.pageHorizontal,
                      12,
                      GakujiSpacing.pageHorizontal,
                      28,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 40,
                      ),
                      child: Column(
                        children: [
                          SizedBox(height: constraints.maxHeight * 0.02),
                          Text(
                            'Crosscheck',
                            textAlign: TextAlign.center,
                            textScaler: TextScaler.noScaling,
                            style: GakujiText.xLarge.copyWith(
                              color: GakujiColors.darkGray,
                            ),
                          ),
                          SizedBox(height: 34 + constraints.maxHeight * 0.06),
                          _modeCard(
                            mode: CrosscheckMode.normal,
                            title: 'Normal',
                            description: '3 mistakes • Complete the deck',
                          ),
                          const SizedBox(height: 18),
                          _modeCard(
                            mode: CrosscheckMode.rush,
                            title: 'Rush',
                            description:
                                '5 → 1.5 seconds • $_rushFieldLabel • Sudden death',
                          ),
                          const SizedBox(height: 18),
                          _modeCard(
                            mode: CrosscheckMode.endless,
                            title: 'Endless',
                            description: 'Loop the deck • 3 mistakes end the run',
                          ),
                          const SizedBox(height: 24),
                          if (gameTerms.isEmpty)
                            Text(
                              'No entries are available for Crosscheck.',
                              textAlign: TextAlign.center,
                              textScaler: TextScaler.noScaling,
                              style: GakujiText.small.copyWith(
                                color: GakujiColors.mediumGray,
                              ),
                            ),
                        ],
                      ),
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

  Widget _modeCard({
    required CrosscheckMode mode,
    required String title,
    required String description,
  }) {
    final enabled = _termsForMode(mode).isNotEmpty;
    final best = highScores[mode] ?? 0;

    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: SizedBox(
        width: double.infinity,
        height: 118,
        child: Material(
          color: deckPrimaryColor,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => unawaited(startGame(mode)) : null,
            splashColor: Colors.white.withValues(alpha: 0.12),
            highlightColor: Colors.white.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      fontSize: 27,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: Color(0xE6FFFFFF),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'BEST  $best',
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                      color: Color(0xCCFFFFFF),
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

  Widget _gameScreen(BuildContext context) {
    final round = currentRound;

    if (round == null) {
      return _resultsScreen(context);
    }

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            _gameTopBar(context),
            _progressBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  14,
                  18,
                  18,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (!isRushMode)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(3, (index) {
                              return Padding(
                                padding: EdgeInsets.only(
                                  right: index == 2 ? 0 : 6,
                                ),
                                child: Text(
                                  'X',
                                  textScaler: TextScaler.noScaling,
                                  style: TextStyle(
                                    fontSize: 20,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                    color: index < mistakeCount
                                        ? GakujiColors.pinRed
                                        : GakujiColors.softGray,
                                  ),
                                ),
                              );
                            }),
                          ),
                        const Spacer(),
                        Text(
                          'Score  $correctCount',
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.gameScore,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _targetWord(round.visitor),
                    const SizedBox(height: 42),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: FractionallySizedBox(
                            widthFactor: 0.94,
                            alignment: Alignment.topCenter,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                ..._evidenceFieldsForRound(round),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (showingCorrection) ...[
                      const SizedBox(height: 18),
                      _correctionSection(),
                      const SizedBox(height: 18),
                      _primaryButton(
                        label: mistakeCount >= mistakeLimit
                            ? 'VIEW RESULTS'
                            : 'CONTINUE',
                        onTap: continueAfterCorrection,
                      ),
                    ] else ...[
                      const SizedBox(height: 30),
                      Row(
                        children: [
                          Expanded(
                            child: _verdictButton(
                              icon: Icons.close_rounded,
                              semanticLabel: 'Incorrect',
                              fillColor: _incorrectRed,
                              foregroundColor: _incorrectRedOutline,
                              onTap: () => answer(approved: false),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _verdictButton(
                              icon: Icons.check_rounded,
                              semanticLabel: 'Correct',
                              fillColor: _correctGreen,
                              foregroundColor: _correctGreenOutline,
                              onTap: () => answer(approved: true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsScreen(BuildContext context) {
    final mode = selectedMode ?? CrosscheckMode.normal;
    final best = highScores[mode] ?? 0;

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            _simpleTopBar(
              context: context,
              icon: Icons.close_rounded,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                child: Column(
                  children: [
                    const SizedBox(height: 34),
                    Text(
                      'Complete!',
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 42,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.3,
                        color: GakujiColors.darkGray,
                      ),
                    ),
                    const SizedBox(height: 46),
                    Text(
                      'SCORE',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                        color: GakujiColors.mediumGray,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$correctCount',
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 54,
                        height: 0.95,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.8,
                        color: GakujiColors.darkGray,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'High Score $best',
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: GakujiColors.mediumGray,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      decoration: BoxDecoration(
                        color: GakujiColors.warmCard.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: GakujiColors.softBorder,
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        children: [
                          _completionStatRow(
                            label: 'Mode',
                            value: _modeLabel(mode),
                          ),
                          const SizedBox(height: 12),
                          _completionStatRow(
                            label: 'Rounds played',
                            value: '$roundsPlayed',
                          ),
                          const SizedBox(height: 12),
                          _completionStatRow(
                            label: 'Correct checks',
                            value: '$correctCount',
                          ),
                          const SizedBox(height: 12),
                          _completionStatRow(
                            label: 'Incorrect checks',
                            value: '$mistakeCount',
                          ),
                          const SizedBox(height: 12),
                          _completionStatRow(
                            label: 'Best streak',
                            value: '$bestStreak',
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _completionPrimaryButton(
                      label: 'PLAY AGAIN',
                      onTap: restartGame,
                    ),
                    const SizedBox(height: 12),
                    _completionSecondaryButton(
                      label: 'RETURN TO MODES',
                      onTap: _returnToModeSelection,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _completionStatRow({
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
            style: GakujiText.small.copyWith(
              color: GakujiColors.mediumGray,
            ),
          ),
        ),
        Text(
          value,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 16,
            height: 1,
            fontWeight: FontWeight.w800,
            color: GakujiColors.darkGray,
          ),
        ),
      ],
    );
  }

  Widget _completionPrimaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Material(
        color: deckPrimaryColor,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(GakujiRadius.pill),
          onTap: onTap,
          splashColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.medium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _completionSecondaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(GakujiRadius.pill),
          onTap: onTap,
          splashColor: deckPrimaryColor.withValues(alpha: 0.08),
          highlightColor: deckPrimaryColor.withValues(alpha: 0.04),
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                color: deckPrimaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _modeLabel(CrosscheckMode mode) {
    switch (mode) {
      case CrosscheckMode.normal:
        return 'Normal';
      case CrosscheckMode.rush:
        return 'Rush';
      case CrosscheckMode.endless:
        return 'Endless';
    }
  }

  Widget _gameTopBar(BuildContext context) {
    return GakujiTopBar(
      leftIcon: Icons.close_rounded,
      onLeftTap: _returnToModeSelection,
      leftIconColor: GakujiColors.darkGray,
      titleWidget: isLoopingMode
          ? const SizedBox.shrink()
          : Text(
              '${currentIndex + 1}/${gameTerms.length}',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 20,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: GakujiColors.darkGray,
              ),
            ),
      rightIcon: Icons.menu_rounded,
      onRightTap: () => _showOptions(context),
      rightIconColor: GakujiColors.darkGray,
    );
  }

  Widget _simpleTopBar({
    required BuildContext context,
    required IconData icon,
  }) {
    return GakujiTopBar(
      leftIcon: icon,
      onLeftTap: () => Navigator.pop(context),
      leftIconColor: GakujiColors.darkGray,
    );
  }

  Widget _progressBar() {
    final total = gameTerms.isEmpty ? 1 : gameTerms.length;
    final progress = isRushMode
        ? _rushProgress
        : isEndlessMode
            ? 0.0
            : (currentIndex / total).clamp(0.0, 1.0).toDouble();

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
          FractionallySizedBox(
            widthFactor: progress,
            alignment: Alignment.centerLeft,
            child: Container(
              height: 4,
              color: isRushMode ? deckPrimaryColor : GakujiColors.darkGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetWord(Term term) {
    final text = _termDisplayText(term);

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: GakujiText.gameTarget.copyWith(
            fontSize: _termFontSizeFor(text),
          ),
        ),
      ),
    );
  }

  List<Widget> _evidenceFieldsForRound(ImposterRound round) {
    final fields = <Widget>[];
    final correctFile = showingCorrection && correctionRound == round
        ? _correctIdentityFile(round.visitor)
        : null;

    void addField(
      String label,
      String value, {
      String? correctValue,
    }) {
      final displayValue = label == 'Definition'
          ? _primaryDefinition(value)
          : _safeValue(value);
      final displayCorrectValue = correctValue == null
          ? null
          : label == 'Definition'
              ? _primaryDefinition(correctValue)
              : _safeValue(correctValue);
      final correctionValue = !round.isValid &&
              displayCorrectValue != null &&
              _normalized(displayValue) != _normalized(displayCorrectValue)
          ? displayCorrectValue
          : null;

      if (fields.isNotEmpty) {
        fields.add(const SizedBox(height: 22));
      }
      fields.add(
        _evidenceField(
          label: label,
          value: displayValue,
          correctionValue: correctionValue,
        ),
      );
    }

    if (!isRushMode || _rushCheckReading) {
      addField(
        'Reading',
        round.file.reading,
        correctValue: correctFile?.reading,
      );
    }

    if (!isRushMode || _rushCheckDefinition) {
      addField(
        'Definition',
        round.file.definition,
        correctValue: correctFile?.definition,
      );
    }

    if (!isRushMode && _checkPartOfSpeech) {
      addField(
        'Part of Speech',
        round.file.partOfSpeech,
        correctValue: correctFile?.partOfSpeech,
      );
    }

    return fields;
  }

  Widget _evidenceField({
    required String label,
    required String value,
    String? correctionValue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: isRushMode ? 15 : 14,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            color: deckPrimaryColor,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _safeValue(value),
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: isRushMode ? 30 : 26,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: GakujiColors.darkGray,
          ),
        ),
        if (correctionValue != null) ...[
          const SizedBox(height: 8),
          Text(
            'Correct: ${_safeValue(correctionValue)}',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.small.copyWith(
              color: GakujiColors.pinRed,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          height: 1,
          width: double.infinity,
          color: GakujiColors.softBorder,
        ),
      ],
    );
  }

  Widget _correctionSection() {
    final round = correctionRound;
    final userApproved = correctionUserApproved;

    if (round == null || userApproved == null) {
      return const SizedBox.shrink();
    }

    final message = round.isValid
        ? 'Not quite — this entry was correct.'
        : 'Not quite — the corrected field is shown above.';

    return Text(
      message,
      textAlign: TextAlign.center,
      textScaler: TextScaler.noScaling,
      style: GakujiText.small.copyWith(
        color: GakujiColors.pinRed,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
    );
  }

  Widget _verdictButton({
    required IconData icon,
    required String semanticLabel,
    required Color fillColor,
    required Color foregroundColor,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        height: 116,
        child: Material(
          color: fillColor,
          borderRadius: BorderRadius.circular(GakujiRadius.small),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GakujiRadius.small),
              border: Border.all(
                color: foregroundColor,
                width: 2,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              splashColor: foregroundColor.withValues(alpha: 0.12),
              highlightColor: foregroundColor.withValues(alpha: 0.06),
              child: Center(
                child: Icon(
                  icon,
                  size: 68,
                  color: foregroundColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Material(
        color: onTap == null
            ? deckPrimaryColor.withValues(alpha: 0.35)
            : deckPrimaryColor,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.medium.copyWith(
                color: GakujiColors.warmCard,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showOptions(BuildContext context) async {
    final pausedRush = _rushTimerShouldRun;
    if (pausedRush) {
      _pauseRushTimer();
    }

    await showGakujiOptionsSheet(
      context: context,
      title: 'Crosscheck Options',
      sectionsBuilder: (sheetContext) => [
        if (isRushMode)
          GakujiOptionsSheetSection(
            title: 'Fields',
            items: [
              GakujiOptionsSheetItem(
                textIcon: '読',
                label: 'Reading',
                subtitle: _rushCheckReading
                    ? 'Included in Rush rounds'
                    : 'Not included in Rush rounds',
                iconColor: _rushCheckReading
                    ? deckPrimaryColor
                    : GakujiColors.mediumGray,
                onTap: () {
                  if (_rushCheckReading && !_rushCheckDefinition) return;

                  setState(() {
                    _rushCheckReading = !_rushCheckReading;

                    if (currentRound != null) {
                      currentRound = _generateRoundForCurrentIndex();
                      _resetRushRoundTimerForCurrentScore();
                    }
                  });

                  unawaited(_persistRushSettings());
                },
              ),
              GakujiOptionsSheetItem(
                textIcon: '意',
                label: 'Definition',
                subtitle: _rushCheckDefinition
                    ? 'Included in Rush rounds'
                    : 'Not included in Rush rounds',
                iconColor: _rushCheckDefinition
                    ? deckPrimaryColor
                    : GakujiColors.mediumGray,
                onTap: () {
                  if (_rushCheckDefinition && !_rushCheckReading) return;

                  setState(() {
                    _rushCheckDefinition = !_rushCheckDefinition;

                    if (currentRound != null) {
                      currentRound = _generateRoundForCurrentIndex();
                      _resetRushRoundTimerForCurrentScore();
                    }
                  });

                  unawaited(_persistRushSettings());
                },
              ),
            ],
          ),
        if (!isRushMode)
          GakujiOptionsSheetSection(
            title: 'Fields',
            items: [
              GakujiOptionsSheetItem(
                textIcon: '品',
                label: 'Part of Speech',
                subtitle: _checkPartOfSpeech
                    ? 'Included in rounds'
                    : 'Not included in rounds',
                iconColor: _checkPartOfSpeech
                    ? deckPrimaryColor
                    : GakujiColors.mediumGray,
                onTap: () {
                  setState(() {
                    _checkPartOfSpeech = !_checkPartOfSpeech;
                  });

                  unawaited(_persistPartOfSpeechSetting());
                },
              ),
            ],
          ),
        GakujiOptionsSheetSection(
          title: 'Session',
          items: [
            GakujiOptionsSheetItem(
              icon: Icons.refresh_rounded,
              label: 'Restart Session',
              iconColor: GakujiColors.mediumGray,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(restartGame());
              },
            ),
            GakujiOptionsSheetItem(
              icon: Icons.grid_view_rounded,
              label: 'Return to Modes',
              iconColor: GakujiColors.mediumGray,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _returnToModeSelection();
              },
            ),
            GakujiOptionsSheetItem(
              icon: Icons.close_rounded,
              label: 'Exit Crosscheck',
              iconColor: GakujiColors.mediumGray,
              onTap: () {
                if (_shouldPersistSelectedSession) {
                  unawaited(_saveSessionSnapshot());
                }
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ],
    );

    if (!mounted) return;

    if (pausedRush && _rushTimerShouldRun && _rushTimer == null) {
      _startRushTimer(reset: false);
    }
  }

  IdentityFile _correctIdentityFile(Term term) {
    return IdentityFile(
      reading: _safeValue(term.reading),
      definition: _definitionText(term),
      partOfSpeech: _safeValue(term.partOfSpeech),
    );
  }

  String _termDisplayText(Term term) {
    final kanji = term.kanji.trim();

    if (kanji.isNotEmpty) return kanji;

    return _safeValue(term.reading);
  }

  String _definitionText(Term term) {
    final cardMeaning = term.cardMeaning.trim();

    if (cardMeaning.isNotEmpty) {
      return _primaryDefinition(cardMeaning);
    }

    return _primaryDefinition(term.meaning);
  }

  String _primaryDefinition(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) return '—';

    final definitions = trimmed
        .split(RegExp(r'\s*(?:/|;|\n)\s*'))
        .map((definition) => definition.trim())
        .where((definition) => definition.isNotEmpty)
        .toList(growable: false);

    if (definitions.isEmpty) return trimmed;

    return definitions.first;
  }

  String _safeValue(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) return '—';

    return trimmed;
  }

  String _normalized(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  double _termFontSizeFor(String text) {
    if (text.length >= 9) return 32;
    if (text.length >= 7) return 36;
    if (text.length >= 5) return 40;
    if (text.length >= 3) return 44;

    return 48;
  }
}

class _RushMismatchOption {
  final _RushField field;
  final String value;

  const _RushMismatchOption({
    required this.field,
    required this.value,
  });
}
