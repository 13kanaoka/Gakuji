import 'package:shared_preferences/shared_preferences.dart';

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
}