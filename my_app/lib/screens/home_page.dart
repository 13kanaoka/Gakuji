import 'package:flutter/material.dart';

import '../data/deck_data.dart';
import '../data/pinned_deck_data.dart';
import '../data/review_card_data.dart';
import '../models/deck.dart';
import '../models/review_card.dart';
import '../services/gakuji_user_data_store.dart';
import '../widgets/gakuji_deck_card.dart';
import '../widgets/gakuji_faded_scroll.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_todo_deck_card.dart';
import '../widgets/gakuji_top_bar.dart';
import 'deck_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  static const Color outlineGray = Color(0xFFD8D8D8);

  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool dataLoaded = false;

  int todoPageIndex = 0;
  int pinnedPageIndex = 0;

  @override
  void initState() {
    super.initState();
    loadState();
  }

  Future<void> loadState() async {
    await loadReviewCards();

    if (!mounted) return;

    setState(() {
      dataLoaded = true;
    });
  }

  void scheduleUserDataSave() {
    GakujiUserDataStore.scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    final todoDecks = _todoDecks();
    final pinnedDecks = _visiblePinnedDecks(todoDecks);

    final todoPages = _chunkDecks(todoDecks, 2);
    final pinnedPages = _chunkDecks(pinnedDecks, 2);

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: Column(
        children: [
          _homeHeader(context),
          Expanded(
            child: dataLoaded
                ? GakujiFadedScroll.withBottomNavigation(
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('To do'),
                          const SizedBox(height: 12),
                          if (todoDecks.isEmpty)
                            _emptySectionText('No Review decks due today')
                          else
                            _pagedTodoDecks(todoPages),
                          const SizedBox(height: 18),
                          _sectionTitle('Pinned'),
                          const SizedBox(height: 12),
                          if (pinnedDecks.isEmpty)
                            _emptySectionText('No pinned decks yet')
                          else
                            _pagedPinnedDecks(pinnedPages),
                        ],
                      ),
                    ),
                  )
                : Center(
                    child: CircularProgressIndicator(
                      color: GakujiColors.darkGray,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _homeHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GakujiTopBar(
            leftIcon: Icons.settings,
            leftIconSize: 30,
            leftIconColor: GakujiColors.darkGray,
            onLeftTap: _openSettingsPage,
            title: 'Home',
            titleStyle: GakujiText.large.copyWith(
              color: GakujiColors.darkGray,
            ),
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  void _openSettingsPage() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return const SettingsPage();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slideAnimation = Tween<Offset>(
            begin: const Offset(-1.0, 0.0),
            end: Offset.zero,
          ).chain(
            CurveTween(curve: Curves.easeOutCubic),
          );

          return SlideTransition(
            position: animation.drive(slideAnimation),
            child: child,
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      textScaler: TextScaler.noScaling,
      style: GakujiText.medium.copyWith(
        color: GakujiColors.darkGray,
      ),
    );
  }

  Widget _pagedTodoDecks(List<List<Deck>> pages) {
    final firstPageCount = pages.isEmpty ? 0 : pages.first.length;
    final pageHeight = firstPageCount <= 1 ? 150.0 : 330.0;

    return Column(
      children: [
        SizedBox(
          height: pageHeight,
          child: PageView.builder(
            clipBehavior: Clip.none,
            itemCount: pages.length,
            onPageChanged: (index) {
              setState(() {
                todoPageIndex = index;
              });
            },
            itemBuilder: (context, pageIndex) {
              final pageDecks = pages[pageIndex];

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < pageDecks.length; i++) ...[
                      _todoDeckCard(
                        context: context,
                        deck: pageDecks[i],
                      ),
                      if (i != pageDecks.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        if (pages.length > 1) ...[
          const SizedBox(height: 8),
          _pageDots(
            count: pages.length,
            activeIndex: todoPageIndex,
          ),
        ],
      ],
    );
  }

  Widget _pagedPinnedDecks(List<List<Deck>> pages) {
    final firstPageCount = pages.isEmpty ? 0 : pages.first.length;
    final pageHeight = firstPageCount <= 1 ? 108.0 : 220.0;

    return Column(
      children: [
        SizedBox(
          height: pageHeight,
          child: PageView.builder(
            clipBehavior: Clip.none,
            itemCount: pages.length,
            onPageChanged: (index) {
              setState(() {
                pinnedPageIndex = index;
              });
            },
            itemBuilder: (context, pageIndex) {
              final pageDecks = pages[pageIndex];

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < pageDecks.length; i++) ...[
                      _deckCard(
                        context: context,
                        deck: pageDecks[i],
                      ),
                      if (i != pageDecks.length - 1)
                        const SizedBox(height: 4),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        if (pages.length > 1) ...[
          const SizedBox(height: 8),
          _pageDots(
            count: pages.length,
            activeIndex: pinnedPageIndex,
          ),
        ],
      ],
    );
  }

  Widget _pageDots({
    required int count,
    required int activeIndex,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == activeIndex;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: active ? 10 : 8,
          height: active ? 10 : 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: active
                ? GakujiColors.darkGray
                : GakujiColors.mediumGray.withOpacity(0.35),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }

  Widget _todoDeckCard({
    required BuildContext context,
    required Deck deck,
  }) {
    return GakujiTodoDeckCard(
      deck: deck,
      newCount: 10,
      learningCount: 10,
      reviewCount: 10,
      isPinned: isDeckPinned(deck),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DeckPage(deck: deck),
          ),
        );

        await loadReviewCards();

        if (!mounted) return;

        setState(() {});
        scheduleUserDataSave();
      },
    );
  }

  Widget _deckCard({
    required BuildContext context,
    required Deck deck,
  }) {
    return GakujiDeckCard(
      title: deck.name,
      subtitle: _deckTypeLabel(deck.type),
      watermark: _watermarkForDeckType(deck.type),
      watermarkAssetPath: _watermarkAssetForDeckType(deck.type),
      patternAssetPath: _patternAssetForDeckType(deck.type),
      isPinned: isDeckPinned(deck),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DeckPage(deck: deck),
          ),
        );

        await loadReviewCards();

        if (!mounted) return;

        setState(() {});
        scheduleUserDataSave();
      },
    );
  }

  Widget _emptySectionText(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        text,
        textScaler: TextScaler.noScaling,
        style: GakujiText.small.copyWith(
          color: GakujiColors.mediumGray,
        ),
      ),
    );
  }

  List<Deck> _todoDecks() {
    return decks.take(3).toList();
  }

  List<Deck> _visiblePinnedDecks(List<Deck> todoDecks) {
    final todoDeckIds = todoDecks.map((deck) => deck.id).toSet();

    return pinnedDecksFrom(decks).where((deck) {
      return !todoDeckIds.contains(deck.id);
    }).toList();
  }

  List<List<Deck>> _chunkDecks(List<Deck> sourceDecks, int chunkSize) {
    final chunks = <List<Deck>>[];

    for (var i = 0; i < sourceDecks.length; i += chunkSize) {
      final end = (i + chunkSize > sourceDecks.length)
          ? sourceDecks.length
          : i + chunkSize;

      chunks.add(sourceDecks.sublist(i, end));
    }

    return chunks;
  }

  int _reviewCountForState(
    List<ReviewCard> cards,
    ReviewCardState state,
  ) {
    return cards.where((card) => card.state == state).length;
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

  String _patternAssetForDeckType(DeckType type) {
    switch (type) {
      case DeckType.writing:
        return 'assets/images/deck_pattern_writing.png';
      case DeckType.reading:
        return 'assets/images/deck_pattern_reading.png';
      case DeckType.hybrid:
        return 'assets/images/deck_pattern_hybrid.png';
    }
  }
}