import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../models/review_card.dart';
import '../models/term.dart';
import '../services/review_calendar_service.dart';
import '../widgets/gakuji_faded_scroll.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import '../widgets/gakuji_term_row.dart';
import 'dictionary_detail_page.dart';

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

  List<_CalendarTermGroup> get groups {
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
    final visibleGroups = groups
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
                  : GakujiFadedScroll(
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
            style: GakujiText.large.copyWith(
              color: GakujiColors.darkGray,
            ),
          ),
          const SizedBox(height: 3),
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
        _sectionHeader('${group.label} ${visibleTerms.length}'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            children: List.generate(visibleTerms.length, (index) {
              final term = visibleTerms[index];
              final titleText = term.kanjiBracketText.isNotEmpty
                  ? term.kanjiBracketText
                  : term.kanji;

              return Column(
                children: [
                  GakujiTermRow(
                    term: term,
                    titleText: titleText,
                    readingText: term.reading,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
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

  Widget _sectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      decoration: BoxDecoration(
        color: GakujiColors.sectionHeader,
        border: Border(
          top: BorderSide(
            color: GakujiColors.darkGray.withOpacity(0.16),
            width: 1,
          ),
          bottom: BorderSide(
            color: GakujiColors.darkGray.withOpacity(0.16),
            width: 1,
          ),
        ),
      ),
      child: Text(
        title,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1,
          color: GakujiColors.darkGray,
        ),
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
