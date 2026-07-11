// Abonnement aux notifications push Web (no-op hors navigateur).
export 'push_client_stub.dart'
    if (dart.library.js_interop) 'push_client_web.dart';

/// Clé publique VAPID du serveur d'envoi (la clé privée reste dans
/// Supabase Vault, lue uniquement par l'Edge Function send-push).
const String pushVapidPublicKey =
    'BDZa9YcR2dn5pzohdAgKuSxfM-2FdudE3WhbPvd4SQKUE4XWeBbExvgABIX2yj7prfmoo-qpJ9Kcoy4SA-KxYio';
