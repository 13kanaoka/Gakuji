import '../models/term.dart';

/// 📚 GLOBAL DICTIONARY (single source of truth)
/// All terms exist here once and are referenced by Decks via termIds
final List<Term> dictionaryWords = [
  Term(
    id: 't1',
    kanji: '月',
    reading: 'つき',
    meaning: 'moon',
  ),
  Term(
    id: 't2',
    kanji: '日',
    reading: 'ひ',
    meaning: 'sun / day',
  ),
  Term(
    id: 't3',
    kanji: '水',
    reading: 'みず',
    meaning: 'water',
  ),
  Term(
    id: 't4',
    kanji: '火',
    reading: 'ひ',
    meaning: 'fire',
  ),
  Term(
    id: 't5',
    kanji: '木',
    reading: 'き',
    meaning: 'tree / wood',
  ),
  Term(
    id: 't6',
    kanji: '火曜日',
    reading: 'かようび',
    meaning: 'Tuesday',
 ),
];

/// 🔍 FAST LOOKUP (IMPORTANT FOR PERFORMANCE)
Term getTermById(String id) {
  return dictionaryWords.firstWhere(
    (t) => t.id == id,
    orElse: () => throw Exception('Term not found: $id'),
  );
}

/// 📦 Convert deck termIds → actual Term objects
List<Term> getTermsFromIds(List<String> ids) {
  return ids.map(getTermById).toList();
}