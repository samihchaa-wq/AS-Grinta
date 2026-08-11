import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('asGrintaBadgeImage.pick')
external JSPromise<JSString> _pickBadgeImage();

Future<Uint8List?> pickBadgeImageBytes() async {
  final dataUrl = (await _pickBadgeImage().toDart).toDart;
  if (dataUrl.isEmpty) return null;

  final comma = dataUrl.indexOf(',');
  if (comma < 0 || comma == dataUrl.length - 1) {
    throw const FormatException('Image web invalide.');
  }

  return base64Decode(dataUrl.substring(comma + 1));
}
