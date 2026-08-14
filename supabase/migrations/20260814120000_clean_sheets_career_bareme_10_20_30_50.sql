-- Nouveau bareme des badges "clean sheets - carriere".
--
-- Les quatre paliers passent de 15 / 25 / 50 / 100 a 10 / 20 / 30 / 50.
-- Chaque palier garde son identifiant interne (id), donc son visuel, sa
-- couleur, son etoile et sa place dans la liste. Seuls le code lisible, le
-- seuil et la description changent.
--
-- Comme le code du badge contient le seuil, les renommages sont faits dans
-- l'ordre 15 -> 10, 25 -> 20, 50 -> 30, 100 -> 50 : chaque code cible est
-- libere avant d'etre reutilise, sans collision avec l'unicite du code.
-- L'ensemble est protege par un test d'entree, pour qu'un rejeu accidentel
-- ne decale pas une seconde fois les paliers.
--
-- Les attributions sont ensuite recalculees : les joueurs qui depassent
-- desormais un palier abaisse recoivent le badge correspondant. Aucun palier
-- n'est releve ici, donc aucun badge n'est retire.

begin;

set local lock_timeout = '5s';

do $migration$
begin
  if not exists (select 1 from public.badges where code = 'clean_sheets__15') then
    raise notice 'bareme clean_sheets deja applique, aucun renommage a faire';
    return;
  end if;

  -- Le marqueur "deja vu" suit le badge renomme, pour ne pas re-notifier un
  -- palier que le joueur possede et a deja consulte.
  update public.profile_badge_seen set badge_code = 'clean_sheets__10' where badge_code = 'clean_sheets__15';
  update public.profile_badge_seen set badge_code = 'clean_sheets__20' where badge_code = 'clean_sheets__25';
  update public.profile_badge_seen set badge_code = 'clean_sheets__30' where badge_code = 'clean_sheets__50';
  update public.profile_badge_seen set badge_code = 'clean_sheets__50' where badge_code = 'clean_sheets__100';

  update public.badges
  set code = 'clean_sheets__10',
      threshold = 10,
      description = 'Atteindre 10 matchs sans encaisser de but avec le club.'
  where code = 'clean_sheets__15';

  update public.badges
  set code = 'clean_sheets__20',
      threshold = 20,
      description = 'Atteindre 20 matchs sans encaisser de but avec le club.'
  where code = 'clean_sheets__25';

  update public.badges
  set code = 'clean_sheets__30',
      threshold = 30,
      description = 'Atteindre 30 matchs sans encaisser de but avec le club.'
  where code = 'clean_sheets__50';

  update public.badges
  set code = 'clean_sheets__50',
      threshold = 50,
      description = 'Atteindre 50 matchs sans encaisser de but avec le club.'
  where code = 'clean_sheets__100';
end;
$migration$;

-- Garde-fou : le bareme attendu doit etre exactement 10 / 20 / 30 / 50.
do $check$
declare
  v_thresholds integer[];
begin
  select array_agg(threshold order by threshold)
    into v_thresholds
  from public.badges
  where metric = 'clean_sheets';

  if v_thresholds is distinct from array[10, 20, 30, 50] then
    raise exception 'bareme clean_sheets inattendu : %', v_thresholds;
  end if;
end;
$check$;

select public.recalculate_all_badges();

commit;
