import 'package:gakuji/domain/term.dart';
import 'package:gakuji/features/dictionary/services/japanese_text_analysis_service.dart';

class CameraTextAnalysisResult {
  final String text;
  final List<Term> isolatedMatches;
  final DictionaryExample? sentenceExample;

  const CameraTextAnalysisResult({
    required this.text,
    this.isolatedMatches = const [],
    this.sentenceExample,
  });

  bool get isIsolated => isolatedMatches.isNotEmpty;

  bool get hasSentenceBreakdown => sentenceExample != null;
}

class CameraTextAnalysisService {
  static Future<CameraTextAnalysisResult> analyze(String rawText) async {
    final analysis = await JapaneseTextAnalysisService.analyze(
      rawText,
      isolatedTermCoverageThreshold: 0.70,
      requireSingleTokenForIsolated: false,
      allowMenuPriceFallback: true,
      removeWhitespace: true,
    );

    return CameraTextAnalysisResult(
      text: analysis.text,
      isolatedMatches: analysis.isolatedMatches,
      sentenceExample: analysis.sentenceExample,
    );
  }
}
