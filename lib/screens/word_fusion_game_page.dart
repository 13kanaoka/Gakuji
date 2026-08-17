import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/term.dart';
import '../models/word_fusion_round.dart';
import '../services/word_fusion_round_generator.dart';
import '../widgets/gakuji_domino.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';

class WordFusionGamePage extends StatefulWidget {
  final List<Term> terms;
  final String deckName;
  final Color? accentColor;

  const WordFusionGamePage({
    super.key,
    required this.terms,
    required this.deckName,
    this.accentColor,
  });

  @override
  State<WordFusionGamePage> createState() => _WordFusionGamePageState();
}

class _WordFusionGamePageState extends State<WordFusionGamePage> {
  static const Color _incorrectRed = Color(0xFFE06F6F);
  static const Color _incorrectRedFill = Color(0xFFF6A3A3);

  late List<WordFusionRound> rounds;
  late List<int?> placedChoiceIndexes;

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

  WordFusionRound get currentRound => rounds[currentRoundIndex];

  Color get _accentColor =>
      widget.accentColor ?? GakujiColors.writing;

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
    rounds = WordFusionRoundGenerator.buildRounds(widget.terms);
    placedChoiceIndexes = _emptyPlacementForCurrentRound();
    _loadHighScore();
  }

  Future<void> _loadHighScore() async {
    final preferences = await SharedPreferences.getInstance();
    final storedHighScore =
        preferences.getInt(_highScorePreferenceKey) ?? 0;

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

    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_highScorePreferenceKey, completedScore);
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
      _recordHighScoreIfNeeded();
      return;
    }

    setState(() {
      currentRoundIndex++;
      placedChoiceIndexes = _emptyPlacementForCurrentRound();
      hasSubmitted = false;
      lastAnswerCorrect = false;
    });
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

    if (completingSession) {
      _recordHighScoreIfNeeded();
    }
  }

  void _restart() {
    setState(() {
      rounds = WordFusionRoundGenerator.buildRounds(widget.terms);
      currentRoundIndex = 0;
      correctCount = 0;
      incorrectCount = 0;
      skippedCount = 0;
      hasSubmitted = false;
      lastAnswerCorrect = false;
      sessionComplete = false;
      placedChoiceIndexes = _emptyPlacementForCurrentRound();
    });
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
      leftIcon: Icons.close_rounded,
      leftIconSize: 34,
      leftIconColor: GakujiColors.darkGray,
      onLeftTap: () => Navigator.pop(context),
      title: '${currentRoundIndex + 1}/${rounds.length}',
      titleStyle: TextStyle(
        fontSize: 20,
        height: 1,
        fontWeight: FontWeight.w700,
        color: GakujiColors.darkGray,
      ),
      rightIcon: Icons.more_horiz_rounded,
      rightIconSize: 36,
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
          style: GakujiText.small.copyWith(
            color: GakujiColors.mediumGray,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
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
        Text(
          currentRound.definition,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 18,
            height: 1.15,
            fontWeight: FontWeight.w700,
            color: GakujiColors.darkGray,
          ),
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
              leftIcon: Icons.close_rounded,
              leftIconSize: 34,
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
                          onTap: () => Navigator.pop(context),
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
              leftIcon: Icons.close_rounded,
              leftIconSize: 34,
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
