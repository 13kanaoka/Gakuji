import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/data/decks/reading_card_edit_data.dart';
import 'package:gakuji/data/decks/reading_card_edit_storage.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/term.dart';

class CustomCardEditPage extends StatefulWidget {
  final Deck deck;
  final Term? term;

  const CustomCardEditPage({
    super.key,
    required this.deck,
    this.term,
  });

  @override
  State<CustomCardEditPage> createState() => _CustomCardEditPageState();
}

class _CustomCardEditPageState extends State<CustomCardEditPage> {
  final TextEditingController writingController = TextEditingController();
  final TextEditingController readingController = TextEditingController();
  final TextEditingController meaningController = TextEditingController();
  final TextEditingController partOfSpeechController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final ImagePicker imagePicker = ImagePicker();

  late final String draftPhotoId;
  late final String initialWriting;
  late final String initialReading;
  late final String initialMeaning;
  late final String initialPartOfSpeech;
  late final String initialNote;

  ReadingCardEditData? existingReadingEdit;

  String? photoPath;
  String? initialPhotoPath;

  bool photoEnabled = false;
  bool initialPhotoEnabled = false;
  bool isLoadingPhoto = false;
  bool isPickingPhoto = false;
  bool isSaving = false;

  double photoScale = 1.0;
  double photoOffsetX = 0.0;
  double photoOffsetY = 0.0;
  double initialPhotoScale = 1.0;
  double initialPhotoOffsetX = 0.0;
  double initialPhotoOffsetY = 0.0;

  String? writingError;
  String? meaningError;

  bool get isEditing => widget.term != null;

  bool get photoFileExists {
    final path = photoPath?.trim();
    return photoEnabled &&
        path != null &&
        path.isNotEmpty &&
        File(path).existsSync();
  }

  bool get _photoHasChanges {
    return photoEnabled != initialPhotoEnabled ||
        photoPath != initialPhotoPath ||
        photoScale != initialPhotoScale ||
        photoOffsetX != initialPhotoOffsetX ||
        photoOffsetY != initialPhotoOffsetY;
  }

  bool get hasChanges {
    return writingController.text.trim() != initialWriting ||
        readingController.text.trim() != initialReading ||
        meaningController.text.trim() != initialMeaning ||
        partOfSpeechController.text.trim() != initialPartOfSpeech ||
        noteController.text.trim() != initialNote ||
        _photoHasChanges;
  }

  @override
  void initState() {
    super.initState();

    draftPhotoId =
        'custom_draft_${DateTime.now().microsecondsSinceEpoch.toString()}';

    final term = widget.term;
    if (term != null) {
      writingController.text = term.preferredSpelling.trim().isNotEmpty
          ? term.preferredSpelling.trim()
          : term.kanji.trim();
      readingController.text = term.reading;
      meaningController.text = term.meaning;
      partOfSpeechController.text =
          term.partOfSpeech == 'custom' ? '' : term.partOfSpeech;
      noteController.text = term.note ?? '';
    }

    initialWriting = writingController.text.trim();
    initialReading = readingController.text.trim();
    initialMeaning = meaningController.text.trim();
    initialPartOfSpeech = partOfSpeechController.text.trim();
    initialNote = noteController.text.trim();

    writingController.addListener(_handleFieldChange);
    readingController.addListener(_handleFieldChange);
    meaningController.addListener(_handleFieldChange);
    partOfSpeechController.addListener(_handleFieldChange);
    noteController.addListener(_handleFieldChange);

    if (term != null) {
      isLoadingPhoto = true;
      _loadExistingPhoto();
    }
  }

  @override
  void dispose() {
    writingController.dispose();
    readingController.dispose();
    meaningController.dispose();
    partOfSpeechController.dispose();
    noteController.dispose();
    super.dispose();
  }

  void _handleFieldChange() {
    if (!mounted) return;

    setState(() {
      if (!hasChanges) {
        writingError = null;
        meaningError = null;
        return;
      }

      if (writingController.text.trim().isNotEmpty) {
        writingError = null;
      }
      if (meaningController.text.trim().isNotEmpty) {
        meaningError = null;
      }
    });
  }

  Future<void> _loadExistingPhoto() async {
    final term = widget.term;
    if (term == null) return;

    try {
      final hasSavedEdit = await ReadingCardEditStorage.hasSavedEdit(
        deck: widget.deck,
        term: term,
      );
      final savedData = await ReadingCardEditStorage.load(
        deck: widget.deck,
        term: term,
      );

      if (!mounted) return;

      setState(() {
        existingReadingEdit = hasSavedEdit ? savedData : null;
        photoEnabled = hasSavedEdit ? savedData.photoEnabled : false;
        photoPath = hasSavedEdit ? savedData.photoPath : null;
        photoScale = hasSavedEdit ? savedData.photoScale : 1.0;
        photoOffsetX = hasSavedEdit ? savedData.photoOffsetX : 0.0;
        photoOffsetY = hasSavedEdit ? savedData.photoOffsetY : 0.0;

        initialPhotoEnabled = photoEnabled;
        initialPhotoPath = photoPath;
        initialPhotoScale = photoScale;
        initialPhotoOffsetX = photoOffsetX;
        initialPhotoOffsetY = photoOffsetY;
        isLoadingPhoto = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoadingPhoto = false;
      });
    }
  }

  Future<void> _openPhotoPicker() async {
    if (isPickingPhoto || isSaving) return;

    setState(() {
      isPickingPhoto = true;
    });

    try {
      final pickedImage = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 78,
        maxWidth: 1400,
        maxHeight: 1400,
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

      if (oldPhotoPath != null && oldPhotoPath != initialPhotoPath) {
        await _deletePhotoFileIfSafe(oldPhotoPath);
      }

      if (!mounted) {
        await _deletePhotoFileIfSafe(savedPhotoPath);
        return;
      }

      setState(() {
        photoEnabled = true;
        photoPath = savedPhotoPath;
        photoScale = 1.0;
        photoOffsetX = 0.0;
        photoOffsetY = 0.0;
        isPickingPhoto = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isPickingPhoto = false;
      });

      _showTemporaryMessage('Could not open photos');
    }
  }

  Future<void> _removePhoto() async {
    if (isPickingPhoto || isSaving) return;

    final oldPhotoPath = photoPath;
    if (oldPhotoPath != null && oldPhotoPath != initialPhotoPath) {
      await _deletePhotoFileIfSafe(oldPhotoPath);
    }

    if (!mounted) return;

    setState(() {
      photoEnabled = false;
      photoPath = null;
      photoScale = 1.0;
      photoOffsetX = 0.0;
      photoOffsetY = 0.0;
    });
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
    final termId = _safeFileNamePart(widget.term?.id ?? draftPhotoId);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${deckId}_${termId}_$timestamp.$extension';
    final savedFile = File('${photoDirectory.path}/$fileName');
    final copiedFile = await File(pickedImage.path).copy(savedFile.path);

    return copiedFile.path;
  }

  Future<void> _deletePhotoFileIfSafe(String path) async {
    try {
      if (path.trim().isEmpty) return;
      if (!await _isReadingCardPhotoPath(path)) return;

      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Photo cleanup is best-effort and should never block card editing.
    }
  }

  Future<bool> _isReadingCardPhotoPath(String path) async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final photoDirectory = Directory(
      '${appDirectory.path}/reading_card_photos',
    );

    return File(path).path.startsWith(photoDirectory.path);
  }

  String _safeExtensionFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last;
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

  Future<void> _discardUnsavedPhotoChanges() async {
    final currentPhotoPath = photoPath;
    if (currentPhotoPath != null && currentPhotoPath != initialPhotoPath) {
      await _deletePhotoFileIfSafe(currentPhotoPath);
    }
  }

  Future<bool> _handleBack() async {
    if (isSaving || isPickingPhoto) return false;
    await _discardUnsavedPhotoChanges();
    return true;
  }

  Future<void> _handleBackTap() async {
    final canPop = await _handleBack();
    if (!mounted || !canPop) return;
    Navigator.pop(context);
  }

  Future<void> _save() async {
    if (isSaving || isLoadingPhoto || isPickingPhoto || !hasChanges) return;

    final writing = writingController.text.trim();
    final meaning = meaningController.text.trim();

    setState(() {
      writingError = writing.isEmpty ? 'Writing required' : null;
      meaningError = meaning.isEmpty ? 'Meaning required' : null;
    });

    if (writing.isEmpty || meaning.isEmpty) return;

    setState(() {
      isSaving = true;
    });

    final existing = widget.term;
    final id = existing?.id ??
        '${widget.deck.id}_custom_${DateTime.now().microsecondsSinceEpoch}';
    final reading = readingController.text.trim();
    final partOfSpeech = partOfSpeechController.text.trim();
    final note = noteController.text.trim();

    final customTerm = Term(
      id: id,
      sourceId: null,
      isCustom: true,
      kanji: writing,
      reading: reading,
      meaning: meaning,
      preferredSpelling: writing,
      hasDictionarySpellingMetadata: false,
      alternativeKanji: const <String>[],
      partOfSpeech: partOfSpeech.isEmpty ? 'custom' : partOfSpeech,
      definitions: <String>[meaning],
      isCommon: false,
      note: note.isEmpty ? null : note,
      kanjiMeaning: meaning,
      marked: existing?.marked ?? false,
    );

    final existingIndex = widget.deck.terms.indexWhere((term) => term.id == id);
    final oldTerm = existingIndex >= 0 ? widget.deck.terms[existingIndex] : null;

    try {
      if (existingIndex >= 0) {
        widget.deck.terms[existingIndex] = customTerm;
      } else {
        widget.deck.terms.add(customTerm);
      }

      if (widget.deck.type == DeckType.hybrid) {
        widget.deck.setHybridCardMode(customTerm, HybridCardMode.reading);
      }

      if (_photoHasChanges) {
        final baseEdit = existingReadingEdit ??
            ReadingCardEditData.empty(
              deckId: widget.deck.id,
              termId: id,
              sourceId: id,
            );
        final photoEdit = baseEdit.copyWith(
          deckId: widget.deck.id,
          termId: id,
          sourceId: id,
          photoEnabled: photoEnabled,
          photoPath: photoPath,
          photoScale: photoScale,
          photoOffsetX: photoOffsetX,
          photoOffsetY: photoOffsetY,
          clearPhotoPath: !photoEnabled || photoPath == null,
        );
        await ReadingCardEditStorage.save(photoEdit);
      }

      if (initialPhotoPath != null && initialPhotoPath != photoPath) {
        await _deletePhotoFileIfSafe(initialPhotoPath!);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (oldTerm != null && existingIndex >= 0) {
        widget.deck.terms[existingIndex] = oldTerm;
      } else {
        widget.deck.terms.removeWhere((term) => term.id == id);
        widget.deck.removeHybridCardMode(customTerm);
      }

      if (!mounted) return;

      setState(() {
        isSaving = false;
      });
      _showTemporaryMessage('Could not save card');
    }
  }

  void _showTemporaryMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
          backgroundColor: Colors.black.withValues(alpha: 0.86),
          content: Text(
            message,
            textScaler: TextScaler.noScaling,
            style: GakujiText.snackBar,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final showSave = hasChanges && !isLoadingPhoto;

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final canPop = await _handleBack();
        if (!context.mounted || !canPop) return;

        Navigator.pop(context, result);
      },
      child: Scaffold(
        backgroundColor: GakujiColors.warmBackground,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                GakujiTopBar(
                  leftIcon: GakujiTopBar.backIcon,
                  leftIconSize: GakujiTopBar.backIconSize,
                  leftIconColor: GakujiColors.darkGray,
                  onLeftTap: _handleBackTap,
                  title: isEditing ? 'Custom Card' : 'Create Card',
                  titleStyle: GakujiText.pageTitle.copyWith(
                    color: GakujiColors.darkGray,
                  ),
                  rightWidget: showSave
                      ? TextButton(
                          onPressed: isSaving || isPickingPhoto ? null : _save,
                          style: TextButton.styleFrom(
                            foregroundColor: GakujiColors.reading,
                            disabledForegroundColor: GakujiColors.softGray,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize:
                                const Size(76, GakujiTopBar.buttonSize),
                          ),
                          child: Text(
                            isSaving ? 'Saving' : 'Save',
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : const SizedBox(
                          width: 76,
                          height: GakujiTopBar.buttonSize,
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 8),
                  child: Text(
                    'Card Edit',
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.xSmall.copyWith(
                      color: GakujiColors.mediumGray,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      GakujiSpacing.roomyContentHorizontal,
                      18,
                      GakujiSpacing.roomyContentHorizontal,
                      40,
                    ),
                    children: [
                      _fieldLabel('Writing'),
                      const SizedBox(height: 9),
                      _field(
                        controller: writingController,
                        hintText: 'Word, phrase, saying, or name',
                        errorText: writingError,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 22),
                      _fieldLabel('Reading'),
                      const SizedBox(height: 9),
                      _field(
                        controller: readingController,
                        hintText: 'Optional',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 22),
                      _fieldLabel('Meaning'),
                      const SizedBox(height: 9),
                      _field(
                        controller: meaningController,
                        hintText: 'Definition or card answer',
                        errorText: meaningError,
                        minLines: 2,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                      ),
                      const SizedBox(height: 22),
                      _fieldLabel('Photo'),
                      const SizedBox(height: 9),
                      _photoField(),
                      const SizedBox(height: 22),
                      _fieldLabel('Part of Speech'),
                      const SizedBox(height: 9),
                      _field(
                        controller: partOfSpeechController,
                        hintText: 'Optional',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 22),
                      _fieldLabel('Note'),
                      const SizedBox(height: 9),
                      _field(
                        controller: noteController,
                        hintText: 'Optional',
                        minLines: 3,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      textScaler: TextScaler.noScaling,
      style: GakujiText.actionLabel.copyWith(
        color: GakujiColors.darkGray,
      ),
    );
  }

  Widget _photoField() {
    if (isLoadingPhoto || isPickingPhoto) {
      return Container(
        height: 132,
        decoration: _fieldDecoration(),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: GakujiColors.reading,
            ),
          ),
        ),
      );
    }

    if (!photoEnabled) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openPhotoPicker,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 112,
            decoration: _fieldDecoration(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 30,
                  color: GakujiColors.reading,
                ),
                const SizedBox(height: 7),
                Text(
                  'Add Photo',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.body.copyWith(
                    color: GakujiColors.reading,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Optional',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.xSmall.copyWith(
                    color: GakujiColors.mediumGray,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 160,
      clipBehavior: Clip.antiAlias,
      decoration: _fieldDecoration(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photoFileExists)
            Image.file(
              File(photoPath!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _photoUnavailable();
              },
            )
          else
            _photoUnavailable(),
          Positioned(
            left: 10,
            bottom: 10,
            child: _photoAction(
              label: 'Remove',
              onTap: _removePhoto,
              destructive: true,
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: _photoAction(
              label: 'Change',
              onTap: _openPhotoPicker,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _fieldDecoration({String? errorText}) {
    return BoxDecoration(
      color: GakujiColors.warmCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: errorText == null
            ? GakujiColors.warmDivider
            : GakujiColors.pinRed,
        width: 1.5,
      ),
      boxShadow: [GakujiShadows.soft],
    );
  }

  Widget _photoUnavailable() {
    return Material(
      color: GakujiColors.warmCard,
      child: InkWell(
        onTap: _openPhotoPicker,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_outlined,
                size: 30,
                color: GakujiColors.mediumGray,
              ),
              const SizedBox(height: 7),
              Text(
                'Photo unavailable',
                textScaler: TextScaler.noScaling,
                style: GakujiText.body.copyWith(
                  color: GakujiColors.mediumGray,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoAction({
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? GakujiColors.pinRed : GakujiColors.reading;

    return Material(
      color: GakujiColors.warmCard.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hintText,
    String? errorText,
    int minLines = 1,
    int maxLines = 1,
    TextInputAction? textInputAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: _fieldDecoration(errorText: errorText),
          child: TextField(
            controller: controller,
            minLines: minLines,
            maxLines: maxLines,
            textInputAction: textInputAction,
            style: GakujiText.body.copyWith(
              color: GakujiColors.darkGray,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: GakujiText.body.copyWith(
                color: GakujiColors.mediumGray,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText,
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.pinRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
