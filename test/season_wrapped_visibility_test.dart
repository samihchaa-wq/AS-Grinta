import 'package:as_grinta/app/router/auth_redirect.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_entry_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('un admin ne voit plus Wrapped pendant une saison ouverte', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          seasonWrappedStateProvider.overrideWith(
            (ref) async => const SeasonWrappedState.unavailable(),
          ),
          isAdminViewProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SeasonWrappedEntryButton()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('season-wrapped-button')), findsNothing);
  });

  testWidgets('Wrapped réapparaît lorsqu’un vrai bilan est disponible', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          seasonWrappedStateProvider.overrideWith(
            (ref) async => const SeasonWrappedState(
              available: true,
              seasonName: '2026-2027',
            ),
          ),
          isAdminViewProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SeasonWrappedEntryButton()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('season-wrapped-button')), findsOneWidget);
  });

  test('le lien d’aperçu Wrapped est bloqué même pour un admin', () {
    const state = AuthState(
      isLoading: false,
      isAuthenticated: true,
      hasSession: true,
      profile: _adminProfile,
    );

    expect(
      resolveAuthRedirect(
        authState: state,
        uri: Uri.parse('/wrapped?apercu=1'),
        matchedLocation: '/wrapped',
      ),
      '/matches',
    );

    // La vraie route reste disponible : son contenu est ensuite servi par les
    // RPC uniquement lorsque le bilan d’intersaison existe réellement.
    expect(
      resolveAuthRedirect(
        authState: state,
        uri: Uri.parse('/wrapped'),
        matchedLocation: '/wrapped',
      ),
      isNull,
    );
  });
}

const _adminProfile = AuthProfile(
  id: 'admin',
  firstName: 'Admin',
  lastName: 'One',
  role: AuthRole.admin,
  isGoalkeeper: false,
  isActive: true,
  mustChangePassword: false,
);
