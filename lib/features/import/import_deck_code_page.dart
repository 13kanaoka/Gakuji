import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/domain/deck.dart';
import 'package:gakuji/features/decks/deck_term_list_page.dart';
import 'package:gakuji/features/import/services/deck_code_service.dart';

enum _DeckImportState {
  idle,
  importing,
  success,
  failed,
}

class ImportDeckCodePage extends StatefulWidget {
  final ValueChanged<Deck>? onImported;

  const ImportDeckCodePage({
    super.key,
    this.onImported,
  });

  @override
  State<ImportDeckCodePage> createState() => _ImportDeckCodePageState();
}

class _ImportDeckCodePageState extends State<ImportDeckCodePage> {
  final TextEditingController codeController = TextEditingController();
  final FocusNode codeFocusNode = FocusNode();

  _DeckImportState importState = _DeckImportState.idle;
  String? statusMessage;
  Deck? importedDeck;

  bool get isImporting => importState == _DeckImportState.importing;

  @override
  void dispose() {
    codeController.dispose();
    codeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _importDeck() async {
    if (isImporting) return;

    final code = codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        importState = _DeckImportState.failed;
        statusMessage = 'Enter a deck code first.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      importState = _DeckImportState.importing;
      statusMessage = null;
      importedDeck = null;
    });

    try {
      final deck = await DeckCodeService.importDeck(code);
      if (!mounted) return;

      setState(() {
        importedDeck = deck;
        importState = _DeckImportState.success;
        statusMessage = '${deck.name} was added to your library.';
      });
      widget.onImported?.call(deck);
    } on DeckCodeException catch (error) {
      if (!mounted) return;

      setState(() {
        importState = _DeckImportState.failed;
        statusMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        importState = _DeckImportState.failed;
        statusMessage = 'Gakuji could not import that deck. Try again.';
      });
    }
  }

  Future<void> _viewImportedDeck() async {
    final deck = importedDeck;
    if (deck == null) return;

    await Navigator.push<void>(
      context,
      GakujiPageRoute<void>(
        builder: (context) => DeckTermListPage(deck: deck),
      ),
    );
  }

  void _finish() {
    Navigator.pop(context, importedDeck);
  }

  void _handleCodeChanged(String value) {
    if (importState != _DeckImportState.failed) return;

    setState(() {
      importState = _DeckImportState.idle;
      statusMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              GakujiTopBar(
                leftIcon: GakujiTopBar.backIcon,
                leftIconSize: GakujiTopBar.backIconSize,
                leftIconColor: GakujiColors.darkGray,
                onLeftTap: () => Navigator.pop(context, importedDeck),
                title: 'Import Deck',
                titleStyle: GakujiText.pageTitle.copyWith(
                  color: GakujiColors.darkGray,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    26,
                    20,
                    28 + bottomInset,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.sizeOf(context).height - 180,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 20),
                          Icon(
                            Icons.key_rounded,
                            size: 68,
                            color: GakujiColors.darkGray,
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Enter Deck Code',
                            textAlign: TextAlign.center,
                            textScaler: TextScaler.noScaling,
                            style: GakujiText.pageTitle.copyWith(
                              color: GakujiColors.darkGray,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Paste or enter the code from a shared Gakuji deck.',
                            textAlign: TextAlign.center,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                              color: GakujiColors.mediumGray,
                            ),
                          ),
                          const SizedBox(height: 34),
                          _codeField(),
                          const SizedBox(height: 18),
                          if (importState != _DeckImportState.idle)
                            _statusPanel(),
                          const Spacer(),
                          const SizedBox(height: 32),
                          if (importState == _DeckImportState.success) ...[
                            _primaryButton(
                              label: 'View Deck',
                              onTap: _viewImportedDeck,
                            ),
                            const SizedBox(height: 12),
                            _secondaryButton(
                              label: 'Done',
                              onTap: _finish,
                            ),
                          ] else
                            _primaryButton(
                              label: importState == _DeckImportState.failed
                                  ? 'Try Again'
                                  : 'Import Deck',
                              onTap: isImporting ? null : _importDeck,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeField() {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: importState == _DeckImportState.failed
              ? GakujiColors.pinRed.withValues(alpha: 0.55)
              : GakujiColors.warmDivider,
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: TextField(
        controller: codeController,
        focusNode: codeFocusNode,
        enabled: !isImporting && importState != _DeckImportState.success,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
          LengthLimitingTextInputFormatter(14),
        ],
        onChanged: _handleCodeChanged,
        onSubmitted: (_) {
          if (!isImporting && importState != _DeckImportState.success) {
            _importDeck();
          }
        },
        style: GakujiText.actionLabel.copyWith(
          color: GakujiColors.darkGray,
          letterSpacing: 1.1,
        ),
        cursorColor: GakujiColors.reading,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'XXXX-XXXX-XXXX',
          hintStyle: GakujiText.actionLabel.copyWith(
            color: GakujiColors.softGray,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _statusPanel() {
    final failed = importState == _DeckImportState.failed;
    final success = importState == _DeckImportState.success;
    final accent = failed ? GakujiColors.pinRed : GakujiColors.reading;
    final title = switch (importState) {
      _DeckImportState.importing => 'Importing deck...',
      _DeckImportState.success => 'Deck import successful',
      _DeckImportState.failed => 'Deck import failed',
      _DeckImportState.idle => '',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: isImporting ? null : 1,
              minHeight: 6,
              backgroundColor: GakujiColors.softBorder,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isImporting)
                Padding(
                  padding: const EdgeInsets.only(right: 9, top: 1),
                  child: Icon(
                    success
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 21,
                    color: accent,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: GakujiColors.darkGray,
                      ),
                    ),
                    if (statusMessage != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        statusMessage!,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: GakujiColors.mediumGray,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 56,
      child: Material(
        color: onTap == null ? GakujiColors.softBorder : GakujiColors.reading,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.actionLabel.copyWith(
                color: onTap == null ? GakujiColors.mediumGray : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 54,
      child: Material(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GakujiRadius.pill),
              border: Border.all(
                color: GakujiColors.reading,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                label,
                textScaler: TextScaler.noScaling,
                style: GakujiText.actionLabel.copyWith(
                  color: GakujiColors.reading,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
