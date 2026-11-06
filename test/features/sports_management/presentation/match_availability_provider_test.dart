import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability.dart';
import 'package:as_grinta/features/sports_management/presentation/match_availability_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Revenir sur un match peu après l'avoir quitté ne relance pas la lecture de
/// sa disponibilité : la réponse est gardée deux minutes, puis relue.
void main() {
  testWidgets('la disponibilité reste en mémoire deux minutes', (tester) async {
    final repository = _CountingAvailabilityRepository();
    final container = ProviderContainer(
      overrides: [
        sportsManagementEnabledProvider.overrideWithValue(true),
        matchAvailabilityRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    Future<void> openAndLeave() async {
      final subscription = container.listen(
        myMatchAvailabilityProvider('m1'),
        (_, __) {},
      );
      await container.read(myMatchAvailabilityProvider('m1').future);
      subscription.close();
      await tester.pump();
    }

    await openAndLeave();
    expect(repository.reads, 1);

    await tester.pump(const Duration(seconds: 90));
    await openAndLeave();
    expect(repository.reads, 1, reason: 'relu avant la fin des deux minutes');

    await tester.pump(const Duration(minutes: 2, seconds: 5));
    await openAndLeave();
    expect(repository.reads, 2, reason: 'pas relu après deux minutes');

    await tester.pump(const Duration(minutes: 3));
  });
}

class _CountingAvailabilityRepository implements MatchAvailabilityRepository {
  int reads = 0;

  @override
  Future<MatchAvailability?> fetchMyAvailability(String matchId) async {
    reads += 1;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
