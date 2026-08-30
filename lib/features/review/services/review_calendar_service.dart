import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/review_card.dart';
import 'package:gakuji/data/review/review_settings.dart';

class ReviewCalendarDayData {
  final List<ReviewCard> projectedNewCards;
  final List<ReviewCard> projectedReviewCards;
  final List<ReviewCard> scheduledNewCards;
  final List<ReviewCard> scheduledLearningCards;
  final List<ReviewCard> scheduledReviewCards;

  const ReviewCalendarDayData({
    this.projectedNewCards = const [],
    this.projectedReviewCards = const [],
    this.scheduledNewCards = const [],
    this.scheduledLearningCards = const [],
    this.scheduledReviewCards = const [],
  });

  int get projectedNew => projectedNewCards.length;
  int get projectedReview => projectedReviewCards.length;
  int get scheduledNew => scheduledNewCards.length;
  int get scheduledLearning => scheduledLearningCards.length;
  int get scheduledReview => scheduledReviewCards.length;

  bool get hasProjected =>
      projectedNewCards.isNotEmpty || projectedReviewCards.isNotEmpty;

  bool get hasScheduled =>
      scheduledNewCards.isNotEmpty ||
      scheduledLearningCards.isNotEmpty ||
      scheduledReviewCards.isNotEmpty;
}

class ReviewCalendarService {
  static Future<Map<DateTime, ReviewCalendarDayData>> buildForDeck({
    required Deck deck,
    required List<ReviewCard> allReviewCards,
    DateTime? now,
  }) async {
    final checkTime = now ?? DateTime.now();
    final today = _dateOnly(checkTime);
    final settings = await ReviewSettingsStore.load();
    final newCardsStartedToday =
        await ReviewSettingsStore.newCardsStartedToday(
          deckId: deck.id,
          now: checkTime,
        );
    final reviewsCompletedToday =
        await ReviewSettingsStore.reviewsCompletedToday(
          deckId: deck.id,
          now: checkTime,
        );

    final builders = <DateTime, _ReviewCalendarDayBuilder>{};

    _addScheduledCards(
      deckId: deck.id,
      cards: allReviewCards,
      today: today,
      builders: builders,
    );

    _addProjectedNewCards(
      deck: deck,
      allReviewCards: allReviewCards,
      today: today,
      newLimit: settings.newLimit,
      newCardsStartedToday: newCardsStartedToday,
      builders: builders,
    );

    _addProjectedReviewCards(
      deckId: deck.id,
      cards: allReviewCards,
      today: today,
      reviewLimit: settings.reviewLimit,
      reviewsCompletedToday: reviewsCompletedToday,
      builders: builders,
    );

    return {
      for (final entry in builders.entries)
        entry.key: entry.value.freeze(),
    };
  }

  static void _addScheduledCards({
    required String deckId,
    required List<ReviewCard> cards,
    required DateTime today,
    required Map<DateTime, _ReviewCalendarDayBuilder> builders,
  }) {
    for (final card in cards) {
      if (card.deckId != deckId) continue;

      final state = card.state;

      if (state != ReviewCardState.learning &&
          state != ReviewCardState.relearning &&
          state != ReviewCardState.review) {
        continue;
      }

      var scheduledDate = _dateOnly(card.dueDate);

      if (scheduledDate.isBefore(today)) {
        scheduledDate = today;
      }

      final builder = _builderFor(builders, scheduledDate);

      if (state == ReviewCardState.review) {
        builder.scheduledReviewCards.add(card);
      } else {
        builder.scheduledLearningCards.add(card);
      }
    }

    for (final builder in builders.values) {
      builder.scheduledLearningCards.sort(_compareDueCards);
      builder.scheduledReviewCards.sort(_compareDueCards);
    }
  }

  static void _addProjectedNewCards({
    required Deck deck,
    required List<ReviewCard> allReviewCards,
    required DateTime today,
    required int newLimit,
    required int newCardsStartedToday,
    required Map<DateTime, _ReviewCalendarDayBuilder> builders,
  }) {
    if (newLimit <= 0) return;

    final deckNewCards = allReviewCards.where((card) {
      return card.deckId == deck.id &&
          card.state == ReviewCardState.newCard;
    }).toList();

    if (deckNewCards.isEmpty) return;

    final orderedNewCards = _orderNewCardsByDeck(
      deck: deck,
      newCards: deckNewCards,
    );

    final todayCapacity =
        (newLimit - newCardsStartedToday).clamp(0, newLimit).toInt();

    final todayEndIndex =
        todayCapacity.clamp(0, orderedNewCards.length).toInt();

    if (todayEndIndex > 0) {
      _builderFor(builders, today)
          .scheduledNewCards
          .addAll(orderedNewCards.sublist(0, todayEndIndex));
    }

    var cardIndex = todayEndIndex;
    var projectedDate = today.add(const Duration(days: 1));

    while (cardIndex < orderedNewCards.length) {
      final endIndex =
          (cardIndex + newLimit).clamp(0, orderedNewCards.length).toInt();

      _builderFor(builders, projectedDate)
          .projectedNewCards
          .addAll(orderedNewCards.sublist(cardIndex, endIndex));

      cardIndex = endIndex;
      projectedDate = projectedDate.add(const Duration(days: 1));
    }
  }

  static void _addProjectedReviewCards({
    required String deckId,
    required List<ReviewCard> cards,
    required DateTime today,
    required int reviewLimit,
    required int reviewsCompletedToday,
    required Map<DateTime, _ReviewCalendarDayBuilder> builders,
  }) {
    if (reviewLimit <= 0) return;

    final reviewCards = cards.where((card) {
      return card.deckId == deckId &&
          card.state == ReviewCardState.review;
    }).toList()
      ..sort((first, second) {
        final firstDate = _effectiveDueDate(first, today);
        final secondDate = _effectiveDueDate(second, today);
        final dateComparison = firstDate.compareTo(secondDate);

        if (dateComparison != 0) return dateComparison;

        return _compareDueCards(first, second);
      });

    if (reviewCards.isEmpty) return;

    var projectedDate = today;
    var remainingCapacity =
        (reviewLimit - reviewsCompletedToday).clamp(0, reviewLimit).toInt();

    for (final card in reviewCards) {
      final dueDate = _effectiveDueDate(card, today);

      if (dueDate.isAfter(projectedDate)) {
        projectedDate = dueDate;
        remainingCapacity = reviewLimit;
      }

      while (remainingCapacity <= 0) {
        projectedDate = projectedDate.add(const Duration(days: 1));
        remainingCapacity = reviewLimit;
      }

      _builderFor(builders, projectedDate)
          .projectedReviewCards
          .add(card);

      remainingCapacity--;
    }
  }

  static List<ReviewCard> _orderNewCardsByDeck({
    required Deck deck,
    required List<ReviewCard> newCards,
  }) {
    final cardsByTermId = <String, List<ReviewCard>>{};

    for (final card in newCards) {
      cardsByTermId.putIfAbsent(card.termId, () => []).add(card);
    }

    for (final cards in cardsByTermId.values) {
      cards.sort((first, second) {
        return first.cardType.index.compareTo(second.cardType.index);
      });
    }

    final ordered = <ReviewCard>[];
    final addedCardIds = <String>{};

    for (final term in deck.terms) {
      final termId = term.sourceId ?? term.id;
      final matchingCards = cardsByTermId[termId] ?? const <ReviewCard>[];

      for (final card in matchingCards) {
        ordered.add(card);
        addedCardIds.add(card.id);
      }
    }

    final unmatchedCards = newCards
        .where((card) => !addedCardIds.contains(card.id))
        .toList()
      ..sort((first, second) => first.id.compareTo(second.id));

    ordered.addAll(unmatchedCards);

    return ordered;
  }

  static _ReviewCalendarDayBuilder _builderFor(
    Map<DateTime, _ReviewCalendarDayBuilder> builders,
    DateTime date,
  ) {
    final normalizedDate = _dateOnly(date);

    return builders.putIfAbsent(
      normalizedDate,
      _ReviewCalendarDayBuilder.new,
    );
  }

  static DateTime _effectiveDueDate(
    ReviewCard card,
    DateTime today,
  ) {
    final dueDate = _dateOnly(card.dueDate);
    return dueDate.isBefore(today) ? today : dueDate;
  }

  static int _compareDueCards(
    ReviewCard first,
    ReviewCard second,
  ) {
    final dueComparison =
        first.dueDate.toUtc().compareTo(second.dueDate.toUtc());

    if (dueComparison != 0) return dueComparison;

    return first.id.compareTo(second.id);
  }

  static DateTime _dateOnly(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}

class _ReviewCalendarDayBuilder {
  final List<ReviewCard> projectedNewCards = [];
  final List<ReviewCard> projectedReviewCards = [];
  final List<ReviewCard> scheduledNewCards = [];
  final List<ReviewCard> scheduledLearningCards = [];
  final List<ReviewCard> scheduledReviewCards = [];

  ReviewCalendarDayData freeze() {
    return ReviewCalendarDayData(
      projectedNewCards: List.unmodifiable(projectedNewCards),
      projectedReviewCards: List.unmodifiable(projectedReviewCards),
      scheduledNewCards: List.unmodifiable(scheduledNewCards),
      scheduledLearningCards:
          List.unmodifiable(scheduledLearningCards),
      scheduledReviewCards:
          List.unmodifiable(scheduledReviewCards),
    );
  }
}
