class WritingPrompt {
  final String id;

  /// Visible prompt shown to the user.
  ///
  /// For writing cards, this should be the term's reading/furigana.
  final String reading;

  /// Visible definition shown to the user.
  final String meaning;

  /// Hidden correct answer.
  ///
  /// This is the kanji the user is expected to write.
  final String answer;

  const WritingPrompt({
    required this.id,
    required this.reading,
    required this.meaning,
    required this.answer,
  });

  /// One writing box per kanji character.
  ///
  /// For now, writing cards are kanji-only, so the answer length gives us the
  /// number of writing slots.
  int get slotCount {
    return answer.runes.length;
  }

  @override
  String toString() {
    return 'WritingPrompt(id: $id, reading: $reading, meaning: $meaning, answer: $answer, slotCount: $slotCount)';
  }
}