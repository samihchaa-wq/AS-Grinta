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

  testWidgets('page-sized indeterminate loader keeps a stable 92px size',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: GrintaProgressIndicator()),
        ),
      ),
    );

    final loader = find.byType(GrintaProgressIndicator);
    final paint = find.descendant(
      of: loader,
      matching: find.byType(CustomPaint),
    );
    expect(paint, findsOneWidget);
    expect(tester.getSize(paint), const Size.square(92));
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
