import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';

import 'package:gakuji/features/camera/services/camera_text_recognition_service.dart';

class CameraSavedScan {
  final String id;
  final String imagePath;
  final DateTime savedAt;
  final CameraRecognitionResult recognition;

  const CameraSavedScan({
    required this.id,
    required this.imagePath,
    required this.savedAt,
    required this.recognition,
  });
}

class CameraSavedScanStore {
  static const String _folderName = 'gakuji_saved_scans';
  static const String _imagesFolderName = 'images';
  static const String _indexFileName = 'saved_scans.json';

  static Future<List<CameraSavedScan>> loadScans() async {
    final root = await _rootDirectory();
    final indexFile = File(path_util.join(root.path, _indexFileName));

    if (!await indexFile.exists()) {
      return const [];
    }

    try {
      final decoded = jsonDecode(await indexFile.readAsString());
      if (decoded is! List) return const [];

      final scans = <CameraSavedScan>[];
      var removedMissingFile = false;

      for (final entry in decoded) {
        if (entry is! Map) continue;

        final map = Map<String, dynamic>.from(entry);
        final scan = await _scanFromJson(root, map);

        if (scan == null) {
          removedMissingFile = true;
          continue;
        }

        scans.add(scan);
      }

      scans.sort((first, second) => second.savedAt.compareTo(first.savedAt));

      if (removedMissingFile) {
        await _writeIndex(root, scans);
      }

      return scans;
    } catch (_) {
      return const [];
    }
  }

  static Future<CameraSavedScan> saveScan({
    required String sourceImagePath,
    required CameraRecognitionResult recognition,
  }) async {
    final root = await _rootDirectory();
    final imagesDirectory = Directory(
      path_util.join(root.path, _imagesFolderName),
    );
    await imagesDirectory.create(recursive: true);

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final sourceExtension = path_util.extension(sourceImagePath);
    final extension = sourceExtension.isEmpty ? '.jpg' : sourceExtension;
    final fileName = '$id$extension';
    final destinationPath = path_util.join(imagesDirectory.path, fileName);

    await File(sourceImagePath).copy(destinationPath);

    final scan = CameraSavedScan(
      id: id,
      imagePath: destinationPath,
      savedAt: DateTime.now(),
      recognition: recognition,
    );

    final scans = await loadScans();
    await _writeIndex(root, <CameraSavedScan>[scan, ...scans]);

    return scan;
  }

  static Future<void> deleteScan(String id) async {
    final root = await _rootDirectory();
    final scans = await loadScans();
    CameraSavedScan? removed;

    final remaining = <CameraSavedScan>[];
    for (final scan in scans) {
      if (scan.id == id) {
        removed = scan;
      } else {
        remaining.add(scan);
      }
    }

    if (removed != null) {
      try {
        final imageFile = File(removed.imagePath);
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      } catch (_) {
        // Keep metadata cleanup independent from file cleanup failures.
      }
    }

    await _writeIndex(root, remaining);
  }

  static Future<Directory> _rootDirectory() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final root = Directory(
      path_util.join(documentsDirectory.path, _folderName),
    );
    await root.create(recursive: true);
    return root;
  }

  static Future<CameraSavedScan?> _scanFromJson(
    Directory root,
    Map<String, dynamic> map,
  ) async {
    final id = map['id']?.toString() ?? '';
    final fileName = map['imageFileName']?.toString() ?? '';
    final savedAtRaw = map['savedAt']?.toString() ?? '';
    final recognitionRaw = map['recognition'];

    if (id.isEmpty ||
        fileName.isEmpty ||
        savedAtRaw.isEmpty ||
        recognitionRaw is! Map) {
      return null;
    }

    final imagePath = path_util.join(
      root.path,
      _imagesFolderName,
      fileName,
    );

    if (!await File(imagePath).exists()) {
      return null;
    }

    final savedAt = DateTime.tryParse(savedAtRaw);
    if (savedAt == null) return null;

    final recognition = _recognitionFromJson(
      Map<String, dynamic>.from(recognitionRaw),
    );
    if (recognition == null) return null;

    return CameraSavedScan(
      id: id,
      imagePath: imagePath,
      savedAt: savedAt,
      recognition: recognition,
    );
  }

  static CameraRecognitionResult? _recognitionFromJson(
    Map<String, dynamic> map,
  ) {
    final width = _doubleFromJson(map['width']);
    final height = _doubleFromJson(map['height']);
    final unitsRaw = map['units'];

    if (width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        unitsRaw is! List) {
      return null;
    }

    final units = <CameraTextUnit>[];

    for (final unitRaw in unitsRaw) {
      if (unitRaw is! Map) continue;

      final unitMap = Map<String, dynamic>.from(unitRaw);
      final text = unitMap['text']?.toString() ?? '';
      final boxesRaw = unitMap['boxes'];

      if (text.isEmpty || boxesRaw is! List) continue;

      final boxes = <Rect>[];
      for (final boxRaw in boxesRaw) {
        if (boxRaw is! Map) continue;
        final boxMap = Map<String, dynamic>.from(boxRaw);
        final left = _doubleFromJson(boxMap['left']);
        final top = _doubleFromJson(boxMap['top']);
        final right = _doubleFromJson(boxMap['right']);
        final bottom = _doubleFromJson(boxMap['bottom']);

        if (left == null || top == null || right == null || bottom == null) {
          continue;
        }

        boxes.add(Rect.fromLTRB(left, top, right, bottom));
      }

      if (boxes.isEmpty) continue;

      units.add(
        CameraTextUnit(
          text: text,
          boundingBoxes: boxes,
        ),
      );
    }

    return CameraRecognitionResult(
      imageSize: Size(width, height),
      units: List.unmodifiable(units),
    );
  }

  static double? _doubleFromJson(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static Future<void> _writeIndex(
    Directory root,
    List<CameraSavedScan> scans,
  ) async {
    final indexFile = File(path_util.join(root.path, _indexFileName));
    final payload = scans.map(_scanToJson).toList(growable: false);
    await indexFile.writeAsString(
      jsonEncode(payload),
      flush: true,
    );
  }

  static Map<String, dynamic> _scanToJson(CameraSavedScan scan) {
    return <String, dynamic>{
      'id': scan.id,
      'imageFileName': path_util.basename(scan.imagePath),
      'savedAt': scan.savedAt.toIso8601String(),
      'recognition': <String, dynamic>{
        'width': scan.recognition.imageSize.width,
        'height': scan.recognition.imageSize.height,
        'units': scan.recognition.units.map((unit) {
          return <String, dynamic>{
            'text': unit.text,
            'boxes': unit.boundingBoxes.map((box) {
              return <String, dynamic>{
                'left': box.left,
                'top': box.top,
                'right': box.right,
                'bottom': box.bottom,
              };
            }).toList(growable: false),
          };
        }).toList(growable: false),
      },
    };
  }
}
