import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/dictionary_data.dart' as fallback_dictionary;
import '../models/term.dart';

class DictionaryService {
  static const String dictionaryAssetPath = 'assets/dictionary/dictionary.db';

  /// Increase this whenever you regenerate assets/dictionary/dictionary.db.
  /// This forces the app to copy the fresh database into app storage.
  static const String dictionaryDatabaseFileName = 'dictionary_v18.db';

  static const String _kanjiIdPrefix = 'kanji_';
  static const String _storedListSeparator = ';';

  static Database? _database;
  static Future<void>? _loadFuture;
  static bool _usingFallbackDictionary = false;

  static Future<void> loadDictionary() {
    if (_database != null || _usingFallbackDictionary) {
      return Future.value();
    }

    _loadFuture ??= _openDictionaryDatabase().catchError(
      (Object error, StackTrace stackTrace) {
        debugPrint('DictionaryService failed to load SQLite dictionary: $error');
        debugPrint('$stackTrace');

        _database = null;
        _usingFallbackDictionary = true;
      },
    );

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
    await database.rawQuery('SELECT COUNT(*) FROM kanji_entries LIMIT 1');

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

    if (query.isEmpty || limit <= 0) return const [];

    await loadDictionary();

    final database = _database;

    if (database == null) {
      return _fallbackSearch(query, limit: limit);
    }

    if (_isLikelyEnglishQuery(query)) {
      final wordResults = await _searchEnglish(
        database: database,
        query: query,
        limit: limit,
      );

      final kanjiResults = await _searchKanjiByEnglish(
        database: database,
        query: query,
        limit: _kanjiSearchLimit(limit),
      );

      return _mergeSearchResults(
        primary: wordResults,
        secondary: kanjiResults,
        limit: limit,
        secondaryInsertIndex: 5,
      );
    }

    final wordResults = await _searchJapanese(
      database: database,
      query: query,
      limit: limit,
    );

    final kanjiResults = await _searchKanjiByJapanese(
      database: database,
      query: query,
    );

    return _mergeSearchResults(
      primary: kanjiResults,
      secondary: wordResults,
      limit: limit,
    );
  }

  /// Finds likely lexical entries for a CSV import row.
  ///
  /// Exact spelling and reading matches are fetched in one database query so
  /// large imports do not need to run the full dictionary search repeatedly.
  /// When no exact entry exists, the normal ranked search is used as a
  /// fallback so the user can still choose a close result manually.
  static Future<List<Term>> findImportCandidates({
    String term = '',
    List<String> readings = const [],
    int limit = 12,
  }) async {
    if (limit <= 0) return const [];

    final lookupValues = <String>[];

    void addLookupValue(String value) {
      final normalized = value.trim();

      if (normalized.isEmpty || lookupValues.contains(normalized)) return;

      lookupValues.add(normalized);
    }

    addLookupValue(term);

    for (final reading in readings) {
      addLookupValue(reading);
    }

    if (lookupValues.isEmpty) return const [];

    await loadDictionary();

    final database = _database;

    if (database == null) {
      final merged = <String, Term>{};

      for (final query in lookupValues) {
        for (final result in _fallbackSearch(query, limit: limit)) {
          merged.putIfAbsent(result.id, () => result);
        }
      }

      return merged.values.take(limit).toList(growable: false);
    }

    final placeholders = List.filled(lookupValues.length, '?').join(', ');
    final preferredValue = term.trim().isNotEmpty
        ? term.trim()
        : lookupValues.first;
    final exactRows = await database.rawQuery(
      """
      SELECT
        t.id,
        t.kanji,
        t.reading,
        t.meaning,
        t.part_of_speech,
        t.is_common,
        t.common_score
      FROM terms t
      WHERE
        t.kanji IN ($placeholders)
        OR t.reading IN ($placeholders)
      ORDER BY
        CASE
          WHEN t.kanji = ? THEN 0
          WHEN t.reading = ? THEN 1
          ELSE 2
        END,
        t.is_common DESC,
        t.common_score DESC,
        LENGTH(t.kanji) ASC
      LIMIT ?
      """,
      [
        ...lookupValues,
        ...lookupValues,
        preferredValue,
        preferredValue,
        limit,
      ],
    );

    if (exactRows.isNotEmpty) {
      return _termsFromRows(database, exactRows);
    }

    return search(
      preferredValue,
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

  static Future<List<Term>> _searchKanjiByEnglish({
    required Database database,
    required String query,
    required int limit,
  }) async {
    final lowerQuery = query.toLowerCase().trim();

    if (lowerQuery.isEmpty || limit <= 0) return const [];

    final exactStoredMeaning = ';$lowerQuery;';
    final rows = lowerQuery.length < 3
        ? await database.rawQuery(
            """
            SELECT
              character,
              meaning,
              onyomi,
              kunyomi,
              nanori,
              stroke_count,
              grade,
              jlpt_level,
              frequency,
              radical,
              has_word_entry
            FROM kanji_entries
            WHERE
              LOWER(meaning) = ?
              OR INSTR(';' || LOWER(meaning) || ';', ?) > 0
            """,
            [
              lowerQuery,
              exactStoredMeaning,
            ],
          )
        : await database.rawQuery(
            """
            SELECT
              character,
              meaning,
              onyomi,
              kunyomi,
              nanori,
              stroke_count,
              grade,
              jlpt_level,
              frequency,
              radical,
              has_word_entry
            FROM kanji_entries
            WHERE LOWER(meaning) LIKE ?
            """,
            ['%$lowerQuery%'],
          );

    final rankedRows = rows
        .map(
          (row) => MapEntry(
            row,
            _kanjiMeaningMatchScore(
              row['meaning']?.toString() ?? '',
              lowerQuery,
            ),
          ),
        )
        .where((candidate) => candidate.value > 0)
        .toList();

    rankedRows.sort((left, right) {
      final scoreComparison = right.value.compareTo(left.value);

      if (scoreComparison != 0) return scoreComparison;

      final leftGrade = _nullableInt(left.key['grade']);
      final rightGrade = _nullableInt(right.key['grade']);
      final leftIsSchoolKanji = leftGrade != null && leftGrade <= 6;
      final rightIsSchoolKanji = rightGrade != null && rightGrade <= 6;

      if (leftIsSchoolKanji != rightIsSchoolKanji) {
        return leftIsSchoolKanji ? -1 : 1;
      }

      final leftFrequency = _nullableInt(left.key['frequency']);
      final rightFrequency = _nullableInt(right.key['frequency']);

      if (leftFrequency != null && rightFrequency != null) {
        final frequencyComparison = leftFrequency.compareTo(rightFrequency);

        if (frequencyComparison != 0) return frequencyComparison;
      } else if (leftFrequency != null) {
        return -1;
      } else if (rightFrequency != null) {
        return 1;
      }

      final leftHasWordEntry = left.key['has_word_entry'] == 1;
      final rightHasWordEntry = right.key['has_word_entry'] == 1;

      if (leftHasWordEntry != rightHasWordEntry) {
        return leftHasWordEntry ? -1 : 1;
      }

      final leftCharacter = left.key['character']?.toString() ?? '';
      final rightCharacter = right.key['character']?.toString() ?? '';

      return leftCharacter.compareTo(rightCharacter);
    });

    return rankedRows
        .take(limit)
        .map((candidate) => _kanjiTermFromRow(candidate.key))
        .toList();
  }

  static Future<List<Term>> _searchKanjiByJapanese({
    required Database database,
    required String query,
  }) async {
    if (!_isSingleKanjiCharacter(query)) return const [];

    final rows = await database.query(
      'kanji_entries',
      where: 'character = ?',
      whereArgs: [query],
      limit: 1,
    );

    return rows.map(_kanjiTermFromRow).toList();
  }

  static Future<Term?> getKanjiEntryAsync(String rawCharacter) async {
    final character = rawCharacter.trim();

    if (!_isSingleKanjiCharacter(character)) return null;

    await loadDictionary();

    final database = _database;

    if (database == null) return null;

    final rows = await database.query(
      'kanji_entries',
      where: 'character = ?',
      whereArgs: [character],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return _kanjiTermFromRow(rows.first);
  }

  static Future<KanjiStrokeData?> getKanjiStrokeData(
    String rawCharacter,
  ) async {
    final character = rawCharacter.trim();

    if (!_isSingleKanjiCharacter(character)) return null;

    await loadDictionary();

    final database = _database;

    if (database == null) return null;

    try {
      final rows = await database.query(
        'kanji_strokes',
        columns: [
          'character',
          'codepoint',
          'view_box',
          'strokes_json',
        ],
        where: 'character = ?',
        whereArgs: [character],
        limit: 1,
      );

      if (rows.isEmpty) return null;

      final row = rows.first;
      final rawStrokes = jsonDecode(
        row['strokes_json']?.toString() ?? '[]',
      );

      if (rawStrokes is! List) return null;

      final strokes = rawStrokes
          .whereType<Map>()
          .map(
            (item) => KanjiStroke.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((stroke) => stroke.number > 0 && stroke.pathData.isNotEmpty)
          .toList()
        ..sort((left, right) => left.number.compareTo(right.number));

      if (strokes.isEmpty) return null;

      return KanjiStrokeData(
        character: row['character']?.toString() ?? character,
        codepoint: row['codepoint']?.toString() ?? '',
        viewBox: row['view_box']?.toString() ?? '0 0 109 109',
        strokes: strokes,
      );
    } on DatabaseException catch (error) {
      debugPrint('Kanji stroke data unavailable for $character: $error');
      return null;
    } on FormatException catch (error) {
      debugPrint('Kanji stroke JSON is invalid for $character: $error');
      return null;
    }
  }

  static Future<List<Term>> getKanjiEntriesForText(String text) async {
    final characters = _uniqueKanjiCharacters(text);

    if (characters.isEmpty) return const [];

    await loadDictionary();

    final database = _database;

    if (database == null) return const [];

    final placeholders = List.filled(characters.length, '?').join(', ');

    final rows = await database.rawQuery(
      """
      SELECT
        character,
        meaning,
        onyomi,
        kunyomi,
        nanori,
        stroke_count,
        grade,
        jlpt_level,
        frequency,
        radical,
        has_word_entry
      FROM kanji_entries
      WHERE character IN ($placeholders)
      """,
      characters,
    );

    final entriesByCharacter = <String, Term>{};

    for (final row in rows) {
      final entry = _kanjiTermFromRow(row);
      entriesByCharacter[entry.kanji] = entry;
    }

    return characters
        .map((character) => entriesByCharacter[character])
        .whereType<Term>()
        .toList();
  }

  static Future<Term> getTermByIdAsync(String id) async {
    if (id.startsWith(_kanjiIdPrefix)) {
      final character = id.substring(_kanjiIdPrefix.length);
      final kanjiEntry = await getKanjiEntryAsync(character);

      if (kanjiEntry != null) return kanjiEntry;

      throw StateError('Kanji dictionary entry not found: $character');
    }

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
    final sensesByTermId = await _sensesByTermId(
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
        senses: sensesByTermId[id] ?? const [],
        isCommon: row['is_common'] == 1,
        kanjiMeaning: row['meaning']?.toString() ?? '',
      );
    }).toList();
  }

  static Term _kanjiTermFromRow(Map<String, Object?> row) {
    final character = row['character']?.toString() ?? '';
    final meanings = _splitStoredList(row['meaning']);
    final onyomi = _splitStoredList(row['onyomi']);
    final kunyomi = _splitStoredList(row['kunyomi']);
    final nanori = _splitStoredList(row['nanori']);

    final meaning = meanings.join(' / ');
    final reading = _kanjiReadingLabel(
      character: character,
      onyomi: onyomi,
      kunyomi: kunyomi,
    );
    final frequency = _nullableInt(row['frequency']);

    return Term(
      id: '$_kanjiIdPrefix$character',
      kanji: character,
      reading: reading,
      meaning: meaning,
      partOfSpeech: 'kanji',
      definitions: meanings,
      isCommon: frequency != null && frequency <= 2500,
      kanjiMeaning: meaning,
      onyomi: onyomi,
      kunyomi: kunyomi,
      nanori: nanori,
      strokeCount: _nullableInt(row['stroke_count']),
      grade: _nullableInt(row['grade']),
      jlptLevel: _nullableText(row['jlpt_level']),
      frequency: frequency,
      radical: _nullableText(row['radical']),
    );
  }

  static Future<Map<String, List<DictionarySense>>> _sensesByTermId({
    required Database database,
    required List<String> termIds,
  }) async {
    if (termIds.isEmpty) return const {};

    final placeholders = List.filled(termIds.length, '?').join(', ');

    final senseRows = await database.rawQuery(
      """
      SELECT term_id, sense_index, position
      FROM senses
      WHERE term_id IN ($placeholders)
      ORDER BY term_id, position
      """,
      termIds,
    );

    final glossRows = await database.rawQuery(
      """
      SELECT term_id, sense_index, definition
      FROM definitions
      WHERE term_id IN ($placeholders)
      ORDER BY term_id, sense_index, position
      """,
      termIds,
    );

    final partOfSpeechRows = await database.rawQuery(
      """
      SELECT term_id, sense_index, tag
      FROM sense_part_of_speech
      WHERE term_id IN ($placeholders)
      ORDER BY term_id, sense_index, position
      """,
      termIds,
    );

    final relatedTermRows = await database.rawQuery(
      """
      SELECT term_id, sense_index, related_term
      FROM sense_related_terms
      WHERE term_id IN ($placeholders)
      ORDER BY term_id, sense_index, position
      """,
      termIds,
    );

    final exampleRows = await database.rawQuery(
      """
      SELECT id, term_id, sense_index, japanese, reading, english
      FROM examples
      WHERE term_id IN ($placeholders)
      ORDER BY term_id, sense_index, position
      """,
      termIds,
    );

    final exampleTokenRows = await database.rawQuery(
      """
      SELECT
        et.example_id,
        et.position,
        et.surface,
        et.headword,
        et.reading,
        et.term_id
      FROM example_tokens et
      INNER JOIN examples e ON e.id = et.example_id
      WHERE e.term_id IN ($placeholders)
      ORDER BY et.example_id, et.position
      """,
      termIds,
    );

    final senseOrderByTermId = <String, List<int>>{};
    final glossesBySense = <String, Map<int, List<String>>>{};
    final partOfSpeechBySense = <String, Map<int, List<String>>>{};
    final relatedTermsBySense = <String, Map<int, List<String>>>{};
    final examplesBySense = <String, Map<int, List<DictionaryExample>>>{};
    final tokensByExampleId = <int, List<DictionaryExampleToken>>{};

    for (final row in senseRows) {
      final termId = row['term_id']?.toString() ?? '';
      final senseIndex = _nullableInt(row['sense_index']);
      if (termId.isEmpty || senseIndex == null) continue;
      senseOrderByTermId.putIfAbsent(termId, () => <int>[]).add(senseIndex);
    }

    for (final row in glossRows) {
      final termId = row['term_id']?.toString() ?? '';
      final senseIndex = _nullableInt(row['sense_index']);
      final definition = row['definition']?.toString().trim() ?? '';
      if (termId.isEmpty || senseIndex == null || definition.isEmpty) continue;
      glossesBySense
          .putIfAbsent(termId, () => <int, List<String>>{})
          .putIfAbsent(senseIndex, () => <String>[])
          .add(definition);
    }

    for (final row in partOfSpeechRows) {
      final termId = row['term_id']?.toString() ?? '';
      final senseIndex = _nullableInt(row['sense_index']);
      final tag = row['tag']?.toString().trim() ?? '';
      if (termId.isEmpty || senseIndex == null || tag.isEmpty) continue;
      partOfSpeechBySense
          .putIfAbsent(termId, () => <int, List<String>>{})
          .putIfAbsent(senseIndex, () => <String>[])
          .add(tag);
    }

    for (final row in relatedTermRows) {
      final termId = row['term_id']?.toString() ?? '';
      final senseIndex = _nullableInt(row['sense_index']);
      final relatedTerm = row['related_term']?.toString().trim() ?? '';
      if (termId.isEmpty || senseIndex == null || relatedTerm.isEmpty) continue;
      relatedTermsBySense
          .putIfAbsent(termId, () => <int, List<String>>{})
          .putIfAbsent(senseIndex, () => <String>[])
          .add(relatedTerm);
    }

    for (final row in exampleTokenRows) {
      final exampleId = _nullableInt(row['example_id']);
      final surface = row['surface']?.toString().trim() ?? '';
      final headword = row['headword']?.toString().trim() ?? '';
      final reading = row['reading']?.toString().trim() ?? '';
      final termId = _nullableText(row['term_id']);

      if (exampleId == null || (surface.isEmpty && headword.isEmpty)) {
        continue;
      }

      tokensByExampleId
          .putIfAbsent(exampleId, () => <DictionaryExampleToken>[])
          .add(
            DictionaryExampleToken(
              surface: surface,
              headword: headword,
              reading: reading,
              termId: termId,
            ),
          );
    }

    for (final row in exampleRows) {
      final exampleId = _nullableInt(row['id']);
      final termId = row['term_id']?.toString() ?? '';
      final senseIndex = _nullableInt(row['sense_index']);
      final japanese = row['japanese']?.toString().trim() ?? '';
      final reading = row['reading']?.toString().trim() ?? '';
      final english = row['english']?.toString().trim() ?? '';

      if (termId.isEmpty ||
          senseIndex == null ||
          japanese.isEmpty ||
          english.isEmpty) {
        continue;
      }

      examplesBySense
          .putIfAbsent(termId, () => <int, List<DictionaryExample>>{})
          .putIfAbsent(senseIndex, () => <DictionaryExample>[])
          .add(
            DictionaryExample(
              japanese: japanese,
              reading: reading,
              english: english,
              tokens: exampleId == null
                  ? const []
                  : tokensByExampleId[exampleId] ?? const [],
            ),
          );
    }

    final result = <String, List<DictionarySense>>{};

    for (final termId in termIds) {
      final senseIndexes = senseOrderByTermId[termId] ?? const <int>[];
      result[termId] = senseIndexes.map((senseIndex) {
        return DictionarySense(
          index: senseIndex,
          glosses: glossesBySense[termId]?[senseIndex] ?? const [],
          examples: examplesBySense[termId]?[senseIndex] ?? const [],
          relatedTerms: relatedTermsBySense[termId]?[senseIndex] ?? const [],
          partOfSpeechTags: partOfSpeechBySense[termId]?[senseIndex] ?? const [],
        );
      }).toList();
    }

    return result;
  }

  static List<Term> _mergeSearchResults({
    required List<Term> primary,
    required List<Term> secondary,
    required int limit,
    int? secondaryInsertIndex,
  }) {
    final combined = <Term>[];
    final seenIds = <String>{};

    void addTerm(Term term) {
      if (combined.length >= limit) return;
      if (!seenIds.add(term.id)) return;

      combined.add(term);
    }

    if (secondaryInsertIndex == null) {
      for (final term in primary) {
        addTerm(term);
      }

      for (final term in secondary) {
        addTerm(term);
      }

      return combined;
    }

    final insertIndex = secondaryInsertIndex.clamp(0, primary.length).toInt();

    for (final term in primary.take(insertIndex)) {
      addTerm(term);
    }

    for (final term in secondary) {
      addTerm(term);
    }

    for (final term in primary.skip(insertIndex)) {
      addTerm(term);
    }

    return combined;
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

  static int _kanjiMeaningMatchScore(
    String storedMeanings,
    String lowerQuery,
  ) {
    var bestScore = 0;

    for (final meaning in _splitStoredList(storedMeanings)) {
      final lowerMeaning = meaning.toLowerCase();

      if (lowerMeaning == lowerQuery) {
        bestScore = 6000;
        continue;
      }

      if (lowerQuery.length < 3) continue;

      final words = lowerMeaning
          .split(RegExp(r'[^a-zA-Z]+'))
          .where((word) => word.isNotEmpty)
          .toList();

      if (words.any((word) => word == lowerQuery)) {
        if (bestScore < 5500) bestScore = 5500;
        continue;
      }

      if (lowerMeaning.startsWith(lowerQuery)) {
        if (bestScore < 4200) bestScore = 4200;
        continue;
      }

      if (words.any((word) => word.startsWith(lowerQuery))) {
        if (bestScore < 3500) bestScore = 3500;
      }
    }

    return bestScore;
  }

  static List<String> _splitStoredList(Object? rawValue) {
    final value = rawValue?.toString().trim() ?? '';

    if (value.isEmpty) return const [];

    final seen = <String>{};
    final values = <String>[];

    for (final item in value.split(_storedListSeparator)) {
      final cleaned = item.trim();

      if (cleaned.isEmpty || !seen.add(cleaned)) continue;

      values.add(cleaned);
    }

    return values;
  }

  static String _kanjiReadingLabel({
    required String character,
    required List<String> onyomi,
    required List<String> kunyomi,
  }) {
    final readings = <String>[
      ...onyomi,
      ...kunyomi,
    ];

    if (readings.isEmpty) return character;

    return readings.join('・');
  }

  static List<String> _uniqueKanjiCharacters(String text) {
    final characters = <String>[];
    final seen = <String>{};

    for (final rune in text.runes) {
      if (!_isKanjiRune(rune)) continue;

      final character = String.fromCharCode(rune);

      if (seen.add(character)) {
        characters.add(character);
      }
    }

    return characters;
  }

  static bool _isSingleKanjiCharacter(String value) {
    final runes = value.runes.toList();

    return runes.length == 1 && _isKanjiRune(runes.first);
  }

  static bool _isKanjiRune(int rune) {
    return (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0x20000 && rune <= 0x2FA1F);
  }

  static int _kanjiSearchLimit(int requestedLimit) {
    if (requestedLimit <= 0) return 0;
    if (requestedLimit < 12) return requestedLimit;

    return 12;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;

    return int.tryParse(value.toString());
  }

  static String? _nullableText(Object? value) {
    if (value == null) return null;

    final text = value.toString().trim();

    return text.isEmpty ? null : text;
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
