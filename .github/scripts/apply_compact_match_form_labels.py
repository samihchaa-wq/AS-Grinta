from pathlib import Path

form = Path('lib/features/matches/presentation/calendar_entry_form_page.dart')
text = form.read_text()

old = """              title: const Text('Garder cette adresse pour cette équipe'),
              controlAffinity: ListTileControlAffinity.leading,
"""
new = """              title: Text(
                'Mémorise cette adresse',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              controlAffinity: ListTileControlAffinity.leading,
"""
assert old in text, 'remember-address block not found'
text = text.replace(old, new, 1)

old = """          title: const Text('Nombre de joueurs convoqués'),
          subtitle: Text(
            '${_squadSizeController.text} joueur${_squadSizeController.text == '1' ? '' : 's'}',
          ),
          trailing: const Icon(Icons.unfold_more_rounded),
"""
new = """          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Nombre de joueurs convoqués ${_squadSizeController.text} joueur${_squadSizeController.text == '1' ? '' : 's'}',
              maxLines: 1,
            ),
          ),
          trailing: const Icon(Icons.unfold_more_rounded),
"""
assert old in text, 'squad-size block not found'
text = text.replace(old, new, 1)
form.write_text(text)

round_tile = Path('lib/features/matches/presentation/widgets/championship_round_tile.dart')
text = round_tile.read_text()
old = """      title: const Text('Journée de championnat'),
      subtitle: Text(
        current == null
            ? 'Numéro automatique'
            : duplicated
                ? 'J$current · déjà utilisée cette saison'
                : 'J$current',
        style: duplicated
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      trailing: const Icon(Icons.unfold_more_rounded),
"""
new = """      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          current == null
              ? 'Journée de championnat · Numéro automatique'
              : duplicated
                  ? 'Journée de championnat J$current · déjà utilisée cette saison'
                  : 'Journée de championnat J$current',
          maxLines: 1,
          style: duplicated
              ? TextStyle(color: Theme.of(context).colorScheme.error)
              : null,
        ),
      ),
      trailing: const Icon(Icons.unfold_more_rounded),
"""
assert old in text, 'championship-round block not found'
text = text.replace(old, new, 1)
round_tile.write_text(text)
