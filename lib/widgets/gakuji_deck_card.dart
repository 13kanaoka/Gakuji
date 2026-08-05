import 'package:flutter/material.dart';

import 'gakuji_styles.dart';

enum GakujiDeckCardSize {
  large,
  compact,
}

class GakujiDeckCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String watermark;
  final String? watermarkAssetPath;
  final String? patternAssetPath;
  final String? pinAssetPath;
  final VoidCallback onTap;
  final GakujiDeckCardSize size;
  final Color? shellColor;
  final Color? cardColor;
  final bool showShell;
  final bool isPinned;

  /// Kept for compatibility with older calls.
  /// The redesigned deck card no longer displays these counts.
  final int? newCount;
  final int? learnCount;
  final int? reviewCount;

  const GakujiDeckCard({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.watermark,
    this.watermarkAssetPath,
    this.patternAssetPath,
    this.pinAssetPath,
    required this.onTap,
    this.size = GakujiDeckCardSize.large,
    this.shellColor,
    this.cardColor,
    this.showShell = true,
    this.isPinned = false,
    this.newCount,
    this.learnCount,
    this.reviewCount,
  });

  static const Color readingBlue = Color(0xFF5B84B8);
  static const Color writingGreen = Color(0xFF7C8F3A);
  static const Color hybridRed = Color(0xFFA57A48);
  Color get deckCircle => resolvedCardColor;

  bool get hasSubtitle {
    return subtitle.trim().isNotEmpty;
  }

  bool get isHybrid {
    return subtitle.toLowerCase().trim() == 'hybrid';
  }

  int get titleCharacterLimit {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 14;
      case GakujiDeckCardSize.compact:
        return 12;
    }
  }

  String get displayedTitle {
    final cleanTitle = title.trim();

    if (cleanTitle.length <= titleCharacterLimit) {
      return cleanTitle;
    }

    return '${cleanTitle.substring(0, titleCharacterLimit)}...';
  }

  double get cardHeight {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 86;
      case GakujiDeckCardSize.compact:
        return 74;
    }
  }

  double get borderRadius {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 18;
      case GakujiDeckCardSize.compact:
        return 16;
    }
  }

  double get leftInset {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 18;
      case GakujiDeckCardSize.compact:
        return 15;
    }
  }

  double get rightInset {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 18;
      case GakujiDeckCardSize.compact:
        return 16;
    }
  }

  double get circleSize {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 66;
      case GakujiDeckCardSize.compact:
        return 57;
    }
  }

  double get watermarkTextSize {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 48;
      case GakujiDeckCardSize.compact:
        return 40;
    }
  }

  double get watermarkImageSize {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 54;
      case GakujiDeckCardSize.compact:
        return 46;
    }
  }

  double get patternSize {
    switch (size) {
      case GakujiDeckCardSize.large:
        return isHybrid ? 450 : 340;
      case GakujiDeckCardSize.compact:
        return isHybrid ? 320 : 280;
    }
  }

  double get patternRightOffset {
    switch (size) {
      case GakujiDeckCardSize.large:
        return isHybrid ? -210 : -122;
      case GakujiDeckCardSize.compact:
        return isHybrid ? -185 : -102;
    }
  }

  double get patternTopOffset {
    switch (size) {
      case GakujiDeckCardSize.large:
        return isHybrid ? -165 : -127;
      case GakujiDeckCardSize.compact:
        return isHybrid ? -122 : -102;
    }
  }

  double get titleLeftPadding {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 94;
      case GakujiDeckCardSize.compact:
        return 80;
    }
  }

  double get pinIconSize {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 22;
      case GakujiDeckCardSize.compact:
        return 18;
    }
  }

  double get pinIconTop {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 8;
      case GakujiDeckCardSize.compact:
        return 6;
    }
  }

  double get pinIconRight {
    switch (size) {
      case GakujiDeckCardSize.large:
        return 8;
      case GakujiDeckCardSize.compact:
        return 7;
    }
  }

  Color get deckTypeColor {
    switch (subtitle.toLowerCase().trim()) {
      case 'reading':
        return readingBlue;
      case 'writing':
        return writingGreen;
      case 'hybrid':
        return hybridRed;
      default:
        return GakujiColors.deckBlue;
    }
  }

  Color get resolvedCardColor {
    return cardColor ?? GakujiColors.warmCard;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: resolvedCardColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: GakujiColors.softBorder,
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: GakujiColors.deckBlue.withOpacity(0.07),
          highlightColor: GakujiColors.deckBlue.withOpacity(0.035),
          child: SizedBox(
            height: cardHeight,
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  right: patternRightOffset,
                  top: patternTopOffset,
                  child: _pattern(),
                ),
                Positioned(
                  left: leftInset,
                  top: 0,
                  bottom: 0,
                  child: _watermarkBox(),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    titleLeftPadding,
                    0,
                    rightInset + 26,
                    0,
                  ),
                  child: _mainContent(),
                ),
                if (isPinned) _pinIcon(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mainContent() {
    return Row(
      children: [
        Expanded(
          child: _titleBlock(),
        ),
      ],
    );
  }

  Widget _titleBlock() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayedTitle,
          maxLines: 1,
          overflow: TextOverflow.clip,
          textScaler: TextScaler.noScaling,
          style: GakujiText.small.copyWith(
            color: GakujiColors.darkGray,
          ),
        ),
        if (hasSubtitle) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              color: GakujiColors.darkGray,
            ),
          ),
        ],
      ],
    );
  }

   Widget _pattern() {
    final assetPath = patternAssetPath;

    if (assetPath == null || assetPath.isEmpty) {
      return const SizedBox.shrink();
    }

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
            width: patternSize,
            height: patternSize,
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _watermarkBox() {
    return Center(
      child: Container(
        width: circleSize,
        height: circleSize,
        decoration: BoxDecoration(
          color: deckCircle,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: _watermarkContent(),
        ),
      ),
    );
  }

  Widget _watermarkContent() {
    final assetPath = watermarkAssetPath;

    if (assetPath != null && assetPath.isNotEmpty) {
      return Image.asset(
        assetPath,
        width: watermarkImageSize,
        height: watermarkImageSize,
        fit: BoxFit.contain,
        color: deckTypeColor,
        colorBlendMode: BlendMode.srcIn,
        errorBuilder: (context, error, stackTrace) {
          return _textWatermarkContent();
        },
      );
    }

    return _textWatermarkContent();
  }

  Widget _textWatermarkContent() {
    return Text(
      watermark,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: watermarkTextSize,
        height: 1,
        fontWeight: FontWeight.w700,
        color: deckTypeColor,
      ),
    );
  }

  Widget _pinIcon() {
    final assetPath = pinAssetPath;

    return Positioned(
      top: pinIconTop,
      right: pinIconRight,
      child: IgnorePointer(
        child: assetPath != null && assetPath.isNotEmpty
            ? Image.asset(
                assetPath,
                width: pinIconSize,
                height: pinIconSize,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return _fallbackPinIcon();
                },
              )
            : _fallbackPinIcon(),
      ),
    );
  }

  Widget _fallbackPinIcon() {
    return Transform.rotate(
      angle: 0.72,
      child: Icon(
        Icons.push_pin,
        size: pinIconSize,
        color: GakujiColors.darkGray,
      ),
    );
  }
}