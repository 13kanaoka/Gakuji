import 'package:flutter/material.dart';

import 'package:gakuji/domain/review_card.dart';
import 'package:gakuji/data/review/review_settings.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';

class ReviewScheduleCard extends StatefulWidget {
  final String deckId;
  final List<ReviewCard> reviewCards;

  const ReviewScheduleCard({
    super.key,
    required this.deckId,
    required this.reviewCards,
  });

  @override
  State<ReviewScheduleCard> createState() => _ReviewScheduleCardState();
}

class _ReviewScheduleCardState extends State<ReviewScheduleCard> {
  late DateTime selectedDate;
  int remainingNewCardsToday = ReviewSettings.defaults.newLimit;
  int remainingReviewCardsToday = ReviewSettings.defaults.reviewLimit;

  DateTime get today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    selectedDate = today;
    _loadDailyAvailability();
  }

  @override
  void didUpdateWidget(covariant ReviewScheduleCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.deckId != widget.deckId ||
        oldWidget.reviewCards != widget.reviewCards) {
      _loadDailyAvailability();
    }
  }

  Future<void> _loadDailyAvailability() async {
    final settings = await ReviewSettingsStore.load();
    final newCardsStartedToday =
        await ReviewSettingsStore.newCardsStartedToday(deckId: widget.deckId);
    final reviewsCompletedToday =
        await ReviewSettingsStore.reviewsCompletedToday(deckId: widget.deckId);

    if (!mounted) return;

    setState(() {
      remainingNewCardsToday =
          (settings.newLimit - newCardsStartedToday).clamp(0, 9999).toInt();
      remainingReviewCardsToday =
          (settings.reviewLimit - reviewsCompletedToday).clamp(0, 9999).toInt();
    });
  }

  List<DateTime> get visibleDates {
    final monday = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );

    return List.generate(
      7,
      (index) => monday.add(Duration(days: index)),
    );
  }

  int get selectedNewCount {
    final rawCount = _cardsForSelectedDate
        .where((card) => card.state == ReviewCardState.newCard)
        .length;

    if (!_isSameDate(selectedDate, today)) return rawCount;

    return rawCount < remainingNewCardsToday
        ? rawCount
        : remainingNewCardsToday;
  }

  int get selectedLearningCount {
    return _cardsForSelectedDate.where((card) {
      return card.state == ReviewCardState.learning ||
          card.state == ReviewCardState.relearning;
    }).length;
  }

  int get selectedReviewCount {
    final rawCount = _cardsForSelectedDate
        .where((card) => card.state == ReviewCardState.review)
        .length;

    if (!_isSameDate(selectedDate, today)) return rawCount;

    return rawCount < remainingReviewCardsToday
        ? rawCount
        : remainingReviewCardsToday;
  }

  List<ReviewCard> get _cardsForSelectedDate {
    return widget.reviewCards.where((card) {
      return _isCardDueOnDate(card, selectedDate);
    }).toList();
  }

  bool _isCardDueOnDate(ReviewCard card, DateTime date) {
    final cardDueDate = _dateOnly(card.dueDate.toLocal());
    final selectedDay = _dateOnly(date);
    final todayDate = today;

    if (_isSameDate(selectedDay, todayDate)) {
      return cardDueDate.isBefore(todayDate) ||
          _isSameDate(cardDueDate, todayDate);
    }

    return _isSameDate(cardDueDate, selectedDay);
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  bool _isWeekend(DateTime date) {
    return date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;
  }

  String _weekdayLabel(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'MON';
      case DateTime.tuesday:
        return 'TUE';
      case DateTime.wednesday:
        return 'WED';
      case DateTime.thursday:
        return 'THU';
      case DateTime.friday:
        return 'FRI';
      case DateTime.saturday:
        return 'SAT';
      case DateTime.sunday:
        return 'SUN';
      default:
        return '';
    }
  }

  String _monthLabel(BuildContext context, DateTime date) {
    return MaterialLocalizations.of(context)
        .formatMonthYear(date)
        .split(' ')
        .first;
  }

  String _selectedDateSubtitle(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final weekdayName =
        localizations.formatFullDate(selectedDate).split(',').first;

    if (_isSameDate(selectedDate, today)) {
      return 'Today, $weekdayName';
    }

    return weekdayName;
  }

  @override
  Widget build(BuildContext context) {
    final selectedMonth = _monthLabel(context, selectedDate);
    final selectedSubtitle = _selectedDateSubtitle(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
      decoration: BoxDecoration(
        color: GakujiColors.whiteCard,
        borderRadius: BorderRadius.circular(GakujiRadius.small),
        border: Border.all(
          color: GakujiColors.softBorder,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(
            month: selectedMonth,
            subtitle: selectedSubtitle,
          ),
          const SizedBox(height: 28),
          _dateRow(),
          const SizedBox(height: 18),
          _divider(),
          const SizedBox(height: 22),
          _scheduleStats(),
        ],
      ),
    );
  }

  Widget _header({
    required String month,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${selectedDate.day}',
            textScaler: TextScaler.noScaling,
            style: GakujiText.calendarDate,
          ),
          const SizedBox(width: 22),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  month,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.calendarMeta,
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.calendarMeta,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateRow() {
    return Row(
      children: visibleDates.map((date) {
        final selected = _isSameDate(date, selectedDate);

        return Expanded(
          child: _dateButton(
            date: date,
            selected: selected,
          ),
        );
      }).toList(),
    );
  }

  Widget _dateButton({
    required DateTime date,
    required bool selected,
  }) {
    final muted = _isWeekend(date);
    final isToday = _isSameDate(date, today);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(GakujiRadius.pill),
      child: InkWell(
        onTap: () {
          setState(() {
            selectedDate = date;
          });
        },
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        splashColor: GakujiColors.deckBlue.withValues(alpha: 0.08),
        highlightColor: GakujiColors.deckBlue.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _weekdayLabel(date),
                textScaler: TextScaler.noScaling,
                style: GakujiText.calendarSmall.copyWith(
                  color: muted
                      ? GakujiColors.mediumGray.withValues(alpha: 0.35)
                      : GakujiColors.mediumGray,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                width: 36,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? GakujiColors.deckBlue.withValues(alpha: 0.78)
                      : isToday
                          ? GakujiColors.softBorder.withValues(alpha: 0.55)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(GakujiRadius.pill),
                  boxShadow: selected ? [GakujiShadows.soft] : const [],
                ),
                child: Text(
                  '${date.day}',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.calendarSmall.copyWith(
                    color: selected
                        ? Colors.white
                        : muted
                            ? GakujiColors.mediumGray.withValues(alpha: 0.35)
                            : GakujiColors.mediumGray,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: double.infinity,
      height: 1.5,
      decoration: BoxDecoration(
        color: GakujiColors.softBorder,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
      ),
    );
  }

  Widget _scheduleStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _scheduleStat(
            label: 'New',
            count: selectedNewCount,
          ),
          _scheduleStat(
            label: 'Learning',
            count: selectedLearningCount,
          ),
          _scheduleStat(
            label: 'Review',
            count: selectedReviewCount,
          ),
        ],
      ),
    );
  }

  Widget _scheduleStat({
    required String label,
    required int count,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textScaler: TextScaler.noScaling,
          style: GakujiText.calendarMeta.copyWith(
            color: GakujiColors.mediumGray,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$count',
          textScaler: TextScaler.noScaling,
          style: GakujiText.calendarMeta.copyWith(
            color: GakujiColors.mediumGray,
          ),
        ),
      ],
    );
  }
}
