# Gakuji Camera Mode - PaddleOCR Android setup

This patch adds PP-OCRv5 mobile as an **experimental Android character-recognition backend** for vertical Camera Mode columns.

Gakuji still uses the existing ML Kit/layout pipeline to establish physical text geometry, separate ruby/furigana, infer text boxes, and reconstruct sentences. PaddleOCR receives only a localized main-text column crop and performs its own detection/rectification/recognition inside that crop.

## Why the Android minimum changes

PaddleOCR's official `ppocr-sdk` currently declares Android `minSdk = 26`. This patch therefore changes Gakuji's Android minimum from API 24 to API 26.

## One-time installation

From the Gakuji project root in PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tools\install_paddle_android.ps1
```

The script:

1. Sparse-clones the official PaddleOCR Android SDK source.
2. Copies `com.paddle.ocr` into Gakuji's local `gakuji_paddle_ocr` Flutter plugin.
3. Downloads the official PP-OCRv5 mobile detection and recognition ONNX archives.
4. Installs `inference.onnx` / `inference.yml` under the plugin's Android assets.
5. Copies PaddleOCR's Apache-2.0 license into the local plugin.

The large third-party model binaries are intentionally not included in this patch ZIP.

Then rebuild native code:

```powershell
flutter pub get
flutter clean
flutter run
```

A hot reload is not enough for the first PaddleOCR build because the patch adds a local Flutter plugin, Android native dependencies, Kotlin source, and model assets.

## Debug behavior

In debug builds Camera Mode logs entries similar to:

```text
[Camera OCR] PADDLE line=2 mlkit="ロの炎一つで" paddle="己の炎一つで" conf=0.916 items=1 decision=REPLACE
```

If PaddleOCR is missing, cannot initialize, or fails on a crop, Camera Mode keeps the existing ML Kit result. The current ML Kit retry/fusion path is not removed by this patch.

## Current scope

- Android only for this first integration.
- PP-OCRv5 mobile.
- Paddle is applied to localized **vertical primary columns** only.
- Existing horizontal OCR and all Gakuji layout/highlight behavior remain unchanged.

Note: the local plugin pins QuickBird OpenCV to `4.5.3.0`; a July 2026 PaddleOCR Android issue/PR reports that the incomplete `4.5.3` coordinate can fail to load the native OpenCV library on device.
