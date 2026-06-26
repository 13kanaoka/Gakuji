import 'package:flutter/material.dart';
import '../widgets/daily_card.dart';
import '../widgets/small_card.dart';
import '../data/deck_data.dart';
import '../models/deck.dart';
import 'deck_page.dart';
import 'library_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // settings page later
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Daily',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const DailyCard(),
            const DailyCard(),
            const DailyCard(),

            const SizedBox(height: 30),
            const Text(
              'Decks',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            /// 🔥 REAL DECK DATA (NEW SYSTEM)
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: decks.length,
                itemBuilder: (context, index) {
                  final deck = decks[index];

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DeckPage(deck: deck),
                        ),
                      );
                    },
                    child: SmallCard(
                      title: deck.name,
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 30),
            const Text(
              'Folders',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: const [
                  SmallCard(title: 'JLPT'),
                  SmallCard(title: 'School'),
                  SmallCard(title: 'Work'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}