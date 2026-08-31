import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/data/dictionary/dictionary_service.dart';

/// Repairs legacy/partial deck terms at persistence boundaries.
///
/// Study screens must never query the dictionary to render a card. A deck term
/// is expected to own the lexical payload it needs. Older cloud writers can,
/// however, leave behind a term containing only an id/spelling, and deck terms
/// saved before dictionary spelling metadata existed do not know the preferred
/// written form. This service repairs those records from the on-device
/// dictionary before they reach study UI.
class GakujiTermPayloadRepair {
  static bool hasStudyDefinition(Term term) {
    for (final sense in term.senses) {
      if (sense.glosses.any((gloss) => gloss.trim().isNotEmpty)) {
        return true;
      }
    }

    return term.meaning.trim().isNotEmpty;
  }

  /// Repairs incomplete lexical payloads and missing dictionary spelling
  /// metadata in [decks] in place.
  ///
  /// [fallbackDecks] is useful during cloud hydration: a complete local term is
  /// preferred over a dictionary lookup when the study payload is missing.
  /// Spelling metadata is loaded in one lightweight bulk query so migrating an
  /// existing large deck does not materialize every full dictionary entry.
  /// The return value is the number of repaired term records.
  static Future<int> repairDecks(
    List<Deck> decks, {
    List<Deck> fallbackDecks = const <Deck>[],
  }) async {
    if (decks.isEmpty) return 0;

    final fallbackByDeckId = <String, Map<String, Term>>{};
    for (final deck in fallbackDecks) {
      final byIdentity = <String, Term>{};
      for (final term in deck.terms) {
        if (!hasStudyDefinition(term)) continue;
        byIdentity.putIfAbsent(term.id, () => term);
        final sourceId = term.sourceId?.trim();
        if (sourceId != null && sourceId.isNotEmpty) {
          byIdentity.putIfAbsent(sourceId, () => term);
        }
      }
      fallbackByDeckId[deck.id] = byIdentity;
    }

    // Preferred writing is dictionary-owned data, so refresh it for every
    // saved card instead of trusting the copy stored in user data. This is
    // important when the bundled dictionary corrects a preferred form after a
    // card has already been saved (for example 此処 -> ここ or 煙草 -> タバコ).
    final spellingCandidateIds = <String>{};
    for (final deck in decks) {
      for (final term in deck.terms) {
        spellingCandidateIds.addAll(_candidateDictionaryIds(term));
      }
    }

    Map<String, DictionaryTermSpellingMetadata> spellingMetadataByTermId =
        const {};
    if (spellingCandidateIds.isNotEmpty) {
      try {
        spellingMetadataByTermId =
            await DictionaryService.spellingMetadataForTermIds(
          spellingCandidateIds,
        );
      } catch (_) {
        // Preferred-writing metadata is additive. Legacy definition repair must
        // still work if an older bundled dictionary does not have the table.
        spellingMetadataByTermId = const {};
      }
    }

    final unresolvedSpellingTerms = <Term>[];
    for (final deck in decks) {
      for (final term in deck.terms) {
        final hasIdMetadata = _candidateDictionaryIds(term).any(
          spellingMetadataByTermId.containsKey,
        );
        if (!hasIdMetadata) unresolvedSpellingTerms.add(term);
      }
    }

    Map<String, DictionaryTermSpellingMetadata> spellingMetadataByLexicalKey =
        const {};
    if (unresolvedSpellingTerms.isNotEmpty) {
      try {
        spellingMetadataByLexicalKey =
            await DictionaryService.spellingMetadataForTerms(
          unresolvedSpellingTerms,
        );
      } catch (_) {
        spellingMetadataByLexicalKey = const {};
      }
    }

    final dictionaryCache = <String, Term?>{};
    var repairedCount = 0;

    for (final deck in decks) {
      final fallbackTerms = fallbackByDeckId[deck.id] ?? const <String, Term>{};

      for (var index = 0; index < deck.terms.length; index++) {
        final original = deck.terms[index];
        final candidateSourceIds = _candidateDictionaryIds(original);
        if (candidateSourceIds.isEmpty) continue;

        var repaired = original;
        var changed = false;

        if (!hasStudyDefinition(repaired)) {
          Term? complete = fallbackTerms[repaired.id];
          for (final candidateId in candidateSourceIds) {
            complete ??= fallbackTerms[candidateId];
          }

          if (complete == null || !hasStudyDefinition(complete)) {
            complete = null;

            for (final candidateId in candidateSourceIds) {
              if (dictionaryCache.containsKey(candidateId)) {
                complete = dictionaryCache[candidateId];
              } else {
                try {
                  final dictionaryTerm =
                      await DictionaryService.getTermByIdAsync(candidateId);
                  complete = hasStudyDefinition(dictionaryTerm)
                      ? dictionaryTerm
                      : null;
                } catch (_) {
                  complete = null;
                }
                dictionaryCache[candidateId] = complete;
              }

              if (complete != null && hasStudyDefinition(complete)) break;
            }
          }

          if (complete != null && hasStudyDefinition(complete)) {
            repaired = _mergeCompletePayload(
              complete: complete,
              partial: repaired,
            );
            changed = true;
          }
        }

        DictionaryTermSpellingMetadata? metadata;
        for (final candidateId in candidateSourceIds) {
          metadata = spellingMetadataByTermId[candidateId];
          if (metadata != null) break;
        }

        metadata ??= spellingMetadataByLexicalKey[
          DictionaryService.spellingMetadataLexicalKey(repaired)
        ];

        if (metadata != null &&
            (_normalized(repaired.preferredSpelling) !=
                    _normalized(metadata.preferredSpelling) ||
                repaired.usuallyWrittenInKana !=
                    metadata.usuallyWrittenInKana ||
                !repaired.hasDictionarySpellingMetadata ||
                repaired.spellings.isNotEmpty)) {
          repaired = repaired.copyWith(
            preferredSpelling: metadata.preferredSpelling,
            // Keep deck/cloud payloads lean. Card Edit loads the canonical
            // dictionary term on demand when it needs every written form.
            spellings: const [],
            usuallyWrittenInKana: metadata.usuallyWrittenInKana,
            hasDictionarySpellingMetadata: true,
          );
          changed = true;
        }

        if (!changed) continue;

        deck.terms[index] = repaired;
        repairedCount++;
      }
    }

    return repairedCount;
  }

  /// Refreshes dictionary-owned spelling metadata on persisted recent-search
  /// terms. Unlike deck copies, recent searches keep the complete spelling
  /// list because the dictionary UI needs those alternatives when the entry is
  /// reopened from History.
  static Future<int> repairRecentSearches(List<Term> terms) async {
    if (terms.isEmpty) return 0;

    final candidateIds = <String>{};
    for (final term in terms) {
      candidateIds.addAll(_candidateDictionaryIds(term));
    }

    if (candidateIds.isEmpty) return 0;

    Map<String, DictionaryTermSpellingMetadata> metadataByTermId = const {};
    Map<String, DictionaryTermSpellingMetadata> metadataByLexicalKey = const {};
    try {
      metadataByTermId = await DictionaryService.spellingMetadataForTermIds(
        candidateIds,
      );

      final unresolvedTerms = terms.where((term) {
        return !_candidateDictionaryIds(term).any(metadataByTermId.containsKey);
      }).toList(growable: false);

      if (unresolvedTerms.isNotEmpty) {
        metadataByLexicalKey = await DictionaryService.spellingMetadataForTerms(
          unresolvedTerms,
        );
      }
    } catch (_) {
      return 0;
    }

    var repairedCount = 0;

    for (var index = 0; index < terms.length; index++) {
      final original = terms[index];
      DictionaryTermSpellingMetadata? metadata;

      for (final candidateId in _candidateDictionaryIds(original)) {
        metadata = metadataByTermId[candidateId];
        if (metadata != null) break;
      }

      metadata ??= metadataByLexicalKey[
        DictionaryService.spellingMetadataLexicalKey(original)
      ];

      if (metadata == null) continue;

      final alreadyCurrent =
          _normalized(original.preferredSpelling) ==
                  _normalized(metadata.preferredSpelling) &&
              original.usuallyWrittenInKana ==
                  metadata.usuallyWrittenInKana &&
              original.hasDictionarySpellingMetadata &&
              _sameSpellings(original.spellings, metadata.spellings);

      if (alreadyCurrent) continue;

      terms[index] = original.copyWith(
        preferredSpelling: metadata.preferredSpelling,
        spellings: metadata.spellings,
        usuallyWrittenInKana: metadata.usuallyWrittenInKana,
        hasDictionarySpellingMetadata: true,
      );
      repairedCount++;
    }

    return repairedCount;
  }

  static bool _sameSpellings(
    List<DictionarySpelling> first,
    List<DictionarySpelling> second,
  ) {
    if (first.length != second.length) return false;

    for (var index = 0; index < first.length; index++) {
      final a = first[index];
      final b = second[index];

      if (a.text != b.text ||
          a.kind != b.kind ||
          a.isPreferred != b.isPreferred ||
          !_sameStrings(a.infoTags, b.infoTags) ||
          !_sameStrings(a.priorityTags, b.priorityTags) ||
          !_sameStrings(a.restrictions, b.restrictions)) {
        return false;
      }
    }

    return true;
  }

  static bool _sameStrings(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  static String _normalized(String value) => value.trim();

  static List<String> _candidateDictionaryIds(Term term) {
    final result = <String>[];

    void add(String? value) {
      final cleaned = value?.trim() ?? '';
      if (cleaned.isEmpty || result.contains(cleaned)) return;
      result.add(cleaned);
    }

    add(term.sourceId);
    add(term.id);

    // Older deck copies sometimes encoded the dictionary id followed by a
    // microsecond timestamp but did not persist sourceId. Recover that stable
    // prefix once here rather than making study screens query the dictionary.
    final legacyMatch = RegExp(r'^(.*)_([0-9]{13,})$').firstMatch(term.id);
    if (legacyMatch != null) {
      add(legacyMatch.group(1));
    }

    return result;
  }

  static Term _mergeCompletePayload({
    required Term complete,
    required Term partial,
  }) {
    final json = Map<String, dynamic>.from(complete.toJson());

    // Full dictionary spelling arrays can be surprisingly large across a
    // library and are not needed by study screens. Preserve the one preferred
    // writing and migration marker, but leave alternatives on the canonical
    // dictionary term that Card Edit resolves on demand.
    json.remove('spellings');

    // Preserve the deck-owned identity and mutable card state from the partial
    // record while taking lexical content (senses/examples/etc.) from the
    // complete local source.
    json['id'] = partial.id;

    final sourceId = partial.sourceId?.trim();
    if (sourceId != null && sourceId.isNotEmpty) {
      json['sourceId'] = sourceId;
    }

    final kanji = partial.kanji.trim();
    if (kanji.isNotEmpty) json['kanji'] = kanji;

    final reading = partial.reading.trim();
    if (reading.isNotEmpty) json['reading'] = reading;

    json['marked'] = partial.marked;

    if (partial.selectedGlosses.isNotEmpty) {
      json['selectedGlosses'] = partial.selectedGlosses
          .map((selection) => selection.toJson())
          .toList(growable: false);
    }

    if (partial.defaultCardDefinitionLimit != 3) {
      json['defaultCardDefinitionLimit'] = partial.defaultCardDefinitionLimit;
    }

    final note = partial.note?.trim();
    if (note != null && note.isNotEmpty) {
      json['note'] = partial.note;
    }

    return Term.fromJson(json);
  }
}
