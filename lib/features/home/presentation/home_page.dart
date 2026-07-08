import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AS Grinta')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Bienvenue', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('Le socle Flutter est prêt.'),
        ],
      ),
    );
  }
}
