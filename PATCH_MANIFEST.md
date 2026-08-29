# Gakuji PaddleOCR native-batch speed patch

This patch is narrowly scoped to Camera Mode OCR latency and Paddle result safety.

## Changed files

- `lib/services/camera_text_recognition_service.dart`
  - Replaces per-column Dart PNG rendering/temp-file Paddle calls with one native batch request.
  - Uses a tighter main-column crop tailored to Paddle while preserving original source pixels.
  - Adds per-column and aggregate Paddle timing logs.
  - Requires differing Paddle replacements to preserve 84%-118% of the Japanese core length and stay within 0.42 normalized edit distance.
  - Scopes legacy whole-text-box ML Kit verification to local unresolved neighborhoods (up to four unresolved columns plus immediate context) instead of rereading an entire large text box.

- `lib/services/paddle_camera_ocr_service.dart`
  - Adds batched localized-column request/result types.
  - Sends the original image path and all Paddle crop rectangles in one native call.

- `packages/gakuji_paddle_ocr/lib/gakuji_paddle_ocr.dart`
  - Adds the `recognizeLocalizedColumns` method-channel API and batch timing/result models.
  - Keeps the original single-column API for compatibility.

- `packages/gakuji_paddle_ocr/android/src/main/kotlin/com/mattrohde/gakuji_paddle_ocr/GakujiPaddleOcrPlugin.kt`
  - Decodes/orients the source image once per scan.
  - Crops all requested columns in memory; no Paddle temp PNG files.
  - Reuses one already-loaded PaddleOCR instance for the full request.
  - Sets `recBatchSize = 4` so Paddle batches recognition boxes internally while keeping the same PP-OCRv5 mobile models and detection/recognition thresholds.
  - Returns per-column Paddle timings plus source decode and native batch wall time.

## Important

No Paddle model, model weights, detector thresholds, confidence threshold, Camera UI, ruby classification, sentence reconstruction, or dictionary behavior was changed.

Because the native Kotlin plugin changed, do a full Android rebuild. You do **not** need to rerun `tools/install_paddle_android.ps1`.

```text
flutter clean
flutter pub get
flutter run
```
