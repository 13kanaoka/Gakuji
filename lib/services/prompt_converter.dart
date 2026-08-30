import 'package:gakuji/models/term.dart';
import 'package:gakuji/models/writing_prompt.dart';

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