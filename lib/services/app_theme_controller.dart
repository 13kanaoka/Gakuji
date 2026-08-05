import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  static const String _storageKey = 'gakuji_theme_mode';

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode _savedThemeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  ThemeMode get savedThemeMode => _savedThemeMode;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedValue = preferences.getString(_storageKey);
    final loadedMode = _normalizeThemeModeName(savedValue);

    _savedThemeMode = loadedMode;
    _themeMode = loadedMode;
  }

  void previewThemeMode(ThemeMode value) {
    final normalizedValue = _normalizeThemeMode(value);

    if (_themeMode == normalizedValue) return;

    _themeMode = normalizedValue;
    notifyListeners();
  }

  Future<void> saveThemeMode(ThemeMode value) async {
    final normalizedValue = _normalizeThemeMode(value);

    // Apply the theme before waiting for disk persistence so the interface
    // responds immediately when Save is pressed.
    previewThemeMode(normalizedValue);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, normalizedValue.name);

    _savedThemeMode = normalizedValue;
  }

  Future<void> setThemeMode(ThemeMode value) {
    return saveThemeMode(value);
  }

  void discardThemePreview() {
    previewThemeMode(_savedThemeMode);
  }

  ThemeMode _normalizeThemeMode(ThemeMode value) {
    return value == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
  }

  ThemeMode _normalizeThemeModeName(String? value) {
    return value == ThemeMode.dark.name
        ? ThemeMode.dark
        : ThemeMode.light;
  }
}

final AppThemeController appThemeController = AppThemeController();
