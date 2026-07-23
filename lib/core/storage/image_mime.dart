/// Convertit une extension de fichier image en type MIME normalisé.
///
/// Les buckets Supabase filtrent sur des types MIME stricts
/// (`image/jpeg`, `image/png`, `image/webp`). Une extension `jpg` produit
/// naïvement `image/jpg`, qui n'existe pas et fait échouer l'upload. On mappe
/// donc explicitement vers les types canoniques, avec `image/jpeg` par défaut.
String imageMimeForExt(String? fileExt) {
  final ext = (fileExt ?? '').trim().toLowerCase().replaceFirst('.', '');
  return switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    _ => 'image/jpeg',
  };
}
