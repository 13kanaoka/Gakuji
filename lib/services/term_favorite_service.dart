import '../data/deck_data.dart';
import '../data/dictionary_data.dart';
import '../models/term.dart';

class TermFavoriteService {
  static String sourceIdFor(Term term) => term.sourceId ?? term.id;

  static bool toggle(Term term) {
    final nextMarked = !term.marked;
    setMarked(term, nextMarked);
    return nextMarked;
  }

  static void setMarked(Term term, bool marked) {
    final sourceId = sourceIdFor(term);

    term.marked = marked;

    for (final dictionaryTerm in dictionaryWords) {
      if (dictionaryTerm.id == sourceId ||
          dictionaryTerm.sourceId == sourceId) {
        dictionaryTerm.marked = marked;
      }
    }

    for (final deck in decks) {
      for (final deckTerm in deck.terms) {
        if (sourceIdFor(deckTerm) == sourceId) {
          deckTerm.marked = marked;
        }
      }
    }
  }
}
