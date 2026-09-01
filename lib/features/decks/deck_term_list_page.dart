import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';

import 'package:gakuji/data/decks/deck_storage.dart';
import 'package:gakuji/data/review/review_card_data.dart';
import 'package:gakuji/data/sync/gakuji_user_data_store.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/domain/term.dart';
import 'package:gakuji/core/widgets/gakuji_search_bar.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_term_row.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/core/widgets/gakuji_compact_menu.dart';
import 'package:gakuji/features/decks/custom_card_edit_page.dart';
import 'package:gakuji/features/dictionary/dictionary_detail_page.dart';
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
  bool isExportingCsv = false;

  bool get isSharingOrExporting => isPreparingDeckCode || isExportingCsv;

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

  Future<void> _openCustomCardEditor(Term term) async {
    FocusScope.of(context).unfocus();

    final changed = await Navigator.push<bool>(
      context,
      GakujiPageRoute(
        builder: (context) => CustomCardEditPage(
          deck: widget.deck,
          term: term,
        ),
      ),
    );

    if (!mounted || changed != true) return;

    setState(() {
      searchController.clear();
      searchQuery = '';
      deckInfoCollapsed = false;
    });

    GakujiUserDataStore.scheduleSave();

    final reviewEnabled = await DeckStorage.loadReviewEnabled(widget.deck.id);
    if (reviewEnabled) {
      await createReviewCardsForDeck(widget.deck);
    }
  }

  Future<void> _downloadDeckCsv() async {
    if (isSharingOrExporting) return;

    setState(() {
      isExportingCsv = true;
    });

    try {
      final rows = <List<String>>[
        const ['Term', 'Reading', 'Meaning', 'Part of Speech', 'Note'],
        ...widget.deck.terms.map((term) {
          final writing = term.preferredSpelling.trim().isNotEmpty
              ? term.preferredSpelling.trim()
              : term.kanji.trim().isNotEmpty
                  ? term.kanji.trim()
                  : term.reading.trim();

          return <String>[
            writing,
            term.reading.trim(),
            term.cardMeaning.trim(),
            term.partOfSpeech.trim(),
            (term.note ?? '').trim(),
          ];
        }),
      ];

      final csvText = rows
          .map((row) => row.map(_escapeCsvField).join(','))
          .join('\r\n');
      final bytes = Uint8List.fromList(
        utf8.encode('\uFEFF$csvText'),
      );

      final output = await FilePicker.saveFile(
        dialogTitle: 'Download deck CSV',
        fileName: _deckCsvFileName(),
        bytes: bytes,
      );

      if (!mounted || output == null) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.fixed,
            duration: const Duration(milliseconds: 1500),
            backgroundColor: Colors.black.withValues(alpha: 0.86),
            content: Text(
              'Deck CSV downloaded',
              textScaler: TextScaler.noScaling,
              style: GakujiText.snackBar,
            ),
          ),
        );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.fixed,
            duration: const Duration(milliseconds: 2200),
            backgroundColor: Colors.black.withValues(alpha: 0.86),
            content: Text(
              'Could not download deck CSV',
              textScaler: TextScaler.noScaling,
              style: GakujiText.snackBar,
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          isExportingCsv = false;
        });
      }
    }
  }

  String _escapeCsvField(String value) {
    final escaped = value.replaceAll('\"', '\"\"');
    final needsQuotes = escaped.contains(',') ||
        escaped.contains('\n') ||
        escaped.contains('\r') ||
        escaped.contains('\"');

    return needsQuotes ? '\"$escaped\"' : escaped;
  }

  String _deckCsvFileName() {
    final cleaned = widget.deck.name
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    final baseName = cleaned.isEmpty ? 'Gakuji Deck' : cleaned;

    return '$baseName.csv';
  }

  Future<void> _showDeckCodeDialog() async {
    if (isPreparingDeckCode) return;

    setState(() {
      isPreparingDeckCode = true;
    });

    try {
      final result = await showGeneralDialog<_DeckCodeDialogResult>(
        context: context,
        barrierDismissible: false,
        barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.42),
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (dialogContext, _, __) {
          return SafeArea(
            child: _DeckCodeDialog(deck: widget.deck),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      );

      if (!mounted || result == null) return;

      if (result.errorMessage != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.fixed,
              duration: const Duration(milliseconds: 2200),
              backgroundColor: Colors.black.withValues(alpha: 0.86),
              content: Text(
                result.errorMessage!,
                textScaler: TextScaler.noScaling,
                style: GakujiText.snackBar,
              ),
            ),
          );
        return;
      }

      if (!result.copied) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.fixed,
            duration: const Duration(milliseconds: 1500),
            backgroundColor: Colors.black.withValues(alpha: 0.86),
            content: Text(
              'Deck code copied',
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
                rightWidget: GakujiCompactMenuButton(
                  icon: Icons.ios_share_rounded,
                  iconSize: 25,
                  iconColor: isSharingOrExporting
                      ? GakujiColors.softGray
                      : GakujiColors.darkGray,
                  enabled: !isSharingOrExporting,
                  menuWidth: 214,
                  alignment: GakujiCompactMenuAlignment.topRight,
                  onBeforeOpen: () => FocusScope.of(context).unfocus(),
                  items: [
                    GakujiCompactMenuItem(
                      icon: Icons.share_rounded,
                      label: 'Share Deck Code',
                      onTap: () => unawaited(_showDeckCodeDialog()),
                    ),
                    GakujiCompactMenuItem(
                      icon: Icons.download_rounded,
                      label: 'Download Deck CSV',
                      onTap: () => unawaited(_downloadDeckCsv()),
                    ),
                  ],
                ),
                showOptionsButton: false,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GakujiSpacing.contentHorizontal,
                    12,
                    GakujiSpacing.contentHorizontal,
                    0,
                  ),
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
                      SizedBox(height: terms.isEmpty ? 20 : 4),
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
          top: 22,
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
              if (term.isCustom) {
                _openCustomCardEditor(term);
                return;
              }

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

class _DeckCodeDialogResult {
  final bool copied;
  final String? errorMessage;

  const _DeckCodeDialogResult({
    this.copied = false,
    this.errorMessage,
  });
}

class _DeckCodeDialog extends StatefulWidget {
  final Deck deck;

  const _DeckCodeDialog({required this.deck});

  @override
  State<_DeckCodeDialog> createState() => _DeckCodeDialogState();
}

class _DeckCodeDialogState extends State<_DeckCodeDialog> {
  String? _deckCode;

  @override
  void initState() {
    super.initState();
    _generateCode();
  }

  Future<void> _generateCode() async {
    try {
      final code = await DeckCodeService.shareDeck(widget.deck);
      if (!mounted) return;

      setState(() {
        _deckCode = code;
      });
    } on DeckCodeException catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop(
        _DeckCodeDialogResult(errorMessage: error.message),
      );
    }
  }

  Future<void> _copyCode() async {
    final code = _deckCode;
    if (code == null) return;

    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;

    Navigator.of(context).pop(
      const _DeckCodeDialogResult(copied: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = (screenWidth * 0.84).clamp(300.0, 360.0);
    final code = _deckCode;

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: dialogWidth,
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          decoration: BoxDecoration(
            color: context.gakujiColors.whiteCard,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [GakujiShadows.card],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Deck Code',
                textAlign: TextAlign.left,
                textScaler: TextScaler.noScaling,
                style: GakujiText.medium.copyWith(
                  color: context.gakujiColors.darkGray,
                  fontSize: 21,
                ),
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: code == null
                    ? Row(
                        key: const ValueKey('generating'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: GakujiColors.reading,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Generating code…',
                            textScaler: TextScaler.noScaling,
                            style: GakujiText.xSmall.copyWith(
                              color: context.gakujiColors.mediumGray,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        code,
                        key: const ValueKey('code'),
                        textAlign: TextAlign.left,
                        textScaler: TextScaler.noScaling,
                        style: GakujiText.medium.copyWith(
                          color: GakujiColors.darkGray,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
              ),
              if (code != null) ...[
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: _DeckCodeDialogButton(
                        label: 'Close',
                        primary: false,
                        onTap: () => Navigator.of(context).pop(
                          const _DeckCodeDialogResult(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DeckCodeDialogButton(
                        label: 'Copy Code',
                        primary: true,
                        onTap: _copyCode,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckCodeDialogButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _DeckCodeDialogButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: primary
            ? GakujiColors.reading
            : context.gakujiColors.whiteCard,
        borderRadius: BorderRadius.circular(14),
        border: primary
            ? null
            : Border.all(
                color: context.gakujiColors.warmDivider,
                width: 1.5,
              ),
        boxShadow: primary ? [GakujiShadows.soft] : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: primary
                    ? Colors.white
                    : context.gakujiColors.darkGray,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

