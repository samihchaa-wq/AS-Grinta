import 'package:as_grinta/app/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebKit browser history page policy', () {
    test('uses NoTransitionPage policy for iOS web', () {
      expect(
        shouldUseNoTransitionPageForWebKitHistory(
          isWeb: true,
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
    });

    test('uses the same policy for macOS web', () {
      expect(
        shouldUseNoTransitionPageForWebKitHistory(
          isWeb: true,
          platform: TargetPlatform.macOS,
        ),
        isTrue,
      );
    });

    test('keeps normal transitions on Android web and native iOS', () {
      expect(
        shouldUseNoTransitionPageForWebKitHistory(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
      expect(
        shouldUseNoTransitionPageForWebKitHistory(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
    });
  });
}
