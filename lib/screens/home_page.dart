import 'package:flutter/material.dart';

import '../data/deck_data.dart';
import '../data/pinned_deck_data.dart';
import '../models/deck.dart';
import '../theme/app_text_styles.dart';
import '../widgets/gakuji_deck_card.dart';
import 'deck_page.dart';

class HomePage extends StatefulWidget {
  static const Color deckBlue = Color(0xFF4D7EF7);
  static const Color outlineGray = Color(0xFFD8D8D8);

  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final dailyDecks = decks.take(3).toList();
    final pinnedDecks = pinnedDecksFrom(decks);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _homeHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Daily'),
                  const SizedBox(height: 16),
                  if (dailyDecks.isEmpty)
                    _emptySectionText('No daily decks yet')
                  else
                    Column(
                      children: [
                        for (final deck in dailyDecks) ...[
                          _deckCard(context: context, deck: deck),
                          const SizedBox(height: 18),
                        ],
                      ],
                    ),
                  const SizedBox(height: 12),
                  _sectionTitle('Pinned'),
                  const SizedBox(height: 16),
                  if (pinnedDecks.isEmpty)
                    _emptySectionText('No pinned decks yet')
                  else
                    Column(
                      children: [
                        for (final deck in pinnedDecks) ...[
                          _deckCard(context: context, deck: deck),
                          const SizedBox(height: 18),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeHeader(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      height: topInset + 58,
      color: HomePage.deckBlue,
      padding: EdgeInsets.fromLTRB(28, topInset + 18, 28, 18),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Text(
            'Home',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: AppText.pageTitle,
          ),
          Align(alignment: Alignment.centerRight, child: _settingsButton()),
        ],
      ),
    );
  }

  Widget _settingsButton() {
    return Transform.translate(
      offset: const Offset(8, 0),
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        icon: const Icon(Icons.settings, color: Colors.white, size: 22),
        onPressed: () {
          // TODO: Settings page
        },
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      textScaler: TextScaler.noScaling,
      style: AppText.sectionTitle,
    );
  }

  Widget _deckCard({required BuildContext context, required Deck deck}) {
    return GakujiDeckCard(
      title: deck.name,
      subtitle: _deckTypeLabel(deck.type),
      watermark: _watermarkForDeckType(deck.type),
      watermarkAssetPath: _watermarkAssetForDeckType(deck.type),
      isPinned: isDeckPinned(deck),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => DeckPage(deck: deck)),
        );

        if (!mounted) return;

        setState(() {});
      },
    );
  }

  Widget _emptySectionText(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        text,
        textScaler: TextScaler.noScaling,
        style: AppText.emptyState,
      ),
    );
  }

  String _deckTypeLabel(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'Writing';
      case DeckType.reading:
        return 'Reading';
      case DeckType.hybrid:
        return 'Hybrid';
    }
  }

  String _watermarkForDeckType(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return '書';
      case DeckType.reading:
        return '読';
      case DeckType.hybrid:
        return '学';
    }
  }

  String _watermarkAssetForDeckType(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'assets/images/deck_watermark_3.png';
      case DeckType.reading:
        return 'assets/images/deck_watermark_2.png';
      case DeckType.hybrid:
        return 'assets/images/deck_watermark_1.png';
    }
  }
}
