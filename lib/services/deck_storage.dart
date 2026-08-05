import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';

class DeckStorage {
  /// 💾 SAVE STUDY POSITION
  static Future<void> saveProgress(String deckName, int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${deckName}_progress', index);
  }

  /// 📥 LOAD STUDY POSITION
  static Future<int> loadProgress(String deckName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('${deckName}_progress') ?? 0;
  }

  /// 🔀 SAVE SHUFFLE STATE
  static Future<void> saveShuffle(String deckName, bool isShuffled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${deckName}_shuffle', isShuffled);
  }

  /// 📥 LOAD SHUFFLE STATE
  static Future<bool> loadShuffle(String deckName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('${deckName}_shuffle') ?? false;
  }

  /// 🧠 SAVE WHETHER REVIEW HAS BEEN ENABLED
  static Future<void> saveReviewEnabled(
    String deckName,
    bool reviewEnabled,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${deckName}_review_enabled', reviewEnabled);
  }

  /// 📥 LOAD WHETHER REVIEW HAS BEEN ENABLED
  static Future<bool> loadReviewEnabled(String deckName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('${deckName}_review_enabled') ?? false;
  }

  /// 🔁 SAVE ACTIVE STUDY MODE
  static Future<void> saveActiveStudyMode(
    String deckName,
    StudyMode activeStudyMode,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${deckName}_active_study_mode',
      activeStudyMode.name,
    );
  }

  /// 📥 LOAD ACTIVE STUDY MODE
  static Future<StudyMode> loadActiveStudyMode(String deckName) async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('${deckName}_active_study_mode');

    switch (savedMode) {
      case 'review':
        return StudyMode.review;
      case 'study':
      default:
        return StudyMode.study;
    }
  }

  /// 📅 SAVE WHEN REVIEW WAS FIRST ENABLED
  static Future<void> saveReviewEnabledAt(
    String deckName,
    DateTime reviewEnabledAt,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${deckName}_review_enabled_at',
      reviewEnabledAt.toIso8601String(),
    );
  }

  /// 📥 LOAD WHEN REVIEW WAS FIRST ENABLED
  static Future<DateTime?> loadReviewEnabledAt(String deckName) async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('${deckName}_review_enabled_at');

    if (savedDate == null) {
      return null;
    }

    return DateTime.tryParse(savedDate);
  }
}