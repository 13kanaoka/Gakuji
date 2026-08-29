import '../models/deck.dart';
import '../models/term.dart';
import 'dictionary_service.dart';

/// Repairs legacy/partial deck terms at persistence boundaries.
///
/// Study screens must never query the dictionary to render a card. A deck term
/// is expected to own the lexical payload it needs. Older cloud writers can,
/// however, leave behind a term containing only an id/spelling. This service
/// repairs only those incomplete records from the on-device dictionary and
/// returns a complete deck-owned copy before the term reaches study UI.
class GakujiTermPayloadRepair {
  static bool hasStudyDefinition(Term term) {
    for (final sense in term.senses) {
      if (sense.glosses.any((gloss) => gloss.trim().isNotEmpty)) {
        return true;
      }
    }

    return term.meaning.trim().isNotEmpty;
  }

  /// Repairs incomplete terms in [decks] in place.
  ///
  /// [fallbackDecks] is useful during cloud hydration: a complete local term is
  /// preferred over a dictionary lookup when the remote copy is incomplete.
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

    final dictionaryCache = <String, Term?>{};
    var repairedCount = 0;

    for (final deck in decks) {
      final fallbackTerms = fallbackByDeckId[deck.id] ?? const <String, Term>{};

      for (var index = 0; index < deck.terms.length; index++) {
        final partial = deck.terms[index];
        if (hasStudyDefinition(partial)) continue;

        final candidateSourceIds = _candidateDictionaryIds(partial);
        if (candidateSourceIds.isEmpty) continue;

        Term? complete = fallbackTerms[partial.id];
        for (final candidateId in candidateSourceIds) {
          complete ??= fallbackTerms[candidateId];
        }

        if (complete == null || !hasStudyDefinition(complete)) {
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

        if (complete == null || !hasStudyDefinition(complete)) continue;

        deck.terms[index] = _mergeCompletePayload(
          complete: complete,
          partial: partial,
        );
        repairedCount++;
      }
    }

    return repairedCount;
  }

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
