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
          opaque: !enableSwipeBack,
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
    this.distanceThreshold = 72,
    this.velocityThreshold = 800,
  });

  final Widget child;
  final GakujiPageSide side;
  final double distanceThreshold;
  final double velocityThreshold;

  @override
  State<GakujiSwipeBackScope> createState() => _GakujiSwipeBackScopeState();
}

class _GakujiSwipeBackScopeState extends State<GakujiSwipeBackScope>
    with SingleTickerProviderStateMixin {
  static const double _gestureSlop = 8;
  static const double _verticalCancelDistance = 32;
  static const double _directionLockRatio = 1.1;

  int? _pointer;
  Offset? _startPosition;
  Offset? _latestPosition;
  Duration? _startTimestamp;
  bool _cancelled = false;
  bool _dragAccepted = false;
  bool _popRequested = false;
  bool _settling = false;
  double _dragOffset = 0;

  late final AnimationController _settleController;
  Animation<double>? _settleAnimation;

  double get _directionSign =>
      widget.side == GakujiPageSide.right ? 1.0 : -1.0;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(_handleSettleTick);
  }

  @override
  void dispose() {
    _settleController
      ..removeListener(_handleSettleTick)
      ..dispose();
    super.dispose();
  }

  void _handleSettleTick() {
    final animation = _settleAnimation;
    if (!mounted || animation == null) return;

    setState(() {
      _dragOffset = animation.value;
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null || _popRequested || _settling) return;

    _settleController.stop();
    _settleAnimation = null;
    _pointer = event.pointer;
    _startPosition = event.localPosition;
    _latestPosition = event.localPosition;
    _startTimestamp = event.timeStamp;
    _cancelled = false;
    _dragAccepted = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _cancelled || _settling) return;

    _latestPosition = event.localPosition;

    final start = _startPosition;
    if (start == null) return;

    final delta = event.localPosition - start;
    final horizontal = delta.dx.abs();
    final vertical = delta.dy.abs();
    final directionalDistance = delta.dx * _directionSign;

    if (!_dragAccepted) {
      if (horizontal < _gestureSlop && vertical < _gestureSlop) return;

      if (directionalDistance <= 0 ||
          (vertical > _verticalCancelDistance &&
              vertical > horizontal * _directionLockRatio) ||
          vertical > horizontal) {
        _cancelled = true;
        return;
      }

      _dragAccepted = true;
    }

    final width = MediaQuery.sizeOf(context).width;
    final clampedDistance =
        directionalDistance.clamp(0.0, width).toDouble();
    final nextOffset = clampedDistance * _directionSign;

    if (nextOffset == _dragOffset) return;

    setState(() {
      _dragOffset = nextOffset;
    });
  }

  Future<void> _handlePointerUp(PointerUpEvent event) async {
    if (event.pointer != _pointer) return;

    final start = _startPosition;
    final latest = _latestPosition ?? event.localPosition;
    final startTimestamp = _startTimestamp;
    final cancelled = _cancelled;
    final dragAccepted = _dragAccepted;

    _resetPointer();

    if (cancelled ||
        !dragAccepted ||
        start == null ||
        startTimestamp == null ||
        _popRequested) {
      if (_dragOffset != 0) {
        await _animateOffsetTo(0);
      }
      return;
    }

    final delta = latest - start;
    final directionalDistance = delta.dx * _directionSign;
    final elapsedMicros =
        (event.timeStamp - startTimestamp).inMicroseconds.clamp(1, 1 << 31);
    final elapsedSeconds = elapsedMicros / Duration.microsecondsPerSecond;
    final velocity = directionalDistance / elapsedSeconds;

    final shouldPop = directionalDistance >= widget.distanceThreshold ||
        velocity >= widget.velocityThreshold;

    if (!shouldPop || !mounted) {
      await _animateOffsetTo(0);
      return;
    }

    _popRequested = true;
    final width = MediaQuery.sizeOf(context).width;
    await _animateOffsetTo(width * _directionSign);

    if (!mounted) return;

    final didPop = await Navigator.of(context).maybePop();

    if (!mounted) return;

    if (!didPop) {
      _popRequested = false;
      await _animateOffsetTo(0);
    }
  }

  Future<void> _handlePointerCancel(PointerCancelEvent event) async {
    if (event.pointer != _pointer) return;

    final hadDrag = _dragAccepted && _dragOffset != 0;
    _resetPointer();

    if (hadDrag) {
      await _animateOffsetTo(0);
    }
  }

  Future<void> _animateOffsetTo(double target) async {
    if (!mounted || _dragOffset == target) return;

    _settling = true;
    _settleAnimation = Tween<double>(
      begin: _dragOffset,
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _settleController,
        curve: Curves.easeOutCubic,
      ),
    );

    try {
      await _settleController.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    } finally {
      if (mounted) {
        setState(() {
          _settling = false;
        });
      }
    }
  }

  void _resetPointer() {
    _pointer = null;
    _startPosition = null;
    _latestPosition = null;
    _startTimestamp = null;
    _cancelled = false;
    _dragAccepted = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: Transform.translate(
        offset: Offset(_dragOffset, 0),
        child: IgnorePointer(
          ignoring: _settling,
          child: widget.child,
        ),
      ),
    );
  }
}
