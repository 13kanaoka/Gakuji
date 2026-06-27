class DictionaryExample {
  final String japanese;
  final String reading;
  final String english;

  const DictionaryExample({
    required this.japanese,
    required this.reading,
    required this.english,
  });

  factory DictionaryExample.fromJson(Map<String, dynamic> json) {
    return DictionaryExample(
      japanese: json['japanese']?.toString() ?? '',
      reading: json['reading']?.toString() ?? '',
      english: json['english']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'japanese': japanese,
      'reading': reading,
      'english': english,
    };
  }
}

class KanjiCompound {
  final String kanji;
  final String reading;
  final String meaning;

  /// Optional dictionary term ID.
  ///
  /// If this points to a real dictionary term, the kanji detail page can
  /// open the normal dictionary detail page for this compound later.
  final String? termId;

  const KanjiCompound({
    required this.kanji,
    required this.reading,
    required this.meaning,
    this.termId,
  });

  factory KanjiCompound.fromJson(Map<String, dynamic> json) {
    return KanjiCompound(
      kanji: json['kanji']?.toString() ?? '',
      reading: json['reading']?.toString() ?? '',
      meaning: json['meaning']?.toString() ?? '',
      termId: _nullableString(json['termId']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kanji': kanji,
      'reading': reading,
      'meaning': meaning,
      if (termId != null) 'termId': termId,
    };
  }
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

  /// Kanji-detail data.
  ///
  /// These are optional so normal word entries can still use the same Term
  /// model without needing kanji-only data.
  final List<String> nanori;
  final int? strokeCount;
  final int? grade;
  final String? jlptLevel;
  final int? frequency;
  final String? radical;
  final List<String> similarKanji;
  final List<KanjiCompound> compounds;

  /// Star/focus-study marker for copied deck terms.
  ///
  /// This should not control the dictionary heart. The dictionary heart is
  /// based on whether the term has been saved to a deck.
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
    List<String>? nanori,
    this.strokeCount,
    this.grade,
    this.jlptLevel,
    this.frequency,
    this.radical,
    List<String>? similarKanji,
    List<KanjiCompound>? compounds,
    this.marked = false,
  })  : definitions = definitions ?? const [],
        relatedTerms = relatedTerms ?? const [],
        kanjiMeaning = kanjiMeaning ?? meaning,
        kunyomi = kunyomi ?? const [],
        onyomi = onyomi ?? const [],
        examples = examples ?? const [],
        nanori = nanori ?? const [],
        similarKanji = similarKanji ?? const [],
        compounds = compounds ?? const [];

  factory Term.fromJson(Map<String, dynamic> json) {
    return Term(
      id: json['id']?.toString() ?? '',
      sourceId: _nullableString(json['sourceId']),
      kanji: json['kanji']?.toString() ?? '',
      reading: json['reading']?.toString() ?? '',
      meaning: json['meaning']?.toString() ?? '',
      partOfSpeech: json['partOfSpeech']?.toString() ?? 'noun',
      definitions: _stringList(json['definitions']),
      isCommon: json['isCommon'] == true,
      relatedTerms: _stringList(json['relatedTerms']),
      note: _nullableString(json['note']),
      kanjiMeaning: json['kanjiMeaning']?.toString(),
      kunyomi: _stringList(json['kunyomi']),
      onyomi: _stringList(json['onyomi']),
      examples: _dictionaryExamples(json['examples']),
      nanori: _stringList(json['nanori']),
      strokeCount: _nullableInt(json['strokeCount']),
      grade: _nullableInt(json['grade']),
      jlptLevel: _nullableString(json['jlptLevel']),
      frequency: _nullableInt(json['frequency']),
      radical: _nullableString(json['radical']),
      similarKanji: _stringList(json['similarKanji']),
      compounds: _kanjiCompounds(json['compounds']),
      marked: json['marked'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (sourceId != null) 'sourceId': sourceId,
      'kanji': kanji,
      'reading': reading,
      'meaning': meaning,
      'partOfSpeech': partOfSpeech,
      'definitions': definitions,
      'isCommon': isCommon,
      'relatedTerms': relatedTerms,
      if (note != null) 'note': note,
      'kanjiMeaning': kanjiMeaning,
      'kunyomi': kunyomi,
      'onyomi': onyomi,
      'examples': examples.map((example) => example.toJson()).toList(),
      'nanori': nanori,
      if (strokeCount != null) 'strokeCount': strokeCount,
      if (grade != null) 'grade': grade,
      if (jlptLevel != null) 'jlptLevel': jlptLevel,
      if (frequency != null) 'frequency': frequency,
      if (radical != null) 'radical': radical,
      'similarKanji': similarKanji,
      'compounds': compounds.map((compound) => compound.toJson()).toList(),
      'marked': marked,
    };
  }

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
      partOfSpeech: dictionaryTerm.partOfSpeech,
      definitions: dictionaryTerm.definitions,
      isCommon: dictionaryTerm.isCommon,
      relatedTerms: dictionaryTerm.relatedTerms,
      note: dictionaryTerm.note,
      kanjiMeaning: dictionaryTerm.kanjiMeaning,
      kunyomi: dictionaryTerm.kunyomi,
      onyomi: dictionaryTerm.onyomi,
      examples: dictionaryTerm.examples,
      nanori: dictionaryTerm.nanori,
      strokeCount: dictionaryTerm.strokeCount,
      grade: dictionaryTerm.grade,
      jlptLevel: dictionaryTerm.jlptLevel,
      frequency: dictionaryTerm.frequency,
      radical: dictionaryTerm.radical,
      similarKanji: dictionaryTerm.similarKanji,
      compounds: dictionaryTerm.compounds,
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

  /// Helps determine whether a term has enough real kanji data to open the
  /// kanji dictionary detail page.
  bool get hasKanjiDetails {
    return kunyomi.isNotEmpty ||
        onyomi.isNotEmpty ||
        nanori.isNotEmpty ||
        strokeCount != null ||
        grade != null ||
        jlptLevel != null ||
        frequency != null ||
        radical != null ||
        similarKanji.isNotEmpty ||
        compounds.isNotEmpty;
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
    List<String>? nanori,
    int? strokeCount,
    int? grade,
    String? jlptLevel,
    int? frequency,
    String? radical,
    List<String>? similarKanji,
    List<KanjiCompound>? compounds,
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
      nanori: nanori ?? this.nanori,
      strokeCount: strokeCount ?? this.strokeCount,
      grade: grade ?? this.grade,
      jlptLevel: jlptLevel ?? this.jlptLevel,
      frequency: frequency ?? this.frequency,
      radical: radical ?? this.radical,
      similarKanji: similarKanji ?? this.similarKanji,
      compounds: compounds ?? this.compounds,
      marked: marked ?? this.marked,
    );
  }
}

String? _nullableString(dynamic value) {
  if (value == null) return null;

  final text = value.toString().trim();

  return text.isEmpty ? null : text;
}

int? _nullableInt(dynamic value) {
  if (value == null) return null;

  if (value is int) return value;

  return int.tryParse(value.toString());
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];

  return value.map((item) => item.toString()).toList();
}

List<DictionaryExample> _dictionaryExamples(dynamic value) {
  if (value is! List) return const [];

  return value
      .whereType<Map<String, dynamic>>()
      .map(DictionaryExample.fromJson)
      .toList();
}

List<KanjiCompound> _kanjiCompounds(dynamic value) {
  if (value is! List) return const [];

  return value
      .whereType<Map<String, dynamic>>()
      .map(KanjiCompound.fromJson)
      .toList();
}