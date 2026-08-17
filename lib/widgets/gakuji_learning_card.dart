import 'package:flutter/material.dart';

import 'gakuji_styles.dart';

class GakujiLearningCard extends StatelessWidget {
  static const double cardHeight = 148;

  final String label;
  final String subtitle;
  final String backgroundAsset;
  final VoidCallback onTap;

  const GakujiLearningCard({
    super.key,
    required this.label,
    required this.subtitle,
    required this.backgroundAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: cardHeight,
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
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
          splashColor: GakujiColors.darkGray.withValues(alpha: 0.06),
          highlightColor: GakujiColors.darkGray.withValues(alpha: 0.03),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                right: 24,
                top: 7,
                child: _backgroundGraphic(),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(left: 22, right: 136),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _labelBlock(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelBlock() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          textAlign: TextAlign.left,
          textScaler: TextScaler.noScaling,
          style: GakujiText.xLarge.copyWith(
            fontSize: 38,
            height: 0.94,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: GakujiColors.darkGray,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
          textScaler: TextScaler.noScaling,
          style: GakujiText.xSmall.copyWith(
            fontSize: 16.5,
            height: 1.03,
            fontWeight: FontWeight.w600,
            color: GakujiColors.mediumGray.withValues(alpha: 0.62),
          ),
        ),
      ],
    );
  }

  Widget _backgroundGraphic() {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.40,
        child: SizedBox(
          width: 145,
          height: 135,
          child: Image.asset(
            backgroundAsset,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            color: GakujiColors.isDarkMode
                ? Colors.white
                : GakujiColors.darkGray,
            colorBlendMode: BlendMode.srcIn,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
