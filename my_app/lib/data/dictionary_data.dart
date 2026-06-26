import '../models/term.dart';

/// 📚 GLOBAL DICTIONARY
///
/// These are the original dictionary entries.
/// Decks should not store references to these objects directly.
/// When a term is saved to a deck, the term should be copied into that deck
/// with its own unique card ID and a sourceId pointing back to the dictionary ID.
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

/// Looks up an original dictionary term by dictionary ID.
Term getTermById(String id) {
  return dictionaryWords.firstWhere(
    (term) => term.id == id,
    orElse: () => throw Exception('Term not found: $id'),
  );
}