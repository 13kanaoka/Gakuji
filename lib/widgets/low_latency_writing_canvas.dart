import 'package:flutter/material.dart';

import '../models/writing_point.dart';
import 'gakuji_styles.dart';

/// A low-latency handwriting surface that keeps pointer updates and repaints
/// isolated from the surrounding page/card.
///
/// The supplied callbacks are responsible for mutating [strokes]. The canvas
/// then repaints itself directly through a repaint notifier, so a full parent
/// setState is not required for every sampled point.
class GakujiLowLatencyWritingCanvas extends StatefulWidget {
  final List<List<WritingPoint>> strokes;
  final ValueChanged<Offset> onStrokeStart;
  final ValueChanged<Offset> onStrokeUpdate;
  final VoidCallback? onStrokeEnd;
  final bool showGrid;
  final Color? penColor;
  final Color? gridColor;
  final Color? borderColor;
  final double strokeWidth;
  final double gridStrokeWidth;
  final double borderWidth;
  final double minPointDistance;
  final Widget? child;

  const GakujiLowLatencyWritingCanvas({
    super.key,
    required this.strokes,
    required this.onStrokeStart,
    required this.onStrokeUpdate,
    this.onStrokeEnd,
    this.showGrid = false,
    this.penColor,
    this.gridColor,
    this.borderColor,
    this.strokeWidth = 4,
    this.gridStrokeWidth = 1,
    this.borderWidth = 1,
    this.minPointDistance = 0.6,
    this.child,
  });

  @override
  State<GakujiLowLatencyWritingCanvas> createState() =>
      _GakujiLowLatencyWritingCanvasState();
}

class _GakujiLowLatencyWritingCanvasState
    extends State<GakujiLowLatencyWritingCanvas> {
  final ChangeNotifier _repaint = ChangeNotifier();

  int? _activePointer;
  Offset? _lastAcceptedPoint;

  @override
  void dispose() {
    _repaint.dispose();
    super.dispose();
  }

  bool _shouldAccept(Offset point) {
    final previous = _lastAcceptedPoint;
    if (previous == null) return true;

    final dx = point.dx - previous.dx;
    final dy = point.dy - previous.dy;
    final minimum = widget.minPointDistance;
    return (dx * dx) + (dy * dy) >= minimum * minimum;
  }

  void _startStroke(PointerDownEvent event) {
    if (_activePointer != null) return;

    _activePointer = event.pointer;
    _lastAcceptedPoint = event.localPosition;
    widget.onStrokeStart(event.localPosition);
    _repaint.notifyListeners();
  }

  void _updateStroke(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;

    final point = event.localPosition;
    if (!_shouldAccept(point)) return;

    _lastAcceptedPoint = point;
    widget.onStrokeUpdate(point);
    _repaint.notifyListeners();
  }

  void _finishStroke(PointerEvent event) {
    if (event.pointer != _activePointer) return;

    final point = event.localPosition;
    if (_shouldAccept(point)) {
      _lastAcceptedPoint = point;
      widget.onStrokeUpdate(point);
      _repaint.notifyListeners();
    }

    _activePointer = null;
    _lastAcceptedPoint = null;
    widget.onStrokeEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final penColor = widget.penColor ?? GakujiColors.darkGray;
    final gridColor = widget.gridColor ?? GakujiColors.warmDivider;

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {},
        onPanUpdate: (_) {},
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _startStroke,
          onPointerMove: _updateStroke,
          onPointerUp: _finishStroke,
          onPointerCancel: _finishStroke,
          child: CustomPaint(
            painter: _LowLatencyWritingPainter(
              strokes: widget.strokes,
              showGrid: widget.showGrid,
              penColor: penColor,
              gridColor: gridColor,
              borderColor: widget.borderColor,
              strokeWidth: widget.strokeWidth,
              gridStrokeWidth: widget.gridStrokeWidth,
              borderWidth: widget.borderWidth,
              repaint: _repaint,
            ),
            child: widget.child ?? const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _LowLatencyWritingPainter extends CustomPainter {
  final List<List<WritingPoint>> strokes;
  final bool showGrid;
  final Color penColor;
  final Color gridColor;
  final Color? borderColor;
  final double strokeWidth;
  final double gridStrokeWidth;
  final double borderWidth;

  _LowLatencyWritingPainter({
    required this.strokes,
    required this.showGrid,
    required this.penColor,
    required this.gridColor,
    required this.borderColor,
    required this.strokeWidth,
    required this.gridStrokeWidth,
    required this.borderWidth,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final border = borderColor;
    if (border != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    }

    if (showGrid) {
      final gridPaint = Paint()
        ..color = gridColor
        ..strokeWidth = gridStrokeWidth;

      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        gridPaint,
      );
    }

    final pen = Paint()
      ..color = penColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;

      if (stroke.length == 1) {
        final point = stroke.first;
        canvas.drawCircle(
          Offset(point.x, point.y),
          strokeWidth / 2,
          Paint()
            ..color = penColor
            ..isAntiAlias = true,
        );
        continue;
      }

      final path = Path()
        ..moveTo(stroke.first.x, stroke.first.y);

      for (var index = 1; index < stroke.length; index++) {
        path.lineTo(stroke[index].x, stroke[index].y);
      }

      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(covariant _LowLatencyWritingPainter oldDelegate) => true;
}
