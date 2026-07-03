import 'package:flutter/material.dart';

class FlashcardRow extends StatelessWidget {
  final bool marked;

  const FlashcardRow({super.key, required this.marked});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade400,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '漢字  [かな]',
                  style: TextStyle(fontSize: 20, color: Colors.white),
                ),
                Text(
                  'Definition ...',
                  style: TextStyle(fontSize: 11, color: Colors.white),
                ),
              ],
            ),
          ),
          Icon(
            marked ? Icons.star : Icons.star_border,
            color: Colors.white,
            size: 32,
          ),
        ],
      ),
    );
  }
}