import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// La vidéo muette du stade, posée sur son image fixe.
///
/// Une balise vidéo directe plutôt que le paquet `video_player` : sur iPhone,
/// Safari ne charge une vidéo sans geste de l'utilisateur que si elle est
/// muette et lue dans la page dès sa création. `video_player` ne la coupe
/// qu'une fois chargée, et attendait donc un chargement qui ne venait jamais.
///
/// La vidéo reste invisible tant qu'elle ne joue pas : si le téléphone refuse
/// de la lire (mode économie d'énergie, par exemple), c'est l'image fixe du
/// stade qu'on voit, jamais un rectangle noir.
class StadiumVideo extends StatefulWidget {
  const StadiumVideo({
    super.key,
    required this.video,
    required this.poster,
    required this.playing,
    required this.take,
    required this.onReady,
  });

  /// Chemins des fichiers dans les assets de l'appli.
  final String video;
  final String poster;

  /// La présentation tourne : la vidéo doit jouer.
  final bool playing;

  /// Change à chaque « Revoir » : la vidéo repart du début.
  final int take;

  /// Appelé une fois, dès que la vidéo peut démarrer ou qu'on y renonce.
  final VoidCallback onReady;

  @override
  State<StadiumVideo> createState() => _StadiumVideoState();
}

class _StadiumVideoState extends State<StadiumVideo> {
  static int _views = 0;

  final String _viewType = 'as-grinta-stade-${_views++}';
  late final web.HTMLVideoElement _video;
  final _subscriptions = <StreamSubscription<web.Event>>[];
  Timer? _giveUp;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _video = web.HTMLVideoElement()
      ..muted = true
      ..defaultMuted = true
      ..playsInline = true
      ..autoplay = false
      ..controls = false
      ..preload = 'auto';
    // Les attributs comptent autant que les propriétés pour Safari.
    _video
      ..setAttribute('muted', '')
      ..setAttribute('playsinline', '')
      ..setAttribute('webkit-playsinline', '')
      ..setAttribute('disablepictureinpicture', '')
      ..setAttribute('disableremoteplayback', '');
    _video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..pointerEvents = 'none'
      ..backgroundColor = 'transparent'
      ..opacity = '0'
      ..transition = 'opacity 120ms linear';
    _subscriptions
      ..add(_video.onCanPlay.listen((_) => _report()))
      ..add(_video.onPlaying.listen((_) {
        _video.style.opacity = '1';
        // Lecture d'essai avant le départ : elle prouve que la vidéo peut
        // jouer ; on revient au début en attendant le vrai départ.
        if (!widget.playing) {
          _video.pause();
          _video.currentTime = 0;
        }
        _report();
      }))
      ..add(_video.onError.listen((_) => _report()));
    _video.src = ui_web.assetManager.getAssetUrl(widget.video);
    _video.load();
    // Safari peut ne rien charger tant qu'on ne demande pas la lecture :
    // la vidéo étant muette, il l'accepte sans geste de l'utilisateur.
    _play();
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _video,
    );
    _giveUp = Timer(const Duration(seconds: 5), _report);
  }

  void _report() {
    if (_reported || !mounted) return;
    _reported = true;
    _giveUp?.cancel();
    widget.onReady();
  }

  void _play() {
    unawaited(
      _video.play().toDart.then<void>((_) {}, onError: (Object _) {
        // Lecture refusée : l'image fixe reste visible.
      }),
    );
  }

  @override
  void didUpdateWidget(StadiumVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.take != oldWidget.take) {
      _video.currentTime = 0;
      _play();
    } else if (widget.playing && !oldWidget.playing) {
      _video.currentTime = 0;
      _play();
    }
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _video
      ..pause()
      ..removeAttribute('src');
    _video.load();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(widget.poster, fit: BoxFit.cover, gaplessPlayback: true),
        HtmlElementView(viewType: _viewType),
      ],
    );
  }
}
