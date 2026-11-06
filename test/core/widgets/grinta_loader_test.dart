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
  testWidgets('post-startup loading screen renders no loader visual',
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
      find.descendant(
        of: loader,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: loader,
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets('determinate statistic rings stay visible', (tester) async {
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

  testWidgets('indeterminate progress indicator renders nothing',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: GrintaProgressIndicator()),
        ),
      ),
    );

    final loader = find.byType(GrintaProgressIndicator);
    expect(loader, findsOneWidget);
    expect(
      find.descendant(
        of: loader,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: loader,
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets('startup progress bar is the only indeterminate loader visual',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GrintaStartupProgressBar()),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, isNull);
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
