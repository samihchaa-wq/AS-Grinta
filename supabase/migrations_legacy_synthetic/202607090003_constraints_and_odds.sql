begin;

-- Prevent users from escalating their own privileges through the self-update policy.
create or replace function public.guard_sensitive_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() = old.id and not public.is_moderator() then
    if new.role is distinct from old.role
       or new.status is distinct from old.status
       or new.is_goalkeeper is distinct from old.is_goalkeeper then
      raise exception 'Sensitive profile fields require Moderator role';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_sensitive_profile_fields on public.profiles;
create trigger trg_guard_sensitive_profile_fields
before update on public.profiles
for each row execute function public.guard_sensitive_profile_fields();

-- Canonical conditional validations for goals.
alter table public.goals
  drop constraint if exists goals_players_consistency;
alter table public.goals
  add constraint goals_players_consistency check (
    (
      team = 'adverse'
      and scorer_profile_id is null
      and assist_profile_id is null
      and assist_type is null
    )
    or
    (
      team = 'as_grinta'
      and goal_type = 'csc_adverse'
      and scorer_profile_id is null
      and assist_profile_id is null
      and assist_type is null
    )
    or
    (
      team = 'as_grinta'
      and goal_type in ('jeu','penalty','coup_franc')
      and scorer_profile_id is not null
      and (
        (assist_type = 'connu' and assist_profile_id is not null)
        or (assist_type in ('sans_passe','inconnu') and assist_profile_id is null)
      )
      and assist_profile_id is distinct from scorer_profile_id
    )
  );

-- Backfill required audit columns before making them mandatory.
update public.matches
set created_by = (
  select id from public.profiles
  where role in ('moderateur','admin')
  order by created_at
  limit 1
)
where created_by is null;

update public.match_motm
set created_by = (
  select id from public.profiles
  where role in ('moderateur','admin')
  order by created_at
  limit 1
)
where created_by is null;

alter table public.matches alter column created_by set not null;
alter table public.match_motm alter column created_by set not null;

-- Server-side odds calculation, frozen at match creation.
create or replace function public.compute_match_odds(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_opponent uuid;
  v_lambda_for numeric;
  v_lambda_against numeric;
  v_gap numeric;
  v_draw numeric;
  v_win_share numeric;
  v_win numeric;
  v_loss numeric;
  v_weight_total numeric;
begin
  select opponent_id into v_opponent
  from public.matches
  where id = p_match_id;

  if v_opponent is null then
    raise exception 'Match not found';
  end if;

  with ranked_seasons as (
    select
      id,
      row_number() over (order by name desc) - 1 as age
    from public.seasons
  ), weighted_history as (
    select
      m.score_as_grinta::numeric as goals_for,
      m.score_adverse::numeric as goals_against,
      case rs.age
        when 0 then 0.40
        when 1 then 0.25
        when 2 then 0.18
        when 3 then 0.10
        else 0.07
      end
      * case when m.opponent_id = v_opponent then 1.5 else 1.0 end as weight
    from public.matches m
    join ranked_seasons rs on rs.id = m.season_id
    where m.status in ('termine','archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  )
  select
    coalesce(sum(goals_for * weight) / nullif(sum(weight), 0), 1.5),
    coalesce(sum(goals_against * weight) / nullif(sum(weight), 0), 1.5),
    coalesce(sum(weight), 0)
  into v_lambda_for, v_lambda_against, v_weight_total
  from weighted_history;

  v_gap := (v_lambda_for - v_lambda_against)
    / (v_lambda_for + v_lambda_against + 0.001);

  v_draw := case
    when abs(v_gap) < 0.15 then 0.30
    when abs(v_gap) < 0.35 then 0.25
    when abs(v_gap) < 0.55 then 0.21
    else 0.17
  end;
  v_draw := greatest(v_draw, 0.155);

  v_win_share := 0.5 + least(0.32, abs(v_gap) / 2);
  if v_gap > 0 then
    v_win := (1 - v_draw) * v_win_share;
  else
    v_win := (1 - v_draw) * (1 - v_win_share);
  end if;
  v_win := least(v_win, 0.82);
  v_loss := 1 - v_draw - v_win;

  insert into public.match_odds (
    match_id,
    odds_victoire_as_grinta,
    odds_nul,
    odds_victoire_adverse,
    computed_at
  ) values (
    p_match_id,
    round((1 / (v_win * 1.05))::numeric, 2),
    round((1 / (v_draw * 1.05))::numeric, 2),
    round((1 / (v_loss * 1.05))::numeric, 2),
    now()
  )
  on conflict (match_id) do nothing;
end;
$$;

create or replace function public.create_match_odds_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.compute_match_odds(new.id);
  return new;
end;
$$;

drop trigger if exists trg_create_match_odds on public.matches;
create trigger trg_create_match_odds
after insert on public.matches
for each row execute function public.create_match_odds_after_insert();

-- Atomic position movement with slot conflict resolution.
create or replace function public.move_live_player(
  p_match_id uuid,
  p_controller_session_id text,
  p_profile_id uuid,
  p_slot_code text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_live_session_id uuid;
begin
  select id into v_live_session_id
  from public.live_sessions
  where match_id = p_match_id
    and controller_profile_id = auth.uid()
    and controller_session_id = p_controller_session_id;

  if v_live_session_id is null then
    return false;
  end if;

  if not exists (
    select 1 from public.match_participants mp
    where mp.match_id = p_match_id and mp.profile_id = p_profile_id
  ) then
    raise exception 'Player is not a match participant';
  end if;

  delete from public.live_positions
  where live_session_id = v_live_session_id
    and (
      profile_id = p_profile_id
      or (p_slot_code is not null and slot_code = p_slot_code)
    );

  insert into public.live_positions(live_session_id, profile_id, slot_code)
  values (v_live_session_id, p_profile_id, p_slot_code);

  return true;
end;
$$;

-- Atomic substitution pair plus position swap.
create or replace function public.record_substitution(
  p_match_id uuid,
  p_controller_session_id text,
  p_minute integer,
  p_in_profile_id uuid,
  p_out_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_live_session_id uuid;
  v_out_slot text;
begin
  if p_minute < 0 or p_minute > 100 or p_in_profile_id = p_out_profile_id then
    raise exception 'Invalid substitution';
  end if;

  select id into v_live_session_id
  from public.live_sessions
  where match_id = p_match_id
    and controller_profile_id = auth.uid()
    and controller_session_id = p_controller_session_id;

  if v_live_session_id is null then
    return false;
  end if;

  select slot_code into v_out_slot
  from public.live_positions
  where live_session_id = v_live_session_id
    and profile_id = p_out_profile_id
    and slot_code is not null;

  if v_out_slot is null then
    raise exception 'Outgoing player is not on the pitch';
  end if;

  if exists (
    select 1 from public.live_positions
    where live_session_id = v_live_session_id
      and profile_id = p_in_profile_id
      and slot_code is not null
  ) then
    raise exception 'Incoming player is not on the bench';
  end if;

  insert into public.substitutions(live_session_id, profile_id, action, minute)
  values
    (v_live_session_id, p_out_profile_id, 'out', p_minute),
    (v_live_session_id, p_in_profile_id, 'in', p_minute);

  delete from public.live_positions
  where live_session_id = v_live_session_id
    and profile_id in (p_in_profile_id, p_out_profile_id);

  insert into public.live_positions(live_session_id, profile_id, slot_code)
  values (v_live_session_id, p_in_profile_id, v_out_slot);

  return true;
end;
$$;

commit;
