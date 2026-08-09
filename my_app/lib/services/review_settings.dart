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
  static const String _reviewUsageDateKey = 'review_usage_date';
  static const String _reviewUsageCountKey = 'review_usage_count';
  static const String _newUsageDateKey = 'review_new_usage_date';
  static const String _newUsageCountKey = 'review_new_usage_count';

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

  static Future<int> newCardsStartedToday({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dateKey(now ?? DateTime.now());
    final savedDate = prefs.getString(_newUsageDateKey);

    if (savedDate != todayKey) {
      await Future.wait([
        prefs.setString(_newUsageDateKey, todayKey),
        prefs.setInt(_newUsageCountKey, 0),
      ]);
      return 0;
    }

    return prefs.getInt(_newUsageCountKey) ?? 0;
  }

  static Future<void> recordStartedNewCard({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dateKey(now ?? DateTime.now());
    final savedDate = prefs.getString(_newUsageDateKey);

    if (savedDate != todayKey) {
      await Future.wait([
        prefs.setString(_newUsageDateKey, todayKey),
        prefs.setInt(_newUsageCountKey, 1),
      ]);
      return;
    }

    final currentCount = prefs.getInt(_newUsageCountKey) ?? 0;
    await prefs.setInt(
      _newUsageCountKey,
      (currentCount + 1).clamp(0, 9999).toInt(),
    );
  }

  static Future<int> reviewsCompletedToday({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dateKey(now ?? DateTime.now());
    final savedDate = prefs.getString(_reviewUsageDateKey);

    if (savedDate != todayKey) {
      await Future.wait([
        prefs.setString(_reviewUsageDateKey, todayKey),
        prefs.setInt(_reviewUsageCountKey, 0),
      ]);
      return 0;
    }

    return prefs.getInt(_reviewUsageCountKey) ?? 0;
  }

  static Future<void> recordCompletedReview({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dateKey(now ?? DateTime.now());
    final savedDate = prefs.getString(_reviewUsageDateKey);

    if (savedDate != todayKey) {
      await Future.wait([
        prefs.setString(_reviewUsageDateKey, todayKey),
        prefs.setInt(_reviewUsageCountKey, 1),
      ]);
      return;
    }

    final currentCount = prefs.getInt(_reviewUsageCountKey) ?? 0;
    await prefs.setInt(_reviewUsageCountKey, currentCount + 1);
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
