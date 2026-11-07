import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/incident_error_view.dart';
import 'package:flutter/material.dart';

/// Écran dont le code n'est téléchargé qu'à sa première ouverture.
///
/// Les écrans réservés aux admins et le bilan de saison étaient compris dans
/// le programme téléchargé par chaque joueur à chaque mise à jour. Importés
/// en différé (`deferred as`) dans le routeur, ils forment des morceaux à
/// part, chargés ici la première fois qu'on les ouvre (quelques dizaines de
/// kilo-octets), puis gardés pour la session.
///
/// Pendant le chargement, rien n'est affiché, comme pour toutes les attentes
/// de l'application (voir [GrintaLoader]). En cas d'échec (hors ligne), une
/// erreur avec « Réessayer » remplace l'écran.
class DeferredRoutePage extends StatefulWidget {
  const DeferredRoutePage({
    required this.load,
    required this.builder,
    super.key,
  });

  /// `loadLibrary` de la bibliothèque différée.
  final Future<void> Function() load;

  /// Construit l'écran une fois son code chargé.
  final WidgetBuilder builder;

  @override
  State<DeferredRoutePage> createState() => _DeferredRoutePageState();
}

class _DeferredRoutePageState extends State<DeferredRoutePage> {
  late Future<void> _loading = widget.load();
  String? _incidentReference;

  void _retry() {
    setState(() {
      _incidentReference = null;
      _loading = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: GrintaLoader.page());
        }
        final error = snapshot.error;
        if (error != null) {
          final reference = _incidentReference ??= AppLogger.error(
            'router.deferred_page',
            error,
            snapshot.stackTrace,
          );
          return IncidentErrorView(
            title: 'Écran indisponible',
            message: 'Cet écran n’a pas pu être chargé. Vérifie ta connexion '
                'puis réessaie.',
            incidentReference: reference,
            onRetry: _retry,
          );
        }
        return widget.builder(context);
      },
    );
  }
}
