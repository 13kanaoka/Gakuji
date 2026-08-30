class DictionaryExampleToken {
  final String surface;
  final String headword;
  final String reading;
  final String? termId;

  const DictionaryExampleToken({
    required this.surface,
    required this.headword,
    required this.reading,
    this.termId,
  });

  factory DictionaryExampleToken.fromJson(Map<String, dynamic> json) {
    return DictionaryExampleToken(
      surface: json['surface']?.toString() ?? '',
      headword: json['headword']?.toString() ?? '',
      reading: json['reading']?.toString() ?? '',
      termId: _nullableString(json['termId']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'surface': surface,
      'headword': headword,
      'reading': reading,
      if (termId != null) 'termId': termId,
    };
  }

  String get displayText {
    final cleanedSurface = surface.trim();

    if (cleanedSurface.isNotEmpty) {
      return cleanedSurface;
    }

    return headword.trim();
  }

  bool get canOpenDictionary {
    return termId != null && termId!.trim().isNotEmpty;
  }
}

class DictionaryExample {
  final String japanese;
  final String reading;
  final String english;
  final List<DictionaryExampleToken> tokens;

  const DictionaryExample({
    required this.japanese,
    required this.reading,
    required this.english,
    this.tokens = const [],
  });

  factory DictionaryExample.fromJson(Map<String, dynamic> json) {
    return DictionaryExample(
      japanese: json['japanese']?.toString() ?? '',
      reading: json['reading']?.toString() ?? '',
      english: json['english']?.toString() ?? '',
      tokens: _dictionaryExampleTokens(json['tokens']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'japanese': japanese,
      'reading': reading,
      'english': english,
      'tokens': tokens.map((token) => token.toJson()).toList(),
    };
  }
}

/// One JMdict meaning/sense belonging to a term.
///
/// A term remains one dictionary entry and one flashcard. Its senses keep the
/// glosses, examples, related terms, and part-of-speech information for each
/// distinct meaning together.
class DictionarySense {
  final int index;
  final List<String> glosses;
  final List<DictionaryExample> examples;
  final List<String> relatedTerms;
  final List<String> partOfSpeechTags;

  DictionarySense({
    required this.index,
    List<String>? glosses,
    List<DictionaryExample>? examples,
    List<String>? relatedTerms,
    List<String>? partOfSpeechTags,
  })  : glosses = _cleanDefinitionList(glosses ?? const []),
        examples = List.unmodifiable(examples ?? const []),
        relatedTerms = _cleanStringList(relatedTerms ?? const []),
        partOfSpeechTags = _cleanStringList(partOfSpeechTags ?? const []);

  factory DictionarySense.fromJson(Map<String, dynamic> json) {
    return DictionarySense(
      index: _nullableInt(json['index']) ?? 0,
      glosses: _stringList(json['glosses']),
      examples: _dictionaryExamples(json['examples']),
      relatedTerms: _stringList(json['relatedTerms']),
      partOfSpeechTags: _stringList(json['partOfSpeechTags']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'glosses': glosses,
      'examples': examples.map((example) => example.toJson()).toList(),
      'relatedTerms': relatedTerms,
      'partOfSpeechTags': partOfSpeechTags,
    };
  }

  String get displayDefinition => glosses.join('; ');

  bool get hasExamples => examples.isNotEmpty;

  DictionarySense copyWith({
    int? index,
    List<String>? glosses,
    List<DictionaryExample>? examples,
    List<String>? relatedTerms,
    List<String>? partOfSpeechTags,
  }) {
    return DictionarySense(
      index: index ?? this.index,
      glosses: glosses ?? this.glosses,
      examples: examples ?? this.examples,
      relatedTerms: relatedTerms ?? this.relatedTerms,
      partOfSpeechTags: partOfSpeechTags ?? this.partOfSpeechTags,
    );
  }
}

/// Identifies one exact gloss on a saved card.
///
/// This preserves the user's current ability to choose individual glosses,
/// while keeping each selection connected to the sense that supplies its
/// example sentences.
class GlossSelection {
  final int senseIndex;
  final int glossIndex;

  const GlossSelection({
    required this.senseIndex,
    required this.glossIndex,
  });

  factory GlossSelection.fromJson(Map<String, dynamic> json) {
    return GlossSelection(
      senseIndex: _nullableInt(json['senseIndex']) ?? 0,
      glossIndex: _nullableInt(json['glossIndex']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'senseIndex': senseIndex,
      'glossIndex': glossIndex,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is GlossSelection &&
        other.senseIndex == senseIndex &&
        other.glossIndex == glossIndex;
  }

  @override
  int get hashCode => Object.hash(senseIndex, glossIndex);
}

class KanjiStroke {
  final int number;
  final String pathData;
  final String? type;

  const KanjiStroke({
    required this.number,
    required this.pathData,
    this.type,
  });

  factory KanjiStroke.fromJson(Map<String, dynamic> json) {
    return KanjiStroke(
      number: _nullableInt(json['number']) ?? 0,
      pathData: json['path']?.toString() ?? '',
      type: _nullableString(json['type']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'path': pathData,
      if (type != null) 'type': type,
    };
  }
}

/// Ordered KanjiVG stroke data for one character.
///
/// This is loaded on demand for the kanji detail page rather than stored on
/// every saved card.
class KanjiStrokeData {
  final String character;
  final String codepoint;
  final String viewBox;
  final List<KanjiStroke> strokes;

  KanjiStrokeData({
    required this.character,
    required this.codepoint,
    required this.viewBox,
    required List<KanjiStroke> strokes,
  }) : strokes = List.unmodifiable(
          strokes.where((stroke) => stroke.pathData.trim().isNotEmpty),
        );

  int get strokeCount => strokes.length;

  bool get isEmpty => strokes.isEmpty;

  bool get isNotEmpty => strokes.isNotEmpty;
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
  /// This stays null for dictionary terms. A copied deck term points back to
  /// the original dictionary entry through this ID.
  final String? sourceId;

  /// Main kanji/spelling shown for this word.
  final String kanji;
  final String reading;
  final String meaning;

  /// Alternative kanji/spellings from the dictionary source.
  final List<String> alternativeKanji;

  /// Entry-level fallback part of speech.
  ///
  /// Sense-specific tags live inside [DictionarySense.partOfSpeechTags].
  final String partOfSpeech;

  /// The source of truth for definitions, examples, and related terms.
  ///
  /// Senses always remain children of this term. They are not separate terms
  /// and are not separate flashcards.
  final List<DictionarySense> senses;

  /// Exact glosses enabled on this saved card.
  ///
  /// An empty list means the card uses its normal default glosses.
  final List<GlossSelection> selectedGlosses;

  /// Default number of sense groups to show on deck cards.
  final int defaultCardDefinitionLimit;

  final bool isCommon;
  final String? note;
  final String kanjiMeaning;
  final List<String> kunyomi;
  final List<String> onyomi;

  /// Kanji-detail data.
  final List<String> nanori;
  final int? strokeCount;
  final int? grade;
  final String? jlptLevel;
  final int? frequency;
  final String? radical;
  final List<String> similarKanji;
  final List<KanjiCompound> compounds;

  /// Star/focus-study marker for copied deck terms.
  bool marked;

  /// Creates a term using senses as the real stored structure.
  ///
  /// The legacy [definitions], [examples], [relatedTerms], and
  /// [selectedDefinitionIndexes] arguments remain temporarily accepted so the
  /// rest of the app can be migrated in controlled steps. When [senses] is
  /// supplied, the legacy content arguments are ignored.
  factory Term({
    required String id,
    String? sourceId,
    required String kanji,
    required String reading,
    required String meaning,
    List<String>? alternativeKanji,
    String partOfSpeech = 'noun',
    List<DictionarySense>? senses,
    List<GlossSelection>? selectedGlosses,
    List<String>? definitions,
    List<int>? selectedDefinitionIndexes,
    int defaultCardDefinitionLimit = 3,
    bool isCommon = false,
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
    bool marked = false,
  }) {
    final resolvedSenses = _resolveSenses(
      senses: senses,
      legacyDefinitions: definitions,
      legacyExamples: examples,
      legacyRelatedTerms: relatedTerms,
      fallbackMeaning: meaning,
      fallbackPartOfSpeech: partOfSpeech,
    );

    final resolvedSelections = selectedGlosses != null
        ? _cleanGlossSelections(selectedGlosses, resolvedSenses)
        : _legacyIndexesToSelections(
            selectedDefinitionIndexes ?? const [],
            resolvedSenses,
          );

    return Term._internal(
      id: id,
      sourceId: sourceId,
      kanji: kanji,
      reading: reading,
      meaning: meaning,
      alternativeKanji: _cleanSpellingList(
        alternativeKanji ?? const [],
        primarySpelling: kanji,
        reading: reading,
      ),
      partOfSpeech: partOfSpeech,
      senses: resolvedSenses,
      selectedGlosses: resolvedSelections,
      defaultCardDefinitionLimit: defaultCardDefinitionLimit,
      isCommon: isCommon,
      note: note,
      kanjiMeaning: kanjiMeaning ?? meaning,
      kunyomi: List.unmodifiable(kunyomi ?? const []),
      onyomi: List.unmodifiable(onyomi ?? const []),
      nanori: List.unmodifiable(nanori ?? const []),
      strokeCount: strokeCount,
      grade: grade,
      jlptLevel: jlptLevel,
      frequency: frequency,
      radical: radical,
      similarKanji: List.unmodifiable(similarKanji ?? const []),
      compounds: List.unmodifiable(compounds ?? const []),
      marked: marked,
    );
  }

  Term._internal({
    required this.id,
    required this.sourceId,
    required this.kanji,
    required this.reading,
    required this.meaning,
    required this.alternativeKanji,
    required this.partOfSpeech,
    required this.senses,
    required this.selectedGlosses,
    required this.defaultCardDefinitionLimit,
    required this.isCommon,
    required this.note,
    required this.kanjiMeaning,
    required this.kunyomi,
    required this.onyomi,
    required this.nanori,
    required this.strokeCount,
    required this.grade,
    required this.jlptLevel,
    required this.frequency,
    required this.radical,
    required this.similarKanji,
    required this.compounds,
    required this.marked,
  });

  factory Term.fromJson(Map<String, dynamic> json) {
    final kanji = json['kanji']?.toString() ?? '';
    final reading = json['reading']?.toString() ?? '';

    final directAlternatives = _stringList(json['alternativeKanji']);
    final legacyAlternatives = _stringList(json['alternativeSpellings']);
    final spellingList = _stringList(json['kanjiSpellings']);

    final alternativeKanji = _cleanSpellingList(
      [
        ...directAlternatives,
        ...legacyAlternatives,
        ...spellingList,
      ],
      primarySpelling: kanji,
      reading: reading,
    );

    final storedSenses = _dictionarySenses(json['senses']);
    final storedSelections = _glossSelections(json['selectedGlosses']);

    return Term(
      id: json['id']?.toString() ?? '',
      sourceId: _nullableString(json['sourceId']),
      kanji: kanji,
      reading: reading,
      meaning: json['meaning']?.toString() ?? '',
      alternativeKanji: alternativeKanji,
      partOfSpeech: json['partOfSpeech']?.toString() ?? 'noun',
      senses: storedSenses.isEmpty ? null : storedSenses,
      selectedGlosses: storedSelections.isEmpty ? null : storedSelections,
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
      'senses': senses.map((sense) => sense.toJson()).toList(),
      if (selectedGlosses.isNotEmpty)
        'selectedGlosses':
            selectedGlosses.map((selection) => selection.toJson()).toList(),
      if (defaultCardDefinitionLimit != 3)
        'defaultCardDefinitionLimit': defaultCardDefinitionLimit,
      'isCommon': isCommon,
      if (note != null) 'note': note,
      'kanjiMeaning': kanjiMeaning,
      'kunyomi': kunyomi,
      'onyomi': onyomi,
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
      alternativeKanji: dictionaryTerm.alternativeKanji,
      partOfSpeech: dictionaryTerm.partOfSpeech,
      senses: dictionaryTerm.senses,
      selectedGlosses: dictionaryTerm.selectedGlosses,
      defaultCardDefinitionLimit: dictionaryTerm.defaultCardDefinitionLimit,
      isCommon: dictionaryTerm.isCommon,
      note: dictionaryTerm.note,
      kanjiMeaning: dictionaryTerm.kanjiMeaning,
      kunyomi: dictionaryTerm.kunyomi,
      onyomi: dictionaryTerm.onyomi,
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

  /// Legacy flat definition view.
  ///
  /// Existing screens can continue reading this while they are migrated. The
  /// values are derived from [senses] and are not separately stored.
  List<String> get definitions => rawDefinitions;

  /// Legacy flat example view derived from all senses.
  List<DictionaryExample> get examples {
    return List.unmodifiable(
      senses.expand((sense) => sense.examples),
    );
  }

  /// Legacy flat related-term view derived from all senses.
  List<String> get relatedTerms {
    return _cleanStringList(
      senses.expand((sense) => sense.relatedTerms),
    );
  }

  /// Legacy flat gloss indexes derived from [selectedGlosses].
  ///
  /// New card code should use [selectedGlosses] directly.
  List<int> get selectedDefinitionIndexes {
    final indexes = <int>[];
    var flatIndex = 0;

    for (final sense in senses) {
      for (var glossIndex = 0;
          glossIndex < sense.glosses.length;
          glossIndex++) {
        if (selectedGlosses.contains(
          GlossSelection(
            senseIndex: sense.index,
            glossIndex: glossIndex,
          ),
        )) {
          indexes.add(flatIndex);
        }

        flatIndex++;
      }
    }

    return indexes;
  }

  /// Main + alternative kanji spellings for display.
  List<String> get kanjiSpellings {
    return _cleanSpellingList(
      [
        kanji,
        ...alternativeKanji,
      ],
      primarySpelling: '',
      reading: reading,
    );
  }

  String get kanjiBracketText => kanjiSpellings.join('・');

  bool get hasKanjiBracketText => kanjiBracketText.isNotEmpty;

  /// Every raw gloss, flattened only for older UI and search helpers.
  List<String> get rawDefinitions {
    final glosses = _cleanDefinitionList(
      senses.expand((sense) => sense.glosses),
    );

    if (glosses.isNotEmpty) return glosses;

    return _cleanDefinitionList(meaning.split('/'));
  }

  /// One learner-facing row per sense.
  ///
  /// Synonymous glosses inside the same sense stay together instead of being
  /// incorrectly presented as separate meanings.
  List<String> get learnerDefinitions {
    return senses
        .map((sense) => sense.displayDefinition)
        .where((definition) => definition.isNotEmpty)
        .toList(growable: false);
  }

  List<String> get displayDefinitions => learnerDefinitions;

  /// Definitions shown on the back of a card.
  ///
  /// Explicit selections preserve exact gloss control. They are grouped back
  /// into their parent senses so the card's examples can come from those same
  /// meanings.
  List<String> get cardDefinitions {
    if (selectedGlosses.isNotEmpty) {
      final selectedBySense = <int, List<String>>{};

      for (final selection in selectedGlosses) {
        final sense = senseForIndex(selection.senseIndex);

        if (sense == null ||
            selection.glossIndex < 0 ||
            selection.glossIndex >= sense.glosses.length) {
          continue;
        }

        selectedBySense
            .putIfAbsent(sense.index, () => <String>[])
            .add(sense.glosses[selection.glossIndex]);
      }

      final selectedDefinitions = <String>[];

      for (final sense in senses) {
        final glosses = selectedBySense[sense.index];

        if (glosses == null || glosses.isEmpty) continue;

        selectedDefinitions.add(_cleanDefinitionList(glosses).join('; '));
      }

      if (selectedDefinitions.isNotEmpty) {
        return selectedDefinitions;
      }
    }

    final limit =
        defaultCardDefinitionLimit <= 0 ? 3 : defaultCardDefinitionLimit;

    return learnerDefinitions.take(limit).toList();
  }

  /// Examples eligible to appear on the card back.
  ///
  /// When glosses are selected, only examples from those same senses are
  /// returned. Otherwise examples follow the default senses shown on the card.
  List<DictionaryExample> get cardExamples {
    final senseIndexes = selectedGlosses.isNotEmpty
        ? selectedGlosses.map((selection) => selection.senseIndex).toSet()
        : senses
            .take(defaultCardDefinitionLimit <= 0
                ? 3
                : defaultCardDefinitionLimit)
            .map((sense) => sense.index)
            .toSet();

    return List.unmodifiable(
      senses
          .where((sense) => senseIndexes.contains(sense.index))
          .expand((sense) => sense.examples),
    );
  }

  List<DictionarySense> get selectedSenses {
    if (selectedGlosses.isEmpty) {
      final limit =
          defaultCardDefinitionLimit <= 0 ? 3 : defaultCardDefinitionLimit;
      return senses.take(limit).toList(growable: false);
    }

    final selectedIndexes =
        selectedGlosses.map((selection) => selection.senseIndex).toSet();

    return senses
        .where((sense) => selectedIndexes.contains(sense.index))
        .toList(growable: false);
  }

  DictionarySense? senseForIndex(int senseIndex) {
    for (final sense in senses) {
      if (sense.index == senseIndex) return sense;
    }

    return null;
  }

  String get cardMeaning {
    final definitions = cardDefinitions;

    if (definitions.isEmpty) return meaning;

    return definitions.join('; ');
  }

  bool get hasMoreDefinitions {
    return rawDefinitions.length > learnerDefinitions.length;
  }

  int get hiddenDefinitionCount {
    final hidden = rawDefinitions.length - learnerDefinitions.length;

    return hidden < 0 ? 0 : hidden;
  }

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

  bool get isKanjiDictionaryEntry {
    return partOfSpeech.toLowerCase() == 'kanji' || id.startsWith('kanji_');
  }

  bool get isWordDictionaryEntry => !isKanjiDictionaryEntry;

  bool get isDeckCopy => sourceId != null;

  @override
  String toString() {
    return 'Term(id: $id, sourceId: $sourceId, kanji: $kanji, reading: $reading, meaning: $meaning, senses: ${senses.length}, marked: $marked)';
  }

  Term copyWith({
    String? id,
    String? sourceId,
    String? kanji,
    String? reading,
    String? meaning,
    List<String>? alternativeKanji,
    String? partOfSpeech,
    List<DictionarySense>? senses,
    List<GlossSelection>? selectedGlosses,
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
    final isUsingLegacySenseReplacement = definitions != null ||
        examples != null ||
        relatedTerms != null ||
        selectedDefinitionIndexes != null;

    return Term(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      kanji: kanji ?? this.kanji,
      reading: reading ?? this.reading,
      meaning: meaning ?? this.meaning,
      alternativeKanji: alternativeKanji ?? this.alternativeKanji,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      senses: isUsingLegacySenseReplacement ? null : (senses ?? this.senses),
      selectedGlosses: isUsingLegacySenseReplacement
          ? null
          : (selectedGlosses ?? this.selectedGlosses),
      definitions: definitions,
      selectedDefinitionIndexes: selectedDefinitionIndexes,
      defaultCardDefinitionLimit:
          defaultCardDefinitionLimit ?? this.defaultCardDefinitionLimit,
      isCommon: isCommon ?? this.isCommon,
      relatedTerms: relatedTerms,
      note: note ?? this.note,
      kanjiMeaning: kanjiMeaning ?? this.kanjiMeaning,
      kunyomi: kunyomi ?? this.kunyomi,
      onyomi: onyomi ?? this.onyomi,
      examples: examples,
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

List<DictionaryExampleToken> _dictionaryExampleTokens(dynamic value) {
  if (value is! List) return const [];

  return value
      .whereType<Map>()
      .map(
        (item) => DictionaryExampleToken.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
      .toList();
}

List<DictionaryExample> _dictionaryExamples(dynamic value) {
  if (value is! List) return const [];

  return value
      .whereType<Map>()
      .map((item) => DictionaryExample.fromJson(
            Map<String, dynamic>.from(item),
          ))
      .toList();
}

List<DictionarySense> _dictionarySenses(dynamic value) {
  if (value is! List) return const [];

  return value
      .whereType<Map>()
      .map((item) => DictionarySense.fromJson(
            Map<String, dynamic>.from(item),
          ))
      .toList();
}

List<GlossSelection> _glossSelections(dynamic value) {
  if (value is! List) return const [];

  return value
      .whereType<Map>()
      .map((item) => GlossSelection.fromJson(
            Map<String, dynamic>.from(item),
          ))
      .toList();
}

List<KanjiCompound> _kanjiCompounds(dynamic value) {
  if (value is! List) return const [];

  return value
      .whereType<Map>()
      .map((item) => KanjiCompound.fromJson(
            Map<String, dynamic>.from(item),
          ))
      .toList();
}

List<DictionarySense> _resolveSenses({
  required List<DictionarySense>? senses,
  required List<String>? legacyDefinitions,
  required List<DictionaryExample>? legacyExamples,
  required List<String>? legacyRelatedTerms,
  required String fallbackMeaning,
  required String fallbackPartOfSpeech,
}) {
  if (senses != null && senses.isNotEmpty) {
    final cleaned = senses
        .where((sense) => sense.glosses.isNotEmpty)
        .map(
          (sense) => sense.copyWith(
            index: sense.index < 0 ? 0 : sense.index,
          ),
        )
        .toList();

    cleaned.sort((a, b) => a.index.compareTo(b.index));

    return List.unmodifiable(cleaned);
  }

  var glosses = _cleanDefinitionList(legacyDefinitions ?? const []);

  if (glosses.isEmpty) {
    glosses = _cleanDefinitionList(fallbackMeaning.split('/'));
  }

  if (glosses.isEmpty) return const [];

  return List.unmodifiable([
    DictionarySense(
      index: 0,
      glosses: glosses,
      examples: legacyExamples,
      relatedTerms: legacyRelatedTerms,
      partOfSpeechTags:
          fallbackPartOfSpeech.trim().isEmpty ? const [] : [fallbackPartOfSpeech],
    ),
  ]);
}

List<GlossSelection> _cleanGlossSelections(
  Iterable<GlossSelection> selections,
  List<DictionarySense> senses,
) {
  final cleaned = <GlossSelection>[];
  final seen = <GlossSelection>{};
  final sensesByIndex = {
    for (final sense in senses) sense.index: sense,
  };

  for (final selection in selections) {
    final sense = sensesByIndex[selection.senseIndex];

    if (sense == null) continue;
    if (selection.glossIndex < 0 ||
        selection.glossIndex >= sense.glosses.length) {
      continue;
    }
    if (!seen.add(selection)) continue;

    cleaned.add(selection);
  }

  cleaned.sort((a, b) {
    final senseComparison = a.senseIndex.compareTo(b.senseIndex);

    if (senseComparison != 0) return senseComparison;

    return a.glossIndex.compareTo(b.glossIndex);
  });

  return List.unmodifiable(cleaned);
}

List<GlossSelection> _legacyIndexesToSelections(
  Iterable<int> indexes,
  List<DictionarySense> senses,
) {
  final wanted = indexes.where((index) => index >= 0).toSet();

  if (wanted.isEmpty) return const [];

  final selections = <GlossSelection>[];
  var flatIndex = 0;

  for (final sense in senses) {
    for (var glossIndex = 0;
        glossIndex < sense.glosses.length;
        glossIndex++) {
      if (wanted.contains(flatIndex)) {
        selections.add(
          GlossSelection(
            senseIndex: sense.index,
            glossIndex: glossIndex,
          ),
        );
      }

      flatIndex++;
    }
  }

  return List.unmodifiable(selections);
}

List<String> _cleanDefinitionList(Iterable<dynamic> values) {
  final cleaned = <String>[];
  final seen = <String>{};

  for (final value in values) {
    final definition = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

    if (definition.isEmpty) continue;

    final key = definition.toLowerCase();

    if (!seen.add(key)) continue;

    cleaned.add(definition);
  }

  return List.unmodifiable(cleaned);
}

List<String> _cleanStringList(Iterable<dynamic> values) {
  final cleaned = <String>[];
  final seen = <String>{};

  for (final value in values) {
    final text = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

    if (text.isEmpty) continue;

    final key = text.toLowerCase();

    if (!seen.add(key)) continue;

    cleaned.add(text);
  }

  return List.unmodifiable(cleaned);
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

    if (!seen.add(key)) continue;

    cleaned.add(spelling);
  }

  return List.unmodifiable(cleaned);
}

bool _containsKanji(String text) {
  return RegExp(r'[\u4E00-\u9FFF]').hasMatch(text);
}
