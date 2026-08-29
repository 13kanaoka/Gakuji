import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:gakuji_paddle_ocr/gakuji_paddle_ocr.dart';

class CameraPaddleCropRequest {
  final int lineIndex;
  final Rect cropRect;

  const CameraPaddleCropRequest({
    required this.lineIndex,
    required this.cropRect,
  });
}

class CameraPaddleRecognition {
  final String text;
  final double confidence;
  final int detectedItemCount;
  final int detectionTimeMs;
  final int recognitionTimeMs;
  final int totalTimeMs;
  final int cropWidth;
  final int cropHeight;

  const CameraPaddleRecognition({
    required this.text,
    required this.confidence,
    required this.detectedItemCount,
    required this.detectionTimeMs,
    required this.recognitionTimeMs,
    required this.totalTimeMs,
    required this.cropWidth,
    required this.cropHeight,
  });
}

class CameraPaddleBatchRecognition {
  final Map<int, CameraPaddleRecognition> resultsByLineIndex;
  final int sourceDecodeTimeMs;
  final int nativeBatchWallTimeMs;

  const CameraPaddleBatchRecognition({
    required this.resultsByLineIndex,
    required this.sourceDecodeTimeMs,
    required this.nativeBatchWallTimeMs,
  });
}

class PaddleCameraOcrService {
  static bool _disabledForSession = false;

  static Future<CameraPaddleBatchRecognition?> recognizeLocalizedVerticalCrops({
    required String imagePath,
    required Size imageSize,
    required List<CameraPaddleCropRequest> crops,
  }) async {
    if (_disabledForSession ||
        defaultTargetPlatform != TargetPlatform.android ||
        crops.isEmpty) {
      return null;
    }

    try {
      final batch = await GakujiPaddleOcr.recognizeLocalizedColumns(
        imagePath: imagePath,
        imageWidth: imageSize.width,
        imageHeight: imageSize.height,
        columns: <GakujiPaddleOcrColumnRequest>[
          for (final crop in crops)
            GakujiPaddleOcrColumnRequest(
              requestId: crop.lineIndex,
              left: crop.cropRect.left,
              top: crop.cropRect.top,
              right: crop.cropRect.right,
              bottom: crop.cropRect.bottom,
            ),
        ],
      );

      final results = <int, CameraPaddleRecognition>{};
      for (final result in batch.results) {
        final text = result.text.trim();
        if (result.requestId < 0 || text.isEmpty) continue;
        results[result.requestId] = CameraPaddleRecognition(
          text: text,
          confidence: result.confidence,
          detectedItemCount: result.detectedItemCount,
          detectionTimeMs: result.detectionTimeMs,
          recognitionTimeMs: result.recognitionTimeMs,
          totalTimeMs: result.totalTimeMs,
          cropWidth: result.cropWidth,
          cropHeight: result.cropHeight,
        );
      }

      return CameraPaddleBatchRecognition(
        resultsByLineIndex: results,
        sourceDecodeTimeMs: batch.sourceDecodeTimeMs,
        nativeBatchWallTimeMs: batch.batchWallTimeMs,
      );
    } on GakujiPaddleOcrUnavailableException catch (error) {
      _disabledForSession = true;
      if (kDebugMode) {
        debugPrint('[Camera OCR] PADDLE unavailable: ${error.message}');
      }
      return null;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Camera OCR] PADDLE batch error: $error');
      }
      return null;
    }
  }
}
