import 'package:flutter/material.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';

import 'package:gakuji/data/seed/deck_seed.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/features/import/models/deck_import_result.dart';
import 'package:gakuji/features/import/models/deck_import_row.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/features/auth/services/account_username_service.dart';
import 'package:gakuji/features/import/services/term_import_service.dart';
import 'package:gakuji/features/import/services/dictionary_import_matcher.dart';
import 'package:gakuji/data/dictionary/dictionary_service.dart';
import 'package:gakuji/data/sync/gakuji_user_data_store.dart';
import 'package:gakuji/core/widgets/gakuji_faded_scroll.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_term_row.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/features/import/import_terms_results_page.dart';

class ImportTermsPreviewPage extends StatefulWidget {
  final TermImportDocument document;
  final DeckImportMapping mapping;
  final bool firstRowIsHeader;

  const ImportTermsPreviewPage({
    super.key,
    required this.document,
    required this.mapping,
    required this.firstRowIsHeader,
  });

  @override
  State<ImportTermsPreviewPage> createState() =>
      _ImportTermsPreviewPageState();
}

enum _ImportRowFilter {
  all,
  needsReview,
}

class _ImportTermsPreviewPageState extends State<ImportTermsPreviewPage> {
  static const String _newDeckValue = '__new_deck__';

  late final List<DeckImportRow> rows;
  late final TextEditingController deckNameController;

  String selectedDestination = _newDeckValue;
  DeckType selectedDeckType = DeckType.reading;
  _ImportRowFilter rowFilter = _ImportRowFilter.all;

  bool isMatching = true;
  bool isImporting = false;
  int matchedProgress = 0;
  int totalMatchableRows = 0;
  String? matchingError;
  String? importError;

  Deck? get selectedExistingDeck {
    if (selectedDestination == _newDeckValue) return null;

    for (final deck in decks) {
      if (deck.id == selectedDestination) return deck;
    }

    return null;
  }

  DeckType get destinationDeckType {
    return selectedExistingDeck?.type ?? selectedDeckType;
  }

  Color get destinationColor {
    switch (destinationDeckType) {
      case DeckType.reading:
        return GakujiColors.reading;
      case DeckType.writing:
        return GakujiColors.writing;
      case DeckType.hybrid:
        return GakujiColors.hybrid;
    }
  }

  int get readyCount {
    return rows.where((row) => row.canImport).length;
  }

  int get ambiguousCount {
    return rows.where((row) {
      return row.status == DeckImportMatchStatus.ambiguous;
    }).length;
  }

  int get unmatchedCount {
    return rows.where((row) {
      return row.status == DeckImportMatchStatus.unmatched;
    }).length;
  }

  int get duplicateCount {
    return rows.where((row) {
      return row.status == DeckImportMatchStatus.duplicate;
    }).length;
  }

  int get skippedCount {
    return rows.where((row) {
      return row.status == DeckImportMatchStatus.skipped;
    }).length;
  }

  List<DeckImportRow> get visibleRows {
    if (rowFilter == _ImportRowFilter.all) return rows;

    return rows.where((row) {
      return row.status != DeckImportMatchStatus.matched;
    }).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();

    rows = TermImportService.buildImportRows(
      document: widget.document,
      mapping: widget.mapping,
      firstRowIsHeader: widget.firstRowIsHeader,
    );
    totalMatchableRows = rows.where((row) {
      return row.status != DeckImportMatchStatus.skipped;
    }).length;
    deckNameController = TextEditingController(
      text: _defaultDeckName(widget.document.fileName),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _matchRows();
    });
  }

  @override
  void dispose() {
    deckNameController.dispose();
    super.dispose();
  }

  Future<void> _matchRows() async {
    setState(() {
      isMatching = true;
      matchedProgress = 0;
      matchingError = null;
      importError = null;
    });

    try {
      await DictionaryImportMatcher.matchRows(
        rows,
        onProgress: (completed, total) {
          if (!mounted) return;

          setState(() {
            matchedProgress = completed;
            totalMatchableRows = total;
          });
        },
      );

      if (!mounted) return;

      setState(() {
        isMatching = false;
        _refreshDuplicates();
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isMatching = false;
        matchingError =
            'Gakuji could not finish matching this file. Please try again.';
      });
    }
  }

  void _refreshDuplicates() {
    final existingSourceIds = selectedExistingDeck?.terms.map((term) {
          return term.sourceId ?? term.id;
        }).toSet() ??
        <String>{};
    final seenSourceIds = <String>{...existingSourceIds};

    for (final row in rows) {
      if (row.status == DeckImportMatchStatus.duplicate) {
        row
          ..status = DeckImportMatchStatus.matched
          ..included = true
          ..message = null;
      }

      final sourceId = row.selectedSourceId;

      if (sourceId == null ||
          row.status == DeckImportMatchStatus.unmatched ||
          row.status == DeckImportMatchStatus.ambiguous ||
          row.status == DeckImportMatchStatus.skipped ||
          !row.included) {
        continue;
      }

      if (seenSourceIds.contains(sourceId)) {
        row
          ..status = DeckImportMatchStatus.duplicate
          ..included = false
          ..message = selectedExistingDeck == null
              ? 'This dictionary entry appears more than once in the import file.'
              : 'This dictionary entry is already in the selected deck.';
        continue;
      }

      seenSourceIds.add(sourceId);
    }
  }

  void _toggleRow(DeckImportRow row, bool value) {
    if (row.selectedTerm == null ||
        row.status == DeckImportMatchStatus.unmatched ||
        row.status == DeckImportMatchStatus.ambiguous ||
        row.status == DeckImportMatchStatus.skipped ||
        row.status == DeckImportMatchStatus.duplicate) {
      return;
    }

    setState(() {
      row.included = value;
      _refreshDuplicates();
    });
  }

  Future<void> _chooseCandidate(DeckImportRow row) async {
    if (row.candidates.isEmpty) return;

    final selected = await showModalBottomSheet<Term>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.76,
            ),
            decoration: BoxDecoration(
              color: GakujiColors.warmBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: GakujiColors.softBorder,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose a dictionary entry',
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.sectionTitle.copyWith(
                          color: GakujiColors.darkGray,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'File row ${row.rowNumber}: ${row.importedLabel}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.body.copyWith(
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: GakujiColors.mediumGray,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: GakujiColors.warmDivider,
                ),
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
                    itemCount: row.candidates.length,
                    separatorBuilder: (context, index) {
                      return const Divider(
                        height: 1,
                        thickness: 1,
                        color: GakujiTermRow.dividerColor,
                      );
                    },
                    itemBuilder: (context, index) {
                      final term = row.candidates[index].term;

                      return GakujiTermRow(
                        term: term,
                        titleText: term.kanjiBracketText.isNotEmpty
                            ? term.kanjiBracketText
                            : term.kanji,
                        readingText: term.reading,
                        meaningMaxLines: 2,
                        onTap: () => Navigator.pop(context, term),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) return;

    setState(() {
      row
        ..selectedTerm = selected
        ..status = DeckImportMatchStatus.matched
        ..included = true
        ..message = null;
      _refreshDuplicates();
    });
  }

  Future<void> _importTerms() async {
    if (isMatching || isImporting || readyCount == 0) return;

    final existingDeck = selectedExistingDeck;
    final newDeckName = deckNameController.text.trim();

    if (existingDeck == null && newDeckName.isEmpty) {
      setState(() {
        importError = 'Enter a name for the new deck.';
      });
      return;
    }

    if (existingDeck == null &&
        GakujiUsernameService.containsRestrictedLanguage(newDeckName)) {
      setState(() {
        importError = 'Deck name contains a restricted term.';
      });
      return;
    }

    setState(() {
      isImporting = true;
      importError = null;
    });

    Deck? targetDeck;
    final addedTerms = <Term>[];
    var addedNewDeck = false;

    try {
      targetDeck = existingDeck ??
          Deck(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: newDeckName,
            type: selectedDeckType,
            terms: [],
          );
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      var importedCount = 0;

      for (final row in rows) {
        if (!row.canImport) continue;

        var dictionaryTerm = row.selectedTerm!;
        final sourceId = dictionaryTerm.sourceId ?? dictionaryTerm.id;

        // Import the canonical dictionary entry, just like saving a term from
        // Dictionary Detail. Matcher results can be lightweight, so reloading by
        // source ID guarantees the deck copy carries its normal senses/examples.
        try {
          dictionaryTerm = await DictionaryService.getTermByIdAsync(sourceId);
        } catch (_) {
          // Keep the matched term as a safe fallback if the dictionary reload
          // is unavailable. Term.deckCopyFrom still preserves its card data.
        }

        final deckTerm = Term.deckCopyFrom(
          dictionaryTerm,
          id: '${targetDeck.id}_${sourceId}_${timestamp}_$importedCount',
          marked: false,
        );

        targetDeck.terms.add(deckTerm);
        addedTerms.add(deckTerm);
        importedCount++;
      }

      if (existingDeck == null) {
        decks.add(targetDeck);
        addedNewDeck = true;
      }

      await GakujiUserDataStore.saveNow();
      GakujiUserDataStore.scheduleSave();

      if (!mounted) return;

      final unresolvedRows = rows.where((row) {
        return !row.canImport;
      }).toList(growable: false);
      final result = DeckImportResult(
        deckName: targetDeck.name,
        importedCount: importedCount,
        duplicateCount: duplicateCount,
        unmatchedCount: unmatchedCount,
        ambiguousCount: ambiguousCount,
        skippedCount: skippedCount +
            rows.where((row) {
              return row.status == DeckImportMatchStatus.matched &&
                  !row.included;
            }).length,
        unresolvedRows: unresolvedRows,
      );

      final finished = await Navigator.push<bool>(
        context,
        GakujiPageRoute(
          builder: (context) => ImportTermsResultsPage(
            result: result,
          ),
        ),
      );

      if (!mounted || finished != true) return;

      Navigator.pop(context, true);
    } catch (_) {
      if (targetDeck != null) {
        targetDeck.terms.removeWhere(addedTerms.contains);

        if (addedNewDeck) {
          decks.remove(targetDeck);
        }
      }

      if (!mounted) return;

      setState(() {
        isImporting = false;
        importError = 'Gakuji could not save the imported deck.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredRows = visibleRows;

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _topBar(),
                Expanded(
                  child: GakujiFadedScroll(
                    topFadeEnd: 0.06,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 112),
                      children: [
                        _destinationSection(),
                        const SizedBox(height: 22),
                        if (isMatching)
                          _matchingProgress()
                        else if (matchingError != null)
                          _matchingErrorCard()
                        else ...[
                          _summarySection(),
                          const SizedBox(height: 20),
                          _rowFilter(),
                          const SizedBox(height: 12),
                          if (filteredRows.isEmpty)
                            _emptyFilterState()
                          else
                            ...List.generate(filteredRows.length, (index) {
                              return Column(
                                children: [
                                  _rowCard(filteredRows[index]),
                                  if (index < filteredRows.length - 1)
                                    Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: GakujiColors.softBorder,
                                    ),
                                ],
                              );
                            }),
                        ],
                        if (importError != null) ...[
                          const SizedBox(height: 4),
                          _errorCard(importError!),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 0,
              child: _bottomAction(),
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
      title: 'Import Preview',
      titleStyle: GakujiText.pageTitle.copyWith(
        color: GakujiColors.darkGray,
      ),
    );
  }

  Widget _destinationSection() {
    final existingDeck = selectedExistingDeck;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('Destination'),
        const SizedBox(height: 10),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel('Import Into'),
              const SizedBox(height: 8),
              _dropdownField<String>(
                value: selectedDestination,
                items: [
                  const DropdownMenuItem(
                    value: _newDeckValue,
                    child: Text(
                      'Create a new deck',
                      textScaler: TextScaler.noScaling,
                    ),
                  ),
                  ...decks.map((deck) {
                    return DropdownMenuItem(
                      value: deck.id,
                      child: Text(
                        deck.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                      ),
                    );
                  }),
                ],
                onChanged: (value) {
                  if (value == null) return;

                  setState(() {
                    selectedDestination = value;
                    importError = null;
                    _refreshDuplicates();
                  });
                },
              ),
              if (existingDeck == null) ...[
                const SizedBox(height: 18),
                _fieldLabel('Deck Name'),
                const SizedBox(height: 8),
                _nameField(),
                const SizedBox(height: 18),
                _fieldLabel('Deck Type'),
                const SizedBox(height: 8),
                _dropdownField<DeckType>(
                  value: selectedDeckType,
                  items: DeckType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(
                        _deckTypeLabel(type),
                        textScaler: TextScaler.noScaling,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;

                    setState(() {
                      selectedDeckType = value;
                    });
                  },
                ),
              ] else ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: destinationColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_deckTypeLabel(existingDeck.type)} deck • '
                      '${existingDeck.terms.length} existing terms',
                      textScaler: TextScaler.noScaling,
                      style: GakujiText.deckMeta.copyWith(
                        color: GakujiColors.mediumGray,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _matchingProgress() {
    final progress = totalMatchableRows == 0
        ? 0.0
        : matchedProgress / totalMatchableRows;

    return _sectionCard(
      child: Column(
        children: [
          Text(
            'Matching dictionary entries',
            textScaler: TextScaler.noScaling,
            style: GakujiText.actionLabel.copyWith(
              color: GakujiColors.darkGray,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$matchedProgress of $totalMatchableRows rows',
            textScaler: TextScaler.noScaling,
            style: GakujiText.deckMeta.copyWith(
              color: GakujiColors.mediumGray,
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: GakujiColors.softBorder,
              valueColor: AlwaysStoppedAnimation<Color>(
                GakujiColors.reading,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchingErrorCard() {
    return Column(
      children: [
        _errorCard(matchingError!),
        const SizedBox(height: 14),
        _secondaryButton(
          label: 'Try Matching Again',
          onTap: _matchRows,
        ),
      ],
    );
  }

  Widget _summarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('Match Summary'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _summaryTile(
                label: 'Ready',
                value: readyCount,
                icon: Icons.check_circle_outline_rounded,
                color: GakujiColors.reading,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryTile(
                label: 'Review',
                value: ambiguousCount,
                icon: Icons.help_outline_rounded,
                color: GakujiColors.review,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryTile(
                label: 'Unmatched',
                value: unmatchedCount + duplicateCount + skippedCount,
                icon: Icons.remove_circle_outline_rounded,
                color: GakujiColors.mediumGray,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryTile({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 13),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GakujiColors.warmDivider,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 23,
          ),
          const SizedBox(height: 7),
          Text(
            '$value',
            textScaler: TextScaler.noScaling,
            style: GakujiText.sectionTitle.copyWith(
              fontWeight: FontWeight.w800,
              color: GakujiColors.darkGray,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.deckMeta.copyWith(
              fontWeight: FontWeight.w700,
              color: GakujiColors.mediumGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowFilter() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: GakujiColors.warmDivider,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _filterButton(
              label: 'All ${rows.length}',
              selected: rowFilter == _ImportRowFilter.all,
              onTap: () {
                setState(() {
                  rowFilter = _ImportRowFilter.all;
                });
              },
            ),
          ),
          Expanded(
            child: _filterButton(
              label: 'Needs Review ${rows.length - readyCount}',
              selected: rowFilter == _ImportRowFilter.needsReview,
              onTap: () {
                setState(() {
                  rowFilter = _ImportRowFilter.needsReview;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? GakujiColors.reading : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: GakujiText.deckMeta.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : GakujiColors.mediumGray,
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowCard(DeckImportRow row) {
    final selectedTerm = row.selectedTerm;
    final statusColor = _statusColor(row.status);
    final canChoose = row.candidates.isNotEmpty &&
        (row.status == DeckImportMatchStatus.ambiguous ||
            row.status == DeckImportMatchStatus.unmatched);
    final displayTerm = selectedTerm ??
        Term(
          id: 'import_row_${row.rowNumber}',
          kanji: row.importedTerm,
          reading: row.importedReading,
          meaning: row.importedDefinition.isEmpty
              ? row.message ?? 'No dictionary match found'
              : row.importedDefinition,
        );

    Widget? trailing;

    if (selectedTerm != null &&
        row.status == DeckImportMatchStatus.matched) {
      trailing = Checkbox(
        value: row.included,
        activeColor: GakujiColors.reading,
        onChanged: (value) {
          if (value == null) return;
          _toggleRow(row, value);
        },
      );
    } else if (canChoose ||
        row.status == DeckImportMatchStatus.ambiguous) {
      trailing = TextButton(
        onPressed: () => _chooseCandidate(row),
        style: TextButton.styleFrom(
          foregroundColor: GakujiColors.reading,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: GakujiText.deckMeta.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        child: const Text(
          'Choose',
          textScaler: TextScaler.noScaling,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GakujiTermRow(
          term: displayTerm,
          titleText: displayTerm.kanjiBracketText.isNotEmpty
              ? displayTerm.kanjiBracketText
              : displayTerm.kanji,
          readingText: displayTerm.reading,
          showChevron: false,
          isSelected: row.included,
          meaningMaxLines: 2,
          leading: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _statusIcon(row.status),
              size: 17,
              color: statusColor,
            ),
          ),
          trailing: trailing,
          onTap: canChoose ? () => _chooseCandidate(row) : null,
        ),
        if (row.message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 0, 6),
            child: Text(
              'Row ${row.rowNumber} • ${row.message!}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: GakujiText.deckMeta.copyWith(
                height: 1.3,
                color: statusColor,
              ),
            ),
          ),
      ],
    );
  }

  Widget _emptyFilterState() {
    return _sectionCard(
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 38,
            color: GakujiColors.reading,
          ),
          const SizedBox(height: 10),
          Text(
            'No rows need attention',
            textScaler: TextScaler.noScaling,
            style: GakujiText.actionLabel.copyWith(
              color: GakujiColors.darkGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomAction() {
    final canImport = !isMatching &&
        !isImporting &&
        matchingError == null &&
        readyCount > 0;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: Material(
          color: canImport
              ? destinationColor
              : GakujiColors.softBorder,
          borderRadius: BorderRadius.circular(GakujiRadius.pill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canImport ? _importTerms : null,
            child: Center(
              child: isImporting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isMatching
                          ? 'Matching Terms...'
                          : 'Import $readyCount Terms',
                      textScaler: TextScaler.noScaling,
                      style: GakujiText.actionLabel.copyWith(
                        color: canImport
                            ? Colors.white
                            : GakujiColors.mediumGray,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nameField() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: GakujiColors.warmBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.3,
        ),
      ),
      child: TextField(
        controller: deckNameController,
        textInputAction: TextInputAction.done,
        cursorColor: GakujiColors.darkGray,
        onChanged: (_) {
          if (importError == null) return;
          setState(() {
            importError = null;
          });
        },
        style: GakujiText.actionLabel.copyWith(
          fontWeight: FontWeight.w600,
          color: GakujiColors.darkGray,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Enter deck name',
          hintStyle: GakujiText.actionLabel.copyWith(
            fontWeight: FontWeight.w500,
            color: GakujiColors.mediumGray,
          ),
        ),
      ),
    );
  }

  Widget _dropdownField<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: GakujiColors.warmBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.3,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          isExpanded: true,
          dropdownColor: GakujiColors.warmCard,
          borderRadius: BorderRadius.circular(14),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: GakujiColors.mediumGray,
          ),
          style: GakujiText.actionLabel.copyWith(
            fontWeight: FontWeight.w600,
            color: GakujiColors.darkGray,
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(GakujiRadius.pill),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.actionLabel.copyWith(
                color: GakujiColors.reading,
              ),
            ),
          ),
        ),
      ),
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
              style: GakujiText.body.copyWith(
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

  Widget _sectionCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(17),
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

  Widget _sectionHeading(String label) {
    return Text(
      label,
      textScaler: TextScaler.noScaling,
      style: GakujiText.actionLabel.copyWith(
        fontSize: (GakujiText.actionLabel.fontSize ?? 16) + 2,
        color: GakujiColors.darkGray,
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      textScaler: TextScaler.noScaling,
      style: GakujiText.actionLabel.copyWith(
        color: GakujiColors.darkGray,
      ),
    );
  }

  Color _statusColor(DeckImportMatchStatus status) {
    switch (status) {
      case DeckImportMatchStatus.matched:
        return GakujiColors.reading;
      case DeckImportMatchStatus.ambiguous:
        return GakujiColors.review;
      case DeckImportMatchStatus.unmatched:
      case DeckImportMatchStatus.duplicate:
      case DeckImportMatchStatus.skipped:
        return GakujiColors.mediumGray;
      case DeckImportMatchStatus.pending:
        return GakujiColors.softGray;
    }
  }

  IconData _statusIcon(DeckImportMatchStatus status) {
    switch (status) {
      case DeckImportMatchStatus.matched:
        return Icons.check_rounded;
      case DeckImportMatchStatus.ambiguous:
        return Icons.question_mark_rounded;
      case DeckImportMatchStatus.unmatched:
        return Icons.search_off_rounded;
      case DeckImportMatchStatus.duplicate:
        return Icons.content_copy_rounded;
      case DeckImportMatchStatus.skipped:
        return Icons.remove_rounded;
      case DeckImportMatchStatus.pending:
        return Icons.more_horiz_rounded;
    }
  }

  String _deckTypeLabel(DeckType type) {
    switch (type) {
      case DeckType.reading:
        return 'Reading';
      case DeckType.writing:
        return 'Writing';
      case DeckType.hybrid:
        return 'Hybrid';
    }
  }

  String _defaultDeckName(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final cleaned = baseName.replaceAll(RegExp(r'[_\-]+'), ' ').trim();

    if (cleaned.isEmpty) return 'Imported Deck';

    return cleaned
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty) return word;
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }
}
