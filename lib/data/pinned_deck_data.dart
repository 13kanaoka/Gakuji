import '../models/deck.dart';

const int maxPinnedDecks = 3;

final Set<String> pinnedDeckIds = <String>{};

bool isDeckPinned(Deck deck) {
  return pinnedDeckIds.contains(deck.id);
}

List<Deck> pinnedDecksFrom(List<Deck> decks) {
  final decksById = <String, Deck>{
    for (final deck in decks) deck.id: deck,
  };

  return pinnedDeckIds
      .map((deckId) => decksById[deckId])
      .whereType<Deck>()
      .take(maxPinnedDecks)
      .toList();
}

bool canPinMoreDecks() {
  return pinnedDeckIds.length < maxPinnedDecks;
}