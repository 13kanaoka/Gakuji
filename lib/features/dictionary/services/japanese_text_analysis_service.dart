import 'package:gakuji/domain/term.dart';
import 'package:gakuji/data/dictionary/dictionary_service.dart';
import 'package:gakuji/features/dictionary/services/japanese_conjugation_service.dart';

class JapaneseTextAnalysisResult {
  final String text;
  final List<Term> isolatedMatches;
  final List<Term> sentenceMatches;
  final DictionaryExample? sentenceExample;

  const JapaneseTextAnalysisResult({
    required this.text,
    this.isolatedMatches = const [],
    this.sentenceMatches = const [],
    this.sentenceExample,
  });

  bool get isIsolated => isolatedMatches.isNotEmpty;

  bool get hasSentenceBreakdown => sentenceExample != null;
}

class JapaneseTextAnalysisService {
  static const int _maxCandidateRunes = 12;

  static Future<JapaneseTextAnalysisResult> analyze(
    String rawText, {
    double isolatedTermCoverageThreshold = 1.0,
    bool requireSingleTokenForIsolated = true,
    bool allowMenuPriceFallback = false,
    bool removeWhitespace = false,
  }) async {
    final text = _normalizeText(
      rawText,
      removeWhitespace: removeWhitespace,
    );

    if (text.isEmpty) {
      return const JapaneseTextAnalysisResult(text: '');
    }

    final exactMatches = await DictionaryService.findExactJapanese(
      text,
      limit: 8,
    );

    if (exactMatches.isNotEmpty) {
      return JapaneseTextAnalysisResult(
        text: text,
        isolatedMatches: exactMatches,
      );
    }

    final menuCandidate = _stripTrailingMenuPrice(text);

    if (allowMenuPriceFallback &&
        menuCandidate.isNotEmpty &&
        menuCandidate != text) {
      final menuMatches = await DictionaryService.findExactJapanese(
        menuCandidate,
        limit: 8,
      );

      if (menuMatches.isNotEmpty) {
        return JapaneseTextAnalysisResult(
          text: text,
          isolatedMatches: menuMatches,
        );
      }
    }

    final tokenization = await _tokenize(text);

    if (_looksLikeOneIsolatedTerm(
      text,
      tokenization,
      coverageThreshold: isolatedTermCoverageThreshold,
      requireSingleToken: requireSingleTokenForIsolated,
    )) {
      return JapaneseTextAnalysisResult(
        text: text,
        isolatedMatches: tokenization.uniqueTerms,
      );
    }

    if (tokenization.tokens.isNotEmpty) {
      return JapaneseTextAnalysisResult(
        text: text,
        sentenceMatches: tokenization.uniqueTerms,
        sentenceExample: DictionaryExample(
          japanese: text,
          reading: '',
          english: '',
          tokens: tokenization.tokens,
        ),
      );
    }

    if (_runeLength(text) <= 8) {
      final fallbackQuery = allowMenuPriceFallback && menuCandidate.isNotEmpty
          ? menuCandidate
          : text;
      final fallbackMatches = await DictionaryService.search(
        fallbackQuery,
        limit: 6,
      );

      if (fallbackMatches.isNotEmpty) {
        return JapaneseTextAnalysisResult(
          text: text,
          isolatedMatches: fallbackMatches,
        );
      }
    }

    return JapaneseTextAnalysisResult(text: text);
  }

  static Future<List<Term>> findDeinflectedMatches(
    String rawSurface, {
    int limit = 8,
    bool removeWhitespace = false,
  }) async {
    final surface = _normalizeText(
      rawSurface,
      removeWhitespace: removeWhitespace,
    );

    if (surface.isEmpty || limit <= 0) return const [];

    final dictionaryForms =
        JapaneseConjugationService.deinflectionCandidates(surface);

    if (dictionaryForms.isEmpty) return const [];

    final matchesByDictionaryForm =
        await DictionaryService.findExactJapaneseBatch(
      dictionaryForms,
      perQueryLimit: 4,
    );
    final matchesById = <String, Term>{};

    for (final dictionaryForm in dictionaryForms) {
      final matches =
          matchesByDictionaryForm[dictionaryForm] ?? const <Term>[];

      for (final term in matches) {
        if (!JapaneseConjugationService.surfaceMatchesTerm(term, surface)) {
          continue;
        }

        matchesById.putIfAbsent(term.id, () => term);

        if (matchesById.length >= limit) {
          return List.unmodifiable(matchesById.values);
        }
      }
    }

    return List.unmodifiable(matchesById.values);
  }

  static Future<_JapaneseTextTokenizationResult> _tokenize(String text) async {
    final runes = text.runes
        .map((value) => String.fromCharCode(value))
        .toList(growable: false);
    final candidates = <String>{};
    final purposeStemSurfaces = <String>{};

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

        if (_canQueryCandidate(candidate)) {
          candidates.add(candidate);

          // A verb's continuative / masu stem can stand directly before に in
          // the purpose construction: 見に行く, 食べに行く, 書きに行く.
          // Record only candidates in that grammatical position so bare stems
          // do not compete with normal dictionary entries everywhere else.
          if (_nextNonWhitespaceRune(runes, end + 1) == 'に') {
            purposeStemSurfaces.add(candidate);
          }
        }
      }
    }

    if (candidates.isEmpty) {
      return const _JapaneseTextTokenizationResult();
    }

    final exactMatches = await DictionaryService.findExactJapaneseBatch(
      candidates,
      perQueryLimit: 3,
    );

    // One-kana surfaces have many homographs. Fetch a deeper exact-match set
    // only for them so grammatical entries such as と are not lost behind the
    // first few dictionary homographs, while keeping normal sentence lookup
    // inexpensive.
    final oneKanaCandidates = candidates.where(_isSingleKanaSurface).toList();

    if (oneKanaCandidates.isNotEmpty) {
      final oneKanaMatches = await DictionaryService.findExactJapaneseBatch(
        oneKanaCandidates,
        perQueryLimit: 24,
      );

      for (final surface in oneKanaCandidates) {
        exactMatches[surface] =
            oneKanaMatches[surface] ?? exactMatches[surface] ?? const <Term>[];
      }
    }

    final deinflectionCandidatesBySurface = <String, Set<String>>{};
    final conjunctiveStemCandidatesBySurface = <String, Set<String>>{};
    final dictionaryFormQueries = <String>{};

    for (final surface in candidates) {
      final dictionaryForms =
          JapaneseConjugationService.deinflectionCandidates(surface);

      if (dictionaryForms.isEmpty) continue;

      deinflectionCandidatesBySurface[surface] = dictionaryForms;
      dictionaryFormQueries.addAll(dictionaryForms);
    }

    for (final surface in purposeStemSurfaces) {
      final dictionaryForms =
          JapaneseConjugationService.conjunctiveStemCandidates(surface);

      if (dictionaryForms.isEmpty) continue;

      conjunctiveStemCandidatesBySurface[surface] = dictionaryForms;
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

        final matches = exactMatches[surface] ?? const <Term>[];
        final exactTerm = _bestExactMatch(
          surface: surface,
          matches: matches,
        );

        if (!_canUseCandidate(surface) && exactTerm == null) continue;

        final deinflectedTerm = _bestDeinflectedMatch(
          surface: surface,
          dictionaryForms:
              deinflectionCandidatesBySurface[surface] ?? const <String>{},
          matchesByDictionaryForm: deinflectedMatches,
        );
        final conjunctiveStemTerm = purposeStemSurfaces.contains(surface)
            ? _bestConjunctiveStemMatch(
                surface: surface,
                dictionaryForms: conjunctiveStemCandidatesBySurface[surface] ??
                    const <String>{},
                matchesByDictionaryForm: deinflectedMatches,
              )
            : null;
        final resolvedMatch =
            conjunctiveStemTerm ?? deinflectedTerm ?? exactTerm;

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

    return _JapaneseTextTokenizationResult(
      tokens: List.unmodifiable(tokens),
      uniqueTerms: List.unmodifiable(uniqueTermsById.values),
      matchedJapaneseRunes: matchedJapaneseRunes,
    );
  }

  static Term? _bestExactMatch({
    required String surface,
    required List<Term> matches,
  }) {
    if (matches.isEmpty) return null;

    if (_runeLength(surface) != 1 || _containsKanji(surface)) {
      return matches.first;
    }

    // One-kana dictionary candidates are only useful to sentence analysis when
    // they are grammatical particles. This lets entries such as と, に, は,
    // を, and が appear without turning every unmatched kana inside a word
    // into an unrelated one-character dictionary result.
    for (final term in matches) {
      if (_isParticleTerm(term)) return term;
    }

    return null;
  }

  static bool _isParticleTerm(Term term) {
    final tags = <String>[
      term.partOfSpeech,
      for (final sense in term.senses) ...sense.partOfSpeechTags,
    ];

    for (final tag in tags) {
      final normalized = tag.trim().toLowerCase();
      if (normalized == 'prt' || normalized.contains('particle')) {
        return true;
      }
    }

    return false;
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

  static Term? _bestConjunctiveStemMatch({
    required String surface,
    required Set<String> dictionaryForms,
    required Map<String, List<Term>> matchesByDictionaryForm,
  }) {
    for (final dictionaryForm in dictionaryForms) {
      final matches =
          matchesByDictionaryForm[dictionaryForm] ?? const <Term>[];

      for (final term in matches) {
        if (JapaneseConjugationService.conjunctiveStemMatchesTerm(
          term,
          surface,
        )) {
          return term;
        }
      }
    }

    return null;
  }

  static bool _looksLikeOneIsolatedTerm(
    String text,
    _JapaneseTextTokenizationResult tokenization, {
    required double coverageThreshold,
    required bool requireSingleToken,
  }) {
    if (tokenization.uniqueTerms.length != 1 ||
        tokenization.tokens.isEmpty ||
        (requireSingleToken && tokenization.tokens.length != 1)) {
      return false;
    }

    final totalJapaneseRunes = text.runes.where((rune) {
      return _isJapaneseRune(String.fromCharCode(rune));
    }).length;

    if (totalJapaneseRunes == 0) return false;

    final coverage = tokenization.matchedJapaneseRunes / totalJapaneseRunes;

    return coverage >= coverageThreshold && _runeLength(text) <= 14;
  }

  static String _normalizeText(
    String rawText, {
    required bool removeWhitespace,
  }) {
    final normalized = rawText
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), removeWhitespace ? '' : ' ')
        .trim();

    return normalized;
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

  static bool _canQueryCandidate(String value) {
    if (_canUseCandidate(value)) return true;

    // Query one-kana surfaces as well so genuine particle entries can be
    // recovered. _bestExactMatch filters these results back down to particles.
    return _runeLength(value) == 1 && _isJapaneseRune(value);
  }

  static bool _canUseCandidate(String value) {
    final length = _runeLength(value);

    if (length >= 2) return true;

    return _containsKanji(value);
  }

  static bool _isSingleKanaSurface(String value) {
    return _runeLength(value) == 1 &&
        RegExp(r'^[\u3040-\u30FF]$').hasMatch(value);
  }

  static String? _nextNonWhitespaceRune(List<String> runes, int start) {
    for (var index = start; index < runes.length; index++) {
      final rune = runes[index];
      if (rune.trim().isEmpty) continue;
      return rune;
    }

    return null;
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

class _JapaneseTextTokenizationResult {
  final List<DictionaryExampleToken> tokens;
  final List<Term> uniqueTerms;
  final int matchedJapaneseRunes;

  const _JapaneseTextTokenizationResult({
    this.tokens = const [],
    this.uniqueTerms = const [],
    this.matchedJapaneseRunes = 0,
  });
}
