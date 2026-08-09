import 'dart:math' as math;

import '../models/term.dart';
import '../models/word_fusion_round.dart';

class WordFusionRoundGenerator {
  static final RegExp _kanjiOnlyPattern = RegExp(r'^[一-龯]{2,6}$');
  static final RegExp _kanjiCharacterPattern = RegExp(r'[一-龯]');

  // Used only when a small deck does not contain enough distinct kanji to
  // create a full choice grid. The target kanji always come from the deck.
  static const List<String> _fallbackDistractors = [
    '日',
    '月',
    '火',
    '水',
    '木',
    '金',
    '土',
    '山',
    '川',
    '田',
    '人',
    '口',
    '目',
    '手',
    '心',
    '学',
    '校',
    '生',
    '先',
    '時',
    '間',
    '今',
    '何',
    '本',
    '大',
    '小',
    '上',
    '下',
    '中',
    '外',
    '前',
    '後',
    '新',
    '古',
    '高',
    '長',
    '話',
    '聞',
    '見',
    '行',
  ];

  static List<WordFusionRound> buildRounds(
    List<Term> terms, {
    int choiceCount = 10,
    math.Random? random,
  }) {
    final rng = random ?? math.Random();
    final eligibleTerms = terms.where(isEligibleTerm).toList(growable: false);

    if (eligibleTerms.isEmpty) return const <WordFusionRound>[];

    final deckKanjiPool = <String>[];
    final seenDeckKanji = <String>{};

    for (final term in eligibleTerms) {
      for (final kanji in _kanjiCharacters(term.kanji.trim())) {
        if (seenDeckKanji.add(kanji)) {
          deckKanjiPool.add(kanji);
        }
      }
    }

    final rounds = eligibleTerms.map((term) {
      final word = term.kanji.trim();
      final requiredKanji = _kanjiCharacters(word);
      final choices = _buildChoices(
        requiredKanji: requiredKanji,
        deckKanjiPool: deckKanjiPool,
        choiceCount: math.max(choiceCount, requiredKanji.length),
        random: rng,
      );

      return WordFusionRound(
        termId: term.id,
        word: word,
        reading: term.reading.trim(),
        definition: _definitionFor(term),
        requiredKanji: requiredKanji,
        kanjiChoices: choices,
      );
    }).toList();

    rounds.shuffle(rng);
    return rounds;
  }

  static bool isEligibleTerm(Term term) {
    final spelling = term.kanji.trim();
    return _kanjiOnlyPattern.hasMatch(spelling);
  }

  static int eligibleTermCount(List<Term> terms) {
    return terms.where(isEligibleTerm).length;
  }

  static List<String> _kanjiCharacters(String text) {
    return _kanjiCharacterPattern
        .allMatches(text)
        .map((match) => match.group(0)!)
        .toList(growable: false);
  }

  static String _definitionFor(Term term) {
    final cardMeaning = term.cardMeaning.trim();
    if (cardMeaning.isNotEmpty) return cardMeaning;

    final meaning = term.meaning.trim();
    if (meaning.isNotEmpty) return meaning;

    return 'No definition';
  }

  static List<String> _buildChoices({
    required List<String> requiredKanji,
    required List<String> deckKanjiPool,
    required int choiceCount,
    required math.Random random,
  }) {
    final choices = List<String>.from(requiredKanji);
    final requiredSet = requiredKanji.toSet();

    final distractorCandidates = <String>[];
    final seenDistractors = <String>{};

    void addCandidate(String kanji) {
      if (requiredSet.contains(kanji)) return;
      if (seenDistractors.add(kanji)) {
        distractorCandidates.add(kanji);
      }
    }

    for (final kanji in deckKanjiPool) {
      addCandidate(kanji);
    }

    for (final kanji in _fallbackDistractors) {
      addCandidate(kanji);
    }

    distractorCandidates.shuffle(random);

    for (final distractor in distractorCandidates) {
      if (choices.length >= choiceCount) break;
      choices.add(distractor);
    }

    choices.shuffle(random);
    return choices;
  }
}
