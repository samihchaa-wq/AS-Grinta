part of 'admin_squad_plan_page.dart';

class _BenchBox extends StatelessWidget {
  const _BenchBox({required this.entry, required this.draggable});

  final MatchCompositionEntry entry;
  final bool draggable;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerAvatar(
            photoUrl: entry.photoUrl,
            name: entry.displayName,
            isGoalkeeper: entry.isGoalkeeper,
            size: 58,
          ),
          const SizedBox(height: 4),
          Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    if (!draggable) return box;
    return LongPressDraggable<MatchCompositionEntry>(
      data: entry,
      feedback: Material(color: Colors.transparent, child: box),
      childWhenDragging: Opacity(opacity: .3, child: box),
      child: box,
    );
  }
}

class _FormationDropdown extends StatelessWidget {
  const _FormationDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white54,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        );
    final items = <DropdownMenuItem<String>>[];
    int? lastLine;
    for (final formation in footballFormations) {
      if (formation.defenderLine != lastLine) {
        lastLine = formation.defenderLine;
        items.add(
          DropdownMenuItem<String>(
            enabled: false,
            value: '__hdr_${formation.defenderLine}',
            child: Text(
              '${formation.defenderLine} défenseurs',
              style: headerStyle,
            ),
          ),
        );
      }
      items.add(
        DropdownMenuItem<String>(
          value: formation.code,
          child: Text(formation.code),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Dispositif',
        prefixIcon: Icon(Icons.grid_view_rounded),
        border: OutlineInputBorder(),
      ),
      items: items,
      onChanged: onChanged == null
          ? null
          : (selected) {
              if (selected == null || selected.startsWith('__hdr_')) return;
              onChanged!(selected);
            },
    );
  }
}

class _PlayerInfoRow extends StatelessWidget {
  const _PlayerInfoRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(detail, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
