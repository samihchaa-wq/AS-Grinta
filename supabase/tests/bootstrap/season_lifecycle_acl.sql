begin;

-- La baseline locale reproduit les ACL et politiques actuellement présentes
-- en production pour l'administration des saisons.
grant select, insert, update, delete
on table public.seasons
to authenticated;

drop policy if exists seasons_staff_insert on public.seasons;
create policy seasons_staff_insert
on public.seasons for insert to authenticated
with check ((select private.is_match_staff()));

drop policy if exists seasons_staff_update on public.seasons;
create policy seasons_staff_update
on public.seasons for update to authenticated
using ((select private.is_match_staff()))
with check ((select private.is_match_staff()));

drop policy if exists seasons_staff_delete on public.seasons;
create policy seasons_staff_delete
on public.seasons for delete to authenticated
using ((select private.is_match_staff()));

-- Le schéma minimal ne rejoue pas l'ancienne migration qui avait créé ce
-- trigger. On restaure ici son contrat de production afin que les fixtures
-- vérifient réellement le préremplissage automatique des pronostics saisonniers.
create or replace function public.seed_season_predictions_for_player()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  insert into public.season_predictions(
    season_id, predictor_profile_id, season_player_id, category,
    predicted_value_30, is_filled
  )
  select new.season_id, p.id, new.id,
    case when new.is_goalkeeper then 'clean_sheets' else 'buts' end,
    0, false
  from public.profiles p
  where p.status = 'active'
  on conflict(season_id, predictor_profile_id, season_player_id, category)
    do nothing;
  return new;
end;
$function$;

revoke execute on function public.seed_season_predictions_for_player()
from public, anon, authenticated;
grant execute on function public.seed_season_predictions_for_player()
to service_role;

drop trigger if exists trg_seed_season_predictions_for_player
on public.season_players;
create trigger trg_seed_season_predictions_for_player
after insert on public.season_players
for each row execute function public.seed_season_predictions_for_player();

do $block$
begin
  if not has_table_privilege('authenticated', 'public.seasons', 'SELECT')
     or not has_table_privilege('authenticated', 'public.seasons', 'INSERT')
     or not has_table_privilege('authenticated', 'public.seasons', 'UPDATE')
     or not has_table_privilege('authenticated', 'public.seasons', 'DELETE') then
    raise exception 'Bootstrap assertion failed: season ACL differs from production';
  end if;

  if not (
    select relrowsecurity
    from pg_class
    where oid = 'public.seasons'::regclass
  ) then
    raise exception 'Bootstrap assertion failed: RLS is disabled on seasons';
  end if;

  if (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename = 'seasons'
      and policyname in (
        'seasons_staff_insert',
        'seasons_staff_update',
        'seasons_staff_delete'
      )
  ) <> 3 then
    raise exception 'Bootstrap assertion failed: season staff policies differ from production';
  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.season_players'::regclass
      and tgname = 'trg_seed_season_predictions_for_player'
      and not tgisinternal
  ) then
    raise exception 'Bootstrap assertion failed: season prediction seed trigger is missing';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.seed_season_predictions_for_player()',
       'EXECUTE'
     ) then
    raise exception 'Bootstrap assertion failed: trigger function is directly executable';
  end if;
end;
$block$;

commit;
