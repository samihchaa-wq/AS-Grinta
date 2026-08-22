import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  // Créé à la demande : un remplaçant de test n'a pas à instancier de
  // lecteur audio.
  late final AudioPlayer _player = AudioPlayer();
  bool _started = false;
  bool _paused = false;

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
      _paused = false;
    } catch (error) {
      debugPrint('Musique du bilan indisponible : $error');
    }
  }

  Future<void> pause() async {
    if (!_started || _paused) return;
    _paused = true;
    try {
      await _player.pause();
    } catch (error) {
      debugPrint('Musique du bilan non mise en pause : $error');
    }
  }

  /// Reprend là où la pause a laissé la piste.
  ///
  /// Ne fait rien si la musique n'a jamais été mise en pause : demander à
  /// reprendre une lecture déjà en cours la faisait repartir du début.
  Future<void> resume() async {
    if (!_started) {
      await start();
      return;
    }
    if (!_paused) return;
    _paused = false;
    try {
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

/// La musique du bilan, remplaçable dans les tests.
final wrappedMusicProvider = Provider<WrappedMusic>((ref) => WrappedMusic());
