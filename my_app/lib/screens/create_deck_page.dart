import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../data/deck_data.dart';

class CreateDeckPage extends StatefulWidget {
  const CreateDeckPage({super.key});

  @override
  State<CreateDeckPage> createState() => _CreateDeckPageState();
}

class _CreateDeckPageState extends State<CreateDeckPage> {
  final TextEditingController nameController = TextEditingController();

  DeckType selectedType = DeckType.reading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Deck'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            /// DECK NAME INPUT
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Deck Name',
              ),
            ),

            const SizedBox(height: 24),

            /// TYPE SELECTOR
            DropdownButton<DeckType>(
              value: selectedType,
              isExpanded: true,
              items: DeckType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedType = value!;
                });
              },
            ),

            const SizedBox(height: 24),

            /// CREATE BUTTON
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();

                if (name.isEmpty) return;

                decks.add(
                  Deck(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: name,
                    type: selectedType,
                    termIds: [],
                  ),
                );

                Navigator.pop(context);
              },
              child: const Text('Create Deck'),
            ),
          ],
        ),
      ),
    );
  }
}