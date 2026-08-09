import 'dart:io';

import 'package:flutter/material.dart';

import '../models/term.dart';
import 'gakuji_styles.dart';

/// Shared reading-card shell used by both the study page and card editor.
///
/// Card dimensions, border, radius, padding, and shadow live here so changes
/// automatically apply to both places.
class ReadingCardFrame extends StatelessWidget {
  static const double defaultMinHeight = 590;
  static const double defaultRadius = 24;
  static const EdgeInsets defaultPadding = EdgeInsets.all(18);

  final Widget child;
  final EdgeInsetsGeometry margin;
  final double minHeight;
  final double? maxWidth;
  final Color? borderColor;
  final double borderWidth;
  final Color? backgroundColor;
  final List<BoxShadow>? boxShadow;

  const ReadingCardFrame({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.minHeight = defaultMinHeight,
    this.maxWidth,
    this.borderColor,
    this.borderWidth = 1.2,
    this.backgroundColor,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: minHeight,
        maxWidth: maxWidth ?? double.infinity,
      ),
      margin: margin,
      padding: defaultPadding,
      decoration: BoxDecoration(
        color: backgroundColor ?? GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(defaultRadius),
        border: Border.all(
          color: borderColor ?? GakujiColors.softBorder,
          width: borderWidth,
        ),
        boxShadow: boxShadow ?? [GakujiShadows.card],
      ),
      child: child,
    );
  }
}

/// Shared visual layout for the back of a reading card.
///
/// The editor can supply section callbacks, while the study page leaves them
/// null. Typography, spacing, dividers, examples, and photo sizing therefore
/// stay identical in both places.
class ReadingCardBackContent extends StatelessWidget {
  static const double contentVerticalOffset = -52;
  static const double contentFontSize = 16;
  static const double contentLineHeight = 1.16;
  static const int maxNoteCharacters = 50;
  static const int maxVisibleExamples = 1;

  // The card frame is 590 px tall with 18 px of padding on both sides.
  static const double _defaultInnerHeight = 554;
  static const double _photoBottomGap = 4;

  final List<String> glosses;
  final String note;
  final List<DictionaryExample> examples;
  final String? photoPath;
  final String readingText;
  final bool showReadingOnBack;
  final VoidCallback? onGlossTap;
  final VoidCallback? onNoteTap;
  final VoidCallback? onExamplesTap;
  final VoidCallback? onPhotoTap;

  const ReadingCardBackContent({
    super.key,
    required this.glosses,
    this.note = '',
    this.examples = const [],
    this.photoPath,
    this.readingText = '',
    this.showReadingOnBack = false,
    this.onGlossTap,
    this.onNoteTap,
    this.onExamplesTap,
    this.onPhotoTap,
  });

  bool get _hasPhoto {
    final path = photoPath?.trim();
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    final cleanedNote = _limitedNote(note);
    final cleanedReading = readingText.trim();
    final hasNote = cleanedNote.isNotEmpty;
    final hasExamples = examples.isNotEmpty;
    final hasPhoto = _hasPhoto;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : _defaultInnerHeight;

        return SizedBox(
          height: availableHeight,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: const Offset(0, contentVerticalOffset),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(25, 24, 25, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showReadingOnBack &&
                              cleanedReading.isNotEmpty) ...[
                            Text(
                              cleanedReading,
                              textAlign: TextAlign.center,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 20,
                                height: 1,
                                fontWeight: FontWeight.w600,
                                color: GakujiColors.mediumGray,
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          _sectionTapTarget(
                            onTap: onGlossTap,
                            child: _ReadingCardGlosses(
                              glosses: glosses,
                            ),
                          ),
                          if (hasNote) ...[
                            const SizedBox(height: 18),
                            const _ReadingCardDivider(),
                            const SizedBox(height: 14),
                            _sectionTapTarget(
                              onTap: onNoteTap,
                              child: Text(
                                cleanedNote,
                                textAlign: TextAlign.center,
                                textScaler: TextScaler.noScaling,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: contentFontSize,
                                  height: contentLineHeight,
                                  fontWeight: FontWeight.w600,
                                  color: GakujiColors.mediumGray,
                                ),
                              ),
                            ),
                          ],
                          if (hasExamples) ...[
                            const SizedBox(height: 18),
                            const _ReadingCardDivider(),
                            const SizedBox(height: 14),
                            _sectionTapTarget(
                              onTap: onExamplesTap,
                              child: _ReadingCardExamples(
                                examples: examples,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (hasPhoto)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _photoBottomGap,
                  child: Center(
                    child: _sectionTapTarget(
                      onTap: onPhotoTap,
                      child: _ReadingCardPhoto(path: photoPath!.trim()),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _limitedNote(String value) {
    final trimmed = value.trim();

    if (trimmed.runes.length <= maxNoteCharacters) {
      return trimmed;
    }

    return String.fromCharCodes(
      trimmed.runes.take(maxNoteCharacters),
    );
  }

  Widget _sectionTapTarget({
    required Widget child,
    VoidCallback? onTap,
  }) {
    if (onTap == null) return child;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: GakujiColors.deckBlue.withOpacity(0.08),
        highlightColor: GakujiColors.deckBlue.withOpacity(0.04),
        child: child,
      ),
    );
  }
}

class _ReadingCardGlosses extends StatelessWidget {
  final List<String> glosses;

  const _ReadingCardGlosses({
    required this.glosses,
  });

  @override
  Widget build(BuildContext context) {
    if (glosses.isEmpty) {
      return Text(
        'No glosses selected',
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        softWrap: true,
        style: TextStyle(
          fontSize: ReadingCardBackContent.contentFontSize,
          height: ReadingCardBackContent.contentLineHeight,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
          color: GakujiColors.darkGray,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: glosses.asMap().entries.map((entry) {
        final label = glosses.length == 1
            ? ''
            : '${String.fromCharCode(65 + entry.key)}. ';

        return Padding(
          padding: EdgeInsets.only(
            bottom: entry.key == glosses.length - 1 ? 0 : 7,
          ),
          child: Text(
            '$label${entry.value}',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            softWrap: true,
            style: TextStyle(
              fontSize: ReadingCardBackContent.contentFontSize,
              height: ReadingCardBackContent.contentLineHeight,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.35,
              color: GakujiColors.darkGray,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ReadingCardDivider extends StatelessWidget {
  const _ReadingCardDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 3,
      decoration: BoxDecoration(
        color: GakujiColors.softBorder.withOpacity(0.75),
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
      ),
    );
  }
}

class _ReadingCardExamples extends StatelessWidget {
  static const double contentFontSize =
      ReadingCardBackContent.contentFontSize;
  static const double contentLineHeight =
      ReadingCardBackContent.contentLineHeight;

  final List<DictionaryExample> examples;

  const _ReadingCardExamples({
    required this.examples,
  });

  @override
  Widget build(BuildContext context) {
    final visibleExamples = examples
        .take(ReadingCardBackContent.maxVisibleExamples)
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: visibleExamples.map((example) {
        final english = example.english.trim();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              example.japanese,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              softWrap: true,
              style: TextStyle(
                fontSize: contentFontSize,
                height: contentLineHeight,
                fontWeight: FontWeight.w800,
                color: GakujiColors.darkGray,
              ),
            ),
            if (english.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                english,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                softWrap: true,
                style: TextStyle(
                  fontSize: contentFontSize,
                  height: contentLineHeight,
                  fontWeight: FontWeight.w600,
                  color: GakujiColors.mediumGray,
                ),
              ),
            ],
          ],
        );
      }).toList(),
    );
  }
}

class _ReadingCardPhoto extends StatelessWidget {
  final String path;

  const _ReadingCardPhoto({
    required this.path,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.file(
        File(path),
        width: 188,
        height: 132,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 188,
            height: 132,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: GakujiColors.softBorder,
                width: 1,
              ),
            ),
            child: Text(
              'Photo unavailable',
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 13,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: GakujiColors.mediumGray,
              ),
            ),
          );
        },
      ),
    );
  }
}
