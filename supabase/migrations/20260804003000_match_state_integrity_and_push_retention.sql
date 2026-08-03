-- Prevent impossible match timelines, make deletion complete for Live matches,
-- and stop Web Push subscriptions from growing without bound per profile.

create or replace function private.guard_match_status_chronology()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_kickoff timestamptz;
begin
  if new.match_date is null or new.match_time is null then
    return new;
  end if;

  v_kickoff := (new.match_date + new.match_time) at time zone 'Europe/Paris';

  if new.status = 'termine' and v_kickoff > now() then
    raise exception 'Un match futur ne peut pas être marqué terminé.'
      using errcode = '22023';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_match_status_chronology() from public, anon, authenticated;

drop trigger if exists trg_guard_match_status_chronology on public.matches;
create trigger trg_guard_match_status_chronology
before insert or update of match_date, match_time, status
on public.matches
for each row
execute function private.guard_match_status_chronology();

-- A finished internal match may still be edited for harmless metadata, but the
-- edit must not reopen/reconfigure its pre-match workflow.
create or replace function public.update_internal_match(
  p_match_id uuid,
  p_season_id uuid,
  p_match_date date,
  p_match_time time without time zone
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null or p_season_id is null or p_match_date is null or p_match_time is null then
    raise exception 'Match, saison, date et heure requis.' using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Date de match hors limites.' using errcode = '22023';
  end if;

  select m.status
  into v_status
  from public.matches m
  where m.id = p_match_id
    and m.match_type = 'entre_nous'
  for update;

  if v_status is null then
    raise exception 'Match entre nous introuvable.' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.seasons s where s.id = p_season_id) then
    raise exception 'Saison introuvable.' using errcode = 'P0002';
  end if;

  update public.matches
  set season_id = p_season_id,
      match_date = p_match_date,
      match_time = p_match_time,
      updated_at = now()
  where id = p_match_id;

  if v_status = 'a_venir' then
    perform private.configure_match_sport_workflow(p_match_id, 30);
  end if;

  return true;
end;
$$;

-- Match Live uses RESTRICT foreign keys. Remove its rows before participants
-- and the parent match so the normal admin deletion works for completed tests
-- and for any future Live match that genuinely has to be removed.
create or replace function public.delete_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  perform set_config('as_grinta.allow_postmatch_composition_write', 'on', true);

  delete from public.match_live_events where match_id = p_match_id;
  delete from public.match_live_sessions where match_id = p_match_id;
  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;
  delete from public.match_sport_motm_elections where match_id = p_match_id;
  delete from public.match_composition_entries where match_id = p_match_id;
  delete from public.match_composition_publications where match_id = p_match_id;
  delete from public.match_compositions where match_id = p_match_id;
  delete from public.match_sport_participant_events where match_id = p_match_id;
  delete from public.sport_availability_notification_events where match_id = p_match_id;
  delete from public.match_sport_finalization_versions where match_id = p_match_id;
  delete from public.match_sport_finalizations where match_id = p_match_id;
  delete from public.match_sport_participants where match_id = p_match_id;
  delete from public.match_sport_workflows where match_id = p_match_id;
  delete from public.match_attendance where match_id = p_match_id;
  delete from public.match_player_stats where match_id = p_match_id;
  delete from public.match_predictions where match_id = p_match_id;
  delete from public.match_odds where match_id = p_match_id;
  delete from public.push_delivery_log where match_id = p_match_id;
  delete from public.push_notification_log where match_id = p_match_id;

  delete from public.matches where id = p_match_id;
  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$$;

-- One endpoint remains unique globally. In addition, retain at most the five
-- most recently refreshed endpoints per active profile. This keeps legitimate
-- multi-device use while preventing old PWA/browser installations from
-- accumulating indefinitely and multiplying notifications.
create or replace function public.register_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = actor_id
      and p.status = 'active'
  ) then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;

  if btrim(coalesce(p_endpoint, '')) = ''
     or btrim(coalesce(p_p256dh, '')) = ''
     or btrim(coalesce(p_auth, '')) = '' then
    raise exception 'Invalid push subscription' using errcode = '22023';
  end if;

  if length(p_endpoint) > 2048
     or length(p_p256dh) > 512
     or length(p_auth) > 512
     or length(coalesce(p_user_agent, '')) > 512 then
    raise exception 'Push subscription fields are too long' using errcode = '22001';
  end if;

  insert into public.push_subscriptions(
    profile_id,
    endpoint,
    p256dh,
    auth,
    user_agent
  )
  values (
    actor_id,
    p_endpoint,
    p_p256dh,
    p_auth,
    p_user_agent
  )
  on conflict (endpoint) do update
  set profile_id = excluded.profile_id,
      p256dh = excluded.p256dh,
      auth = excluded.auth,
      user_agent = excluded.user_agent,
      updated_at = now();

  delete from public.push_subscriptions ps
  using (
    select id
    from (
      select
        id,
        row_number() over (order by updated_at desc, created_at desc, id desc) as rn
      from public.push_subscriptions
      where profile_id = actor_id
    ) ranked
    where rn > 5
  ) old
  where ps.id = old.id;
end;
$$;

-- Normalize existing accumulated subscriptions once. Future registrations are
-- kept bounded by the function above.
with ranked as (
  select
    id,
    row_number() over (
      partition by profile_id
      order by updated_at desc, created_at desc, id desc
    ) as rn
  from public.push_subscriptions
)
delete from public.push_subscriptions ps
using ranked r
where ps.id = r.id
  and r.rn > 5;
