import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GakujiTextSize {
  small,
  medium,
  large,
}

class AppThemeController extends ChangeNotifier {
  static const String _storageKey = 'gakuji_theme_mode';
  static const String _textSizeStorageKey = 'gakuji_text_size';

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode _savedThemeMode = ThemeMode.light;
  GakujiTextSize _textSize = GakujiTextSize.small;
  GakujiTextSize _savedTextSize = GakujiTextSize.small;

  ThemeMode get themeMode => _themeMode;
  ThemeMode get savedThemeMode => _savedThemeMode;
  GakujiTextSize get textSize => _textSize;
  GakujiTextSize get savedTextSize => _savedTextSize;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedThemeValue = preferences.getString(_storageKey);
    final savedTextSizeValue = preferences.getString(_textSizeStorageKey);
    final loadedMode = _normalizeThemeModeName(savedThemeValue);
    final loadedTextSize = _normalizeTextSizeName(savedTextSizeValue);

    _savedThemeMode = loadedMode;
    _themeMode = loadedMode;
    _savedTextSize = loadedTextSize;
    _textSize = loadedTextSize;
  }

  void previewThemeMode(ThemeMode value) {
    final normalizedValue = _normalizeThemeMode(value);

    if (_themeMode == normalizedValue) return;

    _themeMode = normalizedValue;
    notifyListeners();
  }

  void previewTextSize(GakujiTextSize value) {
    if (_textSize == value) return;

    _textSize = value;
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

  Future<void> saveTextSize(GakujiTextSize value) async {
    // Keep the live preview active while the preference is persisted.
    previewTextSize(value);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_textSizeStorageKey, value.name);

    _savedTextSize = value;
  }

  Future<void> setThemeMode(ThemeMode value) {
    return saveThemeMode(value);
  }

  void discardThemePreview() {
    previewThemeMode(_savedThemeMode);
  }

  void discardTextSizePreview() {
    previewTextSize(_savedTextSize);
  }

  ThemeMode _normalizeThemeMode(ThemeMode value) {
    return value == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
  }

  ThemeMode _normalizeThemeModeName(String? value) {
    return value == ThemeMode.dark.name
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  GakujiTextSize _normalizeTextSizeName(String? value) {
    return GakujiTextSize.values.firstWhere(
      (size) => size.name == value,
      orElse: () => GakujiTextSize.small,
    );
  }
}

final AppThemeController appThemeController = AppThemeController();
