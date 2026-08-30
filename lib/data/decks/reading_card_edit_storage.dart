import 'package:shared_preferences/shared_preferences.dart';

import 'package:gakuji/data/decks/reading_card_edit_data.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/data/sync/gakuji_cloud_sync_service.dart';
import 'package:gakuji/data/sync/gakuji_user_repository.dart';

class ReadingCardEditDeckSnapshot {
  final Map<String, ReadingCardEditData> editsByTermId;
  final Set<String> savedTermIds;

  const ReadingCardEditDeckSnapshot({
    required this.editsByTermId,
    required this.savedTermIds,
  });
}

/// Reading-card customization stored in the local SQLite user database.
///
/// SharedPreferences is only consulted as a one-time migration path for cards
/// created by older Gakuji builds.
class ReadingCardEditStorage {
  const ReadingCardEditStorage._();

  static String preferenceKeyFor({
    required Deck deck,
    required Term term,
  }) {
    return ReadingCardEditData.preferenceKeyFor(
      deckId: deck.id,
      termId: term.id,
    );
  }

  /// Loads every card edit needed by one deck with a single SQLite query.
  /// Legacy SharedPreferences values are scanned in one pass only for terms
  /// that are not already present in SQLite.
  static Future<ReadingCardEditDeckSnapshot> loadDeck({
    required Deck deck,
    required List<Term> terms,
  }) async {
    final storedEdits =
        await GakujiUserRepository.loadReadingCardEditsForDeck(deck.id);
    final storedByTermId = <String, ReadingCardEditData>{
      for (final edit in storedEdits) edit.termId: edit,
    };

    final editsByTermId = <String, ReadingCardEditData>{};
    final savedTermIds = <String>{};
    final missingTerms = <Term>[];

    for (final term in terms) {
      final stored = storedByTermId[term.id];
      if (stored == null) {
        missingTerms.add(term);
        continue;
      }

      editsByTermId[term.id] = stored.copyWith(
        deckId: deck.id,
        termId: term.id,
        sourceId: ReadingCardEditData.sourceIdFor(term),
      );
      savedTermIds.add(term.id);
    }

    if (missingTerms.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      var migratedAny = false;

      for (final term in missingTerms) {
        final key = preferenceKeyFor(deck: deck, term: term);
        final savedValue = prefs.getString(key);

        if (savedValue == null || savedValue.trim().isEmpty) {
          editsByTermId[term.id] = ReadingCardEditData.empty(
            deckId: deck.id,
            termId: term.id,
            sourceId: ReadingCardEditData.sourceIdFor(term),
          );
          continue;
        }

        try {
          final migrated = ReadingCardEditData.fromJsonString(savedValue).copyWith(
            deckId: deck.id,
            termId: term.id,
            sourceId: ReadingCardEditData.sourceIdFor(term),
          );
          await GakujiUserRepository.saveReadingCardEdit(migrated);
          await prefs.remove(key);
          editsByTermId[term.id] = migrated;
          savedTermIds.add(term.id);
          migratedAny = true;
        } catch (_) {
          await prefs.remove(key);
          editsByTermId[term.id] = ReadingCardEditData.empty(
            deckId: deck.id,
            termId: term.id,
            sourceId: ReadingCardEditData.sourceIdFor(term),
          );
        }
      }

      if (migratedAny) {
        GakujiCloudSyncService.schedulePush();
      }
    }

    return ReadingCardEditDeckSnapshot(
      editsByTermId: editsByTermId,
      savedTermIds: savedTermIds,
    );
  }

  static Future<ReadingCardEditData> load({
    required Deck deck,
    required Term term,
  }) async {
    final local = await GakujiUserRepository.loadReadingCardEdit(
      deckId: deck.id,
      termId: term.id,
    );
    if (local != null) {
      return local.copyWith(
        deckId: deck.id,
        termId: term.id,
        sourceId: ReadingCardEditData.sourceIdFor(term),
      );
    }

    final migrated = await _migrateLegacyEdit(deck: deck, term: term);
    if (migrated != null) return migrated;

    return ReadingCardEditData.empty(
      deckId: deck.id,
      termId: term.id,
      sourceId: ReadingCardEditData.sourceIdFor(term),
    );
  }

  static Future<void> save(ReadingCardEditData data) async {
    await GakujiUserRepository.saveReadingCardEdit(data);
    GakujiCloudSyncService.schedulePush();
  }

  static Future<void> delete({
    required Deck deck,
    required Term term,
  }) async {
    await GakujiUserRepository.deleteReadingCardEdit(
      deckId: deck.id,
      termId: term.id,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(preferenceKeyFor(deck: deck, term: term));
    GakujiCloudSyncService.schedulePush();
  }

  static Future<bool> hasSavedEdit({
    required Deck deck,
    required Term term,
  }) async {
    if (await GakujiUserRepository.hasReadingCardEdit(
      deckId: deck.id,
      termId: term.id,
    )) {
      return true;
    }

    final migrated = await _migrateLegacyEdit(deck: deck, term: term);
    return migrated != null;
  }

  static Future<ReadingCardEditData?> _migrateLegacyEdit({
    required Deck deck,
    required Term term,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = preferenceKeyFor(deck: deck, term: term);
    final savedValue = prefs.getString(key);
    if (savedValue == null || savedValue.trim().isEmpty) return null;

    try {
      final savedData = ReadingCardEditData.fromJsonString(savedValue).copyWith(
        deckId: deck.id,
        termId: term.id,
        sourceId: ReadingCardEditData.sourceIdFor(term),
      );
      await GakujiUserRepository.saveReadingCardEdit(savedData);
      await prefs.remove(key);
      GakujiCloudSyncService.schedulePush();
      return savedData;
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }
}
