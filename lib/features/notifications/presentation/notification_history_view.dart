import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/notifications/data/notification_inbox_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Route de l'application ouverte par une notification, comme le ferait un
/// appui sur la notification du téléphone. Le serveur range des adresses
/// relatives (`matches/<id>/vote`, `matches?match=<id>`, `armoire`, `.`).
/// `null` : rien à ouvrir.
String? notificationRoute(String? url) {
  if (url == null) return null;
  var route = url.trim();
  if (route.startsWith('#')) route = route.substring(1);
  route = route.replaceFirst(RegExp(r'^/+'), '');
  if (route.isEmpty || route == '.') return '/matches';
  // Une adresse externe ou étrange ne mène nulle part.
  if (route.contains('://') || route.startsWith('.')) return null;
  return '/$route';
}

/// Historique des notifications reçues (onglet Historique). Ouvrir l'écran
/// marque tout comme lu ; les notifications qui ne l'étaient pas restent
/// mises en avant pendant cette visite.
class NotificationHistoryView extends ConsumerStatefulWidget {
  const NotificationHistoryView({super.key});

  @override
  ConsumerState<NotificationHistoryView> createState() =>
      _NotificationHistoryViewState();
}

class _NotificationHistoryViewState
    extends ConsumerState<NotificationHistoryView> {
  List<NotificationHistoryEntry>? _entries;
  Object? _error;
  bool _loading = false;
  final Set<int> _unreadAtOpen = {};

  /// Une ligne remise après un échec de suppression doit repartir d'un
  /// glissement neuf : sa clé change à chaque retour.
  final Map<int, int> _restored = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final repository = ref.read(notificationInboxRepositoryProvider);
    try {
      final entries = await repository.fetchHistory();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
        _unreadAtOpen.addAll([
          for (final entry in entries)
            if (entry.unread) entry.id,
        ]);
      });
      // Le joueur a l'historique sous les yeux : tout devient lu, la cloche
      // et la pastille de l'icône repartent de zéro.
      try {
        await repository.markAllRead();
      } catch (_) {
        // Au mieux : la prochaine ouverture réessaiera.
      }
      ref.invalidate(unreadNotificationCountProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(NotificationHistoryEntry entry) async {
    final entries = _entries;
    if (entries == null) return;
    final index = entries.indexWhere((item) => item.id == entry.id);
    if (index < 0) return;
    // La ligne quitte la liste tout de suite : elle a déjà glissé hors de
    // l'écran.
    setState(() => _entries = [...entries]..removeAt(index));
    try {
      await ref.read(notificationInboxRepositoryProvider).delete(entry.id);
      ref.invalidate(unreadNotificationCountProvider);
    } catch (error) {
      if (!mounted) return;
      final current = _entries ?? [];
      setState(() {
        _restored[entry.id] = (_restored[entry.id] ?? 0) + 1;
        _entries = [...current]..insert(index.clamp(0, current.length), entry);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(error))),
      );
    }
  }

  void _open(NotificationHistoryEntry entry) {
    final route = notificationRoute(entry.url);
    if (route == null) return;
    // Le calendrier est la racine de l'application : on y retourne au lieu
    // d'en empiler une seconde copie.
    if (route == '/matches' || route.startsWith('/matches?')) {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Une notification arrive pendant que l'écran est ouvert : elle s'affiche
    // et devient lue aussitôt.
    // Seule une hausse compte : un compteur resté au même nombre ne relance
    // rien, ce qui évite de recharger en boucle.
    ref.listen<AsyncValue<int>>(unreadNotificationCountProvider, (
      previous,
      next,
    ) {
      final before = previous?.valueOrNull ?? 0;
      if ((next.valueOrNull ?? 0) > before && !_loading) _load();
    });

    final entries = _entries;
    if (entries == null) {
      if (_error != null) {
        return _HistoryMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Historique indisponible',
          message: humanizeError(_error),
          onRetry: _load,
        );
      }
      return const Center(child: GrintaLoader.inline());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: entries.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 48),
                _HistoryMessage(
                  icon: Icons.notifications_none_outlined,
                  title: 'Aucune notification pour l’instant',
                  message: 'Les notifications du club arriveront ici, même '
                      'celles que ton téléphone n’a pas affichées.',
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              // Marge à droite : sur iPhone, un glissement qui part du bord
              // de l'écran est intercepté par la navigation.
              padding: const EdgeInsets.fromLTRB(16, 8, 24, 24),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _HistoryTile(
                  key: ValueKey<String>(
                    'notification-history-${entry.id}-'
                    '${_restored[entry.id] ?? 0}',
                  ),
                  entry: entry,
                  highlighted: _unreadAtOpen.contains(entry.id),
                  onDismissed: () => _delete(entry),
                  onTap: notificationRoute(entry.url) == null
                      ? null
                      : () => _open(entry),
                );
              },
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    super.key,
    required this.entry,
    required this.highlighted,
    required this.onDismissed,
    this.onTap,
  });

  final NotificationHistoryEntry entry;
  final bool highlighted;
  final VoidCallback onDismissed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppTheme.radiusMd);

    return Dismissible(
      key: key ?? ValueKey<int>(entry.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: .18),
          borderRadius: radius,
        ),
        child: const Icon(Icons.delete_outline, color: AppTheme.error),
      ),
      child: Material(
        color: highlighted
            ? AppTheme.primaryBright.withValues(alpha: .12)
            : AppTheme.surfaceHigh.withValues(alpha: .46),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: highlighted
                ? AppTheme.primaryBright.withValues(alpha: .45)
                : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 10),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: highlighted
                          ? AppTheme.primaryBright
                          : Colors.transparent,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.title, style: theme.textTheme.titleSmall),
                      if (entry.body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          entry.body,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        AppFormats.dateTime(entry.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppTheme.textFaint),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ],
      ),
    );
  }
}
