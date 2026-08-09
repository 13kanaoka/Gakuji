import 'package:flutter/material.dart';

import 'gakuji_styles.dart';

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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focusSearchBar,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: GakujiColors.warmCard,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: GakujiColors.warmDivider,
            width: 1.5,
          ),
          boxShadow: [GakujiShadows.soft],
        ),
        child: Row(
          children: [
             Icon(
              Icons.search,
              size: 22,
              color: GakujiColors.darkGray,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                focusNode: _activeFocusNode,
                controller: widget.controller,
                enabled: widget.enabled,
                onTap: widget.onTap,
                onChanged: widget.onChanged,
                style: TextStyle(
                  fontSize: 16,
                  height: 1,
                  fontWeight: FontWeight.w400,
                  color: GakujiColors.darkGray,
                ),
                cursorColor: GakujiColors.darkGray,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle:  TextStyle(
                    fontSize: 16,
                    height: 1,
                    fontWeight: FontWeight.w400,
                    color: GakujiColors.mediumGray,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
            if (widget.showClearButton)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clearSearchBar,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: GakujiColors.darkGray,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}