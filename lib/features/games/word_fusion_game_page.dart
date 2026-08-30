import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:gakuji/domain/term.dart';
import 'package:gakuji/features/games/models/word_fusion_round.dart';
import 'package:gakuji/data/sync/gakuji_local_preferences.dart';
import 'package:gakuji/features/games/services/word_fusion_round_generator.dart';
import 'package:gakuji/core/widgets/gakuji_domino.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/data/sync/gakuji_session_storage.dart';

class WordFusionGamePage extends StatefulWidget {
  final List<Term> terms;
  final String? deckId;
  final String deckName;
  final Color? accentColor;

  const WordFusionGamePage({
    super.key,
    required this.terms,
    this.deckId,
    required this.deckName,
    this.accentColor,
  });

  @override
  State<WordFusionGamePage> createState() => _WordFusionGamePageState();
}

class _WordFusionGamePageState extends State<WordFusionGamePage> {
  static const Color _incorrectRed = Color(0xFFE06F6F);
  static const Color _incorrectRedFill = Color(0xFFF6A3A3);

  List<WordFusionRound> rounds = const <WordFusionRound>[];
  List<int?> placedChoiceIndexes = <int?>[];

  int currentRoundIndex = 0;
  int correctCount = 0;
  int incorrectCount = 0;
  int skippedCount = 0;
  int highScore = 0;
  bool hasSubmitted = false;
  bool lastAnswerCorrect = false;
  bool sessionComplete = false;

  static const String _highScorePreferenceKey =
      'word_fusion_high_score_v1';
  static const String _sessionType = 'word_fusion';
  static const String _roundsSessionType = 'word_fusion_rounds';

  late int sessionSeed;
  bool isLoadingSession = true;

  WordFusionRound get currentRound => rounds[currentRoundIndex];

  Color get _accentColor =>
      widget.accentColor ?? GakujiColors.writing;

  String get _sessionDeckId => widget.deckId ?? widget.deckName;

  double get sessionProgress {
    if (rounds.isEmpty) return 0;
    final completed = currentRoundIndex + (hasSubmitted ? 1 : 0);
    return (completed / rounds.length).clamp(0.0, 1.0).toDouble();
  }

  int get arcadeScore {
    if (rounds.isEmpty) return 0;
    return ((correctCount / rounds.length) * 10000).round();
  }

  String _formatScore(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
  }

  bool get canFuse {
    return !hasSubmitted &&
        placedChoiceIndexes.isNotEmpty &&
        placedChoiceIndexes.every((choiceIndex) => choiceIndex != null);
  }

  List<String?> get placedKanji {
    return placedChoiceIndexes.map((choiceIndex) {
      if (choiceIndex == null) return null;
      return currentRound.kanjiChoices[choiceIndex];
    }).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _loadHighScore();
    if (!_restoreCachedSession()) {
      _loadOrCreateSession();
    }
  }

  List<String> get _sessionTermIds {
    return widget.terms.map((term) => term.id).toList(growable: false);
  }

  String get _sessionTermSignature {
    var hash = 0x811C9DC5;
    for (final term in widget.terms) {
      for (final value in <String>[
        term.id,
        term.kanji,
        term.reading,
        term.meaning,
        term.cardMeaning,
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
    return '${widget.terms.length}:${hash.toRadixString(16)}';
  }

  int _newSessionSeed() {
    return math.Random().nextInt(0x7fffffff);
  }

  List<WordFusionRound> _buildRoundsForSeed(int seed) {
    return WordFusionRoundGenerator.buildRounds(
      widget.terms,
      random: math.Random(seed),
    );
  }

  bool _restoreCachedSession() {
    if (!GakujiSessionStorage.hasCached(
      sessionType: _sessionType,
      deckId: _sessionDeckId,
    )) {
      return false;
    }

    final state = GakujiSessionStorage.peek(
      sessionType: _sessionType,
      deckId: _sessionDeckId,
    );
    if (state == null) return false;

    final hasCachedRounds = GakujiSessionStorage.hasCached(
      sessionType: _roundsSessionType,
      deckId: _sessionDeckId,
    );
    if (_asInt(state['version']) == 2 && !hasCachedRounds) {
      return false;
    }

    final roundsSnapshot = hasCachedRounds
        ? GakujiSessionStorage.peek(
            sessionType: _roundsSessionType,
            deckId: _sessionDeckId,
          )
        : null;

    return _restoreSession(state, roundsSnapshot: roundsSnapshot);
  }

  Future<void> _loadOrCreateSession() async {
    final snapshots = await GakujiSessionStorage.loadMany(
      sessionTypes: const [_sessionType, _roundsSessionType],
      deckId: _sessionDeckId,
    );

    if (!mounted) return;

    final state = snapshots[_sessionType];
    final roundsSnapshot = snapshots[_roundsSessionType];
    if (state != null &&
        _restoreSession(state, roundsSnapshot: roundsSnapshot)) {
      return;
    }

    _startFreshSession();
  }

  bool _restoreSession(
    Map<String, dynamic> snapshot, {
    Map<String, dynamic>? roundsSnapshot,
  }) {
    final version = _asInt(snapshot['version']);
    if (version == 2) {
      return _restoreFastSession(snapshot, roundsSnapshot: roundsSnapshot);
    }
    if (version == 1) {
      final restored = _restoreLegacySession(snapshot);
      if (restored) {
        unawaited(_saveRoundBlueprint());
        unawaited(_saveSessionSnapshot());
      }
      return restored;
    }
    return false;
  }

  bool _restoreFastSession(
    Map<String, dynamic> snapshot, {
    Map<String, dynamic>? roundsSnapshot,
  }) {
    if (snapshot['termSignature']?.toString() != _sessionTermSignature) {
      return false;
    }

    final seed = _asInt(snapshot['seed']);
    if (seed == null) return false;

    var restoredRounds = _roundsFromBlueprint(
      roundsSnapshot,
      expectedSeed: seed,
    );
    var rebuiltBlueprint = false;

    if (restoredRounds == null || restoredRounds.isEmpty) {
      restoredRounds = _buildRoundsForSeed(seed);
      rebuiltBlueprint = true;
    }
    if (restoredRounds.isEmpty) return false;

    final savedRoundCount = _asInt(snapshot['roundCount']);
    if (savedRoundCount != restoredRounds.length) return false;

    _applyRestoredSession(
      snapshot,
      seed: seed,
      restoredRounds: restoredRounds,
    );

    if (rebuiltBlueprint) {
      unawaited(_saveRoundBlueprint());
    }
    return true;
  }

  bool _restoreLegacySession(Map<String, dynamic> snapshot) {
    final savedTermIds = _stringList(snapshot['termIds']);
    if (!_sameStringLists(savedTermIds, _sessionTermIds)) return false;

    final seed = _asInt(snapshot['seed']);
    if (seed == null) return false;

    final restoredRounds = _buildRoundsForSeed(seed);
    if (restoredRounds.isEmpty) return false;

    final savedRoundCount = _asInt(snapshot['roundCount']);
    if (savedRoundCount != restoredRounds.length) return false;

    _applyRestoredSession(
      snapshot,
      seed: seed,
      restoredRounds: restoredRounds,
    );
    return true;
  }

  void _applyRestoredSession(
    Map<String, dynamic> snapshot, {
    required int seed,
    required List<WordFusionRound> restoredRounds,
  }) {
    final restoredRoundIndex = (_asInt(snapshot['currentRoundIndex']) ?? 0)
        .clamp(0, restoredRounds.length - 1)
        .toInt();
    final restoredHasSubmitted = snapshot['hasSubmitted'] == true;

    setState(() {
      sessionSeed = seed;
      rounds = restoredRounds;
      currentRoundIndex = restoredRoundIndex;
      correctCount = _asInt(snapshot['correctCount']) ?? 0;
      incorrectCount = _asInt(snapshot['incorrectCount']) ?? 0;
      skippedCount = _asInt(snapshot['skippedCount']) ?? 0;
      hasSubmitted = restoredHasSubmitted;
      lastAnswerCorrect = snapshot['lastAnswerCorrect'] == true;
      sessionComplete = snapshot['sessionComplete'] == true;
      placedChoiceIndexes = _emptyPlacementForCurrentRound();
      if (restoredHasSubmitted) {
        final savedPlacement = _nullableIntList(snapshot['placedChoiceIndexes']);
        if (savedPlacement.length == placedChoiceIndexes.length) {
          placedChoiceIndexes = savedPlacement;
        }
      }
      isLoadingSession = false;
    });
  }

  void _startFreshSession() {
    final seed = _newSessionSeed();
    final freshRounds = _buildRoundsForSeed(seed);

    setState(() {
      sessionSeed = seed;
      rounds = freshRounds;
      currentRoundIndex = 0;
      correctCount = 0;
      incorrectCount = 0;
      skippedCount = 0;
      hasSubmitted = false;
      lastAnswerCorrect = false;
      sessionComplete = false;
      placedChoiceIndexes = _emptyPlacementForCurrentRound();
      isLoadingSession = false;
    });

    if (freshRounds.isEmpty) {
      unawaited(_clearSessionSnapshot());
    } else {
      unawaited(_saveRoundBlueprint());
      unawaited(_saveSessionSnapshot());
    }
  }

  Future<void> _saveSessionSnapshot() {
    if (isLoadingSession || rounds.isEmpty) return Future<void>.value();

    return GakujiSessionStorage.save(
      sessionType: _sessionType,
      deckId: _sessionDeckId,
      snapshot: <String, dynamic>{
        'version': 2,
        'termSignature': _sessionTermSignature,
        'seed': sessionSeed,
        'roundCount': rounds.length,
        'currentRoundIndex': currentRoundIndex,
        'correctCount': correctCount,
        'incorrectCount': incorrectCount,
        'skippedCount': skippedCount,
        'hasSubmitted': hasSubmitted,
        'lastAnswerCorrect': lastAnswerCorrect,
        'sessionComplete': sessionComplete,
        if (hasSubmitted) 'placedChoiceIndexes': placedChoiceIndexes,
      },
    );
  }

  Future<void> _saveRoundBlueprint() {
    if (isLoadingSession || rounds.isEmpty) return Future<void>.value();

    return GakujiSessionStorage.save(
      sessionType: _roundsSessionType,
      deckId: _sessionDeckId,
      snapshot: <String, dynamic>{
        'version': 1,
        'termSignature': _sessionTermSignature,
        'seed': sessionSeed,
        'rounds': rounds.map(_roundToSnapshot).toList(growable: false),
      },
    );
  }

  Future<void> _clearSessionSnapshot() async {
    await Future.wait<void>([
      GakujiSessionStorage.clear(
        sessionType: _sessionType,
        deckId: _sessionDeckId,
      ),
      GakujiSessionStorage.clear(
        sessionType: _roundsSessionType,
        deckId: _sessionDeckId,
      ),
    ]);
  }

  Map<String, dynamic> _roundToSnapshot(WordFusionRound round) {
    return <String, dynamic>{
      'termId': round.termId,
      'word': round.word,
      'reading': round.reading,
      'definition': round.definition,
      'requiredKanji': round.requiredKanji,
      'kanjiChoices': round.kanjiChoices,
    };
  }

  List<WordFusionRound>? _roundsFromBlueprint(
    Map<String, dynamic>? snapshot, {
    required int expectedSeed,
  }) {
    if (snapshot == null || _asInt(snapshot['version']) != 1) return null;
    if (snapshot['termSignature']?.toString() != _sessionTermSignature ||
        _asInt(snapshot['seed']) != expectedSeed) {
      return null;
    }

    final rawRounds = snapshot['rounds'];
    if (rawRounds is! List || rawRounds.isEmpty) return null;

    final restored = <WordFusionRound>[];
    for (final rawRound in rawRounds) {
      if (rawRound is! Map) return null;
      final termId = rawRound['termId']?.toString() ?? '';
      final word = rawRound['word']?.toString() ?? '';
      final requiredKanji = _stringList(rawRound['requiredKanji']);
      final kanjiChoices = _stringList(rawRound['kanjiChoices']);
      if (termId.isEmpty ||
          word.isEmpty ||
          requiredKanji.isEmpty ||
          kanjiChoices.isEmpty) {
        return null;
      }

      restored.add(
        WordFusionRound(
          termId: termId,
          word: word,
          reading: rawRound['reading']?.toString() ?? '',
          definition: rawRound['definition']?.toString() ?? '',
          requiredKanji: List<String>.unmodifiable(requiredKanji),
          kanjiChoices: List<String>.unmodifiable(kanjiChoices),
        ),
      );
    }

    return List<WordFusionRound>.unmodifiable(restored);
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

  static List<int?> _nullableIntList(dynamic value) {
    if (value is! List) return <int?>[];
    return value.map((item) => item == null ? null : _asInt(item)).toList();
  }

  static bool _sameStringLists(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  Future<void> _loadHighScore() async {
    final storedHighScore =
        await GakujiLocalPreferences.loadInt(_highScorePreferenceKey) ?? 0;

    if (!mounted || storedHighScore <= highScore) return;

    setState(() {
      highScore = storedHighScore;
    });
  }

  Future<void> _recordHighScoreIfNeeded() async {
    if (rounds.isEmpty) return;

    final completedScore = arcadeScore;
    if (completedScore <= highScore) return;

    setState(() {
      highScore = completedScore;
    });

    await GakujiLocalPreferences.saveInt(
      _highScorePreferenceKey,
      completedScore,
    );
  }

  List<int?> _emptyPlacementForCurrentRound() {
    if (rounds.isEmpty) return <int?>[];
    return List<int?>.filled(currentRound.requiredKanji.length, null);
  }

  void _placeChoiceInSlot(int choiceIndex, int slotIndex) {
    if (hasSubmitted ||
        choiceIndex < 0 ||
        choiceIndex >= currentRound.kanjiChoices.length ||
        slotIndex < 0 ||
        slotIndex >= placedChoiceIndexes.length) {
      return;
    }

    setState(() {
      final previousSlot = placedChoiceIndexes.indexOf(choiceIndex);
      if (previousSlot != -1) {
        placedChoiceIndexes[previousSlot] = null;
      }
      placedChoiceIndexes[slotIndex] = choiceIndex;
    });
  }

  void _placeChoiceInFirstEmptySlot(int choiceIndex) {
    if (hasSubmitted || placedChoiceIndexes.contains(choiceIndex)) return;

    final emptySlot = placedChoiceIndexes.indexOf(null);
    if (emptySlot == -1) return;

    _placeChoiceInSlot(choiceIndex, emptySlot);
  }

  void _removeFromSlot(int slotIndex) {
    if (hasSubmitted ||
        slotIndex < 0 ||
        slotIndex >= placedChoiceIndexes.length) {
      return;
    }

    setState(() {
      placedChoiceIndexes[slotIndex] = null;
    });
  }

  void _fuse() {
    if (!canFuse) return;

    final answer = placedKanji.whereType<String>().toList(growable: false);
    final correct = _orderedListsMatch(answer, currentRound.requiredKanji);

    setState(() {
      hasSubmitted = true;
      lastAnswerCorrect = correct;
      if (correct) {
        correctCount++;
      } else {
        incorrectCount++;
      }
    });

    unawaited(_saveSessionSnapshot());
  }

  bool _orderedListsMatch(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  void _continue() {
    if (!hasSubmitted) return;

    if (currentRoundIndex >= rounds.length - 1) {
      setState(() {
        sessionComplete = true;
      });
      unawaited(_saveSessionSnapshot());
      _recordHighScoreIfNeeded();
      return;
    }

    setState(() {
      currentRoundIndex++;
      placedChoiceIndexes = _emptyPlacementForCurrentRound();
      hasSubmitted = false;
      lastAnswerCorrect = false;
    });

    unawaited(_saveSessionSnapshot());
  }

  void _skipRound() {
    if (hasSubmitted) return;

    final completingSession = currentRoundIndex >= rounds.length - 1;

    setState(() {
      skippedCount++;

      if (completingSession) {
        sessionComplete = true;
        return;
      }

      currentRoundIndex++;
      placedChoiceIndexes = _emptyPlacementForCurrentRound();
      lastAnswerCorrect = false;
    });

    unawaited(_saveSessionSnapshot());

    if (completingSession) {
      _recordHighScoreIfNeeded();
    }
  }

  void _restart() {
    final seed = _newSessionSeed();

    setState(() {
      sessionSeed = seed;
      rounds = _buildRoundsForSeed(seed);
      currentRoundIndex = 0;
      correctCount = 0;
      incorrectCount = 0;
      skippedCount = 0;
      hasSubmitted = false;
      lastAnswerCorrect = false;
      sessionComplete = false;
      placedChoiceIndexes = _emptyPlacementForCurrentRound();
    });

    unawaited(_saveRoundBlueprint());
    unawaited(_saveSessionSnapshot());
  }

  Future<void> _showOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: GakujiColors.warmBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: GakujiColors.softBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 20),
                _optionRow(
                  icon: Icons.refresh_rounded,
                  label: 'Restart Session',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _restart();
                  },
                ),
                const SizedBox(height: 8),
                _optionRow(
                  icon: Icons.close_rounded,
                  label: 'Exit Word Fusion',
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
          splashColor: _accentColor.withValues(alpha: 0.08),
          highlightColor: _accentColor.withValues(alpha: 0.04),
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

  @override
  Widget build(BuildContext context) {
    if (isLoadingSession) {
      return Scaffold(
        backgroundColor: GakujiColors.warmBackground,
        body: Center(
          child: CircularProgressIndicator(color: _accentColor),
        ),
      );
    }

    if (rounds.isEmpty) return _emptyScreen();
    if (sessionComplete) return _completeScreen();

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            _progressBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: hasSubmitted
                    ? _resultScreen(
                        key: ValueKey('result_$currentRoundIndex'),
                      )
                    : _playScreen(
                        key: ValueKey('play_$currentRoundIndex'),
                      ),
              ),
            ),
          ],
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
      title: '${currentRoundIndex + 1}/${rounds.length}',
      titleStyle: TextStyle(
        fontSize: 20,
        height: 1,
        fontWeight: FontWeight.w700,
        color: GakujiColors.darkGray,
      ),
      rightIcon: Icons.menu_rounded,
      rightIconSize: GakujiTopBar.iconSize,
      rightIconColor: GakujiColors.darkGray,
      onRightTap: _showOptions,
    );
  }

  Widget _progressBar() {
    return SizedBox(
      height: 4,
      width: double.infinity,
      child: Stack(
        children: [
          Container(color: GakujiColors.softBorder),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: sessionProgress),
            duration: const Duration(milliseconds: 240),
            builder: (context, value, child) {
              return FractionallySizedBox(
                widthFactor: value,
                alignment: Alignment.centerLeft,
                child: Container(color: GakujiColors.darkGray),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _playScreen({required Key key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Column(
        children: [
          _scoreRow(showSkip: true),
          const SizedBox(height: 14),
          _prompt(),
          const SizedBox(height: 26),
          _answerSlots(interactive: true),
          const SizedBox(height: 28),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: _choiceGrid(),
            ),
          ),
          _primaryButton(
            label: 'FUSE',
            enabled: canFuse,
            onTap: _fuse,
          ),
        ],
      ),
    );
  }

  Widget _scoreRow({bool showSkip = false}) {
    return Row(
      children: [
        if (showSkip)
          SizedBox(
            height: 34,
            child: Material(
              color: GakujiColors.warmCard,
              borderRadius: BorderRadius.circular(GakujiRadius.pill),
              child: InkWell(
                onTap: hasSubmitted ? null : _skipRound,
                borderRadius: BorderRadius.circular(GakujiRadius.pill),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(GakujiRadius.pill),
                    border: Border.all(
                      color: _accentColor.withValues(alpha: 0.34),
                      width: 1.2,
                    ),
                  ),
                  child: Text(
                    'SKIP',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: _accentColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        Text(
          'Score  ${_formatScore(arcadeScore)}',
          textScaler: TextScaler.noScaling,
          style: GakujiText.gameScore,
        ),
      ],
    );
  }

  TextStyle _definitionStyleForWidth(double maxWidth) {
    final baseStyle = GakujiText.gameDefinition;
    final baseFontSize = baseStyle.fontSize ?? 16;
    const minimumFontSize = 11.0;

    var fontSize = baseFontSize;
    while (fontSize > minimumFontSize) {
      final painter = TextPainter(
        text: TextSpan(
          text: currentRound.definition,
          style: baseStyle.copyWith(fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: maxWidth);

      if (!painter.didExceedMaxLines) {
        break;
      }
      fontSize -= 0.5;
    }

    return baseStyle.copyWith(fontSize: fontSize);
  }

  Widget _prompt() {
    return Column(
      children: [
        Text(
          currentRound.reading,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: GakujiFonts.japanese,
            fontSize: 27,
            height: 1.05,
            fontWeight: FontWeight.w700,
            color: GakujiColors.darkGray,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            return Text(
              currentRound.definition,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: _definitionStyleForWidth(constraints.maxWidth),
            );
          },
        ),
      ],
    );
  }

  Widget _answerSlots({
    required bool interactive,
    List<String?>? displayKanji,
    Color? outlineColor,
    bool compact = false,
  }) {
    final slotKanji = displayKanji ?? placedKanji;

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = slotKanji.length;
        final gap = count >= 5 ? 6.0 : 9.0;
        final availableWidth = constraints.maxWidth - gap * (count - 1);
        final slotWidth = compact
            ? 42.0
            : (availableWidth / count).clamp(42.0, 68.0).toDouble();
        final slotHeight = compact ? 54.0 : slotWidth + 12;

        final row = Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(count, (slotIndex) {
              final kanji = slotKanji[slotIndex];
              final slot = _wordSlot(
                kanji: kanji,
                width: slotWidth,
                height: slotHeight,
                outlineColor: outlineColor,
                onTap: interactive ? () => _removeFromSlot(slotIndex) : null,
              );

              final child = interactive
                  ? DragTarget<int>(
                      onWillAcceptWithDetails: (_) => !hasSubmitted,
                      onAcceptWithDetails: (details) {
                        _placeChoiceInSlot(details.data, slotIndex);
                      },
                      builder: (context, candidates, rejected) {
                        return AnimatedScale(
                          scale: candidates.isNotEmpty ? 1.05 : 1,
                          duration: const Duration(milliseconds: 120),
                          child: slot,
                        );
                      },
                    )
                  : slot;

            return Padding(
              padding: EdgeInsets.only(
                right: slotIndex == count - 1 ? 0 : gap,
              ),
              child: child,
            );
          }),
        );

        if (compact) {
          return SizedBox(
            width: constraints.maxWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: row,
            ),
          );
        }

        return Center(child: row);
      },
    );
  }

  Widget _wordSlot({
    required String? kanji,
    required double width,
    required double height,
    required Color? outlineColor,
    required VoidCallback? onTap,
  }) {
    final isFilled = kanji != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isFilled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isFilled ? GakujiColors.whiteCard : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: outlineColor ?? GakujiColors.softBorder,
            width: outlineColor == null ? 1.8 : 2.5,
          ),
          boxShadow: isFilled ? [GakujiShadows.soft] : const [],
        ),
        child: Center(
          child: isFilled
              ? Text(
                  kanji,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: GakujiFonts.japanese,
                    fontSize:
                        (width * 0.57).clamp(25.0, 38.0).toDouble(),
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: GakujiColors.darkGray,
                  ),
                )
              : Container(
                  width: width * 0.22,
                  height: 3,
                  decoration: BoxDecoration(
                    color: GakujiColors.softBorder,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _choiceGrid() {
    final choices = currentRound.kanjiChoices;
    final rows = <List<int>>[];

    for (var index = 0; index < choices.length; index += 5) {
      rows.add(
        List<int>.generate(
          (choices.length - index).clamp(0, 5).toInt(),
          (offset) => index + offset,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var itemIndex = 0;
                  itemIndex < rows[rowIndex].length;
                  itemIndex++) ...[
                _choiceTile(rows[rowIndex][itemIndex]),
                if (itemIndex < rows[rowIndex].length - 1)
                  const SizedBox(width: 11),
              ],
            ],
          ),
          if (rowIndex < rows.length - 1) const SizedBox(height: 13),
        ],
      ],
    );
  }

  Widget _choiceTile(int choiceIndex) {
    final kanji = currentRound.kanjiChoices[choiceIndex];
    final isUsed = placedChoiceIndexes.contains(choiceIndex);

    final tile = _choiceTileSurface(kanji: kanji, invisible: isUsed);

    if (isUsed) return tile;

    return Draggable<int>(
      data: choiceIndex,
      feedback: Material(
        color: Colors.transparent,
        child: _choiceTileSurface(kanji: kanji, dragging: true),
      ),
      childWhenDragging: _choiceTileSurface(kanji: kanji, invisible: true),
      child: GestureDetector(
        onTap: () => _placeChoiceInFirstEmptySlot(choiceIndex),
        child: tile,
      ),
    );
  }

  Widget _choiceTileSurface({
    required String kanji,
    bool invisible = false,
    bool dragging = false,
  }) {
    return GakujiDomino(
      text: kanji,
      invisible: invisible,
      dragging: dragging,
    );
  }

  Widget _resultScreen({required Key key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
      child: Column(
        children: [
          _scoreRow(),
          const SizedBox(height: 14),
          _prompt(),
          const SizedBox(height: 25),
          if (lastAnswerCorrect)
            _successfulResult()
          else
            _failedResult(),
          const Spacer(),
          _primaryButton(
            label: 'CONTINUE',
            enabled: true,
            onTap: _continue,
          ),
        ],
      ),
    );
  }

  Widget _successfulResult() {
    return Column(
      children: [
        _resultCard(
          label: 'Your Word',
          child: _answerSlots(
            interactive: false,
            outlineColor: _accentColor,
            compact: true,
          ),
          outlineColor: _accentColor,
        ),
        const SizedBox(height: 15),
        _statusPill(
          label: 'Successful fusion',
          color: _accentColor,
          fill: _accentColor.withValues(alpha: 0.10),
        ),
        const SizedBox(height: 25),
        Divider(color: GakujiColors.warmDivider),
        const SizedBox(height: 20),
        Text(
          'Correct!',
          textScaler: TextScaler.noScaling,
          style: GakujiText.medium.copyWith(
            color: _accentColor,
          ),
        ),
        const SizedBox(height: 10),
        _completedWordText(currentRound.word),
      ],
    );
  }

  Widget _failedResult() {
    final correctKanji = currentRound.requiredKanji
        .map<String?>((kanji) => kanji)
        .toList(growable: false);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _resultCard(
                label: 'Your Word',
                child: _answerSlots(
                  interactive: false,
                  outlineColor: _incorrectRed,
                  compact: true,
                ),
                outlineColor: _incorrectRed,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _resultCard(
                label: 'Correct Word',
                child: _answerSlots(
                  interactive: false,
                  displayKanji: correctKanji,
                  outlineColor: _accentColor,
                  compact: true,
                ),
                outlineColor: _accentColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        _statusPill(
          label: 'Fusion failed',
          color: _incorrectRed,
          fill: _incorrectRedFill.withValues(alpha: 0.28),
        ),
        const SizedBox(height: 24),
        Divider(color: GakujiColors.warmDivider),
        const SizedBox(height: 18),
        Text(
          'Correct Answer',
          textScaler: TextScaler.noScaling,
          style: GakujiText.medium.copyWith(
            color: GakujiColors.mediumGray,
          ),
        ),
        const SizedBox(height: 10),
        _completedWordText(currentRound.word),
      ],
    );
  }

  Widget _resultCard({
    required String label,
    required Widget child,
    required Color outlineColor,
  }) {
    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 18),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: outlineColor, width: 3),
      ),
      child: Column(
        children: [
          Text(
            label,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 15,
              height: 1,
              fontWeight: FontWeight.w700,
              color: outlineColor,
            ),
          ),
          const Spacer(),
          child,
          const Spacer(),
        ],
      ),
    );
  }

  Widget _statusPill({
    required String label,
    required Color color,
    required Color fill,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
      ),
      child: Text(
        label,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 15,
          height: 1,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _completedWordText(String word) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        word,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: GakujiFonts.japanese,
          fontSize: 58,
          height: 1,
          fontWeight: FontWeight.w700,
          color: GakujiColors.darkGray,
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Material(
        color: enabled
            ? _accentColor
            : GakujiColors.softBorder,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.medium.copyWith(
                color: enabled ? Colors.white : GakujiColors.mediumGray,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _completeScreen() {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            GakujiTopBar(
              leftIcon: GakujiTopBar.backIcon,
              leftIconSize: GakujiTopBar.backIconSize,
              leftIconColor: GakujiColors.darkGray,
              onLeftTap: () => Navigator.pop(context),
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
                      _formatScore(arcadeScore),
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
                      'High Score ${_formatScore(highScore)}',
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
                            label: 'Rounds played',
                            value: rounds.length,
                          ),
                          const SizedBox(height: 12),
                          _completionStatRow(
                            label: 'Correct words',
                            value: correctCount,
                          ),
                          const SizedBox(height: 12),
                          _completionStatRow(
                            label: 'Incorrect words',
                            value: incorrectCount,
                          ),
                          if (skippedCount > 0) ...[
                            const SizedBox(height: 12),
                            _completionStatRow(
                              label: 'Skipped',
                              value: skippedCount,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Spacer(),
                    _primaryButton(
                      label: 'PLAY AGAIN',
                      enabled: true,
                      onTap: _restart,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: Material(
                        color: GakujiColors.warmCard,
                        borderRadius:
                            BorderRadius.circular(GakujiRadius.pill),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(GakujiRadius.pill),
                          onTap: () async {
                            await _clearSessionSnapshot();
                            if (!mounted) return;
                            Navigator.pop(context);
                          },
                          child: Center(
                            child: Text(
                              'DONE',
                              textScaler: TextScaler.noScaling,
                              style: GakujiText.small.copyWith(
                                color: _accentColor,
                              ),
                            ),
                          ),
                        ),
                      ),
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
    required int value,
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
          '$value',
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

  Widget _emptyScreen() {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            GakujiTopBar(
              leftIcon: GakujiTopBar.backIcon,
              leftIconSize: GakujiTopBar.backIconSize,
              leftIconColor: GakujiColors.darkGray,
              onLeftTap: () => Navigator.pop(context),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    'Word Fusion needs at least one word written entirely with 2–6 kanji.',
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.small.copyWith(
                      color: GakujiColors.mediumGray,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
