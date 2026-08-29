import '../models/term.dart';
import 'dictionary_service.dart';
import 'japanese_conjugation_service.dart';

class CameraTextAnalysisResult {
  final String text;
  final List<Term> isolatedMatches;
  final DictionaryExample? sentenceExample;

  const CameraTextAnalysisResult({
    required this.text,
    this.isolatedMatches = const [],
    this.sentenceExample,
  });

  bool get isIsolated => isolatedMatches.isNotEmpty;

  bool get hasSentenceBreakdown => sentenceExample != null;
}

class CameraTextAnalysisService {
  static const int _maxCandidateRunes = 12;

  static Future<CameraTextAnalysisResult> analyze(String rawText) async {
    final text = _normalizeOcrText(rawText);

    if (text.isEmpty) {
      return const CameraTextAnalysisResult(text: '');
    }

    final exactMatches = await DictionaryService.findExactJapanese(
      text,
      limit: 8,
    );

    if (exactMatches.isNotEmpty) {
      return CameraTextAnalysisResult(
        text: text,
        isolatedMatches: exactMatches,
      );
    }

    final menuCandidate = _stripTrailingMenuPrice(text);

    if (menuCandidate.isNotEmpty && menuCandidate != text) {
      final menuMatches = await DictionaryService.findExactJapanese(
        menuCandidate,
        limit: 8,
      );

      if (menuMatches.isNotEmpty) {
        return CameraTextAnalysisResult(
          text: text,
          isolatedMatches: menuMatches,
        );
      }
    }

    final tokenization = await _tokenize(text);

    if (_looksLikeOneIsolatedTerm(text, tokenization)) {
      return CameraTextAnalysisResult(
        text: text,
        isolatedMatches: tokenization.uniqueTerms,
      );
    }

    if (tokenization.tokens.isNotEmpty) {
      return CameraTextAnalysisResult(
        text: text,
        sentenceExample: DictionaryExample(
          japanese: text,
          reading: '',
          english: '',
          tokens: tokenization.tokens,
        ),
      );
    }

    if (_runeLength(text) <= 8) {
      final fallbackMatches = await DictionaryService.search(
        menuCandidate.isNotEmpty ? menuCandidate : text,
        limit: 6,
      );

      if (fallbackMatches.isNotEmpty) {
        return CameraTextAnalysisResult(
          text: text,
          isolatedMatches: fallbackMatches,
        );
      }
    }

    return CameraTextAnalysisResult(text: text);
  }

  static Future<_CameraTokenizationResult> _tokenize(String text) async {
    final runes = text.runes
        .map((value) => String.fromCharCode(value))
        .toList(growable: false);
    final candidates = <String>{};

    for (var start = 0; start < runes.length; start++) {
      if (!_isJapaneseRune(runes[start])) continue;

      final buffer = StringBuffer();

      for (var end = start;
          end < runes.length && end < start + _maxCandidateRunes;
          end++) {
        final rune = runes[end];

        if (!_isJapaneseRune(rune)) break;

        buffer.write(rune);
        final candidate = buffer.toString();

        if (_canUseCandidate(candidate)) {
          candidates.add(candidate);
        }
      }
    }

    if (candidates.isEmpty) {
      return const _CameraTokenizationResult();
    }

    final exactMatches = await DictionaryService.findExactJapaneseBatch(
      candidates,
      perQueryLimit: 3,
    );

    final deinflectionCandidatesBySurface = <String, Set<String>>{};
    final dictionaryFormQueries = <String>{};

    for (final surface in candidates) {
      final dictionaryForms =
          JapaneseConjugationService.deinflectionCandidates(surface);

      if (dictionaryForms.isEmpty) continue;

      deinflectionCandidatesBySurface[surface] = dictionaryForms;
      dictionaryFormQueries.addAll(dictionaryForms);
    }

    final deinflectedMatches = dictionaryFormQueries.isEmpty
        ? const <String, List<Term>>{}
        : await DictionaryService.findExactJapaneseBatch(
            dictionaryFormQueries,
            perQueryLimit: 4,
          );

    final tokens = <DictionaryExampleToken>[];
    final uniqueTermsById = <String, Term>{};
    var matchedJapaneseRunes = 0;
    var cursor = 0;

    while (cursor < runes.length) {
      if (!_isJapaneseRune(runes[cursor])) {
        cursor += 1;
        continue;
      }

      Term? matchedTerm;
      String? matchedSurface;
      var matchedLength = 0;
      final maxLength = (runes.length - cursor).clamp(
        0,
        _maxCandidateRunes,
      ).toInt();

      for (var length = maxLength; length >= 1; length--) {
        final surface = runes.sublist(cursor, cursor + length).join();

        if (!_canUseCandidate(surface)) continue;

        final matches = exactMatches[surface] ?? const <Term>[];
        final exactTerm = matches.isEmpty ? null : matches.first;
        final deinflectedTerm = _bestDeinflectedMatch(
          surface: surface,
          dictionaryForms:
              deinflectionCandidatesBySurface[surface] ?? const <String>{},
          matchesByDictionaryForm: deinflectedMatches,
        );
        final resolvedMatch = deinflectedTerm ?? exactTerm;

        if (resolvedMatch == null) continue;

        matchedSurface = surface;
        matchedTerm = resolvedMatch;
        matchedLength = length;
        break;
      }

      if (matchedTerm == null || matchedSurface == null) {
        cursor += 1;
        continue;
      }

      final resolvedTerm = matchedTerm;

      tokens.add(
        DictionaryExampleToken(
          surface: matchedSurface,
          headword: resolvedTerm.kanji,
          reading: resolvedTerm.reading,
          termId: resolvedTerm.id,
        ),
      );
      uniqueTermsById.putIfAbsent(resolvedTerm.id, () => resolvedTerm);
      matchedJapaneseRunes += matchedLength;
      cursor += matchedLength;
    }

    return _CameraTokenizationResult(
      tokens: List.unmodifiable(tokens),
      uniqueTerms: List.unmodifiable(uniqueTermsById.values),
      matchedJapaneseRunes: matchedJapaneseRunes,
    );
  }


  static Term? _bestDeinflectedMatch({
    required String surface,
    required Set<String> dictionaryForms,
    required Map<String, List<Term>> matchesByDictionaryForm,
  }) {
    for (final dictionaryForm in dictionaryForms) {
      final matches =
          matchesByDictionaryForm[dictionaryForm] ?? const <Term>[];

      for (final term in matches) {
        if (JapaneseConjugationService.surfaceMatchesTerm(term, surface)) {
          return term;
        }
      }
    }

    return null;
  }

  static bool _looksLikeOneIsolatedTerm(
    String text,
    _CameraTokenizationResult tokenization,
  ) {
    if (tokenization.uniqueTerms.length != 1 || tokenization.tokens.isEmpty) {
      return false;
    }

    final totalJapaneseRunes = text.runes.where((rune) {
      return _isJapaneseRune(String.fromCharCode(rune));
    }).length;

    if (totalJapaneseRunes == 0) return false;

    final coverage = tokenization.matchedJapaneseRunes / totalJapaneseRunes;

    return coverage >= 0.70 && _runeLength(text) <= 14;
  }

  static String _normalizeOcrText(String rawText) {
    return rawText
        .replaceAll(RegExp(r'[\r\n\t]+'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  static String _stripTrailingMenuPrice(String text) {
    var result = text;

    final trailingPricePatterns = <RegExp>[
      RegExp(r'[（(](?:税込|税抜)[）)]$'),
      RegExp(r'(?:[¥￥]\d[\d,.]*|\d[\d,.]*円)(?:税込|税抜)?$'),
      RegExp(r'\d[\d,.]*(?:円)?(?:税込|税抜)$'),
      RegExp(r'\d[\d,.]*$'),
    ];

    for (final pattern in trailingPricePatterns) {
      result = result.replaceFirst(pattern, '');
    }

    return result
        .replaceAll(RegExp(r'[・●○◆◇■□★☆※\-–—:：]+$'), '')
        .trim();
  }

  static bool _canUseCandidate(String value) {
    final length = _runeLength(value);

    if (length >= 2) return true;

    return _containsKanji(value);
  }

  static bool _isJapaneseRune(String value) {
    return RegExp(
      r'^[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々〆ヶ]$',
    ).hasMatch(value);
  }

  static bool _containsKanji(String value) {
    return RegExp(
      r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々]',
    ).hasMatch(value);
  }

  static int _runeLength(String value) => value.runes.length;
}

class _CameraTokenizationResult {
  final List<DictionaryExampleToken> tokens;
  final List<Term> uniqueTerms;
  final int matchedJapaneseRunes;

  const _CameraTokenizationResult({
    this.tokens = const [],
    this.uniqueTerms = const [],
    this.matchedJapaneseRunes = 0,
  });
}
