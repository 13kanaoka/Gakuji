class DictionaryExample {
  final String japanese;
  final String reading;
  final String english;

  const DictionaryExample({
    required this.japanese,
    required this.reading,
    required this.english,
  });
}

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

  final String partOfSpeech;
  final List<String> definitions;
  final bool isCommon;
  final List<String> relatedTerms;
  final String? note;
  final String kanjiMeaning;
  final List<String> kunyomi;
  final List<String> onyomi;
  final List<DictionaryExample> examples;

  bool marked;

  Term({
    required this.id,
    this.sourceId,
    required this.kanji,
    required this.reading,
    required this.meaning,
    this.partOfSpeech = 'noun',
    List<String>? definitions,
    this.isCommon = false,
    List<String>? relatedTerms,
    this.note,
    String? kanjiMeaning,
    List<String>? kunyomi,
    List<String>? onyomi,
    List<DictionaryExample>? examples,
    this.marked = false,
  }) : definitions = definitions ?? const [],
       relatedTerms = relatedTerms ?? const [],
       kanjiMeaning = kanjiMeaning ?? meaning,
       kunyomi = kunyomi ?? const [],
       onyomi = onyomi ?? const [],
       examples = examples ?? const [];

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
      id:
          id ??
          '${dictionaryTerm.sourceId ?? dictionaryTerm.id}_${DateTime.now().microsecondsSinceEpoch}',
      sourceId: dictionaryTerm.sourceId ?? dictionaryTerm.id,
      kanji: dictionaryTerm.kanji,
      reading: dictionaryTerm.reading,
      meaning: dictionaryTerm.meaning,
      partOfSpeech: dictionaryTerm.partOfSpeech,
      definitions: dictionaryTerm.definitions,
      isCommon: dictionaryTerm.isCommon,
      relatedTerms: dictionaryTerm.relatedTerms,
      note: dictionaryTerm.note,
      kanjiMeaning: dictionaryTerm.kanjiMeaning,
      kunyomi: dictionaryTerm.kunyomi,
      onyomi: dictionaryTerm.onyomi,
      examples: dictionaryTerm.examples,
      marked: marked,
    );
  }

  List<String> get displayDefinitions {
    if (definitions.isNotEmpty) {
      return definitions;
    }

    return meaning
        .split('/')
        .map((definition) => definition.trim())
        .where((definition) => definition.isNotEmpty)
        .toList();
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
    String? partOfSpeech,
    List<String>? definitions,
    bool? isCommon,
    List<String>? relatedTerms,
    String? note,
    String? kanjiMeaning,
    List<String>? kunyomi,
    List<String>? onyomi,
    List<DictionaryExample>? examples,
    bool? marked,
  }) {
    return Term(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      kanji: kanji ?? this.kanji,
      reading: reading ?? this.reading,
      meaning: meaning ?? this.meaning,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      definitions: definitions ?? this.definitions,
      isCommon: isCommon ?? this.isCommon,
      relatedTerms: relatedTerms ?? this.relatedTerms,
      note: note ?? this.note,
      kanjiMeaning: kanjiMeaning ?? this.kanjiMeaning,
      kunyomi: kunyomi ?? this.kunyomi,
      onyomi: onyomi ?? this.onyomi,
      examples: examples ?? this.examples,
      marked: marked ?? this.marked,
    );
  }
}
