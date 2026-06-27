import '../models/term.dart';

/// GLOBAL DICTIONARY
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
    partOfSpeech: 'noun',
    definitions: const [
      'moon',
      'month',
      'moonlight',
      '(a) moon; natural satellite',
    ],
    isCommon: true,
    relatedTerms: const ['衛星'],
    kanjiMeaning: 'month, moon',
    kunyomi: const ['つき'],
    onyomi: const ['ゲツ', 'ガツ'],
    examples: const [
      DictionaryExample(
        japanese: 'どうして月は夜輝くのか。',
        reading: 'どうして つき は よる かがやく のか。',
        english: 'How does the moon shine at night?',
      ),
      DictionaryExample(
        japanese: '大統領はその月にフランスを訪れることになっていました。',
        reading: 'だいとうりょう は その つき に フランス を おとずれる こと に なっていました。',
        english: 'The president was visiting France that month.',
      ),
      DictionaryExample(
        japanese: '夜になると彼女はお月様をながめました。',
        reading: 'よる に なる と かのじょ は おつきさま を ながめました。',
        english: 'When night fell, she watched the moon.',
      ),
    ],
  ),
  Term(
    id: 't2',
    kanji: '日',
    reading: 'ひ',
    meaning: 'sun / day',
    partOfSpeech: 'noun',
    definitions: const ['sun', 'day'],
    isCommon: true,
    kanjiMeaning: 'day, sun',
    kunyomi: const ['ひ', 'か'],
    onyomi: const ['ニチ', 'ジツ'],
  ),
  Term(
    id: 't3',
    kanji: '水',
    reading: 'みず',
    meaning: 'water',
    partOfSpeech: 'noun',
    definitions: const ['water'],
    isCommon: true,
    kanjiMeaning: 'water',
    kunyomi: const ['みず'],
    onyomi: const ['スイ'],
  ),
  Term(
    id: 't4',
    kanji: '火',
    reading: 'ひ',
    meaning: 'fire',
    partOfSpeech: 'noun',
    definitions: const ['fire'],
    kanjiMeaning: 'fire',
    kunyomi: const ['ひ'],
    onyomi: const ['カ'],
  ),
  Term(
    id: 't5',
    kanji: '木',
    reading: 'き',
    meaning: 'tree / wood',
    partOfSpeech: 'noun',
    definitions: const ['tree', 'wood'],
    kanjiMeaning: 'tree, wood',
    kunyomi: const ['き'],
    onyomi: const ['モク', 'ボク'],
  ),
  Term(
    id: 't6',
    kanji: '火曜日',
    reading: 'かようび',
    meaning: 'Tuesday',
    partOfSpeech: 'noun',
    definitions: const ['Tuesday'],
    isCommon: true,
    kanjiMeaning: 'Tuesday',
    kunyomi: const ['か', 'ひ'],
    onyomi: const ['カ', 'ヨウ'],
  ),
];

/// Looks up an original dictionary term by dictionary ID.
Term getTermById(String id) {
  return dictionaryWords.firstWhere(
    (term) => term.id == id,
    orElse: () => throw Exception('Term not found: $id'),
  );
}