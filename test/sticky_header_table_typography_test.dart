import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'la largeur minimale reprend exactement la typographie héritée',
    (tester) async {
      double? pinnedWidth;
      double? exactRequiredWidth;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          home: Scaffold(
            body: DefaultTextStyle(
              // Reproduit le point qui diffère selon la typographie de la
              // plateforme : Text hérite notamment du letter-spacing et de la
              // famille de police, contrairement à un TextPainter isolé.
              style: const TextStyle(letterSpacing: 2.5),
              child: Builder(
                builder: (context) {
                  const name = 'Stéphane';
                  const badgeSize = 48.0;
                  const badgeGap = 3.0;
                  final resolvedStyle = DefaultTextStyle.of(
                    context,
                  ).style.merge(
                    grintaTableCellTextStyle(
                      context,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                  final painter = TextPainter(
                    text: TextSpan(text: name, style: resolvedStyle),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    locale: Localizations.maybeLocaleOf(context),
                    maxLines: 1,
                  )..layout();

                  exactRequiredWidth = grintaTablePinnedRowPadding.left +
                      grintaTableRankWidth +
                      grintaTableRankGap +
                      painter.width +
                      badgeGap +
                      badgeSize +
                      grintaTablePinnedRowPadding.right;
                  pinnedWidth = grintaTablePinnedWidthForNames(
                    context,
                    const [name],
                    trailingWidth: badgeSize,
                    trailingGap: badgeGap,
                  );

                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      expect(pinnedWidth, greaterThanOrEqualTo(exactRequiredWidth!));
      expect(pinnedWidth! - exactRequiredWidth!, lessThan(1));
    },
  );
}
