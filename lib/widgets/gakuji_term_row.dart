import 'package:flutter/material.dart';

import '../models/term.dart';
import 'gakuji_styles.dart';

class GakujiTermRow extends StatelessWidget {
  static const Color dividerColor = Color(0xFFC8C8C8);
  static const Color _readingGray = Color(0xFF85868A);
  static const Color _readingFrameGray = Color(0xFFB7B8BC);
  static const Color _chevronGray = Color(0xFF8A8A8A);

  final Term term;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;
  final String? titleText;
  final String? readingText;
  final bool showChevron;
  final bool isSelected;
  final int meaningMaxLines;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  const GakujiTermRow({
    super.key,
    required this.term,
    this.onTap,
    this.leading,
    this.trailing,
    this.titleText,
    this.readingText,
    this.showChevron = true,
    this.isSelected = false,
    this.meaningMaxLines = 1,
    this.padding = const EdgeInsets.fromLTRB(0, 9, 0, 10),
    this.backgroundColor,
  });

  String get _resolvedTitleText {
    final suppliedTitle = titleText?.trim() ?? '';

    if (suppliedTitle.isNotEmpty) {
      return suppliedTitle;
    }

    if (term.kanjiBracketText.trim().isNotEmpty) {
      return term.kanjiBracketText.trim();
    }

    if (term.kanji.trim().isNotEmpty) {
      return term.kanji.trim();
    }

    return term.reading.trim();
  }

  bool _containsKanji(String text) {
    return text.runes.any((rune) {
      return (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0xF900 && rune <= 0xFAFF) ||
          rune == 0x3005;
    });
  }

  String get _resolvedReadingText {
    final resolvedTitle = _resolvedTitleText;

    // Kana-only terms already display their pronunciation as the title,
    // so repeating it would add no useful information.
    if (!_containsKanji(resolvedTitle)) {
      return '';
    }

    final resolvedReading =
        readingText != null ? readingText!.trim() : term.reading.trim();

    if (resolvedReading == resolvedTitle) {
      return '';
    }

    return resolvedReading;
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 25,
                  runSpacing: 4,
                  children: [
                    Text(
                      _resolvedTitleText,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 22,
                        height: 1,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w700,
                        color: GakujiColors.darkGray,
                      ),
                    ),
                    if (_resolvedReadingText.isNotEmpty)
                      _CornerReadingFrame(
                        child: Text(
                          _resolvedReadingText,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            color: _readingGray,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  term.cardMeaning,
                  maxLines: meaningMaxLines,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.15,
                    color: GakujiColors.darkGray,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ] else if (showChevron) ...[
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right,
              size: 27,
              color: _chevronGray,
            ),
          ],
        ],
      ),
    );

    return Material(
      color: backgroundColor ?? GakujiColors.warmBackground,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              child: content,
            ),
    );
  }
}

class _CornerReadingFrame extends StatelessWidget {
  final Widget child;

  const _CornerReadingFrame({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: const _CornerFramePainter(
        color: GakujiTermRow._readingFrameGray,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: child,
      ),
    );
  }
}

class _CornerFramePainter extends CustomPainter {
  final Color color;

  const _CornerFramePainter({
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double cornerLength = 6;
    const double inset = 0.75;

    final left = inset;
    final right = size.width - inset;
    final top = inset;
    final bottom = size.height - inset;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      // Connected left side with short top and bottom caps.
      ..moveTo(left + cornerLength, top)
      ..lineTo(left, top)
      ..lineTo(left, bottom)
      ..lineTo(left + cornerLength, bottom)

      // Connected right side with short top and bottom caps.
      ..moveTo(right - cornerLength, top)
      ..lineTo(right, top)
      ..lineTo(right, bottom)
      ..lineTo(right - cornerLength, bottom);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerFramePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}