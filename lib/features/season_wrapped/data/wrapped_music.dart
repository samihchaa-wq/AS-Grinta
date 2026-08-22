import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Musique de fond du bilan de saison.
///
/// Deux limites assumées, ni l'une ni l'autre contournable :
///
/// - les navigateurs refusent de démarrer un son sans geste de
///   l'utilisateur ; ici c'est l'appui sur le bouton du bilan qui l'autorise ;
/// - sur iPhone en mode silencieux, le son ne sortira pas. Le bilan doit donc
///   rester bon sans musique.
///
/// Tant que la piste n'est pas déposée dans `assets/audio/`, la lecture échoue
/// silencieusement et le bilan s'ouvre sans fond sonore.
class WrappedMusic {
  WrappedMusic();

  static const String assetPath = 'audio/wrapped.mp3';
  static const String _mutedPreferenceKey = 'season_wrapped_music_muted';

  final AudioPlayer _player = AudioPlayer();
  bool _started = false;

  /// `true` quand le joueur a coupé le son la dernière fois.
  static Future<bool> readMuted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_mutedPreferenceKey) ?? false;
    } catch (error) {
      debugPrint('Préférence de musique illisible : $error');
      return false;
    }
  }

  static Future<void> writeMuted(bool muted) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_mutedPreferenceKey, muted);
    } catch (error) {
      debugPrint('Préférence de musique non enregistrée : $error');
    }
  }

  /// Démarre la boucle. Un échec — piste absente, navigateur récalcitrant,
  /// téléphone en silencieux — ne doit jamais empêcher le bilan de s'ouvrir.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(.55);
      await _player.play(AssetSource(assetPath));
    } catch (error) {
      debugPrint('Musique du bilan indisponible : $error');
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (error) {
      debugPrint('Musique du bilan non mise en pause : $error');
    }
  }

  Future<void> resume() async {
    try {
      if (!_started) {
        await start();
        return;
      }
      await _player.resume();
    } catch (error) {
      debugPrint('Musique du bilan non reprise : $error');
    }
  }

  Future<void> dispose() async {
    try {
      await _player.stop();
      await _player.dispose();
    } catch (error) {
      debugPrint('Musique du bilan non arrêtée : $error');
    }
  }
}
