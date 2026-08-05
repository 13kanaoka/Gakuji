import 'dart:async';

import 'package:flutter/material.dart';

import '../services/gakuji_user_data_store.dart';
import '../widgets/gakuji_styles.dart';
import 'home_page.dart';
import 'dictionary_page.dart';
import 'library_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  late final PageController pageController;
  late final List<Widget> pages;

  int selectedIndex = 0;

  bool isPageSwipeLocked = false;
  bool isDictionaryInputActive = false;
  bool isLibraryDeleteModeActive = false;

  bool get isMainShellHidden {
    return isDictionaryInputActive || isLibraryDeleteModeActive;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    pageController = PageController(initialPage: selectedIndex);

    pages = [
      const HomePage(),
      DictionaryPage(
        onHandwritingInputActive: setDictionaryInputActive,
      ),
      LibraryPage(
        onDeleteModeChanged: setLibraryDeleteModeActive,
      ),
    ];
  }

  @override
  void dispose() {
    unawaited(GakujiUserDataStore.flushPendingSave());

    WidgetsBinding.instance.removeObserver(this);
    pageController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;

    unawaited(GakujiUserDataStore.flushPendingSave());
  }

  void setDictionaryInputActive(bool active) {
    if (isDictionaryInputActive == active && isPageSwipeLocked == active) {
      return;
    }

    setState(() {
      isDictionaryInputActive = active;
      isPageSwipeLocked = active;
    });
  }

  void setLibraryDeleteModeActive(bool active) {
    if (isLibraryDeleteModeActive == active) return;

    setState(() {
      isLibraryDeleteModeActive = active;
    });
  }

  void clearTemporaryPageStates() {
    isPageSwipeLocked = false;
    isDictionaryInputActive = false;
    isLibraryDeleteModeActive = false;
  }

  void goToPage(int index) {
    if (index == selectedIndex) {
      if (isPageSwipeLocked || isMainShellHidden) {
        setState(() {
          clearTemporaryPageStates();
        });
      }

      return;
    }

    setState(() {
      selectedIndex = index;
      clearTemporaryPageStates();
    });

    pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          PageView(
            controller: pageController,
            physics: isPageSwipeLocked
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                selectedIndex = index;
                clearTemporaryPageStates();
              });
            },
            children: pages,
          ),
          _floatingMainShell(),
        ],
      ),
    );
  }

  Widget _floatingMainShell() {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomInset + 16,
      child: IgnorePointer(
        ignoring: isMainShellHidden,
        child: AnimatedSlide(
          offset: isMainShellHidden ? const Offset(0, 1.35) : Offset.zero,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: isMainShellHidden ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: GakujiColors.warmCard,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                    color: GakujiColors.warmDivider,
                    width: 1.5,
                  ),
                  boxShadow: [GakujiShadows.soft],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = constraints.maxWidth / pages.length;

                      return Stack(
                        children: [
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            left: selectedIndex * itemWidth,
                            top: 0,
                            bottom: 0,
                            width: itemWidth,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: GakujiColors.warmBackground,
                                  borderRadius: BorderRadius.circular(32),
                                  border: Border.all(
                                    color: GakujiColors.lightDivider,
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              _navImageIcon(
                                'assets/images/nav_home_bonsai.png',
                                0,
                              ),
                              _navIcon(Icons.search_rounded, 1),
                              _navImageIcon(
                                'assets/images/nav_library_books.png',
                                2,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navImageIcon(String assetPath, int index) {
    final selected = selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => goToPage(index),
        child: Center(
          child: AnimatedScale(
            scale: selected ? 1.16 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: ImageIcon(
              AssetImage(assetPath),
              size: 30,
              color: selected
                  ? GakujiColors.darkGray
                  : GakujiColors.mediumGray,
            ),
          ),
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, int index) {
    final selected = selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => goToPage(index),
        child: Center(
          child: AnimatedScale(
            scale: selected ? 1.16 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Icon(
              icon,
              size: 28,
              color: selected
                  ? GakujiColors.darkGray
                  : GakujiColors.mediumGray,
            ),
          ),
        ),
      ),
    );
  }
}