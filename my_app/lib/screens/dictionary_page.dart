import 'dart:async';

import 'package:flutter/material.dart';

import '../data/recent_searches.dart';
import '../models/term.dart';
import '../models/writing_point.dart';
import '../services/dictionary_service.dart';
import '../services/writing_recognition_service.dart';
import '../widgets/gakuji_top_bar.dart';
import 'dictionary_detail_page.dart';

enum DictionaryInputMode {
  keyboard,
  writing,
}

class DictionaryPage extends StatefulWidget {
  final ValueChanged<bool>? onHandwritingInputActive;

  const DictionaryPage({
    super.key,
    this.onHandwritingInputActive,
  });

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  static const Color accentGreen = Color(0xFF2E7D32);

  final TextEditingController searchController = TextEditingController();

  Timer? searchDebounce;

  String searchText = '';
  String handwritingResult = '';

  DictionaryInputMode inputMode = DictionaryInputMode.keyboard;

  final List<List<WritingPoint>> handwritingStrokes = [];
  List<Term> searchResults = [];

  bool isRecognizingHandwriting = false;
  bool isDictionaryLoading = true;
  bool isSearchingDictionary = false;
  bool isHandwritingInputActive = false;

  int searchRequestNumber = 0;

  bool get hasHandwritingInput {
    return handwritingStrokes.any((stroke) => stroke.isNotEmpty);
  }

  @override
  void initState() {
    super.initState();
    loadDictionary();
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    setHandwritingInputActive(false);
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadDictionary() async {
    await DictionaryService.loadDictionary();

    if (!mounted) return;

    setState(() {
      isDictionaryLoading = false;
    });
  }

  void setHandwritingInputActive(bool active) {
    if (isHandwritingInputActive == active) return;

    isHandwritingInputActive = active;
    widget.onHandwritingInputActive?.call(active);
  }

  void updateSearchText(
    String value, {
    bool clearHandwritingResult = true,
  }) {
    setState(() {
      searchText = value;

      if (clearHandwritingResult) {
        handwritingResult = '';
      }
    });

    scheduleDictionarySearch(value);
  }

  void scheduleDictionarySearch(String rawQuery) {
    searchDebounce?.cancel();

    final query = rawQuery.trim();

    searchRequestNumber++;

    if (query.isEmpty) {
      setState(() {
        searchResults = [];
        isSearchingDictionary = false;
      });

      return;
    }

    setState(() {
      searchResults = [];
      isSearchingDictionary = true;
    });

    final requestNumber = searchRequestNumber;

    searchDebounce = Timer(
      const Duration(milliseconds: 280),
      () {
        searchDictionary(
          query: query,
          requestNumber: requestNumber,
        );
      },
    );
  }

  Future<void> searchDictionary({
    required String query,
    required int requestNumber,
  }) async {
    final results = await DictionaryService.search(query);

    if (!mounted) return;
    if (requestNumber != searchRequestNumber) return;
    if (query != searchText.trim()) return;

    setState(() {
      searchResults = results;
      isSearchingDictionary = false;
    });
  }

  void clearSearchState() {
    searchDebounce?.cancel();
    searchRequestNumber++;

    setState(() {
      searchController.clear();
      searchText = '';
      handwritingResult = '';
      searchResults = [];
      isSearchingDictionary = false;
    });
  }

  void addToRecentSearches(Term word) {
    searchDebounce?.cancel();
    searchRequestNumber++;

    setState(() {
      recentSearches.removeWhere(
        (recentWord) => recentWord.id == word.id,
      );

      recentSearches.insert(0, word);

      searchController.clear();
      searchText = '';
      handwritingResult = '';
      searchResults = [];
      isSearchingDictionary = false;
    });
  }

  void openDictionaryDetail(Term word) {
    setHandwritingInputActive(false);
    addToRecentSearches(word);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DictionaryDetailPage(word: word),
      ),
    );
  }

  void switchInputMode(DictionaryInputMode mode) {
    setState(() {
      inputMode = mode;
    });

    if (mode == DictionaryInputMode.keyboard) {
      setHandwritingInputActive(false);
    }

    if (mode == DictionaryInputMode.writing) {
      FocusScope.of(context).unfocus();
    }
  }

  void clearKeyboardSearch() {
    clearSearchState();
  }

  void addHandwritingPoint(
    Offset point, {
    bool isStart = false,
  }) {
    final writingPoint = WritingPoint.fromOffset(
      x: point.dx,
      y: point.dy,
      time: DateTime.now().millisecondsSinceEpoch,
    );

    if (isStart || handwritingStrokes.isEmpty) {
      handwritingStrokes.add(<WritingPoint>[writingPoint]);
    } else {
      handwritingStrokes.last.add(writingPoint);
    }
  }

  void clearHandwritingBox() {
    setHandwritingInputActive(false);
    searchDebounce?.cancel();
    searchRequestNumber++;

    setState(() {
      handwritingStrokes.clear();
      handwritingResult = '';
      searchController.clear();
      searchText = '';
      searchResults = [];
      isSearchingDictionary = false;
    });
  }

  Future<void> recognizeHandwritingSearch() async {
    if (isRecognizingHandwriting) return;

    if (!hasHandwritingInput) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Write in the box first'),
        ),
      );

      return;
    }

    setState(() {
      isRecognizingHandwriting = true;
      handwritingResult = '';
    });

    final recognizedCharacter = await WritingRecognitionService.recognizeSlot(
      slotStrokes: handwritingStrokes,
      mockCharacter: '',
    );

    if (!mounted) return;

    if (recognizedCharacter.isEmpty) {
      setState(() {
        isRecognizingHandwriting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not recognize that character. Try again.'),
        ),
      );

      return;
    }

    setHandwritingInputActive(false);

    setState(() {
      handwritingResult = recognizedCharacter;
      searchText = recognizedCharacter;

      searchController.value = TextEditingValue(
        text: recognizedCharacter,
        selection: TextSelection.collapsed(
          offset: recognizedCharacter.length,
        ),
      );

      isRecognizingHandwriting = false;
    });

    scheduleDictionarySearch(recognizedCharacter);
  }

  @override
  Widget build(BuildContext context) {
    final query = searchText.trim();
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
                    _inputModeSelector(),
                    const SizedBox(height: 12),
                    if (inputMode == DictionaryInputMode.keyboard)
                      _keyboardSearchBar()
                    else
                      _handwritingSearchBox(),
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
                      Expanded(
                        child: Center(
                          child: Text(
                            isDictionaryLoading
                                ? 'Loading dictionary...'
                                : 'Search for a word',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else if (query.isNotEmpty &&
                        isSearchingDictionary &&
                        searchResults.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Searching...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else if (query.isNotEmpty &&
                        !isSearchingDictionary &&
                        searchResults.isEmpty)
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
                        child: ListView.separated(
                          padding: EdgeInsets.only(
                            top: query.isEmpty ? 6 : 0,
                          ),
                          itemCount: wordsToShow.length,
                          separatorBuilder: (context, index) {
                            return const Divider(
                              height: 1,
                              thickness: 1,
                              color: Color(0xFFC8C8C8),
                            );
                          },
                          itemBuilder: (context, index) {
                            final word = wordsToShow[index];

                            return _DictionaryTermTile(
                              word: word,
                              onTap: () => openDictionaryDetail(word),
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

  Widget _inputModeSelector() {
    return Row(
      children: [
        Expanded(
          child: _inputModeButton(
            label: 'Keyboard',
            icon: Icons.keyboard_alt_outlined,
            mode: DictionaryInputMode.keyboard,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _inputModeButton(
            label: 'Writing',
            icon: Icons.draw_outlined,
            mode: DictionaryInputMode.writing,
          ),
        ),
      ],
    );
  }

  Widget _inputModeButton({
    required String label,
    required IconData icon,
    required DictionaryInputMode mode,
  }) {
    final isSelected = inputMode == mode;

    return Material(
      color: isSelected ? accentGreen : const Color(0xFFEDEDED),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => switchInputMode(mode),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: isSelected ? Colors.white : Colors.black,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyboardSearchBar() {
    return Container(
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
              onChanged: updateSearchText,
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
              onPressed: clearKeyboardSearch,
            ),
        ],
      ),
    );
  }

  Widget _handwritingSearchBox() {
    return Column(
      children: [
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFD8D8D8),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) {
                    setHandwritingInputActive(true);
                  },
                  onPanDown: (_) {
                    setHandwritingInputActive(true);
                  },
                  onPanStart: (details) {
                    setHandwritingInputActive(true);

                    final box = context.findRenderObject() as RenderBox;
                    final point = box.globalToLocal(
                      details.globalPosition,
                    );

                    setState(() {
                      addHandwritingPoint(
                        point,
                        isStart: true,
                      );
                    });
                  },
                  onPanUpdate: (details) {
                    final box = context.findRenderObject() as RenderBox;
                    final point = box.globalToLocal(
                      details.globalPosition,
                    );

                    setState(() {
                      addHandwritingPoint(point);
                    });
                  },
                  child: CustomPaint(
                    painter: _HandwritingSearchPainter(
                      strokes: handwritingStrokes,
                      showGrid: true,
                    ),
                    child: Center(
                      child: handwritingStrokes.isEmpty
                          ? const Text(
                              'Write here',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            )
                          : const SizedBox.expand(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton(
              onPressed: hasHandwritingInput && !isRecognizingHandwriting
                  ? clearHandwritingBox
                  : null,
              child: const Text(
                'Clear',
                style: TextStyle(
                  fontSize: 16,
                  color: accentGreen,
                ),
              ),
            ),
            const Spacer(),
            if (handwritingResult.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  'Recognized: $handwritingResult',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.grey,
                  ),
                ),
              ),
            ElevatedButton(
              onPressed: hasHandwritingInput && !isRecognizingHandwriting
                  ? recognizeHandwritingSearch
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentGreen,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: Text(
                isRecognizingHandwriting ? 'Checking...' : 'Search',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DictionaryTermTile extends StatelessWidget {
  static const Color accentGreen = Color(0xFF2E7D32);

  final Term word;
  final VoidCallback onTap;

  const _DictionaryTermTile({
    required this.word,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 10,
                runSpacing: 0,
                children: [
                  Text(
                    word.kanji,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    '【${word.reading}】',
                    style: const TextStyle(
                      fontSize: 19,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: accentGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                word.meaning,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HandwritingSearchPainter extends CustomPainter {
  final List<List<WritingPoint>> strokes;
  final bool showGrid;

  const _HandwritingSearchPainter({
    required this.strokes,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = const Color(0xFFD8D8D8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final grid = Paint()
      ..color = const Color(0xFFE3E3E3)
      ..strokeWidth = 1;

    final pen = Paint()
      ..color = Colors.black
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      border,
    );

    if (showGrid) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        grid,
      );

      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        grid,
      );
    }

    for (final stroke in strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(
          Offset(stroke[i].x, stroke[i].y),
          Offset(stroke[i + 1].x, stroke[i + 1].y),
          pen,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HandwritingSearchPainter oldDelegate) {
    return true;
  }
}