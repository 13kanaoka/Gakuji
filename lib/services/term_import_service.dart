import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as spreadsheet;
import 'package:file_picker/file_picker.dart';

import 'package:gakuji/models/deck_import_row.dart';

class TermImportException implements Exception {
  final String message;

  const TermImportException(this.message);

  @override
  String toString() => message;
}

class TermImportService {
  static const int _maximumColumnCount = 100;

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

  static Future<TermImportFile?> pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'tsv', 'txt', 'xlsx'],
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
      throw const TermImportException(
        'Gakuji could not read the selected file.',
      );
    }
  }

  static TermImportFile parseBytes({
    required String fileName,
    required List<int> bytes,
  }) {
    final fileType = _fileTypeForName(fileName);

    if (fileType == TermImportFileType.xlsx) {
      return _parseWorkbook(
        fileName: fileName,
        bytes: bytes,
      );
    }

    late String contents;

    try {
      contents = utf8.decode(bytes);
    } on FormatException {
      throw const TermImportException(
        'Text files must be saved with UTF-8 encoding.',
      );
    }

    return parseText(
      fileName: fileName,
      fileType: fileType,
      contents: contents,
    );
  }

  static TermImportFile parseText({
    required String fileName,
    required TermImportFileType fileType,
    required String contents,
  }) {
    if (fileType == TermImportFileType.xlsx) {
      throw const TermImportException(
        'Excel workbooks must be read from their original file data.',
      );
    }

    if (contents.trim().isEmpty) {
      throw const TermImportException('The selected file is empty.');
    }

    late List<List<dynamic>> decodedRows;

    try {
      switch (fileType) {
        case TermImportFileType.tsv:
          decodedRows = Csv(
            fieldDelimiter: '\t',
          ).decode(contents);
          break;
        case TermImportFileType.csv:
        case TermImportFileType.text:
          decodedRows = csv.decode(contents);
          break;
        case TermImportFileType.xlsx:
          throw const TermImportException(
            'Excel workbooks must be read from their original file data.',
          );
      }
    } catch (error) {
      if (error is TermImportException) rethrow;

      throw const TermImportException(
        'Gakuji could not understand the file formatting.',
      );
    }

    final document = _buildDocument(
      fileName: fileName,
      fileType: fileType,
      decodedRows: decodedRows,
    );

    return TermImportFile(
      fileName: fileName,
      fileType: fileType,
      documents: [document],
    );
  }

  static TermImportFile _parseWorkbook({
    required String fileName,
    required List<int> bytes,
  }) {
    late spreadsheet.Excel workbook;

    try {
      workbook = spreadsheet.Excel.decodeBytes(bytes);
    } catch (_) {
      throw const TermImportException(
        'Gakuji could not open this Excel workbook.',
      );
    }

    final documents = <TermImportDocument>[];

    for (final sheetName in workbook.tables.keys) {
      final sheet = workbook.tables[sheetName];

      if (sheet == null) continue;

      final decodedRows = sheet.rows.map((row) {
        return row.map((cell) {
          return (cell?.value)?.toString() ?? '';
        }).toList(growable: false);
      }).toList(growable: false);

      try {
        documents.add(
          _buildDocument(
            fileName: fileName,
            fileType: TermImportFileType.xlsx,
            sheetName: sheetName,
            decodedRows: decodedRows,
          ),
        );
      } on TermImportException {
        // Empty worksheets are omitted from the worksheet selector.
      }
    }

    if (documents.isEmpty) {
      throw const TermImportException(
        'This Excel workbook does not contain any usable worksheets.',
      );
    }

    return TermImportFile(
      fileName: fileName,
      fileType: TermImportFileType.xlsx,
      documents: List<TermImportDocument>.unmodifiable(documents),
    );
  }

  static TermImportDocument _buildDocument({
    required String fileName,
    required TermImportFileType fileType,
    required List<List<dynamic>> decodedRows,
    String? sheetName,
  }) {
    final normalizedRows = <TermImportSourceRow>[];
    var columnCount = 0;

    for (var index = 0; index < decodedRows.length; index++) {
      final decodedRow = decodedRows[index];
      final values = decodedRow.map((value) {
        return value
            ?.toString()
            .replaceAll('\uFEFF', '')
            .replaceAll('\r\n', '\n')
            .trim() ??
            '';
      }).toList(growable: false);

      if (values.every((value) => value.isEmpty)) continue;

      if (values.length > columnCount) {
        columnCount = values.length;
      }

      normalizedRows.add(
        TermImportSourceRow(
          rowNumber: index + 1,
          values: values,
        ),
      );
    }

    if (normalizedRows.isEmpty || columnCount == 0) {
      throw const TermImportException(
        'The selected file does not contain any usable rows.',
      );
    }

    if (columnCount > _maximumColumnCount) {
      throw const TermImportException(
        'This file has too many columns. Gakuji supports up to 100 columns.',
      );
    }

    final detectedHeader = _detectHeader(normalizedRows.first, columnCount);
    final suggestedRoles = _suggestRoles(
      rows: normalizedRows,
      columnCount: columnCount,
      firstRowIsHeader: detectedHeader,
    );

    return TermImportDocument(
      fileName: fileName,
      fileType: fileType,
      sheetName: sheetName,
      rows: List<TermImportSourceRow>.unmodifiable(normalizedRows),
      columnCount: columnCount,
      detectedHeader: detectedHeader,
      suggestedRoles: List<TermImportColumnRole>.unmodifiable(suggestedRoles),
    );
  }

  static bool isSuggestedMappingConfident(
    TermImportDocument document,
  ) {
    final roles = document.suggestedRoles;
    final mapping = DeckImportMapping.fromRoles(roles);

    if (!mapping.hasLookupColumn) return false;

    for (final role in const [
      TermImportColumnRole.term,
      TermImportColumnRole.reading,
      TermImportColumnRole.definition,
    ]) {
      if (roles.where((value) => value == role).length > 1) {
        return false;
      }
    }

    final sampledRows = document
        .dataRows(firstRowIsHeader: document.detectedHeader)
        .take(80)
        .toList(growable: false);

    if (sampledRows.isEmpty) return false;

    if (document.detectedHeader) {
      return true;
    }

    final stats = List.generate(
      document.columnCount,
      (columnIndex) => _columnStats(sampledRows, columnIndex),
    );

    bool strongTermColumn(int columnIndex) {
      final value = stats[columnIndex];

      if (value.nonEmptyCells == 0 || value.averageLength > 24) {
        return false;
      }

      return value.japaneseCells / value.nonEmptyCells >= 0.65;
    }

    bool strongReadingColumn(int columnIndex) {
      final value = stats[columnIndex];

      if (value.nonEmptyCells == 0 || value.averageLength > 30) {
        return false;
      }

      return value.kanaOnlyCells / value.nonEmptyCells >= 0.65;
    }

    final termColumn = mapping.termColumn;
    final readingColumn = mapping.readingColumn;

    if (termColumn != null && !strongTermColumn(termColumn)) {
      return false;
    }

    if (readingColumn != null && !strongReadingColumn(readingColumn)) {
      return false;
    }

    return termColumn != null || readingColumn != null;
  }

  static List<DeckImportRow> buildImportRows({
    required TermImportDocument document,
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

  static TermImportFileType _fileTypeForName(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    final extension = dotIndex < 0
        ? ''
        : fileName.substring(dotIndex + 1).toLowerCase();

    switch (extension) {
      case 'csv':
        return TermImportFileType.csv;
      case 'tsv':
        return TermImportFileType.tsv;
      case 'txt':
        return TermImportFileType.text;
      case 'xlsx':
        return TermImportFileType.xlsx;
      default:
        throw const TermImportException(
          'Choose a CSV, TSV, TXT, or XLSX file.',
        );
    }
  }

  static bool _detectHeader(
    TermImportSourceRow firstRow,
    int columnCount,
  ) {
    var recognizedHeaders = 0;

    for (var columnIndex = 0;
        columnIndex < columnCount;
        columnIndex++) {
      final value = _normalizeHeader(firstRow.valueAt(columnIndex));

      if (_roleForHeader(value) != TermImportColumnRole.ignore) {
        recognizedHeaders++;
      }
    }

    return recognizedHeaders > 0;
  }

  static List<TermImportColumnRole> _suggestRoles({
    required List<TermImportSourceRow> rows,
    required int columnCount,
    required bool firstRowIsHeader,
  }) {
    final roles = List<TermImportColumnRole>.filled(
      columnCount,
      TermImportColumnRole.ignore,
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
      return role != TermImportColumnRole.ignore;
    }).toSet();

    final dataRows = firstRowIsHeader ? rows.skip(1) : rows;
    final sampledRows = dataRows.take(80).toList(growable: false);
    final stats = List.generate(
      columnCount,
      (columnIndex) => _columnStats(sampledRows, columnIndex),
    );

    if (!usedRoles.contains(TermImportColumnRole.definition)) {
      final definitionColumn = _bestColumn(
        stats,
        roles,
        (value) => value.definitionScore,
      );

      if (definitionColumn != null &&
          stats[definitionColumn].latinCells > 0) {
        roles[definitionColumn] = TermImportColumnRole.definition;
      }
    }

    if (!usedRoles.contains(TermImportColumnRole.term)) {
      final termColumn = _bestColumn(
        stats,
        roles,
        (value) => value.termScore,
      );

      if (termColumn != null && stats[termColumn].japaneseCells > 0) {
        roles[termColumn] = TermImportColumnRole.term;
      }
    }

    if (!usedRoles.contains(TermImportColumnRole.reading)) {
      final readingColumn = _bestColumn(
        stats,
        roles,
        (value) => value.readingScore,
      );

      if (readingColumn != null &&
          stats[readingColumn].japaneseCells > 0) {
        roles[readingColumn] = TermImportColumnRole.reading;
      }
    }

    return roles;
  }

  static int? _bestColumn(
    List<_TermImportColumnStats> stats,
    List<TermImportColumnRole> roles,
    int Function(_TermImportColumnStats value) scoreFor,
  ) {
    int? bestColumn;
    var bestScore = -1;

    for (var columnIndex = 0;
        columnIndex < stats.length;
        columnIndex++) {
      if (roles[columnIndex] != TermImportColumnRole.ignore) continue;

      final score = scoreFor(stats[columnIndex]);

      if (score > bestScore) {
        bestScore = score;
        bestColumn = columnIndex;
      }
    }

    return bestScore <= 0 ? null : bestColumn;
  }

  static _TermImportColumnStats _columnStats(
    List<TermImportSourceRow> rows,
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

    return _TermImportColumnStats(
      nonEmptyCells: nonEmptyCells,
      japaneseCells: japaneseCells,
      kanjiCells: kanjiCells,
      kanaOnlyCells: kanaOnlyCells,
      latinCells: latinCells,
      averageLength: averageLength,
    );
  }

  static TermImportColumnRole _roleForHeader(String normalizedHeader) {
    if (_termHeaders.contains(normalizedHeader)) {
      return TermImportColumnRole.term;
    }

    if (_readingHeaders.contains(normalizedHeader)) {
      return TermImportColumnRole.reading;
    }

    if (_definitionHeaders.contains(normalizedHeader)) {
      return TermImportColumnRole.definition;
    }

    return TermImportColumnRole.ignore;
  }

  static String _normalizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }
}

class _TermImportColumnStats {
  final int nonEmptyCells;
  final int japaneseCells;
  final int kanjiCells;
  final int kanaOnlyCells;
  final int latinCells;
  final int averageLength;

  const _TermImportColumnStats({
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
