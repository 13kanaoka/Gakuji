import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/data/seed/dictionary_seed.dart';

List<Term> _deckCopies(String deckId, List<String> sourceIds) {
  return sourceIds.map((sourceId) {
    final dictionaryTerm = getTermById(sourceId);

    return Term.deckCopyFrom(
      dictionaryTerm,
      id: '${deckId}_$sourceId',
      marked: false,
    );
  }).toList();
}

List<Deck> buildSampleDecks() {
  return [
    // DEFAULT READING DECK
    Deck(
      id: 'd1',
      name: 'Gakuji test deck',
      type: DeckType.reading,
      terms: _deckCopies('d1', ['t1', 't2', 't3', 't4', 't5', 't6']),
    ),

    // DEFAULT WRITING DECK
    Deck(
      id: 'd2',
      name: 'Gakuji write test',
      type: DeckType.writing,
      terms: _deckCopies('d2', ['t1', 't2', 't3', 't4', 't5', 't6']),
    ),
  ];
}

final List<Deck> decks = buildSampleDecks();
