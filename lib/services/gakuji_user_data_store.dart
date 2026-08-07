import 'dart:async';

import '../data/deck_data.dart';
import '../data/folder_data.dart';
import '../data/pinned_deck_data.dart';
import 'gakuji_user_repository.dart';

class GakujiUserDataStore {
  static const String initializedPreferenceKey =
      'gakuji_user_data_initialized';

  static const Duration saveDebounceDuration = Duration(milliseconds: 450);

  static Timer? _saveDebounce;
  static bool _loaded = false;
  static bool _isSaving = false;
  static bool _canSave = true;

  static Future<void> load() async {
    if (_loaded) return;

    _canSave = true;

    final initialized = await GakujiUserRepository.loadPreference(
      initializedPreferenceKey,
    );

    if (initialized == 'true') {
      final loadedDecks = await GakujiUserRepository.loadDecks();
      final loadedFolders = await GakujiUserRepository.loadFolders();
      final loadedPinnedDeckIds =
          await GakujiUserRepository.loadPinnedDeckIds();

      decks
        ..clear()
        ..addAll(loadedDecks);

      folders
        ..clear()
        ..addAll(loadedFolders);

      pinnedDeckIds
        ..clear()
        ..addAll(loadedPinnedDeckIds);
    } else {
      await saveNow();

      await GakujiUserRepository.savePreference(
        key: initializedPreferenceKey,
        value: 'true',
      );
    }

    _loaded = true;
  }

  static Future<void> saveNow() async {
    if (_isSaving || !_canSave) return;

    _isSaving = true;

    try {
      await GakujiUserRepository.saveAll(
        decks: decks,
        folders: folders,
        pinnedDeckIds: pinnedDeckIds.toList(),
      );

      await GakujiUserRepository.savePreference(
        key: initializedPreferenceKey,
        value: 'true',
      );
    } finally {
      _isSaving = false;
    }
  }

  static void scheduleSave() {
    _saveDebounce?.cancel();

    _saveDebounce = Timer(saveDebounceDuration, () {
      saveNow();
    });
  }

  static Future<void> flushPendingSave() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;

    await saveNow();
  }

  static Future<void> reset() async {
    await flushPendingSave();

    _canSave = false;
    _loaded = false;

    decks
      ..clear()
      ..addAll(buildSampleDecks());

    folders
      ..clear()
      ..addAll(buildSampleFolders());

    pinnedDeckIds.clear();
  }
}
