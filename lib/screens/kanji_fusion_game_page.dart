import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:gakuji/models/kanji_fusion_round.dart';
import 'package:gakuji/models/term.dart';
import 'package:gakuji/services/gakuji_local_preferences.dart';
import 'package:gakuji/services/kanji_fusion_round_generator.dart';
import 'package:gakuji/widgets/gakuji_domino.dart';
import 'package:gakuji/widgets/gakuji_styles.dart';
import 'package:gakuji/widgets/gakuji_top_bar.dart';

class KanjiFusionGamePage extends StatefulWidget {
  final List<Term> terms;
  final String deckName;
  final Color? accentColor;

  const KanjiFusionGamePage({
    super.key,
    required this.terms,
    required this.deckName,
    this.accentColor,
  });

  @override
  State<KanjiFusionGamePage> createState() => _KanjiFusionGamePageState();
}

class _FusionDragData {
  final int choiceIndex;
  final String componentForm;
  final int? sourceSlotIndex;

  const _FusionDragData({
    required this.choiceIndex,
    required this.componentForm,
    this.sourceSlotIndex,
  });
}

class _PlacedFusionBlock {
  final int choiceIndex;
  final String component;
  final Offset position;

  const _PlacedFusionBlock({
    required this.choiceIndex,
    required this.component,
    required this.position,
  });

  _PlacedFusionBlock copyWith({
    int? choiceIndex,
    String? component,
    Offset? position,
  }) {
    return _PlacedFusionBlock(
      choiceIndex: choiceIndex ?? this.choiceIndex,
      component: component ?? this.component,
      position: position ?? this.position,
    );
  }
}

class _KanjiFusionGamePageState extends State<KanjiFusionGamePage> {
  late List<KanjiFusionRound> rounds;

  KanjiFusionDifficulty selectedDifficulty = KanjiFusionDifficulty.normal;
  KanjiFusionRadicalMode selectedRadicalMode =
      KanjiFusionRadicalMode.create;
  int currentRoundIndex = 0;
  int correctCount = 0;
  int incorrectCount = 0;
  int skippedCount = 0;
  int highScore = 0;
  bool isReviewSession = false;
  final List<KanjiFusionRound> incorrectRounds = [];

  final List<int?> placedChoiceIndexes = [];
  final List<String?> placedComponentForms = [];
  final List<int> choiceFormIndexes = [];
  int? activeChoiceIndex;
  String? activeChoiceForm;
  static const double _fusionFieldSize = 205;
  static const double _placedBlockSize = 54;
  static const Color _studyIncorrectRed = Color(0xFFE06F6F);
  static const Color _studyIncorrectRedFill = Color(0xFFF6A3A3);
  static const String _highScorePreferenceKey =
      'kanji_fusion_high_score_v1';

  final GlobalKey _fusionFieldKey = GlobalKey();
  final List<_PlacedFusionBlock> placedBlocks = [];

  int? _movingPlacedIndex;
  Offset _movingGrabOffset = Offset.zero;

  bool hasSubmitted = false;
  bool lastAnswerCorrect = false;
  bool sessionComplete = false;

  KanjiFusionRound get currentRound => rounds[currentRoundIndex];

  Color get _accentColor =>
      widget.accentColor ?? GakujiColors.deckBlue;

  List<String> get selectedComponents {
    switch (selectedDifficulty) {
      case KanjiFusionDifficulty.easy:
        return placedChoiceIndexes
            .whereType<int>()
            .map((index) => currentRound.componentChoices[index])
            .toList(growable: false);
      case KanjiFusionDifficulty.normal:
        return placedComponentForms.whereType<String>().toList(growable: false);
      case KanjiFusionDifficulty.hard:
        return placedBlocks
            .map((block) => block.component)
            .toList(growable: false);
    }
  }

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
    if (hasSubmitted) return false;

    switch (selectedDifficulty) {
      case KanjiFusionDifficulty.easy:
        return placedChoiceIndexes.isNotEmpty &&
            placedChoiceIndexes.every((index) => index != null);
      case KanjiFusionDifficulty.normal:
        return placedChoiceIndexes.isNotEmpty &&
            placedChoiceIndexes.every((index) => index != null) &&
            placedComponentForms.every((component) => component != null);
      case KanjiFusionDifficulty.hard:
        return placedBlocks.isNotEmpty;
    }
  }

  @override
  void initState() {
    super.initState();
    rounds = KanjiFusionRoundGenerator.buildRounds(
      widget.terms,
      difficulty: selectedDifficulty,
      radicalMode: selectedRadicalMode,
    );
    _resetRoundPlacement();
    _loadHighScore();
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
    if (isReviewSession || rounds.isEmpty) return;

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

  Future<void> _toggleChoice(int choiceIndex) async {
    if (hasSubmitted || selectedDifficulty == KanjiFusionDifficulty.hard) {
      return;
    }

    if (placedChoiceIndexes.contains(choiceIndex)) return;

    if (activeChoiceIndex == choiceIndex) {
      setState(() {
        activeChoiceIndex = null;
        activeChoiceForm = null;
      });
      return;
    }

    final form = await _resolveChoiceForm(choiceIndex);
    if (!mounted || form == null) return;

    setState(() {
      activeChoiceIndex = choiceIndex;
      activeChoiceForm = form;
    });
  }

  Future<String?> _resolveChoiceForm(int choiceIndex) async {
    final forms = currentRound.formsForChoice(choiceIndex);
    if (forms.isEmpty) return null;

    final shouldChooseForm =
        selectedDifficulty == KanjiFusionDifficulty.normal &&
            selectedRadicalMode == KanjiFusionRadicalMode.create &&
            forms.length > 1;

    if (!shouldChooseForm) return forms.first;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            decoration: BoxDecoration(
              color: GakujiColors.warmBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: GakujiColors.softBorder,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Choose Radical Form',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.medium.copyWith(
                    color: GakujiColors.darkGray,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: forms.map((form) {
                    return GakujiDomino(
                      text: form,
                      onTap: () => Navigator.pop(sheetContext, form),
                    );
                  }).toList(growable: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  String _currentChoiceForm(int choiceIndex) {
    final forms = currentRound.formsForChoice(choiceIndex);
    if (forms.isEmpty) return currentRound.componentChoices[choiceIndex];

    final formIndex = choiceIndex < choiceFormIndexes.length
        ? choiceFormIndexes[choiceIndex]
        : 0;
    return forms[formIndex.clamp(0, forms.length - 1).toInt()];
  }

  void _cycleChoiceForm(int choiceIndex) {
    if (hasSubmitted ||
        selectedDifficulty != KanjiFusionDifficulty.normal ||
        choiceIndex < 0 ||
        choiceIndex >= currentRound.componentChoices.length ||
        placedChoiceIndexes.contains(choiceIndex)) {
      return;
    }

    final forms = currentRound.formsForChoice(choiceIndex);
    if (forms.length <= 1) return;

    setState(() {
      final currentIndex = choiceFormIndexes[choiceIndex];
      choiceFormIndexes[choiceIndex] = (currentIndex + 1) % forms.length;
    });
  }

  bool _canAcceptSlotDrag(
    _FusionDragData dragData,
    int slotIndex,
  ) {
    if (hasSubmitted ||
        slotIndex < 0 ||
        slotIndex >= placedChoiceIndexes.length) {
      return false;
    }

    if (dragData.sourceSlotIndex != null) return true;

    return !placedChoiceIndexes.contains(dragData.choiceIndex);
  }

  void _placeChoiceInSlot(
    _FusionDragData dragData,
    int slotIndex,
  ) {
    if (!_canAcceptSlotDrag(dragData, slotIndex)) return;

    setState(() {
      final sourceSlotIndex = dragData.sourceSlotIndex;
      final displacedChoiceIndex = placedChoiceIndexes[slotIndex];
      final displacedComponentForm = placedComponentForms[slotIndex];

      if (sourceSlotIndex == slotIndex) {
        activeChoiceIndex = null;
        activeChoiceForm = null;
        return;
      }

      if (sourceSlotIndex != null &&
          sourceSlotIndex >= 0 &&
          sourceSlotIndex < placedChoiceIndexes.length) {
        placedChoiceIndexes[sourceSlotIndex] = displacedChoiceIndex;
        placedComponentForms[sourceSlotIndex] = displacedComponentForm;
      }

      placedChoiceIndexes[slotIndex] = dragData.choiceIndex;
      placedComponentForms[slotIndex] = dragData.componentForm;
      activeChoiceIndex = null;
      activeChoiceForm = null;
    });
  }

  void _placeActiveChoice(int slotIndex) {
    final choiceIndex = activeChoiceIndex;
    final componentForm = activeChoiceForm;
    if (hasSubmitted || choiceIndex == null || componentForm == null) return;

    _placeChoiceInSlot(
      _FusionDragData(
        choiceIndex: choiceIndex,
        componentForm: componentForm,
      ),
      slotIndex,
    );
  }

  void _removeSlot(int slotIndex) {
    if (hasSubmitted ||
        slotIndex < 0 ||
        slotIndex >= placedChoiceIndexes.length) {
      return;
    }

    setState(() {
      placedChoiceIndexes[slotIndex] = null;
      placedComponentForms[slotIndex] = null;
    });
  }

  void _handleSlotDragEnd(
    int sourceSlotIndex,
    DraggableDetails details,
  ) {
    if (!details.wasAccepted) {
      _removeSlot(sourceSlotIndex);
    }
  }

  void _removePlacedBlock(int placedIndex) {
    if (hasSubmitted ||
        placedIndex < 0 ||
        placedIndex >= placedBlocks.length) {
      return;
    }

    setState(() {
      placedBlocks.removeAt(placedIndex);
    });
  }

  void _resetRoundPlacement() {
    placedChoiceIndexes.clear();
    placedComponentForms.clear();
    choiceFormIndexes.clear();
    placedBlocks.clear();
    activeChoiceIndex = null;
    activeChoiceForm = null;
    _movingPlacedIndex = null;
    _movingGrabOffset = Offset.zero;

    if (rounds.isEmpty) return;

    choiceFormIndexes.addAll(
      List<int>.filled(currentRound.componentChoices.length, 0),
    );

    switch (selectedDifficulty) {
      case KanjiFusionDifficulty.easy:
        placedChoiceIndexes.addAll(
          List<int?>.filled(currentRound.requiredComponents.length, null),
        );
        placedComponentForms.addAll(
          List<String?>.filled(currentRound.requiredComponents.length, null),
        );
        break;
      case KanjiFusionDifficulty.normal:
        placedChoiceIndexes.addAll(
          List<int?>.filled(currentRound.structuralSlots.length, null),
        );
        placedComponentForms.addAll(
          List<String?>.filled(currentRound.structuralSlots.length, null),
        );
        break;
      case KanjiFusionDifficulty.hard:
        break;
    }
  }

  void _placeBlock(
    _FusionDragData dragData,
    Offset globalDropPosition,
  ) {
    if (hasSubmitted) return;

    final renderObject =
        _fusionFieldKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;

    final localDropPosition = renderObject.globalToLocal(globalDropPosition);
    final position = _clampPlacedBlockPosition(
      Offset(
        localDropPosition.dx - (_placedBlockSize / 2),
        localDropPosition.dy - (_placedBlockSize / 2),
      ),
    );

    setState(() {
      final alreadyPlaced = placedBlocks.any(
        (block) => block.choiceIndex == dragData.choiceIndex,
      );
      if (alreadyPlaced) return;

      placedBlocks.add(
        _PlacedFusionBlock(
          choiceIndex: dragData.choiceIndex,
          component: dragData.componentForm,
          position: position,
        ),
      );
    });
  }

  Offset _clampPlacedBlockPosition(Offset position) {
    final maxCoordinate = _fusionFieldSize - _placedBlockSize;

    return Offset(
      position.dx.clamp(0.0, maxCoordinate).toDouble(),
      position.dy.clamp(0.0, maxCoordinate).toDouble(),
    );
  }

  void _startMovingPlacedBlock(
    int placedIndex,
    DragStartDetails details,
  ) {
    if (hasSubmitted ||
        placedIndex < 0 ||
        placedIndex >= placedBlocks.length) {
      return;
    }

    setState(() {
      _movingPlacedIndex = placedIndex;
      _movingGrabOffset = details.localPosition;
    });
  }

  void _movePlacedBlock(DragUpdateDetails details) {
    final placedIndex = _movingPlacedIndex;

    if (hasSubmitted ||
        placedIndex == null ||
        placedIndex < 0 ||
        placedIndex >= placedBlocks.length) {
      return;
    }

    final renderObject =
        _fusionFieldKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;

    final pointerInField = renderObject.globalToLocal(details.globalPosition);
    final position = _clampPlacedBlockPosition(
      pointerInField - _movingGrabOffset,
    );

    setState(() {
      placedBlocks[placedIndex] = placedBlocks[placedIndex].copyWith(
        position: position,
      );
    });
  }

  void _stopMovingPlacedBlock() {
    if (_movingPlacedIndex == null) return;

    setState(() {
      _movingPlacedIndex = null;
      _movingGrabOffset = Offset.zero;
    });
  }

  void _fuse() {
    if (!canFuse) return;

    late final bool correct;

    switch (selectedDifficulty) {
      case KanjiFusionDifficulty.easy:
        correct = _componentCountsMatch(
          selectedComponents,
          currentRound.requiredComponents,
        );
        break;
      case KanjiFusionDifficulty.normal:
        correct = placedComponentForms.asMap().entries.every((entry) {
          return entry.value == currentRound.structuralSlots[entry.key].component;
        });
        break;
      case KanjiFusionDifficulty.hard:
        correct = _componentCountsMatch(
              selectedComponents,
              currentRound.requiredComponents,
            ) &&
            _freeformPlacementMatches();
        break;
    }

    setState(() {
      hasSubmitted = true;
      lastAnswerCorrect = correct;

      if (correct) {
        correctCount++;
      } else {
        incorrectCount++;
        incorrectRounds.add(currentRound);
      }
    });
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
      _resetRoundPlacement();
      hasSubmitted = false;
      lastAnswerCorrect = false;
    });
  }

  void _skipRound() {
    if (hasSubmitted) return;

    setState(() {
      skippedCount++;

      if (currentRoundIndex >= rounds.length - 1) {
        sessionComplete = true;
        return;
      }

      currentRoundIndex++;
      _resetRoundPlacement();
      hasSubmitted = false;
      lastAnswerCorrect = false;
    });

    if (sessionComplete) {
      _recordHighScoreIfNeeded();
    }
  }

  void _restart() {
    setState(() {
      rounds = KanjiFusionRoundGenerator.buildRounds(
        widget.terms,
        difficulty: selectedDifficulty,
        radicalMode: selectedRadicalMode,
      );
      currentRoundIndex = 0;
      correctCount = 0;
      incorrectCount = 0;
      skippedCount = 0;
      isReviewSession = false;
      incorrectRounds.clear();
      hasSubmitted = false;
      lastAnswerCorrect = false;
      sessionComplete = false;
      _resetRoundPlacement();
    });
  }

  bool _componentCountsMatch(
    List<String> selected,
    List<String> required,
  ) {
    final selectedCounts = _componentCounts(selected);
    final requiredCounts = _componentCounts(required);

    if (selectedCounts.length != requiredCounts.length) return false;

    for (final entry in requiredCounts.entries) {
      if (selectedCounts[entry.key] != entry.value) return false;
    }

    return true;
  }

  Map<String, int> _componentCounts(List<String> components) {
    final counts = <String, int>{};

    for (final component in components) {
      counts[component] = (counts[component] ?? 0) + 1;
    }

    return counts;
  }

  bool _freeformPlacementMatches() {
    if (placedBlocks.length != currentRound.structuralSlots.length) return false;

    final expectedCenters = currentRound.structuralSlots.map((slot) {
      return Offset(
        slot.left + (slot.width / 2),
        slot.top + (slot.height / 2),
      );
    }).toList(growable: false);
    final placedCenters = placedBlocks.map((block) {
      return Offset(
        (block.position.dx + (_placedBlockSize / 2)) / _fusionFieldSize,
        (block.position.dy + (_placedBlockSize / 2)) / _fusionFieldSize,
      );
    }).toList(growable: false);

    final usedPlacedIndexes = <int>{};

    bool tryMatchExpected(int expectedIndex, List<int> assignment) {
      if (expectedIndex == currentRound.structuralSlots.length) {
        return _spatialPatternMatches(
          expectedCenters: expectedCenters,
          placedCenters: placedCenters,
          assignment: assignment,
        );
      }

      final expectedComponent =
          currentRound.structuralSlots[expectedIndex].component;

      for (var placedIndex = 0;
          placedIndex < placedBlocks.length;
          placedIndex++) {
        if (usedPlacedIndexes.contains(placedIndex)) continue;

        final placedComponent = placedBlocks[placedIndex].component;
        if (placedComponent != expectedComponent) continue;

        usedPlacedIndexes.add(placedIndex);
        assignment.add(placedIndex);

        if (tryMatchExpected(expectedIndex + 1, assignment)) return true;

        assignment.removeLast();
        usedPlacedIndexes.remove(placedIndex);
      }

      return false;
    }

    return tryMatchExpected(0, <int>[]);
  }

  bool _spatialPatternMatches({
    required List<Offset> expectedCenters,
    required List<Offset> placedCenters,
    required List<int> assignment,
  }) {
    const overlapExpectedDistance = 0.16;
    const overlapPlacedTolerance = 0.30;
    const minimumSeparatedDistance = 0.08;
    const maximumAngleDifference = math.pi / 3;

    for (var first = 0; first < expectedCenters.length; first++) {
      for (var second = first + 1;
          second < expectedCenters.length;
          second++) {
        final expectedVector =
            expectedCenters[second] - expectedCenters[first];
        final placedVector = placedCenters[assignment[second]] -
            placedCenters[assignment[first]];
        final expectedDistance = expectedVector.distance;
        final placedDistance = placedVector.distance;

        if (expectedDistance <= overlapExpectedDistance) {
          if (placedDistance > overlapPlacedTolerance) return false;
          continue;
        }

        if (placedDistance < minimumSeparatedDistance) return false;

        final dotProduct =
            (expectedVector.dx * placedVector.dx) +
            (expectedVector.dy * placedVector.dy);
        final cosine = (dotProduct / (expectedDistance * placedDistance))
            .clamp(-1.0, 1.0)
            .toDouble();
        final angleDifference = math.acos(cosine);

        if (angleDifference > maximumAngleDifference) return false;
      }
    }

    return true;
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
                  label: 'Exit Fusion',
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
    if (rounds.isEmpty) {
      return _emptyScreen();
    }

    if (sessionComplete) {
      return _completeScreen();
    }

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            _progressBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
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
        letterSpacing: -0.2,
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
          Container(
            width: double.infinity,
            height: 4,
            color: GakujiColors.softBorder,
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0,
              end: sessionProgress,
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

  Widget _playScreen({required Key key}) {
    return Column(
      key: key,
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              24,
              8,
              24,
              8,
            ),
            child: Column(
              children: [
                _scoreRow(showSkip: true),
                SizedBox(height: 10),
                _prompt(),
                SizedBox(height: 14),
                _answerSlots(),
                SizedBox(height: 18),
                _componentGrid(),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            28,
            8,
            28,
            18,
          ),
          child: _primaryButton(
            label: 'FUSE',
            enabled: canFuse,
            onTap: _fuse,
          ),
        ),
      ],
    );
  }

  Widget _resultScreen({required Key key}) {
    return Column(
      key: key,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
            child: Column(
              children: [
                _scoreRow(),
                const SizedBox(height: 22),
                _prompt(),
                const SizedBox(height: 26),
                lastAnswerCorrect
                    ? _successfulFusionResultCard()
                    : _failedFusionComparison(),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  height: 1,
                  color: GakujiColors.warmDivider,
                ),
                const SizedBox(height: 24),
                Text(
                  lastAnswerCorrect ? 'Correct!' : 'Correct Answer',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.medium.copyWith(
                    color: lastAnswerCorrect
                        ? _accentColor
                        : GakujiColors.mediumGray,
                  ),
                ),
                const SizedBox(height: 14),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.scale(
                        scale: 0.82 + (0.18 * value),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    currentRound.targetKanji,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontFamily: GakujiFonts.japanese,
                      fontSize: 76,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: GakujiColors.darkGray,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
          child: _primaryButton(
            label: currentRoundIndex == rounds.length - 1
                ? 'FINISH'
                : 'CONTINUE',
            enabled: true,
            onTap: _continue,
          ),
        ),
      ],
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
          style: GakujiText.gameReading,
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

  Widget _answerSlots() {
    switch (selectedDifficulty) {
      case KanjiFusionDifficulty.easy:
        return _easyAnswerSlots();
      case KanjiFusionDifficulty.normal:
        return _structuredAnswerSlots();
      case KanjiFusionDifficulty.hard:
        return _hardAnswerField();
    }
  }

  Color get _blockFillColor => Colors.white;

  Color get _blockTextColor => const Color(0xFF666666);

  Color get _blockOutlineColor => const Color(0xFFB8B8B8);

  Color get _blockSelectionColor => const Color(0xFF7A7A7A);

  bool get _compactChoiceTiles =>
      currentRound.componentChoices.length > 15;

  Widget _easyAnswerSlots() {
    final slotCount = currentRound.requiredComponents.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columnCount = math.min(slotCount, 4);
        final availableWidth =
            constraints.maxWidth - (gap * (columnCount - 1));
        final slotWidth = math.min(72.0, availableWidth / columnCount);
        final slotHeight = slotWidth * 1.15;

        return Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: List.generate(slotCount, (index) {
            final choiceIndex = placedChoiceIndexes[index];
            final component = choiceIndex == null
                ? null
                : currentRound.componentChoices[choiceIndex];

            return SizedBox(
              width: slotWidth,
              height: slotHeight,
              child: DragTarget<_FusionDragData>(
                onWillAcceptWithDetails: (details) {
                  return _canAcceptSlotDrag(details.data, index);
                },
                onAcceptWithDetails: (details) {
                  _placeChoiceInSlot(details.data, index);
                },
                builder: (context, candidates, rejected) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (activeChoiceIndex != null) {
                        _placeActiveChoice(index);
                      } else if (component != null) {
                        _removeSlot(index);
                      }
                    },
                    child: component == null
                        ? CustomPaint(
                            painter: _DashedRoundedRectPainter(
                              color: candidates.isNotEmpty
                                  ? _accentColor
                                  : GakujiColors.mediumGray,
                              radius: 17,
                            ),
                          )
                        : _draggableSelectedSlot(
                            slotIndex: index,
                            choiceIndex: choiceIndex!,
                            component: component,
                          ),
                  );
                },
              ),
            );
          }),
        );
      },
    );
  }

  Widget _draggableSelectedSlot({
    required int slotIndex,
    required int choiceIndex,
    required String component,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Draggable<_FusionDragData>(
          data: _FusionDragData(
            choiceIndex: choiceIndex,
            componentForm: component,
            sourceSlotIndex: slotIndex,
          ),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          maxSimultaneousDrags: hasSubmitted ? 0 : 1,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: _selectedSlot(component),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.20,
            child: _selectedSlot(component),
          ),
          onDragEnd: (details) {
            _handleSlotDragEnd(slotIndex, details);
          },
          child: _selectedSlot(component),
        );
      },
    );
  }

  Widget _selectedSlot(String component) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final baseSize = (shortestSide * 0.52).clamp(16.0, 38.0);
        final fontSize = component.length > 1 ? baseSize * 0.72 : baseSize;

        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _blockFillColor,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: _blockOutlineColor,
              width: 1.6,
            ),
            boxShadow: [GakujiShadows.soft],
          ),
          child: Text(
            component,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: GakujiFonts.japanese,
              fontSize: fontSize,
              height: 1,
              fontWeight: FontWeight.w600,
              color: _blockTextColor,
            ),
          ),
        );
      },
    );
  }

  Widget _structuralGroupOutline(
    KanjiFusionGroup group, {
    bool preview = false,
  }) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _NestedGroupOutlinePainter(
          color: _accentColor.withValues(alpha: 
            preview ? 0.28 : (group.depth == 0 ? 0.36 : 0.25),
          ),
          fillColor: _accentColor.withValues(alpha: 
            preview ? 0.018 : (group.depth == 0 ? 0.030 : 0.018),
          ),
          radius: preview
              ? 12.0
              : math.max(12.0, 20.0 - (group.depth * 3.0)).toDouble(),
          strokeWidth: preview ? 1.0 : 1.35,
        ),
      ),
    );
  }

  Widget _structuredAnswerSlots() {
    const boardSize = 224.0;

    return Center(
      child: SizedBox(
        width: boardSize,
        height: boardSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final group in currentRound.structuralGroups)
              Positioned(
                left: group.left * boardSize,
                top: group.top * boardSize,
                width: group.width * boardSize,
                height: group.height * boardSize,
                child: _structuralGroupOutline(group),
              ),
            ...List.generate(currentRound.structuralSlots.length, (index) {
              final slot = currentRound.structuralSlots[index];
              final choiceIndex = placedChoiceIndexes[index];
              final component = placedComponentForms[index];

              return Positioned(
                left: slot.left * boardSize,
                top: slot.top * boardSize,
                width: slot.width * boardSize,
                height: slot.height * boardSize,
                child: _structuredSlotTarget(
                  slot: slot,
                  slotIndex: index,
                  choiceIndex: choiceIndex,
                  component: component,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _structuredSlotTarget({
    required KanjiFusionSlot slot,
    required int slotIndex,
    required int? choiceIndex,
    required String? component,
  }) {
    return DragTarget<_FusionDragData>(
      onWillAcceptWithDetails: (details) {
        return _canAcceptSlotDrag(details.data, slotIndex);
      },
      onAcceptWithDetails: (details) {
        _placeChoiceInSlot(details.data, slotIndex);
      },
      builder: (context, candidates, rejected) {
        final outlineColor = candidates.isNotEmpty
            ? _accentColor
            : _blockOutlineColor;
        final isInnerEnclosureSlot =
            slot.shape == KanjiFusionSlotShape.standard &&
            currentRound.structuralSlots.any(
              (candidate) =>
                  candidate.shape == KanjiFusionSlotShape.enclosure,
            );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: component == null ? null : () => _removeSlot(slotIndex),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: _structuralSlotSurface(
                      slot: slot,
                      outlineColor: outlineColor,
                      isFilled: component != null,
                      showShadow: !isInnerEnclosureSlot,
                    ),
                  ),
                  if (component != null)
                    Positioned(
                      left: constraints.maxWidth * slot.contentLeft,
                      top: constraints.maxHeight * slot.contentTop,
                      width: constraints.maxWidth * slot.contentWidth,
                      height: constraints.maxHeight * slot.contentHeight,
                      child: _draggableStructuralComponent(
                        slotIndex: slotIndex,
                        choiceIndex: choiceIndex!,
                        component: component,
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _structuralSlotSurface({
    required KanjiFusionSlot slot,
    required Color outlineColor,
    required bool isFilled,
    bool showShadow = true,
  }) {
    if (slot.shape == KanjiFusionSlotShape.gate) {
      return CustomPaint(
        painter: _GateSlotPainter(
          color: outlineColor,
          fillColor: _blockFillColor,
          isFilled: isFilled,
          showShadow: showShadow,
        ),
      );
    }

    if (slot.shape == KanjiFusionSlotShape.enclosure) {
      return CustomPaint(
        painter: _EnclosureSlotPainter(
          color: outlineColor,
          fillColor: _blockFillColor,
          isFilled: isFilled,
          showShadow: showShadow,
        ),
      );
    }

    if (slot.shape == KanjiFusionSlotShape.cliff) {
      return CustomPaint(
        painter: _CliffSlotPainter(
          color: outlineColor,
          fillColor: _blockFillColor,
          isFilled: isFilled,
          showShadow: showShadow,
        ),
      );
    }

    if (slot.shape == KanjiFusionSlotShape.rightHook) {
      return CustomPaint(
        painter: _RightHookSlotPainter(
          color: outlineColor,
          fillColor: _blockFillColor,
          isFilled: isFilled,
          showShadow: showShadow,
        ),
      );
    }

    if (slot.shape == KanjiFusionSlotShape.cutout) {
      return CustomPaint(
        painter: _DashedCutoutSlotPainter(
          color: outlineColor,
        ),
      );
    }

    if (!isFilled) {
      return CustomPaint(
        painter: _DashedRoundedRectPainter(
          color: outlineColor,
          radius: 17,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _blockFillColor,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: outlineColor,
          width: 1.5,
        ),
        boxShadow: showShadow ? [GakujiShadows.soft] : null,
      ),
    );
  }

  Widget _draggableStructuralComponent({
    required int slotIndex,
    required int choiceIndex,
    required String component,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Draggable<_FusionDragData>(
          data: _FusionDragData(
            choiceIndex: choiceIndex,
            componentForm: component,
            sourceSlotIndex: slotIndex,
          ),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          maxSimultaneousDrags: hasSubmitted ? 0 : 1,
          feedback: Material(
            color: Colors.transparent,
            child: _dragFeedback(component),
          ),
          childWhenDragging: Opacity(
            opacity: 0.18,
            child: _structuralComponentGlyph(component),
          ),
          onDragEnd: (details) {
            _handleSlotDragEnd(slotIndex, details);
          },
          child: _structuralComponentGlyph(component),
        );
      },
    );
  }

  Widget _structuralComponentGlyph(
    String component, {
    double maxFontSize = 44,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final effectiveMaxFontSize = math.min(maxFontSize, 36.0);
        final baseSize =
            (shortestSide * 0.46).clamp(16.0, effectiveMaxFontSize);
        final fontSize = component.length > 1 ? baseSize * 0.72 : baseSize;

        return Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Text(
            component,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: GakujiFonts.japanese,
              fontSize: fontSize,
              height: 1,
              fontWeight: FontWeight.w600,
              color: _blockTextColor,
            ),
          ),
        );
      },
    );
  }

  Widget _hardAnswerField() {
    return Center(
      child: DragTarget<_FusionDragData>(
        onWillAcceptWithDetails: (details) {
          if (hasSubmitted) return false;

          return !placedBlocks.any(
            (block) => block.choiceIndex == details.data.choiceIndex,
          );
        },
        onAcceptWithDetails: (details) {
          _placeBlock(details.data, details.offset);
        },
        builder: (context, candidates, rejected) {
          return AnimatedContainer(
            key: _fusionFieldKey,
            duration: const Duration(milliseconds: 140),
            width: _fusionFieldSize,
            height: _fusionFieldSize,
            decoration: BoxDecoration(
              color: candidates.isEmpty
                  ? GakujiColors.warmCard
                  : _accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: candidates.isEmpty
                    ? GakujiColors.mediumGray
                    : _accentColor,
                width: 2,
              ),
              boxShadow: [GakujiShadows.soft],
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: List.generate(placedBlocks.length, (placedIndex) {
                final block = placedBlocks[placedIndex];
                final component = block.component;

                return Positioned(
                  left: block.position.dx,
                  top: block.position.dy,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: hasSubmitted
                        ? null
                        : (details) => _startMovingPlacedBlock(
                              placedIndex,
                              details,
                            ),
                    onPanUpdate: hasSubmitted ? null : _movePlacedBlock,
                    onPanEnd: hasSubmitted
                        ? null
                        : (_) => _stopMovingPlacedBlock(),
                    onPanCancel: hasSubmitted
                        ? null
                        : _stopMovingPlacedBlock,
                    child: _placedBlockTile(
                      component,
                      selected: _movingPlacedIndex == placedIndex,
                      onRemove: hasSubmitted
                          ? null
                          : () => _removePlacedBlock(placedIndex),
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  Widget _placedBlockTile(
    String component, {
    bool selected = false,
    VoidCallback? onRemove,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: _placedBlockSize,
      height: _placedBlockSize,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: selected ? _blockSelectionColor : Colors.transparent,
          width: 2.5,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _blockFillColor,
                borderRadius: BorderRadius.circular(
            _compactChoiceTiles ? 11 : 13,
          ),
                border: Border.all(
                  color: _blockOutlineColor,
                  width: 1.5,
                ),
                boxShadow: [GakujiShadows.soft],
              ),
              child: Text(
                component,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontFamily: GakujiFonts.japanese,
                  fontSize: component.length > 1 ? 20 : 28,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: _blockTextColor,
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _blockSelectionColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _componentGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final choiceCount = currentRound.componentChoices.length;
        const horizontalGap = 11.0;
        const verticalGap = 13.0;
        const fiveColumnWidth =
            (GakujiDomino.width * 5) + (horizontalGap * 4);
        final canFitFiveColumns = constraints.maxWidth >= fiveColumnWidth;
        final columns = choiceCount >= 9 && canFitFiveColumns ? 5 : 4;
        final gridWidth =
            (GakujiDomino.width * columns) +
            (horizontalGap * (columns - 1));

        final rows = <List<int>>[];

        for (var start = 0; start < choiceCount; start += columns) {
          final end = math.min(start + columns, choiceCount);
          rows.add(List<int>.generate(end - start, (index) => start + index));
        }

        return SizedBox(
          width: gridWidth,
          child: Column(
            children: List.generate(rows.length, (rowIndex) {
              return Padding(
                padding: EdgeInsets.only(
                  top: rowIndex == 0 ? 0 : verticalGap,
                ),
                child: _componentChoiceRow(
                  indexes: rows[rowIndex],
                  gap: horizontalGap,
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _componentChoiceRow({
    required List<int> indexes,
    required double gap,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(indexes.length, (position) {
        return Padding(
          padding: EdgeInsets.only(
            right: position == indexes.length - 1 ? 0 : gap,
          ),
          child: _componentTile(index: indexes[position]),
        );
      }),
    );
  }

  Widget _componentTile({required int index}) {
    switch (selectedDifficulty) {
      case KanjiFusionDifficulty.easy:
      case KanjiFusionDifficulty.normal:
        return _slottedComponentTile(index: index);
      case KanjiFusionDifficulty.hard:
        return _hardComponentTile(index: index);
    }
  }

  Widget _slottedComponentTile({required int index}) {
    final component = currentRound.componentChoices[index];
    final placed = placedChoiceIndexes.contains(index);

    if (selectedDifficulty == KanjiFusionDifficulty.normal) {
      final forms = currentRound.formsForChoice(index);
      final currentForm = _currentChoiceForm(index);
      final transformable = forms.length > 1;
      final selectedFormIndex = index < choiceFormIndexes.length
          ? choiceFormIndexes[index].clamp(0, forms.length - 1).toInt()
          : 0;
      final tile = _choiceTileSurface(
        component: currentForm,
        showFormControl: transformable,
        formCount: forms.length,
        selectedFormIndex: selectedFormIndex,
        onTap: transformable ? () => _cycleChoiceForm(index) : null,
      );

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: placed
            ? _emptyChoiceFootprint(
                key: ValueKey('slotted_empty_$index'),
              )
            : Draggable<_FusionDragData>(
                key: ValueKey('slotted_choice_$index'),
                data: _FusionDragData(
                  choiceIndex: index,
                  componentForm: currentForm,
                ),
                dragAnchorStrategy: pointerDragAnchorStrategy,
                maxSimultaneousDrags: hasSubmitted ? 0 : 1,
                feedback: Material(
                  color: Colors.transparent,
                  child: _dragFeedback(currentForm),
                ),
                childWhenDragging: _emptyChoiceFootprint(),
                child: tile,
              ),
      );
    }

    final active = activeChoiceIndex == index;
    final forms = currentRound.formsForChoice(index);
    final resolvedForm = active && activeChoiceForm != null
        ? activeChoiceForm
        : forms.length == 1
            ? forms.first
            : null;
    final displayComponent = active && activeChoiceForm != null
        ? activeChoiceForm!
        : component;

    final tile = _choiceTileSurface(
      component: displayComponent,
      selected: active,
      onTap: () {
        _toggleChoice(index);
      },
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: placed
          ? _emptyChoiceFootprint(
              key: ValueKey('slotted_empty_$index'),
            )
          : resolvedForm == null
              ? KeyedSubtree(
                  key: ValueKey('slotted_choice_unresolved_$index'),
                  child: tile,
                )
              : Draggable<_FusionDragData>(
                  key: ValueKey('slotted_choice_$index'),
                  data: _FusionDragData(
                    choiceIndex: index,
                    componentForm: resolvedForm,
                  ),
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  maxSimultaneousDrags: hasSubmitted ? 0 : 1,
                  feedback: Material(
                    color: Colors.transparent,
                    child: _dragFeedback(resolvedForm),
                  ),
                  childWhenDragging: _emptyChoiceFootprint(),
                  child: tile,
                ),
    );
  }

  Widget _hardComponentTile({required int index}) {
    final component = currentRound.componentChoices[index];
    final placed = placedBlocks.any(
      (block) => block.choiceIndex == index,
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: placed
          ? _emptyChoiceFootprint(
              key: ValueKey('hard_empty_$index'),
            )
          : Draggable<_FusionDragData>(
              key: ValueKey('hard_choice_$index'),
              data: _FusionDragData(
                choiceIndex: index,
                componentForm: component,
              ),
              dragAnchorStrategy: pointerDragAnchorStrategy,
              maxSimultaneousDrags: hasSubmitted ? 0 : 1,
              feedback: Material(
                color: Colors.transparent,
                child: _dragFeedback(component),
              ),
              childWhenDragging: _emptyChoiceFootprint(),
              child: _choiceTileSurface(component: component),
            ),
    );
  }

  Widget _emptyChoiceFootprint({Key? key}) {
    return SizedBox(
      key: key,
      width: GakujiDomino.width,
      height: GakujiDomino.height,
    );
  }

  Widget _choiceTileSurface({
    required String component,
    bool selected = false,
    bool showFormControl = false,
    int formCount = 1,
    int selectedFormIndex = 0,
    VoidCallback? onTap,
  }) {
    return GakujiDomino(
      text: component,
      selected: selected,
      selectionColor: _blockSelectionColor,
      showFormControl: showFormControl,
      formCount: formCount,
      selectedFormIndex: selectedFormIndex,
      onTap: onTap,
    );
  }

  Widget _dragFeedback(String component) {
    return GakujiDomino(
      text: component,
      dragging: true,
    );
  }

  Widget _successfulFusionResultCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final comparisonCardWidth = (constraints.maxWidth - 14) / 2;

        return Column(
          children: [
            SizedBox(
              width: comparisonCardWidth,
              child: _fusionComparisonCard(
                title: 'Your Fusion',
                accentColor: _accentColor,
                child: _placedFusionPreview(
                  previewSize: 112,
                  maxFontSize: 22,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(GakujiRadius.pill),
                border: Border.all(
                  color: _accentColor,
                  width: 1.5,
                ),
              ),
              child: Text(
                'Successful fusion',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _accentColor,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _failedFusionComparison() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _fusionComparisonCard(
                title: 'Your Fusion',
                accentColor: _studyIncorrectRed,
                child: _placedFusionPreview(
                  previewSize: 112,
                  maxFontSize: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _fusionComparisonCard(
                title: 'Correct Fusion',
                accentColor: _accentColor.withValues(alpha: 0.82),
                child: _correctFusionPreview(
                  previewSize: 112,
                  maxFontSize: 22,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: _studyIncorrectRedFill,
            borderRadius: BorderRadius.circular(GakujiRadius.pill),
            border: Border.all(
              color: _studyIncorrectRed,
              width: 1.5,
            ),
          ),
          child: Text(
            'Fusion failed',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _studyIncorrectRed,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fusionComparisonCard({
    required String title,
    required Color accentColor,
    required Widget child,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 190),
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accentColor,
          width: 3,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: GakujiColors.mediumGray,
            ),
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.82, end: 1),
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutBack,
            builder: (context, value, animatedChild) {
              return Transform.scale(
                scale: value,
                child: animatedChild,
              );
            },
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _placedFusionPreview({
    double previewSize = 150,
    double maxFontSize = 28,
  }) {
    switch (selectedDifficulty) {
      case KanjiFusionDifficulty.easy:
        return Text(
          selectedComponents.join(''),
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: GakujiFonts.japanese,
            fontSize: selectedComponents.length >= 4 ? 50 : 66,
            height: 1.05,
            fontWeight: FontWeight.w600,
            color: GakujiColors.darkGray,
          ),
        );
      case KanjiFusionDifficulty.normal:
        return _structuredFusionPreview(
          previewSize: previewSize,
          maxFontSize: maxFontSize,
        );
      case KanjiFusionDifficulty.hard:
        return _hardFusionPreview();
    }
  }

  Widget _correctFusionPreview({
    double previewSize = 150,
    double maxFontSize = 28,
  }) {
    switch (selectedDifficulty) {
      case KanjiFusionDifficulty.easy:
        return Text(
          currentRound.requiredComponents.join(''),
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: GakujiFonts.japanese,
            fontSize: currentRound.requiredComponents.length >= 4 ? 42 : 56,
            height: 1.05,
            fontWeight: FontWeight.w600,
            color: GakujiColors.darkGray,
          ),
        );
      case KanjiFusionDifficulty.normal:
        return _structuredFusionPreview(
          showCorrectComponents: true,
          previewSize: previewSize,
          maxFontSize: maxFontSize,
        );
      case KanjiFusionDifficulty.hard:
        return _structuredFusionPreview(
          showCorrectComponents: true,
          previewSize: previewSize,
          maxFontSize: maxFontSize,
        );
    }
  }

  Widget _structuredFusionPreview({
    bool showCorrectComponents = false,
    double previewSize = 150,
    double maxFontSize = 28,
  }) {
    return SizedBox(
      width: previewSize,
      height: previewSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final group in currentRound.structuralGroups)
            Positioned(
              left: group.left * previewSize,
              top: group.top * previewSize,
              width: group.width * previewSize,
              height: group.height * previewSize,
              child: _structuralGroupOutline(group, preview: true),
            ),
          ...List.generate(currentRound.structuralSlots.length, (index) {
            final slot = currentRound.structuralSlots[index];
            final component = showCorrectComponents
                ? slot.component
                : placedComponentForms[index];

            return Positioned(
              left: slot.left * previewSize,
              top: slot.top * previewSize,
              width: slot.width * previewSize,
              height: slot.height * previewSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: _structuralSlotSurface(
                      slot: slot,
                      outlineColor: _blockOutlineColor,
                      isFilled: component != null,
                      showShadow: false,
                    ),
                  ),
                  if (component != null)
                    Positioned(
                      left: slot.contentLeft * slot.width * previewSize,
                      top: slot.contentTop * slot.height * previewSize,
                      width: slot.contentWidth * slot.width * previewSize,
                      height: slot.contentHeight * slot.height * previewSize,
                      child: _structuralComponentGlyph(
                        component,
                        maxFontSize: maxFontSize,
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _hardFusionPreview() {
    const previewSize = 150.0;
    final previewBlockSize =
        (_placedBlockSize / _fusionFieldSize) * previewSize;

    return SizedBox(
      width: previewSize,
      height: previewSize,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: List.generate(placedBlocks.length, (placedIndex) {
          final block = placedBlocks[placedIndex];
          final component = block.component;

          return Positioned(
            left: (block.position.dx / _fusionFieldSize) * previewSize,
            top: (block.position.dy / _fusionFieldSize) * previewSize,
            child: Container(
              width: previewBlockSize,
              height: previewBlockSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _blockFillColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _blockOutlineColor,
                  width: 1,
                ),
              ),
              child: Text(
                component,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontFamily: GakujiFonts.japanese,
                  fontSize: component.length > 1 ? 15 : 22,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: _blockTextColor,
                ),
              ),
            ),
          );
        }),
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
                            label: 'Correct fusions',
                            value: correctCount,
                          ),
                          const SizedBox(height: 12),
                          _completionStatRow(
                            label: 'Incorrect fusions',
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
                    'This deck does not contain any supported kanji with two or more components yet.',
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.small.copyWith(
                      color: GakujiColors.mediumGray,
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

class _NestedGroupOutlinePainter extends CustomPainter {
  final Color color;
  final Color fillColor;
  final double radius;
  final double strokeWidth;

  const _NestedGroupOutlinePainter({
    required this.color,
    required this.fillColor,
    required this.radius,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(math.min(radius, size.shortestSide * 0.22)),
    );

    canvas.drawRRect(
      rect,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );

    final path = Path()..addRRect(rect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 6, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NestedGroupOutlinePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _GateSlotPainter extends CustomPainter {
  final Color color;
  final Color fillColor;
  final bool isFilled;
  final bool showShadow;

  const _GateSlotPainter({
    required this.color,
    required this.fillColor,
    required this.isFilled,
    required this.showShadow,
  });

  Path _gatePath(Size size) {
    final outerLeft = 0.0;
    final outerTop = 0.0;
    final outerRight = size.width;
    final outerBottom = size.height;
    final innerLeft = size.width * 0.22;
    final innerTop = size.height * 0.24;
    final innerRight = size.width * 0.78;
    final outerRadius = math.min(17.0, size.shortestSide * 0.12);
    final innerRadius = math.min(15.0, size.shortestSide * 0.10);

    return Path()
      ..moveTo(outerLeft + outerRadius, outerTop)
      ..lineTo(outerRight - outerRadius, outerTop)
      ..quadraticBezierTo(
        outerRight,
        outerTop,
        outerRight,
        outerTop + outerRadius,
      )
      ..lineTo(outerRight, outerBottom - outerRadius)
      ..quadraticBezierTo(
        outerRight,
        outerBottom,
        outerRight - outerRadius,
        outerBottom,
      )
      ..lineTo(innerRight + innerRadius, outerBottom)
      ..quadraticBezierTo(
        innerRight,
        outerBottom,
        innerRight,
        outerBottom - innerRadius,
      )
      ..lineTo(innerRight, innerTop + innerRadius)
      ..quadraticBezierTo(
        innerRight,
        innerTop,
        innerRight - innerRadius,
        innerTop,
      )
      ..lineTo(innerLeft + innerRadius, innerTop)
      ..quadraticBezierTo(
        innerLeft,
        innerTop,
        innerLeft,
        innerTop + innerRadius,
      )
      ..lineTo(innerLeft, outerBottom - innerRadius)
      ..quadraticBezierTo(
        innerLeft,
        outerBottom,
        innerLeft - innerRadius,
        outerBottom,
      )
      ..lineTo(outerLeft + outerRadius, outerBottom)
      ..quadraticBezierTo(
        outerLeft,
        outerBottom,
        outerLeft,
        outerBottom - outerRadius,
      )
      ..lineTo(outerLeft, outerTop + outerRadius)
      ..quadraticBezierTo(
        outerLeft,
        outerTop,
        outerLeft + outerRadius,
        outerTop,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _gatePath(size);

    if (isFilled) {
      if (showShadow) {
        canvas.drawShadow(
          path,
          Colors.black.withValues(alpha: 0.16),
          6,
          false,
        );
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      return;
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;

      while (distance < metric.length) {
        final next = math.min(distance + 9, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 15;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GateSlotPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.isFilled != isFilled ||
        oldDelegate.showShadow != showShadow;
  }
}

class _EnclosureSlotPainter extends CustomPainter {
  final Color color;
  final Color fillColor;
  final bool isFilled;
  final bool showShadow;

  const _EnclosureSlotPainter({
    required this.color,
    required this.fillColor,
    required this.isFilled,
    required this.showShadow,
  });

  Path _enclosurePath(Size size) {
    final outerRadius = math.min(17.0, size.shortestSide * 0.10);
    final innerRadius = math.min(15.0, size.shortestSide * 0.09);
    final insetX = size.width * 0.22;
    final insetY = size.height * 0.22;

    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(outerRadius),
    );
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        insetX,
        insetY,
        size.width - insetX,
        size.height - insetY,
      ),
      Radius.circular(innerRadius),
    );

    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outer)
      ..addRRect(inner);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _enclosurePath(size);

    if (isFilled) {
      if (showShadow) {
        canvas.drawShadow(
          path,
          Colors.black.withValues(alpha: 0.16),
          6,
          false,
        );
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      return;
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;

      while (distance < metric.length) {
        final next = math.min(distance + 9, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 15;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EnclosureSlotPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.isFilled != isFilled ||
        oldDelegate.showShadow != showShadow;
  }
}

class _CliffSlotPainter extends CustomPainter {
  final Color color;
  final Color fillColor;
  final bool isFilled;
  final bool showShadow;

  const _CliffSlotPainter({
    required this.color,
    required this.fillColor,
    required this.isFilled,
    required this.showShadow,
  });

  Path _cliffPath(Size size) {
    final outerRadius = math.min(17.0, size.shortestSide * 0.12);
    final innerRadius = math.min(14.0, size.shortestSide * 0.10);
    final legRight = size.width * 0.34;
    final barBottom = size.height * 0.30;

    return Path()
      ..moveTo(outerRadius, 0)
      ..lineTo(size.width - outerRadius, 0)
      ..quadraticBezierTo(
        size.width,
        0,
        size.width,
        outerRadius,
      )
      ..lineTo(size.width, barBottom - outerRadius)
      ..quadraticBezierTo(
        size.width,
        barBottom,
        size.width - outerRadius,
        barBottom,
      )
      ..lineTo(legRight + innerRadius, barBottom)
      ..quadraticBezierTo(
        legRight,
        barBottom,
        legRight,
        barBottom + innerRadius,
      )
      ..lineTo(legRight, size.height - outerRadius)
      ..quadraticBezierTo(
        legRight,
        size.height,
        legRight - outerRadius,
        size.height,
      )
      ..lineTo(outerRadius, size.height)
      ..quadraticBezierTo(
        0,
        size.height,
        0,
        size.height - outerRadius,
      )
      ..lineTo(0, outerRadius)
      ..quadraticBezierTo(0, 0, outerRadius, 0)
      ..close();
  }

  void _drawDashedPath(Canvas canvas, Path path) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 9, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 15;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _cliffPath(size);

    if (!isFilled) {
      _drawDashedPath(canvas, path);
      return;
    }

    if (showShadow) {
      canvas.drawShadow(
        path,
        Colors.black.withValues(alpha: 0.16),
        6,
        false,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CliffSlotPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.isFilled != isFilled ||
        oldDelegate.showShadow != showShadow;
  }
}

class _RightHookSlotPainter extends CustomPainter {
  final Color color;
  final Color fillColor;
  final bool isFilled;
  final bool showShadow;

  const _RightHookSlotPainter({
    required this.color,
    required this.fillColor,
    required this.isFilled,
    required this.showShadow,
  });

  Path _rightHookPath(Size size) {
    final outerRadius = math.min(17.0, size.shortestSide * 0.12);
    final innerRadius = math.min(14.0, size.shortestSide * 0.10);
    final legLeft = size.width * 0.64;
    final barBottom = size.height * 0.30;

    return Path()
      ..moveTo(outerRadius, 0)
      ..lineTo(size.width - outerRadius, 0)
      ..quadraticBezierTo(
        size.width,
        0,
        size.width,
        outerRadius,
      )
      ..lineTo(size.width, size.height - outerRadius)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width - outerRadius,
        size.height,
      )
      ..lineTo(legLeft + outerRadius, size.height)
      ..quadraticBezierTo(
        legLeft,
        size.height,
        legLeft,
        size.height - outerRadius,
      )
      ..lineTo(legLeft, barBottom + innerRadius)
      ..quadraticBezierTo(
        legLeft,
        barBottom,
        legLeft - innerRadius,
        barBottom,
      )
      ..lineTo(outerRadius, barBottom)
      ..quadraticBezierTo(
        0,
        barBottom,
        0,
        barBottom - outerRadius,
      )
      ..lineTo(0, outerRadius)
      ..quadraticBezierTo(0, 0, outerRadius, 0)
      ..close();
  }

  void _drawDashedPath(Canvas canvas, Path path) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 9, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 15;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _rightHookPath(size);

    if (!isFilled) {
      _drawDashedPath(canvas, path);
      return;
    }

    if (showShadow) {
      canvas.drawShadow(
        path,
        Colors.black.withValues(alpha: 0.16),
        6,
        false,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RightHookSlotPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.isFilled != isFilled ||
        oldDelegate.showShadow != showShadow;
  }
}

class _DashedCutoutSlotPainter extends CustomPainter {
  final Color color;

  const _DashedCutoutSlotPainter({
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cutoutLeft = size.width * 0.35;
    final cutoutTop = size.height * 0.30;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, cutoutTop)
      ..lineTo(cutoutLeft, cutoutTop)
      ..lineTo(cutoutLeft, size.height)
      ..lineTo(0, size.height)
      ..close();

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;

      while (distance < metric.length) {
        final next = math.min(distance + 9, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 15;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCutoutSlotPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _DashedRoundedRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedRoundedRectPainter({
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;

      while (distance < metric.length) {
        final next = math.min(distance + 9, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 15;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
