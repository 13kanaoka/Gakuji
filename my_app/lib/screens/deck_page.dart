import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../data/dictionary_helpers.dart';
import '../services/deck_storage.dart';
import 'study_page.dart';
import 'deck_edit_page.dart';
import 'writing_study_page.dart';

class DeckPage extends StatefulWidget {
  final Deck deck;

  const DeckPage({super.key, required this.deck});

  @override
  State<DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<DeckPage> {
  bool showMenu = false;
  bool showStarredOnly = false;

  bool isShuffled = false;
  bool dataLoaded = false;

  int lastIndex = 0;

  List<Term> shuffledTerms = [];

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

      if (isShuffled) {
        shuffledTerms = getTermsFromDeck(widget.deck.termIds)..shuffle();
      }
    });
  }

  void toggleStar(Term term) {
    setState(() {
      term.marked = !term.marked;
    });
  }

  void toggleShuffle() async {
    setState(() {
      isShuffled = !isShuffled;

      if (isShuffled) {
        shuffledTerms = getTermsFromDeck(widget.deck.termIds)..shuffle();
      } else {
        shuffledTerms = [];
      }
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
    List<Term> studyTerms;

    if (showStarredOnly) {
      final starred = getTermsFromDeck(widget.deck.termIds)
          .where((t) => t.marked)
          .toList();

      studyTerms = isShuffled
          ? (List.from(starred)..shuffle())
          : starred;
    } else {
      studyTerms =
          isShuffled ? shuffledTerms : getTermsFromDeck(widget.deck.termIds);
    }

    if (widget.deck.type == DeckType.writing) {
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
            terms: studyTerms,
            deck: widget.deck,
          ),
        ),
      );
    }

    final updatedIndex =
        await DeckStorage.loadProgress(widget.deck.id);

    setState(() {
      lastIndex = updatedIndex;
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

    final List<Term> terms = getTermsFromDeck(widget.deck.termIds);

    final visibleTerms =
        showStarredOnly ? terms.where((t) => t.marked).toList() : terms;

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
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// TOP BAR
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFFBEBEBE),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_ios_new,
                                size: 20, color: Colors.black),
                          ),
                        ),
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFFBEBEBE),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              setState(() {
                                showMenu = !showMenu;
                              });
                            },
                            icon: const Icon(Icons.more_horiz,
                                color: Colors.black),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

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

                    /// 🔥 RESTORED METADATA SECTION
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

                    /// TOGGLE (kept animated feel intact via structure)
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
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFB8B8B8),
                                    borderRadius: BorderRadius.circular(6),
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
                                        onPressed: () => toggleStar(term),
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

              /// MENU (unchanged)
              if (showMenu)
                Positioned(
                  top: 70,
                  right: 22,
                  child: Container(
                    width: 220,
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
                        const Divider(),
                        InkWell(
                          onTap: toggleShuffle,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            child: const Row(
                              children: [
                                Icon(Icons.shuffle, color: Colors.grey),
                                SizedBox(width: 10),
                                Text('Shuffle'),
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
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pillButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Text(label),
      ),
    );
  }
}