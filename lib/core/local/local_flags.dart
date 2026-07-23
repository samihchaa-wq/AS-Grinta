// Petits drapeaux persistés côté appareil (localStorage sur Web, mémoire
// ailleurs). Sert à retenir des choses purement locales, comme « l'écran
// d'accueil a déjà été vu », sans toucher au serveur.
export 'local_flags_stub.dart'
    if (dart.library.js_interop) 'local_flags_web.dart';
