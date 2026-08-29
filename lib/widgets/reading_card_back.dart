import 'dart:io';

import 'package:flutter/material.dart';

import '../models/term.dart';
import 'gakuji_furigana_sentence.dart';
import 'gakuji_styles.dart';

/// Shared reading-card shell used by both the study page and card editor.
///
/// Card dimensions, border, radius, padding, and shadow live here so changes
/// automatically apply to both places.
class ReadingCardFrame extends StatelessWidget {
  static const double defaultMinHeight = 590;
  static const double readingStudyMinHeight = 640;
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
  final bool? isStarred;
  final VoidCallback? onStarTap;

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
    this.isStarred,
    this.onStarTap,
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
      child: _cardChild(),
    );
  }

  Widget _cardChild() {
    if (isStarred == null || onStarTap == null) {
      return child;
    }

    return Stack(
      children: [
        child,
        Positioned(
          top: -2,
          right: -2,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onStarTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Icon(
                  isStarred!
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 30,
                  color: isStarred!
                      ? GakujiColors.starred
                      : GakujiColors.mediumGray,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared visual layout for the back of a reading card.
///
/// The editor can supply section callbacks, while the study page leaves them
/// null. Typography, spacing, dividers, examples, and photo sizing therefore
/// stay identical in both places.
class ReadingCardBackContent extends StatelessWidget {
  static const double contentFontSize = 16;
  static const double contentLineHeight = 1.16;
  static const int maxVisibleExamples = 1;

  // Fallback for the editor or any other unbounded preview. Reading study cards
  // normally provide a finite height through ReadingCardFrame.
  static const double _defaultInnerHeight = 554;
  static const double _outerVerticalInset = 14;
  static const double _sectionGap = 8;
  static const double _regionVerticalPadding = 8;
  static const double _regionHorizontalPadding = 8;
  static const double _photoBaseWidth = 188;
  static const double _photoBaseHeight = 132;
  static const double _photoMaxScale = 1.55;
  static const double _photoSpareGrowthFraction = 0.45;
  static const double _photoMaxSpareGrowth = 28;

  static const double _readingMaxFontSize = 20;
  static const double _readingMinFontSize = 15;
  static const double _glossMaxFontSize = 16;
  static const double _glossMinFontSize = 12;
  static const double _noteMaxFontSize = 16;
  static const double _noteMinFontSize = 11.5;
  static const double _exampleJapaneseMaxFontSize = 17;
  static const double _exampleEnglishMaxFontSize = 14;
  static const double _exampleMinimumScale = 0.78;
  static const double _exampleFuriganaFontSize = 9.5;
  static const double _exampleFuriganaGap = 1.0;
  static const double _exampleFuriganaRunSpacing = 2.0;
  static const double _exampleFuriganaWrapWidthFactor = 0.88;
  static const double _exampleGap = 6;
  static const double _glossItemGap = 7;

  final List<String> glosses;
  final String note;
  final List<DictionaryExample> examples;
  final String? photoPath;
  final double photoScale;
  final double photoOffsetX;
  final double photoOffsetY;
  final String readingText;
  final bool showReadingOnBack;
  final bool showExampleFurigana;
  final Color? textColor;
  final Color? glossColor;
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
    this.photoScale = 1.0,
    this.photoOffsetX = 0.0,
    this.photoOffsetY = 0.0,
    this.readingText = '',
    this.showReadingOnBack = false,
    this.showExampleFurigana = true,
    this.textColor,
    this.glossColor,
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
    final cleanedNote = note.trim();
    final cleanedReading = readingText.trim();
    final hasNote = cleanedNote.isNotEmpty;
    final hasExamples = examples.isNotEmpty;
    final hasPhoto = _hasPhoto;
    final showReading = showReadingOnBack && cleanedReading.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : _defaultInnerHeight;
        final innerWidth = (constraints.maxWidth - 8)
            .clamp(0.0, double.infinity)
            .toDouble();
        final textWidth = (innerWidth - (_regionHorizontalPadding * 2))
            .clamp(0.0, double.infinity)
            .toDouble();

        final sections = <_ReadingSectionSpec>[];

        if (showReading) {
          sections.add(
            _ReadingSectionSpec(
              kind: _ReadingSection.reading,
              desiredHeight: _singleTextHeight(
                    context: context,
                    text: cleanedReading,
                    width: textWidth,
                    fontSize: _readingMaxFontSize,
                    lineHeight: 1,
                    fontWeight: FontWeight.w600,
                  ) +
                  _regionVerticalPadding,
              minimumHeight: _singleTextHeight(
                    context: context,
                    text: cleanedReading,
                    width: textWidth,
                    fontSize: _readingMinFontSize,
                    lineHeight: 1,
                    fontWeight: FontWeight.w600,
                  ) +
                  _regionVerticalPadding,
            ),
          );
        }

        sections.add(
          _ReadingSectionSpec(
            kind: _ReadingSection.glosses,
            desiredHeight: _glossesHeight(
                  context: context,
                  width: textWidth,
                  fontSize: _glossMaxFontSize,
                ) +
                _regionVerticalPadding,
            minimumHeight: _glossesHeight(
                  context: context,
                  width: textWidth,
                  fontSize: _glossMinFontSize,
                ) +
                _regionVerticalPadding,
          ),
        );

        if (hasNote) {
          sections.add(
            _ReadingSectionSpec(
              kind: _ReadingSection.note,
              desiredHeight: _singleTextHeight(
                    context: context,
                    text: cleanedNote,
                    width: textWidth,
                    fontSize: _noteMaxFontSize,
                    lineHeight: contentLineHeight,
                    fontWeight: FontWeight.w600,
                  ) +
                  _regionVerticalPadding,
              minimumHeight: _singleTextHeight(
                    context: context,
                    text: cleanedNote,
                    width: textWidth,
                    fontSize: _noteMinFontSize,
                    lineHeight: contentLineHeight,
                    fontWeight: FontWeight.w600,
                  ) +
                  _regionVerticalPadding,
            ),
          );
        }

        if (hasExamples) {
          sections.add(
            _ReadingSectionSpec(
              kind: _ReadingSection.example,
              desiredHeight: _exampleHeight(
                    context: context,
                    width: textWidth,
                    scale: 1,
                  ) +
                  _regionVerticalPadding,
              minimumHeight: _exampleHeight(
                    context: context,
                    width: textWidth,
                    scale: _exampleMinimumScale,
                  ) +
                  _regionVerticalPadding,
            ),
          );
        }

        final visibleFieldCount = sections.length + (hasPhoto ? 1 : 0);
        final totalGapHeight = visibleFieldCount <= 1
            ? 0.0
            : _sectionGap * (visibleFieldCount - 1);
        final usableHeight = (availableHeight - (_outerVerticalInset * 2))
            .clamp(0.0, double.infinity)
            .toDouble();
        final fieldBudget = (usableHeight - totalGapHeight)
            .clamp(0.0, double.infinity)
            .toDouble();

        final desiredTextHeight = sections.fold<double>(
          0,
          (sum, section) => sum + section.desiredHeight,
        );
        final minimumTextHeight = sections.fold<double>(
          0,
          (sum, section) => sum + section.minimumHeight,
        );

        // Build the card as a centered content cluster instead of pinning every
        // active field to the top. Sparse cards therefore stay near the middle,
        // while fuller cards naturally expand outward until they reach the
        // same safe vertical bounds as a maximum-content card.
        var targetPhotoHeight = hasPhoto
            ? _preferredPhotoHeight(
                availableWidth: innerWidth,
                hasNote: hasNote,
                hasExamples: hasExamples,
                showReading: showReading,
              )
            : 0.0;

        if (hasPhoto) {
          // If all text already fits at its preferred size, use part of the
          // genuinely spare room to grow the photo a little. Keep a hard cap
          // so sparse cards still read as study cards rather than photo cards.
          final spareAtPreferred =
              fieldBudget - desiredTextHeight - targetPhotoHeight;
          if (spareAtPreferred > 0) {
            final growth = (spareAtPreferred * _photoSpareGrowthFraction)
                .clamp(0.0, _photoMaxSpareGrowth)
                .toDouble();
            targetPhotoHeight = (targetPhotoHeight + growth)
                .clamp(
                  0.0,
                  _maximumPhotoHeight(availableWidth: innerWidth),
                )
                .toDouble();
          }

          // Text still has first claim on the height it needs at its measured
          // minimum. If the card is unusually dense, the photo yields before
          // any text region is forced below that minimum allocation.
          final maximumPhotoWithMinimumText =
              (fieldBudget - minimumTextHeight)
                  .clamp(0.0, fieldBudget)
                  .toDouble();
          targetPhotoHeight = targetPhotoHeight
              .clamp(0.0, maximumPhotoWithMinimumText)
              .toDouble();
        }

        final textBudget = (fieldBudget - targetPhotoHeight)
            .clamp(0.0, double.infinity)
            .toDouble();
        final sectionHeights = _allocateSectionHeights(
          sections: sections,
          budget: textBudget,
        );
        final usedTextHeight = sectionHeights.values.fold<double>(
          0,
          (sum, height) => sum + height,
        );
        final remainingForPhoto = (fieldBudget - usedTextHeight)
            .clamp(0.0, double.infinity)
            .toDouble();
        final photoHeight = hasPhoto
            ? targetPhotoHeight.clamp(0.0, remainingForPhoto).toDouble()
            : 0.0;
        final groupHeight = (usedTextHeight +
                photoHeight +
                totalGapHeight)
            .clamp(0.0, usableHeight)
            .toDouble();

        final children = <Widget>[];

        void addGapIfNeeded() {
          if (children.isNotEmpty) {
            children.add(const SizedBox(height: _sectionGap));
          }
        }

        if (showReading) {
          addGapIfNeeded();
          children.add(
            _textRegion(
              height: sectionHeights[_ReadingSection.reading] ?? 0,
              child: _AutoFitSingleText(
                text: cleanedReading,
                maxFontSize: _readingMaxFontSize,
                minFontSize: 8,
                lineHeight: 1,
                fontWeight: FontWeight.w600,
                color: textColor ?? GakujiColors.mediumGray,
              ),
            ),
          );
        }

        addGapIfNeeded();
        children.add(
          _textRegion(
            height: sectionHeights[_ReadingSection.glosses] ?? 0,
            onTap: onGlossTap,
            child: _ReadingCardGlosses(
              glosses: glosses,
              color: textColor ?? glossColor ?? GakujiColors.darkGray,
              maxFontSize: _glossMaxFontSize,
            ),
          ),
        );

        if (hasNote) {
          addGapIfNeeded();
          children.add(
            _textRegion(
              height: sectionHeights[_ReadingSection.note] ?? 0,
              onTap: onNoteTap,
              child: _AutoFitSingleText(
                text: cleanedNote,
                maxFontSize: _noteMaxFontSize,
                minFontSize: 8,
                lineHeight: contentLineHeight,
                fontWeight: FontWeight.w600,
                color: textColor ?? GakujiColors.mediumGray,
              ),
            ),
          );
        }

        if (hasExamples) {
          addGapIfNeeded();
          children.add(
            _textRegion(
              height: sectionHeights[_ReadingSection.example] ?? 0,
              onTap: onExamplesTap,
              child: _ReadingCardExamples(
                examples: examples,
                textColor: textColor,
                showFurigana: showExampleFurigana,
              ),
            ),
          );
        }

        if (hasPhoto) {
          addGapIfNeeded();
          children.add(
            SizedBox(
              height: photoHeight,
              child: _photoRegion(
                path: photoPath!.trim(),
                height: photoHeight,
              ),
            ),
          );
        }

        return SizedBox(
          height: availableHeight,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: _outerVerticalInset,
            ),
            child: Align(
              alignment: Alignment.center,
              child: SizedBox(
                height: groupHeight,
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Map<_ReadingSection, double> _allocateSectionHeights({
    required List<_ReadingSectionSpec> sections,
    required double budget,
  }) {
    if (sections.isEmpty || budget <= 0) return const {};

    final desiredTotal = sections.fold<double>(
      0,
      (sum, section) => sum + section.desiredHeight,
    );

    if (budget >= desiredTotal) {
      return {
        for (final section in sections)
          section.kind: section.desiredHeight,
      };
    }

    final minimumTotal = sections.fold<double>(
      0,
      (sum, section) => sum + section.minimumHeight,
    );

    if (budget <= minimumTotal) {
      final scale = minimumTotal <= 0 ? 0.0 : budget / minimumTotal;
      return {
        for (final section in sections)
          section.kind: section.minimumHeight * scale,
      };
    }

    final extraBudget = budget - minimumTotal;
    final totalDeficit = sections.fold<double>(
      0,
      (sum, section) =>
          sum + (section.desiredHeight - section.minimumHeight),
    );

    return {
      for (final section in sections)
        section.kind: section.minimumHeight +
            (totalDeficit <= 0
                ? 0
                : extraBudget *
                    ((section.desiredHeight - section.minimumHeight) /
                        totalDeficit)),
    };
  }

  double _singleTextHeight({
    required BuildContext context,
    required String text,
    required double width,
    required double fontSize,
    required double lineHeight,
    required FontWeight fontWeight,
    double letterSpacing = 0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          height: lineHeight,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: width);

    return painter.height;
  }

  double _glossesHeight({
    required BuildContext context,
    required double width,
    required double fontSize,
  }) {
    final visibleGlosses = glosses.isEmpty
        ? const ['No glosses selected']
        : glosses;
    var height = 0.0;

    for (var index = 0; index < visibleGlosses.length; index++) {
      final label = visibleGlosses.length == 1
          ? ''
          : '${String.fromCharCode(65 + index)}. ';
      height += _singleTextHeight(
        context: context,
        text: '$label${visibleGlosses[index]}',
        width: width,
        fontSize: fontSize,
        lineHeight: contentLineHeight,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.35,
      );

      if (index != visibleGlosses.length - 1) {
        height += _glossItemGap;
      }
    }

    return height;
  }

  double _exampleHeight({
    required BuildContext context,
    required double width,
    required double scale,
  }) {
    final visibleExamples = examples.take(maxVisibleExamples).toList();
    if (visibleExamples.isEmpty) return 0;

    final example = visibleExamples.first;
    final japanese = example.japanese.trim();
    final english = example.english.trim();
    var height = 0.0;

    if (japanese.isNotEmpty) {
      final reserveFurigana =
          showExampleFurigana && _exampleHasPotentialFurigana(example);
      final japaneseMeasureWidth = reserveFurigana
          ? width * _exampleFuriganaWrapWidthFactor
          : width;
      final japaneseHeight = _singleTextHeight(
        context: context,
        text: japanese,
        width: japaneseMeasureWidth,
        fontSize: _exampleJapaneseMaxFontSize * scale,
        lineHeight: contentLineHeight,
        fontWeight: FontWeight.w800,
      );
      height += japaneseHeight;

      if (reserveFurigana) {
        final japaneseLineHeight =
            _exampleJapaneseMaxFontSize * scale * contentLineHeight;
        final estimatedLineCount =
            (japaneseHeight / japaneseLineHeight).ceil();
        height += estimatedLineCount.toDouble() *
            ((_exampleFuriganaFontSize * scale) +
                _exampleFuriganaGap +
                _exampleFuriganaRunSpacing);
      }
    }

    if (japanese.isNotEmpty && english.isNotEmpty) {
      height += _exampleGap;
    }

    if (english.isNotEmpty) {
      height += _singleTextHeight(
        context: context,
        text: english,
        width: width,
        fontSize: _exampleEnglishMaxFontSize * scale,
        lineHeight: contentLineHeight,
        fontWeight: FontWeight.w600,
      );
    }

    return height;
  }

  bool _exampleHasPotentialFurigana(DictionaryExample example) {
    if (example.reading.trim().isNotEmpty) {
      return true;
    }

    return example.tokens.any((token) {
      if (token.reading.trim().isNotEmpty) {
        return true;
      }

      if (!token.canOpenDictionary) {
        return false;
      }

      return RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々]')
          .hasMatch(token.displayText);
    });
  }

  Widget _textRegion({
    required double height,
    required Widget child,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: height,
      child: _layoutGuideBox(
        child: _sectionTapTarget(
          onTap: onTap,
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _regionHorizontalPadding,
                vertical: _regionVerticalPadding / 2,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  double _preferredPhotoHeight({
    required double availableWidth,
    required bool hasNote,
    required bool hasExamples,
    required bool showReading,
  }) {
    var scale = 1.0;
    if (!hasNote) scale += 0.18;
    if (!hasExamples) scale += 0.25;
    if (!showReading) scale += 0.07;
    scale = scale.clamp(1.0, _photoMaxScale).toDouble();

    const aspectRatio = _photoBaseWidth / _photoBaseHeight;
    final maxWidth = availableWidth * 0.88;
    final width = (_photoBaseWidth * scale)
        .clamp(0.0, maxWidth)
        .toDouble();
    return width / aspectRatio;
  }

  double _maximumPhotoHeight({required double availableWidth}) {
    const aspectRatio = _photoBaseWidth / _photoBaseHeight;
    final width = (_photoBaseWidth * _photoMaxScale)
        .clamp(0.0, availableWidth * 0.90)
        .toDouble();
    return width / aspectRatio;
  }

  Widget _photoRegion({
    required String path,
    required double height,
  }) {
    const aspectRatio = _photoBaseWidth / _photoBaseHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final actualHeight = height
            .clamp(0.0, constraints.maxHeight)
            .toDouble();
        var width = actualHeight * aspectRatio;
        final maxWidth = constraints.maxWidth * 0.90;

        var resolvedHeight = actualHeight;
        if (width > maxWidth) {
          width = maxWidth;
          resolvedHeight = width / aspectRatio;
        }

        return Center(
          child: SizedBox(
            width: width,
            height: resolvedHeight,
            child: _layoutGuideBox(
              fullWidth: false,
              child: _sectionTapTarget(
                onTap: onPhotoTap,
                child: _ReadingCardPhoto(
                  path: path,
                  width: width,
                  height: resolvedHeight,
                  scale: photoScale,
                  offsetX: photoOffsetX,
                  offsetY: photoOffsetY,
                  textColor: textColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _layoutGuideBox({
    required Widget child,
    bool fullWidth = true,
  }) {
    if (!fullWidth) return child;

    return SizedBox.expand(child: child);
  }

  Widget _sectionTapTarget({
    required Widget child,
    VoidCallback? onTap,
  }) {
    if (onTap == null) return child;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: GakujiColors.deckBlue.withValues(alpha: 0.08),
        highlightColor: GakujiColors.deckBlue.withValues(alpha: 0.04),
        child: child,
      ),
    );
  }
}

enum _ReadingSection {
  reading,
  glosses,
  note,
  example,
}

class _ReadingSectionSpec {
  final _ReadingSection kind;
  final double desiredHeight;
  final double minimumHeight;

  const _ReadingSectionSpec({
    required this.kind,
    required this.desiredHeight,
    required this.minimumHeight,
  });
}

class _AutoFitSingleText extends StatelessWidget {
  final String text;
  final double maxFontSize;
  final double minFontSize;
  final double lineHeight;
  final FontWeight fontWeight;
  final Color color;
  final double letterSpacing;

  const _AutoFitSingleText({
    required this.text,
    required this.maxFontSize,
    required this.minFontSize,
    required this.lineHeight,
    required this.fontWeight,
    required this.color,
    this.letterSpacing = 0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Render at the preferred/max size first, then let FittedBox scale the
        // whole text block down only when this region is smaller than the text
        // needs. This makes the region boundary absolute: text can never push
        // into the next card field.
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Text(
                text,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                softWrap: true,
                style: TextStyle(
                  fontSize: maxFontSize,
                  height: lineHeight,
                  fontWeight: fontWeight,
                  letterSpacing: letterSpacing,
                  color: color,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReadingCardGlosses extends StatelessWidget {
  final List<String> glosses;
  final Color color;
  final double maxFontSize;

  const _ReadingCardGlosses({
    required this.glosses,
    required this.color,
    required this.maxFontSize,
  });

  @override
  Widget build(BuildContext context) {
    final visibleGlosses = glosses.isEmpty
        ? const ['No glosses selected']
        : glosses;

    return LayoutBuilder(
      builder: (context, constraints) {
        final glossColumn = SizedBox(
          width: constraints.maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: visibleGlosses.asMap().entries.map((entry) {
              final label = visibleGlosses.length == 1
                  ? ''
                  : '${String.fromCharCode(65 + entry.key)}. ';

              return Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == visibleGlosses.length - 1
                      ? 0
                      : ReadingCardBackContent._glossItemGap,
                ),
                child: Text(
                  '$label${entry.value}',
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: maxFontSize,
                    height: ReadingCardBackContent.contentLineHeight,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                    color: color,
                  ),
                ),
              );
            }).toList(),
          ),
        );

        return ClipRect(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: glossColumn,
          ),
        );
      },
    );
  }
}

class _ReadingCardExamples extends StatelessWidget {
  final List<DictionaryExample> examples;
  final Color? textColor;
  final bool showFurigana;

  const _ReadingCardExamples({
    required this.examples,
    this.textColor,
    this.showFurigana = true,
  });

  @override
  Widget build(BuildContext context) {
    final visibleExamples = examples
        .take(ReadingCardBackContent.maxVisibleExamples)
        .toList();

    if (visibleExamples.isEmpty) return const SizedBox.shrink();

    final example = visibleExamples.first;
    final japanese = example.japanese.trim();
    final english = example.english.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Japanese and English keep distinct preferred sizes. The complete
        // example block is then uniformly scaled down only if the region is
        // too short, preserving the Japanese > English visual hierarchy while
        // guaranteeing that neither line can escape the example box.
        final exampleColumn = SizedBox(
          width: constraints.maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (japanese.isNotEmpty)
                GakujiFuriganaSentence(
                  example: example,
                  alignment: WrapAlignment.center,
                  runSpacing:
                      ReadingCardBackContent._exampleFuriganaRunSpacing,
                  furiganaGap:
                      ReadingCardBackContent._exampleFuriganaGap,
                  showFurigana: showFurigana,
                  emptyLineSpacingFactor: 0.5,
                  textStyle: TextStyle(
                    fontSize:
                        ReadingCardBackContent._exampleJapaneseMaxFontSize,
                    height: ReadingCardBackContent.contentLineHeight,
                    fontWeight: FontWeight.w800,
                    color: textColor ?? GakujiColors.darkGray,
                  ),
                  furiganaStyle: TextStyle(
                    fontSize:
                        ReadingCardBackContent._exampleFuriganaFontSize,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: textColor ?? GakujiColors.mediumGray,
                  ),
                ),
              if (japanese.isNotEmpty && english.isNotEmpty)
                const SizedBox(
                  height: ReadingCardBackContent._exampleGap,
                ),
              if (english.isNotEmpty)
                Text(
                  english,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  softWrap: true,
                  style: TextStyle(
                    fontSize:
                        ReadingCardBackContent._exampleEnglishMaxFontSize,
                    height: ReadingCardBackContent.contentLineHeight,
                    fontWeight: FontWeight.w600,
                    color: textColor ?? GakujiColors.mediumGray,
                  ),
                ),
            ],
          ),
        );

        return ClipRect(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: exampleColumn,
          ),
        );
      },
    );
  }
}

class _ReadingCardPhoto extends StatelessWidget {
  final String path;
  final double width;
  final double height;
  final double scale;
  final double offsetX;
  final double offsetY;
  final Color? textColor;

  const _ReadingCardPhoto({
    required this.path,
    required this.width,
    required this.height,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return ReadingCardPhotoView(
      path: path,
      width: width,
      height: height,
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY,
      borderRadius: 16,
      errorTextColor: textColor,
    );
  }
}

/// Shared reading-card photo viewport.
///
/// The source image starts at the default cover size. [scale] can zoom slightly
/// outward to reveal more of the original or zoom inward for a tighter crop,
/// while [offsetX]
/// and [offsetY] store a normalized position within the remaining pan range.
/// This lets the editor save a crop that reproduces consistently even when the
/// card is rendered at a different physical size.
class ReadingCardPhotoView extends StatefulWidget {
  final String path;
  final double width;
  final double height;
  final double scale;
  final double offsetX;
  final double offsetY;
  final double borderRadius;
  final bool interactive;
  final Color? errorTextColor;
  final void Function(double scale, double offsetX, double offsetY)?
      onTransformChanged;

  const ReadingCardPhotoView({
    super.key,
    required this.path,
    required this.width,
    required this.height,
    this.scale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.borderRadius = 16,
    this.interactive = false,
    this.errorTextColor,
    this.onTransformChanged,
  });

  @override
  State<ReadingCardPhotoView> createState() => _ReadingCardPhotoViewState();
}

class _ReadingCardPhotoViewState extends State<ReadingCardPhotoView> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  double? _sourceAspectRatio;

  double _gestureBaseScale = 1.0;
  double _gestureScale = 1.0;
  double _gestureOffsetX = 0.0;
  double _gestureOffsetY = 0.0;
  Offset _lastFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant ReadingCardPhotoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _removeImageListener();
      _sourceAspectRatio = null;
      _resolveImage();
    }
  }

  void _resolveImage() {
    final provider = FileImage(File(widget.path));
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (info, synchronousCall) {
        if (!mounted) return;
        final width = info.image.width.toDouble();
        final height = info.image.height.toDouble();
        if (width <= 0 || height <= 0) return;

        setState(() {
          _sourceAspectRatio = width / height;
        });
      },
      onError: (error, stackTrace) {
        if (!mounted) return;
        setState(() {
          _sourceAspectRatio = null;
        });
      },
    );

    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  void _removeImageListener() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageListener = null;
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  _PhotoGeometry _geometryFor(double scale) {
    final sourceAspect = _sourceAspectRatio;
    final viewportAspect = widget.width / widget.height;
    final safeScale = scale.clamp(0.75, 3.0).toDouble();

    if (sourceAspect == null || sourceAspect <= 0) {
      return _PhotoGeometry(
        renderedWidth: widget.width * safeScale,
        renderedHeight: widget.height * safeScale,
        maxPanX: widget.width * (safeScale - 1) / 2,
        maxPanY: widget.height * (safeScale - 1) / 2,
      );
    }

    final baseWidth = sourceAspect >= viewportAspect
        ? widget.height * sourceAspect
        : widget.width;
    final baseHeight = sourceAspect >= viewportAspect
        ? widget.height
        : widget.width / sourceAspect;
    final renderedWidth = baseWidth * safeScale;
    final renderedHeight = baseHeight * safeScale;

    return _PhotoGeometry(
      renderedWidth: renderedWidth,
      renderedHeight: renderedHeight,
      maxPanX: ((renderedWidth - widget.width) / 2)
          .clamp(0.0, double.infinity)
          .toDouble(),
      maxPanY: ((renderedHeight - widget.height) / 2)
          .clamp(0.0, double.infinity)
          .toDouble(),
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _gestureBaseScale = widget.scale.clamp(0.75, 3.0).toDouble();
    _gestureScale = _gestureBaseScale;
    _gestureOffsetX = widget.offsetX.clamp(-1.0, 1.0).toDouble();
    _gestureOffsetY = widget.offsetY.clamp(-1.0, 1.0).toDouble();
    _lastFocalPoint = details.localFocalPoint;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final nextScale = (_gestureBaseScale * details.scale)
        .clamp(0.75, 3.0)
        .toDouble();
    final previousGeometry = _geometryFor(_gestureScale);
    final nextGeometry = _geometryFor(nextScale);
    final focalDelta = details.localFocalPoint - _lastFocalPoint;

    final currentX = (_gestureOffsetX * previousGeometry.maxPanX) +
        focalDelta.dx;
    final currentY = (_gestureOffsetY * previousGeometry.maxPanY) +
        focalDelta.dy;

    final nextOffsetX = nextGeometry.maxPanX <= 0
        ? 0.0
        : (currentX / nextGeometry.maxPanX)
            .clamp(-1.0, 1.0)
            .toDouble();
    final nextOffsetY = nextGeometry.maxPanY <= 0
        ? 0.0
        : (currentY / nextGeometry.maxPanY)
            .clamp(-1.0, 1.0)
            .toDouble();

    _gestureScale = nextScale;
    _gestureOffsetX = nextOffsetX;
    _gestureOffsetY = nextOffsetY;
    _lastFocalPoint = details.localFocalPoint;

    widget.onTransformChanged?.call(
      nextScale,
      nextOffsetX,
      nextOffsetY,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_sourceAspectRatio == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Image.file(
          File(widget.path),
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _photoErrorFallback(context);
          },
        ),
      );
    }

    final geometry = _geometryFor(widget.scale);
    final safeOffsetX = widget.offsetX.clamp(-1.0, 1.0).toDouble();
    final safeOffsetY = widget.offsetY.clamp(-1.0, 1.0).toDouble();
    final translation = Offset(
      safeOffsetX * geometry.maxPanX,
      safeOffsetY * geometry.maxPanY,
    );

    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: ColoredBox(
          color: GakujiColors.warmCard,
          child: OverflowBox(
            alignment: Alignment.center,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: translation,
              child: SizedBox(
                width: geometry.renderedWidth,
                height: geometry.renderedHeight,
                child: Image.file(
                  File(widget.path),
                  width: geometry.renderedWidth,
                  height: geometry.renderedHeight,
                  fit: BoxFit.fill,
                  errorBuilder: (context, error, stackTrace) {
                    return _photoErrorFallback(context);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!widget.interactive) return photo;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      child: photo,
    );
  }

  Widget _photoErrorFallback(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(widget.borderRadius),
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
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: widget.errorTextColor ?? GakujiColors.mediumGray,
        ),
      ),
    );
  }
}

class _PhotoGeometry {
  final double renderedWidth;
  final double renderedHeight;
  final double maxPanX;
  final double maxPanY;

  const _PhotoGeometry({
    required this.renderedWidth,
    required this.renderedHeight,
    required this.maxPanX,
    required this.maxPanY,
  });
}

