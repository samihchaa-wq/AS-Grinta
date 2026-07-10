begin;

-- Les inscriptions directes restent non actives. Seules les invitations du staff
-- peuvent créer un profil actif via raw_user_meta_data.invited=true.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  insert into public.profiles(
    id,email,first_name,last_name,role,is_goalkeeper,status
  ) values (
    new.id,
    coalesce(new.email,''),
    coalesce(new.raw_user_meta_data->>'first_name',''),
    coalesce(new.raw_user_meta_data->>'last_name',''),
    'pronostiqueur',
    false,
    case
      when coalesce((new.raw_user_meta_data->>'invited')::boolean, false)
        then 'active'
      else 'pending'
    end
  )
  on conflict(id) do update
  set email=excluded.email,
      first_name=case when public.profiles.first_name='' then excluded.first_name else public.profiles.first_name end,
      last_name=case when public.profiles.last_name='' then excluded.last_name else public.profiles.last_name end,
      updated_at=now();
  return new;
end;
$$;

-- Le terme moderator désigne désormais uniquement le rôle modérateur exact.
create or replace function public.is_moderator()
returns boolean
language sql
stable
security definer
set search_path='public'
as $$ select public.is_exact_moderator(); $$;

-- Ne jamais supprimer, archiver ou rétrograder le dernier administrateur actif.
create or replace function public.moderator_update_profile_admin_fields(
  p_profile_id uuid,
  p_role text,
  p_status text,
  p_is_goalkeeper boolean
)
returns boolean
language plpgsql
security definer
set search_path='public'
as $$
declare
  current_row public.profiles%rowtype;
  resulting_role text;
  resulting_status text;
  active_admins integer;
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;

  select * into current_row
  from public.profiles
  where id = p_profile_id
  for update;

  if not found then return false; end if;

  if p_role is not null and p_role not in ('pronostiqueur','admin','moderateur') then
    raise exception 'Invalid role';
  end if;
  if p_status is not null and p_status not in ('pending','active','archived') then
    raise exception 'Invalid status';
  end if;

  resulting_role := coalesce(p_role, current_row.role::text);
  resulting_status := coalesce(p_status, current_row.status::text);

  if (p_role is distinct from current_row.role::text or
      p_status is distinct from current_row.status::text)
     and not (public.is_admin() or public.is_exact_moderator()) then
    raise exception 'Admin or moderator role required';
  end if;

  if current_row.role::text = 'admin'
     and current_row.status::text = 'active'
     and (resulting_role <> 'admin' or resulting_status <> 'active') then
    select count(*) into active_admins
    from public.profiles
    where role='admin' and status='active';
    if active_admins <= 1 then
      raise exception 'The last active administrator cannot be removed or archived';
    end if;
  end if;

  update public.profiles
  set role=resulting_role,
      status=resulting_status,
      is_goalkeeper=coalesce(p_is_goalkeeper,is_goalkeeper),
      updated_at=now()
  where id=p_profile_id;
  return true;
end;
$$;

-- Les pronostics sont réservés aux pronostiqueurs actifs.
create or replace function public.seed_match_predictions()
returns trigger
language plpgsql
security definer
set search_path='public'
as $$
begin
  insert into public.match_predictions(
    match_id,profile_id,predicted_score_as_grinta,predicted_score_adverse,is_filled
  )
  select new.id,id,0,0,false
  from public.profiles
  where status='active' and role='pronostiqueur'
  on conflict(match_id,profile_id) do nothing;
  return new;
end;
$$;

create or replace function public.seed_predictions_for_active_profile()
returns trigger
language plpgsql
security definer
set search_path='public'
as $$
begin
  if new.status<>'active' or new.role<>'pronostiqueur' then return new; end if;

  insert into public.match_predictions(
    match_id,profile_id,predicted_score_as_grinta,predicted_score_adverse,is_filled
  )
  select id,new.id,0,0,false
  from public.matches
  where status='a_venir'
  on conflict(match_id,profile_id) do nothing;

  insert into public.season_predictions(
    season_id,predictor_profile_id,player_profile_id,category,predicted_value_20,is_filled
  )
  select sp.season_id,new.id,sp.profile_id,c.category,0,false
  from public.season_players sp
  join public.seasons s on s.id=sp.season_id and s.status='open'
  cross join lateral unnest(
    case when sp.is_goalkeeper_snapshot
      then array['clean_sheets','penalty_faults']::text[]
      else array['buts','passes','hommes_du_match','penalty_faults']::text[]
    end
  ) c(category)
  on conflict(season_id,predictor_profile_id,player_profile_id,category) do nothing;
  return new;
end;
$$;

create or replace function public.seed_season_predictions_for_player()
returns trigger
language plpgsql
security definer
set search_path='public'
as $$
begin
  insert into public.season_predictions(
    season_id,predictor_profile_id,player_profile_id,category,predicted_value_20,is_filled
  )
  select new.season_id,p.id,new.profile_id,c.category,0,false
  from public.profiles p
  cross join lateral unnest(
    case when new.is_goalkeeper_snapshot
      then array['clean_sheets','penalty_faults']::text[]
      else array['buts','passes','hommes_du_match','penalty_faults']::text[]
    end
  ) c(category)
  where p.status='active' and p.role='pronostiqueur'
  on conflict(season_id,predictor_profile_id,player_profile_id,category) do nothing;
  return new;
end;
$$;

create or replace function public.validate_season_prediction_category()
returns trigger
language plpgsql
set search_path='public'
as $$
declare goalkeeper boolean;
begin
  select is_goalkeeper_snapshot into goalkeeper
  from public.season_players
  where season_id=new.season_id and profile_id=new.player_profile_id;

  if goalkeeper is null then
    raise exception 'Player is not in the season squad';
  end if;

  if goalkeeper and new.category not in ('clean_sheets','penalty_faults') then
    raise exception 'Invalid goalkeeper prediction category';
  end if;
  if not goalkeeper and new.category not in ('buts','passes','hommes_du_match','penalty_faults') then
    raise exception 'Invalid outfield prediction category';
  end if;
  return new;
end;
$$;

-- Backfill des fautes provoquant un penalty pour la saison ouverte.
insert into public.season_predictions(
  season_id,predictor_profile_id,player_profile_id,category,predicted_value_20,is_filled
)
select sp.season_id,p.id,sp.profile_id,'penalty_faults',0,false
from public.season_players sp
join public.seasons s on s.id=sp.season_id and s.status='open'
join public.profiles p on p.status='active' and p.role='pronostiqueur'
on conflict(season_id,predictor_profile_id,player_profile_id,category) do nothing;

-- Supprime les lignes de pronostics attribuées par erreur aux comptes staff.
delete from public.match_predictions mp
using public.profiles p
where p.id=mp.profile_id and p.role<>'pronostiqueur';

delete from public.season_predictions sp
using public.profiles p
where p.id=sp.predictor_profile_id and p.role<>'pronostiqueur';

-- Classement limité aux pronostiqueurs actifs.
create or replace view public.v_classement_general
with (security_invoker=true)
as
with mt as (
  select profile_id,coalesce(sum(points),0::numeric) as match_points
  from public.v_match_prediction_points
  group by profile_id
), st as (
  select predictor_profile_id as profile_id,
         coalesce(sum(points),0::bigint)::numeric as season_points
  from public.v_season_prediction_points
  group by predictor_profile_id
), match_max as (
  select coalesce(sum(
    case
      when m.score_as_grinta>m.score_adverse then mo.odds_victoire_as_grinta
      when m.score_as_grinta=m.score_adverse then mo.odds_nul
      else mo.odds_victoire_adverse
    end * 15::numeric
  ),0::numeric) as max_points
  from public.matches m
  join public.match_odds mo on mo.match_id=m.id
  where m.status in ('termine','archive')
    and m.score_as_grinta is not null
    and m.score_adverse is not null
), season_expected as (
  select sp.predictor_profile_id as profile_id,count(*)::numeric*20::numeric as max_points
  from public.season_predictions sp
  join public.seasons s on s.id=sp.season_id
  left join public.v_player_season_stats stats
    on stats.season_id=sp.season_id and stats.profile_id=sp.player_profile_id
  where not (s.status='archived' and coalesce(stats.matches_played,0)<3)
  group by sp.predictor_profile_id
)
select p.id as profile_id,p.first_name,p.last_name,
       coalesce(mt.match_points,0::numeric) as match_points,
       coalesce(st.season_points,0::numeric) as season_points,
       coalesce(mt.match_points,0::numeric)+coalesce(st.season_points,0::numeric) as total_points,
       mm.max_points as match_max_points,
       coalesce(se.max_points,0::numeric) as season_max_points,
       case when mm.max_points>0 then round(100*coalesce(mt.match_points,0)/mm.max_points,2) else 0 end as match_percentage,
       case when coalesce(se.max_points,0)>0 then round(100*coalesce(st.season_points,0)/se.max_points,2) else 0 end as season_percentage,
       p.surnom
from public.profiles p
cross join match_max mm
left join mt on mt.profile_id=p.id
left join st on st.profile_id=p.id
left join season_expected se on se.profile_id=p.id
where p.status='active' and p.role='pronostiqueur';

-- Tokens de revendication : lecture complète uniquement par le staff.
drop policy if exists authenticated_read_players on public.players;
create policy players_staff_read
on public.players for select to authenticated
using (public.is_match_staff());
create policy players_self_read
on public.players for select to authenticated
using (linked_profile_id=(select auth.uid()));

create or replace function public.staff_list_players()
returns table(
  id uuid,first_name text,last_name text,surnom text,is_goalkeeper boolean,
  is_active boolean,linked_profile_id uuid,claimed_at timestamptz,
  claim_token uuid,claim_expires_at timestamptz
)
language sql
stable
security definer
set search_path='public'
as $$
  select p.id,p.first_name,p.last_name,p.surnom,p.is_goalkeeper,p.is_active,
         p.linked_profile_id,p.claimed_at,p.claim_token,p.claim_expires_at
  from public.players p
  where public.is_match_staff()
  order by p.first_name,p.last_name;
$$;
revoke all on function public.staff_list_players() from public,anon;
grant execute on function public.staff_list_players() to authenticated;

-- Les emails ne sont plus exposés dans l'annuaire général.
revoke select on public.profiles from authenticated;
grant select(
  id,first_name,last_name,photo_url,role,is_goalkeeper,status,
  created_at,updated_at,surnom,notify_match_reminders,notify_prediction_reminders
) on public.profiles to authenticated;
grant update(first_name,last_name,surnom,photo_url,updated_at,
  notify_match_reminders,notify_prediction_reminders)
on public.profiles to authenticated;

create or replace function public.staff_list_profiles()
returns table(
  id uuid,first_name text,last_name text,surnom text,email text,photo_url text,
  role text,is_goalkeeper boolean,status text,created_at timestamptz,updated_at timestamptz
)
language sql
stable
security definer
set search_path='public'
as $$
  select p.id,p.first_name,p.last_name,p.surnom,p.email,p.photo_url,
         p.role,p.is_goalkeeper,p.status,p.created_at,p.updated_at
  from public.profiles p
  where public.is_match_staff()
  order by p.first_name,p.last_name;
$$;
revoke all on function public.staff_list_profiles() from public,anon;
grant execute on function public.staff_list_profiles() to authenticated;

-- La validation et les corrections passent uniquement par les RPC SECURITY DEFINER.
drop policy if exists match_player_stats_staff_write on public.match_player_stats;
drop policy if exists match_guest_stats_staff_write on public.match_guest_stats;
drop policy if exists goals_staff_write on public.goals;
revoke insert,update,delete on public.match_player_stats from authenticated;
revoke insert,update,delete on public.match_guest_stats from authenticated;
revoke insert,update,delete on public.goals from authenticated;

-- L'audit technique est réservé au staff.
drop policy if exists match_correction_audit_authenticated_read on public.match_correction_audit;
create policy match_correction_audit_staff_read
on public.match_correction_audit for select to authenticated
using (public.is_match_staff());

-- Création transactionnelle d'un match, de ses cotes et de ses pronostics.
create or replace function public.create_match_with_odds(
  p_season_id uuid,p_opponent_id uuid,p_match_date date,p_match_time time,
  p_location text,p_competition text,p_win numeric,p_draw numeric,p_loss numeric
)
returns uuid
language plpgsql
security definer
set search_path='public'
as $$
declare new_id uuid;
begin
  if not public.is_match_staff() then raise exception 'Staff role required'; end if;
  if p_location not in ('domicile','exterieur') then raise exception 'Invalid location'; end if;
  if btrim(coalesce(p_competition,''))='' then raise exception 'Competition required'; end if;
  if p_win<1.01 or p_draw<1.01 or p_loss<1.01 or p_win>100 or p_draw>100 or p_loss>100 then
    raise exception 'Invalid odds';
  end if;

  insert into public.matches(
    season_id,opponent_id,match_date,match_time,location,competition,
    planned_duration_minutes,status,created_by
  ) values (
    p_season_id,p_opponent_id,p_match_date,p_match_time,p_location,btrim(p_competition),
    90,'a_venir',auth.uid()
  ) returning id into new_id;

  perform public.set_match_odds(new_id,p_win,p_draw,p_loss);
  return new_id;
end;
$$;
revoke all on function public.create_match_with_odds(uuid,uuid,date,time,text,text,numeric,numeric,numeric) from public,anon;
grant execute on function public.create_match_with_odds(uuid,uuid,date,time,text,text,numeric,numeric,numeric) to authenticated;

-- Un seul trigger de verrouillage H-5.
drop trigger if exists match_predictions_window_guard on public.match_predictions;

-- Index nécessaires et suppression des doublons.
create index if not exists idx_match_correction_audit_actor on public.match_correction_audit(actor_profile_id);
create index if not exists idx_match_guest_stats_match on public.match_guest_stats(match_id);
create index if not exists idx_match_player_stats_profile on public.match_player_stats(profile_id);
create index if not exists idx_players_created_by on public.players(created_by);
drop index if exists public.match_participants_match_profile_uidx;
drop index if exists public.match_player_stats_match_profile_uidx;
drop index if exists public.match_predictions_match_profile_uidx;

-- Aucun accès métier anonyme.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;

-- L'extension HTTP de diagnostic n'est pas requise par l'application.
drop extension if exists http;

commit;
