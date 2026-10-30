import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// La vidéo muette du stade, posée sur son image fixe.
///
/// Tout est fait pour qu'un téléphone ne puisse pas la refuser :
/// - elle est téléchargée d'un bloc puis lue depuis la mémoire du téléphone :
///   aucun téléchargement par morceaux, que l'ancien service worker faisait
///   échouer, et elle reste ensuite dans le cache pour la fois suivante ;
/// - un téléphone qui ne lit pas la grande version sans à-coups reçoit la
///   version légère ;
/// - elle est muette, lue dans la page, et « débloquée » pendant l'appui sur
///   le bouton qui l'ouvre ([primeStadiumVideo]) : même en économie
///   d'énergie, l'iPhone accepte alors de la lire ;
/// - arrivée en retard, elle rejoint la présentation au bon instant.
///
/// Tant qu'elle ne joue pas, c'est l'image fixe du stade qu'on voit, jamais un
/// rectangle noir. [StadiumVideo.onStatus] dit ce qui s'est passé.
class StadiumVideo extends StatefulWidget {
  const StadiumVideo({
    super.key,
    required this.video,
    required this.lightVideo,
    required this.poster,
    required this.playing,
    required this.take,
    required this.elapsed,
    required this.onReady,
    this.onStatus,
  });

  /// Chemins des fichiers dans les assets de l'appli.
  final String video;
  final String lightVideo;
  final String poster;

  /// La présentation tourne : la vidéo doit jouer.
  final bool playing;

  /// Change à chaque « Revoir » : la vidéo repart du début.
  final int take;

  /// Instant de la présentation, en secondes.
  final double Function() elapsed;

  /// Appelé une fois, dès que la vidéo peut démarrer ou qu'on y renonce.
  final VoidCallback onReady;

  /// État de la vidéo en clair, pour l'aperçu de l'admin.
  final ValueChanged<String>? onStatus;

  @override
  State<StadiumVideo> createState() => _StadiumVideoState();
}

web.HTMLVideoElement? _primed;

/// À appeler pendant l'appui sur le bouton qui ouvre la vidéo, avant toute
/// attente : une lecture lancée par un geste « débloque » la balise vidéo,
/// que le téléphone laissera ensuite jouer sans nouveau geste.
void primeStadiumVideo() {
  if (_primed != null) return;
  final video = _newVideoElement();
  unawaited(
    video.play().toDart.then<void>((_) {}, onError: (Object _) {}),
  );
  video.pause();
  _primed = video;
}

web.HTMLVideoElement _newVideoElement() {
  final video = web.HTMLVideoElement()
    ..muted = true
    ..defaultMuted = true
    ..playsInline = true
    ..autoplay = false
    ..controls = false
    ..preload = 'auto';
  // Les attributs comptent autant que les propriétés pour Safari.
  video
    ..setAttribute('muted', '')
    ..setAttribute('playsinline', '')
    ..setAttribute('webkit-playsinline', '')
    ..setAttribute('disablepictureinpicture', '')
    ..setAttribute('disableremoteplayback', '');
  video.style
    ..width = '100%'
    ..height = '100%'
    ..objectFit = 'cover'
    ..pointerEvents = 'none'
    ..backgroundColor = 'transparent';
  return video;
}

class _StadiumVideoState extends State<StadiumVideo> {
  static int _views = 0;

  final String _viewType = 'as-grinta-stade-${_views++}';
  late final web.HTMLVideoElement _video;
  final _subscriptions = <StreamSubscription<web.Event>>[];
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _giveUp;
  bool _reported = false;
  bool _attached = false;
  bool _sourceSet = false;
  bool _played = false;
  String? _objectUrl;
  String _version = '';
  String? _problem;
  final List<String> _events = [];

  @override
  void initState() {
    super.initState();
    _video = _primed ?? _newVideoElement();
    final unlocked = _primed != null;
    _primed = null;
    _video.poster = ui_web.assetManager.getAssetUrl(widget.poster);
    _subscriptions
      ..add(_video.onCanPlay.listen((_) {
        // Arrivée en retard : elle se recale sur la présentation.
        if (widget.playing && !_played) _tryPlay();
        _report();
      }))
      ..add(_video.onPlaying.listen((_) {
        if (!widget.playing) {
          // Lecture d'essai avant le départ : retour au début.
          _video.pause();
          _video.currentTime = 0;
        } else {
          _played = true;
          _status();
        }
        _report();
      }))
      ..add(_video.onError.listen((_) {
        final code = _video.error?.code;
        _problem = 'vidéo illisible sur ce téléphone (erreur $code)';
        _status();
        _report();
      }));
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _video,
    );
    _log(unlocked ? 'débloquée par l’appui' : 'sans appui préalable');
    unawaited(_loadSource());
    _giveUp = Timer(const Duration(seconds: 6), () {
      _problem ??= 'vidéo trop longue à charger';
      _status();
      _report();
    });
  }

  void _log(String event) {
    _events.add('${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s '
        '$event');
  }

  /// La grande version si le téléphone la lit sans à-coups, la légère sinon.
  Future<String> _pickVersion() async {
    try {
      final capabilities = web.window.navigator.mediaCapabilities;
      final info = await capabilities
          .decodingInfo(
            web.MediaDecodingConfiguration(
              type: 'file',
              video: web.VideoConfiguration(
                contentType: 'video/mp4; codecs="avc1.640032"',
                width: 1080,
                height: 2338,
                bitrate: 2300000,
                framerate: 30,
              ),
            ),
          )
          .toDart
          .timeout(const Duration(milliseconds: 800));
      if (info.supported && info.smooth) {
        _version = '1080 px';
        return widget.video;
      }
    } catch (_) {
      // Navigateur ancien : on ne prend pas de risque.
    }
    _version = '720 px';
    return widget.lightVideo;
  }

  Future<void> _loadSource() async {
    final asset = await _pickVersion();
    final url = ui_web.assetManager.getAssetUrl(asset);
    _log('version $_version');
    String source = url;
    try {
      final response = await web.window.fetch(url.toJS).toDart.timeout(
            const Duration(seconds: 20),
          );
      if (!response.ok) throw StateError('HTTP ${response.status}');
      final blob = await response.blob().toDart;
      _objectUrl = web.URL.createObjectURL(blob);
      source = _objectUrl!;
      _log('téléchargée');
    } catch (error) {
      // Dernier recours : lecture directe depuis le réseau.
      _log('téléchargement en bloc impossible ($error)');
    }
    if (!mounted) return;
    _video.src = source;
    _sourceSet = true;
    _video.load();
    _tryPlay();
  }

  void _onAttached(int _) {
    _attached = true;
    _log('affichée');
    _tryPlay();
  }

  /// Lance (ou relance) la lecture au bon instant de la présentation.
  void _tryPlay() {
    if (!_sourceSet || !_attached || !mounted) return;
    if (widget.playing) {
      final target = widget.elapsed();
      if ((_video.currentTime - target).abs() > 0.35) {
        _video.currentTime = target;
      }
    }
    unawaited(
      _video.play().toDart.then<void>((_) {}, onError: (Object error) {
        String name;
        try {
          name = (error as web.DOMException).name;
        } catch (_) {
          name = '$error';
        }
        if (name == 'AbortError') return;
        final problem = 'lecture refusée par le téléphone ($name)';
        if (_problem != problem) {
          _problem = problem;
          _log(problem);
          _status();
        }
        _report();
      }),
    );
  }

  void _report() {
    if (_reported || !mounted) return;
    _reported = true;
    _giveUp?.cancel();
    widget.onReady();
  }

  void _status() {
    final summary = _played
        ? 'Vidéo du stade : animée ($_version).'
        : 'Vidéo du stade : image fixe — ${_problem ?? 'pas encore lancée'}.';
    widget.onStatus?.call('$summary\n${_events.join(' · ')}');
  }

  @override
  void didUpdateWidget(StadiumVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.take != oldWidget.take ||
        (widget.playing && !oldWidget.playing)) {
      _video.currentTime = 0;
      _tryPlay();
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
    final objectUrl = _objectUrl;
    if (objectUrl != null) web.URL.revokeObjectURL(objectUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(widget.poster, fit: BoxFit.cover, gaplessPlayback: true),
        HtmlElementView(
          viewType: _viewType,
          onPlatformViewCreated: _onAttached,
        ),
      ],
    );
  }
}
