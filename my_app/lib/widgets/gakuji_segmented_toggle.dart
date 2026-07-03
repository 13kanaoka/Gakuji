import 'package:flutter/material.dart';

class GakujiSegmentedToggle extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final bool isLeftSelected;
  final VoidCallback onLeftTap;
  final VoidCallback onRightTap;

  const GakujiSegmentedToggle({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.isLeftSelected,
    required this.onLeftTap,
    required this.onRightTap,
  });

  static const double height = 38;
  static const double innerHeight = 30;
  static const double buttonWidth = 86;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFB5B5B5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GakujiSegmentedToggleButton(
                label: leftLabel,
                selected: isLeftSelected,
                onTap: onLeftTap,
              ),
              _GakujiSegmentedToggleButton(
                label: rightLabel,
                selected: !isLeftSelected,
                onTap: onRightTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GakujiSegmentedToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GakujiSegmentedToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: GakujiSegmentedToggle.buttonWidth,
      height: GakujiSegmentedToggle.innerHeight,
      child: Material(
        color: selected ? const Color(0xFFDCDCDC) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                fontSize: 16,
                height: 1,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}