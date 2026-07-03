import '../models/deck.dart';

const int maxPinnedDecks = 3;

final Set<String> pinnedDeckIds = <String>{};

bool isDeckPinned(Deck deck) {
  return pinnedDeckIds.contains(deck.id);
}

List<Deck> pinnedDecksFrom(List<Deck> decks) {
  return decks.where(isDeckPinned).take(maxPinnedDecks).toList();
}

bool canPinMoreDecks() {
  return pinnedDeckIds.length < maxPinnedDecks;
}