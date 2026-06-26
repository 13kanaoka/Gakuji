enum DeckType {
  writing,
  reading,
  hybrid,
}

enum StudyMode {
  normal,
  spacedRepetition,
}

/// 🗂 Deck = container of Term IDs (NOT actual words)
class Deck {
  final String id;
  final String name;

  final DeckType type;

  /// 🔥 References to GLOBAL dictionary Terms
  final List<String> termIds;

  /// 🧠 Study progress tracking
  int lastStudyIndex;

  /// 🔀 Shuffle state per deck
  bool isShuffled;

  Deck({
    required this.id,
    required this.name,
    required this.type,
    required this.termIds,
    this.lastStudyIndex = 0,
    this.isShuffled = false,
  });

  /// 🧠 Helpful copy method (needed later for updates + persistence)
  Deck copyWith({
    String? id,
    String? name,
    DeckType? type,
    List<String>? termIds,
    int? lastStudyIndex,
    bool? isShuffled,
  }) {
    return Deck(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      termIds: termIds ?? this.termIds,
      lastStudyIndex: lastStudyIndex ?? this.lastStudyIndex,
      isShuffled: isShuffled ?? this.isShuffled,
    );
  }

  /// 🧠 Debug helper
  @override
  String toString() {
    return 'Deck(id: $id, name: $name, terms: ${termIds.length}, progress: $lastStudyIndex, shuffled: $isShuffled)';
  }
}