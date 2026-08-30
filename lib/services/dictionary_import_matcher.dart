import 'package:gakuji/models/deck_import_row.dart';
import 'package:gakuji/models/term.dart';
import 'package:gakuji/services/dictionary_service.dart';

class DictionaryImportMatcher {
  static const Set<String> _definitionStopWords = {
    'a',
    'an',
    'and',
    'as',
    'at',
    'be',
    'by',
    'for',
    'from',
    'in',
    'is',
    'it',
    'of',
    'on',
    'or',
    'that',
    'the',
    'to',
    'with',
  };

  static Future<void> matchRows(
    List<DeckImportRow> rows, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final matchableRows = rows.where((row) {
      return row.status != DeckImportMatchStatus.skipped;
    }).toList(growable: false);

    var completed = 0;

    for (final row in matchableRows) {
      final match = await _matchRow(row);

      row
        ..candidates = match.candidates
        ..selectedTerm = match.selectedTerm
        ..status = match.status
        ..included = match.selectedTerm != null
        ..message = match.message;

      completed++;
      onProgress?.call(completed, matchableRows.length);
    }
  }

  static Future<_DeckImportMatch> _matchRow(DeckImportRow row) async {
    final readingVariants = _readingVariants(row.importedReading)
        .take(6)
        .toList(growable: false);
    final candidateTerms = await DictionaryService.findImportCandidates(
      term: row.importedTerm,
      readings: readingVariants,
      limit: 24,
    );

    final rankedCandidates = candidateTerms
        .map(
          (term) => DeckImportCandidate(
            term: term,
            score: _scoreCandidate(row, term),
          ),
        )
        .where((candidate) => candidate.score > 0)
        .toList();

    rankedCandidates.sort((left, right) {
      final scoreComparison = right.score.compareTo(left.score);

      if (scoreComparison != 0) return scoreComparison;

      if (left.term.isCommon != right.term.isCommon) {
        return left.term.isCommon ? -1 : 1;
      }

      return left.term.kanji.length.compareTo(right.term.kanji.length);
    });

    final candidates = rankedCandidates.take(8).toList(growable: false);

    if (candidates.isEmpty) {
      return const _DeckImportMatch(
        candidates: [],
        status: DeckImportMatchStatus.unmatched,
        message: 'No dictionary match was found.',
      );
    }

    if (candidates.first.score < 70) {
      return _DeckImportMatch(
        candidates: candidates,
        status: DeckImportMatchStatus.unmatched,
        message: 'No confident dictionary match was found.',
      );
    }

    final top = candidates.first;
    final secondScore = candidates.length > 1 ? candidates[1].score : 0;
    final margin = top.score - secondScore;
    final confident = top.score >= 150 ||
        (top.score >= 120 && margin >= 8) ||
        (top.score >= 95 && margin >= 18) ||
        (candidates.length == 1 && top.score >= 90);

    if (confident) {
      return _DeckImportMatch(
        candidates: candidates,
        selectedTerm: top.term,
        status: DeckImportMatchStatus.matched,
      );
    }

    return _DeckImportMatch(
      candidates: candidates,
      status: DeckImportMatchStatus.ambiguous,
      message: 'Choose the intended dictionary entry.',
    );
  }

  static int _scoreCandidate(DeckImportRow row, Term candidate) {
    var score = 0;

    final importedTerm = _normalizeJapanese(row.importedTerm);
    final importedReadings = _readingVariants(row.importedReading)
        .map(_normalizeJapanese)
        .where((value) => value.isNotEmpty)
        .toSet();
    final candidateSpellings = <String>{
      candidate.kanji,
      ...candidate.alternativeKanji,
    }.map(_normalizeJapanese).where((value) => value.isNotEmpty).toSet();
    final candidateReading = _normalizeJapanese(candidate.reading);

    final termMatchesSpelling = importedTerm.isNotEmpty &&
        candidateSpellings.contains(importedTerm);
    final termMatchesReading = importedTerm.isNotEmpty &&
        candidateReading == importedTerm;
    final readingMatches = importedReadings.isNotEmpty &&
        importedReadings.contains(candidateReading);

    if (termMatchesSpelling) score += 120;
    if (termMatchesReading) score += 105;
    if (readingMatches) score += 110;

    if (termMatchesSpelling && readingMatches) {
      score += 35;
    } else if ((termMatchesSpelling || termMatchesReading) &&
        row.importedReading.trim().isEmpty) {
      score += 12;
    } else if (readingMatches && row.importedTerm.trim().isEmpty) {
      score += 18;
    }

    if (importedTerm.isNotEmpty && !termMatchesSpelling && !termMatchesReading) {
      for (final spelling in candidateSpellings) {
        if (spelling.startsWith(importedTerm) ||
            importedTerm.startsWith(spelling)) {
          score += 45;
          break;
        }
      }
    }

    if (importedReadings.isNotEmpty && !readingMatches) {
      for (final reading in importedReadings) {
        if (candidateReading.startsWith(reading) ||
            reading.startsWith(candidateReading)) {
          score += 38;
          break;
        }
      }
    }

    score += _definitionScore(
      row.importedDefinition,
      candidate,
    );

    if (candidate.isCommon) score += 3;

    return score;
  }

  static int _definitionScore(String importedDefinition, Term candidate) {
    final importedTokens = _definitionTokens(importedDefinition);

    if (importedTokens.isEmpty) return 0;

    final candidateText = <String>[
      candidate.meaning,
      ...candidate.rawDefinitions,
    ].join(' ');
    final candidateTokens = _definitionTokens(candidateText);

    if (candidateTokens.isEmpty) return 0;

    final sharedTokens = importedTokens.intersection(candidateTokens).length;

    if (sharedTokens == 0) return 0;

    final coverage = sharedTokens / importedTokens.length;
    final sharedTokenBonus = sharedTokens.clamp(0, 6).toInt() * 2;
    final score = (coverage * 28).round() + sharedTokenBonus;

    return score.clamp(0, 40).toInt();
  }

  static Set<String> _definitionTokens(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) {
          return token.length > 1 && !_definitionStopWords.contains(token);
        })
        .toSet();
  }

  static Iterable<String> _readingVariants(String value) sync* {
    final seen = <String>{};

    for (final part in value.split(RegExp(r'[,、;/|]+'))) {
      final reading = part.trim();

      if (reading.isEmpty || !seen.add(reading)) continue;

      yield reading;
    }
  }

  static String _normalizeJapanese(String value) {
    final trimmed = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s・･._\-]+'), '');

    return String.fromCharCodes(
      trimmed.runes.map((rune) {
        if (rune >= 0x30A1 && rune <= 0x30F6) {
          return rune - 0x60;
        }

        return rune;
      }),
    );
  }
}

class _DeckImportMatch {
  final List<DeckImportCandidate> candidates;
  final Term? selectedTerm;
  final DeckImportMatchStatus status;
  final String? message;

  const _DeckImportMatch({
    required this.candidates,
    this.selectedTerm,
    required this.status,
    this.message,
  });
}
