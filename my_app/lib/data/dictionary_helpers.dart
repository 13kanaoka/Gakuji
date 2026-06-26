import 'dictionary_data.dart';
import '../models/term.dart';

/// 🔍 Get a single Term from global dictionary
Term getTermById(String id) {
  return dictionaryWords.firstWhere(
    (t) => t.id == id,
    orElse: () => throw Exception('Term not found: $id'),
  );
}

/// 📦 Convert Deck termIds → actual Term objects
List<Term> getTermsFromDeck(List<String> ids) {
  return ids.map(getTermById).toList();
}