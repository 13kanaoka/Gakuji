import '../models/deck.dart';
import '../models/term.dart';
import 'dictionary_data.dart';

class DefaultDecks {
  /// 📚 SAME DICTIONARY SOURCE SET USED FOR BOTH MODES
  static final List<String> sourceIds = [
    't1',
    't2',
    't3',
    't4',
    't5',
  ];

  static List<Term> _deckCopies(String deckId) {
    return sourceIds.map((sourceId) {
      final dictionaryTerm = getTermById(sourceId);

      return Term.deckCopyFrom(
        dictionaryTerm,
        id: '${deckId}_$sourceId',
      );
    }).toList();
  }

  /// 📚 READING DEFAULT DECK
  static final Deck reading = Deck(
    id: 'default_reading',
    name: 'Gakuji Test Deck (Reading)',
    type: DeckType.reading,
    terms: _deckCopies('default_reading'),
  );

  /// ✍️ WRITING DEFAULT DECK
  static final Deck writing = Deck(
    id: 'default_writing',
    name: 'Gakuji Test Deck (Writing)',
    type: DeckType.writing,
    terms: _deckCopies('default_writing'),
  );

  /// 🧠 Helper: original dictionary terms
  static List<Term> get dictionaryTerms {
    return sourceIds.map(getTermById).toList();
  }
}