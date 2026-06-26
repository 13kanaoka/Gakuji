class Term {
  final String id;

  final String kanji;
  final String reading;
  final String meaning;

  bool marked;

  Term({
    required this.id,
    required this.kanji,
    required this.reading,
    required this.meaning,
    this.marked = false,
  });

  /// 🔥 Optional: helps debugging + stable UI identity
  @override
  String toString() {
    return 'Term(id: $id, kanji: $kanji, reading: $reading, meaning: $meaning, marked: $marked)';
  }

  /// 🔥 Optional: safe copying for future persistence/state management
  Term copyWith({
    String? id,
    String? kanji,
    String? reading,
    String? meaning,
    bool? marked,
  }) {
    return Term(
      id: id ?? this.id,
      kanji: kanji ?? this.kanji,
      reading: reading ?? this.reading,
      meaning: meaning ?? this.meaning,
      marked: marked ?? this.marked,
    );
  }
}