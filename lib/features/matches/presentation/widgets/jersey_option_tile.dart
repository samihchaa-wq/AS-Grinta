import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:flutter/material.dart';

/// Vignette d'un maillot proposé pour un match, avec sa coche quand il est
/// choisi. Partagée par le formulaire de création et celui de modification
/// d'un match.
/// Rangée des maillots proposés. Chaque vignette prend une part égale de la
/// largeur disponible, pour que les maillots restent sur une seule ligne quelle
/// que soit la taille de l'écran (plafonnés pour ne pas devenir énormes sur
/// tablette).
class JerseyOptionPicker extends StatelessWidget {
  const JerseyOptionPicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final JerseyOption? selected;

  /// Reçoit le maillot choisi, ou `null` quand on retape sur celui déjà
  /// sélectionné. `null` désactive la sélection.
  final ValueChanged<JerseyOption?>? onChanged;

  static const double _spacing = 12;
  static const double _maxTileWidth = 130;

  @override
  Widget build(BuildContext context) {
    final options = JerseyOption.values;
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: _spacing),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxTileWidth),
                child: JerseyOptionTile(
                  option: options[i],
                  selected: selected == options[i],
                  onTap: onChanged == null
                      ? null
                      : () => onChanged!(
                            selected == options[i] ? null : options[i],
                          ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class JerseyOptionTile extends StatelessWidget {
  const JerseyOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final JerseyOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 96 / 108,
        child: Stack(
          children: [
            Center(
              child: Image.asset(
                option.assetPath,
                fit: BoxFit.contain,
                semanticLabel: 'Maillot ${option.label}',
                errorBuilder: (context, _, __) =>
                    _JerseyFallback(label: option.label, selected: selected),
              ),
            ),
            if (selected)
              Positioned(
                right: 0,
                top: 0,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _JerseyFallback extends StatelessWidget {
  const _JerseyFallback({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checkroom_rounded, color: colors.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
