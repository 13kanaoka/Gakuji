import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import '../models/term.dart';
import 'dictionary_service.dart';
import 'japanese_conjugation_service.dart';
import 'paddle_camera_ocr_service.dart';

enum CameraTextOrientation {
  horizontal,
  vertical,
}

class CameraTextAnnotation {
  final String text;
  final Rect boundingBox;
  final double? confidence;
  final CameraTextOrientation orientation;

  const CameraTextAnnotation({
    required this.text,
    required this.boundingBox,
    this.confidence,
    this.orientation = CameraTextOrientation.horizontal,
  });
}

class CameraTextUnit {
  final String text;
  final List<Rect> boundingBoxes;
  final List<CameraTextAnnotation> annotations;
  final CameraTextOrientation orientation;

  CameraTextUnit({
    required this.text,
    required List<Rect> boundingBoxes,
    List<CameraTextAnnotation> annotations = const [],
    this.orientation = CameraTextOrientation.horizontal,
  })  : boundingBoxes = List.unmodifiable(boundingBoxes),
        annotations = List.unmodifiable(annotations);

  Rect get boundingBox {
    if (boundingBoxes.isEmpty) return Rect.zero;

    var combined = boundingBoxes.first;

    for (final box in boundingBoxes.skip(1)) {
      combined = combined.expandToInclude(box);
    }

    return combined;
  }
}

class CameraRecognitionResult {
  final Size imageSize;
  final List<CameraTextUnit> units;

  const CameraRecognitionResult({
    required this.imageSize,
    required this.units,
  });
}

typedef CameraScanProgressCallback = void Function(double progress);

class CameraTextRecognitionService {
  // TEMPORARY: Keep this enabled while tuning Camera Mode sentence grouping.
  // All logs are debug-build only and can be disabled from this one flag.
  static const bool _debugOcrPipeline = true;

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.japanese,
  );

  Future<CameraRecognitionResult> recognizePhoto(
    String imagePath, {
    CameraScanProgressCallback? onProgress,
  }) async {
    _emitScanProgress(onProgress, 0.0);

    final inputImage = InputImage.fromFilePath(imagePath);
    final recognizedText = await _runTimedScanStage(
      task: () => _textRecognizer.processImage(inputImage),
      onProgress: onProgress,
      start: 0.02,
      end: 0.18,
      expectedDuration: const Duration(seconds: 4),
    );
    final imageSize = await _runTimedScanStage(
      task: () => _imageSizeForFile(imagePath),
      onProgress: onProgress,
      start: 0.18,
      end: 0.21,
      expectedDuration: const Duration(milliseconds: 700),
    );
    final physicalLines = <_CameraRawLine>[];

    for (var blockIndex = 0;
        blockIndex < recognizedText.blocks.length;
        blockIndex++) {
      final block = recognizedText.blocks[blockIndex];

      for (final line in block.lines) {
        final orientation = _orientationForRecognizedLine(
          line: line,
          block: block,
        );
        final cleanedText = _cleanLineText(
          _textForRecognizedLine(
            line: line,
            orientation: orientation,
          ),
        );
        final text = orientation == CameraTextOrientation.vertical
            ? _normalizeVerticalSmallKanaByLanguage(cleanedText)
            : cleanedText;

        if (!_isUsefulJapaneseLine(text)) continue;

        physicalLines.add(
          _CameraRawLine(
            text: text,
            boundingBox: line.boundingBox,
            blockIndex: blockIndex,
            confidence: line.confidence,
            angle: line.angle,
            orientation: orientation,
          ),
        );
      }
    }

    physicalLines.sort(_compareRawLinesForDebug);
    _debugRawLines('RAW PHYSICAL LINES', physicalLines);

    // Furigana/ruby is useful reading evidence, but it must never enter the
    // primary sentence stream. Horizontal ruby is normally above its base;
    // vertical ruby is normally a smaller column on the right side.
    final rubyClassification = _classifyRubyAnnotations(physicalLines);
    _debugRubyClassification(rubyClassification);

    // Keep the first full-photo OCR pass authoritative. Ruby/layout cleanup
    // happens before the confidence-gated vertical character verification so
    // retry crops focus on primary printed dialogue rather than annotations.
    final overlapResolvedPrimaryLines =
        _resolveOverlappingVerticalPrimaryLines(rubyClassification.primaryLines);
    _debugRawLines(
      'PRIMARY LINES AFTER VERTICAL OVERLAP FILTER',
      overlapResolvedPrimaryLines,
    );

    _emitScanProgress(onProgress, 0.24);

    // PP-OCRv5 mobile now gets the first character-recognition pass once
    // Gakuji/ML Kit has established geometry and removed ruby. A strong Paddle
    // result confirms that vertical column even when its text exactly agrees
    // with ML Kit. Confirmed columns skip the older, much more expensive ML Kit
    // crop/contrast/text-box retry maze. If Paddle is weak, unavailable, or
    // structurally implausible, that line falls through to the unchanged legacy
    // verifier below. This changes scheduling, not recognition quality gates.
    final paddleStopwatch = Stopwatch()..start();
    final paddleRefinement = await _runTimedScanStage(
      task: () => _refineVerticalLinesWithPaddleOcr(
        imagePath: imagePath,
        imageSize: imageSize,
        lines: overlapResolvedPrimaryLines,
      ),
      onProgress: onProgress,
      start: 0.24,
      end: 0.58,
      expectedDuration: const Duration(seconds: 7),
    );
    paddleStopwatch.stop();
    _debugRawLines(
      'PRIMARY LINES AFTER PADDLE OCR',
      paddleRefinement.lines,
    );

    if (kDebugMode && _debugOcrPipeline) {
      debugPrint(
        '[Camera OCR] TIMING paddle=${paddleStopwatch.elapsedMilliseconds}ms '
        'confirmed=${paddleRefinement.confirmedLineIndexes.length} '
        'smartKeep=${paddleRefinement.directKeepLineIndexes.length}',
      );
    }

    // Legacy ML Kit verification is now reserved for genuine unresolved
    // disagreements. Paddle-confirmed lines skip it, and so do reasonably
    // confident ML Kit lines when Paddle independently reads only a strict
    // subset of the same text. The latter is positive evidence that Paddle
    // simply missed characters, not evidence that the ML Kit line needs more
    // expensive same-model retries.
    final legacyVerificationStopwatch = Stopwatch()..start();
    final verifiedPrimaryLines = await _runTimedScanStage(
      task: () => _verifyLowConfidenceVerticalLines(
        imagePath: imagePath,
        imageSize: imageSize,
        lines: paddleRefinement.lines,
        skipLineIndexes: paddleRefinement.skipLegacyLineIndexes,
      ),
      onProgress: onProgress,
      start: 0.58,
      end: 0.88,
      expectedDuration: const Duration(seconds: 10),
    );
    legacyVerificationStopwatch.stop();
    _debugRawLines(
      'PRIMARY LINES AFTER OCR VERIFICATION',
      verifiedPrimaryLines,
    );

    if (kDebugMode && _debugOcrPipeline) {
      debugPrint(
        '[Camera OCR] TIMING legacyVerticalFallback='
        '${legacyVerificationStopwatch.elapsedMilliseconds}ms',
      );
    }

    final refinedPhysicalLines = await _runTimedScanStage(
      task: () => _refinePhysicalLinesWithSecondPass(
        imagePath: imagePath,
        imageSize: imageSize,
        lines: verifiedPrimaryLines,
      ),
      onProgress: onProgress,
      start: 0.88,
      end: 0.94,
      expectedDuration: const Duration(seconds: 3),
    );
    _debugRawLines('REFINED PHYSICAL LINES', refinedPhysicalLines);

    final fragments = <_CameraTextFragment>[];

    for (final line in refinedPhysicalLines) {
      fragments.addAll(
        _splitLineIntoSentenceFragments(
          text: line.text,
          boundingBox: line.boundingBox,
          blockIndex: line.blockIndex,
          annotations: line.annotations,
          orientation: line.orientation,
        ),
      );
    }

    final horizontalFragments = fragments
        .where(
          (fragment) =>
              fragment.orientation == CameraTextOrientation.horizontal,
        )
        .toList(growable: false);
    final verticalFragments = fragments
        .where(
          (fragment) =>
              fragment.orientation == CameraTextOrientation.vertical,
        )
        .toList(growable: false);

    final horizontalOrdered = _orderFragmentsByVisualRows(horizontalFragments);
    _debugFragments('HORIZONTAL VISUAL ROW ORDER', horizontalOrdered);
    final horizontalReconstructed =
        _mergeSameVisualLineFragments(horizontalOrdered);
    _debugFragments(
      'HORIZONTAL SAME-ROW MERGE RESULT',
      horizontalReconstructed,
    );
    final horizontalUnits =
        await _mergeFragmentsIntoTextUnits(horizontalReconstructed);
    _emitScanProgress(onProgress, 0.96);

    // Vertical manga/dialogue is reconstructed inside inferred local text boxes.
    // This prevents columns from different speech bubbles, menu items, or
    // separated bands inside one large bubble from becoming neighbors merely
    // because they are close in global right-to-left page order.
    final verticalTextBoxes = _clusterVerticalFragmentsIntoTextBoxes(
      verticalFragments,
    );
    _debugVerticalTextBoxes(verticalTextBoxes);

    final verticalUnits = <CameraTextUnit>[];

    for (var boxIndex = 0;
        boxIndex < verticalTextBoxes.length;
        boxIndex++) {
      final textBox = verticalTextBoxes[boxIndex];
      final verticalOrdered = _orderFragmentsByVisualColumns(
        textBox.fragments,
      );
      _debugFragments(
        'VERTICAL TEXT BOX $boxIndex VISUAL COLUMN ORDER',
        verticalOrdered,
      );
      final verticalReconstructed =
          _mergeSameVisualColumnFragments(verticalOrdered);
      _debugFragments(
        'VERTICAL TEXT BOX $boxIndex SAME-COLUMN MERGE RESULT',
        verticalReconstructed,
      );
      verticalUnits.addAll(
        await _mergeFragmentsIntoTextUnits(
          verticalReconstructed,
          isInferredTextBox: true,
        ),
      );

      if (verticalTextBoxes.isNotEmpty) {
        final completedFraction = (boxIndex + 1) / verticalTextBoxes.length;
        _emitScanProgress(
          onProgress,
          0.96 + (0.03 * completedFraction),
        );
      }
    }

    final units = _combineOrientationUnits(
      horizontalUnits,
      verticalUnits,
    );
    _debugUnits(units);
    _emitScanProgress(onProgress, 1.0);

    return CameraRecognitionResult(
      imageSize: imageSize,
      units: List.unmodifiable(units),
    );
  }

  void _emitScanProgress(
    CameraScanProgressCallback? onProgress,
    double progress,
  ) {
    onProgress?.call(progress.clamp(0.0, 1.0).toDouble());
  }

  Future<T> _runTimedScanStage<T>({
    required Future<T> Function() task,
    required CameraScanProgressCallback? onProgress,
    required double start,
    required double end,
    required Duration expectedDuration,
  }) async {
    _emitScanProgress(onProgress, start);

    final stopwatch = Stopwatch()..start();
    final expectedMs = expectedDuration.inMilliseconds.clamp(1, 1 << 30);
    Timer? timer;

    if (onProgress != null && end > start) {
      timer = Timer.periodic(const Duration(milliseconds: 180), (_) {
        final elapsedFraction = stopwatch.elapsedMilliseconds / expectedMs;
        final cappedFraction = elapsedFraction.clamp(0.0, 1.0);
        final easedFraction = 1.0 - ((1.0 - cappedFraction) * (1.0 - cappedFraction));
        final stageFraction =
            (easedFraction * 0.92).clamp(0.0, 0.92).toDouble();
        _emitScanProgress(
          onProgress,
          start + ((end - start) * stageFraction),
        );
      });
    }

    try {
      final result = await task();
      _emitScanProgress(onProgress, end);
      return result;
    } finally {
      stopwatch.stop();
      timer?.cancel();
    }
  }

  CameraTextOrientation _orientationForRecognizedLine({
    required TextLine line,
    required TextBlock block,
  }) {
    final angle = line.angle;

    if (angle != null) {
      var normalized = angle.abs() % 180.0;
      if (normalized > 90.0) normalized = 180.0 - normalized;

      if (normalized >= 55.0) {
        return CameraTextOrientation.vertical;
      }

      if (normalized <= 25.0 &&
          line.boundingBox.width >= line.boundingBox.height * 1.15) {
        return CameraTextOrientation.horizontal;
      }
    }

    final box = line.boundingBox;

    if (box.height >= box.width * 1.35) {
      return CameraTextOrientation.vertical;
    }

    if (box.width >= box.height * 1.35) {
      return CameraTextOrientation.horizontal;
    }

    if (line.elements.length >= 2) {
      final centers = line.elements
          .map((element) => element.boundingBox.center)
          .toList(growable: false);
      final minX = centers.map((point) => point.dx).reduce((a, b) => a < b ? a : b);
      final maxX = centers.map((point) => point.dx).reduce((a, b) => a > b ? a : b);
      final minY = centers.map((point) => point.dy).reduce((a, b) => a < b ? a : b);
      final maxY = centers.map((point) => point.dy).reduce((a, b) => a > b ? a : b);
      final horizontalSpread = maxX - minX;
      final verticalSpread = maxY - minY;

      if (verticalSpread > horizontalSpread * 1.25) {
        return CameraTextOrientation.vertical;
      }

      if (horizontalSpread > verticalSpread * 1.25) {
        return CameraTextOrientation.horizontal;
      }
    }

    // Ambiguous one-character/square detections can inherit a strong block
    // direction. This is important when ML Kit returns one glyph per line in
    // a vertical manga column.
    final blockBox = block.boundingBox;
    if (block.lines.length >= 2 && blockBox.height > blockBox.width * 1.45) {
      return CameraTextOrientation.vertical;
    }

    return CameraTextOrientation.horizontal;
  }

  String _textForRecognizedLine({
    required TextLine line,
    required CameraTextOrientation orientation,
  }) {
    if (orientation != CameraTextOrientation.vertical ||
        line.elements.length <= 1) {
      return line.text;
    }

    final elements = line.elements.toList()
      ..sort((first, second) {
        final vertical =
            first.boundingBox.center.dy.compareTo(second.boundingBox.center.dy);
        if (vertical != 0) return vertical;
        return second.boundingBox.center.dx.compareTo(first.boundingBox.center.dx);
      });

    final rebuilt = _rebuildVerticalElementText(elements);
    return rebuilt.isEmpty ? line.text : rebuilt;
  }

  String _rebuildVerticalElementText(List<TextElement> elements) {
    if (elements.isEmpty) return '';

    final positiveWidths = elements
        .map((element) => element.boundingBox.width)
        .where((width) => width > 0)
        .toList()
      ..sort();
    final positiveHeights = elements
        .map((element) => element.boundingBox.height)
        .where((height) => height > 0)
        .toList()
      ..sort();
    final centers = elements
        .map((element) => element.boundingBox.center.dx)
        .toList()
      ..sort();

    final medianWidth = positiveWidths.isEmpty
        ? 1.0
        : positiveWidths[positiveWidths.length ~/ 2];
    final medianHeight = positiveHeights.isEmpty
        ? 1.0
        : positiveHeights[positiveHeights.length ~/ 2];
    final axisX = centers[centers.length ~/ 2];

    final rebuilt = <String>[];

    for (final element in elements) {
      final rawText = element.text.trim();
      if (rawText.isEmpty) continue;

      rebuilt.add(
        _normalizeVerticalSmallKanaElement(
          text: rawText,
          boundingBox: element.boundingBox,
          axisX: axisX,
          medianWidth: medianWidth,
          medianHeight: medianHeight,
        ),
      );
    }

    return rebuilt.join();
  }

  String _normalizeVerticalSmallKanaElement({
    required String text,
    required Rect boundingBox,
    required double axisX,
    required double medianWidth,
    required double medianHeight,
  }) {
    if (text.length != 1 || medianWidth <= 0 || medianHeight <= 0) {
      return text;
    }

    const smallKanaMap = <String, String>{
      'つ': 'っ',
      'や': 'ゃ',
      'ゆ': 'ゅ',
      'よ': 'ょ',
      'ツ': 'ッ',
      'ヤ': 'ャ',
      'ユ': 'ュ',
      'ヨ': 'ョ',
    };

    final normalized = smallKanaMap[text];
    if (normalized == null) return text;

    final widthRatio = boundingBox.width / medianWidth;
    final heightRatio = boundingBox.height / medianHeight;
    final axisOffsetRatio =
        (boundingBox.center.dx - axisX) / medianWidth;

    // Vertical small kana are physically smaller and sit slightly to the
    // right of the main character axis. Furigana sits farther outside the
    // column corridor, while a normal full-size kana is not small enough.
    final genuinelySmall = widthRatio <= 0.78 && heightRatio <= 0.82;
    final insideMainCorridor = axisOffsetRatio >= 0.04 &&
        axisOffsetRatio <= 0.48;

    if (!genuinelySmall || !insideMainCorridor) return text;

    if (kDebugMode && _debugOcrPipeline) {
      debugPrint(
        '[Camera OCR] SMALL KANA text="$text" -> "$normalized" '
        'widthRatio=${widthRatio.toStringAsFixed(3)} '
        'heightRatio=${heightRatio.toStringAsFixed(3)} '
        'axisOffset=${axisOffsetRatio.toStringAsFixed(3)}',
      );
    }

    return normalized;
  }

  String _normalizeVerticalSmallKanaByLanguage(String text) {
    if (text.length < 3) return text;

    final chars = <String>[
      for (var index = 0; index < text.length; index++)
        text.substring(index, index + 1),
    ];
    var changed = false;

    for (var index = 1; index < chars.length - 1; index++) {
      final current = chars[index];
      final previous = chars[index - 1];
      final next = chars[index + 1];

      String? replacement;
      double confidence = 0;

      // In modern Japanese prose, a full-size つ between Japanese text and
      // て/た is overwhelmingly likely to be a missed small っ. This catches
      // vertical OCR cases such as ナルトつていう and やつて while leaving
      // standalone lexical つて untouched because it has no preceding
      // Japanese character inside the same primary column.
      if (current == 'つ' &&
          _isJapaneseCharacter(previous) &&
          (next == 'て' || next == 'た')) {
        replacement = 'っ';
        confidence = 0.96;
      } else if (current == 'ツ' &&
          _isKatakanaCharacter(previous) &&
          (next == 'テ' || next == 'タ')) {
        replacement = 'ッ';
        confidence = 0.96;
      }

      if (replacement == null) continue;

      chars[index] = replacement;
      changed = true;

      if (kDebugMode && _debugOcrPipeline) {
        final contextStart = (index - 2).clamp(0, chars.length).toInt();
        final contextEnd = (index + 3).clamp(0, chars.length).toInt();
        final context = chars.sublist(contextStart, contextEnd).join();
        debugPrint(
          '[Camera OCR] LANGUAGE SMALL KANA text="$current" -> '
          '"$replacement" context="$context" '
          'score=${confidence.toStringAsFixed(3)}',
        );
      }
    }

    return changed ? chars.join() : text;
  }

  bool _isJapaneseCharacter(String value) {
    if (value.isEmpty) return false;
    return RegExp(
      r'^[\u3041-\u3096\u30A1-\u30FA\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々〆ヶ]$',
    ).hasMatch(value);
  }

  bool _isKatakanaCharacter(String value) {
    if (value.isEmpty) return false;
    return RegExp(r'^[\u30A1-\u30FA]$').hasMatch(value);
  }

  int _compareRawLinesForDebug(_CameraRawLine first, _CameraRawLine second) {
    if (first.orientation == CameraTextOrientation.vertical &&
        second.orientation == CameraTextOrientation.vertical) {
      final horizontal =
          second.boundingBox.center.dx.compareTo(first.boundingBox.center.dx);
      if (horizontal != 0) return horizontal;
      return first.boundingBox.top.compareTo(second.boundingBox.top);
    }

    final vertical = first.boundingBox.top.compareTo(second.boundingBox.top);
    if (vertical != 0) return vertical;
    return first.boundingBox.left.compareTo(second.boundingBox.left);
  }

  void _debugRawLines(String label, List<_CameraRawLine> lines) {
    if (!kDebugMode || !_debugOcrPipeline) return;

    debugPrint('[Camera OCR] ===== $label =====');

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      debugPrint(
        '[Camera OCR] LINE $index '
        'block=${line.blockIndex} '
        'conf=${_debugConfidence(line.confidence)} '
        'angle=${_debugConfidence(line.angle)} '
        'orientation=${line.orientation.name} '
        'box=${_debugRect(line.boundingBox)} '
        'ruby=${line.annotations.length} '
        'text="${line.text}"',
      );
    }
  }


  void _debugRubyClassification(_CameraRubyClassification result) {
    if (!kDebugMode || !_debugOcrPipeline) return;

    debugPrint('[Camera OCR] ===== RUBY / FURIGANA CLASSIFICATION =====');

    if (result.attachments.isEmpty) {
      debugPrint('[Camera OCR] No ruby annotations classified.');
    }

    for (var index = 0; index < result.attachments.length; index++) {
      final attachment = result.attachments[index];
      debugPrint(
        '[Camera OCR] RUBY $index '
        'text="${attachment.annotation.text}" '
        'box=${_debugRect(attachment.annotation.boundingBox)} '
        '-> primary="${attachment.primaryText}" '
        'primaryBox=${_debugRect(attachment.primaryBoundingBox)} '
        'score=${attachment.score.toStringAsFixed(3)}',
      );
    }

    debugPrint(
      '[Camera OCR] primaryLines=${result.primaryLines.length} '
      'rubyLines=${result.attachments.length}',
    );
  }

  void _debugVerticalTextBoxes(List<_CameraVerticalTextBox> boxes) {
    if (!kDebugMode || !_debugOcrPipeline) return;

    debugPrint('[Camera OCR] ===== VERTICAL TEXT BOXES =====');

    if (boxes.isEmpty) {
      debugPrint('[Camera OCR] No vertical text boxes found.');
      return;
    }

    for (var index = 0; index < boxes.length; index++) {
      final textBox = boxes[index];
      debugPrint(
        '[Camera OCR] TEXT BOX $index '
        'fragments=${textBox.fragments.length} '
        'box=${_debugRect(textBox.boundingBox)}',
      );

      for (var fragmentIndex = 0;
          fragmentIndex < textBox.fragments.length;
          fragmentIndex++) {
        final fragment = textBox.fragments[fragmentIndex];
        debugPrint(
          '[Camera OCR]   TEXT BOX $index FRAGMENT $fragmentIndex '
          'box=${_debugRect(fragment.boundingBox)} '
          'text="${fragment.text}"',
        );
      }
    }
  }

  void _debugFragments(String label, List<_CameraTextFragment> fragments) {
    if (!kDebugMode || !_debugOcrPipeline) return;

    debugPrint('[Camera OCR] ===== $label =====');

    for (var index = 0; index < fragments.length; index++) {
      final fragment = fragments[index];
      debugPrint(
        '[Camera OCR] FRAGMENT $index '
        'block=${fragment.blockIndex} '
        'orientation=${fragment.orientation.name} '
        'endsSentence=${fragment.endsSentence} '
        'boxes=${fragment.boundingBoxes.length} '
        'ruby=${fragment.annotations.length} '
        'head=${_debugRect(fragment.headBoundingBox)} '
        'tail=${_debugRect(fragment.tailBoundingBox)} '
        'text="${fragment.text}"',
      );
    }
  }

  void _debugUnits(List<CameraTextUnit> units) {
    if (!kDebugMode || !_debugOcrPipeline) return;

    debugPrint('[Camera OCR] ===== FINAL TEXT UNITS =====');

    for (var index = 0; index < units.length; index++) {
      final unit = units[index];
      debugPrint(
        '[Camera OCR] UNIT $index '
        'orientation=${unit.orientation.name} '
        'boxes=${unit.boundingBoxes.length} '
        'ruby=${unit.annotations.length} '
        'text="${unit.text}"',
      );
    }
  }

  void _debugBoundary({
    required int number,
    required _CameraTextFragment current,
    required _CameraTextFragment next,
    required _CameraBoundaryLanguageEvidence languageEvidence,
    required double confidence,
    required bool shouldMerge,
    bool isInferredTextBox = false,
  }) {
    if (!kDebugMode || !_debugOcrPipeline) return;

    final currentText = current.text.trim();
    final nextText = next.text.trim();
    final geometryPasses = _passesCrossLineGeometry(current, next);
    final hardBoundary = current.endsSentence ||
        _endsWithHardSentenceBoundary(currentText);
    final listMarker = _looksLikeListMarker(nextText);
    final continuationPunctuation =
        RegExp(r'[、，,「『（\(\[]$').hasMatch(currentText);
    final startsWithContinuation = _startsWithContinuation(nextText);
    final endsWithContinuation =
        _endsWithGrammaticalContinuation(currentText);
    final lexicalBridge = _bestLexicalBridge(
      currentText,
      nextText,
      languageEvidence,
    );
    final splitScriptBridge = _looksLikeJapaneseWordContinuesAcrossBoundary(
      currentText,
      nextText,
    );
    final softSentenceEnd = _looksLikeSoftSentenceEnd(currentText);
    final verticalColumnTransition =
        _isVerticalColumnTransition(current, next);
    final verticalProsePair = verticalColumnTransition &&
        _looksLikeVerticalProseColumn(current) &&
        _looksLikeVerticalProseColumn(next);
    final verticalIncomplete = verticalProsePair &&
        !_looksLikeSoftSentenceEnd(currentText) &&
        !_endsWithHardSentenceBoundary(currentText);
    final nextClosesSentence =
        next.endsSentence || _endsWithHardSentenceBoundary(nextText);
    final currentLength = _japaneseContentLength(currentText);
    final nextLength = _japaneseContentLength(nextText);
    final textBoxContinuation = isInferredTextBox &&
        verticalColumnTransition &&
        currentLength >= 4 &&
        nextLength >= 2 &&
        !_looksLikeSoftSentenceEnd(currentText);

    final reasons = <String>[
      'orientation=${current.orientation.name}',
      'geometry=$geometryPasses',
      'hardBoundary=$hardBoundary',
      'listMarker=$listMarker',
      'continuationPunctuation=$continuationPunctuation',
      'startsWithContinuation=$startsWithContinuation',
      'endsWithContinuation=$endsWithContinuation',
      'lexicalBridge=${lexicalBridge ?? '-'}',
      'splitScriptBridge=$splitScriptBridge',
      'softSentenceEnd=$softSentenceEnd',
      'verticalColumnTransition=$verticalColumnTransition',
      'verticalProsePair=$verticalProsePair',
      'verticalIncomplete=$verticalIncomplete',
      'nextClosesSentence=$nextClosesSentence',
      'sameTextBox=$isInferredTextBox',
      'textBoxContinuation=$textBoxContinuation',
    ];

    debugPrint('[Camera OCR] ----- BOUNDARY $number -----');
    debugPrint('[Camera OCR] A="$currentText"');
    debugPrint('[Camera OCR] B="$nextText"');
    debugPrint(
      '[Camera OCR] score=${confidence.toStringAsFixed(3)} '
      'threshold=0.560 JOIN=${shouldMerge ? 'YES' : 'NO'}',
    );
    debugPrint('[Camera OCR] ${reasons.join(' | ')}');

    final candidates = _crossBoundarySurfaceCandidates(currentText, nextText)
        .toList()
      ..sort((first, second) {
        final lengthDifference = second.length.compareTo(first.length);
        if (lengthDifference != 0) return lengthDifference;
        return first.compareTo(second);
      });

    if (candidates.isNotEmpty) {
      final sample = candidates.take(12).join(', ');
      debugPrint('[Camera OCR] bridgeCandidates=$sample');
    }
  }

  String _debugRect(Rect rect) {
    return '('
        '${rect.left.toStringAsFixed(1)},'
        '${rect.top.toStringAsFixed(1)},'
        '${rect.right.toStringAsFixed(1)},'
        '${rect.bottom.toStringAsFixed(1)})';
  }

  String _debugConfidence(double? confidence) {
    if (confidence == null) return '-';
    return confidence.toStringAsFixed(3);
  }

  _CameraRubyClassification _classifyRubyAnnotations(
    List<_CameraRawLine> lines,
  ) {
    if (lines.length < 2) {
      return _CameraRubyClassification(
        primaryLines: List<_CameraRawLine>.from(lines),
      );
    }

    final annotationIndexes = <int>{};
    final annotationsByPrimaryIndex = <int, List<CameraTextAnnotation>>{};
    final attachments = <_CameraRubyAttachment>[];

    for (var candidateIndex = 0;
        candidateIndex < lines.length;
        candidateIndex++) {
      final candidate = lines[candidateIndex];

      if (!_looksLikeRubyText(candidate.text)) continue;

      var bestPrimaryIndex = -1;
      var bestScore = double.negativeInfinity;

      for (var primaryIndex = 0;
          primaryIndex < lines.length;
          primaryIndex++) {
        if (primaryIndex == candidateIndex) continue;

        final primary = lines[primaryIndex];
        final score = _rubyAttachmentScore(
          ruby: candidate,
          primary: primary,
        );

        if (score == null || score <= bestScore) continue;

        bestScore = score;
        bestPrimaryIndex = primaryIndex;
      }

      // Keep this intentionally conservative. A missed furigana line is less
      // harmful than deleting a genuine short kana label from the text stream.
      if (bestPrimaryIndex < 0 || bestScore < 0.62) continue;

      final primary = lines[bestPrimaryIndex];
      final annotation = CameraTextAnnotation(
        text: candidate.text,
        boundingBox: candidate.boundingBox,
        confidence: candidate.confidence,
        orientation: candidate.orientation,
      );

      annotationIndexes.add(candidateIndex);
      annotationsByPrimaryIndex
          .putIfAbsent(bestPrimaryIndex, () => <CameraTextAnnotation>[])
          .add(annotation);
      attachments.add(
        _CameraRubyAttachment(
          annotation: annotation,
          primaryText: primary.text,
          primaryBoundingBox: primary.boundingBox,
          score: bestScore,
        ),
      );
    }

    final primaryLines = <_CameraRawLine>[];

    for (var index = 0; index < lines.length; index++) {
      if (annotationIndexes.contains(index)) continue;

      final annotations = annotationsByPrimaryIndex[index] ?? const [];
      final primaryLine = lines[index];
      final sortedAnnotations = List<CameraTextAnnotation>.from(annotations)
        ..sort((first, second) {
          if (primaryLine.orientation == CameraTextOrientation.vertical) {
            final vertical =
                first.boundingBox.top.compareTo(second.boundingBox.top);
            if (vertical != 0) return vertical;
            return second.boundingBox.right.compareTo(first.boundingBox.right);
          }

          final horizontal =
              first.boundingBox.left.compareTo(second.boundingBox.left);
          if (horizontal != 0) return horizontal;
          return first.boundingBox.top.compareTo(second.boundingBox.top);
        });

      primaryLines.add(
        primaryLine.copyWith(annotations: sortedAnnotations),
      );
    }

    return _CameraRubyClassification(
      primaryLines: primaryLines,
      attachments: attachments,
    );
  }

  bool _looksLikeRubyText(String value) {
    final text = value.replaceAll(RegExp(r'\s+'), '');
    if (text.isEmpty) return false;

    final japaneseLength = _japaneseContentLength(text);
    if (japaneseLength == 0 || japaneseLength > 12) return false;

    // Ruby should never contain kanji. Manga OCR can, however, contaminate a
    // short reading with one junk glyph (for example Sちぞく), so classify
    // kana-dominant side text rather than requiring perfectly clean kana.
    if (RegExp(
      r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々〆ヶ]',
    ).hasMatch(text)) {
      return false;
    }

    final kanaCount = RegExp(
      r'[\u3041-\u3096\u30A1-\u30FA]',
    ).allMatches(text).length;
    if (kanaCount == 0) return false;

    final stripped = text.replaceAll(
      RegExp(
        r'[\u3041-\u3096\u30A1-\u30FAー・･…〜~\-、，。！？?!.,]',
      ),
      '',
    );
    final noiseCount = stripped.runes.length;

    if (noiseCount == 0) return true;

    // One OCR-noise glyph is tolerated only when the rest is clearly a kana
    // reading. This keeps product codes and genuine mixed-script labels out.
    if (noiseCount > 1 || kanaCount < 2) return false;

    final kanaRatio = kanaCount / (kanaCount + noiseCount);
    return kanaRatio >= 0.67;
  }

  double? _rubyAttachmentScore({
    required _CameraRawLine ruby,
    required _CameraRawLine primary,
  }) {
    if (!_containsKanji(primary.text)) return null;

    final rubyBox = ruby.boundingBox;
    final primaryBox = primary.boundingBox;

    if (rubyBox.height <= 0 || primaryBox.height <= 0) return null;
    if (rubyBox.width <= 0 || primaryBox.width <= 0) return null;

    double? score;

    if (primary.orientation == CameraTextOrientation.vertical) {
      score = _verticalRubyAttachmentScore(
        rubyBox: rubyBox,
        primaryBox: primaryBox,
      );

      // ML Kit often keeps ruby and its base kanji in the same block even
      // when it emits them as separate TextLine objects. Treat that as
      // supporting evidence, never as enough evidence on its own.
      if (score != null && ruby.blockIndex == primary.blockIndex) {
        score += 0.10;
      }
    } else {
      score = _horizontalRubyAttachmentScore(
        rubyBox: rubyBox,
        primaryBox: primaryBox,
      );
    }

    return score?.clamp(0.0, 1.0).toDouble();
  }

  double? _horizontalRubyAttachmentScore({
    required Rect rubyBox,
    required Rect primaryBox,
  }) {
    final heightRatio = rubyBox.height / primaryBox.height;

    if (heightRatio >= 0.70) return null;
    if (rubyBox.center.dy >= primaryBox.center.dy) return null;

    final verticalGap = primaryBox.top - rubyBox.bottom;
    if (verticalGap < -rubyBox.height * 0.55) return null;
    if (verticalGap > primaryBox.height * 0.58) return null;

    final overlapLeft =
        rubyBox.left > primaryBox.left ? rubyBox.left : primaryBox.left;
    final overlapRight =
        rubyBox.right < primaryBox.right ? rubyBox.right : primaryBox.right;
    final horizontalOverlap =
        (overlapRight - overlapLeft).clamp(0.0, double.infinity);
    final overlapRatio =
        (horizontalOverlap / rubyBox.width).clamp(0.0, 1.0).toDouble();
    final centerInsidePrimary = rubyBox.center.dx >=
            primaryBox.left - rubyBox.width * 0.35 &&
        rubyBox.center.dx <= primaryBox.right + rubyBox.width * 0.35;

    if (overlapRatio < 0.20 && !centerInsidePrimary) return null;

    final normalizedGap =
        (verticalGap.abs() / primaryBox.height).clamp(0.0, 1.0).toDouble();
    final sizeEvidence =
        ((0.70 - heightRatio) / 0.70).clamp(0.0, 1.0).toDouble();
    final verticalEvidence = (1.0 - normalizedGap).clamp(0.0, 1.0);
    final horizontalEvidence = overlapRatio >= 0.20
        ? overlapRatio
        : (centerInsidePrimary ? 0.45 : 0.0);

    return (sizeEvidence * 0.44 +
            verticalEvidence * 0.31 +
            horizontalEvidence * 0.25)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double? _verticalRubyAttachmentScore({
    required Rect rubyBox,
    required Rect primaryBox,
  }) {
    final widthRatio = rubyBox.width / primaryBox.width;

    // Vertical ruby is a narrow side-track immediately to the RIGHT of the
    // main column. Size alone is not enough: small kana such as っ/ゃ/ゅ/ょ
    // can live on the primary axis, while furigana sits clearly off-axis.
    if (widthRatio >= 0.72) return null;
    if (rubyBox.center.dx <= primaryBox.center.dx) return null;

    final axisOffset = rubyBox.center.dx - primaryBox.center.dx;
    final axisOffsetRatio = axisOffset / primaryBox.width;

    // Keep the inner edge strict enough to protect real small kana, but allow
    // a wider outer window for manga ruby whose OCR box can sit almost one
    // primary-column width to the right.
    if (axisOffsetRatio < 0.28 || axisOffsetRatio > 1.12) return null;

    final horizontalGap = rubyBox.left - primaryBox.right;
    if (horizontalGap < -rubyBox.width * 0.78) return null;
    if (horizontalGap > primaryBox.width * 0.62) return null;

    final overlapTop =
        rubyBox.top > primaryBox.top ? rubyBox.top : primaryBox.top;
    final overlapBottom =
        rubyBox.bottom < primaryBox.bottom ? rubyBox.bottom : primaryBox.bottom;
    final verticalOverlap =
        (overlapBottom - overlapTop).clamp(0.0, double.infinity);
    final overlapRatio =
        (verticalOverlap / rubyBox.height).clamp(0.0, 1.0).toDouble();

    if (overlapRatio < 0.22) return null;

    final sizeEvidence =
        ((0.72 - widthRatio) / 0.72).clamp(0.0, 1.0).toDouble();
    final axisEvidence =
        (1.0 - ((axisOffsetRatio - 0.64).abs() / 0.64))
            .clamp(0.0, 1.0)
            .toDouble();
    final verticalEvidence = overlapRatio.clamp(0.0, 1.0).toDouble();

    // A tiny physical gap at the side of the kanji column is particularly
    // strong ruby evidence. This catches manga readings such as てき / とも /
    // ひとだす without lowering the global ruby threshold.
    final normalizedSideGap = primaryBox.width <= 0
        ? 1.0
        : (horizontalGap.abs() / primaryBox.width)
            .clamp(0.0, 1.0)
            .toDouble();
    final sideTrackEvidence = (1.0 - normalizedSideGap).clamp(0.0, 1.0);

    return (sizeEvidence * 0.26 +
            axisEvidence * 0.30 +
            verticalEvidence * 0.24 +
            sideTrackEvidence * 0.20)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  List<_CameraRawLine> _resolveOverlappingVerticalPrimaryLines(
    List<_CameraRawLine> lines,
  ) {
    if (lines.length < 2) return List<_CameraRawLine>.from(lines);

    final resolved = <_CameraRawLine>[];

    for (final candidate in lines) {
      if (candidate.orientation != CameraTextOrientation.vertical) {
        resolved.add(candidate);
        continue;
      }

      var duplicateIndex = -1;

      for (var index = 0; index < resolved.length; index++) {
        final existing = resolved[index];

        if (existing.orientation != CameraTextOrientation.vertical) continue;
        if (!_looksLikeOverlappingVerticalHypothesis(existing, candidate)) {
          continue;
        }

        duplicateIndex = index;
        break;
      }

      if (duplicateIndex < 0) {
        resolved.add(candidate);
        continue;
      }

      final existing = resolved[duplicateIndex];
      final fused = _fuseOverlappingVerticalHypotheses(
        existing,
        candidate,
      );

      if (kDebugMode && _debugOcrPipeline) {
        final shared = _longestSharedJapaneseRunMatch(
          existing.text,
          candidate.text,
        );
        debugPrint(
          '[Camera OCR] VERTICAL OVERLAP fusion '
          'first="${existing.text}" second="${candidate.text}" '
          'shared="${shared?.text ?? '-'}" fused="${fused.text}" '
          'box=${_debugRect(fused.boundingBox)}',
        );
      }

      resolved[duplicateIndex] = fused;
    }

    return resolved;
  }

  bool _looksLikeOverlappingVerticalHypothesis(
    _CameraRawLine first,
    _CameraRawLine second,
  ) {
    final firstBox = first.boundingBox;
    final secondBox = second.boundingBox;
    if (firstBox.width <= 0 || secondBox.width <= 0) return false;
    if (firstBox.height <= 0 || secondBox.height <= 0) return false;

    final overlapLeft =
        firstBox.left > secondBox.left ? firstBox.left : secondBox.left;
    final overlapRight =
        firstBox.right < secondBox.right ? firstBox.right : secondBox.right;
    final horizontalOverlap =
        (overlapRight - overlapLeft).clamp(0.0, double.infinity);
    final narrowerWidth =
        firstBox.width < secondBox.width ? firstBox.width : secondBox.width;
    final horizontalOverlapRatio =
        (horizontalOverlap / narrowerWidth).clamp(0.0, 1.0).toDouble();

    final overlapTop =
        firstBox.top > secondBox.top ? firstBox.top : secondBox.top;
    final overlapBottom =
        firstBox.bottom < secondBox.bottom ? firstBox.bottom : secondBox.bottom;
    final verticalOverlap =
        (overlapBottom - overlapTop).clamp(0.0, double.infinity);
    final shorterHeight =
        firstBox.height < secondBox.height ? firstBox.height : secondBox.height;
    final verticalOverlapRatio =
        (verticalOverlap / shorterHeight).clamp(0.0, 1.0).toDouble();

    final centerDifference =
        (firstBox.center.dx - secondBox.center.dx).abs();
    final referenceWidth =
        firstBox.width > secondBox.width ? firstBox.width : secondBox.width;
    final sameAxis = centerDifference <= referenceWidth * 0.24;

    if (!sameAxis || horizontalOverlapRatio < 0.72) return false;
    if (verticalOverlapRatio < 0.52) return false;

    return _longestSharedJapaneseRun(first.text, second.text) >= 3;
  }

  _CameraRawLine _fuseOverlappingVerticalHypotheses(
    _CameraRawLine first,
    _CameraRawLine second,
  ) {
    final match = _longestSharedJapaneseRunMatch(first.text, second.text);

    // The duplicate detector already requires a meaningful shared Japanese
    // run, but keep a safe fallback in case future tuning relaxes that gate.
    if (match == null || match.length < 3) {
      return _preferredOverlappingVerticalHypothesis(first, second);
    }

    final firstText = first.text.replaceAll(RegExp(r'\s+'), '');
    final secondText = second.text.replaceAll(RegExp(r'\s+'), '');

    final leading = first.boundingBox.top <= second.boundingBox.top
        ? first
        : second;
    final trailing = first.boundingBox.bottom >= second.boundingBox.bottom
        ? first
        : second;

    // If a single hypothesis already owns both the earliest top and latest
    // bottom, it already covers the complete physical span. Prefer it rather
    // than manufacturing a longer string from a nested reread.
    if (identical(leading, trailing)) {
      return _preferredOverlappingVerticalHypothesis(first, second);
    }

    final leadingText = identical(leading, first) ? firstText : secondText;
    final trailingText = identical(trailing, first) ? firstText : secondText;
    final leadingMatchStart = identical(leading, first)
        ? match.firstStart
        : match.secondStart;
    final trailingMatchStart = identical(trailing, first)
        ? match.firstStart
        : match.secondStart;

    final prefix = leadingText.substring(0, leadingMatchStart);
    final shared = match.text;
    final suffixStart = trailingMatchStart + match.length;
    final suffix = suffixStart < trailingText.length
        ? trailingText.substring(suffixStart)
        : '';
    final fusedText = '$prefix$shared$suffix';

    final longestSourceLength = firstText.length > secondText.length
        ? firstText.length
        : secondText.length;

    // Fusion must add complementary coverage, not explode two similar reads
    // into an implausibly long duplicate string.
    if (fusedText.length < longestSourceLength ||
        fusedText.length > firstText.length + secondText.length - match.length) {
      return _preferredOverlappingVerticalHypothesis(first, second);
    }

    final mergedAnnotations = <CameraTextAnnotation>[];
    final annotationKeys = <String>{};

    for (final annotation in <CameraTextAnnotation>[
      ...first.annotations,
      ...second.annotations,
    ]) {
      final box = annotation.boundingBox;
      final key = '${annotation.text}|'
          '${box.left.toStringAsFixed(1)}|${box.top.toStringAsFixed(1)}|'
          '${box.right.toStringAsFixed(1)}|${box.bottom.toStringAsFixed(1)}';
      if (!annotationKeys.add(key)) continue;
      mergedAnnotations.add(annotation);
    }

    mergedAnnotations.sort((a, b) {
      final vertical = a.boundingBox.top.compareTo(b.boundingBox.top);
      if (vertical != 0) return vertical;
      return b.boundingBox.right.compareTo(a.boundingBox.right);
    });

    final firstConfidence = first.confidence;
    final secondConfidence = second.confidence;
    double? fusedConfidence;

    if (firstConfidence != null && secondConfidence != null) {
      final firstWeight = _japaneseContentLength(firstText).clamp(1, 9999);
      final secondWeight = _japaneseContentLength(secondText).clamp(1, 9999);
      fusedConfidence =
          ((firstConfidence * firstWeight) +
                  (secondConfidence * secondWeight)) /
              (firstWeight + secondWeight);
    } else {
      fusedConfidence = firstConfidence ?? secondConfidence;
    }

    final fusedAngle = first.angle != null && second.angle != null
        ? (first.angle! + second.angle!) / 2
        : first.angle ?? second.angle;

    return _CameraRawLine(
      text: fusedText,
      boundingBox: first.boundingBox.expandToInclude(second.boundingBox),
      blockIndex: leading.blockIndex,
      confidence: fusedConfidence,
      angle: fusedAngle,
      orientation: CameraTextOrientation.vertical,
      annotations: mergedAnnotations,
    );
  }

  _CameraRawLine _preferredOverlappingVerticalHypothesis(
    _CameraRawLine first,
    _CameraRawLine second,
  ) {
    // Prefer the hypothesis that covers more of the physical column. This is
    // safer than confidence alone: ML Kit can return a high-confidence partial
    // reread of the lower half of an already detected vertical column.
    final heightDifference = first.boundingBox.height - second.boundingBox.height;
    final largerHeight = first.boundingBox.height > second.boundingBox.height
        ? first.boundingBox.height
        : second.boundingBox.height;

    if (largerHeight > 0 && heightDifference.abs() / largerHeight >= 0.10) {
      return heightDifference >= 0 ? first : second;
    }

    final firstTop = first.boundingBox.top;
    final secondTop = second.boundingBox.top;
    if ((firstTop - secondTop).abs() >= 24) {
      return firstTop <= secondTop ? first : second;
    }

    final firstConfidence = first.confidence ?? 0.0;
    final secondConfidence = second.confidence ?? 0.0;
    return firstConfidence >= secondConfidence ? first : second;
  }

  int _longestSharedJapaneseRun(String first, String second) {
    return _longestSharedJapaneseRunMatch(first, second)?.length ?? 0;
  }

  _CameraSharedRunMatch? _longestSharedJapaneseRunMatch(
    String first,
    String second,
  ) {
    final a = first.replaceAll(RegExp(r'\s+'), '');
    final b = second.replaceAll(RegExp(r'\s+'), '');
    if (a.isEmpty || b.isEmpty) return null;

    var bestLength = 0;
    var bestFirstEnd = 0;
    var bestSecondEnd = 0;
    final previous = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);

      for (var j = 1; j <= b.length; j++) {
        if (a[i - 1] != b[j - 1]) continue;
        if (!_isJapaneseCharacter(a[i - 1])) continue;

        current[j] = previous[j - 1] + 1;
        if (current[j] > bestLength) {
          bestLength = current[j];
          bestFirstEnd = i;
          bestSecondEnd = j;
        }
      }

      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }

    if (bestLength == 0) return null;

    final firstStart = bestFirstEnd - bestLength;
    final secondStart = bestSecondEnd - bestLength;

    return _CameraSharedRunMatch(
      firstStart: firstStart,
      secondStart: secondStart,
      length: bestLength,
      text: a.substring(firstStart, bestFirstEnd),
    );
  }

  bool _containsKanji(String value) {
    return RegExp(
      r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々〆ヶ]',
    ).hasMatch(value);
  }

  List<CameraTextAnnotation> _annotationsForBoundingBox(
    List<CameraTextAnnotation> annotations,
    Rect boundingBox, {
    required CameraTextOrientation orientation,
  }) {
    if (annotations.isEmpty) return const [];

    return annotations.where((annotation) {
      final box = annotation.boundingBox;

      if (orientation == CameraTextOrientation.vertical) {
        final overlapTop = box.top > boundingBox.top ? box.top : boundingBox.top;
        final overlapBottom =
            box.bottom < boundingBox.bottom ? box.bottom : boundingBox.bottom;
        final overlap =
            (overlapBottom - overlapTop).clamp(0.0, double.infinity);
        final denominator = box.height <= 0 ? 1.0 : box.height;
        return overlap / denominator >= 0.18;
      }

      final overlapLeft =
          box.left > boundingBox.left ? box.left : boundingBox.left;
      final overlapRight =
          box.right < boundingBox.right ? box.right : boundingBox.right;
      final overlap =
          (overlapRight - overlapLeft).clamp(0.0, double.infinity);
      final denominator = box.width <= 0 ? 1.0 : box.width;
      return overlap / denominator >= 0.18;
    }).toList(growable: false);
  }

  Future<void> dispose() async {
    await _textRecognizer.close();
  }

  List<_CameraTextFragment> _splitLineIntoSentenceFragments({
    required String text,
    required Rect boundingBox,
    required int blockIndex,
    required List<CameraTextAnnotation> annotations,
    required CameraTextOrientation orientation,
  }) {
    final fragments = <_CameraTextFragment>[];
    final sentenceEndPattern = RegExp(r'[。！？!?]+[」』】）\)\]]*');
    var start = 0;

    for (final match in sentenceEndPattern.allMatches(text)) {
      final end = match.end;
      final fragmentText = text.substring(start, end).trim();

      if (fragmentText.isNotEmpty && _containsJapaneseCore(fragmentText)) {
        final fragmentBox = _sliceBoundingBox(
          fullText: text,
          boundingBox: boundingBox,
          start: start,
          end: end,
          orientation: orientation,
        );

        fragments.add(
          _CameraTextFragment(
            text: fragmentText,
            boundingBoxes: <Rect>[fragmentBox],
            annotations: _annotationsForBoundingBox(
              annotations,
              fragmentBox,
              orientation: orientation,
            ),
            blockIndex: blockIndex,
            orientation: orientation,
            endsSentence: true,
          ),
        );
      }

      start = end;
    }

    if (start < text.length) {
      final fragmentText = text.substring(start).trim();

      if (fragmentText.isNotEmpty && _containsJapaneseCore(fragmentText)) {
        final fragmentBox = _sliceBoundingBox(
          fullText: text,
          boundingBox: boundingBox,
          start: start,
          end: text.length,
          orientation: orientation,
        );

        fragments.add(
          _CameraTextFragment(
            text: fragmentText,
            boundingBoxes: <Rect>[fragmentBox],
            annotations: _annotationsForBoundingBox(
              annotations,
              fragmentBox,
              orientation: orientation,
            ),
            blockIndex: blockIndex,
            orientation: orientation,
            endsSentence: false,
          ),
        );
      }
    }

    if (fragments.isEmpty && _containsJapaneseCore(text)) {
      fragments.add(
        _CameraTextFragment(
          text: text,
          boundingBoxes: <Rect>[boundingBox],
          annotations: annotations,
          blockIndex: blockIndex,
          orientation: orientation,
          endsSentence: false,
        ),
      );
    }

    return fragments;
  }

  List<_CameraTextFragment> _orderFragmentsByVisualRows(
    List<_CameraTextFragment> fragments,
  ) {
    if (fragments.length <= 1) {
      return List<_CameraTextFragment>.from(fragments);
    }

    final positiveHeights = fragments
        .map((fragment) => fragment.boundingBox.height)
        .where((height) => height > 0)
        .toList()
      ..sort();

    final medianHeight = positiveHeights.isEmpty
        ? 1.0
        : positiveHeights[positiveHeights.length ~/ 2];
    final oversizedThreshold = medianHeight * 1.65;

    final normalFragments = fragments
        .where((fragment) => fragment.boundingBox.height <= oversizedThreshold)
        .toList()
      ..sort(_compareFragmentsByTopThenLeft);
    final oversizedFragments = fragments
        .where((fragment) => fragment.boundingBox.height > oversizedThreshold)
        .toList()
      ..sort(_compareFragmentsByTopThenLeft);

    final rows = <_CameraVisualRow>[];

    for (final fragment in normalFragments) {
      final row = _bestVisualRowForFragment(
        fragment: fragment,
        rows: rows,
        medianHeight: medianHeight,
        oversized: false,
      );

      if (row == null) {
        rows.add(_CameraVisualRow(fragment));
      } else {
        row.addAnchorFragment(fragment);
      }
    }

    // Tall decorative glyphs (for example the large leading カ in the test
    // page) can have centers that fall between two real text rows. Attach them
    // only after normal-height rows exist, using overlap and top alignment.
    for (final fragment in oversizedFragments) {
      final row = _bestVisualRowForFragment(
        fragment: fragment,
        rows: rows,
        medianHeight: medianHeight,
        oversized: true,
      );

      if (row == null) {
        rows.add(_CameraVisualRow(fragment));
      } else {
        row.addDetachedFragment(fragment);
      }
    }

    rows.sort((first, second) {
      final vertical = first.anchorBoundingBox.center.dy
          .compareTo(second.anchorBoundingBox.center.dy);
      if (vertical != 0) return vertical;
      return first.anchorBoundingBox.left
          .compareTo(second.anchorBoundingBox.left);
    });

    final ordered = <_CameraTextFragment>[];

    for (final row in rows) {
      row.fragments.sort((first, second) {
        final horizontal =
            first.boundingBox.left.compareTo(second.boundingBox.left);
        if (horizontal != 0) return horizontal;
        return first.boundingBox.top.compareTo(second.boundingBox.top);
      });
      ordered.addAll(row.fragments);
    }

    return ordered;
  }

  _CameraVisualRow? _bestVisualRowForFragment({
    required _CameraTextFragment fragment,
    required List<_CameraVisualRow> rows,
    required double medianHeight,
    required bool oversized,
  }) {
    if (rows.isEmpty) return null;

    final box = fragment.boundingBox;
    _CameraVisualRow? bestRow;
    var bestScore = double.negativeInfinity;

    for (final row in rows) {
      final rowBox = row.anchorBoundingBox;
      final overlapTop = box.top > rowBox.top ? box.top : rowBox.top;
      final overlapBottom =
          box.bottom < rowBox.bottom ? box.bottom : rowBox.bottom;
      final overlap = (overlapBottom - overlapTop).clamp(0.0, double.infinity);
      final shorterHeight =
          box.height < rowBox.height ? box.height : rowBox.height;
      final overlapRatio = shorterHeight <= 0
          ? 0.0
          : (overlap / shorterHeight).clamp(0.0, 1.0).toDouble();
      final centerDifference = (box.center.dy - rowBox.center.dy).abs();
      final topDifference = (box.top - rowBox.top).abs();
      final safeMedian = medianHeight <= 0 ? 1.0 : medianHeight;

      bool eligible;
      double score;

      if (oversized) {
        final rowCoverage = rowBox.height <= 0
            ? 0.0
            : (overlap / rowBox.height).clamp(0.0, 1.0).toDouble();
        eligible = rowCoverage >= 0.58 ||
            topDifference <= safeMedian * 0.48;
        score = rowCoverage * 5.0 +
            overlapRatio * 1.5 -
            (topDifference / safeMedian) * 1.35 -
            (centerDifference / safeMedian) * 0.12;
      } else {
        eligible = overlapRatio >= 0.38 ||
            centerDifference <= safeMedian * 0.58;
        score = overlapRatio * 4.0 -
            (centerDifference / safeMedian) * 1.25 -
            (topDifference / safeMedian) * 0.15;
      }

      if (!eligible || score <= bestScore) continue;

      bestScore = score;
      bestRow = row;
    }

    return bestRow;
  }

  int _compareFragmentsByTopThenLeft(
    _CameraTextFragment first,
    _CameraTextFragment second,
  ) {
    final topDifference =
        first.boundingBox.top.compareTo(second.boundingBox.top);
    if (topDifference != 0) return topDifference;
    return first.boundingBox.left.compareTo(second.boundingBox.left);
  }

  List<_CameraVerticalTextBox> _clusterVerticalFragmentsIntoTextBoxes(
    List<_CameraTextFragment> fragments,
  ) {
    if (fragments.isEmpty) return const [];

    if (fragments.length == 1) {
      return <_CameraVerticalTextBox>[
        _CameraVerticalTextBox(<_CameraTextFragment>[fragments.first]),
      ];
    }

    final positiveWidths = fragments
        .map((fragment) => fragment.boundingBox.width)
        .where((width) => width > 0)
        .toList()
      ..sort();
    final medianWidth = positiveWidths.isEmpty
        ? 1.0
        : positiveWidths[positiveWidths.length ~/ 2];

    // Build local connected components. Unlike the old broad page-region
    // graph, a connection now means these fragments plausibly occupy the same
    // dialogue/menu/text box, not merely the same general part of the page.
    final visited = List<bool>.filled(fragments.length, false);
    final boxes = <_CameraVerticalTextBox>[];

    for (var startIndex = 0; startIndex < fragments.length; startIndex++) {
      if (visited[startIndex]) continue;

      final queue = <int>[startIndex];
      final boxFragments = <_CameraTextFragment>[];
      visited[startIndex] = true;

      while (queue.isNotEmpty) {
        final currentIndex = queue.removeLast();
        final current = fragments[currentIndex];
        boxFragments.add(current);

        for (var candidateIndex = 0;
            candidateIndex < fragments.length;
            candidateIndex++) {
          if (visited[candidateIndex]) continue;

          final candidate = fragments[candidateIndex];
          if (!_verticalFragmentsShareTextBox(
            current,
            candidate,
            medianWidth,
          )) {
            continue;
          }

          visited[candidateIndex] = true;
          queue.add(candidateIndex);
        }
      }

      boxes.add(_CameraVerticalTextBox(boxFragments));
    }

    // Stable page ordering only. Japanese reading order is still resolved
    // independently inside each inferred box.
    boxes.sort((first, second) {
      final firstBox = first.boundingBox;
      final secondBox = second.boundingBox;
      final referenceWidth = medianWidth <= 0 ? 1.0 : medianWidth;
      final topDifference = firstBox.top - secondBox.top;

      if (topDifference.abs() > referenceWidth * 1.8) {
        return firstBox.top.compareTo(secondBox.top);
      }

      final horizontal = secondBox.right.compareTo(firstBox.right);
      if (horizontal != 0) return horizontal;
      return firstBox.top.compareTo(secondBox.top);
    });

    return boxes;
  }

  bool _verticalFragmentsShareTextBox(
    _CameraTextFragment first,
    _CameraTextFragment second,
    double medianWidth,
  ) {
    if (first.orientation != CameraTextOrientation.vertical ||
        second.orientation != CameraTextOrientation.vertical) {
      return false;
    }

    final firstBox = first.boundingBox;
    final secondBox = second.boundingBox;
    final safeWidth = medianWidth <= 0 ? 1.0 : medianWidth;

    final overlapTop =
        firstBox.top > secondBox.top ? firstBox.top : secondBox.top;
    final overlapBottom =
        firstBox.bottom < secondBox.bottom ? firstBox.bottom : secondBox.bottom;
    final verticalOverlap =
        (overlapBottom - overlapTop).clamp(0.0, double.infinity);
    final shorterHeight = firstBox.height < secondBox.height
        ? firstBox.height
        : secondBox.height;
    final verticalOverlapRatio = shorterHeight <= 0
        ? 0.0
        : (verticalOverlap / shorterHeight).clamp(0.0, 1.0).toDouble();

    final horizontalGap = _rectAxisGap(
      firstBox.left,
      firstBox.right,
      secondBox.left,
      secondBox.right,
    );
    final verticalGap = _rectAxisGap(
      firstBox.top,
      firstBox.bottom,
      secondBox.top,
      secondBox.bottom,
    );
    final centerXDifference =
        (firstBox.center.dx - secondBox.center.dx).abs();
    final topDifference = (firstBox.top - secondBox.top).abs();
    final bottomDifference = (firstBox.bottom - secondBox.bottom).abs();

    // Pieces on the same writing axis may be fragments of one physical
    // column, but only bridge a genuinely small vertical interruption. The
    // old 3.15x-width allowance was what let upper and lower dialogue bands
    // collapse into one giant region.
    final sameAxis = centerXDifference <= safeWidth * 0.86;
    if (sameAxis) {
      if (verticalOverlapRatio >= 0.16) return true;
      return verticalGap <= safeWidth * 0.82;
    }

    // Different columns must be local neighbors in BOTH axes. This naturally
    // creates inferred boxes around manga dialogue and separates menu rows or
    // unrelated captions even when their global X positions are adjacent.
    final neighboringColumns =
        horizontalGap <= safeWidth * 2.45 &&
        centerXDifference <= safeWidth * 3.45;
    if (!neighboringColumns) return false;

    if (verticalOverlapRatio >= 0.30) return true;

    // Uneven tategaki columns inside one bubble can start/end slightly apart,
    // but a visible blank band should split them into separate text boxes.
    final locallyAlignedTop = topDifference <= safeWidth * 1.45;
    final locallyAlignedBottom = bottomDifference <= safeWidth * 1.45;
    final smallBandGap = verticalGap <= safeWidth * 0.82;

    return smallBandGap && (locallyAlignedTop || locallyAlignedBottom);
  }

  double _rectAxisGap(
    double firstStart,
    double firstEnd,
    double secondStart,
    double secondEnd,
  ) {
    if (firstEnd < secondStart) return secondStart - firstEnd;
    if (secondEnd < firstStart) return firstStart - secondEnd;
    return 0.0;
  }

  List<_CameraTextFragment> _orderFragmentsByVisualColumns(
    List<_CameraTextFragment> fragments,
  ) {
    if (fragments.length <= 1) {
      return List<_CameraTextFragment>.from(fragments);
    }

    final positiveWidths = fragments
        .map((fragment) => fragment.boundingBox.width)
        .where((width) => width > 0)
        .toList()
      ..sort();

    final medianWidth = positiveWidths.isEmpty
        ? 1.0
        : positiveWidths[positiveWidths.length ~/ 2];
    final oversizedThreshold = medianWidth * 1.65;

    final normalFragments = fragments
        .where((fragment) => fragment.boundingBox.width <= oversizedThreshold)
        .toList()
      ..sort(_compareFragmentsByRightThenTop);
    final oversizedFragments = fragments
        .where((fragment) => fragment.boundingBox.width > oversizedThreshold)
        .toList()
      ..sort(_compareFragmentsByRightThenTop);

    final columns = <_CameraVisualColumn>[];

    for (final fragment in normalFragments) {
      final column = _bestVisualColumnForFragment(
        fragment: fragment,
        columns: columns,
        medianWidth: medianWidth,
        oversized: false,
      );

      if (column == null) {
        columns.add(_CameraVisualColumn(fragment));
      } else {
        column.addAnchorFragment(fragment);
      }
    }

    // Wide decorative fragments are attached only after stable columns exist,
    // mirroring the horizontal large-glyph handling used by the existing path.
    for (final fragment in oversizedFragments) {
      final column = _bestVisualColumnForFragment(
        fragment: fragment,
        columns: columns,
        medianWidth: medianWidth,
        oversized: true,
      );

      if (column == null) {
        columns.add(_CameraVisualColumn(fragment));
      } else {
        column.addDetachedFragment(fragment);
      }
    }

    // Traditional Japanese vertical text reads top -> bottom within a column,
    // then continues into the next column to the left.
    columns.sort((first, second) {
      final horizontal = second.anchorBoundingBox.center.dx
          .compareTo(first.anchorBoundingBox.center.dx);
      if (horizontal != 0) return horizontal;
      return first.anchorBoundingBox.top.compareTo(second.anchorBoundingBox.top);
    });

    final ordered = <_CameraTextFragment>[];

    for (final column in columns) {
      column.fragments.sort((first, second) {
        final vertical = first.boundingBox.top.compareTo(second.boundingBox.top);
        if (vertical != 0) return vertical;
        return second.boundingBox.right.compareTo(first.boundingBox.right);
      });
      ordered.addAll(column.fragments);
    }

    return ordered;
  }

  _CameraVisualColumn? _bestVisualColumnForFragment({
    required _CameraTextFragment fragment,
    required List<_CameraVisualColumn> columns,
    required double medianWidth,
    required bool oversized,
  }) {
    if (columns.isEmpty) return null;

    final box = fragment.boundingBox;
    _CameraVisualColumn? bestColumn;
    var bestScore = double.negativeInfinity;

    for (final column in columns) {
      final columnBox = column.anchorBoundingBox;
      final overlapLeft = box.left > columnBox.left ? box.left : columnBox.left;
      final overlapRight =
          box.right < columnBox.right ? box.right : columnBox.right;
      final overlap = (overlapRight - overlapLeft).clamp(0.0, double.infinity);
      final narrowerWidth = box.width < columnBox.width ? box.width : columnBox.width;
      final overlapRatio = narrowerWidth <= 0
          ? 0.0
          : (overlap / narrowerWidth).clamp(0.0, 1.0).toDouble();
      final centerDifference = (box.center.dx - columnBox.center.dx).abs();
      final rightDifference = (box.right - columnBox.right).abs();
      final safeMedian = medianWidth <= 0 ? 1.0 : medianWidth;

      bool eligible;
      double score;

      if (oversized) {
        final columnCoverage = columnBox.width <= 0
            ? 0.0
            : (overlap / columnBox.width).clamp(0.0, 1.0).toDouble();
        eligible = columnCoverage >= 0.58 ||
            rightDifference <= safeMedian * 0.52;
        score = columnCoverage * 5.0 +
            overlapRatio * 1.5 -
            (rightDifference / safeMedian) * 1.35 -
            (centerDifference / safeMedian) * 0.12;
      } else {
        // The center-axis corridor is the primary signal for vertical text.
        // This deliberately tolerates small kana that are shifted slightly to
        // the right while still rejecting a separate neighboring ruby track.
        final insideColumnCorridor = centerDifference <= safeMedian * 0.64;
        eligible = overlapRatio >= 0.32 || insideColumnCorridor;
        score = overlapRatio * 3.8 +
            (insideColumnCorridor ? 1.15 : 0.0) -
            (centerDifference / safeMedian) * 1.20 -
            (rightDifference / safeMedian) * 0.12;
      }

      if (!eligible || score <= bestScore) continue;

      bestScore = score;
      bestColumn = column;
    }

    return bestColumn;
  }

  int _compareFragmentsByRightThenTop(
    _CameraTextFragment first,
    _CameraTextFragment second,
  ) {
    final horizontal =
        second.boundingBox.right.compareTo(first.boundingBox.right);
    if (horizontal != 0) return horizontal;
    return first.boundingBox.top.compareTo(second.boundingBox.top);
  }

  List<_CameraTextFragment> _mergeSameVisualLineFragments(
    List<_CameraTextFragment> fragments,
  ) {
    if (fragments.isEmpty) return const [];

    final merged = <_CameraTextFragment>[];

    for (final next in fragments) {
      if (merged.isEmpty) {
        merged.add(next);
        continue;
      }

      final current = merged.last;

      if (!_shouldMergeOnSameVisualLine(current, next)) {
        merged.add(next);
        continue;
      }

      merged[merged.length - 1] = _CameraTextFragment(
        text: _joinText(current.text, next.text),
        boundingBoxes: <Rect>[
          ...current.boundingBoxes,
          ...next.boundingBoxes,
        ],
        annotations: <CameraTextAnnotation>[
          ...current.annotations,
          ...next.annotations,
        ],
        blockIndex: current.blockIndex,
        orientation: current.orientation,
        endsSentence: next.endsSentence,
      );
    }

    return merged;
  }

  bool _shouldMergeOnSameVisualLine(
    _CameraTextFragment current,
    _CameraTextFragment next,
  ) {
    if (current.orientation != CameraTextOrientation.horizontal ||
        next.orientation != CameraTextOrientation.horizontal) {
      return false;
    }
    if (current.endsSentence) return false;

    final currentBox = current.boundingBox;
    final nextBox = next.boundingBox;
    final averageHeight = (currentBox.height + nextBox.height) / 2;
    if (averageHeight <= 0) return false;

    final overlapTop =
        currentBox.top > nextBox.top ? currentBox.top : nextBox.top;
    final overlapBottom =
        currentBox.bottom < nextBox.bottom ? currentBox.bottom : nextBox.bottom;
    final verticalOverlap = overlapBottom - overlapTop;
    final shorterHeight =
        currentBox.height < nextBox.height ? currentBox.height : nextBox.height;
    final overlapRatio = shorterHeight <= 0
        ? 0.0
        : (verticalOverlap / shorterHeight).clamp(0.0, 1.0).toDouble();
    final centerDifference =
        (currentBox.center.dy - nextBox.center.dy).abs();
    final sameRow = overlapRatio >= 0.45 ||
        centerDifference <= averageHeight * 0.42;

    if (!sameRow) return false;

    final horizontalGap = nextBox.left - currentBox.right;
    if (horizontalGap < -averageHeight * 0.35) return false;
    if (horizontalGap > averageHeight * 1.55) return false;

    final currentLength = _japaneseContentLength(current.text);
    final nextLength = _japaneseContentLength(next.text);

    // A detached one- or two-character fragment next to a longer Japanese
    // line is very often part of that same printed line. This recovers large
    // decorative/initial glyphs without combining distant labels.
    if (currentLength <= 2 || nextLength <= 2) {
      return horizontalGap <= averageHeight * 1.55;
    }

    // ML Kit can also divide an ordinary printed line into neighboring blocks.
    // Only bridge those when the physical gap is tight.
    return horizontalGap <= averageHeight * 0.72;
  }

  List<_CameraTextFragment> _mergeSameVisualColumnFragments(
    List<_CameraTextFragment> fragments,
  ) {
    if (fragments.isEmpty) return const [];

    final merged = <_CameraTextFragment>[];

    for (final next in fragments) {
      if (merged.isEmpty) {
        merged.add(next);
        continue;
      }

      final current = merged.last;

      if (!_shouldMergeOnSameVisualColumn(current, next)) {
        merged.add(next);
        continue;
      }

      merged[merged.length - 1] = _CameraTextFragment(
        text: _joinText(current.text, next.text),
        boundingBoxes: <Rect>[
          ...current.boundingBoxes,
          ...next.boundingBoxes,
        ],
        annotations: <CameraTextAnnotation>[
          ...current.annotations,
          ...next.annotations,
        ],
        blockIndex: current.blockIndex,
        orientation: CameraTextOrientation.vertical,
        endsSentence: next.endsSentence,
      );
    }

    return merged;
  }

  bool _shouldMergeOnSameVisualColumn(
    _CameraTextFragment current,
    _CameraTextFragment next,
  ) {
    if (current.endsSentence) return false;
    if (current.orientation != CameraTextOrientation.vertical ||
        next.orientation != CameraTextOrientation.vertical) {
      return false;
    }

    final currentBox = current.boundingBox;
    final nextBox = next.boundingBox;
    final averageWidth = (currentBox.width + nextBox.width) / 2;
    if (averageWidth <= 0) return false;

    final overlapLeft =
        currentBox.left > nextBox.left ? currentBox.left : nextBox.left;
    final overlapRight =
        currentBox.right < nextBox.right ? currentBox.right : nextBox.right;
    final horizontalOverlap = overlapRight - overlapLeft;
    final narrowerWidth =
        currentBox.width < nextBox.width ? currentBox.width : nextBox.width;
    final overlapRatio = narrowerWidth <= 0
        ? 0.0
        : (horizontalOverlap / narrowerWidth).clamp(0.0, 1.0).toDouble();
    final centerDifference =
        (currentBox.center.dx - nextBox.center.dx).abs();
    final referenceWidth = currentBox.width > nextBox.width
        ? currentBox.width
        : nextBox.width;
    final insideColumnCorridor =
        centerDifference <= referenceWidth * 0.58;
    final sameColumn = overlapRatio >= 0.40 || insideColumnCorridor;

    if (!sameColumn) return false;

    final verticalGap = nextBox.top - currentBox.bottom;
    if (verticalGap < -averageWidth * 0.35) return false;
    if (verticalGap > averageWidth * 1.55) return false;

    final currentLength = _japaneseContentLength(current.text);
    final nextLength = _japaneseContentLength(next.text);

    if (currentLength <= 2 || nextLength <= 2) {
      return verticalGap <= averageWidth * 1.55;
    }

    return verticalGap <= averageWidth * 0.72;
  }

  List<CameraTextUnit> _combineOrientationUnits(
    List<CameraTextUnit> horizontalUnits,
    List<CameraTextUnit> verticalUnits,
  ) {
    if (horizontalUnits.isEmpty) {
      return List<CameraTextUnit>.from(verticalUnits);
    }

    if (verticalUnits.isEmpty) {
      return List<CameraTextUnit>.from(horizontalUnits);
    }

    final combined = <CameraTextUnit>[
      ...horizontalUnits,
      ...verticalUnits,
    ];

    // Mixed-orientation pages are common in manga (vertical dialogue with
    // horizontal labels/SFX). Units are already internally reconstructed in
    // the correct orientation; this final sort is only for stable overlay
    // coloring and does not alter text inside a unit.
    combined.sort((first, second) {
      final topDifference =
          first.boundingBox.top.compareTo(second.boundingBox.top);
      final averageHeight =
          (first.boundingBox.height + second.boundingBox.height) / 2;

      if (topDifference.abs() > averageHeight * 0.35) {
        return topDifference;
      }

      if (first.orientation == CameraTextOrientation.vertical &&
          second.orientation == CameraTextOrientation.vertical) {
        return second.boundingBox.right.compareTo(first.boundingBox.right);
      }

      return first.boundingBox.left.compareTo(second.boundingBox.left);
    });

    return combined;
  }

  Future<List<CameraTextUnit>> _mergeFragmentsIntoTextUnits(
    List<_CameraTextFragment> fragments, {
    bool isInferredTextBox = false,
  }) async {
    if (fragments.isEmpty) return const [];

    final languageEvidence = await _buildBoundaryLanguageEvidence(fragments);
    final units = <CameraTextUnit>[];
    _CameraTextFragment? current;
    var boundaryNumber = 0;

    void flushCurrent() {
      final fragment = current;
      if (fragment == null) return;

      if (_containsJapaneseCore(fragment.text)) {
        units.add(
          CameraTextUnit(
            text: fragment.text.trim(),
            boundingBoxes: fragment.boundingBoxes,
            annotations: fragment.annotations,
            orientation: fragment.orientation,
          ),
        );
      }

      current = null;
    }

    for (final next in fragments) {
      final active = current;

      if (active == null) {
        current = next;

        if (next.endsSentence) {
          flushCurrent();
        }

        continue;
      }

      final confidence = _lineConnectionConfidence(
        active,
        next,
        languageEvidence,
        isInferredTextBox: isInferredTextBox,
      );
      final shouldMerge = confidence >= 0.56;

      _debugBoundary(
        number: boundaryNumber++,
        current: active,
        next: next,
        languageEvidence: languageEvidence,
        confidence: confidence,
        shouldMerge: shouldMerge,
        isInferredTextBox: isInferredTextBox,
      );

      if (shouldMerge) {
        current = _CameraTextFragment(
          text: _joinText(active.text, next.text),
          boundingBoxes: <Rect>[
            ...active.boundingBoxes,
            ...next.boundingBoxes,
          ],
          annotations: <CameraTextAnnotation>[
            ...active.annotations,
            ...next.annotations,
          ],
          blockIndex: active.blockIndex,
          orientation: active.orientation,
          endsSentence: next.endsSentence,
        );

        if (next.endsSentence) {
          flushCurrent();
        }

        continue;
      }

      flushCurrent();
      current = next;

      if (next.endsSentence) {
        flushCurrent();
      }
    }

    flushCurrent();

    return units;
  }

  Future<_CameraBoundaryLanguageEvidence> _buildBoundaryLanguageEvidence(
    List<_CameraTextFragment> fragments,
  ) async {
    if (fragments.length < 2) {
      return const _CameraBoundaryLanguageEvidence();
    }

    final surfaces = <String>{};
    final deinflectionsBySurface = <String, Set<String>>{};
    final lookupQueries = <String>{};

    for (var index = 0; index < fragments.length - 1; index++) {
      final current = fragments[index];
      final next = fragments[index + 1];

      if (!_passesCrossLineGeometry(current, next)) continue;

      for (final surface in _crossBoundarySurfaceCandidates(
        current.text,
        next.text,
      )) {
        surfaces.add(surface);
        lookupQueries.add(surface);

        final deinflections =
            JapaneseConjugationService.deinflectionCandidates(surface);
        if (deinflections.isEmpty) continue;

        deinflectionsBySurface[surface] = deinflections;
        lookupQueries.addAll(deinflections);
      }
    }

    if (lookupQueries.isEmpty) {
      return const _CameraBoundaryLanguageEvidence();
    }

    try {
      final results = await DictionaryService.findExactJapaneseBatch(
        lookupQueries,
        perQueryLimit: 4,
      );
      final lexicalSurfaces = <String>{};

      for (final surface in surfaces) {
        if ((results[surface] ?? const []).isNotEmpty) {
          lexicalSurfaces.add(surface);
          continue;
        }

        final deinflections = deinflectionsBySurface[surface];
        if (deinflections == null) continue;

        var matched = false;

        for (final dictionaryForm in deinflections) {
          final terms = results[dictionaryForm] ?? const [];

          for (final term in terms) {
            if (JapaneseConjugationService.surfaceMatchesTerm(term, surface)) {
              lexicalSurfaces.add(surface);
              matched = true;
              break;
            }
          }

          if (matched) break;
        }
      }

      return _CameraBoundaryLanguageEvidence(
        lexicalSurfaces: lexicalSurfaces,
      );
    } catch (_) {
      // Dictionary evidence improves line joining, but OCR must remain usable
      // even if the dictionary is unavailable during this best-effort pass.
      return const _CameraBoundaryLanguageEvidence();
    }
  }

  double _lineConnectionConfidence(
    _CameraTextFragment current,
    _CameraTextFragment next,
    _CameraBoundaryLanguageEvidence languageEvidence, {
    bool isInferredTextBox = false,
  }) {
    if (current.orientation != next.orientation) return 0;
    if (current.endsSentence) return 0;
    if (_endsWithHardSentenceBoundary(current.text)) return 0;
    if (_looksLikeListMarker(next.text)) return 0;

    final geometryPasses = _passesCrossLineGeometry(current, next);
    if (!geometryPasses) return 0;

    final currentText = current.text.trim();
    final nextText = next.text.trim();
    final currentLength = _japaneseContentLength(currentText);
    final nextLength = _japaneseContentLength(nextText);
    final combinedLength = currentLength + nextLength;
    final sameMlKitBlock = current.blockIndex == next.blockIndex;
    final hasContinuationPunctuation =
        RegExp(r'[、，,「『（\(\[]$').hasMatch(currentText);
    final startsWithContinuation = _startsWithContinuation(nextText);
    final endsWithContinuation = _endsWithGrammaticalContinuation(currentText);
    final lexicalBridge = _bestLexicalBridge(
      currentText,
      nextText,
      languageEvidence,
    );
    final splitScriptBridge = _looksLikeJapaneseWordContinuesAcrossBoundary(
      currentText,
      nextText,
    );
    final verticalColumnTransition =
        _isVerticalColumnTransition(current, next);
    final verticalProsePair = verticalColumnTransition &&
        _looksLikeVerticalProseColumn(current) &&
        _looksLikeVerticalProseColumn(next);
    final verticalIncomplete = verticalProsePair &&
        !_looksLikeSoftSentenceEnd(currentText) &&
        !_endsWithHardSentenceBoundary(currentText);
    final nextClosesSentence =
        next.endsSentence || _endsWithHardSentenceBoundary(nextText);
    final textBoxContinuation = isInferredTextBox &&
        verticalColumnTransition &&
        currentLength >= 4 &&
        nextLength >= 2 &&
        !_looksLikeSoftSentenceEnd(currentText);

    var score = 0.0;

    // Physical proximity is only the starting point. The final decision is
    // intentionally linguistic-first so ordinary prose can survive line wraps.
    score += 0.14;

    if (current.orientation == CameraTextOrientation.vertical) {
      score += 0.05;
    }

    // Tategaki prose commonly continues from the bottom of one column into
    // the top of the adjacent column to its left. Once visual-column ordering
    // has established a clean neighboring pair, lack of sentence-final
    // punctuation is strong evidence that the thought is still incomplete.
    // This is intentionally separate from lexical bridge logic because a
    // perfectly normal break such as 長い間 + ありがとうございました does not
    // split a single dictionary word at the boundary.
    if (verticalProsePair) {
      score += 0.24;

      if (verticalIncomplete) score += 0.16;
      if (nextClosesSentence) score += 0.12;
    }

    // The inferred text box is a useful structural prior: adjacent substantial
    // columns inside one bubble/menu region are more likely to continue even
    // when one OCR character destroys dictionary evidence. Keep the bonus
    // modest so punctuation and explicit sentence endings remain authoritative.
    if (textBoxContinuation) score += 0.14;

    if (sameMlKitBlock) score += 0.08;
    if (hasContinuationPunctuation) score += 0.42;
    if (startsWithContinuation && currentLength >= 2) score += 0.30;
    if (endsWithContinuation) score += 0.28;

    if (lexicalBridge != null) {
      score += 0.36;

      if (_looksLikeWordSplitAtBoundary(
        currentText,
        nextText,
        lexicalBridge,
      )) {
        score += 0.20;
      }
    }

    // This catches very common Japanese line-wrap seams even when dictionary
    // lookup misses the exact surface. Examples include 成功 + し and 向 + かう.
    if (splitScriptBridge) score += 0.34;

    if (currentLength >= 6) score += 0.07;
    if (nextLength >= 4) score += 0.06;
    if (combinedLength >= 12) score += 0.07;

    // A polite/plain finite ending is evidence that the line may already be a
    // complete sentence, but continuation evidence can still outweigh it.
    if (_looksLikeSoftSentenceEnd(currentText) && !startsWithContinuation) {
      score -= 0.38;
    }

    // Very short neighboring labels should not be glued together just because
    // they happen to sit close to one another.
    if (currentLength <= 2 && nextLength <= 2 && lexicalBridge == null) {
      score -= 0.35;
    }

    return score.clamp(0.0, 1.0).toDouble();
  }

  bool _isVerticalColumnTransition(
    _CameraTextFragment current,
    _CameraTextFragment next,
  ) {
    if (current.orientation != CameraTextOrientation.vertical ||
        next.orientation != CameraTextOrientation.vertical) {
      return false;
    }

    final currentBox = current.tailBoundingBox;
    final nextBox = next.headBoundingBox;
    final averageWidth = (currentBox.width + nextBox.width) / 2;
    if (averageWidth <= 0) return false;

    // Same-column fragments are handled before sentence reconstruction. A
    // true tategaki transition moves to a distinct neighboring column on the
    // left.
    final centerDifference =
        (currentBox.center.dx - nextBox.center.dx).abs();
    if (centerDifference <= averageWidth * 0.72) return false;
    if (nextBox.center.dx >= currentBox.center.dx) return false;

    final horizontalGap = currentBox.left - nextBox.right;
    return horizontalGap >= -averageWidth * 0.65 &&
        horizontalGap <= averageWidth * 2.45;
  }

  bool _looksLikeVerticalProseColumn(_CameraTextFragment fragment) {
    if (fragment.orientation != CameraTextOrientation.vertical) return false;

    final japaneseLength = _japaneseContentLength(fragment.text);
    if (japaneseLength < 4) return false;

    final box = fragment.boundingBox;
    if (box.width <= 0 || box.height <= 0) return false;

    // Real prose columns are normally substantially taller than they are wide.
    // Requiring this prevents the extra cross-column confidence from joining
    // compact labels, prices, issue numbers, or isolated manga annotations.
    return box.height >= box.width * 1.65;
  }

  bool _looksLikeJapaneseWordContinuesAcrossBoundary(
    String current,
    String next,
  ) {
    final left = _japaneseBoundaryCore(current, fromEnd: true);
    final right = _japaneseBoundaryCore(next, fromEnd: false);

    if (left.isEmpty || right.isEmpty) return false;

    final leftChar = left.substring(left.length - 1);
    final rightChar = right.substring(0, 1);
    final currentLength = _japaneseContentLength(current);
    final nextLength = _japaneseContentLength(next);

    // A kanji stem followed by hiragana is one of the strongest visual signs
    // that a Japanese word was split by line wrapping: 向 + かう, 成功 + し.
    if (_isKanjiCharacter(leftChar) && _isHiraganaCharacter(rightChar)) {
      return currentLength >= 4 && nextLength >= 2;
    }

    // Kana-to-kana wrapping also occurs, but it is much easier to over-merge,
    // so only use it for substantial prose lines.
    if (_isKanaCharacter(leftChar) && _isKanaCharacter(rightChar)) {
      return currentLength >= 7 && nextLength >= 4;
    }

    return false;
  }

  bool _isHiraganaCharacter(String value) {
    if (value.isEmpty) return false;
    return RegExp(r'^[\u3041-\u3096]$').hasMatch(value);
  }

  bool _passesCrossLineGeometry(
    _CameraTextFragment current,
    _CameraTextFragment next,
  ) {
    if (current.orientation != next.orientation) return false;

    if (current.orientation == CameraTextOrientation.vertical) {
      return _passesVerticalFlowGeometry(current, next);
    }

    final currentBox = current.tailBoundingBox;
    final nextBox = next.headBoundingBox;
    final averageHeight = (currentBox.height + nextBox.height) / 2;

    if (averageHeight <= 0) return false;

    final verticalGap = nextBox.top - currentBox.bottom;
    if (verticalGap > averageHeight * 1.55) return false;
    if (verticalGap < -averageHeight * 0.6) return false;

    final overlapWidth =
        (currentBox.right < nextBox.right ? currentBox.right : nextBox.right) -
            (currentBox.left > nextBox.left ? currentBox.left : nextBox.left);
    final narrowerWidth = currentBox.width < nextBox.width
        ? currentBox.width
        : nextBox.width;
    final horizontalOverlap = narrowerWidth <= 0
        ? 0.0
        : (overlapWidth / narrowerWidth).clamp(0.0, 1.0).toDouble();
    final leftDifference = (currentBox.left - nextBox.left).abs();

    return horizontalOverlap >= 0.22 ||
        leftDifference <= averageHeight * 5.0;
  }

  bool _passesVerticalFlowGeometry(
    _CameraTextFragment current,
    _CameraTextFragment next,
  ) {
    final currentBox = current.tailBoundingBox;
    final nextBox = next.headBoundingBox;
    final averageWidth = (currentBox.width + nextBox.width) / 2;

    if (averageWidth <= 0) return false;

    final centerDifference =
        (currentBox.center.dx - nextBox.center.dx).abs();
    final sameColumn = centerDifference <= averageWidth * 0.72;

    if (sameColumn) {
      final verticalGap = nextBox.top - currentBox.bottom;
      return verticalGap <= averageWidth * 1.65 &&
          verticalGap >= -averageWidth * 0.65;
    }

    // Moving to the next tategaki column means moving left. Once visual-column
    // ordering has established that sequence, allow a linguistic boundary test
    // when the neighboring columns are physically close enough.
    if (nextBox.center.dx >= currentBox.center.dx) return false;

    final horizontalGap = currentBox.left - nextBox.right;
    if (horizontalGap > averageWidth * 2.45) return false;
    if (horizontalGap < -averageWidth * 0.65) return false;

    final overlapTop =
        currentBox.top > nextBox.top ? currentBox.top : nextBox.top;
    final overlapBottom =
        currentBox.bottom < nextBox.bottom ? currentBox.bottom : nextBox.bottom;
    final verticalOverlap =
        (overlapBottom - overlapTop).clamp(0.0, double.infinity);
    final shorterHeight = currentBox.height < nextBox.height
        ? currentBox.height
        : nextBox.height;
    final overlapRatio = shorterHeight <= 0
        ? 0.0
        : (verticalOverlap / shorterHeight).clamp(0.0, 1.0).toDouble();

    return current.blockIndex == next.blockIndex ||
        overlapRatio >= 0.10 ||
        horizontalGap <= averageWidth * 1.45;
  }

  String? _bestLexicalBridge(
    String current,
    String next,
    _CameraBoundaryLanguageEvidence languageEvidence,
  ) {
    String? best;

    for (final surface in _crossBoundarySurfaceCandidates(current, next)) {
      if (!languageEvidence.lexicalSurfaces.contains(surface)) continue;

      if (best == null ||
          _japaneseContentLength(surface) > _japaneseContentLength(best)) {
        best = surface;
      }
    }

    return best;
  }

  Set<String> _crossBoundarySurfaceCandidates(
    String current,
    String next,
  ) {
    final left = _japaneseBoundaryCore(current, fromEnd: true);
    final right = _japaneseBoundaryCore(next, fromEnd: false);

    if (left.isEmpty || right.isEmpty) return const <String>{};

    final candidates = <String>{};
    final maxLeft = left.length.clamp(1, 4).toInt();
    final maxRight = right.length.clamp(1, 5).toInt();

    for (var leftLength = 1; leftLength <= maxLeft; leftLength++) {
      final suffix = left.substring(left.length - leftLength);

      for (var rightLength = 1; rightLength <= maxRight; rightLength++) {
        final prefix = right.substring(0, rightLength);
        final candidate = '$suffix$prefix';
        final japaneseLength = _japaneseContentLength(candidate);

        if (japaneseLength < 2 || japaneseLength > 8) continue;
        candidates.add(candidate);
      }
    }

    return candidates;
  }

  String _japaneseBoundaryCore(
    String value, {
    required bool fromEnd,
  }) {
    final text = value.trim();
    if (text.isEmpty) return '';

    final matches = RegExp(
      r'[\u3041-\u3096\u30A1-\u30FA\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々〆ヶ]+',
    ).allMatches(text).toList(growable: false);

    if (matches.isEmpty) return '';

    final match = fromEnd ? matches.last : matches.first;

    if (fromEnd && match.end != text.length) return '';
    if (!fromEnd && match.start != 0) return '';

    return match.group(0) ?? '';
  }

  bool _looksLikeWordSplitAtBoundary(
    String current,
    String next,
    String lexicalBridge,
  ) {
    final left = _japaneseBoundaryCore(current, fromEnd: true);
    final right = _japaneseBoundaryCore(next, fromEnd: false);

    if (left.isEmpty || right.isEmpty) return false;

    final leftBoundary = left.substring(left.length - 1);
    final rightBoundary = right.substring(0, 1);
    final kanjiToKana = _isKanjiCharacter(leftBoundary) &&
        _isKanaCharacter(rightBoundary);
    final kanaToKana = _isKanaCharacter(leftBoundary) &&
        _isKanaCharacter(rightBoundary);

    if (kanjiToKana) return true;

    // Kana-only splits are accepted only for a longer validated lexical form;
    // this avoids joining nearby labels because two kana happen to make a word.
    return kanaToKana && _japaneseContentLength(lexicalBridge) >= 3;
  }

  bool _endsWithHardSentenceBoundary(String value) {
    return RegExp(r'[。！？!?‼⁉]+[」』】）\)\]]*$').hasMatch(value.trim());
  }

  bool _endsWithGrammaticalContinuation(String value) {
    final text = value.trim();

    return RegExp(
      r'(へと|として|について|によって|により|ので|のに|のは|けど|けれど|けれども|ながら|から|まで|より|って|では|には|とは|ても|でも|て|で|を|が|に|へ|と|の|し)$',
    ).hasMatch(text);
  }

  bool _isKanjiCharacter(String value) {
    if (value.isEmpty) return false;

    return RegExp(
      r'^[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々〆ヶ]$',
    ).hasMatch(value);
  }

  bool _isKanaCharacter(String value) {
    if (value.isEmpty) return false;

    return RegExp(r'^[\u3041-\u3096\u30A1-\u30FA]$').hasMatch(value);
  }

  bool _looksLikeSoftSentenceEnd(String value) {
    final text = value.trim();

    return RegExp(
      r'(でした|ました|ません|でしょう|です|ます|だった|である|ください|下さい|宜しく|よろしく|だね|だよ)$',
    ).hasMatch(text);
  }

  bool _startsWithContinuation(String value) {
    final text = value.trimLeft();

    return RegExp(
      r'^(が|けど|けれど|けれども|ので|のに|し|て|で|と|を|に|へ|から|まで|なら|ならば|でも)',
    ).hasMatch(text);
  }

  bool _looksLikeListMarker(String value) {
    final text = value.trimLeft();

    return RegExp(r'^[・●○■□◆◇※★☆▶▷►▸➤→←↑↓]').hasMatch(text);
  }

  String _joinText(String first, String second) {
    final left = first.trimRight();
    final right = second.trimLeft();

    if (left.isEmpty) return right;
    if (right.isEmpty) return left;

    // Japanese normally does not need an inserted space when OCR wraps one
    // sentence across multiple visual lines. Preserve an existing OCR space
    // only when both sides are primarily Latin/digit text.
    if (_endsWithLatinOrDigit(left) && _startsWithLatinOrDigit(right)) {
      return '$left $right';
    }

    return '$left$right';
  }

  bool _endsWithLatinOrDigit(String value) {
    return RegExp(r'[A-Za-z0-9]$').hasMatch(value);
  }

  bool _startsWithLatinOrDigit(String value) {
    return RegExp(r'^[A-Za-z0-9]').hasMatch(value);
  }

  int _japaneseContentLength(String value) {
    return RegExp(
      r'[\u3041-\u3096\u30A1-\u30FA\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々〆ヶ]',
    ).allMatches(value).length;
  }

  String _japaneseCoreSequence(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      if (_isJapaneseCharacter(character)) {
        buffer.write(character);
      }
    }
    return buffer.toString();
  }

  Rect _sliceBoundingBox({
    required String fullText,
    required Rect boundingBox,
    required int start,
    required int end,
    required CameraTextOrientation orientation,
  }) {
    if (fullText.isEmpty || start <= 0 && end >= fullText.length) {
      return boundingBox;
    }

    final safeStart = start.clamp(0, fullText.length);
    final safeEnd = end.clamp(safeStart, fullText.length);
    final startRatio = safeStart / fullText.length;
    final endRatio = safeEnd / fullText.length;

    if (orientation == CameraTextOrientation.horizontal) {
      return Rect.fromLTRB(
        boundingBox.left + (boundingBox.width * startRatio),
        boundingBox.top,
        boundingBox.left + (boundingBox.width * endRatio),
        boundingBox.bottom,
      );
    }

    return Rect.fromLTRB(
      boundingBox.left,
      boundingBox.top + (boundingBox.height * startRatio),
      boundingBox.right,
      boundingBox.top + (boundingBox.height * endRatio),
    );
  }

  Future<List<_CameraRawLine>> _verifyLowConfidenceVerticalLines({
    required String imagePath,
    required Size imageSize,
    required List<_CameraRawLine> lines,
    Set<int> skipLineIndexes = const <int>{},
  }) async {
    const maxVerificationLines = 10;

    final candidateIndexes = <int>[
      for (var index = 0; index < lines.length; index++)
        if (!skipLineIndexes.contains(index) &&
            _shouldVerifyVerticalPhysicalLine(lines[index]))
          index,
    ];

    if (candidateIndexes.isEmpty) {
      if (kDebugMode && _debugOcrPipeline && skipLineIndexes.isNotEmpty) {
        debugPrint('[Camera OCR] ===== LOW-CONFIDENCE OCR VERIFICATION =====');
        debugPrint(
          '[Camera OCR] eligible=0 selected=0 max=$maxVerificationLines '
          'skippedByPaddle=${skipLineIndexes.length}',
        );
      }
      return lines;
    }

    candidateIndexes.sort((firstIndex, secondIndex) {
      final first = lines[firstIndex];
      final second = lines[secondIndex];
      final firstPriority = _verticalVerificationPriority(first);
      final secondPriority = _verticalVerificationPriority(second);
      final priorityDifference = secondPriority.compareTo(firstPriority);
      if (priorityDifference != 0) return priorityDifference;
      return firstIndex.compareTo(secondIndex);
    });

    final selectedIndexes = candidateIndexes
        .take(maxVerificationLines)
        .toSet();

    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;
    final temporaryDirectory = await getTemporaryDirectory();
    final verifiedLines = <_CameraRawLine>[];

    if (kDebugMode && _debugOcrPipeline) {
      debugPrint('[Camera OCR] ===== LOW-CONFIDENCE OCR VERIFICATION =====');
      debugPrint(
        '[Camera OCR] eligible=${candidateIndexes.length} '
        'selected=${selectedIndexes.length} max=$maxVerificationLines '
        'skippedByPaddle=${skipLineIndexes.length}',
      );
    }

    final textBoxAttempts = <int, List<_CameraVerificationAttempt>>{};

    try {
      try {
        textBoxAttempts.addAll(
          await _collectVerticalTextBoxVerificationAttempts(
            sourceImage: sourceImage,
            imageSize: imageSize,
            lines: lines,
            selectedLineIndexes: selectedIndexes,
            directory: temporaryDirectory,
          ),
        );
      } catch (_) {
        // Contextual box verification is optional. Per-line verification still
        // runs even if box inference/rendering fails unexpectedly.
      }

      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];

        if (!selectedIndexes.contains(index)) {
          verifiedLines.add(line);
          continue;
        }

        final attempts = <_CameraVerificationAttempt>[
          ...?textBoxAttempts[index],
        ];
        final temporaryFiles = <File>[];
        final originalConfidence = line.confidence ?? 0.0;

        try {
          final naturalFile = await _renderVerticalVerificationImage(
            sourceImage: sourceImage,
            imageSize: imageSize,
            line: line,
            directory: temporaryDirectory,
            index: index,
            enhanced: false,
          );
          temporaryFiles.add(naturalFile);

          final naturalRecognition = await _textRecognizer.processImage(
            InputImage.fromFilePath(naturalFile.path),
          );
          final naturalCandidate = _bestVerticalVerificationCandidate(
            recognizedText: naturalRecognition,
            original: line,
          );

          if (naturalCandidate != null) {
            attempts.add(
              _CameraVerificationAttempt(
                label: 'enlarged',
                candidate: naturalCandidate,
              ),
            );
          }

          // A second rendering is most useful when the first retry either
          // failed to produce a usable line or disagreed with the full-photo
          // OCR. This keeps the extra work focused on exactly the uncertain
          // characters we are trying to verify instead of rerunning every
          // low-confidence column twice. Very weak originals still receive the
          // second pass even when the first retry repeats the same text.
          final attemptEnhancedVariant =
              originalConfidence < 0.35 ||
              naturalCandidate == null ||
              naturalCandidate.text != line.text;

          if (attemptEnhancedVariant) {
            final enhancedFile = await _renderVerticalVerificationImage(
              sourceImage: sourceImage,
              imageSize: imageSize,
              line: line,
              directory: temporaryDirectory,
              index: index,
              enhanced: true,
            );
            temporaryFiles.add(enhancedFile);

            final enhancedRecognition = await _textRecognizer.processImage(
              InputImage.fromFilePath(enhancedFile.path),
            );
            final enhancedCandidate = _bestVerticalVerificationCandidate(
              recognizedText: enhancedRecognition,
              original: line,
            );

            if (enhancedCandidate != null) {
              attempts.add(
                _CameraVerificationAttempt(
                  label: 'contrast',
                  candidate: enhancedCandidate,
                ),
              );
            }
          }

          final replacement = await _chooseVerticalVerificationReplacement(
            original: line,
            attempts: attempts,
          );

          if (kDebugMode && _debugOcrPipeline) {
            debugPrint(
              '[Camera OCR] VERIFY line=$index '
              'original="${line.text}" '
              'conf=${_debugConfidence(line.confidence)} '
              'attempts=${attempts.length}',
            );

            for (final attempt in attempts) {
              final candidate = attempt.candidate;
              final accepted = replacement != null &&
                  candidate.text == replacement.text;
              debugPrint(
                '[Camera OCR]   ${attempt.label} '
                'text="${candidate.text}" '
                'conf=${_debugConfidence(candidate.confidence)} '
                'changed=${candidate.text != line.text} '
                'accepted=$accepted',
              );
            }

            debugPrint(
              replacement == null
                  ? '[Camera OCR] VERIFY RESULT keep="${line.text}"'
                  : '[Camera OCR] VERIFY RESULT replace="${line.text}" '
                      '-> "${replacement.text}" '
                      'conf=${_debugConfidence(replacement.confidence)}',
            );
          }

          if (replacement != null) {
            verifiedLines.add(
              line.copyWith(
                text: replacement.text,
                confidence: replacement.confidence,
              ),
            );
          } else {
            verifiedLines.add(line);
          }
        } catch (_) {
          // Verification must never make Camera Mode less reliable. Any crop,
          // encoding, or retry failure simply keeps the original full-photo OCR.
          verifiedLines.add(line);
        } finally {
          for (final file in temporaryFiles) {
            try {
              if (await file.exists()) await file.delete();
            } catch (_) {
              // Temporary verification files are best-effort cleanup only.
            }
          }
        }
      }
    } finally {
      sourceImage.dispose();
      codec.dispose();
    }

    return verifiedLines;
  }

  Future<_CameraPaddleRefinementResult> _refineVerticalLinesWithPaddleOcr({
    required String imagePath,
    required Size imageSize,
    required List<_CameraRawLine> lines,
  }) async {
    final candidateIndexes = <int>[
      for (var index = 0; index < lines.length; index++)
        if (_shouldTryPaddleForVerticalLine(lines[index])) index,
    ];

    if (candidateIndexes.isEmpty ||
        defaultTargetPlatform != TargetPlatform.android) {
      return _CameraPaddleRefinementResult(
        lines: lines,
        confirmedLineIndexes: const <int>{},
        directKeepLineIndexes: const <int>{},
      );
    }

    final cropRequests = <CameraPaddleCropRequest>[
      for (final index in candidateIndexes)
        CameraPaddleCropRequest(
          lineIndex: index,
          cropRect: _paddedPaddleVerticalRect(
            lines[index].boundingBox,
            imageSize,
          ),
        ),
    ];

    if (kDebugMode && _debugOcrPipeline) {
      debugPrint('[Camera OCR] ===== PADDLE LOCALIZED COLUMN OCR =====');
      debugPrint(
        '[Camera OCR] eligible=${candidateIndexes.length} '
        'backend=PP-OCRv5-mobile native-batch-local-column-pipeline',
      );
    }

    final batch = await PaddleCameraOcrService.recognizeLocalizedVerticalCrops(
      imagePath: imagePath,
      imageSize: imageSize,
      crops: cropRequests,
    );

    final refinedLines = List<_CameraRawLine>.from(lines);
    final confirmedLineIndexes = <int>{};
    final directKeepLineIndexes = <int>{};
    var modelTotalMs = 0;
    var detectionTotalMs = 0;
    var recognitionTotalMs = 0;

    for (final index in candidateIndexes) {
      final line = refinedLines[index];
      final paddle = batch?.resultsByLineIndex[index];

      if (paddle == null) {
        if (kDebugMode && _debugOcrPipeline) {
          debugPrint(
            '[Camera OCR] PADDLE line=$index '
            'mlkit="${line.text}" result=- decision=FALLBACK',
          );
        }
        continue;
      }

      modelTotalMs += paddle.totalTimeMs;
      detectionTotalMs += paddle.detectionTimeMs;
      recognitionTotalMs += paddle.recognitionTimeMs;

      final candidateText = _normalizeVerticalSmallKanaByLanguage(
        _cleanLineText(paddle.text),
      );
      final strongEvidence = _isStrongPaddleVerticalEvidence(
        original: line,
        candidateText: candidateText,
        candidateConfidence: paddle.confidence,
      );
      final originalCore = _japaneseCoreSequence(line.text);
      final candidateCore = _japaneseCoreSequence(candidateText);
      final shouldReplace =
          strongEvidence && candidateCore != originalCore;
      final shouldKeepMlKitDirectly = !strongEvidence &&
          _shouldKeepMlKitWithoutLegacyVerification(
            original: line,
            candidateText: candidateText,
            candidateConfidence: paddle.confidence,
          );

      if (strongEvidence) {
        confirmedLineIndexes.add(index);
      } else if (shouldKeepMlKitDirectly) {
        directKeepLineIndexes.add(index);
      }

      if (kDebugMode && _debugOcrPipeline) {
        final decision = shouldReplace
            ? 'REPLACE'
            : strongEvidence
                ? 'CONFIRM'
                : shouldKeepMlKitDirectly
                    ? 'KEEP_MLKIT'
                    : 'FALLBACK';
        debugPrint(
          '[Camera OCR] PADDLE line=$index '
          'mlkit="${line.text}" '
          'paddle="$candidateText" '
          'conf=${paddle.confidence.toStringAsFixed(3)} '
          'items=${paddle.detectedItemCount} '
          'crop=${paddle.cropWidth}x${paddle.cropHeight} '
          'det=${paddle.detectionTimeMs}ms '
          'rec=${paddle.recognitionTimeMs}ms '
          'total=${paddle.totalTimeMs}ms '
          'decision=$decision',
        );
      }

      if (!shouldReplace) continue;

      refinedLines[index] = line.copyWith(
        text: candidateText,
        // Paddle and ML Kit confidence values are not calibrated against one
        // another. Keep the original confidence so later Gakuji layout
        // heuristics are not accidentally retuned by a backend swap.
        confidence: line.confidence,
      );
    }

    if (kDebugMode && _debugOcrPipeline && batch != null) {
      debugPrint(
        '[Camera OCR] PADDLE BATCH '
        'native=${batch.nativeBatchWallTimeMs}ms '
        'decode=${batch.sourceDecodeTimeMs}ms '
        'modelSum=${modelTotalMs}ms '
        'detSum=${detectionTotalMs}ms '
        'recSum=${recognitionTotalMs}ms '
        'confirmed=${confirmedLineIndexes.length}/${candidateIndexes.length} '
        'smartKeep=${directKeepLineIndexes.length}',
      );
    }

    return _CameraPaddleRefinementResult(
      lines: refinedLines,
      confirmedLineIndexes: confirmedLineIndexes,
      directKeepLineIndexes: directKeepLineIndexes,
    );
  }

  Rect _paddedPaddleVerticalRect(Rect rect, Size imageSize) {
    // Paddle's detector already normalizes its own input size. Keep its crop
    // close to the ML Kit main-column geometry instead of rendering a 2.65x
    // PNG first. The asymmetric horizontal padding also avoids reintroducing
    // vertical ruby, which normally sits to the right of the main column.
    final leftPadding = (rect.width * 0.12).clamp(3.0, 14.0).toDouble();
    final rightPadding = (rect.width * 0.08).clamp(2.0, 10.0).toDouble();
    final verticalPadding = (rect.width * 0.16).clamp(4.0, 18.0).toDouble();

    return Rect.fromLTRB(
      (rect.left - leftPadding).clamp(0.0, imageSize.width).toDouble(),
      (rect.top - verticalPadding).clamp(0.0, imageSize.height).toDouble(),
      (rect.right + rightPadding).clamp(0.0, imageSize.width).toDouble(),
      (rect.bottom + verticalPadding).clamp(0.0, imageSize.height).toDouble(),
    );
  }

  bool _shouldTryPaddleForVerticalLine(_CameraRawLine line) {
    if (line.orientation != CameraTextOrientation.vertical) return false;
    if (_japaneseContentLength(line.text) < 2) return false;

    // Tiny boxes are usually ruby/noise that survived classification and do
    // not provide enough pixels for a meaningful localized Paddle pass.
    if (line.boundingBox.width < 12 || line.boundingBox.height < 24) {
      return false;
    }

    return true;
  }

  bool _isStrongPaddleVerticalEvidence({
    required _CameraRawLine original,
    required String candidateText,
    required double candidateConfidence,
  }) {
    if (!_containsJapaneseCore(candidateText)) return false;

    final japaneseRatio = _japaneseCharacterRatio(candidateText);
    if (japaneseRatio < 0.80) return false;

    // Keep the same conservative confidence threshold used by the first
    // Paddle integration. The speed pass changes transport/batching, not the
    // confidence standard required for Paddle to bypass the ML Kit fallback.
    if (candidateConfidence < 0.80) return false;

    final originalCore = _japaneseCoreSequence(original.text);
    final candidateCore = _japaneseCoreSequence(candidateText);
    if (originalCore.isEmpty || candidateCore.isEmpty) return false;

    final originalLength = originalCore.length;
    final candidateLength = candidateCore.length;
    final lengthRatio = candidateLength / originalLength;

    if (candidateText == original.text || candidateCore == originalCore) {
      return true;
    }

    // Paddle may occasionally be highly confident while silently dropping
    // internal kana from an otherwise correct ML Kit line (for example,
    // ジャンプ -> ジンプ). A strict deletion-only reading is supporting
    // evidence for the original, not permission to shorten it. Keep it out of
    // the replacement path and let the smart fallback policy decide whether
    // the original can be trusted directly or needs legacy verification.
    if (_isStrictRuneSubsequence(candidateCore, originalCore)) return false;

    // A differing Paddle result must remain substantially complete. This
    // blocks high-confidence fragments such as a shortened partial sentence
    // from replacing a longer ML Kit column merely because Paddle liked the
    // fragment it managed to read.
    if (lengthRatio < 0.84 || lengthRatio > 1.18) return false;

    final editDistance = _levenshteinDistance(originalCore, candidateCore);
    final longestLength = originalLength > candidateLength
        ? originalLength
        : candidateLength;
    final normalizedDifference = longestLength == 0
        ? 0.0
        : editDistance / longestLength;
    if (normalizedDifference > 0.42) return false;

    final originalPenalty = _suspiciousTextPenalty(original.text);
    final candidatePenalty = _suspiciousTextPenalty(candidateText);
    if (candidatePenalty > originalPenalty + 0.5) return false;

    // Paddle remains an independent recognizer and may correct valid Japanese
    // characters without dictionary support, but only when the whole-column
    // shape and content remain close enough to the ML Kit observation.
    return true;
  }

  bool _shouldKeepMlKitWithoutLegacyVerification({
    required _CameraRawLine original,
    required String candidateText,
    required double candidateConfidence,
  }) {
    final originalConfidence = original.confidence;
    if (originalConfidence == null || originalConfidence < 0.55) return false;
    if (candidateConfidence < 0.85) return false;
    if (!_containsJapaneseCore(candidateText)) return false;
    if (_japaneseCharacterRatio(candidateText) < 0.80) return false;

    final originalCore = _japaneseCoreSequence(original.text);
    final candidateCore = _japaneseCoreSequence(candidateText);
    if (originalCore.isEmpty || candidateCore.isEmpty) return false;
    if (candidateCore == originalCore) return true;

    final coverage = candidateCore.length / originalCore.length;

    // The safest fast-path is when Paddle's output is literally a strict
    // subsequence of ML Kit's Japanese characters. Paddle has independently
    // confirmed the surviving runes but failed to see some characters. When
    // ML Kit itself is at least moderately confident, another series of ML Kit
    // crops is unlikely to add useful independent evidence. Require a majority
    // of the original to be seen so a tiny accidental fragment cannot qualify.
    if (_isStrictRuneSubsequence(candidateCore, originalCore) &&
        coverage >= 0.55) {
      return true;
    }

    // For a high-confidence ML Kit line, a shorter Paddle reading with only a
    // small overall disagreement is also more consistent with Paddle truncation
    // than with a character-level ambiguity that merits several legacy passes.
    // Keep this deliberately narrow; genuinely different low-confidence text
    // still falls through to the full verifier.
    if (originalConfidence >= 0.68 && coverage < 0.84 && coverage >= 0.65) {
      final distance = _levenshteinDistance(originalCore, candidateCore);
      final normalizedDifference = distance / originalCore.length;
      if (normalizedDifference <= 0.42) return true;
    }

    return false;
  }

  bool _isStrictRuneSubsequence(String candidate, String original) {
    if (candidate.isEmpty || candidate.length >= original.length) return false;

    final candidateRunes = candidate.runes.toList(growable: false);
    final originalRunes = original.runes.toList(growable: false);
    var candidateIndex = 0;

    for (final rune in originalRunes) {
      if (candidateIndex >= candidateRunes.length) break;
      if (rune == candidateRunes[candidateIndex]) {
        candidateIndex += 1;
      }
    }

    return candidateIndex == candidateRunes.length;
  }

  double _japaneseCharacterRatio(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return 0.0;

    var japanese = 0;
    var total = 0;

    for (final rune in compact.runes) {
      total += 1;
      if (_isJapaneseCharacter(String.fromCharCode(rune)) ||
          rune == 0x3001 || // 、
          rune == 0x3002 || // 。
          rune == 0xFF01 || // ！
          rune == 0xFF1F || // ？
          rune == 0x30FC) { // ー
        japanese += 1;
      }
    }

    return total == 0 ? 0.0 : japanese / total;
  }

  bool _shouldVerifyVerticalPhysicalLine(_CameraRawLine line) {
    if (line.orientation != CameraTextOrientation.vertical) return false;

    final japaneseLength = _japaneseContentLength(line.text);
    if (japaneseLength < 2) return false;

    final confidence = line.confidence;
    final lowPrimaryConfidence = confidence == null || confidence < 0.55;
    final suspicious = _suspiciousTextPenalty(line.text) > 0;
    final hasRuby = line.annotations.isNotEmpty;
    final rubySuggestsDifficultPrint = line.annotations.any(
      (annotation) =>
          annotation.confidence != null && annotation.confidence! < 0.52,
    );

    // Furigana-heavy manga is a particularly difficult OCR case. A primary
    // column with attached ruby gets one verification pass while confidence is
    // still below a reasonably strong 0.72, even if ML Kit's primary-line
    // confidence alone would otherwise look acceptable.
    final rubyAssistedVerification =
        hasRuby && (confidence == null || confidence < 0.72);

    return lowPrimaryConfidence ||
        suspicious ||
        rubySuggestsDifficultPrint ||
        rubyAssistedVerification;
  }

  double _verticalVerificationPriority(_CameraRawLine line) {
    final confidence = line.confidence ?? 0.0;
    var priority =
        (1.0 - confidence).clamp(0.0, 1.0).toDouble() * 10.0;

    priority += _suspiciousTextPenalty(line.text) * 2.5;

    if (line.annotations.isNotEmpty) {
      priority += 1.4;
    }

    if (line.annotations.any(
      (annotation) =>
          annotation.confidence != null && annotation.confidence! < 0.52,
    )) {
      priority += 1.8;
    }

    return priority;
  }

  Future<Map<int, List<_CameraVerificationAttempt>>>
      _collectVerticalTextBoxVerificationAttempts({
    required ui.Image sourceImage,
    required Size imageSize,
    required List<_CameraRawLine> lines,
    required Set<int> selectedLineIndexes,
    required Directory directory,
  }) async {
    const maxVerificationBoxes = 2;

    final boxes = _scopedVerticalVerificationBoxes(
      boxes: _buildVerticalVerificationBoxes(lines),
      selectedLineIndexes: selectedLineIndexes,
      lines: lines,
    )
        .where((box) => _shouldVerifyVerticalTextBox(box, lines))
        .toList(growable: false)
      ..sort((first, second) {
        final firstPriority = _verticalTextBoxVerificationPriority(first, lines);
        final secondPriority =
            _verticalTextBoxVerificationPriority(second, lines);
        return secondPriority.compareTo(firstPriority);
      });

    final selectedBoxes = boxes.take(maxVerificationBoxes).toList(growable: false);
    final attemptsByLine = <int, List<_CameraVerificationAttempt>>{};

    if (kDebugMode && _debugOcrPipeline) {
      debugPrint(
        '[Camera OCR] ===== LOW-CONFIDENCE TEXT-BOX OCR VERIFICATION =====',
      );
      debugPrint(
        '[Camera OCR] eligibleBoxes=${boxes.length} '
        'selectedBoxes=${selectedBoxes.length} max=$maxVerificationBoxes',
      );
    }

    for (var boxIndex = 0; boxIndex < selectedBoxes.length; boxIndex++) {
      final box = selectedBoxes[boxIndex];
      final temporaryFiles = <File>[];

      if (kDebugMode && _debugOcrPipeline) {
        final confidences = box.lineIndexes
            .map((index) => lines[index].confidence ?? 0.0)
            .toList(growable: false);
        final averageConfidence = confidences.isEmpty
            ? 0.0
            : confidences.reduce((a, b) => a + b) / confidences.length;
        debugPrint(
          '[Camera OCR] BOX VERIFY box=$boxIndex '
          'lines=${box.lineIndexes} '
          'avgConf=${averageConfidence.toStringAsFixed(3)} '
          'box=${_debugRect(box.boundingBox)}',
        );
      }

      try {
        for (final enhanced in <bool>[false, true]) {
          final rendered = await _renderVerticalTextBoxVerificationImage(
            sourceImage: sourceImage,
            imageSize: imageSize,
            box: box,
            lines: lines,
            directory: directory,
            index: boxIndex,
            enhanced: enhanced,
          );
          temporaryFiles.add(rendered.file);

          final recognition = await _textRecognizer.processImage(
            InputImage.fromFilePath(rendered.file.path),
          );
          final candidates = _bestVerticalTextBoxVerificationCandidates(
            recognizedText: recognition,
            rendered: rendered,
            box: box,
            lines: lines,
          );
          final label = enhanced ? 'box-contrast' : 'box-enlarged';

          for (final entry in candidates.entries) {
            if (!selectedLineIndexes.contains(entry.key)) continue;

            attemptsByLine
                .putIfAbsent(entry.key, () => <_CameraVerificationAttempt>[])
                .add(
                  _CameraVerificationAttempt(
                    label: label,
                    candidate: entry.value,
                  ),
                );

            if (kDebugMode && _debugOcrPipeline) {
              debugPrint(
                '[Camera OCR]   $label line=${entry.key} '
                'original="${lines[entry.key].text}" '
                'candidate="${entry.value.text}" '
                'conf=${_debugConfidence(entry.value.confidence)}',
              );
            }
          }
        }
      } catch (_) {
        // Whole-box OCR is only an additional source of candidates. If the
        // contextual crop fails for any reason, the existing per-line retry
        // path remains fully available and authoritative.
      } finally {
        for (final file in temporaryFiles) {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {
            // Temporary text-box verification files are best-effort cleanup.
          }
        }
      }
    }

    return attemptsByLine;
  }

  List<_CameraVerticalVerificationBox> _scopedVerticalVerificationBoxes({
    required List<_CameraVerticalVerificationBox> boxes,
    required Set<int> selectedLineIndexes,
    required List<_CameraRawLine> lines,
  }) {
    final scoped = <_CameraVerticalVerificationBox>[];

    for (final box in boxes) {
      final ordered = box.lineIndexes;
      final selectedPositions = <int>[
        for (var position = 0; position < ordered.length; position++)
          if (selectedLineIndexes.contains(ordered[position])) position,
      ];
      if (selectedPositions.isEmpty) continue;

      final groups = <List<int>>[];
      var current = <int>[];
      for (final position in selectedPositions) {
        if (current.isEmpty || position == current.last + 1) {
          current.add(position);
          continue;
        }
        groups.add(current);
        current = <int>[position];
      }
      if (current.isNotEmpty) groups.add(current);

      for (final group in groups) {
        for (var offset = 0; offset < group.length; offset += 4) {
          final chunk = group.skip(offset).take(4).toList(growable: false);
          if (chunk.isEmpty) continue;

          var start = chunk.first;
          var end = chunk.last;
          if (start > 0) start -= 1;
          if (end + 1 < ordered.length) end += 1;

          final indexes = ordered.sublist(start, end + 1);
          if (!indexes.any(selectedLineIndexes.contains)) continue;

          var bounds = lines[indexes.first].boundingBox;
          for (final lineIndex in indexes.skip(1)) {
            bounds = bounds.expandToInclude(lines[lineIndex].boundingBox);
          }

          scoped.add(
            _CameraVerticalVerificationBox(
              lineIndexes: indexes,
              boundingBox: bounds,
            ),
          );
        }
      }
    }

    return scoped;
  }

  List<_CameraVerticalVerificationBox> _buildVerticalVerificationBoxes(
    List<_CameraRawLine> lines,
  ) {
    final fragments = <_CameraTextFragment>[];
    final lineIndexByFragment = <_CameraTextFragment, int>{};

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.orientation != CameraTextOrientation.vertical) continue;

      final fragment = _CameraTextFragment(
        text: line.text,
        boundingBoxes: <Rect>[line.boundingBox],
        annotations: line.annotations,
        blockIndex: line.blockIndex,
        orientation: CameraTextOrientation.vertical,
        endsSentence: false,
      );
      fragments.add(fragment);
      lineIndexByFragment[fragment] = index;
    }

    if (fragments.isEmpty) return const <_CameraVerticalVerificationBox>[];

    final clustered = _clusterVerticalFragmentsIntoTextBoxes(fragments);
    final boxes = <_CameraVerticalVerificationBox>[];

    for (final textBox in clustered) {
      final indexes = <int>[
        for (final fragment in textBox.fragments)
          lineIndexByFragment[fragment]!,
      ]..sort((first, second) {
          final firstBox = lines[first].boundingBox;
          final secondBox = lines[second].boundingBox;
          final horizontal = secondBox.center.dx.compareTo(firstBox.center.dx);
          if (horizontal != 0) return horizontal;
          return firstBox.top.compareTo(secondBox.top);
        });

      if (indexes.isEmpty) continue;
      boxes.add(
        _CameraVerticalVerificationBox(
          lineIndexes: indexes,
          boundingBox: textBox.boundingBox,
        ),
      );
    }

    return boxes;
  }

  bool _shouldVerifyVerticalTextBox(
    _CameraVerticalVerificationBox box,
    List<_CameraRawLine> lines,
  ) {
    // A one-column box is already handled by the tighter per-line crop. The
    // contextual reread is specifically for bubbles/labels where neighboring
    // columns can give ML Kit useful structure while unrelated page content is
    // removed.
    if (box.lineIndexes.length < 2) return false;

    final confidences = box.lineIndexes
        .map((index) => lines[index].confidence ?? 0.0)
        .toList(growable: false);
    final averageConfidence =
        confidences.reduce((a, b) => a + b) / confidences.length;
    final minimumConfidence = confidences.reduce((a, b) => a < b ? a : b);
    final lowConfidenceCount = confidences.where((value) => value < 0.48).length;
    final suspicious = box.lineIndexes.any(
      (index) => _suspiciousTextPenalty(lines[index].text) > 0,
    );

    return averageConfidence < 0.50 ||
        minimumConfidence < 0.40 ||
        lowConfidenceCount >= 2 ||
        suspicious;
  }

  double _verticalTextBoxVerificationPriority(
    _CameraVerticalVerificationBox box,
    List<_CameraRawLine> lines,
  ) {
    final confidences = box.lineIndexes
        .map((index) => lines[index].confidence ?? 0.0)
        .toList(growable: false);
    final averageConfidence =
        confidences.reduce((a, b) => a + b) / confidences.length;
    final minimumConfidence = confidences.reduce((a, b) => a < b ? a : b);
    final lowConfidenceCount = confidences.where((value) => value < 0.48).length;
    final suspiciousCount = box.lineIndexes
        .where((index) => _suspiciousTextPenalty(lines[index].text) > 0)
        .length;

    return (1.0 - averageConfidence).clamp(0.0, 1.0).toDouble() * 10.0 +
        (1.0 - minimumConfidence).clamp(0.0, 1.0).toDouble() * 4.0 +
        lowConfidenceCount * 1.25 +
        suspiciousCount * 2.0;
  }

  Future<_CameraTextBoxVerificationRender>
      _renderVerticalTextBoxVerificationImage({
    required ui.Image sourceImage,
    required Size imageSize,
    required _CameraVerticalVerificationBox box,
    required List<_CameraRawLine> lines,
    required Directory directory,
    required int index,
    required bool enhanced,
  }) async {
    final lineWidths = box.lineIndexes
        .map((lineIndex) => lines[lineIndex].boundingBox.width)
        .where((width) => width > 0)
        .toList()
      ..sort();
    final medianWidth = lineWidths.isEmpty
        ? 48.0
        : lineWidths[lineWidths.length ~/ 2];
    final sourceRect = _paddedVerticalTextBoxVerificationRect(
      box.boundingBox,
      imageSize,
      medianLineWidth: medianWidth,
      expandedContext: enhanced,
    );

    if (sourceRect.width <= 1 || sourceRect.height <= 1) {
      throw StateError('Vertical text-box OCR verification crop is empty.');
    }

    var scale = (150.0 / medianWidth).clamp(
      enhanced ? 1.70 : 1.55,
      enhanced ? 2.85 : 2.55,
    ).toDouble();

    if (sourceRect.width * scale > 2200) {
      scale = 2200 / sourceRect.width;
    }
    if (sourceRect.height * scale > 2800) {
      scale = 2800 / sourceRect.height;
    }
    scale = scale.clamp(1.0, 2.85).toDouble();

    const outerPadding = 20.0;
    final contentWidth = sourceRect.width * scale;
    final contentHeight = sourceRect.height * scale;
    final targetWidth = (contentWidth + outerPadding * 2).ceil();
    final targetHeight = (contentHeight + outerPadding * 2).ceil();
    final destinationRect = Rect.fromLTWH(
      outerPadding,
      outerPadding,
      contentWidth,
      contentHeight,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    if (enhanced) {
      // Mild grayscale/contrast gives faint manga strokes another chance
      // without turning the contextual pass into a thresholding/autocorrect
      // system. The original full-photo pixels still generate every candidate.
      paint.colorFilter = ColorFilter.matrix(<double>[
        0.26575, 0.89400, 0.09025, 0.0, -28.0,
        0.26575, 0.89400, 0.09025, 0.0, -28.0,
        0.26575, 0.89400, 0.09025, 0.0, -28.0,
        0.0,     0.0,     0.0,     1.0,   0.0,
      ]);
    }

    canvas.drawImageRect(
      sourceImage,
      sourceRect,
      destinationRect,
      paint,
    );

    final picture = recorder.endRecording();
    final verificationImage = await picture.toImage(targetWidth, targetHeight);

    try {
      final data = await verificationImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (data == null) {
        throw StateError('Could not encode text-box OCR verification image.');
      }

      final suffix = enhanced ? 'contrast' : 'enlarged';
      final file = File(
        '${directory.path}/gakuji_camera_box_verify_'
        '${DateTime.now().microsecondsSinceEpoch}_${index}_$suffix.png',
      );
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );

      return _CameraTextBoxVerificationRender(
        file: file,
        sourceRect: sourceRect,
        destinationRect: destinationRect,
      );
    } finally {
      verificationImage.dispose();
    }
  }

  Rect _paddedVerticalTextBoxVerificationRect(
    Rect rect,
    Size imageSize, {
    required double medianLineWidth,
    required bool expandedContext,
  }) {
    final safeWidth = medianLineWidth <= 0 ? 48.0 : medianLineWidth;
    final horizontalPadding = (safeWidth * (expandedContext ? 0.62 : 0.42))
        .clamp(10.0, 72.0)
        .toDouble();
    final verticalPadding = (safeWidth * (expandedContext ? 0.72 : 0.48))
        .clamp(10.0, 84.0)
        .toDouble();

    return Rect.fromLTRB(
      (rect.left - horizontalPadding).clamp(0.0, imageSize.width).toDouble(),
      (rect.top - verticalPadding).clamp(0.0, imageSize.height).toDouble(),
      (rect.right + horizontalPadding).clamp(0.0, imageSize.width).toDouble(),
      (rect.bottom + verticalPadding).clamp(0.0, imageSize.height).toDouble(),
    );
  }

  Map<int, _CameraRefinementCandidate>
      _bestVerticalTextBoxVerificationCandidates({
    required RecognizedText recognizedText,
    required _CameraTextBoxVerificationRender rendered,
    required _CameraVerticalVerificationBox box,
    required List<_CameraRawLine> lines,
  }) {
    final candidates = <_CameraTextBoxCandidateLine>[];

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final detectedOrientation = _orientationForRecognizedLine(
          line: line,
          block: block,
        );
        final rebuilt = _textForRecognizedLine(
          line: line,
          orientation: detectedOrientation,
        );
        var text = _cleanLineText(rebuilt);
        if (detectedOrientation == CameraTextOrientation.vertical) {
          text = _normalizeVerticalSmallKanaByLanguage(text);
        }
        if (!_isUsefulJapaneseLine(text)) continue;

        final mappedBox = _mapTextBoxVerificationRectToSource(
          line.boundingBox,
          rendered,
        );
        if (mappedBox.width <= 1 || mappedBox.height <= 1) continue;

        final looksVertical =
            detectedOrientation == CameraTextOrientation.vertical ||
            mappedBox.height >= mappedBox.width * 1.12;
        if (!looksVertical) continue;

        candidates.add(
          _CameraTextBoxCandidateLine(
            text: text,
            boundingBox: mappedBox,
            confidence: line.confidence,
          ),
        );
      }
    }

    if (candidates.isEmpty) return const <int, _CameraRefinementCandidate>{};

    final matches = <_CameraTextBoxCandidateMatch>[];

    for (final lineIndex in box.lineIndexes) {
      final original = lines[lineIndex];
      final originalCompact = original.text.replaceAll(RegExp(r'\s+'), '');
      final originalLength = _japaneseContentLength(original.text);
      if (originalLength == 0) continue;

      for (var candidateIndex = 0;
          candidateIndex < candidates.length;
          candidateIndex++) {
        final candidate = candidates[candidateIndex];
        final candidateLength = _japaneseContentLength(candidate.text);
        if (candidateLength == 0) continue;

        final lengthRatio = candidateLength / originalLength;
        if (lengthRatio < 0.55 || lengthRatio > 1.45) continue;

        final candidateCompact = candidate.text.replaceAll(RegExp(r'\s+'), '');
        final editDistance = _levenshteinDistance(
          originalCompact,
          candidateCompact,
        );
        final longestLength = originalCompact.length > candidateCompact.length
            ? originalCompact.length
            : candidateCompact.length;
        final difference = longestLength == 0
            ? 0.0
            : editDistance / longestLength;
        if (difference > 0.48) continue;

        final originalBox = original.boundingBox;
        final candidateBox = candidate.boundingBox;
        final referenceWidth = originalBox.width > candidateBox.width
            ? originalBox.width
            : candidateBox.width;
        final safeWidth = referenceWidth <= 0 ? 1.0 : referenceWidth;
        final xDistanceRatio =
            (originalBox.center.dx - candidateBox.center.dx).abs() / safeWidth;

        final overlapTop = originalBox.top > candidateBox.top
            ? originalBox.top
            : candidateBox.top;
        final overlapBottom = originalBox.bottom < candidateBox.bottom
            ? originalBox.bottom
            : candidateBox.bottom;
        final overlap =
            (overlapBottom - overlapTop).clamp(0.0, double.infinity).toDouble();
        final shorterHeight = originalBox.height < candidateBox.height
            ? originalBox.height
            : candidateBox.height;
        final overlapRatio = shorterHeight <= 0
            ? 0.0
            : (overlap / shorterHeight).clamp(0.0, 1.0).toDouble();
        final referenceHeight = originalBox.height > candidateBox.height
            ? originalBox.height
            : candidateBox.height;
        final safeHeight = referenceHeight <= 0 ? 1.0 : referenceHeight;
        final yCenterDifferenceRatio =
            (originalBox.center.dy - candidateBox.center.dy).abs() / safeHeight;

        if (xDistanceRatio > 1.45 ||
            (overlapRatio < 0.18 && yCenterDifferenceRatio > 0.50)) {
          continue;
        }

        final confidence = candidate.confidence ?? 0.0;
        final score = confidence * 10.0 +
            (1.0 - difference) * 7.0 +
            overlapRatio * 4.0 -
            xDistanceRatio * 5.0 -
            yCenterDifferenceRatio * 1.5 -
            _suspiciousTextPenalty(candidate.text) * 2.0;
        if (score < 4.0) continue;

        matches.add(
          _CameraTextBoxCandidateMatch(
            lineIndex: lineIndex,
            candidateIndex: candidateIndex,
            score: score,
          ),
        );
      }
    }

    matches.sort((first, second) => second.score.compareTo(first.score));
    final usedLines = <int>{};
    final usedCandidates = <int>{};
    final result = <int, _CameraRefinementCandidate>{};

    for (final match in matches) {
      if (usedLines.contains(match.lineIndex) ||
          usedCandidates.contains(match.candidateIndex)) {
        continue;
      }

      final candidate = candidates[match.candidateIndex];
      usedLines.add(match.lineIndex);
      usedCandidates.add(match.candidateIndex);
      result[match.lineIndex] = _CameraRefinementCandidate(
        text: candidate.text,
        confidence: candidate.confidence,
      );
    }

    return result;
  }

  Rect _mapTextBoxVerificationRectToSource(
    Rect rect,
    _CameraTextBoxVerificationRender rendered,
  ) {
    final destination = rendered.destinationRect;
    if (destination.width <= 0 || destination.height <= 0) return Rect.zero;

    final left = rect.left.clamp(destination.left, destination.right).toDouble();
    final top = rect.top.clamp(destination.top, destination.bottom).toDouble();
    final right = rect.right.clamp(destination.left, destination.right).toDouble();
    final bottom = rect.bottom.clamp(destination.top, destination.bottom).toDouble();
    if (right <= left || bottom <= top) return Rect.zero;

    final source = rendered.sourceRect;
    final leftRatio = (left - destination.left) / destination.width;
    final topRatio = (top - destination.top) / destination.height;
    final rightRatio = (right - destination.left) / destination.width;
    final bottomRatio = (bottom - destination.top) / destination.height;

    return Rect.fromLTRB(
      source.left + source.width * leftRatio,
      source.top + source.height * topRatio,
      source.left + source.width * rightRatio,
      source.top + source.height * bottomRatio,
    );
  }

  Future<File> _renderVerticalVerificationImage({
    required ui.Image sourceImage,
    required Size imageSize,
    required _CameraRawLine line,
    required Directory directory,
    required int index,
    required bool enhanced,
  }) async {
    final sourceRect = _paddedVerticalVerificationRect(
      line.boundingBox,
      imageSize,
      expandedContext: enhanced,
    );

    if (sourceRect.width <= 1 || sourceRect.height <= 1) {
      throw StateError('Vertical OCR verification crop is empty.');
    }

    var scale = enhanced ? 3.0 : 2.65;

    if (sourceRect.width * scale > 980) {
      scale = 980 / sourceRect.width;
    }

    if (sourceRect.height * scale > 3200) {
      scale = 3200 / sourceRect.height;
    }

    scale = scale.clamp(1.15, 3.0).toDouble();

    const outerPadding = 18.0;
    final targetWidth = (sourceRect.width * scale + outerPadding * 2)
        .ceil()
        .clamp(1, 1040)
        .toInt();
    final targetHeight = (sourceRect.height * scale + outerPadding * 2)
        .ceil()
        .clamp(1, 3260)
        .toInt();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        targetWidth.toDouble(),
        targetHeight.toDouble(),
      ),
      Paint()..color = Colors.white,
    );

    final destination = Rect.fromLTWH(
      outerPadding,
      outerPadding,
      sourceRect.width * scale,
      sourceRect.height * scale,
    );

    final paint = Paint()..filterQuality = FilterQuality.high;

    if (enhanced) {
      // Grayscale plus restrained contrast. This is intentionally mild: the
      // retry should reveal faint strokes, not invent hard edges that were not
      // present in the source photograph.
      paint.colorFilter = ColorFilter.matrix(<double>[
        0.26575, 0.89400, 0.09025, 0.0, -32.0,
        0.26575, 0.89400, 0.09025, 0.0, -32.0,
        0.26575, 0.89400, 0.09025, 0.0, -32.0,
        0.0,     0.0,     0.0,     1.0,   0.0,
      ]);
    }

    canvas.drawImageRect(
      sourceImage,
      sourceRect,
      destination,
      paint,
    );

    final picture = recorder.endRecording();
    final verificationImage = await picture.toImage(
      targetWidth,
      targetHeight,
    );

    try {
      final data = await verificationImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (data == null) {
        throw StateError('Could not encode vertical OCR verification image.');
      }

      final suffix = enhanced ? 'contrast' : 'enlarged';
      final file = File(
        '${directory.path}/gakuji_camera_verify_'
        '${DateTime.now().microsecondsSinceEpoch}_${index}_$suffix.png',
      );
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );

      return file;
    } finally {
      verificationImage.dispose();
    }
  }

  Rect _paddedVerticalVerificationRect(
    Rect rect,
    Size imageSize, {
    required bool expandedContext,
  }) {
    // Ruby normally sits to the right of a vertical main column. The first
    // retry stays tight, while the second retry adds more context primarily on
    // the left/top/bottom so clipped strokes can be recovered without simply
    // pulling the furigana track back into the crop.
    final leftPadding = expandedContext
        ? (rect.width * 0.34).clamp(8.0, 30.0).toDouble()
        : (rect.width * 0.16).clamp(4.0, 18.0).toDouble();
    final rightPadding = expandedContext
        ? (rect.width * 0.18).clamp(5.0, 18.0).toDouble()
        : (rect.width * 0.16).clamp(4.0, 18.0).toDouble();
    final verticalPadding = expandedContext
        ? (rect.width * 0.38).clamp(8.0, 30.0).toDouble()
        : (rect.width * 0.22).clamp(4.0, 22.0).toDouble();

    return Rect.fromLTRB(
      (rect.left - leftPadding).clamp(0.0, imageSize.width).toDouble(),
      (rect.top - verticalPadding).clamp(0.0, imageSize.height).toDouble(),
      (rect.right + rightPadding).clamp(0.0, imageSize.width).toDouble(),
      (rect.bottom + verticalPadding).clamp(0.0, imageSize.height).toDouble(),
    );
  }

  _CameraRefinementCandidate? _bestVerticalVerificationCandidate({
    required RecognizedText recognizedText,
    required _CameraRawLine original,
  }) {
    _CameraRefinementCandidate? best;
    var bestScore = double.negativeInfinity;
    final originalLength = _japaneseContentLength(original.text);
    final originalCompact = original.text.replaceAll(RegExp(r'\s+'), '');

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final detectedOrientation = _orientationForRecognizedLine(
          line: line,
          block: block,
        );
        final rebuilt = _textForRecognizedLine(
          line: line,
          orientation: detectedOrientation,
        );
        var text = _cleanLineText(rebuilt);

        if (detectedOrientation == CameraTextOrientation.vertical) {
          text = _normalizeVerticalSmallKanaByLanguage(text);
        }

        if (!_isUsefulJapaneseLine(text)) continue;

        final japaneseLength = _japaneseContentLength(text);
        if (japaneseLength == 0 || originalLength == 0) continue;

        final lengthRatio = japaneseLength / originalLength;
        if (lengthRatio < 0.68 || lengthRatio > 1.32) continue;

        final compact = text.replaceAll(RegExp(r'\s+'), '');
        final editDistance = _levenshteinDistance(originalCompact, compact);
        final longestLength = originalCompact.length > compact.length
            ? originalCompact.length
            : compact.length;
        final normalizedDifference = longestLength == 0
            ? 0.0
            : editDistance / longestLength;

        // Verification is allowed to correct characters, not invent a new
        // sentence. Large disagreements remain with the full-photo OCR.
        if (normalizedDifference > 0.36) continue;

        final confidence = line.confidence;
        final verticalShapeBonus =
            line.boundingBox.height >= line.boundingBox.width * 1.15
                ? 3.0
                : 0.0;
        final score =
            (confidence ?? 0.0) * 14.0 +
            (1.0 - normalizedDifference) * 10.0 +
            japaneseLength.clamp(1, 24).toDouble() * 0.35 +
            verticalShapeBonus -
            _suspiciousTextPenalty(text) * 5.0;

        if (score <= bestScore) continue;

        bestScore = score;
        best = _CameraRefinementCandidate(
          text: text,
          confidence: confidence,
        );
      }
    }

    return best;
  }

  Future<_CameraRefinementCandidate?> _chooseVerticalVerificationReplacement({
    required _CameraRawLine original,
    required List<_CameraVerificationAttempt> attempts,
  }) async {
    if (attempts.isEmpty) return null;

    final originalCompact = original.text.replaceAll(RegExp(r'\s+'), '');
    final originalConfidence = original.confidence ?? 0.0;
    final originalPenalty = _suspiciousTextPenalty(original.text);

    // Two independently rendered retries agreeing on the same small correction
    // is stronger evidence than either confidence value alone. This remains the
    // strongest non-lexical signal because both alternatives were actually
    // produced by OCR; Gakuji never invents a third spelling here.
    if (attempts.length >= 2) {
      final grouped = <String, List<_CameraRefinementCandidate>>{};

      for (final attempt in attempts) {
        final candidate = attempt.candidate;
        if (candidate.text == original.text) continue;
        grouped.putIfAbsent(candidate.text, () => <_CameraRefinementCandidate>[])
            .add(candidate);
      }

      for (final entry in grouped.entries) {
        if (entry.value.length < 2) continue;

        final candidate = entry.value.reduce((first, second) {
          return (second.confidence ?? 0.0) > (first.confidence ?? 0.0)
              ? second
              : first;
        });
        final candidateCompact = candidate.text.replaceAll(RegExp(r'\s+'), '');
        final editDistance = _levenshteinDistance(
          originalCompact,
          candidateCompact,
        );
        final longestLength = originalCompact.length > candidateCompact.length
            ? originalCompact.length
            : candidateCompact.length;
        final difference = longestLength == 0
            ? 0.0
            : editDistance / longestLength;
        final candidatePenalty = _suspiciousTextPenalty(candidate.text);
        final weakestConfidence = entry.value
            .map((value) => value.confidence ?? 0.0)
            .reduce((first, second) => first < second ? first : second);

        final confidenceFloor = editDistance == 1
            ? originalConfidence - 0.10
            : originalConfidence - 0.02;

        if (difference <= 0.20 &&
            candidatePenalty <= originalPenalty &&
            weakestConfidence >= confidenceFloor) {
          return candidate;
        }
      }
    }

    // When OCR passes disagree by exactly one Japanese character, confidence
    // alone is not a reliable arbiter across differently rendered crops. Ask
    // the bundled dictionary whether either *OCR-proposed* spelling forms a
    // real lexical item around the changed character. Ruby may support that
    // evidence, but neither the dictionary nor ruby is allowed to invent text.
    final dictionaryReplacement =
        await _chooseDictionaryArbitratedVerificationCandidate(
      original: original,
      attempts: attempts,
    );
    if (dictionaryReplacement != null) {
      return dictionaryReplacement;
    }

    // If no complete OCR candidate is trustworthy, combine only character
    // evidence that was independently observed by both the per-line crop
    // family and the whole-text-box crop family. Deletions/insertions in a
    // retry are alignment noise only; fusion keeps the original string length
    // and may substitute at most two Japanese characters. This lets partial
    // successes reinforce each other without allowing Gakuji to invent text.
    final fusedReplacement = await _chooseFusedVerticalVerificationCandidate(
      original: original,
      attempts: attempts,
    );
    if (fusedReplacement != null) {
      return fusedReplacement;
    }

    _CameraRefinementCandidate? best;
    var bestScore = double.negativeInfinity;

    for (final attempt in attempts) {
      final candidate = attempt.candidate;
      if (!_shouldUseVerticalVerificationCandidate(
        original: original,
        candidate: candidate,
      )) {
        continue;
      }

      final candidateCompact = candidate.text.replaceAll(RegExp(r'\s+'), '');
      final editDistance = _levenshteinDistance(
        originalCompact,
        candidateCompact,
      );
      final longestLength = originalCompact.length > candidateCompact.length
          ? originalCompact.length
          : candidateCompact.length;
      final difference = longestLength == 0
          ? 0.0
          : editDistance / longestLength;
      final score =
          (candidate.confidence ?? 0.0) * 12.0 -
          difference * 5.0 -
          _suspiciousTextPenalty(candidate.text) * 3.0;

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return best;
  }

  Future<_CameraRefinementCandidate?>
      _chooseFusedVerticalVerificationCandidate({
    required _CameraRawLine original,
    required List<_CameraVerificationAttempt> attempts,
  }) async {
    if (attempts.length < 2) return null;

    final originalRunes = original.text
        .replaceAll(RegExp(r'\s+'), '')
        .runes
        .toList(growable: false);
    if (originalRunes.length < 3 || originalRunes.length > 48) return null;

    // votes[index][candidateRune][family] = strongest confidence-weighted vote
    // from that OCR family. Variants from the same crop family cannot double
    // count, so box-enlarged + box-contrast are one independent source and
    // enlarged + contrast are the other.
    final votes = List<Map<int, Map<String, double>>>.generate(
      originalRunes.length,
      (_) => <int, Map<String, double>>{},
      growable: false,
    );
    final labels = List<Map<int, Set<String>>>.generate(
      originalRunes.length,
      (_) => <int, Set<String>>{},
      growable: false,
    );

    for (final attempt in attempts) {
      final normalized = _normalizeBoundaryNoiseForDictionaryArbitration(
        original: original,
        attempt: attempt,
        attempts: attempts,
      );
      final candidateRunes = normalized.text
          .replaceAll(RegExp(r'\s+'), '')
          .runes
          .toList(growable: false);

      if ((candidateRunes.length - originalRunes.length).abs() > 2 ||
          candidateRunes.isEmpty) {
        continue;
      }

      final editDistance = _levenshteinDistance(
        String.fromCharCodes(originalRunes),
        String.fromCharCodes(candidateRunes),
      );
      final longestLength = originalRunes.length > candidateRunes.length
          ? originalRunes.length
          : candidateRunes.length;
      final normalizedDifference = longestLength == 0
          ? 0.0
          : editDistance / longestLength;
      if (normalizedDifference > 0.36) continue;

      final aligned = _alignVerificationCandidateToOriginalRunes(
        originalRunes: originalRunes,
        candidateRunes: candidateRunes,
      );
      if (aligned == null) continue;

      final family = _verificationAttemptFamily(attempt.label);
      if (family != 'line' && family != 'box') continue;
      final confidence =
          (normalized.confidence ?? 0.0).clamp(0.0, 1.0).toDouble();
      final voteWeight = 1.0 + confidence;

      for (var index = 0; index < originalRunes.length; index++) {
        for (final candidateRune in aligned[index]) {
          if (candidateRune == originalRunes[index]) continue;

          final originalCharacter = String.fromCharCode(originalRunes[index]);
          final candidateCharacter = String.fromCharCode(candidateRune);
          if (!_isJapaneseCharacter(originalCharacter) ||
              !_isJapaneseCharacter(candidateCharacter)) {
            continue;
          }

          final familyVotes = votes[index].putIfAbsent(
            candidateRune,
            () => <String, double>{},
          );
          final previous = familyVotes[family];
          if (previous == null || voteWeight > previous) {
            familyVotes[family] = voteWeight;
          }
          labels[index]
              .putIfAbsent(candidateRune, () => <String>{})
              .add(attempt.label);
        }
      }
    }

    final fusedRunes = List<int>.from(originalRunes);
    final fusedEditIndexes = <int>[];
    final fusedEditLabels = <int, String>{};

    for (var index = 0; index < originalRunes.length; index++) {
      final alternatives = votes[index].entries
          .where((entry) => entry.value.keys.toSet().containsAll(
                const <String>{'line', 'box'},
              ))
          .toList(growable: false);
      if (alternatives.isEmpty) continue;

      alternatives.sort((first, second) {
        final firstScore = first.value.values.fold<double>(0.0, (a, b) => a + b);
        final secondScore = second.value.values.fold<double>(0.0, (a, b) => a + b);
        return secondScore.compareTo(firstScore);
      });

      // If two different replacement characters receive essentially the same
      // independent support, keep the original rather than guessing.
      if (alternatives.length > 1) {
        final firstScore = alternatives[0]
            .value
            .values
            .fold<double>(0.0, (a, b) => a + b);
        final secondScore = alternatives[1]
            .value
            .values
            .fold<double>(0.0, (a, b) => a + b);
        if ((firstScore - secondScore).abs() < 0.20) continue;
      }

      final chosen = alternatives.first;
      fusedRunes[index] = chosen.key;
      fusedEditIndexes.add(index);
      fusedEditLabels[index] =
          (labels[index][chosen.key] ?? const <String>{}).join(',');
    }

    if (fusedEditIndexes.isEmpty || fusedEditIndexes.length > 2) return null;

    // Cross-family agreement is strong OCR evidence, but do not let it destroy
    // an already well-supported lexical sequence. This specifically protects
    // cases like 全て when two noisy crops independently hallucinate 金て.
    // Dictionary/ruby evidence may veto an OCR-voted substitution, but it
    // still cannot introduce a character that no OCR pass observed.
    final preliminaryText = String.fromCharCodes(fusedRunes);
    final allQueries = <String>{};
    final originalQueriesByIndex = <int, List<String>>{};
    final fusedQueriesByIndex = <int, List<String>>{};

    for (final index in fusedEditIndexes) {
      final originalQueries = _dictionaryQueriesAroundRuneIndex(
        original.text,
        index,
      );
      final fusedQueries = _dictionaryQueriesAroundRuneIndex(
        preliminaryText,
        index,
      );
      originalQueriesByIndex[index] = originalQueries;
      fusedQueriesByIndex[index] = fusedQueries;
      allQueries
        ..addAll(originalQueries)
        ..addAll(fusedQueries);
    }

    if (allQueries.isNotEmpty) {
      final dictionaryMatches = await DictionaryService.findExactJapaneseBatch(
        allQueries,
        perQueryLimit: 4,
      );

      for (final index in List<int>.from(fusedEditIndexes)) {
        final originalEvidence = _bestDictionaryArbitrationEvidence(
          queries: originalQueriesByIndex[index] ?? const <String>[],
          dictionaryMatches: dictionaryMatches,
          annotations: original.annotations,
        );
        final fusedEvidence = _bestDictionaryArbitrationEvidence(
          queries: fusedQueriesByIndex[index] ?? const <String>[],
          dictionaryMatches: dictionaryMatches,
          annotations: original.annotations,
        );
        final lexicalLoss = originalEvidence.score - fusedEvidence.score;
        final rubyContradiction = originalEvidence.rubySupported &&
            !fusedEvidence.rubySupported;
        final veto = rubyContradiction ||
            (originalEvidence.japaneseLength >= 2 && lexicalLoss >= 0.90);

        if (!veto) continue;

        if (kDebugMode && _debugOcrPipeline) {
          debugPrint(
            '[Camera OCR] FUSE VETO index=$index '
            '${String.fromCharCode(originalRunes[index])}'
            '->${String.fromCharCode(fusedRunes[index])} '
            'originalDict=${_debugDictionaryEvidence(originalEvidence)} '
            'fusedDict=${_debugDictionaryEvidence(fusedEvidence)}',
          );
        }

        fusedRunes[index] = originalRunes[index];
        fusedEditIndexes.remove(index);
        fusedEditLabels.remove(index);
      }
    }

    if (fusedEditIndexes.isEmpty) return null;

    final fusedText = String.fromCharCodes(fusedRunes);
    final editDistance = _levenshteinDistance(original.text, fusedText);
    final normalizedDifference = originalRunes.isEmpty
        ? 0.0
        : editDistance / originalRunes.length;
    if (normalizedDifference > 0.25) return null;

    // Fusion should not make the string look structurally less Japanese than
    // the original. This is only a safety brake; lexical evidence is not used
    // here to generate characters.
    if (_suspiciousTextPenalty(fusedText) >
        _suspiciousTextPenalty(original.text)) {
      return null;
    }

    if (kDebugMode && _debugOcrPipeline) {
      final descriptions = fusedEditIndexes.map((index) {
        return '$index:${String.fromCharCode(originalRunes[index])}'
            '->${String.fromCharCode(fusedRunes[index])}'
            '[${fusedEditLabels[index] ?? ''}]';
      }).join(' | ');
      debugPrint(
        '[Camera OCR] FUSE original="${original.text}" '
        '-> "$fusedText" edits=$descriptions',
      );
    }

    return _CameraRefinementCandidate(
      text: fusedText,
      // The fused spelling is synthesized from observed OCR characters rather
      // than emitted by one recognizer pass, so do not inflate confidence.
      confidence: original.confidence,
    );
  }

  List<Set<int>>? _alignVerificationCandidateToOriginalRunes({
    required List<int> originalRunes,
    required List<int> candidateRunes,
  }) {
    final n = originalRunes.length;
    final m = candidateRunes.length;
    if (n == 0 || m == 0 || n > 64 || m > 64) return null;

    final forward = List<List<int>>.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
      growable: false,
    );
    for (var i = 0; i <= n; i++) {
      forward[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      forward[0][j] = j;
    }

    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final substitutionCost =
            originalRunes[i - 1] == candidateRunes[j - 1] ? 0 : 1;
        final diagonal = forward[i - 1][j - 1] + substitutionCost;
        final deletion = forward[i - 1][j] + 1;
        final insertion = forward[i][j - 1] + 1;
        var best = diagonal;
        if (deletion < best) best = deletion;
        if (insertion < best) best = insertion;
        forward[i][j] = best;
      }
    }

    // Reverse edit-distance table lets us retain every candidate-to-original
    // diagonal mapping that participates in at least one optimal alignment.
    // That matters for OCR like "ロの炎つで": the missing 一 makes 炎
    // positionally ambiguous, but another crop can disambiguate it by voting
    // for 炎 at the same original position.
    final reverse = List<List<int>>.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
      growable: false,
    );
    for (var i = n; i >= 0; i--) {
      reverse[i][m] = n - i;
    }
    for (var j = m; j >= 0; j--) {
      reverse[n][j] = m - j;
    }

    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        final substitutionCost =
            originalRunes[i] == candidateRunes[j] ? 0 : 1;
        final diagonal = reverse[i + 1][j + 1] + substitutionCost;
        final deletion = reverse[i + 1][j] + 1;
        final insertion = reverse[i][j + 1] + 1;
        var best = diagonal;
        if (deletion < best) best = deletion;
        if (insertion < best) best = insertion;
        reverse[i][j] = best;
      }
    }

    final totalDistance = forward[n][m];
    final aligned = List<Set<int>>.generate(
      n,
      (_) => <int>{},
      growable: false,
    );

    for (var i = 0; i < n; i++) {
      for (var j = 0; j < m; j++) {
        final substitutionCost =
            originalRunes[i] == candidateRunes[j] ? 0 : 1;
        final participatesInOptimalAlignment =
            forward[i][j] +
                substitutionCost +
                reverse[i + 1][j + 1] ==
            totalDistance;
        if (participatesInOptimalAlignment) {
          aligned[i].add(candidateRunes[j]);
        }
      }
    }

    return aligned;
  }

  String _verificationAttemptFamily(String label) {
    if (label.startsWith('box-')) return 'box';
    if (label == 'enlarged' || label == 'contrast') return 'line';
    return label;
  }

  Future<_CameraRefinementCandidate?>
      _chooseDictionaryArbitratedVerificationCandidate({
    required _CameraRawLine original,
    required List<_CameraVerificationAttempt> attempts,
  }) async {
    final alternatives = <_CameraDictionaryArbitrationAlternative>[];
    final allQueries = <String>{};

    for (final attempt in attempts) {
      final candidate = _normalizeBoundaryNoiseForDictionaryArbitration(
        original: original,
        attempt: attempt,
        attempts: attempts,
      );
      final substitutionIndex = _singleJapaneseSubstitutionRuneIndex(
        original.text,
        candidate.text,
      );
      if (substitutionIndex == null) continue;

      final originalQueries = _dictionaryQueriesAroundRuneIndex(
        original.text,
        substitutionIndex,
      );
      final candidateQueries = _dictionaryQueriesAroundRuneIndex(
        candidate.text,
        substitutionIndex,
      );
      if (candidateQueries.isEmpty) continue;

      allQueries
        ..addAll(originalQueries)
        ..addAll(candidateQueries);
      alternatives.add(
        _CameraDictionaryArbitrationAlternative(
          attempt: _CameraVerificationAttempt(
            label: attempt.label,
            candidate: candidate,
          ),
          substitutionIndex: substitutionIndex,
          originalQueries: originalQueries,
          candidateQueries: candidateQueries,
        ),
      );
    }

    if (alternatives.isEmpty || allQueries.isEmpty) return null;

    final dictionaryMatches = await DictionaryService.findExactJapaneseBatch(
      allQueries,
      perQueryLimit: 4,
    );

    _CameraRefinementCandidate? best;
    var bestDecisionScore = double.negativeInfinity;

    for (final alternative in alternatives) {
      final candidate = alternative.attempt.candidate;
      final originalEvidence = _bestDictionaryArbitrationEvidence(
        queries: alternative.originalQueries,
        dictionaryMatches: dictionaryMatches,
        annotations: original.annotations,
      );
      final candidateEvidence = _bestDictionaryArbitrationEvidence(
        queries: alternative.candidateQueries,
        dictionaryMatches: dictionaryMatches,
        annotations: original.annotations,
      );

      final originalConfidence = original.confidence ?? 0.0;
      final candidateConfidence = candidate.confidence ?? 0.0;
      final confidenceDelta = candidateConfidence - originalConfidence;
      final lexicalAdvantage = candidateEvidence.score - originalEvidence.score;

      final hasCandidateWord = candidateEvidence.japaneseLength >= 2;
      final materiallyBetterLexicalEvidence = lexicalAdvantage >= 1.10;
      final confidenceIsCloseEnough = candidateEvidence.rubySupported
          ? confidenceDelta >= -0.12
          : candidateEvidence.japaneseLength >= 4
              ? confidenceDelta >= -0.08
              : confidenceDelta >= -0.01;

      final accepted = hasCandidateWord &&
          materiallyBetterLexicalEvidence &&
          confidenceIsCloseEnough;

      if (kDebugMode && _debugOcrPipeline) {
        debugPrint(
          '[Camera OCR] ARBITRATE original="${original.text}" '
          'candidate="${candidate.text}" '
          'editIndex=${alternative.substitutionIndex} '
          'confDelta=${confidenceDelta >= 0 ? '+' : ''}'
          '${confidenceDelta.toStringAsFixed(3)}',
        );
        debugPrint(
          '[Camera OCR]   originalDict=${_debugDictionaryEvidence(originalEvidence)} '
          'candidateDict=${_debugDictionaryEvidence(candidateEvidence)} '
          'lexicalAdvantage=${lexicalAdvantage.toStringAsFixed(2)} '
          'decision=${accepted ? 'REPLACE' : 'KEEP'}',
        );
      }

      if (!accepted) continue;

      final decisionScore =
          lexicalAdvantage * 4.0 +
          confidenceDelta * 8.0 +
          candidateEvidence.japaneseLength * 0.35 +
          (candidateEvidence.rubySupported ? 1.5 : 0.0);

      if (decisionScore > bestDecisionScore) {
        bestDecisionScore = decisionScore;
        best = candidate;
      }
    }

    return best;
  }

  _CameraRefinementCandidate _normalizeBoundaryNoiseForDictionaryArbitration({
    required _CameraRawLine original,
    required _CameraVerificationAttempt attempt,
    required List<_CameraVerificationAttempt> attempts,
  }) {
    final candidate = attempt.candidate;
    final originalRunes = original.text
        .replaceAll(RegExp(r'\s+'), '')
        .runes
        .toList(growable: false);
    final candidateRunes = candidate.text
        .replaceAll(RegExp(r'\s+'), '')
        .runes
        .toList(growable: false);

    // This normalization is deliberately narrower than general edit-distance
    // cleanup. It handles one crop-edge glyph only when removing that glyph
    // exposes the exact one-Japanese-character substitution that the existing
    // dictionary/ruby arbitration layer already knows how to judge.
    if (candidateRunes.length != originalRunes.length + 1 ||
        originalRunes.length < 2) {
      return candidate;
    }

    String? normalizedText;
    String? edgeLabel;
    String? removedCharacter;

    void considerBoundaryTrim({required bool leading}) {
      if (normalizedText != null) return;

      final boundaryRune = leading ? candidateRunes.first : candidateRunes.last;
      final boundaryCharacter = String.fromCharCode(boundaryRune);
      if (!_isLikelyVerificationBoundaryNoiseCharacter(boundaryCharacter)) {
        return;
      }

      if (_otherVerificationAttemptSupportsBoundaryRune(
        attempts: attempts,
        sourceAttempt: attempt,
        boundaryRune: boundaryRune,
        leading: leading,
        originalRuneLength: originalRunes.length,
      )) {
        return;
      }

      final trimmedRunes = leading
          ? candidateRunes.sublist(1)
          : candidateRunes.sublist(0, candidateRunes.length - 1);
      final trimmedText = String.fromCharCodes(trimmedRunes);

      if (_singleJapaneseSubstitutionRuneIndex(
            original.text,
            trimmedText,
          ) ==
          null) {
        return;
      }

      normalizedText = trimmedText;
      edgeLabel = leading ? 'leading' : 'trailing';
      removedCharacter = boundaryCharacter;
    }

    // Try both crop edges. If both could plausibly normalize the candidate,
    // keep the raw OCR candidate rather than guessing which edge was noise.
    considerBoundaryTrim(leading: true);
    final leadingText = normalizedText;
    final leadingEdge = edgeLabel;
    final leadingRemoved = removedCharacter;

    normalizedText = null;
    edgeLabel = null;
    removedCharacter = null;
    considerBoundaryTrim(leading: false);

    if (leadingText != null && normalizedText != null) {
      return candidate;
    }

    final chosenText = leadingText ?? normalizedText;
    final chosenEdge = leadingText != null ? leadingEdge : edgeLabel;
    final chosenRemoved = leadingText != null ? leadingRemoved : removedCharacter;
    if (chosenText == null) return candidate;

    if (kDebugMode && _debugOcrPipeline) {
      debugPrint(
        '[Camera OCR] ALIGN candidate="${candidate.text}" '
        '-> "$chosenText" trim=$chosenEdge removed="$chosenRemoved"',
      );
    }

    return _CameraRefinementCandidate(
      text: chosenText,
      confidence: candidate.confidence,
    );
  }

  bool _isLikelyVerificationBoundaryNoiseCharacter(String character) {
    // Do not trim punctuation. A tightly cropped retry can lose or hallucinate
    // sentence marks, and the full-photo pass is intentionally authoritative
    // for punctuation. Restrict this to glyph-like OCR spillover.
    return _isJapaneseCharacter(character) ||
        RegExp(r'[A-Za-z0-9]').hasMatch(character);
  }

  bool _otherVerificationAttemptSupportsBoundaryRune({
    required List<_CameraVerificationAttempt> attempts,
    required _CameraVerificationAttempt sourceAttempt,
    required int boundaryRune,
    required bool leading,
    required int originalRuneLength,
  }) {
    for (final otherAttempt in attempts) {
      if (identical(otherAttempt, sourceAttempt)) continue;

      final otherRunes = otherAttempt.candidate.text
          .replaceAll(RegExp(r'\s+'), '')
          .runes
          .toList(growable: false);
      if (otherRunes.length <= originalRuneLength) continue;

      final supported = leading
          ? otherRunes.first == boundaryRune
          : otherRunes.last == boundaryRune;
      if (supported) return true;
    }

    return false;
  }

  int? _singleJapaneseSubstitutionRuneIndex(String original, String candidate) {
    final originalRunes = original
        .replaceAll(RegExp(r'\s+'), '')
        .runes
        .toList(growable: false);
    final candidateRunes = candidate
        .replaceAll(RegExp(r'\s+'), '')
        .runes
        .toList(growable: false);

    if (originalRunes.length != candidateRunes.length) return null;

    int? differenceIndex;

    for (var index = 0; index < originalRunes.length; index++) {
      if (originalRunes[index] == candidateRunes[index]) continue;
      if (differenceIndex != null) return null;

      final originalCharacter = String.fromCharCode(originalRunes[index]);
      final candidateCharacter = String.fromCharCode(candidateRunes[index]);

      // Arbitration is intentionally character-focused. Punctuation, spacing,
      // or Latin OCR changes are never promoted by dictionary evidence.
      if (!_isJapaneseCharacter(originalCharacter) ||
          !_isJapaneseCharacter(candidateCharacter)) {
        return null;
      }

      differenceIndex = index;
    }

    return differenceIndex;
  }

  List<String> _dictionaryQueriesAroundRuneIndex(String value, int runeIndex) {
    final runes = value
        .replaceAll(RegExp(r'\s+'), '')
        .runes
        .toList(growable: false);
    if (runeIndex < 0 || runeIndex >= runes.length) return const [];

    var left = runeIndex;
    while (left > 0 &&
        _isJapaneseCharacter(String.fromCharCode(runes[left - 1]))) {
      left--;
    }

    var right = runeIndex + 1;
    while (right < runes.length &&
        _isJapaneseCharacter(String.fromCharCode(runes[right]))) {
      right++;
    }

    final lexicalRun = runes.sublist(left, right);
    final localIndex = runeIndex - left;
    if (lexicalRun.length < 2) return const [];

    final maxLength = lexicalRun.length < 10 ? lexicalRun.length : 10;
    final queries = <String>[];
    final seen = <String>{};

    // Longer exact entries are stronger evidence, so generate them first.
    for (var length = maxLength; length >= 2; length--) {
      var startMin = localIndex - length + 1;
      if (startMin < 0) startMin = 0;
      var startMax = localIndex;
      final lastPossibleStart = lexicalRun.length - length;
      if (startMax > lastPossibleStart) startMax = lastPossibleStart;

      for (var start = startMin; start <= startMax; start++) {
        final end = start + length;
        final surface = String.fromCharCodes(lexicalRun.sublist(start, end));
        if (seen.add(surface)) queries.add(surface);
      }
    }

    return queries;
  }

  _CameraDictionaryArbitrationEvidence _bestDictionaryArbitrationEvidence({
    required List<String> queries,
    required Map<String, List<Term>> dictionaryMatches,
    required List<CameraTextAnnotation> annotations,
  }) {
    var best = const _CameraDictionaryArbitrationEvidence();

    for (final query in queries) {
      final matches = dictionaryMatches[query] ?? const [];
      final japaneseLength = _japaneseContentLength(query);
      if (japaneseLength < 2) continue;

      for (final term in matches) {
        final kanji = term.kanji;
        final reading = term.reading;
        final exactSpelling = kanji == query;
        final exactReading = reading == query;
        if (!exactSpelling && !exactReading) continue;

        final rubySupported = _rubySupportsDictionaryReading(
          annotations,
          reading,
        );
        final score =
            japaneseLength.toDouble() +
            (exactSpelling ? 0.60 : 0.20) +
            (rubySupported ? 1.25 : 0.0);

        if (score <= best.score) continue;
        best = _CameraDictionaryArbitrationEvidence(
          surface: query,
          reading: reading,
          japaneseLength: japaneseLength,
          rubySupported: rubySupported,
          score: score,
        );
      }
    }

    return best;
  }

  bool _rubySupportsDictionaryReading(
    List<CameraTextAnnotation> annotations,
    String reading,
  ) {
    final normalizedReading = _normalizeKanaForArbitration(reading);
    if (normalizedReading.length < 2) return false;

    for (final annotation in annotations) {
      final normalizedRuby = _normalizeKanaForArbitration(annotation.text);
      if (normalizedRuby.length < 2) continue;

      if (normalizedRuby == normalizedReading) return true;

      final shorterLength = normalizedRuby.length < normalizedReading.length
          ? normalizedRuby.length
          : normalizedReading.length;
      if (shorterLength >= 3 &&
          (normalizedReading.contains(normalizedRuby) ||
              normalizedRuby.contains(normalizedReading))) {
        return true;
      }

      if (shorterLength >= 4) {
        final distance = _levenshteinDistance(
          normalizedRuby,
          normalizedReading,
        );
        final longestLength = normalizedRuby.length > normalizedReading.length
            ? normalizedRuby.length
            : normalizedReading.length;
        if (distance <= 1 && distance / longestLength <= 0.25) {
          return true;
        }
      }
    }

    return false;
  }

  String _normalizeKanaForArbitration(String value) {
    final buffer = StringBuffer();

    for (final rune in value.runes) {
      // Katakana and hiragana are normalized to hiragana so dictionary readings
      // can be compared with ruby regardless of script style.
      if (rune >= 0x30A1 && rune <= 0x30F6) {
        buffer.writeCharCode(rune - 0x60);
      } else if (rune >= 0x3041 && rune <= 0x3096) {
        buffer.writeCharCode(rune);
      } else if (rune == 0x30FC) {
        buffer.writeCharCode(rune);
      }
    }

    return buffer.toString();
  }

  String _debugDictionaryEvidence(_CameraDictionaryArbitrationEvidence evidence) {
    if (evidence.surface == null) return '-';
    final ruby = evidence.rubySupported ? ' ruby=yes' : '';
    final reading = evidence.reading == null || evidence.reading!.isEmpty
        ? ''
        : '[${evidence.reading}]';
    return '"${evidence.surface}"$reading '
        'len=${evidence.japaneseLength} score=${evidence.score.toStringAsFixed(2)}$ruby';
  }

  bool _shouldUseVerticalVerificationCandidate({
    required _CameraRawLine original,
    required _CameraRefinementCandidate candidate,
  }) {
    final candidateText = _cleanLineText(candidate.text);
    if (!_containsJapaneseCore(candidateText)) return false;
    if (candidateText == original.text) return false;

    // Do not let a higher-confidence crop erase or rewrite punctuation while
    // leaving every Japanese character unchanged. The full-photo pass has much
    // better context for sentence marks than a tightly cropped verification
    // image.
    if (_japaneseCoreSequence(candidateText) ==
        _japaneseCoreSequence(original.text)) {
      return false;
    }

    // A single Japanese-character substitution is handled by OCR consensus or
    // the dictionary/ruby arbitration layer above. Confidence by itself is not
    // enough to rewrite one valid-looking Japanese character into another.
    if (_singleJapaneseSubstitutionRuneIndex(original.text, candidateText) !=
        null) {
      return false;
    }

    final originalLength = _japaneseContentLength(original.text);
    final candidateLength = _japaneseContentLength(candidateText);
    if (originalLength == 0 || candidateLength == 0) return false;

    final lengthRatio = candidateLength / originalLength;
    if (lengthRatio < 0.78 || lengthRatio > 1.22) return false;

    final originalCompact = original.text.replaceAll(RegExp(r'\s+'), '');
    final candidateCompact = candidateText.replaceAll(RegExp(r'\s+'), '');
    final editDistance = _levenshteinDistance(
      originalCompact,
      candidateCompact,
    );
    final longestLength = originalCompact.length > candidateCompact.length
        ? originalCompact.length
        : candidateCompact.length;
    final difference = longestLength == 0
        ? 0.0
        : editDistance / longestLength;

    if (difference > 0.26) return false;

    final originalPenalty = _suspiciousTextPenalty(original.text);
    final candidatePenalty = _suspiciousTextPenalty(candidateText);
    if (candidatePenalty > originalPenalty) return false;

    final originalConfidence = original.confidence;
    final candidateConfidence = candidate.confidence;

    if (originalConfidence != null && candidateConfidence != null) {
      // A near-tie single-character reread is useful evidence when the original
      // line itself is not especially strong. ML Kit confidence is not directly
      // calibrated across differently cropped images, so requiring the crop to
      // score higher can reject a visually better reading (for example a retry
      // correcting one kanji while landing only a few points lower). Keep this
      // narrow: exactly one edit, close overall text, and an original below 0.58.
      if (editDistance == 1 &&
          originalConfidence < 0.58 &&
          candidateConfidence >= originalConfidence - 0.04 &&
          difference <= 0.14) {
        return true;
      }

      // Strong general rule: the retry must win by a meaningful amount.
      if (candidateConfidence >= originalConfidence + 0.08) {
        return true;
      }

      // Single-character corrections need less of a confidence jump because
      // this is the exact failure mode the verification pass is intended for.
      if (editDistance == 1 &&
          candidateConfidence >= originalConfidence + 0.05) {
        return true;
      }

      // Very uncertain originals may accept a close reread with a smaller
      // confidence gain, while still requiring the text to remain very close.
      if (originalConfidence < 0.35 &&
          candidateConfidence >= originalConfidence + 0.04 &&
          difference <= 0.18) {
        return true;
      }

      if (candidatePenalty < originalPenalty &&
          candidateConfidence >= originalConfidence - 0.01 &&
          difference <= 0.14) {
        return true;
      }

      return false;
    }

    return candidatePenalty < originalPenalty && difference <= 0.12;
  }

  Future<List<_CameraRawLine>> _refinePhysicalLinesWithSecondPass({
    required String imagePath,
    required Size imageSize,
    required List<_CameraRawLine> lines,
  }) async {
    if (!lines.any(_shouldRefinePhysicalLine)) {
      return lines;
    }

    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;
    final temporaryDirectory = await getTemporaryDirectory();
    final refinedLines = <_CameraRawLine>[];

    try {
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];

        if (!_shouldRefinePhysicalLine(line)) {
          refinedLines.add(line);
          continue;
        }

        File? refinementFile;

        try {
          refinementFile = await _renderPhysicalLineRefinementImage(
            sourceImage: sourceImage,
            imageSize: imageSize,
            line: line,
            directory: temporaryDirectory,
            index: index,
          );

          final refinedInput = InputImage.fromFilePath(refinementFile.path);
          final refinedRecognition =
              await _textRecognizer.processImage(refinedInput);
          final candidate = _bestPhysicalLineCandidate(refinedRecognition);

          if (candidate != null &&
              _shouldUseRefinedPhysicalLine(
                original: line,
                candidate: candidate,
              )) {
            refinedLines.add(
              line.copyWith(
                text: candidate.text,
                confidence: candidate.confidence,
              ),
            );
          } else {
            refinedLines.add(line);
          }
        } catch (_) {
          // Refinement is best-effort. The first pass always remains available.
          refinedLines.add(line);
        } finally {
          if (refinementFile != null) {
            try {
              if (await refinementFile.exists()) {
                await refinementFile.delete();
              }
            } catch (_) {
              // Temporary refinement files are best-effort cleanup only.
            }
          }
        }
      }
    } finally {
      sourceImage.dispose();
      codec.dispose();
    }

    return refinedLines;
  }

  bool _shouldRefinePhysicalLine(_CameraRawLine line) {
    if (line.orientation == CameraTextOrientation.vertical) {
      return false;
    }

    final japaneseLength = _japaneseContentLength(line.text);

    // Short labels are usually already reliable and do not benefit enough from
    // another OCR call. Sentence-like horizontal lines and suspicious readings
    // do. Vertical columns are handled separately by the confidence-gated
    // crop verification pass above.
    return japaneseLength >= 6 || _suspiciousTextPenalty(line.text) > 0;
  }

  Future<File> _renderPhysicalLineRefinementImage({
    required ui.Image sourceImage,
    required Size imageSize,
    required _CameraRawLine line,
    required Directory directory,
    required int index,
  }) async {
    final sourceRect = _paddedPhysicalLineRect(
      line.boundingBox,
      imageSize,
    );

    if (sourceRect.width <= 1 || sourceRect.height <= 1) {
      throw StateError('Physical line refinement crop is empty.');
    }

    var scale = 2.35;

    if (sourceRect.width * scale > 3200) {
      scale = 3200 / sourceRect.width;
    }

    if (sourceRect.height * scale > 900) {
      scale = 900 / sourceRect.height;
    }

    scale = scale.clamp(1.0, 2.5).toDouble();

    const outerPadding = 12.0;
    final targetWidth = (sourceRect.width * scale + outerPadding * 2)
        .ceil()
        .clamp(1, 3400)
        .toInt();
    final targetHeight = (sourceRect.height * scale + outerPadding * 2)
        .ceil()
        .clamp(1, 1000)
        .toInt();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        targetWidth.toDouble(),
        targetHeight.toDouble(),
      ),
      Paint()..color = Colors.white,
    );

    final destination = Rect.fromLTWH(
      outerPadding,
      outerPadding,
      sourceRect.width * scale,
      sourceRect.height * scale,
    );

    canvas.drawImageRect(
      sourceImage,
      sourceRect,
      destination,
      Paint()..filterQuality = FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final refinedImage = await picture.toImage(targetWidth, targetHeight);

    try {
      final data = await refinedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (data == null) {
        throw StateError('Could not encode physical line refinement image.');
      }

      final file = File(
        '${directory.path}/gakuji_camera_line_refine_'
        '${DateTime.now().microsecondsSinceEpoch}_$index.png',
      );
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );

      return file;
    } finally {
      refinedImage.dispose();
    }
  }

  Rect _paddedPhysicalLineRect(Rect rect, Size imageSize) {
    final horizontalPadding =
        (rect.height * 0.42).clamp(5.0, 38.0).toDouble();
    final verticalPadding =
        (rect.height * 0.24).clamp(3.0, 20.0).toDouble();

    return Rect.fromLTRB(
      (rect.left - horizontalPadding)
          .clamp(0.0, imageSize.width)
          .toDouble(),
      (rect.top - verticalPadding)
          .clamp(0.0, imageSize.height)
          .toDouble(),
      (rect.right + horizontalPadding)
          .clamp(0.0, imageSize.width)
          .toDouble(),
      (rect.bottom + verticalPadding)
          .clamp(0.0, imageSize.height)
          .toDouble(),
    );
  }

  _CameraRefinementCandidate? _bestPhysicalLineCandidate(
    RecognizedText recognizedText,
  ) {
    final pieces = <_CameraRefinementPiece>[];

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = _cleanLineText(line.text);
        if (!_isUsefulJapaneseLine(text)) continue;

        pieces.add(
          _CameraRefinementPiece(
            text: text,
            boundingBox: line.boundingBox,
            confidence: line.confidence,
          ),
        );
      }
    }

    if (pieces.isEmpty) return null;

    pieces.sort((first, second) {
      final vertical =
          first.boundingBox.center.dy.compareTo(second.boundingBox.center.dy);
      if (vertical != 0) return vertical;
      return first.boundingBox.left.compareTo(second.boundingBox.left);
    });

    final rows = <List<_CameraRefinementPiece>>[];

    for (final piece in pieces) {
      if (rows.isEmpty) {
        rows.add(<_CameraRefinementPiece>[piece]);
        continue;
      }

      final currentRow = rows.last;
      var rowBox = currentRow.first.boundingBox;

      for (final currentPiece in currentRow.skip(1)) {
        rowBox = rowBox.expandToInclude(currentPiece.boundingBox);
      }

      final averageHeight = (rowBox.height + piece.boundingBox.height) / 2;
      final centerDifference =
          (rowBox.center.dy - piece.boundingBox.center.dy).abs();
      final overlapTop = rowBox.top > piece.boundingBox.top
          ? rowBox.top
          : piece.boundingBox.top;
      final overlapBottom = rowBox.bottom < piece.boundingBox.bottom
          ? rowBox.bottom
          : piece.boundingBox.bottom;
      final overlap = overlapBottom - overlapTop;
      final shorter = rowBox.height < piece.boundingBox.height
          ? rowBox.height
          : piece.boundingBox.height;
      final overlapRatio = shorter <= 0
          ? 0.0
          : (overlap / shorter).clamp(0.0, 1.0).toDouble();

      if (overlapRatio >= 0.40 ||
          centerDifference <= averageHeight * 0.48) {
        currentRow.add(piece);
      } else {
        rows.add(<_CameraRefinementPiece>[piece]);
      }
    }

    _CameraRefinementCandidate? best;
    double bestScore = double.negativeInfinity;

    for (final row in rows) {
      row.sort((first, second) {
        return first.boundingBox.left.compareTo(second.boundingBox.left);
      });

      var text = '';
      var weightedConfidence = 0.0;
      var confidenceWeight = 0.0;

      for (final piece in row) {
        text = _joinText(text, piece.text);

        final confidence = piece.confidence;
        if (confidence != null) {
          final weight = _japaneseContentLength(piece.text).clamp(1, 40);
          weightedConfidence += confidence * weight;
          confidenceWeight += weight;
        }
      }

      final cleanedText = _cleanLineText(text);
      final japaneseLength = _japaneseContentLength(cleanedText);
      if (japaneseLength == 0) continue;

      final confidence = confidenceWeight > 0
          ? weightedConfidence / confidenceWeight
          : null;
      final score = japaneseLength * 4.0 +
          (confidence ?? 0.0) * 8.0 -
          _suspiciousTextPenalty(cleanedText) * 5.0;

      if (score > bestScore) {
        bestScore = score;
        best = _CameraRefinementCandidate(
          text: cleanedText,
          confidence: confidence,
        );
      }
    }

    return best;
  }

  bool _shouldUseRefinedPhysicalLine({
    required _CameraRawLine original,
    required _CameraRefinementCandidate candidate,
  }) {
    final refinedText = _cleanLineText(candidate.text);

    if (!_containsJapaneseCore(refinedText)) return false;
    if (refinedText == original.text) return false;

    final originalLength = _japaneseContentLength(original.text);
    final refinedLength = _japaneseContentLength(refinedText);
    if (originalLength == 0 || refinedLength == 0) return false;

    final lengthRatio = refinedLength / originalLength;
    if (lengthRatio < 0.82 || lengthRatio > 1.18) return false;

    final originalCompact = original.text.replaceAll(RegExp(r'\s+'), '');
    final refinedCompact = refinedText.replaceAll(RegExp(r'\s+'), '');
    final editDistance = _levenshteinDistance(
      originalCompact,
      refinedCompact,
    );
    final longestLength = originalCompact.length > refinedCompact.length
        ? originalCompact.length
        : refinedCompact.length;
    final normalizedDifference =
        longestLength == 0 ? 0.0 : editDistance / longestLength;

    // A line-level re-read is a correction tool, not permission to rewrite the
    // sentence. Large disagreements stay with the first full-photo OCR result.
    if (normalizedDifference > 0.26) return false;

    final originalPenalty = _suspiciousTextPenalty(original.text);
    final refinedPenalty = _suspiciousTextPenalty(refinedText);

    if (refinedPenalty > originalPenalty) return false;

    final originalConfidence = original.confidence;
    final refinedConfidence = candidate.confidence;

    if (originalConfidence != null && refinedConfidence != null) {
      if (refinedConfidence < originalConfidence - 0.02) return false;

      if (refinedPenalty < originalPenalty &&
          refinedConfidence >= originalConfidence - 0.01 &&
          normalizedDifference <= 0.18) {
        return true;
      }

      if (refinedConfidence >= originalConfidence + 0.05 &&
          normalizedDifference <= 0.24) {
        return true;
      }

      if (originalConfidence < 0.72 &&
          refinedConfidence >= 0.82 &&
          normalizedDifference <= 0.20) {
        return true;
      }

      // A one-character correction still needs a measurable confidence win.
      if (editDistance == 1 &&
          refinedConfidence >= originalConfidence + 0.03) {
        return true;
      }

      return false;
    }

    // Confidence can be unavailable on some platforms. In that case only use
    // the reread when it clearly removes suspicious OCR artifacts and makes a
    // very small change to the first-pass text.
    return refinedPenalty < originalPenalty && normalizedDifference <= 0.12;
  }

  int _suspiciousTextPenalty(String value) {
    if (!_containsJapaneseCore(value)) return 0;

    var penalty = 0;
    final characters = value.split('');

    for (var index = 0; index < characters.length; index++) {
      final character = characters[index];

      if (RegExp(r'[�□]').hasMatch(character)) {
        penalty += 3;
        continue;
      }

      if (!_isLatinOcrNoiseCandidate(character)) continue;

      final previous = _nearestNonSpaceCharacter(
        characters,
        start: index - 1,
        direction: -1,
      );
      final next = _nearestNonSpaceCharacter(
        characters,
        start: index + 1,
        direction: 1,
      );

      if (_isJapaneseCharacter(previous) || _isJapaneseCharacter(next)) {
        penalty += 2;
      }
    }

    return penalty;
  }

  int _levenshteinDistance(String first, String second) {
    if (first == second) return 0;
    if (first.isEmpty) return second.length;
    if (second.isEmpty) return first.length;

    var previous = List<int>.generate(second.length + 1, (index) => index);

    for (var firstIndex = 0; firstIndex < first.length; firstIndex++) {
      final current = List<int>.filled(second.length + 1, 0);
      current[0] = firstIndex + 1;

      for (var secondIndex = 0;
          secondIndex < second.length;
          secondIndex++) {
        final substitutionCost =
            first[firstIndex] == second[secondIndex] ? 0 : 1;
        final deletion = previous[secondIndex + 1] + 1;
        final insertion = current[secondIndex] + 1;
        final substitution = previous[secondIndex] + substitutionCost;

        current[secondIndex + 1] = deletion < insertion
            ? (deletion < substitution ? deletion : substitution)
            : (insertion < substitution ? insertion : substitution);
      }

      previous = current;
    }

    return previous.last;
  }

  Future<Size> _imageSizeForFile(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final size = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    image.dispose();
    codec.dispose();

    return size;
  }

  String _cleanLineText(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();

    return _removeInterstitialOcrNoise(normalized);
  }

  String _removeInterstitialOcrNoise(String value) {
    if (value.length < 3) return value;

    final characters = value.split('');
    final withoutLatinNoise = <String>[];

    for (var index = 0; index < characters.length; index++) {
      final character = characters[index];

      if (_isLatinOcrNoiseCandidate(character)) {
        final previous = _nearestNonSpaceCharacter(
          characters,
          start: index - 1,
          direction: -1,
        );
        final next = _nearestNonSpaceCharacter(
          characters,
          start: index + 1,
          direction: 1,
        );
        final previousImmediate = index > 0 ? characters[index - 1] : '';
        final nextImmediate =
            index + 1 < characters.length ? characters[index + 1] : '';
        final partOfLatinRun = _isLatinOcrNoiseCandidate(previousImmediate) ||
            _isLatinOcrNoiseCandidate(nextImmediate);

        if (!partOfLatinRun &&
            _isJapaneseCharacter(previous) &&
            _isJapaneseCharacter(next)) {
          continue;
        }
      }

      withoutLatinNoise.add(character);
    }

    final compacted = <String>[];

    for (var index = 0; index < withoutLatinNoise.length; index++) {
      final character = withoutLatinNoise[index];

      if (character == ' ') {
        final previous = _nearestNonSpaceCharacter(
          withoutLatinNoise,
          start: index - 1,
          direction: -1,
        );
        final next = _nearestNonSpaceCharacter(
          withoutLatinNoise,
          start: index + 1,
          direction: 1,
        );

        if (_isJapaneseCharacter(previous) && _isJapaneseCharacter(next)) {
          continue;
        }
      }

      compacted.add(character);
    }

    return compacted.join().trim();
  }

  String _nearestNonSpaceCharacter(
    List<String> characters, {
    required int start,
    required int direction,
  }) {
    var index = start;

    while (index >= 0 && index < characters.length) {
      final character = characters[index];

      if (character.trim().isNotEmpty) {
        return character;
      }

      index += direction;
    }

    return '';
  }

  bool _isLatinOcrNoiseCandidate(String value) {
    if (value.length != 1) return false;

    return RegExp(r'[A-Za-zＡ-Ｚａ-ｚ]').hasMatch(value);
  }


  bool _isUsefulJapaneseLine(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;

    final japaneseCount = _japaneseContentLength(text);
    if (japaneseCount == 0) return false;

    // A single Japanese-looking glyph mixed into a product number/ISBN is
    // commonly an OCR hallucination. Keep real one-character signs/labels,
    // but reject code-like strings dominated by Latin letters or digits.
    if (japaneseCount == 1) {
      final latinOrDigitCount = RegExp(
        r'[A-Za-z0-9Ａ-Ｚａ-ｚ０-９]',
      ).allMatches(text).length;

      if (latinOrDigitCount >= 2) return false;
    }

    return true;
  }

  bool _containsJapaneseCore(String value) {
    return RegExp(
      r'[\u3041-\u3096\u30A1-\u30FA\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々〆ヶ]',
    ).hasMatch(value);
  }
}

class _CameraRubyClassification {
  final List<_CameraRawLine> primaryLines;
  final List<_CameraRubyAttachment> attachments;

  _CameraRubyClassification({
    required List<_CameraRawLine> primaryLines,
    List<_CameraRubyAttachment> attachments = const [],
  })  : primaryLines = List.unmodifiable(primaryLines),
        attachments = List.unmodifiable(attachments);
}

class _CameraRubyAttachment {
  final CameraTextAnnotation annotation;
  final String primaryText;
  final Rect primaryBoundingBox;
  final double score;

  const _CameraRubyAttachment({
    required this.annotation,
    required this.primaryText,
    required this.primaryBoundingBox,
    required this.score,
  });
}

class _CameraBoundaryLanguageEvidence {
  final Set<String> lexicalSurfaces;

  const _CameraBoundaryLanguageEvidence({
    this.lexicalSurfaces = const <String>{},
  });
}

class _CameraSharedRunMatch {
  final int firstStart;
  final int secondStart;
  final int length;
  final String text;

  const _CameraSharedRunMatch({
    required this.firstStart,
    required this.secondStart,
    required this.length,
    required this.text,
  });
}

class _CameraPaddleRefinementResult {
  final List<_CameraRawLine> lines;
  final Set<int> confirmedLineIndexes;
  final Set<int> directKeepLineIndexes;

  Set<int> get skipLegacyLineIndexes => <int>{
        ...confirmedLineIndexes,
        ...directKeepLineIndexes,
      };

  _CameraPaddleRefinementResult({
    required List<_CameraRawLine> lines,
    required Set<int> confirmedLineIndexes,
    required Set<int> directKeepLineIndexes,
  })  : lines = List.unmodifiable(lines),
        confirmedLineIndexes = Set.unmodifiable(confirmedLineIndexes),
        directKeepLineIndexes = Set.unmodifiable(directKeepLineIndexes);
}

class _CameraRawLine {
  final String text;
  final Rect boundingBox;
  final int blockIndex;
  final double? confidence;
  final double? angle;
  final CameraTextOrientation orientation;
  final List<CameraTextAnnotation> annotations;

  _CameraRawLine({
    required this.text,
    required this.boundingBox,
    required this.blockIndex,
    required this.confidence,
    this.angle,
    required this.orientation,
    List<CameraTextAnnotation> annotations = const [],
  }) : annotations = List.unmodifiable(annotations);

  _CameraRawLine copyWith({
    String? text,
    double? confidence,
    double? angle,
    CameraTextOrientation? orientation,
    List<CameraTextAnnotation>? annotations,
  }) {
    return _CameraRawLine(
      text: text ?? this.text,
      boundingBox: boundingBox,
      blockIndex: blockIndex,
      confidence: confidence ?? this.confidence,
      angle: angle ?? this.angle,
      orientation: orientation ?? this.orientation,
      annotations: annotations ?? this.annotations,
    );
  }
}

class _CameraDictionaryArbitrationAlternative {
  final _CameraVerificationAttempt attempt;
  final int substitutionIndex;
  final List<String> originalQueries;
  final List<String> candidateQueries;

  const _CameraDictionaryArbitrationAlternative({
    required this.attempt,
    required this.substitutionIndex,
    required this.originalQueries,
    required this.candidateQueries,
  });
}

class _CameraDictionaryArbitrationEvidence {
  final String? surface;
  final String? reading;
  final int japaneseLength;
  final bool rubySupported;
  final double score;

  const _CameraDictionaryArbitrationEvidence({
    this.surface,
    this.reading,
    this.japaneseLength = 0,
    this.rubySupported = false,
    this.score = 0.0,
  });
}

class _CameraVerticalVerificationBox {
  final List<int> lineIndexes;
  final Rect boundingBox;

  _CameraVerticalVerificationBox({
    required List<int> lineIndexes,
    required this.boundingBox,
  }) : lineIndexes = List.unmodifiable(lineIndexes);
}

class _CameraTextBoxVerificationRender {
  final File file;
  final Rect sourceRect;
  final Rect destinationRect;

  const _CameraTextBoxVerificationRender({
    required this.file,
    required this.sourceRect,
    required this.destinationRect,
  });
}

class _CameraTextBoxCandidateLine {
  final String text;
  final Rect boundingBox;
  final double? confidence;

  const _CameraTextBoxCandidateLine({
    required this.text,
    required this.boundingBox,
    required this.confidence,
  });
}

class _CameraTextBoxCandidateMatch {
  final int lineIndex;
  final int candidateIndex;
  final double score;

  const _CameraTextBoxCandidateMatch({
    required this.lineIndex,
    required this.candidateIndex,
    required this.score,
  });
}

class _CameraVerificationAttempt {
  final String label;
  final _CameraRefinementCandidate candidate;

  const _CameraVerificationAttempt({
    required this.label,
    required this.candidate,
  });
}

class _CameraRefinementPiece {
  final String text;
  final Rect boundingBox;
  final double? confidence;

  const _CameraRefinementPiece({
    required this.text,
    required this.boundingBox,
    required this.confidence,
  });
}

class _CameraRefinementCandidate {
  final String text;
  final double? confidence;

  const _CameraRefinementCandidate({
    required this.text,
    required this.confidence,
  });
}

class _CameraVisualRow {
  final List<_CameraTextFragment> fragments = <_CameraTextFragment>[];
  Rect anchorBoundingBox;

  _CameraVisualRow(_CameraTextFragment first)
      : anchorBoundingBox = first.boundingBox {
    fragments.add(first);
  }

  void addAnchorFragment(_CameraTextFragment fragment) {
    fragments.add(fragment);
    anchorBoundingBox = anchorBoundingBox.expandToInclude(fragment.boundingBox);
  }

  void addDetachedFragment(_CameraTextFragment fragment) {
    fragments.add(fragment);
  }
}

class _CameraVerticalTextBox {
  final List<_CameraTextFragment> fragments;

  _CameraVerticalTextBox(List<_CameraTextFragment> fragments)
      : fragments = List.unmodifiable(fragments);

  Rect get boundingBox {
    if (fragments.isEmpty) return Rect.zero;

    var combined = fragments.first.boundingBox;
    for (final fragment in fragments.skip(1)) {
      combined = combined.expandToInclude(fragment.boundingBox);
    }

    return combined;
  }
}

class _CameraVisualColumn {
  final List<_CameraTextFragment> fragments = <_CameraTextFragment>[];
  Rect anchorBoundingBox;

  _CameraVisualColumn(_CameraTextFragment first)
      : anchorBoundingBox = first.boundingBox {
    fragments.add(first);
  }

  void addAnchorFragment(_CameraTextFragment fragment) {
    fragments.add(fragment);
    anchorBoundingBox = anchorBoundingBox.expandToInclude(fragment.boundingBox);
  }

  void addDetachedFragment(_CameraTextFragment fragment) {
    fragments.add(fragment);
  }
}

class _CameraTextFragment {
  final String text;
  final List<Rect> boundingBoxes;
  final List<CameraTextAnnotation> annotations;
  final int blockIndex;
  final CameraTextOrientation orientation;
  final bool endsSentence;

  _CameraTextFragment({
    required this.text,
    required List<Rect> boundingBoxes,
    List<CameraTextAnnotation> annotations = const [],
    required this.blockIndex,
    required this.orientation,
    required this.endsSentence,
  })  : boundingBoxes = List.unmodifiable(boundingBoxes),
        annotations = List.unmodifiable(annotations);

  Rect get boundingBox {
    if (boundingBoxes.isEmpty) return Rect.zero;

    var combined = boundingBoxes.first;
    for (final box in boundingBoxes.skip(1)) {
      combined = combined.expandToInclude(box);
    }

    return combined;
  }

  Rect get headBoundingBox =>
      boundingBoxes.isEmpty ? Rect.zero : boundingBoxes.first;

  Rect get tailBoundingBox =>
      boundingBoxes.isEmpty ? Rect.zero : boundingBoxes.last;
}
