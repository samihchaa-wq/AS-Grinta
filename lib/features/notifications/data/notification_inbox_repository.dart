import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Une notification reçue, telle que rangée dans l'historique du joueur.
class NotificationHistoryEntry {
  const NotificationHistoryEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.matchId,
    this.url,
    this.readAt,
  });

  factory NotificationHistoryEntry.fromRow(Map<String, dynamic> row) {
    return NotificationHistoryEntry(
      id: (row['id'] as num).toInt(),
      kind: row['kind']?.toString() ?? 'custom',
      matchId: row['match_id']?.toString(),
      title: row['title']?.toString() ?? '',
      body: row['body']?.toString() ?? '',
      url: row['url']?.toString(),
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      readAt: DateTime.tryParse(row['read_at']?.toString() ?? '')?.toLocal(),
    );
  }

  final int id;
  final String kind;
  final String? matchId;
  final String title;
  final String body;
  final String? url;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get unread => readAt == null;
}

/// Historique des notifications du compte connecté. Interface séparée pour
/// que les tests puissent fournir leur propre version.
abstract interface class NotificationInboxRepository {
  /// Les notifications des 90 derniers jours, la plus récente en premier.
  Future<List<NotificationHistoryEntry>> fetchHistory();

  Future<int> unreadCount();

  /// Marque tout comme lu (ouverture de l'écran) et rend le nombre marqué.
  Future<int> markAllRead();

  /// Supprime définitivement une notification, sur tous les appareils.
  Future<void> delete(int id);
}

class SupabaseNotificationInboxRepository
    implements NotificationInboxRepository {
  SupabaseNotificationInboxRepository(this._client);

  final SupabaseClient _client;

  void _requireSession() {
    if (_client.auth.currentUser == null) {
      throw StateError('Ta session a expiré. Reconnecte-toi.');
    }
  }

  @override
  Future<List<NotificationHistoryEntry>> fetchHistory() async {
    _requireSession();
    final rows = await _client.rpc(
      'get_my_notification_history',
      params: {'p_limit': 200},
    );
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map)
          NotificationHistoryEntry.fromRow(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<int> unreadCount() async {
    if (_client.auth.currentUser == null) return 0;
    final result = await _client.rpc('get_my_unread_notification_count');
    return (result as num?)?.toInt() ?? 0;
  }

  @override
  Future<int> markAllRead() async {
    _requireSession();
    final result = await _client.rpc('mark_my_notifications_read');
    return (result as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> delete(int id) async {
    _requireSession();
    await _client.rpc('delete_my_notification', params: {'p_id': id});
  }
}

final notificationInboxRepositoryProvider =
    Provider<NotificationInboxRepository>((ref) {
  return SupabaseNotificationInboxRepository(
    ref.watch(supabaseClientProvider),
  );
});

/// Nombre de notifications non lues du compte connecté : petit chiffre de la
/// cloche et pastille de l'icône. Zéro hors connexion. Une erreur (réseau,
/// serveur pas encore à jour) donne aussi zéro : la cloche ne doit jamais
/// casser l'en-tête.
final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final profileId = ref.watch(
    authControllerProvider.select((state) => state.profile?.id),
  );
  if (profileId == null) return 0;
  try {
    return await ref.watch(notificationInboxRepositoryProvider).unreadCount();
  } catch (_) {
    return 0;
  }
});
