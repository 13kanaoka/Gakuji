import 'package:flutter/material.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';

import 'package:gakuji/data/review/review_card_data.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/review_card.dart';
import 'package:gakuji/features/review/services/review_calendar_service.dart';
import 'package:gakuji/core/widgets/gakuji_faded_scroll.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/features/review/review_calendar_term_list_page.dart';

class ReviewCalendarPage extends StatefulWidget {
  final Deck deck;
  final String title;
  final DateTime? initialMonth;
  final DateTime? initialSelectedDate;

  const ReviewCalendarPage({
    super.key,
    required this.deck,
    this.title = 'Review Calendar',
    this.initialMonth,
    this.initialSelectedDate,
  });

  @override
  State<ReviewCalendarPage> createState() => _ReviewCalendarPageState();
}

class _ReviewCalendarPageState extends State<ReviewCalendarPage> {
  static const int _initialMonthPage = 12000;

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

  static const List<String> _weekdayLabels = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN',
  ];

  late DateTime visibleMonth;
  late DateTime selectedDate;
  late DateTime _anchorMonth;
  late PageController _monthController;

  Map<DateTime, ReviewCalendarDayData> dayData = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();

    final startingMonth = widget.initialMonth ?? DateTime.now();

    visibleMonth = DateTime(
      startingMonth.year,
      startingMonth.month,
    );

    _anchorMonth = visibleMonth;
    _monthController = PageController(
      initialPage: _initialMonthPage,
    );

    final initialSelection =
        widget.initialSelectedDate ?? DateTime.now();

    selectedDate = DateTime(
      initialSelection.year,
      initialSelection.month,
      initialSelection.day,
    );

    _loadCalendarData();
  }

  ReviewCalendarDayData get selectedDayData {
    return dayData[_dateOnly(selectedDate)] ??
        const ReviewCalendarDayData();
  }

  bool get selectedDateIsFuture {
    return selectedDate.isAfter(_dateOnly(DateTime.now()));
  }

  bool get selectedDateIsToday {
    return _isSameDate(selectedDate, DateTime.now());
  }

  Future<void> _loadCalendarData() async {
    await createReviewCardsForDeck(widget.deck);
    await loadReviewCards();

    final calculatedData = await ReviewCalendarService.buildForDeck(
      deck: widget.deck,
      allReviewCards: List<ReviewCard>.from(reviewCards),
      now: DateTime.now(),
    );

    if (!mounted) return;

    setState(() {
      dayData = calculatedData;
      isLoading = false;
    });
  }

  DateTime _monthForPage(int page) {
    final monthOffset = page - _initialMonthPage;

    return DateTime(
      _anchorMonth.year,
      _anchorMonth.month + monthOffset,
    );
  }

  void _handleMonthChanged(int page) {
    final month = _monthForPage(page);

    setState(() {
      visibleMonth = month;
      selectedDate = _selectionForMonth(month);
    });
  }

  @override
  void dispose() {
    _monthController.dispose();
    super.dispose();
  }

  DateTime _selectionForMonth(DateTime month) {
    final now = DateTime.now();

    if (now.year == month.year && now.month == month.month) {
      return DateTime(now.year, now.month, now.day);
    }

    return DateTime(month.year, month.month, 1);
  }

  DateTime _dateOnly(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  bool _isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  bool _isToday(DateTime date) {
    return _isSameDate(date, DateTime.now());
  }

  Future<void> _openTermList(
    ReviewCalendarListType listType,
  ) async {
    final data = selectedDayData;

    await Navigator.push(
      context,
      GakujiPageRoute(
        builder: (context) => ReviewCalendarTermListPage(
          deck: widget.deck,
          date: selectedDate,
          listType: listType,
          dayData: data,
        ),
      ),
    );
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
              child: isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: GakujiColors.deckBlue,
                      ),
                    )
                  : GakujiFadedScroll(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(
                          top: 24,
                          bottom: 28,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  _monthHeader(),
                                  const SizedBox(height: 20),
                                  _weekdayHeader(),
                                  const SizedBox(height: 8),
                                  Divider(
                                    height: 1,
                                    thickness: 1.5,
                                    color: GakujiColors.warmDivider,
                                  ),
                                  const SizedBox(height: 6),
                                  _monthPager(),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                            _selectedDaySummary(),
                          ],
                        ),
                      ),
                    ),
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
      title: widget.title,
      titleStyle: GakujiText.dictionaryTopBarTitle.copyWith(
        color: GakujiColors.darkGray,
      ),
    );
  }

  Widget _monthHeader() {
    return Text(
      '${_monthNames[visibleMonth.month - 1]} ${visibleMonth.year}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
      style: GakujiText.large.copyWith(
        color: GakujiColors.darkGray,
      ),
    );
  }

  int _calendarRowCount(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final leadingEmptyCells =
        firstDay.weekday - DateTime.monday;
    final daysInMonth = DateUtils.getDaysInMonth(
      month.year,
      month.month,
    );

    return ((leadingEmptyCells + daysInMonth) / 7).ceil();
  }

  double _calendarHeight(DateTime month) {
    final rowCount = _calendarRowCount(month);
    const rowHeight = 58.0;
    const dividerHeight = 1.0;

    return (rowCount * rowHeight) +
        ((rowCount - 1) * dividerHeight);
  }

  Widget _monthPager() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: _calendarHeight(visibleMonth),
      child: PageView.builder(
        controller: _monthController,
        onPageChanged: _handleMonthChanged,
        itemBuilder: (context, page) {
          final month = _monthForPage(page);

          return _calendarGrid(month);
        },
      ),
    );
  }

  Widget _weekdayHeader() {
    return Row(
      children: _weekdayLabels.map((label) {
        return Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              color: GakujiColors.mediumGray,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _calendarGrid(DateTime month) {
    final firstDay = DateTime(
      month.year,
      month.month,
      1,
    );

    final daysInMonth = DateUtils.getDaysInMonth(
      month.year,
      month.month,
    );

    final leadingEmptyCells = firstDay.weekday - DateTime.monday;
    final rowCount = _calendarRowCount(month);

    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerHeight = 1.0;
        final totalDividerHeight =
            (rowCount - 1) * dividerHeight;
        final rowHeight =
            (constraints.maxHeight - totalDividerHeight) / rowCount;

        return Column(
          children: List.generate(rowCount, (rowIndex) {
            final rowStart = rowIndex * 7;

            return Column(
              children: [
                SizedBox(
                  height: rowHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(7, (columnIndex) {
                      final cellIndex = rowStart + columnIndex;
                      final dayNumber =
                          cellIndex - leadingEmptyCells + 1;

                      if (dayNumber < 1 ||
                          dayNumber > daysInMonth) {
                        return const Expanded(
                          child: SizedBox.shrink(),
                        );
                      }

                      final date = DateTime(
                        month.year,
                        month.month,
                        dayNumber,
                      );

                      return Expanded(
                        child: _calendarDay(date),
                      );
                    }),
                  ),
                ),
                if (rowIndex < rowCount - 1)
                   Divider(
                    height: dividerHeight,
                    thickness: dividerHeight,
                    color: GakujiColors.lightDivider,
                  ),
              ],
            );
          }),
        );
      },
    );
  }

  Widget _calendarDay(DateTime date) {
    final selected = _isSameDate(date, selectedDate);
    final today = _isToday(date);

    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () {
        setState(() {
          selectedDate = date;
        });
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: selected
                ? GakujiColors.deckBlue
                : Colors.transparent,
            shape: BoxShape.circle,
            border: !selected && today
                ? Border.all(
                    color: GakujiColors.deckBlue,
                    width: 1.7,
                  )
                : null,
            boxShadow:
                selected ? [GakujiShadows.soft] : const [],
          ),
          child: Text(
            '${date.day}',
            textScaler: TextScaler.noScaling,
            style: GakujiText.small.copyWith(
              color: selected
                  ? Colors.white
                  : today
                      ? GakujiColors.deckBlue
                      : GakujiColors.darkGray,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectedDaySummary() {
    final data = selectedDayData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedDateIsFuture) ...[
          _summaryGroup(
            label: 'Projected',
            rows: [
              _SummaryRow('New', data.projectedNew),
              _SummaryRow('Review', data.projectedReview),
            ],
            enabled: data.hasProjected,
            onTap: () {
              _openTermList(
                ReviewCalendarListType.projected,
              );
            },
          ),
          const SizedBox(height: 20),
        ],
        _summaryGroup(
          label: 'Scheduled',
          rows: [
            if (selectedDateIsToday)
              _SummaryRow('New', data.scheduledNew),
            _SummaryRow('Learning', data.scheduledLearning),
            _SummaryRow('Review', data.scheduledReview),
          ],
          enabled: data.hasScheduled,
          onTap: () {
            _openTermList(
              ReviewCalendarListType.scheduled,
            );
          },
        ),
      ],
    );
  }

  Widget _summaryGroup({
    required String label,
    required List<_SummaryRow> rows,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final contentColor = enabled
        ? GakujiColors.darkGray
        : GakujiColors.softGray;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.58,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          color: contentColor,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 27,
                      color: enabled
                          ? GakujiColors.mediumGray
                          : GakujiColors.softGray,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: Column(
              children: rows.map((row) {
                return _summaryRow(
                  row,
                  contentColor: contentColor,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    _SummaryRow row, {
    required Color contentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                color: contentColor,
              ),
            ),
          ),
          Text(
            '${row.value}',
            textScaler: TextScaler.noScaling,
            style: GakujiText.small.copyWith(
              color: contentColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow {
  final String label;
  final int value;

  const _SummaryRow(this.label, this.value);
}
