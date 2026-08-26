"""Genere la migration du lot 1 : heure, adresse, type et journee sur l'archive."""
import json
import os
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
db = json.load(open(os.path.join(HERE, 'db_matches.json'), encoding='utf-8'))
se_all = json.load(open('/home/user/AS-Grinta/tool/sporteasy/data/matches_full.json',
                        encoding='utf-8'))
se = {}
for m in se_all.values():
    if m['annule'] or m['score_grinta'] is None:
        continue
    se[m['date']] = m

TYPES = {'championnat', 'amical', 'entre_nous'}

rows = []
sans_corresp = []
stats = Counter()
rounds_par_saison = defaultdict(list)

for r in db:
    m = se.get(r['match_date'])
    if not m:
        sans_corresp.append(r['match_date'])
        continue
    mt = m['type'] if m['type'] in TYPES else None
    if mt is None:
        stats['type_non_convertible'] += 1
    rnd = m['journee'] if mt == 'championnat' else None
    if rnd is not None and rnd <= 0:
        rnd = None
    heure = m['heure'] or None
    adresse = (m['adresse'] or '').strip() or None
    stats['heure'] += 1 if heure else 0
    stats['adresse'] += 1 if adresse else 0
    stats['type'] += 1 if mt else 0
    stats['journee'] += 1 if rnd else 0
    if rnd:
        rounds_par_saison[m['saison']].append(rnd)
    rows.append((r['id'], heure, adresse, mt, rnd))

print('matchs de la base couverts :', len(rows), '/', len(db))
print('sans correspondance        :', sans_corresp)
print('a remplir ->', dict(stats))
print()
print('--- journees en double dans une meme saison ? ---')
souci = False
for saison, lst in sorted(rounds_par_saison.items()):
    dup = [j for j, n in Counter(lst).items() if n > 1]
    if dup:
        souci = True
        print('  %s : journees repetees %s' % (saison, sorted(dup)))
if not souci:
    print('  aucune')

print()
print('--- repartition des types ---')
print(Counter(t for _, _, _, t, _ in rows))


def sql_txt(v):
    if v is None:
        return 'null'
    return "'" + str(v).replace("'", "''") + "'"


lines = []
for mid, heure, adresse, mt, rnd in rows:
    lines.append('  (%s::uuid, %s::time, %s::text, %s::text, %s::integer)' % (
        sql_txt(mid), sql_txt(heure), sql_txt(adresse), sql_txt(mt),
        rnd if rnd else 'null'))

sql = """-- Lot 1 de l'import SportEasy : complete l'archive avec l'heure de coup
-- d'envoi, l'adresse, le type de match et la journee de championnat.
--
-- Ces quatre colonnes ont ete ajoutees vides le 2026-08-26 en prevision d'un
-- import plus riche. Elles sont ici remplies a partir du releve SportEasy du
-- 2026-08-26 (tool/sporteasy/data/matches_full.json).
--
-- Aucun score, aucun joueur, aucun classement n'est touche : le releve est
-- identique a l'archive sur ces points, verification faite match par match.
-- Les rencontres dont SportEasy ne connait pas le type (tournois) gardent
-- match_type a null : l'application les affiche alors en gris, sans libelle,
-- plutot que d'inventer une categorie.

begin;

create temporary table tmp_sporteasy_lot1 (
  match_id uuid primary key,
  match_time time,
  address text,
  match_type text,
  championship_round integer
) on commit drop;

insert into tmp_sporteasy_lot1
  (match_id, match_time, address, match_type, championship_round)
values
%s;

-- Garde-fou : on ne met a jour que des lignes existantes et connues.
do $verif$
declare
  v_absents integer;
begin
  select count(*) into v_absents
  from tmp_sporteasy_lot1 t
  where not exists (
    select 1 from public.historical_match_scores h where h.id = t.match_id
  );
  if v_absents > 0 then
    raise exception 'Lot 1 : %% lignes ne correspondent a aucun match archive', v_absents;
  end if;
end;
$verif$;

update public.historical_match_scores h
set match_time = t.match_time,
    address = t.address,
    match_type = t.match_type,
    championship_round = t.championship_round
from tmp_sporteasy_lot1 t
where h.id = t.match_id;

-- Controle de sortie : le compte doit correspondre exactement.
do $controle$
declare
  v_type integer;
  v_heure integer;
begin
  select count(*) filter (where match_type is not null),
         count(*) filter (where match_time is not null)
  into v_type, v_heure
  from public.historical_match_scores;

  if v_type <> %d then
    raise exception 'Lot 1 : %% matchs typés au lieu de %d', v_type;
  end if;
  if v_heure <> %d then
    raise exception 'Lot 1 : %% matchs horodatés au lieu de %d', v_heure;
  end if;
end;
$controle$;

commit;
""" % (',\n'.join(lines), stats['type'], stats['type'], stats['heure'], stats['heure'])

out = '/home/user/AS-Grinta/supabase/migrations/20260826150000_sporteasy_history_metadata_lot1.sql'
open(out, 'w', encoding='utf-8').write(sql)
print()
print('migration ecrite :', out, len(sql), 'caracteres')
