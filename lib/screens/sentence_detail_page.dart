import 'dart:async';

import 'package:flutter/material.dart';

import '../models/term.dart';
import '../services/dictionary_service.dart';
import '../widgets/gakuji_faded_scroll.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_term_row.dart';
import '../widgets/gakuji_top_bar.dart';

typedef SentenceTokenTap = Future<void> Function(
  BuildContext context,
  DictionaryExampleToken token,
);

class SentenceDetailPage extends StatefulWidget {
  final DictionaryExample example;

  /// Kept for compatibility with the dictionary page while the sentence page
  /// no longer displays the source sense label.
  final String senseLabel;

  final SentenceTokenTap onTokenTap;

  const SentenceDetailPage({
    super.key,
    required this.example,
    required this.senseLabel,
    required this.onTokenTap,
  });

  @override
  State<SentenceDetailPage> createState() => _SentenceDetailPageState();
}

class _SentenceDetailPageState extends State<SentenceDetailPage> {
  static const Color accentBlue = GakujiColors.deckBlue;
  static Color get darkText => GakujiColors.darkGray;
  static Color get softTextGray => GakujiColors.mediumGray;
  static Color get dividerColor => GakujiColors.warmDivider;

  final Map<String, Term> _termsById = {};

  int? loadingTokenIndex;
  int _termLoadRequestId = 0;
  bool _termsLoading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadIncludedTerms());
  }

  @override
  void didUpdateWidget(covariant SentenceDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.example.japanese != widget.example.japanese ||
        oldWidget.example.english != widget.example.english) {
      loadingTokenIndex = null;
      unawaited(_loadIncludedTerms());
    }
  }

  Future<void> _loadIncludedTerms() async {
    final requestId = ++_termLoadRequestId;
    final termIds = <String>[];
    final seenTermIds = <String>{};

    for (final token in widget.example.tokens) {
      final termId = token.termId?.trim() ?? '';

      if (termId.isEmpty || !seenTermIds.add(termId)) {
        continue;
      }

      termIds.add(termId);
    }

    if (mounted) {
      setState(() {
        _termsById.clear();
        _termsLoading = termIds.isNotEmpty;
      });
    }

    if (termIds.isEmpty) {
      return;
    }

    final loadedTerms = <String, Term>{};

    for (final termId in termIds) {
      try {
        loadedTerms[termId] = await DictionaryService.getTermByIdAsync(termId);
      } catch (_) {
        // Leave unresolved corpus tokens out of the tappable term list rather
        // than displaying a potentially incorrect dictionary entry.
      }
    }

    if (!mounted || requestId != _termLoadRequestId) {
      return;
    }

    setState(() {
      _termsById
        ..clear()
        ..addAll(loadedTerms);
      _termsLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            GakujiTopBar(
              leftIcon: GakujiTopBar.backIcon,
              leftIconSize: GakujiTopBar.backIconSize,
              leftIconColor: darkText,
              onLeftTap: () => Navigator.of(context).pop(),
              title: '',
              titleStyle:  TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w500,
                color: darkText,
              ),
            ),
            Expanded(
              child: GakujiFadedScroll(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 90),
                  children: [
                    _sentenceSection(),
                    _breakdownSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sentenceSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 27),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _furiganaSentence(),
          const SizedBox(height: 17),
          Container(
            width: 34,
            height: 1.5,
            color: dividerColor,
          ),
          const SizedBox(height: 14),
          Text(
            widget.example.english,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 17.5,
              height: 1.35,
              color: darkText,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _furiganaSentence() {
    final segments = _buildSentenceSegments();

    if (segments.isEmpty) {
      return Text(
        widget.example.japanese,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 25,
          height: 1.38,
          color: darkText,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Wrap(
      spacing: 0,
      runSpacing: 9,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: segments.map(_sentenceSegmentWidget).toList(),
    );
  }

  Widget _sentenceSegmentWidget(_SentenceSegment segment) {
    final token = segment.token;
    final reading = token == null ? '' : _readingForSurfaceToken(token);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 16,
          child: reading.isEmpty
              ? null
              : Text(
                  reading,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1,
                    color: softTextGray,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
        const SizedBox(height: 2),
        Text(
          segment.text,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 25,
            height: 1.12,
            color: darkText,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  List<_SentenceSegment> _buildSentenceSegments() {
    final sentence = widget.example.japanese;

    if (sentence.isEmpty) {
      return const [];
    }

    final segments = <_SentenceSegment>[];
    var cursor = 0;
    var matchedToken = false;

    for (final token in widget.example.tokens) {
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
        _appendRawSentenceText(
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
      _appendRawSentenceText(
        segments,
        sentence.substring(cursor),
      );
    }

    return segments;
  }

  void _appendRawSentenceText(
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

  String _readingForSurfaceToken(DictionaryExampleToken token) {
    final surface = token.displayText.trim();

    if (!_containsKanji(surface)) {
      return '';
    }

    final termId = token.termId?.trim() ?? '';
    final termReading = _termsById[termId]?.reading.trim() ?? '';
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

  String _inflectedReading({
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

  Widget _breakdownSection() {
    final includedTokens = widget.example.tokens
        .asMap()
        .entries
        .where((entry) {
          final termId = entry.value.termId?.trim() ?? '';
          return termId.isNotEmpty && _termsById.containsKey(termId);
        })
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Breakdown'),
        if (_termsLoading)
           Padding(
            padding: EdgeInsets.fromLTRB(22, 18, 22, 20),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: accentBlue,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'Loading terms...',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.2,
                    color: softTextGray,
                  ),
                ),
              ],
            ),
          )
        else if (includedTokens.isEmpty)
           Padding(
            padding: EdgeInsets.fromLTRB(22, 17, 22, 20),
            child: Text(
              'Dictionary terms are not available for this sentence yet.',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.25,
                color: softTextGray,
              ),
            ),
          )
        else
          ...includedTokens.asMap().entries.map((entry) {
            final includedEntry = entry.value;
            final tokenIndex = includedEntry.key;
            final token = includedEntry.value;
            final termId = token.termId!.trim();
            final term = _termsById[termId]!;
            final isLast = entry.key == includedTokens.length - 1;
            final isLoading = loadingTokenIndex == tokenIndex;

            return Column(
              children: [
                GakujiTermRow(
                  term: term,
                  meaningMaxLines: 2,
                  padding: const EdgeInsets.fromLTRB(22, 11, 15, 12),
                  backgroundColor: GakujiColors.warmBackground,
                  trailing: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: accentBlue,
                          ),
                        )
                      : null,
                  onTap: loadingTokenIndex == null
                      ? () => _openToken(tokenIndex, token)
                      : null,
                ),
                if (!isLast)
                   Padding(
                    padding: EdgeInsets.only(left: 22, right: 16),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: GakujiTermRow.dividerColor,
                    ),
                  ),
              ],
            );
          }),
      ],
    );
  }

  bool _containsKanji(String text) {
    return RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々]')
        .hasMatch(text);
  }

  bool _isKanaOnly(String value) {
    return RegExp(r'^[\u3040-\u30FFー]+$').hasMatch(value);
  }

  bool _isPunctuation(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');

    if (compact.isEmpty) {
      return false;
    }

    return RegExp(
      r'^[、。！？!?…‥・「」『』（）()［］\[\]【】〈〉《》〔〕〜～ー—―,.;:]+$',
    ).hasMatch(compact);
  }

  Future<void> _openToken(
    int index,
    DictionaryExampleToken token,
  ) async {
    setState(() {
      loadingTokenIndex = index;
    });

    try {
      await widget.onTokenTap(context, token);
    } finally {
      if (mounted) {
        setState(() {
          loadingTokenIndex = null;
        });
      }
    }
  }

  Widget _sectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        border: Border(
          top: BorderSide(color: dividerColor, width: 1),
          bottom: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      child: Text(
        title,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 20,
          height: 1,
          color: darkText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
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
