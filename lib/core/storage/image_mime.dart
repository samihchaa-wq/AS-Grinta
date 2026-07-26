import 'dart:typed_data';

const int maxImageUploadBytes = 5 * 1024 * 1024;

class ValidatedImageUpload {
  const ValidatedImageUpload({
    required this.extension,
    required this.mimeType,
  });

  final String extension;
  final String mimeType;
}

/// Convertit une extension de fichier image en type MIME normalisé.
String imageMimeForExt(String? fileExt) {
  final ext = (fileExt ?? '').trim().toLowerCase().replaceFirst('.', '');
  return switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

/// Vérifie la taille et la signature binaire réelle d’une photo avant upload.
///
/// L’extension fournie par le sélecteur n’est jamais considérée comme une
/// preuve du format. Le nom et le type MIME envoyés à Supabase sont dérivés
/// de la signature du fichier, ce qui évite les extensions falsifiées et les
/// formats non acceptés par le bucket.
ValidatedImageUpload validateImageUpload(
  Uint8List bytes, {
  String? fileExt,
}) {
  if (bytes.isEmpty) {
    throw const FormatException('La photo sélectionnée est vide.');
  }
  if (bytes.lengthInBytes > maxImageUploadBytes) {
    throw const FormatException(
      'La photo dépasse la taille maximale autorisée de 5 Mo.',
    );
  }

  if (_hasPrefix(bytes, const [0xFF, 0xD8, 0xFF])) {
    return const ValidatedImageUpload(
      extension: 'jpg',
      mimeType: 'image/jpeg',
    );
  }
  if (_hasPrefix(bytes, const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ])) {
    return const ValidatedImageUpload(
      extension: 'png',
      mimeType: 'image/png',
    );
  }
  if (
      bytes.lengthInBytes >= 12 &&
      _asciiAt(bytes, 0, 'RIFF') &&
      _asciiAt(bytes, 8, 'WEBP')) {
    return const ValidatedImageUpload(
      extension: 'webp',
      mimeType: 'image/webp',
    );
  }

  final claimed = (fileExt ?? '').trim().toLowerCase().replaceFirst('.', '');
  final detail = claimed.isEmpty ? '' : ' (extension .$claimed)';
  throw FormatException(
    'Format de photo non reconnu$detail. Utilise une image JPEG, PNG ou WebP.',
  );
}

bool _hasPrefix(Uint8List bytes, List<int> prefix) {
  if (bytes.lengthInBytes < prefix.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) return false;
  }
  return true;
}

bool _asciiAt(Uint8List bytes, int offset, String value) {
  if (bytes.lengthInBytes < offset + value.length) return false;
  for (var index = 0; index < value.length; index++) {
    if (bytes[offset + index] != value.codeUnitAt(index)) return false;
  }
  return true;
}
