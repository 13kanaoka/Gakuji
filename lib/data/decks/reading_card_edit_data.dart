import 'dart:convert';

import 'package:gakuji/domain/term.dart';

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

  /// User-controlled crop/position settings for the reading-card photo.
  /// Scale is relative to the default cover size; values below 1 can reveal more
  /// of the original photo, while offsets are normalized to
  /// the available pan range on each axis (-1 to 1).
  final double photoScale;
  final double photoOffsetX;
  final double photoOffsetY;

  const ReadingCardEditData({
    required this.deckId,
    required this.termId,
    required this.sourceId,
    required this.selectedGlosses,
    required this.selectedExampleKeys,
    required this.note,
    required this.photoEnabled,
    required this.photoPath,
    this.photoScale = 1.0,
    this.photoOffsetX = 0.0,
    this.photoOffsetY = 0.0,
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
      photoScale: 1.0,
      photoOffsetX: 0.0,
      photoOffsetY: 0.0,
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
      photoScale: _doubleFromJson(json['photoScale'], fallback: 1.0)
          .clamp(0.75, 3.0)
          .toDouble(),
      photoOffsetX: _doubleFromJson(json['photoOffsetX'])
          .clamp(-1.0, 1.0)
          .toDouble(),
      photoOffsetY: _doubleFromJson(json['photoOffsetY'])
          .clamp(-1.0, 1.0)
          .toDouble(),
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
    double? photoScale,
    double? photoOffsetX,
    double? photoOffsetY,
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
      photoScale: (photoScale ?? this.photoScale).clamp(0.75, 3.0).toDouble(),
      photoOffsetX:
          (photoOffsetX ?? this.photoOffsetX).clamp(-1.0, 1.0).toDouble(),
      photoOffsetY:
          (photoOffsetY ?? this.photoOffsetY).clamp(-1.0, 1.0).toDouble(),
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
      'photoScale': photoScale,
      'photoOffsetX': photoOffsetX,
      'photoOffsetY': photoOffsetY,
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

  static double _doubleFromJson(
    dynamic value, {
    double fallback = 0.0,
  }) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
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