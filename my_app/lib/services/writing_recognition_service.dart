import 'dart:ui';

import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';

import '../models/writing_point.dart';

class WritingRecognitionService {
  static const String japaneseModel = 'ja';

  static final DigitalInkRecognizer _recognizer =
      DigitalInkRecognizer(languageCode: japaneseModel);

  static final DigitalInkRecognizerModelManager _modelManager =
      DigitalInkRecognizerModelManager();

  static bool _modelReady = false;

  /// Makes sure the Japanese handwriting model is available on the device.
  ///
  /// The model is downloaded the first time recognition is needed.
  static Future<bool> ensureJapaneseModelDownloaded() async {
    if (_modelReady) return true;

    final isDownloaded = await _modelManager.isModelDownloaded(japaneseModel);

    if (isDownloaded) {
      _modelReady = true;
      return true;
    }

    final didDownload = await _modelManager.downloadModel(japaneseModel);

    _modelReady = didDownload;

    return didDownload;
  }

  /// Recognizes only the currently active writing slot.
  ///
  /// Each slot should represent one kanji character.
  static Future<String> recognizeSlot({
    required List<List<WritingPoint>> slotStrokes,
    required String mockCharacter,
  }) async {
    if (!hasStrokesInSlot(slotStrokes)) return '';

    try {
      final modelReady = await ensureJapaneseModelDownloaded();

      if (!modelReady) return '';

      final ink = _buildInkFromSlot(slotStrokes);
      final candidates = await _recognizer.recognize(ink);

      if (candidates.isEmpty) return '';

      final bestCandidate = candidates.first.text;

      return _firstCharacterOnly(bestCandidate);
    } catch (error) {
      return '';
    }
  }

  static Ink _buildInkFromSlot(List<List<WritingPoint>> slotStrokes) {
    final ink = Ink();

    ink.strokes = slotStrokes
        .where((rawStroke) => rawStroke.isNotEmpty)
        .map((rawStroke) {
      final stroke = Stroke();

      stroke.points = rawStroke.map((point) {
        return StrokePoint(
          x: point.x,
          y: point.y,
          t: point.time,
        );
      }).toList();

      return stroke;
    }).toList();

    return ink;
  }

  static String _firstCharacterOnly(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), '');

    if (normalized.isEmpty) return '';

    return String.fromCharCode(normalized.runes.first);
  }

  /// Checks whether the active slot has any drawn strokes.
  static bool hasStrokesInSlot(List<List<WritingPoint>> slotStrokes) {
    return slotStrokes.isNotEmpty;
  }

  /// Checks whether every answer slot has been filled with a recognized value.
  static bool areAllSlotsFilled(List<String?> slotAnswers) {
    return slotAnswers.every((answer) => answer != null && answer.isNotEmpty);
  }

  /// Joins all recognized slot values into one submitted answer.
  static String buildSubmittedAnswer(List<String?> slotAnswers) {
    return slotAnswers.map((answer) => answer ?? '').join();
  }

  /// Releases native ML Kit resources.
  ///
  /// We are not calling this from the writing page yet because this recognizer
  /// is shared statically. Later, if we move this service to instance-based
  /// lifecycle management, we can call this from dispose().
  static Future<void> close() async {
    await _recognizer.close();
  }
}