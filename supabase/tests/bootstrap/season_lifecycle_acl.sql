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

-- Contrat RLS actuel des pronostics saisonniers : chacun voit ses propres
-- pronostics, ceux des autres ne sont révélés qu'après verrou ou archivage,
-- et toute écriture est limitée à une saison ouverte et non verrouillée.
drop policy if exists read_own_season_predictions
on public.season_predictions;
drop policy if exists own_season_predictions_insert
on public.season_predictions;
drop policy if exists own_season_predictions_update
on public.season_predictions;
drop policy if exists authenticated_read_season_predictions
on public.season_predictions;
drop policy if exists season_predictions_owner_insert
on public.season_predictions;
drop policy if exists season_predictions_owner_update
on public.season_predictions;

create policy authenticated_read_season_predictions
on public.season_predictions for select to authenticated
using (
  predictor_profile_id = (select auth.uid())
  or exists (
    select 1
    from public.seasons s
    where s.id = season_predictions.season_id
      and (
        s.season_predictions_locked_at is not null
        or s.status = 'archived'
      )
  )
);

create policy season_predictions_owner_insert
on public.season_predictions for insert to authenticated
with check (
  predictor_profile_id = (select auth.uid())
  and (select private.is_active_profile())
  and exists (
    select 1
    from public.seasons s
    where s.id = season_predictions.season_id
      and s.status = 'open'
      and s.season_predictions_locked_at is null
  )
);

create policy season_predictions_owner_update
on public.season_predictions for update to authenticated
using (predictor_profile_id = (select auth.uid()))
with check (
  predictor_profile_id = (select auth.uid())
  and (select private.is_active_profile())
  and exists (
    select 1
    from public.seasons s
    where s.id = season_predictions.season_id
      and s.status = 'open'
      and s.season_predictions_locked_at is null
  )
);

-- Le schéma minimal ne rejoue pas les anciennes migrations qui avaient créé
-- ces triggers. On restaure ici leurs contrats de production afin que les
-- fixtures vérifient réellement préremplissage et validation métier.
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

create or replace function public.validate_season_prediction_row()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_player_season_id uuid;
  v_is_goalkeeper boolean;
  v_is_active boolean;
  v_max_value integer;
begin
  select sp.season_id, sp.is_goalkeeper, sp.is_active
  into v_player_season_id, v_is_goalkeeper, v_is_active
  from public.season_players sp
  where sp.id = new.season_player_id;

  if not found then
    raise exception 'Joueur de saison introuvable.' using errcode = '23503';
  end if;

  if v_player_season_id <> new.season_id then
    raise exception 'Le joueur n’appartient pas à cette saison.' using errcode = '23514';
  end if;

  if not v_is_active then
    raise exception 'Ce joueur n’est plus actif pour cette saison.' using errcode = '23514';
  end if;

  if v_is_goalkeeper and new.category <> 'clean_sheets' then
    raise exception 'Un gardien doit être pronostiqué en clean sheets.' using errcode = '23514';
  end if;

  if not v_is_goalkeeper and new.category <> 'buts' then
    raise exception 'Un joueur de champ doit être pronostiqué en buts.' using errcode = '23514';
  end if;

  v_max_value := case when v_is_goalkeeper then 30 else 99 end;
  if new.predicted_value_30 < 0 or new.predicted_value_30 > v_max_value then
    raise exception 'Valeur de pronostic hors limites.' using errcode = '22003';
  end if;

  return new;
end;
$function$;

revoke execute on function public.validate_season_prediction_row()
from public, anon, authenticated;
grant execute on function public.validate_season_prediction_row()
to service_role;

drop trigger if exists trg_validate_season_prediction_row
on public.season_predictions;
create trigger trg_validate_season_prediction_row
before insert or update of season_id, season_player_id, category, predicted_value_30
on public.season_predictions
for each row execute function public.validate_season_prediction_row();

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

  if (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename = 'season_predictions'
      and policyname in (
        'authenticated_read_season_predictions',
        'season_predictions_owner_insert',
        'season_predictions_owner_update'
      )
  ) <> 3 then
    raise exception 'Bootstrap assertion failed: season prediction policies differ from production';
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

  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.season_predictions'::regclass
      and tgname = 'trg_validate_season_prediction_row'
      and not tgisinternal
  ) then
    raise exception 'Bootstrap assertion failed: season prediction validator trigger is missing';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.seed_season_predictions_for_player()',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.validate_season_prediction_row()',
       'EXECUTE'
     ) then
    raise exception 'Bootstrap assertion failed: trigger function is directly executable';
  end if;
end;
$block$;

commit;
