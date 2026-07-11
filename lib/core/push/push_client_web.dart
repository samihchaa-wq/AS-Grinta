// Pont vers window.asGrintaPush défini dans web/index.html.
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
