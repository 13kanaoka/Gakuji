import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../models/term.dart';
import '../services/deck_storage.dart';
import '../widgets/gakuji_top_bar.dart';
import 'deck_edit_page.dart';
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
  bool showMenu = false;
  bool showStarredOnly = false;

  bool isShuffled = false;
  bool showFurigana = true;
  bool termFirst = true;
  bool dataLoaded = false;

  int lastIndex = 0;

  bool get usesReadingStudyOptions => widget.deck.type != DeckType.writing;

  @override
  void initState() {
    super.initState();
    loadState();
  }

  Future<void> loadState() async {
    final savedIndex = await DeckStorage.loadProgress(widget.deck.id);
    final savedShuffle = await DeckStorage.loadShuffle(widget.deck.id);

    setState(() {
      lastIndex = savedIndex;
      isShuffled = savedShuffle;
      dataLoaded = true;
    });
  }

  void toggleStar(Term term) {
    setState(() {
      term.marked = !term.marked;
    });
  }

  Future<void> toggleShuffle() async {
    setState(() {
      isShuffled = !isShuffled;
      showMenu = false;
    });

    await DeckStorage.saveShuffle(widget.deck.id, isShuffled);
  }

  Future<void> resetDeck() async {
    setState(() {
      lastIndex = 0;
      showMenu = false;
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

  void toggleFurigana() {
    setState(() {
      showFurigana = !showFurigana;
      showMenu = false;
    });
  }

  void toggleCardOrientation() {
    setState(() {
      termFirst = !termFirst;
      showMenu = false;
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
        backgroundColor: Color(0xFFD0D0D0),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final List<Term> terms = widget.deck.terms;

    final visibleTerms =
        showStarredOnly ? terms.where((term) => term.marked).toList() : terms;

    final hasProgress = lastIndex > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFD0D0D0),
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
                crossAxisAlignment: CrossAxisAlignment.start,
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

                  const SizedBox(height: 18),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          /// HEADER + REVIEW BUTTON
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.deck.name,
                                  style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () {},
                                child: const Text('Review'),
                              ),
                            ],
                          ),

                          /// METADATA SECTION
                          const SizedBox(height: 6),
                          const Text(
                            'Created by: Name',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            widget.deck.type.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            'Terms: ${terms.length}',
                            style: const TextStyle(fontSize: 14),
                          ),

                          const SizedBox(height: 20),

                          /// BIG BUTTON
                          Center(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(100),
                              onTap: openStudy,
                              child: Container(
                                width: 155,
                                height: 155,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFB8B8B8),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    hasProgress ? 'Resume' : 'Study',
                                    style: const TextStyle(
                                      fontSize: 46,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          /// TOGGLE
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _pillButton('All', !showStarredOnly, () {
                                    setState(() => showStarredOnly = false);
                                  }),
                                  _pillButton('Starred', showStarredOnly, () {
                                    setState(() => showStarredOnly = true);
                                  }),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          /// LIST
                          Expanded(
                            child: visibleTerms.isEmpty
                                ? const Center(child: Text('No terms yet'))
                                : ListView.builder(
                                    itemCount: visibleTerms.length,
                                    itemBuilder: (context, index) {
                                      final term = visibleTerms[index];

                                      return Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFB8B8B8),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(term.kanji),
                                                  Text(term.reading),
                                                  Text(term.meaning),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                term.marked
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                color: term.marked
                                                    ? Colors.blue
                                                    : Colors.white,
                                              ),
                                              onPressed: () =>
                                                  toggleStar(term),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
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

  Widget _menuOverlay() {
    return Positioned(
      top: 70,
      right: 22,
      child: Container(
        width: 240,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: openDeckEdit,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.edit),
                    SizedBox(width: 10),
                    Text('Edit Deck'),
                  ],
                ),
              ),
            ),
            if (usesReadingStudyOptions) ...[
              const Divider(),
              InkWell(
                onTap: toggleFurigana,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Text(
                        'あ',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: showFurigana ? Colors.black : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        showFurigana ? 'Hide Furigana' : 'Show Furigana',
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              InkWell(
                onTap: toggleCardOrientation,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swap_horiz,
                        color: termFirst ? Colors.black : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Card Orientation:'),
                            const SizedBox(height: 2),
                            Text(
                              termFirst ? 'Term -> Def.' : 'Def. -> Term',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const Divider(),
            InkWell(
              onTap: toggleShuffle,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.shuffle,
                      color: isShuffled ? Colors.black : Colors.grey,
                    ),
                    const SizedBox(width: 10),
                    Text(isShuffled ? 'Unshuffle' : 'Shuffle'),
                  ],
                ),
              ),
            ),
            const Divider(),
            InkWell(
              onTap: resetDeck,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.grey),
                    SizedBox(width: 10),
                    Text('Reset Deck'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label),
      ),
    );
  }
}