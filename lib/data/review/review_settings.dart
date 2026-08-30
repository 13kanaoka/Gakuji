import 'package:shared_preferences/shared_preferences.dart';

class ReviewSettings {
  final int newLimit;
  final int reviewLimit;

  const ReviewSettings({
    required this.newLimit,
    required this.reviewLimit,
  });

  static const ReviewSettings defaults = ReviewSettings(
    newLimit: 30,
    reviewLimit: 200,
  );

  ReviewSettings copyWith({
    int? newLimit,
    int? reviewLimit,
  }) {
    return ReviewSettings(
      newLimit: newLimit ?? this.newLimit,
      reviewLimit: reviewLimit ?? this.reviewLimit,
    );
  }
}

class ReviewSettingsStore {
  static const String _newLimitKey = 'review_new_limit';
  static const String _reviewLimitKey = 'review_review_limit';
  static const String _reviewUsageDateKeyPrefix = 'review_usage_date_';
  static const String _reviewUsageCountKeyPrefix = 'review_usage_count_';
  static const String _newUsageDateKeyPrefix = 'review_new_usage_date_';
  static const String _newUsageCountKeyPrefix = 'review_new_usage_count_';

  static Future<ReviewSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    return ReviewSettings(
      newLimit: _sanitizeLimit(
        prefs.getInt(_newLimitKey),
        ReviewSettings.defaults.newLimit,
      ),
      reviewLimit: _sanitizeLimit(
        prefs.getInt(_reviewLimitKey),
        ReviewSettings.defaults.reviewLimit,
      ),
    );
  }

  static Future<void> save(ReviewSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await Future.wait([
      prefs.setInt(_newLimitKey, _sanitizeLimit(settings.newLimit, 0)),
      prefs.setInt(_reviewLimitKey, _sanitizeLimit(settings.reviewLimit, 0)),
    ]);
  }

  static Future<int> newCardsStartedToday({
    required String deckId,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dateKey(now ?? DateTime.now());
    final dateKey = _deckUsageKey(_newUsageDateKeyPrefix, deckId);
    final countKey = _deckUsageKey(_newUsageCountKeyPrefix, deckId);
    final savedDate = prefs.getString(dateKey);

    if (savedDate != todayKey) {
      await Future.wait([
        prefs.setString(dateKey, todayKey),
        prefs.setInt(countKey, 0),
      ]);
      return 0;
    }

    return prefs.getInt(countKey) ?? 0;
  }

  static Future<void> recordStartedNewCard({
    required String deckId,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dateKey(now ?? DateTime.now());
    final dateKey = _deckUsageKey(_newUsageDateKeyPrefix, deckId);
    final countKey = _deckUsageKey(_newUsageCountKeyPrefix, deckId);
    final savedDate = prefs.getString(dateKey);

    if (savedDate != todayKey) {
      await Future.wait([
        prefs.setString(dateKey, todayKey),
        prefs.setInt(countKey, 1),
      ]);
      return;
    }

    final currentCount = prefs.getInt(countKey) ?? 0;
    await prefs.setInt(
      countKey,
      (currentCount + 1).clamp(0, 9999).toInt(),
    );
  }

  static Future<int> reviewsCompletedToday({
    required String deckId,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dateKey(now ?? DateTime.now());
    final dateKey = _deckUsageKey(_reviewUsageDateKeyPrefix, deckId);
    final countKey = _deckUsageKey(_reviewUsageCountKeyPrefix, deckId);
    final savedDate = prefs.getString(dateKey);

    if (savedDate != todayKey) {
      await Future.wait([
        prefs.setString(dateKey, todayKey),
        prefs.setInt(countKey, 0),
      ]);
      return 0;
    }

    return prefs.getInt(countKey) ?? 0;
  }

  static Future<void> recordCompletedReview({
    required String deckId,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dateKey(now ?? DateTime.now());
    final dateKey = _deckUsageKey(_reviewUsageDateKeyPrefix, deckId);
    final countKey = _deckUsageKey(_reviewUsageCountKeyPrefix, deckId);
    final savedDate = prefs.getString(dateKey);

    if (savedDate != todayKey) {
      await Future.wait([
        prefs.setString(dateKey, todayKey),
        prefs.setInt(countKey, 1),
      ]);
      return;
    }

    final currentCount = prefs.getInt(countKey) ?? 0;
    await prefs.setInt(
      countKey,
      (currentCount + 1).clamp(0, 9999).toInt(),
    );
  }

  static String _deckUsageKey(String prefix, String deckId) {
    return '$prefix$deckId';
  }

  static int _sanitizeLimit(int? value, int fallback) {
    if (value == null) return fallback;
    return value.clamp(0, 9999).toInt();
  }

  static String _dateKey(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}
