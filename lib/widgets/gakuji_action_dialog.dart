import 'package:flutter/material.dart';

import 'gakuji_styles.dart';

/// Shared Gakuji confirmation/action popup.
///
/// Use this for short modal decisions that need a title, explanatory copy,
/// and a primary/secondary action pair. The popup stays visually consistent
/// with Gakuji's cards and controls in both light and dark mode.
class GakujiActionDialog extends StatelessWidget {
  final String title;
  final String message;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;
  final bool primaryDestructive;
  final Color? primaryColor;
  final TextStyle? messageStyle;

  const GakujiActionDialog({
    super.key,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
    this.primaryDestructive = false,
    this.primaryColor,
    this.messageStyle,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = (screenWidth * 0.84).clamp(300.0, 360.0);

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
                title,
                textAlign: TextAlign.left,
                textScaler: TextScaler.noScaling,
                style: GakujiText.medium.copyWith(
                  color: context.gakujiColors.darkGray,
                  fontSize: 21,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.left,
                textScaler: TextScaler.noScaling,
                style: messageStyle ??
                    GakujiText.xSmall.copyWith(
                      color: context.gakujiColors.mediumGray,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: secondaryLabel,
                      primary: false,
                      onTap: onSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DialogButton(
                      label: primaryLabel,
                      primary: true,
                      destructive: primaryDestructive,
                      primaryColor: primaryColor,
                      onTap: onPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final bool primary;
  final bool destructive;
  final Color? primaryColor;
  final VoidCallback onTap;

  const _DialogButton({
    required this.label,
    required this.primary,
    this.destructive = false,
    this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: primary
            ? (destructive
                ? GakujiColors.pinRed
                : (primaryColor ?? GakujiColors.deckBlue))
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

Future<bool?> showGakujiActionDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String primaryLabel,
  String secondaryLabel = 'Cancel',
  bool primaryDestructive = false,
  Color? primaryColor,
  TextStyle? messageStyle,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, __) {
      return SafeArea(
        child: GakujiActionDialog(
          title: title,
          message: message,
          primaryLabel: primaryLabel,
          secondaryLabel: secondaryLabel,
          onPrimary: () => Navigator.of(dialogContext).pop(true),
          onSecondary: () => Navigator.of(dialogContext).pop(false),
          primaryDestructive: primaryDestructive,
          primaryColor: primaryColor,
          messageStyle: messageStyle,
        ),
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
}


class GakujiPasswordConfirmationDialog extends StatefulWidget {
  final String title;
  final String message;
  final String primaryLabel;
  final String secondaryLabel;
  final bool destructive;

  const GakujiPasswordConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.primaryLabel,
    this.secondaryLabel = 'Cancel',
    this.destructive = false,
  });

  @override
  State<GakujiPasswordConfirmationDialog> createState() =>
      _GakujiPasswordConfirmationDialogState();
}

class _GakujiPasswordConfirmationDialogState
    extends State<GakujiPasswordConfirmationDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    if (password.isEmpty) return;
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = (screenWidth * 0.84).clamp(300.0, 360.0);

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
                widget.title,
                textAlign: TextAlign.left,
                textScaler: TextScaler.noScaling,
                style: GakujiText.medium.copyWith(
                  color: context.gakujiColors.darkGray,
                  fontSize: 21,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.message,
                textAlign: TextAlign.left,
                textScaler: TextScaler.noScaling,
                style: GakujiText.xSmall.copyWith(
                  color: context.gakujiColors.mediumGray,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                autofocus: true,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Current password',
                  filled: true,
                  fillColor: context.gakujiColors.warmCard,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: context.gakujiColors.warmDivider,
                      width: 1.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: context.gakujiColors.warmDivider,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: GakujiColors.deckBlue,
                      width: 1.7,
                    ),
                  ),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: context.gakujiColors.mediumGray,
                    ),
                  ),
                ),
                style: GakujiText.small.copyWith(
                  color: context.gakujiColors.darkGray,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: widget.secondaryLabel,
                      primary: false,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DialogButton(
                      label: widget.primaryLabel,
                      primary: true,
                      destructive: widget.destructive,
                      onTap: _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> showGakujiPasswordConfirmationDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String primaryLabel,
  String secondaryLabel = 'Cancel',
  bool destructive = false,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, __) {
      return SafeArea(
        child: GakujiPasswordConfirmationDialog(
          title: title,
          message: message,
          primaryLabel: primaryLabel,
          secondaryLabel: secondaryLabel,
          destructive: destructive,
        ),
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
}
