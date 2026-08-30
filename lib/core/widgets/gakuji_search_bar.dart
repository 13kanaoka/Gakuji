import 'package:flutter/material.dart';

import 'package:gakuji/core/theme/gakuji_styles.dart';

class GakujiSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final VoidCallback? onTap;
  final bool enabled;
  final bool showClearButton;

  const GakujiSearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hintText,
    required this.onChanged,
    this.onClear,
    this.onTap,
    this.enabled = true,
    this.showClearButton = false,
  });

  @override
  State<GakujiSearchBar> createState() => _GakujiSearchBarState();
}

class _GakujiSearchBarState extends State<GakujiSearchBar> {
  static const double _barHeight = 44;
  static const double _borderWidth = 1.5;

  late final FocusNode _internalFocusNode;

  FocusNode get _activeFocusNode {
    return widget.focusNode ?? _internalFocusNode;
  }

  @override
  void initState() {
    super.initState();

    _internalFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _internalFocusNode.dispose();

    super.dispose();
  }

  void _focusSearchBar() {
    if (!widget.enabled) return;

    _activeFocusNode.requestFocus();
    widget.onTap?.call();
  }

  void _clearSearchBar() {
    if (widget.onClear == null) return;

    widget.onClear!();
    _focusSearchBar();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _barHeight,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: GakujiColors.warmCard,
          shape: StadiumBorder(
            side: BorderSide(
              color: GakujiColors.warmDivider,
              width: _borderWidth,
            ),
          ),
          shadows: [GakujiShadows.soft],
        ),
        child: TextField(
          focusNode: _activeFocusNode,
          controller: widget.controller,
          enabled: widget.enabled,
          onTap: widget.onTap,
          onChanged: widget.onChanged,
          enableInteractiveSelection: true,
          textAlignVertical: TextAlignVertical.center,
          style: TextStyle(
            fontSize: 16,
            height: 1,
            fontWeight: FontWeight.w400,
            color: GakujiColors.darkGray,
          ),
          cursorColor: GakujiColors.darkGray,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(
              fontSize: 16,
              height: 1,
              fontWeight: FontWeight.w400,
              color: GakujiColors.mediumGray,
            ),
            prefixIcon: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _focusSearchBar,
              child: Icon(
                Icons.search,
                size: 22,
                color: GakujiColors.darkGray,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 47,
              minHeight: 44,
            ),
            suffixIcon: widget.showClearButton
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _clearSearchBar,
                    child: SizedBox(
                      width: 40,
                      height: _barHeight,
                      child: Center(
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: GakujiColors.darkGray,
                        ),
                      ),
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 44,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
          ),
        ),
      ),
    );
  }
}
