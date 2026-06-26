import 'package:flutter/material.dart';

class DailyCard extends StatelessWidget {
  const DailyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Deck Name'),
              Text('Items: 20'),
              SizedBox(height: 4),
              Text(
                'Deck Type: Reading',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          Column(
            children: [
              Text('New: 5'),
              Text('Review: 10'),
            ],
          ),
        ],
      ),
    );
  }
}