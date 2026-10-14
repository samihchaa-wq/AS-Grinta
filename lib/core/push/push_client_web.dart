// Pont vers window.asGrintaPush défini dans web/app_shell.js.
import 'dart:js_interop';

@JS('asGrintaPush.support')
external JSBoolean _support();

@JS('asGrintaPush.permission')
external JSString _permission();

@JS('asGrintaPush.subscribe')
external JSPromise<JSString> _subscribe(JSString vapidKey);

@JS('asGrintaPush.current')
external JSPromise<JSString> _current();

@JS('asGrintaPush.unsubscribe')
external JSPromise<JSString> _unsubscribe();

@JS('asGrintaPush.receipts')
external JSPromise<JSString> _receipts();

@JS('asGrintaPush.forgetReceipts')
external JSPromise<JSAny?> _forgetReceipts(JSString sentJson);

@JS('asGrintaPush.setBadge')
external JSPromise<JSAny?> _setBadge(JSNumber count);

@JS('asGrintaPush.onReceived')
external void _onReceived(JSFunction callback);

Future<bool> pushSupported() async {
  try {
    return _support().toDart;
  } catch (_) {
    return false;
  }
}

Future<String> pushPermission() async {
  try {
    return _permission().toDart;
  } catch (_) {
    return 'unsupported';
  }
}

Future<String?> pushSubscribe(String vapidPublicKey) async {
  try {
    final result = (await _subscribe(vapidPublicKey.toJS).toDart).toDart;
    return result.isEmpty ? null : result;
  } catch (_) {
    return null;
  }
}

Future<String?> pushCurrentSubscription() async {
  try {
    final result = (await _current().toDart).toDart;
    return result.isEmpty ? null : result;
  } catch (_) {
    return null;
  }
}

Future<String?> pushUnsubscribe() async {
  try {
    final result = (await _unsubscribe().toDart).toDart;
    return result.isEmpty ? null : result;
  } catch (_) {
    return null;
  }
}

/// Accusés d'affichage notés par le service worker, en JSON (`[]` si aucun).
Future<String> pushDisplayReceipts() async {
  try {
    return (await _receipts().toDart).toDart;
  } catch (_) {
    return '[]';
  }
}

/// Oublie les accusés déjà transmis au serveur.
Future<void> pushForgetDisplayReceipts(String sentJson) async {
  try {
    await _forgetReceipts(sentJson.toJS).toDart;
  } catch (_) {}
}

/// Pose le nombre de notifications non lues sur l'icône de l'application
/// (zéro l'efface). Sans effet là où l'icône ne porte pas de chiffre.
Future<void> pushSetAppBadge(int count) async {
  try {
    await _setBadge(count.toJS).toDart;
  } catch (_) {}
}

/// Appelé quand une notification arrive pendant que l'application est
/// ouverte sur cet appareil. Un seul abonné : un nouvel appel remplace le
/// précédent.
void pushListenReceived(void Function() callback) {
  try {
    _onReceived(callback.toJS);
  } catch (_) {}
}
