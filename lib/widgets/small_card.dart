import 'package:flutter/material.dart';
import '../screens/deck_page.dart';
import '../models/deck.dart';
import '../data/deck_data.dart';

class SmallCard extends StatelessWidget {
  final String title;

  const SmallCard({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final deck = decks.firstWhere(
          (d) => d.name == title,
          orElse: () => decks.first,
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DeckPage(deck: deck),
          ),
        );
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12, bottom: 25),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 8),
            const Text('Items: 50'),
          ],
        ),
      ),
    );
  }
}