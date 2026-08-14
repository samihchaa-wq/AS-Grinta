-- Nouveau bareme des badges "matchs joues - carriere".
--
-- Les quatre paliers passent de 150 / 200 / 250 / 300 a 50 / 100 / 200 / 300.
-- Le dernier palier (Legende du club) ne bouge pas.
--
-- Chaque palier garde son identifiant interne (id), donc son visuel, sa
-- couleur, son etoile et sa place dans la liste. Seuls le code lisible, le
-- seuil et la description changent.
--
-- Comme le code du badge contient le seuil, les renommages sont faits dans
-- l'ordre 150 -> 50, 200 -> 100, 250 -> 200 : chaque code cible est libere
-- avant d'etre reutilise, sans collision avec l'unicite du code. L'ensemble
-- est protege par un test d'entree, pour qu'un rejeu accidentel ne decale pas
-- une seconde fois les paliers.
--
-- Les attributions sont ensuite recalculees : les joueurs qui depassent
-- desormais un palier abaisse recoivent le badge correspondant. Aucun palier
-- n'est releve ici, donc aucun badge n'est retire.

begin;

set local lock_timeout = '5s';

do $migration$
begin
  if not exists (select 1 from public.badges where code = 'matches_played__150') then
    raise notice 'bareme matches_played deja applique, aucun renommage a faire';
    return;
  end if;

  -- Le marqueur "deja vu" suit le badge renomme, pour ne pas re-notifier un
  -- palier que le joueur possede et a deja consulte.
  update public.profile_badge_seen set badge_code = 'matches_played__50' where badge_code = 'matches_played__150';
  update public.profile_badge_seen set badge_code = 'matches_played__100' where badge_code = 'matches_played__200';
  update public.profile_badge_seen set badge_code = 'matches_played__200' where badge_code = 'matches_played__250';

  update public.badges
  set code = 'matches_played__50',
      threshold = 50,
      description = 'Atteindre 50 matchs joués avec le club.'
  where code = 'matches_played__150';

  update public.badges
  set code = 'matches_played__100',
      threshold = 100,
      description = 'Atteindre 100 matchs joués avec le club.'
  where code = 'matches_played__200';

  update public.badges
  set code = 'matches_played__200',
      threshold = 200,
      description = 'Atteindre 200 matchs joués avec le club.'
  where code = 'matches_played__250';
end;
$migration$;

-- Garde-fou : le bareme attendu doit etre exactement 50 / 100 / 200 / 300.
do $check$
declare
  v_thresholds integer[];
begin
  select array_agg(threshold order by threshold)
    into v_thresholds
  from public.badges
  where metric = 'matches_played';

  if v_thresholds is distinct from array[50, 100, 200, 300] then
    raise exception 'bareme matches_played inattendu : %', v_thresholds;
  end if;
end;
$check$;

select public.recalculate_all_badges();

commit;
