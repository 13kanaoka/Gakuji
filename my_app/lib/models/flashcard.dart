/// ⚠️ LEGACY FILE (NO LONGER USED)
///
/// Flashcard system has been replaced by:
/// ✔ Term (global dictionary system)
/// ✔ Deck.termIds
/// ✔ dictionary_data.dart

@Deprecated('Use Term instead')
class Flashcard {
  final String front;
  final String back;

  const Flashcard({
    required this.front,
    required this.back,
  });
}