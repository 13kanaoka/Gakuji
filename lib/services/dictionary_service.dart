import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/dictionary_data.dart' as fallback_dictionary;
import '../models/term.dart';

class DictionaryService {
  static const String dictionaryAssetPath = 'assets/dictionary/dictionary.db';
 /// Whenever you regenerate assets/dictionary/dictionary.db,
 ///increase the dictionary version by 1, ex: v7,v8, etc.///
  static const String dictionaryDatabaseFileName = 'dictionary_v7.db';

  static Database? _database;
  static Future<void>? _loadFuture;

  static Future<void> loadDictionary() {
    if (_database != null) {
      return Future.value();
    }

    _loadFuture ??= _openDictionaryDatabase().catchError((error) {
      _loadFuture = null;
      throw error;
    });

    return _loadFuture!;
  }

  static Future<void> _openDictionaryDatabase() async {
    final directory = await getApplicationSupportDirectory();
    final databasePath = path.join(
      directory.path,
      dictionaryDatabaseFileName,
    );

    await _copyAssetDatabaseIfNeeded(databasePath);

    final database = await openDatabase(
      databasePath,
      readOnly: true,
    );

    await database.rawQuery('SELECT COUNT(*) FROM terms LIMIT 1');

    _database = database;
  }

  static Future<void> _copyAssetDatabaseIfNeeded(String databasePath) async {
    final databaseFile = File(databasePath);

    if (await databaseFile.exists()) return;

    final assetData = await rootBundle.load(dictionaryAssetPath);
    final assetBytes = assetData.buffer.asUint8List(
      assetData.offsetInBytes,
      assetData.lengthInBytes,
    );

    await databaseFile.parent.create(recursive: true);
    await databaseFile.writeAsBytes(
      assetBytes,
      flush: true,
    );
  }

  static Future<List<Term>> search(
    String rawQuery, {
    int limit = 60,
  }) async {
    final query = rawQuery.trim();

    if (query.isEmpty) return const [];

    await loadDictionary();

    final database = _database;

    if (database == null) {
      return _fallbackSearch(query, limit: limit);
    }

    if (_isLikelyEnglishQuery(query)) {
      return _searchEnglish(
        database: database,
        query: query,
        limit: limit,
      );
    }

    return _searchJapanese(
      database: database,
      query: query,
      limit: limit,
    );
  }

  static Future<List<Term>> _searchEnglish({
    required Database database,
    required String query,
    required int limit,
  }) async {
    final lowerQuery = query.toLowerCase();

    final tokens = lowerQuery
        .split(RegExp(r'[^a-zA-Z]+'))
        .map((token) => token.trim())
        .where((token) {
      return token.isNotEmpty && !_isEnglishStopWord(token);
    }).toList();

    final searchTokens = tokens.isEmpty ? <String>[lowerQuery] : tokens;

    final exactRows = await _searchEnglishByExactKeywords(
      database: database,
      keywords: searchTokens,
      limit: limit,
    );

    if (exactRows.isNotEmpty) {
      return _termsFromRows(database, exactRows);
    }

    if (lowerQuery.length < 3) return const [];

    final prefixRows = await database.rawQuery(
      """
      SELECT
        t.id,
        t.kanji,
        t.reading,
        t.meaning,
        t.part_of_speech,
        t.is_common,
        t.common_score,
        MAX(sk.weight) AS keyword_weight,
        CASE
          WHEN t.reading LIKE '%たべ%' THEN 900
          WHEN t.kanji LIKE '%食べ%' THEN 900
          WHEN t.reading LIKE '%くう%' THEN 650
          WHEN t.reading LIKE '%くい%' THEN 650
          WHEN t.kanji LIKE '%食%' THEN 350
          ELSE 0
        END AS learner_bonus,
        CASE
          WHEN t.kanji LIKE '%する' THEN 1
          WHEN t.kanji LIKE '%上がる' THEN 1
          ELSE 0
        END AS learner_penalty
      FROM search_keywords sk
      JOIN terms t ON t.id = sk.term_id
      WHERE sk.keyword LIKE ?
      GROUP BY t.id
      ORDER BY
        keyword_weight DESC,
        learner_bonus DESC,
        learner_penalty ASC,
        t.is_common DESC,
        t.common_score DESC,
        LENGTH(t.kanji) ASC
      LIMIT ?
      """,
      [
        '$lowerQuery%',
        limit,
      ],
    );

    return _termsFromRows(database, prefixRows);
  }

  static Future<List<Map<String, Object?>>> _searchEnglishByExactKeywords({
    required Database database,
    required List<String> keywords,
    required int limit,
  }) async {
    final placeholders = List.filled(keywords.length, '?').join(', ');

    return database.rawQuery(
      """
      SELECT
        t.id,
        t.kanji,
        t.reading,
        t.meaning,
        t.part_of_speech,
        t.is_common,
        t.common_score,
        MAX(sk.weight) AS keyword_weight,
        CASE
          WHEN t.reading LIKE '%たべ%' THEN 900
          WHEN t.kanji LIKE '%食べ%' THEN 900
          WHEN t.reading LIKE '%くう%' THEN 650
          WHEN t.reading LIKE '%くい%' THEN 650
          WHEN t.kanji LIKE '%食%' THEN 350
          ELSE 0
        END AS learner_bonus,
        CASE
          WHEN t.kanji LIKE '%する' THEN 1
          WHEN t.kanji LIKE '%上がる' THEN 1
          ELSE 0
        END AS learner_penalty
      FROM search_keywords sk
      JOIN terms t ON t.id = sk.term_id
      WHERE sk.keyword IN ($placeholders)
      GROUP BY t.id
      ORDER BY
        keyword_weight DESC,
        learner_bonus DESC,
        learner_penalty ASC,
        t.is_common DESC,
        t.common_score DESC,
        LENGTH(t.kanji) ASC
      LIMIT ?
      """,
      [
        ...keywords,
        limit,
      ],
    );
  }

  static Future<List<Term>> _searchJapanese({
    required Database database,
    required String query,
    required int limit,
  }) async {
    final prefixQuery = '$query%';
    final containsQuery = '%$query%';

    final rows = await database.rawQuery(
      """
      SELECT
        t.id,
        t.kanji,
        t.reading,
        t.meaning,
        t.part_of_speech,
        t.is_common,
        t.common_score,
        CASE
          WHEN t.kanji = ? THEN 5000
          WHEN t.reading = ? THEN 4900
          WHEN t.kanji LIKE ? THEN 3600
          WHEN t.reading LIKE ? THEN 3500
          WHEN t.kanji LIKE ? THEN 1800
          WHEN t.reading LIKE ? THEN 1700
          ELSE 1000
        END AS match_score
      FROM terms t
      WHERE
        t.kanji = ?
        OR t.reading = ?
        OR t.kanji LIKE ?
        OR t.reading LIKE ?
        OR t.kanji LIKE ?
        OR t.reading LIKE ?
      ORDER BY
        match_score DESC,
        t.is_common DESC,
        t.common_score DESC,
        LENGTH(t.kanji) ASC
      LIMIT ?
      """,
      [
        query,
        query,
        prefixQuery,
        prefixQuery,
        containsQuery,
        containsQuery,
        query,
        query,
        prefixQuery,
        prefixQuery,
        containsQuery,
        containsQuery,
        limit,
      ],
    );

    return _termsFromRows(database, rows);
  }

  static Future<Term> getTermByIdAsync(String id) async {
    await loadDictionary();

    final database = _database;

    if (database == null) {
      return fallback_dictionary.getTermById(id);
    }

    final rows = await database.query(
      'terms',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return fallback_dictionary.getTermById(id);
    }

    final terms = await _termsFromRows(database, rows);

    return terms.first;
  }

  static Term getTermById(String id) {
    return fallback_dictionary.getTermById(id);
  }

  static Future<List<Term>> _termsFromRows(
    Database database,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return const [];

    final ids = rows.map((row) => row['id'].toString()).toList();
    final definitionsByTermId = await _definitionsByTermId(
      database: database,
      termIds: ids,
    );

    return rows.map((row) {
      final id = row['id'].toString();

      return Term(
        id: id,
        kanji: row['kanji']?.toString() ?? '',
        reading: row['reading']?.toString() ?? '',
        meaning: row['meaning']?.toString() ?? '',
        partOfSpeech: row['part_of_speech']?.toString() ?? 'word',
        definitions: definitionsByTermId[id] ?? const [],
        isCommon: row['is_common'] == 1,
        kanjiMeaning: row['meaning']?.toString() ?? '',
      );
    }).toList();
  }

  static Future<Map<String, List<String>>> _definitionsByTermId({
    required Database database,
    required List<String> termIds,
  }) async {
    if (termIds.isEmpty) return const {};

    final placeholders = List.filled(termIds.length, '?').join(', ');

    final rows = await database.rawQuery(
      """
      SELECT term_id, definition
      FROM definitions
      WHERE term_id IN ($placeholders)
      ORDER BY term_id, position
      """,
      termIds,
    );

    final definitionsByTermId = <String, List<String>>{};

    for (final row in rows) {
      final termId = row['term_id']?.toString() ?? '';
      final definition = row['definition']?.toString() ?? '';

      if (termId.isEmpty || definition.isEmpty) continue;

      definitionsByTermId.putIfAbsent(termId, () => <String>[]).add(definition);
    }

    return definitionsByTermId;
  }

  static List<Term> _fallbackSearch(
    String rawQuery, {
    required int limit,
  }) {
    final query = rawQuery.trim();
    final lowerQuery = query.toLowerCase();

    final results = fallback_dictionary.dictionaryWords.where((term) {
      return term.kanji.contains(query) ||
          term.reading.contains(query) ||
          term.meaning.toLowerCase().contains(lowerQuery) ||
          term.definitions.any(
            (definition) => definition.toLowerCase().contains(lowerQuery),
          );
    }).toList();

    return results.take(limit).toList();
  }

  static bool _isLikelyEnglishQuery(String query) {
    return RegExp(r'[a-zA-Z]').hasMatch(query);
  }

  static bool _isEnglishStopWord(String value) {
    return const {
      'a',
      'an',
      'and',
      'as',
      'at',
      'be',
      'by',
      'for',
      'from',
      'in',
      'into',
      'is',
      'it',
      'of',
      'on',
      'or',
      'the',
      'to',
      'with',
    }.contains(value);
  }
}