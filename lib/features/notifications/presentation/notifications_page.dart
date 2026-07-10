import 'package:as_grinta/features/notifications/data/notifications_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Paramètres des notifications',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          await ref.read(notificationsProvider.future);
        },
        child: notificationsAsync.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (_, __) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
            children: [
              const Icon(Icons.notifications_off_outlined, size: 54),
              const SizedBox(height: 16),
              Text(
                'Notifications temporairement indisponibles',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Center(
                child: FilledButton.icon(
                  onPressed: () => ref.invalidate(notificationsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualiser'),
                ),
              ),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                children: [
                  const Icon(Icons.notifications_none_outlined, size: 54),
                  const SizedBox(height: 16),
                  Text(
                    'Aucune notification',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Les rappels de matchs et de pronostics apparaîtront ici.',
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(_iconFor(item.kind)),
                    ),
                    title: Text(item.title),
                    subtitle: Text(
                      '${item.message}\n${_formatDate(item.date)}',
                    ),
                    isThreeLine: true,
                    onTap: item.kind == 'prediction'
                        ? () => context.push('/predictions')
                        : () => context.push('/matches'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  IconData _iconFor(String kind) {
    return switch (kind) {
      'live' => Icons.sensors,
      'prediction' => Icons.auto_awesome_outlined,
      _ => Icons.sports_soccer_outlined,
    };
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
