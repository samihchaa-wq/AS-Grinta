import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_running_page.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tableau Blanc : banc et terrain à la même taille', () {
    // Largeurs utiles typiques : petit téléphone, iPhone courant, tablette.
    const widths = [300.0, 361.0, 500.0];

    test('la colonne du banc et le terrain remplissent la largeur donnée', () {
      for (final available in widths) {
        final metrics = benchAndPitchMetrics(available);
        // Le terrain occupe ce qui reste une fois le banc et l'écart posés.
        final pitchWidth =
            available - benchColumnWidth(metrics) - AppSpacing.contentGap;
        // Et cette largeur de terrain redonne bien la même taille de vignette :
        // sans quoi le banc et les titulaires divergeraient à l'affichage.
        expect(
          FormationMarkerMetrics.forPitch(pitchWidth).width,
          closeTo(metrics.width, 0.01),
          reason: 'largeur disponible : $available',
        );
      }
    });

    test('une vignette de banc reprend les mesures d’un titulaire', () {
      final metrics = benchAndPitchMetrics(361);
      // Photo et prénom viennent des mêmes formules : c'est ce partage qui
      // garantit qu'un remplaçant occupe la place d'un titulaire.
      expect(metrics.avatarSize, closeTo(metrics.width * .82, 0.01));
      expect(metrics.nameFontSize, greaterThanOrEqualTo(10.5));
      expect(metrics.nameFontSize, lessThanOrEqualTo(12.5));
    });

    test('les marqueurs restent dans des bornes lisibles', () {
      expect(benchAndPitchMetrics(200).width, greaterThanOrEqualTo(44));
      expect(benchAndPitchMetrics(2000).width, lessThanOrEqualTo(64));
    });
  });
}
