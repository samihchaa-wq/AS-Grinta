#!/usr/bin/env python3
"""Compare les fonctions SQL du dépôt avec celles de la production.

Les deux fichiers d'entrée sont produits par la même requête,
`supabase/diagnostics/function_definitions_snapshot.sql` : l'un sur une base
reconstruite depuis les migrations du dépôt, l'autre sur la production.

Pour chaque fonction des schémas `public` et `private`, le script compare :

- le corps, sans tenir compte des commentaires, des espaces ni de la casse des
  mots-clés et identifiants non entre guillemets (PostgreSQL les met de toute
  façon en minuscules) ; le texte des chaînes et des identifiants entre
  guillemets reste comparé à l'octet près ;
- `SECURITY DEFINER` ;
- la configuration (`search_path`, etc.) ;
- les droits d'exécution ;
- l'en-tête : langage, arguments et valeurs par défaut, type de retour,
  volatilité et propriétaire.

Une fonction présente d'un seul côté est aussi une différence. Le script sort
en erreur dès qu'une différence réelle existe.

Le corps d'une fonction de production n'est jamais affiché : seul l'extrait du
dépôt, déjà public, sert à situer la différence.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

WORD_CHARS = re.compile(r"[A-Za-z0-9_$\u0080-\U0010FFFF]")
DOLLAR_TAG = re.compile(r"\$([A-Za-z_\u0080-\U0010FFFF][A-Za-z0-9_\u0080-\U0010FFFF]*)?\$")


def body_tokens(source: str) -> list[str]:
    """Découpe un corps de fonction en éléments significatifs.

    Les commentaires et les espaces disparaissent ; les chaînes, les
    identifiants entre guillemets et les blocs `$tag$ ... $tag$` sont gardés
    tels quels ; le reste est mis en minuscules.
    """

    tokens: list[str] = []
    i = 0
    n = len(source)
    while i < n:
        char = source[i]

        if char.isspace():
            i += 1
            continue

        if source.startswith("--", i):
            end = source.find("\n", i)
            i = n if end == -1 else end + 1
            continue

        if source.startswith("/*", i):
            depth = 0
            while i < n:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                    if depth == 0:
                        break
                else:
                    i += 1
            continue

        if char == "'":
            j = i + 1
            escaped = bool(tokens) and tokens[-1] == "e" and i > 0 and source[i - 1] in "eE"
            while j < n:
                if escaped and source[j] == "\\":
                    j += 2
                    continue
                if source[j] == "'":
                    if j + 1 < n and source[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            tokens.append(source[i : j + 1])
            i = j + 1
            continue

        if char == '"':
            j = i + 1
            while j < n:
                if source[j] == '"':
                    if j + 1 < n and source[j + 1] == '"':
                        j += 2
                        continue
                    break
                j += 1
            tokens.append(source[i : j + 1])
            i = j + 1
            continue

        if char == "$":
            match = DOLLAR_TAG.match(source, i)
            if match:
                tag = match.group(0)
                end = source.find(tag, match.end())
                end = n if end == -1 else end + len(tag)
                tokens.append(source[i:end])
                i = end
                continue

        if WORD_CHARS.match(char):
            j = i + 1
            while j < n and WORD_CHARS.match(source[j]):
                j += 1
            tokens.append(source[i:j].lower())
            i = j
            continue

        tokens.append(char)
        i += 1

    return tokens


def load_snapshot(path: Path) -> dict[str, dict]:
    """Lit un instantané produit par psql ou par l'API de gestion Supabase."""

    raw = json.loads(path.read_text(encoding="utf-8"))
    # L'API de gestion renvoie une liste de lignes : [{"snapshot": [...]}].
    if isinstance(raw, dict) and "result" in raw:
        raw = raw["result"]
    if (
        isinstance(raw, list)
        and len(raw) == 1
        and isinstance(raw[0], dict)
        and "snapshot" in raw[0]
    ):
        raw = raw[0]["snapshot"]
    if isinstance(raw, str):
        raw = json.loads(raw)
    if not isinstance(raw, list):
        raise SystemExit(f"{path} : instantané illisible.")
    functions = {}
    for item in raw:
        functions[item["signature"]] = item
    if not functions:
        raise SystemExit(f"{path} : aucune fonction lue, instantané vide.")
    return functions


HEADER_FIELDS = (
    ("language", "langage"),
    ("arguments", "arguments"),
    ("result", "type de retour"),
    ("volatility", "volatilité"),
    ("kind", "nature"),
    ("owner", "propriétaire"),
)


def first_difference(code: list[str], production: list[str]) -> int:
    for index, (left, right) in enumerate(zip(code, production)):
        if left != right:
            return index
    return min(len(code), len(production))


def compare(code: dict[str, dict], production: dict[str, dict]) -> list[str]:
    findings: list[str] = []

    for signature in sorted(set(code) - set(production)):
        findings.append(f"{signature}\n  présente dans le dépôt, absente en production")
    for signature in sorted(set(production) - set(code)):
        findings.append(f"{signature}\n  présente en production, absente du dépôt")

    for signature in sorted(set(code) & set(production)):
        left = code[signature]
        right = production[signature]
        details: list[str] = []

        for field, label in HEADER_FIELDS:
            if left.get(field) != right.get(field):
                details.append(
                    f"{label} : dépôt={left.get(field)!r} production={right.get(field)!r}"
                )

        if bool(left.get("security_definer")) != bool(right.get("security_definer")):
            details.append(
                "SECURITY DEFINER : "
                f"dépôt={bool(left.get('security_definer'))} "
                f"production={bool(right.get('security_definer'))}"
            )

        left_config = sorted(left.get("config") or [])
        right_config = sorted(right.get("config") or [])
        if left_config != right_config:
            details.append(f"configuration : dépôt={left_config} production={right_config}")

        left_grants = sorted(left.get("grants") or [])
        right_grants = sorted(right.get("grants") or [])
        if left_grants != right_grants:
            only_code = sorted(set(left_grants) - set(right_grants))
            only_prod = sorted(set(right_grants) - set(left_grants))
            details.append(
                f"droits : seulement dans le dépôt={only_code} "
                f"seulement en production={only_prod}"
            )

        left_tokens = body_tokens(left.get("body") or "")
        right_tokens = body_tokens(right.get("body") or "")
        if left_tokens != right_tokens:
            index = first_difference(left_tokens, right_tokens)
            excerpt = " ".join(left_tokens[max(0, index - 12) : index + 12])
            details.append(
                "corps : différent (hors commentaires et espaces) à partir de "
                f"l'élément {index + 1} ; extrait du dépôt : … {excerpt} …"
            )

        if details:
            findings.append(signature + "\n" + "\n".join(f"  {line}" for line in details))

    return findings


def self_test() -> None:
    same = [
        ("begin\n  return 1; -- un\nend;", "BEGIN return 1;\n/* deux */ END;"),
        ("select a  ,b from t", "select a,b from t"),
        ("perform f( x )", "perform f(x)"),
        ("select $x$ a  b $x$", "select $x$ a  b $x$"),
        ("/* a /* b */ c */ select 1", "select 1"),
    ]
    different = [
        ("select 'a  b'", "select 'a b'"),
        ('select "Mixed"', 'select "mixed"'),
        ("select $x$ a  b $x$", "select $x$ a b $x$"),
        ("perform private.assert_match_admin_edit_open(p_match_id);", ""),
        ("select 1 -- x\n + 2", "select 1"),
        ("select e'it\\'s -- here'", "select e'it\\'s'"),
    ]
    for left, right in same:
        assert body_tokens(left) == body_tokens(right), (left, right)
    for left, right in different:
        assert body_tokens(left) != body_tokens(right), (left, right)

    base = {
        "signature": "public.f(p uuid)",
        "owner": "postgres",
        "kind": "f",
        "language": "plpgsql",
        "security_definer": True,
        "volatility": "v",
        "config": ['search_path=""'],
        "arguments": "p uuid",
        "result": "jsonb",
        "body": "begin return null; end;",
        "grants": ["authenticated:EXECUTE", "postgres:EXECUTE"],
    }
    assert compare({"f": base}, {"f": dict(base, body="BEGIN\n return null; -- ok\nEND;")}) == []
    assert compare({"f": base}, {"f": dict(base, security_definer=False)})
    assert compare({"f": base}, {"f": dict(base, config=[])})
    assert compare({"f": base}, {"f": dict(base, grants=["postgres:EXECUTE"])})
    assert compare({"f": base}, {"f": dict(base, language="sql")})
    assert compare({"f": base}, {})
    print("Auto-test de la comparaison : OK")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--code", type=Path, help="instantané de la base reconstruite")
    parser.add_argument("--production", type=Path, help="instantané de la production")
    parser.add_argument("--summary", type=Path, help="fichier Markdown de résumé (facultatif)")
    parser.add_argument("--self-test", action="store_true", help="vérifie la comparaison elle-même")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        if not args.code:
            return 0

    if not args.code or not args.production:
        parser.error("--code et --production sont obligatoires")

    code = load_snapshot(args.code)
    production = load_snapshot(args.production)
    findings = compare(code, production)

    lines = [
        "## Contenu des fonctions : dépôt contre production",
        "",
        f"- Fonctions comparées : {len(set(code) | set(production))} "
        f"(dépôt {len(code)}, production {len(production)})",
        f"- Différences réelles : {len(findings)}",
    ]
    if findings:
        lines += ["", "```text", *("\n".join(findings).splitlines()), "```"]
    report = "\n".join(lines) + "\n"
    print(report)
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as handle:
            handle.write(report)

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
