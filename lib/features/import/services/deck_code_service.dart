import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gakuji/data/dictionary/dictionary_service.dart';
import 'package:gakuji/data/seed/deck_seed.dart';
import 'package:gakuji/data/sync/gakuji_user_data_store.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/features/auth/services/account_username_service.dart';

enum DeckShareStage {
  preparing,
  sharing,
}

typedef DeckShareStageCallback = void Function(DeckShareStage stage);

class _PreparedDeckShare {
  final List<Map<String, dynamic>>? inlineRecords;
  final List<List<Map<String, dynamic>>> chunks;
  final String snapshotHash;
  final int termCount;

  const _PreparedDeckShare({
    required this.inlineRecords,
    required this.chunks,
    required this.snapshotHash,
    required this.termCount,
  });
}

class _ShareHashAccumulator {
  int _fnv = 2166136261 & 0x7fffffff;
  int _djb = 5381;
  int _byteLength = 0;

  void addText(String value) {
    addBytes(utf8.encode(value));
  }

  void addBytes(List<int> bytes) {
    for (final byte in bytes) {
      _fnv = ((_fnv ^ byte) * 16777619) & 0x7fffffff;
      _djb = ((_djb * 33) ^ byte) & 0x7fffffff;
    }
    _byteLength += bytes.length;
  }

  String finish() {
    return '${_fnv.toRadixString(16).padLeft(8, '0')}-'
        '${_djb.toRadixString(16).padLeft(8, '0')}-$_byteLength';
  }
}

_PreparedDeckShare _prepareDeckShare(Deck deck) {
  final records = <Map<String, dynamic>>[];
  final encodedRecordBytes = <List<int>>[];
  final hash = _ShareHashAccumulator();
  var totalRecordBytes = 0;

  // Dictionary-backed cards share only Gakuji-native identity plus the tiny
  // amount of deck state needed to reconstruct them. User-authored custom cards
  // carry their own compact lexical fields because they have no dictionary ID.
  hash
    ..addText('{"colorValue":')
    ..addText(jsonEncode(deck.colorValue))
    ..addText(',"name":')
    ..addText(jsonEncode(deck.name))
    ..addText(',"records":[');

  var customShareIndex = 0;

  for (var index = 0; index < deck.terms.length; index++) {
    final term = deck.terms[index];
    late final Map<String, dynamic> record;

    if (term.isCustom) {
      customShareIndex += 1;
      record = <String, dynamic>{
        'custom': true,
        // This ID exists only inside this immutable share snapshot. The
        // recipient receives a fresh deck-local term ID on import.
        'customId': 'c${customShareIndex.toString().padLeft(4, '0')}',
        'writing': term.preferredSpelling.trim().isNotEmpty
            ? term.preferredSpelling.trim()
            : term.kanji.trim(),
        if (term.reading.trim().isNotEmpty) 'reading': term.reading.trim(),
        'meaning': term.meaning.trim(),
        if (term.partOfSpeech.trim().isNotEmpty &&
            term.partOfSpeech.trim() != 'custom')
          'partOfSpeech': term.partOfSpeech.trim(),
        if (term.note?.trim().isNotEmpty == true) 'note': term.note!.trim(),
        if (deck.type == DeckType.hybrid)
          'hybridCardMode': deck.cardModeFor(term).name,
      };
    } else {
      final sourceId = (term.sourceId ?? term.id).trim();
      final fallbackTerm = term.kanji.trim().isNotEmpty
          ? term.kanji.trim()
          : term.preferredSpelling.trim();
      record = <String, dynamic>{
        'sourceId': sourceId,
        if (fallbackTerm.isNotEmpty) 'fallbackTerm': fallbackTerm,
        if (term.reading.trim().isNotEmpty)
          'fallbackReading': term.reading.trim(),
        if (deck.type == DeckType.hybrid)
          'hybridCardMode': deck.cardModeFor(term).name,
      };
    }

    final canonicalRecordBytes = utf8.encode(
      jsonEncode(_canonicalizeShareValue(record)),
    );

    records.add(record);
    encodedRecordBytes.add(canonicalRecordBytes);
    totalRecordBytes += canonicalRecordBytes.length;

    if (index > 0) hash.addText(',');
    hash.addBytes(canonicalRecordBytes);
  }

  hash
    ..addText('],"type":')
    ..addText(jsonEncode(deck.type.name))
    ..addText('}');

  // Most decks now fit directly on the share document, turning sharing into
  // just a parent create + ready update. Larger decks still fall back to the
  // existing chunk collection without changing the public share-code model.
  if (totalRecordBytes <= DeckCodeService._maxInlineRecordBytes) {
    return _PreparedDeckShare(
      inlineRecords: records,
      chunks: const <List<Map<String, dynamic>>>[],
      snapshotHash: hash.finish(),
      termCount: records.length,
    );
  }

  final chunks = <List<Map<String, dynamic>>>[];
  var currentChunk = <Map<String, dynamic>>[];
  var currentBytes = 0;

  for (var index = 0; index < records.length; index++) {
    final recordBytes = encodedRecordBytes[index].length;
    if (currentChunk.isNotEmpty &&
        currentBytes + recordBytes > DeckCodeService._maxChunkBytes) {
      chunks.add(currentChunk);
      currentChunk = <Map<String, dynamic>>[];
      currentBytes = 0;
    }

    currentChunk.add(records[index]);
    currentBytes += recordBytes;
  }

  if (currentChunk.isNotEmpty) {
    chunks.add(currentChunk);
  }

  return _PreparedDeckShare(
    inlineRecords: null,
    chunks: chunks,
    snapshotHash: hash.finish(),
    termCount: records.length,
  );
}

dynamic _canonicalizeShareValue(dynamic value) {
  if (value is Map) {
    final entries = value.entries
        .map((entry) => MapEntry(entry.key.toString(), entry.value))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return <String, dynamic>{
      for (final entry in entries)
        entry.key: _canonicalizeShareValue(entry.value),
    };
  }
  if (value is List) {
    return value.map(_canonicalizeShareValue).toList();
  }
  return value;
}

class DeckCodeException implements Exception {
  final String message;

  const DeckCodeException(this.message);

  @override
  String toString() => message;
}

class DeckCodeService {
  static const String _collectionName = 'deckShares';
  static const String _chunkCollectionName = 'termChunks';
  static const int _schemaVersion = 4;
  static const int _maxChunkBytes = 450000;
  static const int _maxInlineRecordBytes = 450000;
  static const int _chunkWritesPerBatch = 8;
  static const int _shareCodeLength = 12;
  static const Duration _shareLifetime = Duration(days: 90);
  static const String _shareCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static final Random _secureRandom = Random.secure();

  static CollectionReference<Map<String, dynamic>> get _shares {
    return FirebaseFirestore.instance.collection(_collectionName);
  }

  /// Shares an immutable snapshot copy of [deck].
  ///
  /// If the deck still matches its most recently shared/imported snapshot, the
  /// existing code is reused. Once shareable deck content changes, a new
  /// snapshot and code are created while the previous code remains unchanged.
  /// Recipients always import the snapshot as an independent deck copy.
  static Future<String> shareDeck(
    Deck deck, {
    DeckShareStageCallback? onStage,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const DeckCodeException(
        'Sign in to Gakuji before sharing a deck.',
      );
    }

    try {
      onStage?.call(DeckShareStage.preparing);
      await Future<void>.delayed(Duration.zero);
      final prepared = _prepareDeckShare(deck);
      final snapshotHash = prepared.snapshotHash;
      onStage?.call(DeckShareStage.sharing);
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
      final adaptedBy = _shareAdapterCredits(
        deck.adaptedBy,
        currentUserUid: user.uid,
        currentUsername: currentUsername,
        addCurrentUser: shouldCreditCurrentAdapter,
      );
      final shareReference = await _newShareReference();
      final revision = DateTime.now().microsecondsSinceEpoch.toString();
      final expiresAt = _nextExpiryTimestamp();
      final chunks = prepared.chunks;
      final chunkCollection = shareReference.collection(_chunkCollectionName);

      // Create the parent share first so Firestore rules can verify ownership
      // before accepting any term chunks. The share stays unavailable until all
      // chunks are present and the owner marks it ready.
      await shareReference.set({
        'schemaVersion': _schemaVersion,
        'ownerUid': user.uid,
        'sharerUid': user.uid,
        'sharerUsername': currentUsername,
        'sourceDeckId': deck.id,
        'creatorUid': creatorUid,
        'creatorUsername': creatorUsername,
        'adaptedBy': adaptedBy.map((credit) => credit.toJson()).toList(),
        'name': deck.name,
        'type': deck.type.name,
        'colorValue': deck.colorValue,
        'termCount': prepared.termCount,
        'chunkCount': chunks.length,
        if (prepared.inlineRecords != null) 'records': prepared.inlineRecords,
        'revision': revision,
        'snapshotHash': snapshotHash,
        'ready': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'expiresAt': expiresAt,
      });

      try {
        final firestore = FirebaseFirestore.instance;
        var batch = firestore.batch();
        var pendingWrites = 0;

        Future<void> flushChunkBatch() async {
          if (pendingWrites == 0) return;
          await batch.commit();
          batch = firestore.batch();
          pendingWrites = 0;
        }

        for (var index = 0; index < chunks.length; index++) {
          final chunkId = _chunkDocumentId(revision, index);
          batch.set(chunkCollection.doc(chunkId), {
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
          pendingWrites++;

          if (pendingWrites >= _chunkWritesPerBatch) {
            await flushChunkBatch();
          }
        }

        await flushChunkBatch();

        await shareReference.update({
          'ready': true,
          'lastActiveAt': FieldValue.serverTimestamp(),
          'expiresAt': expiresAt,
        });
      } catch (_) {
        await _deleteIncompleteShareBestEffort(
          reference: shareReference,
          revision: revision,
          chunkCount: chunks.length,
        );
        rethrow;
      }

      deck.adaptedBy
        ..clear()
        ..addAll(adaptedBy);
      deck.shareCode = shareReference.id;
      deck.shareSnapshotHash = snapshotHash;

      // The share is already safely finalized in Firestore. Persist the local
      // share-code metadata through the normal debounced save instead of making
      // the user wait for a full local workspace flush before showing the code.
      GakujiUserDataStore.scheduleSave();

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

      if (data['ready'] == false) {
        throw const DeckCodeException(
          'This shared deck is incomplete and could not be imported.',
        );
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

      final records = <Map<String, dynamic>>[];
      final inlineRecords = data['records'];

      if (inlineRecords is List) {
        for (final rawRecord in inlineRecords) {
          if (rawRecord is Map) {
            records.add(Map<String, dynamic>.from(rawRecord));
          }
        }
      } else if (chunkCount > 0) {
        final chunkCollection = shareReference.collection(_chunkCollectionName);
        final snapshots = await Future.wait(
          List.generate(chunkCount, (index) {
            return chunkCollection
                .doc(_chunkDocumentId(revision, index))
                .get();
          }),
        );

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
      }

      final expectedTermCount = _asInt(data['termCount']);
      if (records.length != expectedTermCount) {
        throw const DeckCodeException(
          'This shared deck is incomplete and could not be imported.',
        );
      }

      final importedDeck = schemaVersion >= 3
          ? await _buildImportedDeckFromReferences(
              metadata: data,
              records: records,
            )
          : _buildImportedDeckLegacy(
              metadata: data,
              records: records,
            );
      final snapshotHash =
          _nullableTrimmedString(data['snapshotHash']) ??
              _buildSnapshotHash(importedDeck);
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

  static String _buildSnapshotHash(Deck deck) {
    return _prepareDeckShare(deck).snapshotHash;
  }

  static List<DeckAdapterCredit> _shareAdapterCredits(
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

  static Future<Deck> _buildImportedDeckFromReferences({
    required Map<String, dynamic> metadata,
    required List<Map<String, dynamic>> records,
  }) async {
    final newDeckId = DateTime.now().microsecondsSinceEpoch.toString();
    final type = _deckTypeFromText(metadata['type']?.toString());
    final sourceIds = records
        .where((record) => record['custom'] != true)
        .map((record) => _nullableTrimmedString(record['sourceId']))
        .whereType<String>()
        .toList(growable: false);
    final dictionaryTermsById = await DictionaryService.getTermsByIdsAsync(
      sourceIds,
    );

    final missingFallbackQueries = <String>{};
    for (final record in records) {
      if (record['custom'] == true) continue;

      final sourceId = _nullableTrimmedString(record['sourceId']);
      if (sourceId != null && dictionaryTermsById.containsKey(sourceId)) {
        continue;
      }

      final fallbackTerm = _nullableTrimmedString(record['fallbackTerm']);
      final fallbackReading =
          _nullableTrimmedString(record['fallbackReading']);
      if (fallbackTerm != null) missingFallbackQueries.add(fallbackTerm);
      if (fallbackReading != null) missingFallbackQueries.add(fallbackReading);
    }

    final fallbackMatches = missingFallbackQueries.isEmpty
        ? const <String, List<Term>>{}
        : await DictionaryService.findExactJapaneseBatch(
            missingFallbackQueries,
            perQueryLimit: 12,
          );

    final importedTerms = <Term>[];
    final hybridCardModes = <String, HybridCardMode>{};

    for (var index = 0; index < records.length; index++) {
      final record = records[index];

      if (record['custom'] == true) {
        final writing = _nullableTrimmedString(record['writing']);
        final meaning = _nullableTrimmedString(record['meaning']);

        if (writing == null || meaning == null) {
          throw const DeckCodeException(
            'This shared deck contains an unreadable custom card.',
          );
        }

        final reading = _nullableTrimmedString(record['reading']) ?? '';
        final partOfSpeech =
            _nullableTrimmedString(record['partOfSpeech']) ?? 'custom';
        final note = _nullableTrimmedString(record['note']);
        final importedTerm = Term(
          id: '${newDeckId}_custom_$index',
          sourceId: null,
          isCustom: true,
          kanji: writing,
          reading: reading,
          meaning: meaning,
          preferredSpelling: writing,
          hasDictionarySpellingMetadata: false,
          alternativeKanji: const <String>[],
          partOfSpeech: partOfSpeech,
          definitions: <String>[meaning],
          isCommon: false,
          note: note,
          kanjiMeaning: meaning,
          marked: false,
        );
        importedTerms.add(importedTerm);

        if (type == DeckType.hybrid) {
          hybridCardModes[importedTerm.id] = hybridCardModeFromStorage(
            record['hybridCardMode']?.toString(),
          );
        }
        continue;
      }

      final sourceId = _nullableTrimmedString(record['sourceId']);
      final fallbackTerm = _nullableTrimmedString(record['fallbackTerm']);
      final fallbackReading =
          _nullableTrimmedString(record['fallbackReading']);

      Term? dictionaryTerm;
      if (sourceId != null) {
        dictionaryTerm = dictionaryTermsById[sourceId];
      }
      dictionaryTerm ??= _resolveFallbackDictionaryTerm(
        fallbackMatches: fallbackMatches,
        fallbackTerm: fallbackTerm,
        fallbackReading: fallbackReading,
      );

      if (dictionaryTerm == null) {
        throw const DeckCodeException(
          'One or more terms in this shared deck are not available in this version of Gakuji.',
        );
      }

      final canonicalSourceId = dictionaryTerm.sourceId ?? dictionaryTerm.id;
      final importedTerm = Term.deckCopyFrom(
        dictionaryTerm,
        id: '${newDeckId}_${canonicalSourceId}_$index',
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

  static Term? _resolveFallbackDictionaryTerm({
    required Map<String, List<Term>> fallbackMatches,
    required String? fallbackTerm,
    required String? fallbackReading,
  }) {
    final candidates = <String, Term>{};

    if (fallbackTerm != null) {
      for (final term in fallbackMatches[fallbackTerm] ?? const <Term>[]) {
        candidates.putIfAbsent(term.id, () => term);
      }
    }
    if (fallbackReading != null) {
      for (final term in fallbackMatches[fallbackReading] ?? const <Term>[]) {
        candidates.putIfAbsent(term.id, () => term);
      }
    }

    for (final candidate in candidates.values) {
      final spellingMatches = fallbackTerm == null ||
          candidate.kanji == fallbackTerm ||
          candidate.preferredSpelling == fallbackTerm ||
          candidate.alternativeKanji.contains(fallbackTerm);
      final readingMatches =
          fallbackReading == null || candidate.reading == fallbackReading;

      if (spellingMatches && readingMatches) return candidate;
    }

    return null;
  }

  static Deck _buildImportedDeckLegacy({
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
    final user = FirebaseAuth.instance.currentUser;
    final ownerUid = _nullableTrimmedString(metadata['ownerUid']);

    // A shared deck is a read-only transfer snapshot for recipients. Only the
    // owner of that snapshot may refresh or otherwise mutate it.
    if (user == null || ownerUid == null || ownerUid != user.uid) return;

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

  static Future<void> _deleteIncompleteShareBestEffort({
    required DocumentReference<Map<String, dynamic>> reference,
    required String revision,
    required int chunkCount,
  }) async {
    try {
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
        batch.delete(
          reference
              .collection(_chunkCollectionName)
              .doc(_chunkDocumentId(revision, index)),
        );
        operationCount++;
        if (operationCount >= 400) {
          await flush();
        }
      }

      await flush();
      await reference.delete();
    } catch (_) {
      // A failed cleanup must not hide the original sharing error. Orphaned
      // incomplete shares remain unreadable because their ready flag is false.
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
            ? 'Gakuji could not share this deck.'
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
