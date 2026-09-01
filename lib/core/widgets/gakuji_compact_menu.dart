import 'dart:async';

import 'package:flutter/material.dart';

import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';

enum GakujiCompactMenuAlignment {
  topLeft,
  topRight,
}

class GakujiCompactMenuItem {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;
  final Color? iconColor;
  final Color? textColor;
  final bool selected;

  const GakujiCompactMenuItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.iconColor,
    this.textColor,
    this.selected = false,
  }) : assert(icon == null || leading == null);
}

class GakujiCompactMenuButton extends StatefulWidget {
  final IconData icon;
  final List<GakujiCompactMenuItem> items;
  final GakujiCompactMenuAlignment alignment;
  final Color? iconColor;
  final double iconSize;
  final double menuWidth;
  final double horizontalOffset;
  final bool enabled;
  final VoidCallback? onBeforeOpen;

  const GakujiCompactMenuButton({
    super.key,
    required this.icon,
    required this.items,
    this.alignment = GakujiCompactMenuAlignment.topRight,
    this.iconColor,
    this.iconSize = GakujiTopBar.iconSize,
    this.menuWidth = 194,
    this.horizontalOffset = 0,
    this.enabled = true,
    this.onBeforeOpen,
  });

  @override
  State<GakujiCompactMenuButton> createState() =>
      _GakujiCompactMenuButtonState();
}

class _GakujiCompactMenuButtonState extends State<GakujiCompactMenuButton>
    with SingleTickerProviderStateMixin {
  static const Duration _menuAnimationDuration = Duration(milliseconds: 190);

  final GlobalKey _anchorKey = GlobalKey();

  OverlayEntry? _overlayEntry;
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  bool get isOpen => _overlayEntry != null;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: _menuAnimationDuration,
      reverseDuration: const Duration(milliseconds: 140),
    );
    final curvedAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _scaleAnimation = Tween<double>(begin: 0.72, end: 1).animate(
      curvedAnimation,
    );
  }

  @override
  void didUpdateWidget(covariant GakujiCompactMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    final overlayEntry = _overlayEntry;
    if (overlayEntry == null) return;

    // Parent widgets such as GakujiTopBar can rebuild while this menu is open.
    // Rebuilding the OverlayEntry synchronously from didUpdateWidget would mark
    // the overlay dirty during that parent build, which Flutter does not allow.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _overlayEntry != overlayEntry) return;
      overlayEntry.markNeedsBuild();
    });
  }

  @override
  void deactivate() {
    _removeOverlay();
    super.deactivate();
  }

  @override
  void dispose() {
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _toggleMenu() async {
    if (!widget.enabled || widget.items.isEmpty) return;

    if (isOpen) {
      await _closeMenu();
      return;
    }

    widget.onBeforeOpen?.call();
    _openMenu();
  }

  void _openMenu() {
    final anchorContext = _anchorKey.currentContext;
    final overlay = Overlay.of(context, rootOverlay: true);
    final renderObject = anchorContext?.findRenderObject();

    if (anchorContext == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      return;
    }

    final anchorTopLeft = renderObject.localToGlobal(Offset.zero);
    final anchorRect = anchorTopLeft & renderObject.size;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final screenWidth = MediaQuery.sizeOf(overlayContext).width;
        final maxLeft = screenWidth - widget.menuWidth - 8;
        final rawLeft = switch (widget.alignment) {
          GakujiCompactMenuAlignment.topLeft =>
            anchorRect.left + widget.horizontalOffset,
          GakujiCompactMenuAlignment.topRight =>
            anchorRect.right - widget.menuWidth + widget.horizontalOffset,
        };
        final menuLeft =
            rawLeft.clamp(8.0, maxLeft < 8 ? 8.0 : maxLeft).toDouble();
        final scaleAlignment =
            widget.alignment == GakujiCompactMenuAlignment.topLeft
            ? Alignment.topLeft
            : Alignment.topRight;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => unawaited(_closeMenu()),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            Positioned(
              top: anchorRect.top,
              left: menuLeft,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  alignment: scaleAlignment,
                  child: _menuCard(),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
    _animationController.forward(from: 0);
  }

  Future<void> _closeMenu() async {
    if (!isOpen) return;

    try {
      await _animationController.reverse();
    } on TickerCanceled {
      return;
    }

    _removeOverlay();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;

    if (_animationController.isAnimating || _animationController.value != 0) {
      _animationController.value = 0;
    }
  }

  Future<void> _selectItem(GakujiCompactMenuItem item) async {
    await _closeMenu();
    if (!mounted) return;
    item.onTap();
  }

  Widget _menuCard() {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: widget.menuWidth,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: GakujiColors.warmCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: GakujiColors.warmDivider,
            width: 1,
          ),
          boxShadow: [GakujiShadows.soft],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < widget.items.length; index++) ...[
              _menuItem(widget.items[index]),
              if (index != widget.items.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: GakujiColors.warmDivider,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _menuItem(GakujiCompactMenuItem item) {
    final textColor = item.textColor ?? GakujiColors.darkGray;

    return InkWell(
      onTap: () => unawaited(_selectItem(item)),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              if (item.leading != null) ...[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(child: item.leading),
                ),
                const SizedBox(width: 10),
              ] else if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: 22,
                  color: item.iconColor ?? textColor,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  item.label,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1,
                    fontWeight:
                        item.selected ? FontWeight.w700 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
              if (item.selected)
                const Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: GakujiColors.reading,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _anchorKey,
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? () => unawaited(_toggleMenu()) : null,
      child: SizedBox(
        width: GakujiTopBar.buttonSize,
        height: GakujiTopBar.buttonSize,
        child: Center(
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: widget.iconColor ?? GakujiColors.darkGray,
          ),
        ),
      ),
    );
  }
}
