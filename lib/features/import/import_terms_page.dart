import 'package:flutter/material.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';

import 'package:gakuji/features/import/models/deck_import_row.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/features/import/services/term_import_service.dart';
import 'package:gakuji/core/widgets/gakuji_faded_scroll.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_term_row.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/features/import/import_terms_preview_page.dart';

class ImportTermsPage extends StatefulWidget {
  const ImportTermsPage({super.key});

  @override
  State<ImportTermsPage> createState() => _ImportTermsPageState();
}

class _ImportTermsPageState extends State<ImportTermsPage> {
  TermImportFile? importFile;
  int selectedDocumentIndex = 0;
  List<TermImportColumnRole> columnRoles = [];
  bool firstRowIsHeader = false;
  bool isPickingFile = false;
  String? errorMessage;

  TermImportDocument? get document {
    final selectedFile = importFile;

    if (selectedFile == null || selectedFile.documents.isEmpty) return null;

    return selectedFile.documents[selectedDocumentIndex];
  }

  DeckImportMapping get mapping {
    return DeckImportMapping.fromRoles(columnRoles);
  }

  Future<void> _pickFile() async {
    if (isPickingFile) return;

    setState(() {
      isPickingFile = true;
      errorMessage = null;
    });

    try {
      final selectedFile = await TermImportService.pickFile();

      if (!mounted || selectedFile == null) return;

      final selectedDocument = selectedFile.documents.first;

      setState(() {
        importFile = selectedFile;
        selectedDocumentIndex = 0;
        firstRowIsHeader = selectedDocument.detectedHeader;
        columnRoles = List<TermImportColumnRole>.from(
          selectedDocument.suggestedRoles,
        );
      });

      if (!selectedFile.hasMultipleDocuments &&
          TermImportService.isSuggestedMappingConfident(selectedDocument)) {
        await _continueToPreview();
      }
    } on TermImportException catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Gakuji could not open that file.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isPickingFile = false;
        });
      }
    }
  }

  void _selectDocument(int documentIndex) {
    final selectedFile = importFile;

    if (selectedFile == null ||
        documentIndex < 0 ||
        documentIndex >= selectedFile.documents.length) {
      return;
    }

    final selectedDocument = selectedFile.documents[documentIndex];

    setState(() {
      selectedDocumentIndex = documentIndex;
      firstRowIsHeader = selectedDocument.detectedHeader;
      columnRoles = List<TermImportColumnRole>.from(
        selectedDocument.suggestedRoles,
      );
      errorMessage = null;
    });
  }

  void _setColumnRole(
    int columnIndex,
    TermImportColumnRole role,
  ) {
    setState(() {
      if (role != TermImportColumnRole.ignore) {
        for (var index = 0; index < columnRoles.length; index++) {
          if (index != columnIndex && columnRoles[index] == role) {
            columnRoles[index] = TermImportColumnRole.ignore;
          }
        }
      }

      columnRoles[columnIndex] = role;
      errorMessage = null;
    });
  }

  Future<void> _continueToPreview() async {
    final selectedDocument = document;

    if (selectedDocument == null) {
      await _pickFile();
      return;
    }

    if (!mapping.hasLookupColumn) {
      setState(() {
        errorMessage = 'Choose a Term or Reading column before continuing.';
      });
      return;
    }

    final rows = TermImportService.buildImportRows(
      document: selectedDocument,
      mapping: mapping,
      firstRowIsHeader: firstRowIsHeader,
    );
    final usableRowCount = rows.where((row) {
      return row.status != DeckImportMatchStatus.skipped;
    }).length;

    if (usableRowCount == 0) {
      setState(() {
        errorMessage = 'No usable terms were found with this column mapping.';
      });
      return;
    }

    final imported = await Navigator.push<bool>(
      context,
      GakujiPageRoute(
        builder: (context) => ImportTermsPreviewPage(
          document: selectedDocument,
          mapping: mapping,
          firstRowIsHeader: firstRowIsHeader,
        ),
      ),
    );

    if (!mounted || imported != true) return;

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: document == null
                  ? _initialImportView()
                  : _mappingView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return GakujiTopBar(
      leftIcon: GakujiTopBar.backIcon,
      leftIconSize: GakujiTopBar.backIconSize,
      leftIconColor: GakujiColors.darkGray,
      onLeftTap: () => Navigator.pop(context),
      title: document == null ? null : 'Import Terms',
      titleStyle: GakujiText.pageTitle.copyWith(
        color: GakujiColors.darkGray,
      ),
    );
  }

  Widget _initialImportView() {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(28, 0, 28, 28 + bottomInset),
      child: Column(
        children: [
          const SizedBox(height: 78),
          Icon(
            Icons.ios_share_rounded,
            size: 76,
            color: GakujiColors.darkGray,
          ),
          const SizedBox(height: 34),
          Text(
            'Import Terms',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.pageTitle.copyWith(
              color: GakujiColors.darkGray,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Import CSV, TSV, UTF-8 TXT, or XLSX files.\n'
            'TXT files may also contain one term per line.',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 15.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: GakujiColors.mediumGray,
            ),
          ),
          const Spacer(),
          if (errorMessage != null) ...[
            _errorCard(errorMessage!),
            const SizedBox(height: 16),
          ],
          _chooseFileButton(),
        ],
      ),
    );
  }

  Widget _mappingView() {
    return GakujiFadedScroll(
      topFadeEnd: 0.06,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        children: [
          _selectedFileCard(document!),
          if (importFile!.hasMultipleDocuments) ...[
            const SizedBox(height: 20),
            _worksheetSelector(importFile!),
          ],
          const SizedBox(height: 20),
          _headerSetting(document!),
          const SizedBox(height: 20),
          _columnMapping(document!),
          const SizedBox(height: 20),
          _mappedPreview(document!),
          if (errorMessage != null) ...[
            const SizedBox(height: 16),
            _errorCard(errorMessage!),
          ],
          const SizedBox(height: 28),
          _continueButton(),
        ],
      ),
    );
  }

  Widget _chooseFileButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: isPickingFile
            ? GakujiColors.softBorder
            : GakujiColors.reading,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isPickingFile ? null : _pickFile,
          child: Center(
            child: Text(
              isPickingFile ? 'Opening Files...' : 'Choose File',
              textScaler: TextScaler.noScaling,
              style: GakujiText.medium.copyWith(
                color: isPickingFile
                    ? GakujiColors.mediumGray
                    : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectedFileCard(TermImportDocument selectedDocument) {
    final rowCount = selectedDocument.dataRowCount(
      firstRowIsHeader: firstRowIsHeader,
    );
    final details = <String>[
      selectedDocument.fileType.label,
      if (selectedDocument.sheetName != null) selectedDocument.sheetName!,
      '$rowCount rows',
      '${selectedDocument.columnCount} columns',
    ];

    return _sectionCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: GakujiColors.reading.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              _fileIcon(selectedDocument.fileType),
              color: GakujiColors.reading,
              size: 29,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedDocument.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: GakujiColors.darkGray,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  details.join(' • '),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: GakujiColors.mediumGray,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: isPickingFile ? null : _pickFile,
            child: Text(
              'Change',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: GakujiColors.reading,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _worksheetSelector(TermImportFile selectedFile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('Worksheet'),
        const SizedBox(height: 10),
        _sectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: selectedDocumentIndex,
              isExpanded: true,
              dropdownColor: GakujiColors.warmCard,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: GakujiColors.mediumGray,
              ),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: GakujiColors.darkGray,
              ),
              items: List.generate(selectedFile.documents.length, (index) {
                final sheet = selectedFile.documents[index];
                final rowCount = sheet.dataRowCount(
                  firstRowIsHeader: sheet.detectedHeader,
                );

                return DropdownMenuItem<int>(
                  value: index,
                  child: Text(
                    '${sheet.sheetName ?? "Worksheet ${index + 1}"} • $rowCount rows',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                  ),
                );
              }),
              onChanged: (index) {
                if (index == null) return;
                _selectDocument(index);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerSetting(TermImportDocument selectedDocument) {
    return _sectionCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'First row contains headers',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: GakujiColors.darkGray,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedDocument.detectedHeader
                      ? 'Gakuji detected a possible header row.'
                      : 'Gakuji did not detect a header row.',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: GakujiColors.mediumGray,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: firstRowIsHeader,
            activeThumbColor: GakujiColors.reading,
            onChanged: (value) {
              setState(() {
                firstRowIsHeader = value;
                errorMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _columnMapping(TermImportDocument selectedDocument) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('Column Mapping'),
        const SizedBox(height: 10),
        ...List.generate(selectedDocument.columnCount, (columnIndex) {
          final samples = selectedDocument
              .dataRows(firstRowIsHeader: firstRowIsHeader)
              .map((row) => row.valueAt(columnIndex))
              .where((value) => value.isNotEmpty)
              .take(2)
              .toList(growable: false);

          return Padding(
            padding: EdgeInsets.only(
              bottom: columnIndex == selectedDocument.columnCount - 1 ? 0 : 12,
            ),
            child: _columnCard(
              label: selectedDocument.columnLabel(
                columnIndex,
                firstRowIsHeader: firstRowIsHeader,
              ),
              samples: samples,
              role: columnRoles[columnIndex],
              onChanged: (role) {
                if (role == null) return;
                _setColumnRole(columnIndex, role);
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _columnCard({
    required String label,
    required List<String> samples,
    required TermImportColumnRole role,
    required ValueChanged<TermImportColumnRole?> onChanged,
  }) {
    return _sectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: GakujiColors.darkGray,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 126,
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: GakujiColors.warmBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: role == TermImportColumnRole.ignore
                        ? GakujiColors.warmDivider
                        : GakujiColors.reading.withValues(alpha: 0.55),
                    width: 1.3,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TermImportColumnRole>(
                    value: role,
                    isExpanded: true,
                    dropdownColor: GakujiColors.warmCard,
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: GakujiColors.mediumGray,
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: role == TermImportColumnRole.ignore
                          ? GakujiColors.mediumGray
                          : GakujiColors.darkGray,
                    ),
                    items: TermImportColumnRole.values.map((value) {
                      return DropdownMenuItem(
                        value: value,
                        child: Text(
                          value.label,
                          textScaler: TextScaler.noScaling,
                        ),
                      );
                    }).toList(),
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
          if (samples.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...samples.map((sample) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  sample,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: GakujiColors.mediumGray,
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _mappedPreview(TermImportDocument selectedDocument) {
    final rows = TermImportService.buildImportRows(
      document: selectedDocument,
      mapping: mapping,
      firstRowIsHeader: firstRowIsHeader,
    ).take(5).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('Preview'),
        const SizedBox(height: 10),
        ...List.generate(rows.length, (index) {
          final row = rows[index];
          final previewTerm = Term(
            id: 'import_preview_${row.rowNumber}',
            kanji: row.importedTerm,
            reading: row.importedReading,
            meaning: row.importedDefinition.isEmpty
                ? 'No definition provided'
                : row.importedDefinition,
          );

          return Column(
            children: [
              GakujiTermRow(
                term: previewTerm,
                titleText: row.importedLabel,
                readingText: row.importedReading,
                showChevron: false,
                meaningMaxLines: 2,
                padding: const EdgeInsets.fromLTRB(0, 11, 0, 12),
              ),
              if (index < rows.length - 1)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: GakujiTermRow.dividerColor,
                ),
            ],
          );
        }),
      ],
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GakujiColors.pinRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: GakujiColors.pinRed.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 21,
            color: GakujiColors.pinRed,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: GakujiColors.darkGray,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _continueButton() {
    final ready = document != null && mapping.hasLookupColumn;

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Material(
        color: ready
            ? GakujiColors.reading
            : GakujiColors.softBorder,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isPickingFile ? null : _continueToPreview,
          child: Center(
            child: Text(
              document == null ? 'Choose File' : 'Match Dictionary Terms',
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                color: ready ? Colors.white : GakujiColors.mediumGray,
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _fileIcon(TermImportFileType fileType) {
    switch (fileType) {
      case TermImportFileType.csv:
      case TermImportFileType.tsv:
        return Icons.description_rounded;
      case TermImportFileType.text:
        return Icons.text_snippet_rounded;
      case TermImportFileType.xlsx:
        return Icons.grid_on_rounded;
    }
  }

  Widget _sectionHeading(String label) {
    return Text(
      label,
      textScaler: TextScaler.noScaling,
      style: GakujiText.small.copyWith(
        color: GakujiColors.darkGray,
      ),
    );
  }

  Widget _sectionCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.2,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: child,
    );
  }
}
