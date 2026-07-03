import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/pinned_deck_data.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../services/deck_storage.dart';
import '../widgets/gakuji_top_bar.dart';
import 'deck_edit_page.dart';
import 'deck_term_list_page.dart';
import 'study_page.dart';
import 'writing_study_page.dart';

class DeckPage extends StatefulWidget {
  final Deck deck;

  const DeckPage({
    super.key,
    required this.deck,
  });

  @override
  State<DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<DeckPage> {
  static const Color deckBlue = Color(0xFF4D7EF7);
  static const Color metadataGray = Color(0xFF6F6F6F);
  static const Color dividerGray = Color(0xFFE1E1E1);
  static const Color pinRed = Color(0xFFFF4B4B);

  bool showMenu = false;
  bool showStarredOnly = false;

  bool isShuffled = false;
  bool showFurigana = true;
  bool termFirst = true;
  bool showWritingGrid = true;
  bool dataLoaded = false;

  bool isLargeStudyButtonPressed = false;
  bool isLargeStudyButtonTapLocked = false;

  int lastIndex = 0;

  bool get isWritingDeck => widget.deck.type == DeckType.writing;
  bool get usesReadingStudyOptions => !isWritingDeck;
  bool get deckIsPinned => isDeckPinned(widget.deck);

  String get writingGridPreferenceKey {
    return 'writing_grid_visible_${widget.deck.id}';
  }

  @override
  void initState() {
    super.initState();
    loadState();
  }

  Future<void> loadState() async {
    final savedIndex = await DeckStorage.loadProgress(widget.deck.id);
    final savedShuffle = await DeckStorage.loadShuffle(widget.deck.id);
    final prefs = await SharedPreferences.getInstance();
    final savedWritingGrid = prefs.getBool(writingGridPreferenceKey);

    if (!mounted) return;

    setState(() {
      lastIndex = savedIndex;
      isShuffled = savedShuffle;
      showWritingGrid = savedWritingGrid ?? true;
      dataLoaded = true;
    });
  }

  Future<void> saveWritingGridPreference() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      writingGridPreferenceKey,
      showWritingGrid,
    );
  }

  Future<void> openTermList() async {
    setState(() {
      showMenu = false;
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeckTermListPage(deck: widget.deck),
      ),
    );

    if (!mounted) return;

    setState(() {});
  }

  void togglePinnedDeck() {
    if (deckIsPinned) {
      setState(() {
        pinnedDeckIds.remove(widget.deck.id);
      });

      return;
    }

    if (!canPinMoreDecks()) {
      _showPinLimitMessage();
      return;
    }

    setState(() {
      pinnedDeckIds.add(widget.deck.id);
    });
  }

  void _showPinLimitMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1500),
          backgroundColor: Colors.black.withValues(alpha: 0.86),
          content: const Text(
            'You can pin up to 3 decks',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      );
  }

  void toggleStar(Term term) {
    setState(() {
      term.marked = !term.marked;
    });
  }

  void toggleStarredTermFilter() {
    setState(() {
      showStarredOnly = !showStarredOnly;
    });
  }

  Future<void> toggleShuffle() async {
    setState(() {
      isShuffled = !isShuffled;
    });

    await DeckStorage.saveShuffle(widget.deck.id, isShuffled);
  }

  void toggleWritingGrid() {
    if (!isWritingDeck) return;

    setState(() {
      showWritingGrid = !showWritingGrid;
    });

    saveWritingGridPreference();
  }

  Future<void> resetDeck() async {
    setState(() {
      showMenu = false;
      lastIndex = 0;
    });

    await DeckStorage.saveProgress(widget.deck.id, 0);
  }

  Future<void> openStudy() async {
    final baseStudyTerms = showStarredOnly
        ? widget.deck.terms.where((term) => term.marked).toList()
        : List<Term>.from(widget.deck.terms);

    if (widget.deck.type == DeckType.writing) {
      final studyTerms = isShuffled
          ? (List<Term>.from(baseStudyTerms)..shuffle())
          : baseStudyTerms;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WritingStudyPage(
            terms: studyTerms,
            deck: widget.deck,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StudyPage(
            terms: baseStudyTerms,
            deck: widget.deck,
            initialIsShuffled: isShuffled,
            initialShowFurigana: showFurigana,
            initialTermFirst: termFirst,
          ),
        ),
      );
    }

    final updatedIndex = await DeckStorage.loadProgress(widget.deck.id);

    if (!mounted) return;

    setState(() {
      lastIndex = updatedIndex;
    });
  }

  void setLargeStudyButtonPressed(bool value) {
    if (!mounted || isLargeStudyButtonPressed == value) return;

    setState(() {
      isLargeStudyButtonPressed = value;
    });
  }

  Future<void> handleLargeStudyButtonTap() async {
    if (isLargeStudyButtonTapLocked) return;

    isLargeStudyButtonTapLocked = true;
    setLargeStudyButtonPressed(true);

    await Future.delayed(const Duration(milliseconds: 75));

    if (!mounted) return;

    setLargeStudyButtonPressed(false);

    await Future.delayed(const Duration(milliseconds: 35));

    if (!mounted) return;

    isLargeStudyButtonTapLocked = false;
    await openStudy();
  }

  void toggleFurigana() {
    setState(() {
      showFurigana = !showFurigana;
    });
  }

  void toggleCardOrientation() {
    setState(() {
      termFirst = !termFirst;
    });
  }

  Future<void> openDeckEdit() async {
    setState(() {
      showMenu = false;
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeckEditPage(deck: widget.deck),
      ),
    );

    if (!mounted) return;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!dataLoaded) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final terms = widget.deck.terms;

    final visibleTerms =
        showStarredOnly ? terms.where((term) => term.marked).toList() : terms;

    final hasProgress = lastIndex > 0;
    final studyButtonText = hasProgress ? 'Resume' : 'Study';

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (showMenu) {
            setState(() => showMenu = false);
          }
        },
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  GakujiTopBar(
                    leftIcon: Icons.arrow_back_ios_new,
                    onLeftTap: () => Navigator.pop(context),
                    title: '',
                    showOptionsButton: true,
                    optionsSelected: showMenu,
                    onOptionsTap: () {
                      setState(() => showMenu = !showMenu);
                    },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _deckHeader(
                            termsCount: terms.length,
                            smallButtonText: 'Study',
                          ),
                          Transform.translate(
                            offset: const Offset(0, -16),
                            child: Center(
                              child: _largeStudyButton(studyButtonText),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: visibleTerms.isEmpty
                                ? Center(
                                    child: Text(
                                      showStarredOnly
                                          ? 'No starred terms yet'
                                          : 'No terms yet',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 16,
                                      ),
                                    ),
                                  )
                                : _fadedTermList(visibleTerms),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (showMenu) _menuOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deckHeader({
    required int termsCount,
    required String smallButtonText,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.deck.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    fontSize: 38,
                    height: 0.95,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.1,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                _metadataText('Created by: You'),
                const SizedBox(height: 3),
                _metadataText(_deckTypeLabel(widget.deck.type)),
                const SizedBox(height: 3),
                _metadataText('Terms: $termsCount'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 18),
        _smallStudyButton(smallButtonText),
      ],
    );
  }

  Widget _metadataText(String text) {
    return Text(
      text,
      textScaler: TextScaler.noScaling,
      style: const TextStyle(
        fontSize: 16,
        height: 1.08,
        fontWeight: FontWeight.w400,
        color: metadataGray,
      ),
    );
  }

  Widget _smallStudyButton(String label) {
    return Container(
      width: 86,
      height: 44,
      decoration: BoxDecoration(
        color: deckBlue.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: deckBlue,
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 0,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openStudy,
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _largeStudyButton(String label) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setLargeStudyButtonPressed(true),
      onTapCancel: () => setLargeStudyButtonPressed(false),
      onTap: handleLargeStudyButtonTap,
      child: AnimatedContainer(
        width: 190,
        height: 190,
        duration: const Duration(milliseconds: 55),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          0,
          isLargeStudyButtonPressed ? 8 : 0,
          0,
        ),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: isLargeStudyButtonPressed
              ? const []
              : const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 0,
                    offset: Offset(0, 8),
                  ),
                ],
        ),
        child: Material(
          color: const Color(0xD64D7EF7),
          shape: const CircleBorder(
            side: BorderSide(
              color: deckBlue,
              width: 5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                fontSize: 46,
                fontWeight: FontWeight.w400,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fadedTermList(List<Term> visibleTerms) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00000000),
            Colors.black,
            Colors.black,
            Color(0x00000000),
          ],
          stops: [
            0.0,
            0.06,
            0.92,
            1.0,
          ],
        ).createShader(bounds);
      },
      child: _termList(visibleTerms),
    );
  }

  Widget _termList(List<Term> visibleTerms) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: visibleTerms.length,
      separatorBuilder: (context, index) {
        return const Divider(
          height: 1,
          thickness: 1,
          color: Color(0xFFC8C8C8),
        );
      },
      itemBuilder: (context, index) {
        final term = visibleTerms[index];

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 10,
                      runSpacing: 0,
                      children: [
                        Text(
                          term.kanji,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          '【${term.reading}】',
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontSize: 19,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            color: deckBlue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      term.meaning,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.1,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  term.marked ? Icons.star : Icons.star_border,
                  color: term.marked ? deckBlue : const Color(0xFFC8C8C8),
                ),
                onPressed: () => toggleStar(term),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _menuOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                showMenu = false;
              });
            },
            child: Container(
              color: Colors.transparent,
            ),
          ),
          Positioned(
            top: 58,
            right: 22,
            child: _deckMenuCard(),
          ),
        ],
      ),
    );
  }

  Widget _deckMenuCard() {
    return Container(
      width: 258,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 0,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _menuItem(
            icon: Icons.edit,
            label: 'Edit Deck',
            onTap: openDeckEdit,
          ),
          const Divider(height: 1, color: dividerGray),
          _menuItem(
            icon: Icons.format_list_bulleted_rounded,
            label: 'View Term List',
            iconColor: Colors.black,
            onTap: openTermList,
          ),
          const Divider(height: 1, color: dividerGray),
          _menuItem(
            icon: Icons.push_pin,
            label: deckIsPinned ? 'Unpin Deck' : 'Pin Deck',
            iconColor: deckIsPinned ? pinRed : Colors.grey,
            onTap: togglePinnedDeck,
          ),
          const Divider(height: 1, color: dividerGray),
          _menuItem(
            icon: showStarredOnly ? Icons.star : Icons.star_border,
            label: showStarredOnly ? 'Starred terms only' : 'All terms',
            iconColor: showStarredOnly ? deckBlue : Colors.grey,
            onTap: toggleStarredTermFilter,
          ),
          const Divider(height: 1, color: dividerGray),
          if (isWritingDeck) ...[
            _menuItem(
              icon: showWritingGrid ? Icons.visibility : Icons.visibility_off,
              label: showWritingGrid ? 'Hide Grid' : 'Show Grid',
              iconColor: showWritingGrid ? Colors.black : Colors.grey,
              onTap: toggleWritingGrid,
            ),
            const Divider(height: 1, color: dividerGray),
          ],
          if (usesReadingStudyOptions) ...[
            _textMenuItem(
              textIcon: 'あ',
              label: showFurigana ? 'Hide Furigana' : 'Show Furigana',
              iconColor: showFurigana ? Colors.black : Colors.grey,
              onTap: toggleFurigana,
            ),
            const Divider(height: 1, color: dividerGray),
            _menuItem(
              icon: Icons.swap_horiz,
              label: termFirst ? 'Term First' : 'Definition First',
              iconColor: termFirst ? Colors.grey : Colors.black,
              onTap: toggleCardOrientation,
            ),
            const Divider(height: 1, color: dividerGray),
          ],
          _menuItem(
            customIcon: _ShuffleMenuIcon(
              color: isShuffled ? Colors.black : Colors.grey,
            ),
            label: isShuffled ? 'Shuffled' : 'Unshuffled',
            onTap: toggleShuffle,
          ),
          const Divider(height: 1, color: dividerGray),
          _menuItem(
            icon: Icons.refresh,
            label: 'Reset Deck',
            iconColor: Colors.grey,
            onTap: resetDeck,
          ),
        ],
      ),
    );
  }

  Widget _menuItem({
    IconData? icon,
    Widget? customIcon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.black,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Center(
                child: customIcon ??
                    Icon(
                      icon,
                      color: iconColor,
                      size: 24,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textMenuItem({
    required String textIcon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.black,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Center(
                child: Text(
                  textIcon,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: iconColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
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
}

class _ShuffleMenuIcon extends StatelessWidget {
  const _ShuffleMenuIcon({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/shuffle_menu_icon.png',
      width: 24,
      height: 24,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.shuffle,
          size: 24,
          color: color,
        );
      },
    );
  }
}