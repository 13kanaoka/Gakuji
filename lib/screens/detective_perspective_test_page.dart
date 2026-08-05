import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/gakuji_styles.dart';

class DetectivePerspectiveTestPage extends StatefulWidget {
  const DetectivePerspectiveTestPage({
    super.key,
  });

  @override
  State<DetectivePerspectiveTestPage> createState() =>
      _DetectivePerspectiveTestPageState();
}

class _DetectivePerspectiveTestPageState
    extends State<DetectivePerspectiveTestPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _cameraPan;
  late final Animation<double> _fileMorph;
  late final Animation<double> _fileDetailsOpacity;
  late final Animation<double> _buttonOpacity;

  bool expanded = false;

  static const Color roomWallColor = Color(0xFFD8D0C1);
  static const Color deskColor = Color(0xFFE7D4B6);

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );

    _cameraPan = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutCubic,
      ),
    );

    _fileMorph = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
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
        parent: _controller,
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
        parent: _controller,
        curve: const Interval(
          0.56,
          1.0,
          curve: Curves.easeOut,
        ),
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    _controller.dispose();
    super.dispose();
  }

  void toggleDesk() {
    setState(() {
      expanded = !expanded;
    });

    if (expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  double _lerp(double start, double end, double progress) {
    return start + ((end - start) * progress);
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
              animation: _controller,
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
                      _testButton(),
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
    final deskHeight = height * 0.22;

    return Container(
      color: roomWallColor,
      child: Stack(
        children: [
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
            bottom: deskHeight + 12,
            child: _bookshelf(),
          ),
          Positioned(
            right: 48,
            bottom: deskHeight + 34,
            child: _plant(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: deskHeight - 10,
            child: _visitor(),
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

  Widget _visitor() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 112,
          height: 112,
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
              '食べる',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 28,
                height: 1,
                fontWeight: FontWeight.w900,
                color: GakujiColors.darkGray,
              ),
            ),
          ),
        ),
        Container(
          width: 154,
          height: 100,
          decoration: BoxDecoration(
            color: GakujiColors.warmCard,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(82),
            ),
            border: Border.all(
              color: GakujiColors.darkGray,
              width: 4,
            ),
          ),
        ),
      ],
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
      ((height - fileHeight) / 2).clamp(44.0, 72.0),
      progress,
    );

    final buttonsTop = ((height - 176) / 2).clamp(46.0, 118.0);

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
            child: _perspectiveFile(
              width: fileWidth,
              height: fileHeight,
              progress: progress,
            ),
          ),
          Positioned(
            right: 52,
            top: buttonsTop,
            child: Opacity(
              opacity: _buttonOpacity.value,
              child: _buttons(),
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
        child: Text(
          '食べる',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 36,
            height: 1,
            fontWeight: FontWeight.w900,
            color: GakujiColors.darkGray,
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
          'IDENTITY FILE',
          textScaler: TextScaler.noScaling,
          style: GakujiText.small.copyWith(
            color: const Color(0xFF4F78B9),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        _fileLine('Visitor', '食べる'),
        _fileLine('Reading', 'たべる'),
        _fileLine('Part of Speech', 'Verb'),
        _fileLine('Definition', 'to eat'),
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

  Widget _buttons() {
    return SizedBox(
      width: 128,
      child: Column(
        children: [
          _button(
            'DENY',
            const Color(0xFFFF8C8C),
          ),
          const SizedBox(height: 16),
          _button(
            'APPROVE',
            const Color(0xFFC8F29D),
          ),
        ],
      ),
    );
  }

  Widget _button(String text, Color color) {
    return Container(
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

  Widget _testButton() {
    return Positioned(
      right: 18,
      top: 16,
      child: ElevatedButton(
        onPressed: toggleDesk,
        style: ElevatedButton.styleFrom(
          backgroundColor: GakujiColors.darkGray,
          foregroundColor: GakujiColors.warmCard,
        ),
        child: Text(
          expanded ? 'Reset' : 'Look Down',
          textScaler: TextScaler.noScaling,
        ),
      ),
    );
  }
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