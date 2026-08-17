import 'package:shared_preferences/shared_preferences.dart';

const String _recentDeckIdsPreferenceKey = 'library_recent_deck_ids_v1';

final List<String> recentlyOpenedDeckIds = <String>[];

bool _recentDeckIdsLoaded = false;
Future<void>? _recentDeckIdsLoadFuture;

Future<void> loadRecentlyOpenedDeckIds() {
  if (_recentDeckIdsLoaded) return Future<void>.value();

  return _recentDeckIdsLoadFuture ??= _loadRecentlyOpenedDeckIds();
}

Future<void> _loadRecentlyOpenedDeckIds() async {
  final prefs = await SharedPreferences.getInstance();
  final savedIds = prefs.getStringList(_recentDeckIdsPreferenceKey) ??
      const <String>[];

  recentlyOpenedDeckIds
    ..clear()
    ..addAll(savedIds);

  _recentDeckIdsLoaded = true;
}

Future<void> markDeckOpenedRecently(String deckId) async {
  await loadRecentlyOpenedDeckIds();

  recentlyOpenedDeckIds
    ..remove(deckId)
    ..insert(0, deckId);

  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(
    _recentDeckIdsPreferenceKey,
    recentlyOpenedDeckIds,
  );
}

Future<void> removeDecksFromRecentOrder(Iterable<String> deckIds) async {
  await loadRecentlyOpenedDeckIds();

  final idsToRemove = deckIds.toSet();
  recentlyOpenedDeckIds.removeWhere(idsToRemove.contains);

  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(
    _recentDeckIdsPreferenceKey,
    recentlyOpenedDeckIds,
  );
}

Future<void> removeDeckFromRecentOrder(String deckId) {
  return removeDecksFromRecentOrder(<String>[deckId]);
}
