class WritingPrompt {
  final String id;

  /// Correct written answer, e.g. 火曜日
  final String answer;

  /// Furigana / reading, e.g. かようび
  final String reading;

  /// Definition / meaning, e.g. Tuesday
  final String meaning;

  /// Number of writing slots to display
  final int slotCount;

  WritingPrompt({
    required this.id,
    required this.answer,
    required this.reading,
    required this.meaning,
    required this.slotCount,
  });
}