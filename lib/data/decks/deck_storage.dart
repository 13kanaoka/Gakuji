import 'package:shared_preferences/shared_preferences.dart';

import 'package:gakuji/data/seed/deck_seed.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/data/sync/gakuji_cloud_sync_service.dart';
import 'package:gakuji/data/sync/gakuji_user_repository.dart';

/// Local persistence for per-deck study runtime state.
///
/// SQLite is authoritative. Older SharedPreferences values are migrated once
/// per deck, then removed. Cloud synchronization happens later through the
/// repository's `dirtyDeckRuntime` delta and never participates in these reads.
class DeckStorage {
  static final Set<String> _migratedDeckIds = <String>{};

  static String _migrationKey(String deckId) =>
      'gakuji_deck_runtime_sqlite_migrated_$deckId';

  static String _progressKey(String deckId) => '${deckId}_progress';
  static String _shuffleKey(String deckId) => '${deckId}_shuffle';
  static String _reviewEnabledKey(String deckId) =>
      '${deckId}_review_enabled';
  static String _activeStudyModeKey(String deckId) =>
      '${deckId}_active_study_mode';
  static String _reviewEnabledAtKey(String deckId) =>
      '${deckId}_review_enabled_at';

  static void _updateInMemoryDeck(
    String deckId,
    Deck Function(Deck deck) update,
  ) {
    final index = decks.indexWhere((deck) => deck.id == deckId);
    if (index == -1) return;
    decks[index] = update(decks[index]);
  }

  static Future<void> _ensureMigrated(String deckId) async {
    if (_migratedDeckIds.contains(deckId)) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationKey(deckId)) == true) {
      _migratedDeckIds.add(deckId);
      return;
    }

    final current = await GakujiUserRepository.loadDeckRuntimeState(deckId);
    if (current == null) {
      await prefs.setBool(_migrationKey(deckId), true);
      _migratedDeckIds.add(deckId);
      return;
    }

    final sqliteIsDefault =
        _asInt(current['review_enabled']) == 0 &&
        (current['active_study_mode']?.toString() ?? 'study') == 'study' &&
        current['review_enabled_at'] == null &&
        _asInt(current['last_study_index']) == 0 &&
        _asInt(current['is_shuffled']) == 0;

    final legacyProgress = prefs.getInt(_progressKey(deckId));
    final legacyShuffle = prefs.getBool(_shuffleKey(deckId));
    final legacyReviewEnabled = prefs.getBool(_reviewEnabledKey(deckId));
    final legacyMode = prefs.getString(_activeStudyModeKey(deckId));
    final legacyReviewEnabledAt =
        prefs.getString(_reviewEnabledAtKey(deckId));

    final hasMeaningfulLegacyState =
        (legacyProgress ?? 0) != 0 ||
        legacyShuffle == true ||
        legacyReviewEnabled == true ||
        legacyMode == StudyMode.review.name ||
        legacyReviewEnabledAt != null;

    // Preserve existing local/cloud SQLite runtime state when it already has a
    // value. Only use legacy preferences to seed a still-default deck row.
    if (sqliteIsDefault && hasMeaningfulLegacyState) {
      final migratedMode = legacyMode == null
          ? StudyMode.study
          : legacyMode == StudyMode.review.name
              ? StudyMode.review
              : StudyMode.study;
      final migratedReviewEnabledAt = legacyReviewEnabledAt == null
          ? null
          : DateTime.tryParse(legacyReviewEnabledAt);

      await GakujiUserRepository.updateDeckRuntimeState(
        deckId: deckId,
        reviewEnabled: legacyReviewEnabled,
        activeStudyMode: legacyMode == null ? null : migratedMode,
        reviewEnabledAt: migratedReviewEnabledAt,
        lastStudyIndex: legacyProgress,
        isShuffled: legacyShuffle,
      );

      _updateInMemoryDeck(
        deckId,
        (deck) => deck.copyWith(
          reviewEnabled: legacyReviewEnabled ?? false,
          activeStudyMode: migratedMode,
          reviewEnabledAt: migratedReviewEnabledAt,
          lastStudyIndex: legacyProgress ?? 0,
          isShuffled: legacyShuffle ?? false,
        ),
      );
    }

    await prefs.remove(_progressKey(deckId));
    await prefs.remove(_shuffleKey(deckId));
    await prefs.remove(_reviewEnabledKey(deckId));
    await prefs.remove(_activeStudyModeKey(deckId));
    await prefs.remove(_reviewEnabledAtKey(deckId));
    await prefs.setBool(_migrationKey(deckId), true);
    _migratedDeckIds.add(deckId);
  }

  static Future<void> saveProgress(String deckId, int index) async {
    _updateInMemoryDeck(
      deckId,
      (deck) => deck.copyWith(lastStudyIndex: index),
    );
    await _ensureMigrated(deckId);
    await GakujiUserRepository.updateDeckRuntimeState(
      deckId: deckId,
      lastStudyIndex: index,
    );
    GakujiCloudSyncService.schedulePush();
  }

  static Future<int> loadProgress(String deckId) async {
    await _ensureMigrated(deckId);
    final state = await GakujiUserRepository.loadDeckRuntimeState(deckId);
    return _asInt(state?['last_study_index']);
  }

  static Future<void> saveShuffle(String deckId, bool isShuffled) async {
    _updateInMemoryDeck(
      deckId,
      (deck) => deck.copyWith(isShuffled: isShuffled),
    );
    await _ensureMigrated(deckId);
    await GakujiUserRepository.updateDeckRuntimeState(
      deckId: deckId,
      isShuffled: isShuffled,
    );
    GakujiCloudSyncService.schedulePush();
  }

  static Future<bool> loadShuffle(String deckId) async {
    await _ensureMigrated(deckId);
    final state = await GakujiUserRepository.loadDeckRuntimeState(deckId);
    return _asInt(state?['is_shuffled']) != 0;
  }

  static Future<void> saveReviewEnabled(
    String deckId,
    bool reviewEnabled,
  ) async {
    _updateInMemoryDeck(
      deckId,
      (deck) => deck.copyWith(reviewEnabled: reviewEnabled),
    );
    await _ensureMigrated(deckId);
    await GakujiUserRepository.updateDeckRuntimeState(
      deckId: deckId,
      reviewEnabled: reviewEnabled,
    );
    GakujiCloudSyncService.schedulePush();
  }

  static Future<bool> loadReviewEnabled(String deckId) async {
    await _ensureMigrated(deckId);
    final state = await GakujiUserRepository.loadDeckRuntimeState(deckId);
    return _asInt(state?['review_enabled']) != 0;
  }

  static Future<void> saveActiveStudyMode(
    String deckId,
    StudyMode activeStudyMode,
  ) async {
    _updateInMemoryDeck(
      deckId,
      (deck) => deck.copyWith(activeStudyMode: activeStudyMode),
    );
    await _ensureMigrated(deckId);
    await GakujiUserRepository.updateDeckRuntimeState(
      deckId: deckId,
      activeStudyMode: activeStudyMode,
    );
    GakujiCloudSyncService.schedulePush();
  }

  static Future<StudyMode> loadActiveStudyMode(String deckId) async {
    await _ensureMigrated(deckId);
    final state = await GakujiUserRepository.loadDeckRuntimeState(deckId);
    return state?['active_study_mode']?.toString() == StudyMode.review.name
        ? StudyMode.review
        : StudyMode.study;
  }

  static Future<void> saveReviewEnabledAt(
    String deckId,
    DateTime reviewEnabledAt,
  ) async {
    _updateInMemoryDeck(
      deckId,
      (deck) => deck.copyWith(reviewEnabledAt: reviewEnabledAt),
    );
    await _ensureMigrated(deckId);
    await GakujiUserRepository.updateDeckRuntimeState(
      deckId: deckId,
      reviewEnabledAt: reviewEnabledAt,
    );
    GakujiCloudSyncService.schedulePush();
  }

  static Future<DateTime?> loadReviewEnabledAt(String deckId) async {
    await _ensureMigrated(deckId);
    final state = await GakujiUserRepository.loadDeckRuntimeState(deckId);
    final milliseconds = _nullableInt(state?['review_enabled_at']);
    if (milliseconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true)
        .toLocal();
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
