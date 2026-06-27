import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/dictionary_data.dart' as fallback_dictionary;
import '../models/term.dart';

class DictionaryService {
  static const String dictionaryAssetPath =
      'assets/dictionary/dictionary_words.json';

  static List<Term> _terms = fallback_dictionary.dictionaryWords;
  static Future<void>? _loadFuture;

  static List<Term> get terms => _terms;

  static Future<void> loadDictionary() {
    _loadFuture ??= _loadDictionaryFromAssets();
    return _loadFuture!;
  }

  static Future<void> _loadDictionaryFromAssets() async {
    try {
      final rawJson = await rootBundle.loadString(dictionaryAssetPath);
      final decoded = jsonDecode(rawJson);

      if (decoded is! List) return;

      final loadedTerms = decoded
          .whereType<Map<String, dynamic>>()
          .map(Term.fromJson)
          .where((term) {
        return term.id.isNotEmpty &&
            term.kanji.isNotEmpty &&
            term.reading.isNotEmpty &&
            term.meaning.isNotEmpty;
      }).toList();

      if (loadedTerms.isNotEmpty) {
        _terms = loadedTerms;
      }
    } catch (_) {
      _terms = fallback_dictionary.dictionaryWords;
    }
  }

  static List<Term> search(
    String rawQuery, {
    int limit = 60,
  }) {
    final query = rawQuery.trim();

    if (query.isEmpty) return const [];

    final lowerQuery = query.toLowerCase();
    final matches = <_RankedDictionaryMatch>[];

    for (final term in _terms) {
      final score = _scoreTerm(
        term: term,
        query: query,
        lowerQuery: lowerQuery,
      );

      if (score > 0) {
        matches.add(
          _RankedDictionaryMatch(
            term: term,
            score: score,
          ),
        );
      }
    }

    matches.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;

      if (a.term.isCommon != b.term.isCommon) {
        return a.term.isCommon ? -1 : 1;
      }

      return a.term.kanji.length.compareTo(b.term.kanji.length);
    });

    return matches.take(limit).map((match) => match.term).toList();
  }

  static Term getTermById(String id) {
    try {
      return _terms.firstWhere((term) => term.id == id);
    } catch (_) {
      return fallback_dictionary.getTermById(id);
    }
  }

  static int _scoreTerm({
    required Term term,
    required String query,
    required String lowerQuery,
  }) {
    var score = 0;

    final meaningLower = term.meaning.toLowerCase();
    final definitionsLower = term.definitions
        .map((definition) => definition.toLowerCase())
        .toList();

    // Japanese exact matches.
    if (term.kanji == query) score += 3000;
    if (term.reading == query) score += 2900;

    // Japanese prefix matches.
    if (term.kanji.startsWith(query)) score += 2200;
    if (term.reading.startsWith(query)) score += 2100;

    // Japanese contains matches.
    if (term.kanji.contains(query)) score += 1200;
    if (term.reading.contains(query)) score += 1100;

    // English meaning matches.
    if (meaningLower == lowerQuery) score += 2600;
    if (meaningLower.startsWith(lowerQuery)) score += 2000;
    if (_containsWholeWord(meaningLower, lowerQuery)) score += 1600;
    if (meaningLower.contains(lowerQuery)) score += 500;

    for (final definition in definitionsLower) {
      final simplified = _simplifyEnglishDefinition(definition);

      if (definition == lowerQuery) score += 3000;
      if (simplified == lowerQuery) score += 2950;

      if (definition == 'to $lowerQuery') score += 2900;
      if (definition.startsWith('to $lowerQuery')) score += 2800;

      if (definition.startsWith(lowerQuery)) score += 2200;
      if (simplified.startsWith(lowerQuery)) score += 2150;

      if (_containsWholeWord(definition, lowerQuery)) score += 1700;
      if (_containsWholeWord(simplified, lowerQuery)) score += 1700;

      if (definition.contains(lowerQuery)) score += 350;
    }

    if (term.kunyomi.any((reading) => reading == query)) score += 800;
    if (term.onyomi.any((reading) => reading == query)) score += 800;
    if (term.nanori.any((reading) => reading == query)) score += 600;

    if (term.isCommon) score += 500;

    if (term.kanji.length <= 4) score += 120;
    if (term.kanji.length <= 3) score += 120;
    if (term.kanji.length <= 2) score += 80;

    return score;
  }

  static String _simplifyEnglishDefinition(String value) {
    var simplified = value.toLowerCase().trim();

    if (simplified.startsWith('to ')) {
      simplified = simplified.substring(3).trim();
    }

    simplified = simplified
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return simplified;
  }

  static bool _containsWholeWord(String value, String lowerQuery) {
    if (lowerQuery.isEmpty) return false;

    final pattern = RegExp(
      r'(^|[^a-zA-Z])' + RegExp.escape(lowerQuery) + r'($|[^a-zA-Z])',
      caseSensitive: false,
    );

    return pattern.hasMatch(value);
  }
}

class _RankedDictionaryMatch {
  final Term term;
  final int score;

  const _RankedDictionaryMatch({
    required this.term,
    required this.score,
  });
}