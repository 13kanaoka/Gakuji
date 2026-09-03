import 'package:flutter/material.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';

import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/review_card.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/features/review/services/review_calendar_service.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_term_row.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/features/dictionary/dictionary_detail_page.dart';

enum ReviewCalendarListType {
  projected,
  scheduled,
}

class ReviewCalendarTermListPage extends StatelessWidget {
  final Deck deck;
  final DateTime date;
  final ReviewCalendarListType listType;
  final ReviewCalendarDayData dayData;

  const ReviewCalendarTermListPage({
    super.key,
    required this.deck,
    required this.date,
    required this.listType,
    required this.dayData,
  });

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String get pageTitle {
    switch (listType) {
      case ReviewCalendarListType.projected:
        return 'Projected';
      case ReviewCalendarListType.scheduled:
        return 'Scheduled';
    }
  }

  String get dateLabel {
    return '${_monthNames[date.month - 1]} ${date.day}';
  }

  Map<String, Term> get _termsByReviewId {
    return {
      for (final term in deck.terms)
        term.sourceId ?? term.id: term,
    };
  }

  List<_CalendarTermGroup> get _groups {
    switch (listType) {
      case ReviewCalendarListType.projected:
        return [
          _CalendarTermGroup(
            label: 'New',
            cards: dayData.projectedNewCards,
          ),
          _CalendarTermGroup(
            label: 'Review',
            cards: dayData.projectedReviewCards,
          ),
        ];
      case ReviewCalendarListType.scheduled:
        return [
          _CalendarTermGroup(
            label: 'New',
            cards: dayData.scheduledNewCards,
          ),
          _CalendarTermGroup(
            label: 'Learning',
            cards: dayData.scheduledLearningCards,
          ),
          _CalendarTermGroup(
            label: 'Review',
            cards: dayData.scheduledReviewCards,
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleGroups = _groups
        .where((group) => group.cards.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: visibleGroups.isEmpty
                  ? _emptyState()
                  : ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) {
                        return const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x00000000),
                            Colors.black,
                            Colors.black,
                            Color(0x00000000),
                          ],
                          stops: [
                            0.0,
                            0.035,
                            0.94,
                            1.0,
                          ],
                        ).createShader(bounds);
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.only(
                          top: 18,
                          bottom: 36,
                        ),
                        itemCount: visibleGroups.length,
                        itemBuilder: (context, index) {
                          return _termGroup(
                            context,
                            visibleGroups[index],
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return GakujiTopBar(
      leftIcon: GakujiTopBar.backIcon,
      leftIconSize: GakujiTopBar.backIconSize,
      leftIconColor: GakujiColors.darkGray,
      onLeftTap: () => Navigator.pop(context),
      titleWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pageTitle,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.dictionaryTopBarTitle.copyWith(
              color: GakujiColors.darkGray,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            dateLabel,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              color: GakujiColors.mediumGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Text(
        'No terms for this day',
        textScaler: TextScaler.noScaling,
        style: GakujiText.small.copyWith(
          color: GakujiColors.mediumGray,
        ),
      ),
    );
  }

  Widget _termGroup(
    BuildContext context,
    _CalendarTermGroup group,
  ) {
    final termsById = _termsByReviewId;
    final visibleTerms = <Term>[];

    for (final card in group.cards) {
      final term = termsById[card.termId];

      if (term != null && !visibleTerms.contains(term)) {
        visibleTerms.add(term);
      }
    }

    if (visibleTerms.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(group.label, visibleTerms.length),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GakujiSpacing.contentHorizontal),
          child: Column(
            children: List.generate(visibleTerms.length, (index) {
              final term = visibleTerms[index];
              final titleText = term.preferredSpelling.trim().isNotEmpty
                  ? term.preferredSpelling.trim()
                  : term.kanji.trim().isNotEmpty
                      ? term.kanji.trim()
                      : term.reading.trim();

              return Column(
                children: [
                  GakujiTermRow(
                    term: term,
                    titleText: titleText,
                    readingText: term.reading,
                    onTap: () {
                      Navigator.push(
                        context,
                        GakujiPageRoute(
                          builder: (context) =>
                              DictionaryDetailPage(word: term),
                        ),
                      );
                    },
                  ),
                  if (index < visibleTerms.length - 1)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: GakujiTermRow.dividerColor,
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String label, int termCount) {
    final countLabel = termCount == 1 ? '(1 term)' : '($termCount terms)';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(GakujiSpacing.contentHorizontal, 8, GakujiSpacing.contentHorizontal, 8),
      decoration: BoxDecoration(
        color: GakujiColors.sectionHeader,
        border: Border(
          top: BorderSide(
            color: GakujiColors.darkGray.withValues(alpha: 0.16),
            width: 1,
          ),
          bottom: BorderSide(
            color: GakujiColors.darkGray.withValues(alpha: 0.16),
            width: 1,
          ),
        ),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1,
                color: GakujiColors.darkGray,
              ),
            ),
            TextSpan(
              text: ' $countLabel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1,
                color: GakujiColors.mediumGray,
              ),
            ),
          ],
        ),
        textScaler: TextScaler.noScaling,
      ),
    );
  }


}

class _CalendarTermGroup {
  final String label;
  final List<ReviewCard> cards;

  const _CalendarTermGroup({
    required this.label,
    required this.cards,
  });
}
