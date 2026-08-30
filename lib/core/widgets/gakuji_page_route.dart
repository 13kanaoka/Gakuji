import 'package:flutter/material.dart';

enum GakujiPageSide {
  left,
  right,
}

const Duration gakujiPageOpenDuration = Duration(milliseconds: 280);
const Duration gakujiPageCloseDuration = Duration(milliseconds: 240);

class GakujiPageRoute<T> extends PageRouteBuilder<T> {
  GakujiPageRoute({
    required WidgetBuilder builder,
    GakujiPageSide side = GakujiPageSide.right,
    bool enableSwipeBack = true,
    super.settings,
    super.transitionDuration = gakujiPageOpenDuration,
    super.reverseTransitionDuration = gakujiPageCloseDuration,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) {
            final page = builder(context);

            if (!enableSwipeBack) {
              return page;
            }

            return GakujiSwipeBackScope(
              side: side,
              child: page,
            );
          },
          transitionsBuilder: (
            context,
            animation,
            secondaryAnimation,
            child,
          ) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            final begin = side == GakujiPageSide.right
                ? const Offset(1, 0)
                : const Offset(-1, 0);

            return SlideTransition(
              position: Tween<Offset>(
                begin: begin,
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            );
          },
        );
}

class GakujiSwipeBackScope extends StatefulWidget {
  const GakujiSwipeBackScope({
    super.key,
    required this.child,
    this.side = GakujiPageSide.right,
    this.edgeWidth = 24,
    this.distanceThreshold = 72,
    this.velocityThreshold = 800,
  });

  final Widget child;
  final GakujiPageSide side;
  final double edgeWidth;
  final double distanceThreshold;
  final double velocityThreshold;

  @override
  State<GakujiSwipeBackScope> createState() => _GakujiSwipeBackScopeState();
}

class _GakujiSwipeBackScopeState extends State<GakujiSwipeBackScope> {
  int? _pointer;
  Offset? _startPosition;
  Offset? _latestPosition;
  Duration? _startTimestamp;
  bool _cancelled = false;
  bool _popRequested = false;

  bool _startsOnBackEdge(PointerDownEvent event) {
    final width = MediaQuery.sizeOf(context).width;

    if (widget.side == GakujiPageSide.right) {
      return event.localPosition.dx <= widget.edgeWidth;
    }

    return event.localPosition.dx >= width - widget.edgeWidth;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null || _popRequested || !_startsOnBackEdge(event)) {
      return;
    }

    _pointer = event.pointer;
    _startPosition = event.localPosition;
    _latestPosition = event.localPosition;
    _startTimestamp = event.timeStamp;
    _cancelled = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _cancelled) return;

    _latestPosition = event.localPosition;

    final start = _startPosition;
    if (start == null) return;

    final delta = event.localPosition - start;
    final horizontal = delta.dx.abs();
    final vertical = delta.dy.abs();

    if (vertical > 32 && vertical > horizontal * 1.1) {
      _cancelled = true;
    }
  }

  Future<void> _handlePointerUp(PointerUpEvent event) async {
    if (event.pointer != _pointer) return;

    final start = _startPosition;
    final latest = _latestPosition ?? event.localPosition;
    final startTimestamp = _startTimestamp;
    final cancelled = _cancelled;

    _resetPointer();

    if (cancelled || start == null || startTimestamp == null || _popRequested) {
      return;
    }

    final delta = latest - start;
    final horizontal = delta.dx.abs();
    final vertical = delta.dy.abs();
    final directionalDistance = widget.side == GakujiPageSide.right
        ? delta.dx
        : -delta.dx;

    if (directionalDistance <= 0 || horizontal <= vertical * 1.15) {
      return;
    }

    final elapsedMicros =
        (event.timeStamp - startTimestamp).inMicroseconds.clamp(1, 1 << 31);
    final elapsedSeconds = elapsedMicros / Duration.microsecondsPerSecond;
    final velocity = directionalDistance / elapsedSeconds;

    final shouldPop = directionalDistance >= widget.distanceThreshold ||
        velocity >= widget.velocityThreshold;

    if (!shouldPop || !mounted) return;

    _popRequested = true;
    await Navigator.of(context).maybePop();

    if (mounted) {
      _popRequested = false;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) {
      _resetPointer();
    }
  }

  void _resetPointer() {
    _pointer = null;
    _startPosition = null;
    _latestPosition = null;
    _startTimestamp = null;
    _cancelled = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}
