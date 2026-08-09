import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';

import '../models/deck_import_row.dart';

class CsvImportException implements Exception {
  final String message;

  const CsvImportException(this.message);

  @override
  String toString() => message;
}

class CsvImportService {
  static final RegExp _kanjiPattern = RegExp(r'[一-龯々〆ヵヶ]');
  static final RegExp _hiraganaPattern = RegExp(r'[ぁ-ゖ]');
  static final RegExp _katakanaPattern = RegExp(r'[ァ-ヺー]');
  static final RegExp _latinPattern = RegExp(r'[A-Za-z]');

  static const Set<String> _termHeaders = {
    'term',
    'word',
    'expression',
    'front',
    'japanese',
    'kanji',
    'vocabulary',
    'vocab',
  };

  static const Set<String> _readingHeaders = {
    'reading',
    'pronunciation',
    'kana',
    'hiragana',
    'furigana',
    'yomikata',
  };

  static const Set<String> _definitionHeaders = {
    'definition',
    'definitions',
    'meaning',
    'meanings',
    'gloss',
    'english',
    'back',
    'translation',
  };

  static Future<CsvImportDocument?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes = await _readBytes(file);

    return parseBytes(
      fileName: file.name,
      bytes: bytes,
    );
  }

  static Future<Uint8List> _readBytes(PlatformFile file) async {
    final inMemoryBytes = file.bytes;

    if (inMemoryBytes != null) return inMemoryBytes;

    try {
      return await file.xFile.readAsBytes();
    } catch (_) {
      throw const CsvImportException(
        'Gakuji could not read the selected file.',
      );
    }
  }

  static CsvImportDocument parseBytes({
    required String fileName,
    required List<int> bytes,
  }) {
    late String contents;

    try {
      contents = utf8.decode(bytes);
    } on FormatException {
      throw const CsvImportException(
        'This CSV must be saved with UTF-8 encoding.',
      );
    }

    return parseText(
      fileName: fileName,
      contents: contents,
    );
  }

  static CsvImportDocument parseText({
    required String fileName,
    required String contents,
  }) {
    if (contents.trim().isEmpty) {
      throw const CsvImportException('The selected CSV is empty.');
    }

    late List<List<dynamic>> decodedRows;

    try {
      decodedRows = csv.decode(contents);
    } catch (_) {
      throw const CsvImportException(
        'Gakuji could not understand the CSV formatting.',
      );
    }

    final normalizedRows = <CsvImportSourceRow>[];
    var columnCount = 0;

    for (var index = 0; index < decodedRows.length; index++) {
      final decodedRow = decodedRows[index];
      final values = decodedRow.map((value) {
        return value?.toString().replaceAll('\uFEFF', '').trim() ?? '';
      }).toList(growable: false);

      if (values.every((value) => value.isEmpty)) continue;

      if (values.length > columnCount) {
        columnCount = values.length;
      }

      normalizedRows.add(
        CsvImportSourceRow(
          rowNumber: index + 1,
          values: values,
        ),
      );
    }

    if (normalizedRows.isEmpty || columnCount == 0) {
      throw const CsvImportException(
        'The selected CSV does not contain any usable rows.',
      );
    }

    if (columnCount > 20) {
      throw const CsvImportException(
        'This CSV has too many columns. Gakuji supports up to 20 columns.',
      );
    }

    final detectedHeader = _detectHeader(normalizedRows.first, columnCount);
    final suggestedRoles = _suggestRoles(
      rows: normalizedRows,
      columnCount: columnCount,
      firstRowIsHeader: detectedHeader,
    );

    return CsvImportDocument(
      fileName: fileName,
      rows: List<CsvImportSourceRow>.unmodifiable(normalizedRows),
      columnCount: columnCount,
      detectedHeader: detectedHeader,
      suggestedRoles: List<CsvImportColumnRole>.unmodifiable(suggestedRoles),
    );
  }

  static List<DeckImportRow> buildImportRows({
    required CsvImportDocument document,
    required DeckImportMapping mapping,
    required bool firstRowIsHeader,
  }) {
    final importRows = <DeckImportRow>[];

    for (final sourceRow in document.dataRows(
      firstRowIsHeader: firstRowIsHeader,
    )) {
      final term = sourceRow.valueAt(mapping.termColumn);
      final reading = sourceRow.valueAt(mapping.readingColumn);
      final definition = sourceRow.valueAt(mapping.definitionColumn);
      final hasLookupText = term.isNotEmpty || reading.isNotEmpty;

      importRows.add(
        DeckImportRow(
          rowNumber: sourceRow.rowNumber,
          rawValues: sourceRow.values,
          importedTerm: term,
          importedReading: reading,
          importedDefinition: definition,
          status: hasLookupText
              ? DeckImportMatchStatus.pending
              : DeckImportMatchStatus.skipped,
          included: hasLookupText,
          message: hasLookupText ? null : 'No term or reading was found.',
        ),
      );
    }

    return importRows;
  }

  static bool _detectHeader(
    CsvImportSourceRow firstRow,
    int columnCount,
  ) {
    var recognizedHeaders = 0;

    for (var columnIndex = 0;
        columnIndex < columnCount;
        columnIndex++) {
      final value = _normalizeHeader(firstRow.valueAt(columnIndex));

      if (_roleForHeader(value) != CsvImportColumnRole.ignore) {
        recognizedHeaders++;
      }
    }

    return recognizedHeaders > 0;
  }

  static List<CsvImportColumnRole> _suggestRoles({
    required List<CsvImportSourceRow> rows,
    required int columnCount,
    required bool firstRowIsHeader,
  }) {
    final roles = List<CsvImportColumnRole>.filled(
      columnCount,
      CsvImportColumnRole.ignore,
    );

    if (firstRowIsHeader && rows.isNotEmpty) {
      for (var columnIndex = 0;
          columnIndex < columnCount;
          columnIndex++) {
        roles[columnIndex] = _roleForHeader(
          _normalizeHeader(rows.first.valueAt(columnIndex)),
        );
      }
    }

    final usedRoles = roles.where((role) {
      return role != CsvImportColumnRole.ignore;
    }).toSet();

    final dataRows = firstRowIsHeader ? rows.skip(1) : rows;
    final sampledRows = dataRows.take(80).toList(growable: false);
    final stats = List.generate(
      columnCount,
      (columnIndex) => _columnStats(sampledRows, columnIndex),
    );

    if (!usedRoles.contains(CsvImportColumnRole.definition)) {
      final definitionColumn = _bestColumn(
        stats,
        roles,
        (value) => value.definitionScore,
      );

      if (definitionColumn != null &&
          stats[definitionColumn].latinCells > 0) {
        roles[definitionColumn] = CsvImportColumnRole.definition;
      }
    }

    if (!usedRoles.contains(CsvImportColumnRole.term)) {
      final termColumn = _bestColumn(
        stats,
        roles,
        (value) => value.termScore,
      );

      if (termColumn != null && stats[termColumn].japaneseCells > 0) {
        roles[termColumn] = CsvImportColumnRole.term;
      }
    }

    if (!usedRoles.contains(CsvImportColumnRole.reading)) {
      final readingColumn = _bestColumn(
        stats,
        roles,
        (value) => value.readingScore,
      );

      if (readingColumn != null &&
          stats[readingColumn].japaneseCells > 0) {
        roles[readingColumn] = CsvImportColumnRole.reading;
      }
    }

    return roles;
  }

  static int? _bestColumn(
    List<_CsvColumnStats> stats,
    List<CsvImportColumnRole> roles,
    int Function(_CsvColumnStats value) scoreFor,
  ) {
    int? bestColumn;
    var bestScore = -1;

    for (var columnIndex = 0;
        columnIndex < stats.length;
        columnIndex++) {
      if (roles[columnIndex] != CsvImportColumnRole.ignore) continue;

      final score = scoreFor(stats[columnIndex]);

      if (score > bestScore) {
        bestScore = score;
        bestColumn = columnIndex;
      }
    }

    return bestScore <= 0 ? null : bestColumn;
  }

  static _CsvColumnStats _columnStats(
    List<CsvImportSourceRow> rows,
    int columnIndex,
  ) {
    var nonEmptyCells = 0;
    var japaneseCells = 0;
    var kanjiCells = 0;
    var kanaOnlyCells = 0;
    var latinCells = 0;
    var totalLength = 0;

    for (final row in rows) {
      final value = row.valueAt(columnIndex);

      if (value.isEmpty) continue;

      nonEmptyCells++;
      totalLength += value.length;

      final hasKanji = _kanjiPattern.hasMatch(value);
      final hasHiragana = _hiraganaPattern.hasMatch(value);
      final hasKatakana = _katakanaPattern.hasMatch(value);
      final hasJapanese = hasKanji || hasHiragana || hasKatakana;
      final hasLatin = _latinPattern.hasMatch(value);

      if (hasJapanese) japaneseCells++;
      if (hasKanji) kanjiCells++;
      if (hasLatin) latinCells++;

      if (!hasKanji && (hasHiragana || hasKatakana)) {
        kanaOnlyCells++;
      }
    }

    final averageLength = nonEmptyCells == 0
        ? 0
        : (totalLength / nonEmptyCells).round();

    return _CsvColumnStats(
      nonEmptyCells: nonEmptyCells,
      japaneseCells: japaneseCells,
      kanjiCells: kanjiCells,
      kanaOnlyCells: kanaOnlyCells,
      latinCells: latinCells,
      averageLength: averageLength,
    );
  }

  static CsvImportColumnRole _roleForHeader(String normalizedHeader) {
    if (_termHeaders.contains(normalizedHeader)) {
      return CsvImportColumnRole.term;
    }

    if (_readingHeaders.contains(normalizedHeader)) {
      return CsvImportColumnRole.reading;
    }

    if (_definitionHeaders.contains(normalizedHeader)) {
      return CsvImportColumnRole.definition;
    }

    return CsvImportColumnRole.ignore;
  }

  static String _normalizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }
}

class _CsvColumnStats {
  final int nonEmptyCells;
  final int japaneseCells;
  final int kanjiCells;
  final int kanaOnlyCells;
  final int latinCells;
  final int averageLength;

  const _CsvColumnStats({
    required this.nonEmptyCells,
    required this.japaneseCells,
    required this.kanjiCells,
    required this.kanaOnlyCells,
    required this.latinCells,
    required this.averageLength,
  });

  int get definitionScore {
    return (latinCells * 6) + averageLength - (japaneseCells * 2);
  }

  int get termScore {
    return (kanjiCells * 8) +
        (japaneseCells * 2) -
        (kanaOnlyCells * 2) -
        latinCells;
  }

  int get readingScore {
    return (kanaOnlyCells * 7) +
        (japaneseCells * 2) -
        (kanjiCells * 5) -
        latinCells;
  }
}
