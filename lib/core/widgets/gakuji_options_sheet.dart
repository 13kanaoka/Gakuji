import 'package:flutter/material.dart';

import 'package:gakuji/core/theme/gakuji_styles.dart';

typedef GakujiOptionsSheetSectionsBuilder
    = List<GakujiOptionsSheetSection> Function(BuildContext context);

class GakujiOptionsSheetSection {
  final String? title;
  final List<GakujiOptionsSheetItem> items;

  const GakujiOptionsSheetSection({
    this.title,
    required this.items,
  });
}

class GakujiOptionsSheetItem {
  final IconData? icon;
  final String? textIcon;
  final String label;
  final String? subtitle;
  final Color? iconColor;
  final Color? textColor;
  final VoidCallback onTap;

  const GakujiOptionsSheetItem({
    this.icon,
    this.textIcon,
    required this.label,
    this.subtitle,
    this.iconColor,
    this.textColor,
    required this.onTap,
  });
}

Future<void> showGakujiOptionsSheet({
  required BuildContext context,
  required String title,
  List<GakujiOptionsSheetSection>? sections,
  GakujiOptionsSheetSectionsBuilder? sectionsBuilder,
}) {
  assert(
    sections != null || sectionsBuilder != null,
    'Either sections or sectionsBuilder must be provided.',
  );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final currentSections =
              sectionsBuilder?.call(context) ?? sections ?? const [];

          return GakujiOptionsSheet(
            title: title,
            sections: currentSections,
            onOptionTapped: () {
              setSheetState(() {});
            },
          );
        },
      );
    },
  );
}

class GakujiOptionsSheet extends StatelessWidget {
  final String title;
  final List<GakujiOptionsSheetSection> sections;
  final VoidCallback? onOptionTapped;

  const GakujiOptionsSheet({
    super.key,
    required this.title,
    required this.sections,
    this.onOptionTapped,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    final bottomSafePadding =
        mediaQuery.padding.bottom > 0 ? mediaQuery.padding.bottom + 14.0 : 24.0;

    final maxSheetHeight =
        mediaQuery.size.height - mediaQuery.padding.top - 18.0;

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: const SizedBox.expand(),
            ),
          ),
          SafeArea(
            top: false,
            bottom: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxSheetHeight,
                ),
                child: Material(
                  color: GakujiColors.warmBackground,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        0,
                        32,
                        0,
                        bottomSafePadding,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _sheetHandle(),
                          const SizedBox(height: 22),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            textScaler: TextScaler.noScaling,
                            style: GakujiText.large.copyWith(
                              color: GakujiColors.darkGray,
                            ),
                          ),
                          const SizedBox(height: 22),
                          ..._sectionWidgets(context),
                        ],
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

  List<Widget> _sectionWidgets(BuildContext context) {
    final widgets = <Widget>[];

    for (int i = 0; i < sections.length; i++) {
      final section = sections[i];

      if (section.title != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                section.title!,
                textScaler: TextScaler.noScaling,
                style: GakujiText.xSmall.copyWith(
                  color: GakujiColors.mediumGray,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        );
      }

      widgets.add(
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: GakujiColors.warmCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: GakujiColors.warmDivider,
              width: 1.4,
            ),
          ),
          child: Column(
            children: [
              for (int itemIndex = 0;
                  itemIndex < section.items.length;
                  itemIndex++) ...[
                _optionItem(
                  context,
                  section.items[itemIndex],
                ),
                if (itemIndex != section.items.length - 1)
                   Divider(
                    height: 1,
                    color: GakujiColors.lightDivider,
                  ),
              ],
            ],
          ),
        ),
      );

      if (i != sections.length - 1) {
        widgets.add(const SizedBox(height: 8));
      }
    }

    return widgets;
  }

  Widget _sheetHandle() {
    return Center(
      child: Container(
        width: 42,
        height: 5,
        decoration: BoxDecoration(
          color: GakujiColors.softGray,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _optionItem(
    BuildContext context,
    GakujiOptionsSheetItem item,
  ) {
    final iconColor = item.iconColor ?? GakujiColors.mediumGray;
    final textColor = item.textColor ?? GakujiColors.darkGray;

    return InkWell(
      onTap: () {
        item.onTap();
        onOptionTapped?.call();
      },
      splashColor: GakujiColors.deckBlue.withValues(alpha: 0.07),
      highlightColor: GakujiColors.deckBlue.withValues(alpha: 0.035),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Center(
                child: item.textIcon != null
                    ? Text(
                        item.textIcon!,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: 22,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: iconColor,
                        ),
                      )
                    : Icon(
                        item.icon,
                        size: 24,
                        color: iconColor,
                      ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.menuItem.copyWith(
                      color: textColor,
                    ),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle!,
                      textScaler: TextScaler.noScaling,
                      style: GakujiText.xSmall.copyWith(
                        color: GakujiColors.mediumGray,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}