import 'package:flutter/material.dart';

/// App-wide text style ramp. Text styles should come from here rather than
/// inline TextStyles, so typography can be retuned in one place.
abstract final class AppText {
  static const Color _ink = Colors.black;
  static const Color _inkMuted = Colors.grey;
  static const Color _accent = Color(0xFF4D7EF7);

  // Page chrome
  static const TextStyle pageTitle = TextStyle(
    fontSize: 18,
    height: 1,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 24,
    height: 1,
    fontWeight: FontWeight.bold,
    color: _ink,
  );

  static const TextStyle listHeading = TextStyle(
    fontSize: 17,
    height: 1,
    fontWeight: FontWeight.bold,
    color: _ink,
  );

  static const TextStyle topBarTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w400,
    color: _ink,
  );

  static const TextStyle topBarTitleSmall = TextStyle(
    fontSize: 15.5,
    fontWeight: FontWeight.w400,
    color: _ink,
  );

  static const TextStyle displayTitle = TextStyle(
    fontSize: 41,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    color: _ink,
  );

  static const TextStyle screenTitle = TextStyle(
    fontSize: 29,
    height: 0.98,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    color: _ink,
  );

  // Cards and list rows
  static const TextStyle listTitle = TextStyle(
    fontSize: 16.5,
    height: 1,
    fontWeight: FontWeight.w700,
    color: _ink,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 19,
    height: 1,
    fontWeight: FontWeight.w700,
    color: _ink,
  );

  static const TextStyle cardReading = TextStyle(
    fontSize: 16.5,
    height: 1,
    fontWeight: FontWeight.w600,
    color: _accent,
  );

  static const TextStyle cardCaption = TextStyle(
    fontSize: 12.5,
    height: 1,
    color: _ink,
  );

  // Kanji display
  static const TextStyle kanjiCandidate = TextStyle(
    fontSize: 28,
    height: 1,
    fontWeight: FontWeight.w500,
    color: _ink,
  );

  static const TextStyle kanjiHero = TextStyle(
    fontSize: 66,
    height: 1,
    fontWeight: FontWeight.w400,
    color: _ink,
  );

  static const TextStyle kanjiStroke = TextStyle(
    fontSize: 23,
    fontWeight: FontWeight.w400,
    color: _ink,
  );

  static const TextStyle kanjiGlyphLarge = TextStyle(
    fontSize: 39,
    fontWeight: FontWeight.w400,
    color: Colors.white,
  );

  static const TextStyle kanjiGlyphSmall = TextStyle(
    fontSize: 19,
    height: 1,
    fontWeight: FontWeight.w800,
    color: _ink,
  );

  // Body and inputs
  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1,
    fontWeight: FontWeight.w400,
    color: _ink,
  );

  static const TextStyle input = TextStyle(
    fontSize: 14.5,
    height: 1,
    fontWeight: FontWeight.w400,
    color: _ink,
  );

  static const TextStyle inputHint = TextStyle(
    fontSize: 14.5,
    height: 1,
    fontWeight: FontWeight.w400,
    color: Color(0xFF777777),
  );

  // Detail rows (dictionary/kanji detail pages)
  static const TextStyle detailLabel = TextStyle(
    fontSize: 15.5,
    color: _inkMuted,
  );

  static const TextStyle detailValue = TextStyle(
    fontSize: 17,
    height: 1.25,
    color: _ink,
  );

  // Dialogs
  static const TextStyle dialogTitle = TextStyle(
    fontSize: 30,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    color: _ink,
  );

  static const TextStyle fieldLabel = TextStyle(
    fontSize: 13,
    height: 1,
    fontWeight: FontWeight.w600,
    color: _ink,
  );

  static const TextStyle smallLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: _ink,
  );

  // Buttons and controls
  static const TextStyle primaryButton = TextStyle(
    fontSize: 17,
    height: 1,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  static const TextStyle buttonLarge = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontSize: 13,
    height: 1,
    fontWeight: FontWeight.w700,
    color: _ink,
  );

  static const TextStyle toggleLabel = TextStyle(
    fontSize: 14,
    height: 1,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static const TextStyle emptyState = TextStyle(fontSize: 14, color: _inkMuted);
}
