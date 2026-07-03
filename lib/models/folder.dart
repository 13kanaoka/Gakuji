class Folder {
  final String id;
  final String name;

  /// Deck IDs stored inside this folder.
  ///
  /// Folders organize existing decks, but they do not copy or own decks.
  final List<String> deckIds;

  Folder({
    required this.id,
    required this.name,
    required this.deckIds,
  });

  Folder copyWith({
    String? id,
    String? name,
    List<String>? deckIds,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      deckIds: deckIds ?? this.deckIds,
    );
  }

  @override
  String toString() {
    return 'Folder(id: $id, name: $name, decks: ${deckIds.length})';
  }
}