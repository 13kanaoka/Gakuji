import 'package:shared_preferences/shared_preferences.dart';

import 'package:gakuji/data/sync/gakuji_cloud_sync_service.dart';
import 'package:gakuji/data/sync/gakuji_user_repository.dart';

/// User-scoped preferences that belong to the local Gakuji workspace.
///
/// SQLite is authoritative. SharedPreferences is consulted only once to migrate
/// values written by older builds. Registered accounts then mirror these values
/// through the normal cloud synchronization layer.
///
/// Writes are serialized per key and exposed immediately through [_pendingValues]
/// so a screen that closes/reopens before SQLite finishes cannot momentarily
/// fall back to an older/default value.
class GakujiLocalPreferences {
  static final Map<String, String> _pendingValues = <String, String>{};
  static final Map<String, Future<void>> _writeChains =
      <String, Future<void>>{};

  static Future<bool?> loadBool(String key) async {
    final pending = _pendingValues[key];
    if (pending != null) return _parseBool(pending);

    final stored = await GakujiUserRepository.loadPreference(key);
    if (stored != null) return _parseBool(stored);

    final legacy = await SharedPreferences.getInstance();
    if (!legacy.containsKey(key)) return null;

    final value = legacy.getBool(key);
    if (value == null) return null;

    await _saveValue(key, value.toString());
    await legacy.remove(key);
    return value;
  }

  static Future<void> saveBool(String key, bool value) {
    return _saveValue(key, value.toString());
  }

  static Future<int?> loadInt(String key) async {
    final pending = _pendingValues[key];
    if (pending != null) return int.tryParse(pending);

    final stored = await GakujiUserRepository.loadPreference(key);
    if (stored != null) return int.tryParse(stored);

    final legacy = await SharedPreferences.getInstance();
    if (!legacy.containsKey(key)) return null;

    final value = legacy.getInt(key);
    if (value == null) return null;

    await _saveValue(key, value.toString());
    await legacy.remove(key);
    return value;
  }

  static Future<void> saveInt(String key, int value) {
    return _saveValue(key, value.toString());
  }

  static Future<void> _saveValue(String key, String value) {
    // This assignment happens synchronously, before the first await in the
    // queued write. Any immediate read therefore sees the user's newest choice.
    _pendingValues[key] = value;

    final previous = _writeChains[key] ?? Future<void>.value();
    final next = () async {
      try {
        await previous;
      } catch (_) {
        // A failed older write must not prevent the newest value from being
        // persisted.
      }

      await GakujiUserRepository.savePreference(
        key: key,
        value: value,
      );
      GakujiCloudSyncService.schedulePush();
    }();

    _writeChains[key] = next;

    return next.whenComplete(() {
      if (identical(_writeChains[key], next)) {
        _writeChains.remove(key);
        if (_pendingValues[key] == value) {
          _pendingValues.remove(key);
        }
      }
    });
  }

  static bool? _parseBool(String value) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
      default:
        return null;
    }
  }
}
