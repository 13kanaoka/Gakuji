import 'package:flutter/material.dart';

import '../data/deck_data.dart';
import '../data/dictionary_data.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../theme/app_text_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import 'dictionary_detail_page.dart';

class KanjiDictionaryDetailPage extends StatefulWidget {
  final Term kanjiEntry;

  const KanjiDictionaryDetailPage({super.key, required this.kanjiEntry});

  @override
  State<KanjiDictionaryDetailPage> createState() =>
      _KanjiDictionaryDetailPageState();
}

class _KanjiDictionaryDetailPageState extends State<KanjiDictionaryDetailPage> {
  static const Color sectionColor = Color(0xFFEAF4E9);
  static const Color accentGreen = Color(0xFF6E9A3E);
  static const Color dividerColor = Color(0xFFE3E3E3);

  Deck get defaultDeck =>
      decks.firstWhere((deck) => deck.name == 'Gakuji test deck');

  String get sourceId => widget.kanjiEntry.sourceId ?? widget.kanjiEntry.id;

  bool deckContainsEntry(Deck deck) {
    return deck.terms.any((term) => term.sourceId == sourceId);
  }

  Term copiedEntryForDeck(Deck deck) {
    return Term.deckCopyFrom(
      widget.kanjiEntry,
      id: '${deck.id}_${sourceId}_${DateTime.now().microsecondsSinceEpoch}',
      marked: false,
    );
  }

  bool get isSaved {
    return deckContainsEntry(defaultDeck);
  }

  void toggleDefaultDeck() {
    setState(() {
      if (isSaved) {
        defaultDeck.terms.removeWhere((term) => term.sourceId == sourceId);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Removed from deck')));
      } else {
        defaultDeck.terms.add(copiedEntryForDeck(defaultDeck));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to Gakuji test deck')),
        );
      }
    });
  }

  void openDeckPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('Choose Deck', style: AppText.listHeading),
              ),
            ),
            const Divider(),
            ...decks.map((deck) {
              final exists = deckContainsEntry(deck);

              return ListTile(
                title: Text(deck.name),
                trailing: Icon(
                  exists ? Icons.check : null,
                  color: Colors.green,
                ),
                onTap: () {
                  setState(() {
                    if (!exists) {
                      deck.terms.add(copiedEntryForDeck(deck));
                    }
                  });

                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        exists
                            ? 'Already saved to ${deck.name}'
                            : 'Saved to ${deck.name}',
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }

  void openCompound(KanjiCompound compound) {
    final termId = compound.termId;

    if (termId == null) return;

    final matchingTerm = getTermById(termId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DictionaryDetailPage(word: matchingTerm),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.kanjiEntry;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            GakujiTopBar(
              leftIcon: Icons.arrow_back_ios_new,
              onLeftTap: () => Navigator.pop(context),
              title: entry.kanji,
              rightWidget: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _topActionButton(
                    icon: isSaved ? Icons.favorite : Icons.favorite_border,
                    iconColor: isSaved ? Colors.red : Colors.grey,
                    onTap: toggleDefaultDeck,
                  ),
                  const SizedBox(width: GakujiTopBar.actionGap),
                  _topActionButton(
                    icon: Icons.menu_book_outlined,
                    iconColor: Colors.black,
                    onTap: openDeckPicker,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  _kanjiHeader(entry),
                  _readingBlock(entry),
                  _noteSection(entry),
                  _infoSection(entry),
                  _compoundsSection(entry),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kanjiHeader(Term entry) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 23, 18, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 98,
            child: Text(
              entry.kanji.isEmpty ? '' : entry.kanji.substring(0, 1),
              textAlign: TextAlign.center,
              style: AppText.kanjiHero,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: _strokePreview(entry)),
        ],
      ),
    );
  }

  Widget _strokePreview(Term entry) {
    final kanji = entry.kanji.isEmpty ? '' : entry.kanji.substring(0, 1);

    return SizedBox(
      height: 82,
      child: Row(
        children: List.generate(4, (index) {
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index == 3 ? 0 : 7),
              decoration: BoxDecoration(
                border: Border.all(color: dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  kanji,
                  style: AppText.kanjiStroke.copyWith(
                    color: Colors.black.withValues(
                      alpha: 0.25 + (index * 0.18),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _readingBlock(Term entry) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _readingLine('Meaning', entry.kanjiMeaning),
          if (entry.onyomi.isNotEmpty)
            _readingLine('ON', entry.onyomi.join('、')),
          if (entry.kunyomi.isNotEmpty)
            _readingLine('Kun', entry.kunyomi.join('、')),
          if (entry.nanori.isNotEmpty)
            _readingLine('Nanori', entry.nanori.join('、')),
        ],
      ),
    );
  }

  Widget _readingLine(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label, style: AppText.detailLabel)),
          Expanded(child: Text(value, style: AppText.detailValue)),
        ],
      ),
    );
  }

  Widget _noteSection(Term entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Note'),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 21, 18, 25),
          child: Text(
            entry.note ?? 'Write a note',
            style: AppText.detailValue.copyWith(
              color: entry.note == null ? accentGreen : Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoSection(Term entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Info'),
        _infoRow('Strokes', entry.strokeCount?.toString()),
        _infoRow('Grade', entry.grade?.toString()),
        _infoRow('JLPT', entry.jlptLevel),
        _infoRow('Frequency', entry.frequency?.toString()),
        _infoRow('Radical', entry.radical),
        if (entry.similarKanji.isNotEmpty)
          _infoRow('Similar', entry.similarKanji.join('  ')),
      ],
    );
  }

  Widget _infoRow(String label, String? value) {
    if (value == null || value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: AppText.detailLabel)),
          Expanded(child: Text(value, style: AppText.detailValue)),
        ],
      ),
    );
  }

  Widget _compoundsSection(Term entry) {
    final compounds = entry.compounds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Compounds'),
        if (compounds.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: Text('No compounds yet', style: AppText.emptyState),
          )
        else
          ...compounds.asMap().entries.map((entryMap) {
            final isLast = entryMap.key == compounds.length - 1;
            return _compoundRow(compound: entryMap.value, showDivider: !isLast);
          }),
      ],
    );
  }

  Widget _compoundRow({
    required KanjiCompound compound,
    required bool showDivider,
  }) {
    final canOpen = compound.termId != null;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: canOpen ? () => openCompound(compound) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      compound.kanji,
                      style: AppText.cardTitle.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '【${compound.reading}】 ${compound.meaning}',
                      style: AppText.detailValue,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 28,
                    color: canOpen ? Colors.grey : dividerColor,
                  ),
                ],
              ),
              if (showDivider)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Divider(height: 1, thickness: 1, color: dividerColor),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      width: double.infinity,
      color: sectionColor,
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Text(title, style: AppText.cardTitle),
    );
  }

  Widget _topActionButton({
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: GakujiTopBar.buttonSize,
      height: GakujiTopBar.buttonSize,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, size: 28, color: iconColor),
        ),
      ),
    );
  }
}
