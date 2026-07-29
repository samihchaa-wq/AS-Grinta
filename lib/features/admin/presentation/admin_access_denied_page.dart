import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class AdminAccessDeniedPage extends StatelessWidget {
  const AdminAccessDeniedPage({super.key});

  static final Uint8List _portraitBytes = base64Decode(_portraitBase64);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 8,
              top: 4,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 52, 28, 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 520,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(0, .1),
                                  radius: .72,
                                  colors: [
                                    const Color(
                                      0xFF183566,
                                    ).withValues(alpha: .34),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.topCenter,
                            child: Image.memory(
                              _portraitBytes,
                              height: 455,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              gaplessPlayback: true,
                            ),
                          ),
                          Container(
                            width: 104,
                            height: 104,
                            decoration: const BoxDecoration(
                              color: Color(0xFF132A56),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.lock_outline_rounded,
                              size: 48,
                              color: Color(0xFFFF3D8D),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    Text(
                      'Tu n’as pas les droits',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'pour accéder à cette page.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w400,
                          ),
                    ),
                    const SizedBox(height: 46),
                    Text(
                      'Seuls les administrateurs peuvent\naccéder à cette section.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white60,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _portraitBase64 =
    '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';
