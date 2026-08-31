import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:gakuji/data/sync/gakuji_user_database.dart';

/// Local-only persistence for resumable study and game sessions.
///
/// Session snapshots live in the user-scoped SQLite metadata table so they
/// survive page/app restarts without becoming part of the Firestore sync
/// payload. A small in-memory cache makes same-process resumes immediate, while
/// writes are coalesced so rapid gameplay only persists the newest snapshot.
class GakujiSessionStorage {
  static const String _keyPrefix = 'gakuji_runtime_session_v1';

  static const int _maxRuntimeCacheEntries = 12;

  static final Map<String, Map<String, dynamic>?> _runtimeCache =
      <String, Map<String, dynamic>?>{};
  static final Map<String, Map<String, dynamic>?> _pendingSnapshots =
      <String, Map<String, dynamic>?>{};
  static final Map<String, List<Completer<void>>> _pendingWaiters =
      <String, List<Completer<void>>>{};
  static final Map<String, Future<void>> _writeWorkers =
      <String, Future<void>>{};

  static String _key({
    required String sessionType,
    required String deckId,
  }) {
    return '$_keyPrefix:$sessionType:$deckId';
  }

  static String _runtimeKey({
    required String sessionType,
    required String deckId,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'signed_out';
    final signInMarker =
        user?.metadata.lastSignInTime?.millisecondsSinceEpoch ?? 0;
    return '$uid:$signInMarker:${_key(sessionType: sessionType, deckId: deckId)}';
  }

  // Full Fusion round blueprints can be large. They stay persisted in SQLite,
  // but are deliberately not retained in the process-wide RAM cache. The game
  // page turns a blueprint into its typed round objects and then lets the JSON
  // snapshot be collected.
  static bool _shouldCacheSessionType(String sessionType) {
    return !sessionType.endsWith('_rounds');
  }

  static void _purgeUncacheableRuntimeEntries() {
    final marker = '$_keyPrefix:';
    _runtimeCache.removeWhere((runtimeKey, _) {
      final markerIndex = runtimeKey.indexOf(marker);
      if (markerIndex == -1) return false;

      final remainder = runtimeKey.substring(markerIndex + marker.length);
      final separatorIndex = remainder.indexOf(':');
      if (separatorIndex == -1) return false;

      final sessionType = remainder.substring(0, separatorIndex);
      return !_shouldCacheSessionType(sessionType);
    });
  }

  static void _cacheRuntimeValue(
    String runtimeKey,
    Map<String, dynamic>? value,
  ) {
    // Reinsert existing keys so frequently-used sessions stay near the end of
    // the insertion-ordered map and older deck sessions are evicted first.
    _runtimeCache.remove(runtimeKey);
    _runtimeCache[runtimeKey] = value;

    while (_runtimeCache.length > _maxRuntimeCacheEntries) {
      _runtimeCache.remove(_runtimeCache.keys.first);
    }
  }

  /// Whether this session has already been resolved during the current app
  /// process. A cached null means we already know there is no saved session.
  static bool hasCached({
    required String sessionType,
    required String deckId,
  }) {
    _purgeUncacheableRuntimeEntries();
    if (!_shouldCacheSessionType(sessionType)) return false;

    return _runtimeCache.containsKey(
      _runtimeKey(sessionType: sessionType, deckId: deckId),
    );
  }

  /// Synchronous same-process lookup used to avoid showing a loading frame when
  /// returning to a session that was already loaded or saved in this process.
  static Map<String, dynamic>? peek({
    required String sessionType,
    required String deckId,
  }) {
    _purgeUncacheableRuntimeEntries();
    if (!_shouldCacheSessionType(sessionType)) return null;

    final runtimeKey = _runtimeKey(
      sessionType: sessionType,
      deckId: deckId,
    );
    final cached = _runtimeCache[runtimeKey];
    if (cached == null) return null;

    _cacheRuntimeValue(runtimeKey, cached);
    return Map<String, dynamic>.from(cached);
  }

  static Map<String, dynamic>? _decodeSnapshot(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } catch (_) {
      return null;
    }
  }

  /// Loads several session records for one deck with a single SQLite query.
  /// Cached records are returned immediately and excluded from the database
  /// lookup.
  static Future<Map<String, Map<String, dynamic>?>> loadMany({
    required List<String> sessionTypes,
    required String deckId,
  }) async {
    _purgeUncacheableRuntimeEntries();
    final result = <String, Map<String, dynamic>?>{};
    final uncachedTypes = <String>[];

    for (final sessionType in sessionTypes) {
      final runtimeKey = _runtimeKey(
        sessionType: sessionType,
        deckId: deckId,
      );
      if (_shouldCacheSessionType(sessionType) &&
          _runtimeCache.containsKey(runtimeKey)) {
        final cached = _runtimeCache[runtimeKey];
        _cacheRuntimeValue(runtimeKey, cached);
        result[sessionType] =
            cached == null ? null : Map<String, dynamic>.from(cached);
      } else {
        uncachedTypes.add(sessionType);
      }
    }

    if (uncachedTypes.isEmpty) return result;

    final keys = uncachedTypes
        .map((sessionType) => _key(sessionType: sessionType, deckId: deckId))
        .toList(growable: false);
    final placeholders = List.filled(keys.length, '?').join(', ');
    final database = await GakujiUserDatabase.database;
    final rows = await database.query(
      'app_metadata',
      columns: ['key', 'value'],
      where: 'key IN ($placeholders)',
      whereArgs: keys,
    );
    final rawByKey = <String, String>{
      for (final row in rows)
        if (row['key'] != null && row['value'] != null)
          row['key'].toString(): row['value'].toString(),
    };

    for (var index = 0; index < uncachedTypes.length; index++) {
      final sessionType = uncachedTypes[index];
      final snapshot = _decodeSnapshot(rawByKey[keys[index]]);
      final runtimeKey = _runtimeKey(
        sessionType: sessionType,
        deckId: deckId,
      );
      if (_shouldCacheSessionType(sessionType)) {
        _cacheRuntimeValue(runtimeKey, snapshot);
      } else {
        _runtimeCache.remove(runtimeKey);
      }
      result[sessionType] =
          snapshot == null ? null : Map<String, dynamic>.from(snapshot);
    }

    return result;
  }

  static Future<Map<String, dynamic>?> load({
    required String sessionType,
    required String deckId,
  }) async {
    _purgeUncacheableRuntimeEntries();
    final runtimeKey = _runtimeKey(
      sessionType: sessionType,
      deckId: deckId,
    );

    if (_shouldCacheSessionType(sessionType) &&
        _runtimeCache.containsKey(runtimeKey)) {
      final cached = _runtimeCache[runtimeKey];
      _cacheRuntimeValue(runtimeKey, cached);
      return cached == null ? null : Map<String, dynamic>.from(cached);
    }

    final key = _key(sessionType: sessionType, deckId: deckId);
    final raw = await GakujiUserDatabase.readMetadata(key);

    final snapshot = _decodeSnapshot(raw);
    if (_shouldCacheSessionType(sessionType)) {
      _cacheRuntimeValue(runtimeKey, snapshot);
    } else {
      _runtimeCache.remove(runtimeKey);
    }
    return snapshot == null ? null : Map<String, dynamic>.from(snapshot);
  }

  static Future<void> save({
    required String sessionType,
    required String deckId,
    required Map<String, dynamic> snapshot,
  }) {
    _purgeUncacheableRuntimeEntries();
    final runtimeKey = _runtimeKey(
      sessionType: sessionType,
      deckId: deckId,
    );
    final shouldCache = _shouldCacheSessionType(sessionType);
    final storedSnapshot = shouldCache ? _copySnapshot(snapshot) : snapshot;

    if (shouldCache) {
      _cacheRuntimeValue(runtimeKey, storedSnapshot);
    } else {
      // Avoid keeping a second deep-copied representation of a potentially
      // large round blueprint alive for the rest of the app process.
      _runtimeCache.remove(runtimeKey);
    }

    return _queueWrite(
      key: _key(sessionType: sessionType, deckId: deckId),
      snapshot: storedSnapshot,
    );
  }

  static Future<void> clear({
    required String sessionType,
    required String deckId,
  }) {
    _purgeUncacheableRuntimeEntries();
    final runtimeKey = _runtimeKey(
      sessionType: sessionType,
      deckId: deckId,
    );
    if (_shouldCacheSessionType(sessionType)) {
      _cacheRuntimeValue(runtimeKey, null);
    } else {
      _runtimeCache.remove(runtimeKey);
    }

    return _queueWrite(
      key: _key(sessionType: sessionType, deckId: deckId),
      snapshot: null,
    );
  }

  static Map<String, dynamic> _copySnapshot(Map<String, dynamic> snapshot) {
    return <String, dynamic>{
      for (final entry in snapshot.entries)
        entry.key: _copyJsonValue(entry.value),
    };
  }

  static dynamic _copyJsonValue(dynamic value) {
    if (value is List) {
      return value.map(_copyJsonValue).toList(growable: false);
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _copyJsonValue(entry.value),
      };
    }
    return value;
  }

  /// Keeps at most one waiting snapshot behind the currently executing write.
  /// If several saves happen while SQLite is busy, only the newest one is
  /// written next; callers waiting on superseded saves complete when that newer
  /// snapshot is safely persisted.
  static Future<void> _queueWrite({
    required String key,
    required Map<String, dynamic>? snapshot,
  }) {
    _pendingSnapshots[key] = snapshot;

    final completer = Completer<void>();
    _pendingWaiters.putIfAbsent(key, () => <Completer<void>>[]).add(completer);

    _writeWorkers.putIfAbsent(key, () => _drainWrites(key));
    return completer.future;
  }

  static Future<void> _drainWrites(String key) async {
    try {
      while (_pendingSnapshots.containsKey(key)) {
        // Give same-event-loop updates a chance to collapse into one snapshot.
        await Future<void>.delayed(const Duration(milliseconds: 12));

        final snapshot = _pendingSnapshots.remove(key);
        final waiters = List<Completer<void>>.from(
          _pendingWaiters[key] ?? const <Completer<void>>[],
        );
        _pendingWaiters[key]?.clear();

        try {
          if (snapshot == null) {
            await GakujiUserDatabase.deleteMetadata(key);
          } else {
            await GakujiUserDatabase.writeMetadata(
              key,
              jsonEncode(snapshot),
            );
          }

          for (final waiter in waiters) {
            if (!waiter.isCompleted) waiter.complete();
          }
        } catch (error, stackTrace) {
          for (final waiter in waiters) {
            if (!waiter.isCompleted) {
              waiter.completeError(error, stackTrace);
            }
          }
        }
      }
    } finally {
      _writeWorkers.remove(key);

      // A save can arrive between the loop's final containsKey check and the
      // worker removal. Restart the worker if that race occurred.
      if (_pendingSnapshots.containsKey(key)) {
        _writeWorkers.putIfAbsent(key, () => _drainWrites(key));
      }
    }
  }
}
