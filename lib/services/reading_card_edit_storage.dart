import 'package:shared_preferences/shared_preferences.dart';

import '../data/reading_card_edit_data.dart';
import '../models/deck.dart';
import '../models/term.dart';

class ReadingCardEditStorage {
  const ReadingCardEditStorage._();

  static String preferenceKeyFor({required Deck deck, required Term term}) {
    return ReadingCardEditData.preferenceKeyFor(
      deckId: deck.id,
      termId: term.id,
    );
  }

  static Future<ReadingCardEditData> load({
    required Deck deck,
    required Term term,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = preferenceKeyFor(deck: deck, term: term);

    final savedValue = prefs.getString(key);

    if (savedValue == null || savedValue.trim().isEmpty) {
      return ReadingCardEditData.empty(
        deckId: deck.id,
        termId: term.id,
        sourceId: ReadingCardEditData.sourceIdFor(term),
      );
    }

    try {
      final savedData = ReadingCardEditData.fromJsonString(savedValue);

      return savedData.copyWith(
        deckId: deck.id,
        termId: term.id,
        sourceId: ReadingCardEditData.sourceIdFor(term),
      );
    } catch (_) {
      await prefs.remove(key);

      return ReadingCardEditData.empty(
        deckId: deck.id,
        termId: term.id,
        sourceId: ReadingCardEditData.sourceIdFor(term),
      );
    }
  }

  static Future<void> save(ReadingCardEditData data) async {
    final prefs = await SharedPreferences.getInstance();
    final key = ReadingCardEditData.preferenceKeyFor(
      deckId: data.deckId,
      termId: data.termId,
    );

    await prefs.setString(key, data.toJsonString());
  }

  static Future<void> delete({required Deck deck, required Term term}) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(preferenceKeyFor(deck: deck, term: term));
  }

  static Future<bool> hasSavedEdit({
    required Deck deck,
    required Term term,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.containsKey(preferenceKeyFor(deck: deck, term: term));
  }
}
