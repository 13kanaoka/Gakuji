import 'dart:math' as math;

import 'package:fsrs/fsrs.dart' as fsrs;

import 'package:gakuji/domain/review_card.dart';

class ReviewScheduleResult {
  final ReviewCard card;
  final ReviewLogEntry reviewLog;

  const ReviewScheduleResult({
    required this.card,
    required this.reviewLog,
  });
}

class ReviewScheduler {
  /// Fuzzing is disabled so the interval shown above each rating button is the
  /// same interval that is applied when the user chooses that rating.
  static final fsrs.Scheduler _scheduler = fsrs.Scheduler(
    desiredRetention: 0.9,
    learningSteps: const [
      Duration(minutes: 1),
      Duration(minutes: 10),
    ],
    relearningSteps: const [
      Duration(minutes: 10),
    ],
    maximumInterval: 36500,
    enableFuzzing: false,
  );

  /// Creates a new FSRS-backed Review card for a deck-owned term.
  ///
  /// Review data belongs to:
  /// deckId + termId + cardType
  static ReviewCard createReviewCard({
    required String deckId,
    required String termId,
    required ReviewCardType cardType,
    DateTime? now,
  }) {
    final createdAt = (now ?? DateTime.now()).toUtc();
    final reviewCardId = _buildReviewCardId(
      deckId: deckId,
      termId: termId,
      cardType: cardType,
    );

    final fsrsCard = fsrs.Card(
      cardId: _stableFsrsCardId(reviewCardId),
      due: createdAt,
    );

    return ReviewCard(
      id: reviewCardId,
      deckId: deckId,
      termId: termId,
      cardType: cardType,
      state: ReviewCardState.newCard,
      dueDate: createdAt,
      intervalDays: 0,
      easeFactor: 2.5,
      repetitions: 0,
      lapses: 0,
      lastReviewedAt: null,
      fsrsCard: Map<String, dynamic>.from(fsrsCard.toMap()),
    );
  }

  /// Reviews a card through FSRS and returns both the updated card and the
  /// immutable review log produced for that rating.
  static ReviewScheduleResult reviewCard({
    required ReviewCard card,
    required ReviewRating rating,
    DateTime? now,
    int? reviewDurationMilliseconds,
  }) {
    final reviewedAt = (now ?? DateTime.now()).toUtc();
    final currentFsrsCard = _fsrsCardFor(card);
    final currentFsrsState = currentFsrsCard.state;

    final result = _scheduler.reviewCard(
      currentFsrsCard,
      _fsrsRatingFor(rating),
      reviewDateTime: reviewedAt,
      reviewDuration: reviewDurationMilliseconds,
    );

    final updatedFsrsCard = result.card;
    final scheduledDuration = updatedFsrsCard.due.difference(reviewedAt);
    final intervalDays = math.max(0, scheduledDuration.inDays).toInt();
    final wasLapse = currentFsrsState == fsrs.State.review &&
        rating == ReviewRating.again;

    final updatedCard = card.copyWith(
      state: _reviewCardStateFor(updatedFsrsCard),
      dueDate: updatedFsrsCard.due.toUtc(),
      intervalDays: intervalDays,
      repetitions: rating == ReviewRating.again
          ? card.repetitions
          : card.repetitions + 1,
      lapses: wasLapse ? card.lapses + 1 : card.lapses,
      lastReviewedAt: updatedFsrsCard.lastReview?.toUtc(),
      fsrsCard: Map<String, dynamic>.from(updatedFsrsCard.toMap()),
    );

    final reviewLog = ReviewLogEntry(
      id: _buildReviewLogId(
        reviewCardId: card.id,
        reviewedAt: result.reviewLog.reviewDateTime,
        rating: rating,
      ),
      reviewCardId: card.id,
      rating: rating,
      reviewedAt: result.reviewLog.reviewDateTime.toUtc(),
      fsrsLog: Map<String, dynamic>.from(result.reviewLog.toMap()),
    );

    return ReviewScheduleResult(
      card: updatedCard,
      reviewLog: reviewLog,
    );
  }

  /// Calculates the interval each rating would currently produce without
  /// mutating or saving the card.
  static Map<ReviewRating, Duration> previewIntervals({
    required ReviewCard card,
    DateTime? now,
  }) {
    final previewAt = (now ?? DateTime.now()).toUtc();
    final currentFsrsCard = _fsrsCardFor(card);
    final previews = <ReviewRating, Duration>{};

    for (final rating in ReviewRating.values) {
      final result = _scheduler.reviewCard(
        currentFsrsCard,
        _fsrsRatingFor(rating),
        reviewDateTime: previewAt,
      );

      final interval = result.card.due.difference(previewAt);
      previews[rating] = interval.isNegative ? Duration.zero : interval;
    }

    return previews;
  }

  static String formatInterval(Duration? interval) {
    if (interval == null) return '--';

    final seconds = math.max(0, interval.inSeconds).toInt();

    if (seconds < 60) {
      return '<1 min';
    }

    final minutes = _ceilDivide(seconds, 60);

    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = _ceilDivide(seconds, 60 * 60);

    if (hours < 24) {
      return hours == 1 ? '1 hr' : '$hours hr';
    }

    final days = _ceilDivide(seconds, 24 * 60 * 60);

    if (days < 30) {
      return days == 1 ? '1 day' : '$days days';
    }

    if (days < 365) {
      final months = math.max(1, (days / 30).round()).toInt();
      return months == 1 ? '1 mo' : '$months mo';
    }

    final years = math.max(1, (days / 365).round()).toInt();
    return years == 1 ? '1 yr' : '$years yr';
  }

  /// Returns only cards due at or before [now].
  static List<ReviewCard> dueCards(
    List<ReviewCard> cards, {
    DateTime? now,
  }) {
    final checkTime = (now ?? DateTime.now()).toUtc();

    return cards.where((card) => card.isDue(checkTime)).toList()
      ..sort((first, second) {
        return first.dueDate.toUtc().compareTo(second.dueDate.toUtc());
      });
  }

  /// Returns all Review cards belonging to a specific deck.
  static List<ReviewCard> cardsForDeck(
    List<ReviewCard> cards,
    String deckId,
  ) {
    return cards.where((card) => card.deckId == deckId).toList();
  }

  /// Returns due Review cards belonging to a specific deck.
  static List<ReviewCard> dueCardsForDeck(
    List<ReviewCard> cards,
    String deckId, {
    DateTime? now,
  }) {
    return dueCards(
      cardsForDeck(cards, deckId),
      now: now,
    );
  }

  static fsrs.Card _fsrsCardFor(ReviewCard card) {
    if (card.hasFsrsState) {
      try {
        final storedMap = Map<String, dynamic>.from(card.fsrsCard!);
        _normalizeFsrsCardDates(storedMap);
        return fsrs.Card.fromMap(storedMap);
      } catch (_) {
        // Fall through to a one-time legacy conversion.
      }
    }

    return _legacyFsrsCardFor(card);
  }

  static fsrs.Card _legacyFsrsCardFor(ReviewCard card) {
    final cardId = _stableFsrsCardId(card.id);
    final due = card.dueDate.toUtc();
    final lastReview = card.lastReviewedAt?.toUtc();

    switch (card.state) {
      case ReviewCardState.newCard:
        return fsrs.Card(
          cardId: cardId,
          due: due,
        );

      case ReviewCardState.learning:
        return fsrs.Card(
          cardId: cardId,
          state: fsrs.State.learning,
          step: 0,
          due: due,
          lastReview: lastReview,
        );

      case ReviewCardState.review:
        return fsrs.Card(
          cardId: cardId,
          state: fsrs.State.review,
          step: null,
          stability: _legacyStabilityFor(card),
          difficulty: 5.0,
          due: due,
          lastReview: lastReview ?? _estimatedLegacyLastReview(card),
        );

      case ReviewCardState.relearning:
        return fsrs.Card(
          cardId: cardId,
          state: fsrs.State.relearning,
          step: 0,
          stability: _legacyStabilityFor(card),
          difficulty: 5.0,
          due: due,
          lastReview: lastReview ?? _estimatedLegacyLastReview(card),
        );
    }
  }

  static double _legacyStabilityFor(ReviewCard card) {
    return math.max(1.0, card.intervalDays.toDouble()).toDouble();
  }

  static DateTime _estimatedLegacyLastReview(ReviewCard card) {
    final interval = math.max(1, card.intervalDays).toInt();
    return card.dueDate.toUtc().subtract(Duration(days: interval));
  }

  static ReviewCardState _reviewCardStateFor(fsrs.Card card) {
    if (card.lastReview == null) {
      return ReviewCardState.newCard;
    }

    switch (card.state) {
      case fsrs.State.learning:
        return ReviewCardState.learning;
      case fsrs.State.review:
        return ReviewCardState.review;
      case fsrs.State.relearning:
        return ReviewCardState.relearning;
    }
  }

  static fsrs.Rating _fsrsRatingFor(ReviewRating rating) {
    switch (rating) {
      case ReviewRating.again:
        return fsrs.Rating.again;
      case ReviewRating.hard:
        return fsrs.Rating.hard;
      case ReviewRating.good:
        return fsrs.Rating.good;
      case ReviewRating.easy:
        return fsrs.Rating.easy;
    }
  }

  static void _normalizeFsrsCardDates(Map<String, dynamic> map) {
    final dueValue = map['due']?.toString();

    if (dueValue != null && dueValue.isNotEmpty) {
      map['due'] = DateTime.parse(dueValue).toUtc().toIso8601String();
    }

    final lastReviewValue = map['lastReview']?.toString();

    if (lastReviewValue != null && lastReviewValue.isNotEmpty) {
      map['lastReview'] =
          DateTime.parse(lastReviewValue).toUtc().toIso8601String();
    }
  }

  static int _stableFsrsCardId(String value) {
    // Combine two small deterministic hashes into one web-safe 53-bit int.
    var high = 0;
    var low = 0;

    for (final codeUnit in value.codeUnits) {
      high = (high * 31 + codeUnit) & 0xFFFFFFFF;
      low = (low * 131 + codeUnit) & 0x1FFFFF;
    }

    final combined = high * 0x200000 + low;
    return combined == 0 ? 1 : combined;
  }

  static int _ceilDivide(int value, int divisor) {
    return (value + divisor - 1) ~/ divisor;
  }

  static String _buildReviewCardId({
    required String deckId,
    required String termId,
    required ReviewCardType cardType,
  }) {
    return '${deckId}_${termId}_${cardType.name}';
  }

  static String _buildReviewLogId({
    required String reviewCardId,
    required DateTime reviewedAt,
    required ReviewRating rating,
  }) {
    return '${reviewCardId}_${reviewedAt.toUtc().microsecondsSinceEpoch}_${rating.name}';
  }
}
