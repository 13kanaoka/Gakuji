import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/reading_card_edit_data.dart';
import '../models/deck.dart';
import '../models/folder.dart';
import '../models/review_card.dart';
import '../models/term.dart';
import 'gakuji_user_repository.dart';
import 'gakuji_term_payload_repair.dart';

class _DeckCloudTermRecord {
  final String stableKey;
  final Term term;
  final HybridCardMode? hybridMode;
  final Map<String, dynamic> data;
  final int stableHash;
  final int approxBytes;

  const _DeckCloudTermRecord({
    required this.stableKey,
    required this.term,
    required this.hybridMode,
    required this.data,
    required this.stableHash,
    required this.approxBytes,
  });
}

class _DeckCloudChunk {
  final String id;
  final List<_DeckCloudTermRecord> records;
  final String hash;

  const _DeckCloudChunk({
    required this.id,
    required this.records,
    required this.hash,
  });
}

class _DeckChunkManifestEntry {
  final String hash;
  final String documentId;

  const _DeckChunkManifestEntry({
    required this.hash,
    required this.documentId,
  });

  Map<String, dynamic> toJson() {
    return {
      'hash': hash,
      'documentId': documentId,
    };
  }
}

class _DeckRemoteTermPiece {
  final String stableKey;
  final Term term;
  final HybridCardMode? hybridMode;

  const _DeckRemoteTermPiece({
    required this.stableKey,
    required this.term,
    required this.hybridMode,
  });
}

/// Firestore is a synchronization junction, never Gakuji's working database.
///
/// Every study feature reads/writes SQLite through [GakujiUserRepository].
/// This service only mirrors that local workspace to/from the signed-in user's
/// Firestore area when a connection is available.
class GakujiCloudSyncService {
  static const Duration pushDebounce = Duration(seconds: 8);
  static const int _batchLimit = 100;
  static const Duration _deltaWriteBackpressure = Duration(milliseconds: 25);
  static const int _snapshotBatchLimit = 50;
  static const Duration _snapshotWriteBackpressure = Duration(milliseconds: 75);
  static const int _deckTermStorageVersion = 2;
  static const int _baseTermChunkBuckets = 32;
  static const int _maxTermsPerChunk = 75;
  static const int _maxApproxTermChunkBytes = 300 * 1024;
  static const int _chunkFetchConcurrency = 4;

  static Timer? _pushTimer;
  static bool _syncing = false;
  static bool _syncRequested = false;
  static bool _accountDeletionSuspended = false;

  static User? get _user => FirebaseAuth.instance.currentUser;

  static bool get canSync {
    final user = _user;
    return user != null && !user.isAnonymous && !_accountDeletionSuspended;
  }

  static DocumentReference<Map<String, dynamic>> get _userDoc {
    final user = _user;
    if (user == null || user.isAnonymous) {
      throw StateError('Cloud sync requires a registered Firebase user.');
    }
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  /// Schedules a conservative delta push after a local save.
  ///
  /// SQLite already knows exactly which entities changed. After a quiet period
  /// the worker performs one lightweight root-metadata read to avoid overwriting
  /// unseen cross-device/Manamoji work, then writes only the dirty documents.
  static void schedulePush() {
    if (!canSync) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDebounce, () {
      unawaited(_runBackgroundPush());
    });
  }

  static Future<void> _runBackgroundPush() async {
    try {
      await _pushPendingChanges();
    } catch (_) {
      // Offline/background failure is expected. SQLite remains authoritative,
      // and the dirty queue is retained for the next retry.
    }
  }

  static Future<void> waitForIdle() async {
    while (_syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  /// Stops background cloud work while a permanent account deletion is in
  /// progress. This prevents a delayed local save from recreating Firestore
  /// documents after the deletion cleanup has started.
  static Future<void> suspendForAccountDeletion() async {
    _accountDeletionSuspended = true;
    _pushTimer?.cancel();
    _pushTimer = null;
    _syncRequested = false;
    _forcePullRequested = false;
    await waitForIdle();
  }

  /// Restores normal synchronization after a failed deletion attempt. On a
  /// successful deletion the Firebase user is already gone, so this simply
  /// leaves the service ready for the next signed-in session.
  static void resumeAfterAccountDeletion() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _syncRequested = false;
    _forcePullRequested = false;
    _accountDeletionSuspended = false;
  }

  static Future<void> flushPendingPush() async {
    _pushTimer?.cancel();
    _pushTimer = null;
    if (!canSync) return;

    await waitForIdle();
    if (!await GakujiUserRepository.hasUnsyncedChanges()) return;
    await _pushPendingChanges();
    await waitForIdle();
  }

  /// Bidirectional synchronization for deliberate remote checks such as app
  /// launch and pull-to-refresh.
  ///
  /// A normal launch performs one lightweight user-document metadata read. The
  /// expensive collections are fetched only when the cloud timestamp is newer,
  /// the device has never bootstrapped, or [forcePull] is explicitly requested.
  static Future<bool> syncNow({bool forcePull = false}) async {
    if (!canSync) return false;
    if (_syncing) {
      _syncRequested = true;
      _forcePullRequested = _forcePullRequested || forcePull;
      return false;
    }
    _syncing = true;

    try {
      final bootstrapComplete =
          await GakujiUserRepository.cloudBootstrapComplete();
      final localWasDirty = await GakujiUserRepository.hasUnsyncedChanges();
      final syncStartVersion =
          await GakujiUserRepository.localChangeVersion();
      final lastSyncAt = await GakujiUserRepository.lastCloudSyncAtMs();
      final lastRevision = await GakujiUserRepository.lastCloudRevision();

      // This is intentionally the only routine Firestore read on launch.
      final rootSnapshot = await _userDoc.get();
      final rootData = rootSnapshot.data() ?? const <String, dynamic>{};
      final remoteUpdatedAt = _asInt(rootData['studyDataUpdatedAtMs']);
      final remoteRevision = _asInt(rootData['studyDataRevision']);

      final shouldPull = !bootstrapComplete ||
          forcePull ||
          remoteRevision > lastRevision ||
          (remoteUpdatedAt > 0 && remoteUpdatedAt > lastSyncAt);

      var pulledAnything = false;
      if (shouldPull) {
        pulledAnything = await _pullAndMerge(
          rootData: rootData,
          preferRemote: !localWasDirty,
          preserveLegacyLocalOnlyData: !bootstrapComplete,
        );
      }

      if (!bootstrapComplete) {
        // Initial hydration/migration is intentionally allowed to use a full
        // snapshot. It happens once, after the remote state has been considered.
        await _pushLocalSnapshotInternal(baseCloudRevision: remoteRevision);
        return true;
      }

      if (await GakujiUserRepository.hasUnsyncedChanges()) {
        await _pushPendingChangesInternal(
          baseCloudRevision: remoteRevision,
        );
        return true;
      }

      if (pulledAnything) {
        final syncedAt = remoteUpdatedAt > 0
            ? remoteUpdatedAt
            : DateTime.now().millisecondsSinceEpoch;
        final finalized = await GakujiUserRepository.finalizeCloudSync(
          syncedAtMs: syncedAt,
          syncedRevision: remoteRevision,
          expectedLocalChangeVersion: syncStartVersion,
        );
        if (!finalized) {
          _syncRequested = true;
        }
      }

      return pulledAnything;
    } finally {
      _syncing = false;
      _scheduleRequestedRerun();
    }
  }

  /// Backward-compatible entry point. Normal pushes are now delta-based; a full
  /// snapshot is reserved for bootstrap/fallback repair paths.
  static Future<void> pushLocalSnapshot() async {
    if (!canSync) return;
    if (!await GakujiUserRepository.hasUnsyncedChanges()) return;
    await _pushPendingChanges();
  }

  static bool _forcePullRequested = false;

  static void _scheduleRequestedRerun() {
    final rerun = _syncRequested;
    final forcePull = _forcePullRequested;
    _syncRequested = false;
    _forcePullRequested = false;

    if (!rerun || !canSync) return;
    if (forcePull) {
      unawaited(syncNow(forcePull: true));
    } else {
      unawaited(_runBackgroundPush());
    }
  }

  static Future<void> _pushPendingChanges() async {
    if (!canSync) return;
    if (_syncing) {
      _syncRequested = true;
      return;
    }

    _syncing = true;
    try {
      if (!await GakujiUserRepository.hasUnsyncedChanges()) return;

      final bootstrapComplete =
          await GakujiUserRepository.cloudBootstrapComplete();
      final lastSyncAt = await GakujiUserRepository.lastCloudSyncAtMs();
      final lastRevision = await GakujiUserRepository.lastCloudRevision();

      // One small metadata read protects delta writes from silently overwriting
      // cloud changes made by another Gakuji device or Manamoji. Collection
      // reads happen only when this marker says the cloud actually changed.
      final rootSnapshot = await _userDoc.get();
      final rootData = rootSnapshot.data() ?? const <String, dynamic>{};
      final remoteUpdatedAt = _asInt(rootData['studyDataUpdatedAtMs']);
      final remoteRevision = _asInt(rootData['studyDataRevision']);
      final remoteChanged = !bootstrapComplete ||
          remoteRevision > lastRevision ||
          (remoteUpdatedAt > 0 && remoteUpdatedAt > lastSyncAt);

      if (remoteChanged) {
        await _pullAndMerge(
          rootData: rootData,
          preferRemote: false,
          preserveLegacyLocalOnlyData: !bootstrapComplete,
        );
      }

      if (!bootstrapComplete) {
        await _pushLocalSnapshotInternal(baseCloudRevision: remoteRevision);
      } else {
        await _pushPendingChangesInternal(
          baseCloudRevision: remoteRevision,
        );
      }
    } finally {
      _syncing = false;
      _scheduleRequestedRerun();
    }
  }

  static Future<void> _pushPendingChangesInternal({
    required int baseCloudRevision,
  }) async {
    final snapshotVersion = await GakujiUserRepository.localChangeVersion();
    final dirtyEntities = await GakujiUserRepository.loadDirtyEntities();
    final tombstones = await GakujiUserRepository.loadSyncTombstones();

    // A v5 device can upgrade while it already has unsynced work, or a legacy
    // call path may still mark the workspace dirty without naming an entity.
    // Preserve correctness with one exceptional full snapshot, then all future
    // changes use the delta queue.
    final needsFullFallback = dirtyEntities.any(
          (item) => item.entityType == GakujiUserRepository.dirtyWorkspace,
        ) ||
        (dirtyEntities.isEmpty && tombstones.isEmpty);
    if (needsFullFallback) {
      await _pushLocalSnapshotInternal(baseCloudRevision: baseCloudRevision);
      return;
    }

    final dirtyByType = <String, Set<String>>{};
    for (final item in dirtyEntities) {
      dirtyByType.putIfAbsent(item.entityType, () => <String>{}).add(item.entityId);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final firestore = FirebaseFirestore.instance;
    var batch = firestore.batch();
    var operationCount = 0;

    Future<void> flushBatch() async {
      if (operationCount == 0) return;
      await batch.commit();
      batch = firestore.batch();
      operationCount = 0;
      await Future<void>.delayed(_deltaWriteBackpressure);
    }

    Future<void> setDocument(
      DocumentReference<Map<String, dynamic>> reference,
      Map<String, dynamic> data,
    ) async {
      batch.set(reference, data);
      operationCount++;
      if (operationCount >= _batchLimit) await flushBatch();
    }

    Future<void> deleteDocument(
      DocumentReference<Map<String, dynamic>> reference,
    ) async {
      batch.delete(reference);
      operationCount++;
      if (operationCount >= _batchLimit) await flushBatch();
    }

    final dirtyDeckIds =
        dirtyByType[GakujiUserRepository.dirtyDeck] ?? const <String>{};
    if (dirtyDeckIds.isNotEmpty) {
      final decks = await GakujiUserRepository.loadDecks();
      var mergedLegacyRemoteTerms = false;
      final tombstoneKeys = tombstones.map((item) => item.key).toSet();

      for (var index = 0; index < decks.length; index++) {
        final deck = decks[index];
        if (!dirtyDeckIds.contains(deck.id)) continue;

        final mergedRemoteTerms = await _pushDeckWithChunks(
          deck: deck,
          position: index,
          now: now,
          preserveRemoteOnlyTerms: true,
          tombstoneKeys: tombstoneKeys,
        );
        mergedLegacyRemoteTerms =
            mergedLegacyRemoteTerms || mergedRemoteTerms;
      }

      if (mergedLegacyRemoteTerms) {
        await GakujiUserRepository.saveAll(
          decks: decks,
          folders: await GakujiUserRepository.loadFolders(),
          pinnedDeckIds: await GakujiUserRepository.loadPinnedDeckIds(),
          markDirty: false,
        );
      }
    }

    final dirtyDeckRuntimeIds =
        dirtyByType[GakujiUserRepository.dirtyDeckRuntime] ?? const <String>{};
    if (dirtyDeckRuntimeIds.isNotEmpty) {
      final decks = await GakujiUserRepository.loadDecks();
      for (var index = 0; index < decks.length; index++) {
        final deck = decks[index];
        if (!dirtyDeckRuntimeIds.contains(deck.id) ||
            dirtyDeckIds.contains(deck.id)) {
          continue;
        }

        final deckReference = _userDoc.collection('decks').doc(deck.id);
        try {
          await deckReference.update({
            'reviewEnabled': deck.reviewEnabled,
            'activeStudyMode': deck.activeStudyMode.name,
            'reviewEnabledAt':
                deck.reviewEnabledAt?.toUtc().toIso8601String(),
            'lastStudyIndex': deck.lastStudyIndex,
            'isShuffled': deck.isShuffled,
            'updatedAtMs': now,
          });
        } on FirebaseException catch (error) {
          if (error.code != 'not-found') rethrow;
          await _pushDeckWithChunks(
            deck: deck,
            position: index,
            now: now,
            preserveRemoteOnlyTerms: false,
            tombstoneKeys: const <String>{},
          );
        }
      }
    }

    final dirtyFolderIds =
        dirtyByType[GakujiUserRepository.dirtyFolder] ?? const <String>{};
    if (dirtyFolderIds.isNotEmpty) {
      final folders = await GakujiUserRepository.loadFolders();
      for (var index = 0; index < folders.length; index++) {
        final folder = folders[index];
        if (!dirtyFolderIds.contains(folder.id)) continue;
        await setDocument(
          _userDoc.collection('folders').doc(folder.id),
          {
            'name': folder.name,
            'deckIds': folder.deckIds,
            'position': index,
            'updatedAtMs': now,
          },
        );
      }
    }

    final dirtyReviewCardIds =
        dirtyByType[GakujiUserRepository.dirtyReviewCard] ?? const <String>{};
    if (dirtyReviewCardIds.isNotEmpty) {
      final cards = await GakujiUserRepository.loadReviewCards();
      for (final card in cards) {
        if (!dirtyReviewCardIds.contains(card.id)) continue;
        await setDocument(
          _userDoc.collection('reviewCards').doc(card.id),
          {...card.toJson(), 'updatedAtMs': now},
        );
      }
    }

    final dirtyReviewLogIds =
        dirtyByType[GakujiUserRepository.dirtyReviewLog] ?? const <String>{};
    if (dirtyReviewLogIds.isNotEmpty) {
      final logs = await GakujiUserRepository.loadReviewLogs();
      for (final log in logs) {
        if (!dirtyReviewLogIds.contains(log.id)) continue;
        await setDocument(
          _userDoc.collection('reviewLogs').doc(log.id),
          {...log.toJson(), 'updatedAtMs': now},
        );
      }
    }

    final dirtyNoteIds =
        dirtyByType[GakujiUserRepository.dirtyDictionaryNote] ?? const <String>{};
    if (dirtyNoteIds.isNotEmpty) {
      final notes = await GakujiUserRepository.loadDictionaryNotes();
      for (final sourceId in dirtyNoteIds) {
        final note = notes[sourceId];
        if (note == null) continue;
        await setDocument(
          _userDoc.collection('dictionaryNotes').doc(sourceId),
          {
            'sourceId': sourceId,
            'note': note,
            'updatedAtMs': now,
          },
        );
      }
    }

    final dirtyEditIds =
        dirtyByType[GakujiUserRepository.dirtyReadingCardEdit] ?? const <String>{};
    if (dirtyEditIds.isNotEmpty) {
      final edits = await GakujiUserRepository.loadReadingCardEdits();
      for (final edit in edits) {
        final compoundId =
            GakujiUserRepository.compoundEntityId(edit.deckId, edit.termId);
        if (!dirtyEditIds.contains(compoundId)) continue;
        await setDocument(
          _userDoc.collection('readingCardEdits').doc(_readingEditDocumentId(edit)),
          {
            ...edit.toJson(),
            'photoPath': null,
            'updatedAtMs': now,
          },
        );
      }
    }

    for (final tombstone in tombstones) {
      switch (tombstone.entityType) {
        case GakujiUserRepository.tombstoneDeck:
          await flushBatch();
          await _deleteCloudDeck(tombstone.entityId);
          break;
        case GakujiUserRepository.tombstoneFolder:
          await deleteDocument(_userDoc.collection('folders').doc(tombstone.entityId));
          break;
        case GakujiUserRepository.tombstoneReviewCard:
          await deleteDocument(
            _userDoc.collection('reviewCards').doc(tombstone.entityId),
          );
          break;
        case GakujiUserRepository.tombstoneReviewLog:
          await deleteDocument(
            _userDoc.collection('reviewLogs').doc(tombstone.entityId),
          );
          break;
        case GakujiUserRepository.tombstoneReadingCardEdit:
          final cloudId = _readingEditDocumentIdFromCompound(tombstone.entityId);
          if (cloudId != null) {
            await deleteDocument(_userDoc.collection('readingCardEdits').doc(cloudId));
          }
          break;
      }
    }

    await flushBatch();

    final rootAllDirty =
        (dirtyByType[GakujiUserRepository.dirtyRoot] ?? const <String>{}).isNotEmpty;
    final pinsDirty = rootAllDirty ||
        (dirtyByType[GakujiUserRepository.dirtyPinnedDecks] ?? const <String>{})
            .isNotEmpty;
    final recentDirty = rootAllDirty ||
        (dirtyByType[GakujiUserRepository.dirtyRecentSearches] ?? const <String>{})
            .isNotEmpty;
    final preferencesDirty = rootAllDirty ||
        (dirtyByType[GakujiUserRepository.dirtyPreferences] ?? const <String>{})
            .isNotEmpty;

    final rootUpdate = <String, dynamic>{
      'studyDataUpdatedAtMs': now,
      'studyDataRevision': FieldValue.increment(1),
      'deckStorageVersion': _deckTermStorageVersion,
    };
    if (pinsDirty) {
      rootUpdate['pinnedDeckIds'] =
          await GakujiUserRepository.loadPinnedDeckIds();
    }
    if (recentDirty) {
      final recentSearches = await GakujiUserRepository.loadRecentSearches();
      rootUpdate['recentSearches'] =
          recentSearches.map((term) => term.toJson()).toList();
    }
    if (preferencesDirty) {
      rootUpdate['preferences'] =
          await GakujiUserRepository.loadSyncablePreferences();
    }

    try {
      await _userDoc.update(rootUpdate);
    } on FirebaseException catch (error) {
      if (error.code != 'not-found') rethrow;
      await _userDoc.set(rootUpdate, SetOptions(merge: true));
    }

    final finalized = await GakujiUserRepository.finalizeCloudSync(
      syncedAtMs: now,
      syncedRevision: baseCloudRevision + 1,
      expectedLocalChangeVersion: snapshotVersion,
    );
    if (!finalized) {
      _syncRequested = true;
    }
  }

  /// Full collection mirroring is intentionally retained only for first
  /// bootstrap and legacy/fallback repair. It is not used for ordinary saves.
  static Future<void> _pushLocalSnapshotInternal({
    required int baseCloudRevision,
  }) async {
    final snapshotVersion = await GakujiUserRepository.localChangeVersion();
    final now = DateTime.now().millisecondsSinceEpoch;
    final decks = await GakujiUserRepository.loadDecks();
    final folders = await GakujiUserRepository.loadFolders();
    final pinnedDeckIds = await GakujiUserRepository.loadPinnedDeckIds();
    final recentSearches = await GakujiUserRepository.loadRecentSearches();
    final preferences = await GakujiUserRepository.loadSyncablePreferences();
    final reviewCards = await GakujiUserRepository.loadReviewCards();
    final reviewLogs = await GakujiUserRepository.loadReviewLogs();
    final dictionaryNotes = await GakujiUserRepository.loadDictionaryNotes();
    final readingCardEdits =
        await GakujiUserRepository.loadReadingCardEdits();

    await _replaceDeckCollection(
      decks: decks,
      now: now,
    );

    await _replaceCollection(
      collection: _userDoc.collection('folders'),
      documents: {
        for (var index = 0; index < folders.length; index++)
          folders[index].id: {
            'name': folders[index].name,
            'deckIds': folders[index].deckIds,
            'position': index,
            'updatedAtMs': now,
          },
      },
    );

    await _replaceCollection(
      collection: _userDoc.collection('reviewCards'),
      documents: {
        for (final card in reviewCards)
          card.id: {...card.toJson(), 'updatedAtMs': now},
      },
    );

    await _replaceCollection(
      collection: _userDoc.collection('reviewLogs'),
      documents: {
        for (final log in reviewLogs)
          log.id: {...log.toJson(), 'updatedAtMs': now},
      },
    );

    await _replaceCollection(
      collection: _userDoc.collection('dictionaryNotes'),
      documents: {
        for (final entry in dictionaryNotes.entries)
          entry.key: {
            'sourceId': entry.key,
            'note': entry.value,
            'updatedAtMs': now,
          },
      },
    );

    await _replaceCollection(
      collection: _userDoc.collection('readingCardEdits'),
      documents: {
        for (final edit in readingCardEdits)
          _readingEditDocumentId(edit): {
            ...edit.toJson(),
            'photoPath': null,
            'updatedAtMs': now,
          },
      },
    );

    final rootSnapshot = <String, dynamic>{
      'pinnedDeckIds': pinnedDeckIds,
      'recentSearches': recentSearches.map((term) => term.toJson()).toList(),
      'preferences': preferences,
      'studyDataUpdatedAtMs': now,
      'studyDataRevision': FieldValue.increment(1),
      'deckStorageVersion': _deckTermStorageVersion,
    };
    try {
      await _userDoc.update(rootSnapshot);
    } on FirebaseException catch (error) {
      if (error.code != 'not-found') rethrow;
      await _userDoc.set(rootSnapshot, SetOptions(merge: true));
    }

    final finalized = await GakujiUserRepository.finalizeCloudSync(
      syncedAtMs: now,
      syncedRevision: baseCloudRevision + 1,
      expectedLocalChangeVersion: snapshotVersion,
    );
    if (!finalized) {
      _syncRequested = true;
    }
  }

  static Future<bool> _pullAndMerge({
    required Map<String, dynamic> rootData,
    required bool preferRemote,
    required bool preserveLegacyLocalOnlyData,
  }) async {
    final localDecks = await GakujiUserRepository.loadDecks();
    var remoteDecks = await _loadCloudDecks(localDecks: localDecks);
    var remoteFolders = await _loadCloudFolders();
    var remoteReviewCards = await _loadCloudReviewCards();
    final remoteReviewLogs = await _loadCloudReviewLogs();
    final remoteNotes = await _loadCloudDictionaryNotes();
    var remoteEdits = await _loadCloudReadingCardEdits();
    var remotePinned = _stringList(rootData['pinnedDeckIds']);
    final remoteRecent = _termsFromList(rootData['recentSearches']);
    var remotePreferences = _stringMap(rootData['preferences']);

    // A local edit may have happened while the network reads above were in
    // flight. Re-check before choosing an exact remote replacement.
    final useRemoteSnapshot =
        preferRemote && !await GakujiUserRepository.hasUnsyncedChanges();

    final localDirtyTypes = <String>{};
    final localTombstoneTypes = <String>{};

    // Local deletions must survive the pre-push pull. Without tombstones, a
    // just-deleted deck/term/folder would simply be downloaded again before the
    // local snapshot had a chance to remove it from Firestore.
    if (!useRemoteSnapshot) {
      localDirtyTypes.addAll(
        (await GakujiUserRepository.loadDirtyEntities())
            .map((item) => item.entityType),
      );
      final tombstones = await GakujiUserRepository.loadSyncTombstones();
      localTombstoneTypes.addAll(tombstones.map((item) => item.entityType));
      final keys = tombstones.map((item) => item.key).toSet();
      remoteDecks = _applyDeckTombstones(remoteDecks, keys);
      remoteFolders = _applyFolderTombstones(remoteFolders, keys);
      remoteReviewCards = remoteReviewCards.where((card) {
        return !_hasTombstone(
          keys,
          GakujiUserRepository.tombstoneReviewCard,
          card.id,
        );
      }).toList();
      remoteEdits = remoteEdits.where((edit) {
        return !_hasTombstone(
          keys,
          GakujiUserRepository.tombstoneReadingCardEdit,
          GakujiUserRepository.compoundEntityId(edit.deckId, edit.termId),
        );
      }).toList();
      remotePinned = remotePinned.where((deckId) {
        return !_hasTombstone(
          keys,
          GakujiUserRepository.tombstonePin,
          deckId,
        );
      }).toList();
      remotePreferences = Map<String, String>.from(remotePreferences)
        ..removeWhere((key, value) {
          return _hasTombstone(
            keys,
            GakujiUserRepository.tombstonePreference,
            key,
          );
        });
    }

    final remoteHasStudyData = remoteDecks.isNotEmpty ||
        remoteFolders.isNotEmpty ||
        remoteReviewCards.isNotEmpty ||
        remoteReviewLogs.isNotEmpty ||
        remoteNotes.isNotEmpty ||
        remoteEdits.isNotEmpty ||
        remotePinned.isNotEmpty ||
        remoteRecent.isNotEmpty ||
        remotePreferences.isNotEmpty ||
        rootData.containsKey('studyDataUpdatedAtMs') ||
        rootData.containsKey('studyDataRevision');

    if (!remoteHasStudyData) return false;

    final localFolders = await GakujiUserRepository.loadFolders();
    final localPinned = await GakujiUserRepository.loadPinnedDeckIds();
    final localRecent = await GakujiUserRepository.loadRecentSearches();
    final localPreferences =
        await GakujiUserRepository.loadSyncablePreferences();
    final localReviewCards = await GakujiUserRepository.loadReviewCards();
    final localReviewLogs = await GakujiUserRepository.loadReviewLogs();
    final localNotes = await GakujiUserRepository.loadDictionaryNotes();
    final localEdits = await GakujiUserRepository.loadReadingCardEdits();

    // A newer cloud revision may contain terms written by an older Gakuji or
    // Manamoji build that only stored id/spelling. Never let such a remote copy
    // downgrade a complete local deck-owned lexical payload. Prefer the complete
    // local copy when available, otherwise repair from the on-device dictionary.
    await GakujiTermPayloadRepair.repairDecks(
      remoteDecks,
      fallbackDecks: localDecks,
    );

    final workspaceLocallyDirty =
        localDirtyTypes.contains(GakujiUserRepository.dirtyWorkspace);
    final decksLocallyDirty = workspaceLocallyDirty ||
        localDirtyTypes.contains(GakujiUserRepository.dirtyDeck) ||
        localDirtyTypes.contains(GakujiUserRepository.dirtyDeckRuntime) ||
        localTombstoneTypes.contains(GakujiUserRepository.tombstoneDeck) ||
        localTombstoneTypes.contains(GakujiUserRepository.tombstoneDeckTerm);
    final foldersLocallyDirty = workspaceLocallyDirty ||
        localDirtyTypes.contains(GakujiUserRepository.dirtyFolder) ||
        localTombstoneTypes.contains(GakujiUserRepository.tombstoneFolder) ||
        localTombstoneTypes.contains(GakujiUserRepository.tombstoneFolderDeck);
    final reviewCardsLocallyDirty = workspaceLocallyDirty ||
        localDirtyTypes.contains(GakujiUserRepository.dirtyReviewCard) ||
        localTombstoneTypes.contains(GakujiUserRepository.tombstoneReviewCard);
    final reviewLogsLocallyDirty = workspaceLocallyDirty ||
        localDirtyTypes.contains(GakujiUserRepository.dirtyReviewLog) ||
        localTombstoneTypes.contains(GakujiUserRepository.tombstoneReviewLog);
    final notesLocallyDirty = workspaceLocallyDirty ||
        localDirtyTypes.contains(GakujiUserRepository.dirtyDictionaryNote);
    final editsLocallyDirty = workspaceLocallyDirty ||
        localDirtyTypes.contains(GakujiUserRepository.dirtyReadingCardEdit) ||
        localTombstoneTypes.contains(
          GakujiUserRepository.tombstoneReadingCardEdit,
        );

    final mergedDecks = useRemoteSnapshot || !decksLocallyDirty
        ? remoteDecks
        : _mergeDecksLocalFirst(localDecks, remoteDecks);
    final mergedFolders = useRemoteSnapshot || !foldersLocallyDirty
        ? remoteFolders
        : _mergeFoldersLocalFirst(localFolders, remoteFolders);
    final rootAllDirty = localDirtyTypes.contains(
      GakujiUserRepository.dirtyRoot,
    ) ||
        localDirtyTypes.contains(GakujiUserRepository.dirtyWorkspace);
    final pinsLocallyDirty = rootAllDirty ||
        localDirtyTypes.contains(GakujiUserRepository.dirtyPinnedDecks);
    final recentLocallyDirty = rootAllDirty ||
        localDirtyTypes.contains(GakujiUserRepository.dirtyRecentSearches);
    final preferencesLocallyDirty = rootAllDirty ||
        localDirtyTypes.contains(GakujiUserRepository.dirtyPreferences);

    final mergedPinned = useRemoteSnapshot || !pinsLocallyDirty
        ? remotePinned
        : localPinned;
    final mergedRecent = useRemoteSnapshot || !recentLocallyDirty
        ? remoteRecent
        : _mergeRecentSearches(localRecent, remoteRecent);
    final mergedPreferences = useRemoteSnapshot || !preferencesLocallyDirty
        ? remotePreferences
        : <String, String>{...remotePreferences, ...localPreferences};
    final candidateReviewCards =
        useRemoteSnapshot || !reviewCardsLocallyDirty
            ? remoteReviewCards
            : _mergeReviewCards(localReviewCards, remoteReviewCards);
    final mergedReviewCards = _filterReviewCardsForDecks(
      candidateReviewCards,
      mergedDecks,
    );
    final mergedReviewCardIds = mergedReviewCards.map((card) => card.id).toSet();
    final mergedReviewLogs = _mergeReviewLogs(
      useRemoteSnapshot || !reviewLogsLocallyDirty
          ? remoteReviewLogs
          : localReviewLogs,
      useRemoteSnapshot || !reviewLogsLocallyDirty
          ? localReviewLogs
          : remoteReviewLogs,
    ).where((log) {
      return mergedReviewCardIds.contains(log.reviewCardId);
    }).toList();

    // Dictionary notes and reading-card edits historically lived only on the
    // device, even while decks/review state were cloud-first. Preserve those
    // local-only values during the one-time bootstrap so this migration cannot
    // erase them. After bootstrap, a clean pull accepts remote text choices,
    // while a local photo path remains device-only.
    final mergedNotes = preserveLegacyLocalOnlyData
        ? <String, String>{...remoteNotes, ...localNotes}
        : useRemoteSnapshot || !notesLocallyDirty
            ? remoteNotes
            : <String, String>{...remoteNotes, ...localNotes};
    final candidateEdits = preserveLegacyLocalOnlyData
        ? _mergeReadingEdits(localEdits, remoteEdits)
        : useRemoteSnapshot || !editsLocallyDirty
            ? _mergeReadingEditsPreferRemote(localEdits, remoteEdits)
            : _mergeReadingEdits(localEdits, remoteEdits);
    final mergedEdits = _filterReadingEditsForDecks(
      candidateEdits,
      mergedDecks,
    );

    // Cloud hydration must never manufacture new local dirty work. Existing
    // local edits already have precise dirty-entity records, and those records
    // survive this merge so only the originally changed entities are pushed.
    const markDirty = false;

    await GakujiUserRepository.saveAll(
      decks: mergedDecks,
      folders: mergedFolders,
      pinnedDeckIds: mergedPinned,
      markDirty: markDirty,
    );
    await GakujiUserRepository.saveRecentSearches(
      mergedRecent,
      markDirty: markDirty,
    );
    await GakujiUserRepository.syncReviewCards(
      mergedReviewCards,
      markDirty: markDirty,
    );
    await GakujiUserRepository.replaceReviewLogs(
      mergedReviewLogs,
      markDirty: markDirty,
    );
    await GakujiUserRepository.replaceSyncablePreferences(
      mergedPreferences,
      markDirty: markDirty,
    );
    await GakujiUserRepository.replaceDictionaryNotes(
      mergedNotes,
      markDirty: markDirty,
    );
    await GakujiUserRepository.replaceReadingCardEdits(
      mergedEdits,
      markDirty: markDirty,
    );

    return true;
  }

  static Deck _deckFromCloudMetadata(
    String id,
    Map<String, dynamic> data, {
    required List<Term> terms,
    required Map<String, HybridCardMode> hybridModes,
  }) {
    final type = _deckTypeFromText(data['type']?.toString() ?? 'reading');

    return Deck(
      id: id,
      name: data['name']?.toString() ?? '',
      type: type,
      colorValue: _nullableInt(data['colorValue']),
      terms: terms,
      hybridCardModes: hybridModes,
      reviewEnabled: data['reviewEnabled'] == true,
      activeStudyMode: data['activeStudyMode'] == 'review'
          ? StudyMode.review
          : StudyMode.study,
      reviewEnabledAt: _dateTime(data['reviewEnabledAt']),
      lastStudyIndex: _asInt(data['lastStudyIndex']),
      isShuffled: data['isShuffled'] == true,
    );
  }

  /// Legacy reader for pre-chunk deck documents. New writes never place the
  /// full term list on the deck document, but keeping this reader allows a
  /// device to hydrate old cloud data and migrate it on the next deck push.
  static Deck _deckFromCloudData(
    String id,
    Map<String, dynamic> data,
  ) {
    final terms = _termsFromList(data['terms']);
    final hybridModes = <String, HybridCardMode>{};
    final rawModes = data['hybridCardModes'];
    if (rawModes is Map) {
      rawModes.forEach((key, value) {
        hybridModes[key.toString()] = hybridCardModeFromStorage(
          value?.toString(),
        );
      });
    }

    return _deckFromCloudMetadata(
      id,
      data,
      terms: terms,
      hybridModes: hybridModes,
    );
  }

  static bool _usesChunkedTermStorage(Map<String, dynamic> data) {
    return _asInt(data['termStorageVersion']) >= _deckTermStorageVersion &&
        data['termChunkManifest'] is Map;
  }

  static Future<List<Deck>> _loadCloudDecks({
    required List<Deck> localDecks,
  }) async {
    final snapshot = await _userDoc.collection('decks').orderBy('position').get();
    final localById = <String, Deck>{
      for (final deck in localDecks) deck.id: deck,
    };
    final result = <Deck>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (!_usesChunkedTermStorage(data)) {
        result.add(_deckFromCloudData(doc.id, data));
        continue;
      }

      result.add(
        await _loadChunkedCloudDeck(
          deckId: doc.id,
          data: data,
          localDeck: localById[doc.id],
        ),
      );
    }

    return result;
  }

  static Future<Deck> _loadChunkedCloudDeck({
    required String deckId,
    required Map<String, dynamic> data,
    required Deck? localDeck,
  }) async {
    final manifest = _chunkManifestFromCloud(data['termChunkManifest']);
    final localChunks = localDeck == null
        ? const <String, _DeckCloudChunk>{}
        : _buildDeckChunks(localDeck);
    final piecesByKey = <String, _DeckRemoteTermPiece>{};
    final pendingFetches = <MapEntry<String, _DeckChunkManifestEntry>>[];

    final chunkIds = manifest.keys.toList()..sort();
    for (final chunkId in chunkIds) {
      final remoteEntry = manifest[chunkId]!;
      final localChunk = localChunks[chunkId];
      if (localChunk != null && localChunk.hash == remoteEntry.hash) {
        for (final record in localChunk.records) {
          piecesByKey[record.stableKey] = _DeckRemoteTermPiece(
            stableKey: record.stableKey,
            term: record.term,
            hybridMode: record.hybridMode,
          );
        }
        continue;
      }
      pendingFetches.add(MapEntry(chunkId, remoteEntry));
    }

    for (var start = 0;
        start < pendingFetches.length;
        start += _chunkFetchConcurrency) {
      final end = (start + _chunkFetchConcurrency < pendingFetches.length)
          ? start + _chunkFetchConcurrency
          : pendingFetches.length;
      final batch = pendingFetches.sublist(start, end);
      final fetched = await Future.wait(
        batch.map((entry) {
          return _loadCloudTermChunk(
            deckId: deckId,
            chunkId: entry.key,
            manifestEntry: entry.value,
          );
        }),
      );
      for (final chunkPieces in fetched) {
        for (final piece in chunkPieces) {
          piecesByKey[piece.stableKey] = piece;
        }
      }
    }

    final orderedTerms = <Term>[];
    final hybridModes = <String, HybridCardMode>{};
    final termOrder = _stringList(data['termOrder']);
    final seenKeys = <String>{};

    for (final stableKey in termOrder) {
      final piece = piecesByKey[stableKey];
      if (piece == null || !seenKeys.add(stableKey)) continue;
      orderedTerms.add(piece.term);
      if (piece.hybridMode != null) {
        hybridModes[piece.term.id] = piece.hybridMode!;
      }
    }

    final remainingKeys = piecesByKey.keys
        .where((key) => !seenKeys.contains(key))
        .toList()
      ..sort();
    for (final stableKey in remainingKeys) {
      final piece = piecesByKey[stableKey]!;
      orderedTerms.add(piece.term);
      if (piece.hybridMode != null) {
        hybridModes[piece.term.id] = piece.hybridMode!;
      }
    }

    // Manamoji/older Gakuji builds may append a legacy `terms` array even after
    // this deck has moved to chunk storage. Fold those remote-only terms in so
    // the next Gakuji push can migrate them into chunks without data loss.
    final legacyTerms = _termsFromList(data['terms']);
    if (legacyTerms.isNotEmpty) {
      final rawModes = data['hybridCardModes'];
      final legacyModes = <String, HybridCardMode>{};
      if (rawModes is Map) {
        rawModes.forEach((key, value) {
          legacyModes[key.toString()] = hybridCardModeFromStorage(
            value?.toString(),
          );
        });
      }
      final existingSourceIds = orderedTerms
          .map((term) => term.sourceId ?? term.id)
          .toSet();
      for (final term in legacyTerms) {
        final sourceId = term.sourceId ?? term.id;
        if (!existingSourceIds.add(sourceId)) continue;
        orderedTerms.add(term);
        final mode = legacyModes[term.id];
        if (mode != null) hybridModes[term.id] = mode;
      }
    }

    final expectedCount = _asInt(data['termCount']);
    if (legacyTerms.isEmpty &&
        expectedCount > 0 &&
        orderedTerms.length != expectedCount) {
      throw StateError(
        'Incomplete cloud deck $deckId: expected $expectedCount terms, '
        'received ${orderedTerms.length}.',
      );
    }

    return _deckFromCloudMetadata(
      deckId,
      data,
      terms: orderedTerms,
      hybridModes: hybridModes,
    );
  }

  static Future<List<_DeckRemoteTermPiece>> _loadCloudTermChunk({
    required String deckId,
    required String chunkId,
    required _DeckChunkManifestEntry manifestEntry,
  }) async {
    final snapshot = await _userDoc
        .collection('decks')
        .doc(deckId)
        .collection('termChunks')
        .doc(manifestEntry.documentId)
        .get();
    final data = snapshot.data();
    if (data == null) {
      throw StateError(
        'Missing term chunk ${manifestEntry.documentId} for deck $deckId.',
      );
    }

    final storedHash = data['hash']?.toString() ?? '';
    if (storedHash.isNotEmpty && storedHash != manifestEntry.hash) {
      throw StateError(
        'Term chunk hash mismatch for $deckId/$chunkId.',
      );
    }

    final rawTerms = data['terms'];
    if (rawTerms is! List) return const <_DeckRemoteTermPiece>[];

    final result = <_DeckRemoteTermPiece>[];
    for (final raw in rawTerms) {
      if (raw is! Map) continue;
      final record = Map<String, dynamic>.from(raw);
      final rawTerm = record['term'];
      if (rawTerm is! Map) continue;
      try {
        final term = Term.fromJson(Map<String, dynamic>.from(rawTerm));
        final stableKey = record['key']?.toString() ??
            term.sourceId ??
            term.id;
        final rawMode = record['hybridCardMode']?.toString();
        result.add(
          _DeckRemoteTermPiece(
            stableKey: stableKey,
            term: term,
            hybridMode: rawMode == null || rawMode.isEmpty
                ? null
                : hybridCardModeFromStorage(rawMode),
          ),
        );
      } catch (_) {
        // A malformed row is ignored here; the termCount integrity check above
        // prevents an incomplete chunk set from replacing a healthy local deck.
      }
    }
    return result;
  }

  static Future<List<Folder>> _loadCloudFolders() async {
    final snapshot =
        await _userDoc.collection('folders').orderBy('position').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return Folder(
        id: doc.id,
        name: data['name']?.toString() ?? '',
        deckIds: _stringList(data['deckIds']),
      );
    }).toList();
  }

  static Future<List<ReviewCard>> _loadCloudReviewCards() async {
    final snapshot = await _userDoc.collection('reviewCards').get();
    final result = <ReviewCard>[];
    for (final doc in snapshot.docs) {
      try {
        result.add(ReviewCard.fromJson(doc.data()));
      } catch (_) {
        // Ignore corrupted cloud review rows.
      }
    }
    return result;
  }

  static Future<List<ReviewLogEntry>> _loadCloudReviewLogs() async {
    final snapshot = await _userDoc.collection('reviewLogs').get();
    final result = <ReviewLogEntry>[];
    for (final doc in snapshot.docs) {
      try {
        result.add(ReviewLogEntry.fromJson(doc.data()));
      } catch (_) {
        // Ignore corrupted cloud review history rows.
      }
    }
    result.sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt));
    return result;
  }

  static Future<Map<String, String>> _loadCloudDictionaryNotes() async {
    final snapshot = await _userDoc.collection('dictionaryNotes').get();
    final result = <String, String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final sourceId = data['sourceId']?.toString() ?? doc.id;
      final note = data['note']?.toString();
      if (sourceId.isNotEmpty && note != null) result[sourceId] = note;
    }
    return result;
  }

  static Future<List<ReadingCardEditData>> _loadCloudReadingCardEdits() async {
    final snapshot = await _userDoc.collection('readingCardEdits').get();
    final result = <ReadingCardEditData>[];
    for (final doc in snapshot.docs) {
      try {
        result.add(ReadingCardEditData.fromJson(doc.data()));
      } catch (_) {
        // Ignore a malformed cloud edit.
      }
    }
    return result;
  }

  static Future<void> _replaceCollection({
    required CollectionReference<Map<String, dynamic>> collection,
    required Map<String, Map<String, dynamic>> documents,
  }) async {
    final existing = await collection.get();
    final firestore = FirebaseFirestore.instance;
    var batch = firestore.batch();
    var operationCount = 0;

    Future<void> flush() async {
      if (operationCount == 0) return;
      await batch.commit();
      batch = firestore.batch();
      operationCount = 0;
      await Future<void>.delayed(_snapshotWriteBackpressure);
    }

    final desiredIds = documents.keys.toSet();
    for (final doc in existing.docs) {
      if (desiredIds.contains(doc.id)) continue;
      batch.delete(doc.reference);
      operationCount++;
      if (operationCount >= _snapshotBatchLimit) await flush();
    }

    for (final entry in documents.entries) {
      batch.set(collection.doc(entry.key), entry.value);
      operationCount++;
      if (operationCount >= _snapshotBatchLimit) await flush();
    }

    await flush();
  }

  static Map<String, _DeckChunkManifestEntry> _chunkManifestFromCloud(
    dynamic rawManifest,
  ) {
    final result = <String, _DeckChunkManifestEntry>{};
    if (rawManifest is! Map) return result;

    rawManifest.forEach((rawKey, rawValue) {
      if (rawValue is! Map) return;
      final value = Map<String, dynamic>.from(rawValue);
      final hash = value['hash']?.toString() ?? '';
      final documentId = value['documentId']?.toString() ?? '';
      if (hash.isEmpty || documentId.isEmpty) return;
      result[rawKey.toString()] = _DeckChunkManifestEntry(
        hash: hash,
        documentId: documentId,
      );
    });
    return result;
  }

  static Map<String, dynamic> _chunkManifestToCloud(
    Map<String, _DeckChunkManifestEntry> manifest,
  ) {
    final keys = manifest.keys.toList()..sort();
    return <String, dynamic>{
      for (final key in keys) key: manifest[key]!.toJson(),
    };
  }

  static Map<String, _DeckCloudChunk> _buildDeckChunks(Deck deck) {
    final baseBuckets = <int, List<_DeckCloudTermRecord>>{};

    for (final term in deck.terms) {
      final stableKey = term.sourceId ?? term.id;
      final hybridMode = deck.type == DeckType.hybrid
          ? deck.cardModeFor(term)
          : null;
      final data = <String, dynamic>{
        'key': stableKey,
        'term': term.toJson(),
        if (hybridMode != null) 'hybridCardMode': hybridMode.name,
      };
      final canonical = _canonicalJson(data);
      final stableHash = _stableHash32(stableKey);
      final record = _DeckCloudTermRecord(
        stableKey: stableKey,
        term: term,
        hybridMode: hybridMode,
        data: data,
        stableHash: stableHash,
        approxBytes: utf8.encode(canonical).length,
      );
      final bucket = stableHash % _baseTermChunkBuckets;
      baseBuckets.putIfAbsent(bucket, () => <_DeckCloudTermRecord>[]).add(record);
    }

    final result = <String, _DeckCloudChunk>{};
    final bucketIds = baseBuckets.keys.toList()..sort();
    for (final bucket in bucketIds) {
      final chunkId = 'b${bucket.toString().padLeft(2, '0')}';
      _splitDeckChunk(
        records: baseBuckets[bucket]!,
        chunkId: chunkId,
        splitDepth: 0,
        output: result,
      );
    }
    return result;
  }

  static void _splitDeckChunk({
    required List<_DeckCloudTermRecord> records,
    required String chunkId,
    required int splitDepth,
    required Map<String, _DeckCloudChunk> output,
  }) {
    final approxBytes = records.fold<int>(
      64,
      (runningTotal, record) => runningTotal + record.approxBytes + 16,
    );
    final fits = records.length <= _maxTermsPerChunk &&
        approxBytes <= _maxApproxTermChunkBytes;

    if (fits || records.length <= 1) {
      output[chunkId] = _createDeckChunk(chunkId, records);
      return;
    }

    // The first five low bits chose the 32 stable base buckets. Additional
    // hash bits split only the oversized bucket, so adding one term never
    // reshuffles unrelated chunks elsewhere in the deck.
    final bitPosition = 5 + splitDepth;
    if (bitPosition < 31) {
      final zero = <_DeckCloudTermRecord>[];
      final one = <_DeckCloudTermRecord>[];
      for (final record in records) {
        if (((record.stableHash >> bitPosition) & 1) == 0) {
          zero.add(record);
        } else {
          one.add(record);
        }
      }

      if (zero.isNotEmpty && one.isNotEmpty) {
        _splitDeckChunk(
          records: zero,
          chunkId: '$chunkId-0',
          splitDepth: splitDepth + 1,
          output: output,
        );
        _splitDeckChunk(
          records: one,
          chunkId: '$chunkId-1',
          splitDepth: splitDepth + 1,
          output: output,
        );
        return;
      }

      final nonEmpty = zero.isNotEmpty ? zero : one;
      final suffix = zero.isNotEmpty ? '0' : '1';
      _splitDeckChunk(
        records: nonEmpty,
        chunkId: '$chunkId-$suffix',
        splitDepth: splitDepth + 1,
        output: output,
      );
      return;
    }

    // Pathological 32-bit hash collisions fall back to small deterministic
    // slices. Normal decks will never reach this branch.
    final sorted = [...records]
      ..sort((a, b) => a.stableKey.compareTo(b.stableKey));
    var sliceIndex = 0;
    var current = <_DeckCloudTermRecord>[];
    var currentBytes = 64;

    void flush() {
      if (current.isEmpty) return;
      final id = '$chunkId-x${sliceIndex.toString().padLeft(2, '0')}';
      output[id] = _createDeckChunk(id, current);
      sliceIndex++;
      current = <_DeckCloudTermRecord>[];
      currentBytes = 64;
    }

    for (final record in sorted) {
      final nextBytes = currentBytes + record.approxBytes + 16;
      if (current.isNotEmpty &&
          (current.length >= _maxTermsPerChunk ||
              nextBytes > _maxApproxTermChunkBytes)) {
        flush();
      }
      current.add(record);
      currentBytes += record.approxBytes + 16;
    }
    flush();
  }

  static _DeckCloudChunk _createDeckChunk(
    String chunkId,
    List<_DeckCloudTermRecord> records,
  ) {
    final sortedRecords = [...records]
      ..sort((a, b) => a.stableKey.compareTo(b.stableKey));
    final payload = sortedRecords.map((record) => record.data).toList();
    return _DeckCloudChunk(
      id: chunkId,
      records: sortedRecords,
      hash: _contentHash(payload),
    );
  }

  static int _stableHash32(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  static String _contentHash(dynamic value) {
    final bytes = utf8.encode(_canonicalJson(value));
    var fnv = 0x811c9dc5;
    var djb = 5381;
    for (final byte in bytes) {
      fnv ^= byte;
      fnv = (fnv * 0x01000193) & 0x7FFFFFFF;
      djb = ((djb * 33) ^ byte) & 0x7FFFFFFF;
    }
    return '${fnv.toRadixString(16).padLeft(8, '0')}-'
        '${djb.toRadixString(16).padLeft(8, '0')}-${bytes.length}';
  }

  static String _canonicalJson(dynamic value) {
    return jsonEncode(_canonicalizeForHash(value));
  }

  static dynamic _canonicalizeForHash(dynamic value) {
    if (value is Map) {
      final entries = value.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return <String, dynamic>{
        for (final entry in entries)
          entry.key: _canonicalizeForHash(entry.value),
      };
    }
    if (value is List) {
      return value.map(_canonicalizeForHash).toList();
    }
    return value;
  }

  static String _chunkDocumentId(_DeckCloudChunk chunk) {
    return '${chunk.id}-${chunk.hash}';
  }

  static Map<String, dynamic> _deckMetadataToCloud({
    required Deck deck,
    required int position,
    required int now,
    required Map<String, _DeckChunkManifestEntry> manifest,
  }) {
    return {
      'name': deck.name,
      'type': deck.type.name,
      'colorValue': deck.colorValue,
      'reviewEnabled': deck.reviewEnabled,
      'activeStudyMode': deck.activeStudyMode.name,
      'reviewEnabledAt': deck.reviewEnabledAt?.toUtc().toIso8601String(),
      'lastStudyIndex': deck.lastStudyIndex,
      'isShuffled': deck.isShuffled,
      'position': position,
      'updatedAtMs': now,
      'termStorageVersion': _deckTermStorageVersion,
      'termCount': deck.terms.length,
      'termOrder': deck.terms
          .map((term) => term.sourceId ?? term.id)
          .toList(growable: false),
      'termChunkManifest': _chunkManifestToCloud(manifest),
    };
  }

  /// Writes only the term chunks whose hashes differ from the current cloud
  /// manifest. Chunk documents are content-addressed and written before the
  /// small deck metadata document, so an interrupted upload cannot publish a
  /// manifest that points at data which was never uploaded.
  ///
  /// Returns true when a targeted compatibility merge added remote-only terms
  /// to [deck], allowing the caller to persist that merged local copy.
  static Future<bool> _pushDeckWithChunks({
    required Deck deck,
    required int position,
    required int now,
    required bool preserveRemoteOnlyTerms,
    required Set<String> tombstoneKeys,
    bool cleanupStaleChunks = false,
  }) async {
    final deckReference = _userDoc.collection('decks').doc(deck.id);
    final remoteSnapshot = await deckReference.get();
    final remoteData = remoteSnapshot.data();
    var mergedRemoteOnlyTerms = false;

    if (preserveRemoteOnlyTerms && remoteData != null) {
      Deck remoteDeck;
      if (_usesChunkedTermStorage(remoteData)) {
        remoteDeck = await _loadChunkedCloudDeck(
          deckId: deck.id,
          data: remoteData,
          localDeck: deck,
        );
      } else {
        remoteDeck = _deckFromCloudData(deck.id, remoteData);
      }

      final filteredRemote = _applyDeckTombstones(
        [remoteDeck],
        tombstoneKeys,
      );
      if (filteredRemote.isNotEmpty) {
        await GakujiTermPayloadRepair.repairDecks(
          filteredRemote,
          fallbackDecks: [deck],
        );
        final beforeSourceIds = deck.terms
            .map((term) => term.sourceId ?? term.id)
            .toSet();
        _mergeDecksLocalFirst([deck], filteredRemote);
        final afterSourceIds = deck.terms
            .map((term) => term.sourceId ?? term.id)
            .toSet();
        mergedRemoteOnlyTerms =
            afterSourceIds.length != beforeSourceIds.length;
      }
    }

    final remoteManifest = remoteData == null
        ? <String, _DeckChunkManifestEntry>{}
        : _chunkManifestFromCloud(remoteData['termChunkManifest']);
    final localChunks = _buildDeckChunks(deck);
    final finalManifest = <String, _DeckChunkManifestEntry>{};
    final chunkIds = localChunks.keys.toList()..sort();

    for (final chunkId in chunkIds) {
      final chunk = localChunks[chunkId]!;
      final existing = remoteManifest[chunkId];
      if (existing != null && existing.hash == chunk.hash) {
        finalManifest[chunkId] = existing;
        continue;
      }

      final documentId = _chunkDocumentId(chunk);

      // Full snapshot/bootstrap pushes may be resuming after an interrupted
      // migration. Chunk document IDs are content-addressed, so reuse an
      // already-staged matching document instead of retransmitting it.
      if (cleanupStaleChunks) {
        final stagedSnapshot = await deckReference
            .collection('termChunks')
            .doc(documentId)
            .get();
        final stagedData = stagedSnapshot.data();
        if (stagedSnapshot.exists &&
            stagedData?['hash']?.toString() == chunk.hash) {
          finalManifest[chunkId] = _DeckChunkManifestEntry(
            hash: chunk.hash,
            documentId: documentId,
          );
          continue;
        }
      }

      await deckReference.collection('termChunks').doc(documentId).set({
        'storageVersion': _deckTermStorageVersion,
        'chunkId': chunk.id,
        'hash': chunk.hash,
        'terms': chunk.records.map((record) => record.data).toList(),
        'updatedAtMs': now,
      });
      finalManifest[chunkId] = _DeckChunkManifestEntry(
        hash: chunk.hash,
        documentId: documentId,
      );
    }

    await deckReference.set(
      _deckMetadataToCloud(
        deck: deck,
        position: position,
        now: now,
        manifest: finalManifest,
      ),
    );

    if (cleanupStaleChunks) {
      await _cleanupDeckTermChunks(
        deckId: deck.id,
        activeDocumentIds: finalManifest.values
            .map((entry) => entry.documentId)
            .toSet(),
      );
    }

    return mergedRemoteOnlyTerms;
  }

  static Future<void> _replaceDeckCollection({
    required List<Deck> decks,
    required int now,
  }) async {
    final collection = _userDoc.collection('decks');
    final existing = await collection.get();
    final desiredIds = decks.map((deck) => deck.id).toSet();

    for (var index = 0; index < decks.length; index++) {
      await _pushDeckWithChunks(
        deck: decks[index],
        position: index,
        now: now,
        preserveRemoteOnlyTerms: false,
        tombstoneKeys: const <String>{},
        cleanupStaleChunks: true,
      );
    }

    for (final doc in existing.docs) {
      if (desiredIds.contains(doc.id)) continue;
      await _deleteCloudDeck(doc.id);
    }
  }

  static Future<void> _deleteCloudDeck(String deckId) async {
    final reference = _userDoc.collection('decks').doc(deckId);
    await reference.delete();
    await _cleanupDeckTermChunks(
      deckId: deckId,
      activeDocumentIds: const <String>{},
    );
  }

  static Future<void> _cleanupDeckTermChunks({
    required String deckId,
    required Set<String> activeDocumentIds,
  }) async {
    final collection = _userDoc
        .collection('decks')
        .doc(deckId)
        .collection('termChunks');

    while (true) {
      final snapshot = await collection.limit(_snapshotBatchLimit).get();
      if (snapshot.docs.isEmpty) return;

      final stale = snapshot.docs
          .where((doc) => !activeDocumentIds.contains(doc.id))
          .toList();
      if (stale.isEmpty) {
        // The first page may consist entirely of active content-addressed
        // chunks. Avoid repeatedly querying the same page; ordinary sync leaves
        // harmless historical chunks in place until a later full snapshot.
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in stale) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      await Future<void>.delayed(_snapshotWriteBackpressure);

      if (activeDocumentIds.isNotEmpty) return;
    }
  }

  static bool _hasTombstone(
    Set<String> keys,
    String entityType,
    String entityId,
  ) {
    return keys.contains('$entityType\u001f$entityId');
  }

  static List<Deck> _applyDeckTombstones(
    List<Deck> remote,
    Set<String> keys,
  ) {
    final result = <Deck>[];
    for (final deck in remote) {
      if (_hasTombstone(keys, GakujiUserRepository.tombstoneDeck, deck.id)) {
        continue;
      }

      final retainedTerms = deck.terms.where((term) {
        final sourceId = term.sourceId ?? term.id;
        return !_hasTombstone(
          keys,
          GakujiUserRepository.tombstoneDeckTerm,
          GakujiUserRepository.compoundEntityId(deck.id, sourceId),
        );
      }).toList();

      final retainedIds = retainedTerms.map((term) => term.id).toSet();
      final retainedModes = <String, HybridCardMode>{};
      deck.hybridCardModes.forEach((termId, mode) {
        if (retainedIds.contains(termId)) retainedModes[termId] = mode;
      });

      result.add(
        deck.copyWith(
          terms: retainedTerms,
          hybridCardModes: retainedModes,
        ),
      );
    }
    return result;
  }

  static List<Folder> _applyFolderTombstones(
    List<Folder> remote,
    Set<String> keys,
  ) {
    final result = <Folder>[];
    for (final folder in remote) {
      if (_hasTombstone(
        keys,
        GakujiUserRepository.tombstoneFolder,
        folder.id,
      )) {
        continue;
      }

      final deckIds = folder.deckIds.where((deckId) {
        return !_hasTombstone(
          keys,
          GakujiUserRepository.tombstoneFolderDeck,
          GakujiUserRepository.compoundEntityId(folder.id, deckId),
        );
      }).toList();

      result.add(Folder(id: folder.id, name: folder.name, deckIds: deckIds));
    }
    return result;
  }

  static List<Deck> _mergeDecksLocalFirst(
    List<Deck> local,
    List<Deck> remote,
  ) {
    final merged = <Deck>[...local];
    final localById = {for (final deck in merged) deck.id: deck};

    for (final remoteDeck in remote) {
      final localDeck = localById[remoteDeck.id];
      if (localDeck == null) {
        merged.add(remoteDeck);
        localById[remoteDeck.id] = remoteDeck;
        continue;
      }

      // External tools such as Manamoji can append terms directly in Firestore.
      // Preserve local deck settings while adding remote-only lexical entries.
      final seenSourceIds = localDeck.terms
          .map((term) => term.sourceId ?? term.id)
          .toSet();
      for (final remoteTerm in remoteDeck.terms) {
        final sourceId = remoteTerm.sourceId ?? remoteTerm.id;
        if (seenSourceIds.add(sourceId)) {
          localDeck.terms.add(remoteTerm);
          if (remoteDeck.type == DeckType.hybrid) {
            localDeck.hybridCardModes[remoteTerm.id] =
                remoteDeck.cardModeFor(remoteTerm);
          }
        }
      }
    }

    return merged;
  }

  static List<Folder> _mergeFoldersLocalFirst(
    List<Folder> local,
    List<Folder> remote,
  ) {
    final merged = <Folder>[...local];
    final localById = {for (final folder in merged) folder.id: folder};
    for (final remoteFolder in remote) {
      final localFolder = localById[remoteFolder.id];
      if (localFolder == null) {
        merged.add(remoteFolder);
        continue;
      }
      for (final deckId in remoteFolder.deckIds) {
        if (!localFolder.deckIds.contains(deckId)) {
          localFolder.deckIds.add(deckId);
        }
      }
    }
    return merged;
  }

  static List<Term> _mergeRecentSearches(List<Term> local, List<Term> remote) {
    final result = <Term>[];
    final ids = <String>{};
    for (final term in [...local, ...remote]) {
      if (ids.add(term.id)) result.add(term);
    }
    return result.take(30).toList();
  }

  static List<ReviewCard> _mergeReviewCards(
    List<ReviewCard> local,
    List<ReviewCard> remote,
  ) {
    final result = <String, ReviewCard>{for (final card in local) card.id: card};
    for (final remoteCard in remote) {
      final localCard = result[remoteCard.id];
      if (localCard == null) {
        result[remoteCard.id] = remoteCard;
        continue;
      }
      final localReviewed = localCard.lastReviewedAt;
      final remoteReviewed = remoteCard.lastReviewedAt;
      if (remoteReviewed != null &&
          (localReviewed == null || remoteReviewed.isAfter(localReviewed))) {
        result[remoteCard.id] = remoteCard;
      }
    }
    return result.values.toList();
  }

  static List<ReviewLogEntry> _mergeReviewLogs(
    List<ReviewLogEntry> primary,
    List<ReviewLogEntry> secondary,
  ) {
    final result = <String, ReviewLogEntry>{
      for (final log in primary) log.id: log,
    };
    for (final log in secondary) {
      result.putIfAbsent(log.id, () => log);
    }
    final values = result.values.toList();
    values.sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt));
    return values;
  }

  static List<ReadingCardEditData> _mergeReadingEdits(
    List<ReadingCardEditData> local,
    List<ReadingCardEditData> remote,
  ) {
    final result = <String, ReadingCardEditData>{};
    for (final edit in remote) {
      result[_readingEditDocumentId(edit)] = edit;
    }
    for (final edit in local) {
      result[_readingEditDocumentId(edit)] = edit;
    }
    return result.values.toList();
  }

  static List<ReadingCardEditData> _mergeReadingEditsPreferRemote(
    List<ReadingCardEditData> local,
    List<ReadingCardEditData> remote,
  ) {
    final localById = <String, ReadingCardEditData>{
      for (final edit in local) _readingEditDocumentId(edit): edit,
    };

    return remote.map((remoteEdit) {
      final localEdit = localById[_readingEditDocumentId(remoteEdit)];
      final localPhotoPath = localEdit?.photoPath?.trim();
      if (localPhotoPath == null || localPhotoPath.isEmpty) return remoteEdit;

      return remoteEdit.copyWith(photoPath: localPhotoPath);
    }).toList();
  }

  static List<ReviewCard> _filterReviewCardsForDecks(
    List<ReviewCard> cards,
    List<Deck> decks,
  ) {
    final termIdsByDeck = <String, Set<String>>{
      for (final deck in decks)
        deck.id: deck.terms.map((term) => term.sourceId ?? term.id).toSet(),
    };

    return cards.where((card) {
      final validTermIds = termIdsByDeck[card.deckId];
      return validTermIds != null && validTermIds.contains(card.termId);
    }).toList();
  }

  static List<ReadingCardEditData> _filterReadingEditsForDecks(
    List<ReadingCardEditData> edits,
    List<Deck> decks,
  ) {
    final termIdsByDeck = <String, Set<String>>{
      for (final deck in decks) deck.id: deck.terms.map((term) => term.id).toSet(),
    };

    return edits.where((edit) {
      final validTermIds = termIdsByDeck[edit.deckId];
      return validTermIds != null && validTermIds.contains(edit.termId);
    }).toList();
  }

  static String _readingEditDocumentId(ReadingCardEditData edit) {
    return '${edit.deckId}__${edit.termId}';
  }

  static String? _readingEditDocumentIdFromCompound(String compoundId) {
    final parts = compoundId.split('\u001f');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return '${parts[0]}__${parts[1]}';
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

  static List<String> _stringList(dynamic value) {
    if (value is! List) return <String>[];
    return value.map((item) => item.toString()).toList();
  }

  static Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) return <String, String>{};
    return value.map(
      (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
    );
  }

  static List<Term> _termsFromList(dynamic value) {
    if (value is! List) return <Term>[];
    final result = <Term>[];
    for (final item in value) {
      if (item is! Map) continue;
      try {
        result.add(Term.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // Ignore corrupted remote terms.
      }
    }
    return result;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _nullableInt(dynamic value) {
    if (value == null) return null;
    return _asInt(value);
  }

  static DateTime? _dateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is int || value is num) {
      return DateTime.fromMillisecondsSinceEpoch(_asInt(value), isUtc: true);
    }
    return DateTime.tryParse(value.toString())?.toUtc();
  }
}
