import 'dart:io';

import 'package:as_grinta/core/sync/resume_refresh_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('une courte absence ne recharge pas tout', () {
    expect(shouldFullyRefreshOnResume(const Duration(seconds: 20)), isFalse);
    expect(shouldFullyRefreshOnResume(const Duration(minutes: 29)), isFalse);
  });

  test('une longue absence ou une durée inconnue recharge tout', () {
    expect(shouldFullyRefreshOnResume(const Duration(minutes: 30)), isTrue);
    expect(shouldFullyRefreshOnResume(const Duration(hours: 5)), isTrue);
    expect(shouldFullyRefreshOnResume(null), isTrue);
  });

  test('le retour au premier plan relit toujours le signal et la cloche',
      () async {
    final app = await File('lib/app/app.dart').readAsString();
    final start = app.indexOf('void didChangeAppLifecycleState(');
    final policy = app.indexOf('shouldFullyRefreshOnResume(awayFor)', start);
    final signal =
        app.indexOf('ref.invalidate(sharedDataSignalProvider);', start);
    final bell =
        app.indexOf('ref.invalidate(unreadNotificationCountProvider);', start);
    final full = app.indexOf(').refreshAll()', start);

    expect(start, isNonNegative);
    expect(signal, inInclusiveRange(start, policy));
    expect(bell, inInclusiveRange(start, policy));
    expect(full, greaterThan(policy));
  });
}
