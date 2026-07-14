import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:flutter/material.dart';

class AdminAccessDeniedPage extends StatelessWidget {
  const AdminAccessDeniedPage({super.key});

  static const _portraitUrl =
      'https://cdns.klimg.com/resized/1200x720/p/headline/'
      'asal-usul-meme-dictator-mbappe-yang-vir-170078.jpg';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: GrintaAppBar(title: const SizedBox.shrink()),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
          child: Column(
            children: [
              SizedBox(
                height: 430,
                width: double.infinity,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const RadialGradient(
                    center: Alignment(0, -.16),
                    radius: .92,
                    colors: [
                      Colors.white,
                      Colors.white,
                      Color(0xD9FFFFFF),
                      Colors.transparent,
                    ],
                    stops: [0, .52, .76, 1],
                  ).createShader(bounds),
                  child: Image.network(
                    _portraitUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.shield_outlined, size: 160),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -24),
                child: Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 42,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Text(
                'Tu n’as pas les droits',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'pour accéder à cette page.',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 34),
              Text(
                'Seuls les administrateurs peuvent accéder à cette section.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
