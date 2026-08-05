import 'package:flutter/material.dart';

import '../models/deck.dart';
import 'gakuji_styles.dart';

class GakujiTodoDeckCard extends StatelessWidget {
  final Deck deck;

  final int newCount;
  final int learningCount;
  final int reviewCount;

  final bool isPinned;
  final VoidCallback onTap;

  const GakujiTodoDeckCard({
    super.key,
    required this.deck,
    required this.newCount,
    required this.learningCount,
    required this.reviewCount,
    required this.isPinned,
    required this.onTap,
  });

  static const double cardHeight = 148;
  static const double reviewBarHeight = 48;

  static Color get cardSurface => GakujiColors.warmCard;
  static Color get deckCircle => cardSurface.withOpacity(0.10);

  Color get deckPrimaryColor {
    switch (deck.type) {
      case DeckType.reading:
        return GakujiColors.reading;
      case DeckType.writing:
        return GakujiColors.writing;
      case DeckType.hybrid:
        return GakujiColors.hybrid;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: cardHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardSurface,
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
          splashColor: deckPrimaryColor.withOpacity(0.08),
          highlightColor: deckPrimaryColor.withOpacity(0.04),
          child: Stack(
            children: [
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
              if (isPinned)
                Positioned(
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
                ),
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
          style: GakujiText.small.copyWith(
            color: GakujiColors.darkGray,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _deckTypeLabel(deck.type),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textScaler: TextScaler.noScaling,
          style: GakujiText.xSmall.copyWith(
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
        color: deckPrimaryColor.withOpacity(0.92),
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
        color: Colors.white,
      ),
    );
  }

  Widget _pattern() {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.24,
        child: Image.asset(
          _patternAssetForDeckType(deck.type),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.shrink();
          },
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