import 'package:flutter/material.dart';

import '../models/term.dart';
import 'gakuji_styles.dart';

class GakujiTermRow extends StatelessWidget {
  static const Color dividerColor = Color(0xFFC8C8C8);
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
    this.showChevron = false,
    this.isSelected = false,
    this.meaningMaxLines = 1,
    this.padding = const EdgeInsets.fromLTRB(0, 4, 0, 5),
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

  String get _resolvedReadingText {
    final resolvedReading =
        readingText != null ? readingText!.trim() : term.reading.trim();

    if (resolvedReading.isEmpty || resolvedReading == _resolvedTitleText) {
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
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 10,
                  runSpacing: 0,
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
                      Text(
                        '【$_resolvedReadingText】',
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          fontSize: 19,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          color: GakujiColors.reading,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  term.cardMeaning,
                  maxLines: meaningMaxLines,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1,
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
