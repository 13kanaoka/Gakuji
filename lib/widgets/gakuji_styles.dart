import 'package:flutter/material.dart';

class GakujiColors {
  static const Color deckBlue = Color(0xFF4D7EF7);

  static const Color folderYellow = Color(0xFFFFCF4D);
  static const Color folderOrange = Color(0xFFF08B32);

  static const Color searchBackground = Color(0xFFF8F8F8);
  static const Color softGray = Color(0xFFEDEDED);
  static const Color mediumGray = Color(0xFFB5B5B5);
  static const Color textGray = Color(0xFF888888);

  static const Color accentGreen = Color(0xFF2E7D32);
}

class GakujiCorners {
  static const double small = 12;
  static const double medium = 18;
  static const double large = 24;
  static const double pill = 32;
}

class GakujiShadows {
  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> cardDrop = [
    BoxShadow(color: Color(0x22000000), blurRadius: 0, offset: Offset(0, 10)),
  ];

  static const List<BoxShadow> folderDrop = [
    BoxShadow(color: Color(0x22000000), blurRadius: 0, offset: Offset(0, 8)),
  ];
}

class GakujiSpacing {
  static const double pageHorizontal = 18;
  static const double pageBottomPadding = 100;

  static const double small = 8;
  static const double medium = 12;
  static const double large = 18;
  static const double extraLarge = 24;
  static const double huge = 34;
}
