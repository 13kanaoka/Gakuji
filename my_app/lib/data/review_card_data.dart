import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';
import '../models/review_card.dart';
import '../models/term.dart';
import '../services/gakuji_user_repository.dart';
import '../services/review_scheduler.dart';
import '../services/review_settings.dart';

const String _legacyReviewCardsStorageKey = 'review_cards';

final List<ReviewCard> reviewCards = [];
final List<ReviewLogEntry> reviewLogs = [];

Future<void> loadReviewCards() async {
  var loadedCards = await GakujiUserRepository.loadReviewCards();

  if (loadedCards.isEmpty) {
    final legacyCards = await _loadLegacyReviewCards();

    if (legacyCards.isNotEmpty) {
      await GakujiUserRepository.syncReviewCards(legacyCards);
      loadedCards = legacyCards;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyReviewCardsStorageKey);
    }
  }

  reviewCards
    ..clear()
    ..addAll(loadedCards);
}

Future<List<ReviewCard>> _loadLegacyReviewCards() async {
  final prefs = await SharedPreferences.getInstance();
  final savedCards = prefs.getString(_legacyReviewCardsStorageKey);

  if (savedCards == null || savedCards.trim().isEmpty) {
    return const [];
  }

  try {
    final decodedCards = jsonDecode(savedCards);

    if (decodedCards is! List) {
      return const [];
    }

    return decodedCards
        .whereType<Map<String, dynamic>>()
        .map(ReviewCard.fromJson)
        .where((card) => card.id.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

Future<void> saveReviewCards() async {
  await GakujiUserRepository.syncReviewCards(reviewCards);
}

Future<void> loadReviewLogs({String? reviewCardId}) async {
  final loadedLogs = await GakujiUserRepository.loadReviewLogs(
    reviewCardId: reviewCardId,
  );

  reviewLogs
    ..clear()
    ..addAll(loadedLogs);
}

Future<void> addReviewLog(ReviewLogEntry reviewLog) async {
  final existingIndex = reviewLogs.indexWhere(
    (existingLog) => existingLog.id == reviewLog.id,
  );

  if (existingIndex == -1) {
    reviewLogs.add(reviewLog);
  } else {
    reviewLogs[existingIndex] = reviewLog;
  }

  await GakujiUserRepository.saveReviewLog(reviewLog);
}

Future<void> applyReviewResult(ReviewScheduleResult result) async {
  await GakujiUserRepository.saveReviewResult(
    card: result.card,
    reviewLog: result.reviewLog,
  );

  final cardIndex = reviewCards.indexWhere(
    (card) => card.id == result.card.id,
  );

  if (cardIndex == -1) {
    reviewCards.add(result.card);
  } else {
    reviewCards[cardIndex] = result.card;
  }

  final logIndex = reviewLogs.indexWhere(
    (log) => log.id == result.reviewLog.id,
  );

  if (logIndex == -1) {
    reviewLogs.add(result.reviewLog);
  } else {
    reviewLogs[logIndex] = result.reviewLog;
  }
}

List<ReviewCard> getReviewCardsForDeck(String deckId) {
  return reviewCards.where((card) => card.deckId == deckId).toList();
}

List<ReviewCard> getDueReviewCardsForDeck(
  String deckId, {
  DateTime? now,
}) {
  return ReviewScheduler.dueCardsForDeck(
    reviewCards,
    deckId,
    now: now,
  );
}


Future<List<ReviewCard>> getLimitedReviewCardsForDeck(
  String deckId, {
  DateTime? now,
  bool includeShortIntervalCards = false,
}) async {
  final checkTime = now ?? DateTime.now();
  final settings = await ReviewSettingsStore.load();
  final newCardsStartedToday =
      await ReviewSettingsStore.newCardsStartedToday(now: checkTime);
  final reviewsCompletedToday =
      await ReviewSettingsStore.reviewsCompletedToday(now: checkTime);

  final availableNew =
      (settings.newLimit - newCardsStartedToday).clamp(0, 9999).toInt();
  final availableReview =
      (settings.reviewLimit - reviewsCompletedToday).clamp(0, 9999).toInt();
  final cutoff = includeShortIntervalCards
      ? checkTime.add(const Duration(minutes: 10))
      : checkTime;

  final deckCards = getReviewCardsForDeck(deckId);

  // New cards are controlled by how many unseen cards have actually
  // been started today. Existing Learning/Relearning cards never consume
  // additional New capacity and remain eligible whenever they are due.
  final newCards = deckCards
      .where((card) => card.state == ReviewCardState.newCard)
      .take(availableNew)
      .toList();

  final learningCards = deckCards.where((card) {
    final isLearning = card.state == ReviewCardState.learning ||
        card.state == ReviewCardState.relearning;

    return isLearning && !card.dueDate.isAfter(cutoff);
  }).toList();

  final dueReviewCards = deckCards
      .where((card) {
        return card.state == ReviewCardState.review &&
            !card.dueDate.isAfter(cutoff);
      })
      .take(availableReview)
      .toList();

  return [
    ...learningCards,
    ...dueReviewCards,
    ...newCards,
  ];
}

ReviewCard? getReviewCardById(String reviewCardId) {
  try {
    return reviewCards.firstWhere((card) => card.id == reviewCardId);
  } catch (_) {
    return null;
  }
}

bool reviewCardExists({
  required String deckId,
  required String termId,
  required ReviewCardType cardType,
}) {
  final expectedId = '${deckId}_${termId}_${cardType.name}';

  return reviewCards.any((card) => card.id == expectedId);
}

Future<void> addReviewCard(ReviewCard card) async {
  final existingIndex = reviewCards.indexWhere(
    (existingCard) => existingCard.id == card.id,
  );

  if (existingIndex == -1) {
    reviewCards.add(card);
  } else {
    reviewCards[existingIndex] = card;
  }

  await GakujiUserRepository.saveReviewCard(card);
}

Future<void> updateReviewCard(ReviewCard updatedCard) async {
  final index = reviewCards.indexWhere(
    (card) => card.id == updatedCard.id,
  );

  if (index == -1) {
    reviewCards.add(updatedCard);
  } else {
    reviewCards[index] = updatedCard;
  }

  await GakujiUserRepository.saveReviewCard(updatedCard);
}

Future<void> createReviewCardsForDeck(Deck deck) async {
  final expectedCards = _expectedReviewCardsForDeck(deck);
  final expectedIds = expectedCards.map((card) => card.id).toSet();
  var changed = false;

  final obsoleteIds = reviewCards
      .where((card) => card.deckId == deck.id)
      .where((card) => !expectedIds.contains(card.id))
      .map((card) => card.id)
      .toSet();

  if (obsoleteIds.isNotEmpty) {
    reviewCards.removeWhere((card) => obsoleteIds.contains(card.id));
    changed = true;
  }

  for (final expectedCard in expectedCards) {
    final exists = reviewCards.any((card) => card.id == expectedCard.id);

    if (exists) continue;

    reviewCards.add(
      ReviewScheduler.createReviewCard(
        deckId: expectedCard.deckId,
        termId: expectedCard.termId,
        cardType: expectedCard.cardType,
      ),
    );

    changed = true;
  }

  await GakujiUserRepository.deleteReviewCardsNotInForDeck(
    deckId: deck.id,
    retainedReviewCardIds: expectedIds,
  );

  if (changed) {
    await saveReviewCards();
  }
}

List<_ExpectedReviewCard> _expectedReviewCardsForDeck(Deck deck) {
  final expected = <_ExpectedReviewCard>[];

  for (final term in deck.terms) {
    final termId = _reviewTermId(term);

    switch (deck.type) {
      case DeckType.reading:
        expected.add(
          _ExpectedReviewCard(
            deckId: deck.id,
            termId: termId,
            cardType: ReviewCardType.reading,
          ),
        );
        break;

      case DeckType.writing:
        expected.add(
          _ExpectedReviewCard(
            deckId: deck.id,
            termId: termId,
            cardType: ReviewCardType.writing,
          ),
        );
        break;

      case DeckType.hybrid:
        final mode = deck.cardModeFor(term);

        if (mode == HybridCardMode.reading || mode == HybridCardMode.both) {
          expected.add(
            _ExpectedReviewCard(
              deckId: deck.id,
              termId: termId,
              cardType: ReviewCardType.reading,
            ),
          );
        }

        if (mode == HybridCardMode.writing || mode == HybridCardMode.both) {
          expected.add(
            _ExpectedReviewCard(
              deckId: deck.id,
              termId: termId,
              cardType: ReviewCardType.writing,
            ),
          );
        }
        break;
    }
  }

  return expected;
}

String _reviewTermId(Term term) {
  return term.sourceId ?? term.id;
}

class _ExpectedReviewCard {
  final String deckId;
  final String termId;
  final ReviewCardType cardType;

  const _ExpectedReviewCard({
    required this.deckId,
    required this.termId,
    required this.cardType,
  });

  String get id => '${deckId}_${termId}_${cardType.name}';
}
