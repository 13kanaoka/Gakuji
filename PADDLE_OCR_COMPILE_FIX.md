# PaddleOCR Android compile fix

The first integration installed PaddleOCR's Kotlin SDK under `src/main/kotlin/com/paddle/ocr`.
On the failing Gakuji build, the Flutter plugin itself was discovered, but every import from
`com.paddle.ocr` was unresolved. The repair mirrors PaddleOCR's official Android module
layout exactly by installing the SDK under:

`packages/gakuji_paddle_ocr/android/src/main/java/com/paddle/ocr`

The installer now verifies the public entry point plus representative model/util files and
refuses to continue if the SDK copy is incomplete. The plugin Gradle file also adds a
pre-build check that produces one clear error if the SDK was not installed.

## Apply

Overwrite these two project-relative files:

- `packages/gakuji_paddle_ocr/android/build.gradle`
- `tools/install_paddle_android.ps1`

Then from the **Gakuji project root** run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tools\install_paddle_android.ps1
flutter clean
flutter pub get
flutter run
```

The installer removes the stale old `src/main/kotlin/com/paddle/ocr` SDK copy automatically.
It preserves already-downloaded PP-OCRv5 model assets when all three required model files
are present.

The Gradle 8.13 deprecation warning and Flutter Built-in Kotlin warning seen in the log are
not the current build blocker; they can be handled separately after PaddleOCR compiles.
