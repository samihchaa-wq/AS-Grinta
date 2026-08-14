/// Paramètres uniques de livraison des illustrations de badges.
///
/// Les emblèmes culminent à ~123 px dans l'interface. 360 px laisse donc une
/// marge confortable pour les écrans à forte densité tout en évitant de servir
/// les PNG historiques de 1000 px.
const int kBadgeImageDeliveryWidth = 360;
const int kBadgeImageDeliveryQuality = 75;

const String _badgeObjectMarker =
    '/storage/v1/object/public/badge-images/';
const String _badgeRenderMarker =
    '/storage/v1/render/image/public/badge-images/';

/// Route une URL publique du bucket `badge-images` vers le service de
/// transformation Supabase.
///
/// Les URL externes ou inconnues sont laissées intactes. Les anciennes images
/// restent donc compatibles, tandis que les objets Supabase existants sont
/// redimensionnés et, quand le client le supporte, servis automatiquement en
/// WebP par le CDN.
String badgeImageDeliveryUrl(
  String source, {
  int width = kBadgeImageDeliveryWidth,
  int quality = kBadgeImageDeliveryQuality,
}) {
  final uri = Uri.tryParse(source.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return source;

  String path;
  if (uri.path.contains(_badgeObjectMarker)) {
    path = uri.path.replaceFirst(_badgeObjectMarker, _badgeRenderMarker);
  } else if (uri.path.contains(_badgeRenderMarker)) {
    path = uri.path;
  } else {
    return source;
  }

  final params = Map<String, String>.from(uri.queryParameters)
    ..['width'] = '$width'
    ..['quality'] = '$quality';

  return uri.replace(path: path, queryParameters: params).toString();
}
