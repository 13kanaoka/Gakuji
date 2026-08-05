import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/deck.dart';
import '../models/folder.dart';
import '../models/review_card.dart';
import '../models/term.dart';
import 'gakuji_user_database.dart';

class GakujiUserRepository {
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
          terms: loadedTerms,
          hybridCardModes: loadedHybridCardModes,
        ),
      );
    }

    return loadedDecks;
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

  static Future<void> saveAll({
    required List<Deck> decks,
    required List<Folder> folders,
    required List<String> pinnedDeckIds,
  }) async {
    final database = await GakujiUserDatabase.database;

    await database.transaction((transaction) async {
      final now = _now;
      final savedDeckIds = decks.map((deck) => deck.id).toSet();
      final savedFolderIds = folders.map((folder) => folder.id).toSet();

      await _deleteRemovedDecks(
        transaction: transaction,
        savedDeckIds: savedDeckIds,
      );

      for (var deckIndex = 0; deckIndex < decks.length; deckIndex++) {
        final deck = decks[deckIndex];

        await _saveDeck(
          transaction: transaction,
          deck: deck,
          position: deckIndex,
          now: now,
        );
      }

      await _deleteRemovedFolders(
        transaction: transaction,
        savedFolderIds: savedFolderIds,
      );

      for (var folderIndex = 0; folderIndex < folders.length; folderIndex++) {
        final folder = folders[folderIndex];

        await _saveFolder(
          transaction: transaction,
          folder: folder,
          position: folderIndex,
          existingDeckIds: savedDeckIds,
          now: now,
        );
      }

      await _syncPinnedDecks(
        transaction: transaction,
        pinnedDeckIds: pinnedDeckIds,
        existingDeckIds: savedDeckIds,
        now: now,
      );
    });
  }

  static Future<void> _deleteRemovedDecks({
    required Transaction transaction,
    required Set<String> savedDeckIds,
  }) async {
    final existingRows = await transaction.query(
      'decks',
      columns: ['id'],
    );

    for (final row in existingRows) {
      final deckId = row['id']?.toString() ?? '';

      if (deckId.isEmpty || savedDeckIds.contains(deckId)) continue;

      await transaction.delete(
        'decks',
        where: 'id = ?',
        whereArgs: [deckId],
      );
    }
  }

  static Future<void> _saveDeck({
    required Transaction transaction,
    required Deck deck,
    required int position,
    required int now,
  }) async {
    await transaction.insert(
      'decks',
      {
        'id': deck.id,
        'name': deck.name,
        'type': _deckTypeToText(deck.type),
        'review_enabled': 0,
        'active_study_mode': 'study',
        'review_enabled_at': null,
        'last_study_index': 0,
        'is_shuffled': 0,
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
        'position': position,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [deck.id],
    );

    final existingTermRows = await transaction.query(
      'deck_terms',
      columns: ['id'],
      where: 'deck_id = ?',
      whereArgs: [deck.id],
    );
    final savedTermIds = deck.terms.map((term) => term.id).toSet();

    for (final row in existingTermRows) {
      final termId = row['id']?.toString() ?? '';

      if (termId.isEmpty || savedTermIds.contains(termId)) continue;

      await transaction.delete(
        'deck_terms',
        where: 'id = ?',
        whereArgs: [termId],
      );
    }

    for (var termIndex = 0; termIndex < deck.terms.length; termIndex++) {
      final term = deck.terms[termIndex];
      final termJson = Map<String, dynamic>.from(term.toJson());

      if (deck.type == DeckType.hybrid) {
        termJson['_hybridCardMode'] = _hybridCardModeToText(
          deck.cardModeFor(term),
        );
      }

      final values = <String, Object?>{
        'deck_id': deck.id,
        'source_id': term.sourceId ?? term.id,
        'term_json': jsonEncode(termJson),
        'marked': _boolToInt(term.marked),
        'position': termIndex,
        'updated_at': now,
      };

      await transaction.insert(
        'deck_terms',
        {
          'id': term.id,
          ...values,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      await transaction.update(
        'deck_terms',
        values,
        where: 'id = ?',
        whereArgs: [term.id],
      );
    }
  }

  static Future<void> _deleteRemovedFolders({
    required Transaction transaction,
    required Set<String> savedFolderIds,
  }) async {
    final existingRows = await transaction.query(
      'folders',
      columns: ['id'],
    );

    for (final row in existingRows) {
      final folderId = row['id']?.toString() ?? '';

      if (folderId.isEmpty || savedFolderIds.contains(folderId)) continue;

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
  }) async {
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
      {
        'name': folder.name,
        'position': position,
        'updated_at': now,
      },
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

      await transaction.delete(
        'folder_decks',
        where: 'folder_id = ? AND deck_id = ?',
        whereArgs: [folder.id, deckId],
      );
    }

    var positionIndex = 0;

    for (final deckId in folder.deckIds) {
      if (!existingDeckIds.contains(deckId)) continue;

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
        {
          'position': positionIndex,
        },
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

      await transaction.delete(
        'pinned_decks',
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
    }

    var positionIndex = 0;

    for (final deckId in pinnedDeckIds) {
      if (!existingDeckIds.contains(deckId)) continue;

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
        {
          'position': positionIndex,
        },
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

    await _saveReviewCardWithExecutor(
      executor: database,
      card: card,
      now: _now,
    );
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
      );

      await _saveReviewLogWithExecutor(
        executor: transaction,
        reviewLog: reviewLog,
        now: now,
      );
    });
  }

  static Future<void> syncReviewCards(List<ReviewCard> cards) async {
    final database = await GakujiUserDatabase.database;

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
        );
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

    for (final row in rows) {
      final reviewCardId = row['id']?.toString() ?? '';

      if (reviewCardId.isEmpty || retainedReviewCardIds.contains(reviewCardId)) {
        continue;
      }

      await database.delete(
        'review_cards',
        where: 'id = ?',
        whereArgs: [reviewCardId],
      );
    }
  }

  static Future<void> deleteReviewCardsForDeck(String deckId) async {
    final database = await GakujiUserDatabase.database;

    await database.delete(
      'review_cards',
      where: 'deck_id = ?',
      whereArgs: [deckId],
    );
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

    await _saveReviewLogWithExecutor(
      executor: database,
      reviewLog: reviewLog,
      now: _now,
    );
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
  }) async {
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

    await database.insert(
      'dictionary_notes',
      {
        'source_id': sourceId,
        'note': note,
        'updated_at': _now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
  }) async {
    final database = await GakujiUserDatabase.database;

    await database.insert(
      'user_preferences',
      {
        'key': key,
        'value': value,
        'updated_at': _now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deletePreference(String key) async {
    final database = await GakujiUserDatabase.database;

    await database.delete(
      'user_preferences',
      where: 'key = ?',
      whereArgs: [key],
    );
  }
}
