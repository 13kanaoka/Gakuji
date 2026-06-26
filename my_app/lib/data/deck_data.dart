import '../models/deck.dart';

final List<Deck> decks = [
  /// 📚 DEFAULT READING DECK
  Deck(
    id: 'd1',
    name: 'Gakuji test deck',
    type: DeckType.reading,
    termIds: [
      't1',
      't2',
      't3',
      't4',
      't5',
      't6',
    ],
  ),

  /// ✍️ DEFAULT WRITING DECK
  Deck(
    id: 'd2',
    name: 'Gakuji write test',
    type: DeckType.writing,
    termIds: [
      't1',
      't2',
      't3',
      't4',
      't5',
      't6',
    ],
  ),
];