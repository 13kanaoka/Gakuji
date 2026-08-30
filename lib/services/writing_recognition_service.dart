import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';

import 'package:gakuji/models/writing_point.dart';

class WritingRecognitionService {
  static const String japaneseModel = 'ja';

  static final DigitalInkRecognizer _recognizer =
      DigitalInkRecognizer(languageCode: japaneseModel);

  static final DigitalInkRecognizerModelManager _modelManager =
      DigitalInkRecognizerModelManager();

  static bool _modelReady = false;
  static bool _preloadStarted = false;
  static Future<bool>? _modelPreparation;

  /// Starts provisioning the Japanese handwriting model immediately at app
  /// launch.
  ///
  /// ML Kit stores downloaded digital-ink models on the device, so this is
  /// effectively a one-time download. On later launches the first availability
  /// check returns from the local model cache and no network download is needed.
  ///
  /// A few quiet retries are made during the first minute of the session in case
  /// connectivity is still coming online while Gakuji is opening. Failure is not
  /// fatal: handwriting recognition will try again whenever it is actually used.
  static Future<void> preloadJapaneseModel() async {
    if (_preloadStarted) return;
    _preloadStarted = true;

    const retryDelays = <Duration>[
      Duration.zero,
      Duration(seconds: 8),
      Duration(seconds: 24),
    ];

    for (final delay in retryDelays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }

      try {
        if (await ensureJapaneseModelDownloaded()) return;
      } catch (_) {
        // Startup provisioning is intentionally best-effort. Gakuji must remain
        // usable even when the device is offline during its first launch.
      }
    }
  }

  /// Makes sure the Japanese handwriting model is available on the device.
  ///
  /// The first successful call downloads it if needed. ML Kit then keeps the
  /// model in its on-device model store, so normal future use works offline.
  static Future<bool> ensureJapaneseModelDownloaded() async {
    if (_modelReady) return true;

    final existingPreparation = _modelPreparation;
    if (existingPreparation != null) return existingPreparation;

    final preparation = _prepareJapaneseModel();
    _modelPreparation = preparation;

    try {
      return await preparation;
    } finally {
      if (identical(_modelPreparation, preparation)) {
        _modelPreparation = null;
      }
    }
  }

  static Future<bool> _prepareJapaneseModel() async {
    final isDownloaded = await _modelManager.isModelDownloaded(japaneseModel);

    if (isDownloaded) {
      _modelReady = true;
      return true;
    }

    final didDownload = await _modelManager.downloadModel(japaneseModel);

    if (didDownload) {
      _modelReady = true;
      return true;
    }

    // The manager is the source of truth. Re-check in case the model finished
    // installing while another native request was completing.
    _modelReady = await _modelManager.isModelDownloaded(japaneseModel);
    return _modelReady;
  }

  /// Recognizes only the currently active writing slot.
  ///
  /// Each slot should represent one kanji character. Existing study flows only
  /// need the best match, so this keeps the original single-result API while
  /// the dictionary can use [recognizeCandidates] for handwriting suggestions.
  static Future<String> recognizeSlot({
    required List<List<WritingPoint>> slotStrokes,
    required String mockCharacter,
  }) async {
    final candidates = await recognizeCandidates(
      slotStrokes: slotStrokes,
      mockCharacter: mockCharacter,
      maxCandidates: 1,
    );

    if (candidates.isEmpty) return '';
    return candidates.first;
  }

  /// Returns ML Kit's ranked alternatives for the active writing slot.
  ///
  /// Digital Ink Recognition already ranks characters by how well their stroke
  /// shapes match the user's writing, so exposing more of this list gives the
  /// dictionary useful look-alike/correction candidates instead of discarding
  /// every result after the first one.
  static Future<List<String>> recognizeCandidates({
    required List<List<WritingPoint>> slotStrokes,
    required String mockCharacter,
    int maxCandidates = 16,
    bool kanjiOnly = false,
  }) async {
    if (!hasStrokesInSlot(slotStrokes) || maxCandidates <= 0) {
      return const <String>[];
    }

    try {
      final modelReady = await ensureJapaneseModelDownloaded();

      if (!modelReady) return const <String>[];

      final ink = _buildInkFromSlot(slotStrokes);
      final recognized = await _recognizer.recognize(ink);

      if (recognized.isEmpty) return const <String>[];

      final results = <String>[];
      final seen = <String>{};

      for (final candidate in recognized) {
        final character = _firstCharacterOnly(candidate.text);
        if (character.isEmpty) continue;
        if (kanjiOnly && !_isKanjiCharacter(character)) continue;
        if (!seen.add(character)) continue;

        results.add(character);
        if (results.length >= maxCandidates) break;
      }

      return results;
    } catch (error) {
      return const <String>[];
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

  static bool _isKanjiCharacter(String value) {
    final runes = value.runes.toList();
    if (runes.length != 1) return false;

    final rune = runes.first;
    return (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0xF900 && rune <= 0xFAFF);
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
