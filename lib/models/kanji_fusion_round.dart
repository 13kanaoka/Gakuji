import 'term.dart';

enum KanjiFusionDifficulty { easy, normal, hard }

enum KanjiFusionRadicalMode { receive, create }

enum KanjiFusionSlotShape {
  standard,
  cutout,
  gate,
  enclosure,
  cliff,
  rightHook,
}

class KanjiFusionSlot {
  final String component;
  final double left;
  final double top;
  final double width;
  final double height;
  final KanjiFusionSlotShape shape;
  final double contentLeft;
  final double contentTop;
  final double contentWidth;
  final double contentHeight;

  const KanjiFusionSlot({
    required this.component,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.shape = KanjiFusionSlotShape.standard,
    this.contentLeft = 0,
    this.contentTop = 0,
    this.contentWidth = 1,
    this.contentHeight = 1,
  });
}

/// A visual boundary around leaf slots that together form a reusable kanji
/// component. The component name is retained for future feedback and review,
/// but is intentionally not shown before the answer is submitted.
class KanjiFusionGroup {
  final String component;
  final double left;
  final double top;
  final double width;
  final double height;
  final int depth;

  const KanjiFusionGroup({
    required this.component,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.depth = 0,
  });
}

class KanjiFusionRound {
  final Term term;
  final String targetKanji;
  final List<String> requiredComponents;
  final List<String> componentChoices;
  final List<List<String>> componentFormChoices;
  final List<KanjiFusionSlot> structuralSlots;
  final List<KanjiFusionGroup> structuralGroups;

  const KanjiFusionRound({
    required this.term,
    required this.targetKanji,
    required this.requiredComponents,
    required this.componentChoices,
    this.componentFormChoices = const [],
    this.structuralSlots = const [],
    this.structuralGroups = const [],
  });

  List<String> formsForChoice(int index) {
    if (index < 0 || index >= componentChoices.length) {
      return const [];
    }

    if (index >= componentFormChoices.length ||
        componentFormChoices[index].isEmpty) {
      return <String>[componentChoices[index]];
    }

    return componentFormChoices[index];
  }

  String get reading {
    final value = term.reading.trim();
    return value.isEmpty ? 'No reading available' : value;
  }

  String get definition {
    final cardMeaning = term.cardMeaning.trim();
    if (cardMeaning.isNotEmpty) return cardMeaning;
    final fallback = term.meaning.trim();
    return fallback.isEmpty ? 'No definition available' : fallback;
  }
}
