import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/gakuji_styles.dart';

enum VisitorAnimationPhase {
  offstage,
  walkingIn,
  sittingDown,
  seated,
  standingUp,
  walkingOut,
}

class DetectiveCharacterAnimationTestPage extends StatefulWidget {
  const DetectiveCharacterAnimationTestPage({
    super.key,
  });

  @override
  State<DetectiveCharacterAnimationTestPage> createState() =>
      _DetectiveCharacterAnimationTestPageState();
}

class _DetectiveCharacterAnimationTestPageState
    extends State<DetectiveCharacterAnimationTestPage>
    with TickerProviderStateMixin {
  late final AnimationController _walkController;
  late final AnimationController _sitController;
  late final AnimationController _idleController;
  late final AnimationController _poofController;

  VisitorAnimationPhase phase = VisitorAnimationPhase.offstage;

  bool busy = false;
  int visitorIndex = 0;

  final List<String> visitors = [
    '食べる',
    '見る',
    '学校',
    '猫',
    '先生',
  ];

  static const Color roomWallColor = Color(0xFFD8D0C1);
  static const Color floorColor = Color(0xFFC9B89E);
  static const Color deskColor = Color(0xFFE7D4B6);
  static const Color chairColor = Color(0xFFBFA27A);

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

    _poofController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      runEntrance();
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
    _poofController.dispose();

    super.dispose();
  }

  Future<void> runEntrance() async {
    if (busy) return;

    busy = true;

    _walkController.reset();
    _sitController.reset();
    _poofController.reset();

    setState(() {
      phase = VisitorAnimationPhase.walkingIn;
    });

    await _walkController.forward();

    if (!mounted) return;

    setState(() {
      phase = VisitorAnimationPhase.sittingDown;
    });

    await _sitController.forward();

    if (!mounted) return;

    setState(() {
      phase = VisitorAnimationPhase.seated;
    });

    busy = false;
  }

  Future<void> runExit() async {
    if (busy) return;
    if (phase == VisitorAnimationPhase.offstage) return;

    busy = true;

    setState(() {
      phase = VisitorAnimationPhase.standingUp;
    });

    await _sitController.reverse();

    if (!mounted) return;

    _walkController.reset();

    setState(() {
      phase = VisitorAnimationPhase.walkingOut;
    });

    await _walkController.forward();

    if (!mounted) return;

    setState(() {
      phase = VisitorAnimationPhase.offstage;
    });

    busy = false;
  }

  Future<void> runNextVisitor() async {
    if (busy) return;

    busy = true;

    if (phase != VisitorAnimationPhase.offstage) {
      setState(() {
        phase = VisitorAnimationPhase.standingUp;
      });

      await _sitController.reverse();

      if (!mounted) return;

      _walkController.reset();

      setState(() {
        phase = VisitorAnimationPhase.walkingOut;
      });

      await _walkController.forward();

      if (!mounted) return;
    }

    setState(() {
      visitorIndex = (visitorIndex + 1) % visitors.length;
      phase = VisitorAnimationPhase.walkingIn;
    });

    _walkController.reset();
    _sitController.reset();
    _poofController.reset();

    await _walkController.forward();

    if (!mounted) return;

    setState(() {
      phase = VisitorAnimationPhase.sittingDown;
    });

    await _sitController.forward();

    if (!mounted) return;

    setState(() {
      phase = VisitorAnimationPhase.seated;
    });

    busy = false;
  }

  Future<void> revealTanuki() async {
    if (busy) return;
    if (phase != VisitorAnimationPhase.seated) return;

    busy = true;

    await _poofController.forward(from: 0);

    if (!mounted) return;

    busy = false;
  }

  void resetScene() {
    if (busy) return;

    setState(() {
      phase = VisitorAnimationPhase.offstage;
    });

    _walkController.reset();
    _sitController.reset();
    _poofController.reset();
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
                _poofController,
              ]),
              builder: (context, child) {
                return Stack(
                  children: [
                    _roomScene(
                      width: screenWidth,
                      height: screenHeight,
                    ),
                    _testControls(),
                  ],
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
      height: height,
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

          // Chair back sits behind the visitor.
          Positioned(
            left: chairCenterX - 95,
            bottom: chairBottom + 64,
            child: _chairBack(),
          ),

          // Visitor walks to the chair and sits.
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
                      term: visitors[visitorIndex],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Chair seat/front overlays the lower body so it actually feels seated.
          Positioned(
            left: chairCenterX - 88,
            bottom: chairBottom + 38,
            child: _chairSeatFront(),
          ),

          // Desk edge is lower and more like the foreground inspection desk,
          // not a restaurant counter.
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
    required double height,
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

    if (phase == VisitorAnimationPhase.offstage) {
      left = rightOffscreen;
      opacity = 0;
      baseScale = 0.96;
    }

    if (phase == VisitorAnimationPhase.walkingIn) {
      left = _lerp(
        rightOffscreen,
        seatedLeft,
        walkProgress,
      );

      opacity = (walkRaw * 1.8).clamp(0.0, 1.0);
      baseScale = _lerp(0.96, 1.0, walkProgress);
      rotation = math.sin(walkRaw * math.pi * 6) * 0.03;
    }

    if (phase == VisitorAnimationPhase.sittingDown ||
        phase == VisitorAnimationPhase.seated ||
        phase == VisitorAnimationPhase.standingUp) {
      left = seatedLeft;
      opacity = 1;
      baseScale = 1;

      final idleWave = math.sin(_idleController.value * math.pi * 2);
      rotation = idleWave * 0.01;
    }

    if (phase == VisitorAnimationPhase.walkingOut) {
      left = _lerp(
        seatedLeft,
        leftOffscreen,
        walkProgress,
      );

      opacity = (1 - ((walkRaw - 0.68) / 0.32)).clamp(0.0, 1.0);
      baseScale = _lerp(1.0, 0.94, walkProgress);
      rotation = math.sin(walkRaw * math.pi * 6) * 0.03;
    }

    final walkingBob = math.sin(walkRaw * math.pi * 8) * 7;
    final idleBob = math.sin(_idleController.value * math.pi * 2) * 2.5;

    final isWalking = phase == VisitorAnimationPhase.walkingIn ||
        phase == VisitorAnimationPhase.walkingOut;

    final bob = isWalking ? walkingBob : idleBob;

    // Sitting should visibly lower the character into the chair.
    final sitDrop = _lerp(0, -38, sitProgress);

    // Small squash as they settle into the chair.
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
                color: GakujiColors.darkGray.withOpacity(0.14),
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
              color: GakujiColors.darkGray.withOpacity(0.25),
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

  Widget _testControls() {
    return Positioned(
      right: 16,
      top: 16,
      child: Row(
        children: [
          _controlButton(
            label: 'Enter',
            onTap: runEntrance,
          ),
          const SizedBox(width: 8),
          _controlButton(
            label: 'Next',
            onTap: runNextVisitor,
          ),
          const SizedBox(width: 8),
          _controlButton(
            label: 'Exit',
            onTap: runExit,
          ),
          const SizedBox(width: 8),
          _controlButton(
            label: 'Tanuki',
            onTap: revealTanuki,
          ),
          const SizedBox(width: 8),
          _controlButton(
            label: 'Reset',
            onTap: resetScene,
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: GakujiColors.darkGray,
          foregroundColor: GakujiColors.warmCard,
          disabledBackgroundColor: GakujiColors.mediumGray,
          disabledForegroundColor: GakujiColors.warmCard,
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
          ),
        ),
        child: Text(
          label,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
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
      ..color = Colors.black.withOpacity(opacity)
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