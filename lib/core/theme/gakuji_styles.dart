import 'package:flutter/material.dart';

import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/core/services/app_theme_controller.dart';

class GakujiFonts {
  static const String japanese = 'IBMPlexSansJP';
}

/// App-wide colors.
///
/// Brand colors and legacy deck-type colors remain available as defaults.
/// User-selected deck colors override those defaults per deck. Neutral surface,
/// text, border, divider, and shadow colors switch with the saved theme.
class GakujiColors {
  static bool get isDarkMode {
    return appThemeController.themeMode == ThemeMode.dark;
  }

  static const Color deckBlue = Color(0xFF4D7EF7);

  static const Color reading = Color(0xFF5B84B8);
  static const Color starred = reading;
  static const Color writing = Color(0xFF7C8F3A);
  static const Color hybrid = Color(0xFFA57A48);
  static const Color review = Color(0xFFD9825B);
  static const Color learning = Color(0xFFD66F6B);

  static const Color pinRed = Color(0xFFFF4B4B);
  static const Color watermarkBlue = Color(0x1A4D7EF7);

  static Color defaultDeckColorForType(DeckType type) {
    switch (type) {
      case DeckType.reading:
        return reading;
      case DeckType.writing:
        return writing;
      case DeckType.hybrid:
        return hybrid;
    }
  }

  static Color deckColorFor(Deck deck) {
    final colorValue = deck.colorValue;

    if (colorValue != null) {
      return Color(colorValue);
    }

    return defaultDeckColorForType(deck.type);
  }

  static Color get deckCircle => isDarkMode
      ? const Color(0xFF303136)
      : const Color(0xFFF8F5EC);

  static Color get warmBackground => isDarkMode
      ? const Color(0xFF191A1D)
      : const Color(0xFFFBFAF5);

  static Color get warmCard => isDarkMode
      ? const Color(0xFF242529)
      : const Color(0xFFFFFCF4);

  static Color get sectionHeader => isDarkMode
      ? const Color(0xFF202125)
      : const Color(0xFFFAF7F2);

  static Color get whiteCard => isDarkMode
      ? const Color(0xFF2D2E33)
      : Colors.white;

  static Color get darkGray => isDarkMode
      ? const Color(0xFFF1EDE5)
      : const Color(0xFF555555);

  static Color get mediumGray => isDarkMode
      ? const Color(0xFFB5B1AA)
      : const Color(0xFF888888);

  static Color get softGray => isDarkMode
      ? const Color(0xFF7C7D82)
      : const Color(0xFFAAA39A);

  static Color get softBorder => isDarkMode
      ? const Color(0xFF3A3B40)
      : const Color(0xFFD8D5CF);

  static Color get warmDivider => isDarkMode
      ? const Color(0xFF45464C)
      : const Color(0xFFE8E2D6);

  static Color get lightDivider => isDarkMode
      ? const Color(0xFF515258)
      : const Color(0xFFE1E1E1);
}

@immutable
class GakujiPalette extends ThemeExtension<GakujiPalette> {
  final Color deckCircle;
  final Color warmBackground;
  final Color warmCard;
  final Color whiteCard;
  final Color darkGray;
  final Color mediumGray;
  final Color softGray;
  final Color softBorder;
  final Color warmDivider;
  final Color lightDivider;
  final Color softShadow;
  final Color cardShadow;

  const GakujiPalette({
    required this.deckCircle,
    required this.warmBackground,
    required this.warmCard,
    required this.whiteCard,
    required this.darkGray,
    required this.mediumGray,
    required this.softGray,
    required this.softBorder,
    required this.warmDivider,
    required this.lightDivider,
    required this.softShadow,
    required this.cardShadow,
  });

  static const GakujiPalette light = GakujiPalette(
    deckCircle: Color(0xFFF8F5EC),
    warmBackground: Color(0xFFFBFAF5),
    warmCard: Color(0xFFFFFCF4),
    whiteCard: Colors.white,
    darkGray: Color(0xFF555555),
    mediumGray: Color(0xFF888888),
    softGray: Color(0xFFAAA39A),
    softBorder: Color(0xFFD8D5CF),
    warmDivider: Color(0xFFE8E2D6),
    lightDivider: Color(0xFFE1E1E1),
    softShadow: Color(0x22000000),
    cardShadow: Color(0x36000000),
  );

  static const GakujiPalette dark = GakujiPalette(
    deckCircle: Color(0xFF303136),
    warmBackground: Color(0xFF191A1D),
    warmCard: Color(0xFF242529),
    whiteCard: Color(0xFF2D2E33),
    darkGray: Color(0xFFF1EDE5),
    mediumGray: Color(0xFFB5B1AA),
    softGray: Color(0xFF7C7D82),
    softBorder: Color(0xFF3A3B40),
    warmDivider: Color(0xFF45464C),
    lightDivider: Color(0xFF515258),
    softShadow: Color(0x66000000),
    cardShadow: Color(0x99000000),
  );

  @override
  GakujiPalette copyWith({
    Color? deckCircle,
    Color? warmBackground,
    Color? warmCard,
    Color? whiteCard,
    Color? darkGray,
    Color? mediumGray,
    Color? softGray,
    Color? softBorder,
    Color? warmDivider,
    Color? lightDivider,
    Color? softShadow,
    Color? cardShadow,
  }) {
    return GakujiPalette(
      deckCircle: deckCircle ?? this.deckCircle,
      warmBackground: warmBackground ?? this.warmBackground,
      warmCard: warmCard ?? this.warmCard,
      whiteCard: whiteCard ?? this.whiteCard,
      darkGray: darkGray ?? this.darkGray,
      mediumGray: mediumGray ?? this.mediumGray,
      softGray: softGray ?? this.softGray,
      softBorder: softBorder ?? this.softBorder,
      warmDivider: warmDivider ?? this.warmDivider,
      lightDivider: lightDivider ?? this.lightDivider,
      softShadow: softShadow ?? this.softShadow,
      cardShadow: cardShadow ?? this.cardShadow,
    );
  }

  @override
  GakujiPalette lerp(covariant GakujiPalette? other, double t) {
    if (other == null) return this;

    return GakujiPalette(
      deckCircle: Color.lerp(deckCircle, other.deckCircle, t)!,
      warmBackground: Color.lerp(warmBackground, other.warmBackground, t)!,
      warmCard: Color.lerp(warmCard, other.warmCard, t)!,
      whiteCard: Color.lerp(whiteCard, other.whiteCard, t)!,
      darkGray: Color.lerp(darkGray, other.darkGray, t)!,
      mediumGray: Color.lerp(mediumGray, other.mediumGray, t)!,
      softGray: Color.lerp(softGray, other.softGray, t)!,
      softBorder: Color.lerp(softBorder, other.softBorder, t)!,
      warmDivider: Color.lerp(warmDivider, other.warmDivider, t)!,
      lightDivider: Color.lerp(lightDivider, other.lightDivider, t)!,
      softShadow: Color.lerp(softShadow, other.softShadow, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
    );
  }
}

extension GakujiThemeContext on BuildContext {
  GakujiPalette get gakujiColors {
    return Theme.of(this).extension<GakujiPalette>() ??
        (GakujiColors.isDarkMode
            ? GakujiPalette.dark
            : GakujiPalette.light);
  }

  bool get isGakujiDarkMode => GakujiColors.isDarkMode;
}

class GakujiSpacing {
  static const double pageHorizontal = 24;
  static const double pageBottom = 90;

  static const double sectionGap = 28;
  static const double smallSectionGap = 14;

  static const double buttonGap = 12;
  static const double pillGap = 12;
}

class GakujiRadius {
  static const double small = 10;
  static const double medium = 14;
  static const double large = 18;
  static const double card = 18;
  static const double pill = 999;
}

/// Shared typography follows the active Light/Dark palette.
///
/// General interface roles respond to the user's Small / Medium / Large text
/// preference. Purpose-built study-card, game, and counter typography stays
/// fixed so those layouts keep their tuned proportions.
class GakujiText {
  static double _scaledSize({
    required double small,
    required double medium,
    required double large,
  }) {
    switch (appThemeController.textSize) {
      case GakujiTextSize.small:
        return small;
      case GakujiTextSize.medium:
        return medium;
      case GakujiTextSize.large:
        return large;
    }
  }

  // Legacy broad roles stay fixed because they are still used by some
  // purpose-built activity layouts. New/general UI should prefer the explicit
  // scalable roles below.
  static TextStyle get xLarge => TextStyle(
        fontSize: 38,
        height: 0.92,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        color: GakujiColors.darkGray,
      );

  static TextStyle get large => TextStyle(
        fontSize: 28,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.45,
        color: GakujiColors.darkGray,
      );

  static TextStyle get pageTitle => TextStyle(
        fontSize: _scaledSize(small: 24, medium: 26, large: 28),
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: GakujiColors.darkGray,
      );

  static TextStyle get sectionTitle => TextStyle(
        fontSize: _scaledSize(small: 20, medium: 22, large: 24),
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: GakujiColors.darkGray,
      );

  static TextStyle get actionLabel => TextStyle(
        fontSize: _scaledSize(small: 16, medium: 18, large: 20),
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: GakujiColors.darkGray,
      );

  static TextStyle get medium => TextStyle(
        fontSize: 22,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
        color: GakujiColors.mediumGray,
      );

  static TextStyle get small => TextStyle(
        fontSize: 18,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
        color: GakujiColors.mediumGray,
      );

  static TextStyle get body => TextStyle(
        fontSize: _scaledSize(small: 14, medium: 16, large: 18),
        height: 1,
        fontWeight: FontWeight.w400,
        color: GakujiColors.darkGray,
      );

  static TextStyle get dictionaryTopBarTitle => TextStyle(
        fontSize: _scaledSize(small: 23, medium: 25, large: 27),
        height: 1,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        color: GakujiColors.darkGray,
      );

  static TextStyle get dictionaryTerm => TextStyle(
        fontSize: _scaledSize(small: 22, medium: 24, large: 26),
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: GakujiColors.darkGray,
      );

  static TextStyle get dictionaryKanjiDisplay => TextStyle(
        fontSize: 68,
        height: 1,
        fontWeight: FontWeight.w400,
        color: GakujiColors.darkGray,
      );

  static TextStyle get dictionaryDetailBody => TextStyle(
        fontSize: _scaledSize(small: 16, medium: 18, large: 20),
        height: 1,
        fontWeight: FontWeight.w500,
        color: GakujiColors.darkGray,
      );

  static TextStyle get termTitle => TextStyle(
        fontSize: _scaledSize(small: 20, medium: 22, large: 24),
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
        color: GakujiColors.darkGray,
      );

  static TextStyle get termReading => TextStyle(
        fontSize: _scaledSize(small: 18, medium: 20, large: 22),
        height: 1,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: GakujiColors.reading,
      );

  static TextStyle get termRowTitle => TextStyle(
        fontSize: _scaledSize(small: 22, medium: 24, large: 26),
        height: 1,
        fontWeight: FontWeight.w700,
        color: GakujiColors.darkGray,
      );

  static TextStyle get termRowReading => TextStyle(
        fontSize: _scaledSize(small: 19, medium: 21, large: 23),
        height: 1,
        fontWeight: FontWeight.w600,
        color: GakujiColors.reading,
      );

  static TextStyle get termRowMeaning => TextStyle(
        fontSize: _scaledSize(small: 14, medium: 16, large: 18),
        height: 1.15,
        fontWeight: FontWeight.w400,
        color: GakujiColors.darkGray,
      );

  static TextStyle get deckTitle => TextStyle(
        fontSize: _scaledSize(small: 16, medium: 18, large: 20),
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: GakujiColors.darkGray,
      );

  static TextStyle get deckMeta => TextStyle(
        fontSize: _scaledSize(small: 14, medium: 16, large: 18),
        height: 1,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.05,
        color: GakujiColors.darkGray,
      );

  static TextStyle get learningCardTitle => TextStyle(
        fontSize: _scaledSize(small: 26, medium: 28, large: 30),
        height: 0.96,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: GakujiColors.darkGray,
      );

  static TextStyle get learningCardSubtitle => TextStyle(
        fontSize: _scaledSize(small: 14, medium: 16, large: 18),
        height: 1.08,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.05,
        color: GakujiColors.mediumGray,
      );

  static TextStyle get kanaScriptHeader => TextStyle(
        fontSize: _scaledSize(small: 22, medium: 24, large: 26),
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: GakujiColors.darkGray,
      );

  static TextStyle get kanaSectionTitle => TextStyle(
        fontSize: _scaledSize(small: 16, medium: 18, large: 20),
        height: 1,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.05,
        color: GakujiColors.darkGray,
      );

  static TextStyle get kanaReading => TextStyle(
        fontSize: _scaledSize(small: 11.5, medium: 12.5, large: 13.5),
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: GakujiColors.mediumGray,
      );

  static TextStyle get calendarDate => TextStyle(
        fontSize: _scaledSize(small: 36, medium: 38, large: 40),
        height: 0.9,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        color: GakujiColors.darkGray,
      );

  static TextStyle get calendarMeta => TextStyle(
        fontSize: _scaledSize(small: 14, medium: 15, large: 16),
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.05,
        color: GakujiColors.darkGray,
      );

  static TextStyle get calendarSmall => TextStyle(
        fontSize: _scaledSize(small: 13, medium: 14, large: 15),
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.05,
        color: GakujiColors.mediumGray,
      );

  // Fixed activity typography. These deliberately ignore the app text-size
  // preference so games and study-session UI do not reflow.
  static TextStyle get studyCounter => TextStyle(
        fontSize: 20,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: GakujiColors.darkGray,
      );

  static TextStyle get gameReading => TextStyle(
        fontFamily: GakujiFonts.japanese,
        fontSize: 27,
        height: 1.05,
        fontWeight: FontWeight.w700,
        color: GakujiColors.darkGray,
      );

  static TextStyle get gameDefinition => TextStyle(
        fontSize: 16,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: GakujiColors.darkGray,
      );

  static TextStyle get gameScore => TextStyle(
        fontSize: 16,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: GakujiColors.mediumGray,
      );

  static TextStyle get gameTarget => TextStyle(
        fontFamily: GakujiFonts.japanese,
        fontSize: 48,
        height: 1,
        fontWeight: FontWeight.w600,
        color: GakujiColors.darkGray,
      );

  static TextStyle get studyCounterLabel => TextStyle(
        fontSize: 14,
        height: 1,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.05,
        color: GakujiColors.mediumGray,
      );

  static const TextStyle xSmall = TextStyle(
    fontSize: 15.5,
    height: 1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.15,
    color: GakujiColors.deckBlue,
  );

  static const TextStyle pill = TextStyle(
    fontSize: 15.5,
    height: 1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.15,
  );

  static TextStyle get menuItem => TextStyle(
        fontSize: _scaledSize(small: 15, medium: 17, large: 19),
        height: 1,
        fontWeight: FontWeight.w600,
        color: GakujiColors.darkGray,
      );

  static const TextStyle snackBar = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );
}

class GakujiShadows {
  static BoxShadow get soft => BoxShadow(
        color: GakujiColors.isDarkMode
            ? const Color(0x28000000)
            : const Color(0x22000000),
        blurRadius: GakujiColors.isDarkMode ? 11 : 10,
        spreadRadius: 0,
        offset: Offset(0, GakujiColors.isDarkMode ? 4 : 4),
      );

  static BoxShadow get card => BoxShadow(
        color: GakujiColors.isDarkMode
            ? const Color(0x40000000)
            : const Color(0x36000000),
        blurRadius: GakujiColors.isDarkMode ? 18 : 18,
        spreadRadius: GakujiColors.isDarkMode ? -1 : 0,
        offset: Offset(0, GakujiColors.isDarkMode ? 7 : 8),
      );
}
