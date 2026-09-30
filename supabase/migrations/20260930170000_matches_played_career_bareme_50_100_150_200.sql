-- Nouveau bareme des badges "matchs joues - carriere".
--
-- Les paliers passent de 50 / 100 / 200 / 300 a 50 / 100 / 150 / 200 :
-- "Cadre du club" a 150 matchs, "Legende du club" a 200 matchs.
--
-- Chaque palier garde son identifiant interne (id), donc son visuel, sa
-- couleur, son etoile et sa place dans la liste. Seuls le code lisible, le
-- seuil et la description changent.
--
-- Comme le code du badge contient le seuil, les renommages sont faits dans
-- l'ordre 200 -> 150, puis 300 -> 200 : chaque code cible est libere avant
-- d'etre reutilise. L'ensemble est protege par un test d'entree, pour qu'un
-- rejeu accidentel ne decale pas une seconde fois les paliers.
--
-- Les attributions sont ensuite recalculees : les joueurs qui depassent
-- desormais un palier abaisse recoivent le badge correspondant. Aucun palier
-- n'est releve ici, donc aucun badge n'est retire.

begin;

set local lock_timeout = '5s';

do $migration$
begin
  if not exists (select 1 from public.badges where code = 'matches_played__300') then
    raise notice 'bareme matches_played 50/100/150/200 deja applique, aucun renommage a faire';
    return;
  end if;

  -- Le marqueur "deja vu" suit le badge renomme, pour ne pas re-notifier un
  -- palier que le joueur possede et a deja consulte.
  update public.profile_badge_seen set badge_code = 'matches_played__150' where badge_code = 'matches_played__200';
  update public.profile_badge_seen set badge_code = 'matches_played__200' where badge_code = 'matches_played__300';

  update public.badges
  set code = 'matches_played__150',
      threshold = 150,
      description = 'Atteindre 150 matchs joués avec le club.'
  where code = 'matches_played__200';

  update public.badges
  set code = 'matches_played__200',
      threshold = 200,
      description = 'Atteindre 200 matchs joués avec le club.'
  where code = 'matches_played__300';
end;
$migration$;

-- Garde-fou : quand le catalogue est present, le bareme doit etre exactement
-- 50 / 100 / 150 / 200. Une base neuve (integration continue) applique les
-- migrations sur un catalogue vide, alimente ensuite par supabase/seed.sql :
-- il n'y a alors rien a verifier.
do $check$
declare
  v_thresholds integer[];
begin
  select array_agg(threshold order by threshold)
    into v_thresholds
  from public.badges
  where metric = 'matches_played';

  if v_thresholds is not null and v_thresholds is distinct from array[50, 100, 150, 200] then
    raise exception 'bareme matches_played inattendu : %', v_thresholds;
  end if;
end;
$check$;

select public.recalculate_all_badges();

commit;
