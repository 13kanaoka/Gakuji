class Term {
  /// Unique ID for this specific term/card.
  ///
  /// For dictionary terms, this is the dictionary term ID.
  /// For copied deck terms, this should be a unique deck-card ID.
  final String id;

  /// Original dictionary term ID.
  ///
  /// This stays null for dictionary terms.
  /// When a term is copied into a deck, this points back to the original
  /// dictionary term ID so the dictionary can still check whether the term
  /// has already been saved.
  final String? sourceId;

  final String kanji;
  final String reading;
  final String meaning;

  bool marked;

  Term({
    required this.id,
    this.sourceId,
    required this.kanji,
    required this.reading,
    required this.meaning,
    this.marked = false,
  });

  /// Creates an independent deck-owned copy of a dictionary term.
  ///
  /// The copied term gets its own unique ID, while sourceId keeps track of
  /// the original dictionary term ID.
  factory Term.deckCopyFrom(
    Term dictionaryTerm, {
    String? id,
    bool marked = false,
  }) {
    return Term(
      id: id ??
          '${dictionaryTerm.sourceId ?? dictionaryTerm.id}_${DateTime.now().microsecondsSinceEpoch}',
      sourceId: dictionaryTerm.sourceId ?? dictionaryTerm.id,
      kanji: dictionaryTerm.kanji,
      reading: dictionaryTerm.reading,
      meaning: dictionaryTerm.meaning,
      marked: marked,
    );
  }

  /// Helps distinguish copied deck terms from original dictionary terms.
  bool get isDeckCopy => sourceId != null;

  /// Helps debugging + stable UI identity.
  @override
  String toString() {
    return 'Term(id: $id, sourceId: $sourceId, kanji: $kanji, reading: $reading, meaning: $meaning, marked: $marked)';
  }

  /// Safe copying for future persistence/state management.
  Term copyWith({
    String? id,
    String? sourceId,
    String? kanji,
    String? reading,
    String? meaning,
    bool? marked,
  }) {
    return Term(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      kanji: kanji ?? this.kanji,
      reading: reading ?? this.reading,
      meaning: meaning ?? this.meaning,
      marked: marked ?? this.marked,
    );
  }
}