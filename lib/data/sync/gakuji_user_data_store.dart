import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:gakuji/data/seed/deck_seed.dart';
import 'package:gakuji/data/seed/folder_seed.dart';
import 'package:gakuji/data/state/pinned_deck_data.dart';
import 'package:gakuji/data/state/recent_deck_data.dart';
import 'package:gakuji/data/state/recent_searches.dart';
import 'package:gakuji/data/review/review_card_data.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/data/sync/gakuji_cloud_sync_service.dart';
import 'package:gakuji/data/sync/gakuji_guest_repository.dart';
import 'package:gakuji/data/sync/gakuji_user_database.dart';
import 'package:gakuji/data/sync/gakuji_user_repository.dart';
import 'package:gakuji/data/sync/gakuji_term_payload_repair.dart';

class GakujiUnsyncedDataException implements Exception {
  final String message;

  const GakujiUnsyncedDataException(this.message);

  @override
  String toString() => message;
}

/// Coordinates the in-memory app state with the on-device SQLite database.
///
/// SQLite is always the source of truth. Firestore synchronization is kicked
/// off only after local saves complete and never decides whether studying can
/// proceed.
class GakujiUserDataStore {
  static const String initializedPreferenceKey =
      'gakuji_user_data_initialized';

  static const Duration saveDebounceDuration = Duration(milliseconds: 450);

  static Timer? _saveDebounce;
  static bool _loaded = false;
  static String? _loadedUid;
  static bool _isSaving = false;
  static bool _isRefreshing = false;
  static bool _canSave = true;
  static bool _needsInitialCloudHydration = false;
  static int _memoryRevision = 0;

  static bool get needsInitialCloudHydration => _needsInitialCloudHydration;

  static Future<void> load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_loaded && _loadedUid == user.uid) return;

    _canSave = true;
    _needsInitialCloudHydration = false;
    _loadedUid = user.uid;
    resetRecentlyOpenedDeckIdsCache();

    await GakujiUserRepository.startLocalSession(user.uid);
    await _migrateTemporaryGuestDatabaseIfNeeded(user.uid);

    final initialized = await GakujiUserRepository.loadPreference(
      initializedPreferenceKey,
    );
    final hasLocalData = await GakujiUserRepository.hasSavedUserData();

    if (initialized == 'true' || hasLocalData) {
      await _reloadMemoryFromLocal();
    } else if (user.isAnonymous) {
      // A brand-new guest has no cloud state to discover, so the existing
      // starter workspace can be persisted locally immediately.
      await saveNow();
      await GakujiUserRepository.savePreference(
        key: initializedPreferenceKey,
        value: 'true',
        markDirty: false,
      );
    } else {
      // A registered account on a new installation may already have study data
      // on another device. Never push the in-memory development/sample workspace
      // before we have had a chance to merge the account's cloud copy. Start
      // empty and let the signed-in gate finish this first hydration before
      // MainShell is shown.
      decks.clear();
      folders.clear();
      pinnedDeckIds.clear();
      recentSearches.clear();
      reviewCards.clear();
      reviewLogs.clear();
      _needsInitialCloudHydration = true;
    }

    _loaded = true;
  }

  /// Starts the account-to-account synchronization pass after local SQLite is
  /// loaded. Existing local accounts run this in the background; a registered
  /// account with no local workspace yet may await it once before MainShell is
  /// shown so the first deck list is built from hydrated data.
  static Future<bool> syncAfterLaunch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;

    try {
      final changed = await _syncAndReloadSafely();

      final initialized = await GakujiUserRepository.loadPreference(
        initializedPreferenceKey,
      );
      if (initialized != 'true') {
        await GakujiUserRepository.savePreference(
          key: initializedPreferenceKey,
          value: 'true',
          markDirty: false,
        );
      }

      _needsInitialCloudHydration = false;
      return changed;
    } catch (_) {
      // Offline is a valid launch state. Local Gakuji remains fully usable and
      // another sync is attempted after the next local change or manual refresh.
      return false;
    }
  }

  /// Performs a deliberate remote check without ever replacing newer
  /// in-memory work. Normal launch uses one metadata read and only hydrates
  /// collections when the cloud is newer; pull-to-refresh can force hydration.
  ///
  /// A remote pull can take long enough for the user to edit a deck or
  /// complete a review while Firestore is still responding. Before reloading
  /// the UI from SQLite, verify that neither the in-memory workspace nor the
  /// local database changed during that network pass. If they did, flush the
  /// newer local work and retry. After a few busy retries we simply leave the
  /// current UI alone and let the normal background sync try again later.
  static Future<bool> _syncAndReloadSafely({bool forcePull = false}) async {
    var changedAnything = false;

    for (var attempt = 0; attempt < 3; attempt++) {
      await flushPendingSave();

      final memoryRevisionAtStart = _memoryRevision;
      final localVersionAtStart =
          await GakujiUserRepository.localChangeVersion();

      final changed = await GakujiCloudSyncService.syncNow(
        forcePull: forcePull,
      );
      changedAnything = changedAnything || changed;
      await GakujiCloudSyncService.waitForIdle();

      final localVersionNow = await GakujiUserRepository.localChangeVersion();
      final memoryStayedStable =
          memoryRevisionAtStart == _memoryRevision &&
          _saveDebounce == null &&
          !_isSaving;
      final databaseStayedStable = localVersionAtStart == localVersionNow;

      if (memoryStayedStable && databaseStayedStable) {
        await _reloadMemoryFromLocal();
        return changedAnything;
      }

      // Something local changed while the network pass was in flight. Make
      // sure that newer state reaches SQLite before the next merge attempt.
      await flushPendingSave();
    }

    // The user is actively changing data. Protect the live in-memory state
    // rather than refreshing it from an older snapshot; synchronization will
    // retry after the next quiet period.
    GakujiCloudSyncService.schedulePush();
    return false;
  }

  static Future<void> _reloadMemoryFromLocal() async {
    final loadedDecks = await GakujiUserRepository.loadDecks();
    final loadedFolders = await GakujiUserRepository.loadFolders();
    final loadedPinnedDeckIds =
        await GakujiUserRepository.loadPinnedDeckIds();
    final loadedRecentSearches =
        await GakujiUserRepository.loadRecentSearches();
    final loadedReviewCards = await GakujiUserRepository.loadReviewCards();
    final loadedReviewLogs = await GakujiUserRepository.loadReviewLogs();
    final loadedDictionaryNotes =
        await GakujiUserRepository.loadDictionaryNotes();

    // Legacy/partial cloud writers can leave a deck term with only an id and
    // spelling. Repair those records once from the on-device dictionary before
    // exposing them to study UI. If anything was repaired, persist that complete
    // deck copy locally first and let the normal delta queue mirror it later.
    final repairedTermCount =
        await GakujiTermPayloadRepair.repairDecks(loadedDecks);
    if (repairedTermCount > 0) {
      await GakujiUserRepository.saveAll(
        decks: loadedDecks,
        folders: loadedFolders,
        pinnedDeckIds: loadedPinnedDeckIds,
      );
      GakujiCloudSyncService.schedulePush();
    }

    _applyDictionaryNotesToDecks(
      loadedDecks,
      loadedDictionaryNotes,
    );

    decks
      ..clear()
      ..addAll(loadedDecks);

    folders
      ..clear()
      ..addAll(loadedFolders);

    pinnedDeckIds
      ..clear()
      ..addAll(loadedPinnedDeckIds);

    recentSearches
      ..clear()
      ..addAll(loadedRecentSearches);

    reviewCards
      ..clear()
      ..addAll(loadedReviewCards);

    reviewLogs
      ..clear()
      ..addAll(loadedReviewLogs);
  }


  static void _applyDictionaryNotesToDecks(
    List<Deck> loadedDecks,
    Map<String, String> notes,
  ) {
    if (notes.isEmpty) return;

    for (final deck in loadedDecks) {
      for (var index = 0; index < deck.terms.length; index++) {
        final term = deck.terms[index];
        final sourceId = term.sourceId ?? term.id;

        if (!notes.containsKey(sourceId)) continue;

        final note = notes[sourceId] ?? '';
        if ((term.note ?? '') == note) continue;

        // Dictionary notes are canonical. Deck cards receive an in-memory copy
        // during hydration so study stays entirely local and never needs a
        // per-card note lookup.
        deck.terms[index] = term.copyWith(note: note);
      }
    }
  }

  /// Library pull-to-refresh is the explicit expensive check: it forces a
  /// remote hydration, merges safely into SQLite, then reloads the UI locally.
  static Future<void> refreshFromCloud() async {
    if (_isRefreshing) return;

    _isRefreshing = true;

    try {
      while (_isSaving) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      _canSave = true;
      // Only flush a real pending local edit. Calling saveNow() unconditionally
      // here would mark the entire local workspace dirty and make a clean
      // pull-to-refresh incorrectly prefer stale local state over newer cloud
      // state from another device.
      await flushPendingSave();

      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        await GakujiCloudSyncService.waitForIdle();
        await _syncAndReloadSafely(forcePull: true);
      } else {
        await _reloadMemoryFromLocal();
      }
      _loaded = true;
    } finally {
      _isRefreshing = false;
    }
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
        markDirty: false,
      );
    } finally {
      _isSaving = false;
    }

    // Cloud is deliberately after the local transaction and is not awaited.
    GakujiCloudSyncService.schedulePush();
  }

  static void scheduleSave() {
    _memoryRevision++;
    _saveDebounce?.cancel();

    _saveDebounce = Timer(saveDebounceDuration, () {
      _saveDebounce = null;
      unawaited(saveNow());
    });
  }

  static Future<void> flushPendingSave() async {
    final hadPendingSave = _saveDebounce != null;
    _saveDebounce?.cancel();
    _saveDebounce = null;

    while (_isSaving) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    // Do not manufacture a new dirty snapshot just because a caller is
    // signing out or upgrading an account. Direct repository writes already
    // mark themselves dirty; only a genuinely scheduled in-memory save needs
    // to be flushed here.
    if (hadPendingSave) {
      await saveNow();
    }
  }

  /// Before anonymous Auth is linked, only ensure the newest UI state is in
  /// SQLite. The UID remains the same, so there is nothing to move locally.
  static Future<void> prepareGuestUpgrade() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.isAnonymous != true) return;
    await flushPendingSave();
  }

  /// After provider linking, the same UID simply gains cloud synchronization.
  /// Local data remains the working copy and is mirrored upward once.
  static Future<void> finishGuestUpgrade() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    await GakujiUserRepository.startLocalSession(user.uid);
    await flushPendingSave();
    try {
      await GakujiCloudSyncService.syncNow();
    } catch (_) {
      // The account upgrade itself is complete. Keep the local workspace and
      // let the normal background sync retry when connectivity returns.
      GakujiCloudSyncService.schedulePush();
    }
    _canSave = true;
  }

  /// Permanently discards the on-device workspace after Firebase account
  /// deletion has already succeeded. Unlike [reset], this intentionally does
  /// not sync first: the matching cloud account has just been removed.
  static Future<void> discardLocalAfterAccountDeletion() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;

    while (_isSaving || _isRefreshing) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    _canSave = false;
    _loaded = false;
    _loadedUid = null;
    _needsInitialCloudHydration = false;
    _memoryRevision = 0;

    await GakujiUserDatabase.clearUserData();

    decks
      ..clear()
      ..addAll(buildSampleDecks());
    folders
      ..clear()
      ..addAll(buildSampleFolders());
    pinnedDeckIds.clear();
    recentSearches.clear();
    reviewCards.clear();
    reviewLogs.clear();
    resetRecentlyOpenedDeckIdsCache();
  }

  /// Signs out of the local workspace safely.
  ///
  /// Registered accounts are synchronized first. If the final cloud mirror
  /// fails, local data is intentionally kept and sign-out is blocked so an
  /// offline edit can never be destroyed accidentally. Guests have no cloud
  /// copy, so signing out explicitly discards their local workspace.
  static Future<void> reset() async {
    final user = FirebaseAuth.instance.currentUser;
    final wasGuest = user?.isAnonymous == true;

    await flushPendingSave();

    if (!wasGuest && user != null) {
      try {
        await GakujiCloudSyncService.flushPendingPush();
      } catch (_) {
        throw const GakujiUnsyncedDataException(
          'Gakuji could not finish syncing your latest local changes. '
          'Connect to the internet and try signing out again so your study '
          'data is not lost.',
        );
      }

      if (await GakujiUserRepository.hasUnsyncedChanges()) {
        throw const GakujiUnsyncedDataException(
          'Your latest local changes have not synced yet. Try signing out '
          'again after Gakuji has a connection.',
        );
      }
    }

    _canSave = false;
    _loaded = false;
    _loadedUid = null;
    _needsInitialCloudHydration = false;
    _memoryRevision = 0;

    await GakujiUserDatabase.clearUserData();

    decks
      ..clear()
      ..addAll(buildSampleDecks());

    folders
      ..clear()
      ..addAll(buildSampleFolders());

    pinnedDeckIds.clear();
    recentSearches.clear();
    reviewCards.clear();
    reviewLogs.clear();
    resetRecentlyOpenedDeckIdsCache();
  }

  /// One-time bridge from the temporary separate guest database introduced
  /// during the auth work. After migration, all users use gakuji_user.db.
  static Future<void> _migrateTemporaryGuestDatabaseIfNeeded(String uid) async {
    try {
      if (!await GakujiGuestRepository.isOwnedBy(uid)) return;
      if (!await GakujiGuestRepository.hasSavedUserData()) return;

      final mainAlreadyHasData = await GakujiUserRepository.hasSavedUserData();
      if (mainAlreadyHasData) return;

      final guestDecks = await GakujiGuestRepository.loadDecks();
      final guestFolders = await GakujiGuestRepository.loadFolders();
      final guestPins = await GakujiGuestRepository.loadPinnedDeckIds();
      final guestRecent = await GakujiGuestRepository.loadRecentSearches();
      final guestCards = await GakujiGuestRepository.loadReviewCards();
      final guestLogs = await GakujiGuestRepository.loadReviewLogs();
      final guestPreferences =
          await GakujiGuestRepository.loadSyncablePreferences();
      final guestNotes = await GakujiGuestRepository.loadDictionaryNotes();

      await GakujiUserRepository.saveAll(
        decks: guestDecks,
        folders: guestFolders,
        pinnedDeckIds: guestPins,
      );
      await GakujiUserRepository.saveRecentSearches(guestRecent);
      await GakujiUserRepository.syncReviewCards(guestCards);

      for (final log in guestLogs) {
        await GakujiUserRepository.saveReviewLog(log);
      }
      for (final entry in guestPreferences.entries) {
        await GakujiUserRepository.savePreference(
          key: entry.key,
          value: entry.value,
        );
      }
      for (final entry in guestNotes.entries) {
        await GakujiUserRepository.saveDictionaryNote(
          sourceId: entry.key,
          note: entry.value,
        );
      }

      await GakujiGuestRepository.clearAllData();
    } catch (_) {
      // Migration is best-effort. Never prevent the local app from opening.
    }
  }
}
