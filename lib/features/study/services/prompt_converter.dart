import 'package:gakuji/domain/term.dart';
import 'package:gakuji/domain/writing_prompt.dart';

class PromptConverter {
  static WritingPrompt fromTerm(Term term) {
    return WritingPrompt(
      id: term.id,
      reading: term.reading,
      meaning: term.meaning,
      answer: term.kanji,
    );
  }
}