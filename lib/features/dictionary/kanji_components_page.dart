import 'package:flutter/material.dart';

import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_faded_scroll.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/data/dictionary/dictionary_service.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/features/dictionary/kanji_dictionary_detail_page.dart';

class KanjiComponentsPage extends StatefulWidget {
  final Term rootEntry;
  final List<KanjiComponentNode> componentTree;

  const KanjiComponentsPage({
    super.key,
    required this.rootEntry,
    required this.componentTree,
  });

  @override
  State<KanjiComponentsPage> createState() => _KanjiComponentsPageState();
}

class _KanjiComponentsPageState extends State<KanjiComponentsPage> {
  Map<String, Term> entriesByCharacter = const {};
  bool entriesLoaded = false;
  int loadRequestId = 0;

  Color get darkText => GakujiColors.darkGray;
  Color get softText => GakujiColors.mediumGray;

  @override
  void initState() {
    super.initState();
    _loadComponentEntries();
  }

  @override
  void didUpdateWidget(covariant KanjiComponentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.rootEntry.id != widget.rootEntry.id ||
        oldWidget.componentTree != widget.componentTree) {
      entriesByCharacter = const {};
      entriesLoaded = false;
      _loadComponentEntries();
    }
  }

  Future<void> _loadComponentEntries() async {
    final requestId = ++loadRequestId;
    final characters = <String>{};

    void collect(KanjiComponentNode node) {
      final lookup = node.lookupCharacter.trim();
      if (lookup.isNotEmpty) characters.add(lookup);

      for (final child in node.children) {
        collect(child);
      }
    }

    for (final node in widget.componentTree) {
      collect(node);
    }

    final loadedEntries =
        await DictionaryService.getKanjiEntriesByCharacters(characters);

    if (!mounted || requestId != loadRequestId) return;

    setState(() {
      entriesByCharacter = loadedEntries;
      entriesLoaded = true;
    });
  }

  void _openKanjiEntry(Term term) {
    Navigator.of(context).push(
      GakujiPageRoute(
        builder: (_) => KanjiDictionaryDetailPage(kanjiEntry: term),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _flattenTree(widget.componentTree);

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            GakujiTopBar(
              leftIcon: GakujiTopBar.backIcon,
              leftIconSize: GakujiTopBar.backIconSize,
              leftIconColor: darkText,
              onLeftTap: () => Navigator.of(context).pop(),
              title: 'Components',
              titleStyle: GakujiText.pageTitle.copyWith(color: darkText),
            ),
            Expanded(
              child: GakujiFadedScroll(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    GakujiSpacing.contentHorizontal,
                    18,
                    GakujiSpacing.contentHorizontal,
                    90,
                  ),
                  children: [
                    _rootRow(),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 22, 8, 0),
                        child: Text(
                          'No component breakdown available',
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.dictionaryDetailBody.copyWith(
                            color: softText,
                          ),
                        ),
                      )
                    else
                      ...rows.map(_componentRow),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rootRow() {
    final entry = widget.rootEntry;

    return SizedBox(
      height: 104,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              entry.kanji,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: GakujiText.dictionaryKanjiDisplay.copyWith(
                fontSize: 54,
                color: darkText,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: _entryDetails(entry)),
        ],
      ),
    );
  }

  Widget _componentRow(_ComponentRowData row) {
    final node = row.node;
    final lookupCharacter = node.lookupCharacter;
    final componentEntry = entriesByCharacter[lookupCharacter];
    final canOpen = componentEntry != null;
    final treeWidth = 74.0 + row.depth * 28.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canOpen ? () => _openKanjiEntry(componentEntry) : null,
      child: SizedBox(
        height: 92,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: treeWidth,
              height: 92,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ComponentTreePainter(
                        depth: row.depth,
                        ancestorContinues: row.ancestorContinues,
                        isLast: row.isLast,
                        color: GakujiColors.reading.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 48,
                    child: Center(
                      child: Text(
                        node.element,
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.dictionaryKanjiDisplay.copyWith(
                          fontSize: 42,
                          color: darkText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: componentEntry == null
                  ? _missingEntryDetails(node)
                  : _entryDetails(componentEntry),
            ),
            SizedBox(
              width: 34,
              child: canOpen
                  ? Icon(
                      Icons.chevron_right_rounded,
                      size: 28,
                      color: softText,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryDetails(Term entry) {
    final meaning = entry.kanjiMeaning.trim().isNotEmpty
        ? entry.kanjiMeaning.trim()
        : entry.meaning.trim();
    final kunyomi = entry.kunyomi
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(', ');
    final onyomi = entry.onyomi
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(', ');

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meaning.isNotEmpty)
          Text(
            meaning,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: GakujiText.dictionaryDetailBody.copyWith(
              height: 1.18,
              color: darkText,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (kunyomi.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            kunyomi,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: GakujiText.body.copyWith(
              height: 1.15,
              color: darkText,
            ),
          ),
        ],
        if (onyomi.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            onyomi,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: GakujiText.body.copyWith(
              height: 1.15,
              color: darkText,
            ),
          ),
        ],
      ],
    );
  }

  Widget _missingEntryDetails(KanjiComponentNode node) {
    if (!entriesLoaded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: GakujiColors.reading,
          ),
        ),
      );
    }

    final original = node.original?.trim() ?? '';

    if (original.isEmpty || original == node.element) {
      return const SizedBox.shrink();
    }

    return Text(
      'Variant of $original',
      textScaler: TextScaler.noScaling,
      style: GakujiText.body.copyWith(
        color: softText,
      ),
    );
  }

  List<_ComponentRowData> _flattenTree(List<KanjiComponentNode> roots) {
    final rows = <_ComponentRowData>[];

    void appendLevel(
      List<KanjiComponentNode> nodes,
      int depth,
      List<bool> ancestorContinues,
    ) {
      for (var index = 0; index < nodes.length; index++) {
        final node = nodes[index];
        final isLast = index == nodes.length - 1;

        rows.add(
          _ComponentRowData(
            node: node,
            depth: depth,
            ancestorContinues: List.unmodifiable(ancestorContinues),
            isLast: isLast,
          ),
        );

        if (node.children.isNotEmpty) {
          appendLevel(
            node.children,
            depth + 1,
            <bool>[...ancestorContinues, !isLast],
          );
        }
      }
    }

    appendLevel(roots, 0, const []);
    return rows;
  }
}

class _ComponentRowData {
  final KanjiComponentNode node;
  final int depth;
  final List<bool> ancestorContinues;
  final bool isLast;

  const _ComponentRowData({
    required this.node,
    required this.depth,
    required this.ancestorContinues,
    required this.isLast,
  });
}

class _ComponentTreePainter extends CustomPainter {
  final int depth;
  final List<bool> ancestorContinues;
  final bool isLast;
  final Color color;

  const _ComponentTreePainter({
    required this.depth,
    required this.ancestorContinues,
    required this.isLast,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    final centerY = size.height / 2;

    for (var level = 0; level < ancestorContinues.length; level++) {
      if (!ancestorContinues[level]) continue;

      final x = 15.0 + level * 28.0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    final branchX = 15.0 + depth * 28.0;
    canvas.drawLine(Offset(branchX, 0), Offset(branchX, centerY), paint);

    if (!isLast) {
      canvas.drawLine(
        Offset(branchX, centerY),
        Offset(branchX, size.height),
        paint,
      );
    }

    canvas.drawLine(
      Offset(branchX, centerY),
      Offset(size.width - 39, centerY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ComponentTreePainter oldDelegate) {
    return oldDelegate.depth != depth ||
        oldDelegate.isLast != isLast ||
        oldDelegate.color != color ||
        oldDelegate.ancestorContinues != ancestorContinues;
  }
}
