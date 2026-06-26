import '../models/term.dart';
import '../models/writing_prompt.dart';

class PromptConverter {
  static WritingPrompt fromTerm(Term term) {
    final kanji = term.kanji;

    return WritingPrompt(
      id: '${term.kanji}_${term.reading}_${term.meaning}',

      answer: term.kanji,
      reading: term.reading,
      meaning: term.meaning,

      /// SLOT SYSTEM:
      /// how many writing boxes to show
      slotCount: _calculateSlotCount(term),
    );
  }

  /// Determines how many slots the card should have.
  /// For now: simple character-based rule.
  static int _calculateSlotCount(Term term) {
    final text = term.kanji;

    // remove whitespace just in case
    final cleaned = text.replaceAll(' ', '');

    // basic rule: each character = 1 slot
    // (we can refine later for compounds / kana grouping)
    return cleaned.length;
  }
}