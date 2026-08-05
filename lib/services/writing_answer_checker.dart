class WritingAnswerResult {
  final String submittedAnswer;
  final String correctAnswer;
  final bool isCorrect;

  const WritingAnswerResult({
    required this.submittedAnswer,
    required this.correctAnswer,
    required this.isCorrect,
  });
}

class WritingAnswerChecker {
  /// Normalizes answers before comparison.
  ///
  /// For now, this removes whitespace only.
  /// Later, we can expand this if we need to handle punctuation,
  /// kana variants, full-width/half-width issues, etc.
  static String normalize(String value) {
    return value.replaceAll(RegExp(r'\s+'), '').trim();
  }

  static WritingAnswerResult check({
    required String submittedAnswer,
    required String correctAnswer,
  }) {
    final normalizedSubmitted = normalize(submittedAnswer);
    final normalizedCorrect = normalize(correctAnswer);

    return WritingAnswerResult(
      submittedAnswer: normalizedSubmitted,
      correctAnswer: normalizedCorrect,
      isCorrect: normalizedSubmitted == normalizedCorrect,
    );
  }
}