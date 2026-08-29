import 'package:as_grinta/core/widgets/moment_card_watermark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('momentWatermarkKindForMatchType', () {
    test('maps every calendar match type to its watermark', () {
      expect(
        momentWatermarkKindForMatchType('championnat'),
        MomentWatermarkKind.championship,
      );
      expect(
        momentWatermarkKindForMatchType('amical'),
        MomentWatermarkKind.friendly,
      );
      expect(
        momentWatermarkKindForMatchType('entre_nous'),
        MomentWatermarkKind.internal,
      );
    });

    test('keeps unknown historical match types on championship fallback', () {
      expect(
        momentWatermarkKindForMatchType(null),
        MomentWatermarkKind.championship,
      );
      expect(
        momentWatermarkKindForMatchType('legacy'),
        MomentWatermarkKind.championship,
      );
    });
  });
}
