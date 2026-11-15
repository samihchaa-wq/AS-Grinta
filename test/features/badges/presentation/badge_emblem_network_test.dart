import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('un badge charge son image publique sans transformation bloquée',
      (tester) async {
    const originalUrl =
        'https://ovzijmqrnsgcmryinkfa.supabase.co/storage/v1/object/public/'
        'badge-images/custom/illustration.jpg';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BadgeEmblem(
            emoji: '🏅',
            size: 80,
            imageUrl: originalUrl,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final imageProvider = image.image is ResizeImage
        ? (image.image as ResizeImage).imageProvider
        : image.image;
    expect(imageProvider, isA<NetworkImage>());
    expect((imageProvider as NetworkImage).url, originalUrl);
  });
}
