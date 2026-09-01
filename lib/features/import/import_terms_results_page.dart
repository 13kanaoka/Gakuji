import 'package:flutter/material.dart';

import 'package:gakuji/features/import/models/deck_import_result.dart';
import 'package:gakuji/features/import/models/deck_import_row.dart';
import 'package:gakuji/core/widgets/gakuji_faded_scroll.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';

class ImportTermsResultsPage extends StatelessWidget {
  final DeckImportResult result;

  const ImportTermsResultsPage({
    super.key,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: GakujiColors.warmBackground,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              GakujiTopBar(
                title: 'Import Complete',
                titleStyle: GakujiText.pageTitle.copyWith(
                  color: GakujiColors.darkGray,
                ),
              ),
              Expanded(
                child: GakujiFadedScroll(
                  topFadeEnd: 0.06,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(GakujiSpacing.roomyContentHorizontal, 26, GakujiSpacing.roomyContentHorizontal, 28),
                    children: [
                      _successHeader(),
                      const SizedBox(height: 24),
                      _summaryCard(),
                      if (result.unresolvedRows.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Rows Not Imported',
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.actionLabel.copyWith(
                            fontSize:
                                (GakujiText.actionLabel.fontSize ?? 16) + 2,
                            color: GakujiColors.darkGray,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _unresolvedRowsCard(),
                      ],
                    ],
                  ),
                ),
              ),
              _doneButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _successHeader() {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: GakujiColors.reading.withValues(alpha: 0.13),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            size: 50,
            color: GakujiColors.reading,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '${result.importedCount} terms imported',
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: GakujiText.sectionTitle.copyWith(
            color: GakujiColors.darkGray,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your terms are ready in “${result.deckName}.”',
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: GakujiText.body.copyWith(
            height: 1.4,
            fontWeight: FontWeight.w500,
            color: GakujiColors.mediumGray,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.2,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Column(
        children: [
          _summaryRow(
            label: 'Imported',
            value: result.importedCount,
            icon: Icons.check_circle_outline_rounded,
            color: GakujiColors.reading,
          ),
          _divider(),
          _summaryRow(
            label: 'Duplicates',
            value: result.duplicateCount,
            icon: Icons.content_copy_rounded,
            color: GakujiColors.mediumGray,
          ),
          _divider(),
          _summaryRow(
            label: 'Unmatched',
            value: result.unmatchedCount,
            icon: Icons.search_off_rounded,
            color: GakujiColors.mediumGray,
          ),
          _divider(),
          _summaryRow(
            label: 'Needs review',
            value: result.ambiguousCount,
            icon: Icons.help_outline_rounded,
            color: GakujiColors.review,
          ),
          _divider(),
          _summaryRow(
            label: 'Skipped',
            value: result.skippedCount,
            icon: Icons.remove_circle_outline_rounded,
            color: GakujiColors.mediumGray,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: color,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.actionLabel.copyWith(
                color: GakujiColors.darkGray,
              ),
            ),
          ),
          Text(
            '$value',
            textScaler: TextScaler.noScaling,
            style: GakujiText.actionLabel.copyWith(
              fontWeight: FontWeight.w800,
              color: GakujiColors.darkGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      color: GakujiColors.warmDivider,
    );
  }

  Widget _unresolvedRowsCard() {
    return Container(
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.2,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Column(
        children: List.generate(result.unresolvedRows.length, (index) {
          final row = result.unresolvedRows[index];
          final statusColor = _statusColor(row.status);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _statusIcon(row.status),
                        size: 18,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.importedLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: TextScaler.noScaling,
                            style: GakujiText.termRowTitle.copyWith(
                              fontFamily: GakujiFonts.japanese,
                              color: GakujiColors.darkGray,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Row ${row.rowNumber} • ${_statusLabel(row)}',
                            textScaler: TextScaler.noScaling,
                            style: GakujiText.termRowMeaning.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (index < result.unresolvedRows.length - 1)
                Divider(
                  height: 1,
                  color: GakujiColors.warmDivider,
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _doneButton(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(GakujiSpacing.contentHorizontal, 12, GakujiSpacing.contentHorizontal, 14),
        decoration: BoxDecoration(
          color: GakujiColors.warmBackground,
          border: Border(
            top: BorderSide(
              color: GakujiColors.warmDivider,
            ),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: Material(
            color: GakujiColors.reading,
            borderRadius: BorderRadius.circular(GakujiRadius.pill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.pop(context, true),
              child: Center(
                child: Text(
                  'Done',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.actionLabel.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel(DeckImportRow row) {
    if (row.status == DeckImportMatchStatus.matched && !row.included) {
      return 'Skipped by user';
    }

    switch (row.status) {
      case DeckImportMatchStatus.matched:
        return 'Skipped';
      case DeckImportMatchStatus.ambiguous:
        return 'Match not selected';
      case DeckImportMatchStatus.unmatched:
        return 'No dictionary match';
      case DeckImportMatchStatus.duplicate:
        return 'Duplicate';
      case DeckImportMatchStatus.skipped:
        return 'Missing term or reading';
      case DeckImportMatchStatus.pending:
        return 'Not processed';
    }
  }

  Color _statusColor(DeckImportMatchStatus status) {
    switch (status) {
      case DeckImportMatchStatus.ambiguous:
        return GakujiColors.review;
      case DeckImportMatchStatus.matched:
        return GakujiColors.reading;
      case DeckImportMatchStatus.unmatched:
      case DeckImportMatchStatus.duplicate:
      case DeckImportMatchStatus.skipped:
      case DeckImportMatchStatus.pending:
        return GakujiColors.mediumGray;
    }
  }

  IconData _statusIcon(DeckImportMatchStatus status) {
    switch (status) {
      case DeckImportMatchStatus.matched:
        return Icons.remove_rounded;
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
}
