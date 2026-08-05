import '../models/term.dart';
import 'dictionary_data.dart' as dictionary;

/// Looks up a term from the global dictionary by dictionary term ID.
///
/// Decks now store copied Term objects directly, so this should only be used
/// when looking up original dictionary entries.
Term getTermById(String id) {
  return dictionary.getTermById(id);
}

/// Checks whether the global dictionary contains a term with this ID.
bool dictionaryContainsTerm(String id) {
  return dictionary.dictionaryWords.any((term) => term.id == id);
}