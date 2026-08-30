import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';

import 'package:gakuji/data/seed/deck_seed.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/features/auth/services/account_username_service.dart';
import 'package:gakuji/data/sync/gakuji_user_data_store.dart';
import 'package:gakuji/data/sync/gakuji_user_repository.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/features/import/import_terms_page.dart';

class CreateDeckPage extends StatefulWidget {
  const CreateDeckPage({super.key});

  @override
  State<CreateDeckPage> createState() => _CreateDeckPageState();
}

class _CreateDeckPageState extends State<CreateDeckPage> {
  final TextEditingController nameController = TextEditingController();

  static const String recentDeckColorsPreferenceKey = 'recent_deck_colors';
  static const int maxRecentDeckColors = 6;

  DeckType selectedType = DeckType.reading;
  Color selectedDeckColor = GakujiColors.reading;
  bool hasManuallySelectedDeckColor = false;
  String? deckNameError;
  List<Color> recentDeckColors = [];

  Color defaultDeckColorForType(DeckType type) {
    return GakujiColors.defaultDeckColorForType(type);
  }

  Color readableTextColor(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF3F3F3F);
  }

  @override
  void initState() {
    super.initState();
    loadRecentDeckColors();
  }

  Future<void> loadRecentDeckColors() async {
    final stored = await GakujiUserRepository.loadPreference(
      recentDeckColorsPreferenceKey,
    );

    if (!mounted || stored == null || stored.trim().isEmpty) return;

    final loadedColors = stored
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .map((value) => Color(value))
        .take(maxRecentDeckColors)
        .toList();

    if (loadedColors.isEmpty) return;

    setState(() {
      recentDeckColors = loadedColors;
    });
  }

  Future<void> saveRecentDeckColor(Color color) async {
    final colorValue = color.toARGB32();
    final updatedColors = <Color>[
      color,
      ...recentDeckColors.where(
        (recentColor) => recentColor.toARGB32() != colorValue,
      ),
    ].take(maxRecentDeckColors).toList();

    if (mounted) {
      setState(() {
        recentDeckColors = updatedColors;
      });
    }

    await GakujiUserRepository.savePreference(
      key: recentDeckColorsPreferenceKey,
      value: updatedColors
          .map((recentColor) => recentColor.toARGB32().toString())
          .join(','),
    );
  }

  @override
  void dispose() {
    nameController.dispose();

    super.dispose();
  }

  void scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
  }

  Future<void> openTermsImportPage() async {
    final imported = await Navigator.push<bool>(
      context,
      GakujiPageRoute(
        builder: (context) => const ImportTermsPage(),
      ),
    );

    if (!mounted || imported != true) return;

    Navigator.pop(context, true);
  }

  void createDeck() {
    final name = nameController.text.trim();

    if (name.isEmpty) {
      setState(() {
        deckNameError = 'Deck name required';
      });

      return;
    }

    if (GakujiUsernameService.containsRestrictedLanguage(name)) {
      setState(() {
        deckNameError = 'Deck name contains a restricted term';
      });

      return;
    }

    decks.add(
      Deck(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        type: selectedType,
        colorValue: selectedDeckColor.toARGB32(),
        terms: [],
      ),
    );

    scheduleUserDataSave();

    Navigator.pop(context, true);
  }

  String deckTypeLabel(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'Writing';
      case DeckType.reading:
        return 'Reading';
      case DeckType.hybrid:
        return 'Hybrid';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    Center(
                      child: _deckCreationIcon(),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Create Deck',
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.pageTitle.copyWith(
                          color: GakujiColors.darkGray,
                        ),
                      ),
                    ),
                    const SizedBox(height: 42),
                    _fieldLabel('Deck Name'),
                    const SizedBox(height: 10),
                    _nameField(),
                    const SizedBox(height: 28),
                    _fieldLabel('Deck Type'),
                    const SizedBox(height: 10),
                    _deckTypeDropdown(),
                    const SizedBox(height: 28),
                    _fieldLabel('Deck Color'),
                    const SizedBox(height: 10),
                    _deckColorPicker(),
                    const Spacer(),
                    _createButton(),
                    const SizedBox(height: 12),
                    _importTermsButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return GakujiTopBar(
      leftIcon: Icons.close_rounded,
      leftIconSize: GakujiTopBar.iconSize,
      leftIconColor: GakujiColors.darkGray,
      onLeftTap: () => Navigator.pop(context),
    );
  }

  Widget _deckCreationIcon() {
    return SizedBox(
      width: 84,
      height: 84,
      child: Center(
        child: Image.asset(
          'assets/images/flashcards.png',
          width: 64,
          height: 64,
          fit: BoxFit.contain,
          color: GakujiColors.mediumGray,
          colorBlendMode: BlendMode.srcIn,
          filterQuality: FilterQuality.high,
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

  Widget _nameField() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: deckNameError == null
              ? GakujiColors.warmDivider
              : const Color(0xFFFF6F6F),
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: TextField(
        controller: nameController,
        textInputAction: TextInputAction.done,
        onChanged: (_) {
          if (deckNameError == null) return;

          setState(() {
            deckNameError = null;
          });
        },
        onSubmitted: (_) => createDeck(),
        style: GakujiText.actionLabel.copyWith(
          color: GakujiColors.darkGray,
        ),
        cursorColor: GakujiColors.darkGray,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Enter deck name',
          hintStyle: GakujiText.actionLabel.copyWith(
            color: GakujiColors.mediumGray,
          ),
        ),
      ),
    );
  }

  Widget _deckTypeDropdown() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DeckType>(
          value: selectedType,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          dropdownColor: GakujiColors.warmCard,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: GakujiColors.darkGray,
          ),
          style: GakujiText.actionLabel.copyWith(
            color: GakujiColors.darkGray,
          ),
          items: DeckType.values.map((type) {
            return DropdownMenuItem(
              value: type,
              child: Text(
                deckTypeLabel(type),
                textScaler: TextScaler.noScaling,
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              selectedType = value;

              if (!hasManuallySelectedDeckColor) {
                selectedDeckColor = defaultDeckColorForType(value);
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> openDeckColorPicker() async {
    final pickedColor = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var workingColor = HSVColor.fromColor(selectedDeckColor);
        var sheetDismissDragOffset = 0.0;
        var isSheetDismissDragging = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final previewColor = workingColor.toColor();

            void startSheetDismissDrag(DragStartDetails details) {
              setSheetState(() {
                isSheetDismissDragging = true;
              });
            }

            void updateSheetDismissDrag(DragUpdateDetails details) {
              setSheetState(() {
                isSheetDismissDragging = true;
                sheetDismissDragOffset += details.delta.dy;
                if (sheetDismissDragOffset < 0) {
                  sheetDismissDragOffset = 0;
                }
              });
            }

            void endSheetDismissDrag(DragEndDetails details) {
              final velocity = details.primaryVelocity ?? 0;
              final shouldDismiss =
                  sheetDismissDragOffset > 96 || velocity > 850;

              if (shouldDismiss) {
                Navigator.of(sheetContext).pop();
                return;
              }

              setSheetState(() {
                isSheetDismissDragging = false;
                sheetDismissDragOffset = 0;
              });
            }

            void cancelSheetDismissDrag() {
              setSheetState(() {
                isSheetDismissDragging = false;
                sheetDismissDragOffset = 0;
              });
            }

            final bottomSafePadding =
                MediaQuery.viewPaddingOf(sheetContext).bottom;

            return AnimatedContainer(
                duration: isSheetDismissDragging
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(
                  0,
                  sheetDismissDragOffset,
                  0,
                ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
                ),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    18,
                    24,
                    24 + bottomSafePadding,
                  ),
                  decoration: BoxDecoration(
                    color: GakujiColors.warmCard,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                    border: Border.all(
                      color: GakujiColors.warmDivider,
                      width: 1.2,
                    ),
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragStart: startSheetDismissDrag,
                      onVerticalDragUpdate: updateSheetDismissDrag,
                      onVerticalDragEnd: endSheetDismissDrag,
                      onVerticalDragCancel: cancelSheetDismissDrag,
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 23,
                            child: Center(
                              child: Container(
                                width: 44,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: GakujiColors.softBorder,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Choose Deck Color',
                                  textScaler: TextScaler.noScaling,
                                  style: GakujiText.sectionTitle.copyWith(
                                    color: GakujiColors.darkGray,
                                  ),
                                ),
                              ),
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: previewColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: GakujiColors.softBorder,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _DeckColorWheel(
                      hsvColor: workingColor,
                      onChanged: (value) {
                        setSheetState(() {
                          workingColor = value;
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          'Brightness',
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.deckMeta.copyWith(
                            color: GakujiColors.darkGray,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: previewColor,
                              inactiveTrackColor: GakujiColors.warmDivider,
                              thumbColor: previewColor,
                              overlayColor:
                                  previewColor.withValues(alpha: 0.10),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: workingColor.value,
                              min: 0,
                              max: 1,
                              onChanged: (value) {
                                setSheetState(() {
                                  workingColor = workingColor.withValue(value);
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (recentDeckColors.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Recent Colors',
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.deckMeta.copyWith(
                            color: GakujiColors.darkGray,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: recentDeckColors.map((color) {
                            final isSelected =
                                color.toARGB32() == previewColor.toARGB32();

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setSheetState(() {
                                  workingColor = HSVColor.fromColor(color);
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? GakujiColors.darkGray
                                        : GakujiColors.softBorder,
                                    width: isSelected ? 2.5 : 1.5,
                                  ),
                                ),
                                child: isSelected
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                        color: readableTextColor(color),
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: GakujiColors.softBorder,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                textScaler: TextScaler.noScaling,
                                style: GakujiText.deckMeta.copyWith(
                                  color: GakujiColors.darkGray,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: FilledButton(
                              onPressed: () {
                                Navigator.pop(sheetContext, previewColor);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: previewColor,
                                foregroundColor:
                                    readableTextColor(previewColor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                'Use Color',
                                textScaler: TextScaler.noScaling,
                                style: GakujiText.deckMeta.copyWith(
                                  color: readableTextColor(previewColor),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || pickedColor == null) return;

    setState(() {
      selectedDeckColor = pickedColor;
      hasManuallySelectedDeckColor = true;
    });

    await saveRecentDeckColor(pickedColor);
  }

  Widget _deckColorPicker() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openDeckColorPicker,
          splashColor: selectedDeckColor.withValues(alpha: 0.08),
          highlightColor: selectedDeckColor.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose Color',
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.actionLabel.copyWith(
                      color: GakujiColors.darkGray,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selectedDeckColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: GakujiColors.softBorder,
                      width: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _importTermsButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openTermsImportPage,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GakujiRadius.pill),
              border: Border.all(
                color: GakujiColors.reading,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.upload_file_rounded,
                  color: GakujiColors.reading,
                  size: 23,
                ),
                const SizedBox(width: 10),
                Text(
                  'Import Terms From File',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.actionLabel.copyWith(
                    color: GakujiColors.reading,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _createButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          end: selectedDeckColor,
        ),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        builder: (context, color, child) {
          return Material(
            color: color,
            borderRadius: BorderRadius.circular(GakujiRadius.pill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: createDeck,
              child: Center(
                child: Text(
                  'Create New Deck',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.actionLabel.copyWith(
                    color: readableTextColor(color ?? selectedDeckColor),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DeckColorWheel extends StatelessWidget {
  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onChanged;

  const _DeckColorWheel({
    required this.hsvColor,
    required this.onChanged,
  });

  void _updateColor(Offset localPosition, double size) {
    final center = Offset(size / 2, size / 2);
    final offset = localPosition - center;
    final radius = size / 2;

    final saturation =
        (offset.distance / radius).clamp(0.0, 1.0).toDouble();
    final angle = math.atan2(offset.dy, offset.dx);
    final hue = ((angle * 180 / math.pi) + 360) % 360;

    onChanged(
      HSVColor.fromAHSV(
        1,
        hue,
        saturation,
        hsvColor.value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 204.0).toDouble();

        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) {
              _updateColor(details.localPosition, size);
            },
            onPanUpdate: (details) {
              _updateColor(details.localPosition, size);
            },
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _DeckColorWheelPainter(hsvColor),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeckColorWheelPainter extends CustomPainter {
  final HSVColor hsvColor;

  const _DeckColorWheelPainter(this.hsvColor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final wheelRect = Rect.fromCircle(center: center, radius: radius);

    final huePaint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ).createShader(wheelRect);

    canvas.drawCircle(center, radius, huePaint);

    final saturationPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(wheelRect);

    canvas.drawCircle(center, radius, saturationPaint);

    if (hsvColor.value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.black.withValues(alpha: 1 - hsvColor.value),
      );
    }

    final angle = hsvColor.hue * math.pi / 180;
    final indicatorRadius = radius * hsvColor.saturation;
    final indicatorCenter = Offset(
      center.dx + math.cos(angle) * indicatorRadius,
      center.dy + math.sin(angle) * indicatorRadius,
    );

    canvas.drawCircle(
      indicatorCenter,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );

    canvas.drawCircle(
      indicatorCenter,
      10.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x66000000),
    );
  }

  @override
  bool shouldRepaint(covariant _DeckColorWheelPainter oldDelegate) {
    return oldDelegate.hsvColor != hsvColor;
  }
}

