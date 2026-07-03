import 'package:flutter/material.dart';

import 'gakuji_styles.dart';

enum GakujiDeckCardSize {
  large,
  compact,
}

class GakujiDeckCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String watermark;
  final String? watermarkAssetPath;
  final VoidCallback onTap;
  final GakujiDeckCardSize size;
  final Color? shellColor;
  final Color? cardColor;
  final bool showShell;
  final bool isPinned;

  const GakujiDeckCard({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.watermark,
    this.watermarkAssetPath,
    required this.onTap,
    this.size = GakujiDeckCardSize.large,
    this.shellColor,
    this.cardColor,
    this.showShell = true,
    this.isPinned = false,
  });

  @override
  State<GakujiDeckCard> createState() => _GakujiDeckCardState();
}

class _GakujiDeckCardState extends State<GakujiDeckCard> {
  static const Color defaultShellBlue = Color(0xFF7EA2FF);
  static const Color pinRed = Color(0xFFFF4B4B);

  bool isPressed = false;
  bool isTapLocked = false;

  bool get hasSubtitle {
    return widget.subtitle.trim().isNotEmpty;
  }

  double get innerHeight {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return 66;
      case GakujiDeckCardSize.compact:
        return 58;
    }
  }

  double get shellPadding {
    if (!widget.showShell) return 0;

    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return 6;
      case GakujiDeckCardSize.compact:
        return 5;
    }
  }

  double get totalHeight {
    return innerHeight + shellPadding * 2;
  }

  double get titleSize {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return 20;
      case GakujiDeckCardSize.compact:
        return 17;
    }
  }

  double get subtitleSize {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return 13;
      case GakujiDeckCardSize.compact:
        return 12;
    }
  }

  double get textWatermarkSize {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return 82;
      case GakujiDeckCardSize.compact:
        return 68;
    }
  }

  double get imageWatermarkSize {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return 104;
      case GakujiDeckCardSize.compact:
        return 86;
    }
  }

  EdgeInsetsGeometry get contentPadding {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return const EdgeInsets.fromLTRB(16, 7, 16, 13);
      case GakujiDeckCardSize.compact:
        return const EdgeInsets.fromLTRB(14, 6, 14, 11);
    }
  }

  double get watermarkTop {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return -17;
      case GakujiDeckCardSize.compact:
        return -13;
    }
  }

  double get watermarkRight {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return 24;
      case GakujiDeckCardSize.compact:
        return 20;
    }
  }

  double get contentYOffset {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return 3;
      case GakujiDeckCardSize.compact:
        return 2;
    }
  }

  double get pinDotSize {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return 11;
      case GakujiDeckCardSize.compact:
        return 10;
    }
  }

  double get pinDotOffset {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return 9;
      case GakujiDeckCardSize.compact:
        return 8;
    }
  }

  BorderRadius get shellBorderRadius {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return BorderRadius.circular(20);
      case GakujiDeckCardSize.compact:
        return BorderRadius.circular(18);
    }
  }

  BorderRadius get cardBorderRadius {
    switch (widget.size) {
      case GakujiDeckCardSize.large:
        return BorderRadius.circular(18);
      case GakujiDeckCardSize.compact:
        return BorderRadius.circular(16);
    }
  }

  Color get shellColor {
    return widget.shellColor ?? defaultShellBlue;
  }

  Color get cardColor {
    return widget.cardColor ?? GakujiColors.deckBlue;
  }

  void setPressed(bool value) {
    if (!mounted || isPressed == value) return;

    setState(() {
      isPressed = value;
    });
  }

  Future<void> handleTap() async {
    if (isTapLocked) return;

    isTapLocked = true;
    setPressed(true);

    await Future.delayed(const Duration(milliseconds: 75));

    if (!mounted) return;

    setPressed(false);

    await Future.delayed(const Duration(milliseconds: 35));

    if (!mounted) return;

    isTapLocked = false;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final outerRadius = widget.showShell ? shellBorderRadius : cardBorderRadius;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setPressed(true),
      onTapCancel: () => setPressed(false),
      onTap: handleTap,
      child: AnimatedContainer(
        height: totalHeight,
        duration: const Duration(milliseconds: 55),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          0,
          isPressed ? 7 : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: widget.showShell ? shellColor : Colors.transparent,
          borderRadius: outerRadius,
          boxShadow: isPressed
              ? const []
              : const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 0,
                    offset: Offset(0, 7),
                  ),
                ],
        ),
        padding: EdgeInsets.all(shellPadding),
        child: Material(
          color: cardColor,
          borderRadius: cardBorderRadius,
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: innerHeight,
            child: Stack(
              children: [
                _watermarkLayer(),
                Padding(
                  padding: contentPadding,
                  child: hasSubtitle ? _titleWithSubtitle() : _titleOnly(),
                ),
                if (widget.isPinned) _pinDot(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleOnly() {
    return Transform.translate(
      offset: Offset(0, contentYOffset),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _titleText(),
      ),
    );
  }

  Widget _titleWithSubtitle() {
    return Transform.translate(
      offset: Offset(0, contentYOffset),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titleText(),
            const SizedBox(height: 5),
            Text(
              widget.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: subtitleSize,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
                color: const Color(0x55FFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titleText() {
    return Text(
      widget.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: titleSize,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: Colors.white,
      ),
    );
  }

  Widget _pinDot() {
    return Positioned(
      top: pinDotOffset,
      left: pinDotOffset,
      child: IgnorePointer(
        child: Container(
          width: pinDotSize,
          height: pinDotSize,
          decoration: BoxDecoration(
            color: pinRed,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 0,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _watermarkLayer() {
    final assetPath = widget.watermarkAssetPath;

    return Positioned(
      right: watermarkRight,
      top: watermarkTop,
      child: IgnorePointer(
        child: Opacity(
          opacity: assetPath != null && assetPath.isNotEmpty ? 0.22 : 1,
          child: assetPath != null && assetPath.isNotEmpty
              ? Image.asset(
                  assetPath,
                  width: imageWatermarkSize,
                  height: imageWatermarkSize,
                  fit: BoxFit.contain,
                  color: Colors.white,
                  colorBlendMode: BlendMode.srcIn,
                  errorBuilder: (context, error, stackTrace) {
                    return _textWatermarkContent();
                  },
                )
              : _textWatermarkContent(),
        ),
      ),
    );
  }

  Widget _textWatermarkContent() {
    return Text(
      widget.watermark,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: textWatermarkSize,
        height: 1,
        fontWeight: FontWeight.w900,
        color: const Color(0x20FFFFFF),
      ),
    );
  }
}