import 'package:flutter/services.dart';

class GakujiPaddleOcrUnavailableException implements Exception {
  final String message;

  const GakujiPaddleOcrUnavailableException(this.message);

  @override
  String toString() => 'GakujiPaddleOcrUnavailableException: $message';
}

class GakujiPaddleOcrColumnRequest {
  final int requestId;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const GakujiPaddleOcrColumnRequest({
    required this.requestId,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'requestId': requestId,
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    };
  }
}

class GakujiPaddleOcrResult {
  final int requestId;
  final String text;
  final double confidence;
  final int detectedItemCount;
  final int detectionTimeMs;
  final int recognitionTimeMs;
  final int totalTimeMs;
  final int cropWidth;
  final int cropHeight;

  const GakujiPaddleOcrResult({
    this.requestId = -1,
    required this.text,
    required this.confidence,
    required this.detectedItemCount,
    required this.detectionTimeMs,
    required this.recognitionTimeMs,
    required this.totalTimeMs,
    this.cropWidth = 0,
    this.cropHeight = 0,
  });

  factory GakujiPaddleOcrResult.fromMap(Map<dynamic, dynamic> raw) {
    return GakujiPaddleOcrResult(
      requestId: (raw['requestId'] as num?)?.toInt() ?? -1,
      text: (raw['text'] as String? ?? '').trim(),
      confidence: (raw['confidence'] as num?)?.toDouble() ?? 0.0,
      detectedItemCount: (raw['detectedItemCount'] as num?)?.toInt() ?? 0,
      detectionTimeMs: (raw['detectionTimeMs'] as num?)?.toInt() ?? 0,
      recognitionTimeMs: (raw['recognitionTimeMs'] as num?)?.toInt() ?? 0,
      totalTimeMs: (raw['totalTimeMs'] as num?)?.toInt() ?? 0,
      cropWidth: (raw['cropWidth'] as num?)?.toInt() ?? 0,
      cropHeight: (raw['cropHeight'] as num?)?.toInt() ?? 0,
    );
  }
}

class GakujiPaddleOcrBatchResult {
  final List<GakujiPaddleOcrResult> results;
  final int sourceDecodeTimeMs;
  final int batchWallTimeMs;

  const GakujiPaddleOcrBatchResult({
    required this.results,
    required this.sourceDecodeTimeMs,
    required this.batchWallTimeMs,
  });
}

class GakujiPaddleOcr {
  static const MethodChannel _channel = MethodChannel(
    'com.mattrohde.gakuji/paddle_ocr',
  );

  static Future<GakujiPaddleOcrResult?> recognizeLocalizedColumn(
    String imagePath,
  ) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'recognizeLocalizedColumn',
        <String, dynamic>{'imagePath': imagePath},
      );

      if (raw == null) return null;

      final parsed = GakujiPaddleOcrResult.fromMap(raw);
      if (parsed.text.isEmpty) return null;
      return parsed;
    } on MissingPluginException {
      throw const GakujiPaddleOcrUnavailableException(
        'Android PaddleOCR plugin is not registered.',
      );
    } on PlatformException catch (error) {
      if (error.code == 'paddle_unavailable' ||
          error.code == 'paddle_assets_missing') {
        throw GakujiPaddleOcrUnavailableException(
          error.message ?? 'PaddleOCR is unavailable.',
        );
      }
      rethrow;
    }
  }

  static Future<GakujiPaddleOcrBatchResult> recognizeLocalizedColumns({
    required String imagePath,
    required double imageWidth,
    required double imageHeight,
    required List<GakujiPaddleOcrColumnRequest> columns,
  }) async {
    if (columns.isEmpty) {
      return const GakujiPaddleOcrBatchResult(
        results: <GakujiPaddleOcrResult>[],
        sourceDecodeTimeMs: 0,
        batchWallTimeMs: 0,
      );
    }

    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'recognizeLocalizedColumns',
        <String, dynamic>{
          'imagePath': imagePath,
          'imageWidth': imageWidth,
          'imageHeight': imageHeight,
          'columns': columns.map((column) => column.toMap()).toList(),
        },
      );

      if (raw == null) {
        return const GakujiPaddleOcrBatchResult(
          results: <GakujiPaddleOcrResult>[],
          sourceDecodeTimeMs: 0,
          batchWallTimeMs: 0,
        );
      }

      final rawResults = raw['results'];
      final parsed = <GakujiPaddleOcrResult>[];
      if (rawResults is List) {
        for (final entry in rawResults) {
          if (entry is Map) {
            final item = GakujiPaddleOcrResult.fromMap(entry);
            if (item.text.isNotEmpty) parsed.add(item);
          }
        }
      }

      return GakujiPaddleOcrBatchResult(
        results: parsed,
        sourceDecodeTimeMs:
            (raw['sourceDecodeTimeMs'] as num?)?.toInt() ?? 0,
        batchWallTimeMs: (raw['batchWallTimeMs'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      throw const GakujiPaddleOcrUnavailableException(
        'Android PaddleOCR plugin is not registered.',
      );
    } on PlatformException catch (error) {
      if (error.code == 'paddle_unavailable' ||
          error.code == 'paddle_assets_missing') {
        throw GakujiPaddleOcrUnavailableException(
          error.message ?? 'PaddleOCR is unavailable.',
        );
      }
      rethrow;
    }
  }
}
