import 'package:as_grinta/features/badges/presentation/badge_image_delivery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('badgeImageDeliveryUrl', () {
    test('routes public badge objects through image transformations', () {
      expect(
        badgeImageDeliveryUrl(
          'https://project.supabase.co/storage/v1/object/public/'
          'badge-images/custom/badge.png',
        ),
        'https://project.supabase.co/storage/v1/render/image/public/'
        'badge-images/custom/badge.png?width=360&quality=75',
      );
    });

    test('normalizes an already transformed badge URL', () {
      expect(
        badgeImageDeliveryUrl(
          'https://project.supabase.co/storage/v1/render/image/public/'
          'badge-images/custom/badge.png?width=1000&quality=100',
        ),
        'https://project.supabase.co/storage/v1/render/image/public/'
        'badge-images/custom/badge.png?width=360&quality=75',
      );
    });

    test('leaves unrelated images untouched', () {
      const url = 'https://images.example.com/badge.png';
      expect(badgeImageDeliveryUrl(url), url);
    });

    test('supports an explicit delivery size for future callers', () {
      expect(
        badgeImageDeliveryUrl(
          'https://project.supabase.co/storage/v1/object/public/'
          'badge-images/custom/badge.png',
          width: 240,
          quality: 70,
        ),
        'https://project.supabase.co/storage/v1/render/image/public/'
        'badge-images/custom/badge.png?width=240&quality=70',
      );
    });
  });
}
