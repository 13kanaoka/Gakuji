import 'package:flutter/material.dart';

import '../data/dictionary_data.dart';
import '../data/recent_searches.dart';
import '../models/term.dart';
import '../widgets/gakuji_top_bar.dart';
import 'dictionary_detail_page.dart';

class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  final TextEditingController searchController = TextEditingController();

  String searchText = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void addToRecentSearches(Term word) {
    setState(() {
      recentSearches.removeWhere(
        (recentWord) => recentWord.id == word.id,
      );

      recentSearches.insert(0, word);

      searchController.clear();
      searchText = '';
    });
  }

  void openDictionaryDetail(Term word) {
    addToRecentSearches(word);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DictionaryDetailPage(word: word),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = searchText.trim().toLowerCase();

    final searchResults = query.isEmpty
        ? <Term>[]
        : dictionaryWords.where((word) {
            final kanji = word.kanji;
            final reading = word.reading;
            final meaning = word.meaning.toLowerCase();

            return kanji.contains(query) ||
                reading.contains(query) ||
                meaning.contains(query);
          }).toList();

    final wordsToShow = query.isEmpty ? recentSearches : searchResults;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            GakujiTopBar(
              title: 'Dictionary',
              titleStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: Colors.black,
              ),
            ),

            const SizedBox(height: 26),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 100),
                child: Column(
                  children: [
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDEDED),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: searchController,
                              onChanged: (value) {
                                setState(() {
                                  searchText = value;
                                });
                              },
                              decoration: const InputDecoration(
                                hintText: 'Search',
                                border: InputBorder.none,
                                isCollapsed: true,
                              ),
                            ),
                          ),
                          if (searchText.isNotEmpty)
                            IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                setState(() {
                                  searchController.clear();
                                  searchText = '';
                                });
                              },
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (query.isEmpty && recentSearches.isNotEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Recent Searches',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                    if (query.isEmpty && recentSearches.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Search for a word',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else if (query.isNotEmpty && searchResults.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'No results found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: wordsToShow.length,
                          itemBuilder: (context, index) {
                            final word = wordsToShow[index];

                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => openDictionaryDetail(word),
                              child: Container(
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEDEDED),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      word.kanji,
                                      style: const TextStyle(fontSize: 34),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(word.reading),
                                          Text(
                                            word.meaning,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
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
      ),
    );
  }
}