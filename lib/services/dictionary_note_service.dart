import 'package:shared_preferences/shared_preferences.dart';

import '../data/deck_data.dart';
import '../models/term.dart';
import 'gakuji_cloud_sync_service.dart';
import 'gakuji_user_repository.dart';

/// Canonical local-first storage for user dictionary notes.
///
/// Dictionary notes belong to the dictionary entry, not to an individual deck
/// card. They are saved to SQLite immediately, mirrored into every local
/// deck-owned copy of that dictionary entry, and pushed to cloud later through
/// the normal Gakuji user-data sync queue.
class DictionaryNoteService {
  /// A note should comfortably hold a personal definition plus a personal
  /// example sentence (and, if desired, its translation) without encouraging
  /// essay-length card content.
  static const int maxCharacters = 400;

  static String sourceIdFor(Term term) => term.sourceId ?? term.id;

  static String clean(String value) {
    final normalized = value.replaceAll('\r\n', '\n');
    final runes = normalized.runes.toList(growable: false);

    if (runes.length <= maxCharacters) {
      return normalized.trimRight();
    }

    return String.fromCharCodes(
      runes.take(maxCharacters),
    ).trimRight();
  }

  static Future<String> loadForTerm(Term term) async {
    final sourceId = sourceIdFor(term);
    final localNote = await GakujiUserRepository.loadDictionaryNote(sourceId);

    if (localNote != null) {
      final cleaned = clean(localNote);
      _applyToDeckCopies(sourceId: sourceId, note: cleaned);
      return cleaned;
    }

    // One-time migration path for notes created before dictionary notes moved
    // from SharedPreferences into the local-first SQLite user database.
    final prefs = await SharedPreferences.getInstance();
    final legacyKey = _legacyPreferenceKey(sourceId);
    final legacyNote = prefs.getString(legacyKey);
    final fallback = legacyNote ?? term.note ?? '';
    final cleaned = clean(fallback);

    if (legacyNote != null || cleaned.isNotEmpty) {
      await GakujiUserRepository.saveDictionaryNote(
        sourceId: sourceId,
        note: cleaned,
      );
      await prefs.remove(legacyKey);
      _applyToDeckCopies(sourceId: sourceId, note: cleaned);
      GakujiCloudSyncService.schedulePush();
    }

    return cleaned;
  }

  static Future<String> saveForTerm({
    required Term term,
    required String note,
  }) async {
    final sourceId = sourceIdFor(term);
    final cleaned = clean(note);

    await GakujiUserRepository.saveDictionaryNote(
      sourceId: sourceId,
      note: cleaned,
    );

    _applyToDeckCopies(
      sourceId: sourceId,
      note: cleaned,
    );

    // SQLite already contains the note at this point. Queue only the note's
    // normal delta push; the UI never waits on Firebase.
    GakujiCloudSyncService.schedulePush();

    return cleaned;
  }

  static String _legacyPreferenceKey(String sourceId) {
    return 'gakuji_dictionary_note_$sourceId';
  }

  static bool _applyToDeckCopies({
    required String sourceId,
    required String note,
  }) {
    var changed = false;

    for (final deck in decks) {
      for (var index = 0; index < deck.terms.length; index++) {
        final term = deck.terms[index];
        final termSourceId = term.sourceId ?? term.id;

        if (termSourceId != sourceId) continue;
        if ((term.note ?? '') == note) continue;

        deck.terms[index] = term.copyWith(note: note);
        changed = true;
      }
    }

    return changed;
  }
}
