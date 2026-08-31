import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:gakuji/data/seed/deck_seed.dart';
import 'package:gakuji/data/sync/gakuji_user_data_store.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/features/auth/services/account_username_service.dart';

class DeckCodeException implements Exception {
  final String message;

  const DeckCodeException(this.message);

  @override
  String toString() => message;
}

class DeckCodeService {
  static const String _collectionName = 'deckShares';
  static const String _chunkCollectionName = 'termChunks';
  static const int _schemaVersion = 2;
  static const int _maxChunkBytes = 450000;
  static const int _shareCodeLength = 12;
  static const Duration _shareLifetime = Duration(days: 90);
  static const String _shareCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static final Random _secureRandom = Random.secure();

  static CollectionReference<Map<String, dynamic>> get _shares {
    return FirebaseFirestore.instance.collection(_collectionName);
  }

  /// Publishes an immutable snapshot of [deck].
  ///
  /// If the deck still matches its most recently published/imported snapshot,
  /// the existing code is reused. Once shareable deck content changes, a new
  /// snapshot and code are created while the previous code remains unchanged.
  static Future<String> publishDeck(Deck deck) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const DeckCodeException(
        'Sign in to Gakuji before sharing a deck.',
      );
    }

    try {
      final records = _buildShareRecords(deck);
      final snapshotHash = _buildSnapshotHash(
        deck: deck,
        records: records,
      );
      final storedCode = normalizeCode(deck.shareCode ?? '');
      final storedHash = deck.shareSnapshotHash?.trim();

      if (storedCode.length == _shareCodeLength &&
          storedHash != null &&
          storedHash.isNotEmpty &&
          storedHash == snapshotHash) {
        final existing = await _shares.doc(storedCode).get();
        final existingData = existing.data();

        if (existing.exists &&
            existingData != null &&
            !_isExpired(existingData) &&
            _nullableTrimmedString(existingData['snapshotHash']) ==
                snapshotHash) {
          await _refreshShareActivityBestEffort(
            reference: existing.reference,
            metadata: existingData,
          );
          return formatCode(storedCode);
        }
      }

      final creatorUid = _effectiveCreatorUid(deck, user.uid);
      final creatorUsername = await _effectiveCreatorUsername(
        deck,
        creatorUid: creatorUid,
        currentUserUid: user.uid,
      );
      final currentUsername = await _currentUsername();
      final shouldCreditCurrentAdapter = creatorUid != user.uid &&
          (storedHash == null ||
              storedHash.isEmpty ||
              storedHash != snapshotHash);
      final adaptedBy = _publicationAdapterCredits(
        deck.adaptedBy,
        currentUserUid: user.uid,
        currentUsername: currentUsername,
        addCurrentUser: shouldCreditCurrentAdapter,
      );
      final shareReference = await _newShareReference();
      final revision = DateTime.now().microsecondsSinceEpoch.toString();
      final expiresAt = _nextExpiryTimestamp();
      final chunks = _buildTermChunks(records);
      final chunkCollection = shareReference.collection(_chunkCollectionName);

      for (var index = 0; index < chunks.length; index++) {
        final chunkId = _chunkDocumentId(revision, index);
        await chunkCollection.doc(chunkId).set({
          'schemaVersion': _schemaVersion,
          'ownerUid': user.uid,
          'sourceDeckId': deck.id,
          'revision': revision,
          'index': index,
          'records': chunks[index],
          'createdAt': FieldValue.serverTimestamp(),
          'lastActiveAt': FieldValue.serverTimestamp(),
          'expiresAt': expiresAt,
        });
      }

      await shareReference.set({
        'schemaVersion': _schemaVersion,
        'ownerUid': user.uid,
        'publisherUid': user.uid,
        'publisherUsername': currentUsername,
        'sourceDeckId': deck.id,
        'creatorUid': creatorUid,
        'creatorUsername': creatorUsername,
        'adaptedBy': adaptedBy.map((credit) => credit.toJson()).toList(),
        'name': deck.name,
        'type': deck.type.name,
        'colorValue': deck.colorValue,
        'termCount': records.length,
        'chunkCount': chunks.length,
        'revision': revision,
        'snapshotHash': snapshotHash,
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'expiresAt': expiresAt,
      });

      deck.adaptedBy
        ..clear()
        ..addAll(adaptedBy);
      deck.shareCode = shareReference.id;
      deck.shareSnapshotHash = snapshotHash;

      GakujiUserDataStore.scheduleSave();
      await GakujiUserDataStore.flushPendingSave();

      return formatCode(shareReference.id);
    } on DeckCodeException {
      rethrow;
    } on FirebaseException catch (error) {
      throw DeckCodeException(_firebaseMessage(error, sharing: true));
    } catch (_) {
      throw const DeckCodeException(
        'Gakuji could not create a deck code. Try again.',
      );
    }
  }

  /// Imports the snapshot behind [code] as a fully independent local deck.
  ///
  /// Imported terms always start unstarred and review/session state is reset.
  /// The deck color and card configuration are copied, but the importing user
  /// is free to edit their copy without affecting the shared snapshot.
  static Future<Deck> importDeck(String code) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const DeckCodeException(
        'Sign in to Gakuji before importing a deck.',
      );
    }

    final normalizedCode = normalizeCode(code);
    if (normalizedCode.length != _shareCodeLength) {
      throw const DeckCodeException('Enter a valid deck code.');
    }

    try {
      final shareReference = _shares.doc(normalizedCode);
      final shareSnapshot = await shareReference.get();
      final data = shareSnapshot.data();

      if (!shareSnapshot.exists || data == null) {
        throw const DeckCodeException('Deck code not found.');
      }

      if (_isExpired(data)) {
        throw const DeckCodeException(
          'This deck code has expired.',
        );
      }

      final schemaVersion = _asInt(data['schemaVersion']);
      if (schemaVersion < 1 || schemaVersion > _schemaVersion) {
        throw const DeckCodeException(
          'This deck code uses an unsupported share format.',
        );
      }

      final revision = data['revision']?.toString().trim() ?? '';
      final chunkCount = _asInt(data['chunkCount']);
      if (revision.isEmpty || chunkCount < 0) {
        throw const DeckCodeException(
          'This shared deck is incomplete and could not be imported.',
        );
      }

      final chunkCollection = shareReference.collection(_chunkCollectionName);
      final snapshots = await Future.wait(
        List.generate(chunkCount, (index) {
          return chunkCollection
              .doc(_chunkDocumentId(revision, index))
              .get();
        }),
      );

      final records = <Map<String, dynamic>>[];
      for (final snapshot in snapshots) {
        final chunkData = snapshot.data();
        if (!snapshot.exists || chunkData == null) {
          throw const DeckCodeException(
            'This shared deck is incomplete and could not be imported.',
          );
        }

        final rawRecords = chunkData['records'];
        if (rawRecords is! List) {
          throw const DeckCodeException(
            'This shared deck is incomplete and could not be imported.',
          );
        }

        for (final rawRecord in rawRecords) {
          if (rawRecord is Map) {
            records.add(Map<String, dynamic>.from(rawRecord));
          }
        }
      }

      final expectedTermCount = _asInt(data['termCount']);
      if (records.length != expectedTermCount) {
        throw const DeckCodeException(
          'This shared deck is incomplete and could not be imported.',
        );
      }

      final importedDeck = _buildImportedDeck(
        metadata: data,
        records: records,
      );
      final snapshotHash =
          _nullableTrimmedString(data['snapshotHash']) ??
              _buildSnapshotHash(
                deck: importedDeck,
                records: _buildShareRecords(importedDeck),
              );
      importedDeck.shareCode = normalizedCode;
      importedDeck.shareSnapshotHash = snapshotHash;

      // Never inherit another user's favorite/star state. The imported deck is
      // a copy and favoriting its terms is entirely the importing user's choice.
      for (final term in importedDeck.terms) {
        term.marked = false;
      }

      decks.add(importedDeck);
      try {
        GakujiUserDataStore.scheduleSave();
        await GakujiUserDataStore.flushPendingSave();
      } catch (_) {
        decks.removeWhere((deck) => deck.id == importedDeck.id);
        rethrow;
      }

      await _refreshShareActivityBestEffort(
        reference: shareReference,
        metadata: data,
      );

      return importedDeck;
    } on DeckCodeException {
      rethrow;
    } on FirebaseException catch (error) {
      throw DeckCodeException(_firebaseMessage(error, sharing: false));
    } catch (_) {
      throw const DeckCodeException(
        'Gakuji could not import that deck. Try again.',
      );
    }
  }

  /// Refreshes the current share snapshot when a deck is actively opened.
  ///
  /// This is best-effort and never blocks normal deck use. It keeps the latest
  /// snapshot attached to an active local deck from expiring while allowing
  /// older codes to age out after a newer snapshot replaces them.
  static Future<void> touchDeckActivity(Deck deck) async {
    final code = normalizeCode(deck.shareCode ?? '');
    final localSnapshotHash = deck.shareSnapshotHash?.trim();
    if (code.length != _shareCodeLength ||
        localSnapshotHash == null ||
        localSnapshotHash.isEmpty) {
      return;
    }

    try {
      final reference = _shares.doc(code);
      final snapshot = await reference.get();
      final data = snapshot.data();

      if (!snapshot.exists || data == null || _isExpired(data)) {
        _clearLocalShareState(deck);
        return;
      }

      final remoteSnapshotHash = _nullableTrimmedString(data['snapshotHash']);
      if (remoteSnapshotHash != null && remoteSnapshotHash != localSnapshotHash) {
        _clearLocalShareState(deck);
        return;
      }

      await _refreshShareActivityBestEffort(
        reference: reference,
        metadata: data,
      );
    } on FirebaseException {
      // Opening a deck must remain fully usable offline or under restrictive
      // Firestore rules. A later share/import can refresh the snapshot.
    } catch (_) {
      // Activity refresh is intentionally non-critical.
    }
  }

  static void _clearLocalShareState(Deck deck) {
    if (deck.shareCode == null && deck.shareSnapshotHash == null) return;
    deck.shareCode = null;
    deck.shareSnapshotHash = null;
    GakujiUserDataStore.scheduleSave();
  }

  static Future<DocumentReference<Map<String, dynamic>>>
      _newShareReference() async {
    for (var attempt = 0; attempt < 24; attempt++) {
      final rawCode = List.generate(
        _shareCodeLength,
        (_) => _shareCodeAlphabet[
          _secureRandom.nextInt(_shareCodeAlphabet.length)
        ],
      ).join();
      final reference = _shares.doc(rawCode);
      final snapshot = await reference.get();
      if (!snapshot.exists) return reference;
    }

    throw const DeckCodeException(
      'Gakuji could not create a unique deck code. Try again.',
    );
  }

  static List<Map<String, dynamic>> _buildShareRecords(Deck deck) {
    final records = <Map<String, dynamic>>[];

    for (final term in deck.terms) {
      final sourceId = term.sourceId ?? term.id;
      final termJson = Map<String, dynamic>.from(term.toJson())
        ..['id'] = sourceId
        ..['sourceId'] = sourceId
        ..remove('note')
        ..['marked'] = false;

      records.add({
        'term': termJson,
        if (deck.type == DeckType.hybrid)
          'hybridCardMode': deck.cardModeFor(term).name,
      });
    }

    return records;
  }

  static List<List<Map<String, dynamic>>> _buildTermChunks(
    List<Map<String, dynamic>> records,
  ) {
    final chunks = <List<Map<String, dynamic>>>[];
    var currentChunk = <Map<String, dynamic>>[];
    var currentBytes = 0;

    for (final record in records) {
      final recordBytes = utf8.encode(jsonEncode(record)).length;

      if (currentChunk.isNotEmpty &&
          currentBytes + recordBytes > _maxChunkBytes) {
        chunks.add(currentChunk);
        currentChunk = <Map<String, dynamic>>[];
        currentBytes = 0;
      }

      currentChunk.add(record);
      currentBytes += recordBytes;
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk);
    }

    return chunks;
  }

  static String _buildSnapshotHash({
    required Deck deck,
    required List<Map<String, dynamic>> records,
  }) {
    final payload = <String, dynamic>{
      'name': deck.name,
      'type': deck.type.name,
      'colorValue': deck.colorValue,
      'records': records,
    };
    final bytes = utf8.encode(jsonEncode(_canonicalize(payload)));
    var fnv = 2166136261 & 0x7fffffff;
    var djb = 5381;

    for (final byte in bytes) {
      fnv = ((fnv ^ byte) * 16777619) & 0x7fffffff;
      djb = ((djb * 33) ^ byte) & 0x7fffffff;
    }

    return '${fnv.toRadixString(16).padLeft(8, '0')}-'
        '${djb.toRadixString(16).padLeft(8, '0')}-${bytes.length}';
  }

  static dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final entries = value.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return <String, dynamic>{
        for (final entry in entries)
          entry.key: _canonicalize(entry.value),
      };
    }
    if (value is List) {
      return value.map(_canonicalize).toList();
    }
    return value;
  }

  static List<DeckAdapterCredit> _publicationAdapterCredits(
    List<DeckAdapterCredit> existing, {
    required String currentUserUid,
    required String? currentUsername,
    required bool addCurrentUser,
  }) {
    final result = <DeckAdapterCredit>[];
    final seen = <String>{};

    for (final credit in existing) {
      final uid = credit.uid.trim();
      if (uid.isEmpty || !seen.add(uid)) continue;
      result.add(credit);
    }

    if (!addCurrentUser) return result;

    final existingIndex = result.indexWhere(
      (credit) => credit.uid.trim() == currentUserUid,
    );
    if (existingIndex >= 0) {
      final storedUsername = result[existingIndex].username?.trim();
      if ((storedUsername == null || storedUsername.isEmpty) &&
          currentUsername != null &&
          currentUsername.isNotEmpty) {
        result[existingIndex] = DeckAdapterCredit(
          uid: currentUserUid,
          username: currentUsername,
        );
      }
      return result;
    }

    result.add(
      DeckAdapterCredit(
        uid: currentUserUid,
        username: currentUsername,
      ),
    );
    return result;
  }

  static Deck _buildImportedDeck({
    required Map<String, dynamic> metadata,
    required List<Map<String, dynamic>> records,
  }) {
    final newDeckId = DateTime.now().microsecondsSinceEpoch.toString();
    final type = _deckTypeFromText(metadata['type']?.toString());
    final importedTerms = <Term>[];
    final hybridCardModes = <String, HybridCardMode>{};

    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      final rawTerm = record['term'];
      if (rawTerm is! Map) {
        throw const DeckCodeException(
          'This shared deck contains an unreadable term.',
        );
      }

      final sharedTerm = Term.fromJson(Map<String, dynamic>.from(rawTerm));
      final sourceId = sharedTerm.sourceId ?? sharedTerm.id;
      final importedTerm = Term.deckCopyFrom(
        sharedTerm,
        id: '${newDeckId}_${sourceId}_$index',
        marked: false,
      );
      importedTerms.add(importedTerm);

      if (type == DeckType.hybrid) {
        hybridCardModes[importedTerm.id] = hybridCardModeFromStorage(
          record['hybridCardMode']?.toString(),
        );
      }
    }

    return Deck(
      id: newDeckId,
      name: metadata['name']?.toString().trim().isNotEmpty == true
          ? metadata['name'].toString().trim()
          : 'Imported Deck',
      type: type,
      creatorUid: _sharedCreatorUid(metadata),
      creatorUsername: _nullableTrimmedString(metadata['creatorUsername']),
      adaptedBy: _adapterCreditsFromMetadata(metadata['adaptedBy']),
      colorValue: _nullableInt(metadata['colorValue']),
      terms: importedTerms,
      hybridCardModes: hybridCardModes,
      reviewEnabled: false,
      activeStudyMode: StudyMode.study,
      reviewEnabledAt: null,
      lastStudyIndex: 0,
      isShuffled: false,
    );
  }

  static List<DeckAdapterCredit> _adapterCreditsFromMetadata(dynamic value) {
    if (value is! List) return const <DeckAdapterCredit>[];

    final result = <DeckAdapterCredit>[];
    final seen = <String>{};
    for (final rawCredit in value) {
      if (rawCredit is! Map) continue;
      final credit = DeckAdapterCredit.fromJson(
        Map<String, dynamic>.from(rawCredit),
      );
      final uid = credit.uid.trim();
      if (uid.isEmpty || !seen.add(uid)) continue;
      result.add(credit);
    }
    return result;
  }

  static String _effectiveCreatorUid(Deck deck, String currentUserUid) {
    final storedCreatorUid = deck.creatorUid?.trim();
    if (storedCreatorUid != null && storedCreatorUid.isNotEmpty) {
      return storedCreatorUid;
    }
    return currentUserUid;
  }

  static Future<String?> _effectiveCreatorUsername(
    Deck deck, {
    required String creatorUid,
    required String currentUserUid,
  }) async {
    final storedUsername = deck.creatorUsername?.trim();
    if (storedUsername != null && storedUsername.isNotEmpty) {
      return storedUsername;
    }

    if (creatorUid != currentUserUid) return null;
    return _currentUsername();
  }

  static Future<String?> _currentUsername() async {
    final cachedUsername =
        GakujiUsernameService.cachedCurrentProfile?.username?.trim();
    if (cachedUsername != null && cachedUsername.isNotEmpty) {
      return cachedUsername;
    }

    try {
      final profile = await GakujiUsernameService.loadCurrentProfile();
      final username = profile.username?.trim();
      return username == null || username.isEmpty ? null : username;
    } catch (_) {
      return null;
    }
  }

  static String? _sharedCreatorUid(Map<String, dynamic> metadata) {
    return _nullableTrimmedString(metadata['creatorUid']) ??
        _nullableTrimmedString(metadata['ownerUid']);
  }

  static Future<void> _refreshShareActivityBestEffort({
    required DocumentReference<Map<String, dynamic>> reference,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      final expiresAt = _nextExpiryTimestamp();
      await reference.update({
        'lastActiveAt': FieldValue.serverTimestamp(),
        'expiresAt': expiresAt,
      });

      final revision = _nullableTrimmedString(metadata['revision']);
      final chunkCount = _asInt(metadata['chunkCount']);
      if (revision == null || chunkCount <= 0) return;

      final firestore = FirebaseFirestore.instance;
      var batch = firestore.batch();
      var operationCount = 0;

      Future<void> flush() async {
        if (operationCount == 0) return;
        await batch.commit();
        batch = firestore.batch();
        operationCount = 0;
      }

      for (var index = 0; index < chunkCount; index++) {
        final chunkReference = reference
            .collection(_chunkCollectionName)
            .doc(_chunkDocumentId(revision, index));
        batch.update(chunkReference, {
          'lastActiveAt': FieldValue.serverTimestamp(),
          'expiresAt': expiresAt,
        });
        operationCount++;
        if (operationCount >= 400) {
          await flush();
        }
      }

      await flush();
    } catch (_) {
      // Activity is a heartbeat only. Importing, sharing, and opening the local
      // deck must not fail because a heartbeat could not be written.
    }
  }

  static bool _isExpired(Map<String, dynamic> metadata) {
    final expiresAt = _dateTimeFromFirestore(metadata['expiresAt']);
    if (expiresAt == null) return false;
    return !expiresAt.isAfter(DateTime.now().toUtc());
  }

  static Timestamp _nextExpiryTimestamp() {
    return Timestamp.fromDate(
      DateTime.now().toUtc().add(_shareLifetime),
    );
  }

  static DateTime? _dateTimeFromFirestore(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  static String? _nullableTrimmedString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String _chunkDocumentId(String revision, int index) {
    return '${revision}_c${index.toString().padLeft(4, '0')}';
  }

  static String normalizeCode(String code) {
    return code
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .trim();
  }

  static String formatCode(String code) {
    final normalized = normalizeCode(code);
    if (normalized.length != _shareCodeLength) return normalized;

    return '${normalized.substring(0, 4)}-'
        '${normalized.substring(4, 8)}-'
        '${normalized.substring(8, 12)}';
  }

  static DeckType _deckTypeFromText(String? value) {
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

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _nullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String _firebaseMessage(
    FirebaseException error, {
    required bool sharing,
  }) {
    switch (error.code) {
      case 'permission-denied':
        return sharing
            ? 'Gakuji could not publish this deck for sharing.'
            : 'Gakuji could not access that shared deck.';
      case 'unavailable':
      case 'network-request-failed':
        return 'Could not reach Gakuji. Check your connection and try again.';
      default:
        return sharing
            ? 'Gakuji could not create a deck code. Try again.'
            : 'Gakuji could not import that deck. Try again.';
    }
  }
}
