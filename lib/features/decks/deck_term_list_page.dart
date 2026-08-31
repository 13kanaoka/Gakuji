import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';

import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/core/widgets/gakuji_search_bar.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_term_row.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/features/dictionary/dictionary_detail_page.dart';
import 'package:gakuji/features/auth/widgets/gakuji_action_dialog.dart';
import 'package:gakuji/features/import/services/deck_code_service.dart';

class DeckTermListPage extends StatefulWidget {
  final Deck deck;

  const DeckTermListPage({
    super.key,
    required this.deck,
  });

  @override
  State<DeckTermListPage> createState() => _DeckTermListPageState();
}

class _DeckTermListPageState extends State<DeckTermListPage> {
  static const Duration _headerCollapseDuration = Duration(milliseconds: 400);

  final TextEditingController searchController = TextEditingController();
  final ScrollController termsScrollController = ScrollController();

  String searchQuery = '';
  bool deckInfoCollapsed = false;
  bool isPreparingDeckCode = false;

  @override
  void initState() {
    super.initState();

    termsScrollController.addListener(handleTermListScroll);
  }

  @override
  void dispose() {
    searchController.dispose();
    termsScrollController.dispose();

    super.dispose();
  }

  void handleTermListScroll() {
    if (!termsScrollController.hasClients) return;

    final shouldCollapse = termsScrollController.offset > 14;

    if (deckInfoCollapsed == shouldCollapse) return;

    setState(() {
      deckInfoCollapsed = shouldCollapse;
    });
  }

  Future<void> _showDeckCodeDialog() async {
    if (isPreparingDeckCode) return;

    setState(() {
      isPreparingDeckCode = true;
    });

    try {
      final deckCode = await DeckCodeService.publishDeck(widget.deck);
      if (!mounted) return;

      final shouldCopy = await showGakujiActionDialog(
        context: context,
        title: 'Deck Code',
        message: deckCode,
        primaryLabel: 'Copy Code',
        secondaryLabel: 'Close',
        primaryColor: GakujiColors.reading,
        messageStyle: GakujiText.medium.copyWith(
          color: GakujiColors.darkGray,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      );

      if (!mounted || shouldCopy != true) return;

      await Clipboard.setData(ClipboardData(text: deckCode));

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1500),
            backgroundColor: Colors.black.withValues(alpha: 0.86),
            content: Text(
              'Deck code copied',
              textScaler: TextScaler.noScaling,
              style: GakujiText.snackBar,
            ),
          ),
        );
    } on DeckCodeException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 2200),
            backgroundColor: Colors.black.withValues(alpha: 0.86),
            content: Text(
              error.message,
              textScaler: TextScaler.noScaling,
              style: GakujiText.snackBar,
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          isPreparingDeckCode = false;
        });
      }
    }
  }

  List<Term> get visibleTerms {
    final normalizedQuery = searchQuery.trim().toLowerCase();

    if (normalizedQuery.isEmpty) {
      return widget.deck.terms;
    }

    return widget.deck.terms.where((term) {
      final titleText =
          term.kanjiBracketText.isNotEmpty ? term.kanjiBracketText : term.kanji;

      return titleText.toLowerCase().contains(normalizedQuery) ||
          term.kanji.toLowerCase().contains(normalizedQuery) ||
          term.reading.toLowerCase().contains(normalizedQuery) ||
          term.meaning.toLowerCase().contains(normalizedQuery) ||
          term.cardMeaning.toLowerCase().contains(normalizedQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final terms = visibleTerms;

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              GakujiTopBar(
                leftIcon: Icons.arrow_back_ios_new,
                leftIconSize: 25,
                leftIconColor: GakujiColors.darkGray,
                onLeftTap: () => Navigator.pop(context),
                title: 'Term List',
                titleStyle: GakujiText.pageTitle.copyWith(
                  color: GakujiColors.darkGray,
                ),
                rightIcon: Icons.ios_share_rounded,
                rightIconColor: isPreparingDeckCode
                    ? GakujiColors.softGray
                    : GakujiColors.darkGray,
                rightIconSize: 25,
                onRightTap:
                    isPreparingDeckCode ? null : _showDeckCodeDialog,
                showOptionsButton: false,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _collapsingDeckHeader(widget.deck.terms.length),
                      AnimatedContainer(
                        duration: _headerCollapseDuration,
                        curve: Curves.easeOutCubic,
                        height: deckInfoCollapsed ? 8 : 18,
                      ),
                      _searchBar(),
                      const SizedBox(height: 20),
                      Expanded(
                        child: terms.isEmpty
                            ? _emptyState()
                            : _termList(context, terms),
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

  Widget _collapsingDeckHeader(int termsCount) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: deckInfoCollapsed ? 0 : 1,
        end: deckInfoCollapsed ? 0 : 1,
      ),
      duration: _headerCollapseDuration,
      curve: Curves.easeOutCubic,
      child: _deckHeader(termsCount),
      builder: (context, value, child) {
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: value,
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.92 + (0.08 * value),
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _deckHeader(int termsCount) {
    final countLabel = termsCount == 1 ? '1 term' : '$termsCount terms';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.deck.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.pageTitle.copyWith(
              color: GakujiColors.darkGray,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            countLabel,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.deckMeta.copyWith(
              color: GakujiColors.mediumGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return GakujiSearchBar(
      controller: searchController,
      hintText: 'Search terms',
      showClearButton: searchQuery.isNotEmpty,
      onChanged: (value) {
        setState(() {
          searchQuery = value;
        });
      },
      onClear: () {
        setState(() {
          searchController.clear();
          searchQuery = '';
        });
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Text(
        searchQuery.trim().isEmpty ? 'No terms yet' : 'No terms found',
        textScaler: TextScaler.noScaling,
        style: GakujiText.body.copyWith(color: Colors.grey),
      ),
    );
  }

  Widget _termList(BuildContext context, List<Term> terms) {
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
            0.035,
            0.94,
            1.0,
          ],
        ).createShader(bounds);
      },
      child: ListView.separated(
        controller: termsScrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(
          top: 14,
          bottom: 140,
        ),
        itemCount: terms.length,
        separatorBuilder: (context, index) {
          return const Divider(
            height: 1,
            thickness: 1,
            color: GakujiTermRow.dividerColor,
          );
        },
        itemBuilder: (context, index) {
          final term = terms[index];

          final titleText = term.preferredSpelling.trim().isNotEmpty
              ? term.preferredSpelling.trim()
              : term.kanji.trim().isNotEmpty
                  ? term.kanji.trim()
                  : term.reading.trim();

          return GakujiTermRow(
            term: term,
            titleText: titleText,
            readingText: term.reading,
            onTap: () {
              Navigator.push(
                context,
                GakujiPageRoute(
                  builder: (context) => DictionaryDetailPage(word: term),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
