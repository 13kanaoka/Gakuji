import 'term.dart';

enum TermImportFileType {
  csv,
  tsv,
  text,
  xlsx,
}

extension TermImportFileTypeLabel on TermImportFileType {
  String get label {
    switch (this) {
      case TermImportFileType.csv:
        return 'CSV';
      case TermImportFileType.tsv:
        return 'TSV';
      case TermImportFileType.text:
        return 'Text';
      case TermImportFileType.xlsx:
        return 'Excel';
    }
  }
}

enum TermImportColumnRole {
  ignore,
  term,
  reading,
  definition,
}

extension TermImportColumnRoleLabel on TermImportColumnRole {
  String get label {
    switch (this) {
      case TermImportColumnRole.ignore:
        return 'Ignore';
      case TermImportColumnRole.term:
        return 'Term';
      case TermImportColumnRole.reading:
        return 'Reading';
      case TermImportColumnRole.definition:
        return 'Definition';
    }
  }
}

class TermImportSourceRow {
  final int rowNumber;
  final List<String> values;

  const TermImportSourceRow({
    required this.rowNumber,
    required this.values,
  });

  String valueAt(int? columnIndex) {
    if (columnIndex == null ||
        columnIndex < 0 ||
        columnIndex >= values.length) {
      return '';
    }

    return values[columnIndex].trim();
  }
}

class TermImportDocument {
  final String fileName;
  final TermImportFileType fileType;
  final String? sheetName;
  final List<TermImportSourceRow> rows;
  final int columnCount;
  final bool detectedHeader;
  final List<TermImportColumnRole> suggestedRoles;

  const TermImportDocument({
    required this.fileName,
    required this.fileType,
    required this.rows,
    required this.columnCount,
    required this.detectedHeader,
    required this.suggestedRoles,
    this.sheetName,
  });

  int dataRowCount({required bool firstRowIsHeader}) {
    if (rows.isEmpty) return 0;

    return firstRowIsHeader ? rows.length - 1 : rows.length;
  }

  List<TermImportSourceRow> dataRows({required bool firstRowIsHeader}) {
    if (!firstRowIsHeader || rows.isEmpty) {
      return List<TermImportSourceRow>.unmodifiable(rows);
    }

    return List<TermImportSourceRow>.unmodifiable(rows.skip(1));
  }

  String columnLabel(
    int columnIndex, {
    required bool firstRowIsHeader,
  }) {
    if (firstRowIsHeader && rows.isNotEmpty) {
      final header = rows.first.valueAt(columnIndex);

      if (header.isNotEmpty) return header;
    }

    return 'Column ${columnIndex + 1}';
  }
}

class TermImportFile {
  final String fileName;
  final TermImportFileType fileType;
  final List<TermImportDocument> documents;

  const TermImportFile({
    required this.fileName,
    required this.fileType,
    required this.documents,
  });

  bool get hasMultipleDocuments => documents.length > 1;
}

class DeckImportMapping {
  final int? termColumn;
  final int? readingColumn;
  final int? definitionColumn;

  const DeckImportMapping({
    this.termColumn,
    this.readingColumn,
    this.definitionColumn,
  });

  factory DeckImportMapping.fromRoles(
    List<TermImportColumnRole> roles,
  ) {
    int? columnFor(TermImportColumnRole role) {
      final index = roles.indexOf(role);
      return index < 0 ? null : index;
    }

    return DeckImportMapping(
      termColumn: columnFor(TermImportColumnRole.term),
      readingColumn: columnFor(TermImportColumnRole.reading),
      definitionColumn: columnFor(TermImportColumnRole.definition),
    );
  }

  bool get hasLookupColumn {
    return termColumn != null || readingColumn != null;
  }
}

enum DeckImportMatchStatus {
  pending,
  matched,
  ambiguous,
  unmatched,
  duplicate,
  skipped,
}

class DeckImportCandidate {
  final Term term;
  final int score;

  const DeckImportCandidate({
    required this.term,
    required this.score,
  });
}

class DeckImportRow {
  final int rowNumber;
  final List<String> rawValues;
  final String importedTerm;
  final String importedReading;
  final String importedDefinition;

  List<DeckImportCandidate> candidates;
  Term? selectedTerm;
  DeckImportMatchStatus status;
  bool included;
  String? message;

  DeckImportRow({
    required this.rowNumber,
    required this.rawValues,
    required this.importedTerm,
    required this.importedReading,
    required this.importedDefinition,
    this.candidates = const [],
    this.selectedTerm,
    this.status = DeckImportMatchStatus.pending,
    this.included = true,
    this.message,
  });

  String get importedLabel {
    if (importedTerm.isNotEmpty) return importedTerm;
    if (importedReading.isNotEmpty) return importedReading;
    return 'Row $rowNumber';
  }

  String? get selectedSourceId {
    final term = selectedTerm;

    if (term == null) return null;

    return term.sourceId ?? term.id;
  }

  bool get canImport {
    return included &&
        selectedTerm != null &&
        status != DeckImportMatchStatus.duplicate &&
        status != DeckImportMatchStatus.skipped;
  }
}
