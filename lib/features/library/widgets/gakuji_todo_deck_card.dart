import 'package:flutter/material.dart';

import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';

class GakujiTodoDeckCard extends StatelessWidget {
  final Deck deck;

  final int newCount;
  final int learningCount;
  final int reviewCount;

  final bool isPinned;
  final bool compact;
  final VoidCallback onTap;

  const GakujiTodoDeckCard({
    super.key,
    required this.deck,
    required this.newCount,
    required this.learningCount,
    required this.reviewCount,
    required this.isPinned,
    this.compact = false,
    required this.onTap,
  });

  double get cardHeight => compact ? 104 : 148;
  double get reviewBarHeight => compact ? 30 : 48;

  bool get isHybrid => deck.type == DeckType.hybrid;

  double get compactPatternSize => isHybrid ? 450 : 340;
  double get compactPatternRightOffset => isHybrid ? -210 : -122;
  double get compactPatternTopOffset => isHybrid ? -165 : -127;

  static Color get cardSurface => GakujiColors.warmCard;
  static Color get deckCircle => cardSurface.withValues(alpha: 0.10);

  Color get deckPrimaryColor {
    return GakujiColors.deckColorFor(deck);
  }

  Color get deckForegroundColor {
    return ThemeData.estimateBrightnessForColor(deckPrimaryColor) ==
            Brightness.dark
        ? Colors.white
        : const Color(0xFF3F3F3F);
  }

  Color get reviewBarColor {
    return Color.alphaBlend(
      deckPrimaryColor.withValues(alpha: 0.92),
      cardSurface,
    );
  }

  double get reviewBarStart {
    return (cardHeight - reviewBarHeight) / cardHeight;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: cardHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cardSurface,
            cardSurface,
            reviewBarColor,
            reviewBarColor,
          ],
          stops: [
            0,
            reviewBarStart,
            reviewBarStart,
            1,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: GakujiColors.softBorder,
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: deckPrimaryColor.withValues(alpha: 0.08),
          highlightColor: deckPrimaryColor.withValues(alpha: 0.04),
          child: Stack(
            children: [
              if (compact)
                Positioned(
                  right: compactPatternRightOffset,
                  top: compactPatternTopOffset,
                  child: _pattern(),
                )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: reviewBarHeight,
                  child: _pattern(),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: reviewBarHeight,
                child: _deckWidgetContent(),
              ),
              if (isPinned) _pinIcon(),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _reviewBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deckWidgetContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 54, 0),
      child: Row(
        children: [
          _watermarkBox(),
          const SizedBox(width: 10),
          Expanded(
            child: _deckText(),
          ),
        ],
      ),
    );
  }

  Widget _deckText() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          deck.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textScaler: TextScaler.noScaling,
          style: compact
              ? GakujiText.deckTitle
              : GakujiText.small.copyWith(
                  color: GakujiColors.darkGray,
                ),
        ),
        const SizedBox(height: 6),
        Text(
          _deckTypeLabel(deck.type),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textScaler: TextScaler.noScaling,
          style: compact
              ? GakujiText.deckMeta
              : GakujiText.xSmall.copyWith(
                  color: GakujiColors.darkGray,
                ),
        ),
      ],
    );
  }

  Widget _reviewBar() {
    return Container(
      height: reviewBarHeight,
      decoration: BoxDecoration(
        color: reviewBarColor,
        borderRadius: BorderRadius.zero,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _countText(
            label: 'New',
            count: newCount,
          ),
          _countText(
            label: 'Learn',
            count: learningCount,
          ),
          _countText(
            label: 'Review',
            count: reviewCount,
          ),
        ],
      ),
    );
  }

  Widget _countText({
    required String label,
    required int count,
  }) {
    return Text(
      '$label $count',
      textScaler: TextScaler.noScaling,
      style: GakujiText.xSmall.copyWith(
        color: deckForegroundColor,
      ),
    );
  }

  Widget _pattern() {
    if (compact) {
      return IgnorePointer(
        child: Opacity(
          opacity: 0.32,
          child: ShaderMask(
            shaderCallback: (bounds) {
              return const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  Colors.black,
                ],
                stops: [
                  0.22,
                  0.55,
                ],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: SizedBox(
              width: compactPatternSize,
              height: compactPatternSize,
              child: Image.asset(
                _patternAssetForDeckType(deck.type),
                fit: BoxFit.contain,
                alignment: Alignment.center,
                color: deckPrimaryColor,
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Opacity(
        opacity: 0.24,
        child: Image.asset(
          _patternAssetForDeckType(deck.type),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          color: deckPrimaryColor,
          colorBlendMode: BlendMode.srcIn,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _pinIcon() {
    if (compact) {
      return Positioned(
        top: 8,
        right: 8,
        child: IgnorePointer(
          child: Image.asset(
            'assets/images/pin_icon.png',
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            color: GakujiColors.darkGray,
            colorBlendMode: BlendMode.srcIn,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.push_pin_rounded,
                size: 20,
                color: GakujiColors.darkGray,
              );
            },
          ),
        ),
      );
    }

    return Positioned(
      top: 8,
      right: 8,
      child: Transform.rotate(
        angle: 0.72,
        child: Icon(
          Icons.push_pin,
          size: 22,
          color: GakujiColors.darkGray,
        ),
      ),
    );
  }

  Widget _watermarkBox() {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        color: deckCircle,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: _watermark(),
      ),
    );
  }

  Widget _watermark() {
    final assetPath = _watermarkAssetForDeckType(deck.type);

    return IgnorePointer(
      child: Image.asset(
        assetPath,
        width: 54,
        height: 54,
        fit: BoxFit.contain,
        color: deckPrimaryColor,
        colorBlendMode: BlendMode.srcIn,
        errorBuilder: (context, error, stackTrace) {
          return Text(
            _watermarkForDeckType(deck.type),
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 48,
              height: 1,
              fontWeight: FontWeight.w700,
              color: deckPrimaryColor,
            ),
          );
        },
      ),
    );
  }

  String _deckTypeLabel(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'Writing';
      case DeckType.reading:
        return 'Reading';
      case DeckType.hybrid:
        return 'Hybrid';
    }
  }

  String _watermarkForDeckType(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return '書';
      case DeckType.reading:
        return '読';
      case DeckType.hybrid:
        return '合';
    }
  }

  String _watermarkAssetForDeckType(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'assets/images/deck_watermark_3.png';
      case DeckType.reading:
        return 'assets/images/deck_watermark_2.png';
      case DeckType.hybrid:
        return 'assets/images/deck_watermark_1.png';
    }
  }

  String _patternAssetForDeckType(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'assets/images/deck_pattern_writing.png';
      case DeckType.reading:
        return 'assets/images/deck_pattern_reading.png';
      case DeckType.hybrid:
        return 'assets/images/deck_pattern_hybrid.png';
    }
  }
}