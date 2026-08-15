import 'package:as_grinta/features/badges/presentation/badge_descriptor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('goalkeeper role badge has a dedicated descriptor', () {
    final descriptor = badgeDescriptorFor(code: 'role_goalkeeper');

    expect(descriptor.label, 'GARDIEN');
    expect(descriptor.period, isNull);
  });
}
