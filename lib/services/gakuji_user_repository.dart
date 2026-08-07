import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  static String get _uid {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError("No signed-in user");
    }

    return user.uid;
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

  static Future<List<Deck>> loadDecks() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('decks')
        .orderBy('position')
        .get();

    final loadedDecks = <Deck>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final deckType = _deckTypeFromText(data['type']?.toString() ?? 'reading');

      final loadedTerms = <Term>[];
      final termsData = data['terms'];

      if (termsData is List) {
        for (final termData in termsData) {
          if (termData is Map) {
            try {
              loadedTerms.add(
                Term.fromJson(Map<String, dynamic>.from(termData)),
              );
            } catch (_) {
              // skip corrupted term entries instead of crashing the app
            }
          }
        }
      }
      final loadedHybridCardModes = <String, HybridCardMode>{};
      final hybridModesData = data['hybridCardModes'];

      if (hybridModesData is Map) {
        hybridModesData.forEach((key, value) {
          loadedHybridCardModes[key.toString()] = hybridCardModeFromStorage(
            value?.toString(),
          );
        });
      }
      loadedDecks.add(
        Deck(
          id: doc.id,
          name: data['name']?.toString() ?? '',
          type: deckType,
          terms: loadedTerms,
          hybridCardModes: loadedHybridCardModes,
          reviewEnabled: data['reviewEnabled'] == true,
          activeStudyMode: data['activeStudyMode'] == 'review'
              ? StudyMode.review
              : StudyMode.study,
          reviewEnabledAt: data['reviewEnabledAt'] != null
              ? DateTime.tryParse(data['reviewEnabledAt'].toString())
              : null,
          lastStudyIndex: data['lastStudyIndex'] is int
              ? data['lastStudyIndex'] as int
              : int.tryParse(data['lastStudyIndex']?.toString() ?? '') ?? 0,
          isShuffled: data['isShuffled'] == true,
        ),
      );
    }

    return loadedDecks;
  }

  static Future<List<Folder>> loadFolders() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('folders')
        .orderBy('position')
        .get();

    final loadedFolders = <Folder>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final deckIdsData = data["deckIds"];

      final deckIds = deckIdsData is List
          ? deckIdsData.map((deckId) => deckId.toString()).toList()
          : <String>[];

      loadedFolders.add(
        Folder(
          id: doc.id,
          name: data['name']?.toString() ?? '',
          deckIds: deckIds,
        ),
      );
    }

    return loadedFolders;
  }

  static Future<List<String>> loadPinnedDeckIds() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .get();

    final data = doc.data();
    final pinnedDeckIdsData = data?['pinnedDeckIds'];

    if (pinnedDeckIdsData is! List) return [];

    return pinnedDeckIdsData.map((deckId) => deckId.toString()).toList();
  }

  static Future<void> saveAll({
    required List<Deck> decks,
    required List<Folder> folders,
    required List<String> pinnedDeckIds,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final userDoc = firestore.collection('users').doc(_uid);
    final decksRef = userDoc.collection('decks');
    final foldersRef = userDoc.collection('folders');

    final batch = firestore.batch();

    final existingDeckDocs = await decksRef.get();
    final savedDeckIds = decks.map((deck) => deck.id).toSet();

    for (final doc in existingDeckDocs.docs) {
      if (!savedDeckIds.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    for (var deckIndex = 0; deckIndex < decks.length; deckIndex++) {
      final deck = decks[deckIndex];
      final hybridCardModes = <String, String>{};

      deck.hybridCardModes.forEach((termId, mode) {
        hybridCardModes[termId] = _hybridCardModeToText(mode);
      });

      batch.set(decksRef.doc(deck.id), {
        'name': deck.name,
        'type': _deckTypeToText(deck.type),
        'terms': deck.terms.map((term) => term.toJson()).toList(),
        'hybridCardModes': hybridCardModes,
        'reviewEnabled': deck.reviewEnabled,
        'activeStudyMode': deck.activeStudyMode == StudyMode.review
            ? 'review'
            : 'study',
        'reviewEnabledAt': deck.reviewEnabledAt?.toUtc().toIso8601String(),
        'lastStudyIndex': deck.lastStudyIndex,
        'isShuffled': deck.isShuffled,
        'position': deckIndex,
      });
    }

    final existingFolderDocs = await foldersRef.get();
    final savedFolderIds = folders.map((folder) => folder.id).toSet();

    for (final doc in existingFolderDocs.docs) {
      if (!savedFolderIds.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    for (var folderIndex = 0; folderIndex < folders.length; folderIndex++) {
      final folder = folders[folderIndex];
      final validDeckIds = folder.deckIds
          .where((deckId) => savedDeckIds.contains(deckId))
          .toList();

      batch.set(foldersRef.doc(folder.id), {
        'name': folder.name,
        'deckIds': validDeckIds,
        'position': folderIndex,
      });
    }

    final validPinnedDeckIds = pinnedDeckIds
        .where((deckId) => savedDeckIds.contains(deckId))
        .toList();

    batch.set(userDoc, {
      'pinnedDeckIds': validPinnedDeckIds,
    }, SetOptions(merge: true));

    await batch.commit();
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

      if (reviewCardId.isEmpty ||
          retainedReviewCardIds.contains(reviewCardId)) {
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

    await executor.insert('review_logs', {
      'id': reviewLog.id,
      ...values,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

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

    await executor.insert('review_cards', {
      'id': card.id,
      ...values,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

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

    await database.insert('dictionary_notes', {
      'source_id': sourceId,
      'note': note,
      'updated_at': _now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String?> loadPreference(String key) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .get();

    final preferences = doc.data()?['preferences'];

    if (preferences is! Map) return null;

    return preferences[key]?.toString();
  }

  static Future<void> savePreference({
    required String key,
    required String value,
  }) async {
    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'preferences.$key': value,
    }, SetOptions(merge: true));
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
