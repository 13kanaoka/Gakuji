import 'package:gakuji/models/deck_import_row.dart';

class DeckImportResult {
  final String deckName;
  final int importedCount;
  final int duplicateCount;
  final int unmatchedCount;
  final int ambiguousCount;
  final int skippedCount;
  final List<DeckImportRow> unresolvedRows;

  const DeckImportResult({
    required this.deckName,
    required this.importedCount,
    required this.duplicateCount,
    required this.unmatchedCount,
    required this.ambiguousCount,
    required this.skippedCount,
    required this.unresolvedRows,
  });
}
