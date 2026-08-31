import 'package:flutter/material.dart';

import 'package:gakuji/core/theme/gakuji_styles.dart';

class GakujiTopBar extends StatelessWidget {
  static const double horizontalPadding = 14;
  static const double topPadding = 8;
  static const double buttonSize = 44;
  static const double actionGap = 8;
  static const IconData backIcon = Icons.arrow_back_ios_new_rounded;
  static const double iconSize = 28;
  static const double backIconSize = 27;
  static const double backIconHorizontalOffset = -3;

  final IconData? leftIcon;
  final VoidCallback? onLeftTap;
  final Color? leftIconColor;
  final double? leftIconSize;
  final Widget? leftWidget;

  final String? title;
  final Widget? titleWidget;
  final TextStyle? titleStyle;

  final IconData? rightIcon;
  final VoidCallback? onRightTap;
  final Color? rightIconColor;
  final double? rightIconSize;
  final Widget? rightWidget;

  final bool showOptionsButton;
  final VoidCallback? onOptionsTap;
  final bool optionsSelected;

  const GakujiTopBar({
    super.key,
    this.leftIcon,
    this.onLeftTap,
    this.leftIconColor,
    this.leftIconSize,
    this.leftWidget,
    this.title,
    this.titleWidget,
    this.titleStyle,
    this.rightIcon,
    this.onRightTap,
    this.rightIconColor,
    this.rightIconSize,
    this.rightWidget,
    this.showOptionsButton = false,
    this.onOptionsTap,
    this.optionsSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasCustomSide = leftWidget != null || rightWidget != null;
    final sideWidth = hasCustomSide ? buttonSize * 2 + actionGap : buttonSize;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        0,
      ),
      child: SizedBox(
        height: buttonSize,
        child: Row(
          children: [
            SizedBox(
              width: sideWidth,
              child: Align(
                alignment: Alignment.centerLeft,
                child: leftWidget ??
                    _TopBarButton(
                      icon: leftIcon,
                      onTap: onLeftTap,
                      iconColor: leftIconColor,
                      iconSize: leftIconSize,
                    ),
              ),
            ),
            Expanded(
              child: Center(
                child: titleWidget ??
                    Text(
                      title ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: titleStyle ?? GakujiText.pageTitle,
                    ),
              ),
            ),
            SizedBox(
              width: sideWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: rightWidget ?? _rightButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rightButton() {
    if (showOptionsButton) {
      return _TopBarButton(
        icon: Icons.more_horiz,
        onTap: onOptionsTap,
        iconColor: Colors.black,
        iconSize: rightIconSize,
        selected: optionsSelected,
      );
    }

    return _TopBarButton(
      icon: rightIcon,
      onTap: onRightTap,
      iconColor: rightIconColor,
      iconSize: rightIconSize,
    );
  }
}

class _TopBarButton extends StatelessWidget {
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final double? iconSize;
  final bool selected;

  const _TopBarButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.iconSize,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return const SizedBox(
        width: GakujiTopBar.buttonSize,
        height: GakujiTopBar.buttonSize,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: GakujiTopBar.buttonSize,
        height: GakujiTopBar.buttonSize,
        child: Center(
          child: Transform.translate(
            offset: Offset(
              icon == GakujiTopBar.backIcon
                  ? GakujiTopBar.backIconHorizontalOffset
                  : 0,
              0,
            ),
            child: Icon(
              icon,
              size: iconSize ?? GakujiTopBar.iconSize,
              color: iconColor ?? Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}