import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../data/reading_card_edit_data.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../services/dictionary_service.dart';
import '../services/reading_card_edit_storage.dart';
import '../widgets/gakuji_faded_scroll.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import '../widgets/reading_card_back.dart';
import '../services/gakuji_user_data_store.dart';

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

class _SenseGlossOption {
  final int senseIndex;
  final String gloss;
  final List<String> sourceGlosses;

  const _SenseGlossOption({
    required this.senseIndex,
    required this.gloss,
    required this.sourceGlosses,
  });

  String get key => '$senseIndex';

  String get senseLabel {
    if (senseIndex >= 0 && senseIndex < 26) {
      return String.fromCharCode(65 + senseIndex);
    }

    return '•';
  }
}

class _SenseExampleOption {
  final int senseIndex;
  final DictionaryExample example;

  const _SenseExampleOption({
    required this.senseIndex,
    required this.example,
  });

  String get senseLabel {
    if (senseIndex >= 0 && senseIndex < 26) {
      return String.fromCharCode(65 + senseIndex);
    }

    return '•';
  }
}

class _ReadingCardEditPageState extends State<ReadingCardEditPage> {
  static const Color accentBlue = Color(0xFF4D7EF7);
  static const Color removeRed = Color(0xFFFF4B4B);
  static const Color softTextGray = Color(0xFF8A8A8A);
  static const Color softBlueFill = Color(0xFFF5F7FF);
  static const Color softBlueBorder = Color(0xFFEAF0FF);

  static const int maxGlosses = 3;
  static const int maxNoteCharacters = 35;
  static const int maxExamples = 1;

  final ImagePicker imagePicker = ImagePicker();
  final Set<String> photoPathsPendingDeletion = <String>{};

  bool isLoadingEditData = true;
  bool isSaving = false;
  bool isPickingPhoto = false;
  bool hasUnsavedChanges = false;
  bool photoEnabled = false;

  String? photoPath;
  String? lastSavedPhotoPath;

  late Term sourceTerm;
  late List<_SenseGlossOption> selectedGlosses;
  late String cardNote;
  late List<DictionaryExample> selectedExamples;

  @override
  void initState() {
    super.initState();

    sourceTerm = widget.term;
    selectedGlosses = <_SenseGlossOption>[];
    cardNote = _limitNote(widget.term.note ?? '');
    selectedExamples = <DictionaryExample>[];

    unawaited(_initializeEditor());
  }

  Future<void> _initializeEditor() async {
    var resolvedSourceTerm = widget.term;
    final dictionaryTermId = widget.term.sourceId ?? widget.term.id;

    try {
      resolvedSourceTerm = await DictionaryService.getTermByIdAsync(
        dictionaryTermId,
      );
    } catch (_) {
      // Older deck copies can still open even if their dictionary source is
      // temporarily unavailable. In that case, use the copy carried by the
      // card as a fallback.
    }

    if (!mounted) return;

    sourceTerm = resolvedSourceTerm;
    await loadSavedEditData();
  }

  List<_SenseGlossOption> get allGlosses {
    final options = <_SenseGlossOption>[];

    for (final sense in sourceTerm.senses) {
      final definition = sense.displayDefinition.trim();

      if (definition.isEmpty) continue;

      options.add(
        _SenseGlossOption(
          senseIndex: sense.index,
          gloss: definition,
          sourceGlosses: List<String>.from(sense.glosses),
        ),
      );
    }

    if (options.isNotEmpty) return options;

    final fallback = sourceTerm.cardMeaning.trim();

    if (fallback.isEmpty) return const [];

    return [
      _SenseGlossOption(
        senseIndex: 0,
        gloss: fallback,
        sourceGlosses: [fallback],
      ),
    ];
  }

  List<_SenseGlossOption> _defaultGlosses() {
    final optionsBySenseIndex = {
      for (final option in allGlosses) option.senseIndex: option,
    };
    final selectedSenseIndexes = widget.term.selectedGlosses
        .map((selection) => selection.senseIndex)
        .toSet();
    final selected = <_SenseGlossOption>[];

    for (final sense in sourceTerm.senses) {
      if (!selectedSenseIndexes.contains(sense.index)) continue;

      final option = optionsBySenseIndex[sense.index];

      if (option != null) {
        selected.add(option);
      }

      if (selected.length >= maxGlosses) break;
    }

    if (selected.isNotEmpty) return selected;

    return allGlosses.take(maxGlosses).toList();
  }

  List<_SenseGlossOption> _optionsFromStoredGlosses(
    List<String> storedGlosses,
  ) {
    if (storedGlosses.isEmpty) return const [];

    final resolved = <_SenseGlossOption>[];
    final usedSenseIndexes = <int>{};

    for (final storedValue in storedGlosses) {
      final cleanedValue = storedValue.trim();

      if (cleanedValue.isEmpty) continue;

      _SenseGlossOption? matchingOption;

      for (final option in allGlosses) {
        final matchesFullSense = option.gloss == cleanedValue;
        final matchesLegacyIndividualGloss = option.sourceGlosses.any(
          (gloss) => gloss.trim() == cleanedValue,
        );

        if (matchesFullSense || matchesLegacyIndividualGloss) {
          matchingOption = option;
          break;
        }
      }

      if (matchingOption == null ||
          !usedSenseIndexes.add(matchingOption.senseIndex)) {
        continue;
      }

      resolved.add(matchingOption);

      if (resolved.length >= maxGlosses) break;
    }

    return resolved;
  }

  Set<int> _senseIndexesForGlosses(
    List<_SenseGlossOption> glosses,
  ) {
    return glosses
        .where((option) => option.senseIndex >= 0)
        .map((option) => option.senseIndex)
        .toSet();
  }

  List<_SenseExampleOption> _exampleOptionsForGlosses(
    List<_SenseGlossOption> glosses,
  ) {
    final selectedSenseIndexes = _senseIndexesForGlosses(glosses);
    final options = <_SenseExampleOption>[];
    final seen = <String>{};

    final senses = sourceTerm.senses.where(
      (sense) => selectedSenseIndexes.contains(sense.index),
    );

    for (final sense in senses) {
      for (final example in sense.examples) {
        final key = '${example.japanese}\u0000${example.english}';

        if (!seen.add(key)) continue;

        options.add(
          _SenseExampleOption(
            senseIndex: sense.index,
            example: example,
          ),
        );
      }
    }

    return options;
  }

  List<DictionaryExample> _defaultExamples(
    List<_SenseGlossOption> glosses,
  ) {
    return _exampleOptionsForGlosses(glosses)
        .take(maxExamples)
        .map((option) => option.example)
        .toList();
  }

  String _limitNote(String value) {
    if (value.runes.length <= maxNoteCharacters) {
      return value;
    }

    return String.fromCharCodes(
      value.runes.take(maxNoteCharacters),
    );
  }

  bool _sameExample(
    DictionaryExample left,
    DictionaryExample right,
  ) {
    return left.japanese == right.japanese && left.english == right.english;
  }

  String get termTitle {
    if (sourceTerm.kanjiBracketText.trim().isNotEmpty) {
      return sourceTerm.kanjiBracketText.trim();
    }

    if (sourceTerm.kanji.trim().isNotEmpty) {
      return sourceTerm.kanji.trim();
    }

    return sourceTerm.reading.trim();
  }

  ReadingCardEditData get currentEditData {
    return ReadingCardEditData(
      deckId: widget.deck.id,
      termId: widget.term.id,
      sourceId: ReadingCardEditData.sourceIdFor(widget.term),
      selectedGlosses:
          selectedGlosses.map((option) => option.gloss).toList(),
      selectedExampleKeys: ReadingCardEditData.keysFromExamples(
        selectedExamples.take(maxExamples).toList(),
      ),
      note: _limitNote(cardNote),
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

    final loadedGlosses = hasSavedEdit
        ? _optionsFromStoredGlosses(savedData.selectedGlosses)
        : _defaultGlosses();
    final resolvedGlosses = loadedGlosses.isEmpty
        ? _defaultGlosses()
        : loadedGlosses;
    final eligibleExamples = _exampleOptionsForGlosses(resolvedGlosses)
        .map((option) => option.example)
        .toList();
    final savedExamples = ReadingCardEditData.examplesFromKeys(
      examples: eligibleExamples,
      selectedExampleKeys: savedData.selectedExampleKeys,
    );

    setState(() {
      selectedGlosses = resolvedGlosses;

      cardNote = _limitNote(
        hasSavedEdit ? savedData.note : widget.term.note ?? '',
      );

      selectedExamples = hasSavedEdit
          ? savedExamples.take(maxExamples).toList()
          : _defaultExamples(resolvedGlosses);

      photoEnabled = hasSavedEdit ? savedData.photoEnabled : false;
      photoPath = hasSavedEdit ? savedData.photoPath : null;
      lastSavedPhotoPath = photoPath;

      photoPathsPendingDeletion.clear();

      hasUnsavedChanges = false;
      isLoadingEditData = false;
    });
  }

  void scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
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
      _writeGlossSelectionsToDeckTerm();
      await _deletePendingPhotoFiles();

      scheduleUserDataSave();

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

  void _writeGlossSelectionsToDeckTerm() {
    final termIndex = widget.deck.terms.indexWhere(
      (term) => term.id == widget.term.id,
    );

    if (termIndex == -1) return;

    final selections = <GlossSelection>[];

    for (final option in selectedGlosses) {
      for (var glossIndex = 0;
          glossIndex < option.sourceGlosses.length;
          glossIndex++) {
        selections.add(
          GlossSelection(
            senseIndex: option.senseIndex,
            glossIndex: glossIndex,
          ),
        );
      }
    }

    final currentDeckTerm = widget.deck.terms[termIndex];

    // Refresh the deck copy with the current dictionary senses and examples,
    // while preserving card-owned identity and state.
    widget.deck.terms[termIndex] = sourceTerm.copyWith(
      id: currentDeckTerm.id,
      sourceId: currentDeckTerm.sourceId ?? sourceTerm.id,
      selectedGlosses: selections,
      note: currentDeckTerm.note,
      marked: currentDeckTerm.marked,
    );
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
          backgroundColor: Colors.black.withValues(alpha: 0.86),
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
            final eligibleExamples = _exampleOptionsForGlosses(newGlosses)
                .map((option) => option.example)
                .toList();

            setState(() {
              selectedGlosses = newGlosses;
              selectedExamples = selectedExamples
                  .where((selected) {
                    return eligibleExamples.any(
                      (eligible) => _sameExample(eligible, selected),
                    );
                  })
                  .take(maxExamples)
                  .toList();
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
                  minLines: 2,
                  maxLines: 3,
                  maxLength: maxNoteCharacters,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(maxNoteCharacters),
                  ],
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
                      cardNote = _limitNote(controller.text.trimRight());
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
          examples: _exampleOptionsForGlosses(selectedGlosses),
          selectedExamples: selectedExamples,
          onChanged: (newExamples) {
            setState(() {
              selectedExamples = newExamples.take(maxExamples).toList();
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldPop = await handleBack();

        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              GakujiTopBar(
                leftIcon: GakujiTopBar.backIcon,
                leftIconSize: GakujiTopBar.backIconSize,
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
                      : GakujiFadedScroll(
                          child: SingleChildScrollView(
                            padding:
                                const EdgeInsets.fromLTRB(24, 30, 24, 46),
                            child: _cardPreview(),
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
    final glosses = selectedGlosses
        .map((option) => option.gloss)
        .toList(growable: false);
    final previewPhotoPath = photoEnabled ? photoPath : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReadingCardFrame(
          maxWidth: 430,
          child: ReadingCardBackContent(
            glosses: glosses,
            note: cardNote,
            examples: selectedExamples.take(maxExamples).toList(),
            photoPath: previewPhotoPath,
            onGlossTap: openGlossSheet,
            onNoteTap: openNoteSheet,
            onExamplesTap: openExamplesSheet,
            onPhotoTap: openPhotoPicker,
          ),
        ),
        const SizedBox(height: 24),
        _previewEditControls(),
      ],
    );
  }

  Widget _previewEditControls() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        _previewEditButton(
          icon: Icons.translate_rounded,
          label: 'Glosses',
          onTap: openGlossSheet,
        ),
        _previewEditButton(
          icon: Icons.notes_rounded,
          label: cardNote.trim().isEmpty ? 'Add note' : 'Note',
          onTap: openNoteSheet,
        ),
        _previewEditButton(
          icon: Icons.format_quote_rounded,
          label: selectedExamples.isEmpty ? 'Add example' : 'Example',
          onTap: openExamplesSheet,
        ),
        _previewEditButton(
          icon: Icons.photo_outlined,
          label: photoEnabled ? 'Change photo' : 'Add photo',
          onTap: openPhotoPicker,
        ),
        if (photoEnabled)
          _previewEditButton(
            icon: Icons.delete_outline_rounded,
            label: 'Remove photo',
            onTap: removePhoto,
            destructive: true,
          ),
      ],
    );
  }

  Widget _previewEditButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final foreground = destructive ? removeRed : accentBlue;

    return Material(
      color: GakujiColors.warmCard,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 13, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: GakujiColors.softBorder,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: foreground,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1,
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
  final List<_SenseGlossOption> glosses;
  final List<_SenseGlossOption> selectedGlosses;
  final ValueChanged<List<_SenseGlossOption>> onChanged;

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
  static const Color softTextGray = Color(0xFF8A8A8A);
  static const int maxGlosses = 3;

  late List<_SenseGlossOption> workingSelection;

  @override
  void initState() {
    super.initState();

    workingSelection = List<_SenseGlossOption>.from(widget.selectedGlosses);
  }

  bool isSelected(_SenseGlossOption option) {
    return workingSelection.any(
      (selected) => selected.senseIndex == option.senseIndex,
    );
  }

  void toggleGloss(_SenseGlossOption option) {
    setState(() {
      if (isSelected(option)) {
        workingSelection.removeWhere(
          (selected) => selected.senseIndex == option.senseIndex,
        );
      } else {
        if (workingSelection.length >= maxGlosses) return;

        workingSelection.add(option);
      }
    });
  }

  void moveGloss(int oldIndex, int newIndex) {
    setState(() {
      final gloss = workingSelection.removeAt(oldIndex);
      workingSelection.insert(newIndex, gloss);
    });
  }

  void saveAndClose() {
    widget.onChanged(List<_SenseGlossOption>.from(workingSelection));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _CardEditBottomSheet(
      title: 'Choose Glosses',
      child: Column(
        children: [
          Text(
            '${workingSelection.length}/$maxGlosses selected • examples follow the selected meanings',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.2,
              color: softTextGray,
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
                onReorderItem: moveGloss,
                buildDefaultDragHandles: true,
                itemBuilder: (context, index) {
                  final option = workingSelection[index];

                  return ListTile(
                    key: ValueKey('selected_${option.key}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 13,
                      backgroundColor: accentBlue,
                      child: Text(
                        option.senseLabel,
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
                      option.gloss,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.12,
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
                    padding: EdgeInsets.zero,
                    itemCount: widget.glosses.length,
                    separatorBuilder: (context, index) {
                      return const Divider(height: 1, color: dividerGray);
                    },
                    itemBuilder: (context, index) {
                      final option = widget.glosses[index];
                      final selected = isSelected(option);

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => toggleGloss(option),
                        leading: Container(
                          width: 25,
                          height: 25,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: softTextGray,
                              width: 1.4,
                            ),
                          ),
                          child: Text(
                            option.senseLabel,
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1,
                              color: softTextGray,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          option.gloss,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontSize: 15.5,
                            height: 1.17,
                            color: Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: selected ? accentBlue : softTextGray,
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
  final List<_SenseExampleOption> examples;
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
  static const Color softTextGray = Color(0xFF8A8A8A);
  static const int maxExamples = 1;

  late List<DictionaryExample> workingSelection;

  @override
  void initState() {
    super.initState();

    workingSelection = widget.selectedExamples.take(maxExamples).toList();
  }

  bool sameExample(DictionaryExample left, DictionaryExample right) {
    return left.japanese == right.japanese && left.english == right.english;
  }

  bool exampleIsSelected(DictionaryExample example) {
    return workingSelection.any((selected) => sameExample(selected, example));
  }

  void toggleExample(DictionaryExample example) {
    setState(() {
      if (exampleIsSelected(example)) {
        workingSelection.removeWhere(
          (selected) => sameExample(selected, example),
        );
      } else {
        workingSelection
          ..clear()
          ..add(example);
      }
    });
  }

  void saveAndClose() {
    widget.onChanged(workingSelection.take(maxExamples).toList());
    Navigator.pop(context);
  }

  String senseLabel(int senseIndex) {
    if (senseIndex >= 0 && senseIndex < 26) {
      return String.fromCharCode(65 + senseIndex);
    }

    return '•';
  }

  @override
  Widget build(BuildContext context) {
    final groupedExamples = <int, List<_SenseExampleOption>>{};

    for (final option in widget.examples) {
      groupedExamples
          .putIfAbsent(option.senseIndex, () => <_SenseExampleOption>[])
          .add(option);
    }

    return _CardEditBottomSheet(
      title: 'Choose Example',
      child: Column(
        children: [
          Text(
            '${workingSelection.length}/$maxExamples selected • one example per card',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.2,
              color: softTextGray,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.examples.isEmpty
                ? const Center(
                    child: Text(
                      'No examples for the selected glosses',
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: groupedExamples.entries.map((group) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 13, 0, 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: softTextGray,
                                      width: 1.4,
                                    ),
                                  ),
                                  child: Text(
                                    senseLabel(group.key),
                                    textScaler: TextScaler.noScaling,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      height: 1,
                                      color: softTextGray,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 9),
                                const Text(
                                  'Matching examples',
                                  textScaler: TextScaler.noScaling,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1,
                                    color: softTextGray,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...group.value.map((option) {
                            final example = option.example;
                            final selected = exampleIsSelected(example);

                            return Column(
                              children: [
                                ListTile(
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
                                        color: softTextGray,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  trailing: Icon(
                                    selected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                    color: selected
                                        ? accentBlue
                                        : softTextGray,
                                  ),
                                ),
                                const Divider(
                                  height: 1,
                                  color: dividerGray,
                                ),
                              ],
                            );
                          }),
                        ],
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 12),
          _SheetSaveButton(
            label: 'Save Example',
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