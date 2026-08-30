import 'package:flutter/material.dart';

import 'package:gakuji/widgets/gakuji_styles.dart';

class GakujiLearningCard extends StatelessWidget {
  static const double cardHeight = 148;
  static const double _backgroundGraphicWidth = 410;
  static const double _backgroundGraphicHeight = 286;
  static const double _lightBackgroundGraphicOpacity = 0.24;
  static const double _darkBackgroundGraphicOpacity = 0.22;

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
                right: -96,
                top: -69,
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
          style: GakujiText.learningCardTitle,
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
          textScaler: TextScaler.noScaling,
          style: GakujiText.learningCardSubtitle.copyWith(
            color: GakujiColors.mediumGray.withValues(alpha: 0.78),
          ),
        ),
      ],
    );
  }

  Widget _backgroundGraphic() {
    return IgnorePointer(
      child: Opacity(
        opacity: GakujiColors.isDarkMode
            ? _darkBackgroundGraphicOpacity
            : _lightBackgroundGraphicOpacity,
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
            width: _backgroundGraphicWidth,
            height: _backgroundGraphicHeight,
            child: Image.asset(
              backgroundAsset,
              fit: BoxFit.cover,
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
      ),
    );
  }
}
