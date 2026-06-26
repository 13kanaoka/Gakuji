import '../models/term.dart';
import '../data/dictionary_data.dart';
import '../models/deck.dart';

class DefaultDecks {
  /// 📚 SAME TERM SET USED FOR BOTH MODES
  static final List<String> termIds = [
    't1',
    't2',
    't3',
    't4',
    't5',
  ];

  /// 📚 READING DEFAULT DECK
  static final Deck reading = Deck(
    id: 'default_reading',
    name: 'Gakuji Test Deck (Reading)',
    type: DeckType.reading,
    termIds: termIds,
  );

  /// ✍️ WRITING DEFAULT DECK
  static final Deck writing = Deck(
    id: 'default_writing',
    name: 'Gakuji Test Deck (Writing)',
    type: DeckType.writing,
    termIds: termIds,
  );

  /// 🧠 Helper: shared term objects
  static List<Term> get cards {
    return termIds.map(getTermById).toList();
  }
}