import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';
import '../models/imposter_round.dart';
import '../models/term.dart';
import '../services/imposter_round_generator.dart';
import '../widgets/gakuji_styles.dart';

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
  static const Duration _rushRoundDuration = Duration(seconds: 5);
  static const Duration _rushTickInterval = Duration(milliseconds: 50);

  // Match the Study page's correct/incorrect feedback palette.
  static const Color _incorrectRed = Color(0xFFF6A3A3);
  static const Color _incorrectRedOutline = Color(0xFFE06F6F);
  static const Color _correctGreen = Color(0xFFC5E7A5);
  static const Color _correctGreenOutline = Color(0xFF8DBB66);

  late final List<Term> gameTerms;

  final ImposterRoundGenerator _generator = ImposterRoundGenerator();
  final math.Random _random = math.Random();

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
  int _rushRemainingMilliseconds = _rushRoundDuration.inMilliseconds;
  bool _rushTimedOut = false;
  bool _rushCheckReading = true;
  bool _rushCheckDefinition = true;

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
    return (_rushRemainingMilliseconds / _rushRoundDuration.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }


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
  }

  @override
  void dispose() {
    _cancelRushTimer();
    super.dispose();
  }

  Future<void> _loadHighScores() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      for (final mode in CrosscheckMode.values) {
        highScores[mode] = prefs.getInt(_highScoreKey(mode)) ?? 0;
      }
    });
  }

  Future<void> _loadRushSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedReading = prefs.getBool('crosscheck_rush_check_reading_v1');
    final savedDefinition = prefs.getBool('crosscheck_rush_check_definition_v1');

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
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('crosscheck_rush_check_reading_v1', _rushCheckReading),
      prefs.setBool('crosscheck_rush_check_definition_v1', _rushCheckDefinition),
    ]);
  }

  String _highScoreKey(CrosscheckMode mode) {
    return 'crosscheck_high_score_v1_${widget.deck.id}_${mode.name}';
  }

  Future<void> _persistHighScore(CrosscheckMode mode, int score) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_highScoreKey(mode), score);
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

  void startGame(CrosscheckMode mode) {
    if (gameTerms.isEmpty) return;

    _cancelRushTimer();
    gameTerms.shuffle();

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
      _rushTimedOut = false;
      _rushRemainingMilliseconds = _rushRoundDuration.inMilliseconds;
      currentRound = _generateRoundForCurrentIndex();
    });

    if (mode == CrosscheckMode.rush) {
      _startRushTimer(reset: true);
    }
  }

  void _startRushTimer({required bool reset}) {
    _cancelRushTimer();

    if (!_rushTimerShouldRun) return;

    if (reset) {
      _rushRemainingMilliseconds = _rushRoundDuration.inMilliseconds;
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
          .clamp(0, _rushRoundDuration.inMilliseconds)
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
      _rushTimedOut = true;
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
        _rushTimedOut = false;

        if (streak > bestStreak) {
          bestStreak = streak;
        }

        _advanceToNextRound();
      });

      _recordHighScoreIfNeeded();

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
  }

  void continueAfterCorrection() {
    if (!showingCorrection) return;

    setState(() {
      showingCorrection = false;
      correctionRound = null;
      correctionUserApproved = null;
      _advanceToNextRound();
    });
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

  void restartGame() {
    startGame(selectedMode ?? CrosscheckMode.normal);
  }

  void _returnToModeSelection() {
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
      _rushTimedOut = false;
      _rushRemainingMilliseconds = _rushRoundDuration.inMilliseconds;
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
                            description: '5 seconds • $_rushFieldLabel • Sudden death',
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
    final enabled = gameTerms.isNotEmpty;
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
            onTap: enabled ? () => startGame(mode) : null,
            splashColor: Colors.white.withOpacity(0.12),
            highlightColor: Colors.white.withOpacity(0.06),
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
                          style: GakujiText.small.copyWith(
                            color: GakujiColors.mediumGray,
                            fontWeight: FontWeight.w700,
                          ),
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
                              label: 'Incorrect',
                              fillColor: _incorrectRed,
                              foregroundColor: _incorrectRedOutline,
                              onTap: () => answer(approved: false),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _verdictButton(
                              label: 'Correct',
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
                        color: GakujiColors.warmCard.withOpacity(0.42),
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
          splashColor: Colors.white.withOpacity(0.12),
          highlightColor: Colors.white.withOpacity(0.06),
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
          splashColor: deckPrimaryColor.withOpacity(0.08),
          highlightColor: deckPrimaryColor.withOpacity(0.04),
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
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
        child: Row(
          children: [
            _topIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: _returnToModeSelection,
            ),
            Expanded(
              child: Center(
                child: isLoopingMode
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
              ),
            ),
            _topIconButton(
              icon: Icons.more_horiz_rounded,
              onTap: () => _showOptions(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _simpleTopBar({
    required BuildContext context,
    required IconData icon,
  }) {
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
        child: Row(
          children: [
            _topIconButton(
              icon: icon,
              onTap: () => Navigator.pop(context),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _topIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: deckPrimaryColor.withOpacity(0.08),
        highlightColor: deckPrimaryColor.withOpacity(0.04),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 34,
            color: GakujiColors.darkGray,
          ),
        ),
      ),
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
          style: TextStyle(
            fontSize: _termFontSizeFor(text),
            height: 1,
            fontWeight: FontWeight.w600,
            color: GakujiColors.darkGray,
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

    if (!isRushMode) {
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

  List<_CrosscheckMismatch> _mismatchedFields({
    required IdentityFile shown,
    required IdentityFile correct,
  }) {
    final mismatches = <_CrosscheckMismatch>[];

    if ((!isRushMode || _rushCheckReading) &&
        _normalized(shown.reading) != _normalized(correct.reading)) {
      mismatches.add(
        _CrosscheckMismatch(
          label: 'Reading',
          correctValue: correct.reading,
        ),
      );
    }

    if ((!isRushMode || _rushCheckDefinition) &&
        _normalized(shown.definition) != _normalized(correct.definition)) {
      mismatches.add(
        _CrosscheckMismatch(
          label: 'Definition',
          correctValue: correct.definition,
        ),
      );
    }

    if (!isRushMode &&
        _normalized(shown.partOfSpeech) !=
            _normalized(correct.partOfSpeech)) {
      mismatches.add(
        _CrosscheckMismatch(
          label: 'Part of Speech',
          correctValue: correct.partOfSpeech,
        ),
      );
    }

    if (mismatches.isEmpty) {
      mismatches.add(
        _CrosscheckMismatch(
          label: 'Correct information',
          correctValue: _correctInformationSummary(correct),
        ),
      );
    }

    return mismatches;
  }

  Widget _correctionLine({
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
            style: GakujiText.small.copyWith(
              color: GakujiColors.mediumGray,
            ),
          ),
        ),
        Expanded(
          child: Text(
            _safeValue(value),
            textScaler: TextScaler.noScaling,
            style: GakujiText.small.copyWith(
              color: GakujiColors.darkGray,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _verdictButton({
    required String label,
    required Color fillColor,
    required Color foregroundColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
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
            splashColor: foregroundColor.withOpacity(0.12),
            highlightColor: foregroundColor.withOpacity(0.06),
            child: Center(
              child: Text(
                label,
                textScaler: TextScaler.noScaling,
                style: GakujiText.medium.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w800,
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
            ? deckPrimaryColor.withOpacity(0.35)
            : deckPrimaryColor,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white.withOpacity(0.12),
          highlightColor: Colors.white.withOpacity(0.06),
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

  Widget _secondaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Material(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: deckPrimaryColor.withOpacity(0.08),
          highlightColor: deckPrimaryColor.withOpacity(0.04),
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.medium.copyWith(
                color: deckPrimaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          textScaler: TextScaler.noScaling,
          style: GakujiText.small.copyWith(
            color: GakujiColors.mediumGray,
          ),
        ),
        const Spacer(),
        Text(
          value,
          textScaler: TextScaler.noScaling,
          style: GakujiText.medium.copyWith(
            color: GakujiColors.darkGray,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  String _validRoundSummary(Term term) {
    final word = _termDisplayText(term);

    if (!isRushMode) {
      return 'The reading, definition, and part of speech all match $word.';
    }

    if (_rushCheckReading && _rushCheckDefinition) {
      return 'The reading and definition both match $word.';
    }

    if (_rushCheckReading) {
      return 'The reading matches $word.';
    }

    return 'The definition matches $word.';
  }

  String _correctInformationSummary(IdentityFile correct) {
    if (!isRushMode) {
      return '${correct.reading} • ${correct.definition} • ${correct.partOfSpeech}';
    }

    final values = <String>[];
    if (_rushCheckReading) values.add(correct.reading);
    if (_rushCheckDefinition) values.add(correct.definition);
    return values.join(' • ');
  }

  Widget _rushToggleRow({
    required String label,
    required bool value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: GakujiColors.warmCard,
      borderRadius: BorderRadius.circular(GakujiRadius.small),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: deckPrimaryColor.withOpacity(0.08),
        highlightColor: deckPrimaryColor.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.medium.copyWith(
                    color: GakujiColors.darkGray,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                width: 48,
                height: 28,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: value ? deckPrimaryColor : GakujiColors.softBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Align(
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: GakujiColors.warmCard,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
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

    var checkReading = _rushCheckReading;
    var checkDefinition = _rushCheckDefinition;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: GakujiColors.warmBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void applyRushSettings() {
              setState(() {
                _rushCheckReading = checkReading;
                _rushCheckDefinition = checkDefinition;

                if (isRushMode && currentRound != null) {
                  currentRound = _generateRoundForCurrentIndex();
                  _rushRemainingMilliseconds =
                      _rushRoundDuration.inMilliseconds;
                  _rushTimedOut = false;
                }
              });

              unawaited(_persistRushSettings());
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: GakujiColors.softBorder,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (isRushMode) ...[
                      Text(
                        'Rush Fields',
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.small.copyWith(
                          color: GakujiColors.mediumGray,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _rushToggleRow(
                        label: 'Reading',
                        value: checkReading,
                        onTap: () {
                          if (checkReading && !checkDefinition) return;
                          setSheetState(() {
                            checkReading = !checkReading;
                          });
                          applyRushSettings();
                        },
                      ),
                      const SizedBox(height: 8),
                      _rushToggleRow(
                        label: 'Definition',
                        value: checkDefinition,
                        onTap: () {
                          if (checkDefinition && !checkReading) return;
                          setSheetState(() {
                            checkDefinition = !checkDefinition;
                          });
                          applyRushSettings();
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    _optionRow(
                      icon: Icons.refresh_rounded,
                      label: 'Restart Session',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        restartGame();
                      },
                    ),
                    const SizedBox(height: 8),
                    _optionRow(
                      icon: Icons.grid_view_rounded,
                      label: 'Return to Modes',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _returnToModeSelection();
                      },
                    ),
                    const SizedBox(height: 8),
                    _optionRow(
                      icon: Icons.close_rounded,
                      label: 'Exit Crosscheck',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;

    if (pausedRush && _rushTimerShouldRun && _rushTimer == null) {
      _startRushTimer(reset: false);
    }
  }

  Widget _optionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 52,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: deckPrimaryColor.withOpacity(0.08),
          highlightColor: deckPrimaryColor.withOpacity(0.04),
          child: Row(
            children: [
              Icon(
                icon,
                size: 25,
                color: GakujiColors.mediumGray,
              ),
              const SizedBox(width: 14),
              Text(
                label,
                textScaler: TextScaler.noScaling,
                style: GakujiText.small.copyWith(
                  color: GakujiColors.darkGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    if (text.length >= 9) return 34;
    if (text.length >= 7) return 38;
    if (text.length >= 5) return 42;
    if (text.length >= 3) return 46;

    return 52;
  }
}

class _CrosscheckMismatch {
  final String label;
  final String correctValue;

  const _CrosscheckMismatch({
    required this.label,
    required this.correctValue,
  });
}

class _RushMismatchOption {
  final _RushField field;
  final String value;

  const _RushMismatchOption({
    required this.field,
    required this.value,
  });
}
