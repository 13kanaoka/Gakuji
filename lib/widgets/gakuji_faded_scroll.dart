import 'package:flutter/material.dart';

class GakujiFadedScroll extends StatefulWidget {
  final Widget child;
  final double topFadeEnd;
  final double bottomFadeStart;
  final bool fadeBottom;

  const GakujiFadedScroll({
    super.key,
    required this.child,
    this.topFadeEnd = 0.035,
    this.bottomFadeStart = 0.94,
  }) : fadeBottom = false;

  const GakujiFadedScroll.withBottomNavigation({
    super.key,
    required this.child,
  })  : topFadeEnd = 0.055,
        bottomFadeStart = 0.76,
        fadeBottom = true;

  @override
  State<GakujiFadedScroll> createState() => _GakujiFadedScrollState();
}

class _GakujiFadedScrollState extends State<GakujiFadedScroll> {
  static const double _edgeTolerance = 0.5;

  bool showTopFade = false;
  bool showBottomFade = false;
  bool pendingTopFade = false;
  bool pendingBottomFade = false;
  bool fadeUpdateScheduled = false;

  void _queueFadeUpdate(ScrollMetrics metrics) {
    if (axisDirectionToAxis(metrics.axisDirection) != Axis.vertical) {
      return;
    }

    final canScroll =
        metrics.maxScrollExtent - metrics.minScrollExtent > _edgeTolerance;

    pendingTopFade = canScroll &&
        metrics.pixels > metrics.minScrollExtent + _edgeTolerance;
    pendingBottomFade = widget.fadeBottom &&
        canScroll &&
        metrics.pixels < metrics.maxScrollExtent - _edgeTolerance;

    if (fadeUpdateScheduled) {
      return;
    }

    fadeUpdateScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      fadeUpdateScheduled = false;

      if (!mounted ||
          (pendingTopFade == showTopFade &&
              pendingBottomFade == showBottomFade)) {
        return;
      }

      setState(() {
        showTopFade = pendingTopFade;
        showBottomFade = pendingBottomFade;
      });
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth == 0) {
      _queueFadeUpdate(notification.metrics);
    }

    return false;
  }

  bool _handleMetricsNotification(ScrollMetricsNotification notification) {
    _queueFadeUpdate(notification.metrics);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _handleMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                showTopFade ? Colors.transparent : Colors.black,
                Colors.black,
                Colors.black,
                widget.fadeBottom && showBottomFade
                    ? Colors.transparent
                    : Colors.black,
              ],
              stops: [
                0.0,
                widget.topFadeEnd,
                widget.bottomFadeStart,
                1.0,
              ],
            ).createShader(bounds);
          },
          child: widget.child,
        ),
      ),
    );
  }
}
