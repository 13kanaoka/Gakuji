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
    return {'japanese': japanese, 'reading': reading, 'english': english};
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

  /// Main kanji/spelling shown for this word.
  ///
  /// For kana-only words like する or から, this can be empty or the same as
  /// [reading].
  final String kanji;

  final String reading;
  final String meaning;

  /// Alternative kanji/spellings from the dictionary source.
  ///
  /// Example:
  /// 暑い with alternatives 熱い and 厚い can display as:
  /// あつい【暑い・熱い・厚い】
  final List<String> alternativeKanji;

  final String partOfSpeech;

  /// Raw dictionary definitions/glosses.
  ///
  /// This can contain a lot of JMdict-style glosses. UI should usually use
  /// [displayDefinitions] or [cardDefinitions] instead of showing this whole
  /// list directly.
  final List<String> definitions;

  /// Future card customization.
  ///
  /// These indexes point into [learnerDefinitions]. If empty, the card uses
  /// the default top definitions.
  final List<int> selectedDefinitionIndexes;

  /// Default number of simplified gloss groups to show on deck cards.
  ///
  /// This keeps normal cards simple while preserving the full dictionary data
  /// for later advanced settings.
  final int defaultCardDefinitionLimit;

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
  /// This should not control the dictionary save button. The dictionary save
  /// button is based on whether the term has been saved to a deck.
  bool marked;

  Term({
    required this.id,
    this.sourceId,
    required this.kanji,
    required this.reading,
    required this.meaning,
    List<String>? alternativeKanji,
    this.partOfSpeech = 'noun',
    List<String>? definitions,
    List<int>? selectedDefinitionIndexes,
    this.defaultCardDefinitionLimit = 3,
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
  }) : alternativeKanji = _cleanSpellingList(
         alternativeKanji ?? const [],
         primarySpelling: kanji,
         reading: reading,
       ),
       definitions = definitions ?? const [],
       selectedDefinitionIndexes = selectedDefinitionIndexes ?? const [],
       relatedTerms = relatedTerms ?? const [],
       kanjiMeaning = kanjiMeaning ?? meaning,
       kunyomi = kunyomi ?? const [],
       onyomi = onyomi ?? const [],
       examples = examples ?? const [],
       nanori = nanori ?? const [],
       similarKanji = similarKanji ?? const [],
       compounds = compounds ?? const [];

  factory Term.fromJson(Map<String, dynamic> json) {
    final kanji = json['kanji']?.toString() ?? '';
    final reading = json['reading']?.toString() ?? '';

    final directAlternatives = _stringList(json['alternativeKanji']);
    final legacyAlternatives = _stringList(json['alternativeSpellings']);
    final spellingList = _stringList(json['kanjiSpellings']);

    final alternativeKanji = _cleanSpellingList(
      [...directAlternatives, ...legacyAlternatives, ...spellingList],
      primarySpelling: kanji,
      reading: reading,
    );

    return Term(
      id: json['id']?.toString() ?? '',
      sourceId: _nullableString(json['sourceId']),
      kanji: kanji,
      reading: reading,
      meaning: json['meaning']?.toString() ?? '',
      alternativeKanji: alternativeKanji,
      partOfSpeech: json['partOfSpeech']?.toString() ?? 'noun',
      definitions: _stringList(json['definitions']),
      selectedDefinitionIndexes: _intList(json['selectedDefinitionIndexes']),
      defaultCardDefinitionLimit:
          _nullableInt(json['defaultCardDefinitionLimit']) ?? 3,
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
      if (alternativeKanji.isNotEmpty) 'alternativeKanji': alternativeKanji,
      'partOfSpeech': partOfSpeech,
      'definitions': definitions,
      if (selectedDefinitionIndexes.isNotEmpty)
        'selectedDefinitionIndexes': selectedDefinitionIndexes,
      if (defaultCardDefinitionLimit != 3)
        'defaultCardDefinitionLimit': defaultCardDefinitionLimit,
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
      id:
          id ??
          '${dictionaryTerm.sourceId ?? dictionaryTerm.id}_${DateTime.now().microsecondsSinceEpoch}',
      sourceId: dictionaryTerm.sourceId ?? dictionaryTerm.id,
      kanji: dictionaryTerm.kanji,
      reading: dictionaryTerm.reading,
      meaning: dictionaryTerm.meaning,
      alternativeKanji: dictionaryTerm.alternativeKanji,
      partOfSpeech: dictionaryTerm.partOfSpeech,
      definitions: dictionaryTerm.definitions,
      selectedDefinitionIndexes: dictionaryTerm.selectedDefinitionIndexes,
      defaultCardDefinitionLimit: dictionaryTerm.defaultCardDefinitionLimit,
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

  /// Main + alternative kanji spellings for display.
  ///
  /// This excludes kana-only spellings and duplicates.
  List<String> get kanjiSpellings {
    return _cleanSpellingList(
      [kanji, ...alternativeKanji],
      primarySpelling: '',
      reading: reading,
    );
  }

  /// Text that should appear inside Japanese corner brackets.
  ///
  /// Example:
  /// あつい【暑い・熱い・厚い】
  ///
  /// Kana-only words return an empty string, so the UI can hide the brackets.
  String get kanjiBracketText {
    return kanjiSpellings.join('・');
  }

  bool get hasKanjiBracketText {
    return kanjiBracketText.isNotEmpty;
  }

  /// Full raw definitions.
  ///
  /// This preserves the original dictionary gloss data. Use this later for
  /// advanced definition selection.
  List<String> get rawDefinitions {
    if (definitions.isNotEmpty) {
      return _cleanDefinitionList(definitions);
    }

    return _cleanDefinitionList(meaning.split('/'));
  }

  /// Learner-facing definitions.
  ///
  /// This groups long gloss lists into fewer rows so entries like する do not
  /// flood the dictionary detail page with too many tiny meanings.
  List<String> get learnerDefinitions {
    final raw = rawDefinitions;

    if (raw.isEmpty) return const [];

    if (raw.length <= 4) {
      return raw;
    }

    if (raw.length <= 8) {
      return _groupDefinitions(raw, groupSize: 2, maxGroups: 4);
    }

    return _groupDefinitions(raw, groupSize: 3, maxGroups: 4);
  }

  /// Primary definitions shown in dictionary UI.
  ///
  /// This intentionally uses the simplified learner layer instead of raw
  /// JMdict glosses.
  List<String> get displayDefinitions {
    return learnerDefinitions;
  }

  /// Definitions shown on the back of deck cards.
  ///
  /// By default, this uses the top 3 learner definitions. Later, advanced
  /// card settings can populate [selectedDefinitionIndexes] to customize this.
  List<String> get cardDefinitions {
    final learner = learnerDefinitions;

    if (learner.isEmpty) return const [];

    final selected = selectedDefinitionIndexes
        .where((index) => index >= 0 && index < learner.length)
        .map((index) => learner[index])
        .toList();

    if (selected.isNotEmpty) {
      return selected;
    }

    final limit = defaultCardDefinitionLimit <= 0
        ? 3
        : defaultCardDefinitionLimit;

    return learner.take(limit).toList();
  }

  /// One-line card meaning.
  ///
  /// Useful for simple card backs or compact previews.
  String get cardMeaning {
    final definitions = cardDefinitions;

    if (definitions.isEmpty) return meaning;

    return definitions.join('; ');
  }

  /// Whether there is extra raw dictionary data hidden behind the learner view.
  bool get hasMoreDefinitions {
    return rawDefinitions.length > learnerDefinitions.length;
  }

  int get hiddenDefinitionCount {
    final hidden = rawDefinitions.length - learnerDefinitions.length;

    return hidden < 0 ? 0 : hidden;
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
    List<String>? alternativeKanji,
    String? partOfSpeech,
    List<String>? definitions,
    List<int>? selectedDefinitionIndexes,
    int? defaultCardDefinitionLimit,
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
      alternativeKanji: alternativeKanji ?? this.alternativeKanji,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      definitions: definitions ?? this.definitions,
      selectedDefinitionIndexes:
          selectedDefinitionIndexes ?? this.selectedDefinitionIndexes,
      defaultCardDefinitionLimit:
          defaultCardDefinitionLimit ?? this.defaultCardDefinitionLimit,
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

List<int> _intList(dynamic value) {
  if (value is! List) return const [];

  return value.map(_nullableInt).whereType<int>().toList();
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

List<String> _cleanDefinitionList(Iterable<dynamic> values) {
  final cleaned = <String>[];
  final seen = <String>{};

  for (final value in values) {
    final definition = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

    if (definition.isEmpty) continue;

    final key = definition.toLowerCase();

    if (seen.contains(key)) continue;

    seen.add(key);
    cleaned.add(definition);
  }

  return cleaned;
}

List<String> _cleanSpellingList(
  Iterable<dynamic> values, {
  required String primarySpelling,
  required String reading,
}) {
  final cleaned = <String>[];
  final seen = <String>{};

  final normalizedPrimary = primarySpelling.trim();
  final normalizedReading = reading.trim();

  for (final value in values) {
    final spelling = value.toString().replaceAll(RegExp(r'\s+'), '').trim();

    if (spelling.isEmpty) continue;
    if (spelling == normalizedPrimary && cleaned.isNotEmpty) continue;
    if (spelling == normalizedReading) continue;
    if (!_containsKanji(spelling)) continue;

    final key = spelling.toLowerCase();

    if (seen.contains(key)) continue;

    seen.add(key);
    cleaned.add(spelling);
  }

  return cleaned;
}

List<String> _groupDefinitions(
  List<String> definitions, {
  required int groupSize,
  required int maxGroups,
}) {
  final grouped = <String>[];

  for (var index = 0; index < definitions.length; index += groupSize) {
    if (grouped.length >= maxGroups) break;

    final group = definitions.skip(index).take(groupSize).toList();

    if (group.isEmpty) continue;

    grouped.add(group.join('; '));
  }

  return grouped;
}

bool _containsKanji(String text) {
  return RegExp(r'[\u4E00-\u9FFF]').hasMatch(text);
}
