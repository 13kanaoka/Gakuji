import 'term.dart';

enum DeckType {
  writing,
  reading,
  hybrid,
}

enum StudyMode {
  normal,
  spacedRepetition,
}

/// Deck = container of copied deck-owned Terms.
class Deck {
  final String id;
  final String name;

  final DeckType type;

  /// Independent term/card copies saved to this deck.
  ///
  /// These are separate from the global dictionary terms.
  /// Each copied term should keep a sourceId that points back to the
  /// original dictionary term ID.
  final List<Term> terms;

  /// Study progress tracking.
  int lastStudyIndex;

  /// Shuffle state per deck.
  bool isShuffled;

  Deck({
    required this.id,
    required this.name,
    required this.type,
    required this.terms,
    this.lastStudyIndex = 0,
    this.isShuffled = false,
  });

  /// Helpful copy method for updates + persistence.
  Deck copyWith({
    String? id,
    String? name,
    DeckType? type,
    List<Term>? terms,
    int? lastStudyIndex,
    bool? isShuffled,
  }) {
    return Deck(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      terms: terms ?? this.terms,
      lastStudyIndex: lastStudyIndex ?? this.lastStudyIndex,
      isShuffled: isShuffled ?? this.isShuffled,
    );
  }

  /// Debug helper.
  @override
  String toString() {
    return 'Deck(id: $id, name: $name, terms: ${terms.length}, progress: $lastStudyIndex, shuffled: $isShuffled)';
  }
}