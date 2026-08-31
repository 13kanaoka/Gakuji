import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:gakuji/data/seed/dictionary_seed.dart' as fallback_dictionary;
import 'package:gakuji/domain/term.dart';

class DictionaryTermSpellingMetadata {
  final String preferredSpelling;
  final bool usuallyWrittenInKana;
  final List<DictionarySpelling> spellings;

  const DictionaryTermSpellingMetadata({
    required this.preferredSpelling,
    required this.usuallyWrittenInKana,
    required this.spellings,
  });
}

class KanjiComponentNode {
  final String element;
  final String? original;
  final String? position;
  final String? radicalType;
  final List<KanjiComponentNode> children;

  const KanjiComponentNode({
    required this.element,
    this.original,
    this.position,
    this.radicalType,
    this.children = const [],
  });

  String get lookupCharacter {
    final canonical = original?.trim() ?? '';
    return canonical.isNotEmpty ? canonical : element;
  }

  factory KanjiComponentNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    final children = rawChildren is List
        ? rawChildren
            .whereType<Map>()
            .map(
              (child) => KanjiComponentNode.fromJson(
                Map<String, dynamic>.from(child),
              ),
            )
            .where((child) => child.element.isNotEmpty)
            .toList(growable: false)
        : const <KanjiComponentNode>[];

    String? optionalText(Object? value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    return KanjiComponentNode(
      element: json['element']?.toString().trim() ?? '',
      original: optionalText(json['original']),
      position: optionalText(json['position']),
      radicalType: optionalText(json['radical']),
      children: List.unmodifiable(children),
    );
  }
}

class DictionaryService {
  static const String dictionaryAssetPath = 'assets/dictionary/dictionary.db';

  /// Increase this whenever you regenerate assets/dictionary/dictionary.db.
  /// This forces the app to copy the fresh database into app storage.
  static const String dictionaryDatabaseFileName = 'dictionary_v22.db';

  static const String _kanjiIdPrefix = 'kanji_';
  static const String _storedListSeparator = ';';

  // JLPT vocabulary levels are supplemental metadata keyed to dictionary terms.
  static const String _wordJlptLevelsTable = 'term_jlpt_levels';
  static const String _termSpellingsTable = 'term_spellings';
  static const String _kanjiComponentTreesTable = 'kanji_component_trees';

  static Database? _database;
  static Future<void>? _loadFuture;
  static bool _usingFallbackDictionary = false;
  static bool? _hasWordJlptLevelsTable;
  static bool? _hasTermSpellingsTable;
  static bool? _hasKanjiComponentTreesTable;

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

    var database = await openDatabase(
      databasePath,
      readOnly: true,
    );

    // Preferred-writing and KanjiVG component metadata are part of the v21
    // dictionary contract. If this filename was created while an older asset
    // was still bundled, replace that stale extracted copy automatically.
    final hasPreferredWriting =
        await _databaseContainsTable(database, _termSpellingsTable);
    final hasComponentTrees =
        await _databaseContainsTable(database, _kanjiComponentTreesTable);

    if (!hasPreferredWriting || !hasComponentTrees) {
      debugPrint(
        'Dictionary metadata missing from extracted DB; refreshing bundled asset.',
      );
      await database.close();

      final databaseFile = File(databasePath);
      if (await databaseFile.exists()) {
        await databaseFile.delete();
      }

      await _copyAssetDatabaseIfNeeded(databasePath);
      database = await openDatabase(
        databasePath,
        readOnly: true,
      );
    }

    await database.rawQuery('SELECT COUNT(*) FROM terms LIMIT 1');
    await database.rawQuery('SELECT COUNT(*) FROM kanji_entries LIMIT 1');

    _hasWordJlptLevelsTable = null;
    _hasTermSpellingsTable = null;
    _hasKanjiComponentTreesTable = null;
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

  static Future<bool> _databaseContainsTable(
    Database database,
    String tableName,
  ) async {
    final rows = await database.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = ?
      LIMIT 1
      ''',
      [tableName],
    );

    return rows.isNotEmpty;
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

  /// Returns exact Japanese spelling/reading matches for one camera lookup.
  ///
  /// Unlike [search], this does not perform contains/prefix/English matching.
  /// Camera tokenization uses this so a substring is only treated as a word
  /// when that exact surface or reading exists in the dictionary.
  static Future<List<Term>> findExactJapanese(
    String rawQuery, {
    int limit = 8,
  }) async {
    final query = rawQuery.trim();

    if (query.isEmpty || limit <= 0) return const [];

    final grouped = await findExactJapaneseBatch(
      <String>[query],
      perQueryLimit: limit,
    );

    return grouped[query] ?? const [];
  }

  /// Batched exact lookup used by Camera Mode sentence breakdown.
  ///
  /// A scanned line can contain many possible substrings. Fetching them in
  /// batches avoids running a full dictionary search for every candidate.
  static Future<Map<String, List<Term>>> findExactJapaneseBatch(
    Iterable<String> rawQueries, {
    int perQueryLimit = 4,
  }) async {
    if (perQueryLimit <= 0) return const {};

    final queries = <String>[];
    final seenQueries = <String>{};

    for (final rawQuery in rawQueries) {
      final query = rawQuery.trim();
      if (query.isEmpty || !seenQueries.add(query)) continue;
      queries.add(query);
    }

    if (queries.isEmpty) return const {};

    await loadDictionary();

    final database = _database;

    if (database == null) {
      return <String, List<Term>>{
        for (final query in queries)
          query: fallback_dictionary.dictionaryWords
              .where((term) {
                return term.kanji == query || term.reading == query;
              })
              .take(perQueryLimit)
              .toList(growable: false),
      };
    }

    // Each query is used twice in the SQL IN clauses. Keep the chunk well
    // below SQLite's common 999-variable limit.
    const chunkSize = 200;
    final rowsById = <String, Map<String, Object?>>{};

    for (var start = 0; start < queries.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, queries.length).toInt();
      final chunk = queries.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');

      final rows = await database.rawQuery(
        '''
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
          t.is_common DESC,
          t.common_score DESC,
          LENGTH(t.kanji) ASC
        ''',
        <Object?>[
          ...chunk,
          ...chunk,
        ],
      );

      for (final query in chunk) {
        var addedForQuery = 0;

        for (final row in rows) {
          final kanji = row['kanji']?.toString() ?? '';
          final reading = row['reading']?.toString() ?? '';

          if (kanji != query && reading != query) continue;

          final id = row['id']?.toString() ?? '';
          if (id.isEmpty) continue;

          rowsById.putIfAbsent(id, () => row);
          addedForQuery += 1;

          if (addedForQuery >= perQueryLimit) break;
        }
      }
    }

    if (rowsById.isEmpty) {
      return <String, List<Term>>{
        for (final query in queries) query: const <Term>[],
      };
    }

    final terms = await _termsFromRows(
      database,
      rowsById.values.toList(growable: false),
    );

    final result = <String, List<Term>>{};

    for (final query in queries) {
      final kanjiMatches = <Term>[];
      final readingMatches = <Term>[];

      for (final term in terms) {
        if (term.kanji == query) {
          kanjiMatches.add(term);
        } else if (term.reading == query) {
          readingMatches.add(term);
        }
      }

      result[query] = <Term>[
        ...kanjiMatches,
        ...readingMatches,
      ].take(perQueryLimit).toList(growable: false);
    }

    return result;
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

    final directTerms = await _termsFromRows(database, rows);

    // Alternative JMdict spellings/readings already live in search_keywords.
    // Pull exact aliases as well so forms such as たばこ, 莨, and 此処 can
    // resolve to their canonical dictionary entry without scanning the full
    // spelling metadata table on every keystroke.
    final aliasRows = await database.rawQuery(
      """
      SELECT
        t.id,
        t.kanji,
        t.reading,
        t.meaning,
        t.part_of_speech,
        t.is_common,
        t.common_score,
        MAX(sk.weight) AS alias_weight
      FROM search_keywords sk
      JOIN terms t ON t.id = sk.term_id
      WHERE sk.keyword = ?
      GROUP BY t.id
      ORDER BY
        alias_weight DESC,
        t.is_common DESC,
        t.common_score DESC,
        LENGTH(t.kanji) ASC
      LIMIT ?
      """,
      [
        query.toLowerCase(),
        limit,
      ],
    );

    if (aliasRows.isEmpty) return directTerms;

    final aliasTerms = await _termsFromRows(database, aliasRows);

    // An exact known spelling/reading should outrank fuzzy prefix/contains
    // matches. This keeps searches such as たばこ anchored on the タバコ entry
    // instead of placing it below words that merely contain たばこ.
    return _mergeSearchResults(
      primary: aliasTerms,
      secondary: directTerms,
      limit: limit,
    );
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


  static Future<List<KanjiComponentNode>> getKanjiComponentTree(
    String rawCharacter,
  ) async {
    final character = rawCharacter.trim();

    if (character.runes.length != 1) return const [];

    await loadDictionary();
    final database = _database;

    if (database == null || !await _hasKanjiComponentMetadata(database)) {
      return const [];
    }

    try {
      final rows = await database.query(
        _kanjiComponentTreesTable,
        columns: const ['tree_json'],
        where: 'character = ?',
        whereArgs: [character],
        limit: 1,
      );

      if (rows.isEmpty) return const [];

      final decoded = jsonDecode(rows.first['tree_json']?.toString() ?? '[]');
      if (decoded is! List) return const [];

      final nodes = decoded
          .whereType<Map>()
          .map(
            (item) => KanjiComponentNode.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((node) => node.element.isNotEmpty)
          .toList(growable: false);

      return List.unmodifiable(nodes);
    } on DatabaseException catch (error) {
      debugPrint('Kanji component data unavailable for $character: $error');
      return const [];
    } on FormatException catch (error) {
      debugPrint('Kanji component JSON is invalid for $character: $error');
      return const [];
    }
  }

  static Future<Map<String, Term>> getKanjiEntriesByCharacters(
    Iterable<String> rawCharacters,
  ) async {
    final characters = <String>[];
    final seen = <String>{};

    for (final rawCharacter in rawCharacters) {
      final character = rawCharacter.trim();
      if (character.runes.length != 1 || !seen.add(character)) continue;
      characters.add(character);
    }

    if (characters.isEmpty) return const {};

    await loadDictionary();
    final database = _database;
    if (database == null) return const {};

    final entriesByCharacter = <String, Term>{};
    const chunkSize = 350;

    for (var offset = 0; offset < characters.length; offset += chunkSize) {
      final end = offset + chunkSize < characters.length
          ? offset + chunkSize
          : characters.length;
      final chunk = characters.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await database.rawQuery(
        '''
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
        ''',
        chunk,
      );

      for (final row in rows) {
        final term = _kanjiTermFromRow(row);
        entriesByCharacter[term.kanji] = term;
      }
    }

    return entriesByCharacter;
  }

  static String? radicalGlyphForNumber(String? rawRadical) {
    final number = int.tryParse(rawRadical?.trim() ?? '');
    if (number == null || number < 1 || number >= _kangxiRadicals.length) {
      return null;
    }

    return _kangxiRadicals[number];
  }

  static String? formatRadical(String? rawRadical) {
    final value = rawRadical?.trim() ?? '';
    if (value.isEmpty) return null;

    final glyph = radicalGlyphForNumber(value);
    return glyph == null ? value : '$glyph ($value)';
  }

  /// Finds extra kanji suggestions related to handwriting recognition results.
  ///
  /// ML Kit supplies the shape-based alternatives. This supplements those with
  /// characters that use the same dictionary radical, preferring candidates with
  /// a similar stroke count to the strongest recognition results.
  static Future<List<String>> getRelatedKanjiCandidates(
    List<String> rawCharacters, {
    int limit = 20,
  }) async {
    if (limit <= 0) return const <String>[];

    final seedCharacters = <String>[];
    final seenSeeds = <String>{};

    for (final rawCharacter in rawCharacters) {
      final character = rawCharacter.trim();
      if (!_isSingleKanjiCharacter(character)) continue;
      if (!seenSeeds.add(character)) continue;

      seedCharacters.add(character);
      if (seedCharacters.length >= 6) break;
    }

    if (seedCharacters.isEmpty) return const <String>[];

    await loadDictionary();

    final database = _database;
    if (database == null) {
      return _fallbackRelatedKanjiCandidates(
        seedCharacters,
        limit: limit,
      );
    }

    final seedPlaceholders =
        List.filled(seedCharacters.length, '?').join(', ');
    final seedRows = await database.rawQuery(
      """
      SELECT character, radical, stroke_count
      FROM kanji_entries
      WHERE character IN ($seedPlaceholders)
      """,
      seedCharacters,
    );

    if (seedRows.isEmpty) return const <String>[];

    final seedByCharacter = <String, Map<String, Object?>>{
      for (final row in seedRows)
        if (row['character'] != null) row['character'].toString(): row,
    };

    final radicals = <String>[];
    final seenRadicals = <String>{};
    for (final character in seedCharacters) {
      final radical = _nullableText(seedByCharacter[character]?['radical']);
      if (radical != null && seenRadicals.add(radical)) {
        radicals.add(radical);
      }
    }

    if (radicals.isEmpty) return const <String>[];

    final radicalPlaceholders = List.filled(radicals.length, '?').join(', ');
    final rows = await database.rawQuery(
      """
      SELECT character, radical, stroke_count, frequency
      FROM kanji_entries
      WHERE radical IN ($radicalPlaceholders)
      LIMIT 400
      """,
      radicals,
    );

    final seedSet = seedCharacters.toSet();
    final candidates = rows.where((row) {
      final character = row['character']?.toString() ?? '';
      return _isSingleKanjiCharacter(character) && !seedSet.contains(character);
    }).toList();

    int candidateScore(Map<String, Object?> candidate) {
      final candidateRadical = _nullableText(candidate['radical']);
      final candidateStrokeCount = _nullableInt(candidate['stroke_count']);
      var bestScore = 1000000;

      for (var index = 0; index < seedCharacters.length; index++) {
        final seed = seedByCharacter[seedCharacters[index]];
        if (seed == null) continue;

        final seedRadical = _nullableText(seed['radical']);
        if (seedRadical == null || seedRadical != candidateRadical) continue;

        final seedStrokeCount = _nullableInt(seed['stroke_count']);
        final strokeDifference = seedStrokeCount == null ||
                candidateStrokeCount == null
            ? 8
            : (seedStrokeCount - candidateStrokeCount).abs();

        final score = (index * 120) + (strokeDifference * 35);
        if (score < bestScore) bestScore = score;
      }

      final frequency = _nullableInt(candidate['frequency']);
      final frequencyTieBreaker = frequency == null ? 250 : frequency ~/ 100;
      return bestScore + frequencyTieBreaker;
    }

    candidates.sort((left, right) {
      final scoreComparison =
          candidateScore(left).compareTo(candidateScore(right));
      if (scoreComparison != 0) return scoreComparison;

      final leftCharacter = left['character']?.toString() ?? '';
      final rightCharacter = right['character']?.toString() ?? '';
      return leftCharacter.compareTo(rightCharacter);
    });

    final results = <String>[];
    final seenResults = <String>{};

    for (final row in candidates) {
      final character = row['character']?.toString() ?? '';
      if (!seenResults.add(character)) continue;

      results.add(character);
      if (results.length >= limit) break;
    }

    return results;
  }

  static List<String> _fallbackRelatedKanjiCandidates(
    List<String> seedCharacters, {
    required int limit,
  }) {
    final results = <String>[];
    final seen = seedCharacters.toSet();
    final termsByCharacter = <String, Term>{};

    for (final term in fallback_dictionary.dictionaryWords) {
      if (_isSingleKanjiCharacter(term.kanji)) {
        termsByCharacter[term.kanji] = term;
      }
    }

    for (final seedCharacter in seedCharacters) {
      final seedTerm = termsByCharacter[seedCharacter];
      if (seedTerm == null) continue;

      for (final similarCharacter in seedTerm.similarKanji) {
        if (!_isSingleKanjiCharacter(similarCharacter)) continue;
        if (!seen.add(similarCharacter)) continue;

        results.add(similarCharacter);
        if (results.length >= limit) return results;
      }

      final radical = seedTerm.radical;
      if (radical == null || radical.isEmpty) continue;

      final sameRadicalTerms = termsByCharacter.values
          .where((term) => term.radical == radical && !seen.contains(term.kanji))
          .toList()
        ..sort((left, right) {
          final seedStrokeCount = seedTerm.strokeCount;
          final leftStrokeCount = left.strokeCount;
          final rightStrokeCount = right.strokeCount;

          final leftDifference = seedStrokeCount == null || leftStrokeCount == null
              ? 999
              : (seedStrokeCount - leftStrokeCount).abs();
          final rightDifference =
              seedStrokeCount == null || rightStrokeCount == null
                  ? 999
                  : (seedStrokeCount - rightStrokeCount).abs();

          return leftDifference.compareTo(rightDifference);
        });

      for (final term in sameRadicalTerms) {
        if (!seen.add(term.kanji)) continue;
        results.add(term.kanji);
        if (results.length >= limit) return results;
      }
    }

    return results;
  }

  static Future<KanjiStrokeData?> getKanjiStrokeData(
    String rawCharacter,
  ) async {
    final character = rawCharacter.trim();

    if (!_isSingleKanjiCharacter(character)) return null;

    return _getCharacterStrokeData(character);
  }

  static Future<KanjiStrokeData?> getCharacterStrokeData(
    String rawCharacter,
  ) async {
    final character = rawCharacter.trim();

    if (character.runes.length != 1) return null;

    return _getCharacterStrokeData(character);
  }

  static Future<KanjiStrokeData?> _getCharacterStrokeData(
    String character,
  ) async {
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
      debugPrint('Stroke data unavailable for $character: $error');
      return null;
    } on FormatException catch (error) {
      debugPrint('Stroke JSON is invalid for $character: $error');
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

  /// Loads only preferred/alternative spelling metadata for existing deck
  /// copies. This intentionally avoids materializing definitions, examples, or
  /// full dictionary terms during one-time payload migration.
  static Future<Map<String, DictionaryTermSpellingMetadata>>
      spellingMetadataForTermIds(Iterable<String> rawTermIds) async {
    final termIds = rawTermIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && !id.startsWith(_kanjiIdPrefix))
        .toSet()
        .toList(growable: false);

    if (termIds.isEmpty) return const {};

    await loadDictionary();
    final database = _database;
    if (database == null) return const {};

    return _spellingMetadataByTermId(
      database: database,
      termIds: termIds,
    );
  }

  /// Resolves preferred-writing metadata by the lexical kanji/reading pair.
  ///
  /// This is a compatibility fallback for older saved cards whose sourceId is
  /// missing or no longer points at the canonical JMdict id. It intentionally
  /// fetches only term ids plus spelling metadata; it does not materialize
  /// senses/examples for every saved card.
  static Future<Map<String, DictionaryTermSpellingMetadata>>
      spellingMetadataForTerms(Iterable<Term> rawTerms) async {
    final pairs = <String, ({String kanji, String reading})>{};

    for (final term in rawTerms) {
      final kanji = term.kanji.trim();
      final reading = term.reading.trim();
      if (kanji.isEmpty && reading.isEmpty) continue;

      pairs.putIfAbsent(
        _spellingMetadataLexicalKey(kanji, reading),
        () => (kanji: kanji, reading: reading),
      );
    }

    if (pairs.isEmpty) return const {};

    await loadDictionary();
    final database = _database;
    if (database == null || !await _hasTermSpellingMetadata(database)) {
      return const {};
    }

    final termIdByLexicalKey = <String, String>{};
    final values = pairs.values.toList(growable: false);
    const chunkSize = 120;

    try {
      for (var start = 0; start < values.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, values.length).toInt();
        final chunk = values.sublist(start, end);
        final conditions = List.filled(
          chunk.length,
          '(kanji = ? AND reading = ?)',
        ).join(' OR ');
        final arguments = <Object?>[];

        for (final pair in chunk) {
          arguments
            ..add(pair.kanji)
            ..add(pair.reading);
        }

        final rows = await database.rawQuery(
          '''
          SELECT id, kanji, reading
          FROM terms
          WHERE $conditions
          ORDER BY is_common DESC, common_score DESC
          ''',
          arguments,
        );

        for (final row in rows) {
          final id = row['id']?.toString().trim() ?? '';
          final kanji = row['kanji']?.toString().trim() ?? '';
          final reading = row['reading']?.toString().trim() ?? '';
          if (id.isEmpty) continue;

          termIdByLexicalKey.putIfAbsent(
            _spellingMetadataLexicalKey(kanji, reading),
            () => id,
          );
        }
      }
    } on DatabaseException catch (error) {
      debugPrint('Dictionary lexical spelling lookup failed: $error');
      return const {};
    }

    if (termIdByLexicalKey.isEmpty) return const {};

    final metadataById = await _spellingMetadataByTermId(
      database: database,
      termIds: termIdByLexicalKey.values.toSet().toList(growable: false),
    );
    final result = <String, DictionaryTermSpellingMetadata>{};

    for (final entry in termIdByLexicalKey.entries) {
      final metadata = metadataById[entry.value];
      if (metadata != null) result[entry.key] = metadata;
    }

    return result;
  }

  static String spellingMetadataLexicalKey(Term term) {
    return _spellingMetadataLexicalKey(
      term.kanji.trim(),
      term.reading.trim(),
    );
  }

  static String _spellingMetadataLexicalKey(String kanji, String reading) {
    return '$kanji\u0000$reading';
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
    final wordJlptLevelsByTermId = await _wordJlptLevelsByTermId(
      database: database,
      termIds: ids,
    );
    final spellingMetadataByTermId = await _spellingMetadataByTermId(
      database: database,
      termIds: ids,
    );

    return rows.map((row) {
      final id = row['id'].toString();
      final spellingMetadata = spellingMetadataByTermId[id];

      return Term(
        id: id,
        kanji: row['kanji']?.toString() ?? '',
        reading: row['reading']?.toString() ?? '',
        meaning: row['meaning']?.toString() ?? '',
        preferredSpelling: spellingMetadata?.preferredSpelling,
        spellings: spellingMetadata?.spellings,
        usuallyWrittenInKana:
            spellingMetadata?.usuallyWrittenInKana ?? false,
        partOfSpeech: row['part_of_speech']?.toString() ?? 'word',
        senses: sensesByTermId[id] ?? const [],
        isCommon: row['is_common'] == 1,
        kanjiMeaning: row['meaning']?.toString() ?? '',
        jlptLevel: wordJlptLevelsByTermId[id],
        frequency: _nullableInt(row['frequency']),
      );
    }).toList();
  }

  static Future<Map<String, DictionaryTermSpellingMetadata>> _spellingMetadataByTermId({
    required Database database,
    required List<String> termIds,
  }) async {
    if (termIds.isEmpty || !await _hasTermSpellingMetadata(database)) {
      return const {};
    }

    final metadataByTermId = <String, DictionaryTermSpellingMetadata>{};
    const chunkSize = 300;

    try {
      for (var start = 0; start < termIds.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, termIds.length).toInt();
        final chunk = termIds.sublist(start, end);
        final placeholders = List.filled(chunk.length, '?').join(', ');

        final rows = await database.rawQuery(
          '''
          SELECT
            term_id,
            spelling,
            kind,
            position,
            is_preferred,
            usually_written_kana,
            info_tags_json,
            priority_tags_json,
            restrictions_json
          FROM $_termSpellingsTable
          WHERE term_id IN ($placeholders)
          ORDER BY term_id, position
          ''',
          chunk,
        );

        final spellingsByTermId = <String, List<DictionarySpelling>>{};
        final preferredByTermId = <String, String>{};
        final usuallyKanaByTermId = <String, bool>{};

        for (final row in rows) {
          final termId = row['term_id']?.toString().trim() ?? '';
          final text = row['spelling']?.toString().trim() ?? '';
          if (termId.isEmpty || text.isEmpty) continue;

          final kind = row['kind']?.toString().trim().toLowerCase() == 'kana'
              ? DictionarySpellingKind.kana
              : DictionarySpellingKind.kanji;
          final isPreferred = _nullableInt(row['is_preferred']) == 1;

          spellingsByTermId.putIfAbsent(
            termId,
            () => <DictionarySpelling>[],
          ).add(
            DictionarySpelling(
              text: text,
              kind: kind,
              infoTags: _decodeStoredJsonStringList(row['info_tags_json']),
              priorityTags:
                  _decodeStoredJsonStringList(row['priority_tags_json']),
              restrictions:
                  _decodeStoredJsonStringList(row['restrictions_json']),
              isPreferred: isPreferred,
            ),
          );

          if (isPreferred) {
            preferredByTermId[termId] = text;
          }

          if (_nullableInt(row['usually_written_kana']) == 1) {
            usuallyKanaByTermId[termId] = true;
          }
        }

        for (final entry in spellingsByTermId.entries) {
          final spellings = entry.value;
          final preferred = preferredByTermId[entry.key] ??
              spellings.firstWhere(
                (spelling) => spelling.isPreferred,
                orElse: () => spellings.first,
              ).text;

          metadataByTermId[entry.key] = DictionaryTermSpellingMetadata(
            preferredSpelling: preferred,
            usuallyWrittenInKana: usuallyKanaByTermId[entry.key] ?? false,
            spellings: List.unmodifiable(spellings),
          );
        }
      }
    } on DatabaseException catch (error) {
      debugPrint('Dictionary spelling metadata lookup failed: $error');
      return const {};
    }

    return metadataByTermId;
  }

  static Future<bool> _hasKanjiComponentMetadata(Database database) async {
    final cached = _hasKanjiComponentTreesTable;
    if (cached != null) return cached;

    try {
      final exists = await _databaseContainsTable(
        database,
        _kanjiComponentTreesTable,
      );
      _hasKanjiComponentTreesTable = exists;
      return exists;
    } on DatabaseException catch (error) {
      debugPrint('Kanji component metadata unavailable: $error');
      _hasKanjiComponentTreesTable = false;
      return false;
    }
  }

  static Future<bool> _hasTermSpellingMetadata(Database database) async {
    final cached = _hasTermSpellingsTable;
    if (cached != null) return cached;

    try {
      final rows = await database.rawQuery(
        '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table' AND name = ?
        LIMIT 1
        ''',
        [_termSpellingsTable],
      );
      final exists = rows.isNotEmpty;
      _hasTermSpellingsTable = exists;
      return exists;
    } on DatabaseException catch (error) {
      debugPrint('Dictionary spelling metadata unavailable: $error');
      _hasTermSpellingsTable = false;
      return false;
    }
  }

  static List<String> _decodeStoredJsonStringList(Object? rawValue) {
    final text = rawValue?.toString().trim() ?? '';
    if (text.isEmpty) return const [];

    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];

      return decoded
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<Map<String, String>> _wordJlptLevelsByTermId({
    required Database database,
    required List<String> termIds,
  }) async {
    if (termIds.isEmpty || !await _hasWordJlptMetadata(database)) {
      return const {};
    }

    final levelsByTermId = <String, String>{};
    const chunkSize = 400;

    try {
      for (var start = 0; start < termIds.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, termIds.length).toInt();
        final chunk = termIds.sublist(start, end);
        final placeholders = List.filled(chunk.length, '?').join(', ');

        final rows = await database.rawQuery(
          '''
          SELECT term_id, jlpt_level
          FROM $_wordJlptLevelsTable
          WHERE term_id IN ($placeholders)
          ''',
          chunk,
        );

        for (final row in rows) {
          final termId = row['term_id']?.toString().trim() ?? '';
          final level = _normalizeJlptLevel(row['jlpt_level']);

          if (termId.isEmpty || level == null) continue;
          levelsByTermId[termId] = level;
        }
      }
    } on DatabaseException catch (error) {
      debugPrint('Word JLPT metadata lookup failed: $error');
      return const {};
    }

    return levelsByTermId;
  }

  static Future<bool> _hasWordJlptMetadata(Database database) async {
    final cached = _hasWordJlptLevelsTable;
    if (cached != null) return cached;

    try {
      final rows = await database.rawQuery(
        '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table' AND name = ?
        LIMIT 1
        ''',
        [_wordJlptLevelsTable],
      );
      final exists = rows.isNotEmpty;
      _hasWordJlptLevelsTable = exists;
      return exists;
    } on DatabaseException catch (error) {
      debugPrint('Word JLPT metadata unavailable: $error');
      _hasWordJlptLevelsTable = false;
      return false;
    }
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

  static const List<String> _kangxiRadicals = <String>[
    '',
    '一', '丨', '丶', '丿', '乙', '亅', '二', '亠', '人', '儿',
    '入', '八', '冂', '冖', '冫', '几', '凵', '刀', '力', '勹',
    '匕', '匚', '匸', '十', '卜', '卩', '厂', '厶', '又', '口',
    '囗', '土', '士', '夂', '夊', '夕', '大', '女', '子', '宀',
    '寸', '小', '尢', '尸', '屮', '山', '巛', '工', '己', '巾',
    '干', '幺', '广', '廴', '廾', '弋', '弓', '彐', '彡', '彳',
    '心', '戈', '戶', '手', '支', '攴', '文', '斗', '斤', '方',
    '无', '日', '曰', '月', '木', '欠', '止', '歹', '殳', '毋',
    '比', '毛', '氏', '气', '水', '火', '爪', '父', '爻', '爿',
    '片', '牙', '牛', '犬', '玄', '玉', '瓜', '瓦', '甘', '生',
    '用', '田', '疋', '疒', '癶', '白', '皮', '皿', '目', '矛',
    '矢', '石', '示', '禸', '禾', '穴', '立', '竹', '米', '糸',
    '缶', '网', '羊', '羽', '老', '而', '耒', '耳', '聿', '肉',
    '臣', '自', '至', '臼', '舌', '舛', '舟', '艮', '色', '艸',
    '虍', '虫', '血', '行', '衣', '襾', '見', '角', '言', '谷',
    '豆', '豕', '豸', '貝', '赤', '走', '足', '身', '車', '辛',
    '辰', '辵', '邑', '酉', '釆', '里', '金', '長', '門', '阜',
    '隶', '隹', '雨', '靑', '非', '面', '革', '韋', '韭', '音',
    '頁', '風', '飛', '食', '首', '香', '馬', '骨', '高', '髟',
    '鬥', '鬯', '鬲', '鬼', '魚', '鳥', '鹵', '鹿', '麥', '麻',
    '黃', '黍', '黑', '黹', '黽', '鼎', '鼓', '鼠', '鼻', '齊',
    '齒', '龍', '龜', '龠',
  ];

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

  static String? _normalizeJlptLevel(Object? value) {
    final text = _nullableText(value)?.toUpperCase();
    if (text == null) return null;

    if (RegExp(r'^N[1-5]$').hasMatch(text)) return text;
    if (RegExp(r'^[1-5]$').hasMatch(text)) return 'N$text';

    return text;
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

