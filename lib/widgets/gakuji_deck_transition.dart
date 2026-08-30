import 'package:flutter/material.dart';

import 'package:gakuji/widgets/gakuji_page_route.dart';

const Duration gakujiDeckOpenDuration = Duration(milliseconds: 340);
const Duration gakujiDeckCloseDuration = Duration(milliseconds: 300);

String gakujiDeckHeroTag(String deckId) => 'gakuji-deck-$deckId';

String gakujiLearningHeroTag(String pageId) => 'gakuji-learning-$pageId';

Route<T> gakujiLearningRoute<T>({required Widget page}) {
  return gakujiDeckRoute<T>(page: page);
}

Route<T> gakujiDeckRoute<T>({required Widget page}) {
  return PageRouteBuilder<T>(
    opaque: false,
    transitionDuration: gakujiDeckOpenDuration,
    reverseTransitionDuration: gakujiDeckCloseDuration,
    pageBuilder: (context, animation, secondaryAnimation) {
      return GakujiSwipeBackScope(
        side: GakujiPageSide.right,
        child: page,
      );
    },
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return child;
    },
  );
}

RectTween gakujiDeckRectTween(Rect? begin, Rect? end) {
  return _GakujiDeckRectTween(begin: begin, end: end);
}

Widget gakujiDeckFlightShuttleBuilder(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final fromHero = fromHeroContext.widget as Hero;
  final toHero = toHeroContext.widget as Hero;

  final cardHero = direction == HeroFlightDirection.push ? fromHero : toHero;
  final pageHero = direction == HeroFlightDirection.push ? toHero : fromHero;

  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final rawPageProgress =
          ((animation.value - 0.18) / 0.62).clamp(0.0, 1.0).toDouble();
      final pageProgress = Curves.easeInOutCubic.transform(rawPageProgress);
      final cardProgress = 1.0 - pageProgress;
      final cornerRadius = 22.0 * cardProgress;

      return ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: cardProgress,
              child: cardHero.child,
            ),
            Opacity(
              opacity: pageProgress,
              child: pageHero.child,
            ),
          ],
        ),
      );
    },
  );
}

class _GakujiDeckRectTween extends RectTween {
  _GakujiDeckRectTween({super.begin, super.end});

  @override
  Rect? lerp(double t) {
    final eased = Curves.easeInOutCubic.transform(t);
    return Rect.lerp(begin, end, eased);
  }
}
