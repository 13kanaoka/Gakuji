import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gakuji/widgets/gakuji_styles.dart';

enum DetectiveFlowPhase {
  offstage,
  walkingIn,
  sittingDown,
  roomReady,
  lookingDown,
  deskReady,
  resolving,
  lookingUp,
  standingUp,
  walkingOut,
}

enum FileMotionPhase {
  steady,
  entering,
  exiting,
}

class DetectiveFullFlowTestPage extends StatefulWidget {
  const DetectiveFullFlowTestPage({
    super.key,
  });

  @override
  State<DetectiveFullFlowTestPage> createState() =>
      _DetectiveFullFlowTestPageState();
}

class _DetectiveFullFlowTestPageState extends State<DetectiveFullFlowTestPage>
    with TickerProviderStateMixin {
  late final AnimationController _walkController;
  late final AnimationController _sitController;
  late final AnimationController _idleController;
  late final AnimationController _cameraController;
  late final AnimationController _fileController;
  late final AnimationController _fileSlideController;
  late final AnimationController _stampController;
  late final AnimationController _poofController;

  late final Animation<double> _cameraPan;
  late final Animation<double> _fileMorph;
  late final Animation<double> _fileDetailsOpacity;
  late final Animation<double> _buttonOpacity;

  DetectiveFlowPhase phase = DetectiveFlowPhase.offstage;
  FileMotionPhase fileMotionPhase = FileMotionPhase.steady;

  bool busy = false;
  bool deskOnlyView = false;

  bool? lastAnswerApproved;
  bool? lastAnswerCorrect;

  int visitorIndex = 0;

  final List<_TestRound> rounds = const [
    _TestRound(
      visitor: '食べる',
      reading: 'たべる',
      partOfSpeech: 'Verb',
      definition: 'to eat',
      isReal: true,
    ),
    _TestRound(
      visitor: '猫',
      reading: 'ねこ',
      partOfSpeech: 'Noun',
      definition: 'school',
      isReal: false,
    ),
    _TestRound(
      visitor: '見る',
      reading: 'みる',
      partOfSpeech: 'Verb',
      definition: 'to see',
      isReal: true,
    ),
    _TestRound(
      visitor: '先生',
      reading: 'せんせい',
      partOfSpeech: 'Noun',
      definition: 'cat',
      isReal: false,
    ),
  ];

  static const Color roomWallColor = Color(0xFFD8D0C1);
  static const Color floorColor = Color(0xFFC9B89E);
  static const Color deskColor = Color(0xFFE7D4B6);
  static const Color chairColor = Color(0xFFBFA27A);

  _TestRound get currentRound => rounds[visitorIndex];

  bool get canAnswer => !busy && phase == DetectiveFlowPhase.deskReady;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _walkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    _sitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat();

    _cameraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );

    _fileController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );

    _fileSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 430),
    );

    _stampController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    _poofController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    _cameraPan = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _cameraController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _fileMorph = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _fileController,
        curve: const Interval(
          0.05,
          0.82,
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _fileDetailsOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _fileController,
        curve: const Interval(
          0.42,
          0.92,
          curve: Curves.easeOut,
        ),
      ),
    );

    _buttonOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _fileController,
        curve: const Interval(
          0.56,
          1.0,
          curve: Curves.easeOut,
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      startFlow();
    });
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    _walkController.dispose();
    _sitController.dispose();
    _idleController.dispose();
    _cameraController.dispose();
    _fileController.dispose();
    _fileSlideController.dispose();
    _stampController.dispose();
    _poofController.dispose();

    super.dispose();
  }

  Future<void> startFlow() async {
    if (busy) return;

    if (deskOnlyView) {
      await _startDeskOnlyFlow();
    } else {
      await _startVisitorFlow();
    }
  }

  Future<void> _startVisitorFlow() async {
    busy = true;

    _cameraController.reset();
    _fileController.reset();
    _fileSlideController.reset();
    _stampController.reset();
    _poofController.reset();

    setState(() {
      fileMotionPhase = FileMotionPhase.steady;
      lastAnswerApproved = null;
      lastAnswerCorrect = null;
    });

    await _runVisitorEntrance();
    await Future.delayed(const Duration(milliseconds: 240));
    await _lookDownToDesk();

    if (!mounted) return;

    setState(() {
      phase = DetectiveFlowPhase.deskReady;
    });

    busy = false;
  }

  Future<void> _startDeskOnlyFlow() async {
    busy = true;

    _walkController.reset();
    _sitController.reset();
    _cameraController.value = 1;
    _fileController.value = 1;
    _stampController.reset();
    _poofController.reset();
    _fileSlideController.reset();

    setState(() {
      phase = DetectiveFlowPhase.lookingDown;
      fileMotionPhase = FileMotionPhase.entering;
      lastAnswerApproved = null;
      lastAnswerCorrect = null;
    });

    await _fileSlideController.forward(from: 0);

    if (!mounted) return;

    _fileSlideController.reset();

    setState(() {
      phase = DetectiveFlowPhase.deskReady;
      fileMotionPhase = FileMotionPhase.steady;
    });

    busy = false;
  }

  Future<void> answer(bool approved) async {
    if (!canAnswer) return;

    if (deskOnlyView) {
      await _answerDeskOnly(approved);
    } else {
      await _answerVisitorFlow(approved);
    }
  }

  Future<void> _answerVisitorFlow(bool approved) async {
    busy = true;

    final correctAnswerIsApprove = currentRound.isReal;
    final wasCorrect = approved == correctAnswerIsApprove;

    setState(() {
      phase = DetectiveFlowPhase.resolving;
      lastAnswerApproved = approved;
      lastAnswerCorrect = wasCorrect;
    });

    await _stampController.forward(from: 0);

    if (!mounted) return;

    await Future.delayed(const Duration(milliseconds: 260));

    await _lookUpToRoom();

    if (!mounted) return;

    if (!currentRound.isReal) {
      setState(() {
        phase = DetectiveFlowPhase.roomReady;
      });

      await _poofController.forward(from: 0);

      if (!mounted) return;

      await Future.delayed(const Duration(milliseconds: 460));
    }

    await _runVisitorExit();

    if (!mounted) return;

    setState(() {
      visitorIndex = (visitorIndex + 1) % rounds.length;
      lastAnswerApproved = null;
      lastAnswerCorrect = null;
    });

    await _runVisitorEntrance();
    await Future.delayed(const Duration(milliseconds: 240));
    await _lookDownToDesk();

    if (!mounted) return;

    setState(() {
      phase = DetectiveFlowPhase.deskReady;
    });

    busy = false;
  }

  Future<void> _answerDeskOnly(bool approved) async {
    busy = true;

    final correctAnswerIsApprove = currentRound.isReal;
    final wasCorrect = approved == correctAnswerIsApprove;

    setState(() {
      phase = DetectiveFlowPhase.resolving;
      lastAnswerApproved = approved;
      lastAnswerCorrect = wasCorrect;
    });

    await _stampController.forward(from: 0);

    if (!mounted) return;

    await Future.delayed(const Duration(milliseconds: 220));

    setState(() {
      fileMotionPhase = FileMotionPhase.exiting;
    });

    await _fileSlideController.forward(from: 0);

    if (!mounted) return;

    _fileSlideController.reset();
    _stampController.reset();

    setState(() {
      visitorIndex = (visitorIndex + 1) % rounds.length;
      lastAnswerApproved = null;
      lastAnswerCorrect = null;
      fileMotionPhase = FileMotionPhase.entering;
      phase = DetectiveFlowPhase.lookingDown;
    });

    await _fileSlideController.forward(from: 0);

    if (!mounted) return;

    _fileSlideController.reset();

    setState(() {
      fileMotionPhase = FileMotionPhase.steady;
      phase = DetectiveFlowPhase.deskReady;
    });

    busy = false;
  }

  Future<void> _runVisitorEntrance() async {
    _walkController.reset();
    _sitController.reset();
    _poofController.reset();
    _stampController.reset();

    setState(() {
      phase = DetectiveFlowPhase.walkingIn;
    });

    await _walkController.forward();

    if (!mounted) return;

    setState(() {
      phase = DetectiveFlowPhase.sittingDown;
    });

    await _sitController.forward();

    if (!mounted) return;

    setState(() {
      phase = DetectiveFlowPhase.roomReady;
    });
  }

  Future<void> _runVisitorExit() async {
    setState(() {
      phase = DetectiveFlowPhase.standingUp;
    });

    await _sitController.reverse();

    if (!mounted) return;

    _walkController.reset();

    setState(() {
      phase = DetectiveFlowPhase.walkingOut;
    });

    await _walkController.forward();

    if (!mounted) return;

    setState(() {
      phase = DetectiveFlowPhase.offstage;
    });
  }

  Future<void> _lookDownToDesk() async {
    setState(() {
      phase = DetectiveFlowPhase.lookingDown;
    });

    await Future.wait([
      _cameraController.forward(from: 0),
      _fileController.forward(from: 0),
    ]);
  }

  Future<void> _lookUpToRoom() async {
    setState(() {
      phase = DetectiveFlowPhase.lookingUp;
    });

    await Future.wait([
      _cameraController.reverse(),
      _fileController.reverse(),
    ]);
  }

  void toggleDeskOnlyView() {
    if (busy) return;

    final wasDeskOnlyView = deskOnlyView;
    final isCurrentlyAtDesk =
      phase == DetectiveFlowPhase.deskReady && _cameraController.value >= 0.99;

    setState(() {
      deskOnlyView = !deskOnlyView;
    });

    // If the player toggles while already looking at the desk,
    // do not restart the scene. Just change what happens after
    // the next Approve / Deny press.
    if (isCurrentlyAtDesk) {
      if (wasDeskOnlyView && !deskOnlyView) {
        // We are switching from Desk Only back to full visitor animation.
        // Since the room was skipped, prepare the hidden visitor state so
        // the next look-up animation reveals the visitor seated correctly.
        _walkController.value = 1;
        _sitController.value = 1;
        _cameraController.value = 1;
        _fileController.value = 1;

        _fileSlideController.reset();
        _stampController.reset();
        _poofController.reset();
  
        setState(() {
          phase = DetectiveFlowPhase.deskReady;
          fileMotionPhase = FileMotionPhase.steady;
          lastAnswerApproved = null;
          lastAnswerCorrect = null;
        });
      }

      return;
    }

    // If toggled from the room/start state, restart into the chosen mode.
    resetFlow();
  }

  void resetFlow() {
    if (busy) return;

    setState(() {
      phase = DetectiveFlowPhase.offstage;
      fileMotionPhase = FileMotionPhase.steady;
      visitorIndex = 0;
      lastAnswerApproved = null;
      lastAnswerCorrect = null;
    });

    _walkController.reset();
    _sitController.reset();
    _cameraController.reset();
    _fileController.reset();
    _fileSlideController.reset();
    _stampController.reset();
    _poofController.reset();

    startFlow();
  }

  double _lerp(double start, double end, double progress) {
    return start + ((end - start) * progress);
  }

  double _easeOut(double value) {
    return Curves.easeOutCubic.transform(value.clamp(0.0, 1.0));
  }

  double _easeInOut(double value) {
    return Curves.easeInOutCubic.transform(value.clamp(0.0, 1.0));
  }

  double _clampDouble(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  double _fileSlideOffset(double screenWidth) {
    final progress = Curves.easeInOutCubic.transform(
      _fileSlideController.value.clamp(0.0, 1.0),
    );

    if (fileMotionPhase == FileMotionPhase.exiting) {
      return _lerp(0, -screenWidth * 0.95, progress);
    }

    if (fileMotionPhase == FileMotionPhase.entering) {
      return _lerp(screenWidth * 0.95, 0, progress);
    }

    return 0;
  }

  double _fileSlideOpacity() {
    final progress = Curves.easeInOutCubic.transform(
      _fileSlideController.value.clamp(0.0, 1.0),
    );

    if (fileMotionPhase == FileMotionPhase.exiting) {
      return (1 - progress).clamp(0.0, 1.0);
    }

    if (fileMotionPhase == FileMotionPhase.entering) {
      return progress.clamp(0.0, 1.0);
    }

    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;

            return AnimatedBuilder(
              animation: Listenable.merge([
                _walkController,
                _sitController,
                _idleController,
                _cameraController,
                _fileController,
                _fileSlideController,
                _stampController,
                _poofController,
              ]),
              builder: (context, child) {
                return ClipRect(
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minWidth: screenWidth,
                          maxWidth: screenWidth,
                          minHeight: screenHeight * 2,
                          maxHeight: screenHeight * 2,
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              -screenHeight * _cameraPan.value,
                            ),
                            child: SizedBox(
                              width: screenWidth,
                              height: screenHeight * 2,
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: screenWidth,
                                    height: screenHeight,
                                    child: _roomScene(
                                      width: screenWidth,
                                      height: screenHeight,
                                    ),
                                  ),
                                  SizedBox(
                                    width: screenWidth,
                                    height: screenHeight,
                                    child: _deskScene(
                                      width: screenWidth,
                                      height: screenHeight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _topControls(),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _roomScene({
    required double width,
    required double height,
  }) {
    final floorHeight = height * 0.25;
    final deskHeight = height * 0.17;

    final chairCenterX = width / 2;
    final chairBottom = deskHeight - 6;

    final visitorMetrics = _visitorMetrics(
      width: width,
      deskHeight: deskHeight,
      chairCenterX: chairCenterX,
    );

    return Container(
      color: roomWallColor,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: floorHeight,
            child: Container(
              color: floorColor,
            ),
          ),
          Positioned(
            top: 28,
            left: 88,
            child: _window(),
          ),
          Positioned(
            top: 28,
            right: 88,
            child: _window(),
          ),
          Positioned(
            left: 36,
            bottom: floorHeight + 8,
            child: _bookshelf(),
          ),
          Positioned(
            right: 48,
            bottom: floorHeight + 28,
            child: _plant(),
          ),
          Positioned(
            left: chairCenterX - 95,
            bottom: chairBottom + 64,
            child: _chairBack(),
          ),
          Positioned(
            left: visitorMetrics.left,
            bottom: visitorMetrics.bottom,
            child: Transform.translate(
              offset: Offset(
                0,
                visitorMetrics.bob,
              ),
              child: Transform.rotate(
                angle: visitorMetrics.rotation,
                child: Transform.scale(
                  scaleX: visitorMetrics.scaleX,
                  scaleY: visitorMetrics.scaleY,
                  child: Opacity(
                    opacity: visitorMetrics.opacity,
                    child: _visitorRevealStack(
                      term: currentRound.visitor,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: chairCenterX - 88,
            bottom: chairBottom + 38,
            child: _chairSeatFront(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: deskHeight,
            child: _roomDeskEdge(),
          ),
        ],
      ),
    );
  }

  _VisitorMetrics _visitorMetrics({
    required double width,
    required double deskHeight,
    required double chairCenterX,
  }) {
    const visitorWidth = 168.0;

    final seatedLeft = chairCenterX - (visitorWidth / 2);
    final rightOffscreen = width + 90;
    const leftOffscreen = -230.0;

    final walkRaw = _walkController.value;
    final walkProgress = _easeOut(walkRaw);

    final sitRaw = _sitController.value;
    final sitProgress = _easeInOut(sitRaw);

    double left = rightOffscreen;
    double opacity = 0;
    double baseScale = 0.96;
    double rotation = 0;

    if (phase == DetectiveFlowPhase.offstage) {
      left = rightOffscreen;
      opacity = 0;
      baseScale = 0.96;
    }

    if (phase == DetectiveFlowPhase.walkingIn) {
      left = _lerp(
        rightOffscreen,
        seatedLeft,
        walkProgress,
      );

      opacity = (walkRaw * 1.8).clamp(0.0, 1.0);
      baseScale = _lerp(0.96, 1.0, walkProgress);
      rotation = math.sin(walkRaw * math.pi * 6) * 0.03;
    }

    if (phase == DetectiveFlowPhase.sittingDown ||
        phase == DetectiveFlowPhase.roomReady ||
        phase == DetectiveFlowPhase.lookingDown ||
        phase == DetectiveFlowPhase.deskReady ||
        phase == DetectiveFlowPhase.resolving ||
        phase == DetectiveFlowPhase.lookingUp ||
        phase == DetectiveFlowPhase.standingUp) {
      left = seatedLeft;
      opacity = 1;
      baseScale = 1;

      final idleWave = math.sin(_idleController.value * math.pi * 2);
      rotation = idleWave * 0.01;
    }

    if (phase == DetectiveFlowPhase.walkingOut) {
      left = _lerp(
        seatedLeft,
        leftOffscreen,
        walkProgress,
      );

      opacity = (1 - ((walkRaw - 0.68) / 0.32)).clamp(0.0, 1.0);
      baseScale = _lerp(1.0, 0.94, walkProgress);
      rotation = math.sin(walkRaw * math.pi * 6) * 0.03;
    }

    final isWalking = phase == DetectiveFlowPhase.walkingIn ||
        phase == DetectiveFlowPhase.walkingOut;

    final walkingBob = math.sin(walkRaw * math.pi * 8) * 7;
    final idleBob = math.sin(_idleController.value * math.pi * 2) * 2.5;
    final bob = isWalking ? walkingBob : idleBob;

    final sitDrop = _lerp(0, -38, sitProgress);
    final sitSquash = math.sin(sitProgress * math.pi);

    final scaleX = baseScale + (sitSquash * 0.035);
    final scaleY = baseScale - (sitSquash * 0.045);

    return _VisitorMetrics(
      left: left,
      bottom: deskHeight + 16 + sitDrop,
      bob: bob,
      opacity: opacity,
      rotation: rotation,
      scaleX: scaleX,
      scaleY: scaleY,
    );
  }

  Widget _deskScene({
    required double width,
    required double height,
  }) {
    final progress = _fileMorph.value;

    final fileWidth = _lerp(230, 530, progress);
    final fileHeight = _lerp(44, 258, progress);

    final fileLeft = _lerp(
      (width - fileWidth) / 2,
      62,
      progress,
    );

    final fileTop = _lerp(
      14,
      _clampDouble((height - fileHeight) / 2, 44.0, 72.0),
      progress,
    );

    final buttonsTop = _clampDouble((height - 176) / 2, 46.0, 118.0);

    return Container(
      decoration: BoxDecoration(
        color: deskColor,
        border: Border(
          top: BorderSide(
            color: GakujiColors.darkGray,
            width: 4,
          ),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DeskTexturePainter(
                opacity: 0.13,
              ),
            ),
          ),
          Positioned(
            left: 28,
            bottom: 28,
            child: Opacity(
              opacity: 0.22,
              child: _smallPaperStack(),
            ),
          ),
          Positioned(
            left: fileLeft,
            top: fileTop,
            child: Transform.translate(
              offset: Offset(
                _fileSlideOffset(width),
                0,
              ),
              child: Opacity(
                opacity: _fileSlideOpacity(),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _perspectiveFile(
                      width: fileWidth,
                      height: fileHeight,
                      progress: progress,
                    ),
                    _stampOverlay(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 52,
            top: buttonsTop,
            child: Opacity(
              opacity: _buttonOpacity.value,
              child: IgnorePointer(
                ignoring: !canAnswer,
                child: _buttons(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _perspectiveFile({
    required double width,
    required double height,
    required double progress,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _PerspectiveFilePainter(
          progress: progress,
        ),
        child: ClipPath(
          clipper: _PerspectiveFileClipper(
            progress: progress,
          ),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              _lerp(18, 28, progress),
              _lerp(5, 22, progress),
              _lerp(18, 28, progress),
              _lerp(6, 22, progress),
            ),
            child: Opacity(
              opacity: _fileDetailsOpacity.value,
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: _portraitBox(),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 5,
                    child: _fileTextBlock(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _portraitBox() {
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE8DDCA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: GakujiColors.darkGray,
          width: 3,
        ),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            currentRound.visitor,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 36,
              height: 1,
              fontWeight: FontWeight.w900,
              color: GakujiColors.darkGray,
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileTextBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          currentRound.isReal ? 'IDENTITY FILE' : 'SUSPICIOUS FILE',
          textScaler: TextScaler.noScaling,
          style: GakujiText.small.copyWith(
            color: const Color(0xFF4F78B9),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        _fileLine('Visitor', currentRound.visitor),
        _fileLine('Reading', currentRound.reading),
        _fileLine('Part of Speech', currentRound.partOfSpeech),
        _fileLine('Definition', currentRound.definition),
      ],
    );
  }

  Widget _fileLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.mediumGray,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.darkGray,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stampOverlay() {
    final progress = _stampController.value;

    if (progress <= 0) {
      return const SizedBox.shrink();
    }

    final approved = lastAnswerApproved ?? false;
    final correct = lastAnswerCorrect ?? false;

    final scale = _lerp(
      1.6,
      1.0,
      Curves.elasticOut.transform(progress),
    );

    final opacity = progress < 0.82
        ? 1.0
        : (1 - ((progress - 0.82) / 0.18)).clamp(0.0, 1.0);

    final stampText = approved ? 'APPROVED' : 'DENIED';
    final stampColor = correct
        ? const Color(0xFF4F8F5B)
        : const Color(0xFFB54D4D);

    return Transform.rotate(
      angle: -0.12,
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4DC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: stampColor,
                width: 5,
              ),
            ),
            child: Text(
              stampText,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: stampColor,
                fontSize: 28,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buttons() {
    return SizedBox(
      width: 128,
      child: Column(
        children: [
          _answerButton(
            text: 'DENY',
            color: const Color(0xFFFF8C8C),
            onTap: () => answer(false),
          ),
          const SizedBox(height: 16),
          _answerButton(
            text: 'APPROVE',
            color: const Color(0xFFC8F29D),
            onTap: () => answer(true),
          ),
        ],
      ),
    );
  }

  Widget _answerButton({
    required String text,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: canAnswer ? 1 : 0.55,
        child: Container(
          width: 128,
          height: 80,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: GakujiColors.darkGray,
              width: 3,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Text(
            text,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 16,
              height: 1,
              fontWeight: FontWeight.w900,
              color: GakujiColors.darkGray,
            ),
          ),
        ),
      ),
    );
  }

  Widget _visitorRevealStack({
    required String term,
  }) {
    final poofProgress = _poofController.value;

    final visitorOpacity = poofProgress < 0.32
        ? 1.0
        : (1 - ((poofProgress - 0.32) / 0.25)).clamp(0.0, 1.0);

    final tanukiOpacity = poofProgress < 0.36
        ? 0.0
        : ((poofProgress - 0.36) / 0.28).clamp(0.0, 1.0);

    final tanukiScale = _lerp(
      0.65,
      1.0,
      Curves.elasticOut.transform(
        ((poofProgress - 0.35) / 0.65).clamp(0.0, 1.0),
      ),
    );

    return SizedBox(
      width: 168,
      height: 230,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: visitorOpacity,
            child: _termVisitorSprite(term),
          ),
          Transform.scale(
            scale: tanukiScale,
            child: Opacity(
              opacity: tanukiOpacity,
              child: _tanukiSprite(),
            ),
          ),
          if (poofProgress > 0 && poofProgress < 0.72)
            _poofCloud(
              progress: poofProgress,
            ),
        ],
      ),
    );
  }

  Widget _termVisitorSprite(String term) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            color: GakujiColors.warmCard,
            shape: BoxShape.circle,
            border: Border.all(
              color: GakujiColors.darkGray,
              width: 4,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  term,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 27,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: GakujiColors.darkGray,
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: 154,
          height: 102,
          decoration: BoxDecoration(
            color: GakujiColors.warmCard,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(84),
            ),
            border: Border.all(
              color: GakujiColors.darkGray,
              width: 4,
            ),
          ),
          child: Align(
            alignment: const Alignment(0, -0.12),
            child: Container(
              width: 46,
              height: 12,
              decoration: BoxDecoration(
                color: GakujiColors.darkGray.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chairBack() {
    return Container(
      width: 190,
      height: 126,
      decoration: BoxDecoration(
        color: chairColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(40),
        ),
        border: Border.all(
          color: GakujiColors.darkGray,
          width: 4,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 128,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFD3BA8F),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: GakujiColors.darkGray.withValues(alpha: 0.25),
              width: 3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _chairSeatFront() {
    return SizedBox(
      width: 176,
      height: 92,
      child: Stack(
        children: [
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            height: 44,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFA9875C),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: GakujiColors.darkGray,
                  width: 4,
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 4,
            child: Container(
              width: 18,
              height: 62,
              decoration: BoxDecoration(
                color: const Color(0xFF8E704C),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: GakujiColors.darkGray,
                  width: 3,
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 4,
            child: Container(
              width: 18,
              height: 62,
              decoration: BoxDecoration(
                color: const Color(0xFF8E704C),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: GakujiColors.darkGray,
                  width: 3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tanukiSprite() {
    return CustomPaint(
      size: const Size(168, 220),
      painter: _TanukiPainter(),
    );
  }

  Widget _poofCloud({
    required double progress,
  }) {
    final opacity = progress < 0.35
        ? (progress / 0.35).clamp(0.0, 1.0)
        : (1 - ((progress - 0.35) / 0.37)).clamp(0.0, 1.0);

    final scale = _lerp(
      0.65,
      1.3,
      Curves.easeOutCubic.transform(progress),
    );

    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: CustomPaint(
          size: const Size(180, 150),
          painter: _PoofPainter(),
        ),
      ),
    );
  }

  Widget _roomDeskEdge() {
    return Container(
      decoration: BoxDecoration(
        color: deskColor,
        border: Border(
          top: BorderSide(
            color: GakujiColors.darkGray,
            width: 4,
          ),
        ),
      ),
      child: CustomPaint(
        painter: _DeskTexturePainter(
          opacity: 0.10,
        ),
      ),
    );
  }

  Widget _window() {
    return Container(
      width: 120,
      height: 150,
      decoration: BoxDecoration(
        color: const Color(0xFFEFEAE0),
        border: Border.all(
          color: GakujiColors.darkGray,
          width: 4,
        ),
      ),
      child: CustomPaint(
        painter: _WindowPainter(),
      ),
    );
  }

  Widget _bookshelf() {
    return Container(
      width: 130,
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFFBFA27A),
        border: Border.all(
          color: GakujiColors.darkGray,
          width: 4,
        ),
      ),
    );
  }

  Widget _plant() {
    return Container(
      width: 70,
      height: 96,
      decoration: BoxDecoration(
        color: const Color(0xFF7D9B72),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: GakujiColors.darkGray,
          width: 4,
        ),
      ),
    );
  }

  Widget _smallPaperStack() {
    return Container(
      width: 140,
      height: 84,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: GakujiColors.darkGray,
          width: 3,
        ),
      ),
    );
  }

  Widget _topControls() {
    return Positioned(
      right: 16,
      top: 16,
      child: Row(
        children: [
          Container(
            height: 38,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: GakujiColors.warmCard,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: GakujiColors.darkGray,
                width: 2,
              ),
            ),
            child: Text(
              currentRound.isReal ? 'Real file' : 'Fake file',
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.darkGray,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: ElevatedButton(
              onPressed: busy ? null : toggleDeskOnlyView,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    deskOnlyView ? const Color(0xFF4F78B9) : GakujiColors.darkGray,
                foregroundColor: GakujiColors.warmCard,
                disabledBackgroundColor: GakujiColors.mediumGray,
                disabledForegroundColor: GakujiColors.warmCard,
                padding: const EdgeInsets.symmetric(horizontal: 13),
              ),
              child: Text(
                deskOnlyView ? 'Desk Only: On' : 'Desk Only: Off',
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: ElevatedButton(
              onPressed: busy ? null : resetFlow,
              style: ElevatedButton.styleFrom(
                backgroundColor: GakujiColors.darkGray,
                foregroundColor: GakujiColors.warmCard,
                disabledBackgroundColor: GakujiColors.mediumGray,
                disabledForegroundColor: GakujiColors.warmCard,
                padding: const EdgeInsets.symmetric(horizontal: 13),
              ),
              child: const Text(
                'Reset',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestRound {
  final String visitor;
  final String reading;
  final String partOfSpeech;
  final String definition;
  final bool isReal;

  const _TestRound({
    required this.visitor,
    required this.reading,
    required this.partOfSpeech,
    required this.definition,
    required this.isReal,
  });
}

class _VisitorMetrics {
  final double left;
  final double bottom;
  final double bob;
  final double opacity;
  final double rotation;
  final double scaleX;
  final double scaleY;

  const _VisitorMetrics({
    required this.left,
    required this.bottom,
    required this.bob,
    required this.opacity,
    required this.rotation,
    required this.scaleX,
    required this.scaleY,
  });
}

class _PerspectiveFileClipper extends CustomClipper<Path> {
  final double progress;

  const _PerspectiveFileClipper({
    required this.progress,
  });

  double _lerp(double start, double end, double progress) {
    return start + ((end - start) * progress);
  }

  @override
  Path getClip(Size size) {
    final topInset = _lerp(size.width * 0.30, 0, progress);

    return Path()
      ..moveTo(topInset, 0)
      ..lineTo(size.width - topInset, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _PerspectiveFileClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}

class _PerspectiveFilePainter extends CustomPainter {
  final double progress;

  const _PerspectiveFilePainter({
    required this.progress,
  });

  double _lerp(double start, double end, double progress) {
    return start + ((end - start) * progress);
  }

  Path _path(Size size) {
    final topInset = _lerp(size.width * 0.30, 0, progress);

    return Path()
      ..moveTo(topInset, 0)
      ..lineTo(size.width - topInset, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);

    final shadowPaint = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        10,
      );

    canvas.save();
    canvas.translate(0, 7);
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    final fillPaint = Paint()
      ..color = const Color(0xFFFFF4DC)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = GakujiColors.darkGray
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _PerspectiveFilePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _TanukiPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = GakujiColors.darkGray
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bodyPaint = Paint()
      ..color = const Color(0xFF9C754A)
      ..style = PaintingStyle.fill;

    final bellyPaint = Paint()
      ..color = const Color(0xFFEAD9BA)
      ..style = PaintingStyle.fill;

    final maskPaint = Paint()
      ..color = const Color(0xFF4E3A2A)
      ..style = PaintingStyle.fill;

    final tailPaint = Paint()
      ..color = const Color(0xFF8A623B)
      ..style = PaintingStyle.fill;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.24,
        size.height * 0.38,
        size.width * 0.52,
        size.height * 0.48,
      ),
      const Radius.circular(42),
    );

    final headCenter = Offset(
      size.width * 0.5,
      size.height * 0.28,
    );

    final headRadius = size.width * 0.28;

    final leftEar = Path()
      ..moveTo(size.width * 0.30, size.height * 0.13)
      ..lineTo(size.width * 0.22, size.height * 0.01)
      ..lineTo(size.width * 0.42, size.height * 0.08)
      ..close();

    final rightEar = Path()
      ..moveTo(size.width * 0.70, size.height * 0.13)
      ..lineTo(size.width * 0.78, size.height * 0.01)
      ..lineTo(size.width * 0.58, size.height * 0.08)
      ..close();

    final tail = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.66,
        size.height * 0.48,
        size.width * 0.26,
        size.height * 0.28,
      ),
      const Radius.circular(28),
    );

    canvas.drawRRect(tail, tailPaint);
    canvas.drawRRect(tail, outline);

    canvas.drawPath(leftEar, bodyPaint);
    canvas.drawPath(rightEar, bodyPaint);
    canvas.drawPath(leftEar, outline);
    canvas.drawPath(rightEar, outline);

    canvas.drawRRect(body, bodyPaint);
    canvas.drawRRect(body, outline);

    canvas.drawCircle(headCenter, headRadius, bodyPaint);
    canvas.drawCircle(headCenter, headRadius, outline);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.64),
        width: size.width * 0.28,
        height: size.height * 0.24,
      ),
      bellyPaint,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.39, size.height * 0.27),
        width: size.width * 0.20,
        height: size.height * 0.14,
      ),
      maskPaint,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.61, size.height * 0.27),
        width: size.width * 0.20,
        height: size.height * 0.14,
      ),
      maskPaint,
    );

    final eyePaint = Paint()
      ..color = const Color(0xFFFFF4DC)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.39, size.height * 0.27),
      4,
      eyePaint,
    );

    canvas.drawCircle(
      Offset(size.width * 0.61, size.height * 0.27),
      4,
      eyePaint,
    );

    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.36),
      5,
      maskPaint,
    );

    final mouth = Path()
      ..moveTo(size.width * 0.46, size.height * 0.40)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.44,
        size.width * 0.54,
        size.height * 0.40,
      );

    canvas.drawPath(mouth, outline);

    final labelPainter = TextPainter(
      text: TextSpan(
        text: 'たぬき',
        style: TextStyle(
          color: GakujiColors.darkGray,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    labelPainter.paint(
      canvas,
      Offset(
        (size.width - labelPainter.width) / 2,
        size.height * 0.86,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class _PoofPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cloudPaint = Paint()
      ..color = const Color(0xFFF8F0DF)
      ..style = PaintingStyle.fill;

    final outline = Paint()
      ..color = GakujiColors.darkGray
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final circles = [
      Offset(size.width * 0.25, size.height * 0.54),
      Offset(size.width * 0.38, size.height * 0.34),
      Offset(size.width * 0.53, size.height * 0.42),
      Offset(size.width * 0.68, size.height * 0.55),
      Offset(size.width * 0.48, size.height * 0.65),
    ];

    final radii = [
      size.width * 0.16,
      size.width * 0.18,
      size.width * 0.20,
      size.width * 0.16,
      size.width * 0.17,
    ];

    for (int i = 0; i < circles.length; i++) {
      canvas.drawCircle(circles[i], radii[i], cloudPaint);
      canvas.drawCircle(circles[i], radii[i], outline);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class _DeskTexturePainter extends CustomPainter {
  final double opacity;

  const _DeskTexturePainter({
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.black.withValues(alpha: opacity)
      ..strokeWidth = 2;

    for (double y = 34; y < size.height; y += 46) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y + 12),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DeskTexturePainter oldDelegate) {
    return oldDelegate.opacity != opacity;
  }
}

class _WindowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GakujiColors.darkGray
      ..strokeWidth = 4;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}