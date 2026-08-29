import 'package:flutter/material.dart';

import 'gakuji_styles.dart';

class GakujiDomino extends StatelessWidget {
  static const double width = 58;
  static const double height = 68;
  static const double radius = 14;
  static const double borderWidth = 1.7;
  static const double fontSize = 31;

  final String text;
  final String? footerText;
  final TextStyle? footerTextStyle;
  final VoidCallback? onTap;
  final bool invisible;
  final bool dragging;
  final bool selected;
  final Color? selectionColor;
  final bool showFormControl;
  final int formCount;
  final int selectedFormIndex;

  const GakujiDomino({
    super.key,
    required this.text,
    this.footerText,
    this.footerTextStyle,
    this.onTap,
    this.invisible = false,
    this.dragging = false,
    this.selected = false,
    this.selectionColor,
    this.showFormControl = false,
    this.formCount = 1,
    this.selectedFormIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedSelectionColor = selectionColor ?? GakujiColors.mediumGray;
    final hasFooterText = footerText != null && footerText!.isNotEmpty;

    return AnimatedOpacity(
      opacity: invisible ? 0 : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: GakujiColors.whiteCard,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: selected
                ? resolvedSelectionColor
                : GakujiColors.softBorder,
            width: selected ? 2.5 : borderWidth,
          ),
          boxShadow: [dragging ? GakujiShadows.card : GakujiShadows.soft],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: GakujiColors.deckBlue.withValues(alpha: 0.06),
            highlightColor: GakujiColors.deckBlue.withValues(alpha: 0.03),
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: hasFooterText
                          ? 13
                          : showFormControl
                              ? 10
                              : 0,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 140),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.88, end: 1).animate(
                              animation,
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        text,
                        key: ValueKey(text),
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontFamily: GakujiFonts.japanese,
                          fontSize: text.length > 1 ? 22 : fontSize,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          color: GakujiColors.darkGray,
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasFooterText)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 6,
                    child: Text(
                      footerText!,
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.noScaling,
                      style: footerTextStyle ??
                          TextStyle(
                            fontSize: 10.5,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                            color: GakujiColors.mediumGray,
                          ),
                    ),
                  )
                else if (showFormControl && formCount > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 6,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(formCount, (dotIndex) {
                        final isCurrent = dotIndex == selectedFormIndex;

                        return Container(
                          width: isCurrent ? 6 : 5,
                          height: isCurrent ? 6 : 5,
                          margin: EdgeInsets.only(
                            right: dotIndex == formCount - 1 ? 0 : 3,
                          ),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCurrent
                                ? GakujiColors.darkGray
                                : GakujiColors.softBorder,
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
