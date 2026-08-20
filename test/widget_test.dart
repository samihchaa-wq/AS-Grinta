import 'dart:async';

import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_loading_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  testWidgets('loading screen displays the authentication loader',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => AuthController(_LoadingAuthRepository()),
          ),
        ],
        child: const MaterialApp(home: AuthLoadingPage()),
      ),
    );

    final loader = find.byType(GrintaLoader);
    expect(loader, findsOneWidget);
    expect(
      find.descendant(of: loader, matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
  });

  testWidgets('determinate statistic rings do not become animated loaders',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(child: GrintaProgressIndicator(value: 0)),
              Expanded(child: GrintaProgressIndicator(value: .5)),
              Expanded(child: GrintaProgressIndicator(value: 1)),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNWidgets(3));
    final values = tester
        .widgetList<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        )
        .map((indicator) => indicator.value)
        .toList();
    expect(values, [0, .5, 1]);
  });

  testWidgets('a large empty zone loads as a skeleton, never as a mark',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: GrintaProgressIndicator()),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(GrintaProgressIndicator),
        matching: find.byType(GrintaSkeletonLines),
      ),
      findsOneWidget,
    );
    expect(find.byType(GrintaSpinnerArc), findsNothing);
  });

  testWidgets('a button-sized zone loads as a 16px arc', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 18,
              child: GrintaProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
    );

    final arc = find.byType(GrintaSpinnerArc);
    expect(arc, findsOneWidget);
    expect(tester.widget<GrintaSpinnerArc>(arc).size, lessThanOrEqualTo(20));
    expect(find.byType(GrintaSkeletonLines), findsNothing);
  });

  testWidgets('an indeterminate bar becomes the 2px progress thread',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GrintaLinearProgressIndicator()),
      ),
    );

    final thread = find.byType(GrintaProgressThread);
    expect(thread, findsOneWidget);
    expect(tester.getSize(thread).height, 2);
  });

  testWidgets('reduced animations stop every loading state', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                GrintaSkeletonLines(),
                GrintaProgressThread(),
                GrintaSpinnerArc(),
                GrintaDotsLoader(),
              ],
            ),
          ),
        ),
      ),
    );

    // Sans cette garantie, `pumpAndSettle` ne rendrait jamais la main : une
    // animation encore en cours ferait expirer le test.
    await tester.pumpAndSettle();
  });
}

class _LoadingAuthRepository implements AuthRepository {
  final Completer<AuthProfile?> _profile = Completer<AuthProfile?>();

  @override
  Stream<supabase.AuthState> get authStateChanges => const Stream.empty();

  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) =>
      _profile.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
