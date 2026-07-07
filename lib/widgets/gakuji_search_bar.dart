import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

class GakujiSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final bool enabled;
  final bool showClearButton;
  final FocusNode? focusNode;

  const GakujiSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onClear,
    this.focusNode,
    this.enabled = true,
    this.showClearButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => focusNode?.requestFocus(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 22, color: Colors.black),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  onChanged: onChanged,
                  style: AppText.input,
                  cursorColor: Colors.black,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: AppText.inputHint,
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
              if (showClearButton)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClear,
                  child: const SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: Icon(Icons.close, size: 18, color: Colors.black),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
