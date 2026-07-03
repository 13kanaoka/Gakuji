import 'dart:convert';

import '../models/term.dart';

class ReadingCardEditData {
  static const String storagePrefix = 'gakuji_reading_card_edit';

  final String deckId;
  final String termId;
  final String sourceId;

  /// Ordered gloss text. These are card-specific, so users can choose/reorder
  /// glosses differently in different decks.
  final List<String> selectedGlosses;

  /// Ordered example keys. We store keys instead of full examples so the card
  /// can reconnect to the term's current example data.
  final List<String> selectedExampleKeys;

  /// Card-specific note. This is separate from dictionary notes.
  final String note;

  /// Photo is optional. The slot can be enabled before a real photo is picked.
  final bool photoEnabled;
  final String? photoPath;

  const ReadingCardEditData({
    required this.deckId,
    required this.termId,
    required this.sourceId,
    required this.selectedGlosses,
    required this.selectedExampleKeys,
    required this.note,
    required this.photoEnabled,
    required this.photoPath,
  });

  factory ReadingCardEditData.empty({
    required String deckId,
    required String termId,
    required String sourceId,
  }) {
    return ReadingCardEditData(
      deckId: deckId,
      termId: termId,
      sourceId: sourceId,
      selectedGlosses: const [],
      selectedExampleKeys: const [],
      note: '',
      photoEnabled: false,
      photoPath: null,
    );
  }

  factory ReadingCardEditData.fromJson(Map<String, dynamic> json) {
    return ReadingCardEditData(
      deckId: json['deckId'] as String? ?? '',
      termId: json['termId'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      selectedGlosses: _stringListFromJson(json['selectedGlosses']),
      selectedExampleKeys: _stringListFromJson(json['selectedExampleKeys']),
      note: json['note'] as String? ?? '',
      photoEnabled: json['photoEnabled'] as bool? ?? false,
      photoPath: json['photoPath'] as String?,
    );
  }

  ReadingCardEditData copyWith({
    String? deckId,
    String? termId,
    String? sourceId,
    List<String>? selectedGlosses,
    List<String>? selectedExampleKeys,
    String? note,
    bool? photoEnabled,
    String? photoPath,
    bool clearPhotoPath = false,
  }) {
    return ReadingCardEditData(
      deckId: deckId ?? this.deckId,
      termId: termId ?? this.termId,
      sourceId: sourceId ?? this.sourceId,
      selectedGlosses: selectedGlosses ?? this.selectedGlosses,
      selectedExampleKeys: selectedExampleKeys ?? this.selectedExampleKeys,
      note: note ?? this.note,
      photoEnabled: photoEnabled ?? this.photoEnabled,
      photoPath: clearPhotoPath ? null : photoPath ?? this.photoPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deckId': deckId,
      'termId': termId,
      'sourceId': sourceId,
      'selectedGlosses': selectedGlosses,
      'selectedExampleKeys': selectedExampleKeys,
      'note': note,
      'photoEnabled': photoEnabled,
      'photoPath': photoPath,
    };
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }

  static ReadingCardEditData fromJsonString(String value) {
    final decoded = jsonDecode(value);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid reading card edit data');
    }

    return ReadingCardEditData.fromJson(decoded);
  }

  static String preferenceKeyFor({
    required String deckId,
    required String termId,
  }) {
    return '${storagePrefix}_${deckId}_$termId';
  }

  static String sourceIdFor(Term term) {
    return term.sourceId ?? term.id;
  }

  static String exampleKeyFor(DictionaryExample example) {
    return jsonEncode([
      example.japanese,
      example.english,
    ]);
  }

  static List<DictionaryExample> examplesFromKeys({
    required List<DictionaryExample> examples,
    required List<String> selectedExampleKeys,
  }) {
    if (selectedExampleKeys.isEmpty) return const [];

    final examplesByKey = <String, DictionaryExample>{
      for (final example in examples) exampleKeyFor(example): example,
    };

    return selectedExampleKeys
        .map((key) => examplesByKey[key])
        .whereType<DictionaryExample>()
        .toList();
  }

  static List<String> keysFromExamples(List<DictionaryExample> examples) {
    return examples.map(exampleKeyFor).toList();
  }

  static List<String> _stringListFromJson(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}