enum ReviewCardType {
  reading,
  writing,
}

enum ReviewCardState {
  newCard,
  learning,
  review,
  relearning,
}

enum ReviewRating {
  again,
  hard,
  good,
  easy,
}

const Object _reviewCardCopyUnset = Object();

class ReviewCard {
  final String id;

  /// The deck this review card belongs to.
  final String deckId;

  /// The dictionary term this review card points to.
  final String termId;

  /// Whether this is a reading card or writing card.
  final ReviewCardType cardType;

  /// New, learning, review, or relearning.
  final ReviewCardState state;

  /// The next date this card should appear in Review mode.
  final DateTime dueDate;

  /// Current interval in days.
  ///
  /// Retained for compatibility with Gakuji 2.0 review data. FSRS uses the
  /// serialized state stored in [fsrsCard] as the scheduling authority.
  final int intervalDays;

  /// Legacy Gakuji 2.0 ease factor.
  final double easeFactor;

  /// Legacy Gakuji 2.0 successful-review count.
  final int repetitions;

  /// Number of times this card was forgotten after entering Review.
  final int lapses;

  /// Last time this card was reviewed through Review mode.
  final DateTime? lastReviewedAt;

  /// Serialized `fsrs.Card.toMap()` data.
  ///
  /// This remains nullable while existing Gakuji 2.0 cards are migrated.
  /// Once a card has been reviewed by the FSRS scheduler, this map becomes the
  /// source of truth for its memory state.
  final Map<String, dynamic>? fsrsCard;

  const ReviewCard({
    required this.id,
    required this.deckId,
    required this.termId,
    required this.cardType,
    this.state = ReviewCardState.newCard,
    required this.dueDate,
    this.intervalDays = 0,
    this.easeFactor = 2.5,
    this.repetitions = 0,
    this.lapses = 0,
    this.lastReviewedAt,
    this.fsrsCard,
  });

  bool get hasFsrsState => fsrsCard != null && fsrsCard!.isNotEmpty;

  factory ReviewCard.fromJson(Map<String, dynamic> json) {
    return ReviewCard(
      id: json['id']?.toString() ?? '',
      deckId: json['deckId']?.toString() ?? '',
      termId: json['termId']?.toString() ?? '',
      cardType: _reviewCardTypeFromString(
        json['cardType']?.toString(),
      ),
      state: _reviewCardStateFromString(
        json['state']?.toString(),
      ),
      dueDate: _dateTimeFromString(
        json['dueDate']?.toString(),
      ),
      intervalDays: _intFromValue(json['intervalDays']),
      easeFactor: _doubleFromValue(
        json['easeFactor'],
        fallback: 2.5,
      ),
      repetitions: _intFromValue(json['repetitions']),
      lapses: _intFromValue(json['lapses']),
      lastReviewedAt: _nullableDateTimeFromString(
        json['lastReviewedAt']?.toString(),
      ),
      fsrsCard: _mapFromValue(json['fsrsCard']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deckId': deckId,
      'termId': termId,
      'cardType': cardType.name,
      'state': state.name,
      'dueDate': dueDate.toUtc().toIso8601String(),
      'intervalDays': intervalDays,
      'easeFactor': easeFactor,
      'repetitions': repetitions,
      'lapses': lapses,
      if (lastReviewedAt != null)
        'lastReviewedAt': lastReviewedAt!.toUtc().toIso8601String(),
      if (fsrsCard != null) 'fsrsCard': fsrsCard,
    };
  }

  ReviewCard copyWith({
    String? id,
    String? deckId,
    String? termId,
    ReviewCardType? cardType,
    ReviewCardState? state,
    DateTime? dueDate,
    int? intervalDays,
    double? easeFactor,
    int? repetitions,
    int? lapses,
    Object? lastReviewedAt = _reviewCardCopyUnset,
    Object? fsrsCard = _reviewCardCopyUnset,
  }) {
    final nextLastReviewedAt =
        identical(lastReviewedAt, _reviewCardCopyUnset)
            ? this.lastReviewedAt
            : lastReviewedAt as DateTime?;

    final nextFsrsCard = identical(fsrsCard, _reviewCardCopyUnset)
        ? this.fsrsCard
        : fsrsCard == null
            ? null
            : Map<String, dynamic>.from(fsrsCard as Map);

    return ReviewCard(
      id: id ?? this.id,
      deckId: deckId ?? this.deckId,
      termId: termId ?? this.termId,
      cardType: cardType ?? this.cardType,
      state: state ?? this.state,
      dueDate: dueDate ?? this.dueDate,
      intervalDays: intervalDays ?? this.intervalDays,
      easeFactor: easeFactor ?? this.easeFactor,
      repetitions: repetitions ?? this.repetitions,
      lapses: lapses ?? this.lapses,
      lastReviewedAt: nextLastReviewedAt,
      fsrsCard: nextFsrsCard,
    );
  }

  bool isDue(DateTime now) {
    final checkTime = now.toUtc();
    final dueTime = dueDate.toUtc();

    return dueTime.isBefore(checkTime) || dueTime.isAtSameMomentAs(checkTime);
  }

  @override
  String toString() {
    return 'ReviewCard(id: $id, deckId: $deckId, termId: $termId, '
        'cardType: $cardType, state: $state, dueDate: $dueDate, '
        'intervalDays: $intervalDays, easeFactor: $easeFactor, '
        'repetitions: $repetitions, lapses: $lapses, '
        'lastReviewedAt: $lastReviewedAt, hasFsrsState: $hasFsrsState)';
  }
}

class ReviewLogEntry {
  final String id;
  final String reviewCardId;
  final ReviewRating rating;
  final DateTime reviewedAt;

  /// Serialized `fsrs.ReviewLog.toMap()` data.
  final Map<String, dynamic> fsrsLog;

  const ReviewLogEntry({
    required this.id,
    required this.reviewCardId,
    required this.rating,
    required this.reviewedAt,
    required this.fsrsLog,
  });

  factory ReviewLogEntry.fromJson(Map<String, dynamic> json) {
    return ReviewLogEntry(
      id: json['id']?.toString() ?? '',
      reviewCardId: json['reviewCardId']?.toString() ?? '',
      rating: _reviewRatingFromValue(json['rating']),
      reviewedAt: _dateTimeFromString(
        json['reviewedAt']?.toString(),
      ),
      fsrsLog: _mapFromValue(json['fsrsLog']) ?? const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reviewCardId': reviewCardId,
      'rating': rating.index + 1,
      'reviewedAt': reviewedAt.toUtc().toIso8601String(),
      'fsrsLog': fsrsLog,
    };
  }
}

ReviewCardType _reviewCardTypeFromString(String? value) {
  switch (value) {
    case 'writing':
      return ReviewCardType.writing;
    case 'reading':
    default:
      return ReviewCardType.reading;
  }
}

ReviewCardState _reviewCardStateFromString(String? value) {
  switch (value) {
    case 'learning':
      return ReviewCardState.learning;
    case 'review':
      return ReviewCardState.review;
    case 'relearning':
      return ReviewCardState.relearning;
    case 'newCard':
    default:
      return ReviewCardState.newCard;
  }
}

ReviewRating _reviewRatingFromValue(dynamic value) {
  final numericValue = _intFromValue(value, fallback: 3);

  switch (numericValue) {
    case 1:
      return ReviewRating.again;
    case 2:
      return ReviewRating.hard;
    case 4:
      return ReviewRating.easy;
    case 3:
    default:
      return ReviewRating.good;
  }
}

DateTime _dateTimeFromString(String? value) {
  if (value == null || value.trim().isEmpty) {
    return DateTime.now().toUtc();
  }

  return (DateTime.tryParse(value) ?? DateTime.now()).toUtc();
}

DateTime? _nullableDateTimeFromString(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  return DateTime.tryParse(value)?.toUtc();
}

Map<String, dynamic>? _mapFromValue(dynamic value) {
  if (value is! Map) return null;

  return Map<String, dynamic>.from(value);
}

int _intFromValue(dynamic value, {int fallback = 0}) {
  if (value == null) {
    return fallback;
  }

  if (value is int) {
    return value;
  }

  return int.tryParse(value.toString()) ?? fallback;
}

double _doubleFromValue(dynamic value, {double fallback = 0}) {
  if (value == null) {
    return fallback;
  }

  if (value is double) {
    return value;
  }

  if (value is int) {
    return value.toDouble();
  }

  return double.tryParse(value.toString()) ?? fallback;
}
