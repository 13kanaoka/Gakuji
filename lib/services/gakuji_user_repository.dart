import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/deck.dart';
import '../models/folder.dart';
import '../models/review_card.dart';
import '../models/term.dart';
import '../data/reading_card_edit_data.dart';
import 'gakuji_user_database.dart';

class GakujiSyncTombstone {
  final String entityType;
  final String entityId;
  final int deletedAtMs;

  const GakujiSyncTombstone({
    required this.entityType,
    required this.entityId,
    required this.deletedAtMs,
  });

  String get key => '$entityType\u001f$entityId';
}

class GakujiDirtyEntity {
  final String entityType;
  final String entityId;
  final int changedAtMs;

  const GakujiDirtyEntity({
    required this.entityType,
    required this.entityId,
    required this.changedAtMs,
  });

  String get key => '$entityType\u001f$entityId';
}

class GakujiUserRepository {
  static const String tombstoneDeck = 'deck';
  static const String tombstoneDeckTerm = 'deck_term';
  static const String tombstoneFolder = 'folder';
  static const String tombstoneFolderDeck = 'folder_deck';
  static const String tombstonePin = 'pin';
  static const String tombstoneReviewCard = 'review_card';
  static const String tombstoneReadingCardEdit = 'reading_card_edit';
  static const String tombstonePreference = 'preference';
  static const String tombstoneReviewLog = 'review_log';

  static const String dirtyWorkspace = 'workspace';
  static const String dirtyDeck = 'deck';
  static const String dirtyDeckRuntime = 'deck_runtime';
  static const String dirtyFolder = 'folder';
  static const String dirtyRoot = 'root';
  static const String dirtyPinnedDecks = 'pinned_decks';
  static const String dirtyRecentSearches = 'recent_searches';
  static const String dirtyPreferences = 'preferences';
  static const String dirtyReviewCard = 'review_card';
  static const String dirtyReviewLog = 'review_log';
  static const String dirtyDictionaryNote = 'dictionary_note';
  static const String dirtyReadingCardEdit = 'reading_card_edit';

  static String compoundEntityId(String first, String second) {
    return '$first\u001f$second';
  }

  static int get _now {
    return DateTime.now().millisecondsSinceEpoch;
  }

  static String _deckTypeToText(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'writing';
      case DeckType.reading:
        return 'reading';
      case DeckType.hybrid:
        return 'hybrid';
    }
  }

  static DeckType _deckTypeFromText(String value) {
    switch (value) {
      case 'writing':
        return DeckType.writing;
      case 'hybrid':
        return DeckType.hybrid;
      case 'reading':
      default:
        return DeckType.reading;
    }
  }

  static String _hybridCardModeToText(HybridCardMode mode) {
    switch (mode) {
      case HybridCardMode.reading:
        return 'reading';
      case HybridCardMode.writing:
        return 'writing';
      case HybridCardMode.both:
        return 'both';
    }
  }

  static int _boolToInt(bool value) {
    return value ? 1 : 0;
  }

  /// Binds the local workspace to the active Firebase UID.
  ///
  /// The database itself is always the working copy. If a different account
  /// signs in on the same device, the previous account's local workspace is
  /// cleared before the new account is allowed to use it. Linking a guest to
  /// a permanent account keeps the same UID, so no local data is moved.
  static Future<void> startLocalSession(String uid) async {
    final existingOwner = await GakujiUserDatabase.readMetadata(
      GakujiUserDatabase.ownerUidMetadataKey,
    );

    if (existingOwner != null &&
        existingOwner.isNotEmpty &&
        existingOwner != uid) {
      await GakujiUserDatabase.clearUserData();
    }

    await GakujiUserDatabase.writeMetadata(
      GakujiUserDatabase.ownerUidMetadataKey,
      uid,
    );
  }

  static Future<bool> isOwnedBy(String uid) async {
    final owner = await GakujiUserDatabase.readMetadata(
      GakujiUserDatabase.ownerUidMetadataKey,
    );
    return owner == uid;
  }

  static Future<void> _markLocalDirty([DatabaseExecutor? executor]) async {
    final target = executor ?? await GakujiUserDatabase.database;
    final versionRows = await target.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [GakujiUserDatabase.localChangeVersionMetadataKey],
      limit: 1,
    );
    final currentVersion = versionRows.isEmpty
        ? 0
        : int.tryParse(versionRows.first['value']?.toString() ?? '') ?? 0;

    await target.insert(
      'app_metadata',
      {
        'key': GakujiUserDatabase.localDirtyMetadataKey,
        'value': 'true',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await target.insert(
      'app_metadata',
      {
        'key': GakujiUserDatabase.localChangeVersionMetadataKey,
        'value': (currentVersion + 1).toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _recordDirtyEntity(
    DatabaseExecutor executor, {
    required String entityType,
    required String entityId,
    int? changedAt,
  }) async {
    if (entityId.isEmpty) return;
    await executor.insert(
      'sync_dirty_entities',
      {
        'entity_type': entityType,
        'entity_id': entityId,
        'changed_at': changedAt ?? _now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<GakujiDirtyEntity>> loadDirtyEntities() async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'sync_dirty_entities',
      orderBy: 'changed_at ASC',
    );
    return rows.map((row) {
      return GakujiDirtyEntity(
        entityType: row['entity_type']?.toString() ?? '',
        entityId: row['entity_id']?.toString() ?? '',
        changedAtMs: _intFromDatabaseValue(row['changed_at']),
      );
    }).where((item) {
      return item.entityType.isNotEmpty && item.entityId.isNotEmpty;
    }).toList();
  }

  static Future<void> _recordTombstone(
    DatabaseExecutor executor, {
    required String entityType,
    required String entityId,
    required int deletedAt,
  }) async {
    if (entityId.isEmpty) return;
    await executor.insert(
      'sync_tombstones',
      {
        'entity_type': entityType,
        'entity_id': entityId,
        'deleted_at': deletedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _clearTombstone(
    DatabaseExecutor executor, {
    required String entityType,
    required String entityId,
  }) async {
    if (entityId.isEmpty) return;
    await executor.delete(
      'sync_tombstones',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
  }

  static Future<List<GakujiSyncTombstone>> loadSyncTombstones() async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query('sync_tombstones');
    return rows.map((row) {
      return GakujiSyncTombstone(
        entityType: row['entity_type']?.toString() ?? '',
        entityId: row['entity_id']?.toString() ?? '',
        deletedAtMs: _intFromDatabaseValue(row['deleted_at']),
      );
    }).where((item) {
      return item.entityType.isNotEmpty && item.entityId.isNotEmpty;
    }).toList();
  }

  static Future<void> clearSyncTombstones() async {
    final database = await GakujiUserDatabase.database;
    await database.delete('sync_tombstones');
  }

  static Future<bool> hasUnsyncedChanges() async {
    return await GakujiUserDatabase.readMetadata(
          GakujiUserDatabase.localDirtyMetadataKey,
        ) ==
        'true';
  }

  static Future<int> localChangeVersion() async {
    final raw = await GakujiUserDatabase.readMetadata(
      GakujiUserDatabase.localChangeVersionMetadataKey,
    );
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// Finalizes a cloud mirror only if the local workspace did not change while
  /// the network operation was in flight. This prevents a slow sync from
  /// accidentally marking a newer offline edit as already synchronized.
  static Future<bool> finalizeCloudSync({
    required int syncedAtMs,
    required int syncedRevision,
    required int expectedLocalChangeVersion,
  }) async {
    final database = await GakujiUserDatabase.database;

    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'app_metadata',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [GakujiUserDatabase.localChangeVersionMetadataKey],
        limit: 1,
      );
      final currentVersion = rows.isEmpty
          ? 0
          : int.tryParse(rows.first['value']?.toString() ?? '') ?? 0;

      await transaction.insert(
        'app_metadata',
        {
          'key': GakujiUserDatabase.lastCloudSyncMetadataKey,
          'value': syncedAtMs.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.insert(
        'app_metadata',
        {
          'key': GakujiUserDatabase.lastCloudRevisionMetadataKey,
          'value': syncedRevision.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.insert(
        'app_metadata',
        {
          'key': GakujiUserDatabase.cloudBootstrapMetadataKey,
          'value': 'true',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (currentVersion != expectedLocalChangeVersion) {
        return false;
      }

      await transaction.insert(
        'app_metadata',
        {
          'key': GakujiUserDatabase.localDirtyMetadataKey,
          'value': 'false',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete('sync_tombstones');
      await transaction.delete('sync_dirty_entities');
      return true;
    });
  }

  static Future<int> lastCloudSyncAtMs() async {
    final raw = await GakujiUserDatabase.readMetadata(
      GakujiUserDatabase.lastCloudSyncMetadataKey,
    );
    return int.tryParse(raw ?? '') ?? 0;
  }

  static Future<int> lastCloudRevision() async {
    final raw = await GakujiUserDatabase.readMetadata(
      GakujiUserDatabase.lastCloudRevisionMetadataKey,
    );
    return int.tryParse(raw ?? '') ?? 0;
  }

  static Future<bool> cloudBootstrapComplete() async {
    return await GakujiUserDatabase.readMetadata(
          GakujiUserDatabase.cloudBootstrapMetadataKey,
        ) ==
        'true';
  }


  static Future<List<Deck>> loadDecks() async {
    final database = await GakujiUserDatabase.database;

    final deckRows = await database.query(
      'decks',
      orderBy: 'position ASC, created_at ASC',
    );

    final loadedDecks = <Deck>[];

    for (final deckRow in deckRows) {
      final deckId = deckRow['id']?.toString() ?? '';

      if (deckId.isEmpty) continue;

      final termRows = await database.query(
        'deck_terms',
        where: 'deck_id = ?',
        whereArgs: [deckId],
        orderBy: 'position ASC, created_at ASC',
      );

      final deckType = _deckTypeFromText(
        deckRow['type']?.toString() ?? 'reading',
      );
      final loadedTerms = <Term>[];
      final loadedHybridCardModes = <String, HybridCardMode>{};

      for (final termRow in termRows) {
        final termJsonText = termRow['term_json']?.toString() ?? '';

        if (termJsonText.isEmpty) continue;

        try {
          final decoded = jsonDecode(termJsonText);

          if (decoded is Map<String, dynamic>) {
            final term = Term.fromJson(decoded);
            loadedTerms.add(term);

            if (deckType == DeckType.hybrid) {
              final storedMode = decoded['_hybridCardMode']?.toString();

              if (storedMode != null && storedMode.isNotEmpty) {
                loadedHybridCardModes[term.id] =
                    hybridCardModeFromStorage(storedMode);
              }
            }
          }
        } catch (_) {
          // Skip corrupted term rows instead of crashing the app.
        }
      }

      loadedDecks.add(
        Deck(
          id: deckId,
          name: deckRow['name']?.toString() ?? '',
          type: deckType,
          colorValue: _nullableIntFromDatabaseValue(deckRow['color_value']),
          terms: loadedTerms,
          hybridCardModes: loadedHybridCardModes,
          reviewEnabled: _intFromDatabaseValue(deckRow['review_enabled']) != 0,
          activeStudyMode: deckRow['active_study_mode']?.toString() == 'review'
              ? StudyMode.review
              : StudyMode.study,
          reviewEnabledAt: _dateTimeFromDatabaseValue(
            deckRow['review_enabled_at'],
          ),
          lastStudyIndex: _intFromDatabaseValue(deckRow['last_study_index']),
          isShuffled: _intFromDatabaseValue(deckRow['is_shuffled']) != 0,
        ),
      );
    }

    return loadedDecks;
  }

  static Future<Map<String, Object?>?> loadDeckRuntimeState(
    String deckId,
  ) async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'decks',
      columns: [
        'review_enabled',
        'active_study_mode',
        'review_enabled_at',
        'last_study_index',
        'is_shuffled',
      ],
      where: 'id = ?',
      whereArgs: [deckId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, Object?>.from(rows.first);
  }

  static Future<void> saveDeckRuntimeState(Deck deck) async {
    final database = await GakujiUserDatabase.database;
    final current = await loadDeckRuntimeState(deck.id);
    if (current == null) return;

    final desired = <String, Object?>{
      'review_enabled': _boolToInt(deck.reviewEnabled),
      'active_study_mode':
          deck.activeStudyMode == StudyMode.review ? 'review' : 'study',
      'review_enabled_at':
          deck.reviewEnabledAt?.toUtc().millisecondsSinceEpoch,
      'last_study_index': deck.lastStudyIndex,
      'is_shuffled': _boolToInt(deck.isShuffled),
    };
    final changed = desired.entries.any((entry) {
      return current[entry.key] != entry.value;
    });
    if (!changed) return;

    await database.transaction((transaction) async {
      await transaction.update(
        'decks',
        {...desired, 'updated_at': _now},
        where: 'id = ?',
        whereArgs: [deck.id],
      );
      await _recordDirtyEntity(
        transaction,
        entityType: dirtyDeckRuntime,
        entityId: deck.id,
      );
      await _markLocalDirty(transaction);
    });
  }

  /// Updates only the supplied runtime fields for one deck.
  ///
  /// Study progress/review/shuffle state is written to SQLite immediately and
  /// recorded as a runtime delta. Firestore is never consulted here.
  static Future<void> updateDeckRuntimeState({
    required String deckId,
    bool? reviewEnabled,
    StudyMode? activeStudyMode,
    DateTime? reviewEnabledAt,
    int? lastStudyIndex,
    bool? isShuffled,
  }) async {
    final current = await loadDeckRuntimeState(deckId);
    if (current == null) return;

    final updates = <String, Object?>{};

    if (reviewEnabled != null) {
      final value = _boolToInt(reviewEnabled);
      if (current['review_enabled'] != value) {
        updates['review_enabled'] = value;
      }
    }

    if (activeStudyMode != null) {
      final value =
          activeStudyMode == StudyMode.review ? 'review' : 'study';
      if (current['active_study_mode']?.toString() != value) {
        updates['active_study_mode'] = value;
      }
    }

    if (reviewEnabledAt != null) {
      final value = reviewEnabledAt.toUtc().millisecondsSinceEpoch;
      if (_intFromDatabaseValue(current['review_enabled_at']) != value) {
        updates['review_enabled_at'] = value;
      }
    }

    if (lastStudyIndex != null) {
      if (_intFromDatabaseValue(current['last_study_index']) !=
          lastStudyIndex) {
        updates['last_study_index'] = lastStudyIndex;
      }
    }

    if (isShuffled != null) {
      final value = _boolToInt(isShuffled);
      if (_intFromDatabaseValue(current['is_shuffled']) != value) {
        updates['is_shuffled'] = value;
      }
    }

    if (updates.isEmpty) return;

    final database = await GakujiUserDatabase.database;
    await database.transaction((transaction) async {
      await transaction.update(
        'decks',
        {...updates, 'updated_at': _now},
        where: 'id = ?',
        whereArgs: [deckId],
      );
      await _recordDirtyEntity(
        transaction,
        entityType: dirtyDeckRuntime,
        entityId: deckId,
      );
      await _markLocalDirty(transaction);
    });
  }

  static Future<List<Folder>> loadFolders() async {
    final database = await GakujiUserDatabase.database;

    final folderRows = await database.query(
      'folders',
      orderBy: 'position ASC, created_at ASC',
    );

    final loadedFolders = <Folder>[];

    for (final folderRow in folderRows) {
      final folderId = folderRow['id']?.toString() ?? '';

      if (folderId.isEmpty) continue;

      final folderDeckRows = await database.query(
        'folder_decks',
        where: 'folder_id = ?',
        whereArgs: [folderId],
        orderBy: 'position ASC, created_at ASC',
      );

      final deckIds = folderDeckRows
          .map((row) => row['deck_id']?.toString() ?? '')
          .where((deckId) => deckId.isNotEmpty)
          .toList();

      loadedFolders.add(
        Folder(
          id: folderId,
          name: folderRow['name']?.toString() ?? '',
          deckIds: deckIds,
        ),
      );
    }

    return loadedFolders;
  }

  static Future<List<String>> loadPinnedDeckIds() async {
    final database = await GakujiUserDatabase.database;

    final rows = await database.query(
      'pinned_decks',
      orderBy: 'position ASC, created_at ASC',
    );

    return rows
        .map((row) => row['deck_id']?.toString() ?? '')
        .where((deckId) => deckId.isNotEmpty)
        .toList();
  }

  static Future<bool> hasSavedUserData() async {
    final database = await GakujiUserDatabase.database;

    final deckCount = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM decks'),
        ) ??
        0;

    final folderCount = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM folders'),
        ) ??
        0;

    final pinnedCount = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM pinned_decks'),
        ) ??
        0;

    return deckCount > 0 || folderCount > 0 || pinnedCount > 0;
  }

  static Future<List<Term>> loadRecentSearches() async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'recent_searches',
      orderBy: 'position ASC',
    );
    final results = <Term>[];

    for (final row in rows) {
      final raw = row['term_json']?.toString();
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          results.add(Term.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // Ignore a corrupted recent-search entry.
      }
    }

    return results;
  }

  static Future<Map<String, int>> loadRecentSearchTimestamps() async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'recent_searches',
      columns: ['term_json', 'updated_at'],
      orderBy: 'position ASC',
    );
    final results = <String, int>{};

    for (final row in rows) {
      final raw = row['term_json']?.toString();
      final updatedAt = row['updated_at'];

      if (raw == null || raw.isEmpty || updatedAt is! int) continue;

      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;

        final term = Term.fromJson(Map<String, dynamic>.from(decoded));
        results[term.id] = updatedAt;
      } catch (_) {
        // Ignore a corrupted recent-search entry.
      }
    }

    return results;
  }

  static Future<void> saveRecentSearches(
    List<Term> recentSearches, {
    bool markDirty = true,
    Map<String, int>? updatedAtByTermId,
  }) async {
    final database = await GakujiUserDatabase.database;
    final now = _now;
    final desiredJson = recentSearches
        .map((term) => jsonEncode(term.toJson()))
        .toList(growable: false);
    final currentRows = await database.query(
      'recent_searches',
      columns: ['term_json'],
      orderBy: 'position ASC',
    );
    final currentJson = currentRows
        .map((row) => row['term_json']?.toString() ?? '')
        .toList(growable: false);
    final changed = !_stringListsEqual(currentJson, desiredJson);
    if (!changed) return;

    await database.transaction((transaction) async {
      final existingRows = await transaction.query(
        'recent_searches',
        columns: ['term_json', 'updated_at'],
      );
      final existingTimestamps = <String, int>{};

      for (final row in existingRows) {
        final raw = row['term_json']?.toString();
        final updatedAt = row['updated_at'];

        if (raw == null || raw.isEmpty || updatedAt is! int) continue;

        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map) continue;

          final term = Term.fromJson(Map<String, dynamic>.from(decoded));
          existingTimestamps[term.id] = updatedAt;
        } catch (_) {
          // Ignore a corrupted recent-search entry.
        }
      }

      await transaction.delete('recent_searches');

      for (var index = 0; index < recentSearches.length; index++) {
        final term = recentSearches[index];
        final updatedAt = updatedAtByTermId?[term.id] ??
            existingTimestamps[term.id] ??
            now;

        await transaction.insert('recent_searches', {
          'position': index,
          'term_json': desiredJson[index],
          'updated_at': updatedAt,
        });
      }
      if (markDirty) {
        await _recordDirtyEntity(
          transaction,
          entityType: dirtyRecentSearches,
          entityId: dirtyRecentSearches,
          changedAt: now,
        );
        await _markLocalDirty(transaction);
      }
    });
  }

  static String _deckSyncSignature(Deck deck, int position) {
    final hybridModes = <String, String>{};
    final hybridKeys = deck.hybridCardModes.keys.toList()..sort();
    for (final termId in hybridKeys) {
      hybridModes[termId] = deck.hybridCardModes[termId]!.name;
    }

    return jsonEncode({
      'name': deck.name,
      'type': deck.type.name,
      'colorValue': deck.colorValue,
      'terms': deck.terms.map((term) => term.toJson()).toList(),
      'hybridCardModes': hybridModes,
      'reviewEnabled': deck.reviewEnabled,
      'activeStudyMode': deck.activeStudyMode.name,
      'reviewEnabledAt': deck.reviewEnabledAt?.toUtc().toIso8601String(),
      'lastStudyIndex': deck.lastStudyIndex,
      'isShuffled': deck.isShuffled,
      'position': position,
    });
  }

  static String _folderSyncSignature(
    Folder folder,
    int position,
    Set<String> existingDeckIds,
  ) {
    return jsonEncode({
      'name': folder.name,
      'deckIds': folder.deckIds
          .where((deckId) => existingDeckIds.contains(deckId))
          .toList(),
      'position': position,
    });
  }

  static bool _stringListsEqual(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  static Future<void> saveAll({
    required List<Deck> decks,
    required List<Folder> folders,
    required List<String> pinnedDeckIds,
    bool markDirty = true,
  }) async {
    final database = await GakujiUserDatabase.database;
    final savedDeckIds = decks.map((deck) => deck.id).toSet();
    final savedFolderIds = folders.map((folder) => folder.id).toSet();

    final changedDeckIds = <String>{};
    final changedFolderIds = <String>{};
    var pinsChanged = false;
    var deletedDeckIds = <String>{};
    var deletedFolderIds = <String>{};

    if (markDirty) {
      final existingDecks = await loadDecks();
      final existingFolders = await loadFolders();
      final existingPins = await loadPinnedDeckIds();
      final existingDeckIds = existingDecks.map((deck) => deck.id).toSet();

      final existingDeckSignatures = <String, String>{
        for (var index = 0; index < existingDecks.length; index++)
          existingDecks[index].id:
              _deckSyncSignature(existingDecks[index], index),
      };
      for (var index = 0; index < decks.length; index++) {
        final deck = decks[index];
        if (existingDeckSignatures[deck.id] !=
            _deckSyncSignature(deck, index)) {
          changedDeckIds.add(deck.id);
        }
      }
      deletedDeckIds = existingDeckIds.difference(savedDeckIds);

      final existingFolderSignatures = <String, String>{
        for (var index = 0; index < existingFolders.length; index++)
          existingFolders[index].id: _folderSyncSignature(
            existingFolders[index],
            index,
            existingDeckIds,
          ),
      };
      for (var index = 0; index < folders.length; index++) {
        final folder = folders[index];
        if (existingFolderSignatures[folder.id] !=
            _folderSyncSignature(folder, index, savedDeckIds)) {
          changedFolderIds.add(folder.id);
        }
      }
      deletedFolderIds = existingFolders
          .map((folder) => folder.id)
          .toSet()
          .difference(savedFolderIds);

      final desiredPins = pinnedDeckIds
          .where((deckId) => savedDeckIds.contains(deckId))
          .toList(growable: false);
      pinsChanged = !_stringListsEqual(existingPins, desiredPins);

      final changedAnything = changedDeckIds.isNotEmpty ||
          changedFolderIds.isNotEmpty ||
          deletedDeckIds.isNotEmpty ||
          deletedFolderIds.isNotEmpty ||
          pinsChanged;
      if (!changedAnything) return;
    }

    await database.transaction((transaction) async {
      final now = _now;

      await _deleteRemovedDecks(
        transaction: transaction,
        savedDeckIds: savedDeckIds,
        trackLocalChanges: markDirty,
        now: now,
      );

      for (var deckIndex = 0; deckIndex < decks.length; deckIndex++) {
        await _saveDeck(
          transaction: transaction,
          deck: decks[deckIndex],
          position: deckIndex,
          now: now,
          trackLocalChanges: markDirty,
        );
      }

      await _deleteRemovedFolders(
        transaction: transaction,
        savedFolderIds: savedFolderIds,
        trackLocalChanges: markDirty,
        now: now,
      );

      for (var folderIndex = 0; folderIndex < folders.length; folderIndex++) {
        await _saveFolder(
          transaction: transaction,
          folder: folders[folderIndex],
          position: folderIndex,
          existingDeckIds: savedDeckIds,
          now: now,
          trackLocalChanges: markDirty,
        );
      }

      await _syncPinnedDecks(
        transaction: transaction,
        pinnedDeckIds: pinnedDeckIds,
        existingDeckIds: savedDeckIds,
        now: now,
        trackLocalChanges: markDirty,
      );

      if (!markDirty) return;

      for (final deckId in changedDeckIds) {
        await _recordDirtyEntity(
          transaction,
          entityType: dirtyDeck,
          entityId: deckId,
          changedAt: now,
        );
      }
      for (final folderId in changedFolderIds) {
        await _recordDirtyEntity(
          transaction,
          entityType: dirtyFolder,
          entityId: folderId,
          changedAt: now,
        );
      }
      if (pinsChanged) {
        await _recordDirtyEntity(
          transaction,
          entityType: dirtyPinnedDecks,
          entityId: dirtyPinnedDecks,
          changedAt: now,
        );
      }

      final changedAnything = changedDeckIds.isNotEmpty ||
          changedFolderIds.isNotEmpty ||
          deletedDeckIds.isNotEmpty ||
          deletedFolderIds.isNotEmpty ||
          pinsChanged;
      if (changedAnything) await _markLocalDirty(transaction);
    });
  }

  static Future<void> _deleteRemovedDecks({
    required Transaction transaction,
    required Set<String> savedDeckIds,
    required bool trackLocalChanges,
    required int now,
  }) async {
    final existingRows = await transaction.query('decks', columns: ['id']);

    for (final row in existingRows) {
      final deckId = row['id']?.toString() ?? '';
      if (deckId.isEmpty || savedDeckIds.contains(deckId)) continue;

      if (trackLocalChanges) {
        final folderRows = await transaction.query(
          'folder_decks',
          columns: ['folder_id'],
          where: 'deck_id = ?',
          whereArgs: [deckId],
        );
        for (final folderRow in folderRows) {
          final folderId = folderRow['folder_id']?.toString() ?? '';
          if (folderId.isNotEmpty) {
            await _recordDirtyEntity(
              transaction,
              entityType: dirtyFolder,
              entityId: folderId,
              changedAt: now,
            );
          }
        }

        final pinRows = await transaction.query(
          'pinned_decks',
          columns: ['deck_id'],
          where: 'deck_id = ?',
          whereArgs: [deckId],
          limit: 1,
        );
        if (pinRows.isNotEmpty) {
          await _recordDirtyEntity(
            transaction,
            entityType: dirtyPinnedDecks,
            entityId: dirtyPinnedDecks,
            changedAt: now,
          );
        }

        final reviewRows = await transaction.query(
          'review_cards',
          columns: ['id'],
          where: 'deck_id = ?',
          whereArgs: [deckId],
        );
        for (final reviewRow in reviewRows) {
          final reviewCardId = reviewRow['id']?.toString() ?? '';
          if (reviewCardId.isEmpty) continue;
          final logRows = await transaction.query(
            'review_logs',
            columns: ['id'],
            where: 'review_card_id = ?',
            whereArgs: [reviewCardId],
          );
          for (final logRow in logRows) {
            final logId = logRow['id']?.toString() ?? '';
            if (logId.isNotEmpty) {
              await _recordTombstone(
                transaction,
                entityType: tombstoneReviewLog,
                entityId: logId,
                deletedAt: now,
              );
            }
          }
          await _recordTombstone(
            transaction,
            entityType: tombstoneReviewCard,
            entityId: reviewCardId,
            deletedAt: now,
          );
        }

        final editRows = await transaction.query(
          'reading_card_edits',
          columns: ['term_id'],
          where: 'deck_id = ?',
          whereArgs: [deckId],
        );
        for (final editRow in editRows) {
          final termId = editRow['term_id']?.toString() ?? '';
          if (termId.isNotEmpty) {
            await _recordTombstone(
              transaction,
              entityType: tombstoneReadingCardEdit,
              entityId: compoundEntityId(deckId, termId),
              deletedAt: now,
            );
          }
        }

        await _recordTombstone(
          transaction,
          entityType: tombstoneDeck,
          entityId: deckId,
          deletedAt: now,
        );
      }

      await transaction.delete('decks', where: 'id = ?', whereArgs: [deckId]);
    }
  }

  static Future<void> _saveDeck({
    required Transaction transaction,
    required Deck deck,
    required int position,
    required int now,
    required bool trackLocalChanges,
  }) async {
    if (trackLocalChanges) {
      await _clearTombstone(
        transaction,
        entityType: tombstoneDeck,
        entityId: deck.id,
      );
    }

    await transaction.insert(
      'decks',
      {
        'id': deck.id,
        'name': deck.name,
        'type': _deckTypeToText(deck.type),
        'color_value': deck.colorValue,
        'review_enabled': _boolToInt(deck.reviewEnabled),
        'active_study_mode':
            deck.activeStudyMode == StudyMode.review ? 'review' : 'study',
        'review_enabled_at':
            deck.reviewEnabledAt?.toUtc().millisecondsSinceEpoch,
        'last_study_index': deck.lastStudyIndex,
        'is_shuffled': _boolToInt(deck.isShuffled),
        'position': position,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await transaction.update(
      'decks',
      {
        'name': deck.name,
        'type': _deckTypeToText(deck.type),
        'color_value': deck.colorValue,
        'review_enabled': _boolToInt(deck.reviewEnabled),
        'active_study_mode':
            deck.activeStudyMode == StudyMode.review ? 'review' : 'study',
        'review_enabled_at':
            deck.reviewEnabledAt?.toUtc().millisecondsSinceEpoch,
        'last_study_index': deck.lastStudyIndex,
        'is_shuffled': _boolToInt(deck.isShuffled),
        'position': position,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [deck.id],
    );

    final existingTermRows = await transaction.query(
      'deck_terms',
      columns: ['id', 'source_id'],
      where: 'deck_id = ?',
      whereArgs: [deck.id],
    );
    final savedTermIds = deck.terms.map((term) => term.id).toSet();

    for (final row in existingTermRows) {
      final termId = row['id']?.toString() ?? '';
      if (termId.isEmpty || savedTermIds.contains(termId)) continue;

      if (trackLocalChanges) {
        final sourceId = row['source_id']?.toString() ?? termId;
        await _recordTombstone(
          transaction,
          entityType: tombstoneDeckTerm,
          entityId: compoundEntityId(deck.id, sourceId),
          deletedAt: now,
        );
      }
      await transaction.delete(
        'deck_terms',
        where: 'deck_id = ? AND id = ?',
        whereArgs: [deck.id, termId],
      );
    }

    for (var termIndex = 0; termIndex < deck.terms.length; termIndex++) {
      final term = deck.terms[termIndex];
      final termJson = Map<String, dynamic>.from(term.toJson());
      if (deck.type == DeckType.hybrid) {
        termJson['_hybridCardMode'] =
            _hybridCardModeToText(deck.cardModeFor(term));
      }

      final termSourceId = term.sourceId ?? term.id;
      if (trackLocalChanges) {
        await _clearTombstone(
          transaction,
          entityType: tombstoneDeckTerm,
          entityId: compoundEntityId(deck.id, termSourceId),
        );
      }

      final values = <String, Object?>{
        'deck_id': deck.id,
        'source_id': termSourceId,
        'term_json': jsonEncode(termJson),
        'marked': _boolToInt(term.marked),
        'position': termIndex,
        'updated_at': now,
      };

      await transaction.insert(
        'deck_terms',
        {'id': term.id, ...values, 'created_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await transaction.update(
        'deck_terms',
        values,
        where: 'deck_id = ? AND id = ?',
        whereArgs: [deck.id, term.id],
      );
    }
  }

  static Future<void> _deleteRemovedFolders({
    required Transaction transaction,
    required Set<String> savedFolderIds,
    required bool trackLocalChanges,
    required int now,
  }) async {
    final existingRows = await transaction.query('folders', columns: ['id']);
    for (final row in existingRows) {
      final folderId = row['id']?.toString() ?? '';
      if (folderId.isEmpty || savedFolderIds.contains(folderId)) continue;
      if (trackLocalChanges) {
        await _recordTombstone(
          transaction,
          entityType: tombstoneFolder,
          entityId: folderId,
          deletedAt: now,
        );
      }
      await transaction.delete(
        'folders',
        where: 'id = ?',
        whereArgs: [folderId],
      );
    }
  }

  static Future<void> _saveFolder({
    required Transaction transaction,
    required Folder folder,
    required int position,
    required Set<String> existingDeckIds,
    required int now,
    required bool trackLocalChanges,
  }) async {
    if (trackLocalChanges) {
      await _clearTombstone(
        transaction,
        entityType: tombstoneFolder,
        entityId: folder.id,
      );
    }

    await transaction.insert(
      'folders',
      {
        'id': folder.id,
        'name': folder.name,
        'position': position,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await transaction.update(
      'folders',
      {'name': folder.name, 'position': position, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [folder.id],
    );

    final savedFolderDeckIds = folder.deckIds
        .where((deckId) => existingDeckIds.contains(deckId))
        .toSet();
    final existingRows = await transaction.query(
      'folder_decks',
      columns: ['deck_id'],
      where: 'folder_id = ?',
      whereArgs: [folder.id],
    );

    for (final row in existingRows) {
      final deckId = row['deck_id']?.toString() ?? '';
      if (deckId.isEmpty || savedFolderDeckIds.contains(deckId)) continue;
      if (trackLocalChanges) {
        await _recordTombstone(
          transaction,
          entityType: tombstoneFolderDeck,
          entityId: compoundEntityId(folder.id, deckId),
          deletedAt: now,
        );
      }
      await transaction.delete(
        'folder_decks',
        where: 'folder_id = ? AND deck_id = ?',
        whereArgs: [folder.id, deckId],
      );
    }

    var positionIndex = 0;
    for (final deckId in folder.deckIds) {
      if (!existingDeckIds.contains(deckId)) continue;
      if (trackLocalChanges) {
        await _clearTombstone(
          transaction,
          entityType: tombstoneFolderDeck,
          entityId: compoundEntityId(folder.id, deckId),
        );
      }
      await transaction.insert(
        'folder_decks',
        {
          'folder_id': folder.id,
          'deck_id': deckId,
          'position': positionIndex,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await transaction.update(
        'folder_decks',
        {'position': positionIndex},
        where: 'folder_id = ? AND deck_id = ?',
        whereArgs: [folder.id, deckId],
      );
      positionIndex++;
    }
  }

  static Future<void> _syncPinnedDecks({
    required Transaction transaction,
    required List<String> pinnedDeckIds,
    required Set<String> existingDeckIds,
    required int now,
    required bool trackLocalChanges,
  }) async {
    final savedPinnedDeckIds = pinnedDeckIds
        .where((deckId) => existingDeckIds.contains(deckId))
        .toSet();
    final existingRows = await transaction.query(
      'pinned_decks',
      columns: ['deck_id'],
    );

    for (final row in existingRows) {
      final deckId = row['deck_id']?.toString() ?? '';
      if (deckId.isEmpty || savedPinnedDeckIds.contains(deckId)) continue;
      if (trackLocalChanges) {
        await _recordTombstone(
          transaction,
          entityType: tombstonePin,
          entityId: deckId,
          deletedAt: now,
        );
      }
      await transaction.delete(
        'pinned_decks',
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
    }

    var positionIndex = 0;
    for (final deckId in pinnedDeckIds) {
      if (!existingDeckIds.contains(deckId)) continue;
      if (trackLocalChanges) {
        await _clearTombstone(
          transaction,
          entityType: tombstonePin,
          entityId: deckId,
        );
      }
      await transaction.insert(
        'pinned_decks',
        {
          'deck_id': deckId,
          'position': positionIndex,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await transaction.update(
        'pinned_decks',
        {'position': positionIndex},
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
      positionIndex++;
    }
  }

  static Future<List<ReviewCard>> loadReviewCards() async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'review_cards',
      orderBy: 'due_at ASC, created_at ASC',
    );
    final loadedCards = <ReviewCard>[];

    for (final row in rows) {
      final cardJsonText = row['fsrs_card_json']?.toString() ?? '';
      Map<String, dynamic> cardJson = <String, dynamic>{};

      if (cardJsonText.isNotEmpty) {
        try {
          final decoded = jsonDecode(cardJsonText);

          if (decoded is Map<String, dynamic>) {
            cardJson = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          // Fall back to the normalized database columns below.
        }
      }

      final dueAt = _intFromDatabaseValue(row['due_at']);
      final lastReviewedAt = _nullableIntFromDatabaseValue(
        row['last_reviewed_at'],
      );

      cardJson
        ..['id'] = row['id']?.toString() ?? ''
        ..['deckId'] = row['deck_id']?.toString() ?? ''
        ..['termId'] = row['term_id']?.toString() ?? ''
        ..['cardType'] = row['card_type']?.toString() ?? 'reading'
        ..['dueDate'] = DateTime.fromMillisecondsSinceEpoch(
          dueAt,
          isUtc: true,
        ).toIso8601String();

      if (lastReviewedAt == null) {
        cardJson.remove('lastReviewedAt');
      } else {
        cardJson['lastReviewedAt'] = DateTime.fromMillisecondsSinceEpoch(
          lastReviewedAt,
          isUtc: true,
        ).toIso8601String();
      }

      final card = ReviewCard.fromJson(cardJson);

      if (card.id.isNotEmpty) {
        loadedCards.add(card);
      }
    }

    return loadedCards;
  }

  static Future<void> saveReviewCard(ReviewCard card) async {
    final database = await GakujiUserDatabase.database;
    final encoded = jsonEncode(card.toJson());
    final existing = await database.query(
      'review_cards',
      columns: ['fsrs_card_json'],
      where: 'id = ?',
      whereArgs: [card.id],
      limit: 1,
    );
    if (existing.isNotEmpty &&
        existing.first['fsrs_card_json']?.toString() == encoded) {
      return;
    }

    await database.transaction((transaction) async {
      final now = _now;
      await _saveReviewCardWithExecutor(
        executor: transaction,
        card: card,
        now: now,
        trackLocalChanges: true,
      );
      await _recordDirtyEntity(
        transaction,
        entityType: dirtyReviewCard,
        entityId: card.id,
        changedAt: now,
      );
      await _markLocalDirty(transaction);
    });
  }

  static Future<void> saveReviewResult({
    required ReviewCard card,
    required ReviewLogEntry reviewLog,
  }) async {
    final database = await GakujiUserDatabase.database;

    await database.transaction((transaction) async {
      final now = _now;

      await _saveReviewCardWithExecutor(
        executor: transaction,
        card: card,
        now: now,
        trackLocalChanges: true,
      );

      await _saveReviewLogWithExecutor(
        executor: transaction,
        reviewLog: reviewLog,
        now: now,
      );
      await _recordDirtyEntity(
        transaction,
        entityType: dirtyReviewCard,
        entityId: card.id,
        changedAt: now,
      );
      await _recordDirtyEntity(
        transaction,
        entityType: dirtyReviewLog,
        entityId: reviewLog.id,
        changedAt: now,
      );
      await _markLocalDirty(transaction);
    });
  }

  static Future<void> syncReviewCards(
    List<ReviewCard> cards, {
    bool markDirty = true,
  }) async {
    final database = await GakujiUserDatabase.database;
    final desiredById = <String, String>{
      for (final card in cards) card.id: jsonEncode(card.toJson()),
    };
    final changedCardIds = <String>{};
    final removedCardIds = <String>{};

    if (markDirty) {
      final existingRows = await database.query(
        'review_cards',
        columns: ['id', 'fsrs_card_json'],
      );
      final existingById = <String, String>{
        for (final row in existingRows)
          if ((row['id']?.toString() ?? '').isNotEmpty)
            row['id']!.toString(): row['fsrs_card_json']?.toString() ?? '',
      };

      for (final entry in desiredById.entries) {
        if (existingById[entry.key] != entry.value) {
          changedCardIds.add(entry.key);
        }
      }
      removedCardIds.addAll(
        existingById.keys.where((id) => !desiredById.containsKey(id)),
      );

      if (changedCardIds.isEmpty && removedCardIds.isEmpty) return;
    }

    await database.transaction((transaction) async {
      final retainedIds = cards.map((card) => card.id).toSet();
      final existingRows = await transaction.query(
        'review_cards',
        columns: ['id'],
      );

      for (final row in existingRows) {
        final reviewCardId = row['id']?.toString() ?? '';

        if (reviewCardId.isEmpty || retainedIds.contains(reviewCardId)) {
          continue;
        }

        if (markDirty) {
          final logRows = await transaction.query(
            'review_logs',
            columns: ['id'],
            where: 'review_card_id = ?',
            whereArgs: [reviewCardId],
          );
          for (final logRow in logRows) {
            final logId = logRow['id']?.toString() ?? '';
            if (logId.isNotEmpty) {
              await _recordTombstone(
                transaction,
                entityType: tombstoneReviewLog,
                entityId: logId,
                deletedAt: _now,
              );
            }
          }
          await _recordTombstone(
            transaction,
            entityType: tombstoneReviewCard,
            entityId: reviewCardId,
            deletedAt: _now,
          );
        }
        await transaction.delete(
          'review_cards',
          where: 'id = ?',
          whereArgs: [reviewCardId],
        );
      }

      final now = _now;

      for (final card in cards) {
        await _saveReviewCardWithExecutor(
          executor: transaction,
          card: card,
          now: now,
          trackLocalChanges: markDirty,
        );
        if (markDirty && changedCardIds.contains(card.id)) {
          await _recordDirtyEntity(
            transaction,
            entityType: dirtyReviewCard,
            entityId: card.id,
            changedAt: now,
          );
        }
      }
      if (markDirty &&
          (changedCardIds.isNotEmpty || removedCardIds.isNotEmpty)) {
        await _markLocalDirty(transaction);
      }
    });
  }

  static Future<void> deleteReviewCardsNotInForDeck({
    required String deckId,
    required Set<String> retainedReviewCardIds,
  }) async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'review_cards',
      columns: ['id'],
      where: 'deck_id = ?',
      whereArgs: [deckId],
    );

    var changed = false;
    for (final row in rows) {
      final reviewCardId = row['id']?.toString() ?? '';

      if (reviewCardId.isEmpty || retainedReviewCardIds.contains(reviewCardId)) {
        continue;
      }

      final now = _now;
      final logRows = await database.query(
        'review_logs',
        columns: ['id'],
        where: 'review_card_id = ?',
        whereArgs: [reviewCardId],
      );
      for (final logRow in logRows) {
        final logId = logRow['id']?.toString() ?? '';
        if (logId.isNotEmpty) {
          await _recordTombstone(
            database,
            entityType: tombstoneReviewLog,
            entityId: logId,
            deletedAt: now,
          );
        }
      }
      await _recordTombstone(
        database,
        entityType: tombstoneReviewCard,
        entityId: reviewCardId,
        deletedAt: now,
      );
      await database.delete(
        'review_cards',
        where: 'id = ?',
        whereArgs: [reviewCardId],
      );
      changed = true;
    }

    if (changed) await _markLocalDirty(database);
  }

  static Future<void> deleteReviewCardsForDeck(String deckId) async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'review_cards',
      columns: ['id'],
      where: 'deck_id = ?',
      whereArgs: [deckId],
    );
    if (rows.isEmpty) return;

    await database.transaction((transaction) async {
      final now = _now;
      for (final row in rows) {
        final reviewCardId = row['id']?.toString() ?? '';
        if (reviewCardId.isEmpty) continue;
        final logRows = await transaction.query(
          'review_logs',
          columns: ['id'],
          where: 'review_card_id = ?',
          whereArgs: [reviewCardId],
        );
        for (final logRow in logRows) {
          final logId = logRow['id']?.toString() ?? '';
          if (logId.isNotEmpty) {
            await _recordTombstone(
              transaction,
              entityType: tombstoneReviewLog,
              entityId: logId,
              deletedAt: now,
            );
          }
        }
        await _recordTombstone(
          transaction,
          entityType: tombstoneReviewCard,
          entityId: reviewCardId,
          deletedAt: now,
        );
      }
      await transaction.delete(
        'review_cards',
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
      await _markLocalDirty(transaction);
    });
  }

  static Future<List<ReviewLogEntry>> loadReviewLogs({
    String? reviewCardId,
  }) async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'review_logs',
      where: reviewCardId == null ? null : 'review_card_id = ?',
      whereArgs: reviewCardId == null ? null : [reviewCardId],
      orderBy: 'reviewed_at ASC, created_at ASC',
    );
    final loadedLogs = <ReviewLogEntry>[];

    for (final row in rows) {
      final logJsonText = row['fsrs_log_json']?.toString() ?? '';
      Map<String, dynamic> logJson = <String, dynamic>{};

      if (logJsonText.isNotEmpty) {
        try {
          final decoded = jsonDecode(logJsonText);

          if (decoded is Map<String, dynamic>) {
            logJson = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          // Fall back to the normalized database columns below.
        }
      }

      final reviewedAt = _intFromDatabaseValue(row['reviewed_at']);

      logJson
        ..['id'] = row['id']?.toString() ?? ''
        ..['reviewCardId'] = row['review_card_id']?.toString() ?? ''
        ..['rating'] = _intFromDatabaseValue(row['rating'])
        ..['reviewedAt'] = DateTime.fromMillisecondsSinceEpoch(
          reviewedAt,
          isUtc: true,
        ).toIso8601String();

      final reviewLog = ReviewLogEntry.fromJson(logJson);

      if (reviewLog.id.isNotEmpty) {
        loadedLogs.add(reviewLog);
      }
    }

    return loadedLogs;
  }

  static Future<void> saveReviewLog(ReviewLogEntry reviewLog) async {
    final database = await GakujiUserDatabase.database;
    final encoded = jsonEncode(reviewLog.toJson());
    final existing = await database.query(
      'review_logs',
      columns: ['fsrs_log_json'],
      where: 'id = ?',
      whereArgs: [reviewLog.id],
      limit: 1,
    );
    if (existing.isNotEmpty &&
        existing.first['fsrs_log_json']?.toString() == encoded) {
      return;
    }

    await database.transaction((transaction) async {
      final now = _now;
      await _saveReviewLogWithExecutor(
        executor: transaction,
        reviewLog: reviewLog,
        now: now,
      );
      await _recordDirtyEntity(
        transaction,
        entityType: dirtyReviewLog,
        entityId: reviewLog.id,
        changedAt: now,
      );
      await _markLocalDirty(transaction);
    });
  }

  static Future<void> _saveReviewLogWithExecutor({
    required DatabaseExecutor executor,
    required ReviewLogEntry reviewLog,
    required int now,
  }) async {
    final values = <String, Object?>{
      'review_card_id': reviewLog.reviewCardId,
      'rating': reviewLog.rating.index + 1,
      'reviewed_at': reviewLog.reviewedAt.toUtc().millisecondsSinceEpoch,
      'fsrs_log_json': jsonEncode(reviewLog.toJson()),
    };

    await executor.insert(
      'review_logs',
      {
        'id': reviewLog.id,
        ...values,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await executor.update(
      'review_logs',
      values,
      where: 'id = ?',
      whereArgs: [reviewLog.id],
    );
  }

  static Future<void> _saveReviewCardWithExecutor({
    required DatabaseExecutor executor,
    required ReviewCard card,
    required int now,
    required bool trackLocalChanges,
  }) async {
    if (trackLocalChanges) {
      await _clearTombstone(
        executor,
        entityType: tombstoneReviewCard,
        entityId: card.id,
      );
    }

    final deckRows = await executor.query(
      'decks',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [card.deckId],
      limit: 1,
    );

    if (deckRows.isEmpty) return;

    final values = <String, Object?>{
      'deck_id': card.deckId,
      'term_id': card.termId,
      'card_type': card.cardType.name,
      'fsrs_card_json': jsonEncode(card.toJson()),
      'due_at': card.dueDate.toUtc().millisecondsSinceEpoch,
      'last_reviewed_at': card.lastReviewedAt?.toUtc().millisecondsSinceEpoch,
      'updated_at': now,
    };

    await executor.insert(
      'review_cards',
      {
        'id': card.id,
        ...values,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await executor.update(
      'review_cards',
      values,
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  static int _intFromDatabaseValue(dynamic value, {int fallback = 0}) {
    if (value is int) return value;

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int? _nullableIntFromDatabaseValue(dynamic value) {
    if (value == null) return null;

    return int.tryParse(value.toString());
  }

  static DateTime? _dateTimeFromDatabaseValue(dynamic value) {
    final milliseconds = _nullableIntFromDatabaseValue(value);
    if (milliseconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  static Future<String?> loadDictionaryNote(String sourceId) async {
    final database = await GakujiUserDatabase.database;

    final rows = await database.query(
      'dictionary_notes',
      where: 'source_id = ?',
      whereArgs: [sourceId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return rows.first['note']?.toString();
  }

  static Future<void> saveDictionaryNote({
    required String sourceId,
    required String note,
  }) async {
    final database = await GakujiUserDatabase.database;
    final existing = await database.query(
      'dictionary_notes',
      columns: ['note'],
      where: 'source_id = ?',
      whereArgs: [sourceId],
      limit: 1,
    );
    if (existing.isNotEmpty && existing.first['note']?.toString() == note) {
      return;
    }

    await database.transaction((transaction) async {
      final now = _now;
      await transaction.insert(
        'dictionary_notes',
        {
          'source_id': sourceId,
          'note': note,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _recordDirtyEntity(
        transaction,
        entityType: dirtyDictionaryNote,
        entityId: sourceId,
        changedAt: now,
      );
      await _markLocalDirty(transaction);
    });
  }

  static Future<String?> loadPreference(String key) async {
    final database = await GakujiUserDatabase.database;

    final rows = await database.query(
      'user_preferences',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return rows.first['value']?.toString();
  }

  static Future<void> savePreference({
    required String key,
    required String value,
    bool markDirty = true,
  }) async {
    final database = await GakujiUserDatabase.database;
    final existing = await database.query(
      'user_preferences',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (existing.isNotEmpty && existing.first['value']?.toString() == value) {
      return;
    }

    await database.transaction((transaction) async {
      final now = _now;
      if (markDirty) {
        await _clearTombstone(
          transaction,
          entityType: tombstonePreference,
          entityId: key,
        );
      }
      await transaction.insert(
        'user_preferences',
        {
          'key': key,
          'value': value,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (markDirty) {
        await _recordDirtyEntity(
          transaction,
          entityType: dirtyPreferences,
          entityId: dirtyPreferences,
          changedAt: now,
        );
        await _markLocalDirty(transaction);
      }
    });
  }

  static Future<void> deletePreference(String key) async {
    final database = await GakujiUserDatabase.database;

    final existing = await database.query(
      'user_preferences',
      columns: ['key'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (existing.isEmpty) return;

    await database.transaction((transaction) async {
      final now = _now;
      await _recordTombstone(
        transaction,
        entityType: tombstonePreference,
        entityId: key,
        deletedAt: now,
      );
      await transaction.delete(
        'user_preferences',
        where: 'key = ?',
        whereArgs: [key],
      );
      await _recordDirtyEntity(
        transaction,
        entityType: dirtyPreferences,
        entityId: dirtyPreferences,
        changedAt: now,
      );
      await _markLocalDirty(transaction);
    });
  }


  static Future<ReadingCardEditData?> loadReadingCardEdit({
    required String deckId,
    required String termId,
  }) async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'reading_card_edits',
      columns: ['edit_json'],
      where: 'deck_id = ? AND term_id = ?',
      whereArgs: [deckId, termId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final raw = rows.first['edit_json']?.toString();
    if (raw == null || raw.isEmpty) return null;
    try {
      return ReadingCardEditData.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasReadingCardEdit({
    required String deckId,
    required String termId,
  }) async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'reading_card_edits',
      columns: ['term_id'],
      where: 'deck_id = ? AND term_id = ?',
      whereArgs: [deckId, termId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<void> saveReadingCardEdit(ReadingCardEditData data) async {
    final database = await GakujiUserDatabase.database;
    final encoded = data.toJsonString();
    final existing = await database.query(
      'reading_card_edits',
      columns: ['source_id', 'edit_json'],
      where: 'deck_id = ? AND term_id = ?',
      whereArgs: [data.deckId, data.termId],
      limit: 1,
    );
    if (existing.isNotEmpty &&
        existing.first['source_id']?.toString() == data.sourceId &&
        existing.first['edit_json']?.toString() == encoded) {
      return;
    }

    await database.transaction((transaction) async {
      final now = _now;
      await _clearTombstone(
        transaction,
        entityType: tombstoneReadingCardEdit,
        entityId: compoundEntityId(data.deckId, data.termId),
      );
      await transaction.insert(
        'reading_card_edits',
        {
          'deck_id': data.deckId,
          'term_id': data.termId,
          'source_id': data.sourceId,
          'edit_json': encoded,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _recordDirtyEntity(
        transaction,
        entityType: dirtyReadingCardEdit,
        entityId: compoundEntityId(data.deckId, data.termId),
        changedAt: now,
      );
      await _markLocalDirty(transaction);
    });
  }

  static Future<void> deleteReadingCardEdit({
    required String deckId,
    required String termId,
  }) async {
    final database = await GakujiUserDatabase.database;
    final existing = await database.query(
      'reading_card_edits',
      columns: ['term_id'],
      where: 'deck_id = ? AND term_id = ?',
      whereArgs: [deckId, termId],
      limit: 1,
    );
    if (existing.isEmpty) return;

    await database.transaction((transaction) async {
      final now = _now;
      await _recordTombstone(
        transaction,
        entityType: tombstoneReadingCardEdit,
        entityId: compoundEntityId(deckId, termId),
        deletedAt: now,
      );
      await transaction.delete(
        'reading_card_edits',
        where: 'deck_id = ? AND term_id = ?',
        whereArgs: [deckId, termId],
      );
      await _markLocalDirty(transaction);
    });
  }

  static Future<List<ReadingCardEditData>> loadReadingCardEditsForDeck(
    String deckId,
  ) async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'reading_card_edits',
      columns: ['edit_json'],
      where: 'deck_id = ?',
      whereArgs: [deckId],
      orderBy: 'updated_at ASC',
    );

    final edits = <ReadingCardEditData>[];
    for (final row in rows) {
      final raw = row['edit_json']?.toString();
      if (raw == null || raw.isEmpty) continue;
      try {
        edits.add(ReadingCardEditData.fromJsonString(raw));
      } catch (_) {
        // Skip a corrupted edit rather than blocking the deck.
      }
    }
    return edits;
  }

  static Future<List<ReadingCardEditData>> loadReadingCardEdits() async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'reading_card_edits',
      orderBy: 'updated_at ASC',
    );
    final edits = <ReadingCardEditData>[];
    for (final row in rows) {
      final raw = row['edit_json']?.toString();
      if (raw == null || raw.isEmpty) continue;
      try {
        edits.add(ReadingCardEditData.fromJsonString(raw));
      } catch (_) {
        // Skip a corrupted edit rather than blocking the deck.
      }
    }
    return edits;
  }

  /// Replaces review history with an exact snapshot. Cloud pulls use this so
  /// deletions made on another device are reflected locally as well.
  static Future<void> replaceReviewLogs(
    List<ReviewLogEntry> logs, {
    bool markDirty = true,
  }) async {
    final database = await GakujiUserDatabase.database;
    await database.transaction((transaction) async {
      await transaction.delete('review_logs');
      final now = _now;
      for (final log in logs) {
        await _saveReviewLogWithExecutor(
          executor: transaction,
          reviewLog: log,
          now: now,
        );
      }
      if (markDirty) {
        await _recordDirtyEntity(
          transaction,
          entityType: dirtyWorkspace,
          entityId: dirtyWorkspace,
          changedAt: _now,
        );
        await _markLocalDirty(transaction);
      }
    });
  }

  /// Replaces only preferences that participate in cloud synchronization.
  /// Device-only/internal preferences remain untouched.
  static Future<void> replaceSyncablePreferences(
    Map<String, String> preferences, {
    bool markDirty = true,
  }) async {
    final database = await GakujiUserDatabase.database;
    await database.transaction((transaction) async {
      final existing = await transaction.query(
        'user_preferences',
        columns: ['key'],
      );
      for (final row in existing) {
        final key = row['key']?.toString() ?? '';
        if (key.isEmpty ||
            key.startsWith('__') ||
            key == 'gakuji_user_data_initialized') {
          continue;
        }
        if (!preferences.containsKey(key)) {
          await transaction.delete(
            'user_preferences',
            where: 'key = ?',
            whereArgs: [key],
          );
        }
      }

      final now = _now;
      for (final entry in preferences.entries) {
        if (markDirty) {
          await _clearTombstone(
            transaction,
            entityType: tombstonePreference,
            entityId: entry.key,
          );
        }
        await transaction.insert(
          'user_preferences',
          {
            'key': entry.key,
            'value': entry.value,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (markDirty) {
        await _recordDirtyEntity(
          transaction,
          entityType: dirtyWorkspace,
          entityId: dirtyWorkspace,
          changedAt: _now,
        );
        await _markLocalDirty(transaction);
      }
    });
  }

  static Future<void> replaceDictionaryNotes(
    Map<String, String> notes, {
    bool markDirty = true,
  }) async {
    final database = await GakujiUserDatabase.database;
    await database.transaction((transaction) async {
      await transaction.delete('dictionary_notes');
      final now = _now;
      for (final entry in notes.entries) {
        await transaction.insert(
          'dictionary_notes',
          {
            'source_id': entry.key,
            'note': entry.value,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (markDirty) {
        await _recordDirtyEntity(
          transaction,
          entityType: dirtyWorkspace,
          entityId: dirtyWorkspace,
          changedAt: _now,
        );
        await _markLocalDirty(transaction);
      }
    });
  }

  static Future<void> replaceReadingCardEdits(
    List<ReadingCardEditData> edits, {
    bool markDirty = true,
  }) async {
    final database = await GakujiUserDatabase.database;
    await database.transaction((transaction) async {
      await transaction.delete('reading_card_edits');
      final now = _now;
      for (final data in edits) {
        if (markDirty) {
          await _clearTombstone(
            transaction,
            entityType: tombstoneReadingCardEdit,
            entityId: compoundEntityId(data.deckId, data.termId),
          );
        }
        await transaction.insert(
          'reading_card_edits',
          {
            'deck_id': data.deckId,
            'term_id': data.termId,
            'source_id': data.sourceId,
            'edit_json': data.toJsonString(),
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (markDirty) {
        await _recordDirtyEntity(
          transaction,
          entityType: dirtyWorkspace,
          entityId: dirtyWorkspace,
          changedAt: _now,
        );
        await _markLocalDirty(transaction);
      }
    });
  }

  static Future<Map<String, String>> loadSyncablePreferences() async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query('user_preferences');
    final preferences = <String, String>{};

    for (final row in rows) {
      final key = row['key']?.toString() ?? '';
      final value = row['value']?.toString();
      if (key.isEmpty || value == null) continue;
      if (key.startsWith('__') || key == 'gakuji_user_data_initialized') {
        continue;
      }
      preferences[key] = value;
    }

    return preferences;
  }

  static Future<Map<String, String>> loadDictionaryNotes() async {
    final database = await GakujiUserDatabase.database;
    final rows = await database.query('dictionary_notes');
    final notes = <String, String>{};

    for (final row in rows) {
      final sourceId = row['source_id']?.toString() ?? '';
      final note = row['note']?.toString();
      if (sourceId.isEmpty || note == null) continue;
      notes[sourceId] = note;
    }

    return notes;
  }

  static Future<void> clearAllData() {
    return GakujiUserDatabase.clearUserData();
  }
}
