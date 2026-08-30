import 'dart:async';

import 'package:flutter/material.dart';

import 'package:gakuji/domain/term.dart';
import 'package:gakuji/data/dictionary/dictionary_service.dart';

/// Renders a dictionary example sentence with compact furigana above tokens
/// that contain kanji.
///
/// Token readings from the example corpus are used when available. When a
/// token points to a dictionary term, the dictionary reading is used as the
/// preferred base reading so example lists, flash cards, and sentence detail
/// pages all resolve furigana the same way.
class GakujiFuriganaSentence extends StatefulWidget {
  final DictionaryExample example;
  final TextStyle textStyle;
  final TextStyle furiganaStyle;
  final WrapAlignment alignment;
  final double runSpacing;
  final double furiganaGap;
  final double emptyLineSpacingFactor;
  final bool showFurigana;

  /// Terms already resolved by a parent screen. Sentence detail passes its
  /// existing term map here so the shared renderer does not perform duplicate
  /// dictionary lookups.
  final Map<String, Term> resolvedTermsById;

  /// When true, unresolved token term IDs are looked up automatically.
  /// Example rows and flash cards use this default behavior.
  final bool resolveMissingTerms;

  const GakujiFuriganaSentence({
    super.key,
    required this.example,
    required this.textStyle,
    required this.furiganaStyle,
    this.alignment = WrapAlignment.start,
    this.runSpacing = 4,
    this.furiganaGap = 1.5,
    this.emptyLineSpacingFactor = 1.0,
    this.showFurigana = true,
    this.resolvedTermsById = const <String, Term>{},
    this.resolveMissingTerms = true,
  });

  @override
  State<GakujiFuriganaSentence> createState() =>
      _GakujiFuriganaSentenceState();
}

class _GakujiFuriganaSentenceState extends State<GakujiFuriganaSentence> {
  final Map<String, Term> _resolvedTermsById = <String, Term>{};
  final Set<String> _failedTermIds = <String>{};
  int _lookupRequestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMissingTerms());
  }

  @override
  void didUpdateWidget(covariant GakujiFuriganaSentence oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.example != widget.example ||
        oldWidget.resolveMissingTerms != widget.resolveMissingTerms) {
      _failedTermIds.clear();
      unawaited(_loadMissingTerms());
    }
  }

  Future<void> _loadMissingTerms() async {
    if (!widget.resolveMissingTerms) {
      return;
    }

    final termIds = <String>[];
    final seenTermIds = <String>{};

    for (final token in widget.example.tokens) {
      final termId = token.termId?.trim() ?? '';

      if (termId.isEmpty ||
          !seenTermIds.add(termId) ||
          widget.resolvedTermsById.containsKey(termId) ||
          _resolvedTermsById.containsKey(termId) ||
          _failedTermIds.contains(termId)) {
        continue;
      }

      termIds.add(termId);
    }

    if (termIds.isEmpty) {
      return;
    }

    final requestId = ++_lookupRequestId;
    final loadedTerms = <String, Term>{};
    final failedTermIds = <String>{};

    for (final termId in termIds) {
      try {
        loadedTerms[termId] = await DictionaryService.getTermByIdAsync(termId);
      } catch (_) {
        failedTermIds.add(termId);
      }
    }

    if (!mounted || requestId != _lookupRequestId) {
      return;
    }

    setState(() {
      _resolvedTermsById.addAll(loadedTerms);
      _failedTermIds.addAll(failedTermIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final japanese = widget.example.japanese.trim();

    if (japanese.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!widget.showFurigana) {
      return Text(
        japanese,
        textAlign: _textAlignFor(widget.alignment),
        textScaler: TextScaler.noScaling,
        softWrap: true,
        style: widget.textStyle,
      );
    }

    final segments = _buildSegments(widget.example);
    final hasTokenFurigana = segments.any(
      (segment) => _readingForToken(segment.token).isNotEmpty,
    );

    if (!hasTokenFurigana) {
      return _fallbackSentence(japanese);
    }

    final furiganaHeight =
        (widget.furiganaStyle.fontSize ?? 10) *
        (widget.furiganaStyle.height ?? 1);

    final emptyLineSpacingFactor =
        widget.emptyLineSpacingFactor.clamp(0.0, 1.0).toDouble();

    if (emptyLineSpacingFactor < 1.0) {
      return _lineAwareSentence(
        context: context,
        segments: segments,
        furiganaHeight: furiganaHeight,
        emptyLineSpacingFactor: emptyLineSpacingFactor,
      );
    }

    return Wrap(
      spacing: 0,
      runSpacing: widget.runSpacing,
      alignment: widget.alignment,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: segments.map((segment) {
        final reading = _readingForToken(segment.token);

        return _segmentColumn(
          segment: segment,
          reading: reading,
          furiganaHeight: furiganaHeight,
        );
      }).toList(growable: false),
    );
  }

  Widget _lineAwareSentence({
    required BuildContext context,
    required List<_SentenceSegment> segments,
    required double furiganaHeight,
    required double emptyLineSpacingFactor,
  }) {
    final textDirection = Directionality.of(context);
    final measuredSegments = segments.map((segment) {
      final reading = _readingForToken(segment.token);
      final textWidth = _singleLineTextWidth(
        text: segment.text,
        style: widget.textStyle,
        textDirection: textDirection,
      );
      return _MeasuredSentenceSegment(
        segment: segment,
        reading: reading,
        // Japanese text controls horizontal flow. Furigana is allowed to
        // overhang its token like normal ruby text instead of widening the
        // token and creating large gaps between words. Keep a tiny allowance
        // so the measured Row still has room for fractional glyph metrics.
        width: textWidth + 0.5,
      );
    }).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        // Leave a few logical pixels of breathing room for fractional glyph
        // metrics. TextPainter widths can land just under the width Flutter
        // ultimately gives the rendered Row on a physical device, which can
        // otherwise produce a tiny RenderFlex overflow at the right edge.
        final wrapWidth = maxWidth.isFinite && maxWidth > 4.0
            ? maxWidth - 4.0
            : maxWidth;
        final lines = <List<_MeasuredSentenceSegment>>[];
        var currentLine = <_MeasuredSentenceSegment>[];
        var currentWidth = 0.0;

        for (final segment in measuredSegments) {
          final wouldOverflow = currentLine.isNotEmpty &&
              currentWidth + segment.width > wrapWidth;

          if (wouldOverflow) {
            lines.add(currentLine);
            currentLine = <_MeasuredSentenceSegment>[];
            currentWidth = 0.0;
          }

          currentLine.add(segment);
          currentWidth += segment.width;
        }

        if (currentLine.isNotEmpty) {
          lines.add(currentLine);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) ...[
              if (lineIndex > 0)
                SizedBox(
                  height: _lineHasFurigana(lines[lineIndex])
                      ? widget.runSpacing
                      : widget.runSpacing * emptyLineSpacingFactor * 0.5,
                ),
              _furiganaLine(
                line: lines[lineIndex],
                furiganaHeight: furiganaHeight,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _furiganaLine({
    required List<_MeasuredSentenceSegment> line,
    required double furiganaHeight,
  }) {
    final hasFurigana = _lineHasFurigana(line);
    final reservedFuriganaHeight = hasFurigana ? furiganaHeight : 0.0;
    final lineTextStyle = hasFurigana
        ? widget.textStyle
        : widget.textStyle.copyWith(height: 1.0);

    return Row(
      mainAxisAlignment: _mainAxisAlignmentFor(widget.alignment),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: line.map((item) {
        return SizedBox(
          width: item.width,
          child: _segmentColumn(
            segment: item.segment,
            reading: item.reading,
            furiganaHeight: reservedFuriganaHeight,
            textStyle: lineTextStyle,
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _segmentColumn({
    required _SentenceSegment segment,
    required String reading,
    required double furiganaHeight,
    TextStyle? textStyle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (furiganaHeight > 0) ...[
          SizedBox(
            height: furiganaHeight,
            child: reading.isEmpty
                ? null
                : OverflowBox(
                    minWidth: 0,
                    maxWidth: double.infinity,
                    alignment: Alignment.center,
                    child: Text(
                      reading,
                      maxLines: 1,
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: widget.furiganaStyle,
                    ),
                  ),
          ),
          SizedBox(height: widget.furiganaGap),
        ],
        Text(
          segment.text,
          maxLines: 1,
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: textStyle ?? widget.textStyle,
        ),
      ],
    );
  }

  bool _lineHasFurigana(List<_MeasuredSentenceSegment> line) {
    return line.any((segment) => segment.reading.isNotEmpty);
  }

  double _singleLineTextWidth({
    required String text,
    required TextStyle style,
    required TextDirection textDirection,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();

    return painter.width;
  }

  Widget _fallbackSentence(String japanese) {
    final reading = widget.example.reading.trim();

    if (reading.isEmpty || reading == japanese) {
      return Text(
        japanese,
        textAlign: _textAlignFor(widget.alignment),
        textScaler: TextScaler.noScaling,
        softWrap: true,
        style: widget.textStyle,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: _columnAlignmentFor(widget.alignment),
      children: [
        Text(
          reading,
          textAlign: _textAlignFor(widget.alignment),
          textScaler: TextScaler.noScaling,
          softWrap: true,
          style: widget.furiganaStyle,
        ),
        SizedBox(height: widget.furiganaGap),
        Text(
          japanese,
          textAlign: _textAlignFor(widget.alignment),
          textScaler: TextScaler.noScaling,
          softWrap: true,
          style: widget.textStyle,
        ),
      ],
    );
  }

  String _readingForToken(DictionaryExampleToken? token) {
    if (token == null) {
      return '';
    }

    final surface = token.displayText.trim();

    if (surface.isEmpty || !_containsKanji(surface)) {
      return '';
    }

    final termId = token.termId?.trim() ?? '';
    final parentTermReading =
        widget.resolvedTermsById[termId]?.reading.trim() ?? '';
    final loadedTermReading = _resolvedTermsById[termId]?.reading.trim() ?? '';
    final termReading =
        parentTermReading.isNotEmpty ? parentTermReading : loadedTermReading;
    final tokenReading = token.reading.trim();
    final baseReading = termReading.isNotEmpty ? termReading : tokenReading;

    if (baseReading.isEmpty) {
      return '';
    }

    final headword = token.headword.trim();

    if (headword.isEmpty || surface == headword) {
      return baseReading == surface ? '' : baseReading;
    }

    // 来る has irregular stem readings, so a simple suffix replacement can
    // produce incorrect readings such as くた for 来た. Only use a corpus
    // reading when it explicitly differs from the dictionary base reading.
    if (headword == '来る') {
      if (tokenReading.isNotEmpty && tokenReading != termReading) {
        return tokenReading;
      }

      return '';
    }

    final inflectedReading = _inflectedReading(
      surface: surface,
      headword: headword,
      baseReading: baseReading,
    );

    return inflectedReading == surface ? '' : inflectedReading;
  }

  static List<_SentenceSegment> _buildSegments(DictionaryExample example) {
    final sentence = example.japanese;

    if (sentence.isEmpty || example.tokens.isEmpty) {
      return [
        _SentenceSegment(text: sentence),
      ];
    }

    final segments = <_SentenceSegment>[];
    var cursor = 0;
    var matchedToken = false;

    for (final token in example.tokens) {
      final surface = token.displayText;

      if (surface.isEmpty) {
        continue;
      }

      final matchIndex = sentence.indexOf(surface, cursor);

      if (matchIndex < 0) {
        continue;
      }

      matchedToken = true;

      if (matchIndex > cursor) {
        _appendRawText(
          segments,
          sentence.substring(cursor, matchIndex),
        );
      }

      segments.add(
        _SentenceSegment(
          text: surface,
          token: token,
        ),
      );

      cursor = matchIndex + surface.length;
    }

    if (!matchedToken) {
      return [
        _SentenceSegment(text: sentence),
      ];
    }

    if (cursor < sentence.length) {
      _appendRawText(
        segments,
        sentence.substring(cursor),
      );
    }

    return segments;
  }

  static void _appendRawText(
    List<_SentenceSegment> segments,
    String text,
  ) {
    if (text.isEmpty) {
      return;
    }

    if (_isPunctuation(text) && segments.isNotEmpty) {
      final previous = segments.removeLast();
      segments.add(
        _SentenceSegment(
          text: '${previous.text}$text',
          token: previous.token,
        ),
      );
      return;
    }

    segments.add(_SentenceSegment(text: text));
  }

  static String _inflectedReading({
    required String surface,
    required String headword,
    required String baseReading,
  }) {
    var commonPrefixLength = 0;
    final maxPrefixLength =
        surface.length < headword.length ? surface.length : headword.length;

    while (commonPrefixLength < maxPrefixLength &&
        surface[commonPrefixLength] == headword[commonPrefixLength]) {
      commonPrefixLength += 1;
    }

    final headwordSuffix = headword.substring(commonPrefixLength);
    final surfaceSuffix = surface.substring(commonPrefixLength);

    if (headwordSuffix.isEmpty ||
        !_isKanaOnly(headwordSuffix) ||
        !baseReading.endsWith(headwordSuffix)) {
      return '';
    }

    final readingStem = baseReading.substring(
      0,
      baseReading.length - headwordSuffix.length,
    );

    return '$readingStem$surfaceSuffix';
  }

  static bool _containsKanji(String text) {
    return RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々]')
        .hasMatch(text);
  }

  static bool _isKanaOnly(String value) {
    return RegExp(r'^[\u3040-\u30FFー]+$').hasMatch(value);
  }

  static bool _isPunctuation(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');

    if (compact.isEmpty) {
      return false;
    }

    return RegExp(
      r'^[、。！？!?…‥・「」『』（）()［］\[\]【】〈〉《》〔〕〜～ー—―,.;:]+$',
    ).hasMatch(compact);
  }

  static TextAlign _textAlignFor(WrapAlignment alignment) {
    switch (alignment) {
      case WrapAlignment.center:
        return TextAlign.center;
      case WrapAlignment.end:
        return TextAlign.end;
      default:
        return TextAlign.start;
    }
  }

  static MainAxisAlignment _mainAxisAlignmentFor(WrapAlignment alignment) {
    switch (alignment) {
      case WrapAlignment.center:
        return MainAxisAlignment.center;
      case WrapAlignment.end:
        return MainAxisAlignment.end;
      case WrapAlignment.spaceBetween:
        return MainAxisAlignment.spaceBetween;
      case WrapAlignment.spaceAround:
        return MainAxisAlignment.spaceAround;
      case WrapAlignment.spaceEvenly:
        return MainAxisAlignment.spaceEvenly;
      default:
        return MainAxisAlignment.start;
    }
  }

  static CrossAxisAlignment _columnAlignmentFor(WrapAlignment alignment) {
    switch (alignment) {
      case WrapAlignment.center:
        return CrossAxisAlignment.center;
      case WrapAlignment.end:
        return CrossAxisAlignment.end;
      default:
        return CrossAxisAlignment.start;
    }
  }
}

class _SentenceSegment {
  final String text;
  final DictionaryExampleToken? token;

  const _SentenceSegment({
    required this.text,
    this.token,
  });
}

class _MeasuredSentenceSegment {
  final _SentenceSegment segment;
  final String reading;
  final double width;

  const _MeasuredSentenceSegment({
    required this.segment,
    required this.reading,
    required this.width,
  });
}
