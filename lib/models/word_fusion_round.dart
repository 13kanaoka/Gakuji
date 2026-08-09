class WordFusionRound {
  final String termId;
  final String word;
  final String reading;
  final String definition;
  final List<String> requiredKanji;
  final List<String> kanjiChoices;

  const WordFusionRound({
    required this.termId,
    required this.word,
    required this.reading,
    required this.definition,
    required this.requiredKanji,
    required this.kanjiChoices,
  });
}
