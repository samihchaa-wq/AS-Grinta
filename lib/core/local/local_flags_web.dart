// Implémentation Web : drapeaux persistés dans window.localStorage.
import 'dart:js_interop';

@JS('window.localStorage')
external _Storage get _localStorage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

bool localFlagGet(String key) {
  try {
    return _localStorage.getItem(key) == '1';
  } catch (_) {
    return false;
  }
}

void localFlagSet(String key, bool value) {
  try {
    _localStorage.setItem(key, value ? '1' : '0');
  } catch (_) {
    // localStorage indisponible (mode privé strict) : on ignore.
  }
}
