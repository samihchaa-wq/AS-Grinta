import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:flutter/material.dart';

class AuthLoadingPage extends StatelessWidget {
  const AuthLoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: GrintaLoader.page(
          message: 'Préparation de ton espace…',
          semanticLabel: 'Préparation de ton espace',
        ),
      ),
    );
  }
}
