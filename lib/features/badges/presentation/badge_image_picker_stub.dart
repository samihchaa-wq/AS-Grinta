import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

Future<Uint8List?> pickBadgeImageBytes() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 100,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  return file.readAsBytes();
}
