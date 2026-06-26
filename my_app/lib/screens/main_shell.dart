import 'package:flutter/material.dart';
import 'home_page.dart';
import 'dictionary_page.dart';
import 'library_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int selectedIndex = 0;

  final List<Widget> pages = const [
  HomePage(),
  DictionaryPage(),
  LibraryPage(),
];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[selectedIndex],
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _navIcon(Icons.home, 0),
            _navIcon(Icons.search, 1),
            _navIcon(Icons.folder_copy_outlined, 2),
          ],
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, int index) {
    final bool selected = selectedIndex == index;

    return IconButton(
      onPressed: () {
        setState(() {
          selectedIndex = index;
        });
      },
      icon: Icon(
        icon,
        size: selected ? 34 : 28,
        color: selected ? Colors.grey : Colors.black54,
      ),
    );
  }
}