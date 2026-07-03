import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../data/reading_card_edit_data.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../services/reading_card_edit_storage.dart';
import '../widgets/gakuji_top_bar.dart';

class ReadingCardEditPage extends StatefulWidget {
  final Deck deck;
  final Term term;

  const ReadingCardEditPage({
    super.key,
    required this.deck,
    required this.term,
  });

  @override
  State<ReadingCardEditPage> createState() => _ReadingCardEditPageState();
}

class _ReadingCardEditPageState extends State<ReadingCardEditPage> {
  static const Color accentBlue = Color(0xFF4D7EF7);
  static const Color removeRed = Color(0xFFFF4B4B);
  static const Color cardGray = Color(0xFFEDEDED);
  static const Color shadowGray = Color(0xFFBDBDBD);
  static const Color softTextGray = Color(0xFF8A8A8A);
  static const Color softBlueFill = Color(0xFFF5F7FF);
  static const Color softBlueBorder = Color(0xFFEAF0FF);

  static const int maxGlosses = 5;

  final ImagePicker imagePicker = ImagePicker();
  final Set<String> photoPathsPendingDeletion = <String>{};

  bool isLoadingEditData = true;
  bool isSaving = false;
  bool isPickingPhoto = false;
  bool hasUnsavedChanges = false;
  bool photoEnabled = false;

  String? photoPath;
  String? lastSavedPhotoPath;

  late List<String> selectedGlosses;
  late String cardNote;
  late List<DictionaryExample> selectedExamples;

  @override
  void initState() {
    super.initState();

    selectedGlosses = _defaultGlosses();
    cardNote = widget.term.note ?? '';
    selectedExamples = _defaultExamples();

    loadSavedEditData();
  }

  List<String> _defaultGlosses() {
    final definitions = widget.term.displayDefinitions;

    if (definitions.isEmpty && widget.term.cardMeaning.trim().isNotEmpty) {
      return [widget.term.cardMeaning];
    }

    return definitions.take(3).toList();
  }

  List<DictionaryExample> _defaultExamples() {
    return widget.term.examples.take(2).toList();
  }

  List<String> get allGlosses {
    final rawGlosses = widget.term.rawDefinitions
        .map((gloss) => gloss.trim())
        .where((gloss) => gloss.isNotEmpty)
        .toList();

    if (rawGlosses.isNotEmpty) return rawGlosses;

    final displayGlosses = widget.term.displayDefinitions
        .map((gloss) => gloss.trim())
        .where((gloss) => gloss.isNotEmpty)
        .toList();

    if (displayGlosses.isNotEmpty) return displayGlosses;

    final fallback = widget.term.cardMeaning.trim();

    if (fallback.isEmpty) return const [];

    return [fallback];
  }

  String get termTitle {
    if (widget.term.kanjiBracketText.trim().isNotEmpty) {
      return widget.term.kanjiBracketText.trim();
    }

    if (widget.term.kanji.trim().isNotEmpty) {
      return widget.term.kanji.trim();
    }

    return widget.term.reading.trim();
  }

  ReadingCardEditData get currentEditData {
    return ReadingCardEditData(
      deckId: widget.deck.id,
      termId: widget.term.id,
      sourceId: ReadingCardEditData.sourceIdFor(widget.term),
      selectedGlosses: selectedGlosses,
      selectedExampleKeys: ReadingCardEditData.keysFromExamples(
        selectedExamples,
      ),
      note: cardNote,
      photoEnabled: photoEnabled,
      photoPath: photoPath,
    );
  }

  Future<void> loadSavedEditData() async {
    final hasSavedEdit = await ReadingCardEditStorage.hasSavedEdit(
      deck: widget.deck,
      term: widget.term,
    );

    final savedData = await ReadingCardEditStorage.load(
      deck: widget.deck,
      term: widget.term,
    );

    if (!mounted) return;

    final savedExamples = ReadingCardEditData.examplesFromKeys(
      examples: widget.term.examples,
      selectedExampleKeys: savedData.selectedExampleKeys,
    );

    setState(() {
      selectedGlosses = hasSavedEdit
          ? savedData.selectedGlosses
          : _defaultGlosses();

      cardNote = hasSavedEdit ? savedData.note : widget.term.note ?? '';

      selectedExamples = hasSavedEdit ? savedExamples : _defaultExamples();

      photoEnabled = hasSavedEdit ? savedData.photoEnabled : false;
      photoPath = hasSavedEdit ? savedData.photoPath : null;
      lastSavedPhotoPath = photoPath;

      photoPathsPendingDeletion.clear();

      hasUnsavedChanges = false;
      isLoadingEditData = false;
    });
  }

  void markChanged() {
    if (hasUnsavedChanges) return;

    setState(() {
      hasUnsavedChanges = true;
    });
  }

  Future<void> saveChanges() async {
    if (isSaving) return;

    setState(() {
      isSaving = true;
    });

    try {
      await ReadingCardEditStorage.save(currentEditData);
      await _deletePendingPhotoFiles();

      if (!mounted) return;

      setState(() {
        lastSavedPhotoPath = photoPath;
        isSaving = false;
        hasUnsavedChanges = false;
      });

      _showTemporaryMessage('Card changes saved');
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      _showTemporaryMessage('Could not save card');
    }
  }

  Future<bool> handleBack() async {
    if (isSaving || isPickingPhoto) return false;

    if (!hasUnsavedChanges) return true;

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Discard changes?',
            textScaler: TextScaler.noScaling,
          ),
          content: const Text(
            'Your card edits have not been saved yet.',
            textScaler: TextScaler.noScaling,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                textScaler: TextScaler.noScaling,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Discard',
                textScaler: TextScaler.noScaling,
              ),
            ),
          ],
        );
      },
    );

    if (shouldDiscard ?? false) {
      await _discardUnsavedPhotoChanges();
      return true;
    }

    return false;
  }

  Future<void> handleBackTap() async {
    final canLeave = await handleBack();

    if (!mounted || !canLeave) return;

    Navigator.pop(context);
  }

  void _showTemporaryMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1300),
          backgroundColor: Colors.black.withOpacity(0.86),
          content: Text(
            message,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      );
  }

  void openGlossSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _GlossPickerSheet(
          glosses: allGlosses,
          selectedGlosses: selectedGlosses,
          onChanged: (newGlosses) {
            setState(() {
              selectedGlosses = newGlosses;
            });
            markChanged();
          },
        );
      },
    );
  }

  void openNoteSheet() {
    final controller = TextEditingController(text: cardNote);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: _CardEditBottomSheet(
            title: 'Card Note',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 8,
                  cursorColor: accentBlue,
                  decoration: InputDecoration(
                    hintText: 'Write a note for this card',
                    hintStyle: const TextStyle(
                      color: softTextGray,
                      fontWeight: FontWeight.w400,
                    ),
                    filled: true,
                    fillColor: softBlueFill,
                    contentPadding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: softBlueBorder,
                        width: 1.4,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: accentBlue,
                        width: 1.7,
                      ),
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    color: Colors.black,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 14),
                _SheetSaveButton(
                  label: 'Save Note',
                  onTap: () {
                    setState(() {
                      cardNote = controller.text.trimRight();
                    });
                    markChanged();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void openExamplesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ExamplePickerSheet(
          examples: widget.term.examples,
          selectedExamples: selectedExamples,
          onChanged: (newExamples) {
            setState(() {
              selectedExamples = newExamples;
            });
            markChanged();
          },
        );
      },
    );
  }

  Future<void> togglePhotoSlot() async {
    final oldPhotoPath = photoPath;

    setState(() {
      photoEnabled = !photoEnabled;

      if (!photoEnabled) {
        photoPath = null;
      }
    });

    if (!photoEnabled) {
      await _stagePhotoForDeletion(oldPhotoPath);
    }

    markChanged();

    if (photoEnabled) {
      _showTemporaryMessage('Photo slot added');
    } else {
      _showTemporaryMessage('Photo slot removed');
    }
  }

  Future<void> removePhoto() async {
    final oldPhotoPath = photoPath;

    setState(() {
      photoEnabled = false;
      photoPath = null;
    });

    await _stagePhotoForDeletion(oldPhotoPath);

    markChanged();
    _showTemporaryMessage('Photo removed');
  }

  Future<void> openPhotoPicker() async {
    if (isPickingPhoto) return;

    setState(() {
      isPickingPhoto = true;
    });

    try {
      final pickedImage = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 86,
        maxWidth: 1800,
      );

      if (pickedImage == null) {
        if (mounted) {
          setState(() {
            isPickingPhoto = false;
          });
        }
        return;
      }

      final oldPhotoPath = photoPath;
      final savedPhotoPath = await _savePickedPhotoToAppStorage(pickedImage);

      if (!mounted) {
        await _deletePhotoFileIfSafe(savedPhotoPath);
        return;
      }

      setState(() {
        photoEnabled = true;
        photoPath = savedPhotoPath;
        isPickingPhoto = false;
      });

      await _stagePhotoForDeletion(oldPhotoPath);
      markChanged();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isPickingPhoto = false;
      });

      _showTemporaryMessage('Could not open photos');
    }
  }

  Future<String> _savePickedPhotoToAppStorage(XFile pickedImage) async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final photoDirectory = Directory(
      '${appDirectory.path}/reading_card_photos',
    );

    if (!await photoDirectory.exists()) {
      await photoDirectory.create(recursive: true);
    }

    final extension = _safeExtensionFromPath(pickedImage.path);
    final deckId = _safeFileNamePart(widget.deck.id);
    final termId = _safeFileNamePart(widget.term.id);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final fileName = '${deckId}_${termId}_$timestamp.$extension';
    final savedFile = File('${photoDirectory.path}/$fileName');

    final copiedFile = await File(pickedImage.path).copy(savedFile.path);

    return copiedFile.path;
  }

  Future<void> _stagePhotoForDeletion(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    if (path == photoPath) return;

    if (path == lastSavedPhotoPath) {
      photoPathsPendingDeletion.add(path);
      return;
    }

    await _deletePhotoFileIfSafe(path);
  }

  Future<void> _deletePendingPhotoFiles() async {
    final currentPath = photoPath;
    final pathsToDelete = List<String>.from(photoPathsPendingDeletion);

    photoPathsPendingDeletion.clear();

    for (final path in pathsToDelete) {
      if (path == currentPath) continue;

      await _deletePhotoFileIfSafe(path);
    }
  }

  Future<void> _discardUnsavedPhotoChanges() async {
    final currentPath = photoPath;

    if (currentPath != null && currentPath != lastSavedPhotoPath) {
      await _deletePhotoFileIfSafe(currentPath);
    }

    photoPathsPendingDeletion.clear();
  }

  Future<void> _deletePhotoFileIfSafe(String path) async {
    if (path.trim().isEmpty) return;

    final isSafe = await _isReadingCardPhotoPath(path);

    if (!isSafe) return;

    final file = File(path);

    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<bool> _isReadingCardPhotoPath(String path) async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final photoDirectory = Directory(
      '${appDirectory.path}/reading_card_photos',
    );

    final normalizedPhotoDirectory = photoDirectory.path;
    final normalizedPath = File(path).path;

    return normalizedPath.startsWith(normalizedPhotoDirectory);
  }

  String _safeExtensionFromPath(String path) {
    final name = path.split('/').last;
    final dotIndex = name.lastIndexOf('.');

    if (dotIndex == -1 || dotIndex == name.length - 1) {
      return 'jpg';
    }

    final extension = name.substring(dotIndex + 1).toLowerCase();

    if (extension.length > 5 || extension.contains(RegExp(r'[^a-z0-9]'))) {
      return 'jpg';
    }

    return extension;
  }

  String _safeFileNamePart(String value) {
    final trimmedValue = value.trim();

    if (trimmedValue.isEmpty) return 'item';

    return trimmedValue.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  bool get hasPhoto {
    return photoPath != null && photoPath!.trim().isNotEmpty;
  }

  bool get photoFileExists {
    if (!hasPhoto) return false;

    return File(photoPath!).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: handleBack,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              GakujiTopBar(
                leftIcon: Icons.arrow_back_ios_new,
                onLeftTap: handleBackTap,
                title: '',
                rightWidget: _topRightAction(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Column(
                  children: [
                    Text(
                      termTitle,
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 31,
                        height: 1,
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Card Edit',
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1,
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: isLoadingEditData
                      ? const CircularProgressIndicator(
                          color: accentBlue,
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 30, 24, 46),
                          child: _cardPreview(),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topRightAction() {
    return TextButton(
      onPressed: isSaving || isPickingPhoto
          ? null
          : hasUnsavedChanges
              ? saveChanges
              : handleBackTap,
      style: TextButton.styleFrom(
        foregroundColor: hasUnsavedChanges ? accentBlue : softTextGray,
        disabledForegroundColor: softTextGray,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(76, GakujiTopBar.buttonSize),
      ),
      child: Text(
        isSaving
            ? 'Saving'
            : isPickingPhoto
                ? 'Loading'
                : hasUnsavedChanges
                    ? 'Save'
                    : 'Cancel',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 16,
          height: 1,
          fontWeight: hasUnsavedChanges ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
    );
  }

  Widget _cardPreview() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 430),
      decoration: BoxDecoration(
        color: cardGray,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: shadowGray,
            blurRadius: 0,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 25, 20, 29),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cardSlot(
              title: 'Glosses',
              minHeight: 146,
              label: _glossPreviewText(),
              onTap: openGlossSheet,
            ),
            const SizedBox(height: 14),
            _cardSlot(
              title: 'Note',
              minHeight: 68,
              label: cardNote.trim().isEmpty ? 'Tap to add a note' : cardNote,
              onTap: openNoteSheet,
            ),
            const SizedBox(height: 14),
            _cardSlot(
              title: 'Examples',
              minHeight: 78,
              label: _examplesPreviewText(),
              onTap: openExamplesSheet,
            ),
            if (photoEnabled) ...[
              const SizedBox(height: 25),
              _photoSlot(),
            ] else ...[
              const SizedBox(height: 18),
              _addPhotoButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardSlot({
    required String title,
    required double minHeight,
    required String label,
    required VoidCallback onTap,
  }) {
    final isPlaceholder = label.startsWith('Tap to');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(
              color: accentBlue,
              width: 2.4,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1,
                  color: accentBlue,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: title == 'Glosses' ? 5 : title == 'Examples' ? 3 : 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: title == 'Glosses' ? 18 : 17,
                  height: 1.17,
                  color: isPlaceholder ? softTextGray : Colors.black,
                  fontWeight: isPlaceholder ? FontWeight.w600 : FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoSlot() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: openPhotoPicker,
        onLongPress: () {
          togglePhotoSlot();
        },
        child: Container(
          width: 230,
          height: 230,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(
              color: accentBlue,
              width: 2.4,
            ),
          ),
          child: isPickingPhoto
              ? const Center(
                  child: CircularProgressIndicator(
                    color: accentBlue,
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (photoFileExists)
                      Image.file(
                        File(photoPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _photoPlaceholder(
                            'Photo unavailable\nTap to choose another',
                          );
                        },
                      )
                    else
                      _photoPlaceholder(
                        hasPhoto
                            ? 'Photo unavailable\nTap to choose another'
                            : 'Tap to add photo',
                      ),
                    if (hasPhoto)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: GestureDetector(
                          onTap: removePhoto,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Remove',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1,
                                color: removeRed,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (hasPhoto)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Change',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1,
                              color: accentBlue,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _photoPlaceholder(String label) {
    return Center(
      child: Text(
        label,
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontSize: 16.5,
          height: 1.2,
          color: Colors.black,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _addPhotoButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: openPhotoPicker,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0xFFD8D8D8),
            width: 1.3,
          ),
        ),
        child: Text(
          isPickingPhoto ? 'Loading photo' : 'Add photo',
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            fontSize: 14.5,
            height: 1,
            color: accentBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String _glossPreviewText() {
    if (selectedGlosses.isEmpty) {
      return 'Tap to choose glosses';
    }

    return selectedGlosses
        .asMap()
        .entries
        .map((entry) {
          final label = String.fromCharCode(65 + entry.key);
          return '$label. ${entry.value}';
        })
        .join('\n');
  }

  String _examplesPreviewText() {
    if (selectedExamples.isEmpty) {
      return 'Tap to choose examples';
    }

    return selectedExamples.map((example) => example.japanese).join('\n');
  }
}

class _CardEditBottomSheet extends StatelessWidget {
  final String title;
  final Widget child;

  const _CardEditBottomSheet({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.74,
        ),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(22),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                margin: const EdgeInsets.only(top: 9, bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFD8D8D8),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                fontSize: 18,
                height: 1,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

class _GlossPickerSheet extends StatefulWidget {
  final List<String> glosses;
  final List<String> selectedGlosses;
  final ValueChanged<List<String>> onChanged;

  const _GlossPickerSheet({
    required this.glosses,
    required this.selectedGlosses,
    required this.onChanged,
  });

  @override
  State<_GlossPickerSheet> createState() => _GlossPickerSheetState();
}

class _GlossPickerSheetState extends State<_GlossPickerSheet> {
  static const Color accentBlue = Color(0xFF4D7EF7);
  static const Color dividerGray = Color(0xFFE1E1E1);
  static const int maxGlosses = 5;

  late List<String> workingSelection;

  @override
  void initState() {
    super.initState();

    workingSelection = List<String>.from(widget.selectedGlosses);
  }

  void toggleGloss(String gloss) {
    setState(() {
      if (workingSelection.contains(gloss)) {
        workingSelection.remove(gloss);
      } else {
        if (workingSelection.length >= maxGlosses) return;

        workingSelection.add(gloss);
      }
    });
  }

  void moveGloss(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }

      final gloss = workingSelection.removeAt(oldIndex);
      workingSelection.insert(newIndex, gloss);
    });
  }

  void saveAndClose() {
    widget.onChanged(List<String>.from(workingSelection));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _CardEditBottomSheet(
      title: 'Choose Glosses',
      child: Column(
        children: [
          Text(
            '${workingSelection.length}/$maxGlosses selected • drag selected glosses to reorder',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.2,
              color: Color(0xFF8A8A8A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (workingSelection.isNotEmpty) ...[
            SizedBox(
              height: 122,
              child: ReorderableListView.builder(
                padding: EdgeInsets.zero,
                itemCount: workingSelection.length,
                onReorder: moveGloss,
                buildDefaultDragHandles: true,
                itemBuilder: (context, index) {
                  final gloss = workingSelection[index];

                  return ListTile(
                    key: ValueKey('selected_$gloss'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 13,
                      backgroundColor: accentBlue,
                      child: Text(
                        String.fromCharCode(65 + index),
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    title: Text(
                      gloss,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, color: dividerGray),
          ],
          Expanded(
            child: widget.glosses.isEmpty
                ? const Center(
                    child: Text(
                      'No glosses available',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: widget.glosses.length,
                    separatorBuilder: (context, index) {
                      return const Divider(height: 1, color: dividerGray);
                    },
                    itemBuilder: (context, index) {
                      final gloss = widget.glosses[index];
                      final isSelected = workingSelection.contains(gloss);
                      final label =
                          index < 26 ? String.fromCharCode(65 + index) : '•';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => toggleGloss(gloss),
                        leading: SizedBox(
                          width: 32,
                          child: Center(
                            child: Text(
                              label,
                              textScaler: TextScaler.noScaling,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1,
                                color: Color(0xFF8A8A8A),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          gloss,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontSize: 15.5,
                            height: 1.15,
                            color: Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color:
                              isSelected ? accentBlue : const Color(0xFF8A8A8A),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          _SheetSaveButton(
            label: 'Save Glosses',
            onTap: saveAndClose,
          ),
        ],
      ),
    );
  }
}

class _ExamplePickerSheet extends StatefulWidget {
  final List<DictionaryExample> examples;
  final List<DictionaryExample> selectedExamples;
  final ValueChanged<List<DictionaryExample>> onChanged;

  const _ExamplePickerSheet({
    required this.examples,
    required this.selectedExamples,
    required this.onChanged,
  });

  @override
  State<_ExamplePickerSheet> createState() => _ExamplePickerSheetState();
}

class _ExamplePickerSheetState extends State<_ExamplePickerSheet> {
  static const Color accentBlue = Color(0xFF4D7EF7);
  static const Color dividerGray = Color(0xFFE1E1E1);

  late List<DictionaryExample> workingSelection;

  @override
  void initState() {
    super.initState();

    workingSelection = List<DictionaryExample>.from(widget.selectedExamples);
  }

  bool exampleIsSelected(DictionaryExample example) {
    return workingSelection.any((selected) {
      return selected.japanese == example.japanese &&
          selected.english == example.english;
    });
  }

  void toggleExample(DictionaryExample example) {
    setState(() {
      if (exampleIsSelected(example)) {
        workingSelection.removeWhere((selected) {
          return selected.japanese == example.japanese &&
              selected.english == example.english;
        });
      } else {
        workingSelection.add(example);
      }
    });
  }

  void saveAndClose() {
    widget.onChanged(List<DictionaryExample>.from(workingSelection));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _CardEditBottomSheet(
      title: 'Choose Examples',
      child: Column(
        children: [
          Text(
            '${workingSelection.length} selected',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.2,
              color: Color(0xFF8A8A8A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.examples.isEmpty
                ? const Center(
                    child: Text(
                      'No examples yet',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: widget.examples.length,
                    separatorBuilder: (context, index) {
                      return const Divider(height: 1, color: dividerGray);
                    },
                    itemBuilder: (context, index) {
                      final example = widget.examples[index];
                      final isSelected = exampleIsSelected(example);

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => toggleExample(example),
                        title: Text(
                          example.japanese,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontSize: 15.5,
                            height: 1.18,
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            example.english,
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.15,
                              color: Color(0xFF8A8A8A),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        trailing: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color:
                              isSelected ? accentBlue : const Color(0xFF8A8A8A),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          _SheetSaveButton(
            label: 'Save Examples',
            onTap: saveAndClose,
          ),
        ],
      ),
    );
  }
}

class _SheetSaveButton extends StatelessWidget {
  static const Color accentBlue = Color(0xFF4D7EF7);

  final String label;
  final VoidCallback onTap;

  const _SheetSaveButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accentBlue,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              fontSize: 15.5,
              height: 1,
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}