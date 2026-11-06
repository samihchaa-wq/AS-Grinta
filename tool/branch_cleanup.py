#!/usr/bin/env python3
"""Ménage des branches du dépôt, sans rien perdre.

Lancé à la main par le workflow « Ménage des branches »
(.github/workflows/branch_cleanup.yml), dans un clone complet où toutes les
branches distantes ont été récupérées.

Règles, dans l'ordre :

1. Jamais touchées : la branche par défaut, la tête de chaque demande de
   fusion ouverte, et toute branche modifiée depuis moins de --min-age-days
   jours (une session peut être en train d'y travailler).
2. Supprimées : les branches dont le commit est déjà dans la branche par
   défaut, ou identique à la tête d'une ancienne demande de fusion. GitHub
   conserve cette tête (refs/pull/N/head) et propose « Restore branch » sur
   la page de la demande.
3. Archivées puis supprimées : toutes les autres. Chacune est d'abord copiée
   sous refs/archive/<nom>, invisible dans la liste des branches ; la copie
   est relue et comparée commit par commit avant tout retrait. Pour en
   ressortir une : git fetch origin refs/archive/<nom>, puis la republier
   comme branche.

Chaque suppression exige que la branche pointe encore sur le commit analysé
(--force-with-lease) : une branche modifiée entre-temps n'est pas touchée.

Sans --apply, le script ne fait qu'afficher ce qu'il ferait.
"""

import argparse
import os
import subprocess
import time

ARCHIVE_PREFIX = 'refs/archive/'
BATCH = 100


def git(*args, check=True):
    result = subprocess.run(
        ['git', *args], text=True, capture_output=True, check=False
    )
    if check and result.returncode != 0:
        raise SystemExit(f'git {" ".join(args[:2])} a échoué :\n{result.stderr}')
    return result


def remote_refs(pattern):
    refs = {}
    for line in git('ls-remote', 'origin', pattern).stdout.splitlines():
        sha, ref = line.split('\t')
        refs[ref] = sha
    return refs


def commit_age_days(sha):
    stamp = git('log', '-1', '--format=%ct', sha).stdout.strip()
    return (time.time() - int(stamp)) / 86400


def classify(default_branch, open_heads, min_age_days):
    heads = {
        ref[len('refs/heads/'):]: sha
        for ref, sha in remote_refs('refs/heads/*').items()
    }
    pull_heads = set(remote_refs('refs/pull/*/head').values())
    kept, safe, archive = {}, {}, {}
    for branch, sha in sorted(heads.items()):
        if branch == default_branch:
            kept[branch] = 'branche par défaut'
        elif branch in open_heads:
            kept[branch] = 'demande de fusion ouverte'
        elif git('cat-file', '-e', f'{sha}^{{commit}}', check=False).returncode:
            kept[branch] = 'commit introuvable localement'
        elif commit_age_days(sha) < min_age_days:
            kept[branch] = f'modifiée il y a moins de {min_age_days} jours'
        elif not git(
            'merge-base', '--is-ancestor', sha, f'origin/{default_branch}',
            check=False,
        ).returncode or sha in pull_heads:
            safe[branch] = sha
        else:
            archive[branch] = sha
    return heads, kept, safe, archive


def archive_branches(archive):
    items = list(archive.items())
    for start in range(0, len(items), 50):
        chunk = items[start:start + 50]
        git('push', '--quiet', 'origin',
            *[f'{sha}:{ARCHIVE_PREFIX}{branch}' for branch, sha in chunk])
    stored = {
        ref[len(ARCHIVE_PREFIX):]: sha
        for ref, sha in remote_refs(f'{ARCHIVE_PREFIX}*').items()
    }
    missing = [branch for branch, sha in archive.items() if stored.get(branch) != sha]
    if missing:
        raise SystemExit(
            'Archive incomplète, aucune branche supprimée : ' + ', '.join(missing)
        )


def delete_branches(branches):
    items = list(branches.items())
    deleted, refused = [], []
    for start in range(0, len(items), BATCH):
        chunk = items[start:start + BATCH]
        result = git(
            'push', '--porcelain', 'origin',
            *[f'--force-with-lease=refs/heads/{b}:{sha}' for b, sha in chunk],
            *[f':refs/heads/{b}' for b, _ in chunk],
            check=False,
        )
        for line in result.stdout.splitlines():
            if line.startswith('-\t'):
                deleted.append(line.split('\t')[1].split(':')[1])
            elif line.startswith('!\t'):
                refused.append(line)
        if result.returncode and not result.stdout.strip():
            raise SystemExit(f'Suppression interrompue :\n{result.stderr}')
    return deleted, refused


def report(lines):
    text = '\n'.join(lines) + '\n'
    print(text, end='')
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as handle:
            handle.write(text.replace('\n', '  \n'))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--default-branch', required=True)
    parser.add_argument('--open-heads', required=True,
                        help='fichier : une tête de demande ouverte par ligne')
    parser.add_argument('--min-age-days', type=float, default=3)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()

    with open(args.open_heads, encoding='utf-8') as handle:
        open_heads = {line.strip() for line in handle if line.strip()}

    heads, kept, safe, archive = classify(
        args.default_branch, open_heads, args.min_age_days
    )
    lines = [
        f'Branches : {len(heads)}',
        f'Conservées : {len(kept)}',
        *[f'- {branch} ({reason})' for branch, reason in kept.items()],
        f'À supprimer (contenu déjà dans {args.default_branch} '
        f'ou gardé par une demande de fusion) : {len(safe)}',
        f'À archiver puis supprimer : {len(archive)}',
        *[f'- {branch}' for branch in archive],
    ]
    if not args.apply:
        report(lines + ['Mode analyse : rien n’a été modifié.'])
        return

    if archive:
        archive_branches(archive)
        lines.append(f'Archives créées et vérifiées : {len(archive)}')
    deleted, refused = delete_branches({**safe, **archive})
    lines.append(f'Branches supprimées : {len(deleted)}')
    if refused:
        lines.append(f'Suppressions refusées : {len(refused)}')
        lines.extend(f'- {line}' for line in refused[:50])
    remaining = remote_refs('refs/heads/*')
    lines.append(f'Branches restantes : {len(remaining)}')
    report(lines)


if __name__ == '__main__':
    main()
