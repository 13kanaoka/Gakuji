import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';

import '../models/term.dart';
import '../services/camera_saved_scan_store.dart';
import '../services/camera_text_analysis_service.dart';
import '../services/camera_text_recognition_service.dart';
import '../services/dictionary_service.dart';
import '../widgets/gakuji_page_route.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_term_row.dart';
import 'camera_saved_scans_page.dart';
import 'dictionary_detail_page.dart';
import 'camera_sentence_detail_page.dart';

class CameraDictionaryPage extends StatefulWidget {
  const CameraDictionaryPage({super.key});

  @override
  State<CameraDictionaryPage> createState() => _CameraDictionaryPageState();
}

class _CameraDictionaryPageState extends State<CameraDictionaryPage>
    with WidgetsBindingObserver {
  final CameraTextRecognitionService _recognitionService =
      CameraTextRecognitionService();
  final ImagePicker _imagePicker = ImagePicker();
  final TransformationController _photoTransformationController =
      TransformationController();
  final GlobalKey _cameraPreviewKey = GlobalKey();

  CameraController? _cameraController;
  CameraRecognitionResult? _recognitionResult;

  String? _capturedImagePath;
  String? _cameraError;
  String? _scanError;

  bool _isInitializingCamera = false;
  bool _isTakingPhoto = false;
  bool _isRecognizingPhoto = false;
  double _scanProgress = 0.0;
  bool _isAnalyzingSelection = false;
  bool _isPickingImage = false;
  bool _isSavingScan = false;
  bool _isOpeningSavedScans = false;
  bool _deleteCapturedImageWhenDone = false;
  bool _flashEnabled = true;
  double _minCameraZoom = 1.0;
  double _maxCameraZoom = 1.0;
  double _cameraZoomLevel = 1.0;
  double _cameraZoomStartLevel = 1.0;
  Offset? _cameraFocusIndicatorPosition;
  bool _showCameraFocusIndicator = false;
  Timer? _cameraFocusIndicatorTimer;
  String? _savedScanId;
  String? _transientMessage;
  Timer? _transientMessageTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_disposeCameraController());
      return;
    }

    if (state == AppLifecycleState.resumed &&
        _capturedImagePath == null &&
        !_isPickingImage) {
      unawaited(_initializeCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    unawaited(_recognitionService.dispose());
    _photoTransformationController.dispose();
    _cameraFocusIndicatorTimer?.cancel();
    _transientMessageTimer?.cancel();
    unawaited(_deleteCapturedPhoto());
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    if (_isInitializingCamera || _capturedImagePath != null) return;

    setState(() {
      _isInitializingCamera = true;
      _cameraError = null;
    });

    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cameraError = 'No camera is available on this device.';
          _isInitializingCamera = false;
        });
        return;
      }

      final backCameras = cameras
          .where(
            (camera) => camera.lensDirection == CameraLensDirection.back,
          )
          .toList(growable: false);
      final camera = _preferredBackCamera(backCameras, cameras);

      await _disposeCameraController();

      final controller = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      _cameraController = controller;

      await controller.initialize();

      var minZoom = 1.0;
      var maxZoom = 1.0;

      try {
        minZoom = await controller.getMinZoomLevel();
        maxZoom = await controller.getMaxZoomLevel();
      } on CameraException {
        // Keep 1x as a safe fallback when a platform does not report zoom bounds.
      }

      final restoredZoom = _cameraZoomLevel
          .clamp(minZoom, maxZoom)
          .toDouble();

      try {
        await controller.setZoomLevel(restoredZoom);
      } on CameraException {
        // Some camera implementations expose zoom bounds but reject manual zoom.
      }

      _minCameraZoom = minZoom;
      _maxCameraZoom = maxZoom;
      _cameraZoomLevel = restoredZoom;

      // Keep focus and exposure adaptive so printed text remains readable when
      // lighting and camera distance are less than ideal. Unsupported camera
      // implementations simply keep their platform defaults.
      try {
        await controller.setFocusMode(FocusMode.auto);
      } on CameraException {
        // Auto focus is not available on every camera implementation.
      }

      try {
        await controller.setExposureMode(ExposureMode.auto);
      } on CameraException {
        // Auto exposure is not available on every camera implementation.
      }

      await _setCenterFocusAndExposure(controller);

      if (_flashEnabled) {
        try {
          await controller.setFlashMode(FlashMode.auto);
        } on CameraException {
          _flashEnabled = false;
          await controller.setFlashMode(FlashMode.off);
        }
      }

      if (!mounted) return;

      setState(() {
        _isInitializingCamera = false;
      });
    } on CameraException catch (error) {
      if (!mounted) return;

      setState(() {
        _cameraError = _cameraErrorMessage(error);
        _isInitializingCamera = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _cameraError = 'Camera could not start. $error';
        _isInitializingCamera = false;
      });
    }
  }

  CameraDescription _preferredBackCamera(
    List<CameraDescription> backCameras,
    List<CameraDescription> allCameras,
  ) {
    if (backCameras.isEmpty) return allCameras.first;

    for (final camera in backCameras) {
      if (camera.lensType == CameraLensType.wide) {
        return camera;
      }
    }

    for (final camera in backCameras) {
      if (camera.lensType == CameraLensType.unknown) {
        return camera;
      }
    }

    return backCameras.first;
  }

  Future<void> _setCenterFocusAndExposure(CameraController controller) async {
    const center = Offset(0.5, 0.5);

    if (controller.value.focusPointSupported) {
      try {
        await controller.setFocusPoint(center);
      } on CameraException {
        // Point focus is best-effort; keep the platform auto-focus fallback.
      }
    }

    if (controller.value.exposurePointSupported) {
      try {
        await controller.setExposurePoint(center);
      } on CameraException {
        // Point exposure is best-effort; keep the platform auto-exposure fallback.
      }
    }
  }

  void _handleCameraScaleStart(ScaleStartDetails details) {
    // A second finger can join after Flutter has already started the scale
    // gesture, so always capture the current zoom as the pinch baseline.
    _cameraZoomStartLevel = _cameraZoomLevel;
  }

  void _handleCameraScaleUpdate(ScaleUpdateDetails details) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final nextZoom = (_cameraZoomStartLevel * details.scale)
        .clamp(_minCameraZoom, _maxCameraZoom)
        .toDouble();

    if ((nextZoom - _cameraZoomLevel).abs() < 0.01) return;

    _cameraZoomLevel = nextZoom;
    unawaited(_applyCameraZoom(controller, nextZoom));
  }

  Future<void> _applyCameraZoom(
    CameraController controller,
    double zoomLevel,
  ) async {
    if (_cameraController != controller || !controller.value.isInitialized) {
      return;
    }

    try {
      await controller.setZoomLevel(zoomLevel);
    } on CameraException {
      // Ignore a stale zoom update if the camera is being closed or recreated.
    }
  }

  Future<void> _focusCameraAtTap(TapUpDetails details) async {
    final controller = _cameraController;
    final previewContext = _cameraPreviewKey.currentContext;

    if (controller == null ||
        !controller.value.isInitialized ||
        previewContext == null ||
        _isTakingPhoto) {
      return;
    }

    final renderObject = previewContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final size = renderObject.size;
    if (size.width <= 0 || size.height <= 0) return;

    final localPosition = details.localPosition;
    final normalizedPoint = Offset(
      (localPosition.dx / size.width).clamp(0.0, 1.0).toDouble(),
      (localPosition.dy / size.height).clamp(0.0, 1.0).toDouble(),
    );

    _cameraFocusIndicatorTimer?.cancel();

    if (mounted) {
      setState(() {
        _cameraFocusIndicatorPosition = Offset(
          localPosition.dx.clamp(24.0, size.width - 24.0).toDouble(),
          localPosition.dy.clamp(24.0, size.height - 24.0).toDouble(),
        );
        _showCameraFocusIndicator = true;
      });
    }

    _cameraFocusIndicatorTimer = Timer(
      const Duration(milliseconds: 650),
      () {
        if (!mounted) return;
        setState(() {
          _showCameraFocusIndicator = false;
        });
      },
    );

    if (controller.value.focusPointSupported) {
      try {
        await controller.setFocusPoint(normalizedPoint);
      } on CameraException {
        // Tap focus is best-effort; continuous auto focus remains enabled.
      }
    }

    if (controller.value.exposurePointSupported) {
      try {
        await controller.setExposurePoint(normalizedPoint);
      } on CameraException {
        // Match iPhone-style tap metering when the platform supports it.
      }
    }
  }

  Widget _cameraFocusIndicator() {
    final position = _cameraFocusIndicatorPosition;
    if (position == null) return const SizedBox.shrink();

    return Positioned(
      left: position.dx - 21,
      top: position.dy - 21,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _showCameraFocusIndicator ? 1 : 0,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFFD60A),
                width: 1.7,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<String> _normalizeCameraCaptureForOcr(String sourcePath) async {
    if (!Platform.isIOS) return sourcePath;

    ui.Codec? codec;
    ui.Image? image;

    try {
      final bytes = await File(sourcePath).readAsBytes();
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 4096,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final pngData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (pngData == null) return sourcePath;

      final normalizedPath = '$sourcePath.gakuji_ocr.png';
      final normalizedFile = File(normalizedPath);
      await normalizedFile.writeAsBytes(
        pngData.buffer.asUint8List(
          pngData.offsetInBytes,
          pngData.lengthInBytes,
        ),
        flush: true,
      );

      // The normalized PNG has the same upright pixels Flutter displays, with
      // no EXIF rotation dependency. ML Kit geometry, Paddle crops, and the
      // on-screen overlay therefore all use one coordinate system. The original
      // capture stays alive until the UI has switched to this normalized file so
      // the shutter can lock the photo on screen immediately.
      return normalizedPath;
    } catch (_) {
      // Keep the original camera capture as a safe fallback.
      return sourcePath;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  Future<void> _disposeCameraController() async {
    final controller = _cameraController;
    _cameraController = null;

    if (controller != null) {
      await controller.dispose();
    }
  }

  String _cameraErrorMessage(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
        return 'Camera access was denied. Allow camera access to scan Japanese text.';
      case 'CameraAccessDeniedWithoutPrompt':
        return 'Camera access is disabled. Enable it for Gakuji in system settings.';
      case 'CameraAccessRestricted':
        return 'Camera access is restricted on this device.';
      default:
        return 'Camera could not start. ${error.description ?? error.code}';
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) return;

    final nextEnabled = !_flashEnabled;

    try {
      await controller.setFlashMode(
        nextEnabled ? FlashMode.auto : FlashMode.off,
      );

      if (!mounted) return;

      setState(() {
        _flashEnabled = nextEnabled;
      });
    } on CameraException {
      if (!mounted) return;

      setState(() {
        _flashEnabled = false;
      });
    }
  }

  Future<void> _takePhoto() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _isTakingPhoto ||
        _isPickingImage) {
      return;
    }

    _transientMessageTimer?.cancel();
    _transientMessageTimer = null;
    _cameraFocusIndicatorTimer?.cancel();
    _cameraFocusIndicatorTimer = null;

    setState(() {
      _isTakingPhoto = true;
      _showCameraFocusIndicator = false;
      _transientMessage = null;
      _scanError = null;
    });

    try {
      // Focus/exposure are already kept in auto mode while the preview is live.
      // Go straight to the platform shutter instead of re-metering and waiting
      // again here.
      final captured = await controller.takePicture();

      if (!mounted) {
        unawaited(_deleteFile(captured.path));
        return;
      }

      // Lock the captured frame on screen immediately. iOS normalization and OCR
      // continue only after the user can already see the photo they just took.
      _photoTransformationController.value = Matrix4.identity();
      setState(() {
        _capturedImagePath = captured.path;
        _deleteCapturedImageWhenDone = true;
        _savedScanId = null;
        _recognitionResult = null;
        _isTakingPhoto = false;
        _isRecognizingPhoto = true;
        _scanProgress = 0.0;
        _scanError = null;
      });

      await _disposeCameraController();

      final recognitionPath =
          await _normalizeCameraCaptureForOcr(captured.path);

      if (!mounted || _capturedImagePath != captured.path) {
        if (recognitionPath != captured.path) {
          unawaited(_deleteFile(recognitionPath));
        }
        return;
      }

      if (recognitionPath != captured.path) {
        setState(() {
          _capturedImagePath = recognitionPath;
        });
        unawaited(_deleteFile(captured.path));
      }

      await _beginRecognitionForImage(
        imagePath: recognitionPath,
        deleteWhenDone: true,
      );
    } on CameraException catch (error) {
      if (!mounted) return;

      setState(() {
        _isTakingPhoto = false;
        _isRecognizingPhoto = false;
        _scanProgress = 0.0;
        _scanError =
            'Photo could not be captured. ${error.description ?? error.code}';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isTakingPhoto = false;
        _isRecognizingPhoto = false;
        _scanProgress = 0.0;
        _scanError = 'Japanese text could not be read from this photo.';
      });
    }
  }

  Future<void> _pickPhotoFromLibrary() async {
    if (_isPickingImage ||
        _isTakingPhoto ||
        _isRecognizingPhoto ||
        _isAnalyzingSelection ||
        _isOpeningSavedScans) {
      return;
    }

    setState(() {
      _isPickingImage = true;
      _scanError = null;
    });

    await _disposeCameraController();

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (!mounted) return;

      if (picked == null) {
        setState(() {
          _isPickingImage = false;
        });
        await _initializeCamera();
        return;
      }

      final temporaryPath = await _createTemporaryPhotoCopy(picked.path);

      if (!mounted) {
        unawaited(_deleteFile(temporaryPath));
        return;
      }

      setState(() {
        _isPickingImage = false;
      });

      await _beginRecognitionForImage(
        imagePath: temporaryPath,
        deleteWhenDone: true,
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isPickingImage = false;
        _scanError = 'Photo could not be opened.';
      });

      await _initializeCamera();
    }
  }

  Future<String> _createTemporaryPhotoCopy(String sourcePath) async {
    final temporaryDirectory = await getTemporaryDirectory();
    final sourceExtension = path_util.extension(sourcePath);
    final extension = sourceExtension.isEmpty ? '.jpg' : sourceExtension;
    final temporaryPath = path_util.join(
      temporaryDirectory.path,
      'gakuji_scan_${DateTime.now().microsecondsSinceEpoch}$extension',
    );

    await File(sourcePath).copy(temporaryPath);
    return temporaryPath;
  }

  Future<void> _beginRecognitionForImage({
    required String imagePath,
    required bool deleteWhenDone,
  }) async {
    if (!mounted) return;

    _photoTransformationController.value = Matrix4.identity();

    setState(() {
      _capturedImagePath = imagePath;
      _deleteCapturedImageWhenDone = deleteWhenDone;
      _savedScanId = null;
      _recognitionResult = null;
      _isTakingPhoto = false;
      _isRecognizingPhoto = true;
      _scanProgress = 0.0;
      _scanError = null;
    });

    await _disposeCameraController();

    try {
      final recognition = await _recognitionService.recognizePhoto(
        imagePath,
        onProgress: (progress) {
          if (!mounted || _capturedImagePath != imagePath) return;

          final nextProgress = progress.clamp(0.0, 1.0).toDouble();
          if ((nextProgress - _scanProgress).abs() < 0.004) return;

          setState(() {
            _scanProgress = nextProgress;
          });
        },
      );

      if (!mounted || _capturedImagePath != imagePath) return;

      setState(() {
        _recognitionResult = recognition;
        _scanProgress = 1.0;
        _isRecognizingPhoto = false;
      });
    } catch (_) {
      if (!mounted || _capturedImagePath != imagePath) return;

      setState(() {
        _isRecognizingPhoto = false;
        _scanProgress = 0.0;
        _scanError = 'Japanese text could not be read from this photo.';
      });
    }
  }

  Future<void> _retakePhoto() async {
    if (_isRecognizingPhoto || _isAnalyzingSelection || _isSavingScan) return;

    _photoTransformationController.value = Matrix4.identity();
    _transientMessageTimer?.cancel();
    _transientMessageTimer = null;

    final oldPath = _capturedImagePath;
    final deleteOldPath = _deleteCapturedImageWhenDone;

    setState(() {
      _transientMessage = null;
      _capturedImagePath = null;
      _deleteCapturedImageWhenDone = false;
      _savedScanId = null;
      _recognitionResult = null;
      _scanProgress = 0.0;
      _scanError = null;
    });

    if (oldPath != null && deleteOldPath) {
      unawaited(_deleteFile(oldPath));
    }

    await _initializeCamera();
  }

  Future<void> _openSavedScans() async {
    if (_isOpeningSavedScans ||
        _isTakingPhoto ||
        _isPickingImage ||
        _isRecognizingPhoto ||
        _isAnalyzingSelection ||
        _isSavingScan) {
      return;
    }

    setState(() {
      _isOpeningSavedScans = true;
    });

    await _disposeCameraController();

    final selected = await Navigator.of(context).push<CameraSavedScan>(
      GakujiPageRoute<CameraSavedScan>(
        builder: (context) => const CameraSavedScansPage(),
      ),
    );

    if (!mounted) return;

    setState(() {
      _isOpeningSavedScans = false;
    });

    if (selected != null) {
      await _loadSavedScan(selected);
      return;
    }

    if (_capturedImagePath == null) {
      await _initializeCamera();
    }
  }

  Future<void> _loadSavedScan(CameraSavedScan scan) async {
    final oldPath = _capturedImagePath;
    final deleteOldPath = _deleteCapturedImageWhenDone;

    _photoTransformationController.value = Matrix4.identity();

    setState(() {
      _capturedImagePath = scan.imagePath;
      _deleteCapturedImageWhenDone = false;
      _savedScanId = scan.id;
      _recognitionResult = scan.recognition;
      _isTakingPhoto = false;
      _isRecognizingPhoto = false;
      _scanProgress = 1.0;
      _scanError = null;
    });

    await _disposeCameraController();

    if (oldPath != null && deleteOldPath && oldPath != scan.imagePath) {
      unawaited(_deleteFile(oldPath));
    }
  }

  Future<void> _toggleSaveCurrentPhoto() async {
    if (_isSavingScan ||
        _isRecognizingPhoto ||
        _isAnalyzingSelection ||
        _capturedImagePath == null ||
        _recognitionResult == null) {
      return;
    }

    final currentPath = _capturedImagePath!;
    final recognition = _recognitionResult!;
    final savedScanId = _savedScanId;

    setState(() {
      _isSavingScan = true;
    });

    if (savedScanId == null) {
      try {
        final saved = await CameraSavedScanStore.saveScan(
          sourceImagePath: currentPath,
          recognition: recognition,
        );

        if (!mounted || _capturedImagePath != currentPath) return;

        setState(() {
          _savedScanId = saved.id;
          _isSavingScan = false;
        });
        _showMessage('Scan saved');
      } catch (_) {
        if (!mounted) return;

        setState(() {
          _isSavingScan = false;
        });
        _showMessage('Could not save scan');
      }
      return;
    }

    String? temporaryReplacementPath;

    try {
      if (!_deleteCapturedImageWhenDone) {
        temporaryReplacementPath = await _createTemporaryPhotoCopy(currentPath);
      }

      await CameraSavedScanStore.deleteScan(savedScanId);

      if (!mounted || _capturedImagePath != currentPath) {
        if (temporaryReplacementPath != null) {
          unawaited(_deleteFile(temporaryReplacementPath));
        }
        return;
      }

      setState(() {
        if (temporaryReplacementPath != null) {
          _capturedImagePath = temporaryReplacementPath;
          _deleteCapturedImageWhenDone = true;
        }
        _savedScanId = null;
        _isSavingScan = false;
      });
      _showMessage('Removed from Saved Scans');
    } catch (_) {
      if (temporaryReplacementPath != null) {
        unawaited(_deleteFile(temporaryReplacementPath));
      }

      if (!mounted) return;

      setState(() {
        _isSavingScan = false;
      });
      _showMessage('Could not remove saved scan');
    }
  }

  Future<void> _deleteCapturedPhoto() async {
    final path = _capturedImagePath;
    if (path == null || !_deleteCapturedImageWhenDone) return;
    await _deleteFile(path);
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Captures are temporary cache files. Failure to remove one should not
      // interrupt camera navigation.
    }
  }

  Future<void> _openUnit(CameraTextUnit unit) async {
    if (_isAnalyzingSelection || _isRecognizingPhoto) return;

    setState(() {
      _isAnalyzingSelection = true;
    });

    try {
      final analysis = await CameraTextAnalysisService.analyze(unit.text);

      if (!mounted) return;

      if (analysis.isIsolated) {
        await _showDictionaryMatches(
          sourceText: analysis.text,
          matches: analysis.isolatedMatches,
        );
        return;
      }

      final example = analysis.sentenceExample;

      if (example != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CameraSentenceDetailPage(
              example: example,
              senseLabel: '',
              onTokenTap: _openSentenceToken,
            ),
          ),
        );
        return;
      }

      _showMessage('No dictionary terms were found in this text yet.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('This text could not be matched to the dictionary.');
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzingSelection = false;
        });
      }
    }
  }

  Future<void> _openSentenceToken(
    BuildContext sentenceContext,
    DictionaryExampleToken token,
  ) async {
    final termId = token.termId?.trim() ?? '';

    if (termId.isEmpty) return;

    final term = await DictionaryService.getTermByIdAsync(termId);

    if (!sentenceContext.mounted) return;

    await Navigator.of(sentenceContext).push(
      MaterialPageRoute(
        builder: (context) => DictionaryDetailPage(word: term),
      ),
    );
  }

  Future<void> _showDictionaryMatches({
    required String sourceText,
    required List<Term> matches,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _DictionaryMatchSheet(
          sourceText: sourceText,
          matches: matches,
          onTermTap: (term) {
            Navigator.of(sheetContext).pop();
            unawaited(_openDictionaryDetail(term));
          },
        );
      },
    );
  }

  Future<void> _openDictionaryDetail(Term term) async {
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DictionaryDetailPage(word: term),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    _transientMessageTimer?.cancel();

    setState(() {
      _transientMessage = message;
    });

    _transientMessageTimer = Timer(
      const Duration(milliseconds: 900),
      () {
        if (!mounted) return;
        setState(() {
          _transientMessage = null;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                _topBar(),
                Expanded(child: _cameraBody()),
                _bottomControls(),
              ],
            ),
          ),
          Positioned(
            top: topInset + 70,
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                reverseDuration: const Duration(milliseconds: 90),
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0, -0.22),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  );

                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: slide,
                      child: child,
                    ),
                  );
                },
                child: _transientMessage == null
                    ? const SizedBox.shrink(
                        key: ValueKey<String>('camera-message-empty'),
                      )
                    : Center(
                        key: ValueKey<String>(_transientMessage!),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 280),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _transientMessage!,
                            textAlign: TextAlign.center,
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    final captured = _capturedImagePath != null;

    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: SizedBox(
        height: 62,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              'Camera',
              textScaler: TextScaler.noScaling,
              style: GakujiText.pageTitle.copyWith(
                color: Colors.white,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _topIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: captured
                  ? _topIconButton(
                      icon: _savedScanId == null
                          ? Icons.bookmark_border_rounded
                          : Icons.bookmark_rounded,
                      onTap: _isRecognizingPhoto || _isSavingScan
                          ? null
                          : _toggleSaveCurrentPhoto,
                      iconColor: _isRecognizingPhoto || _isSavingScan
                          ? Colors.white38
                          : Colors.white,
                    )
                  : _topIconButton(
                      icon: _flashEnabled
                          ? Icons.flash_auto_rounded
                          : Icons.flash_off_rounded,
                      onTap: _toggleFlash,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topIconButton({
    required IconData icon,
    required VoidCallback? onTap,
    Color iconColor = Colors.white,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 54,
        height: 54,
        child: Center(
          child: Icon(
            icon,
            color: iconColor,
            size: 27,
          ),
        ),
      ),
    );
  }

  Widget _cameraBody() {
    final capturedPath = _capturedImagePath;

    if (capturedPath != null) {
      return _capturedPhotoView(capturedPath);
    }

    if (_cameraError != null) {
      return _cameraErrorView();
    }

    final controller = _cameraController;

    if (_isInitializingCamera ||
        controller == null ||
        !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: GestureDetector(
        key: _cameraPreviewKey,
        behavior: HitTestBehavior.opaque,
        onTapUp: _focusCameraAtTap,
        onScaleStart: _handleCameraScaleStart,
        onScaleUpdate: _handleCameraScaleUpdate,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            CameraPreview(controller),
            _cameraFocusIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _cameraErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 46,
            ),
            const SizedBox(height: 18),
            Text(
              _cameraError ?? 'Camera unavailable.',
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: GakujiText.body.copyWith(
                color: Colors.white,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            TextButton(
              onPressed: _initializeCamera,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _capturedPhotoView(String imagePath) {
    final recognition = _recognitionResult;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        if (recognition == null) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _interactivePhotoSurface(
                child: SizedBox.expand(
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              if (_isRecognizingPhoto) _processingOverlay('Scanning...'),
              if (_scanError != null) _scanErrorOverlay(),
            ],
          );
        }

        final fitted = applyBoxFit(
          BoxFit.contain,
          recognition.imageSize,
          availableSize,
        );
        final photoRect = Alignment.center.inscribe(
          fitted.destination,
          Offset.zero & availableSize,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) => _handlePhotoTap(
                details: details,
                recognition: recognition,
                photoRect: photoRect,
              ),
              child: _interactivePhotoSurface(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fromRect(
                      rect: photoRect,
                      child: Image.file(
                        File(imagePath),
                        fit: BoxFit.fill,
                      ),
                    ),
                    for (final entry in recognition.units.asMap().entries)
                      for (final sourceRect in entry.value.boundingBoxes)
                        _unitOverlay(
                          unit: entry.value,
                          sourceRect: sourceRect,
                          sourceSize: recognition.imageSize,
                          photoRect: photoRect,
                          highlightIndex: entry.key,
                        ),
                  ],
                ),
              ),
            ),
            if (recognition.units.isEmpty)
              _processingOverlay('No Japanese text detected'),
            if (_isAnalyzingSelection) _selectionProgressOverlay(),
          ],
        );
      },
    );
  }

  Widget _interactivePhotoSurface({required Widget child}) {
    return InteractiveViewer(
      transformationController: _photoTransformationController,
      minScale: 1.0,
      maxScale: 6.0,
      panEnabled: true,
      scaleEnabled: true,
      clipBehavior: Clip.hardEdge,
      child: child,
    );
  }

  void _handlePhotoTap({
    required TapUpDetails details,
    required CameraRecognitionResult recognition,
    required Rect photoRect,
  }) {
    if (_isAnalyzingSelection || _isRecognizingPhoto) return;

    final scenePoint =
        _photoTransformationController.toScene(details.localPosition);
    final scaleX = photoRect.width / recognition.imageSize.width;
    final scaleY = photoRect.height / recognition.imageSize.height;

    for (final unit in recognition.units.reversed) {
      for (final sourceRect in unit.boundingBoxes.reversed) {
        final overlayRect = Rect.fromLTWH(
          photoRect.left + sourceRect.left * scaleX,
          photoRect.top + sourceRect.top * scaleY,
          sourceRect.width * scaleX,
          sourceRect.height * scaleY,
        );

        if (overlayRect.inflate(2).contains(scenePoint)) {
          unawaited(_openUnit(unit));
          return;
        }
      }
    }
  }

  Widget _unitOverlay({
    required CameraTextUnit unit,
    required Rect sourceRect,
    required Size sourceSize,
    required Rect photoRect,
    required int highlightIndex,
  }) {
    final scaleX = photoRect.width / sourceSize.width;
    final scaleY = photoRect.height / sourceSize.height;
    final rawLeft = photoRect.left + sourceRect.left * scaleX;
    final rawTop = photoRect.top + sourceRect.top * scaleY;
    final rawWidth = sourceRect.width * scaleX;
    final rawHeight = sourceRect.height * scaleY;
    final insetX = (rawWidth * 0.012).clamp(0.4, 1.2).toDouble();
    final insetY = (rawHeight * 0.08).clamp(0.5, 1.8).toDouble();
    final left = rawLeft + insetX;
    final top = rawTop + insetY;
    final insetWidth = rawWidth - insetX * 2;
    final insetHeight = rawHeight - insetY * 2;
    final width = insetWidth > 1 ? insetWidth : rawWidth;
    final height = insetHeight > 1 ? insetHeight : rawHeight;
    final highlightColor = highlightIndex.isEven
        ? GakujiColors.deckBlue
        : const Color(0xFFE0A21C);

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: highlightColor.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }

  Widget _processingOverlay(String message) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.28),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isRecognizingPhoto) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: 190,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: _scanProgress,
                          minHeight: 6,
                          color: GakujiColors.deckBlue,
                          backgroundColor: const Color(0xFF4A4A4A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(_scanProgress * 100).round()}%',
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionProgressOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 18,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 9),
              Text(
                'Looking up text…',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scanErrorOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.38),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              _scanError ?? '',
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomControls() {
    final captured = _capturedImagePath != null;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      color: Colors.black,
      padding: EdgeInsets.fromLTRB(22, 13, 22, 18 + bottomInset),
      child: captured ? _capturedControls() : _captureControls(),
    );
  }

  Widget _captureControls() {
    return SizedBox(
      height: 106,
      child: Column(
        children: [
          const Text(
            'Photograph Japanese text',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _galleryButton(),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _isTakingPhoto || _isPickingImage || _isOpeningSavedScans
                    ? null
                    : _takePhoto,
                child: Container(
                  width: 74,
                  height: 74,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isTakingPhoto ? Colors.white54 : Colors.white,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _savedScansButton(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _galleryButton() {
    final disabled =
        _isPickingImage || _isTakingPhoto || _isOpeningSavedScans;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : _pickPhotoFromLibrary,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Center(
          child: _isPickingImage
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(
                  Icons.photo_library_outlined,
                  color: Colors.white,
                  size: 28,
                ),
        ),
      ),
    );
  }

  Widget _savedScansButton() {
    final disabled = _isOpeningSavedScans ||
        _isTakingPhoto ||
        _isPickingImage ||
        _isRecognizingPhoto;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : _openSavedScans,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Center(
          child: _isOpeningSavedScans
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  Icons.collections_bookmark_outlined,
                  color: disabled ? Colors.white38 : Colors.white,
                  size: 28,
                ),
        ),
      ),
    );
  }

  Widget _capturedControls() {
    final recognition = _recognitionResult;
    final hasUnits = recognition != null && recognition.units.isNotEmpty;
    final label = _isRecognizingPhoto
        ? 'Finding Japanese text…'
        : hasUnits
            ? 'Tap highlighted text to explore it'
            : 'Retake and frame the Japanese text clearly';

    return SizedBox(
      height: 90,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 18),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _retakePhoto,
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Retake',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DictionaryMatchSheet extends StatelessWidget {
  final String sourceText;
  final List<Term> matches;
  final ValueChanged<Term> onTermTap;

  const _DictionaryMatchSheet({
    required this.sourceText,
    required this.matches,
    required this.onTermTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.72;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: GakujiColors.warmBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: GakujiColors.mediumGray.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sourceText,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: GakujiColors.darkGray,
                    fontSize: 25,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    fontFamily: GakujiFonts.japanese,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  matches.length == 1
                      ? 'Dictionary match'
                      : 'Dictionary matches',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: GakujiColors.mediumGray,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: GakujiColors.warmDivider,
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 18),
              itemCount: matches.length,
              separatorBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(left: 22, right: 16),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: GakujiTermRow.dividerColor,
                  ),
                );
              },
              itemBuilder: (context, index) {
                final term = matches[index];

                return GakujiTermRow(
                  term: term,
                  meaningMaxLines: 2,
                  padding: const EdgeInsets.fromLTRB(22, 12, 15, 13),
                  backgroundColor: GakujiColors.warmBackground,
                  onTap: () => onTermTap(term),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
