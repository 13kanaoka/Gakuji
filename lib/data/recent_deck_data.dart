import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:gakuji/models/deck.dart';
import 'package:gakuji/services/gakuji_user_repository.dart';

const String _legacyRecentDeckIdsPreferenceKey = 'library_recent_deck_ids_v1';

// The leading "__" keeps this out of cloud-synced preferences. Recent deck
// order is useful local UI state, but it should still be scoped to the active
// Gakuji workspace instead of leaking between signed-in users on one device.
const String _localRecentDeckIdsPreferenceKey =
    '__device_library_recent_deck_ids_v1';

final List<String> recentlyOpenedDeckIds = <String>[];

bool _recentDeckIdsLoaded = false;
Future<void>? _recentDeckIdsLoadFuture;

Future<void> loadRecentlyOpenedDeckIds() {
  if (_recentDeckIdsLoaded) return Future<void>.value();

  return _recentDeckIdsLoadFuture ??= _loadRecentlyOpenedDeckIds();
}

Future<void> _loadRecentlyOpenedDeckIds() async {
  var savedIds = <String>[];

  final localValue = await GakujiUserRepository.loadPreference(
    _localRecentDeckIdsPreferenceKey,
  );

  if (localValue != null && localValue.trim().isNotEmpty) {
    savedIds = _decodeIds(localValue);
  } else {
    // One-time migration from the old device-global SharedPreferences value.
    final prefs = await SharedPreferences.getInstance();
    final legacyIds = prefs.getStringList(_legacyRecentDeckIdsPreferenceKey) ??
        const <String>[];

    if (legacyIds.isNotEmpty) {
      savedIds = _cleanIds(legacyIds);
      await _saveLocalIds(savedIds);
      await prefs.remove(_legacyRecentDeckIdsPreferenceKey);
    }
  }

  recentlyOpenedDeckIds
    ..clear()
    ..addAll(savedIds);

  _recentDeckIdsLoaded = true;
  _recentDeckIdsLoadFuture = null;
}

Future<void> markDeckOpenedRecently(String deckId) async {
  await loadRecentlyOpenedDeckIds();

  recentlyOpenedDeckIds
    ..remove(deckId)
    ..insert(0, deckId);

  await _saveLocalIds(recentlyOpenedDeckIds);
}

Future<void> removeDecksFromRecentOrder(Iterable<String> deckIds) async {
  await loadRecentlyOpenedDeckIds();

  final idsToRemove = deckIds.toSet();
  recentlyOpenedDeckIds.removeWhere(idsToRemove.contains);

  await _saveLocalIds(recentlyOpenedDeckIds);
}

Future<void> removeDeckFromRecentOrder(String deckId) {
  return removeDecksFromRecentOrder(<String>[deckId]);
}

List<Deck> orderDecksByRecentInteraction(List<Deck> sourceDecks) {
  final originalIndexes = <String, int>{};
  final orderedDecks = List<Deck>.from(sourceDecks);

  for (var index = 0; index < orderedDecks.length; index++) {
    originalIndexes.putIfAbsent(orderedDecks[index].id, () => index);
  }

  final recentIndexes = <String, int>{};

  for (var index = 0; index < recentlyOpenedDeckIds.length; index++) {
    recentIndexes.putIfAbsent(recentlyOpenedDeckIds[index], () => index);
  }

  orderedDecks.sort((first, second) {
    final firstRecentIndex = recentIndexes[first.id];
    final secondRecentIndex = recentIndexes[second.id];

    if (firstRecentIndex != null && secondRecentIndex != null) {
      return firstRecentIndex.compareTo(secondRecentIndex);
    }

    if (firstRecentIndex != null) return -1;
    if (secondRecentIndex != null) return 1;

    final firstOriginalIndex = originalIndexes[first.id] ?? sourceDecks.length;
    final secondOriginalIndex =
        originalIndexes[second.id] ?? sourceDecks.length;

    return firstOriginalIndex.compareTo(secondOriginalIndex);
  });

  return orderedDecks;
}

/// Clears only the in-memory cache. The database copy is left intact so the
/// same account can reload it, while account switches/sign-out can clear the
/// database independently through GakujiUserDatabase.
void resetRecentlyOpenedDeckIdsCache() {
  recentlyOpenedDeckIds.clear();
  _recentDeckIdsLoaded = false;
  _recentDeckIdsLoadFuture = null;
}

Future<void> _saveLocalIds(Iterable<String> ids) async {
  final cleaned = _cleanIds(ids);
  await GakujiUserRepository.savePreference(
    key: _localRecentDeckIdsPreferenceKey,
    value: jsonEncode(cleaned),
    markDirty: false,
  );
}

List<String> _decodeIds(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <String>[];
    return _cleanIds(decoded.map((value) => value.toString()));
  } catch (_) {
    return <String>[];
  }
}

List<String> _cleanIds(Iterable<String> ids) {
  final seen = <String>{};
  final result = <String>[];

  for (final rawId in ids) {
    final id = rawId.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    result.add(id);
  }

  return result;
}
