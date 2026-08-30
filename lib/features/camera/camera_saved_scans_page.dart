import 'dart:io';

import 'package:flutter/material.dart';

import 'package:gakuji/features/camera/services/camera_saved_scan_store.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';

class CameraSavedScansPage extends StatefulWidget {
  const CameraSavedScansPage({super.key});

  @override
  State<CameraSavedScansPage> createState() => _CameraSavedScansPageState();
}

class _CameraSavedScansPageState extends State<CameraSavedScansPage> {
  List<CameraSavedScan> _scans = const [];
  bool _loading = true;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _loadScans();
  }

  Future<void> _loadScans() async {
    final scans = await CameraSavedScanStore.loadScans();
    if (!mounted) return;

    setState(() {
      _scans = scans;
      _loading = false;
    });
  }

  Future<void> _deleteScan(CameraSavedScan scan) async {
    if (_deletingId != null) return;

    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: GakujiColors.warmCard,
              title: Text(
                'Delete saved scan?',
                textScaler: TextScaler.noScaling,
                style: GakujiText.medium.copyWith(
                  color: GakujiColors.darkGray,
                ),
              ),
              content: Text(
                'This only deletes Gakuji\'s saved copy.',
                textScaler: TextScaler.noScaling,
                style: GakujiText.body.copyWith(
                  color: GakujiColors.mediumGray,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldDelete || !mounted) return;

    setState(() {
      _deletingId = scan.id;
    });

    await CameraSavedScanStore.deleteScan(scan.id);
    if (!mounted) return;

    setState(() {
      _scans = _scans.where((item) => item.id != scan.id).toList();
      _deletingId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : _scans.isEmpty
                      ? _emptyState()
                      : _scanGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return SizedBox(
      height: 62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'Saved Scans',
            textScaler: TextScaler.noScaling,
            style: GakujiText.pageTitle.copyWith(color: Colors.white),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox(
                width: 54,
                height: 54,
                child: Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.collections_bookmark_outlined,
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'No saved scans yet',
              textScaler: TextScaler.noScaling,
              style: GakujiText.medium.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 7),
            Text(
              'Scans stay temporary unless you save them.',
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: GakujiText.body.copyWith(
                color: Colors.white60,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.82,
      ),
      itemCount: _scans.length,
      itemBuilder: (context, index) {
        return _scanTile(_scans[index]);
      },
    );
  }

  Widget _scanTile(CameraSavedScan scan) {
    final deleting = _deletingId == scan.id;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: deleting ? null : () => Navigator.of(context).pop(scan),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF1D1D1D)),
            Image.file(
              File(scan.imagePath),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white38,
                    size: 36,
                  ),
                );
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(11, 20, 11, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.82),
                    ],
                  ),
                ),
                child: Text(
                  _dateLabel(scan.savedAt),
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 7,
              right: 7,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: deleting ? null : () => _deleteScan(scan),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: deleting
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final sameYear = local.year == now.year;
    final month = _monthName(local.month);

    if (sameYear) {
      return '$month ${local.day}';
    }

    return '$month ${local.day}, ${local.year}';
  }

  String _monthName(int month) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    if (month < 1 || month > months.length) return '';
    return months[month - 1];
  }
}
