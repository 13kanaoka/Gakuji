import '../models/deck.dart';
import '../models/term.dart';
import 'dictionary_data.dart';

List<Term> _deckCopies(String deckId, List<String> sourceIds) {
  return sourceIds.map((sourceId) {
    final dictionaryTerm = getTermById(sourceId);

    return Term.deckCopyFrom(
      dictionaryTerm,
      id: '${deckId}_$sourceId',
    );
  }).toList();
}

final List<Deck> decks = [
  /// 📚 DEFAULT READING DECK
  Deck(
    id: 'd1',
    name: 'Gakuji test deck',
    type: DeckType.reading,
    terms: _deckCopies('d1', [
      't1',
      't2',
      't3',
      't4',
      't5',
      't6',
    ]),
  ),

  /// ✍️ DEFAULT WRITING DECK
  Deck(
    id: 'd2',
    name: 'Gakuji write test',
    type: DeckType.writing,
    terms: _deckCopies('d2', [
      't1',
      't2',
      't3',
      't4',
      't5',
      't6',
    ]),
  ),
];