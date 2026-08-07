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

    static Future<List<Term>> loadRecentSearches() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .get();

    final data = doc.data()?['recentSearches'];

    if (data is! List) return [];

    final loadedSearches = <Term>[];

    for (final item in data) {
      if (item is! Map) continue;

      try {
        loadedSearches.add(Term.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // Skip corrupted entries instead of crashing the app.
      }
    }

    return loadedSearches;
  }

  static Future<void> saveRecentSearches(List<Term> recentSearches) async {
    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'recentSearches': recentSearches.map((term) => term.toJson()).toList(),
    }, SetOptions(merge: true));
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
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('reviewCards')
        .orderBy('dueDate')
        .get();

    return snapshot.docs.map((doc) => ReviewCard.fromJson(doc.data())).toList();
  }

  static Future<void> saveReviewCard(ReviewCard card) async {
    final userDoc = FirebaseFirestore.instance.collection('users').doc(_uid);
    final deckDoc = await userDoc.collection('decks').doc(card.deckId).get();

    if (!deckDoc.exists) return;

    await userDoc.collection('reviewCards').doc(card.id).set(card.toJson());
  }

  static Future<void> saveReviewResult({
    required ReviewCard card,
    required ReviewLogEntry reviewLog,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final userDoc = firestore.collection('users').doc(_uid);
    final deckDoc = await userDoc.collection('decks').doc(card.deckId).get();

    if (!deckDoc.exists) return;

    final batch = firestore.batch();

    batch.set(userDoc.collection('reviewCards').doc(card.id), card.toJson());
    batch.set(
      userDoc.collection('reviewLogs').doc(reviewLog.id),
      reviewLog.toJson(),
    );

    await batch.commit();
  }

  static Future<void> syncReviewCards(List<ReviewCard> cards) async {
    final reviewCardsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('reviewCards');

    final existingDocs = await reviewCardsRef.get();
    final retainedIds = cards.map((card) => card.id).toSet();

    final batch = FirebaseFirestore.instance.batch();

    for (final doc in existingDocs.docs) {
      if (!retainedIds.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    for (final card in cards) {
      batch.set(reviewCardsRef.doc(card.id), card.toJson());
    }

    await batch.commit();
  }

  static Future<void> deleteReviewCardsNotInForDeck({
    required String deckId,
    required Set<String> retainedReviewCardIds,
  }) async {
    final reviewCardsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('reviewCards');

    final snapshot = await reviewCardsRef
        .where('deckId', isEqualTo: deckId)
        .get();

    final batch = FirebaseFirestore.instance.batch();

    for (final doc in snapshot.docs) {
      if (!retainedReviewCardIds.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    await batch.commit();
  }

  static Future<void> deleteReviewCardsForDeck(String deckId) async {
    final reviewCardsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('reviewCards');

    final snapshot = await reviewCardsRef
        .where('deckId', isEqualTo: deckId)
        .get();

    final batch = FirebaseFirestore.instance.batch();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  static Future<List<ReviewLogEntry>> loadReviewLogs({
    String? reviewCardId,
  }) async {
    final reviewLogsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('reviewLogs');

    final snapshot = reviewCardId == null
        ? await reviewLogsRef.get()
        : await reviewLogsRef
              .where('reviewCardId', isEqualTo: reviewCardId)
              .get();

    final loadedLogs = snapshot.docs
        .map((doc) => ReviewLogEntry.fromJson(doc.data()))
        .toList();

    loadedLogs.sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt));

    return loadedLogs;
  }

static Future<void> saveReviewLog(ReviewLogEntry reviewLog) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('reviewLogs')
        .doc(reviewLog.id)
        .set(reviewLog.toJson());
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
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(_uid);

    final doc = await userDocRef.get();
    final existingPreferences = doc.data()?['preferences'];

    final updatedPreferences = <String, dynamic>{
      if (existingPreferences is Map)
        ...Map<String, dynamic>.from(existingPreferences),
      key: value,
    };

    await userDocRef.set({
      'preferences': updatedPreferences,
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
