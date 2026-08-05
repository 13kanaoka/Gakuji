import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/deck.dart';
import '../models/imposter_round.dart';
import '../models/term.dart';
import '../services/imposter_round_generator.dart';
import '../widgets/gakuji_styles.dart';

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
  static const int maxMistakes = 3;

  late final List<Term> gameTerms;

  final ImposterRoundGenerator _generator = ImposterRoundGenerator();

  ImposterRound? currentRound;
  ImposterRound? correctionRound;
  bool? correctionUserApproved;

  bool gameStarted = false;
  bool gameOver = false;
  bool showingCorrection = false;

  int currentIndex = 0;
  int correctCount = 0;
  int mistakeCount = 0;
  int streak = 0;
  int bestStreak = 0;

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

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    gameTerms = List<Term>.from(widget.terms)..shuffle();
  }

  @override
  void dispose() {
    _restorePortrait();
    super.dispose();
  }

  Future<void> _restorePortrait() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> _leavePage(BuildContext context) async {
    await _restorePortrait();

    if (!context.mounted) return;

    Navigator.pop(context);
  }

  int get clearedCount => currentIndex;

  bool get clearedDeck {
    return gameTerms.isNotEmpty && currentIndex >= gameTerms.length;
  }

  void startGame() {
    gameTerms.shuffle();

    setState(() {
      gameStarted = true;
      gameOver = false;
      showingCorrection = false;
      correctionRound = null;
      correctionUserApproved = null;
      currentIndex = 0;
      correctCount = 0;
      mistakeCount = 0;
      streak = 0;
      bestStreak = 0;
      currentRound = _generateRoundForCurrentIndex();
    });
  }

  ImposterRound? _generateRoundForCurrentIndex() {
    if (currentIndex >= gameTerms.length) return null;

    return _generator.generate(
      visitor: gameTerms[currentIndex],
      deckTerms: gameTerms,
    );
  }

  void answer({
    required bool approved,
  }) {
    final round = currentRound;

    if (!gameStarted || gameOver || showingCorrection || round == null) return;

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

      return;
    }

    setState(() {
      mistakeCount++;
      streak = 0;
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
    currentIndex++;

    if (mistakeCount >= maxMistakes || currentIndex >= gameTerms.length) {
      gameOver = true;
      currentRound = null;
      return;
    }

    currentRound = _generateRoundForCurrentIndex();
  }

  void restartGame() {
    startGame();
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
    final termCount = gameTerms.length;
    final termLabel = termCount == 1 ? '1 term' : '$termCount terms';

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(
            children: [
              _sideExitRail(
                context: context,
                icon: Icons.arrow_back_ios_new_rounded,
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: _landscapePanel(
                  color: GakujiColors.warmCard,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detective',
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.large,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Inspect identity files and decide who belongs in the library.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.xSmall.copyWith(
                          color: GakujiColors.mediumGray,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _compactInfoCard(termLabel),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: _landscapePanel(
                  color: GakujiColors.whiteCard,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inspection Desk',
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.medium.copyWith(
                          color: deckPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Clear the full deck before reaching 3 mistakes.',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.xSmall.copyWith(
                          color: GakujiColors.mediumGray,
                        ),
                      ),
                      const Spacer(),
                      _startButton(),
                    ],
                  ),
                ),
              ),
            ],
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Column(
            children: [
              _landscapeGameHeader(context),
              const SizedBox(height: 4),
              _progressBar(),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          Expanded(
                            child: _visitorStack(round),
                          ),
                          const SizedBox(height: 8),
                          _scoreRow(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: _identityFile(
                        file: round.file,
                        visitor: round.visitor,
                      )
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: _decisionPanel(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultsScreen(BuildContext context) {
    final cleared = clearedCount.clamp(0, gameTerms.length);
    final completed = cleared >= gameTerms.length && mistakeCount < maxMistakes;

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(
            children: [
              _sideExitRail(
                context: context,
                icon: Icons.arrow_back_ios_new_rounded,
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: _landscapePanel(
                  color: GakujiColors.warmCard,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        completed ? 'Inspection Complete!' : 'Inspection Failed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.large,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        completed
                            ? 'Every term was cleared for the library.'
                            : 'Too many suspicious files slipped through the desk.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.xSmall.copyWith(
                          color: GakujiColors.mediumGray,
                        ),
                      ),
                      const Spacer(),
                      _restartButton(),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: _resultsCard(cleared),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _landscapeGameHeader(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          _smallTopIconButton(
            icon: Icons.close_rounded,
            iconSize: 30,
            onTap: () => _leavePage(context),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${currentIndex + 1}/${gameTerms.length}',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: GakujiColors.darkGray,
                ),
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _sideExitRail({
    required BuildContext context,
    required IconData icon,
  }) {
    return SizedBox(
      width: 42,
      child: Align(
        alignment: Alignment.topCenter,
        child: _smallTopIconButton(
          icon: icon,
          iconSize: 28,
          onTap: () => _leavePage(context),
        ),
      ),
    );
  }

  Widget _smallTopIconButton({
    required IconData icon,
    required double iconSize,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: deckPrimaryColor.withValues(alpha: 0.08),
        highlightColor: deckPrimaryColor.withValues(alpha: 0.04),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: iconSize,
            color: GakujiColors.darkGray,
          ),
        ),
      ),
    );
  }

  Widget _landscapePanel({
    required Widget child,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: GakujiColors.softBorder,
          width: 1.3,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: child,
    );
  }

  Widget _progressBar() {
    final total = gameTerms.isEmpty ? 1 : gameTerms.length;
    final progress = (currentIndex / total).clamp(0.0, 1.0).toDouble();

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
              color: GakujiColors.darkGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreRow() {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          _statPill(
            label: 'Errors',
            value: '$mistakeCount/$maxMistakes',
            color: const Color(0xFFFF8C8C),
          ),
          const SizedBox(width: 8),
          _statPill(
            label: 'Streak',
            value: '$streak',
            color: const Color(0xFFC8F29D),
          ),
        ],
      ),
    );
  }

  Widget _statPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(GakujiRadius.pill),
          border: Border.all(
            color: color,
            width: 2,
          ),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$label: $value',
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.darkGray,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _visitorStack(ImposterRound round) {
    final activeCorrectionRound = correctionRound;
    final userApproved = correctionUserApproved;

    return Stack(
      children: [
        Positioned.fill(
          child: _visitorCard(round.visitor),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !showingCorrection,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slideAnimation = Tween<Offset>(
                  begin: const Offset(-0.35, 0),
                  end: Offset.zero,
                ).animate(animation);

                return SlideTransition(
                  position: slideAnimation,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: showingCorrection &&
                      activeCorrectionRound != null &&
                      userApproved != null
                  ? _correctionPaper(
                      key: const ValueKey('correction-paper'),
                      round: activeCorrectionRound,
                      userApproved: userApproved,
                    )
                  : const SizedBox(
                      key: ValueKey('no-correction-paper'),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _visitorCard(Term term) {
    final termText = _termDisplayText(term);

    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: deckPrimaryColor.withValues(alpha: 0.42),
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            termText,
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: _termFontSizeFor(termText),
              height: 1,
              fontWeight: FontWeight.w700,
              color: GakujiColors.darkGray,
            ),
          ),
        ),
      ),
    );
  }

 Widget _identityFile({
    required IdentityFile file,
    required Term visitor,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: GakujiColors.whiteCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: GakujiColors.softBorder,
          width: 1.3,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Identity File',
            textScaler: TextScaler.noScaling,
            style: GakujiText.medium.copyWith(
              color: deckPrimaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _fileRow(
                    label: 'Visitor',
                    value: _termDisplayText(visitor),
                  ),
                  _fileRow(
                    label: 'Reading',
                    value: file.reading,
                  ),
                  _fileRow(
                    label: 'Part of Speech',
                    value: file.partOfSpeech,
                  ),
                  _fileRow(
                    label: 'Definition',
                    value: file.definition,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _correctionPaper({
    required Key key,
    required ImposterRound round,
    required bool userApproved,
  }) {
    final correctFile = _correctIdentityFile(round.visitor);
    final correctDecision = round.isValid;
    final fileStatus = round.isValid ? 'This file was real.' : 'This file was fake.';

    return Container(
      key: key,
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE0B86F),
          width: 1.6,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_rounded,
                size: 22,
                color: deckPrimaryColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Correction Notice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.small.copyWith(
                    color: deckPrimaryColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'You chose ${_decisionLabel(userApproved)}. Correct call: ${_decisionLabel(correctDecision)}.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              color: GakujiColors.darkGray,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fileStatus,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              color: GakujiColors.mediumGray,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 1,
            color: GakujiColors.softBorder,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _correctionRow(
                    label: 'Visitor',
                    value: _termDisplayText(round.visitor),
                  ),
                  _correctionRow(
                    label: 'Reading',
                    value: correctFile.reading,
                  ),
                  _correctionRow(
                    label: 'Part of Speech',
                    value: correctFile.partOfSpeech,
                  ),
                  _correctionRow(
                    label: 'Definition',
                    value: correctFile.definition,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _continueCorrectionButton(),
        ],
      ),
    );
  }

  Widget _correctionRow({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.mediumGray,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.darkGray,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _continueCorrectionButton() {
    return Container(
      width: double.infinity,
      height: 38,
      decoration: BoxDecoration(
        color: deckPrimaryColor,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: continueAfterCorrection,
          splashColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          child: Center(
            child: Text(
              mistakeCount >= maxMistakes ? 'View Results' : 'Continue',
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.warmCard,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _decisionPanel() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: GakujiColors.softBorder,
          width: 1.3,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Column(
        children: [
          Text(
            'Decision',
            textScaler: TextScaler.noScaling,
            style: GakujiText.medium.copyWith(
              color: deckPrimaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            showingCorrection
                ? 'Review the correction notice and compare it with the file.'
                : 'Does this file belong to the visitor?',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              color: GakujiColors.mediumGray,
            ),
          ),
          const Spacer(),
          _decisionButton(
            label: 'Deny',
            color: const Color(0xFFFF8C8C),
            textColor: const Color(0xFFB84848),
            onTap: () => answer(approved: false),
          ),
          const SizedBox(height: 8),
          _decisionButton(
            label: 'Approve',
            color: const Color(0xFFC8F29D),
            textColor: const Color(0xFF4F8F35),
            onTap: () => answer(approved: true),
          ),
        ],
      ),
    );
  }

  Widget _fileRow({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.mediumGray,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.darkGray,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _decisionButton({
    required String label,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
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
              style: GakujiText.small.copyWith(
                color: textColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactInfoCard(String termLabel) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: GakujiColors.whiteCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: GakujiColors.softBorder,
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _compactInfoRow(
            label: 'Deck',
            value: widget.deck.name,
          ),
          const SizedBox(height: 8),
          _compactInfoRow(
            label: 'Run',
            value: 'Full deck • $termLabel',
          ),
          const SizedBox(height: 8),
          _compactInfoRow(
            label: 'Limit',
            value: '3 mistakes',
          ),
        ],
      ),
    );
  }

  Widget _compactInfoRow({
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              color: GakujiColors.mediumGray,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              color: GakujiColors.darkGray,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultsCard(int cleared) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: GakujiColors.whiteCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: GakujiColors.softBorder,
          width: 1.3,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _resultRow('Cleared', '$cleared/${gameTerms.length}'),
          const SizedBox(height: 12),
          _resultRow('Correct', '$correctCount'),
          const SizedBox(height: 12),
          _resultRow('Errors', '$mistakeCount/$maxMistakes'),
          const SizedBox(height: 12),
          _resultRow('Best Streak', '$bestStreak'),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          textScaler: TextScaler.noScaling,
          style: GakujiText.xSmall.copyWith(
            color: GakujiColors.mediumGray,
          ),
        ),
        const Spacer(),
        Text(
          value,
          textScaler: TextScaler.noScaling,
          style: GakujiText.small.copyWith(
            color: GakujiColors.darkGray,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _startButton() {
    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        color: deckPrimaryColor,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: startGame,
          splashColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          child: Center(
            child: Text(
              'Start Inspection',
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                color: GakujiColors.warmCard,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _restartButton() {
    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        color: deckPrimaryColor,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: restartGame,
          splashColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          child: Center(
            child: Text(
              'Try Again',
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                color: GakujiColors.warmCard,
                fontWeight: FontWeight.w800,
              ),
            ),
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

  String _decisionLabel(bool approved) {
    return approved ? 'Approve' : 'Deny';
  }

  String _termDisplayText(Term term) {
    final kanji = term.kanji.trim();

    if (kanji.isNotEmpty) return kanji;

    return _safeValue(term.reading);
  }

  String _definitionText(Term term) {
    final meaning = term.meaning.trim();

    if (meaning.isNotEmpty) return meaning;

    return _safeValue(term.cardMeaning);
  }

  String _safeValue(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) return '—';

    return trimmed;
  }

  double _termFontSizeFor(String text) {
    if (text.length >= 7) return 34;
    if (text.length >= 5) return 40;
    if (text.length >= 3) return 48;

    return 54;
  }
}